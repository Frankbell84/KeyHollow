import CryptoKit
import Foundation
import Combine
import XCTest
@testable import KeyHollow
@testable import KeyHollowPhotoCore
@testable import KeyHollowGeneralFileSupportAddOn
import KeyHollowItemRenameAddOn
import KeyHollowEncryptedVideoAddOn

final class VaultItemRenameTests: XCTestCase {
    func testPolicyRejectsUnsafeNamesWithoutTruncatingAndCountsExtensionBytes() throws {
        let policy = ItemRenamePolicy(displayName: "old.MOV", preservesExtension: true)
        XCTAssertEqual(policy.initialName, "old")
        XCTAssertEqual(policy.retainedExtension, ".MOV")
        XCTAssertEqual(try policy.completeName(for: "new.name"), "new.name.MOV")
        for name in ["", "   ", "...", " . ", "a/b", "a\\b", "a:b", "a\nb", "a\u{0000}b"] {
            XCTAssertThrowsError(try policy.completeName(for: name), name)
        }
        XCTAssertEqual(try policy.completeName(for: String(repeating: "é", count: 88)).utf8.count, 180)
        XCTAssertThrowsError(try policy.completeName(for: String(repeating: "é", count: 89)))
        let noExtension = ItemRenamePolicy(displayName: "README", preservesExtension: true)
        XCTAssertEqual(try noExtension.completeName(for: "Notes"), "Notes")
        XCTAssertThrowsError(try noExtension.completeName(for: "Notes.pdf"))
        let photo = ItemRenamePolicy(displayName: "old.jpg", preservesExtension: false)
        XCTAssertEqual(try photo.completeName(for: "Holiday"), "Holiday")
        let historical = String(repeating: "é", count: 200) + ".pdf"
        let old = ItemRenamePolicy(displayName: historical, preservesExtension: true)
        XCTAssertEqual(old.initialName, String(repeating: "é", count: 200))
        XCTAssertThrowsError(try old.completeName(for: old.initialName))
        XCTAssertEqual(try old.completeName(for: "Short"), "Short.pdf")
    }

    func testPhotoRenamePreservesIdentityCiphertextAndInvalidatesOtherStoreCache() async throws {
        let f = try RenameFixture()
        defer { f.cleanup() }
        let record = try await f.photo()
        let second = try f.photoStore()
        _ = try await second.loadManifest()
        let blob = try Data(contentsOf: f.photosRoot.appendingPathComponent(record.blobName))
        let thumbnail = try Data(contentsOf: f.photosRoot.appendingPathComponent(record.thumbnailName))
        let snapshot = try await f.photos.renameSnapshot(for: record.id)
        let renamed = try await second.rename(snapshot, to: "Summer")
        XCTAssertEqual(renamed.id, record.id)
        XCTAssertEqual(renamed.importedAt, record.importedAt)
        XCTAssertEqual(renamed.originalByteCount, record.originalByteCount)
        XCTAssertEqual(renamed.blobName, record.blobName)
        XCTAssertEqual(renamed.thumbnailName, record.thumbnailName)
        XCTAssertEqual(try Data(contentsOf: f.photosRoot.appendingPathComponent(record.blobName)), blob)
        XCTAssertEqual(try Data(contentsOf: f.photosRoot.appendingPathComponent(record.thumbnailName)), thumbnail)
        let loaded = try await f.photos.loadPhoto(record)
        XCTAssertEqual(loaded, Data("photo original".utf8))
        let latest = try await f.photos.renameSnapshot(for: record.id)
        XCTAssertEqual(latest.record.displayName, "Summer")
        do { _ = try await f.photos.rename(snapshot, to: "Stale"); XCTFail("Stale rename won") }
        catch { XCTAssertEqual(error as? VaultPhotoStore.StoreError, .renameConflict) }
        let unrelated = try await second.importPhoto(originalData: Data([4]), thumbnailData: Data([5]))
        do { _ = try await f.photos.rename(latest, to: "Stale after import"); XCTFail("Import lost") }
        catch { XCTAssertEqual(error as? VaultPhotoStore.StoreError, .renameConflict) }
        let final = try await f.photos.loadManifest()
        XCTAssertEqual(Set(final.photos.map(\.id)), Set([record.id, unrelated.id]))
        let beforeDelete = try await f.photos.renameSnapshot(for: record.id)
        try await second.delete(record)
        do { _ = try await f.photos.rename(beforeDelete, to: "Resurrected"); XCTFail("Deleted item restored") }
        catch { XCTAssertEqual(error as? VaultPhotoStore.StoreError, .renameConflict) }
        let afterDelete = try await f.photos.loadManifest()
        XCTAssertEqual(afterDelete.photos.map(\.id), [unrelated.id])
    }

