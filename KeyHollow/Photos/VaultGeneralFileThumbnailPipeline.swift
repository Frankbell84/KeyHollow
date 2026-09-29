import Foundation
import KeyHollowEncryptedVideoAddOn
import KeyHollowFolderPresentationAddOn
import KeyHollowGeneralFileSupportAddOn
import KeyHollowSecurePreviewAddOn

/// Gives encrypted thumbnail cache hits a responsive lane while bounding the
/// complete Files-origin cache-miss path to one full plaintext payload at a
/// time. The permit intentionally covers authenticated original loading,
/// bounded ImageIO preparation, and encrypted cache persistence so cell tasks
/// cannot queue multiple large decrypted files between otherwise independent
/// actors. Queued duplicate misses recheck the encrypted cache after the first
/// request completes.
struct VaultGeneralFileThumbnailPipelineHooks: Sendable {
    var didAcquireColdPermit: @Sendable () async -> Void
    var didPrepareVideoPlaintext: @Sendable () async -> Void

    init(
        didAcquireColdPermit: @escaping @Sendable () async -> Void = {},
        didPrepareVideoPlaintext: @escaping @Sendable () async -> Void = {}
    ) {
        self.didAcquireColdPermit = didAcquireColdPermit
        self.didPrepareVideoPlaintext = didPrepareVideoPlaintext
    }
}

actor VaultGeneralFileThumbnailPipeline {
    private enum PipelineError: Error {
        case unsupportedItem
        case invalidPreparedExport
    }

    private struct PermitWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let cachedThumbnailDecoder = VaultSecureImageProcessor()
    private let cacheMissImageProcessor = VaultSecureImageProcessor()
    private let hooks: VaultGeneralFileThumbnailPipelineHooks
    private var isOccupied = false
    private var waiters: [PermitWaiter] = []

    init(hooks: VaultGeneralFileThumbnailPipelineHooks = .init()) {
        self.hooks = hooks
    }

    func image(
        for record: VaultGeneralFileRecord,
        generalFileStore: VaultGeneralFileStore,
        presentationStore: VaultFolderPresentationStore
    ) async throws -> VaultSecureRenderedImage {
        let reference = VaultPresentedContentReference(kind: .generalFile, id: record.id)
        return try await loadOrGenerate(
            loadCached: { [self] in
                try await loadCachedThumbnail(
                    for: reference,
                    presentationStore: presentationStore
                )
            },
            generate: { [self] in
                try await generateThumbnail(
                    for: record,
                    reference: reference,
                    generalFileStore: generalFileStore,
                    presentationStore: presentationStore
                )
            }
        )
    }

    /// Shared cache/cold-work primitive used by both Files-origin images and
    /// videos. Keeping this internal gives deterministic tests direct access
    /// to the production permit and duplicate-cache recheck semantics.
    func loadOrGenerate<Value: Sendable>(
        loadCached: @escaping @Sendable () async throws -> Value?,
        generate: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let cachedValue = try await loadCached() {
            return cachedValue
        }

        guard await acquire() else { throw CancellationError() }
        defer { release() }
        try Task.checkCancellation()

        if let cachedValue = try await loadCached() {
            return cachedValue
        }

        await hooks.didAcquireColdPermit()
        try Task.checkCancellation()
        return try await generate()
    }

    private func generateThumbnail(
        for record: VaultGeneralFileRecord,
        reference: VaultPresentedContentReference,
        generalFileStore: VaultGeneralFileStore,
        presentationStore: VaultFolderPresentationStore
    ) async throws -> VaultSecureRenderedImage {

        let securePreviewKind = VaultSecurePreviewPolicy.kind(
            for: VaultSecurePreviewDescriptor(
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                originalByteCount: record.originalByteCount
            )
        )
        if securePreviewKind == .image {
            try Task.checkCancellation()
            let originalData = try await generalFileStore.loadFile(record)
            try Task.checkCancellation()
            let thumbnail = try await cacheMissImageProcessor.prepareThumbnail(from: originalData)
            try Task.checkCancellation()
            try await presentationStore.storeThumbnail(thumbnail.encodedData, for: reference)
            try Task.checkCancellation()
            return thumbnail.renderedImage
        }

        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: record.displayName,
            contentTypeIdentifier: record.contentTypeIdentifier,
            originalByteCount: record.originalByteCount
        )
        guard VaultEncryptedVideoPolicy.kind(for: descriptor) == .video else {
            throw PipelineError.unsupportedItem
        }

        try Task.checkCancellation()
        let prepared = try await generalFileStore.prepareExport([record])
        do {
            await hooks.didPrepareVideoPlaintext()
            try Task.checkCancellation()
            guard prepared.urls.count == 1, let fileURL = prepared.urls.first else {
                throw PipelineError.invalidPreparedExport
            }
            let playback = try VaultPreparedVideoPlayback(
                id: record.id,
                descriptor: descriptor,
                fileURL: fileURL
            )
            let videoThumbnail = try await VaultEncryptedVideoThumbnailRenderer.render(playback)
            try Task.checkCancellation()

            // The original plaintext is gone before its bounded JPEG enters
            // the encrypted presentation cache.
            await generalFileStore.discardExport(prepared)
            try Task.checkCancellation()
            let renderedImage = try await cachedThumbnailDecoder.decodeThumbnail(
                from: videoThumbnail.jpegData
            )
            try Task.checkCancellation()
            try await presentationStore.storeThumbnail(
                videoThumbnail.jpegData,
                for: reference
            )
            try Task.checkCancellation()
            return renderedImage
        } catch {
            // Idempotent cleanup covers cancellation and every failure point.
            await generalFileStore.discardExport(prepared)
            throw error
        }
    }

    private func loadCachedThumbnail(
        for reference: VaultPresentedContentReference,
        presentationStore: VaultFolderPresentationStore
    ) async throws -> VaultSecureRenderedImage? {
        try Task.checkCancellation()
        guard let cachedData = try await presentationStore.loadThumbnail(for: reference) else {
            return nil
        }
        try Task.checkCancellation()

        do {
            let image = try await cachedThumbnailDecoder.decodeThumbnail(from: cachedData)
            try Task.checkCancellation()
            return image
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            // Invalid cache data is regenerated from the authenticated original.
            return nil
        }
    }

    private func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if !isOccupied {
            isOccupied = true
            return true
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(PermitWaiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            isOccupied = false
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    func permitStateForTesting() -> (isOccupied: Bool, waiterCount: Int) {
        (isOccupied, waiters.count)
    }
}
