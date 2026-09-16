import Foundation
import Photos
@preconcurrency import PhotosUI
@preconcurrency import UIKit
import UniformTypeIdentifiers

public struct PickedVaultPhoto: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let sourceAssetIdentifier: String?
    public let displayName: String?
    public let originalData: Data
    public let thumbnailData: Data

    public init(
        sourceAssetIdentifier: String?,
        displayName: String? = nil,
        originalData: Data,
        thumbnailData: Data
    ) {
        self.sourceAssetIdentifier = sourceAssetIdentifier
        self.displayName = displayName
        self.originalData = originalData
        self.thumbnailData = thumbnailData
    }
}

private final class PickedVaultVideoLease: @unchecked Sendable {
    let fileURL: URL

    private let rootURL: URL
    private let lock = NSLock()
    private var isDiscarded = false

    init(fileURL: URL, rootURL: URL) {
        self.fileURL = fileURL
        self.rootURL = rootURL
    }

    func discard() {
        lock.lock()
        guard !isDiscarded else {
            lock.unlock()
            return
        }
        isDiscarded = true
        lock.unlock()
        try? FileManager.default.removeItem(at: rootURL)
    }

    deinit {
        discard()
    }
}

/// A Photos-origin video staged under complete file protection only long enough
/// for the application-owned encrypted general-file store to consume it. The
/// lease removes the plaintext if import is cancelled, fails, or is abandoned.
public struct PickedVaultVideo: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let sourceAssetIdentifier: String?
    public let displayName: String

    private let lease: PickedVaultVideoLease

    fileprivate init(
        sourceAssetIdentifier: String?,
        displayName: String,
        fileURL: URL,
        rootURL: URL
    ) {
        self.sourceAssetIdentifier = sourceAssetIdentifier
        self.displayName = displayName
        lease = PickedVaultVideoLease(fileURL: fileURL, rootURL: rootURL)
    }

    public var fileURL: URL {
        lease.fileURL
    }

    public func discard() {
        lease.discard()
    }
}

public enum PickedVaultMedia: @unchecked Sendable {
    case photo(PickedVaultPhoto)
    case video(PickedVaultVideo)
}

public enum SequentialPhotoBatchProcessor {
    public static let maximumConcurrentItems = 1

    @MainActor
    public static func process<Element: Sendable, Value: Sendable>(
        _ elements: [Element],
        load: (Element) async throws -> Value,
        consume: (Value) async -> Void,
        didFail: () async -> Void
    ) async {
        for element in elements {
            guard !Task.isCancelled else { return }
            do {
                let value = try await load(element)
                guard !Task.isCancelled else { return }
                await consume(value)
            } catch is CancellationError {
                return
            } catch {
                await didFail()
            }
        }
    }
}

public enum ApplePhotoPickerItemLoader {
    /// Mirrors the authenticated general-file ingress ceiling. A Photos video
    /// larger than this is rejected before it is copied into app-owned
    /// temporary storage.
    public static let maximumVideoByteCount: UInt64 = 100 * 1_024 * 1_024

