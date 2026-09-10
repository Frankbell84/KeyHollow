import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowCryptoCore
@testable import KeyHollowGeneralFileSupportAddOn

final class VaultGeneralFileSupportAddOnTests: XCTestCase {
    func testImportLowKeyContinueAppearsOnlyForACompleteValidMatch() {
        XCTAssertTrue(
            ImportLowKeyContinuation.shouldReveal(
                newPasscode: "73918462",
                confirmation: "73918462",
                requiredLength: 8,
                rejectionMessage: nil
            )
        )
        XCTAssertFalse(
            ImportLowKeyContinuation.shouldReveal(
                newPasscode: "73918462",
                confirmation: "73918461",
                requiredLength: 8,
                rejectionMessage: nil
            )
        )
        XCTAssertFalse(
            ImportLowKeyContinuation.shouldReveal(
                newPasscode: "73918462",
                confirmation: "73918462",
                requiredLength: 8,
                rejectionMessage: "Predictable"
            )
        )
    }

    func testPrimaryVaultIsNotEmptyWhenOnlyGeneralFilesExist() {
        XCTAssertFalse(VaultContentAvailability.isEmpty(photoCount: 0, generalFileCount: 1))
        XCTAssertFalse(VaultContentAvailability.isEmpty(photoCount: 1, generalFileCount: 0))
        XCTAssertFalse(VaultContentAvailability.isEmpty(photoCount: 1, generalFileCount: 1))
        XCTAssertTrue(VaultContentAvailability.isEmpty(photoCount: 0, generalFileCount: 0))
    }

