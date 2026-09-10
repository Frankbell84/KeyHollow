import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowPhotoCore
@testable import KeyHollowVaultCore

final class VaultLifecycleBaselineTests: XCTestCase {
    @MainActor
    func testCompleteVaultLifecyclePersistsAndRemovesAccess() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }

        var service = try fixture.makeService()
        var hasVaults = try await service.hasAnyVaults()
        XCTAssertFalse(hasVaults)

        let created = try await service.createVault(passcode: fixture.originalPasscode)
        hasVaults = try await service.hasAnyVaults()
        XCTAssertTrue(hasVaults)

        let vaultPhotoRoot = fixture.photoRoot.appendingPathComponent(
            created.vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        let photoStore = try VaultPhotoStore(
            vaultID: created.vaultID,
            vaultKey: created.vaultKey,
            storageRoot: vaultPhotoRoot
        )
        let photo = try await photoStore.importPhoto(
            originalData: Data("lifecycle original".utf8),
            thumbnailData: Data("lifecycle thumbnail".utf8)
        )
        let reopenedPhoto = try await photoStore.loadPhoto(photo)
        XCTAssertEqual(reopenedPhoto, Data("lifecycle original".utf8))

        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)
        XCTAssertTrue(session.isUnlocked)
        session.lock()
        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertFalse(session.hasActiveAccess)

        // A new service instance models terminating and relaunching the app.
        service = try fixture.makeService()
        hasVaults = try await service.hasAnyVaults()
        XCTAssertTrue(hasVaults)
        XCTAssertTrue(fixture.credentialFiles().contains { $0.pathExtension == "khv" })
        XCTAssertFalse(fixture.credentialFiles().contains { $0.pathExtension == "khvtmp" })

        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
        XCTAssertEqual(reopened.vaultKey.bytes, created.vaultKey.bytes)

        let changed = try await service.changePasscode(
            currentPasscode: fixture.originalPasscode,
            newPasscode: fixture.replacementPasscode,
            expectedVaultID: created.vaultID
        )
        XCTAssertEqual(changed.vaultID, created.vaultID)
        XCTAssertEqual(changed.vaultKey.bytes, created.vaultKey.bytes)
        do {
            _ = try await service.unlock(passcode: fixture.originalPasscode)
            XCTFail("The previous LowKey remained valid after a successful change")
        } catch VaultUnlockError.invalidCredentials {}

        let reopenedWithNewPasscode = try await service.unlock(
            passcode: fixture.replacementPasscode
        )
        XCTAssertEqual(reopenedWithNewPasscode.vaultID, created.vaultID)
        XCTAssertEqual(reopenedWithNewPasscode.vaultKey.bytes, created.vaultKey.bytes)

        try await deleteVaultThroughRetiredSession(
            service: service,
            passcode: fixture.replacementPasscode,
            vault: created
        )
        hasVaults = try await service.hasAnyVaults()
        XCTAssertFalse(hasVaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultPhotoRoot.path))
        do {
            _ = try await service.unlock(passcode: fixture.replacementPasscode)
            XCTFail("A deleted vault remained accessible")
        } catch VaultUnlockError.invalidCredentials {}
    }

    func testRejectedCreationAndDuplicatePasscodeDoNotChangePersistedVaults() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()

        do {
            _ = try await service.createVault(passcode: "12345678")
            XCTFail("A predictable LowKey created a vault")
        } catch KeyDerivationError.invalidPasscode {}
        var hasVaults = try await service.hasAnyVaults()
        XCTAssertFalse(hasVaults)

        let created = try await service.createVault(passcode: fixture.originalPasscode)
        do {
            _ = try await service.createVault(passcode: fixture.originalPasscode)
            XCTFail("A duplicate LowKey created another vault")
        } catch VaultUnlockError.passcodeAlreadyUsed {}

        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
        hasVaults = try await service.hasAnyVaults()
        XCTAssertTrue(hasVaults)
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 1)
    }

    func testFailedPasscodeChangeAndDeleteLeaveIndependentVaultsAccessible() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()

        let first = try await service.createVault(passcode: fixture.originalPasscode)
        let second = try await service.createVault(passcode: fixture.secondVaultPasscode)

        do {
            _ = try await service.changePasscode(
                currentPasscode: fixture.originalPasscode,
                newPasscode: fixture.secondVaultPasscode,
                expectedVaultID: first.vaultID
            )
            XCTFail("A passcode change replaced another vault credential")
        } catch VaultUnlockError.passcodeAlreadyUsed {}

        do {
            try await deleteVaultThroughRetiredSession(
                service: service,
                passcode: fixture.originalPasscode,
                vault: second
            )
            XCTFail("A mismatched vault identity was deleted")
        } catch VaultUnlockError.invalidCredentials {}

        let reopenedFirst = try await service.unlock(passcode: fixture.originalPasscode)
        let reopenedSecond = try await service.unlock(passcode: fixture.secondVaultPasscode)
        XCTAssertEqual(reopenedFirst.vaultID, first.vaultID)
        XCTAssertEqual(reopenedSecond.vaultID, second.vaultID)
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 2)
    }

    func testReauthenticationFailuresThrottleEveryCurrentVaultMutation() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()
        let vault = try await service.createVault(passcode: fixture.originalPasscode)

        for _ in 0..<5 {
            do {
                _ = try await service.reauthenticateCurrentVault(
                    passcode: fixture.replacementPasscode,
                    expectedVaultID: vault.vaultID
                )
                XCTFail("An incorrect current-vault credential was accepted")
            } catch VaultUnlockError.invalidCredentials {}
        }

        do {
            try await deleteVaultThroughRetiredSession(
                service: service,
                passcode: fixture.originalPasscode,
                vault: vault
            )
            XCTFail("Delete bypassed the shared credential cooldown")
        } catch VaultUnlockError.temporarilyLocked(_) {}
        let stillHasVaults = try await service.hasAnyVaults()
        XCTAssertTrue(stillHasVaults)
    }

    func testMalformedLowKeyAttemptsConsumeExactlyOneFailureEach() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()
        let created = try await service.createVault(passcode: fixture.originalPasscode)

        for _ in 0..<4 {
            do {
                _ = try await service.unlock(passcode: "12")
                XCTFail("A malformed LowKey was accepted")
            } catch VaultUnlockError.invalidCredentials {}
        }

        // Four attempts must not consume a five-attempt budget through
        // double accounting. A valid unlock must remain available at this point.
        XCTAssertEqual(
            fixture.defaults.integer(forKey: "keyhollow.unlock.failure-count.v2"),
            4
        )
        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)

        do {
            _ = try await service.unlock(passcode: "12")
            XCTFail("A malformed LowKey was accepted")
        } catch VaultUnlockError.invalidCredentials {}
        XCTAssertEqual(
            fixture.defaults.integer(forKey: "keyhollow.unlock.failure-count.v2"),
            5
        )
        do {
            _ = try await service.unlock(passcode: fixture.originalPasscode)
            XCTFail("Five malformed attempts did not activate the shared cooldown")
        } catch VaultUnlockError.temporarilyLocked(_) {}
    }

    func testCancelledCredentialReadDoesNotConsumeFailureBudget() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let pausingStore = PausingReadVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: pausingStore)
        let created = try await service.createVault(passcode: fixture.originalPasscode)

        let unlock = Task {
            try await service.unlock(passcode: fixture.originalPasscode)
        }
        await pausingStore.waitUntilReadIsPaused()
        unlock.cancel()
        await pausingStore.resumeRead()

        do {
            _ = try await unlock.value
            XCTFail("A cancelled credential read reported success")
        } catch is CancellationError {}
        XCTAssertEqual(
            fixture.defaults.integer(forKey: "keyhollow.unlock.failure-count.v2"),
            0
        )

        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    func testCreateCollisionOracleIsThrottledAndUsesAtomicWrite() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()
        _ = try await service.createVault(passcode: fixture.originalPasscode)

        for _ in 0..<5 {
            do {
                _ = try await service.createVault(passcode: fixture.originalPasscode)
                XCTFail("An existing LowKey overwrote its vault")
            } catch VaultUnlockError.passcodeAlreadyUsed {}
        }

        do {
            _ = try await service.createVault(passcode: fixture.secondVaultPasscode)
            XCTFail("Vault creation bypassed the shared collision cooldown")
        } catch VaultUnlockError.temporarilyLocked(_) {}
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 1)
    }

    func testConcurrentVaultCreationCannotOverwriteSameLowKeyLocator() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let firstService = try fixture.makeService()
        let secondService = try fixture.makeService()
        let startGate = LifecycleAsyncGate()

        let firstTask = Task {
            await startGate.wait()
            await attemptConcurrentVaultCreation(
                service: firstService,
                passcode: fixture.originalPasscode
            )
        }
        let secondTask = Task {
            await startGate.wait()
            await attemptConcurrentVaultCreation(
                service: secondService,
                passcode: fixture.originalPasscode
            )
        }
        await startGate.open()
        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        let results = [firstResult, secondResult]

        XCTAssertEqual(results.filter { $0.isSuccess }.count, 1)
        XCTAssertEqual(results.filter { $0 == .passcodeAlreadyUsed }.count, 1)
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 1)
        let reopened = try await fixture.makeService().unlock(
            passcode: fixture.originalPasscode
        )
        XCTAssertTrue(results.contains(.success(reopened.vaultID)))
    }

    func testOneServiceRejectsOverlappingCredentialMutationsBeforeTheyInterleave() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let pausingStore = PausingVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: pausingStore)

        let firstTask = Task {
            await attemptConcurrentVaultCreation(
                service: service,
                passcode: fixture.originalPasscode
            )
        }
        await pausingStore.waitUntilContainsIsPaused()

        do {
            _ = try await service.createVault(passcode: fixture.secondVaultPasscode)
            XCTFail("A second credential mutation entered while the first was suspended")
        } catch VaultUnlockError.operationInProgress {}

        await pausingStore.resumeContains()
        let firstResult = await firstTask.value
        guard case .success = firstResult else {
            return XCTFail("The original credential mutation did not complete")
        }
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 1)
    }

    func testCancelledVaultCreationDoesNotReachCredentialWrite() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let pausingStore = PausingVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: pausingStore)

        let creation = Task {
            try await service.createVault(passcode: fixture.originalPasscode)
        }
        await pausingStore.waitUntilContainsIsPaused()
        creation.cancel()
        await pausingStore.resumeContains()

        do {
            _ = try await creation.value
            XCTFail("A cancelled vault creation reported success")
        } catch is CancellationError {}
        XCTAssertTrue(fixture.credentialFiles().isEmpty)
        XCTAssertTrue(fixture.journalFiles(at: fixture.passcodeRotationJournalRoot).isEmpty)
    }

    func testCancelledPasscodeChangeDoesNotBeginJournaledMutation() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let initialService = try fixture.makeService()
        let created = try await initialService.createVault(passcode: fixture.originalPasscode)
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let pausingStore = PausingVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: pausingStore)

        let change = Task {
            try await service.changePasscode(
                currentPasscode: fixture.originalPasscode,
                newPasscode: fixture.replacementPasscode,
                expectedVaultID: created.vaultID
            )
        }
        await pausingStore.waitUntilContainsIsPaused()
        change.cancel()
        await pausingStore.resumeContains()

        do {
            _ = try await change.value
            XCTFail("A cancelled passcode change reported success")
        } catch is CancellationError {}
        XCTAssertTrue(fixture.journalFiles(at: fixture.passcodeRotationJournalRoot).isEmpty)
        let oldLocator = try fixture.locator(for: fixture.originalPasscode)
        let replacementLocator = try fixture.locator(for: fixture.replacementPasscode)
        let oldCredentialRemains = await backingStore.contains(
            locator: oldLocator
        )
        let replacementCredentialExists = await backingStore.contains(
            locator: replacementLocator
        )
        XCTAssertTrue(oldCredentialRemains)
        XCTAssertFalse(replacementCredentialExists)

        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    func testDeleteBlocksConcurrentUnlockAndReauthentication() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let pausingStore = PausingDeleteVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: pausingStore)
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        await pausingStore.pauseNextDelete()

        let deletion = Task {
            try await deleteVaultThroughRetiredSession(
                service: service,
                passcode: fixture.originalPasscode,
                vault: created
            )
        }
        await pausingStore.waitUntilDeleteIsPaused()
        let readsBeforeConcurrentAttempts = await pausingStore.readCallCount()

        do {
            _ = try await service.unlock(passcode: fixture.originalPasscode)
            XCTFail("Unlock entered while credential deletion was suspended")
        } catch VaultUnlockError.operationInProgress {}
        do {
            _ = try await service.reauthenticateCurrentVault(
                passcode: fixture.originalPasscode,
                expectedVaultID: created.vaultID
            )
            XCTFail("Reauthentication entered while credential deletion was suspended")
        } catch VaultUnlockError.operationInProgress {}

        let readsAfterConcurrentAttempts = await pausingStore.readCallCount()
        XCTAssertEqual(readsAfterConcurrentAttempts, readsBeforeConcurrentAttempts)
        await pausingStore.resumeDelete()
        try await deletion.value
    }

    @MainActor
    func testDeletionStartsOnlyAfterCapabilityRevocationAndSensitiveTaskDrainage() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let observingStore = PausingDeleteVaultCredentialStore(backing: backingStore)
        let dataCleanup = CountingVaultDataCleanup()
        let service = fixture.makeService(
            credentialStore: observingStore,
            additionalVaultDataRemover: { vaultID in
                dataCleanup.perform(vaultID: vaultID)
            }
        )
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)

        let cleanupGate = LifecycleAsyncGate()
        let sensitiveTaskStarted = expectation(description: "sensitive task started")
        var cleanupObservedRevocation = false
        _ = session.startSensitiveTask { access in
            sensitiveTaskStarted.fulfill()
            await cleanupGate.wait()
            cleanupObservedRevocation = access.isRevoked
        }
        await fulfillment(of: [sensitiveTaskStarted])

        let deletion = Task { @MainActor in
            try await VaultDeletionSessionCoordinator.deleteVault(
                service: service,
                session: session,
                currentPasscode: fixture.originalPasscode,
                expectedVaultID: created.vaultID
            )
        }
        await waitForSessionRetirement(session)

        let deletesBeforeDrainage = await observingStore.deleteCallCount()
        XCTAssertEqual(deletesBeforeDrainage, 0)
        XCTAssertEqual(dataCleanup.callCount, 0)
        XCTAssertFalse(session.hasActiveAccess)

        await cleanupGate.open()
        try await deletion.value

        let deletesAfterDrainage = await observingStore.deleteCallCount()
        XCTAssertEqual(deletesAfterDrainage, 1)
        XCTAssertEqual(dataCleanup.callCount, 1)
        XCTAssertTrue(cleanupObservedRevocation)
    }

    @MainActor
    func testInvalidDeletionAuthorizationCannotConsumeAnotherPendingGrant() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let firstService = try fixture.makeService()
        let secondService = try fixture.makeService()
        let created = try await firstService.createVault(passcode: fixture.originalPasscode)
        let firstAuthorization = try await firstService.authorizeVaultDeletion(
            currentPasscode: fixture.originalPasscode,
            expectedVaultID: created.vaultID
        )
        let secondAuthorization = try await secondService.authorizeVaultDeletion(
            currentPasscode: fixture.originalPasscode,
            expectedVaultID: created.vaultID
        )

        let secondSession = VaultSession()
        secondSession.unlock(vaultID: created.vaultID, key: created.vaultKey)
        let secondProof = try await secondSession.revokeAndDrainForVaultDeletion(
            secondAuthorization
        )
        do {
            try await firstService.deleteVault(
                authorization: secondAuthorization,
                revocationProof: secondProof
            )
            XCTFail("A grant from another service instance was accepted")
        } catch VaultUnlockError.invalidDeletionAuthorization {}
        let vaultExistsAfterInvalidGrant = try await firstService.hasAnyVaults()
        XCTAssertTrue(vaultExistsAfterInvalidGrant)

        let cancelledSecondGrant = await secondService.cancelVaultDeletionAuthorization(
            secondAuthorization
        )
        XCTAssertTrue(cancelledSecondGrant)
        let firstSession = VaultSession()
        firstSession.unlock(vaultID: created.vaultID, key: created.vaultKey)
        let firstProof = try await firstSession.revokeAndDrainForVaultDeletion(
            firstAuthorization
        )
        try await firstService.deleteVault(
            authorization: firstAuthorization,
            revocationProof: firstProof
        )
        let vaultExistsAfterValidGrant = try await firstService.hasAnyVaults()
        XCTAssertFalse(vaultExistsAfterValidGrant)
    }

    @MainActor
    func testExpiredDeletionAuthorizationFailsWithoutDeletingAndUnwedgesService() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService(vaultDeletionAuthorizationLifetime: 0)
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let authorization = try await service.authorizeVaultDeletion(
            currentPasscode: fixture.originalPasscode,
            expectedVaultID: created.vaultID
        )
        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)
        let proof = try await session.revokeAndDrainForVaultDeletion(authorization)

        do {
            try await service.deleteVault(
                authorization: authorization,
                revocationProof: proof
            )
            XCTFail("An expired deletion authorization was accepted")
        } catch VaultUnlockError.deletionAuthorizationExpired {}

        let vaultExistsAfterExpiredGrant = try await service.hasAnyVaults()
        XCTAssertTrue(vaultExistsAfterExpiredGrant)
        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    @MainActor
    func testDeletionAuthorizationIsOneUseAndCannotBeReplayed() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let dataCleanup = CountingVaultDataCleanup()
        let service = try fixture.makeService(additionalVaultDataRemover: { vaultID in
            dataCleanup.perform(vaultID: vaultID)
        })
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let authorization = try await service.authorizeVaultDeletion(
            currentPasscode: fixture.originalPasscode,
            expectedVaultID: created.vaultID
        )
        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)
        let proof = try await session.revokeAndDrainForVaultDeletion(authorization)

        try await service.deleteVault(
            authorization: authorization,
            revocationProof: proof
        )
        do {
            try await service.deleteVault(
                authorization: authorization,
                revocationProof: proof
            )
            XCTFail("A consumed deletion authorization was replayed")
        } catch VaultUnlockError.invalidDeletionAuthorization {}

        XCTAssertEqual(dataCleanup.callCount, 1)
        let replayCancellationAccepted = await service.cancelVaultDeletionAuthorization(
            authorization
        )
        XCTAssertFalse(replayCancellationAccepted)
    }

    func testCancellingDeletionAuthorizationReleasesCredentialMutationGate() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let authorization = try await service.authorizeVaultDeletion(
            currentPasscode: fixture.originalPasscode,
            expectedVaultID: created.vaultID
        )

        let firstCancellationAccepted = await service.cancelVaultDeletionAuthorization(
            authorization
        )
        let replayCancellationAccepted = await service.cancelVaultDeletionAuthorization(
            authorization
        )
        XCTAssertTrue(firstCancellationAccepted)
        XCTAssertFalse(replayCancellationAccepted)
        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    @MainActor
    func testCancelledDeletionCoordinatorUnwedgesServiceAfterTaskDrainage() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)

        let cleanupGate = LifecycleAsyncGate()
        let sensitiveTaskStarted = expectation(description: "sensitive task started")
        _ = session.startSensitiveTask { _ in
            sensitiveTaskStarted.fulfill()
            await cleanupGate.wait()
        }
        await fulfillment(of: [sensitiveTaskStarted])

        let deletion = Task { @MainActor in
            try await VaultDeletionSessionCoordinator.deleteVault(
                service: service,
                session: session,
                currentPasscode: fixture.originalPasscode,
                expectedVaultID: created.vaultID
            )
        }
        await waitForSessionRetirement(session)
        deletion.cancel()
        await cleanupGate.open()

        do {
            try await deletion.value
            XCTFail("A cancelled deletion coordinator reported success")
        } catch is CancellationError {}

        let vaultExists = try await service.hasAnyVaults()
        XCTAssertTrue(vaultExists)
        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    func testPasscodeChangeCollisionsAccumulateInGlobalFailureBudget() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()
        let first = try await service.createVault(passcode: fixture.originalPasscode)
        _ = try await service.createVault(passcode: fixture.secondVaultPasscode)

        for _ in 0..<5 {
            do {
                _ = try await service.changePasscode(
                    currentPasscode: fixture.originalPasscode,
                    newPasscode: fixture.secondVaultPasscode,
                    expectedVaultID: first.vaultID
                )
                XCTFail("A colliding replacement LowKey was accepted")
            } catch VaultUnlockError.passcodeAlreadyUsed {}
        }

        do {
            _ = try await service.unlock(passcode: fixture.originalPasscode)
            XCTFail("A collision probe did not activate the shared cooldown")
        } catch VaultUnlockError.temporarilyLocked(_) {}
    }

    func testPasscodeChangeRecoversWriteThatThrowsAfterReplacementCommit() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let faultingStore = FaultInjectingVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: faultingStore)
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        await faultingStore.arm(.writeAfterCommit)

        let changed = try await service.changePasscode(
            currentPasscode: fixture.originalPasscode,
            newPasscode: fixture.replacementPasscode,
            expectedVaultID: created.vaultID
        )

        XCTAssertEqual(changed.vaultID, created.vaultID)
        let oldLocator = try fixture.locator(for: fixture.originalPasscode)
        let newLocator = try fixture.locator(for: fixture.replacementPasscode)
        let oldRemains = await faultingStore.contains(locator: oldLocator)
        let newRemains = await faultingStore.contains(locator: newLocator)
        XCTAssertFalse(oldRemains)
        XCTAssertTrue(newRemains)
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 1)
        XCTAssertTrue(fixture.journalFiles(at: fixture.passcodeRotationJournalRoot).isEmpty)
    }

    func testPasscodeChangeRecoversDeleteThatThrowsAfterOriginalRemoval() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let faultingStore = FaultInjectingVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: faultingStore)
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        await faultingStore.arm(.deleteAfterCommit)

        let changed = try await service.changePasscode(
            currentPasscode: fixture.originalPasscode,
            newPasscode: fixture.replacementPasscode,
            expectedVaultID: created.vaultID
        )

        XCTAssertEqual(changed.vaultID, created.vaultID)
        let oldLocator = try fixture.locator(for: fixture.originalPasscode)
        let newLocator = try fixture.locator(for: fixture.replacementPasscode)
        let oldRemains = await faultingStore.contains(locator: oldLocator)
        let newRemains = await faultingStore.contains(locator: newLocator)
        XCTAssertFalse(oldRemains)
        XCTAssertTrue(newRemains)
        XCTAssertTrue(fixture.journalFiles(at: fixture.passcodeRotationJournalRoot).isEmpty)
    }

    func testUnresolvedRotationBlocksEveryLaterCredentialOperationUntilRecovery() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let faultingStore = FaultInjectingVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: faultingStore)
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        await faultingStore.arm(.writeAfterCommitAndFailRecoveryReads)

        do {
            _ = try await service.changePasscode(
                currentPasscode: fixture.originalPasscode,
                newPasscode: fixture.replacementPasscode,
                expectedVaultID: created.vaultID
            )
            XCTFail("An unresolved passcode rotation reported success")
        } catch VaultUnlockError.mutationFailed {}

        let unresolvedJournalCount = fixture.journalFiles(
            at: fixture.passcodeRotationJournalRoot
        ).count
        XCTAssertEqual(unresolvedJournalCount, 1)
        do {
            _ = try await service.unlock(passcode: fixture.originalPasscode)
            XCTFail("Unlock bypassed an unresolved credential journal")
        } catch VaultUnlockError.credentialRecoveryRequired {}
        do {
            _ = try await service.createVault(passcode: fixture.secondVaultPasscode)
            XCTFail("A second credential mutation bypassed unresolved recovery")
        } catch VaultUnlockError.credentialRecoveryRequired {}
        XCTAssertEqual(
            fixture.journalFiles(at: fixture.passcodeRotationJournalRoot).count,
            unresolvedJournalCount
        )

        await faultingStore.allowReads()
        try await service.recoverInterruptedPortableVaultInstalls()
        XCTAssertTrue(fixture.journalFiles(at: fixture.passcodeRotationJournalRoot).isEmpty)
        let reopened = try await service.unlock(passcode: fixture.replacementPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    @MainActor
    func testUnknownDeletionStateLocksWithoutClaimingCredentialDestruction() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let backingStore = try VaultStore(rootOverride: fixture.credentialRoot)
        let faultingStore = FaultInjectingVaultCredentialStore(backing: backingStore)
        let service = fixture.makeService(credentialStore: faultingStore)
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)
        await faultingStore.arm(.deleteBeforeCommitAndFailRecoveryReads)

        do {
            try await VaultDeletionSessionCoordinator.deleteVault(
                service: service,
                session: session,
                currentPasscode: fixture.originalPasscode,
                expectedVaultID: created.vaultID
            )
            XCTFail("An unverified credential deletion reported success")
        } catch VaultUnlockError.credentialStateUnknown {}

        XCTAssertFalse(session.hasActiveAccess)
        let credentialStillExists = try await service.hasAnyVaults()
        XCTAssertTrue(credentialStillExists)
        XCTAssertFalse(fixture.journalFiles(at: fixture.vaultDeletionJournalRoot).isEmpty)

        await faultingStore.allowReads()
        try await service.recoverInterruptedPortableVaultInstalls()
        XCTAssertTrue(fixture.journalFiles(at: fixture.vaultDeletionJournalRoot).isEmpty)
        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    func testStartupRecoveryFinishesInterruptedPasscodeRotation() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let store = try VaultStore(rootOverride: fixture.credentialRoot)
        let oldLocator = try fixture.locator(for: fixture.originalPasscode)
        let newKey = try fixture.unlockKey(for: fixture.replacementPasscode)
        let newLocator = VaultLocator.derive(from: newKey)
        let persistedOldEnvelope = try await store.read(locator: oldLocator)
        let oldEnvelope = try XCTUnwrap(persistedOldEnvelope)
        let replacement = try VaultEnvelope.seal(
            payload: oldEnvelope.open(
                using: try fixture.unlockKey(for: fixture.originalPasscode)
            ),
            using: newKey
        )
        let journal = try PasscodeRotationTransactionJournal(
            authenticationKey: try PasscodeRotationJournalKeySchedule.key(
                devicePepper: FixedDeviceSecrets().loadOrCreate()
            ),
            rootOverride: fixture.passcodeRotationJournalRoot
        )
        _ = try journal.begin(
            vaultID: created.vaultID,
            oldLocator: oldLocator,
            oldEnvelope: oldEnvelope,
            newLocator: newLocator,
            newEnvelope: replacement
        )
        try await store.writeIfAbsent(replacement, locator: newLocator)

        let oldBeforeRecovery = await store.contains(locator: oldLocator)
        let newBeforeRecovery = await store.contains(locator: newLocator)
        XCTAssertTrue(oldBeforeRecovery)
        XCTAssertTrue(newBeforeRecovery)

        let relaunched = try fixture.makeService()
        try await relaunched.recoverInterruptedPortableVaultInstalls()

        let oldAfterRecovery = await store.contains(locator: oldLocator)
        let newAfterRecovery = await store.contains(locator: newLocator)
        XCTAssertFalse(oldAfterRecovery)
        XCTAssertTrue(newAfterRecovery)
        XCTAssertTrue(fixture.journalFiles(at: fixture.passcodeRotationJournalRoot).isEmpty)
        let reopened = try await relaunched.unlock(passcode: fixture.replacementPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
    }

    @MainActor
    func testCommittedDeletionCleanupFailureLocksSessionAndRetriesAtStartup() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let supplementalRoot = fixture.root.appendingPathComponent("supplemental", isDirectory: true)
        try FileManager.default.createDirectory(
            at: supplementalRoot,
            withIntermediateDirectories: true
        )
        let cleanup = FailOnceVaultDataCleanup(root: supplementalRoot)
        let service = try fixture.makeService(additionalVaultDataRemover: { vaultID in
            try cleanup.perform(vaultID: vaultID)
        })
        let created = try await service.createVault(passcode: fixture.originalPasscode)
        let supplementalVaultRoot = supplementalRoot.appendingPathComponent(
            created.vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: supplementalVaultRoot,
            withIntermediateDirectories: true
        )
        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)

        do {
            try await VaultDeletionSessionCoordinator.deleteVault(
                service: service,
                session: session,
                currentPasscode: fixture.originalPasscode,
                expectedVaultID: created.vaultID
            )
            XCTFail("Cleanup failure did not report a committed credential deletion")
        } catch VaultUnlockError.credentialDestroyedCleanupIncomplete {}

        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertFalse(session.hasActiveAccess)
        let hasVaultAfterCommittedDeletion = try await service.hasAnyVaults()
        XCTAssertFalse(hasVaultAfterCommittedDeletion)
        XCTAssertFalse(fixture.journalFiles(at: fixture.vaultDeletionJournalRoot).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: supplementalVaultRoot.path))

        let relaunched = try fixture.makeService(additionalVaultDataRemover: { vaultID in
            try cleanup.perform(vaultID: vaultID)
        })
        try await relaunched.recoverInterruptedPortableVaultInstalls()

        XCTAssertTrue(fixture.journalFiles(at: fixture.vaultDeletionJournalRoot).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: supplementalVaultRoot.path))
        let hasVaultAfterCleanupRecovery = try await relaunched.hasAnyVaults()
        XCTAssertFalse(hasVaultAfterCleanupRecovery)
    }

}