    nonisolated public static func loadMedia(
        _ result: PHPickerResult
    ) async throws -> PickedVaultMedia {
        let provider = result.itemProvider
        if let videoTypeIdentifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .movie) == true
        }) {
            return .video(
                try await loadVideo(
                    result,
                    typeIdentifier: videoTypeIdentifier
                )
            )
        }
        return .photo(try await loadPhoto(result))
    }

    /// Full-resolution images are decoded, normalized, and returned one at a
    /// time. Plaintext image data is never written to KeyHollow storage here.
    nonisolated public static func loadPhoto(
        _ result: PHPickerResult
    ) async throws -> PickedVaultPhoto {
        let provider = result.itemProvider
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let image = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<UIImage, Error>) in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
                }
            }
        }
        try Task.checkCancellation()

        guard let originalData = image.jpegData(compressionQuality: 0.97),
              let thumbnailData = thumbnailJPEG(from: image) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return PickedVaultPhoto(
            sourceAssetIdentifier: result.assetIdentifier,
            displayName: provider.suggestedName,
            originalData: originalData,
            thumbnailData: thumbnailData
        )
    }

    private nonisolated static func loadVideo(
        _ result: PHPickerResult,
        typeIdentifier: String
    ) async throws -> PickedVaultVideo {
        let provider = result.itemProvider
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<PickedVaultVideo, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) {
                sourceURL,
                error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sourceURL else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }

                do {
                    let staged = try stageVideo(
                        from: sourceURL,
                        suggestedName: provider.suggestedName,
                        typeIdentifier: typeIdentifier
                    )
                    continuation.resume(
                        returning: PickedVaultVideo(
                            sourceAssetIdentifier: result.assetIdentifier,
                            displayName: staged.fileURL.lastPathComponent,
                            fileURL: staged.fileURL,
                            rootURL: staged.rootURL
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func stageVideo(
        from sourceURL: URL,
        suggestedName: String?,
        typeIdentifier: String
    ) throws -> (rootURL: URL, fileURL: URL) {
        let fileManager = FileManager.default
        let values = try sourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard UInt64(fileSize) <= maximumVideoByteCount else {
            throw CocoaError(.fileReadTooLarge)
        }

        let containerURL = fileManager.temporaryDirectory
            .appendingPathComponent("KeyHollowPhotoPickerImports", isDirectory: true)
        let rootURL = containerURL
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        do {
            try protectAndExclude(containerURL)
            try protectAndExclude(rootURL)
            let fileName = safeVideoFileName(
                suggestedName: suggestedName,
                sourceURL: sourceURL,
                typeIdentifier: typeIdentifier
            )
            let fileURL = rootURL.appendingPathComponent(fileName, isDirectory: false)
            try fileManager.copyItem(at: sourceURL, to: fileURL)
            try protectAndExclude(fileURL)

            let copiedValues = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ])
            guard copiedValues.isRegularFile == true,
                  copiedValues.isSymbolicLink != true,
                  copiedValues.fileSize == fileSize else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return (rootURL, fileURL)
        } catch {
            try? fileManager.removeItem(at: rootURL)
            throw error
        }
    }

    private nonisolated static func safeVideoFileName(
        suggestedName: String?,
        sourceURL: URL,
        typeIdentifier: String
    ) -> String {
        let proposed = (suggestedName ?? sourceURL.lastPathComponent) as NSString
        var leaf = URL(fileURLWithPath: proposed.lastPathComponent).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
        if leaf.isEmpty {
            leaf = "Vault Video"
        }
        if (leaf as NSString).pathExtension.isEmpty,
           let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension {
            leaf += ".\(fileExtension)"
        }
        return String(leaf.prefix(180))
    }

    private nonisolated static func protectAndExclude(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private nonisolated static func thumbnailJPEG(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 512
        let source = image.size
        guard source.width > 0, source.height > 0 else { return nil }

        let scale = min(1, maxDimension / max(source.width, source.height))
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumbnail.jpegData(compressionQuality: 0.82)
    }
}

public enum PhotoMoveResult: Equatable, Sendable {
    case deleted
    case copiedOnly
}

public enum PhotoLibrarySaveResult: Equatable, Sendable {
    case saved(Int)
    case permissionDenied
    case failed
}

public enum PhotoLibrarySaveService {
    public static let maximumResidentFullSizePhotos = 1

    public static func savePhoto(_ photo: Data) async -> PhotoLibrarySaveResult {
        guard !photo.isEmpty, !Task.isCancelled else { return .failed }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }
        guard !Task.isCancelled else { return .failed }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: photo, options: nil)
                }) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                    }
                }
            }
            return .saved(1)
        } catch {
            return .failed
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

public enum PhotoLibraryDeletionService {
    public static func deleteOriginals(localIdentifiers: [String]) async -> PhotoMoveResult {
        let identifiers = Array(Set(localIdentifiers))
        guard !identifiers.isEmpty, !Task.isCancelled else { return .copiedOnly }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else { return .copiedOnly }
        guard !Task.isCancelled else { return .copiedOnly }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count == identifiers.count else { return .copiedOnly }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.deleteAssets(assets)
                }) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: CocoaError(.userCancelled))
                    }
                }
            }
            return .deleted
        } catch {
            return .copiedOnly
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
