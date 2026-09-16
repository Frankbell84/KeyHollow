import Foundation
import XCTest
import KeyHollowNestedFolderAddOn

final class VaultNestedFolderAddOnTests: XCTestCase {
    func testValidHierarchyProvidesDeterministicChildrenAndBreadcrumbs() throws {
        let root = descriptor("Root", ordinal: 0)
        let second = descriptor("Second", parentID: root.id, ordinal: 2)
        let first = descriptor("First", parentID: root.id, ordinal: 1)
        let leaf = descriptor("Leaf", parentID: first.id, ordinal: 3)
        let hierarchy = try VaultNestedFolderHierarchy(
            folders: [second, leaf, root, first]
        )

        XCTAssertEqual(hierarchy.children(of: root.id).map(\.name), ["First", "Second"])
        XCTAssertEqual(try hierarchy.breadcrumb(to: leaf.id).map(\.name), ["Root", "First", "Leaf"])
    }

    func testRejectsCycleSelfParentOrphanAndDepthOverflow() throws {
        let firstID = UUID()
        let secondID = UUID()

        XCTAssertThrowsError(try VaultNestedFolderHierarchy(folders: [
            descriptor("First", id: firstID, parentID: secondID, ordinal: 0),
            descriptor("Second", id: secondID, parentID: firstID, ordinal: 1),
        ])) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .cycle)
        }
        XCTAssertThrowsError(try VaultNestedFolderHierarchy(folders: [
            descriptor("Self", id: firstID, parentID: firstID, ordinal: 0),
        ])) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .selfParent)
        }
        XCTAssertThrowsError(try VaultNestedFolderHierarchy(folders: [
            descriptor("Orphan", parentID: UUID(), ordinal: 0),
        ])) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .invalidParent)
        }

        var chain: [VaultNestedFolderDescriptor] = []
        var parentID: UUID?
        for ordinal in 0...VaultNestedFolderHierarchy.maximumDepth {
            let folder = descriptor("Level \(ordinal)", parentID: parentID, ordinal: ordinal)
            chain.append(folder)
            parentID = folder.id
        }
        XCTAssertThrowsError(try VaultNestedFolderHierarchy(folders: chain)) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .invalidDepth)
        }
    }

    func testDuplicateNamesAreRejectedOnlyAmongSiblings() throws {
        let firstParent = descriptor("First Parent", ordinal: 0)
        let secondParent = descriptor("Second Parent", ordinal: 1)
        let sharedNameA = descriptor("Résumé", parentID: firstParent.id, ordinal: 2)
        let sharedNameB = descriptor("RESUME", parentID: secondParent.id, ordinal: 3)

        XCTAssertNoThrow(try VaultNestedFolderHierarchy(
            folders: [firstParent, secondParent, sharedNameA, sharedNameB]
        ))

        let duplicateSibling = descriptor(
            "RE\u{0301}SUME\u{0301}",
            parentID: firstParent.id,
            ordinal: 4
        )
        XCTAssertThrowsError(try VaultNestedFolderHierarchy(
            folders: [firstParent, secondParent, sharedNameA, duplicateSibling]
        )) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .duplicateSiblingName)
        }
    }

    func testRejectsOverlongAndControlCharacterNamesWithoutTruncating() {
        let overlongName = String(
            repeating: "A",
            count: VaultNestedFolderDescriptor.maximumNameCharacterCount + 1
        )
        XCTAssertThrowsError(try VaultNestedFolderHierarchy(folders: [
            descriptor(overlongName, ordinal: 0),
        ])) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .invalidName)
        }

        XCTAssertThrowsError(try VaultNestedFolderHierarchy(folders: [
            descriptor("Receipts\u{0000}", ordinal: 0),
        ])) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .invalidName)
        }
    }

    func testMovingFolderRejectsDescendantAndDepthOverflow() throws {
        let root = descriptor("Root", ordinal: 0)
        let child = descriptor("Child", parentID: root.id, ordinal: 1)
        let grandchild = descriptor("Grandchild", parentID: child.id, ordinal: 2)
        let hierarchy = try VaultNestedFolderHierarchy(folders: [root, child, grandchild])

        XCTAssertThrowsError(try hierarchy.movingFolder(id: root.id, to: grandchild.id)) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .cycle)
        }

        var deepChain: [VaultNestedFolderDescriptor] = []
        var parentID: UUID?
        for ordinal in 0..<(VaultNestedFolderHierarchy.maximumDepth - 1) {
            let folder = descriptor("Depth \(ordinal)", parentID: parentID, ordinal: ordinal)
            deepChain.append(folder)
            parentID = folder.id
        }
        let movableParent = descriptor("Movable", ordinal: 20)
        let movableChild = descriptor("Movable Child", parentID: movableParent.id, ordinal: 21)
        let deepHierarchy = try VaultNestedFolderHierarchy(
            folders: deepChain + [movableParent, movableChild]
        )
        XCTAssertThrowsError(
            try deepHierarchy.movingFolder(id: movableParent.id, to: parentID)
        ) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .invalidDepth)
        }
    }

    func testCustomMaximumDepthIsPreservedForMovesAndDestinations() throws {
        let destinationRoot = descriptor("Destination", ordinal: 0)
        let destinationChild = descriptor(
            "Destination Child",
            parentID: destinationRoot.id,
            ordinal: 1
        )
        let movable = descriptor("Movable", ordinal: 2)
        let movableChild = descriptor(
            "Movable Child",
            parentID: movable.id,
            ordinal: 3
        )
        let hierarchy = try VaultNestedFolderHierarchy(
            folders: [destinationRoot, destinationChild, movable, movableChild],
            maximumDepth: 3
        )

        let destinations = try hierarchy.validParentDestinations(for: movable.id)
        XCTAssertTrue(destinations.contains { $0 == destinationRoot.id })
        XCTAssertFalse(destinations.contains { $0 == destinationChild.id })

        XCTAssertNoThrow(
            try hierarchy.movingFolder(id: movable.id, to: destinationRoot.id)
        )
        XCTAssertThrowsError(
            try hierarchy.movingFolder(id: movable.id, to: destinationChild.id)
        ) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .invalidDepth)
        }
    }

    func testSiblingNameCollisionIsExcludedFromMoveDestinations() throws {
        let sourceParent = descriptor("Source", ordinal: 0)
        let destinationParent = descriptor("Destination", ordinal: 1)
        let movable = descriptor(
            "Receipts",
            parentID: sourceParent.id,
            ordinal: 2
        )
        let existingSibling = descriptor(
            "RECEIPTS",
            parentID: destinationParent.id,
            ordinal: 3
        )
        let hierarchy = try VaultNestedFolderHierarchy(
            folders: [sourceParent, destinationParent, movable, existingSibling]
        )

        let destinations = try hierarchy.validParentDestinations(for: movable.id)
        XCTAssertFalse(destinations.contains { $0 == destinationParent.id })
        XCTAssertThrowsError(
            try hierarchy.movingFolder(id: movable.id, to: destinationParent.id)
        ) { error in
            XCTAssertEqual(error as? VaultNestedFolderPolicyError, .duplicateSiblingName)
        }
    }

    func testValidDestinationsExcludeCurrentParentSelfAndDescendants() throws {
        let root = descriptor("Root", ordinal: 0)
        let child = descriptor("Child", parentID: root.id, ordinal: 1)
        let sibling = descriptor("Sibling", parentID: root.id, ordinal: 2)
        let leaf = descriptor("Leaf", parentID: child.id, ordinal: 3)
        let hierarchy = try VaultNestedFolderHierarchy(
            folders: [root, child, sibling, leaf]
        )

        let destinations = try hierarchy.validParentDestinations(for: child.id)
        XCTAssertTrue(destinations.contains { $0 == nil })
        XCTAssertTrue(destinations.contains { $0 == sibling.id })
        XCTAssertFalse(destinations.contains { $0 == root.id })
        XCTAssertFalse(destinations.contains { $0 == child.id })
        XCTAssertFalse(destinations.contains { $0 == leaf.id })
    }

    private func descriptor(
        _ name: String,
        id: UUID = UUID(),
        parentID: UUID? = nil,
        ordinal: Int
    ) -> VaultNestedFolderDescriptor {
        VaultNestedFolderDescriptor(
            id: id,
            parentID: parentID,
            name: name,
            createdAt: Date(timeIntervalSinceReferenceDate: TimeInterval(ordinal)),
            stableOrdinal: ordinal
        )
    }
}
