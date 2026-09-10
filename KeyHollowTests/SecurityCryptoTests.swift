import CryptoKit
import Foundation
import SwiftUI
import XCTest
@testable import KeyHollow
@testable import KeyHollowCryptoCore
@testable import KeyHollowPhotoCore
@testable import KeyHollowVaultCore

final class SecurityCryptoTests: XCTestCase {
    func testPasscodesRequireAtLeastEightDigitsEverywhere() {
        XCTAssertFalse(PasscodePolicy.isValidForUnlock("000000"))
        XCTAssertFalse(PasscodePolicy.isValidForUnlock("1234567"))
        XCTAssertTrue(PasscodePolicy.isValidForUnlock("83057291"))
        XCTAssertFalse(PasscodePolicy.isValidForUnlock("83057291x"))
    }

    func testNewPasscodeGuardrailsRejectPredictableChoices() {
        let rejected = [
            "000000",
            "00000000",
            "111111111",
            "12345678",
            "123456789",
            "987654321",
            "78901234",
            "12121212",
            "12341234",
            "11111234"
        ]

        for passcode in rejected {
            XCTAssertFalse(
                PasscodePolicy.isAcceptableNewPasscode(passcode),
                "Predictable passcode should be rejected: \(passcode)"
            )
        }

        XCTAssertTrue(PasscodePolicy.isAcceptableNewPasscode("83057291"))
        XCTAssertTrue(PasscodePolicy.isAcceptableNewPasscode("8305729146"))
    }

    func testSecurityTiersStartAtEightDigits() {
        XCTAssertEqual(PasscodeTier.standard.fixedLength, 8)
        XCTAssertEqual(PasscodeTier.enhanced.fixedLength, 10)
        XCTAssertEqual(PasscodeTier.high.fixedLength, 12)
        XCTAssertEqual(PasscodeTier.maximum.fixedLength, 16)

        XCTAssertTrue(
            PasscodePolicy.isAcceptableNewPasscode("83057291", tier: .standard)
        )
        XCTAssertFalse(
            PasscodePolicy.isAcceptableNewPasscode("83057291", tier: .enhanced)
        )
    }

    func testRFC9106Argon2idVector() throws {
        let tag = try Argon2id.deriveBytes(
            password: Data(repeating: 0x01, count: 32),
            salt: Data(repeating: 0x02, count: 16),
            memoryKiB: 32,
            iterations: 3,
            parallelism: 4,
            outputByteCount: 32,
            secret: Data(repeating: 0x03, count: 8),
            associatedData: Data(repeating: 0x04, count: 12)
        )

        XCTAssertEqual(
            tag,
            try Data(hex: "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659")
        )
    }

