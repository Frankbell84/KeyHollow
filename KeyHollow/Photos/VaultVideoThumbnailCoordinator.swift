import Combine
import Foundation
import KeyHollowEncryptedVideoAddOn
import KeyHollowGeneralFileSupportAddOn

/// Serializes video-frame decoding so a fast gallery scroll cannot create an
/// unbounded set of media decoders or plaintext temporary files.
@MainActor
final class VaultVideoThumbnailCoordinator: ObservableObject {
    private var isRendering = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func render(
        _ record: VaultGeneralFileRecord,
        using store: VaultGeneralFileStore
    ) async throws -> VaultEncryptedVideoThumbnail {
        await acquirePermit()
        do {
            try Task.checkCancellation()
            let thumbnail = try await renderPrepared(record, using: store)
            releasePermit()
            return thumbnail
        } catch {
            releasePermit()
            throw error
        }
    }

    private func renderPrepared(
        _ record: VaultGeneralFileRecord,
        using store: VaultGeneralFileStore
    ) async throws -> VaultEncryptedVideoThumbnail {
        let prepared = try await store.prepareExport([record])
        do {
            try Task.checkCancellation()
            guard prepared.urls.count == 1,
                  let fileURL = prepared.urls.first else {
                throw VaultVideoPlaybackCoordinatorError.invalidPreparedExport
            }
            let playback = try VaultPreparedVideoPlayback(
                id: record.id,
                descriptor: VaultEncryptedVideoDescriptor(
                    displayName: record.displayName,
                    contentTypeIdentifier: record.contentTypeIdentifier,
                    originalByteCount: record.originalByteCount
                ),
                fileURL: fileURL
            )
            let thumbnail = try await VaultEncryptedVideoThumbnailRenderer.render(playback)
            try Task.checkCancellation()
            await store.discardExport(prepared)
            return thumbnail
        } catch {
            await store.discardExport(prepared)
            throw error
        }
    }

    private func acquirePermit() async {
        if !isRendering {
            isRendering = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releasePermit() {
        guard !waiters.isEmpty else {
            isRendering = false
            return
        }
        waiters.removeFirst().resume()
    }
}