    func testRevokedAccessRejectsEmptyManifestLoad() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.storageRoot.appendingPathComponent("manifest.khm").path
            )
        )

        fixture.access.revoke()

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.loadManifest()
        ) { error in
            XCTAssertEqual(error as? TestAccessError, .revoked)
        }
    }

    func testStoreInstancesSerializeConcurrentImports() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let secondStore = try VaultGeneralFileStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot,
            temporaryRoot: fixture.root.appendingPathComponent("Temporary", isDirectory: true)
        )
        let stores = [fixture.store, secondStore]
        let sources = try (0..<24).map { index in
            try fixture.source(
                named: "concurrent-\(index).txt",
                data: Data("protected-\(index)".utf8)
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, source) in sources.enumerated() {
                let store = stores[index % stores.count]
                group.addTask {
                    _ = try await store.importFile(at: source)
                }
            }
            try await group.waitForAll()
        }

        let manifest = try await fixture.store.validateAllEncryptedFiles()
        XCTAssertEqual(manifest.files.count, sources.count)
        XCTAssertEqual(
            Set(manifest.files.map(\.displayName)),
            Set(sources.map(\.lastPathComponent))
        )
    }

    func testImportAcceptsAuthenticatedManifestWhenReplaceCommitsThenThrows() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.importFile(
            at: fixture.source(named: "existing.txt", data: Data("existing".utf8))
        )
        let faultingStore = try VaultGeneralFileStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot,
            temporaryRoot: fixture.root.appendingPathComponent("FaultTemporary"),
            manifestCommitDidComplete: {
                throw GeneralFileManifestCommitTestError.committedThenThrew
            }
        )

        let record = try await faultingStore.importFile(
            at: fixture.source(named: "new.txt", data: Data("new contents".utf8))
        )

        let durable = try await fixture.store.loadManifest()
        XCTAssertEqual(durable.files.count, 2)
        XCTAssertTrue(durable.files.contains(record))
        let reopened = try await faultingStore.loadFile(record)
        XCTAssertEqual(reopened, Data("new contents".utf8))
    }

    func testImportPreservesBlobWhenPostCommitManifestCannotBeVerified() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.importFile(
            at: fixture.source(named: "existing.txt", data: Data("existing".utf8))
        )
        let manifestURL = fixture.storageRoot.appendingPathComponent("manifest.khm")
        let faultingStore = try VaultGeneralFileStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot,
            temporaryRoot: fixture.root.appendingPathComponent("FaultTemporary"),
            manifestCommitDidComplete: {
                try Data("unverifiable".utf8).write(to: manifestURL, options: .atomic)
                throw GeneralFileManifestCommitTestError.committedThenThrew
            }
        )

        await XCTAssertThrowsErrorAsync(
            try await faultingStore.importFile(
                at: fixture.source(named: "new.txt", data: Data("must remain".utf8))
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultGeneralFileStore.StoreError,
                .manifestCommitStateUnknown
            )
        }

        let storedNames = try FileManager.default.contentsOfDirectory(
            atPath: fixture.storageRoot.path
        )
        XCTAssertEqual(storedNames.filter { $0.hasSuffix(".khf") }.count, 2)
    }

    func testDeleteFinishesCleanupWhenManifestReplaceCommitsThenThrows() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let record = try await fixture.store.importFile(
            at: fixture.source(named: "delete.txt", data: Data("delete me".utf8))
        )
        let blobURL = fixture.storageRoot.appendingPathComponent(record.blobName)
        let faultingStore = try VaultGeneralFileStore(
            vaultID: fixture.access.vaultID,
            access: fixture.access,
            storageRoot: fixture.storageRoot,
            temporaryRoot: fixture.root.appendingPathComponent("FaultTemporary"),
            manifestCommitDidComplete: {
                throw GeneralFileManifestCommitTestError.committedThenThrew
            }
        )

        try await faultingStore.delete([record])

        let durable = try await fixture.store.loadManifest()
        XCTAssertTrue(durable.files.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL.path))
    }

    func testBatchImportEncryptsSelectionAndLeavesSourcesUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let firstData = Data("pdf data".utf8)
        let secondData = Data("private notes".utf8)
        let first = try fixture.source(named: "Invoice.pdf", data: firstData)
        let second = try fixture.source(named: "Notes.txt", data: secondData)

        let result = try await fixture.store.importFiles(at: [first, second])
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(result, VaultGeneralFileImportResult(importedCount: 2, failedCount: 0))
        XCTAssertEqual(Set(manifest.files.map(\.displayName)), Set(["Invoice.pdf", "Notes.txt"]))
        XCTAssertEqual(try Data(contentsOf: first), firstData)
        XCTAssertEqual(try Data(contentsOf: second), secondData)
    }

    func testBatchImportReportsRejectedItemsWithoutRollingBackValidFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let valid = try fixture.source(named: "Notes.txt", data: Data("notes".utf8))
        let rejected = try fixture.source(named: "Backup.khvault", data: Data("backup".utf8))

        let result = try await fixture.store.importFiles(at: [valid, rejected])
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(result, VaultGeneralFileImportResult(importedCount: 1, failedCount: 1))
        XCTAssertEqual(manifest.files.map(\.displayName), ["Notes.txt"])
    }

    func testBatchImportRejectsMoreThanMaximumSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "Notes.txt", data: Data("notes".utf8))
        let selection = Array(
            repeating: source,
            count: VaultGeneralFileStore.maximumBatchCount + 1
        )

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFiles(at: selection)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .batchTooLarge)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
    }

    func testImportEncryptsFileAndLeavesSourceUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "Tax Notes.txt", data: Data("private notes".utf8))

        let record = try await fixture.store.importFile(at: source)
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(manifest.files, [record])
        XCTAssertEqual(record.displayName, "Tax Notes.txt")
        XCTAssertEqual(record.originalByteCount, 13)
        XCTAssertEqual(try Data(contentsOf: source), Data("private notes".utf8))

        let encryptedBlob = try Data(
            contentsOf: fixture.storageRoot.appendingPathComponent(record.blobName)
        )
        XCTAssertNotEqual(encryptedBlob, Data("private notes".utf8))
        XCTAssertFalse(String(decoding: encryptedBlob, as: UTF8.self).contains("private notes"))
    }

    func testExportAuthenticatesAndRestoresOriginalBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data([0, 1, 2, 3, 254, 255])
        let source = try fixture.source(named: "document.bin", data: original)
        let record = try await fixture.store.importFile(at: source)

        let export = try await fixture.store.prepareExport([record])

        XCTAssertEqual(export.urls.count, 1)
        XCTAssertEqual(export.urls[0].lastPathComponent, "document.bin")
        XCTAssertEqual(try Data(contentsOf: export.urls[0]), original)
        await fixture.store.discardExport(export)
    }

    func testExportSeparatesCanonicallyEquivalentNamesWithoutOverwriting() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let composedURL = try fixture.source(
            named: "Caf\u{00E9}.txt",
            data: Data("composed".utf8)
        )
        let composed = try await fixture.store.importFile(at: composedURL)
        try FileManager.default.removeItem(at: composedURL)
        let decomposed = try await fixture.store.importFile(
            at: fixture.source(
                named: "Cafe\u{0301}.txt",
                data: Data("decomposed".utf8)
            )
        )

        let export = try await fixture.store.prepareExport([composed, decomposed])

        XCTAssertEqual(export.urls.count, 2)
        XCTAssertNotEqual(export.urls[0].lastPathComponent, export.urls[1].lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: export.urls[0]), Data("composed".utf8))
        XCTAssertEqual(try Data(contentsOf: export.urls[1]), Data("decomposed".utf8))
        await fixture.store.discardExport(export)
    }

    func testExportWritesPlaintextInsideConsumingAccessBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data("consumer-scoped export".utf8)
        let source = try fixture.source(named: "scoped.txt", data: original)
        let record = try await fixture.store.importFile(at: source)
        fixture.access.requireConsumingOpenForFiles()

        let export = try await fixture.store.prepareExport([record])

        XCTAssertEqual(fixture.access.consumingFileOpenCount, 1)
        XCTAssertEqual(try Data(contentsOf: export.urls[0]), original)
        await fixture.store.discardExport(export)
    }

    func testOpeningAnotherStorePreservesLiveExportAndPurgesOrphanedPlaintext() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data("live export".utf8)
        let source = try fixture.source(named: "live.txt", data: original)
        let record = try await fixture.store.importFile(at: source)
        let export = try await fixture.store.prepareExport([record])
        let temporaryRoot = fixture.root.appendingPathComponent("Temporary", isDirectory: true)
        let orphanedRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileExports", isDirectory: true)
            .appendingPathComponent(
                "\(UUID().uuidString.lowercased())--\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: orphanedRoot,
            withIntermediateDirectories: false
        )
        try Data("orphaned plaintext".utf8).write(
            to: orphanedRoot.appendingPathComponent("stale.txt")
        )

        let secondVaultID = UUID()
        let secondStore = try VaultGeneralFileStore(
            vaultID: secondVaultID,
            access: TestAccess(vaultID: secondVaultID),
            storageRoot: fixture.root.appendingPathComponent("SecondStore", isDirectory: true),
            temporaryRoot: temporaryRoot
        )

        XCTAssertEqual(try Data(contentsOf: export.urls[0]), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedRoot.path))
        await secondStore.discardExport(export)
        XCTAssertEqual(
            try Data(contentsOf: export.urls[0]),
            original,
            "A store must not be able to discard another store's prepared export"
        )
        await fixture.store.discardExport(export)
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.urls[0].path))
    }

    func testPreparedExportKeepsOwnershipAfterPreparingStoreLeavesLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileExportLifecycleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let temporaryRoot = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("lifecycle.txt")
        let original = Data("lifecycle export".utf8)
        try original.write(to: source)

        let firstVaultID = UUID()
        var firstStore: VaultGeneralFileStore? = try VaultGeneralFileStore(
            vaultID: firstVaultID,
            access: TestAccess(vaultID: firstVaultID),
            storageRoot: root.appendingPathComponent("FirstStore", isDirectory: true),
            temporaryRoot: temporaryRoot
        )
        let record = try await firstStore!.importFile(at: source)
        var export: PreparedGeneralFileExport? = try await firstStore!.prepareExport([record])
        let exportURL = try XCTUnwrap(export?.urls.first)
        firstStore = nil

        let secondVaultID = UUID()
        let secondStore = try VaultGeneralFileStore(
            vaultID: secondVaultID,
            access: TestAccess(vaultID: secondVaultID),
            storageRoot: root.appendingPathComponent("SecondStore", isDirectory: true),
            temporaryRoot: temporaryRoot
        )

        XCTAssertEqual(try Data(contentsOf: exportURL), original)
        export = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        _ = secondStore
    }

    func testConcurrentStoreInitializationDoesNotInvalidateLiveExport() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data("concurrent live export".utf8)
        let source = try fixture.source(named: "concurrent-live.txt", data: original)
        let record = try await fixture.store.importFile(at: source)
        let export = try await fixture.store.prepareExport([record])
        let temporaryRoot = fixture.root.appendingPathComponent("Temporary", isDirectory: true)
        let root = fixture.root

        let stores = try await withThrowingTaskGroup(
            of: VaultGeneralFileStore.self,
            returning: [VaultGeneralFileStore].self
        ) { group in
            for index in 0..<16 {
                group.addTask {
                    let vaultID = UUID()
                    return try VaultGeneralFileStore(
                        vaultID: vaultID,
                        access: TestAccess(vaultID: vaultID),
                        storageRoot: root.appendingPathComponent(
                            "ConcurrentStore-\(index)",
                            isDirectory: true
                        ),
                        temporaryRoot: temporaryRoot
                    )
                }
            }

            var created: [VaultGeneralFileStore] = []
            for try await store in group {
                created.append(store)
            }
            return created
        }

        XCTAssertEqual(stores.count, 16)
        XCTAssertEqual(try Data(contentsOf: export.urls[0]), original)
        await fixture.store.discardExport(export)
    }

    func testSessionAccessRevocationWaitsForPlaintextConsumer() throws {
        let capability = VaultAccessCapability(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256)
        )
        let access = SessionGeneralFileAccess(capability: capability)
        let purpose = VaultGeneralFileKeyPurpose.file(UUID())
        let original = Data("revocation-fenced export".utf8)
        let ciphertext = try access.seal(original, for: purpose)
        let consumerEntered = DispatchSemaphore(value: 0)
        let receivedExpectedBytes = DispatchSemaphore(value: 0)
        let releaseConsumer = DispatchSemaphore(value: 0)
        let operationSucceeded = DispatchSemaphore(value: 0)
        let operationFinished = DispatchSemaphore(value: 0)
        let revokeStarted = DispatchSemaphore(value: 0)
        let revokeFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            defer { operationFinished.signal() }
            do {
                try access.open(ciphertext, for: purpose, consuming: { plaintext in
                    if plaintext == original {
                        receivedExpectedBytes.signal()
                    }
                    consumerEntered.signal()
                    _ = releaseConsumer.wait(timeout: .now() + 2)
                })
                operationSucceeded.signal()
            } catch {
                // The foreground assertions below expose any unexpected failure.
            }
        }

        XCTAssertEqual(consumerEntered.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(receivedExpectedBytes.wait(timeout: .now() + 1), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            revokeStarted.signal()
            capability.revoke()
            revokeFinished.signal()
        }

        XCTAssertEqual(revokeStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(revokeFinished.wait(timeout: .now() + 0.1), .timedOut)

        releaseConsumer.signal()

        XCTAssertEqual(operationFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(operationSucceeded.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(revokeFinished.wait(timeout: .now() + 1), .success)
        XCTAssertTrue(capability.isRevoked)
    }

    func testAuthenticatedReadResolvesCallerRecordToPersistedIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data("image bytes for preview".utf8)
        let source = try fixture.source(named: "preview.jpg", data: original)
        let record = try await fixture.store.importFile(at: source)

        let reopened = try await fixture.store.loadFile(record)
        XCTAssertEqual(reopened, original)

        let fabricated = VaultGeneralFileRecord(
            id: record.id,
            importedAt: record.importedAt,
            displayName: record.displayName,
            contentTypeIdentifier: record.contentTypeIdentifier,
            originalByteCount: record.originalByteCount,
            blobName: "fabricated.khf"
        )
        let canonicalBytes = try await fixture.store.loadFile(fabricated)
        XCTAssertEqual(canonicalBytes, original)
    }

    func testExportAndDeleteIgnoreCallerSuppliedBlobPaths() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let firstBytes = Data("first protected file".utf8)
        let secondBytes = Data("second protected file".utf8)
        let first = try await fixture.store.importFile(
            at: fixture.source(named: "first.txt", data: firstBytes)
        )
        let second = try await fixture.store.importFile(
            at: fixture.source(named: "second.txt", data: secondBytes)
        )
        let outsideSentinel = fixture.root.appendingPathComponent("outside-sentinel")
        try Data("must survive".utf8).write(to: outsideSentinel)
        let fabricated = VaultGeneralFileRecord(
            id: first.id,
            importedAt: first.importedAt,
            displayName: "spoofed.txt",
            contentTypeIdentifier: first.contentTypeIdentifier,
            originalByteCount: second.originalByteCount,
            blobName: "../outside-sentinel"
        )

        let export = try await fixture.store.prepareExport([fabricated])
        XCTAssertEqual(export.urls.map(\.lastPathComponent), ["first.txt"])
        XCTAssertEqual(try Data(contentsOf: export.urls[0]), firstBytes)
        await fixture.store.discardExport(export)

        try await fixture.store.delete([fabricated])
        let remaining = try await fixture.store.loadManifest()
        XCTAssertEqual(remaining.files, [second])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideSentinel.path))
        let remainingBytes = try await fixture.store.loadFile(second)
        XCTAssertEqual(remainingBytes, secondBytes)
    }

    func testTamperedBlobCannotBeExported() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "document.pdf", data: Data("pdf data".utf8))
        let record = try await fixture.store.importFile(at: source)
        let blobURL = fixture.storageRoot.appendingPathComponent(record.blobName)
        var ciphertext = try Data(contentsOf: blobURL)
        ciphertext[ciphertext.startIndex] ^= 0x01
        try ciphertext.write(to: blobURL, options: .atomic)

        do {
            _ = try await fixture.store.prepareExport([record])
            XCTFail("Tampered authenticated data must not be exported")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testDeleteCommitsManifestBeforeRemovingBlob() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "notes.txt", data: Data("notes".utf8))
        let record = try await fixture.store.importFile(at: source)
        let blobURL = fixture.storageRoot.appendingPathComponent(record.blobName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobURL.path))

        try await fixture.store.delete([record])

        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("notes".utf8))
    }

    func testBackupAndExecutableTypesAreRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let backup = try fixture.source(named: "backup.khvault", data: Data("backup".utf8))
        let executable = try fixture.source(named: "installer.exe", data: Data("binary".utf8))

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: backup)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .protectedFileType)
        }
        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: executable)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .protectedFileType)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
    }

    func testEmptyFilesAreRejectedWithoutChangingManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "empty.txt", data: Data())

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: source)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .emptyFile)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
    }

    func testPreviouslyValidUnicodeDisplayNameRemainsLoadable() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let legacyName = String(repeating: "界", count: 70) + ".txt"
        XCTAssertGreaterThan(
            legacyName.utf8.count,
            VaultGeneralFileStore.maximumNormalizedDisplayNameByteCount
        )
        XCTAssertLessThanOrEqual(
            legacyName.utf8.count,
            VaultGeneralFileStore.maximumPersistedDisplayNameByteCount
        )
        let record = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(),
            displayName: legacyName,
            contentTypeIdentifier: nil,
            originalByteCount: 1,
            blobName: "legacy.khf"
        )
        try fixture.writeManifest(
            VaultGeneralFileManifest(
                version: VaultGeneralFileManifest.currentVersion,
                files: [record]
            )
        )

        let loaded = try await fixture.store.loadManifest()
        XCTAssertEqual(loaded.files, [record])
    }

    func testLegacyLongContentTypeIdentifierRemainsBrowsable() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let legacyIdentifier = "com.provider." + String(
            repeating: "x",
            count: 512
        )
        let record = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(),
            displayName: "legacy.bin",
            contentTypeIdentifier: legacyIdentifier,
            originalByteCount: 1,
            blobName: "legacy-content-type.khf"
        )
        try fixture.writeManifest(
            VaultGeneralFileManifest(
                version: VaultGeneralFileManifest.currentVersion,
                files: [record]
            )
        )

        let loaded = try await fixture.store.loadManifest()
        XCTAssertEqual(loaded.files, [record])
    }

    func testForgedGeneralFileManifestTopologyFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(),
            displayName: "first.txt",
            contentTypeIdentifier: nil,
            originalByteCount: 1,
            blobName: "first.khf"
        )
        let malformedRecords = [
            [
                first,
                VaultGeneralFileRecord(
                    id: first.id,
                    importedAt: Date(),
                    displayName: "second.txt",
                    contentTypeIdentifier: nil,
                    originalByteCount: 1,
                    blobName: "second.khf"
                )
            ],
            [
                first,
                VaultGeneralFileRecord(
                    id: UUID(),
                    importedAt: Date(),
                    displayName: "second.txt",
                    contentTypeIdentifier: nil,
                    originalByteCount: 1,
                    blobName: first.blobName
                )
            ],
            [
                VaultGeneralFileRecord(
                    id: UUID(),
                    importedAt: Date(),
                    displayName: "escape.txt",
                    contentTypeIdentifier: nil,
                    originalByteCount: 1,
                    blobName: "../escape.khf"
                )
            ],
            [
                VaultGeneralFileRecord(
                    id: UUID(),
                    importedAt: Date(),
                    displayName: "oversized.txt",
                    contentTypeIdentifier: nil,
                    originalByteCount: VaultGeneralFileStore.maximumFileByteCount + 1,
                    blobName: "oversized.khf"
                )
            ]
        ]

        for records in malformedRecords {
            try fixture.writeManifest(
                VaultGeneralFileManifest(
                    version: VaultGeneralFileManifest.currentVersion,
                    files: records
                )
            )
            do {
                _ = try await fixture.store.loadManifest()
                XCTFail("A forged general-file manifest topology was accepted")
            } catch VaultGeneralFileStore.StoreError.invalidManifest {}
        }
    }

    func testLegacyStoredFileCountLoadsAndDeletesButRejectsGrowthWithoutOrphans() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let records = (0...VaultGeneralFileStore.maximumStoredFileCount).map { index in
            VaultGeneralFileRecord(
                id: UUID(),
                importedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                displayName: "f\(index).txt",
                contentTypeIdentifier: nil,
                originalByteCount: 1,
                blobName: "f\(index).khf"
            )
        }
        try fixture.writeManifest(
            VaultGeneralFileManifest(
                version: VaultGeneralFileManifest.currentVersion,
                files: records
            )
        )
        let loadedLegacyManifest = try await fixture.store.loadManifest()
        XCTAssertEqual(loadedLegacyManifest.files.count, records.count)
        let manifestURL = fixture.storageRoot.appendingPathComponent("manifest.khm")
        let manifestBefore = try Data(contentsOf: manifestURL)
        let before = try Set(
            FileManager.default.contentsOfDirectory(atPath: fixture.storageRoot.path)
        )
        let source = try fixture.source(named: "one-more.txt", data: Data("x".utf8))

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: source)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .storedFileLimitReached)
        }

        let after = try Set(
            FileManager.default.contentsOfDirectory(atPath: fixture.storageRoot.path)
        )
        XCTAssertEqual(after, before)
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBefore)

        try await fixture.store.delete([records[0]])
        let manifestAfterDelete = try await fixture.store.loadManifest()
        XCTAssertEqual(
            manifestAfterDelete.files.count,
            records.count - 1
        )
    }

    func testSymlinkedSourceAndStoredBlobAreRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "source.txt", data: Data("source".utf8))
        let symlink = fixture.sourceRoot.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: symlink)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .unsupportedItem)
        }

        let record = try await fixture.store.importFile(at: source)
        let blobURL = fixture.storageRoot.appendingPathComponent(record.blobName)
        try FileManager.default.removeItem(at: blobURL)
        try FileManager.default.createSymbolicLink(at: blobURL, withDestinationURL: source)
        await XCTAssertThrowsErrorAsync(try await fixture.store.loadFile(record)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .invalidManifest)
        }
    }

    func testSparseOversizedStoredBlobIsRejectedBeforeReading() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "source.txt", data: Data("source".utf8))
        let record = try await fixture.store.importFile(at: source)
        let blobURL = fixture.storageRoot.appendingPathComponent(record.blobName)
        try FileManager.default.removeItem(at: blobURL)
        XCTAssertTrue(FileManager.default.createFile(atPath: blobURL.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: blobURL)
        try handle.truncate(atOffset: VaultGeneralFileStore.maximumFileByteCount + 29)
        try handle.close()

        await XCTAssertThrowsErrorAsync(try await fixture.store.loadFile(record)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .fileTooLarge)
        }
    }

    func testManifestRejectsSparseOversizeAndSymlinkBeforeReading() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let manifestURL = fixture.storageRoot.appendingPathComponent("manifest.khm")
        XCTAssertTrue(FileManager.default.createFile(atPath: manifestURL.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: manifestURL)
        try handle.truncate(
            atOffset: UInt64(VaultGeneralFileStore.legacyMaximumManifestByteCount) + 29
        )
        try handle.close()

        await XCTAssertThrowsErrorAsync(try await fixture.store.loadManifest()) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .invalidManifest)
        }

        try FileManager.default.removeItem(at: manifestURL)
        let outside = fixture.root.appendingPathComponent("outside-manifest")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: manifestURL,
            withDestinationURL: outside
        )
        await XCTAssertThrowsErrorAsync(try await fixture.store.loadManifest()) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .invalidManifest)
        }
    }

    func testAccessMustBelongToSameVault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileMismatch-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let access = TestAccess(vaultID: UUID())

        XCTAssertThrowsError(
            try VaultGeneralFileStore(vaultID: UUID(), access: access, storageRoot: root)
        ) { error in
            XCTAssertEqual(error as? VaultGeneralFileStore.StoreError, .accessMismatch)
        }
    }

    func testDestroyVaultDataRemovesOnlyRequestedVaultDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileDestroyTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let firstID = UUID()
        let secondID = UUID()
        let first = root.appendingPathComponent(firstID.uuidString.lowercased(), isDirectory: true)
        let second = root.appendingPathComponent(secondID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        try VaultGeneralFileStore.destroyVaultData(vaultID: firstID, storageRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testOpeningStorePurgesInterruptedPlaintextStaging() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileStagingCleanupTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let temporaryRoot = root.appendingPathComponent("Temporary", isDirectory: true)
        let importRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileImports", isDirectory: true)
            .appendingPathComponent(
                "\(UUID().uuidString.lowercased())--\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        let exportRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileExports", isDirectory: true)
            .appendingPathComponent(
                "\(UUID().uuidString.lowercased())--\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try Data("import plaintext".utf8).write(
            to: importRoot.appendingPathComponent("incoming")
        )
        try Data("export plaintext".utf8).write(
            to: exportRoot.appendingPathComponent("document.txt")
        )

        let vaultID = UUID()
        _ = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: TestAccess(vaultID: vaultID),
            storageRoot: root.appendingPathComponent("Store", isDirectory: true),
            temporaryRoot: temporaryRoot
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: importRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportRoot.path))
    }
}

