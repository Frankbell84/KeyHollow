import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum VaultEncryptedVideoThumbnailError: Error, Equatable, Sendable {
    case invalidDimensions
    case dimensionsTooLarge
    case encodingFailed
    case encodedThumbnailTooLarge
}

public struct VaultEncryptedVideoThumbnail: Equatable, Sendable {
    public let jpegData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

    init(jpegData: Data, pixelWidth: Int, pixelHeight: Int) throws {
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw VaultEncryptedVideoThumbnailError.invalidDimensions
        }
        guard pixelWidth <= VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension,
              pixelHeight <= VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension else {
            throw VaultEncryptedVideoThumbnailError.dimensionsTooLarge
        }
        guard !jpegData.isEmpty else {
            throw VaultEncryptedVideoThumbnailError.encodingFailed
        }
        guard jpegData.count <= VaultEncryptedVideoThumbnailRenderer.maximumEncodedByteCount else {
            throw VaultEncryptedVideoThumbnailError.encodedThumbnailTooLarge
        }

        self.jpegData = jpegData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum VaultEncryptedVideoThumbnailRenderer {
    /// Matches the established square gallery thumbnail envelope without ever
    /// decoding a full-resolution video frame into the grid.
    public static let maximumPixelDimension = 512
    public static let maximumEncodedByteCount = 2 * 1_024 * 1_024

    public static func render(
        _ playback: VaultPreparedVideoPlayback
    ) async throws -> VaultEncryptedVideoThumbnail {
        try Task.checkCancellation()

        let asset = AVURLAsset(url: playback.fileURL)
        let cancellationBox = VaultVideoImageGeneratorCancellationBox(
            AVAssetImageGenerator(asset: asset)
        )
        cancellationBox.generator.appliesPreferredTrackTransform = true
        cancellationBox.generator.maximumSize = CGSize(
            width: maximumPixelDimension,
            height: maximumPixelDimension
        )
        return try await withTaskCancellationHandler {
            defer { cancellationBox.cancel() }
            let result = try await cancellationBox.generator.image(at: .zero)
            try Task.checkCancellation()
            return try encodedThumbnail(from: result.image)
        } onCancel: {
            cancellationBox.cancel()
        }
    }

    static func encodedThumbnail(
        from image: CGImage
    ) throws -> VaultEncryptedVideoThumbnail {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw VaultEncryptedVideoThumbnailError.invalidDimensions
        }
        guard width <= maximumPixelDimension, height <= maximumPixelDimension else {
            throw VaultEncryptedVideoThumbnailError.dimensionsTooLarge
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw VaultEncryptedVideoThumbnailError.encodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw VaultEncryptedVideoThumbnailError.encodingFailed
        }

        return try VaultEncryptedVideoThumbnail(
            jpegData: output as Data,
            pixelWidth: width,
            pixelHeight: height
        )
    }
}

/// AVFoundation's cancellation entry point is designed to be callable from a
/// cancellation handler. The box makes that narrowly reviewed cross-executor
/// capability explicit without making generated image data shared or mutable.
private final class VaultVideoImageGeneratorCancellationBox: @unchecked Sendable {
    let generator: AVAssetImageGenerator

    init(_ generator: AVAssetImageGenerator) {
        self.generator = generator
    }

    func cancel() {
        generator.cancelAllCGImageGeneration()
    }
}
