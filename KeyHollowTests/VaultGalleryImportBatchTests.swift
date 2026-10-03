import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowFolderPresentationAddOn

final class VaultGalleryImportBatchTests: XCTestCase {
    @MainActor
    func testMixedMovePreservesTypedIdentityAndEncryptsBeforePlacement() async throws {
        let destination = destination(folderID: UUID())
        let sharedID = UUID()
        var batch = VaultGalleryImportBatch(mode: .move, total: 2)
        var events: [String] = []
        var placed: [VaultPresentedContentReference] = []
        for (kind, identifier) in [(VaultPresentedContentKind.photo, "photo"), (.generalFile, "video")] {
            let item = VaultPresentedContentReference(kind: kind, id: sharedID)
            let next = await batch.importing(
                sourceAssetIdentifier: identifier, destination: destination,
                encrypt: { events.append("encrypt-\(identifier)"); return item },
                move: { reference, folderID in
                    events.append("place-\(identifier)")
                    XCTAssertEqual(folderID, destination.folderID)
                    placed.append(reference)
                },
                isCurrent: { events.append("current-\(identifier)"); return true }
            )
            batch = try XCTUnwrap(next)
        }
        XCTAssertEqual(events, ["encrypt-photo", "place-photo", "current-photo",
                                "encrypt-video", "place-video", "current-video"])
        XCTAssertEqual(Set(placed), [.init(kind: .photo, id: sharedID), .init(kind: .generalFile, id: sharedID)])
        XCTAssertEqual(batch.importedCount, 2)
        XCTAssertEqual(batch.identifiersToDelete, ["photo", "video"])
        XCTAssertTrue(batch.shouldOfferOriginalDeletion)
        XCTAssertTrue(batch.allImportedItemsAreDeletable)
        XCTAssertEqual(batch.completionMessage(moveResult: .deleted), "Moved 2 items into KeyHollow.")
    }

    @MainActor
    func testCopyAtRootDoesNotPlaceOrRetainDeletionIdentifiers() async throws {
        let original = VaultGalleryImportBatch(mode: .copy, total: 1)
        let result = await original.importing(
            sourceAssetIdentifier: "keep-original", destination: destination(),
            encrypt: { .init(kind: .photo, id: UUID()) },
            move: { _, _ in XCTFail("Root import must not write folder membership") },
            isCurrent: { true }
        )
        let batch = try XCTUnwrap(result)
        XCTAssertEqual(original.importedCount, 0)
        XCTAssertEqual(original.total, 1)
        XCTAssertEqual(batch.importedCount, 1)
        XCTAssertTrue(batch.identifiersToDelete.isEmpty)
        XCTAssertFalse(batch.shouldOfferOriginalDeletion)
        XCTAssertEqual(batch.completionMessage(), "Copied 1 item into KeyHollow.")
    }

    @MainActor
    func testPlacementFailureKeepsVerifiedCopyAtRootAndPreventsOriginalDeletion() async throws {
        let result = await VaultGalleryImportBatch(mode: .move, total: 1).importing(
            sourceAssetIdentifier: "keep-original", destination: destination(folderID: UUID()),
            encrypt: { .init(kind: .generalFile, id: UUID()) },
            move: { _, _ in throw TestError.unavailable },
            isCurrent: { true }
        )
        let batch = try XCTUnwrap(result)
        XCTAssertEqual(batch.importedCount, 1)
        XCTAssertEqual(batch.failedCount, 0)
        XCTAssertEqual(batch.rootFallbackCount, 1)
        XCTAssertFalse(batch.allImportedItemsAreDeletable)
        XCTAssertTrue(batch.identifiersToDelete.isEmpty)
        XCTAssertEqual(batch.completionMessage(),
            "Encrypted 1 item into KeyHollow. Originals were kept because folder placement was incomplete."
            + VaultImportDestination.recoveryMessage(rootCount: 1))
    }

    @MainActor
    func testOneFallbackPreventsDeletingEveryOriginalInAnOtherwiseSuccessfulMove() async throws {
        let destination = destination(folderID: UUID())
        let initial = VaultGalleryImportBatch(mode: .move, total: 2)
        let first = await initial.importing(
            sourceAssetIdentifier: "placed", destination: destination,
            encrypt: { .init(kind: .photo, id: UUID()) }, move: { _, _ in }, isCurrent: { true }
        )
        let placed = try XCTUnwrap(first)
        XCTAssertTrue(placed.allImportedItemsAreDeletable)
        let second = await placed.importing(
            sourceAssetIdentifier: "root", destination: destination,
            encrypt: { .init(kind: .generalFile, id: UUID()) },
            move: { _, _ in throw TestError.unavailable }, isCurrent: { true }
        )
        let batch = try XCTUnwrap(second)
        XCTAssertEqual(batch.importedCount, 2)
        XCTAssertEqual(batch.identifiersToDelete, ["placed"])
        XCTAssertFalse(batch.allImportedItemsAreDeletable)
        XCTAssertEqual(batch.completionMessage(),
            "Encrypted 2 items into KeyHollow. Originals were kept because folder placement was incomplete."
            + VaultImportDestination.recoveryMessage(rootCount: 1))
    }

