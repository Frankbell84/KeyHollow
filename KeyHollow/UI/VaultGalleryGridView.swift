import SwiftUI

/// Source-neutral gallery layout. The application supplies immutable display
/// values and action closures; this module never receives a vault session,
/// cryptographic capability, content store, or plaintext payload.
public struct VaultGalleryGridView<
    FolderContent: View,
    ItemContent: View
>: View {
    private let isContentLoaded: Bool
    private let isWorking: Bool
    private let emptyTitle: String
    private let emptyDescription: String
    private let emptySystemImage: String
    private let folders: [VaultGalleryFolder]
    private let items: [VaultGalleryPresentationItem]
    private let folderContent: (VaultGalleryFolder) -> FolderContent
    private let itemContent: (VaultGalleryPresentationItem) -> ItemContent

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 3),
        count: 3
    )

    public init(
        isContentLoaded: Bool,
        isWorking: Bool,
        emptyTitle: String,
        emptyDescription: String,
        emptySystemImage: String,
        folders: [VaultGalleryFolder],
        items: [VaultGalleryPresentationItem],
        @ViewBuilder folderContent: @escaping (VaultGalleryFolder) -> FolderContent,
        @ViewBuilder itemContent: @escaping (VaultGalleryPresentationItem) -> ItemContent
    ) {
        self.isContentLoaded = isContentLoaded
        self.isWorking = isWorking
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.emptySystemImage = emptySystemImage
        self.folders = folders
        self.items = items
        self.folderContent = folderContent
        self.itemContent = itemContent
    }

    public var body: some View {
        Group {
            if !isContentLoaded {
                ProgressView("Opening vault…")
            } else if folders.isEmpty, items.isEmpty, !isWorking {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(folders) { folder in
                            folderContent(folder)
                        }

                        ForEach(items) { item in
                            itemContent(item)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
                }
            }
        }
        .overlay {
            if isWorking {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
