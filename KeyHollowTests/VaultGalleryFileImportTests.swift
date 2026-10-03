import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowFolderPresentationAddOn
import KeyHollowGeneralFileSupportAddOn

final class VaultGalleryFileImportTests: XCTestCase {
    @MainActor
    func testVerifiedRecordIsPlacedBeforeRefreshAndCompletion() async throws {
        let destination = destination(folderID: UUID())
        let record = record()
        var events: [String] = []
        let message = await VaultGalleryFileImport.perform(
            importFiles: { batch in
                events.append("encrypted")
                try await batch.place(record, destination: destination) { item, folderID in
                    XCTAssertEqual(item, .init(kind: .generalFile, id: record.id))
                    XCTAssertEqual(folderID, destination.folderID)
                    events.append("placed")
                }
                return .init(importedCount: 1, failedCount: 0)
            },
            isCurrent: { events.append("current"); return true },
            reload: { events.append("refreshed") }
        )
        XCTAssertEqual(events, ["encrypted", "placed", "current", "refreshed"])
        XCTAssertEqual(message, "Encrypted 1 file into this vault. The originals were kept.")
    }

    @MainActor
    func testRootImportSkipsMembershipAndKeepsPartialImportCounts() async throws {
        let record = record()
        let destination = destination()
        var refreshCount = 0
        let message = await VaultGalleryFileImport.perform(
            importFiles: { batch in
                try await batch.place(record, destination: destination) { _, _ in
                    XCTFail("Root import must not change membership")
                }
                return .init(importedCount: 1, failedCount: 1)
            },
            isCurrent: { true },
            reload: { refreshCount += 1 }
        )
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(message, "Encrypted 1 file into this vault. 1 selected items were not supported or could not be read. The originals were kept.")
    }

    @MainActor
    func testPlacementFailureReportsRootFallbackWithoutChangingImportCounts() async throws {
        let first = record()
        let second = record()
        let destination = destination(folderID: UUID())
        var placed: [UUID] = []
        let message = await VaultGalleryFileImport.perform(
            importFiles: { batch in
                for record in [first, second] {
                    try await batch.place(record, destination: destination) { item, _ in
                        placed.append(item.id)
                        if item.id == first.id { throw TestError.unavailable }
                    }
                }
                return .init(importedCount: 2, failedCount: 1)
            },
            isCurrent: { true },
            reload: {}
        )
        XCTAssertEqual(placed, [first.id, second.id])
        XCTAssertEqual(message,
            "Encrypted 2 files into this vault. 1 selected items were not supported or could not be read. The originals were kept."
            + VaultImportDestination.recoveryMessage(rootCount: 1))
    }

    @MainActor
    func testFullyRejectedBatchStillRefreshesAndPreservesExistingExplanation() async {
        var refreshed = false
        let message = await VaultGalleryFileImport.perform(
            importFiles: { _ in .init(importedCount: 0, failedCount: 2) },
            isCurrent: { true },
            reload: { refreshed = true }
        )
        XCTAssertTrue(refreshed)
        XCTAssertEqual(message, "No files were imported. Choose regular files up to 100 MB; vault backups, folders, apps, and executable files are excluded.")
    }

    @MainActor
    func testPlacementCancellationStopsBatchAndSuppressesRefreshAndMessage() async {
        let record = record()
        let destination = destination(folderID: UUID())
        var continued = false
        let message = await VaultGalleryFileImport.perform(
            importFiles: { batch in
                try await batch.place(record, destination: destination) { _, _ in
                    throw CancellationError()
                }
                continued = true
                return .init(importedCount: 1, failedCount: 0)
            },
            isCurrent: { XCTFail("Canceled batch cannot publish"); return true },
            reload: { XCTFail("Canceled batch cannot refresh") }
        )
        XCTAssertFalse(continued)
        XCTAssertNil(message)
    }

    @MainActor
    func testCanceledTaskCannotPublishAnImporterThatReturnsLateSuccess() async {
        let task = Task { @MainActor in
            await VaultGalleryFileImport.perform(
                importFiles: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .init(importedCount: 1, failedCount: 0)
                },
                isCurrent: { XCTFail("Cancellation must be checked first"); return true },
                reload: { XCTFail("Canceled completion cannot refresh") }
            )
        }
        let message = await task.value
        XCTAssertNil(message)
    }

    @MainActor
    func testDifferentVaultOrSecurityEpochSuppressesLateSuccessfulCompletion() async {
        let captured = destination()
        for current in [
            VaultImportDestination(vaultID: UUID(), securityEpoch: captured.securityEpoch, folderID: nil),
            VaultImportDestination(vaultID: captured.vaultID, securityEpoch: captured.securityEpoch + 1, folderID: nil),
        ] {
            let message = await VaultGalleryFileImport.perform(
                importFiles: { _ in .init(importedCount: 1, failedCount: 0) },
                isCurrent: {
                    captured.matches(vaultID: current.vaultID, securityEpoch: current.securityEpoch)
                },
                reload: { XCTFail("A stale completion cannot refresh the current vault") }
            )
            XCTAssertNil(message)
        }
    }

    @MainActor
    func testBatchCancellationAndUnexpectedFailureKeepTheirDistinctResults() async {
        for (error, expected) in [
            (CancellationError() as Error, nil as String?),
            (TestError.unavailable as Error, "The selected files could not be imported into this vault."),
        ] {
            let message = await VaultGalleryFileImport.perform(
                importFiles: { _ in throw error },
                isCurrent: { XCTFail("Failed batch cannot publish a success"); return true },
                reload: { XCTFail("Failed batch cannot refresh") }
            )
            XCTAssertEqual(message, expected)
        }
    }

    private func destination(folderID: UUID? = nil) -> VaultImportDestination {
        .init(vaultID: UUID(), securityEpoch: 7, folderID: folderID)
    }

    private func record() -> VaultGeneralFileRecord {
        .init(id: UUID(), importedAt: Date(timeIntervalSince1970: 1),
              displayName: "test.txt", contentTypeIdentifier: "public.plain-text",
              originalByteCount: 1, blobName: "test.khf")
    }

    private enum TestError: Error { case unavailable }
}
