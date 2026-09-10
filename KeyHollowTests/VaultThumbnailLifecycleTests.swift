import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowFolderPresentationAddOn
@testable import KeyHollowGeneralFileSupportAddOn

final class VaultThumbnailLifecycleTests: XCTestCase {
    func testFilesImageAndVideoColdMissesShareExactlyOneLane() async throws {
        let probe = ThumbnailColdWorkProbe()
        let pipeline = VaultGeneralFileThumbnailPipeline(
            hooks: VaultGeneralFileThumbnailPipelineHooks(
                didAcquireColdPermit: { await probe.enterAndWait() }
            )
        )

        let imageTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { nil as String? },
                generate: { "files-image" }
            )
        }
        await probe.waitForEntryCount(1)

        let videoTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { nil as String? },
                generate: { "video" }
            )
        }
        let queued = await waitForWaiterCount(1, in: pipeline)
        XCTAssertTrue(queued)
        var maximumConcurrentCount = await probe.maximumConcurrentCount()
        XCTAssertEqual(maximumConcurrentCount, 1)

        await probe.releaseNext()
        await probe.waitForEntryCount(2)
        maximumConcurrentCount = await probe.maximumConcurrentCount()
        XCTAssertEqual(maximumConcurrentCount, 1)
        await probe.releaseNext()

        let imageValue = try await imageTask.value
        let videoValue = try await videoTask.value
        let values = [imageValue, videoValue]
        XCTAssertEqual(Set(values), Set(["files-image", "video"]))
        maximumConcurrentCount = await probe.maximumConcurrentCount()
        XCTAssertEqual(maximumConcurrentCount, 1)
    }

    func testEncryptedCacheHitCompletesWhileColdMissIsBlocked() async throws {
        let missStarted = ThumbnailEventCounter()
        let missGate = ThumbnailTestGate()
        let unexpectedGeneration = ThumbnailCounter()
        let pipeline = VaultGeneralFileThumbnailPipeline()

        let missTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { nil as Int? },
                generate: {
                    await missStarted.record()
                    await missGate.wait()
                    return 7
                }
            )
        }
        await missStarted.waitForCount(1)

        let cachedValue = try await pipeline.loadOrGenerate(
            loadCached: { 41 },
            generate: {
                await unexpectedGeneration.increment()
                return -1
            }
        )

        XCTAssertEqual(cachedValue, 41)
        let unexpectedGenerationCount = await unexpectedGeneration.value()
        XCTAssertEqual(unexpectedGenerationCount, 0)
        await missGate.open()
        let missValue = try await missTask.value
        XCTAssertEqual(missValue, 7)
    }

    func testQueuedDuplicateRechecksCacheInsteadOfRegenerating() async throws {
        let cache = ThumbnailIntCache()
        let firstGenerationStarted = ThumbnailEventCounter()
        let firstGenerationGate = ThumbnailTestGate()
        let pipeline = VaultGeneralFileThumbnailPipeline()

        let firstTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { await cache.load() },
                generate: {
                    await firstGenerationStarted.record()
                    await firstGenerationGate.wait()
                    await cache.generateAndStore(73)
                    return 73
                }
            )
        }
        await firstGenerationStarted.waitForCount(1)

        let duplicateTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { await cache.load() },
                generate: {
                    await cache.generateAndStore(99)
                    return 99
                }
            )
        }
        let queued = await waitForWaiterCount(1, in: pipeline)
        XCTAssertTrue(queued)

        await firstGenerationGate.open()
        let firstValue = try await firstTask.value
        let duplicateValue = try await duplicateTask.value
        XCTAssertEqual(firstValue, 73)
        XCTAssertEqual(duplicateValue, 73)

        let snapshot = await cache.snapshot()
        XCTAssertEqual(snapshot.generationCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.loadCount, 3)
    }

    func testCancelledQueuedRequestIsRemovedAndCannotLeakPermit() async throws {
        let firstGenerationStarted = ThumbnailEventCounter()
        let firstGenerationGate = ThumbnailTestGate()
        let pipeline = VaultGeneralFileThumbnailPipeline()

        let firstTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { nil as Int? },
                generate: {
                    await firstGenerationStarted.record()
                    await firstGenerationGate.wait()
                    return 1
                }
            )
        }
        await firstGenerationStarted.waitForCount(1)

        let cancelledTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { nil as Int? },
                generate: { 2 }
            )
        }
        var reachedExpectedWaiterCount = await waitForWaiterCount(1, in: pipeline)
        XCTAssertTrue(reachedExpectedWaiterCount)

        cancelledTask.cancel()
        reachedExpectedWaiterCount = await waitForWaiterCount(0, in: pipeline)
        XCTAssertTrue(reachedExpectedWaiterCount)
        do {
            _ = try await cancelledTask.value
            XCTFail("A cancelled queued thumbnail request unexpectedly ran")
        } catch is CancellationError {
            // Expected.
        }

        let nextTask = Task {
            try await pipeline.loadOrGenerate(
                loadCached: { nil as Int? },
                generate: { 3 }
            )
        }
        reachedExpectedWaiterCount = await waitForWaiterCount(1, in: pipeline)
        XCTAssertTrue(reachedExpectedWaiterCount)

        await firstGenerationGate.open()
        let firstValue = try await firstTask.value
        let nextValue = try await nextTask.value
        XCTAssertEqual(firstValue, 1)
        XCTAssertEqual(nextValue, 3)

        let finalState = await pipeline.permitStateForTesting()
        XCTAssertFalse(finalState.isOccupied)
        XCTAssertEqual(finalState.waiterCount, 0)
    }

    func testCancellationAfterVideoPlaintextCreationDeletesExportAndSkipsCache() async throws {
        let sandbox = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let sourceRoot = sandbox.appendingPathComponent("Source", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("GeneralFiles", isDirectory: true)
        let temporaryRoot = sandbox.appendingPathComponent("Temporary", isDirectory: true)
        let presentationRoot = sandbox.appendingPathComponent("Presentation", isDirectory: true)
        for directory in [sourceRoot, storageRoot, temporaryRoot, presentationRoot] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let sourceURL = sourceRoot.appendingPathComponent("sample.mp4")
        try Data("malformed but policy-eligible video".utf8).write(to: sourceURL)

        let vaultID = UUID()
        let capability = VaultAccessCapability(
            vaultID: vaultID,
            vaultKey: SymmetricKey(size: .bits256)
        )
        let generalFileStore = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: SessionGeneralFileAccess(capability: capability),
            storageRoot: storageRoot,
            temporaryRoot: temporaryRoot
        )
        let presentationStore = try VaultFolderPresentationStore(
            vaultID: vaultID,
            access: SessionFolderPresentationAccess(capability: capability),
            storageRoot: presentationRoot
        )
        let importedRecord = try await generalFileStore.importFile(at: sourceURL)
        let videoRecord = VaultGeneralFileRecord(
            id: importedRecord.id,
            importedAt: importedRecord.importedAt,
            displayName: importedRecord.displayName,
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: importedRecord.originalByteCount,
            blobName: importedRecord.blobName
        )

        let plaintextCreated = ThumbnailEventCounter()
        let plaintextGate = ThumbnailTestGate()
        let pipeline = VaultGeneralFileThumbnailPipeline(
            hooks: VaultGeneralFileThumbnailPipelineHooks(
                didPrepareVideoPlaintext: {
                    await plaintextCreated.record()
                    await plaintextGate.wait()
                }
            )
        )
        let thumbnailTask = Task {
            try await pipeline.image(
                for: videoRecord,
                generalFileStore: generalFileStore,
                presentationStore: presentationStore
            )
        }

        await plaintextCreated.waitForCount(1)
        let exportContainer = temporaryRoot.appendingPathComponent(
            "KeyHollowGeneralFileExports",
            isDirectory: true
        )
        let stagedExports = try FileManager.default.contentsOfDirectory(
            at: exportContainer,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(stagedExports.count, 1)
        let stagedExport = try XCTUnwrap(stagedExports.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedExport.path))

        thumbnailTask.cancel()
        await plaintextGate.open()
        do {
            _ = try await thumbnailTask.value
            XCTFail("Cancelled video thumbnail work unexpectedly completed")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedExport.path))
        let reference = VaultPresentedContentReference(
            kind: .generalFile,
            id: videoRecord.id
        )
        let cachedThumbnail = try await presentationStore.loadThumbnail(for: reference)
        XCTAssertNil(cachedThumbnail)

        let nextValue = try await pipeline.loadOrGenerate(
            loadCached: { nil as Int? },
            generate: { 17 }
        )
        XCTAssertEqual(nextValue, 17)
        let finalState = await pipeline.permitStateForTesting()
        XCTAssertFalse(finalState.isOccupied)
        XCTAssertEqual(finalState.waiterCount, 0)
    }

    @MainActor
    func testLockAndWaitObservesRegisteredThumbnailCleanup() async throws {
        let sandbox = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let sourceRoot = sandbox.appendingPathComponent("Source", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("GeneralFiles", isDirectory: true)
        let temporaryRoot = sandbox.appendingPathComponent("Temporary", isDirectory: true)
        let presentationRoot = sandbox.appendingPathComponent("Presentation", isDirectory: true)
        for directory in [sourceRoot, storageRoot, temporaryRoot, presentationRoot] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let sourceURL = sourceRoot.appendingPathComponent("lock-test.mp4")
        try Data("policy-eligible video blocked before decoding".utf8).write(to: sourceURL)

        let vaultID = UUID()
        let vaultKey = SymmetricKey(size: .bits256)
        let session = VaultSession()
        session.unlock(vaultID: vaultID, key: vaultKey)
        let context = try XCTUnwrap(session.activeVaultContext())
        let generalFileStore = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: SessionGeneralFileAccess(capability: context.access),
            storageRoot: storageRoot,
            temporaryRoot: temporaryRoot
        )
        let presentationStore = try VaultFolderPresentationStore(
            vaultID: vaultID,
            access: SessionFolderPresentationAccess(capability: context.access),
            storageRoot: presentationRoot
        )
        let importedRecord = try await generalFileStore.importFile(at: sourceURL)
        let videoRecord = VaultGeneralFileRecord(
            id: importedRecord.id,
            importedAt: importedRecord.importedAt,
            displayName: importedRecord.displayName,
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: importedRecord.originalByteCount,
            blobName: importedRecord.blobName
        )

        let plaintextCreated = ThumbnailEventCounter()
        let plaintextGate = ThumbnailTestGate()
        let callerCompleted = ThumbnailEventCounter()
        let lockCompleted = ThumbnailEventCounter()
        let pipeline = VaultGeneralFileThumbnailPipeline(
            hooks: VaultGeneralFileThumbnailPipelineHooks(
                didPrepareVideoPlaintext: {
                    await plaintextCreated.record()
                    await plaintextGate.wait()
                }
            )
        )
        let caller = Task { @MainActor in
            await session.performSensitiveTask { capability in
                guard capability.vaultID == vaultID else {
                    XCTFail("Thumbnail work received the wrong vault capability")
                    return
                }
                do {
                    _ = try await pipeline.image(
                        for: videoRecord,
                        generalFileStore: generalFileStore,
                        presentationStore: presentationStore
                    )
                    XCTFail("Locked video thumbnail work unexpectedly completed")
                } catch is CancellationError {
                    // Session locking is the expected lifecycle boundary.
                } catch {
                    XCTFail("Unexpected thumbnail failure: \(error)")
                }
            }
            await callerCompleted.record()
        }
        defer { caller.cancel() }

        let didCreatePlaintext = await waitForEventCount(
            1,
            in: plaintextCreated
        )
        XCTAssertTrue(
            didCreatePlaintext,
            "Timed out before video thumbnail plaintext was prepared"
        )
        guard didCreatePlaintext else {
            await plaintextGate.open()
            session.lock()
            return
        }

        let exportContainer = temporaryRoot.appendingPathComponent(
            "KeyHollowGeneralFileExports",
            isDirectory: true
        )
        let stagedExports = try FileManager.default.contentsOfDirectory(
            at: exportContainer,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(stagedExports.count, 1)
        let stagedExport = try XCTUnwrap(stagedExports.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedExport.path))

        let lockTask = Task { @MainActor in
            await session.lockAndWait()
            await lockCompleted.record()
        }
        defer { lockTask.cancel() }

        let didLock = await waitUntilSessionLocks(session)
        XCTAssertTrue(didLock, "Timed out before lockAndWait revoked the session")
        XCTAssertFalse(session.isUnlocked)
        let lockCompletionCountBeforeRelease = await lockCompleted.value()
        XCTAssertEqual(lockCompletionCountBeforeRelease, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedExport.path))

        await plaintextGate.open()
        let didFinishLock = await waitForEventCount(1, in: lockCompleted)
        let didFinishCaller = await waitForEventCount(1, in: callerCompleted)
        XCTAssertTrue(
            didFinishLock,
            "lockAndWait did not observe terminal thumbnail cleanup"
        )
        XCTAssertTrue(
            didFinishCaller,
            "The registered thumbnail caller did not finish after cleanup"
        )
        if didFinishLock {
            await lockTask.value
        }
        if didFinishCaller {
            await caller.value
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedExport.path))
        let presentationFiles = try FileManager.default.subpathsOfDirectory(
            atPath: presentationRoot.path
        )
        XCTAssertFalse(
            presentationFiles.contains {
                URL(fileURLWithPath: $0).pathExtension.lowercased() == "kht"
            },
            "Cancelled thumbnail work persisted an encrypted thumbnail blob"
        )
        let finalState = await pipeline.permitStateForTesting()
        XCTAssertFalse(finalState.isOccupied)
        XCTAssertEqual(finalState.waiterCount, 0)
        XCTAssertFalse(session.hasActiveAccess)
    }

    @MainActor
    private func waitForEventCount(
        _ expectedCount: Int,
        in counter: ThumbnailEventCounter,
        timeout: Duration = .seconds(3)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await counter.value() >= expectedCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await counter.value() >= expectedCount
    }

    @MainActor
    private func waitUntilSessionLocks(
        _ session: VaultSession,
        timeout: Duration = .seconds(3)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if !session.isUnlocked {
                return true
            }
            await Task.yield()
        }
        return !session.isUnlocked
    }

    private func waitForWaiterCount(
        _ expectedCount: Int,
        in pipeline: VaultGeneralFileThumbnailPipeline
    ) async -> Bool {
        for _ in 0..<10_000 {
            let state = await pipeline.permitStateForTesting()
            if state.waiterCount == expectedCount {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowVaultThumbnailLifecycleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private actor ThumbnailTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ThumbnailEventCounter {
    private struct Waiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var count = 0
    private var waiters: [Waiter] = []

    func record() {
        count += 1
        let ready = waiters.filter { count >= $0.target }
        waiters.removeAll { count >= $0.target }
        ready.forEach { $0.continuation.resume() }
    }

    func value() -> Int {
        count
    }

    func waitForCount(_ target: Int) async {
        guard count < target else { return }
        await withCheckedContinuation { continuation in
            if count >= target {
                continuation.resume()
            } else {
                waiters.append(Waiter(target: target, continuation: continuation))
            }
        }
    }
}

private actor ThumbnailCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor ThumbnailColdWorkProbe {
    private struct EntryWaiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var activeCount = 0
    private var maximumActiveCount = 0
    private var entryCount = 0
    private var entryWaiters: [EntryWaiter] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        entryCount += 1
        let ready = entryWaiters.filter { entryCount >= $0.target }
        entryWaiters.removeAll { entryCount >= $0.target }
        ready.forEach { $0.continuation.resume() }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
        activeCount -= 1
    }

    func waitForEntryCount(_ target: Int) async {
        guard entryCount < target else { return }
        await withCheckedContinuation { continuation in
            if entryCount >= target {
                continuation.resume()
            } else {
                entryWaiters.append(EntryWaiter(target: target, continuation: continuation))
            }
        }
    }

    func releaseNext() {
        guard !releaseWaiters.isEmpty else { return }
        releaseWaiters.removeFirst().resume()
    }

    func maximumConcurrentCount() -> Int {
        maximumActiveCount
    }
}

private actor ThumbnailIntCache {
    private var storedValue: Int?
    private var loads = 0
    private var generations = 0

    func load() -> Int? {
        loads += 1
        return storedValue
    }

    func generateAndStore(_ value: Int) {
        generations += 1
        storedValue = value
    }

    func snapshot() -> (loadCount: Int, generationCount: Int) {
        (loads, generations)
    }
}