    @MainActor
    func testMissingSourceIdentifierPreventsBatchDeletionAndReportsCopy() async throws {
        let result = await VaultGalleryImportBatch(mode: .move, total: 1).importing(
            sourceAssetIdentifier: nil, destination: destination(),
            encrypt: { .init(kind: .photo, id: UUID()) }, move: { _, _ in }, isCurrent: { true }
        )
        let batch = try XCTUnwrap(result)
        XCTAssertFalse(batch.allImportedItemsAreDeletable)
        XCTAssertEqual(batch.completionMessage(),
            "Encrypted 1 item into KeyHollow. iOS did not delete every original, so KeyHollow treats this batch as copied.")
    }

    @MainActor
    func testEncryptionFailureCannotPlaceOrMakeAnOriginalEligibleForDeletion() async throws {
        let result = await VaultGalleryImportBatch(mode: .move, total: 1).importing(
            sourceAssetIdentifier: "original", destination: destination(folderID: UUID()),
            encrypt: { throw TestError.unavailable },
            move: { _, _ in XCTFail("An unverified item cannot be placed") },
            isCurrent: { XCTFail("No success may be published"); return true }
        )
        let batch = try XCTUnwrap(result)
        XCTAssertEqual(batch.failedCount, 1)
        XCTAssertEqual(batch.importedCount, 0)
        XCTAssertFalse(batch.shouldOfferOriginalDeletion)
        XCTAssertTrue(batch.identifiersToDelete.isEmpty)
    }

    @MainActor
    func testEncryptionAndPlacementCancellationReturnNoPublishableSnapshot() async {
        for cancelEncryption in [true, false] {
            let result = await VaultGalleryImportBatch(mode: .move, total: 1).importing(
                sourceAssetIdentifier: "original", destination: destination(folderID: UUID()),
                encrypt: {
                    if cancelEncryption { throw CancellationError() }
                    return .init(kind: .photo, id: UUID())
                },
                move: { _, _ in throw CancellationError() },
                isCurrent: { XCTFail("Canceled results cannot reach publication"); return true }
            )
            XCTAssertNil(result)
        }
    }

    @MainActor
    func testLateSessionChangeSuppressesCompletedSnapshot() async {
        var didPlace = false
        let result = await VaultGalleryImportBatch(mode: .move, total: 1).importing(
            sourceAssetIdentifier: "original", destination: destination(folderID: UUID()),
            encrypt: { .init(kind: .photo, id: UUID()) },
            move: { _, _ in didPlace = true },
            isCurrent: { false }
        )
        XCTAssertTrue(didPlace)
        XCTAssertNil(result)
    }

    @MainActor
    func testTaskCancellationAfterEncryptionStopsBeforePlacement() async {
        let destination = destination(folderID: UUID())
        let task = Task { @MainActor in
            await VaultGalleryImportBatch(mode: .move, total: 1).importing(
                sourceAssetIdentifier: "original", destination: destination,
                encrypt: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .init(kind: .photo, id: UUID())
                },
                move: { _, _ in XCTFail("Cancellation must precede placement") },
                isCurrent: { XCTFail("Cancellation must precede publication"); return true }
            )
        }
        let result = await task.value
        XCTAssertNil(result)
    }

    @MainActor
    func testTaskCancellationAfterPlacementDoesNotPublishSuccess() async {
        let destination = destination(folderID: UUID())
        let task = Task { @MainActor in
            await VaultGalleryImportBatch(mode: .move, total: 1).importing(
                sourceAssetIdentifier: "original", destination: destination,
                encrypt: { .init(kind: .photo, id: UUID()) },
                move: { _, _ in withUnsafeCurrentTask { $0?.cancel() } },
                isCurrent: { XCTFail("Cancellation must precede publication"); return true }
            )
        }
        let result = await task.value
        XCTAssertNil(result)
    }

    func testEmptyAndUnreadableBatchesPreserveExistingMessages() {
        var batch = VaultGalleryImportBatch(mode: .copy, total: 2)
        XCTAssertNil(batch.completionMessage())
        batch.recordFailure()
        XCTAssertEqual(batch.completionMessage(),
            "No items were imported. 1 selected item could not be read or exceeded the 100 MB video limit.")
        batch.recordFailure()
        XCTAssertEqual(batch.completionMessage(),
            "No items were imported. 2 selected items could not be read or exceeded the 100 MB video limit.")
        XCTAssertFalse(batch.shouldOfferOriginalDeletion)
    }

    @MainActor
    func testPartialCopyAndMoveMessagesKeepFailureCounts() async throws {
        for mode in [VaultImportMode.copy, .move] {
            var initial = VaultGalleryImportBatch(mode: mode, total: 3)
            initial.recordFailure()
            initial.recordFailure()
            let result = await initial.importing(
                sourceAssetIdentifier: "verified", destination: destination(),
                encrypt: { .init(kind: .photo, id: UUID()) }, move: { _, _ in }, isCurrent: { true }
            )
            let batch = try XCTUnwrap(result)
            XCTAssertEqual(batch.failedCount, 2)
            XCTAssertEqual(batch.completionMessage(moveResult: .deleted),
                "\(mode == .copy ? "Copied" : "Moved") 1 item into KeyHollow. 2 items could not be imported.")
        }
    }

    private func destination(folderID: UUID? = nil) -> VaultImportDestination {
        .init(vaultID: UUID(), securityEpoch: 7, folderID: folderID)
    }

    private enum TestError: Error { case unavailable }
}
