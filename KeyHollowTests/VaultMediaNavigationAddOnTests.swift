import Foundation
import XCTest
@testable import KeyHollowMediaNavigationAddOn

final class VaultMediaNavigationAddOnTests: XCTestCase {
    func testPhotoAndGeneralFileWithSameUUIDHaveDistinctIdentity() throws {
        let sharedUUID = UUID()
        let photoID = VaultMediaNavigationID(source: .photo, rawValue: sharedUUID)
        let fileID = VaultMediaNavigationID(source: .generalFile, rawValue: sharedUUID)

        XCTAssertNotEqual(photoID, fileID)
        XCTAssertEqual(Set([photoID, fileID]).count, 2)

        let queue = try VaultMediaNavigationQueue(
            items: [
                item(id: photoID, title: "Photo"),
                item(id: fileID, title: "File image")
            ],
            selectedID: photoID
        )

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.currentItem.id, photoID)
        XCTAssertEqual(queue.nextItem?.id, fileID)
    }

    func testQueuePreservesVisibleOrderAndSelectedPosition() throws {
        let items = makeItems(count: 4)
        let queue = try VaultMediaNavigationQueue(
            items: items,
            selectedID: items[2].id
        )

        XCTAssertEqual(queue.items, items)
        XCTAssertEqual(queue.currentIndex, 2)
        XCTAssertEqual(queue.currentPosition, 3)
        XCTAssertEqual(queue.currentItem, items[2])
        XCTAssertEqual(queue.previousItem, items[1])
        XCTAssertEqual(queue.nextItem, items[3])
    }

    func testQueueRejectsEmptyDuplicateAndMissingSelectionInputs() {
        let id = mediaID()

        XCTAssertThrowsError(
            try VaultMediaNavigationQueue(items: [], selectedID: id)
        ) { error in
            XCTAssertEqual(
                error as? VaultMediaNavigationQueueError,
                .emptyQueue
            )
        }

        let duplicate = item(id: id, title: "Duplicate")
        XCTAssertThrowsError(
            try VaultMediaNavigationQueue(
                items: [duplicate, duplicate],
                selectedID: id
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultMediaNavigationQueueError,
                .duplicateItemID(id)
            )
        }

        let onlyItem = item(title: "Only")
        let missingID = mediaID()
        XCTAssertThrowsError(
            try VaultMediaNavigationQueue(
                items: [onlyItem],
                selectedID: missingID
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultMediaNavigationQueueError,
                .selectionNotFound(missingID)
            )
        }
    }

    func testNavigationNeverWrapsAtEitherBoundary() throws {
        let items = makeItems(count: 3)
        let first = try VaultMediaNavigationQueue(
            items: items,
            selectedID: items[0].id
        )

        XCTAssertFalse(first.canNavigatePrevious)
        XCTAssertNil(first.previousItem)
        XCTAssertNil(first.selecting(.previous))
        XCTAssertTrue(first.canNavigateNext)

        let last = try first.selecting(items[2].id)
        XCTAssertTrue(last.canNavigatePrevious)
        XCTAssertFalse(last.canNavigateNext)
        XCTAssertNil(last.nextItem)
        XCTAssertNil(last.selecting(.next))
    }

    func testDirectionalNavigationReturnsNewImmutableQueue() throws {
        let items = makeItems(count: 3)
        let original = try VaultMediaNavigationQueue(
            items: items,
            selectedID: items[1].id
        )

        let next = try XCTUnwrap(original.selecting(.next))
        let previous = try XCTUnwrap(original.selecting(.previous))

        XCTAssertEqual(original.currentItem, items[1])
        XCTAssertEqual(next.currentItem, items[2])
        XCTAssertEqual(previous.currentItem, items[0])
        XCTAssertEqual(next.items, original.items)
        XCTAssertEqual(previous.items, original.items)
    }

    func testInvalidDirectSelectionDoesNotProduceAQueue() throws {
        let items = makeItems(count: 2)
        let queue = try VaultMediaNavigationQueue(
            items: items,
            selectedID: items[0].id
        )
        let missingID = mediaID()

        XCTAssertThrowsError(try queue.selecting(missingID)) { error in
            XCTAssertEqual(
                error as? VaultMediaNavigationQueueError,
                .selectionNotFound(missingID)
            )
        }
        XCTAssertEqual(queue.currentItem, items[0])
    }

    func testRemovingSelectedItemPrefersFollowingThenPreviousItem() throws {
        let items = makeItems(count: 3)
        let middle = try VaultMediaNavigationQueue(
            items: items,
            selectedID: items[1].id
        )

        let afterMiddleRemoval = try XCTUnwrap(middle.removing(items[1].id))
        XCTAssertEqual(afterMiddleRemoval.items, [items[0], items[2]])
        XCTAssertEqual(afterMiddleRemoval.currentItem, items[2])

        let last = try VaultMediaNavigationQueue(
            items: items,
            selectedID: items[2].id
        )
        let afterLastRemoval = try XCTUnwrap(last.removing(items[2].id))
        XCTAssertEqual(afterLastRemoval.currentItem, items[1])
    }

    func testRemovingOtherOrUnknownItemPreservesSelection() throws {
        let items = makeItems(count: 3)
        let queue = try VaultMediaNavigationQueue(
            items: items,
            selectedID: items[1].id
        )

        let afterOtherRemoval = try XCTUnwrap(queue.removing(items[0].id))
        XCTAssertEqual(afterOtherRemoval.currentItem, items[1])
        XCTAssertEqual(afterOtherRemoval.currentPosition, 1)

        let afterUnknownRemoval = try XCTUnwrap(queue.removing(mediaID()))
        XCTAssertEqual(afterUnknownRemoval, queue)
    }

    func testRemovingFinalItemSignalsDismissal() throws {
        let onlyItem = item(title: "Only item")
        let queue = try VaultMediaNavigationQueue(
            items: [onlyItem],
            selectedID: onlyItem.id
        )

        XCTAssertNil(queue.removing(onlyItem.id))
    }

    func testAccessibilityDescribesTitleKindAndPosition() throws {
        let blankTitleItem = item(kind: .video, title: "  \n")
        let second = item(kind: .image, title: "Evidence")
        let queue = try VaultMediaNavigationQueue(
            items: [blankTitleItem, second],
            selectedID: second.id
        )

        XCTAssertEqual(VaultMediaNavigationKind.image.accessibilityName, "Image")
        XCTAssertEqual(VaultMediaNavigationKind.video.accessibilityName, "Video")
        XCTAssertEqual(blankTitleItem.accessibilityTitle, "Untitled")
        XCTAssertEqual(queue.accessibilityLabel, "Evidence, Image")
        XCTAssertEqual(queue.accessibilityPosition, "2 of 2")
    }

    func testImageAndVideoKindsRemainExplicitMetadata() {
        let image = item(kind: .image, title: "Still")
        let video = item(kind: .video, title: "Clip")

        XCTAssertEqual(image.kind, .image)
        XCTAssertEqual(video.kind, .video)
        XCTAssertNotEqual(image.kind, video.kind)
    }

    private func makeItems(count: Int) -> [VaultMediaNavigationItem] {
        (0..<count).map { index in
            item(
                source: index.isMultiple(of: 2) ? .photo : .generalFile,
                kind: index.isMultiple(of: 2) ? .image : .video,
                title: "Item \(index + 1)"
            )
        }
    }

    private func item(
        id: VaultMediaNavigationID? = nil,
        source: VaultMediaNavigationSource = .photo,
        kind: VaultMediaNavigationKind = .image,
        title: String
    ) -> VaultMediaNavigationItem {
        VaultMediaNavigationItem(
            id: id ?? mediaID(source: source),
            kind: kind,
            title: title
        )
    }

    private func mediaID(
        source: VaultMediaNavigationSource = .photo
    ) -> VaultMediaNavigationID {
        VaultMediaNavigationID(source: source, rawValue: UUID())
    }
}
