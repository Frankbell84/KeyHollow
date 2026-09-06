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
}

/// One lifecycle-owned plaintext image. The application must release this
/// value when the preview closes or the vault locks. This module never writes
/// the bytes to disk and never receives the capability that decrypted them.
public struct VaultSecureImagePreview: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let originalData: Data

    public init(id: UUID, displayName: String, originalData: Data) throws {
        guard !originalData.isEmpty else {
            throw VaultSecureImagePreviewError.emptyPayload
        }
        guard VaultSecurePreviewPolicy.allowsEncodedImageByteCount(
            UInt64(originalData.count)
        ) else {
            throw VaultSecureImagePreviewError.payloadTooLarge
        }
        guard let source = CGImageSourceCreateWithData(originalData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = Self.positiveDimension(properties[kCGImagePropertyPixelWidth]),
              let height = Self.positiveDimension(properties[kCGImagePropertyPixelHeight]) else {
            throw VaultSecureImagePreviewError.invalidImage
        }
        guard width <= VaultSecurePreviewPolicy.maximumImagePixelCount / height else {
            throw VaultSecureImagePreviewError.imageDimensionsTooLarge
        }

        self.id = id
        self.displayName = displayName
        self.originalData = originalData
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
    private let preview: VaultSecureImagePreview
    private let isSaving: Bool
    @Binding private var message: String?
    private let onDismiss: () -> Void
    private let onSave: () -> Void
    private let onDelete: () -> Void

    public init(
        preview: VaultSecureImagePreview,
        isSaving: Bool,
        message: Binding<String?>,
        onDismiss: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.preview = preview
        self.isSaving = isSaving
        self._message = message
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onDelete = onDelete
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = UIImage(data: preview.originalData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(preview.displayName)
            }

            VStack {
                HStack {
                    Button("Done", action: onDismiss)

                    Spacer()

                    if isSaving {
                        ProgressView()
                    } else {
                        Button(action: onSave) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Save to Photos")
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete from Vault")
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