    func testAESGCMRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("KeyHollow authenticated encryption test".utf8)
        let ciphertext = try CryptoBox.seal(plaintext, using: key)

        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertEqual(try CryptoBox.open(ciphertext, using: key), plaintext)
    }

    func testAESGCMTamperFailsClosed() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("private photo bytes".utf8)
        var ciphertext = try CryptoBox.seal(plaintext, using: key)
        XCTAssertFalse(ciphertext.isEmpty)

        ciphertext[ciphertext.index(before: ciphertext.endIndex)] ^= 0x01
        XCTAssertThrowsError(try CryptoBox.open(ciphertext, using: key))
    }

    func testVaultSubkeysAreDomainSeparated() {
        let vaultKey = SymmetricKey(size: .bits256)
        let id = UUID()

        let manifest = VaultPhotoKeySchedule.manifestKey(from: vaultKey).bytes
        let photo = VaultPhotoKeySchedule.photoKey(from: vaultKey, id: id).bytes
        let thumbnail = VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: id).bytes

        XCTAssertNotEqual(manifest, photo)
        XCTAssertNotEqual(manifest, thumbnail)
        XCTAssertNotEqual(photo, thumbnail)
    }

    func testVaultEnvelopeCanBeRewrappedWithoutChangingVaultKey() throws {
        let oldUnlockKey = SymmetricKey(size: .bits256)
        let newUnlockKey = SymmetricKey(size: .bits256)
        let created = try VaultEnvelope.create(using: oldUnlockKey)

        let replacement = try VaultEnvelope.seal(payload: created.payload, using: newUnlockKey)
        let reopened = try replacement.open(using: newUnlockKey)

        XCTAssertEqual(reopened.vaultID, created.payload.vaultID)
        XCTAssertEqual(reopened.vaultKey, created.payload.vaultKey)
        XCTAssertEqual(reopened.createdAt, created.payload.createdAt)
        XCTAssertThrowsError(try replacement.open(using: oldUnlockKey))
    }

    func testPhotoStorePersistsOnlyAuthenticatedCiphertext() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let key = SymmetricKey(size: .bits256)
        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: key,
            storageRoot: root
        )
        let original = Data("KEYHOLLOW-PLAINTEXT-ORIGINAL-MARKER".utf8)
        let thumbnail = Data("KEYHOLLOW-PLAINTEXT-THUMBNAIL-MARKER".utf8)

        let record = try await store.importPhoto(
            originalData: original,
            thumbnailData: thumbnail
        )

        let storedOriginal = try Data(contentsOf: root.appendingPathComponent(record.blobName))
        let storedThumbnail = try Data(contentsOf: root.appendingPathComponent(record.thumbnailName))
        let storedManifest = try Data(contentsOf: root.appendingPathComponent("manifest.khm"))

        XCTAssertNotEqual(storedOriginal, original)
        XCTAssertNotEqual(storedThumbnail, thumbnail)
        XCTAssertNil(storedOriginal.range(of: original))
        XCTAssertNil(storedThumbnail.range(of: thumbnail))
        XCTAssertThrowsError(try JSONDecoder().decode(VaultPhotoManifest.self, from: storedManifest))
        let reopenedOriginal = try await store.loadPhoto(record)
        let reopenedThumbnail = try await store.loadThumbnail(record)
        XCTAssertEqual(reopenedOriginal, original)
        XCTAssertEqual(reopenedThumbnail, thumbnail)
    }

    func testPhotoImportAcceptsAuthenticatedManifestWhenReplaceCommitsThenThrows() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let initialStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )
        _ = try await initialStore.importPhoto(
            originalData: Data("existing".utf8),
            thumbnailData: Data("existing thumbnail".utf8)
        )
        let faultingStore = try VaultPhotoStore(
            vaultID: vaultID,
            access: DirectVaultPhotoAccess(vaultID: vaultID, vaultKey: key),
            storageRoot: root,
            manifestCommitDidComplete: {
                throw PhotoManifestCommitTestError.committedThenThrew
            }
        )

        let record = try await faultingStore.importPhoto(
            originalData: Data("new original".utf8),
            thumbnailData: Data("new thumbnail".utf8)
        )

        let durable = try await initialStore.loadManifest()
        XCTAssertEqual(durable.photos.count, 2)
        XCTAssertTrue(durable.photos.contains(record))
        let reopenedOriginal = try await faultingStore.loadPhoto(record)
        let reopenedThumbnail = try await faultingStore.loadThumbnail(record)
        XCTAssertEqual(reopenedOriginal, Data("new original".utf8))
        XCTAssertEqual(reopenedThumbnail, Data("new thumbnail".utf8))
    }

    func testPhotoImportPreservesBlobsWhenPostCommitManifestCannotBeVerified() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let initialStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )
        _ = try await initialStore.importPhoto(
            originalData: Data("existing".utf8),
            thumbnailData: Data("existing thumbnail".utf8)
        )
        let manifestURL = root.appendingPathComponent("manifest.khm")
        let faultingStore = try VaultPhotoStore(
            vaultID: vaultID,
            access: DirectVaultPhotoAccess(vaultID: vaultID, vaultKey: key),
            storageRoot: root,
            manifestCommitDidComplete: {
                try Data("unverifiable".utf8).write(to: manifestURL, options: .atomic)
                throw PhotoManifestCommitTestError.committedThenThrew
            }
        )

        do {
            _ = try await faultingStore.importPhoto(
                originalData: Data("must remain encrypted".utf8),
                thumbnailData: Data("thumbnail must remain encrypted".utf8)
            )
            XCTFail("An unverifiable post-commit manifest reported success")
        } catch VaultPhotoStore.StoreError.manifestCommitStateUnknown {}

        let storedNames = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(storedNames.filter { $0.hasSuffix(".khp") }.count, 2)
        XCTAssertEqual(storedNames.filter { $0.hasSuffix(".kht") }.count, 2)
    }

    func testPhotoDeleteFinishesCleanupWhenManifestReplaceCommitsThenThrows() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let initialStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )
        let record = try await initialStore.importPhoto(
            originalData: Data("delete original".utf8),
            thumbnailData: Data("delete thumbnail".utf8)
        )
        let faultingStore = try VaultPhotoStore(
            vaultID: vaultID,
            access: DirectVaultPhotoAccess(vaultID: vaultID, vaultKey: key),
            storageRoot: root,
            manifestCommitDidComplete: {
                throw PhotoManifestCommitTestError.committedThenThrew
            }
        )

        try await faultingStore.delete(record)

        let durable = try await initialStore.loadManifest()
        XCTAssertTrue(durable.photos.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(record.blobName).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(record.thumbnailName).path
            )
        )
    }

    func testPhotoStoreFailsClosedWithWrongKeyOrTamperedBlob() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        let record = try await store.importPhoto(
            originalData: Data("private original".utf8),
            thumbnailData: Data("private thumbnail".utf8)
        )

        let wrongKeyStore = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        do {
            _ = try await wrongKeyStore.loadManifest()
            XCTFail("A different vault key decrypted the manifest")
        } catch {}

        let blobURL = root.appendingPathComponent(record.blobName)
        var ciphertext = try Data(contentsOf: blobURL)
        ciphertext[ciphertext.index(before: ciphertext.endIndex)] ^= 0x01
        try ciphertext.write(to: blobURL, options: .atomic)

        do {
            _ = try await store.loadPhoto(record)
            XCTFail("Tampered photo ciphertext was accepted")
        } catch {}
    }

    func testDeletingPhotoRemovesManifestReferenceAndEncryptedBlobs() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        let record = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )

        try await store.delete(record)

        let manifest = try await store.loadManifest()
        XCTAssertTrue(manifest.photos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(record.blobName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(record.thumbnailName).path))
    }

    func testDeletingMultiplePhotosPreservesUnselectedEncryptedPhoto() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        let first = try await store.importPhoto(
            originalData: Data("first original".utf8),
            thumbnailData: Data("first thumbnail".utf8)
        )
        let second = try await store.importPhoto(
            originalData: Data("second original".utf8),
            thumbnailData: Data("second thumbnail".utf8)
        )
        let preserved = try await store.importPhoto(
            originalData: Data("preserved original".utf8),
            thumbnailData: Data("preserved thumbnail".utf8)
        )

        try await store.delete([first, second])

        let manifest = try await store.loadManifest()
        let preservedData = try await store.loadPhoto(preserved)
        XCTAssertEqual(manifest.photos, [preserved])
        XCTAssertEqual(preservedData, Data("preserved original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.blobName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(second.blobName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(preserved.blobName).path))
    }

    func testPhotoStoreResolvesUnsafeCallerPathsToCanonicalManifestPaths() async throws {
        let root = temporaryDirectory()
        let outside = root.deletingLastPathComponent().appendingPathComponent(
            "KeyHollow-photo-sentinel-\(UUID().uuidString)"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        let record = try await store.importPhoto(
            originalData: Data("canonical original".utf8),
            thumbnailData: Data("canonical thumbnail".utf8)
        )
        try Data("must survive".utf8).write(to: outside)
        let fabricated = VaultPhotoRecord(
            id: record.id,
            importedAt: record.importedAt,
            blobName: "../\(outside.lastPathComponent)",
            thumbnailName: "../\(outside.lastPathComponent)",
            displayName: record.displayName,
            originalByteCount: record.originalByteCount
        )

        let canonicalOriginal = try await store.loadPhoto(fabricated)
        let canonicalThumbnail = try await store.loadThumbnail(fabricated)
        XCTAssertEqual(canonicalOriginal, Data("canonical original".utf8))
        XCTAssertEqual(canonicalThumbnail, Data("canonical thumbnail".utf8))

        try await store.delete(fabricated)
        let manifest = try await store.loadManifest()
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(manifest.photos.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(record.blobName).path
            )
        )
    }

    func testPhotoStoreRejectsForgedManifestTopology() async throws {
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let firstID = UUID()
        let secondID = UUID()
        let first = VaultPhotoRecord(
            id: firstID,
            importedAt: Date(),
            blobName: "first.khp",
            thumbnailName: "first.kht",
            displayName: nil,
            originalByteCount: 1
        )
        let malformedManifests = [
            VaultPhotoManifest(version: VaultPhotoManifest.currentVersion, photos: [
                first,
                VaultPhotoRecord(
                    id: firstID,
                    importedAt: Date(),
                    blobName: "second.khp",
                    thumbnailName: "second.kht",
                    displayName: nil,
                    originalByteCount: 1
                )
            ]),
            VaultPhotoManifest(version: VaultPhotoManifest.currentVersion, photos: [
                first,
                VaultPhotoRecord(
                    id: secondID,
                    importedAt: Date(),
                    blobName: first.blobName,
                    thumbnailName: "second.kht",
                    displayName: nil,
                    originalByteCount: 1
                )
            ]),
            VaultPhotoManifest(version: VaultPhotoManifest.currentVersion, photos: [
                VaultPhotoRecord(
                    id: firstID,
                    importedAt: Date(),
                    blobName: "../outside.khp",
                    thumbnailName: "inside.kht",
                    displayName: nil,
                    originalByteCount: 1
                )
            ])
        ]

        for manifest in malformedManifests {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try VaultPhotoStore(
                vaultID: vaultID,
                vaultKey: key,
                storageRoot: root
            )
            try writeEncryptedPhotoManifest(manifest, key: key, root: root)
            do {
                _ = try await store.loadManifest()
                XCTFail("A forged photo manifest topology was accepted")
            } catch VaultPhotoStore.StoreError.invalidManifest {}
        }
    }

    func testLegacyPhotoCountLoadsAndDeletesButRejectsFurtherGrowthWithoutOrphans() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let store = try VaultPhotoStore(vaultID: vaultID, vaultKey: key, storageRoot: root)
        let records = (0...VaultPhotoStore.maximumPhotoCount).map { index in
            VaultPhotoRecord(
                id: UUID(),
                importedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                blobName: "p\(index).khp",
                thumbnailName: "t\(index).kht",
                displayName: nil,
                originalByteCount: 1
            )
        }
        try writeEncryptedPhotoManifest(
            VaultPhotoManifest(version: VaultPhotoManifest.currentVersion, photos: records),
            key: key,
            root: root
        )
        let loadedLegacyManifest = try await store.loadManifest()
        XCTAssertEqual(loadedLegacyManifest.photos.count, records.count)
        let before = try Set(
            FileManager.default.contentsOfDirectory(atPath: root.path)
        )

        do {
            _ = try await store.importPhoto(
                originalData: Data("one more".utf8),
                thumbnailData: Data("thumb".utf8)
            )
            XCTFail("An import exceeded the photo-count ceiling")
        } catch VaultPhotoStore.StoreError.photoLimitReached {}

        let after = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
        XCTAssertEqual(after, before)

        try await store.delete(records[0])
        let manifestAfterDelete = try await store.loadManifest()
        XCTAssertEqual(manifestAfterDelete.photos.count, records.count - 1)
    }

    func testPhotoManifestKeepsLegacyLargeDeclaredOriginalBrowsable() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let record = VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(),
            blobName: "legacy.khp",
            thumbnailName: "legacy.kht",
            displayName: "Legacy panorama",
            originalByteCount: VaultPhotoStore.maximumOriginalByteCount + 1
        )
        let manifest = VaultPhotoManifest(
            version: VaultPhotoManifest.currentVersion,
            photos: [record]
        )
        let store = try VaultPhotoStore(vaultID: vaultID, vaultKey: key, storageRoot: root)
        try writeEncryptedPhotoManifest(manifest, key: key, root: root)

        let loadedManifest = try await store.loadManifest()
        XCTAssertEqual(loadedManifest.version, manifest.version)
        XCTAssertEqual(loadedManifest.photos, manifest.photos)

        let originalURL = root.appendingPathComponent(record.blobName)
        XCTAssertTrue(FileManager.default.createFile(atPath: originalURL.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: originalURL)
        try handle.truncate(atOffset: VaultPhotoStore.maximumOriginalByteCount + 29)
        try handle.close()
        do {
            _ = try await store.loadPhoto(record)
            XCTFail("An oversized legacy item was opened instead of reporting its item error")
        } catch VaultPhotoStore.StoreError.originalTooLarge {}
    }

    func testPhotoStoresRefreshManifestBeforeSequentialCrossInstanceMutation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let firstStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )
        let secondStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )

        let first = try await firstStore.importPhoto(
            originalData: Data("first".utf8),
            thumbnailData: Data("first thumb".utf8)
        )
        let second = try await secondStore.importPhoto(
            originalData: Data("second".utf8),
            thumbnailData: Data("second thumb".utf8)
        )
        let third = try await firstStore.importPhoto(
            originalData: Data("third".utf8),
            thumbnailData: Data("third thumb".utf8)
        )

        let manifest = try await secondStore.loadManifest()
        XCTAssertEqual(Set(manifest.photos.map(\.id)), Set([first.id, second.id, third.id]))
    }

    func testPhotoStoreInvalidatesCachedRecordAfterAnotherInstanceDeletesIt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let firstStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )
        let secondStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )
        let record = try await firstStore.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        _ = try await firstStore.loadPhoto(record)

        try await secondStore.delete(record)

        do {
            _ = try await firstStore.loadPhoto(record)
            XCTFail("A cross-instance deletion left a cached record usable")
        } catch VaultPhotoStore.StoreError.invalidManifest {}
    }

    func testPhotoDestroySharesMutationBoundaryWithCachedReads() async throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let storageRoot = parent.appendingPathComponent(
            vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: storageRoot
        )
        let original = Data("coherent before destroy".utf8)
        let record = try await store.importPhoto(
            originalData: original,
            thumbnailData: Data("thumbnail".utf8)
        )
        _ = try await store.loadPhoto(record)

        let readTask = Task {
            do {
                return try await store.loadPhoto(record) == original
            } catch VaultPhotoStore.StoreError.invalidManifest {
                return true
            } catch {
                return false
            }
        }
        let destroyTask = Task.detached {
            try VaultPhotoStore.destroyVaultData(vaultID: vaultID, storageRoot: parent)
        }

        let readObservedOnlyCoherentState = await readTask.value
        try await destroyTask.value
        XCTAssertTrue(readObservedOnlyCoherentState)
        let manifestAfterDestroy = try await store.loadManifest()
        XCTAssertTrue(manifestAfterDestroy.photos.isEmpty)
        do {
            _ = try await store.loadPhoto(record)
            XCTFail("Destroy left a cached record usable")
        } catch VaultPhotoStore.StoreError.invalidManifest {}
    }

    func testPhotoStoreRejectsSymlinkedAndSparseOversizedCiphertext() async throws {
        let root = temporaryDirectory()
        let outside = root.deletingLastPathComponent().appendingPathComponent(
            "KeyHollow-photo-blob-sentinel-\(UUID().uuidString)"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        let record = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        let originalURL = root.appendingPathComponent(record.blobName)
        try FileManager.default.removeItem(at: originalURL)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: originalURL, withDestinationURL: outside)
        do {
            _ = try await store.loadPhoto(record)
            XCTFail("A symlinked photo blob was followed")
        } catch VaultPhotoStore.StoreError.invalidManifest {}

        try FileManager.default.removeItem(at: originalURL)
        XCTAssertTrue(FileManager.default.createFile(atPath: originalURL.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: originalURL)
        try handle.truncate(atOffset: VaultPhotoStore.maximumOriginalByteCount + 29)
        try handle.close()
        do {
            _ = try await store.loadPhoto(record)
            XCTFail("A sparse oversized photo blob was read into memory")
        } catch VaultPhotoStore.StoreError.originalTooLarge {}
    }

    func testPhotoStoreRejectsBlobReplacedBySymlinkAfterBoundedRead() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let initialStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: root
        )
        let record = try await initialStore.importPhoto(
            originalData: Data("bounded original".utf8),
            thumbnailData: Data("bounded thumbnail".utf8)
        )
        let replacementURL = root.appendingPathComponent("replacement.khp")
        try Data(repeating: 0x55, count: 64).write(to: replacementURL)

        let faultingStore = try VaultPhotoStore(
            vaultID: vaultID,
            access: DirectVaultPhotoAccess(vaultID: vaultID, vaultKey: key),
            storageRoot: root,
            manifestCommitDidComplete: {},
            ciphertextReadDidComplete: { url in
                guard url.pathExtension == "khp" else { return }
                try! FileManager.default.removeItem(at: url)
                try! FileManager.default.createSymbolicLink(
                    at: url,
                    withDestinationURL: replacementURL
                )
            }
        )

        do {
            _ = try await faultingStore.loadPhoto(record)
            XCTFail("A photo blob replaced by a symlink after its bounded read was accepted")
        } catch VaultPhotoStore.StoreError.invalidManifest {}
    }

    func testPhotoManifestRejectsSparseOversizeAndSymlinkBeforeReading() async throws {
        let root = temporaryDirectory()
        let outside = root.deletingLastPathComponent().appendingPathComponent(
            "KeyHollow-photo-manifest-sentinel-\(UUID().uuidString)"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        let manifestURL = root.appendingPathComponent("manifest.khm")
        XCTAssertTrue(FileManager.default.createFile(atPath: manifestURL.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: manifestURL)
        try handle.truncate(
            atOffset: UInt64(VaultPhotoStore.legacyMaximumManifestByteCount) + 29
        )
        try handle.close()
        do {
            _ = try await store.loadManifest()
            XCTFail("A sparse oversized photo manifest was read into memory")
        } catch VaultPhotoStore.StoreError.invalidManifest {}

        try FileManager.default.removeItem(at: manifestURL)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: manifestURL,
            withDestinationURL: outside
        )
        do {
            _ = try await store.loadManifest()
            XCTFail("A symlinked photo manifest was followed")
        } catch VaultPhotoStore.StoreError.invalidManifest {}
    }

    func testVaultStoreRejectsNonCanonicalLocatorPaths() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try VaultStore(rootOverride: root)

        let containsTraversal = await store.contains(locator: "../escape")
        XCTAssertFalse(containsTraversal)
        do {
            _ = try await store.read(locator: "../escape")
            XCTFail("A traversal locator was accepted")
        } catch VaultStore.StoreError.invalidLocator {}
        do {
            try await store.delete(locator: String(repeating: "A", count: 64))
            XCTFail("An uppercase noncanonical locator was accepted")
        } catch VaultStore.StoreError.invalidLocator {}
    }

    func testVaultStoreRejectsOversizedAndSymbolicLinkCredentialFiles() async throws {
        let root = temporaryDirectory()
        let outside = root.deletingLastPathComponent().appendingPathComponent(
            "KeyHollow-credential-sentinel-\(UUID().uuidString)"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = try VaultStore(rootOverride: root)
        let oversizedLocator = String(repeating: "a", count: 64)
        let oversizedURL = root
            .appendingPathComponent(oversizedLocator)
            .appendingPathExtension("khv")
        try Data(
            repeating: 0x41,
            count: Int(VaultStore.maximumEnvelopeByteCount) + 1
        ).write(to: oversizedURL)

        do {
            _ = try await store.read(locator: oversizedLocator)
            XCTFail("An oversized credential envelope was read into memory")
        } catch VaultStore.StoreError.invalidEnvelopeFile {}

        try Data("outside".utf8).write(to: outside)
        let symlinkLocator = String(repeating: "b", count: 64)
        let symlinkURL = root
            .appendingPathComponent(symlinkLocator)
            .appendingPathExtension("khv")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: outside
        )

        do {
            _ = try await store.read(locator: symlinkLocator)
            XCTFail("A symbolic-link credential envelope was followed")
        } catch VaultStore.StoreError.invalidEnvelopeFile {}

        let encodedOversizeLocator = String(repeating: "c", count: 64)
        do {
            try await store.writeIfAbsent(
                VaultEnvelope(
                    version: 1,
                    sealedPayload: Data(
                        repeating: 0x42,
                        count: Int(VaultStore.maximumEnvelopeByteCount)
                    )
                ),
                locator: encodedOversizeLocator
            )
            XCTFail("An oversized encoded credential envelope was persisted")
        } catch VaultStore.StoreError.invalidEnvelopeFile {}
        let containsOversizedEnvelope = await store.contains(locator: encodedOversizeLocator)
        XCTAssertFalse(containsOversizedEnvelope)
    }

    @MainActor
    func testSystemPhotoOperationScopeIsBalancedAndNestSafe() {
        let session = VaultSession()
        XCTAssertFalse(session.isSystemInteractionActive)

        session.beginSystemPhotoOperation()
        session.beginSystemPhotoOperation()
        XCTAssertTrue(session.isSystemInteractionActive)

        session.endSystemPhotoOperation()
        XCTAssertTrue(session.isSystemInteractionActive)

        session.endSystemPhotoOperation()
        XCTAssertFalse(session.isSystemInteractionActive)

        session.endSystemPhotoOperation()
        XCTAssertFalse(session.isSystemInteractionActive)

        session.beginSystemInteraction()
        XCTAssertTrue(session.isSystemInteractionActive)
        session.lock()
        XCTAssertFalse(session.isSystemInteractionActive)

        session.beginSystemInteraction()
        session.endSystemInteraction()
        XCTAssertFalse(session.isSystemInteractionActive)
    }

    func testPhotosPromptLifecycleDoesNotLockDuringInactiveHandoff() {
        XCTAssertFalse(VaultLifecycleLockPolicy.shouldLock(
            for: .inactive,
            systemInteractionActive: true
        ))
        XCTAssertFalse(VaultLifecycleLockPolicy.shouldLockWhenSystemInteractionEnds(
            scenePhase: .inactive
        ))
        XCTAssertFalse(VaultLifecycleLockPolicy.shouldLock(
            for: .active,
            systemInteractionActive: false
        ))
    }

    func testPhotosPromptLifecycleStillLocksOnRealBackground() {
        XCTAssertTrue(VaultLifecycleLockPolicy.shouldLock(
            for: .background,
            systemInteractionActive: true
        ))
        XCTAssertTrue(VaultLifecycleLockPolicy.shouldLockWhenSystemInteractionEnds(
            scenePhase: .background
        ))
        XCTAssertTrue(VaultLifecycleLockPolicy.shouldLock(
            for: .inactive,
            systemInteractionActive: false
        ))
    }

    func testSuccessfulUnlockDoesNotEraseGlobalFailureBudget() async throws {
        let suite = "KeyHollowTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let limiter = UnlockAttemptLimiter(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)

        for _ in 0..<5 {
            await limiter.recordFailure(now: start)
        }

        // A legitimate unlock may clear the completed active cooldown so the
        // user can enter a known vault, but it must preserve the accumulated
        // failure count. The next bad guess must therefore resume throttling.
        let afterInitialCooldown = start.addingTimeInterval(6)
        await limiter.recordSuccess(now: afterInitialCooldown)
        await limiter.recordFailure(now: afterInitialCooldown)

        do {
            try await limiter.checkAllowed(now: afterInitialCooldown.addingTimeInterval(1))
            XCTFail("A valid vault unlock erased the multi-vault guessing history")
        } catch UnlockAttemptLimiter.LimitError.temporarilyLocked(let until) {
            XCTAssertGreaterThan(until, afterInitialCooldown.addingTimeInterval(1))
        } catch {
            XCTFail("Unexpected limiter error: \(error)")
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyHollowTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeEncryptedPhotoManifest(
        _ manifest: VaultPhotoManifest,
        key: SymmetricKey,
        root: URL
    ) throws {
        let plaintext = try JSONEncoder().encode(manifest)
        let ciphertext = try CryptoBox.seal(
            plaintext,
            using: VaultPhotoKeySchedule.manifestKey(from: key)
        )
        try ciphertext.write(
            to: root.appendingPathComponent("manifest.khm"),
            options: .atomic
        )
    }
}

private extension SymmetricKey {
    var bytes: Data {
        withUnsafeBytes { Data($0) }
    }
}

private enum PhotoManifestCommitTestError: Error {
    case committedThenThrew
}

private extension Data {
    init(hex: String) throws {
        guard hex.count.isMultiple(of: 2) else { throw HexError.invalid }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw HexError.invalid }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    enum HexError: Error { case invalid }
}


