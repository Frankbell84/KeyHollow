import Foundation
import KeyHollowFolderPresentationAddOn
import KeyHollowGalleryUI
import KeyHollowNestedFolderAddOn

enum VaultGalleryMoveTarget {
    case item(VaultPresentedContentReference)
    case selection(Set<VaultPresentedContentReference>)
    case folder(VaultFolderRecord)
}

struct VaultGalleryMoveRequest: Identifiable {
    let id = UUID()
    let target: VaultGalleryMoveTarget
    let prompt: String
    let catalog: VaultMoveDestinationCatalog
}

/// Transient folder dialogs and immutable move requests. This value has no
/// session, task or protected-store authority; composition performs mutations.
struct VaultGalleryFolderActions {
    // Only the text draft is directly editable by the presentation binding.
    var nameDraft = ""
    private var folderBeingRenamed: VaultFolderRecord?
    private(set) var isEditorPresented = false
    private(set) var pendingDeletion: VaultFolderRecord?
    private(set) var moveRequest: VaultGalleryMoveRequest?

    init() {}

    var editorTitle: String {
        folderBeingRenamed == nil ? "New Folder" : "Rename Folder"
    }

    var editorActionTitle: String {
        folderBeingRenamed == nil ? "Create" : "Save"
    }

    var normalizedName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func nameMutation(parentID: UUID?) -> VaultGalleryFolderMutation? {
        let name = normalizedName
        guard !name.isEmpty else { return nil }
        return .saveName(name: name, renaming: folderBeingRenamed?.id, parentID: parentID)
    }

    mutating func requestNewFolder() {
        folderBeingRenamed = nil
        nameDraft = ""
        isEditorPresented = true
    }

    mutating func requestRename(id: UUID, location: VaultGalleryLocationSnapshot) {
        guard let folder = location.folder(id: id) else { return }
        folderBeingRenamed = folder
        nameDraft = folder.name
        isEditorPresented = true
    }

    mutating func clearNameDraft() {
        folderBeingRenamed = nil
        nameDraft = ""
    }

    mutating func dismissEditor() {
        isEditorPresented = false
    }

    mutating func requestDeletion(id: UUID, location: VaultGalleryLocationSnapshot) {
        pendingDeletion = location.folder(id: id)
    }

    mutating func dismissDeletion() {
        pendingDeletion = nil
    }

    mutating func requestItemMove(
        _ item: VaultPresentedContentReference,
        location: VaultGalleryLocationSnapshot
    ) {
        let catalog = location.moveCatalog(for: Set([item]))
        guard catalog.rootIsValid || !catalog.validFolderIDs.isEmpty else { return }
        moveRequest = VaultGalleryMoveRequest(
            target: .item(item),
            prompt: "Choose a destination for this item.",
            catalog: catalog
        )
    }

    mutating func requestSelectionMove(
        _ items: Set<VaultPresentedContentReference>,
        location: VaultGalleryLocationSnapshot
    ) {
        guard !items.isEmpty else { return }
        let catalog = location.moveCatalog(for: items)
        guard catalog.rootIsValid || !catalog.validFolderIDs.isEmpty else { return }
        let noun = items.count == 1 ? "item" : "items"
        moveRequest = VaultGalleryMoveRequest(
            target: .selection(items),
            prompt: "Choose a destination for \(items.count) selected \(noun).",
            catalog: catalog
        )
    }

    mutating func requestFolderMove(
        id: UUID,
        location: VaultGalleryLocationSnapshot
    ) -> String? {
        guard let folder = location.folder(id: id) else { return nil }
        guard let hierarchy = location.nestedFolderHierarchy,
              let destinations = try? hierarchy.validParentDestinations(for: id) else {
            return "Folder destinations are temporarily unavailable. Protected vault contents were not changed."
        }
        let validFolderIDs = Set(destinations.compactMap { $0 })
        let rootIsValid = destinations.contains { $0 == nil }
        guard rootIsValid || !validFolderIDs.isEmpty else {
            return "There is no other valid location for this folder."
        }

        moveRequest = VaultGalleryMoveRequest(
            target: .folder(folder),
            prompt: "Choose a new parent for “\(folder.name)”.",
            catalog: VaultMoveDestinationCatalog(
                folders: location.moveDestinationFolders,
                rootIsValid: rootIsValid,
                validFolderIDs: validFolderIDs
            )
        )
        return nil
    }

    mutating func dismissMove() {
        moveRequest = nil
    }

    mutating func reset() {
        folderBeingRenamed = nil
        pendingDeletion = nil
        moveRequest = nil
        nameDraft = ""
        isEditorPresented = false
    }
}
