import CryptoKit
import Foundation
import XCTest
import KeyHollowMediaNavigationAddOn
import KeyHollowSecurePreviewAddOn
@testable import KeyHollow

@MainActor
final class VaultImagePreviewCoordinatorTests: XCTestCase {
    func testValidatedImageRemainsPublishedUntilDismissalCompletes() async throws {
        let coordinator = VaultImagePreviewCoordinator()
        let processor = VaultSecureImageProcessor()
        let id = mediaID(.photo)
        let imageData = try onePixelPNG()
        let task = Task { @MainActor in
            try await coordinator.prepare(
                id: id,
                displayName: "Evidence",
                processor: processor,
                loadOriginalData: { imageData }
            )
        }
        defer {
            task.cancel()
            coordinator.dismiss()
        }

        let active = try await waitForActive(id, in: coordinator)

        XCTAssertEqual(active.id, id)
        XCTAssertEqual(active.preview.displayName, "Evidence")
        XCTAssertEqual(active.preview.originalData, imageData)

        try await waitForDismissal(of: coordinator)
        await assertCancellation(of: task)

        XCTAssertNil(coordinator.active)
    }

    func testDismissDuringOriginalLoadPreventsLatePreviewPublication() async throws {
        let coordinator = VaultImagePreviewCoordinator()
        let processor = VaultSecureImageProcessor()
        let loadBarrier = ImagePreviewTestBarrier()
        let id = mediaID(.generalFile)
        let imageData = try onePixelPNG()
        let task = Task { @MainActor in
            try await coordinator.prepare(
                id: id,
                displayName: "Delayed",
                processor: processor,
                loadOriginalData: {
                    await loadBarrier.enterAndWait()
                    return imageData
                }
            )
        }
        defer {
            task.cancel()
            coordinator.dismiss()
            Task { await loadBarrier.release() }
        }

        try await loadBarrier.waitUntilEntered()
        coordinator.dismiss()
        await loadBarrier.release()
        try await waitForDismissal(of: coordinator)
        await assertCancellation(of: task)

        XCTAssertNil(coordinator.active)
    }

    func testReplacementFinishesPriorLifetimeBeforeLoadingNextImage() async throws {
        let coordinator = VaultImagePreviewCoordinator()
        let processor = VaultSecureImageProcessor()
        let secondLoadBarrier = ImagePreviewTestBarrier()
        let firstID = mediaID(.photo)
        let secondID = mediaID(.generalFile)
        let imageData = try onePixelPNG()
        let firstTask = Task { @MainActor in
            try await coordinator.prepare(
                id: firstID,
                displayName: "First",
                processor: processor,
                loadOriginalData: { imageData }
            )
        }
        defer {
            firstTask.cancel()
            coordinator.dismiss()
            Task { await secondLoadBarrier.release() }
        }
        _ = try await waitForActive(firstID, in: coordinator)

        let secondTask = Task { @MainActor in
            try await coordinator.prepare(
                id: secondID,
                displayName: "Second",
                processor: processor,
                loadOriginalData: {
                    await secondLoadBarrier.enterAndWait()
                    return imageData
                }
            )
        }
        defer { secondTask.cancel() }

        try await secondLoadBarrier.waitUntilEntered()
        await assertCancellation(of: firstTask)
        XCTAssertNil(coordinator.active)

        await secondLoadBarrier.release()
        let secondActive = try await waitForActive(secondID, in: coordinator)
        XCTAssertEqual(secondActive.preview.displayName, "Second")

        try await waitForDismissal(of: coordinator)
        await assertCancellation(of: secondTask)
        XCTAssertNil(coordinator.active)
    }