    func testFileRenamePreservesTypeBytesSourcesAndSafeDuplicateExports() async throws {
        let f = try RenameFixture()
        defer { f.cleanup() }
        var records: [VaultGeneralFileRecord] = []
        for suffix in ["pdf", "mp3", "jpg", "MOV", ""] {
            let sourceName = suffix.isEmpty ? "README" : "original." + suffix
            let record = try await f.file(sourceName)
            let snapshot = try await f.files.renameSnapshot(for: record.id)
            let cipher = try Data(contentsOf: f.filesRoot.appendingPathComponent(record.blobName))
            let name = suffix.isEmpty ? "Read Me" : "Renamed." + suffix
            let renamed = try await f.files.rename(snapshot, to: name)
            XCTAssertEqual(renamed.id, record.id)
            XCTAssertEqual(renamed.importedAt, record.importedAt)
            XCTAssertEqual(renamed.blobName, record.blobName)
            XCTAssertEqual(renamed.contentTypeIdentifier, record.contentTypeIdentifier)
            XCTAssertEqual(renamed.originalByteCount, record.originalByteCount)
            XCTAssertEqual(try Data(contentsOf: f.filesRoot.appendingPathComponent(record.blobName)), cipher)
            XCTAssertEqual(try Data(contentsOf: f.root.appendingPathComponent(sourceName)), Data(sourceName.utf8))
            records.append(renamed)
        }
        let duplicate = try await f.file("second.pdf")
        let snapshot = try await f.files.renameSnapshot(for: duplicate.id)
        records.append(try await f.files.rename(snapshot, to: "Renamed.pdf"))
        let export = try await f.files.prepareExport(records)
        XCTAssertEqual(export.urls.count, 6)
        XCTAssertEqual(Set(export.urls.map(\.lastPathComponent)).count, 6)
        XCTAssertEqual(export.urls.filter { $0.pathExtension == "pdf" }.count, 2)
        for (record, url) in zip(records, export.urls) {
            let bytes = try await f.files.loadFile(record)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertEqual(url.pathExtension, (record.displayName as NSString).pathExtension)
        }
        await f.files.discardExport(export)
    }

    func testFileStaleEditsCannotOverwriteImportDeleteOrWinner() async throws {
        let f = try RenameFixture()
        defer { f.cleanup() }
        let a = try await f.file("a.pdf")
        let snapshot = try await f.files.renameSnapshot(for: a.id)
        let second = try f.fileStore()
        _ = try await second.rename(snapshot, to: "winner.pdf")
        do { _ = try await f.files.rename(snapshot, to: "loser.pdf"); XCTFail("Lost winner") }
        catch { XCTAssertEqual(error as? VaultGeneralFileStore.StoreError, .renameConflict) }
        let beforeImport = try await second.renameSnapshot(for: a.id)
        let b = try await f.file("b.pdf")
        do { _ = try await second.rename(beforeImport, to: "lost import.pdf"); XCTFail("Lost import") }
        catch { XCTAssertEqual(error as? VaultGeneralFileStore.StoreError, .renameConflict) }
        let beforeDelete = try await second.renameSnapshot(for: a.id)
        try await f.files.delete([a])
        do { _ = try await second.rename(beforeDelete, to: "returned.pdf"); XCTFail("Resurrected deletion") }
        catch { XCTAssertEqual(error as? VaultGeneralFileStore.StoreError, .renameConflict) }
        let final = try await second.loadManifest()
        XCTAssertEqual(final.files, [b])
    }

