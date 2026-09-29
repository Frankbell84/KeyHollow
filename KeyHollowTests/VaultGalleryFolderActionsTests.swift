import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowFolderPresentationAddOn

final class VaultGalleryFolderActionsTests: XCTestCase {
    func testNameMutationCapturesTrimmedDraftIdentityAndParentBeforeDismissal() {
        let parent = folder("Parent")
        let child = folder("Child", parentID: parent.id)
        let location = snapshot(folders: [parent, child])
        var actions = VaultGalleryFolderActions()
        actions.requestRename(id: child.id, location: location)
        XCTAssertTrue(actions.isEditorPresented)
        XCTAssertEqual(actions.editorTitle, "Rename Folder")
        XCTAssertEqual(actions.editorActionTitle, "Save")
        XCTAssertEqual(actions.nameDraft, "Child")

        actions.nameDraft = "  Renamed\n"
        let captured = actions.nameMutation(parentID: parent.id)
        actions.dismissEditor()
        actions.clearNameDraft()
        XCTAssertEqual(captured, .saveName(name: "Renamed", renaming: child.id, parentID: parent.id))
        XCTAssertFalse(actions.isEditorPresented)
        XCTAssertEqual(actions.nameDraft, "")
        XCTAssertNil(actions.nameMutation(parentID: parent.id))

        actions.requestNewFolder()
        XCTAssertEqual(actions.editorTitle, "New Folder")
        XCTAssertEqual(actions.editorActionTitle, "Create")
        actions.nameDraft = "  \n "
        XCTAssertNil(actions.nameMutation(parentID: parent.id))
        actions.nameDraft = "New"
        XCTAssertEqual(actions.nameMutation(parentID: parent.id),
                       .saveName(name: "New", renaming: nil, parentID: parent.id))
    }

    func testMissingFolderDoesNotRetargetAnExistingRename() {
        let existing = folder("Existing")
        let location = snapshot(folders: [existing])
        var actions = VaultGalleryFolderActions()
        actions.requestRename(id: existing.id, location: location)
        actions.requestRename(id: UUID(), location: location)
        XCTAssertEqual(actions.nameMutation(parentID: nil),
                       .saveName(name: "Existing", renaming: existing.id, parentID: nil))
        actions.requestDeletion(id: existing.id, location: location)
        XCTAssertEqual(actions.pendingDeletion, existing)
        actions.requestDeletion(id: UUID(), location: location)
        XCTAssertNil(actions.pendingDeletion)
    }

    func testMoveRequestCapturesTypedSelectionAndLocationPermissions() throws {
        let destination = folder("Destination")
        let shared = UUID()
        let photo = VaultPresentedContentReference(kind: .photo, id: shared)
        let file = VaultPresentedContentReference(kind: .generalFile, id: shared)
        let location = snapshot(folders: [destination], memberships: [
            .init(item: photo, folderID: destination.id),
        ])
        var actions = VaultGalleryFolderActions()
        actions.requestItemMove(photo, location: location)
        let single = try XCTUnwrap(actions.moveRequest)
        XCTAssertTrue(single.catalog.rootIsValid)
        XCTAssertTrue(single.catalog.validFolderIDs.isEmpty)

        actions.requestItemMove(file, location: location)
        let otherSource = try XCTUnwrap(actions.moveRequest)
        XCTAssertFalse(otherSource.catalog.rootIsValid)
        XCTAssertEqual(otherSource.catalog.validFolderIDs, [destination.id])
        XCTAssertNotEqual(single.id, otherSource.id)

        var selection: Set<VaultPresentedContentReference> = [photo, file]
        actions.requestSelectionMove(selection, location: location)
        let batch = try XCTUnwrap(actions.moveRequest)
        selection.removeAll()
        guard case .selection(let captured) = batch.target else {
            return XCTFail("Expected a typed selection request")
        }
        XCTAssertEqual(captured, [photo, file])
        XCTAssertEqual(batch.prompt, "Choose a destination for 2 selected items.")
        XCTAssertTrue(batch.catalog.rootIsValid)
        XCTAssertEqual(batch.catalog.validFolderIDs, [destination.id])
        actions.dismissMove()
        XCTAssertNil(actions.moveRequest)
        XCTAssertEqual(batch.catalog.folders.map(\.id), [destination.id])
    }

