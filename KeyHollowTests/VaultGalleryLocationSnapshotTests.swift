import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowCatalogSearchAddOn
import KeyHollowFolderPresentationAddOn
import KeyHollowGalleryUI
import KeyHollowGeneralFileSupportAddOn
import KeyHollowPhotoCore

final class VaultGalleryLocationSnapshotTests: XCTestCase {
    func testLocationMembershipKeepsSourceKindsAndDescendantsSeparate() {
        let fixture = Fixture()
        let root = fixture.snapshot()
        let parent = fixture.snapshot(folderID: fixture.parent.id)
        let child = fixture.snapshot(folderID: fixture.child.id)

        // The root file and the parent photo deliberately share their UUID.
        XCTAssertEqual(Set(root.filteredVisibleGallerySnapshot.selectableItems), [
            .photo(fixture.rootPhoto.id), .generalFile(fixture.rootFile.id),
        ])
        XCTAssertEqual(Set(parent.filteredVisibleGallerySnapshot.selectableItems), [
            .photo(fixture.parentPhoto.id), .generalFile(fixture.parentFile.id),
        ])
        XCTAssertEqual(child.filteredVisibleGallerySnapshot.selectableItems, [
            .photo(fixture.childPhoto.id),
        ])
        XCTAssertTrue(fixture.snapshot(folderID: fixture.sibling.id)
            .filteredVisibleGallerySnapshot.selectableItems.isEmpty)

        let rootFolders = Dictionary(uniqueKeysWithValues:
            root.filteredVisibleGalleryFolders.map { ($0.id, $0.itemCount) })
        XCTAssertEqual(rootFolders[fixture.parent.id], 3) // Two items and one child.
        XCTAssertEqual(rootFolders[fixture.sibling.id], 0)
        XCTAssertEqual(parent.filteredVisibleGalleryFolders.map(\.id), [fixture.child.id])
        XCTAssertEqual(parent.filteredVisibleGalleryFolders.first?.itemCount, 1)
    }

    func testSearchAndOrderingKeepSelectionAndMediaInsideTheCurrentLocation() throws {
        var fixture = Fixture()
        let hidden = Fixture.photo(name: "Other.jpg")
        fixture.photos.append(hidden)
        fixture.manifest.memberships.append(.init(
            item: .init(kind: .photo, id: hidden.id), folderID: fixture.parent.id
        ))
        let location = fixture.snapshot(
            folderID: fixture.parent.id, search: "clip", order: .nameAscending
        )
        let content = location.filteredVisibleGallerySnapshot
        XCTAssertEqual(content.selectableItems, [
            .generalFile(fixture.parentFile.id), .photo(fixture.parentPhoto.id),
        ])
        let queue = try content.mediaNavigationQueue(startingAt:
            VaultGalleryContentItem.photo(fixture.parentPhoto).mediaNavigationID)
        XCTAssertEqual(queue.items.map(\.id), content.mediaNavigationItems.map(\.id))
        XCTAssertEqual(queue.items.count, 2)
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertTrue(location.filteredVisibleGalleryFolders.isEmpty)
        // Bulk record lookup remains independent of the query. Selection is
        // reconciled by the composition owner against the filtered IDs.
        XCTAssertEqual(Set(location.visiblePhotoRecords.map(\.id)), [
            fixture.parentPhoto.id, hidden.id,
        ])
        XCTAssertEqual(location.visibleGeneralFileRecords.map(\.id), [fixture.parentFile.id])
        XCTAssertEqual(location.galleryEmptyTitle, "No Results")
        XCTAssertEqual(location.galleryEmptySystemImage, "magnifyingglass")
    }

    func testFolderSortAndSearchPreserveDirectLocationScope() {
        let fixture = Fixture()
        XCTAssertEqual(fixture.snapshot().filteredVisibleGalleryFolders.map(\.id), [
            fixture.sibling.id, fixture.parent.id,
        ])
        XCTAssertEqual(fixture.snapshot(order: .oldestFirst)
            .filteredVisibleGalleryFolders.map(\.id), [fixture.parent.id, fixture.sibling.id])
        XCTAssertEqual(fixture.snapshot(search: "zulu").filteredVisibleGalleryFolders.map(\.id), [
            fixture.parent.id,
        ])
        XCTAssertTrue(fixture.snapshot(search: fixture.child.name)
            .filteredVisibleGalleryFolders.isEmpty)
    }

