import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowGeneralFileSupportAddOn
@testable import KeyHollowPhotoCore
@testable import KeyHollowTransferCore
@testable import KeyHollowVaultCore

final class PortableVaultVerificationReportTests: XCTestCase {
    func testPhotoOnlyArchiveReportsAuthenticatedPhotoInventory() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let createdAt = Date(timeIntervalSince1970: 1_700_123_400)
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createPhotoArchive(
            at: roots,
            createdAt: createdAt,
            credential: credential
        )

        let report = try await EncryptedVaultTransferCoordinator().verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            keyDeriver: VerificationTestKeyDeriver()
        )

        XCTAssertEqual(report.authenticatedPhotoCount, 1)
        XCTAssertEqual(report.authenticatedFileCount, 0)
        XCTAssertEqual(report.authenticatedEntryCount, 3)
        XCTAssertEqual(report.sourceVaultCreatedAt, createdAt)
        XCTAssertEqual(report.catalogVersion, PortableArchivePayloadCatalog.currentVersion)
        XCTAssertEqual(report.legacyOversizedPhotoCount, 0)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testVerificationReportsAuthenticatedProgressThroughFinalCleanup() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createMixedArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_123_405),
            credential: credential
        )
        let recorder = ValidationProgressRecorder()

        _ = try await EncryptedVaultTransferCoordinator().verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            supplementalContent: GeneralFilePortableTransferBridge(),
            keyDeriver: VerificationTestKeyDeriver(),
            progress: { recorder.append($0) }
        )

        let updates = recorder.values
        let archiveUpdates = updates.filter { $0.phase == .authenticatingArchive }
        let fileUpdates = updates.filter { $0.phase == .authenticatingFiles }
        let photoUpdates = updates.filter { $0.phase == .authenticatingPhotos }
        let finalUpdates = updates.filter { $0.phase == .finalizing }
        XCTAssertGreaterThan(archiveUpdates.count, 1)
        XCTAssertEqual(
            archiveUpdates.last?.fractionCompleted ?? -1,
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(fileUpdates.last?.fractionCompleted, 1)
        XCTAssertEqual(photoUpdates.last?.fractionCompleted, 1)
        XCTAssertEqual(finalUpdates.last?.fractionCompleted, 1)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
    }

    func testGeneralFileOnlyArchiveReportsAuthenticatedSupplementalInventory() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let createdAt = Date(timeIntervalSince1970: 1_700_123_410)
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createGeneralFileArchive(
            at: roots,
            createdAt: createdAt,
            credential: credential,
            fileName: "verification.pdf",
            contents: Data("authenticated general file".utf8)
        )

        let report = try await EncryptedVaultTransferCoordinator().verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            supplementalContent: GeneralFilePortableTransferBridge(),
            keyDeriver: VerificationTestKeyDeriver()
        )

        XCTAssertEqual(report.authenticatedPhotoCount, 0)
        XCTAssertEqual(report.authenticatedFileCount, 1)
        XCTAssertEqual(report.authenticatedEntryCount, 3)
        XCTAssertEqual(report.sourceVaultCreatedAt, createdAt)
        XCTAssertEqual(report.catalogVersion, PortableArchivePayloadCatalog.currentVersion)
        XCTAssertEqual(report.legacyOversizedPhotoCount, 0)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testVideoImportedAsGeneralFileIsReportedAsAuthenticatedFile() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createGeneralFileArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_123_420),
            credential: credential,
            fileName: "family-trip.mp4",
            contents: Data([
                0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
                0x6d, 0x70, 0x34, 0x32, 0x00, 0x00, 0x00, 0x00,
                0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
            ])
        )

        let report = try await EncryptedVaultTransferCoordinator().verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            supplementalContent: GeneralFilePortableTransferBridge(),
            keyDeriver: VerificationTestKeyDeriver()
        )

        XCTAssertEqual(report.authenticatedPhotoCount, 0)
        XCTAssertEqual(report.authenticatedFileCount, 1)
        XCTAssertEqual(report.authenticatedEntryCount, 3)
        XCTAssertEqual(report.legacyOversizedPhotoCount, 0)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
    }

    func testMixedArchiveReturnsSanitizedReportAndDiscardsStaging() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let createdAt = Date(timeIntervalSince1970: 1_700_123_456)
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createMixedArchive(
            at: roots,
            createdAt: createdAt,
            credential: credential
        )

        let report = try await EncryptedVaultTransferCoordinator().verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            supplementalContent: GeneralFilePortableTransferBridge(),
            keyDeriver: VerificationTestKeyDeriver()
        )

        XCTAssertEqual(report.authenticatedPhotoCount, 1)
        XCTAssertEqual(report.authenticatedFileCount, 1)
        XCTAssertEqual(report.authenticatedEntryCount, 5)
        XCTAssertEqual(report.sourceVaultCreatedAt, createdAt)
        XCTAssertEqual(report.catalogVersion, PortableArchivePayloadCatalog.currentVersion)
        XCTAssertEqual(report.legacyOversizedPhotoCount, 0)
        XCTAssertEqual(report, report)
        requireSendable(report)

        let fieldNames = Set(Mirror(reflecting: report).children.compactMap(\.label))
        XCTAssertEqual(
            fieldNames,
            [
                "authenticatedPhotoCount",
                "authenticatedFileCount",
                "authenticatedEntryCount",
                "sourceVaultCreatedAt",
                "catalogVersion",
                "legacyOversizedPhotoCount"
            ]
        )
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testRepeatedVerificationReturnsSameReportAndDoesNotModifyArchive() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createMixedArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_123_430),
            credential: credential
        )
        let originalArchive = try Data(contentsOf: roots.archive)
        let coordinator = EncryptedVaultTransferCoordinator()

        let firstReport = try await coordinator.verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            supplementalContent: GeneralFilePortableTransferBridge(),
            keyDeriver: VerificationTestKeyDeriver()
        )
        XCTAssertEqual(try Data(contentsOf: roots.archive), originalArchive)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)

        let secondReport = try await coordinator.verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            supplementalContent: GeneralFilePortableTransferBridge(),
            keyDeriver: VerificationTestKeyDeriver()
        )

        XCTAssertEqual(secondReport, firstReport)
        XCTAssertEqual(try Data(contentsOf: roots.archive), originalArchive)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
    }

    func testCorruptedArchiveFailsAndDiscardsPartialStaging() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        // Force more than one authenticated container frame so a final-frame
        // failure happens only after the extractor has staged earlier bytes.
        try await createGeneralFileArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_123_440),
            credential: credential,
            fileName: "corruption-boundary.bin",
            contents: Data(
                repeating: 0x6d,
                count: PortableArchiveContainerFormat.plaintextChunkByteCount + 4_096
            )
        )
        var corrupted = try Data(contentsOf: roots.archive)
        let finalByteIndex = try XCTUnwrap(corrupted.indices.last)
        corrupted[finalByteIndex] ^= 0xff
        try corrupted.write(to: roots.archive, options: .atomic)

        do {
            _ = try await EncryptedVaultTransferCoordinator().verifyArchive(
                archiveURL: roots.archive,
                credential: credential,
                workingRootOverride: roots.working,
                supplementalContent: GeneralFilePortableTransferBridge(),
                keyDeriver: VerificationTestKeyDeriver()
            )
            XCTFail("A corrupted archive produced a verification report")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }

        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testTruncatedArchiveFailsAndDiscardsPartialStaging() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        // Force more than one authenticated container frame so truncation
        // follows successful extraction of at least the first frame.
        try await createGeneralFileArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_123_450),
            credential: credential,
            fileName: "truncation-boundary.bin",
            contents: Data(
                repeating: 0x7e,
                count: PortableArchiveContainerFormat.plaintextChunkByteCount + 4_096
            )
        )
        var truncated = try Data(contentsOf: roots.archive)
        _ = try XCTUnwrap(truncated.indices.last)
        truncated.removeLast()
        try truncated.write(to: roots.archive, options: .atomic)

        do {
            _ = try await EncryptedVaultTransferCoordinator().verifyArchive(
                archiveURL: roots.archive,
                credential: credential,
                workingRootOverride: roots.working,
                supplementalContent: GeneralFilePortableTransferBridge(),
                keyDeriver: VerificationTestKeyDeriver()
            )
            XCTFail("A truncated archive produced a verification report")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }

        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testLegacyV1PhotoArchiveReturnsAuthenticatedCompatibilityReport() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let createdAt = Date(timeIntervalSince1970: 1_700_123_460)
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createLegacyPhotoArchive(
            at: roots,
            version: PortableArchivePayloadCatalog.legacyPhotoOnlyVersion,
            createdAt: createdAt,
            credential: credential
        )

        let report = try await EncryptedVaultTransferCoordinator().verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            keyDeriver: VerificationTestKeyDeriver()
        )

        XCTAssertEqual(report.authenticatedPhotoCount, 1)
        XCTAssertEqual(report.authenticatedFileCount, 0)
        XCTAssertEqual(report.authenticatedEntryCount, 3)
        XCTAssertEqual(report.sourceVaultCreatedAt, createdAt)
        XCTAssertEqual(report.catalogVersion, PortableArchivePayloadCatalog.legacyPhotoOnlyVersion)
        XCTAssertEqual(report.legacyOversizedPhotoCount, 0)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
    }

    func testLegacyV2GeneralFileArchiveReturnsAuthenticatedCompatibilityReport() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let createdAt = Date(timeIntervalSince1970: 1_700_123_470)
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createLegacyGeneralFileArchive(
            at: roots,
            createdAt: createdAt,
            credential: credential
        )

        let report = try await EncryptedVaultTransferCoordinator().verifyArchive(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            supplementalContent: GeneralFilePortableTransferBridge(),
            keyDeriver: VerificationTestKeyDeriver()
        )

        XCTAssertEqual(report.authenticatedPhotoCount, 0)
        XCTAssertEqual(report.authenticatedFileCount, 1)
        XCTAssertEqual(report.authenticatedEntryCount, 3)
        XCTAssertEqual(report.sourceVaultCreatedAt, createdAt)
        XCTAssertEqual(
            report.catalogVersion,
            PortableArchivePayloadCatalog.legacyGeneralFileVersion
        )
        XCTAssertEqual(report.legacyOversizedPhotoCount, 0)
        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
    }

    func testWrongCredentialLeavesNoExtractedStaging() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let correctCredential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createPhotoArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            credential: correctCredential
        )

        do {
            _ = try await EncryptedVaultTransferCoordinator().verifyArchive(
                archiveURL: roots.archive,
                credential: .recoveryCode(
                    "1123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
                ),
                workingRootOverride: roots.working,
                keyDeriver: VerificationTestKeyDeriver()
            )
            XCTFail("A wrong recovery code produced a verification report")
        } catch {
            XCTAssertEqual(error as? PortableArchiveError, .authenticationFailed)
        }

        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testCleanupFailureReturnsNoReportAndFallsBackToCleanup() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createPhotoArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_000_010),
            credential: credential
        )

        do {
            _ = try await EncryptedVaultTransferCoordinator().verifyArchive(
                archiveURL: roots.archive,
                credential: credential,
                workingRootOverride: roots.working,
                keyDeriver: VerificationTestKeyDeriver(),
                discardStaging: { _ in
                    throw VerificationTestError.injectedCleanupFailure
                }
            )
            XCTFail("Cleanup failure produced a verification report")
        } catch {
            XCTAssertEqual(
                error as? EncryptedVaultTransferError,
                .archiveCleanupFailed
            )
        }

        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testCancellationAfterValidationStillSurfacesCheckedCleanupFailure() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createGeneralFileArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_000_050),
            credential: credential,
            fileName: "cancellation-check.pdf",
            contents: Data("authenticated general file".utf8)
        )

        let verification = Task {
            try await EncryptedVaultTransferCoordinator().verifyArchive(
                archiveURL: roots.archive,
                credential: credential,
                workingRootOverride: roots.working,
                supplementalContent: SelfCancellingSupplementalValidator(),
                keyDeriver: VerificationTestKeyDeriver(),
                discardStaging: { _ in
                    throw VerificationTestError.injectedCleanupFailure
                }
            )
        }
        do {
            _ = try await verification.value
            XCTFail("Cancelled verification bypassed its checked cleanup failure")
        } catch {
            XCTAssertEqual(
                error as? EncryptedVaultTransferError,
                .archiveCleanupFailed
            )
        }

        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    func testCancellationDuringValidationDiscardsExtractedStaging() async throws {
        let roots = try VerificationTestRoots.create()
        defer { roots.remove() }
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        try await createMixedArchive(
            at: roots,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            credential: credential
        )
        let pausingValidator = PausingSupplementalValidator()

        let verification = Task {
            try await EncryptedVaultTransferCoordinator().verifyArchive(
                archiveURL: roots.archive,
                credential: credential,
                workingRootOverride: roots.working,
                supplementalContent: pausingValidator,
                keyDeriver: VerificationTestKeyDeriver()
            )
        }
        do {
            try await pausingValidator.waitUntilValidationStarts()
        } catch {
            verification.cancel()
            _ = try? await verification.value
            throw error
        }
        XCTAssertEqual(try workingDirectoryContents(roots.working).count, 1)

        verification.cancel()
        do {
            _ = try await verification.value
            XCTFail("Cancelled verification returned a report")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }

        XCTAssertTrue(try workingDirectoryContents(roots.working).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.archive.path))
    }

    private func createPhotoArchive(
        at roots: VerificationTestRoots,
        createdAt: Date,
        credential: PortableArchiveCredential
    ) async throws {
        let vaultID = UUID()
        let key = SymmetricKey(data: Data(repeating: 0x4a, count: 32))
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.photoSource
        )
        _ = try await store.importPhoto(
            originalData: Data("verification original".utf8),
            thumbnailData: Data("verification thumbnail".utf8)
        )

        _ = try await EncryptedVaultTransferCoordinator().exportVault(
            vaultID: vaultID,
            createdAt: createdAt,
            access: VaultAccessCapability(vaultID: vaultID, vaultKey: key),
            credential: credential,
            destinationURL: roots.archive,
            sourceRootOverride: roots.photoSource,
            workingRootOverride: roots.working,
            keyDeriver: VerificationTestKeyDeriver()
        )
    }

    private func createGeneralFileArchive(
        at roots: VerificationTestRoots,
        createdAt: Date,
        credential: PortableArchiveCredential,
        fileName: String,
        contents: Data
    ) async throws {
        let vaultID = UUID()
        let key = SymmetricKey(data: Data(repeating: 0x4c, count: 32))
        let capability = VaultAccessCapability(vaultID: vaultID, vaultKey: key)
        _ = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.photoSource
        )

        let generalAccess = SessionGeneralFileAccess(capability: capability)
        let generalStore = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: generalAccess,
            storageRoot: roots.generalFileSource,
            temporaryRoot: roots.parent
        )
        let sourceFile = roots.parent.appendingPathComponent(fileName)
        try contents.write(to: sourceFile)
        _ = try await generalStore.importFile(at: sourceFile)

        _ = try await EncryptedVaultTransferCoordinator().exportVault(
            vaultID: vaultID,
            createdAt: createdAt,
            access: capability,
            credential: credential,
            destinationURL: roots.archive,
            sourceRootOverride: roots.photoSource,
            supplementalSourceRootOverride: roots.generalFileSource,
            supplementalContent: GeneralFilePortableTransferBridge(access: generalAccess),
            workingRootOverride: roots.working,
            keyDeriver: VerificationTestKeyDeriver()
        )
    }

    private func createLegacyPhotoArchive(
        at roots: VerificationTestRoots,
        version: Int,
        createdAt: Date,
        credential: PortableArchiveCredential
    ) async throws {
        let vaultID = UUID()
        let keyData = Data(repeating: 0x61, count: 32)
        let key = SymmetricKey(data: keyData)
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.photoSource
        )
        _ = try await store.importPhoto(
            originalData: Data("legacy verification original".utf8),
            thumbnailData: Data("legacy verification thumbnail".utf8)
        )
        let manifest = try await store.loadManifest()
        var sources = [
            LegacyVerificationEntrySource(
                storageName: "manifest.khm",
                role: .manifest,
                sourceURL: roots.photoSource.appendingPathComponent("manifest.khm")
            )
        ]
        for photo in manifest.photos {
            sources.append(
                LegacyVerificationEntrySource(
                    storageName: photo.blobName,
                    role: .original,
                    sourceURL: roots.photoSource.appendingPathComponent(photo.blobName)
                )
            )
            sources.append(
                LegacyVerificationEntrySource(
                    storageName: photo.thumbnailName,
                    role: .thumbnail,
                    sourceURL: roots.photoSource.appendingPathComponent(photo.thumbnailName)
                )
            )
        }

        try createLegacyArchiveContainer(
            at: roots.archive,
            vaultID: vaultID,
            vaultKeyData: keyData,
            createdAt: createdAt,
            credential: credential,
            catalogVersion: version,
            sources: sources
        )
    }

    private func createLegacyGeneralFileArchive(
        at roots: VerificationTestRoots,
        createdAt: Date,
        credential: PortableArchiveCredential
    ) async throws {
        let vaultID = UUID()
        let keyData = Data(repeating: 0x62, count: 32)
        let key = SymmetricKey(data: keyData)
        let capability = VaultAccessCapability(vaultID: vaultID, vaultKey: key)
        let photoStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.photoSource
        )
        _ = try await photoStore.prepareArchiveManifest()
        let generalAccess = SessionGeneralFileAccess(capability: capability)
        let generalStore = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: generalAccess,
            storageRoot: roots.generalFileSource,
            temporaryRoot: roots.parent
        )
        let sourceFile = roots.parent.appendingPathComponent("legacy-document.pdf")
        try Data("legacy authenticated general file".utf8).write(to: sourceFile)
        _ = try await generalStore.importFile(at: sourceFile)

        let supplemental = try await GeneralFilePortableTransferBridge(
            access: generalAccess
        ).authenticatedArchiveInventory(
            vaultID: vaultID,
            sourceRootOverride: roots.generalFileSource
        )
        guard let supplementalManifestURL = supplemental.manifestURL else {
            throw VerificationTestError.missingFixtureData
        }
        var sources = [
            LegacyVerificationEntrySource(
                storageName: "manifest.khm",
                role: .manifest,
                sourceURL: roots.photoSource.appendingPathComponent("manifest.khm")
            ),
            LegacyVerificationEntrySource(
                storageName: "supplemental/manifest.khm",
                role: .supplementalManifest,
                sourceURL: supplementalManifestURL
            )
        ]
        sources.append(contentsOf: supplemental.entries.map { entry in
            LegacyVerificationEntrySource(
                storageName: "supplemental/\(entry.storageName)",
                role: .supplementalBlob,
                sourceURL: entry.sourceURL
            )
        })

        try createLegacyArchiveContainer(
            at: roots.archive,
            vaultID: vaultID,
            vaultKeyData: keyData,
            createdAt: createdAt,
            credential: credential,
            catalogVersion: PortableArchivePayloadCatalog.legacyGeneralFileVersion,
            sources: sources
        )
    }

    private func createLegacyArchiveContainer(
        at archiveURL: URL,
        vaultID: UUID,
        vaultKeyData: Data,
        createdAt: Date,
        credential: PortableArchiveCredential,
        catalogVersion: Int,
        sources: [LegacyVerificationEntrySource]
    ) throws {
        let payloads = try sources.map { source in
            (source: source, bytes: try Data(contentsOf: source.sourceURL))
        }
        let catalog = PortableArchivePayloadCatalog(
            version: catalogVersion,
            entries: payloads.map { payload in
                PortableArchivePayloadEntry(
                    storageName: payload.source.storageName,
                    role: payload.source.role,
                    ciphertextByteCount: UInt64(payload.bytes.count),
                    ciphertextSHA256: Data(SHA256.hash(data: payload.bytes))
                )
            }
        )
        let encodedCatalog = try JSONEncoder().encode(catalog)
        try catalog.validate(encodedCatalogByteCount: encodedCatalog.count)
        let prepared = try EncryptedVaultArchiveHeader.prepare(
            vaultPayload: VaultPayload(
                vaultID: vaultID,
                vaultKey: vaultKeyData,
                createdAt: createdAt
            ),
            credential: credential,
            keyDeriver: VerificationTestKeyDeriver()
        )
        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: prepared
        )
        var prefix = PortableArchivePayloadFormat.magic
        prefix.appendVerificationLittleEndian(PortableArchivePayloadFormat.currentVersion)
        prefix.appendVerificationLittleEndian(UInt32(encodedCatalog.count))
        try writer.append(prefix)
        try writer.append(encodedCatalog)
        for payload in payloads {
            try writer.append(payload.bytes)
        }
        try writer.finish()
    }

    private func createMixedArchive(
        at roots: VerificationTestRoots,
        createdAt: Date,
        credential: PortableArchiveCredential
    ) async throws {
        let vaultID = UUID()
        let key = SymmetricKey(data: Data(repeating: 0x5b, count: 32))
        let capability = VaultAccessCapability(vaultID: vaultID, vaultKey: key)
        let photoStore = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.photoSource
        )
        _ = try await photoStore.importPhoto(
            originalData: Data("mixed verification original".utf8),
            thumbnailData: Data("mixed verification thumbnail".utf8)
        )

        let generalAccess = SessionGeneralFileAccess(capability: capability)
        let generalStore = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: generalAccess,
            storageRoot: roots.generalFileSource,
            temporaryRoot: roots.parent
        )
        let sourceFile = roots.parent.appendingPathComponent("verification.pdf")
        try Data("authenticated general file".utf8).write(to: sourceFile)
        _ = try await generalStore.importFile(at: sourceFile)

        _ = try await EncryptedVaultTransferCoordinator().exportVault(
            vaultID: vaultID,
            createdAt: createdAt,
            access: capability,
            credential: credential,
            destinationURL: roots.archive,
            sourceRootOverride: roots.photoSource,
            supplementalSourceRootOverride: roots.generalFileSource,
            supplementalContent: GeneralFilePortableTransferBridge(access: generalAccess),
            workingRootOverride: roots.working,
            keyDeriver: VerificationTestKeyDeriver()
        )
    }
}

