import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowPhotoCore

final class VaultGalleryPhotoSaveBatchTests: XCTestCase {
    @MainActor
    func testSavesSequentiallyInSelectionOrderAndKeepsVaultCopiesMessage() async {
        let photos = [record(), record()]
        var events: [String] = []
        let result = await VaultGalleryPhotoSaveBatch.perform(photos) { photo in
            events.append("start-\(photo.id)")
            await Task.yield()
            events.append("finish-\(photo.id)")
            return .saved
        }
        XCTAssertEqual(events, photos.flatMap { ["start-\($0.id)", "finish-\($0.id)"] })
        XCTAssertEqual(result?.message, "Saved 2 photos to Photos. The encrypted vault copies were kept.")
        XCTAssertEqual(result?.clearSelection, true)
    }

    @MainActor
    func testSingleSuccessUsesSingularMessage() async {
        let result = await VaultGalleryPhotoSaveBatch.perform([record()]) { _ in .saved }
        XCTAssertEqual(result?.message, "Saved 1 photo to Photos. The encrypted vault copies were kept.")
        XCTAssertEqual(result?.clearSelection, true)
    }

    @MainActor
    func testLoadFailureAndSaveFailureDoNotStopLaterRecords() async {
        let photos = [record(), record(), record()]
        var visited: [UUID] = []
        let result = await VaultGalleryPhotoSaveBatch.perform(photos) { photo in
            visited.append(photo.id)
            if photo.id == photos[0].id { throw TestError.unavailable }
            return photo.id == photos[1].id ? .failed : .saved
        }
        XCTAssertEqual(visited, photos.map(\.id))
        XCTAssertEqual(result?.message, "Saved 1 photo to Photos. 2 selected photos could not be decrypted or saved.")
        XCTAssertEqual(result?.clearSelection, true)
    }

    @MainActor
    func testPermissionDenialStopsBatchAndKeepsSelectionAfterPartialSuccess() async {
        let photos = [record(), record(), record()]
        var visited: [UUID] = []
        let result = await VaultGalleryPhotoSaveBatch.perform(photos) { photo in
            visited.append(photo.id)
            return photo.id == photos[0].id ? .saved : .permissionDenied
        }
        XCTAssertEqual(visited, Array(photos.prefix(2)).map(\.id))
        XCTAssertEqual(result?.message, "Allow KeyHollow to add photos in iPhone Settings, then try again.")
        XCTAssertEqual(result?.clearSelection, false)
    }

    @MainActor
    func testAllFailedKeepsSelectionAndFailureExplanation() async {
        let result = await VaultGalleryPhotoSaveBatch.perform([record(), record()]) { _ in .failed }
        XCTAssertEqual(result?.message, "The selected photos could not be authenticated, decrypted, or saved.")
        XCTAssertEqual(result?.clearSelection, false)
    }

    @MainActor
    func testThrownCancellationWithoutCancelledTaskRemainsAnItemFailure() async {
        let photos = [record(), record()]
        let result = await VaultGalleryPhotoSaveBatch.perform(photos) { photo in
            if photo.id == photos[0].id { throw CancellationError() }
            return .saved
        }
        XCTAssertEqual(result?.message, "Saved 1 photo to Photos. 1 selected photos could not be decrypted or saved.")
        XCTAssertEqual(result?.clearSelection, true)
    }

    @MainActor
    func testCancelledTaskStopsBeforeNextRecordAndSuppressesCompletion() async {
        let photos = [record(), record()]
        var visited: [UUID] = []
        let task = Task { @MainActor in
            await VaultGalleryPhotoSaveBatch.perform(photos) { photo in
                visited.append(photo.id)
                withUnsafeCurrentTask { $0?.cancel() }
                return .saved
            }
        }
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(visited, [photos[0].id])
    }

    @MainActor
    func testLateSuccessAfterCancellationSuppressesFinalCompletion() async {
        let task = Task { @MainActor in
            await VaultGalleryPhotoSaveBatch.perform([record()]) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return .saved
            }
        }
        let result = await task.value
        XCTAssertNil(result)
    }

    private func record() -> VaultPhotoRecord {
        VaultPhotoRecord(
            id: UUID(), importedAt: Date(timeIntervalSinceReferenceDate: 0),
            blobName: "photo.khp", thumbnailName: "photo.kht",
            displayName: "Photo.heic", originalByteCount: 1
        )
    }

    private enum TestError: Error { case unavailable }
}