    func testStorageRejectsInvalidNamesAndTypeChangesWithoutWriting() async throws {
        let f = try RenameFixture()
        defer { f.cleanup() }
        let photo = try await f.photo()
        let file = try await f.file("old.pdf")
        let p = try await f.photos.renameSnapshot(for: photo.id)
        let g = try await f.files.renameSnapshot(for: file.id)
        let before = try f.manifestBytes()
        for name in ["", "...", "\n", "a/b", "a\\b", "a:b", String(repeating: "é", count: 91)] {
            do { _ = try await f.photos.rename(p, to: name); XCTFail("Accepted \(name)") }
            catch { XCTAssertEqual(error as? VaultPhotoStore.StoreError, .invalidDisplayName) }
        }
        for name in ["new.exe", "new.PDF", "no extension", "/a.pdf", "a:b.pdf", String(repeating: "é", count: 89) + ".pdf"] {
            do { _ = try await f.files.rename(g, to: name); XCTFail("Accepted \(name)") }
            catch { XCTAssertEqual(error as? VaultGeneralFileStore.StoreError, .invalidDisplayName) }
        }
        XCTAssertEqual(try f.manifestBytes(), before)
    }

    func testRenamingHistoricalVideoMetadataDoesNotChangePlaybackEligibility() async throws {
        let f = try RenameFixture()
        defer { f.cleanup() }
        let record = try await f.file("old.MOV")
        for type in [nil, "", "invalid type", "public.movie", "public.pdf", "public.mpeg-4"] as [String?] {
            let historical = VaultGeneralFileRecord(
                id: record.id, importedAt: record.importedAt,
                displayName: String(repeating: "é", count: 200) + ".MOV",
                contentTypeIdentifier: type, originalByteCount: record.originalByteCount, blobName: record.blobName
            )
            try f.writeFileManifest([historical])
            let snapshot = try await f.files.renameSnapshot(for: record.id)
            XCTAssertEqual(snapshot.record, historical)
            let renamed = try await f.files.rename(snapshot, to: "Trip.MOV")
            func kind(_ r: VaultGeneralFileRecord) -> VaultEncryptedVideoKind {
                VaultEncryptedVideoPolicy.kind(for: .init(displayName: r.displayName,
                    contentTypeIdentifier: r.contentTypeIdentifier, originalByteCount: r.originalByteCount))
            }
            XCTAssertEqual(kind(renamed), kind(historical))
            XCTAssertEqual(kind(renamed), type == nil || type == "public.mpeg-4" ? .video : .unsupported)
        }
    }

