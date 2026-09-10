import CryptoKit
import Foundation
import XCTest
import KeyHollowCryptoCore
@testable import KeyHollowFolderPresentationAddOn

final class VaultFolderPresentationAddOnTests: XCTestCase {
    func testRevokedAccessRejectsEmptyManifestLoad() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifestURL.path))

        fixture.access.revoke()

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadManifest()
        ) { error in
            XCTAssertEqual(error as? TestAccessError, .revoked)
        }
    }

    func testStoreInstancesSerializeConcurrentFolderCreation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let secondStore = try VaultFolderPresentationStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot
        )
        let stores = [fixture.store, secondStore]
        let names = (0..<40).map { "Concurrent \($0)" }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, name) in names.enumerated() {
                let store = stores[index % stores.count]
                group.addTask {
                    _ = try await store.createFolder(named: name)
                }
            }
            try await group.waitForAll()
        }

        let manifest = try await fixture.store.loadManifest()
        XCTAssertEqual(manifest.folders.count, names.count)
        XCTAssertEqual(Set(manifest.folders.map(\.name)), Set(names))
    }

    func testFolderLifecycleMovesReferencesWithoutOwningContent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())

        let folder = try await fixture.store.createFolder(named: "  Contracts  ")
        XCTAssertEqual(folder.name, "Contracts")
        try await fixture.store.move(item, to: folder.id)
        let assignedFolderID = try await fixture.store.folderID(for: item)
        XCTAssertEqual(assignedFolderID, folder.id)

        try await fixture.store.renameFolder(id: folder.id, to: "Legal")
        let renamedManifest = try await fixture.store.loadManifest()
        XCTAssertEqual(renamedManifest.folders.first?.name, "Legal")

        try await fixture.store.deleteFolder(id: folder.id)
        let deletedFolderID = try await fixture.store.folderID(for: item)
        let deletedManifest = try await fixture.store.loadManifest()
        XCTAssertNil(deletedFolderID)
        XCTAssertTrue(deletedManifest.folders.isEmpty)
    }

    func testMovingBetweenFoldersAndRootKeepsAtMostOneMembership() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .photo, id: UUID())
        let first = try await fixture.store.createFolder(named: "First")
        let second = try await fixture.store.createFolder(named: "Second")

        try await fixture.store.move(item, to: first.id)
        try await fixture.store.move(item, to: second.id)
        var manifest = try await fixture.store.loadManifest()
        XCTAssertEqual(manifest.memberships.count, 1)
        XCTAssertEqual(manifest.memberships.first?.folderID, second.id)

        try await fixture.store.move(item, to: nil)
        manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.memberships.isEmpty)
        let rootFolderID = try await fixture.store.folderID(for: item)
        XCTAssertNil(rootFolderID)
    }

    func testBatchMoveSupportsMixedPhotoAndFileReferencesAtomically() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let photo = VaultPresentedContentReference(kind: .photo, id: UUID())
        let file = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let items: Set<VaultPresentedContentReference> = [photo, file]
        let folder = try await fixture.store.createFolder(named: "Mixed")

        try await fixture.store.move(items, to: folder.id)
        var manifest = try await fixture.store.loadManifest()
        XCTAssertEqual(Set(manifest.memberships.map(\.item)), items)
        XCTAssertEqual(Set(manifest.memberships.map(\.folderID)), [folder.id])

        try await fixture.store.move(items, to: nil)
        manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.memberships.isEmpty)
    }

    func testBatchMoveRejectsMissingDestinationWithoutChangingMemberships() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let photo = VaultPresentedContentReference(kind: .photo, id: UUID())
        let file = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let items: Set<VaultPresentedContentReference> = [photo, file]
        let folder = try await fixture.store.createFolder(named: "Existing")
        try await fixture.store.move(items, to: folder.id)
        let originalManifest = try await fixture.store.loadManifest()

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.move(items, to: UUID())
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .folderNotFound)
        }

        let unchangedManifest = try await fixture.store.loadManifest()
        XCTAssertEqual(unchangedManifest, originalManifest)
    }

    func testDuplicateAndInvalidFolderNamesFailWithoutChangingManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.createFolder(named: "Receipts")
        let manifestBefore = try Data(contentsOf: fixture.manifestURL)

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.createFolder(named: "receipts")
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .duplicateFolderName)
        }
        await XCTAssertThrowsErrorAsync(
            try await fixture.store.createFolder(named: "   ")
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .invalidFolderName)
        }
        let unchangedManifest = try await fixture.store.loadManifest()
        XCTAssertEqual(unchangedManifest.folders.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.manifestURL), manifestBefore)
    }

    func testFolderNameCollisionNormalizationIsConsistentForCreateAndRename() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.createFolder(named: "Caf\u{00E9}")
        let other = try await fixture.store.createFolder(named: "Other")
        let canonicallyEquivalentUppercaseName = "CAFE\u{0301}"

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.createFolder(named: canonicallyEquivalentUppercaseName)
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .duplicateFolderName)
        }
        await XCTAssertThrowsErrorAsync(
            try await fixture.store.renameFolder(
                id: other.id,
                to: canonicallyEquivalentUppercaseName
            )
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .duplicateFolderName)
        }

        let manifest = try await fixture.store.loadManifest()
        XCTAssertEqual(manifest.folders.map(\.name), ["Caf\u{00E9}", "Other"])

        try fixture.writeManifest(
            VaultFolderPresentationManifest(
                version: VaultFolderPresentationManifest.currentVersion,
                folders: [
                    VaultFolderRecord(id: UUID(), name: " Caf\u{00E9} ", createdAt: Date()),
                    VaultFolderRecord(
                        id: UUID(),
                        name: canonicallyEquivalentUppercaseName,
                        createdAt: Date()
                    )
                ],
                memberships: [],
                thumbnails: []
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadManifest()
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .invalidManifest)
        }
    }

    func testThumbnailIsEncryptedAndAuthenticatedAtRest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let thumbnail = Data("KEYHOLLOW-PRIVATE-THUMBNAIL".utf8)

        try await fixture.store.storeThumbnail(thumbnail, for: item)
        let manifest = try await fixture.store.loadManifest()
        let blobName = try XCTUnwrap(manifest.thumbnails.first?.blobName)
        let stored = try Data(contentsOf: fixture.storageRoot.appendingPathComponent(blobName))

        XCTAssertNotEqual(stored, thumbnail)
        XCTAssertNil(stored.range(of: thumbnail))
        let reopenedThumbnail = try await fixture.store.loadThumbnail(for: item)
        XCTAssertEqual(reopenedThumbnail, thumbnail)
    }

    func testThumbnailAcceptsAuthenticatedManifestWhenReplaceCommitsThenThrows() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.createFolder(named: "Existing")
        let faultingStore = try VaultFolderPresentationStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot,
            manifestCommitDidComplete: {
                throw FolderManifestCommitTestError.committedThenThrew
            }
        )
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let thumbnail = Data("committed thumbnail".utf8)

        try await faultingStore.storeThumbnail(thumbnail, for: item)

        let durable = try await fixture.store.loadManifest()
        XCTAssertEqual(durable.thumbnails.count, 1)
        XCTAssertEqual(durable.thumbnails.first?.item, item)
        let reopened = try await faultingStore.loadThumbnail(for: item)
        XCTAssertEqual(reopened, thumbnail)
    }

    func testThumbnailPreservesBlobWhenPostCommitManifestCannotBeVerified() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.createFolder(named: "Existing")
        let manifestURL = fixture.manifestURL
        let faultingStore = try VaultFolderPresentationStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot,
            manifestCommitDidComplete: {
                try Data("unverifiable".utf8).write(to: manifestURL, options: .atomic)
                throw FolderManifestCommitTestError.committedThenThrew
            }
        )
        let item = VaultPresentedContentReference(kind: .photo, id: UUID())

        await XCTAssertThrowsErrorAsync(
            try await faultingStore.storeThumbnail(Data("must remain".utf8), for: item)
        ) { error in
            XCTAssertEqual(
                error as? VaultFolderPresentationStore.StoreError,
                .manifestCommitStateUnknown
            )
        }

        let storedNames = try FileManager.default.contentsOfDirectory(
            atPath: fixture.storageRoot.path
        )
        XCTAssertEqual(storedNames.filter { $0.hasSuffix(".kht") }.count, 1)
    }

    func testReconcileFinishesCleanupWhenManifestReplaceCommitsThenThrows() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        try await fixture.store.storeThumbnail(Data("remove me".utf8), for: item)
        let originalManifest = try await fixture.store.loadManifest()
        let blobName = try XCTUnwrap(originalManifest.thumbnails.first?.blobName)
        let blobURL = fixture.storageRoot.appendingPathComponent(blobName)
        let faultingStore = try VaultFolderPresentationStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot,
            manifestCommitDidComplete: {
                throw FolderManifestCommitTestError.committedThenThrew
            }
        )

        try await faultingStore.reconcile(validItems: [])

        let durable = try await fixture.store.loadManifest()
        XCTAssertTrue(durable.thumbnails.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL.path))
    }

    func testReconcileRemovesOnlyPresentationDataForMissingItems() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let retained = VaultPresentedContentReference(kind: .photo, id: UUID())
        let removed = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let folder = try await fixture.store.createFolder(named: "Keep")
        try await fixture.store.move(retained, to: folder.id)
        try await fixture.store.move(removed, to: folder.id)
        try await fixture.store.storeThumbnail(Data("retained".utf8), for: retained)
        try await fixture.store.storeThumbnail(Data("removed".utf8), for: removed)

        try await fixture.store.reconcile(validItems: [retained])
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(manifest.memberships.map(\.item), [retained])
        XCTAssertEqual(manifest.thumbnails.map(\.item), [retained])
        let retainedThumbnail = try await fixture.store.loadThumbnail(for: retained)
        let removedThumbnail = try await fixture.store.loadThumbnail(for: removed)
        XCTAssertEqual(retainedThumbnail, Data("retained".utf8))
        XCTAssertNil(removedThumbnail)
    }

    func testOversizedThumbnailIsRejectedWithoutChangingManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let oversized = Data(
            repeating: 0xA5,
            count: VaultFolderPresentationStore.maximumThumbnailByteCount + 1
        )

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.storeThumbnail(oversized, for: item)
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .verificationFailed)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.thumbnails.isEmpty)
    }

    func testOversizedStoredThumbnailCiphertextIsRejectedBeforeDecryption() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .photo, id: UUID())
        try await fixture.store.storeThumbnail(Data([0x01]), for: item)
        let manifest = try await fixture.store.loadManifest()
        let blobName = try XCTUnwrap(manifest.thumbnails.first?.blobName)
        let oversizedCiphertext = Data(
            repeating: 0xA5,
            count: VaultFolderPresentationStore.maximumThumbnailByteCount + 29
        )
        try oversizedCiphertext.write(
            to: fixture.storageRoot.appendingPathComponent(blobName)
        )

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadThumbnail(for: item)
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .verificationFailed)
        }
    }

    func testOversizedManifestCiphertextIsRejectedBeforeDecryption() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let oversizedCiphertext = Data(
            repeating: 0xA5,
            count: VaultFolderPresentationStore.legacyMaximumManifestByteCount + 29
        )
        try oversizedCiphertext.write(to: fixture.manifestURL)

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadManifest()
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .invalidManifest)
        }
    }

    func testLegacyFolderCountLoadsAndDeletesButRejectsFurtherGrowth() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let folders = (0...VaultFolderPresentationStore.maximumFolderCount).map { index in
            VaultFolderRecord(id: UUID(), name: "Folder \(index)", createdAt: Date())
        }
        try fixture.writeManifest(
            VaultFolderPresentationManifest(
                version: VaultFolderPresentationManifest.currentVersion,
                folders: folders,
                memberships: [],
                thumbnails: []
            )
        )

        let loadedLegacyManifest = try await fixture.store.loadManifest()
        XCTAssertEqual(loadedLegacyManifest.folders.count, folders.count)
        await XCTAssertThrowsErrorAsync(try await fixture.store.createFolder(named: "One more")) {
            XCTAssertEqual(
                $0 as? VaultFolderPresentationStore.StoreError,
                .folderLimitReached
            )
        }
        try await fixture.store.deleteFolder(id: folders[0].id)
        let manifestAfterDelete = try await fixture.store.loadManifest()
        XCTAssertEqual(
            manifestAfterDelete.folders.count,
            folders.count - 1
        )
    }

    func testLegacyMembershipAndThumbnailCountsLoadButRejectFurtherGrowth() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let folder = VaultFolderRecord(id: UUID(), name: "Legacy", createdAt: Date())
        let items = (0...VaultFolderPresentationStore.maximumMembershipCount).map { _ in
            VaultPresentedContentReference(kind: .photo, id: UUID())
        }
        let memberships = items.map {
            VaultFolderMembership(item: $0, folderID: folder.id)
        }
        let thumbnails = items.enumerated().map { index, item in
            VaultPresentationThumbnailRecord(item: item, blobName: "t\(index).kht")
        }
        try fixture.writeManifest(
            VaultFolderPresentationManifest(
                version: VaultFolderPresentationManifest.currentVersion,
                folders: [folder],
                memberships: memberships,
                thumbnails: thumbnails
            )
        )

        let loaded = try await fixture.store.loadManifest()
        XCTAssertEqual(loaded.memberships.count, memberships.count)
        XCTAssertEqual(loaded.thumbnails.count, thumbnails.count)

        let newItem = VaultPresentedContentReference(kind: .photo, id: UUID())
        await XCTAssertThrowsErrorAsync(try await fixture.store.move(newItem, to: folder.id)) {
            XCTAssertEqual(
                $0 as? VaultFolderPresentationStore.StoreError,
                .membershipLimitReached
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await fixture.store.storeThumbnail(Data([0x01]), for: newItem)
        ) { error in
            XCTAssertEqual(
                error as? VaultFolderPresentationStore.StoreError,
                .thumbnailLimitReached
            )
        }
    }

    func testManifestSymlinkIsRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let externalManifest = fixture.root.appendingPathComponent("external-manifest.khm")
        try fixture.encryptedManifestData(.empty).write(to: externalManifest)
        try FileManager.default.createSymbolicLink(
            at: fixture.manifestURL,
            withDestinationURL: externalManifest
        )

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadManifest()
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .invalidManifest)
        }
    }

    func testThumbnailSymlinkIsRejectedWithoutReadingExternalTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let blobName = "\(UUID().uuidString.lowercased()).kht"
        let externalThumbnail = fixture.root.appendingPathComponent("external-thumbnail.kht")
        let externalCiphertext = try fixture.access.seal(
            Data("external".utf8),
            for: .thumbnail(item)
        )
        try externalCiphertext.write(to: externalThumbnail)
        try FileManager.default.createSymbolicLink(
            at: fixture.storageRoot.appendingPathComponent(blobName),
            withDestinationURL: externalThumbnail
        )
        try fixture.writeManifest(
            VaultFolderPresentationManifest(
                version: VaultFolderPresentationManifest.currentVersion,
                folders: [],
                memberships: [],
                thumbnails: [
                    VaultPresentationThumbnailRecord(item: item, blobName: blobName)
                ]
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadThumbnail(for: item)
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .verificationFailed)
        }
    }

    func testPathTraversalThumbnailNameIsRejectedByManifestValidation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .photo, id: UUID())
        try fixture.writeManifest(
            VaultFolderPresentationManifest(
                version: VaultFolderPresentationManifest.currentVersion,
                folders: [],
                memberships: [],
                thumbnails: [
                    VaultPresentationThumbnailRecord(item: item, blobName: "../outside.kht")
                ]
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadManifest()
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .invalidManifest)
        }
    }

    func testDecryptedThumbnailSizeIsValidated() async throws {
        let vaultID = UUID()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FolderPresentationExpansionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let expandedThumbnail = Data(
            repeating: 0xA5,
            count: VaultFolderPresentationStore.maximumThumbnailByteCount + 1
        )
        let access = TestAccess(
            vaultID: vaultID,
            thumbnailPlaintextOverride: expandedThumbnail
        )
        let store = try VaultFolderPresentationStore(
            vaultID: vaultID,
            access: access,
            storageRoot: root
        )
        let item = VaultPresentedContentReference(kind: .photo, id: UUID())
        let blobName = "\(UUID().uuidString.lowercased()).kht"
        let manifest = VaultFolderPresentationManifest(
            version: VaultFolderPresentationManifest.currentVersion,
            folders: [],
            memberships: [],
            thumbnails: [VaultPresentationThumbnailRecord(item: item, blobName: blobName)]
        )
        let encodedManifest = try JSONEncoder().encode(manifest)
        let manifestCiphertext = try access.seal(encodedManifest, for: .manifest)
        try manifestCiphertext.write(to: root.appendingPathComponent("manifest.khm"))
        let thumbnailCiphertext = try access.seal(Data([0x01]), for: .thumbnail(item))
        try thumbnailCiphertext.write(to: root.appendingPathComponent(blobName))

        await XCTAssertThrowsErrorAsync(
            try await store.loadThumbnail(for: item)
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .verificationFailed)
        }
    }

    func testAccessMustMatchVault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FolderPresentationMismatch-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(
            try VaultFolderPresentationStore(
                vaultID: UUID(),
                access: TestAccess(vaultID: UUID()),
                storageRoot: root
            )
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .accessMismatch)
        }
    }

    func testSymbolicLinkStorageRootIsRejected() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FolderPresentationRootSymlink-\(UUID().uuidString)",
            isDirectory: true
        )
        let target = base.appendingPathComponent("Target", isDirectory: true)
        let link = base.appendingPathComponent("Link", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let vaultID = UUID()
        XCTAssertThrowsError(
            try VaultFolderPresentationStore(
                vaultID: vaultID,
                access: TestAccess(vaultID: vaultID),
                storageRoot: link
            )
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .invalidStorageRoot)
        }
    }
}

