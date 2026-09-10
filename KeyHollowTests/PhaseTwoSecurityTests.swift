import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowPhotoCore
@testable import KeyHollowPhotosAdapter

final class PhaseTwoSecurityTests: XCTestCase {
    func testRevokedCapabilityCannotReadOrMutateVaultStore() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let vaultID = UUID()
        let capability = VaultAccessCapability(
            vaultID: vaultID,
            vaultKey: SymmetricKey(size: .bits256)
        )
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            access: capability,
            storageRoot: root
        )
        let record = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )

        capability.revoke()
        XCTAssertTrue(capability.isRevoked)

        do {
            _ = try await store.loadManifest()
            XCTFail("A revoked capability still exposed cached photo metadata")
        } catch VaultAccessError.revoked {}

        do {
            _ = try await store.loadPhoto(record)
            XCTFail("A revoked capability still decrypted a photo")
        } catch VaultAccessError.revoked {}

        do {
            _ = try await store.importPhoto(
                originalData: Data("second".utf8),
                thumbnailData: Data("second thumb".utf8)
            )
            XCTFail("A revoked capability still mutated the vault")
        } catch VaultAccessError.revoked {}
    }

    func testAddOnScopesAreDomainSeparatedAndRevokedWithSessionCapability() throws {
        let capability = VaultAccessCapability(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256)
        )
        let plaintext = Data("general file secret".utf8)
        let manifestDomain = "general-files.manifest.v1"
        let blobDomain = "general-files.blob.v1.\(UUID().uuidString.lowercased())"

        let manifestCiphertext = try capability.sealScopedData(
            plaintext,
            domain: manifestDomain
        )
        let blobCiphertext = try capability.sealScopedData(
            plaintext,
            domain: blobDomain
        )

        XCTAssertNotEqual(manifestCiphertext, blobCiphertext)
        XCTAssertEqual(
            try capability.openScopedData(manifestCiphertext, domain: manifestDomain),
            plaintext
        )
        XCTAssertThrowsError(
            try capability.openScopedData(manifestCiphertext, domain: blobDomain)
        )

        capability.revoke()
        XCTAssertThrowsError(
            try capability.openScopedData(blobCiphertext, domain: blobDomain)
        ) { error in
            XCTAssertEqual(error as? VaultAccessError, .revoked)
        }
    }

    @MainActor
    func testLockRevokesCapabilityCancelsTaskAndWaitsForCleanup() async throws {
        let session = VaultSession()
        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))

        let started = expectation(description: "sensitive work started")
        var sawCancellation = false
        var sawRevocation = false
        let taskID = session.startSensitiveTask { access in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {}
            sawCancellation = Task.isCancelled
            sawRevocation = access.isRevoked
        }
        XCTAssertNotNil(taskID)
        await fulfillment(of: [started])

        await session.lockAndWait()

        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertTrue(sawCancellation)
        XCTAssertTrue(sawRevocation)
    }

    @MainActor
    func testOneSensitiveTaskCanBeCancelledWithoutLockingVault() async throws {
        let session = VaultSession()
        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))

        let started = expectation(description: "preview work started")
        let finished = expectation(description: "preview work cancelled")
        var sawCancellation = false
        let taskID = try XCTUnwrap(session.startSensitiveTask { _ in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {}
            sawCancellation = Task.isCancelled
            finished.fulfill()
        })
        await fulfillment(of: [started])

        session.cancelSensitiveTask(taskID)
        await fulfillment(of: [finished])

        XCTAssertTrue(sawCancellation)
        XCTAssertTrue(session.isUnlocked)
        XCTAssertTrue(session.hasActiveAccess)
    }

    @MainActor
    func testOneProtectedTaskCanBeCancelledAndAwaitedThroughCleanup() async throws {
        let session = VaultSession()
        let started = expectation(description: "protected work started")
        var cleanupFinished = false
        let taskID = session.startProtectedTask {
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            cleanupFinished = true
        }
        await fulfillment(of: [started])

        await session.cancelSensitiveTaskAndWait(taskID)

        XCTAssertTrue(cleanupFinished)
    }

    @MainActor
    func testVaultSwitchPublishesNewAccessOnlyAfterOldCleanupFinishes() async throws {
        let session = VaultSession()
        let oldVaultID = UUID()
        let newVaultID = UUID()
        session.unlock(vaultID: oldVaultID, key: SymmetricKey(size: .bits256))
        let oldCapability = try XCTUnwrap(session.activeVaultContext()?.access)
        let cleanupGate = PhaseTwoAsyncGate()
        let started = expectation(description: "old vault task started")
        let finished = expectation(description: "old vault cleanup finished")

        _ = session.startSensitiveTask { access in
            started.fulfill()
            await cleanupGate.wait()
            XCTAssertTrue(Task.isCancelled)
            XCTAssertTrue(access.isRevoked)
            finished.fulfill()
        }
        await fulfillment(of: [started])

        session.unlock(vaultID: newVaultID, key: SymmetricKey(size: .bits256))

        XCTAssertTrue(oldCapability.isRevoked)
        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)

        await cleanupGate.open()
        await fulfillment(of: [finished])
        await waitForActiveVault(newVaultID, in: session)

        XCTAssertTrue(session.isUnlocked)
        XCTAssertEqual(session.activeVaultID, newVaultID)
        XCTAssertTrue(session.hasActiveAccess)
    }

    @MainActor
    func testSupersedingUnlockKeepsWaitingForOriginalCleanup() async throws {
        let session = VaultSession()
        let originalVaultID = UUID()
        let supersededVaultID = UUID()
        let finalVaultID = UUID()
        session.unlock(vaultID: originalVaultID, key: SymmetricKey(size: .bits256))
        let cleanupGate = PhaseTwoAsyncGate()
        let started = expectation(description: "original vault task started")
        let finished = expectation(description: "original vault cleanup finished")

        _ = session.startSensitiveTask { _ in
            started.fulfill()
            await cleanupGate.wait()
            finished.fulfill()
        }
        await fulfillment(of: [started])

        session.unlock(vaultID: supersededVaultID, key: SymmetricKey(size: .bits256))
        session.unlock(vaultID: finalVaultID, key: SymmetricKey(size: .bits256))

        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)

        await cleanupGate.open()
        await fulfillment(of: [finished])
        await waitForActiveVault(finalVaultID, in: session)

        XCTAssertTrue(session.isUnlocked)
        XCTAssertEqual(session.activeVaultID, finalVaultID)
    }

    @MainActor
    func testLockCancelsPendingUnlockAndReturnsOriginalCleanupBarrier() async {
        let session = VaultSession()
        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))
        let cleanupGate = PhaseTwoAsyncGate()
        let started = expectation(description: "vault task started")
        let finished = expectation(description: "vault cleanup finished")

        _ = session.startSensitiveTask { _ in
            started.fulfill()
            await cleanupGate.wait()
            finished.fulfill()
        }
        await fulfillment(of: [started])

        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))
        let lockBarrier = session.lock()
        await cleanupGate.open()
        await lockBarrier.wait()
        await fulfillment(of: [finished])
        for _ in 0..<10 { await Task.yield() }

        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertFalse(session.hasActiveAccess)
    }

    @MainActor
    func testUnlockAfterLockStillWaitsForRetainedCleanupBarrier() async {
        let session = VaultSession()
        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))
        let cleanupGate = PhaseTwoAsyncGate()
        let started = expectation(description: "original task started")
        let finished = expectation(description: "original task finished")

        _ = session.startSensitiveTask { _ in
            started.fulfill()
            await cleanupGate.wait()
            finished.fulfill()
        }
        await fulfillment(of: [started])

        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))
        _ = session.lock()
        let finalVaultID = UUID()
        session.unlock(vaultID: finalVaultID, key: SymmetricKey(size: .bits256))

        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)

        await cleanupGate.open()
        await fulfillment(of: [finished])
        await waitForActiveVault(finalVaultID, in: session)

        XCTAssertTrue(session.isUnlocked)
        XCTAssertEqual(session.activeVaultID, finalVaultID)
    }

    @MainActor
    func testLockInvalidatesOutstandingUnlockAuthorization() {
        let session = VaultSession()
        let authorization = session.authorizeUnlockCompletion()

        _ = session.lock()
        let accepted = session.completeUnlock(
            vaultID: UUID(),
            key: SymmetricKey(size: .bits256),
            authorization: authorization
        )

        XCTAssertFalse(accepted)
        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertFalse(session.hasActiveAccess)
    }

    @MainActor
    func testUnlockAuthorizationCannotOverwriteCompetingCompletion() {
        let session = VaultSession()
        let authorization = session.authorizeUnlockCompletion()
        let acceptedVaultID = UUID()

        XCTAssertTrue(
            session.completeUnlock(
                vaultID: acceptedVaultID,
                key: SymmetricKey(size: .bits256),
                authorization: authorization
            )
        )
        XCTAssertFalse(
            session.completeUnlock(
                vaultID: UUID(),
                key: SymmetricKey(size: .bits256),
                authorization: authorization
            )
        )
        XCTAssertEqual(session.activeVaultID, acceptedVaultID)
        XCTAssertTrue(session.hasActiveAccess)
    }

    @MainActor
    func testCancelledAsyncCompletionCannotUnlockSession() async {
        let session = VaultSession()
        let authorization = session.authorizeUnlockCompletion()
        let completion = Task { @MainActor in
            session.completeUnlock(
                vaultID: UUID(),
                key: SymmetricKey(size: .bits256),
                authorization: authorization
            )
        }

        completion.cancel()
        let accepted = await completion.value

        XCTAssertFalse(accepted)
        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertFalse(session.hasActiveAccess)
    }

    func testSecurityEpochClearsLockEntryAndOverridesOpenSystemPicker() {
        var digits = "83057291"
        var message: String? = "stale"
        var isWorking = true

        XCTAssertTrue(
            SecurityEpochCredentialPolicy.mustClearDuringSystemInteraction(true),
            "A real background lock must override the picker lifecycle exemption"
        )
        SecurityEpochCredentialPolicy.clearLockEntry(
            digits: &digits,
            message: &message,
            isWorking: &isWorking
        )

        XCTAssertTrue(digits.isEmpty)
        XCTAssertNil(message)
        XCTAssertFalse(isWorking)
    }

    @MainActor
    func testPhotoBatchProcessorNeverHasMoreThanOneFullSizeItemResident() async {
        let inputs = Array(0..<25)
        var activeLoads = 0
        var maximumActiveLoads = 0
        var consumed: [Int] = []
        var failureCount = 0

        await SequentialPhotoBatchProcessor.process(
            inputs,
            load: { value in
                activeLoads += 1
                maximumActiveLoads = max(maximumActiveLoads, activeLoads)
                await Task.yield()
                activeLoads -= 1
                if value == 7 { throw SyntheticFailure.expected }
                return value
            },
            consume: { value in
                consumed.append(value)
                await Task.yield()
            },
            didFail: {
                failureCount += 1
            }
        )

        XCTAssertEqual(maximumActiveLoads, 1)
        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(consumed, inputs.filter { $0 != 7 })
        XCTAssertEqual(SecurePhotoPicker.maximumResidentFullSizePhotos, 1)
        XCTAssertEqual(PhotoLibrarySaveService.maximumResidentFullSizePhotos, 1)
    }

    @MainActor
    func testPhotoBatchProcessorStopsAfterCancellationAndReleasesCurrentItem() async {
        var consumed: [Int] = []
        var loaded: [Int] = []
        let reachedCutoff = expectation(description: "fifth item consumed")

        let task = Task { @MainActor in
            await SequentialPhotoBatchProcessor.process(
                Array(0..<100),
                load: { value in
                    loaded.append(value)
                    return value
                },
                consume: { value in
                    consumed.append(value)
                    if value == 4 {
                        reachedCutoff.fulfill()
                        while !Task.isCancelled { await Task.yield() }
                    }
                },
                didFail: {}
            )
        }

        // The production cancellation source is VaultSession.lock(). This
        // focused test cancels at a deterministic item boundary.
        await fulfillment(of: [reachedCutoff])
        task.cancel()
        await task.value

        XCTAssertEqual(loaded, Array(0...4))
        XCTAssertEqual(consumed, Array(0...4))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowPhaseTwoTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func waitForActiveVault(
        _ vaultID: UUID,
        in session: VaultSession
    ) async {
        for _ in 0..<1_000 {
            if session.activeVaultID == vaultID { return }
            await Task.yield()
        }
    }
}

private enum SyntheticFailure: Error {
    case expected
}

private actor PhaseTwoAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
