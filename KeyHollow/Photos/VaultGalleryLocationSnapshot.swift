import Foundation
import KeyHollowCatalogSearchAddOn
import KeyHollowFolderPresentationAddOn
import KeyHollowGalleryUI
import KeyHollowGeneralFileSupportAddOn
import KeyHollowNestedFolderAddOn
import KeyHollowPhotoCore

/// Read-only application bridge for one captured gallery location. It derives
/// presentation and routing metadata from supplied records without retaining
/// a session, protected store, task, or mutation callback.
struct VaultGalleryLocationSnapshot {
    private let records: [VaultPhotoRecord]
    private let generalFileRecords: [VaultGeneralFileRecord]
    private let folderManifest: VaultFolderPresentationManifest
    private let activeFolderID: UUID?
    private let searchText: String
    private let catalogSortOrder: VaultCatalogSortOrder
    private let maximumFolderDepth: Int

    init(
        records: [VaultPhotoRecord],
        generalFileRecords: [VaultGeneralFileRecord],
        folderManifest: VaultFolderPresentationManifest,
        activeFolderID: UUID?,
        searchText: String,
        catalogSortOrder: VaultCatalogSortOrder,
        maximumFolderDepth: Int
    ) {
        self.records = records
        self.generalFileRecords = generalFileRecords
        self.folderManifest = folderManifest
        self.activeFolderID = activeFolderID
        self.searchText = searchText
        self.catalogSortOrder = catalogSortOrder
        self.maximumFolderDepth = maximumFolderDepth
    }

    var sortedFolders: [VaultFolderRecord] {
        let source = folderManifest.folders
        if catalogSortOrder == .vaultOrder {
            return source.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        let offsets = catalogSortOrder.orderedOffsets(
            for: source.enumerated().map { offset, folder in
                VaultCatalogSortDescriptor(
                    title: folder.name,
                    timestamp: folder.createdAt,
                    stableOrdinal: offset
                )
            }
        )
        return offsets.map { source[$0] }
    }

    var nestedFolderHierarchy: VaultNestedFolderHierarchy? {
        try? VaultNestedFolderHierarchy(
            folders: folderManifest.folders.enumerated().map { offset, folder in
                VaultNestedFolderDescriptor(
                    id: folder.id,
                    parentID: folder.parentID,
                    name: folder.name,
                    createdAt: folder.createdAt,
                    stableOrdinal: offset
                )
            },
            maximumDepth: maximumFolderDepth
        )
    }

    private var visibleFolders: [VaultFolderRecord] {
        sortedFolders.filter { $0.parentID == activeFolderID }
    }

    private var visibleGalleryFolders: [VaultGalleryFolder] {
        let counts = directEntryCountByFolderID
        return visibleFolders.map {
            VaultGalleryFolder(
                id: $0.id,
                name: $0.name,
                itemCount: counts[$0.id, default: 0]
            )
        }
    }

    private var directEntryCountByFolderID: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(folderManifest.folders.count)
        for membership in folderManifest.memberships {
            counts[membership.folderID, default: 0] += 1
        }
        for folder in folderManifest.folders {
            if let parentID = folder.parentID {
                counts[parentID, default: 0] += 1
            }
        }
        return counts
    }

    var activeCatalogSearchQuery: VaultCatalogSearchQuery {
        VaultCatalogSearchQuery(searchText)
    }

    var filteredVisibleGalleryFolders: [VaultGalleryFolder] {
        let query = activeCatalogSearchQuery
        guard !query.isEmpty else { return visibleGalleryFolders }
        return visibleGalleryFolders.filter { query.matches($0.name) }
    }

    var filteredVisibleGallerySnapshot: VaultGalleryContentSnapshot {
        makeVisibleGallerySnapshot().filtering(with: activeCatalogSearchQuery)
    }

    private func makeVisibleGallerySnapshot() -> VaultGalleryContentSnapshot {
        var folderIDByItem: [VaultPresentedContentReference: UUID] = [:]
        folderIDByItem.reserveCapacity(folderManifest.memberships.count)
        for membership in folderManifest.memberships {
            folderIDByItem[membership.item] = membership.folderID
        }

        var items: [VaultGalleryContentItem] = []
        items.reserveCapacity(records.count + generalFileRecords.count)
        for record in records where folderIDByItem[
            VaultPresentedContentReference(kind: .photo, id: record.id)
        ] == activeFolderID {
            items.append(.photo(record))
        }
        for record in generalFileRecords where folderIDByItem[
            VaultPresentedContentReference(kind: .generalFile, id: record.id)
        ] == activeFolderID {
            items.append(.generalFile(record))
        }

        return VaultGalleryContentSnapshot(
            items: items,
            sortOrder: catalogSortOrder
        )
    }

    var visiblePhotoRecords: [VaultPhotoRecord] {
        makeVisibleGallerySnapshot().orderedSources.compactMap {
            guard case .photo(let record) = $0 else { return nil }
            return record
        }
    }

    var visibleGeneralFileRecords: [VaultGeneralFileRecord] {
        makeVisibleGallerySnapshot().orderedSources.compactMap {
            guard case .generalFile(let record) = $0 else { return nil }
            return record
        }
    }

    var activeFolder: VaultFolderRecord? {
        guard let activeFolderID else { return nil }
        return folderManifest.folders.first { $0.id == activeFolderID }
    }

    var folderBreadcrumbSegments: [VaultFolderBreadcrumbSegment] {
        var segments = [VaultFolderBreadcrumbSegment(folderID: nil, title: "Vault")]
        guard let activeFolderID,
              let hierarchy = nestedFolderHierarchy,
              let path = try? hierarchy.breadcrumb(to: activeFolderID) else {
            return segments
        }
        segments.append(contentsOf: path.map {
            VaultFolderBreadcrumbSegment(folderID: $0.id, title: $0.name)
        })
        return segments
    }

    var moveDestinationFolders: [VaultMoveDestinationFolder] {
        folderManifest.folders.map {
            VaultMoveDestinationFolder(
                id: $0.id,
                parentID: $0.parentID,
                name: $0.name
            )
        }
    }

    var galleryTitle: String {
        activeFolder?.name ?? "Vault"
    }

    var galleryEmptyTitle: String {
        if !activeCatalogSearchQuery.isEmpty {
            return "No Results"
        }
        return activeFolderID == nil ? "Empty Vault" : "Empty Folder"
    }

    var galleryEmptyDescription: String {
        if !activeCatalogSearchQuery.isEmpty {
            return "Try a different search in this vault location."
        }
        if activeFolderID == nil {
            return "Import photos or files to store encrypted copies inside this vault."
        }
        return "Tap + to import photos, videos, or files directly into this folder."
    }

    var galleryEmptySystemImage: String {
        if !activeCatalogSearchQuery.isEmpty {
            return "magnifyingglass"
        }
        return activeFolderID == nil
            ? "photo.on.rectangle.angled"
            : "folder"
    }

    var hasSelectionMoveDestination: Bool {
        activeFolderID != nil || sortedFolders.contains { $0.id != activeFolderID }
    }

    func assignedFolderID(
        for item: VaultPresentedContentReference
    ) -> UUID? {
        folderManifest.memberships.first { $0.item == item }?.folderID
    }

    func moveCatalog(
        for items: Set<VaultPresentedContentReference>
    ) -> VaultMoveDestinationCatalog {
        return VaultMoveDestinationCatalog(
            folders: moveDestinationFolders,
            currentFolderIDs: items.map { assignedFolderID(for: $0) }
        )
    }
}
