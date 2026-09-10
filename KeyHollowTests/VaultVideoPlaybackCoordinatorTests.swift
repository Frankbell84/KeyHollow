import CryptoKit
import Foundation
import XCTest
import KeyHollowCryptoCore
import KeyHollowEncryptedVideoAddOn
import KeyHollowGeneralFileSupportAddOn
@testable import KeyHollow

@MainActor
final class VaultVideoPlaybackCoordinatorTests: XCTestCase {
    func testValidationFinishesBeforeActivePlaybackPublishes() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.MOV")
        let validationBarrier = VideoPlaybackTestBarrier()
        let coordinator = VaultVideoPlaybackCoordinator { playback in
            guard FileManager.default.fileExists(atPath: playback.fileURL.path) else {
                throw VideoPlaybackTestError.missingPreparedPlaintext
            }
            await validationBarrier.enterAndWait()
        }
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        await validationBarrier.waitUntilEntered()

        XCTAssertNil(coordinator.active)
        XCTAssertEqual(fixture.preparedPlaintextFiles().count, 1)

        await validationBarrier.release()
        let active = try await waitForActive(record.id, in: coordinator)
        let playbackURL = active.playback.fileURL

        XCTAssertEqual(active.source, record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playbackURL.path))

        await coordinator.dismissAndWait()
        await assertCancellation(of: task)

        XCTAssertNil(coordinator.active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playbackURL.path))
    }

    func testCancellationAfterPlaintextExistsRemovesItWithoutPublishing() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.mp4")
        let validationBarrier = VideoPlaybackTestBarrier()
        let coordinator = VaultVideoPlaybackCoordinator { _ in
            await validationBarrier.enterAndWait()
        }
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        await validationBarrier.waitUntilEntered()
        XCTAssertEqual(fixture.preparedPlaintextFiles().count, 1)

        task.cancel()
        await validationBarrier.release()
        await assertCancellation(of: task)

        XCTAssertNil(coordinator.active)
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testDismissDuringValidationCannotPublishLatePlayback() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.m4v")
        let validationBarrier = VideoPlaybackTestBarrier()
        let coordinator = VaultVideoPlaybackCoordinator { _ in
            await validationBarrier.enterAndWait()
        }
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        await validationBarrier.waitUntilEntered()
        coordinator.dismiss()
        await validationBarrier.release()
        await assertCancellation(of: task)

        XCTAssertNil(coordinator.active)
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testReplacementWaitsForOldPlaintextCleanupBeforePublishingNewPlayback() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let firstRecord = try await fixture.importFile(named: "First.mp4")
        let secondRecord = try await fixture.importFile(named: "Second.mov")
        let replacementBarrier = VideoPlaybackTestBarrier()
        let coordinator = VaultVideoPlaybackCoordinator { playback in
            if playback.id == secondRecord.id {
                await replacementBarrier.enterAndWait()
            }
        }

        let firstTask = Task { @MainActor in
            try await coordinator.prepare(firstRecord, using: fixture.store)
        }
        let firstActive = try await waitForActive(firstRecord.id, in: coordinator)
        let firstURL = firstActive.playback.fileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        let secondTask = Task { @MainActor in
            try await coordinator.prepare(secondRecord, using: fixture.store)
        }
        await replacementBarrier.waitUntilEntered()
        await assertCancellation(of: firstTask)

        XCTAssertNil(coordinator.active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertEqual(fixture.preparedPlaintextFiles().count, 1)

        await replacementBarrier.release()
        let secondActive = try await waitForActive(secondRecord.id, in: coordinator)
        let secondURL = secondActive.playback.fileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))

        await coordinator.dismissAndWait()
        await assertCancellation(of: secondTask)

        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testRepeatedDismissalIsIdempotent() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.mp4")
        let coordinator = VaultVideoPlaybackCoordinator { _ in }
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        _ = try await waitForActive(record.id, in: coordinator)

        coordinator.dismiss()
        coordinator.dismiss()
        await coordinator.dismissAndWait()
        await assertCancellation(of: task)

        XCTAssertNil(coordinator.active)
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testDismissAndWaitObservesCleanupStartedBySynchronousDismiss() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.mp4")
        let coordinator = VaultVideoPlaybackCoordinator { _ in }
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        let active = try await waitForActive(record.id, in: coordinator)
        let playbackURL = active.playback.fileURL

        coordinator.dismiss()
        await coordinator.dismissAndWait()

        XCTAssertFalse(FileManager.default.fileExists(atPath: playbackURL.path))
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
        await assertCancellation(of: task)
    }

    func testExternalDismissWaitsForPlayerReleaseBeforeDeletingPlaintext() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.mp4")
        let cleanupReachedPlayerBarrier = VideoPlaybackEventCounter()
        let coordinator = VaultVideoPlaybackCoordinator(
            validatePlayable: { _ in },
            playerReleaseWaitObserver: {
                await cleanupReachedPlayerBarrier.record()
            }
        )
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        let active = try await waitForActive(record.id, in: coordinator)
        let playbackURL = active.playback.fileURL
        XCTAssertTrue(coordinator.playerWillAttach(active.playback.id))

        let cleanupCompleted = VideoPlaybackEventCounter()
        let cleanup = Task { @MainActor in
            await coordinator.dismissAndWait()
            await cleanupCompleted.record()
        }
        try await cleanupReachedPlayerBarrier.waitForCount(1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: playbackURL.path))
        var cleanupCompletionCount = await cleanupCompleted.value()
        XCTAssertEqual(cleanupCompletionCount, 0)
        coordinator.playerDidRelease(active.playback.id)
        await cleanup.value
        await assertCancellation(of: task)

        cleanupCompletionCount = await cleanupCompleted.value()
        XCTAssertEqual(cleanupCompletionCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playbackURL.path))
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testPlayerCannotAttachAfterDismissalStarts() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.mov")
        let coordinator = VaultVideoPlaybackCoordinator { _ in }
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        let active = try await waitForActive(record.id, in: coordinator)
        coordinator.dismiss()

        XCTAssertFalse(coordinator.playerWillAttach(active.playback.id))
        await coordinator.dismissAndWait()
        await assertCancellation(of: task)
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testSessionLockAndWaitObservesPlaybackPlaintextCleanup() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.mp4")
        let coordinator = VaultVideoPlaybackCoordinator { _ in }
        let session = VaultSession()
        session.unlock(vaultID: fixture.vaultID, key: SymmetricKey(size: .bits256))

        let taskID = session.startSensitiveTask { _ in
            do {
                try await coordinator.prepare(record, using: fixture.store)
            } catch is CancellationError {
                // Session locking is the expected lifetime boundary.
            } catch {
                XCTFail("Unexpected playback failure: \(error)")
            }
        }
        XCTAssertNotNil(taskID)

        let active = try await waitForActive(record.id, in: coordinator)
        let playbackURL = active.playback.fileURL

        await session.lockAndWait()

        XCTAssertNil(coordinator.active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playbackURL.path))
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testValidationFailureRemovesPreparedPlaintext() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Malformed.mp4")
        let coordinator = VaultVideoPlaybackCoordinator { _ in
            throw VideoPlaybackTestError.rejectedMedia
        }

        do {
            try await coordinator.prepare(record, using: fixture.store)
            XCTFail("Expected prepared media validation to fail")
        } catch {
            XCTAssertEqual(error as? VideoPlaybackTestError, .rejectedMedia)
        }

        XCTAssertNil(coordinator.active)
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }
}

