import Foundation
import SwiftUI
import UIKit
import KeyHollowPhotoCore

enum VaultPhotoPresentationMetadata {
    static func title(for record: VaultPhotoRecord) -> String {
        guard let displayName = record.displayName,
              !displayName.isEmpty else { return "Photo" }
        return displayName
    }

    static func detail(for record: VaultPhotoRecord) -> String {
        if let byteCount = record.originalByteCount {
            return ByteCountFormatter.string(
                fromByteCount: Int64(clamping: byteCount),
                countStyle: .file
            )
        }
        return DateFormatter.localizedString(
            from: record.importedAt,
            dateStyle: .medium,
            timeStyle: .none
        )
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
    private let media: Media

    init(
        title: String,
        detail: String,
        @ViewBuilder media: () -> Media
    ) {
        self.title = title
        self.detail = detail
        self.media = media()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(.secondary.opacity(0.12))

                media
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.ultraThinMaterial)
        }
    }
}
