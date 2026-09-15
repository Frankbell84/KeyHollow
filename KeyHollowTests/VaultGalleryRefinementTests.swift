import XCTest
@testable import KeyHollow
@testable import KeyHollowGalleryUI
@testable import KeyHollowSecurePreviewAddOn

final class VaultGalleryRefinementTests: XCTestCase {
    func testVisibleThumbnailsAreNeverEvictedUnderCachePressure() {
        var policy = VaultGalleryThumbnailRetentionPolicy<Int>(maximumCount: 2)
        policy.recordAccess(1)
        policy.recordAccess(2)
        policy.markVisible(1)
        policy.recordAccess(3)

        XCTAssertEqual(
            policy.evictionCandidates(cachedKeys: [1, 2, 3]),
            [2]
        )
        XCTAssertTrue(policy.isVisible(1))
    }

    func testAllVisibleCacheMayTemporarilyExceedLimitWithoutBlankingTiles() {
        var policy = VaultGalleryThumbnailRetentionPolicy<Int>(maximumCount: 1)
        policy.markVisible(1)
        policy.markVisible(2)

        XCTAssertTrue(
            policy.evictionCandidates(cachedKeys: [1, 2]).isEmpty
        )

        policy.markHidden(1)
        XCTAssertEqual(
            policy.evictionCandidates(cachedKeys: [1, 2]),
            [1]
        )
    }

    func testThumbnailRetentionUsesLeastRecentlyUsedHiddenEntry() {
        var policy = VaultGalleryThumbnailRetentionPolicy<Int>(maximumCount: 2)
        policy.recordAccess(1)
        policy.recordAccess(2)
        policy.recordAccess(1)
        policy.recordAccess(3)

        XCTAssertEqual(
            policy.evictionCandidates(cachedKeys: [1, 2, 3]),
            [2]
        )
    }

    func testPhotoPickerProgressIsBoundedAndDescriptive() {
        var progress = SecurePhotoPickerProgressState(total: 2)
        XCTAssertEqual(progress.statusText, "Encrypting 0 of 2")
        XCTAssertEqual(progress.fractionCompleted, 0)

        progress.advance()
        XCTAssertEqual(progress.statusText, "Encrypting 1 of 2")
        XCTAssertEqual(progress.fractionCompleted, 0.5)

        progress.advance()
        progress.advance()
        XCTAssertEqual(progress.statusText, "Encrypting 2 of 2")
        XCTAssertEqual(progress.fractionCompleted, 1)
    }

    func testGeneralFileImportProgressTracksSuccessAndFailureDeterministically() {
        var progress = GeneralFileImportProgressState(total: 3)
        XCTAssertEqual(progress.statusText, "Encrypting file 1 of 3")
        XCTAssertEqual(progress.fractionCompleted, 0)

        progress.advance(succeeded: true)
        XCTAssertEqual(progress.statusText, "Encrypting file 2 of 3")
        XCTAssertEqual(progress.fractionCompleted, 1.0 / 3.0, accuracy: 0.0001)

        progress.advance(succeeded: false)
        progress.advance(succeeded: true)
        progress.advance(succeeded: true)
        XCTAssertEqual(progress.statusText, "Encrypted 3 of 3 files")
        XCTAssertEqual(progress.fractionCompleted, 1)
        XCTAssertEqual(progress.result.importedCount, 2)
        XCTAssertEqual(progress.result.failedCount, 1)
    }

    func testImageZoomPolicyClampsAndDoubleTapResets() {
        XCTAssertEqual(
            VaultSecureImageZoomPolicy.clampedScale(0.25),
            VaultSecureImageZoomPolicy.minimumScale
        )
        XCTAssertEqual(
            VaultSecureImageZoomPolicy.clampedScale(12),
            VaultSecureImageZoomPolicy.maximumScale
        )
        XCTAssertEqual(
            VaultSecureImageZoomPolicy.doubleTapDestination(from: 1),
            VaultSecureImageZoomPolicy.doubleTapScale
        )
        XCTAssertEqual(
            VaultSecureImageZoomPolicy.doubleTapDestination(from: 3),
            VaultSecureImageZoomPolicy.minimumScale
        )
    }
}
