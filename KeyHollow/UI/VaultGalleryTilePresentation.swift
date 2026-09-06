import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import KeyHollowGeneralFileSupportAddOn
import KeyHollowPhotoCore

enum VaultGalleryTileMetrics {
    static let mediaAspectRatio: CGFloat = 1
    static let footerHeight: CGFloat = 56
    static let selectionInset: CGFloat = 8
}

enum VaultGalleryPresentationMetadata {
    static func title(
        displayName: String?,
        isImage: Bool,
        fallback: String
    ) -> String {
        guard let displayName else { return fallback }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard isImage else { return trimmed }

        let title = (trimmed as NSString).deletingPathExtension
        return title.isEmpty ? fallback : title
    }

    static func detail(byteCount: UInt64?, importedAt: Date) -> String {
        if let byteCount {
            return ByteCountFormatter.string(
                fromByteCount: Int64(clamping: byteCount),
                countStyle: .file
            )
        }
        return DateFormatter.localizedString(
            from: importedAt,
            dateStyle: .medium,
            timeStyle: .none
        )
    }

    static func isImage(
        contentTypeIdentifier: String?,
        displayName: String
    ) -> Bool {
        if let contentTypeIdentifier,
           UTType(contentTypeIdentifier)?.conforms(to: .image) == true {
            return true
        }
        let pathExtension = (displayName as NSString).pathExtension
        return !pathExtension.isEmpty
            && UTType(filenameExtension: pathExtension)?.conforms(to: .image) == true
    }
}

enum VaultGalleryPresentationItem: Identifiable, Equatable {
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

    var importedAt: Date {
        switch self {
        case .photo(let record):
            record.importedAt
        case .generalFile(let record):
            record.importedAt
        }
    }

    var title: String {
        switch self {
        case .photo(let record):
            VaultGalleryPresentationMetadata.title(
                displayName: record.displayName,
                isImage: true,
                fallback: "Photo"
            )
        case .generalFile(let record):
            VaultGalleryPresentationMetadata.title(
                displayName: record.displayName,
                isImage: isImage,
                fallback: "File"
            )
        }
    }

    var detail: String {
        switch self {
        case .photo(let record):
            VaultGalleryPresentationMetadata.detail(
                byteCount: record.originalByteCount,
                importedAt: record.importedAt
            )
        case .generalFile(let record):
            VaultGalleryPresentationMetadata.detail(
                byteCount: record.originalByteCount,
                importedAt: record.importedAt
            )
        }
    }

    var iconName: String {
        switch self {
        case .photo:
            "photo"
        case .generalFile(let record):
            GeneralFilePresentation.iconName(for: record.contentTypeIdentifier)
        }
    }

    var isImage: Bool {
        switch self {
        case .photo:
            true
        case .generalFile(let record):
            VaultGalleryPresentationMetadata.isImage(
                contentTypeIdentifier: record.contentTypeIdentifier,
                displayName: record.displayName
            )
        }
    }

    var accessibilityKind: String {
        switch self {
        case .photo:
            "Encrypted photo"
        case .generalFile:
            "Encrypted file"
        }
    }

    static func sourceNeutralOrder(
        _ first: VaultGalleryPresentationItem,
        _ second: VaultGalleryPresentationItem
    ) -> Bool {
        if first.importedAt != second.importedAt {
            return first.importedAt > second.importedAt
        }
        let titleOrder = first.title.localizedCaseInsensitiveCompare(second.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return String(describing: first.id) < String(describing: second.id)
    }
}

enum VaultGalleryThumbnailRenderer {
    static func jpegData(from image: UIImage, maximumDimension: CGFloat = 512) -> Data? {
        let sourceSize = orientedPixelSize(for: image)
        let longestEdge = max(sourceSize.width, sourceSize.height)
        guard longestEdge > 0, maximumDimension > 0 else { return nil }

        let scale = min(1, maximumDimension / longestEdge)
        let targetSize = CGSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return thumbnail.jpegData(compressionQuality: 0.82)
    }

    static func orientedPixelSize(for image: UIImage) -> CGSize {
        let rawSize: CGSize
        if let cgImage = image.cgImage {
            rawSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            rawSize = CGSize(
                width: image.size.width * image.scale,
                height: image.size.height * image.scale
            )
        }

        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: rawSize.height, height: rawSize.width)
        default:
            return rawSize
        }
    }
}

struct VaultGalleryTileSurface<Media: View>: View {
    let title: String
    let detail: String
    let selectionState: Bool?
    private let media: Media

    init(
        title: String,
        detail: String,
        selectionState: Bool?,
        @ViewBuilder media: () -> Media
    ) {
        self.title = title
        self.detail = detail
        self.selectionState = selectionState
        self.media = media()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Rectangle()
                        .fill(.secondary.opacity(0.12))

                    media
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(VaultGalleryTileMetrics.mediaAspectRatio, contentMode: .fit)
                .clipped()

                if let isSelected = selectionState {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(
                            isSelected ? Color.accentColor : Color.white,
                            Color.white
                        )
                        .padding(VaultGalleryTileMetrics.selectionInset)
                        .shadow(radius: 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(
                maxWidth: .infinity,
                minHeight: VaultGalleryTileMetrics.footerHeight,
                maxHeight: VaultGalleryTileMetrics.footerHeight,
                alignment: .topLeading
            )
            .background(.ultraThinMaterial)
        }
    }
}

struct VaultGalleryItemTileView: View {
    let item: VaultGalleryPresentationItem
    let thumbnail: UIImage?
    let selectionState: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VaultGalleryTileSurface(
                title: item.title,
                detail: item.detail,
                selectionState: selectionState
            ) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(
                            item.isImage ? Color.secondary : Color.accentColor
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            selectionState == nil
                ? "Opens this encrypted vault item"
                : "Toggles selection for this item"
        )
    }

    private var accessibilityValue: String {
        let metadata = "\(item.accessibilityKind), \(item.detail)"
        guard let isSelected = selectionState else { return metadata }
        return "\(isSelected ? "Selected" : "Not selected"), \(metadata)"
    }
}