    func testSessionLockAndWaitObservesImagePreviewRelease() async throws {
        let coordinator = VaultImagePreviewCoordinator()
        let processor = VaultSecureImageProcessor()
        let session = VaultSession()
        let vaultID = UUID()
        let id = mediaID(.photo)
        let imageData = try onePixelPNG()
        session.unlock(vaultID: vaultID, key: SymmetricKey(size: .bits256))

        let taskID = session.startSensitiveTask { capability in
            XCTAssertEqual(capability.vaultID, vaultID)
            do {
                try await coordinator.prepare(
                    id: id,
                    displayName: "Locked",
                    processor: processor,
                    loadOriginalData: { imageData }
                )
            } catch is CancellationError {
                // Locking is the expected lifetime boundary.
            } catch {
                XCTFail("Unexpected image-preview failure: \(error)")
            }
        }
        defer {
            coordinator.dismiss()
            _ = session.lock()
        }
        XCTAssertNotNil(taskID)
        _ = try await waitForActive(id, in: coordinator)

        try await waitForSessionLock(session)

        XCTAssertNil(coordinator.active)
        XCTAssertFalse(session.isUnlocked)
    }

    func testSessionLockWaitsForAttachedImageSurfaceRelease() async throws {
        let cleanupReachedSurfaceBarrier = ImagePreviewEventCounter()
        let lockCompleted = ImagePreviewEventCounter()
        let coordinator = VaultImagePreviewCoordinator(
            surfaceReleaseWaitObserver: {
                await cleanupReachedSurfaceBarrier.record()
            }
        )
        let processor = VaultSecureImageProcessor()
        let session = VaultSession()
        let vaultID = UUID()
        let id = mediaID(.photo)
        let imageData = try onePixelPNG()
        session.unlock(vaultID: vaultID, key: SymmetricKey(size: .bits256))

        let taskID = session.startSensitiveTask { capability in
            XCTAssertEqual(capability.vaultID, vaultID)
            do {
                try await coordinator.prepare(
                    id: id,
                    displayName: "Attached while locking",
                    processor: processor,
                    loadOriginalData: { imageData }
                )
            } catch is CancellationError {
                // Locking is the expected lifetime boundary.
            } catch {
                XCTFail("Unexpected image-preview failure: \(error)")
            }
        }
        defer {
            coordinator.imageDidRelease(id)
            coordinator.dismiss()
            _ = session.lock()
        }
        XCTAssertNotNil(taskID)
        _ = try await waitForActive(id, in: coordinator)
        XCTAssertTrue(coordinator.imageWillAttach(id))

        let lockTask = Task { @MainActor in
            await session.lockAndWait()
            await lockCompleted.record()
        }
        defer { lockTask.cancel() }

        try await cleanupReachedSurfaceBarrier.waitForCount(1)

        var completionCount = await lockCompleted.value()
        XCTAssertEqual(completionCount, 0)
        XCTAssertFalse(session.isUnlocked)

        coordinator.imageDidRelease(id)
        try await lockCompleted.waitForCount(1)
        await lockTask.value

        completionCount = await lockCompleted.value()
        XCTAssertEqual(completionCount, 1)
        XCTAssertNil(coordinator.active)
        XCTAssertFalse(session.isUnlocked)
    }

    func testReplacementWaitsForAttachedImageSurfaceReleaseBeforeLoadingNextImage() async throws {
        let cleanupReachedSurfaceBarrier = ImagePreviewEventCounter()
        let secondLoadStarted = ImagePreviewEventCounter()
        let coordinator = VaultImagePreviewCoordinator(
            surfaceReleaseWaitObserver: {
                await cleanupReachedSurfaceBarrier.record()
            }
        )
        let processor = VaultSecureImageProcessor()
        let firstID = mediaID(.photo)
        let secondID = mediaID(.generalFile)
        let imageData = try onePixelPNG()
        let firstTask = Task { @MainActor in
            try await coordinator.prepare(
                id: firstID,
                displayName: "First attached image",
                processor: processor,
                loadOriginalData: { imageData }
            )
        }
        defer {
            firstTask.cancel()
            coordinator.imageDidRelease(firstID)
            coordinator.imageDidRelease(secondID)
            coordinator.dismiss()
        }
        _ = try await waitForActive(firstID, in: coordinator)
        XCTAssertTrue(coordinator.imageWillAttach(firstID))

        let secondTask = Task { @MainActor in
            try await coordinator.prepare(
                id: secondID,
                displayName: "Second image",
                processor: processor,
                loadOriginalData: {
                    await secondLoadStarted.record()
                    return imageData
                }
            )
        }
        defer { secondTask.cancel() }

        try await cleanupReachedSurfaceBarrier.waitForCount(1)

        let loadStartCount = await secondLoadStarted.value()
        XCTAssertEqual(loadStartCount, 0)
        XCTAssertNil(coordinator.active)

        coordinator.imageDidRelease(firstID)
        try await secondLoadStarted.waitForCount(1)
        let secondActive = try await waitForActive(secondID, in: coordinator)
        XCTAssertEqual(secondActive.preview.displayName, "Second image")
        await assertCancellation(of: firstTask)

        try await waitForDismissal(of: coordinator)
        await assertCancellation(of: secondTask)
        XCTAssertNil(coordinator.active)
    }

