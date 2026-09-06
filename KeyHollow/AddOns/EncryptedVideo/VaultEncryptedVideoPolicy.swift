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
    /// Build 35's general-file store is deliberately bounded at 100 MB. The
    /// first video add-on release preserves that encrypted-storage boundary;
    /// larger streaming video requires a separately versioned storage review.
    public static let maximumPlaybackByteCount: UInt64 = 100 * 1_024 * 1_024

    private static let fallbackExtensions: Set<String> = ["m4v", "mov", "mp4"]

    public static func kind(
        for descriptor: VaultEncryptedVideoDescriptor
    ) -> VaultEncryptedVideoKind {
        guard allowsPlaybackByteCount(descriptor.originalByteCount) else {
            return .unsupported
        }

        if let identifier = descriptor.contentTypeIdentifier,
           let type = UTType(identifier) {
            // A recognized non-video declaration is authoritative. Do not send
            // a PDF or other mismatched file into a media decoder merely because
            // its filename was changed to use a video extension.
            return type.conforms(to: .movie) ? .video : .unsupported
        }

        let pathExtension = (descriptor.displayName as NSString)
            .pathExtension
            .lowercased()
        return fallbackExtensions.contains(pathExtension) ? .video : .unsupported
    }

    public static func allowsPlaybackByteCount(_ byteCount: UInt64) -> Bool {
        byteCount > 0 && byteCount <= maximumPlaybackByteCount
    }
}

public enum VaultPreparedVideoPlaybackError: Error, Equatable, Sendable {
    case unsupportedVideo
    case invalidPlaybackURL
}

/// A validated handoff to a future playback surface. The application creates
/// and owns the protected temporary file, and remains responsible for deleting
/// it on dismissal, locking, cancellation, backgrounding, and failure.
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
        guard fileURL.isFileURL else {
            throw VaultPreparedVideoPlaybackError.invalidPlaybackURL
        }

        self.id = id
        self.descriptor = descriptor
        self.fileURL = fileURL
    }
}