private func requireSendable<T: Sendable>(_ value: T) {}

private final class ValidationProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [PortableVaultValidationProgress] = []

    var values: [PortableVaultValidationProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: PortableVaultValidationProgress) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}

private func workingDirectoryContents(_ root: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    )
}

private struct VerificationTestKeyDeriver: PortableArchiveKeyDeriving {
    func deriveWrappingKey(
        credential: PortableArchiveCredential,
        parameters: PortableArchiveKDFParameters
    ) throws -> SymmetricKey {
        try parameters.validate()
        var input = try credential.keyMaterial()
        input.append(parameters.salt)
        return SymmetricKey(data: SHA256.hash(data: input))
    }
}

private struct LegacyVerificationEntrySource {
    let storageName: String
    let role: PortableArchivePayloadEntryRole
    let sourceURL: URL
}

private struct VerificationTestRoots {
    let parent: URL
    let photoSource: URL
    let generalFileSource: URL
    let working: URL
    let archive: URL

    static func create() throws -> VerificationTestRoots {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowVerificationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        return VerificationTestRoots(
            parent: parent,
            photoSource: parent.appendingPathComponent("photo-source", isDirectory: true),
            generalFileSource: parent.appendingPathComponent(
                "general-file-source",
                isDirectory: true
            ),
            working: parent.appendingPathComponent("working", isDirectory: true),
            archive: parent.appendingPathComponent("verification.khvault")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: parent)
    }
}

