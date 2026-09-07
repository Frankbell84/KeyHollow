import CoreFoundation
import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

public enum VaultSecurePreviewKind: Equatable, Sendable {
    case image
    case unsupported
}

/// Immutable metadata used to decide whether an encrypted item has an approved
/// in-memory preview path. It contains no record, storage location, key, or
/// cryptographic capability.
public struct VaultSecurePreviewDescriptor: Equatable, Sendable {
    public let displayName: String
    public let contentTypeIdentifier: String?
    public let originalByteCount: UInt64

    public init(
        displayName: String,
        contentTypeIdentifier: String?,
        originalByteCount: UInt64
    ) {
        self.displayName = displayName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.originalByteCount = originalByteCount
    }
}

public enum VaultSecurePreviewPolicy {
    /// Matches the encrypted general-file ingress ceiling and prevents an
    /// unbounded encoded payload from entering the presentation layer.
    public static let maximumEncodedImageByteCount: UInt64 = 100 * 1_024 * 1_024

    /// Prevents small, hostile compressed images from expanding without a
    /// practical upper bound when UIKit decodes them for display.
    public static let maximumImagePixelCount: UInt64 = 80_000_000

    public static func kind(for descriptor: VaultSecurePreviewDescriptor) -> VaultSecurePreviewKind {
        if let identifier = descriptor.contentTypeIdentifier,
           UTType(identifier)?.conforms(to: .image) == true {
            return .image
        }

        let pathExtension = (descriptor.displayName as NSString).pathExtension
        if !pathExtension.isEmpty,
           UTType(filenameExtension: pathExtension)?.conforms(to: .image) == true {
            return .image
        }

        return .unsupported
    }

    public static func allowsEncodedImageByteCount(_ byteCount: UInt64) -> Bool {
        byteCount > 0 && byteCount <= maximumEncodedImageByteCount
    }
}

public enum VaultSecureImagePreviewError: Error, Equatable, Sendable {
    case emptyPayload
    case payloadTooLarge
    case invalidImage
    case imageDimensionsTooLarge
    case renderingFailed
}

/// Immutable UIKit image ownership used only after ImageIO has bounded and
/// eagerly prepared the decoded pixel surface away from the main actor.
/// `UIImage` is immutable for this use; the wrapper never exposes mutation.
public struct VaultSecureRenderedImage: @unchecked Sendable {
    public let image: UIImage

    fileprivate init(image: UIImage) {
        self.image = image
    }
}

public struct VaultSecurePreparedThumbnail: Sendable {
    public let encodedData: Data
    public let renderedImage: VaultSecureRenderedImage

    fileprivate init(encodedData: Data, renderedImage: VaultSecureRenderedImage) {
        self.encodedData = encodedData
        self.renderedImage = renderedImage
    }
}

/// Serializes bounded ImageIO work on a non-main actor. Callers retain storage
/// and cryptographic capabilities; this processor receives only one already-
/// authenticated in-memory payload and never writes plaintext to disk.
public actor VaultSecureImageProcessor {
    public static let galleryThumbnailMaximumPixelDimension = 512
    public static let previewMaximumPixelDimension = 2_048

    public init() {}

    public func decodeThumbnail(
        from encodedData: Data
    ) throws -> VaultSecureRenderedImage {
        try Task.checkCancellation()
        let image = try VaultSecureImageDecoder.renderedImage(
            from: encodedData,
            maximumPixelDimension: Self.galleryThumbnailMaximumPixelDimension
        )
        try Task.checkCancellation()
        return image
    }

    public func prepareThumbnail(
        from originalData: Data
    ) throws -> VaultSecurePreparedThumbnail {
        try Task.checkCancellation()
        let renderedImage = try VaultSecureImageDecoder.renderedImage(
            from: originalData,
            maximumPixelDimension: Self.galleryThumbnailMaximumPixelDimension
        )
        let encodedData = try VaultSecureImageDecoder.jpegData(from: renderedImage)
        try Task.checkCancellation()
        return VaultSecurePreparedThumbnail(
            encodedData: encodedData,
            renderedImage: renderedImage
        )
    }

    public func preparePreview(
        id: UUID,
        displayName: String,
        originalData: Data
    ) throws -> VaultSecureImagePreview {
        try Task.checkCancellation()
        let displayImage = try VaultSecureImageDecoder.renderedImage(
            from: originalData,
            maximumPixelDimension: Self.previewMaximumPixelDimension
        )
        try Task.checkCancellation()
        return VaultSecureImagePreview(
            id: id,
            displayName: displayName,
            originalData: originalData,
            displayImage: displayImage
        )
    }
}

