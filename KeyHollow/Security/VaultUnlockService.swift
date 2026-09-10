import Foundation
import CryptoKit
import KeyHollowPhotoCore
import KeyHollowTransferCore
import KeyHollowVaultCore

enum VaultUnlockError: Error, Equatable {
    case invalidCredentials
    case passcodeAlreadyUsed
    case temporarilyLocked(Date)
    case mutationFailed
    case operationInProgress
    /// An authenticated credential transaction remains unresolved. All new
    /// credential operations stay blocked until journal recovery succeeds.
    case credentialRecoveryRequired
    /// The credential store could not prove whether destructive deletion
    /// committed. The session must lock, but the vault must not be reported as
    /// deleted until startup recovery can recheck the authenticated journal.
    case credentialStateUnknown
    /// The credential is gone and must never be presented as retryable, even
    /// though one or more encrypted data directories could not be removed.
    case credentialDestroyedCleanupIncomplete
    /// The deletion grant did not originate from, or is no longer pending in,
    /// this service. No credential or vault data was changed.
    case invalidDeletionAuthorization
    /// Session retirement took longer than the short lifetime of the deletion
    /// grant. The grant was discarded and no deletion was started.
    case deletionAuthorizationExpired
}

struct UnlockedVault {
    let vaultID: UUID
    let vaultKey: SymmetricKey
    let createdAt: Date
}

struct ReauthenticatedVault {
    let vaultID: UUID
    let createdAt: Date
}

/// A short-lived, one-use grant produced only after the current LowKey has
/// authenticated the vault selected for deletion. It contains no key material.
struct VaultDeletionAuthorization: Sendable, Equatable {
    let vaultID: UUID
    let authorizationID: UUID

    fileprivate init(vaultID: UUID, authorizationID: UUID) {
        self.vaultID = vaultID
        self.authorizationID = authorizationID
    }
}

private struct AuthenticatedVaultCredential {
    let payload: VaultPayload
    let locator: String
    let envelope: VaultEnvelope
}

private struct PendingVaultDeletionAuthorization {
    let authorizationID: UUID
    let vaultID: UUID
    let locator: String
    let envelope: VaultEnvelope
    let expiresAtUptime: TimeInterval
}

protocol VaultCredentialStoring: PortableVaultCredentialStoring {
    func hasAnyVaults() async throws -> Bool
}

extension VaultStore: VaultCredentialStoring {}

