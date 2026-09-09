import AVFoundation
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public enum VaultEncryptedVideoKind: Equatable, Sendable {
    case video
    case unsupported
}

/// Source-neutral metadata used to decide whether an existing encrypted
/// general-file record may enter the video playback path. The descriptor owns
/// no record, storage URL, vault key, or authenticated capability.
public struct VaultEncryptedVideoDescriptor: Equatable, Sendable {
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

public enum VaultEncryptedVideoPolicy {
    /// The first video presentation release intentionally matches the existing
    /// encrypted general-file ingress ceiling. Larger video requires a
    /// separately reviewed storage and streaming design.
    public static let maximumPlaybackByteCount: UInt64 = 100 * 1_024 * 1_024
    /// Reject extreme source frames before AVAssetImageGenerator can allocate
    /// decoder surfaces. This admits ordinary 4K and 8K media while bounding a
    /// crafted small-file/high-resolution memory-pressure input.
    public static let maximumSourcePixelDimension: CGFloat = 8_192
    public static let maximumSourcePixelCount: CGFloat = 7_680 * 4_320

    private static let supportedExtensions: Set<String> = ["m4v", "mov", "mp4"]
    private static let supportedDeclaredTypeIdentifiers: Set<String> = [
        "com.apple.m4v-video",
        "com.apple.quicktime-movie",
        "public.mpeg-4"
    ]

    public static func kind(
        for descriptor: VaultEncryptedVideoDescriptor
    ) -> VaultEncryptedVideoKind {
        guard allowsPlaybackByteCount(descriptor.originalByteCount) else {
            return .unsupported
        }

        if let identifier = descriptor.contentTypeIdentifier {
            // A declaration is authoritative, including an empty, malformed,
            // unknown, or broader movie declaration. Filename fallback is only
            // for records whose type metadata is genuinely absent.
            guard let declaredType = UTType(identifier) else {
                return .unsupported
            }
            return supportedDeclaredTypeIdentifiers.contains(
                declaredType.identifier.lowercased()
            ) ? .video : .unsupported
        }

        let pathExtension = (descriptor.displayName as NSString)
            .pathExtension
            .lowercased()
        return supportedExtensions.contains(pathExtension) ? .video : .unsupported
    }

    public static func allowsPlaybackByteCount(_ byteCount: UInt64) -> Bool {
        byteCount > 0 && byteCount <= maximumPlaybackByteCount
    }

    static func allowsSourceDimensions(_ dimensions: CGSize) -> Bool {
        let width = abs(dimensions.width)
        let height = abs(dimensions.height)
        guard width.isFinite,
              height.isFinite,
              width > 0,
              height > 0,
              width <= maximumSourcePixelDimension,
              height <= maximumSourcePixelDimension else {
            return false
        }
        return width * height <= maximumSourcePixelCount
    }
}

public enum VaultPreparedVideoPlaybackError: Error, Equatable, Sendable {
    case unsupportedVideo
    case invalidPlaybackURL
    case missingPlaybackFile
    case playbackURLIsDirectory
    case unplayableVideo
}

/// A local, regular-file handoff to the video presentation module. The
/// application creates and owns this protected temporary file and remains
/// responsible for deleting it on dismissal, locking, cancellation,
/// backgrounding, and failure.
public struct VaultPreparedVideoPlayback: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let descriptor: VaultEncryptedVideoDescriptor
    public let fileURL: URL

    public init(
        id: UUID,
        descriptor: VaultEncryptedVideoDescriptor,
        fileURL: URL
    ) throws {
        guard VaultEncryptedVideoPolicy.kind(for: descriptor) == .video else {
            throw VaultPreparedVideoPlaybackError.unsupportedVideo
        }
        try Self.validateLocalRegularFile(at: fileURL)

        self.id = id
        self.descriptor = descriptor
        self.fileURL = fileURL
    }

    /// Loads the local asset's real media metadata before the application
    /// publishes playback. This rejects malformed media, unsupported codecs,
    /// files without a video track, and reference movies that could reach
    /// outside the application-owned local file.
    public func validatePlayable() async throws {
        try Task.checkCancellation()
        try Self.validateLocalRegularFile(at: fileURL)

        let asset = makeRestrictedAsset()
        do {
            guard try await asset.load(.isPlayable) else {
                throw VaultPreparedVideoPlaybackError.unplayableVideo
            }
            try Task.checkCancellation()

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else {
                throw VaultPreparedVideoPlaybackError.unplayableVideo
            }

            let allTracks = try await asset.load(.tracks)
            for track in allTracks {
                try Task.checkCancellation()
                guard try await track.load(.isSelfContained) else {
                    throw VaultPreparedVideoPlaybackError.unplayableVideo
                }
            }

            var hasDecodableVideoTrack = false
            for track in videoTracks {
                try Task.checkCancellation()
                let naturalSize = try await track.load(.naturalSize)
                let preferredTransform = try await track.load(.preferredTransform)
                let presentationSize = naturalSize.applying(preferredTransform)
                let formatDescriptions = try await track.load(.formatDescriptions)
                guard VaultEncryptedVideoPolicy.allowsSourceDimensions(naturalSize),
                      VaultEncryptedVideoPolicy.allowsSourceDimensions(
                          presentationSize
                      ),
                      formatDescriptions.allSatisfy({ description in
                          let dimensions = CMVideoFormatDescriptionGetDimensions(
                              description
                          )
                          return VaultEncryptedVideoPolicy.allowsSourceDimensions(
                              CGSize(
                                  width: CGFloat(dimensions.width),
                                  height: CGFloat(dimensions.height)
                              )
                          )
                      }) else {
                    throw VaultPreparedVideoPlaybackError.unplayableVideo
                }
                if try await track.load(.isDecodable) {
                    hasDecodableVideoTrack = true
                }
            }
            guard hasDecodableVideoTrack else {
                throw VaultPreparedVideoPlaybackError.unplayableVideo
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VaultPreparedVideoPlaybackError {
            throw error
        } catch {
            throw VaultPreparedVideoPlaybackError.unplayableVideo
        }
    }

    /// Creates every AVFoundation asset in this add-on with the strongest
    /// reference restriction. A crafted reference movie therefore cannot ask
    /// AVFoundation to resolve media outside the protected local container.
    func makeRestrictedAsset() -> AVURLAsset {
        AVURLAsset(
            url: fileURL,
            options: [
                AVURLAssetReferenceRestrictionsKey:
                    AVAssetReferenceRestrictions.forbidAll.rawValue
            ]
        )
    }

    private static func validateLocalRegularFile(at fileURL: URL) throws {
        guard fileURL.isFileURL else {
            throw VaultPreparedVideoPlaybackError.invalidPlaybackURL
        }

        guard (try? fileURL.checkResourceIsReachable()) == true else {
            throw VaultPreparedVideoPlaybackError.missingPlaybackFile
        }

        let values: URLResourceValues
        do {
            values = try fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isReadableKey,
                .isRegularFileKey
            ])
        } catch {
            throw VaultPreparedVideoPlaybackError.invalidPlaybackURL
        }
        guard values.isDirectory != true else {
            throw VaultPreparedVideoPlaybackError.playbackURLIsDirectory
        }
        guard values.isRegularFile == true, values.isReadable == true else {
            throw VaultPreparedVideoPlaybackError.invalidPlaybackURL
        }
    }
}