/// One lifecycle-owned plaintext image. The application must release this
/// value when the preview closes or the vault locks. This module never writes
/// the bytes to disk and never receives the capability that decrypted them.
public struct VaultSecureImagePreview: Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let originalData: Data
    public let displayImage: VaultSecureRenderedImage

    init(id: UUID, displayName: String, originalData: Data) throws {
        let displayImage = try VaultSecureImageDecoder.renderedImage(
            from: originalData,
            maximumPixelDimension: VaultSecureImageProcessor.previewMaximumPixelDimension
        )
        self.init(
            id: id,
            displayName: displayName,
            originalData: originalData,
            displayImage: displayImage
        )
    }

    fileprivate init(
        id: UUID,
        displayName: String,
        originalData: Data,
        displayImage: VaultSecureRenderedImage
    ) {
        self.id = id
        self.displayName = displayName
        self.originalData = originalData
        self.displayImage = displayImage
    }
}

private enum VaultSecureImageDecoder {
    static func renderedImage(
        from encodedData: Data,
        maximumPixelDimension: Int
    ) throws -> VaultSecureRenderedImage {
        guard !encodedData.isEmpty else {
            throw VaultSecureImagePreviewError.emptyPayload
        }
        guard VaultSecurePreviewPolicy.allowsEncodedImageByteCount(
            UInt64(encodedData.count)
        ) else {
            throw VaultSecureImagePreviewError.payloadTooLarge
        }
        guard maximumPixelDimension > 0,
              let source = CGImageSourceCreateWithData(encodedData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = positiveDimension(properties[kCGImagePropertyPixelWidth]),
              let height = positiveDimension(properties[kCGImagePropertyPixelHeight]) else {
            throw VaultSecureImagePreviewError.invalidImage
        }
        guard width <= VaultSecurePreviewPolicy.maximumImagePixelCount / height else {
            throw VaultSecureImagePreviewError.imageDimensionsTooLarge
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw VaultSecureImagePreviewError.renderingFailed
        }
        return VaultSecureRenderedImage(image: UIImage(cgImage: image))
    }

    static func jpegData(
        from renderedImage: VaultSecureRenderedImage
    ) throws -> Data {
        guard let image = renderedImage.image.cgImage else {
            throw VaultSecureImagePreviewError.renderingFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw VaultSecureImagePreviewError.renderingFailed
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw VaultSecureImagePreviewError.renderingFailed
        }
        return data as Data
    }

    private static func positiveDimension(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber else { return nil }
        let dimension = number.uint64Value
        return dimension > 0 ? dimension : nil
    }
}

/// Shared image surface for Photos-origin and Files-origin encrypted images.
/// Storage, authentication, saving, and deletion remain action closures owned
/// by the application composition layer.
public struct VaultSecureImagePreviewView: View {
    @Binding private var preview: VaultSecureImagePreview?
    private let placeholder: UIImage?
    private let displayName: String
    private let isLoading: Bool
    private let isSaving: Bool
    @Binding private var message: String?
    private let onDismiss: () -> Void
    private let onSave: () -> Void
    private let onDelete: () -> Void

    public init(
        preview: Binding<VaultSecureImagePreview?>,
        placeholder: UIImage?,
        displayName: String,
        isLoading: Bool,
        isSaving: Bool,
        message: Binding<String?>,
        onDismiss: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self._preview = preview
        self.placeholder = placeholder
        self.displayName = displayName
        self.isLoading = isLoading
        self.isSaving = isSaving
        self._message = message
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onDelete = onDelete
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = preview?.displayImage.image ?? placeholder {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(displayName)
            }

            if isLoading {
                ProgressView("Opening…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack {
                HStack {
                    Button("Done", action: onDismiss)

                    Spacer()

                    if isLoading || isSaving {
                        ProgressView()
                    } else if preview != nil {
                        Button(action: onSave) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Save to Photos")
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete from Vault")
                    .disabled(isLoading)
                }
                .padding()
                .background(.ultraThinMaterial)

                Spacer()
            }
        }
        .alert("KeyHollow", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}