private final class LifecycleFixture: @unchecked Sendable {
    let root: URL
    let credentialRoot: URL
    let photoRoot: URL
    let generalFileRoot: URL
    let portableRestoreJournalRoot: URL
    let portableRestoreWorkingRoot: URL
    let passcodeRotationJournalRoot: URL
    let vaultDeletionJournalRoot: URL
    let defaults: UserDefaults
    let defaultsSuite: String

    let originalPasscode = "83057291"
    let replacementPasscode = "60483927"
    let secondVaultPasscode = "27594086"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowLifecycleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        credentialRoot = root.appendingPathComponent("credentials", isDirectory: true)
        photoRoot = root.appendingPathComponent("photos", isDirectory: true)
        generalFileRoot = root.appendingPathComponent("general-files", isDirectory: true)
        portableRestoreJournalRoot = root.appendingPathComponent(
            "portable-restore-journals",
            isDirectory: true
        )
        portableRestoreWorkingRoot = root.appendingPathComponent(
            "portable-restore-working",
            isDirectory: true
        )
        passcodeRotationJournalRoot = root.appendingPathComponent(
            "passcode-rotation-journals",
            isDirectory: true
        )
        vaultDeletionJournalRoot = root.appendingPathComponent(
            "vault-deletion-journals",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: credentialRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generalFileRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: portableRestoreWorkingRoot,
            withIntermediateDirectories: true
        )