    func testBreadcrumbsAndMoveHierarchyRemainBounded() throws {
        let fixture = Fixture()
        let child = fixture.snapshot(folderID: fixture.child.id)
        XCTAssertEqual(child.folderBreadcrumbSegments.map(\.folderID), [
            nil, fixture.parent.id, fixture.child.id,
        ])
        XCTAssertEqual(child.folderBreadcrumbSegments.map(\.title), ["Vault", "Zulu", "Child"])
        XCTAssertEqual(child.activeFolder?.parentID, fixture.parent.id)
        XCTAssertEqual(child.galleryTitle, "Child")
        let hierarchy = try XCTUnwrap(child.nestedFolderHierarchy)
        let destinations = try hierarchy.validParentDestinations(for: fixture.parent.id)
        XCTAssertFalse(destinations.contains(fixture.parent.id))
        XCTAssertFalse(destinations.contains(fixture.child.id))
        XCTAssertTrue(destinations.contains(fixture.sibling.id))

        let missing = fixture.snapshot(folderID: UUID())
        XCTAssertNil(missing.activeFolder)
        XCTAssertEqual(missing.folderBreadcrumbSegments.map(\.title), ["Vault"])
        let tooDeep = fixture.snapshot(folderID: fixture.child.id, maximumDepth: 1)
        XCTAssertNil(tooDeep.nestedFolderHierarchy)
        XCTAssertEqual(tooDeep.folderBreadcrumbSegments.map(\.title), ["Vault"])

        var cyclic = fixture
        cyclic.manifest.folders[0].parentID = fixture.child.id
        XCTAssertNil(cyclic.snapshot().nestedFolderHierarchy)
    }

    func testMoveCatalogUsesTypedLocationsWithoutChangingMembership() {
        let fixture = Fixture()
        let location = fixture.snapshot()
        let photo = VaultPresentedContentReference(kind: .photo, id: fixture.parentPhoto.id)
        let file = VaultPresentedContentReference(kind: .generalFile, id: fixture.rootFile.id)
        XCTAssertEqual(location.assignedFolderID(for: photo), fixture.parent.id)
        XCTAssertNil(location.assignedFolderID(for: file))

        let fromFolder = location.moveCatalog(for: [photo])
        XCTAssertTrue(fromFolder.rootIsValid)
        XCTAssertFalse(fromFolder.canMove(to: fixture.parent.id))
        XCTAssertTrue(fromFolder.canMove(to: fixture.sibling.id))
        let fromRoot = location.moveCatalog(for: [file])
        XCTAssertFalse(fromRoot.rootIsValid)
        XCTAssertTrue(fromRoot.canMove(to: fixture.parent.id))
        let mixed = location.moveCatalog(for: [photo, file])
        XCTAssertTrue(mixed.rootIsValid)
        XCTAssertTrue(mixed.canMove(to: fixture.parent.id))
        let empty = location.moveCatalog(for: [])
        XCTAssertFalse(empty.rootIsValid)
        XCTAssertTrue(empty.validFolderIDs.isEmpty)
        XCTAssertEqual(location.assignedFolderID(for: photo), fixture.parent.id)
    }

    func testSnapshotRetainsItsCapturedValuesWhenCallerChangesMetadata() {
        var fixture = Fixture()
        let captured = fixture.snapshot(folderID: fixture.parent.id)
        fixture.manifest.folders[0].name = "Renamed"
        fixture.manifest.memberships = []
        fixture.photos = []

        XCTAssertEqual(captured.galleryTitle, "Zulu")
        XCTAssertEqual(captured.visiblePhotoRecords.map(\.id), [fixture.parentPhoto.id])
        XCTAssertEqual(captured.visibleGeneralFileRecords.map(\.id), [fixture.parentFile.id])
        let refreshed = fixture.snapshot(folderID: fixture.parent.id)
        XCTAssertEqual(refreshed.galleryTitle, "Renamed")
        XCTAssertTrue(refreshed.filteredVisibleGallerySnapshot.selectableItems.isEmpty)
    }