private struct Fixture {
    let root: URL
    let storageRoot: URL
    let access: TestAccess
    let store: VaultFolderPresentationStore

    var manifestURL: URL {
        storageRoot.appendingPathComponent("manifest.khm")
    }

    init() throws {
        let vaultID = UUID()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FolderPresentationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storageRoot = root.appendingPathComponent("Store", isDirectory: true)
        access = TestAccess(vaultID: vaultID)
        store = try VaultFolderPresentationStore(
            vaultID: vaultID,
            access: access,
            storageRoot: storageRoot
        )
    }

    func encryptedManifestData(_ manifest: VaultFolderPresentationManifest) throws -> Data {
        let plaintext = try JSONEncoder().encode(manifest)
        return try access.seal(plaintext, for: .manifest)
    }

    func writeManifest(_ manifest: VaultFolderPresentationManifest) throws {
        try encryptedManifestData(manifest).write(to: manifestURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class TestAccess: VaultFolderPresentationCryptographicAccess,
    @unchecked Sendable {
    let vaultID: UUID
    private let key = SymmetricKey(size: .bits256)
    private let thumbnailPlaintextOverride: Data?
    private let lock = NSLock()
    private var revoked = false

    init(vaultID: UUID, thumbnailPlaintextOverride: Data? = nil) {
        self.vaultID = vaultID
        self.thumbnailPlaintextOverride = thumbnailPlaintextOverride
    }

    func checkAccess() throws {
        lock.lock()
        defer { lock.unlock() }
        if revoked { throw TestAccessError.revoked }
    }

    func seal(
        _ plaintext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try checkAccess()
        return try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(
        _ ciphertext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try checkAccess()
        let plaintext = try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
        if case .thumbnail(_) = purpose,
           let thumbnailPlaintextOverride {
            return thumbnailPlaintextOverride
        }
        return plaintext
    }

    func revoke() {
        lock.lock()
        revoked = true
        lock.unlock()
    }

    private func derivedKey(for purpose: VaultFolderPresentationKeyPurpose) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(purpose.cryptographicDomain.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}

private enum TestAccessError: Error, Equatable {
    case revoked
}

private enum FolderManifestCommitTestError: Error {
    case committedThenThrew
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