        defaultsSuite = "KeyHollowLifecycleTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: defaultsSuite) else {
            throw CocoaError(.featureUnsupported)
        }
        defaults = isolatedDefaults
    }

    func makeService(
        additionalVaultDataRemover: @escaping @Sendable (UUID) throws -> Void = { _ in },
        vaultDeletionAuthorizationLifetime: TimeInterval = 300
    ) throws -> VaultUnlockService {
        try VaultUnlockService(
            kdf: FastLifecycleKDF(),
            limiter: UnlockAttemptLimiter(defaults: defaults),
            secrets: FixedDeviceSecrets(),
            vaultStorageRootOverride: credentialRoot,
            photoStorageRootOverride: photoRoot,
            generalFileStorageRootOverride: generalFileRoot,
            portableRestoreJournalRootOverride: portableRestoreJournalRoot,
            portableRestoreWorkingRootOverride: portableRestoreWorkingRoot,
            passcodeRotationJournalRootOverride: passcodeRotationJournalRoot,
            vaultDeletionJournalRootOverride: vaultDeletionJournalRoot,
            additionalVaultDataRemover: additionalVaultDataRemover,
            vaultDeletionAuthorizationLifetime: vaultDeletionAuthorizationLifetime
        )
    }

    func makeService(
        credentialStore: any VaultCredentialStoring,
        additionalVaultDataRemover: @escaping @Sendable (UUID) throws -> Void = { _ in }
    ) -> VaultUnlockService {
        VaultUnlockService(
            credentialStore: credentialStore,
            kdf: FastLifecycleKDF(),
            limiter: UnlockAttemptLimiter(defaults: defaults),
            secrets: FixedDeviceSecrets(),
            photoStorageRootOverride: photoRoot,
            generalFileStorageRootOverride: generalFileRoot,
            portableRestoreJournalRootOverride: portableRestoreJournalRoot,
            portableRestoreWorkingRootOverride: portableRestoreWorkingRoot,
            passcodeRotationJournalRootOverride: passcodeRotationJournalRoot,
            vaultDeletionJournalRootOverride: vaultDeletionJournalRoot,
            additionalVaultDataRemover: additionalVaultDataRemover
        )
    }

    func unlockKey(for passcode: String) throws -> SymmetricKey {
        try FastLifecycleKDF().deriveKey(
            passcode: passcode,
            installationSalt: FixedDeviceSecrets().loadOrCreateInstallationSalt(),
            pepper: FixedDeviceSecrets().loadOrCreate()
        )
    }

    func locator(for passcode: String) throws -> String {
        VaultLocator.derive(from: try unlockKey(for: passcode))
    }

    func journalFiles(at root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    func credentialFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: credentialRoot,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: root)
    }
}

