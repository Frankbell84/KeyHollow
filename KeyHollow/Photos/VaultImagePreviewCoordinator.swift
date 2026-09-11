import Combine
import Foundation
import KeyHollowMediaNavigationAddOn
import KeyHollowSecurePreviewAddOn

struct ActiveVaultImagePreview {
    let id: VaultMediaNavigationID
    let preview: VaultSecureImagePreview
}

/// Application-owned lifetime bridge for one authenticated image preview.
/// The coordinator mirrors the encrypted-video cleanup contract: prepare stays
/// suspended while plaintext is visible, replacement waits for the prior
/// lifetime to finish, and lockAndWait can observe terminal release through the
/// enclosing VaultSession sensitive task.
@MainActor
final class VaultImagePreviewCoordinator: ObservableObject {
    @Published private(set) var active: ActiveVaultImagePreview?

    typealias OriginalDataLoader = @Sendable () async throws -> Data
    typealias SurfaceReleaseWaitObserver = @Sendable () async -> Void

    private struct PreviewOperation {
        let generation: UInt64
        let id: VaultMediaNavigationID
        let task: Task<Void, Error>
        let lifetime: VaultImagePreviewLifetime
    }

    private var generation: UInt64 = 0
    private var operation: PreviewOperation?
    private var activeGeneration: UInt64?
    private let surfaceReleaseWaitObserver: SurfaceReleaseWaitObserver

    init(
        surfaceReleaseWaitObserver: @escaping SurfaceReleaseWaitObserver = {}
    ) {
        self.surfaceReleaseWaitObserver = surfaceReleaseWaitObserver
    }

    func prepare(
        id: VaultMediaNavigationID,
        displayName: String,
        processor: VaultSecureImageProcessor,
        loadOriginalData: @escaping OriginalDataLoader
    ) async throws {
        let (operationGeneration, previousOperation) = beginNewGeneration()

        if let previousOperation {
            do {
                try await previousOperation.task.value
            } catch {
                // Replacement waits for release, not for the cancellation result.
            }
        }

        try requireCurrent(operationGeneration)

        let lifetime = VaultImagePreviewLifetime(
            surfaceReleaseWaitObserver: surfaceReleaseWaitObserver
        )
        let task: Task<Void, Error> = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await self.run(
                id: id,
                displayName: displayName,
                generation: operationGeneration,
                lifetime: lifetime,
                processor: processor,
                loadOriginalData: loadOriginalData
            )
        }
        operation = PreviewOperation(
            generation: operationGeneration,
            id: id,
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
                // Cancellation is the expected release path.
            }
            completeOperationIfCurrent(endingOperation.generation)
        }
    }

    func isPresenting(_ id: VaultMediaNavigationID) -> Bool {
        active?.id == id
    }

    /// Establishes a presentation-surface lease. A late SwiftUI/UIKit mount
    /// after dismissal is rejected, and replacement waits until the attached
    /// UIImageView has synchronously cleared its image reference.
    func imageWillAttach(_ id: VaultMediaNavigationID) -> Bool {
        guard let operation, operation.id == id else { return false }
        return operation.lifetime.beginSurfaceUse()
    }

    func imageDidRelease(_ id: VaultMediaNavigationID) {
        guard let operation, operation.id == id else { return }
        operation.lifetime.endSurfaceUse()
    }

    private func beginNewGeneration() -> (
        generation: UInt64,
        previousOperation: PreviewOperation?
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
        id: VaultMediaNavigationID,
        displayName: String,
        generation operationGeneration: UInt64,
        lifetime: VaultImagePreviewLifetime,
        processor: VaultSecureImageProcessor,
        loadOriginalData: @escaping OriginalDataLoader
    ) async throws {
        do {
            try requireCurrent(operationGeneration)
            let originalData = try await loadOriginalData()
            try requireCurrent(operationGeneration)

            let preview = try await processor.preparePreview(
                id: id.rawValue,
                displayName: displayName,
                originalData: originalData
            )
            try requireCurrent(operationGeneration)

            active = ActiveVaultImagePreview(id: id, preview: preview)
            activeGeneration = operationGeneration

            await waitForDismissal(lifetime)
            await lifetime.waitForSurfaceRelease()
            try Task.checkCancellation()
            clearActiveIfOwned(by: operationGeneration)
        } catch {
            await lifetime.waitForSurfaceRelease()
            clearActiveIfOwned(by: operationGeneration)
            throw error
        }
    }

    private func waitForDismissal(
        _ lifetime: VaultImagePreviewLifetime
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

private final class VaultImagePreviewLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let surfaceReleaseWaitObserver: @Sendable () async -> Void
    private var isFinished = false
    private var isSurfaceAttached = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var surfaceReleaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        surfaceReleaseWaitObserver: @escaping @Sendable () async -> Void
    ) {
        self.surfaceReleaseWaitObserver = surfaceReleaseWaitObserver
    }

    func beginSurfaceUse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, !isSurfaceAttached else { return false }
        isSurfaceAttached = true
        return true
    }

    func endSurfaceUse() {
        lock.lock()
        guard isSurfaceAttached else {
            lock.unlock()
            return
        }
        isSurfaceAttached = false
        let pendingWaiters = surfaceReleaseWaiters
        surfaceReleaseWaiters.removeAll()
        lock.unlock()

        pendingWaiters.forEach { $0.resume() }
    }

    func waitForSurfaceRelease() async {
        if isSurfaceAttachedSnapshot() {
            await surfaceReleaseWaitObserver()
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            if !isSurfaceAttached {
                lock.unlock()
                continuation.resume()
                return
            }
            surfaceReleaseWaiters.append(continuation)
            lock.unlock()
        }
    }

    private func isSurfaceAttachedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSurfaceAttached
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
