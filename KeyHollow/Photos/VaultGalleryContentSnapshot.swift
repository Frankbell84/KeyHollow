import Foundation
import KeyHollowCatalogSearchAddOn
import KeyHollowEncryptedVideoAddOn
import KeyHollowGalleryUI
import KeyHollowGeneralFileSupportAddOn
import KeyHollowMediaNavigationAddOn
import KeyHollowPhotoCore
import KeyHollowSecurePreviewAddOn

/// App-owned routing record. Storage models stop here and are translated into
/// immutable, source-neutral values before crossing into `KeyHollowGalleryUI`.
enum VaultGalleryContentItem: Identifiable, Equatable, Sendable {
    case photo(VaultPhotoRecord)
    case generalFile(VaultGeneralFileRecord)

    var id: VaultGallerySelection.Item {
        switch self {
        case .photo(let record):
            .photo(record.id)
        case .generalFile(let record):
            .generalFile(record.id)
        }
    }

    var sourceID: UUID {
        switch self {
        case .photo(let record):
            record.id
        case .generalFile(let record):
            record.id
        }
    }

    var mediaNavigationID: VaultMediaNavigationID {
        switch self {
        case .photo(let record):
            VaultMediaNavigationID(source: .photo, rawValue: record.id)
        case .generalFile(let record):
            VaultMediaNavigationID(source: .generalFile, rawValue: record.id)
        }
    }

    var presentationItem: VaultGalleryPresentationItem {
        switch self {
        case .photo(let record):
            return VaultGalleryPresentationItem(
                id: id,
                importedAt: record.importedAt,
                displayName: record.displayName,
                originalByteCount: record.originalByteCount,
                isImage: true,
                fallbackTitle: "Photo",
                iconName: "photo",
                accessibilityKind: "Encrypted photo"
            )
        case .generalFile(let record):
            let image = Self.isImage(record)
            return VaultGalleryPresentationItem(
                id: id,
                importedAt: record.importedAt,
                displayName: record.displayName,
                originalByteCount: record.originalByteCount,
                isImage: image,
                fallbackTitle: "File",
                iconName: GeneralFilePresentation.iconName(
                    for: record.contentTypeIdentifier
                ),
                accessibilityKind: "Encrypted file"
            )
        }
    }

    static func sourceNeutralOrder(
        _ first: Self,
        _ second: Self
    ) -> Bool {
        VaultGalleryPresentationItem.sourceNeutralOrder(
            first.presentationItem,
            second.presentationItem
        )
    }

    var openRoute: VaultGalleryOpenRoute {
        switch self {
        case .photo:
            return .imagePreview
        case .generalFile(let record):
            let securePreviewKind = VaultSecurePreviewPolicy.kind(
                for: VaultSecurePreviewDescriptor(
                    displayName: record.displayName,
                    contentTypeIdentifier: record.contentTypeIdentifier,
                    originalByteCount: record.originalByteCount
                )
            )
            if securePreviewKind == .image {
                return .imagePreview
            }

            let encryptedVideoKind = VaultEncryptedVideoPolicy.kind(
                for: VaultEncryptedVideoDescriptor(
                    displayName: record.displayName,
                    contentTypeIdentifier: record.contentTypeIdentifier,
                    originalByteCount: record.originalByteCount
                )
            )
            return encryptedVideoKind == .video ? .videoPlayback : .fileManagement
        }
    }

    var mediaNavigationItem: VaultMediaNavigationItem? {
        let kind: VaultMediaNavigationKind
        switch openRoute {
        case .imagePreview:
            kind = .image
        case .videoPlayback:
            kind = .video
        case .fileManagement:
            return nil
        }

        return VaultMediaNavigationItem(
            id: mediaNavigationID,
            kind: kind,
            title: presentationItem.title
        )
    }

    private static func isImage(_ record: VaultGeneralFileRecord) -> Bool {
        VaultSecurePreviewPolicy.kind(
            for: VaultSecurePreviewDescriptor(
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                originalByteCount: record.originalByteCount
            )
        ) == .image
    }
}

enum VaultGalleryOpenRoute: Equatable {
    case imagePreview
    case videoPlayback
    case fileManagement
}

/// One immutable bridge between protected source records and the compiled,
/// source-neutral gallery UI. Presentation values are built and sorted once;
/// a tile recovers its source record with a constant-time lookup instead of
/// rebuilding the complete mixed gallery during every cell evaluation.
struct VaultGalleryContentSnapshot {
    let orderedSources: [VaultGalleryContentItem]
    let presentations: [VaultGalleryPresentationItem]
    let sourceByID: [VaultGallerySelection.Item: VaultGalleryContentItem]
    private let sortOrder: VaultCatalogSortOrder

    init(
        items: [VaultGalleryContentItem],
        sortOrder: VaultCatalogSortOrder = .vaultOrder
    ) {
        let entries = items.map { source in
            (source: source, presentation: source.presentationItem)
        }.sorted {
            VaultGalleryPresentationItem.sourceNeutralOrder(
                $0.presentation,
                $1.presentation
            )
        }
        let orderedOffsets = sortOrder.orderedOffsets(
            for: entries.enumerated().map { offset, entry in
                VaultCatalogSortDescriptor(
                    title: entry.presentation.title,
                    timestamp: entry.presentation.importedAt,
                    stableOrdinal: offset
                )
            }
        )
        let orderedEntries = orderedOffsets.map { entries[$0] }

        self.sortOrder = sortOrder
        orderedSources = orderedEntries.map(\.source)
        presentations = orderedEntries.map(\.presentation)
        sourceByID = Dictionary(
            uniqueKeysWithValues: orderedEntries.map {
                ($0.presentation.id, $0.source)
            }
        )
    }

    var selectableItems: [VaultGallerySelection.Item] {
        presentations.map(\.id)
    }

    var mediaNavigationItems: [VaultMediaNavigationItem] {
        orderedSources.compactMap(\.mediaNavigationItem)
    }

    var mediaNavigationSourceByID: [VaultMediaNavigationID: VaultGalleryContentItem] {
        Dictionary(
            uniqueKeysWithValues: orderedSources.compactMap { source in
                guard let item = source.mediaNavigationItem else { return nil }
                return (item.id, source)
            }
        )
    }

    func mediaNavigationQueue(
        startingAt id: VaultMediaNavigationID
    ) throws -> VaultMediaNavigationQueue {
        try VaultMediaNavigationQueue(
            items: mediaNavigationItems,
            selectedID: id
        )
    }

    func filtering(
        with query: VaultCatalogSearchQuery
    ) -> VaultGalleryContentSnapshot {
        guard !query.isEmpty else { return self }
        return VaultGalleryContentSnapshot(
            items: orderedSources.filter {
                query.matches($0.presentationItem.title)
            },
            sortOrder: sortOrder
        )
    }
}
