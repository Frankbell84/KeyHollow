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
            destination: destination,
            importFiles: { didImport, progress in
                events.append("encrypted")
                try await didImport(record)
                progress(GeneralFileImportProgressState(total: 1))
                return .init(importedCount: 1, failedCount: 0)
            },
            move: { item, folderID in
                XCTAssertEqual(item, .init(kind: .generalFile, id: record.id))
                XCTAssertEqual(folderID, destination.folderID)
                events.append("placed")
            },
            progressDidChange: { _ in events.append("progress") },
            isCurrent: { events.append("current"); return true },
            reload: { events.append("refreshed") }
        )
        XCTAssertEqual(events, ["encrypted", "placed", "progress", "current", "refreshed"])
        XCTAssertEqual(message, "Encrypted 1 file into this vault. The originals were kept.")
    }

    @MainActor
    func testRootImportDoesNotWriteMembershipAndForwardsProgressUnchanged() async throws {
        let record = record()
        var expected = [GeneralFileImportProgressState(total: 2)]
        var completed = expected[0]
        completed.advance(succeeded: true)
        expected.append(completed)
        completed.advance(succeeded: false)
        expected.append(completed)
        var updates: [GeneralFileImportProgressState] = []
        var refreshCount = 0
        let message = await VaultGalleryFileImport.perform(
            destination: destination(),
            importFiles: { didImport, progress in
                progress(expected[0])
                try await didImport(record)
                progress(expected[1])
                progress(expected[2])
                return completed.result
            },
            move: { _, _ in XCTFail("Root import must not change membership") },
            progressDidChange: { updates.append($0) },
            isCurrent: { true },
            reload: { refreshCount += 1 }
        )
        XCTAssertEqual(updates, expected)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(message, "Encrypted 1 file into this vault. 1 selected items were not supported or could not be read. The originals were kept.")
    }

    @MainActor
    func testPlacementFailureReportsRootFallbackWithoutChangingImportCounts() async throws {
        let first = record()
        let second = record()
        var placed: [UUID] = []
        let message = await VaultGalleryFileImport.perform(
            destination: destination(folderID: UUID()),
            importFiles: { didImport, _ in
                try await didImport(first)
                try await didImport(second)
                return .init(importedCount: 2, failedCount: 1)
            },
            move: { item, _ in
                placed.append(item.id)
                if item.id == first.id { throw TestError.unavailable }
            },
            progressDidChange: { _ in },
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
            destination: destination(),
            importFiles: { _, _ in .init(importedCount: 0, failedCount: 2) },
            move: { _, _ in XCTFail("Rejected files cannot be placed") },
            progressDidChange: { _ in },
            isCurrent: { true },
            reload: { refreshed = true }
        )
        XCTAssertTrue(refreshed)
        XCTAssertEqual(message, "No files were imported. Choose regular files up to 100 MB; vault backups, folders, apps, and executable files are excluded.")
    }

    @MainActor
    func testPlacementCancellationStopsBatchAndSuppressesRefreshAndMessage() async {
        let record = record()
        var continued = false
        let message = await VaultGalleryFileImport.perform(
            destination: destination(folderID: UUID()),
            importFiles: { didImport, _ in
                try await didImport(record)
                continued = true
                return .init(importedCount: 1, failedCount: 0)
            },
            move: { _, _ in throw CancellationError() },
            progressDidChange: { _ in XCTFail("Canceled placement cannot advance progress") },
            isCurrent: { XCTFail("Canceled batch cannot publish"); return true },
            reload: { XCTFail("Canceled batch cannot refresh") }
        )
        XCTAssertFalse(continued)
        XCTAssertNil(message)
    }

    @MainActor
    func testCanceledTaskCannotPublishAnImporterThatReturnsLateSuccess() async {
        let destination = destination()
        let task = Task { @MainActor in
            await VaultGalleryFileImport.perform(
                destination: destination,
                importFiles: { _, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .init(importedCount: 1, failedCount: 0)
                },
                move: { _, _ in XCTFail("No record was published") },
                progressDidChange: { _ in },
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
                destination: captured,
                importFiles: { _, _ in .init(importedCount: 1, failedCount: 0) },
                move: { _, _ in XCTFail("No record was published") },
                progressDidChange: { _ in },
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
                destination: destination(),
                importFiles: { _, _ in throw error },
                move: { _, _ in XCTFail("Failed batch cannot place a record") },
                progressDidChange: { _ in },
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