private struct Fixture {
    let root: URL
    let sourceRoot: URL
    let storageRoot: URL
    let access: TestAccess
    let store: VaultGeneralFileStore

    init() throws {
        let vaultID = UUID()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileSupportTests-\(UUID().uuidString)",
            isDirectory: true
        )
        sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        storageRoot = root.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        access = TestAccess(vaultID: vaultID)
        store = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: access,
            storageRoot: storageRoot,
            temporaryRoot: root.appendingPathComponent("Temporary", isDirectory: true)
        )
    }

    func source(named name: String, data: Data) throws -> URL {
        let url = sourceRoot.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeManifest(_ manifest: VaultGeneralFileManifest) throws {
        let plaintext = try JSONEncoder().encode(manifest)
        let ciphertext = try access.seal(plaintext, for: .manifest)
        try ciphertext.write(
            to: storageRoot.appendingPathComponent("manifest.khm"),
            options: .atomic
        )
    }
}

private final class TestAccess: VaultGeneralFileCryptographicAccess, @unchecked Sendable {
    let vaultID: UUID
    private let key = SymmetricKey(size: .bits256)
    private let lock = NSLock()
    private var mustConsumeFileOpens = false
    private var _consumingFileOpenCount = 0
    private var revoked = false

    init(vaultID: UUID) {
        self.vaultID = vaultID
    }