    func testDismissWaitsForImageSurfaceRelease() async throws {
        let cleanupReachedSurfaceBarrier = ImagePreviewEventCounter()
        let cleanupCompleted = ImagePreviewEventCounter()
        let coordinator = VaultImagePreviewCoordinator(
            surfaceReleaseWaitObserver: {
                await cleanupReachedSurfaceBarrier.record()
            }
        )
        let processor = VaultSecureImageProcessor()
        let id = mediaID(.photo)
        let imageData = try onePixelPNG()
        let task = Task { @MainActor in
            try await coordinator.prepare(
                id: id,
                displayName: "Attached",
                processor: processor,
                loadOriginalData: { imageData }
            )
        }
        defer {
            task.cancel()
            coordinator.imageDidRelease(id)
            coordinator.dismiss()
        }
        _ = try await waitForActive(id, in: coordinator)
        XCTAssertTrue(coordinator.imageWillAttach(id))

        let cleanup = Task { @MainActor in
            await coordinator.dismissAndWait()
            await cleanupCompleted.record()
        }
        defer { cleanup.cancel() }
        try await cleanupReachedSurfaceBarrier.waitForCount(1)

        var completionCount = await cleanupCompleted.value()
        XCTAssertEqual(completionCount, 0)
        coordinator.imageDidRelease(id)
        try await cleanupCompleted.waitForCount(1)
        await cleanup.value
        await assertCancellation(of: task)

        completionCount = await cleanupCompleted.value()
        XCTAssertEqual(completionCount, 1)
        XCTAssertNil(coordinator.active)
    }

    func testImageSurfaceCannotAttachAfterDismissalStarts() async throws {
        let coordinator = VaultImagePreviewCoordinator()
        let processor = VaultSecureImageProcessor()
        let id = mediaID(.photo)
        let imageData = try onePixelPNG()
        let task = Task { @MainActor in
            try await coordinator.prepare(
                id: id,
                displayName: "Late",
                processor: processor,
                loadOriginalData: { imageData }
            )
        }
        defer {
            task.cancel()
            coordinator.dismiss()
        }
        _ = try await waitForActive(id, in: coordinator)

        coordinator.dismiss()

        XCTAssertFalse(coordinator.imageWillAttach(id))
        try await waitForDismissal(of: coordinator)
        await assertCancellation(of: task)
        XCTAssertNil(coordinator.active)
    }

    func testRepeatedDismissalIsIdempotent() async throws {
        let coordinator = VaultImagePreviewCoordinator()
        let processor = VaultSecureImageProcessor()
        let id = mediaID(.photo)
        let imageData = try onePixelPNG()
        let task = Task { @MainActor in
            try await coordinator.prepare(
                id: id,
                displayName: "Evidence",
                processor: processor,
                loadOriginalData: { imageData }
            )
        }
        defer {
            task.cancel()
            coordinator.dismiss()
        }
        _ = try await waitForActive(id, in: coordinator)

        coordinator.dismiss()
        coordinator.dismiss()
        try await waitForDismissal(of: coordinator)
        await assertCancellation(of: task)

        XCTAssertNil(coordinator.active)
    }