actor VaultUnlockService {
    private let secrets: DeviceSecretProviding
    private let kdf: PasswordKeyDeriving
    private let limiter: UnlockAttemptLimiter
    private let store: any VaultCredentialStoring
    private let photoStorageRootOverride: URL?
    private let generalFileStorageRootOverride: URL?
    private let portableRestoreJournalRootOverride: URL?
    private let portableRestoreWorkingRootOverride: URL?
    private let passcodeRotationJournalRootOverride: URL?
    private let vaultDeletionJournalRootOverride: URL?
    private let additionalVaultDataRemover: @Sendable (UUID) throws -> Void
    private let vaultDeletionAuthorizationLifetime: TimeInterval
    private let authorizationUptime: @Sendable () -> TimeInterval
    private var credentialOperationInProgress = false
    private var credentialRecoveryRequired = false
    private var pendingVaultDeletionAuthorization: PendingVaultDeletionAuthorization?

    init(
        kdf: PasswordKeyDeriving = ProductionArgon2idKDF(),
        limiter: UnlockAttemptLimiter = UnlockAttemptLimiter(),
        secrets: DeviceSecretProviding = DevicePepperStore(),
        vaultStorageRootOverride: URL? = nil,
        photoStorageRootOverride: URL? = nil,
        generalFileStorageRootOverride: URL? = nil,
        portableRestoreJournalRootOverride: URL? = nil,
        portableRestoreWorkingRootOverride: URL? = nil,
        passcodeRotationJournalRootOverride: URL? = nil,
        vaultDeletionJournalRootOverride: URL? = nil,
        additionalVaultDataRemover: @escaping @Sendable (UUID) throws -> Void = { _ in },
        vaultDeletionAuthorizationLifetime: TimeInterval = 300,
        authorizationUptime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) throws {
        self.kdf = kdf
        self.limiter = limiter
        self.secrets = secrets
        self.store = try VaultStore(rootOverride: vaultStorageRootOverride)
        self.photoStorageRootOverride = photoStorageRootOverride
        self.generalFileStorageRootOverride = generalFileStorageRootOverride
        self.portableRestoreJournalRootOverride = portableRestoreJournalRootOverride
        self.portableRestoreWorkingRootOverride = portableRestoreWorkingRootOverride
        self.passcodeRotationJournalRootOverride = passcodeRotationJournalRootOverride
        self.vaultDeletionJournalRootOverride = vaultDeletionJournalRootOverride
        self.additionalVaultDataRemover = additionalVaultDataRemover
        self.vaultDeletionAuthorizationLifetime = vaultDeletionAuthorizationLifetime
        self.authorizationUptime = authorizationUptime
    }

    init(
        credentialStore: any VaultCredentialStoring,
        kdf: PasswordKeyDeriving = ProductionArgon2idKDF(),
        limiter: UnlockAttemptLimiter = UnlockAttemptLimiter(),
        secrets: DeviceSecretProviding = DevicePepperStore(),
        photoStorageRootOverride: URL? = nil,
        generalFileStorageRootOverride: URL? = nil,
        portableRestoreJournalRootOverride: URL? = nil,
        portableRestoreWorkingRootOverride: URL? = nil,
        passcodeRotationJournalRootOverride: URL? = nil,
        vaultDeletionJournalRootOverride: URL? = nil,
        additionalVaultDataRemover: @escaping @Sendable (UUID) throws -> Void = { _ in },
        vaultDeletionAuthorizationLifetime: TimeInterval = 300,
        authorizationUptime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.kdf = kdf
        self.limiter = limiter
        self.secrets = secrets
        self.store = credentialStore
        self.photoStorageRootOverride = photoStorageRootOverride
        self.generalFileStorageRootOverride = generalFileStorageRootOverride
        self.portableRestoreJournalRootOverride = portableRestoreJournalRootOverride
        self.portableRestoreWorkingRootOverride = portableRestoreWorkingRootOverride
        self.passcodeRotationJournalRootOverride = passcodeRotationJournalRootOverride
        self.vaultDeletionJournalRootOverride = vaultDeletionJournalRootOverride
        self.additionalVaultDataRemover = additionalVaultDataRemover
        self.vaultDeletionAuthorizationLifetime = vaultDeletionAuthorizationLifetime
        self.authorizationUptime = authorizationUptime
    }

    func hasAnyVaults() async throws -> Bool {
        try await store.hasAnyVaults()
    }

    /// Recovers any credential transaction that was interrupted before its
    /// authenticated journal could be cleared. Call during startup before
    /// allowing unlock or vault creation.
    func recoverInterruptedPortableVaultInstalls() async throws {
        try EncryptedVaultTransferCoordinator.cleanUpAbandonedWorkingDirectories(
            workingRootOverride: portableRestoreWorkingRootOverride
        )
        try beginCredentialOperation(allowsRecovery: true)
        do {
            try await recoverPendingCredentialTransactions()
            guard !(try hasPendingCredentialTransactions()) else {
                throw VaultUnlockError.credentialRecoveryRequired
            }
            credentialRecoveryRequired = false
            finishCredentialOperation()
        } catch {
            credentialRecoveryRequired = true
            finishCredentialOperation()
            throw error
        }
    }

    func createVault(passcode: String) async throws -> UnlockedVault {
        try beginCredentialOperation()
        defer { finishCredentialOperation() }
        guard PasscodePolicy.isAcceptableNewPasscode(passcode) else {
            throw KeyDerivationError.invalidPasscode
        }

        try await checkCredentialLookupAllowed()

        let unlockKey = try deriveUnlockKey(passcode: passcode)
        try Task.checkCancellation()
        let locator = VaultLocator.derive(from: unlockKey)

        let locatorAlreadyExists = await store.contains(locator: locator)
        try Task.checkCancellation()
        if locatorAlreadyExists {
            await limiter.recordFailure()
            throw VaultUnlockError.passcodeAlreadyUsed
        }

        let created = try VaultEnvelope.create(using: unlockKey)
        try Task.checkCancellation()
        do {
            try await store.writeIfAbsent(created.envelope, locator: locator)
        } catch VaultCredentialStoreError.locatorAlreadyExists {
            await limiter.recordFailure()
            throw VaultUnlockError.passcodeAlreadyUsed
        }

        return unlockedVault(from: created.payload)
    }

    /// Gives a fully validated portable vault a new device-local LowKey
    /// wrapper. The archive recovery credential is never accepted by the
    /// normal keypad and no existing vault credential or photo directory is
    /// replaced.
    func installValidatedPortableVault(
        _ restore: ValidatedPortableVaultRestore,
        newPasscode: String
    ) async throws -> UnlockedVault {
        try beginCredentialOperation()
        defer { finishCredentialOperation() }
        guard PasscodePolicy.isAcceptableNewPasscode(newPasscode) else {
            throw KeyDerivationError.invalidPasscode
        }

        try await checkCredentialLookupAllowed()
        let unlockKey = try deriveUnlockKey(passcode: newPasscode)
        try Task.checkCancellation()
        let locator = VaultLocator.derive(from: unlockKey)
        let locatorAlreadyExists = await store.contains(locator: locator)
        try Task.checkCancellation()
        if locatorAlreadyExists {
            await limiter.recordFailure()
            throw VaultUnlockError.passcodeAlreadyUsed
        }
        let installer = try PortableVaultRestoreInstaller(
            credentialStore: store,
            journalAuthenticationKey: try portableRestoreJournalKey(),
            journalRootOverride: portableRestoreJournalRootOverride,
            photoDataRootOverride: photoStorageRootOverride,
            generalFileDataRootOverride: generalFileStorageRootOverride
        )
        try Task.checkCancellation()
        do {
            let payload = try await installer.install(
                restore,
                localUnlockKey: unlockKey
            )
            return unlockedVault(from: payload)
        } catch is CancellationError {
            throw CancellationError()
        } catch PortableVaultRestoreInstallationError.credentialAlreadyUsed {
            await limiter.recordFailure()
            throw VaultUnlockError.passcodeAlreadyUsed
        } catch {
            markCredentialRecoveryRequiredIfNeeded()
            throw VaultUnlockError.mutationFailed
        }
    }

    func unlock(passcode: String) async throws -> UnlockedVault {
        try beginCredentialOperation()
        defer { finishCredentialOperation() }
        let credential = try await authenticateExistingVault(passcode: passcode)
        try Task.checkCancellation()
        return unlockedVault(from: credential.payload)
    }

    /// Re-authenticates the vault that is already open without revealing or
    /// accepting credentials for any other local vault.
    func reauthenticateCurrentVault(
        passcode: String,
        expectedVaultID: UUID
    ) async throws -> ReauthenticatedVault {
        try beginCredentialOperation()
        defer { finishCredentialOperation() }
        let credential = try await authenticateExistingVault(
            passcode: passcode,
            expectedVaultID: expectedVaultID
        )
        try Task.checkCancellation()
        // Deliberately do not return a second copy of the vault key. The active
        // session capability remains the only key source used by export.
        return ReauthenticatedVault(
            vaultID: credential.payload.vaultID,
            createdAt: credential.payload.createdAt
        )
    }

    /// Changes only the passcode wrapper. The vault's random data key and all
    /// encrypted photo blobs remain unchanged, avoiding bulk decrypt/re-encrypt.
    /// The current passcode must resolve to the vault that is actually open.
    func changePasscode(
        currentPasscode: String,
        newPasscode: String,
        expectedVaultID: UUID
    ) async throws -> UnlockedVault {
        try beginCredentialOperation()
        defer { finishCredentialOperation() }
        guard PasscodePolicy.isAcceptableNewPasscode(newPasscode) else {
            throw KeyDerivationError.invalidPasscode
        }

        let current = try await authenticateExistingVault(
            passcode: currentPasscode,
            expectedVaultID: expectedVaultID
        )
        try Task.checkCancellation()

        let newKey = try deriveUnlockKey(passcode: newPasscode)
        try Task.checkCancellation()
        let newLocator = VaultLocator.derive(from: newKey)
        guard newLocator != current.locator else {
            await limiter.recordFailure()
            throw VaultUnlockError.passcodeAlreadyUsed
        }
        let replacementLocatorAlreadyExists = await store.contains(locator: newLocator)
        try Task.checkCancellation()
        guard !replacementLocatorAlreadyExists else {
            await limiter.recordFailure()
            throw VaultUnlockError.passcodeAlreadyUsed
        }

        let replacement = try VaultEnvelope.seal(payload: current.payload, using: newKey)
        try Task.checkCancellation()

        let journal: PasscodeRotationTransactionJournal
        let transaction: PasscodeRotationTransactionRecord
        do {
            journal = try passcodeRotationJournal()
            try Task.checkCancellation()
            transaction = try journal.begin(
                vaultID: current.payload.vaultID,
                oldLocator: current.locator,
                oldEnvelope: current.envelope,
                newLocator: newLocator,
                newEnvelope: replacement
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VaultUnlockError.mutationFailed
        }

        // Write the replacement first so a storage failure cannot strand the
        // user without a valid envelope. The authenticated journal makes the
        // following two-file transaction recoverable after process termination.
        do {
            try await store.writeIfAbsent(replacement, locator: newLocator)
        } catch VaultCredentialStoreError.locatorAlreadyExists {
            do {
                let outcome = try await journal.recover(
                    transaction,
                    credentialStore: store
                )
                if outcome == .replacementCommitted {
                    return unlockedVault(from: current.payload)
                }
                await limiter.recordFailure()
                throw VaultUnlockError.passcodeAlreadyUsed
            } catch let error as VaultUnlockError {
                throw error
            } catch {
                markCredentialRecoveryRequiredIfNeeded()
                throw VaultUnlockError.mutationFailed
            }
        } catch {
            if let outcome = try? await journal.recover(
                transaction,
                credentialStore: store
            ), outcome == .replacementCommitted {
                return unlockedVault(from: current.payload)
            }
            markCredentialRecoveryRequiredIfNeeded()
            throw VaultUnlockError.mutationFailed
        }
        do {
            try await store.delete(locator: current.locator)
            try journal.finish(transaction)
        } catch {
            // Best-effort immediate convergence. If cleanup cannot complete,
            // the journal remains for mandatory startup recovery.
            if let outcome = try? await journal.recover(
                transaction,
                credentialStore: store
            ), outcome == .replacementCommitted {
                return unlockedVault(from: current.payload)
            }
            markCredentialRecoveryRequiredIfNeeded()
            throw VaultUnlockError.mutationFailed
        }

        return unlockedVault(from: current.payload)
    }

    /// Authenticates a deletion request while reserving the credential mutation
    /// gate. This phase does not create a journal, delete a credential, or touch
    /// vault data. The returned grant must be paired with a session-retirement
    /// proof before deletion can begin.
    func authorizeVaultDeletion(
        currentPasscode: String,
        expectedVaultID: UUID
    ) async throws -> VaultDeletionAuthorization {
        try beginCredentialOperation()
        var releasesCredentialGate = true
        defer {
            if releasesCredentialGate {
                finishCredentialOperation()
            }
        }

        let current = try await authenticateExistingVault(
            passcode: currentPasscode,
            expectedVaultID: expectedVaultID
        )
        try Task.checkCancellation()

        let authorization = VaultDeletionAuthorization(
            vaultID: current.payload.vaultID,
            authorizationID: UUID()
        )
        pendingVaultDeletionAuthorization = PendingVaultDeletionAuthorization(
            authorizationID: authorization.authorizationID,
            vaultID: current.payload.vaultID,
            locator: current.locator,
            envelope: current.envelope,
            expiresAtUptime: authorizationUptime()
                + vaultDeletionAuthorizationLifetime
        )
        releasesCredentialGate = false
        return authorization
    }

    /// Releases an unused grant. A mismatched or already-consumed grant cannot
    /// disturb another pending deletion.
    @discardableResult
    func cancelVaultDeletionAuthorization(
        _ authorization: VaultDeletionAuthorization
    ) -> Bool {
        discardExpiredVaultDeletionAuthorizationIfNeeded()
        guard let pending = pendingVaultDeletionAuthorization,
              pending.authorizationID == authorization.authorizationID,
              pending.vaultID == authorization.vaultID else {
            return false
        }
        pendingVaultDeletionAuthorization = nil
        finishCredentialOperation()
        return true
    }

    /// Deletes the credential envelope first, cryptographically removing the
    /// app's route to the vault key, then removes encrypted vault data. A proof
    /// minted only after synchronous capability revocation and task drainage is
    /// required, making that phase boundary structural instead of call-order
    /// convention.
    func deleteVault(
        authorization: VaultDeletionAuthorization,
        revocationProof: VaultSession.VaultDeletionRevocationProof
    ) async throws {
        if let pending = pendingVaultDeletionAuthorization,
           authorizationUptime() >= pending.expiresAtUptime {
            pendingVaultDeletionAuthorization = nil
            finishCredentialOperation()
            throw VaultUnlockError.deletionAuthorizationExpired
        }
        guard let current = pendingVaultDeletionAuthorization,
              current.authorizationID == authorization.authorizationID,
              current.vaultID == authorization.vaultID,
              revocationProof.authorizationID == authorization.authorizationID,
              revocationProof.vaultID == authorization.vaultID else {
            throw VaultUnlockError.invalidDeletionAuthorization
        }
        pendingVaultDeletionAuthorization = nil
        defer { finishCredentialOperation() }
        try Task.checkCancellation()

        let journal: VaultDeletionTransactionJournal
        let transaction: VaultDeletionTransactionRecord
        do {
            journal = try vaultDeletionJournal()
            transaction = try journal.begin(
                vaultID: current.vaultID,
                credentialLocator: current.locator,
                credentialEnvelope: current.envelope
            )
        } catch {
            throw VaultUnlockError.mutationFailed
        }

        // Remove the only persisted wrapper around the random vault data key
        // before deleting encrypted blobs. If blob cleanup later fails, orphaned
        // ciphertext remains inaccessible through KeyHollow.
        do {
            try await store.delete(locator: current.locator)
        } catch {
            do {
                let outcome = try await journal.recover(
                    transaction,
                    credentialStore: store,
                    cleanup: vaultDataCleanupOperation()
                )
                if outcome == .credentialDestroyed {
                    return
                }
                throw VaultUnlockError.mutationFailed
            } catch VaultDeletionRecoveryError.credentialDestroyedCleanupIncomplete {
                markCredentialRecoveryRequiredIfNeeded()
                throw VaultUnlockError.credentialDestroyedCleanupIncomplete
            } catch let error as VaultUnlockError {
                throw error
            } catch {
                markCredentialRecoveryRequiredIfNeeded()
                throw VaultUnlockError.credentialStateUnknown
            }
        }
        do {
            try vaultDataCleanupOperation()(current.vaultID)
            try journal.finish(transaction)
        } catch {
            // Credential destruction succeeded, so do not recreate the envelope.
            // The authenticated journal keeps cleanup retryable at next startup.
            markCredentialRecoveryRequiredIfNeeded()
            throw VaultUnlockError.credentialDestroyedCleanupIncomplete
        }
    }

    private func checkCredentialLookupAllowed() async throws {
        do {
            try await limiter.checkAllowed()
        } catch UnlockAttemptLimiter.LimitError.temporarilyLocked(let until) {
            throw VaultUnlockError.temporarilyLocked(until)
        }
    }

    private func authenticateExistingVault(
        passcode: String,
        expectedVaultID: UUID? = nil
    ) async throws -> AuthenticatedVaultCredential {
        try await checkCredentialLookupAllowed()
        try Task.checkCancellation()

        guard PasscodePolicy.isValidForUnlock(passcode) else {
            await limiter.recordFailure()
            throw VaultUnlockError.invalidCredentials
        }

        do {
            let unlockKey = try deriveUnlockKey(passcode: passcode)
            try Task.checkCancellation()
            let locator = VaultLocator.derive(from: unlockKey)
            let persistedEnvelope = try await store.read(locator: locator)
            try Task.checkCancellation()
            guard let envelope = persistedEnvelope else {
                throw VaultUnlockError.invalidCredentials
            }
            let payload = try envelope.open(using: unlockKey)
            try Task.checkCancellation()
            if let expectedVaultID, payload.vaultID != expectedVaultID {
                throw VaultUnlockError.invalidCredentials
            }
            await limiter.recordSuccess()
            try Task.checkCancellation()
            return AuthenticatedVaultCredential(
                payload: payload,
                locator: locator,
                envelope: envelope
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch VaultUnlockError.invalidCredentials {
            await limiter.recordFailure()
            throw VaultUnlockError.invalidCredentials
        } catch {
            await limiter.recordFailure()
            throw VaultUnlockError.invalidCredentials
        }
    }

    private func deriveUnlockKey(passcode: String) throws -> SymmetricKey {
        let pepper = try secrets.loadOrCreate()
        let installationSalt = try secrets.loadOrCreateInstallationSalt()
        return try kdf.deriveKey(
            passcode: passcode,
            installationSalt: installationSalt,
            pepper: pepper
        )
    }

    private func portableRestoreJournalKey() throws -> SymmetricKey {
        try PortableVaultRestoreJournalKeySchedule.key(
            devicePepper: secrets.loadOrCreate()
        )
    }

    private func passcodeRotationJournal() throws -> PasscodeRotationTransactionJournal {
        let authenticationKey = try PasscodeRotationJournalKeySchedule.key(
            devicePepper: secrets.loadOrCreate()
        )
        return try PasscodeRotationTransactionJournal(
            authenticationKey: authenticationKey,
            rootOverride: passcodeRotationJournalRootOverride
        )
    }

    private func vaultDeletionJournal() throws -> VaultDeletionTransactionJournal {
        let authenticationKey = try VaultDeletionJournalKeySchedule.key(
            devicePepper: secrets.loadOrCreate()
        )
        return try VaultDeletionTransactionJournal(
            authenticationKey: authenticationKey,
            rootOverride: vaultDeletionJournalRootOverride
        )
    }

    private func vaultDataCleanupOperation() -> @Sendable (UUID) throws -> Void {
        let photoRoot = self.photoStorageRootOverride
        let additionalDataRemover = self.additionalVaultDataRemover
        return { vaultID in
            var firstError: Error?
            do {
                try VaultPhotoStore.destroyVaultData(
                    vaultID: vaultID,
                    storageRoot: photoRoot
                )
            } catch {
                firstError = error
            }
            do {
                try additionalDataRemover(vaultID)
            } catch {
                if firstError == nil { firstError = error }
            }
            if let firstError { throw firstError }
        }
    }

    /// Actor methods can re-enter while awaiting storage. This synchronous gate
    /// is acquired before the first suspension point so an unlock or
    /// re-authentication can never observe a credential while a mutation is in
    /// an intermediate state.
    private func beginCredentialOperation(allowsRecovery: Bool = false) throws {
        discardExpiredVaultDeletionAuthorizationIfNeeded()
        guard !credentialOperationInProgress else {
            throw VaultUnlockError.operationInProgress
        }
        if !allowsRecovery {
            guard !credentialRecoveryRequired else {
                throw VaultUnlockError.credentialRecoveryRequired
            }
            do {
                guard !(try hasPendingCredentialTransactions()) else {
                    credentialRecoveryRequired = true
                    throw VaultUnlockError.credentialRecoveryRequired
                }
            } catch let error as VaultUnlockError {
                throw error
            } catch {
                credentialRecoveryRequired = true
                throw VaultUnlockError.credentialRecoveryRequired
            }
        }
        credentialOperationInProgress = true
    }

    private func finishCredentialOperation() {
        credentialOperationInProgress = false
    }

    private func discardExpiredVaultDeletionAuthorizationIfNeeded() {
        guard let pending = pendingVaultDeletionAuthorization,
              authorizationUptime() >= pending.expiresAtUptime else { return }
        pendingVaultDeletionAuthorization = nil
        credentialOperationInProgress = false
    }

    private func hasPendingCredentialTransactions() throws -> Bool {
        try PasscodeRotationTransactionJournal.recoveryRequired(
            rootOverride: passcodeRotationJournalRootOverride
        ) || VaultDeletionTransactionJournal.recoveryRequired(
            rootOverride: vaultDeletionJournalRootOverride
        ) || PortableVaultRestoreTransactionJournal.recoveryRequired(
            journalRootOverride: portableRestoreJournalRootOverride
        )
    }

    private func recoverPendingCredentialTransactions() async throws {
        if try PasscodeRotationTransactionJournal.recoveryRequired(
            rootOverride: passcodeRotationJournalRootOverride
        ) {
            try await passcodeRotationJournal().recoverAll(credentialStore: store)
        }

        if try VaultDeletionTransactionJournal.recoveryRequired(
            rootOverride: vaultDeletionJournalRootOverride
        ) {
            let cleanup = vaultDataCleanupOperation()
            try await vaultDeletionJournal().recoverAll(
                credentialStore: store,
                cleanup: cleanup
            )
        }

        if try PortableVaultRestoreTransactionJournal.recoveryRequired(
            journalRootOverride: portableRestoreJournalRootOverride
        ) {
            let installer = try PortableVaultRestoreInstaller(
                credentialStore: store,
                journalAuthenticationKey: try portableRestoreJournalKey(),
                journalRootOverride: portableRestoreJournalRootOverride,
                photoDataRootOverride: photoStorageRootOverride,
                generalFileDataRootOverride: generalFileStorageRootOverride
            )
            try await installer.recoverInterruptedInstalls()
        }
    }

    private func markCredentialRecoveryRequiredIfNeeded() {
        do {
            if try hasPendingCredentialTransactions() {
                credentialRecoveryRequired = true
            }
        } catch {
            credentialRecoveryRequired = true
        }
    }

    private func unlockedVault(from payload: VaultPayload) -> UnlockedVault {
        UnlockedVault(
            vaultID: payload.vaultID,
            vaultKey: SymmetricKey(data: payload.vaultKey),
            createdAt: payload.createdAt
        )
    }
}