    func testPhotoReplacementFailuresReportDurableWinnerAndRetainPayloads() async throws {
        for mode in RenameFault.allCases {
            let f = try RenameFixture()
            defer { f.cleanup() }
            let record = try await f.photo()
            let before = try f.photoManifestBytes()
            let target = f.photosRoot.appendingPathComponent("manifest.khm")
            let faultStore = try f.photoStore(before: {
                if mode == .before { throw RenameFaultError.injected }
            }, after: {
                if mode == .unreadable { try Data([0]).write(to: target) }
                throw RenameFaultError.injected
            })
            let snapshot = try await faultStore.renameSnapshot(for: record.id)
            do {
                let result = try await faultStore.rename(snapshot, to: "Renamed")
                XCTAssertEqual(mode, .after)
                XCTAssertEqual(result.displayName, "Renamed")
            } catch {
                if mode == .before { XCTAssertEqual(error as? RenameFaultError, .injected) }
                else { XCTAssertEqual(error as? VaultPhotoStore.StoreError, .manifestCommitStateUnknown) }
            }
            if mode == .before { XCTAssertEqual(try f.photoManifestBytes(), before) }
            if mode == .after {
                let manifest = try await f.photos.loadManifest()
                XCTAssertEqual(manifest.photos.first?.displayName, "Renamed")
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.photosRoot.appendingPathComponent(record.blobName).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.photosRoot.appendingPathComponent(record.thumbnailName).path))
        }
    }

    func testFileReplacementFailuresReportDurableWinnerAndRetainPayloads() async throws {
        for mode in RenameFault.allCases {
            let f = try RenameFixture()
            defer { f.cleanup() }
            let record = try await f.file("original.pdf")
            let target = f.filesRoot.appendingPathComponent("manifest.khm")
            let before = try Data(contentsOf: target)
            let faultStore = try f.fileStore(before: {
                if mode == .before { throw RenameFaultError.injected }
            }, after: {
                if mode == .unreadable { try Data([0]).write(to: target) }
                throw RenameFaultError.injected
            })
            let snapshot = try await faultStore.renameSnapshot(for: record.id)
            do {
                let result = try await faultStore.rename(snapshot, to: "Renamed.pdf")
                XCTAssertEqual(mode, .after)
                XCTAssertEqual(result.displayName, "Renamed.pdf")
            } catch {
                if mode == .before { XCTAssertEqual(error as? RenameFaultError, .injected) }
                else { XCTAssertEqual(error as? VaultGeneralFileStore.StoreError, .manifestCommitStateUnknown) }
            }
            if mode == .before { XCTAssertEqual(try Data(contentsOf: target), before) }
            if mode == .after {
                let manifest = try await f.files.loadManifest()
                XCTAssertEqual(manifest.files.first?.displayName, "Renamed.pdf")
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.filesRoot.appendingPathComponent(record.blobName).path))
            XCTAssertEqual(try Data(contentsOf: f.root.appendingPathComponent("original.pdf")), Data("original.pdf".utf8))
        }
    }

    @MainActor
    func testRealMutationsAtRevocationBarriersMatchDurableStorage() async throws {
        for isPhoto in [true, false] {
            for beforeReplacement in [true, false] {
                let f = try RenameFixture()
                defer { f.cleanup() }
                let photo = try await f.photo()
                let file = try await f.file("Original.pdf")
                let session = VaultSession()
                session.unlock(vaultID: f.id, key: f.key)
                let access = try XCTUnwrap(session.activeVaultContext()?.access)
                let entered = expectation(description: "At replacement barrier")
                let release = DispatchSemaphore(value: 0)
                let stop: @Sendable () throws -> Void = {
                    entered.fulfill()
                    guard release.wait(timeout: .now() + 10) == .success else { throw RenameFaultError.injected }
                }
                let before: @Sendable () throws -> Void = { if beforeReplacement { try stop() } }
                let after: @Sendable () throws -> Void = { if !beforeReplacement { try stop() } }
                let photos = try VaultPhotoStore(vaultID: f.id, access: access, storageRoot: f.photosRoot,
                    manifestCommitDidComplete: after, manifestCommitWillReplace: before)
                let files = try VaultGeneralFileStore(vaultID: f.id, access: SessionGeneralFileAccess(capability: access),
                    storageRoot: f.filesRoot, temporaryRoot: f.root.appendingPathComponent("Temp"),
                    manifestCommitDidComplete: after, manifestCommitWillReplace: before)
                var returnedError: Error?
                session.startSensitiveTask { _ in
                    do {
                        if isPhoto {
                            let snapshot = try await photos.renameSnapshot(for: photo.id)
                            _ = try await photos.rename(snapshot, to: "Changed")
                        } else {
                            let snapshot = try await files.renameSnapshot(for: file.id)
                            _ = try await files.rename(snapshot, to: "Changed.pdf")
                        }
                    } catch { returnedError = error }
                }
                await fulfillment(of: [entered], timeout: 5)
                let barrier = session.lock()
                XCTAssertFalse(barrier.isEmpty)
                release.signal()
                await barrier.wait()
                if beforeReplacement {
                    XCTAssertTrue(returnedError is CancellationError || returnedError as? VaultAccessError == .revoked)
                } else {
                    XCTAssertNil(returnedError, "An already committed rename must not be called a rollback")
                }
                let photoName = try await f.photos.loadManifest().photos.first?.displayName
                let fileName = try await f.files.loadManifest().files.first?.displayName
                XCTAssertEqual(photoName, isPhoto && !beforeReplacement ? "Changed" : "Original")
                XCTAssertEqual(fileName, !isPhoto && !beforeReplacement ? "Changed.pdf" : "Original.pdf")
                let photoBytes = try await f.photos.loadPhoto(photo)
                let fileBytes = try await f.files.loadFile(file)
                XCTAssertEqual(photoBytes, Data("photo original".utf8))
                XCTAssertEqual(fileBytes, Data("Original.pdf".utf8))
            }
        }
    }

    @MainActor
    func testEditorValidationCanRetryAndSaveThroughRealStore() async throws {
        let f = try RenameFixture()
        defer { f.cleanup() }
        let record = try await f.file("Original.pdf")
        let session = VaultSession()
        session.unlock(vaultID: f.id, key: f.key)
        let editor = VaultItemRenameCoordinator()
        let shown = expectation(description: "Shown")
        let invalid = expectation(description: "Invalid name shown")
        let finished = expectation(description: "Saved")
        let shownSubscription = editor.$isPresented.dropFirst().filter { $0 }.prefix(1).sink { _ in shown.fulfill() }
        let errorSubscription = editor.$error.compactMap { $0 }.prefix(1).sink { _ in invalid.fulfill() }
        editor.begin(fileStore: f.files, id: record.id, session: session) { error in
            XCTAssertNil(error)
            finished.fulfill()
        }
        await fulfillment(of: [shown], timeout: 3)
        editor.draft = "../bad"
        editor.save()
        await fulfillment(of: [invalid], timeout: 3)
        XCTAssertTrue(editor.isPresented)
        XCTAssertFalse(editor.isSaving)
        editor.draft = "Good"
        editor.save()
        await fulfillment(of: [finished], timeout: 3)
        let loaded = try await f.files.loadManifest()
        XCTAssertEqual(loaded.files.first?.displayName, "Good.pdf")
        XCTAssertEqual(editor.draft, "")
        XCTAssertFalse(editor.isPresented)
        await session.lockAndWait()
        withExtendedLifetime([shownSubscription, errorSubscription]) {}
    }

    @MainActor
    func testEditorCancellationAndLockClearDraftWithoutSaving() async throws {
        let f = try RenameFixture()
        defer { f.cleanup() }
        let record = try await f.photo()
        let session = VaultSession()
        session.unlock(vaultID: f.id, key: f.key)
        let editor = VaultItemRenameCoordinator()
        for shouldLock in [false, true] {
            let shown = expectation(description: "Editor shown")
            let subscription = editor.$isPresented.dropFirst().filter { $0 }.prefix(1).sink { _ in shown.fulfill() }
            editor.begin(photoStore: f.photos, id: record.id, session: session) { _ in XCTFail("Cancelled edit published") }
            await fulfillment(of: [shown], timeout: 3)
            editor.draft = "Private draft"
            if shouldLock { await session.lockAndWait() }
            else { editor.cancel(in: session) }
            XCTAssertFalse(editor.isPresented)
            XCTAssertEqual(editor.draft, "")
            withExtendedLifetime(subscription) {}
        }
        let manifest = try await f.photos.loadManifest()
        XCTAssertEqual(manifest.photos, [record])
    }

    @MainActor
    func testLockDuringPreparationCannotPublishIntoNewVault() async throws {
        let session = VaultSession()
        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))
        let editor = VaultItemRenameCoordinator()
        let entered = expectation(description: "Preparing")
        let gate = RenameAsyncGate()
        editor.begin(session: session, prepare: {
            entered.fulfill()
            await gate.wait()
            return .init(policy: .init(displayName: "Secret", preservesExtension: false), commit: { _ in XCTFail("Revoked commit") })
        }, finished: { _ in XCTFail("Old editor published") })
        await fulfillment(of: [entered], timeout: 3)
        let barrier = session.lock()
        XCTAssertFalse(editor.isActive)
        let nextID = UUID()
        session.unlock(vaultID: nextID, key: SymmetricKey(size: .bits256))
        XCTAssertFalse(session.hasActiveAccess)
        await gate.open()
        await barrier.wait()
        XCTAssertEqual(editor.draft, "")
        XCTAssertFalse(editor.isPresented)
        await session.lockAndWait()
    }

    @MainActor
    func testLockDuringCommitWaitsAndSuppressesLateSuccess() async throws {
        let session = VaultSession()
        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))
        let editor = VaultItemRenameCoordinator()
        let shown = expectation(description: "Shown")
        let entered = expectation(description: "Commit entered")
        let gate = RenameAsyncGate()
        let subscription = editor.$isPresented.dropFirst().filter { $0 }.prefix(1).sink { _ in shown.fulfill() }
        editor.begin(session: session, prepare: {
            .init(policy: .init(displayName: "Secret", preservesExtension: false), commit: { _ in
                entered.fulfill()
                await gate.wait() // models an authorized replacement already in flight
            })
        }, finished: { _ in XCTFail("Revoked success published") })
        await fulfillment(of: [shown], timeout: 3)
        editor.draft = "New secret"
        editor.save()
        await fulfillment(of: [entered], timeout: 3)
        let barrier = session.lock()
        XCTAssertFalse(barrier.isEmpty)
        XCTAssertEqual(editor.draft, "")
        XCTAssertFalse(editor.isSaving)
        await gate.open()
        await barrier.wait()
        XCTAssertFalse(editor.isPresented)
        withExtendedLifetime(subscription) {}
    }
}

