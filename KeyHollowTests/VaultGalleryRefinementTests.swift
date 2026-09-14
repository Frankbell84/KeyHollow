import XCTest
@testable import KeyHollow
@testable import KeyHollowGalleryUI

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
}