private enum VideoPlaybackTestError: Error, Equatable {
    case activePlaybackTimedOut
    case missingPreparedPlaintext
    case rejectedMedia
}

@MainActor
private func waitForActive(
    _ recordID: UUID,
    in coordinator: VaultVideoPlaybackCoordinator
) async throws -> ActiveVaultVideoPlayback {
    for _ in 0..<1_000 {
        if let active = coordinator.active,
           active.source.id == recordID {
            return active
        }
        await Task.yield()
    }
    throw VideoPlaybackTestError.activePlaybackTimedOut
}

@MainActor
private func assertCancellation(
    of task: Task<Void, Error>,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await task.value
        XCTFail("Expected playback lifetime cancellation", file: file, line: line)
    } catch is CancellationError {
        // Expected.
    } catch {
        XCTFail("Expected CancellationError, got \(error)", file: file, line: line)
    }
}

private actor VideoPlaybackTestBarrier {
    private var didEnter = false
    private var isReleased = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        if !didEnter {
            didEnter = true
            let pendingEntryWaiters = entryWaiters
            entryWaiters.removeAll()
            pendingEntryWaiters.forEach { $0.resume() }
        }

        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        let pendingReleaseWaiters = releaseWaiters
        releaseWaiters.removeAll()
        pendingReleaseWaiters.forEach { $0.resume() }
    }
}

private actor VideoPlaybackEventCounter {
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
                throw VideoPlaybackTestError.activePlaybackTimedOut
            }
            await Task.yield()
        }
    }
}

private struct VideoPlaybackFixture {
    let vaultID: UUID
    let root: URL
    let sourceRoot: URL
    let temporaryRoot: URL
    let store: VaultGeneralFileStore

    init() throws {
        let vaultID = UUID()
        self.vaultID = vaultID
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VideoPlaybackCoordinatorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        temporaryRoot = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        store = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: VideoPlaybackTestAccess(vaultID: vaultID),
            storageRoot: root.appendingPathComponent("Store", isDirectory: true),
            temporaryRoot: temporaryRoot
        )
    }

    func importFile(named name: String) async throws -> VaultGeneralFileRecord {
        let sourceURL = sourceRoot.appendingPathComponent(name)
        try Data(repeating: 0x2a, count: 1_024).write(to: sourceURL, options: .atomic)
        return try await store.importFile(at: sourceURL)
    }

    func preparedPlaintextFiles() -> [URL] {
        let exportRoot = temporaryRoot.appendingPathComponent(
            "KeyHollowGeneralFileExports",
            isDirectory: true
        )
        guard let enumerator = FileManager.default.enumerator(
            at: exportRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                  ).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class VideoPlaybackTestAccess:
    VaultGeneralFileCryptographicAccess,
    @unchecked Sendable
{
    let vaultID: UUID
    private let key = SymmetricKey(size: .bits256)

    init(vaultID: UUID) {
        self.vaultID = vaultID
    }

    func checkAccess() throws {}

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    func open(
        _ ciphertext: Data,
        for purpose: VaultGeneralFileKeyPurpose,
        consuming consumer: (Data) throws -> Void
    ) throws {
        try consumer(open(ciphertext, for: purpose))
    }

    private func derivedKey(for purpose: VaultGeneralFileKeyPurpose) -> SymmetricKey {
        let domain: String
        switch purpose {
        case .manifest:
            domain = "manifest"
        case .file(let id):
            domain = "file.\(id.uuidString.lowercased())"
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(domain.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}
