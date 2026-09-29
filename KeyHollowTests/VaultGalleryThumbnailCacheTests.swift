import UIKit
import XCTest
@testable import KeyHollow
import KeyHollowGalleryUI

final class VaultGalleryThumbnailCacheTests: XCTestCase {
    func testEqualUUIDsKeepPhotoAndFileImagesDistinct() {
        let id = UUID()
        let photo = UIImage()
        let file = UIImage()
        var cache = VaultGalleryThumbnailCache()
        cache.insert(photo, for: .photo(id))
        cache.insert(file, for: .generalFile(id))

        XCTAssertTrue(cache[.photo(id)] === photo)
        XCTAssertTrue(cache[.generalFile(id)] === file)
        cache.remove(.generalFile(id))
        XCTAssertNil(cache[.generalFile(id)])
        XCTAssertTrue(cache[.photo(id)] === photo)
    }

    func testBothSourcesShareOneBudgetAndEvictTheOldestHiddenImage() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let image = UIImage()
        var cache = VaultGalleryThumbnailCache(maximumCount: 2)
        cache.insert(image, for: .photo(first))
        cache.insert(image, for: .generalFile(second))
        cache.insert(image, for: .photo(third))

        XCTAssertNil(cache[.photo(first)])
        XCTAssertNotNil(cache[.generalFile(second)])
        XCTAssertNotNil(cache[.photo(third)])
    }

    func testVisibleImagesSurvivePressureUntilTheyLeaveTheViewport() {
        let first = UUID()
        let second = UUID()
        let image = UIImage()
        var cache = VaultGalleryThumbnailCache(maximumCount: 1)
        // Tile appearance can precede asynchronous image delivery.
        cache.markVisible(.photo(first))
        cache.markVisible(.generalFile(second))
        cache.insert(image, for: .photo(first))
        cache.insert(image, for: .generalFile(second))
        XCTAssertNotNil(cache[.photo(first)])
        XCTAssertNotNil(cache[.generalFile(second)])

        cache.markHidden(.photo(first))
        XCTAssertNil(cache[.photo(first)])
        XCTAssertNotNil(cache[.generalFile(second)])
    }

    func testReappearingTileBecomesTheMostRecentlyUsedHiddenImage() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let image = UIImage()
        var cache = VaultGalleryThumbnailCache(maximumCount: 2)
        cache.insert(image, for: .photo(first))
        cache.insert(image, for: .generalFile(second))
        cache.markVisible(.photo(first))
        cache.markHidden(.photo(first))
        cache.insert(image, for: .generalFile(third))

        XCTAssertNotNil(cache[.photo(first)])
        XCTAssertNil(cache[.generalFile(second)])
        XCTAssertNotNil(cache[.generalFile(third)])
    }

    func testCatalogRefreshPrunesOnlyThatSourcesImages() {
        let shared = UUID()
        let retained = UUID()
        let image = UIImage()
        var cache = VaultGalleryThumbnailCache()
        cache.insert(image, for: .photo(shared))
        cache.insert(image, for: .photo(retained))
        cache.insert(image, for: .generalFile(shared))
        cache.retainPhotos(withIDs: [retained])
        XCTAssertNil(cache[.photo(shared)])
        XCTAssertNotNil(cache[.photo(retained)])
        XCTAssertNotNil(cache[.generalFile(shared)])

        cache.retainGeneralFiles(withIDs: [])
        XCTAssertNil(cache[.generalFile(shared)])
        XCTAssertNotNil(cache[.photo(retained)])
    }

    func testReconciledMembershipForgetsStaleVisibility() {
        let removed = UUID()
        let next = UUID()
        let image = UIImage()
        var cache = VaultGalleryThumbnailCache(maximumCount: 1)
        cache.markVisible(.photo(removed))
        cache.insert(image, for: .photo(removed))
        cache.retainPhotos(withIDs: [])
        cache.retainKnownItems([])

        cache.insert(image, for: .photo(removed))
        cache.insert(image, for: .generalFile(next))
        XCTAssertNil(cache[.photo(removed)])
        XCTAssertNotNil(cache[.generalFile(next)])
    }

    func testVaultResetClearsBothSourcesAndVisibilityAndPreservesBudget() {
        let reused = UUID()
        let next = UUID()
        let image = UIImage()
        var cache = VaultGalleryThumbnailCache(maximumCount: 1)
        cache.markVisible(.photo(reused))
        cache.markVisible(.generalFile(reused))
        cache.insert(image, for: .photo(reused))
        cache.insert(image, for: .generalFile(reused))
        cache.removeAll()
        XCTAssertNil(cache[.photo(reused)])
        XCTAssertNil(cache[.generalFile(reused)])

        cache.insert(image, for: .photo(reused))
        cache.insert(image, for: .generalFile(next))
        XCTAssertNil(cache[.photo(reused)])
        XCTAssertNotNil(cache[.generalFile(next)])
    }

    func testCopiesHaveIndependentMembershipAndRetentionState() {
        let first = UUID()
        let second = UUID()
        let image = UIImage()
        var original = VaultGalleryThumbnailCache(maximumCount: 1)
        original.insert(image, for: .photo(first))
        var copy = original
        copy.insert(image, for: .generalFile(second))
        XCTAssertNil(copy[.photo(first)])
        XCTAssertNotNil(original[.photo(first)])
        XCTAssertNil(original[.generalFile(second)])
    }

    func testVaultResetReleasesTheCachesImageReferences() {
        var cache = VaultGalleryThumbnailCache()
        weak var photo: UIImage?
        weak var file: UIImage?
        autoreleasepool {
            let photoImage = UIImage()
            let fileImage = UIImage()
            photo = photoImage
            file = fileImage
            cache.insert(photoImage, for: .photo(UUID()))
            cache.insert(fileImage, for: .generalFile(UUID()))
        }
        XCTAssertNotNil(photo)
        XCTAssertNotNil(file)
        cache.removeAll()
        XCTAssertNil(photo)
        XCTAssertNil(file)
    }

    func testDefaultBudgetRemains96AcrossBothSources() {
        let first = UUID()
        let image = UIImage()
        var cache = VaultGalleryThumbnailCache()
        cache.insert(image, for: .photo(first))
        for _ in 0..<95 {
            cache.insert(image, for: .generalFile(UUID()))
        }
        XCTAssertNotNil(cache[.photo(first)])
        cache.insert(image, for: .generalFile(UUID()))
        XCTAssertNil(cache[.photo(first)])
    }
}
