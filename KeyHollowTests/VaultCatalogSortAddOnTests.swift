import Foundation
import XCTest
import KeyHollowCatalogSearchAddOn

final class VaultCatalogSortAddOnTests: XCTestCase {
    private let baseDate = Date(timeIntervalSinceReferenceDate: 1_000)

    func testVaultOrderPreservesApplicationSuppliedBaselineOrder() {
        let descriptors = [
            descriptor("Older", age: 20, ordinal: 0),
            descriptor("Newest", age: 0, ordinal: 1),
            descriptor("Middle", age: 10, ordinal: 2),
        ]

        XCTAssertEqual(
            VaultCatalogSortOrder.vaultOrder.orderedOffsets(for: descriptors),
            [0, 1, 2]
        )
    }

    func testDateOrdersAreExactOppositesForDistinctDates() {
        let descriptors = [
            descriptor("First", age: 30, ordinal: 0),
            descriptor("Second", age: 10, ordinal: 1),
            descriptor("Third", age: 20, ordinal: 2),
        ]

        XCTAssertEqual(
            VaultCatalogSortOrder.newestFirst.orderedOffsets(for: descriptors),
            [1, 2, 0]
        )
        XCTAssertEqual(
            VaultCatalogSortOrder.oldestFirst.orderedOffsets(for: descriptors),
            [0, 2, 1]
        )
    }

    func testNameOrderIsCaseDiacriticWidthAndNumberAware() {
        let descriptors = [
            descriptor("Item 10", age: 0, ordinal: 0),
            descriptor("ＩＴＥＭ 2", age: 1, ordinal: 1),
            descriptor("Résumé", age: 2, ordinal: 2),
            descriptor("resume", age: 3, ordinal: 3),
        ]

        XCTAssertEqual(
            VaultCatalogSortOrder.nameAscending.orderedOffsets(for: descriptors),
            [1, 0, 2, 3]
        )
        XCTAssertEqual(
            VaultCatalogSortOrder.nameDescending.orderedOffsets(for: descriptors),
            [2, 3, 0, 1]
        )
    }

    func testEqualMetadataUsesStableOrdinalThenInputOffset() {
        let sharedDate = baseDate
        let descriptors = [
            VaultCatalogSortDescriptor(
                title: "Same",
                timestamp: sharedDate,
                stableOrdinal: 2
            ),
            VaultCatalogSortDescriptor(
                title: "same",
                timestamp: sharedDate,
                stableOrdinal: 1
            ),
            VaultCatalogSortDescriptor(
                title: "SAME",
                timestamp: sharedDate,
                stableOrdinal: 1
            ),
        ]

        XCTAssertEqual(
            VaultCatalogSortOrder.nameAscending.orderedOffsets(for: descriptors),
            [1, 2, 0]
        )
    }

    func testDescriptorBoundsDisplayTextWork() {
        let descriptor = VaultCatalogSortDescriptor(
            title: String(repeating: "a", count: 2_000),
            timestamp: baseDate,
            stableOrdinal: 0
        )

        XCTAssertEqual(
            descriptor.title.count,
            VaultCatalogSortDescriptor.maximumTitleCharacterCount
        )
    }

    private func descriptor(
        _ title: String,
        age: TimeInterval,
        ordinal: Int
    ) -> VaultCatalogSortDescriptor {
        VaultCatalogSortDescriptor(
            title: title,
            timestamp: baseDate.addingTimeInterval(-age),
            stableOrdinal: ordinal
        )
    }
}