    private func onePixelPNG() throws -> Data {
        try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
    }

    private func mediaID(
        _ source: VaultMediaNavigationSource
    ) -> VaultMediaNavigationID {
        VaultMediaNavigationID(source: source, rawValue: UUID())
    }
}

private enum ImagePreviewCoordinatorTestError: Error, Sendable {
    case activePreviewTimedOut
    case barrierTimedOut
    case eventTimedOut
    case taskCompletionTimedOut
}

@MainActor
private func waitForDismissal(
    of coordinator: VaultImagePreviewCoordinator
) async throws {
    let completed = ImagePreviewEventCounter()
    let cleanup = Task { @MainActor in
        await coordinator.dismissAndWait()
        await completed.record()
    }
    defer {
        cleanup.cancel()
        coordinator.dismiss()
    }

    try await completed.waitForCount(1)
    await cleanup.value
}

@MainActor
private func waitForSessionLock(
    _ session: VaultSession
) async throws {
    let completed = ImagePreviewEventCounter()
    let lockTask = Task { @MainActor in
        await session.lockAndWait()
        await completed.record()
    }
    defer {
        lockTask.cancel()
        _ = session.lock()
    }

    try await completed.waitForCount(1)
    await lockTask.value
}

@MainActor
private func waitForActive(
    _ id: VaultMediaNavigationID,
    in coordinator: VaultImagePreviewCoordinator,
    timeout: Duration = .seconds(2)
) async throws -> ActiveVaultImagePreview {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if let active = coordinator.active, active.id == id {
            return active
        }
        await Task.yield()
    }
    throw ImagePreviewCoordinatorTestError.activePreviewTimedOut
}

@MainActor
private func assertCancellation(
    of task: Task<Void, Error>,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let resultRecorder = ImagePreviewTaskResultRecorder()
    let observer = Task { @MainActor in
        do {
            try await task.value
            await resultRecorder.record(.completed)
        } catch is CancellationError {
            await resultRecorder.record(.cancelled)
        } catch {
            await resultRecorder.record(.failed(String(describing: error)))
        }
    }
    defer { observer.cancel() }

    do {
        let result = try await resultRecorder.waitForResult()
        switch result {
        case .completed:
            XCTFail("Expected image-preview lifetime cancellation", file: file, line: line)
        case .cancelled:
            break
        case .failed(let description):
            XCTFail("Expected CancellationError, got \(description)", file: file, line: line)
        }
    } catch {
        task.cancel()
        XCTFail(
            "Timed out waiting for image-preview lifetime cancellation",
            file: file,
            line: line
        )
    }
}

private enum ImagePreviewObservedTaskResult: Sendable {
    case completed
    case cancelled
    case failed(String)
}

private actor ImagePreviewTaskResultRecorder {
    private var result: ImagePreviewObservedTaskResult?

    func record(_ result: ImagePreviewObservedTaskResult) {
        guard self.result == nil else { return }
        self.result = result
    }

    func waitForResult(
        timeout: Duration = .seconds(2)
    ) async throws -> ImagePreviewObservedTaskResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while result == nil {
            guard clock.now < deadline else {
                throw ImagePreviewCoordinatorTestError.taskCompletionTimedOut
            }
            await Task.yield()
        }
        return result!
    }
}

private actor ImagePreviewTestBarrier {
    private var didEnter = false
    private var isReleased = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        didEnter = true

        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered(
        timeout: Duration = .seconds(2)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !didEnter {
            guard clock.now < deadline else {
                throw ImagePreviewCoordinatorTestError.barrierTimedOut
            }
            await Task.yield()
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        let pending = releaseWaiters
        releaseWaiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ImagePreviewEventCounter {
    private var count = 0

    func record() {
        count += 1
    }

    func value() -> Int {
        count
    }

    func waitForCount(
        _ target: Int,
        timeout: Duration = .seconds(2)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while count < target {
            guard clock.now < deadline else {
                throw ImagePreviewCoordinatorTestError.eventTimedOut
            }
            await Task.yield()
        }
    }
}