private enum ConcurrentVaultCreationResult: Equatable, Sendable {
    case success(UUID)
    case passcodeAlreadyUsed
    case unexpectedFailure

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private actor LifecycleAsyncGate {
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

private actor PausingVaultCredentialStore: VaultCredentialStoring {
    private let backing: VaultStore
    private var shouldPauseContains = true
    private var containsIsPaused = false
    private var pauseObservers: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    init(backing: VaultStore) {
        self.backing = backing
    }

    func waitUntilContainsIsPaused() async {
        guard !containsIsPaused else { return }
        await withCheckedContinuation { continuation in
            pauseObservers.append(continuation)
        }
    }

    func resumeContains() {
        let pending = resumeWaiters
        resumeWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func hasAnyVaults() async throws -> Bool {
        try await backing.hasAnyVaults()
    }

    func contains(locator: String) async -> Bool {
        if shouldPauseContains {
            shouldPauseContains = false
            containsIsPaused = true
            let observers = pauseObservers
            pauseObservers.removeAll()
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                resumeWaiters.append(continuation)
            }
        }
        return await backing.contains(locator: locator)
    }

    func read(locator: String) async throws -> VaultEnvelope? {
        try await backing.read(locator: locator)
    }

    func writeIfAbsent(_ envelope: VaultEnvelope, locator: String) async throws {
        try await backing.writeIfAbsent(envelope, locator: locator)
    }

    func delete(locator: String) async throws {
        try await backing.delete(locator: locator)
    }
}

private actor PausingReadVaultCredentialStore: VaultCredentialStoring {
    private let backing: VaultStore
    private var shouldPauseRead = true
    private var readIsPaused = false
    private var pauseObservers: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    init(backing: VaultStore) {
        self.backing = backing
    }

    func waitUntilReadIsPaused() async {
        guard !readIsPaused else { return }
        await withCheckedContinuation { continuation in
            pauseObservers.append(continuation)
        }
    }

    func resumeRead() {
        let pending = resumeWaiters
        resumeWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func hasAnyVaults() async throws -> Bool {
        try await backing.hasAnyVaults()
    }

    func contains(locator: String) async -> Bool {
        await backing.contains(locator: locator)
    }

    func read(locator: String) async throws -> VaultEnvelope? {
        if shouldPauseRead {
            shouldPauseRead = false
            readIsPaused = true
            let observers = pauseObservers
            pauseObservers.removeAll()
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                resumeWaiters.append(continuation)
            }
        }
        return try await backing.read(locator: locator)
    }

    func writeIfAbsent(_ envelope: VaultEnvelope, locator: String) async throws {
        try await backing.writeIfAbsent(envelope, locator: locator)
    }

    func delete(locator: String) async throws {
        try await backing.delete(locator: locator)
    }
}

private actor PausingDeleteVaultCredentialStore: VaultCredentialStoring {
    private let backing: VaultStore
    private var shouldPauseDelete = false
    private var deleteIsPaused = false
    private var deletePauseObservers: [CheckedContinuation<Void, Never>] = []
    private var deleteResumeWaiters: [CheckedContinuation<Void, Never>] = []
    private var reads = 0
    private var deletes = 0

    init(backing: VaultStore) {
        self.backing = backing
    }

    func pauseNextDelete() {
        shouldPauseDelete = true
    }

    func waitUntilDeleteIsPaused() async {
        guard !deleteIsPaused else { return }
        await withCheckedContinuation { continuation in
            deletePauseObservers.append(continuation)
        }
    }

    func resumeDelete() {
        let pending = deleteResumeWaiters
        deleteResumeWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func readCallCount() -> Int {
        reads
    }

    func deleteCallCount() -> Int {
        deletes
    }

    func hasAnyVaults() async throws -> Bool {
        try await backing.hasAnyVaults()
    }

    func contains(locator: String) async -> Bool {
        await backing.contains(locator: locator)
    }

    func read(locator: String) async throws -> VaultEnvelope? {
        reads += 1
        return try await backing.read(locator: locator)
    }

    func writeIfAbsent(_ envelope: VaultEnvelope, locator: String) async throws {
        try await backing.writeIfAbsent(envelope, locator: locator)
    }

    func delete(locator: String) async throws {
        deletes += 1
        if shouldPauseDelete {
            shouldPauseDelete = false
            deleteIsPaused = true
            let observers = deletePauseObservers
            deletePauseObservers.removeAll()
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                deleteResumeWaiters.append(continuation)
            }
        }
        try await backing.delete(locator: locator)
    }
}

private final class CountingVaultDataCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func perform(vaultID: UUID) {
        _ = vaultID
        lock.lock()
        calls += 1
        lock.unlock()
    }
}

private enum InjectedCredentialStoreFailure: Error, Equatable, Sendable {
    case writeAfterCommit
    case writeAfterCommitAndFailRecoveryReads
    case deleteAfterCommit
    case deleteBeforeCommitAndFailRecoveryReads
    case read
}

private actor FaultInjectingVaultCredentialStore: VaultCredentialStoring {
    private let backing: VaultStore
    private var armedFault: InjectedCredentialStoreFailure?
    private var readsFail = false

    init(backing: VaultStore) {
        self.backing = backing
    }

    func arm(_ fault: InjectedCredentialStoreFailure) {
        armedFault = fault
    }

    func hasAnyVaults() async throws -> Bool {
        try await backing.hasAnyVaults()
    }

    func contains(locator: String) async -> Bool {
        await backing.contains(locator: locator)
    }

    func read(locator: String) async throws -> VaultEnvelope? {
        if readsFail {
            throw InjectedCredentialStoreFailure.read
        }
        return try await backing.read(locator: locator)
    }

    func writeIfAbsent(_ envelope: VaultEnvelope, locator: String) async throws {
        try await backing.writeIfAbsent(envelope, locator: locator)
        if armedFault == .writeAfterCommit {
            armedFault = nil
            throw InjectedCredentialStoreFailure.writeAfterCommit
        }
        if armedFault == .writeAfterCommitAndFailRecoveryReads {
            armedFault = nil
            readsFail = true
            throw InjectedCredentialStoreFailure.writeAfterCommitAndFailRecoveryReads
        }
    }

    func delete(locator: String) async throws {
        if armedFault == .deleteBeforeCommitAndFailRecoveryReads {
            armedFault = nil
            readsFail = true
            throw InjectedCredentialStoreFailure.deleteBeforeCommitAndFailRecoveryReads
        }
        try await backing.delete(locator: locator)
        if armedFault == .deleteAfterCommit {
            armedFault = nil
            throw InjectedCredentialStoreFailure.deleteAfterCommit
        }
    }

    func allowReads() {
        readsFail = false
    }
}

private final class FailOnceVaultDataCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private var shouldFail = true