private enum RenameFault: CaseIterable, Sendable, Equatable { case before, after, unreadable }
private enum RenameFaultError: Error, Equatable { case injected }

private actor RenameAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private struct RenameFixture {
    let root: URL
    let id = UUID()
    let key = SymmetricKey(size: .bits256)
    let access: VaultAccessCapability
    let photos: VaultPhotoStore
    let files: VaultGeneralFileStore
    var photosRoot: URL { root.appendingPathComponent("Photos") }
    var filesRoot: URL { root.appendingPathComponent("Files") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Rename-\(UUID())")
        access = VaultAccessCapability(vaultID: id, vaultKey: key)
        photos = try VaultPhotoStore(vaultID: id, access: access, storageRoot: root.appendingPathComponent("Photos"))
        files = try VaultGeneralFileStore(vaultID: id, access: SessionGeneralFileAccess(capability: access),
            storageRoot: root.appendingPathComponent("Files"), temporaryRoot: root.appendingPathComponent("Temp"))
    }
    func photo() async throws -> VaultPhotoRecord {
        try await photos.importPhoto(originalData: Data("photo original".utf8), thumbnailData: Data("thumb".utf8), displayName: "Original")
    }
    func file(_ name: String) async throws -> VaultGeneralFileRecord {
        let url = root.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return try await files.importFile(at: url)
    }
    func photoStore(before: @escaping @Sendable () throws -> Void = {},
                    after: @escaping @Sendable () throws -> Void = {}) throws -> VaultPhotoStore {
        try VaultPhotoStore(vaultID: id, access: access, storageRoot: photosRoot,
            manifestCommitDidComplete: after, manifestCommitWillReplace: before)
    }
    func fileStore(before: @escaping @Sendable () throws -> Void = {},
                   after: @escaping @Sendable () throws -> Void = {}) throws -> VaultGeneralFileStore {
        try VaultGeneralFileStore(vaultID: id, access: SessionGeneralFileAccess(capability: access),
            storageRoot: filesRoot, temporaryRoot: root.appendingPathComponent("Temp"),
            manifestCommitDidComplete: after, manifestCommitWillReplace: before)
    }
    func photoManifestBytes() throws -> Data { try Data(contentsOf: photosRoot.appendingPathComponent("manifest.khm")) }
    func manifestBytes() throws -> [Data] { try [photoManifestBytes(), Data(contentsOf: filesRoot.appendingPathComponent("manifest.khm"))] }
    func writeFileManifest(_ records: [VaultGeneralFileRecord]) throws {
        let data = try JSONEncoder().encode(VaultGeneralFileManifest(version: 1, files: records))
        let encrypted = try SessionGeneralFileAccess(capability: access).seal(data, for: .manifest)
        try encrypted.write(to: filesRoot.appendingPathComponent("manifest.khm"), options: .atomic)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
