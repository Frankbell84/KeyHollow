import Foundation
import XCTest
@testable import KeyHollow

final class VaultGalleryDeletionBatchTests: XCTestCase {
    @MainActor
    func testDeletesPhotosBeforeFilesAndReportsCombinedCount() async {
        var events: [String] = []
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 2, fileCount: 3,
            deletePhotos: { events.append("photos"); return true },
            deleteFiles: { events.append("files"); return true }
        )
        XCTAssertEqual(events, ["photos", "files"])
        XCTAssertEqual(result?.message, "Deleted 5 items from this vault.")
    }

    @MainActor
    func testEmptyPhotoGroupDoesNotCallStoreAndSingleFileUsesSingularMessage() async {
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 0, fileCount: 1,
            deletePhotos: { XCTFail("Empty group must not access the store"); return true },
            deleteFiles: { true }
        )
        XCTAssertEqual(result?.message, "Deleted 1 item from this vault.")
    }

    @MainActor
    func testEmptyFileGroupDoesNotCallStore() async {
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 2, fileCount: 0,
            deletePhotos: { true },
            deleteFiles: { XCTFail("Empty group must not access the store"); return true }
        )
        XCTAssertEqual(result?.message, "Deleted 2 items from this vault.")
    }

    @MainActor
    func testPhotoFailureStillAttemptsFilesAndCountsWholeFailedGroup() async {
        var filesDeleted = false
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 2, fileCount: 1,
            deletePhotos: { throw TestError.unavailable },
            deleteFiles: { filesDeleted = true; return true }
        )
        XCTAssertTrue(filesDeleted)
        XCTAssertEqual(result?.message, "Deleted 1 selected items. 2 items could not be removed.")
    }

    @MainActor
    func testUnavailableFileStoreCountsAsFailureAfterPhotoSuccess() async {
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 2, fileCount: 3,
            deletePhotos: { true }, deleteFiles: { false }
        )
        XCTAssertEqual(result?.message, "Deleted 2 selected items. 3 items could not be removed.")
    }

    @MainActor
    func testUnavailablePhotoStoreAndFileFailureProduceExistingFailureMessage() async {
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 1, fileCount: 2,
            deletePhotos: { false }, deleteFiles: { throw TestError.unavailable }
        )
        XCTAssertEqual(result?.message, "The selected items could not be deleted from the vault.")
    }

    @MainActor
    func testPhotoCancellationStopsBeforeFilesAndSuppressesCompletion() async {
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 1, fileCount: 1,
            deletePhotos: { throw CancellationError() },
            deleteFiles: { XCTFail("Cancellation must stop the batch"); return true }
        )
        XCTAssertNil(result)
    }

    @MainActor
    func testFileCancellationSuppressesCompletionAfterPhotoSuccess() async {
        var photosDeleted = false
        let result = await VaultGalleryDeletionBatch.perform(
            photoCount: 1, fileCount: 1,
            deletePhotos: { photosDeleted = true; return true },
            deleteFiles: { throw CancellationError() }
        )
        XCTAssertTrue(photosDeleted)
        XCTAssertNil(result)
    }

    private enum TestError: Error { case unavailable }
}