private actor PausingSupplementalValidator: PortableVaultSupplementalContentProviding {
    private var validationStarted = false

    func authenticatedArchiveInventory(
        vaultID: UUID,
        sourceRootOverride: URL?
    ) async throws -> PortableVaultSupplementalArchiveInventory {
        .empty
    }

    func validateStagedContent(
        at rootURL: URL,
        sourceVaultID: UUID,
        vaultKey: SymmetricKey
    ) async throws -> PortableVaultSupplementalValidation {
        validationStarted = true
        while !Task.isCancelled {
            await Task.yield()
        }
        throw CancellationError()
    }

    func waitUntilValidationStarts() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !validationStarted {
            guard clock.now < deadline else {
                throw VerificationTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct SelfCancellingSupplementalValidator: PortableVaultSupplementalContentProviding {
    func authenticatedArchiveInventory(
        vaultID: UUID,
        sourceRootOverride: URL?
    ) async throws -> PortableVaultSupplementalArchiveInventory {
        .empty
    }

    func validateStagedContent(
        at rootURL: URL,
        sourceVaultID: UUID,
        vaultKey: SymmetricKey
    ) async throws -> PortableVaultSupplementalValidation {
        let validation = try await GeneralFilePortableTransferBridge().validateStagedContent(
            at: rootURL,
            sourceVaultID: sourceVaultID,
            vaultKey: vaultKey
        )
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        return validation
    }
}

private enum VerificationTestError: Error {
    case injectedCleanupFailure
    case missingFixtureData
    case timedOut
}

private extension Data {
    mutating func appendVerificationLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
