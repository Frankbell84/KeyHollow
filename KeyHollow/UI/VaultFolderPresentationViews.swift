import Foundation
import SwiftUI

public struct VaultGalleryFolder: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let itemCount: Int

    public init(id: UUID, name: String, itemCount: Int) {
        self.id = id
        self.name = name
        self.itemCount = itemCount
    }
}

public struct VaultFolderBreadcrumbSegment: Identifiable, Equatable, Sendable {
    public let id: String
    public let folderID: UUID?
    public let title: String

    public init(folderID: UUID?, title: String) {
        self.id = folderID?.uuidString ?? "vault-root"
        self.folderID = folderID
        self.title = title
    }
}

public enum VaultFolderPathPresentation {
    public static func destinationTitle(
        rootTitle: String = "Vault Root",
        path: [String]
    ) -> String {
        ([rootTitle] + path.map(escapedSegment)).joined(separator: " › ")
    }

    private static func escapedSegment(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "›", with: "\\›")
    }
}

public struct VaultFolderBreadcrumbView: View {
    let segments: [VaultFolderBreadcrumbSegment]
    let navigate: (UUID?) -> Void

    public init(
        segments: [VaultFolderBreadcrumbSegment],
        navigate: @escaping (UUID?) -> Void
    ) {
        self.segments = segments
        self.navigate = navigate
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(segments.indices, id: \.self) { offset in
                    let segment = segments[offset]
                    if offset > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Button(segment.title) {
                        navigate(segment.folderID)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(offset == segments.count - 1 ? .semibold : .regular))
                    .foregroundStyle(
                        offset == segments.count - 1 ? Color.primary : Color.accentColor
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .accessibilityLabel("Folder path")
    }
}

public struct VaultFolderTileView: View {
    let folder: VaultGalleryFolder
    let isEnabled: Bool
    let open: () -> Void
    let rename: () -> Void
    let move: () -> Void
    let delete: () -> Void

    private var itemDescription: String {
        "\(folder.itemCount) \(folder.itemCount == 1 ? "item" : "items")"
    }

    public init(
        folder: VaultGalleryFolder,
        isEnabled: Bool,
        open: @escaping () -> Void,
        rename: @escaping () -> Void,
        move: @escaping () -> Void,
        delete: @escaping () -> Void
    ) {
        self.folder = folder
        self.isEnabled = isEnabled
        self.open = open
        self.rename = rename
        self.move = move
        self.delete = delete
    }

    public var body: some View {
        Button(action: open) {
            VaultGalleryTileSurface(
                title: folder.name,
                detail: itemDescription,
                selectionState: nil
            ) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(folder.name)
        .accessibilityValue(itemDescription)
        .accessibilityHint("Opens this vault folder")
        .contextMenu {
            Button(action: rename) {
                Label("Rename Folder", systemImage: "pencil")
            }
            Button(action: move) {
                Label("Move Folder", systemImage: "folder")
            }
            Button(role: .destructive, action: delete) {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
}