    func checkAccess() throws {
        lock.lock()
        defer { lock.unlock() }
        if revoked { throw TestAccessError.revoked }
    }

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try checkAccess()
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try checkAccess()
        lock.lock()
        let rejectDirectOpen = mustConsumeFileOpens && purpose.isFilePurpose
        lock.unlock()
        if rejectDirectOpen {
            throw TestAccessError.directFileOpenForbidden
        }
        return try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    func open(
        _ ciphertext: Data,
        for purpose: VaultGeneralFileKeyPurpose,
        consuming consumer: (Data) throws -> Void
    ) throws {
        try checkAccess()
        let plaintext = try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
        if purpose.isFilePurpose {
            lock.lock()
            _consumingFileOpenCount += 1
            lock.unlock()
        }
        try consumer(plaintext)
    }

    func requireConsumingOpenForFiles() {
        lock.lock()
        mustConsumeFileOpens = true
        lock.unlock()
    }

    func revoke() {
        lock.lock()
        revoked = true
        lock.unlock()
    }

    var consumingFileOpenCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _consumingFileOpenCount
    }

    private func derivedKey(for purpose: VaultGeneralFileKeyPurpose) -> SymmetricKey {
        let domain: String
        switch purpose {
        case .manifest:
            domain = "manifest"
        case .file(let id):
            domain = "file.\(id.uuidString.lowercased())"
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(domain.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}

private enum TestAccessError: Error, Equatable {
    case directFileOpenForbidden
    case revoked
}

private enum GeneralFileManifestCommitTestError: Error {
    case committedThenThrew
}

private extension VaultGeneralFileKeyPurpose {
    var isFilePurpose: Bool {
        if case .file = self { return true }
        return false
    }
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
