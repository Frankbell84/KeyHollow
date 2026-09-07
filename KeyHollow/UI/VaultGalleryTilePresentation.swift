import Foundation
import SwiftUI
import UIKit

enum VaultGalleryTileMetrics {
    static let columnCount = 3
    static let gridSpacing: CGFloat = 3
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

}

public struct VaultGalleryPresentationItem: Identifiable, Equatable, Sendable {
    public let id: VaultGallerySelection.Item
    public let importedAt: Date
    public let title: String
    public let detail: String
    public let iconName: String
    public let isImage: Bool
    public let accessibilityKind: String

    public init(
        id: VaultGallerySelection.Item,
        importedAt: Date,
        displayName: String?,
        originalByteCount: UInt64?,
        isImage: Bool,
        fallbackTitle: String,
        iconName: String,
        accessibilityKind: String
    ) {
        self.id = id
        self.importedAt = importedAt
        self.title = VaultGalleryPresentationMetadata.title(
            displayName: displayName,
            isImage: isImage,
            fallback: fallbackTitle
        )
        self.detail = VaultGalleryPresentationMetadata.detail(
            byteCount: originalByteCount,
            importedAt: importedAt
        )
        self.iconName = iconName
        self.isImage = isImage
        self.accessibilityKind = accessibilityKind
    }

    public static func sourceNeutralOrder(
        _ first: Self,
        _ second: Self
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

public enum VaultGalleryThumbnailRenderer {
    public static func jpegData(from image: UIImage, maximumDimension: CGFloat = 512) -> Data? {
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

    public static func orientedPixelSize(for image: UIImage) -> CGSize {
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
            Rectangle()
                .fill(.secondary.opacity(0.12))
                .aspectRatio(
                    VaultGalleryTileMetrics.mediaAspectRatio,
                    contentMode: .fit
                )
                .overlay {
                    media
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
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
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

public struct VaultGalleryItemTileView: View {
    let item: VaultGalleryPresentationItem
    let thumbnail: UIImage?
    let selectionState: Bool?
    let action: () -> Void

    public init(
        item: VaultGalleryPresentationItem,
        thumbnail: UIImage?,
        selectionState: Bool?,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.thumbnail = thumbnail
        self.selectionState = selectionState
        self.action = action
    }

    public var body: some View {
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