    func testEmptyOrImmovableRequestsDoNotPresentADestinationPicker() {
        var actions = VaultGalleryFolderActions()
        let empty = snapshot(folders: [])
        actions.requestSelectionMove([], location: empty)
        actions.requestItemMove(.init(kind: .photo, id: UUID()), location: empty)
        XCTAssertNil(actions.moveRequest)

        let onlyFolder = folder("Only")
        XCTAssertEqual(actions.requestFolderMove(id: onlyFolder.id,
                       location: snapshot(folders: [onlyFolder])),
                       "There is no other valid location for this folder.")
        XCTAssertNil(actions.moveRequest)
        XCTAssertNil(actions.requestFolderMove(id: UUID(), location: empty))
    }

    func testFolderMoveExcludesCurrentParentSelfAndDescendants() throws {
        let parent = folder("Parent")
        let child = folder("Child", parentID: parent.id)
        let other = folder("Other")
        var actions = VaultGalleryFolderActions()
        XCTAssertNil(actions.requestFolderMove(id: parent.id,
            location: snapshot(folders: [parent, child, other])))
        let request = try XCTUnwrap(actions.moveRequest)
        guard case .folder(let captured) = request.target else {
            return XCTFail("Expected a folder move request")
        }
        XCTAssertEqual(captured, parent)
        XCTAssertFalse(request.catalog.rootIsValid)
        XCTAssertEqual(request.catalog.validFolderIDs, [other.id])
        XCTAssertEqual(request.prompt, "Choose a new parent for “Parent”.")
    }

    func testInvalidHierarchyReportsExistingFailureWithoutPublishingRequest() {
        let id = UUID()
        let cyclic = VaultFolderRecord(id: id, name: "Cycle", createdAt: Date(), parentID: id)
        var actions = VaultGalleryFolderActions()
        XCTAssertEqual(actions.requestFolderMove(id: id, location: snapshot(folders: [cyclic])),
                       "Folder destinations are temporarily unavailable. Protected vault contents were not changed.")
        XCTAssertNil(actions.moveRequest)
    }

    func testVaultResetClearsEveryTransientFolderInteraction() {
        let record = folder("Private name")
        let location = snapshot(folders: [record])
        var actions = VaultGalleryFolderActions()
        actions.requestRename(id: record.id, location: location)
        actions.requestDeletion(id: record.id, location: location)
        actions.requestItemMove(.init(kind: .photo, id: UUID()), location: location)
        actions.reset()

        XCTAssertFalse(actions.isEditorPresented)
        XCTAssertEqual(actions.nameDraft, "")
        XCTAssertEqual(actions.editorTitle, "New Folder")
        XCTAssertNil(actions.pendingDeletion)
        XCTAssertNil(actions.moveRequest)
        XCTAssertNil(actions.nameMutation(parentID: nil))
    }

    private func folder(_ name: String, parentID: UUID? = nil) -> VaultFolderRecord {
        .init(id: UUID(), name: name, createdAt: Date(timeIntervalSince1970: 1), parentID: parentID)
    }

    private func snapshot(
        folders: [VaultFolderRecord], memberships: [VaultFolderMembership] = []
    ) -> VaultGalleryLocationSnapshot {
        .init(records: [], generalFileRecords: [], folderManifest: .init(
            version: VaultFolderPresentationManifest.currentVersion,
            folders: folders, memberships: memberships, thumbnails: []
        ), activeFolderID: nil, searchText: "", catalogSortOrder: .vaultOrder, maximumFolderDepth: 8)
    }
}