    func testEmptyLocationLabelsAndMoveAvailabilityStayUnchanged() {
        var fixture = Fixture()
        let folder = fixture.snapshot(folderID: fixture.sibling.id)
        XCTAssertEqual(folder.galleryEmptyTitle, "Empty Folder")
        XCTAssertEqual(folder.galleryEmptySystemImage, "folder")
        XCTAssertTrue(folder.hasSelectionMoveDestination)

        fixture.manifest = .empty
        fixture.photos = []
        fixture.files = []
        let root = fixture.snapshot()
        XCTAssertEqual(root.galleryTitle, "Vault")
        XCTAssertEqual(root.galleryEmptyTitle, "Empty Vault")
        XCTAssertEqual(root.galleryEmptySystemImage, "photo.on.rectangle.angled")
        XCTAssertFalse(root.hasSelectionMoveDestination)
        XCTAssertEqual(fixture.snapshot(search: "missing").galleryEmptyDescription,
                       "Try a different search in this vault location.")
    }

    private struct Fixture {
        let parent: VaultFolderRecord
        let child: VaultFolderRecord
        let sibling: VaultFolderRecord
        let rootPhoto: VaultPhotoRecord
        let parentPhoto: VaultPhotoRecord
        let childPhoto: VaultPhotoRecord
        let rootFile: VaultGeneralFileRecord
        let parentFile: VaultGeneralFileRecord
        var photos: [VaultPhotoRecord]
        var files: [VaultGeneralFileRecord]
        var manifest: VaultFolderPresentationManifest

        init() {
            parent = .init(id: UUID(), name: "Zulu", createdAt: Date(timeIntervalSince1970: 10))
            child = .init(id: UUID(), name: "Child", createdAt: Date(timeIntervalSince1970: 30),
                          parentID: parent.id)
            sibling = .init(id: UUID(), name: "Alpha", createdAt: Date(timeIntervalSince1970: 20))
            rootPhoto = Self.photo(name: "Clip Root.jpg")
            parentPhoto = Self.photo(name: "Clip Zeta.jpg")
            childPhoto = Self.photo(name: "Clip Child.jpg")
            rootFile = Self.file(id: parentPhoto.id, name: "Clip Root.mp4")
            parentFile = Self.file(id: UUID(), name: "Clip Alpha.mp4")
            photos = [rootPhoto, parentPhoto, childPhoto]
            files = [rootFile, parentFile]
            manifest = .init(version: VaultFolderPresentationManifest.currentVersion,
                             folders: [parent, child, sibling], memberships: [
                .init(item: .init(kind: .photo, id: parentPhoto.id), folderID: parent.id),
                .init(item: .init(kind: .generalFile, id: parentFile.id), folderID: parent.id),
                .init(item: .init(kind: .photo, id: childPhoto.id), folderID: child.id),
            ], thumbnails: [])
        }

        func snapshot(
            folderID: UUID? = nil, search: String = "",
            order: VaultCatalogSortOrder = .vaultOrder, maximumDepth: Int = 8
        ) -> VaultGalleryLocationSnapshot {
            .init(records: photos, generalFileRecords: files, folderManifest: manifest,
                  activeFolderID: folderID, searchText: search, catalogSortOrder: order,
                  maximumFolderDepth: maximumDepth)
        }

        static func photo(name: String) -> VaultPhotoRecord {
            .init(id: UUID(), importedAt: Date(timeIntervalSince1970: 100),
                  blobName: "photo.khp", thumbnailName: "photo.kht",
                  displayName: name, originalByteCount: 100)
        }

        private static func file(id: UUID, name: String) -> VaultGeneralFileRecord {
            .init(id: id, importedAt: Date(timeIntervalSince1970: 100), displayName: name,
                  contentTypeIdentifier: "public.mpeg-4", originalByteCount: 100,
                  blobName: "file.khg")
        }
    }
}