    init(root: URL) {
        self.root = root
    }

    func perform(vaultID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
        let target = root.appendingPathComponent(
            vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
    }
}

private func attemptConcurrentVaultCreation(
    service: VaultUnlockService,
    passcode: String
) async -> ConcurrentVaultCreationResult {
    do {
        let created = try await service.createVault(passcode: passcode)
        return .success(created.vaultID)
    } catch VaultUnlockError.passcodeAlreadyUsed {
        return .passcodeAlreadyUsed
    } catch {
        return .unexpectedFailure
    }
}

@MainActor
private func deleteVaultThroughRetiredSession(
    service: VaultUnlockService,
    passcode: String,
    vault: UnlockedVault
) async throws {
    let session = VaultSession()
    session.unlock(vaultID: vault.vaultID, key: vault.vaultKey)
    try await VaultDeletionSessionCoordinator.deleteVault(
        service: service,
        session: session,
        currentPasscode: passcode,
        expectedVaultID: vault.vaultID
    )
}

@MainActor
private func waitForSessionRetirement(_ session: VaultSession) async {
    for _ in 0..<1_000 {
        if !session.hasActiveAccess { return }
        await Task.yield()
    }
    XCTFail("The deletion coordinator did not revoke the active capability")
}

private struct FixedDeviceSecrets: DeviceSecretProviding {
    func loadOrCreate() throws -> Data {
        Data(repeating: 0x51, count: 32)
    }

    func loadOrCreateInstallationSalt() throws -> Data {
        Data(repeating: 0xA7, count: 16)
    }
}

private struct FastLifecycleKDF: PasswordKeyDeriving {
    func deriveKey(passcode: String, installationSalt: Data, pepper: Data) throws -> SymmetricKey {
        var input = Data(passcode.utf8)
        input.append(installationSalt)
        input.append(pepper)
        return SymmetricKey(data: Data(SHA256.hash(data: input)))
    }
}

private extension SymmetricKey {
    var bytes: Data {
        withUnsafeBytes { Data($0) }
    }
}

