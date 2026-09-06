import Combine
import Foundation
import KeyHollowEncryptedVideoAddOn
import KeyHollowGeneralFileSupportAddOn

enum VaultVideoPlaybackCoordinatorError: Error, Equatable {
    case invalidPreparedExport
}

struct ActiveVaultVideoPlayback: Identifiable {
    let source: VaultGeneralFileRecord
    let playback: VaultPreparedVideoPlayback
    fileprivate let preparedExport: PreparedGeneralFileExport

    var id: UUID { playback.id }
}

/// Application-owned bridge between authenticated encrypted storage and the
/// capability-free video player. This is the sole owner of the prepared
/// plaintext lifetime and never exposes a store to the video add-on.
@MainActor
final class VaultVideoPlaybackCoordinator: ObservableObject {
    @Published private(set) var active: ActiveVaultVideoPlayback?

    private var cleanupStore: VaultGeneralFileStore?

    func prepare(
        _ record: VaultGeneralFileRecord,
        using store: VaultGeneralFileStore
    ) async throws {
        await dismissAndWait()
        try Task.checkCancellation()

        let prepared = try await store.prepareExport([record])
        do {
            try Task.checkCancellation()
            guard prepared.urls.count == 1,
                  let fileURL = prepared.urls.first else {
                throw VaultVideoPlaybackCoordinatorError.invalidPreparedExport
            }

            let descriptor = VaultEncryptedVideoDescriptor(
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                originalByteCount: record.originalByteCount
            )
            let playback = try VaultPreparedVideoPlayback(
                id: record.id,
                descriptor: descriptor,
                fileURL: fileURL
            )
            try Task.checkCancellation()

            cleanupStore = store
            active = ActiveVaultVideoPlayback(
                source: record,
                playback: playback,
                preparedExport: prepared
            )
        } catch {
            await store.discardExport(prepared)
            throw error
        }
    }

    /// Starts best-effort cleanup for synchronous view-lifecycle callbacks.
    /// `dismissAndWait()` is used whenever the vault session itself changes.
    func dismiss() {
        guard let cleanup = takeCleanup() else { return }
        Task {
            await cleanup.store.discardExport(cleanup.export)
        }
    }

    func dismissAndWait() async {
        guard let cleanup = takeCleanup() else { return }
        await cleanup.store.discardExport(cleanup.export)
    }

    private func takeCleanup() -> (
        store: VaultGeneralFileStore,
        export: PreparedGeneralFileExport
    )? {
        defer {
            active = nil
            cleanupStore = nil
        }
        guard let active, let cleanupStore else { return nil }
        return (cleanupStore, active.preparedExport)
    }
}
