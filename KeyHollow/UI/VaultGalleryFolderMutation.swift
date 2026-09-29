import Foundation
import KeyHollowFolderPresentationAddOn

/// A captured folder-metadata operation. Composition supplies the existing
/// authenticated store and calls this only inside its registered session task.
enum VaultGalleryFolderMutation: Equatable, Sendable {
    case saveName(name: String, renaming: UUID?, parentID: UUID?)
    case moveFolder(id: UUID, parentID: UUID?)
    case moveItem(VaultPresentedContentReference, folderID: UUID?)
    case moveSelection(Set<VaultPresentedContentReference>, folderID: UUID?)
    case deleteFolder(id: UUID)

    @MainActor
    func perform(using presentationStore: VaultFolderPresentationStore) async throws
        -> VaultFolderPresentationManifest {
        switch self {
        case .saveName(let name, let folderID, let parentID):
            if let folderID {
                try await presentationStore.renameFolder(id: folderID, to: name)
            } else {
                _ = try await presentationStore.createFolder(named: name, in: parentID)
            }
        case .moveFolder(let id, let parentID):
            try await presentationStore.moveFolder(id: id, to: parentID)
        case .moveItem(let item, let folderID):
            try await presentationStore.move(item, to: folderID)
        case .moveSelection(let items, let folderID):
            try await presentationStore.move(items, to: folderID)
        case .deleteFolder(let id):
            try await presentationStore.deleteFolder(id: id)
        }
        return try await presentationStore.loadManifest()
    }

    func failureMessage(for error: Error) -> String {
        let storeError = error as? VaultFolderPresentationStore.StoreError
        switch self {
        case .saveName:
            switch storeError {
            case .some(.duplicateFolderName):
                return "A folder with that name already exists."
            case .some(.invalidFolderName):
                return "Use a folder name between 1 and 80 characters."
            case .some(.folderDepthLimitReached):
                return "This folder would exceed the maximum folder depth."
            default:
                return "The encrypted folder could not be saved."
            }
        case .moveFolder:
            switch storeError {
            case .some(.duplicateFolderName):
                return "That location already contains a folder with this name."
            case .some(.folderDepthLimitReached):
                return "That move would exceed the maximum folder depth."
            default:
                return "The folder could not be moved. Protected vault contents were not changed."
            }
        case .moveItem:
            return "The item could not be moved. Protected vault contents were not changed."
        case .moveSelection:
            return "The selected items could not be moved. Protected vault contents were not changed."
        case .deleteFolder:
            switch storeError {
            case .some(.duplicateFolderName):
                return "Move or rename the conflicting child folder before deleting this folder."
            case .some(.folderDepthLimitReached):
                return "The folder could not be removed without exceeding the folder depth limit."
            default:
                return "The folder could not be deleted. Protected vault contents were not changed."
            }
        }
    }
}
