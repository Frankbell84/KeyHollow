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

/// A source-neutral folder value used by the move destination picker. The
/// picker never receives a store, vault key, or protected-content reference;
/// it only renders the already-authorized destination tree supplied by the
/// application composition layer.
public struct VaultMoveDestinationFolder: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let parentID: UUID?
    public let name: String

    public init(id: UUID, parentID: UUID?, name: String) {
        self.id = id
        self.parentID = parentID
        self.name = name
    }
}

/// Immutable navigation and authorization data for the Files-style move
/// picker. Destination permission is intentionally separate from navigation:
/// an unavailable parent may still contain an available child destination.
public struct VaultMoveDestinationCatalog: Sendable {
    public let folders: [VaultMoveDestinationFolder]
    public let rootIsValid: Bool
    public let validFolderIDs: Set<UUID>

    public init(
        folders: [VaultMoveDestinationFolder],
        rootIsValid: Bool,
        validFolderIDs: Set<UUID>
    ) {
        self.folders = folders
        self.rootIsValid = rootIsValid
        self.validFolderIDs = validFolderIDs
    }

    /// Builds item-move permissions from the current locations of every item
    /// in the request. A destination is disabled only when every requested
    /// item is already there; mixed-location batches can still consolidate in
    /// any one of their existing locations.
    public init(
        folders: [VaultMoveDestinationFolder],
        currentFolderIDs: [UUID?]
    ) {
        self.folders = folders
        guard !currentFolderIDs.isEmpty else {
            rootIsValid = false
            validFolderIDs = []
            return
        }

        rootIsValid = currentFolderIDs.contains { $0 != nil }
        validFolderIDs = Set(folders.compactMap { folder -> UUID? in
            currentFolderIDs.allSatisfy { $0 == folder.id }
                ? nil
                : folder.id
        })
    }

    public func childFolders(of parentID: UUID?) -> [VaultMoveDestinationFolder] {
        folders
            .filter { $0.parentID == parentID }
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                if comparison == .orderedSame {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return comparison == .orderedAscending
            }
    }

    public func title(for folderID: UUID?) -> String {
        guard let folderID else { return "Vault Root" }
        return folders.first { $0.id == folderID }?.name ?? "Folder"
    }

    public func canMove(to folderID: UUID?) -> Bool {
        guard let folderID else { return rootIsValid }
        return validFolderIDs.contains(folderID)
    }

    /// A folder remains browsable when it is itself a valid destination or
    /// when one of its descendants is valid. This makes a same-location row
    /// usable as a route to deeper folders while disabling an entire forbidden
    /// subtree (for example, the folder currently being moved).
    public func canBrowse(folderID: UUID) -> Bool {
        var pending = [folderID]
        var visited = Set<UUID>()

        while let candidate = pending.popLast() {
            guard visited.insert(candidate).inserted else { continue }
            if validFolderIDs.contains(candidate) {
                return true
            }
            pending.append(contentsOf: childFolders(of: candidate).map(\.id))
        }
        return false
    }
}

public struct VaultMoveDestinationPicker: View {
    private let catalog: VaultMoveDestinationCatalog
    private let prompt: String
    private let cancel: () -> Void
    private let move: (UUID?) -> Void

    @State private var path: [UUID] = []

    public init(
        catalog: VaultMoveDestinationCatalog,
        prompt: String,
        cancel: @escaping () -> Void,
        move: @escaping (UUID?) -> Void
    ) {
        self.catalog = catalog
        self.prompt = prompt
        self.cancel = cancel
        self.move = move
    }

    public var body: some View {
        NavigationStack(path: $path) {
            destinationLevel(parentID: nil)
                .navigationDestination(for: UUID.self) { folderID in
                    destinationLevel(parentID: folderID)
                }
        }
    }

    @ViewBuilder
    private func destinationLevel(parentID: UUID?) -> some View {
        let children = catalog.childFolders(of: parentID)
        List {
            Section {
                if children.isEmpty {
                    ContentUnavailableView(
                        "No Folders Here",
                        systemImage: "folder",
                        description: Text("You can move the selection to this location when it is available.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(children) { folder in
                        NavigationLink(value: folder.id) {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                        .disabled(!catalog.canBrowse(folderID: folder.id))
                        .accessibilityHint(
                            Text(
                                catalog.canBrowse(folderID: folder.id)
                                    ? "Opens this folder"
                                    : "This folder and its contents cannot be used as a destination"
                            )
                        )
                    }
                }
            } header: {
                Text(prompt)
            }
        }
        .navigationTitle(catalog.title(for: parentID))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !catalog.canMove(to: parentID) {
                    Text("This location cannot be used as the destination.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    move(parentID)
                } label: {
                    Text("Move Here")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!catalog.canMove(to: parentID))
                .accessibilityHint("Moves the selection into the folder shown above")
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.regularMaterial)
        }
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
