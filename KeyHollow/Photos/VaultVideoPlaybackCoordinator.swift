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

    var id: UUID { playback.id }
}

/// Application-owned bridge between authenticated encrypted storage and the
/// capability-free video player. The coordinator owns both the protected
/// plaintext lifetime and the task that keeps that lifetime registered with
/// the unlocked vault session.
@MainActor
final class VaultVideoPlaybackCoordinator: ObservableObject {
    typealias PlaybackValidator =
        @Sendable (VaultPreparedVideoPlayback) async throws -> Void
    typealias PlayerReleaseWaitObserver = @Sendable () async -> Void

    @Published private(set) var active: ActiveVaultVideoPlayback?

    private struct PlaybackOperation {
        let generation: UInt64
        let recordID: UUID
        let task: Task<Void, Error>
        let lifetime: VaultVideoPlaybackLifetime
    }

    private let validatePlayable: PlaybackValidator
    private let playerReleaseWaitObserver: PlayerReleaseWaitObserver
    private var generation: UInt64 = 0
    private var operation: PlaybackOperation?
    private var activeGeneration: UInt64?

    init(
        validatePlayable: @escaping PlaybackValidator = { playback in
            try await playback.validatePlayable()
        },
        playerReleaseWaitObserver: @escaping PlayerReleaseWaitObserver = {}
    ) {
        self.validatePlayable = validatePlayable
        self.playerReleaseWaitObserver = playerReleaseWaitObserver
    }

    /// Prepares and validates one app-owned plaintext export, publishes it for
    /// playback, and then remains suspended until dismissal or cancellation.
    ///
    /// Call this from VaultSession.startSensitiveTask. Because this method
    /// does not return while playback is active, VaultSession.lockAndWait()
    /// observes the final plaintext cleanup before its registered task ends.
    func prepare(
        _ record: VaultGeneralFileRecord,
        using store: VaultGeneralFileStore
    ) async throws {
        let (operationGeneration, previousOperation) = beginNewGeneration()

        if let previousOperation {
            do {
                try await previousOperation.task.value
            } catch {
                // Replacement waits for the previous plaintext cleanup, not
                // for its cancellation result.
            }
        }

        try requireCurrent(operationGeneration)

        let lifetime = VaultVideoPlaybackLifetime(
            playerReleaseWaitObserver: playerReleaseWaitObserver
        )
        let task: Task<Void, Error> = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await self.run(
                record,
                using: store,
                generation: operationGeneration,
                lifetime: lifetime
            )
        }
        operation = PlaybackOperation(
            generation: operationGeneration,
            recordID: record.id,
            task: task,
            lifetime: lifetime
        )

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
                lifetime.finish()
            }
        } catch {
            completeOperationIfCurrent(operationGeneration)
            throw error
        }

        completeOperationIfCurrent(operationGeneration)
    }

    /// Invalidates the current generation immediately and starts cleanup.
    /// dismissAndWait() is the session-transition boundary when the caller
    /// must observe that cleanup before continuing.
    func dismiss() {
        generation &+= 1
        active = nil
        activeGeneration = nil
        operation?.task.cancel()
        operation?.lifetime.finish()
    }

    func dismissAndWait() async {
        let endingOperation = operation
        dismiss()

        if let endingOperation {
            do {
                try await endingOperation.task.value
            } catch {
                // Cancellation is the normal dismissal path. The worker does
                // not finish until its prepared export has been discarded.
            }
            completeOperationIfCurrent(endingOperation.generation)
        }
    }

    /// Establishes an explicit decoder/file-handle lease. A late SwiftUI mount
    /// after dismissal is rejected, while an attached player makes plaintext
    /// cleanup wait until the module confirms AVPlayer has released its item.
    func playerWillAttach(_ playbackID: UUID) -> Bool {
        guard let operation, operation.recordID == playbackID else {
            return false
        }
        return operation.lifetime.beginPlayerUse()
    }

    func playerDidRelease(_ playbackID: UUID) {
        guard let operation, operation.recordID == playbackID else { return }
        operation.lifetime.endPlayerUse()
    }

    private func beginNewGeneration() -> (
        generation: UInt64,
        previousOperation: PlaybackOperation?
    ) {
        generation &+= 1
        let operationGeneration = generation
        let previousOperation = operation

        active = nil
        activeGeneration = nil
        previousOperation?.task.cancel()
        previousOperation?.lifetime.finish()

        return (operationGeneration, previousOperation)
    }

    private func run(
        _ record: VaultGeneralFileRecord,
        using store: VaultGeneralFileStore,
        generation operationGeneration: UInt64,
        lifetime: VaultVideoPlaybackLifetime
    ) async throws {
        try requireCurrent(operationGeneration)
        let prepared = try await store.prepareExport([record])

        do {
            try requireCurrent(operationGeneration)
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

            try await validatePlayable(playback)
            try requireCurrent(operationGeneration)

            active = ActiveVaultVideoPlayback(
                source: record,
                playback: playback
            )
            activeGeneration = operationGeneration

            await waitForDismissal(lifetime)
            await lifetime.waitForPlayerRelease()
            try Task.checkCancellation()
            await store.discardExport(prepared)
            clearActiveIfOwned(by: operationGeneration)
        } catch {
            await lifetime.waitForPlayerRelease()
            await store.discardExport(prepared)
            clearActiveIfOwned(by: operationGeneration)
            throw error
        }
    }

    private func waitForDismissal(
        _ lifetime: VaultVideoPlaybackLifetime
    ) async {
        await withTaskCancellationHandler {
            await lifetime.wait()
        } onCancel: {
            lifetime.finish()
        }
    }

    private func requireCurrent(_ operationGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard generation == operationGeneration else {
            throw CancellationError()
        }
    }

    private func clearActiveIfOwned(by operationGeneration: UInt64) {
        guard activeGeneration == operationGeneration else { return }
        active = nil
        activeGeneration = nil
    }

    private func completeOperationIfCurrent(_ operationGeneration: UInt64) {
        guard operation?.generation == operationGeneration else { return }
        operation = nil
        clearActiveIfOwned(by: operationGeneration)
    }
}

/// A lock-backed one-shot signal lets synchronous lifecycle callbacks wake an
/// async playback task without introducing an unstructured cleanup task.
private final class VaultVideoPlaybackLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let playerReleaseWaitObserver: @Sendable () async -> Void
    private var isFinished = false
    private var isPlayerAttached = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var playerReleaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(playerReleaseWaitObserver: @escaping @Sendable () async -> Void) {
        self.playerReleaseWaitObserver = playerReleaseWaitObserver
    }

    func beginPlayerUse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, !isPlayerAttached else { return false }
        isPlayerAttached = true
        return true
    }

    func endPlayerUse() {
        lock.lock()
        guard isPlayerAttached else {
            lock.unlock()
            return
        }
        isPlayerAttached = false
        let pendingWaiters = playerReleaseWaiters
        playerReleaseWaiters.removeAll()
        lock.unlock()

        pendingWaiters.forEach { $0.resume() }
    }

    func waitForPlayerRelease() async {
        if isPlayerAttachedSnapshot() {
            await playerReleaseWaitObserver()
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            if !isPlayerAttached {
                lock.unlock()
                continuation.resume()
                return
            }
            playerReleaseWaiters.append(continuation)
            lock.unlock()
        }
    }

    private func isPlayerAttachedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPlayerAttached
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isFinished {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let pendingWaiters = waiters
        waiters.removeAll()
        lock.unlock()

        pendingWaiters.forEach { $0.resume() }
    }
}
