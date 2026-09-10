import Foundation
import CryptoKit
import KeyHollowCryptoCore
import KeyHollowPhotoCore
import KeyHollowTransferCore
import KeyHollowVaultCore

enum VaultAccessError: Error, Equatable {
    case revoked
}

enum VaultSessionDeletionError: Error, Equatable {
    case inactiveOrMismatchedVault
}

/// Captures the sensitive tasks canceled by one lock transition. Locking and
/// key revocation happen synchronously; production lifecycle code can then
/// await this value so temporary plaintext cleanup reaches a terminal state.
struct VaultSessionLockBarrier: Sendable {
    fileprivate let tasks: [Task<Void, Never>]

    var isEmpty: Bool { tasks.isEmpty }

    func wait() async {
        for task in tasks {
            await task.value
        }
    }
}

/// A narrow, revocable boundary around a vault key.
///
/// Callers never receive a key to retain. A revocation waits for any currently
/// executing synchronous key operation to leave the critical section, clears
/// the capability's key reference, and prevents every later operation.
final class VaultAccessCapability: PortableVaultExportAccess, @unchecked Sendable {
    let vaultID: UUID

    private let lock = NSLock()
    private var vaultKey: SymmetricKey?

    init(vaultID: UUID, vaultKey: SymmetricKey) {
        self.vaultID = vaultID
        self.vaultKey = vaultKey
    }

    private func withKey<T>(_ operation: (SymmetricKey) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let vaultKey else { throw VaultAccessError.revoked }
        return try operation(vaultKey)
    }

    func seal(_ plaintext: Data, for purpose: VaultKeyPurpose) throws -> Data {
        try withKey { vaultKey in
            try CryptoBox.seal(plaintext, using: derivedKey(from: vaultKey, for: purpose))
        }
    }

    func open(_ ciphertext: Data, for purpose: VaultKeyPurpose) throws -> Data {
        try withKey { vaultKey in
            try CryptoBox.open(ciphertext, using: derivedKey(from: vaultKey, for: purpose))
        }
    }

    func preparePortableArchive(
        createdAt: Date,
        credential: PortableArchiveCredential,
        keyDeriver: any PortableArchiveKeyDeriving
    ) throws -> PreparedEncryptedVaultArchive {
        try withKey { vaultKey in
            let keyData = vaultKey.withUnsafeBytes { Data($0) }
            return try EncryptedVaultArchiveHeader.prepare(
                vaultPayload: VaultPayload(
                    vaultID: vaultID,
                    vaultKey: keyData,
                    createdAt: createdAt
                ),
                credential: credential,
                keyDeriver: keyDeriver
            )
        }
    }

    func checkAccess() throws {
        _ = try withKey { _ in () }
    }

    /// Application-composition seam for independently compiled local add-ons.
    /// Callers receive a scoped cryptographic operation, never the vault key.
    func sealScopedData(_ plaintext: Data, domain: String) throws -> Data {
        try withKey { vaultKey in
            try CryptoBox.seal(plaintext, using: scopedKey(from: vaultKey, domain: domain))
        }
    }

    func openScopedData(_ ciphertext: Data, domain: String) throws -> Data {
        try withKey { vaultKey in
            try CryptoBox.open(ciphertext, using: scopedKey(from: vaultKey, domain: domain))
        }
    }

    /// Opens add-on data and consumes it while the capability's key-lifetime
    /// fence is still held. This intentionally avoids returning decrypted
    /// bytes across the revocation boundary.
    func consumeOpenedScopedData(
        _ ciphertext: Data,
        domain: String,
        _ consumer: (Data) throws -> Void
    ) throws {
        try withKey { vaultKey in
            let plaintext = try CryptoBox.open(
                ciphertext,
                using: scopedKey(from: vaultKey, domain: domain)
            )
            try consumer(plaintext)
        }
    }

    private func scopedKey(from vaultKey: SymmetricKey, domain: String) -> SymmetricKey {
        let label = "keyhollow.addon.\(domain)"
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: vaultKey,
            salt: Data(label.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }

    private func derivedKey(from vaultKey: SymmetricKey, for purpose: VaultKeyPurpose) -> SymmetricKey {
        switch purpose {
        case .manifest:
            VaultPhotoKeySchedule.manifestKey(from: vaultKey)
        case .photo(let id):
            VaultPhotoKeySchedule.photoKey(from: vaultKey, id: id)
        case .thumbnail(let id):
            VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: id)
        }
    }

    func revoke() {
        lock.lock()
        vaultKey = nil
        lock.unlock()
    }

    var isRevoked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return vaultKey == nil
    }
}

@MainActor
final class VaultSession: ObservableObject {
    /// An opaque, epoch-bound authorization for an asynchronous authentication
    /// result to become the active session. Locking or completing another access
    /// transition invalidates every outstanding authorization from that epoch.
    struct UnlockAuthorization: Sendable {
        fileprivate let transition: UInt64
    }

    /// Proof that this session revoked the authorization's matching vault
    /// capability and observed all registered sensitive tasks reach terminal
    /// cleanup. Only `VaultSession` can mint this value.
    struct VaultDeletionRevocationProof: Sendable {
        let vaultID: UUID
        let authorizationID: UUID

        fileprivate init(vaultID: UUID, authorizationID: UUID) {
            self.vaultID = vaultID
            self.authorizationID = authorizationID
        }
    }

    private struct PendingVaultAccess {
        let transition: UInt64
        let vaultID: UUID
        let key: SymmetricKey
    }

    @Published private(set) var isUnlocked = false
    @Published private(set) var activeVaultID: UUID?
    @Published private(set) var isSystemInteractionActive = false
    @Published private(set) var securityEpoch: UInt64 = 0

    private var activeCapability: VaultAccessCapability?
    private var systemInteractionCount = 0
    private var sensitiveTasks: [UUID: Task<Void, Never>] = [:]
    private var accessTransitionEpoch: UInt64 = 0
    private var pendingAccessRetirement: VaultSessionLockBarrier?
    private var pendingAccess: PendingVaultAccess?
    private var pendingRetirementEpoch: UInt64 = 0

    var isSystemPhotoOperationActive: Bool { isSystemInteractionActive }

    func authorizeUnlockCompletion() -> UnlockAuthorization {
        UnlockAuthorization(transition: accessTransitionEpoch)
    }

    /// Publishes an asynchronous authentication result only if the session has
    /// not locked or started another access transition since work began.
    @discardableResult
    func completeUnlock(
        vaultID: UUID,
        key: SymmetricKey,
        authorization: UnlockAuthorization
    ) -> Bool {
        guard !Task.isCancelled,
              authorization.transition == accessTransitionEpoch else {
            return false
        }
        transitionToUnlocked(vaultID: vaultID, key: key)
        return true
    }

#if DEBUG
    /// Immediate access setup retained only for deterministic unit-test fixtures.
    func unlock(vaultID: UUID, key: SymmetricKey) {
        transitionToUnlocked(vaultID: vaultID, key: key)
    }
#endif

    private func transitionToUnlocked(vaultID: UUID, key: SymmetricKey) {
        accessTransitionEpoch &+= 1
        let transition = accessTransitionEpoch
        // Release any superseded key immediately. Pending waiter tasks retain
        // only their cleanup barrier and transition token, never key material.
        pendingAccess = nil
        let hadRetiringAccess = activeCapability != nil || !sensitiveTasks.isEmpty
        let currentRetirement = retireActiveAccess(
            incrementSecurityEpoch: hadRetiringAccess
        )
        let barrier = combinedBarrier(
            pendingAccessRetirement,
            currentRetirement
        )

        guard !barrier.isEmpty else {
            retainPendingRetirement(barrier)
            publishAccess(vaultID: vaultID, key: key)
            return
        }
        retainPendingRetirement(barrier)
        pendingAccess = PendingVaultAccess(
            transition: transition,
            vaultID: vaultID,
            key: key
        )

        // Do not expose a new vault while plaintext cleanup from the previous
        // access context is still running. This detached transition also works
        // when an import's protected task is itself part of the barrier: that
        // operation returns, reaches terminal cleanup, and only then publishes.
        Task { @MainActor [weak self] in
            await barrier.wait()
            self?.publishPendingAccess(for: transition)
        }
    }

    private func publishPendingAccess(for transition: UInt64) {
        guard accessTransitionEpoch == transition,
              let pendingAccess,
              pendingAccess.transition == transition else { return }
        self.pendingAccess = nil
        publishAccess(vaultID: pendingAccess.vaultID, key: pendingAccess.key)
    }

    private func publishAccess(vaultID: UUID, key: SymmetricKey) {
        activeVaultID = vaultID
        activeCapability = VaultAccessCapability(vaultID: vaultID, vaultKey: key)
        isUnlocked = true
    }

    var hasActiveAccess: Bool {
        isUnlocked && activeCapability?.isRevoked == false
    }

    func activeVaultContext() -> (id: UUID, access: VaultAccessCapability)? {
        guard isUnlocked,
              let activeVaultID,
              let activeCapability,
              !activeCapability.isRevoked else { return nil }
        return (activeVaultID, activeCapability)
    }

    /// Starts work that must not outlive the unlocked vault session. Locking
    /// revokes the capability first, then cancels every registered task.
    @discardableResult
    func startSensitiveTask(
        _ operation: @escaping @MainActor (VaultAccessCapability) async -> Void
    ) -> UUID? {
        guard isUnlocked,
              let capability = activeCapability,
              !capability.isRevoked else { return nil }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            if !Task.isCancelled {
                await operation(capability)
            }
            self?.sensitiveTasks[id] = nil
        }
        sensitiveTasks[id] = task
        return id
    }

    /// Runs and awaits one lifecycle-owned sensitive operation. The internal
    /// task is registered before work begins so `lockAndWait()` can revoke,
    /// cancel, and observe terminal cleanup. Cancellation of the awaiting
    /// caller is propagated to the registered task and awaited as well.
    func performSensitiveTask(
        _ operation: @escaping @MainActor (VaultAccessCapability) async -> Void
    ) async {
        guard !Task.isCancelled,
              isUnlocked,
              let capability = activeCapability,
              !capability.isRevoked else { return }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.sensitiveTasks[id] = nil }
            guard !Task.isCancelled else { return }
            await operation(capability)
        }
        sensitiveTasks[id] = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Cancels one lifecycle-owned sensitive operation without affecting other
    /// vault work. The operation remains responsible for cancellation checks
    /// around any in-flight synchronous cryptographic or decoding boundary.
    func cancelSensitiveTask(_ id: UUID) {
        sensitiveTasks[id]?.cancel()
    }

    /// Cancels one registered operation and does not return until its terminal
    /// cleanup has run. User-driven dismissal uses this barrier so a captured
    /// credential or protected temporary lease cannot outlive its screen.
    func cancelSensitiveTaskAndWait(_ id: UUID) async {
        guard let task = sensitiveTasks[id] else { return }
        task.cancel()
        await task.value
    }

    /// Tracks cryptographic work that does not use the currently unlocked
    /// vault capability, such as authenticating an encrypted portable vault.
    /// Background locking cancels this work even when the keypad is showing.
    @discardableResult
    func startProtectedTask(
        _ operation: @escaping @MainActor () async -> Void
    ) -> UUID {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            if !Task.isCancelled {
                await operation()
            }
            self?.sensitiveTasks[id] = nil
        }
        sensitiveTasks[id] = task
        return id
    }

    func beginSystemInteraction() {
        systemInteractionCount += 1
        isSystemInteractionActive = true
    }

    func endSystemInteraction() {
        systemInteractionCount = max(0, systemInteractionCount - 1)
        isSystemInteractionActive = systemInteractionCount > 0
    }

    func beginSystemPhotoOperation() {
        beginSystemInteraction()
    }

    func endSystemPhotoOperation() {
        endSystemInteraction()
    }

    @discardableResult
    func lock() -> VaultSessionLockBarrier {
        accessTransitionEpoch &+= 1
        pendingAccess = nil
        let currentRetirement = retireActiveAccess(incrementSecurityEpoch: true)
        let barrier = combinedBarrier(
            pendingAccessRetirement,
            currentRetirement
        )
        retainPendingRetirement(barrier)
        return barrier
    }

    /// Revokes access synchronously, then waits for every sensitive task that
    /// held the capability to finish cleanup before producing deletion proof.
    func revokeAndDrainForVaultDeletion(
        _ authorization: VaultDeletionAuthorization
    ) async throws -> VaultDeletionRevocationProof {
        guard hasActiveAccess,
              activeVaultID == authorization.vaultID else {
            throw VaultSessionDeletionError.inactiveOrMismatchedVault
        }
        let proof = VaultDeletionRevocationProof(
            vaultID: authorization.vaultID,
            authorizationID: authorization.authorizationID
        )
        let barrier = lock()
        await barrier.wait()
        try Task.checkCancellation()
        return proof
    }

    private func combinedBarrier(
        _ first: VaultSessionLockBarrier?,
        _ second: VaultSessionLockBarrier
    ) -> VaultSessionLockBarrier {
        VaultSessionLockBarrier(tasks: (first?.tasks ?? []) + second.tasks)
    }

    private func retainPendingRetirement(_ barrier: VaultSessionLockBarrier) {
        pendingRetirementEpoch &+= 1
        let retirement = pendingRetirementEpoch
        guard !barrier.isEmpty else {
            pendingAccessRetirement = nil
            return
        }
        pendingAccessRetirement = barrier
        Task { @MainActor [weak self] in
            await barrier.wait()
            guard let self, self.pendingRetirementEpoch == retirement else { return }
            self.pendingAccessRetirement = nil
        }
    }

    private func retireActiveAccess(
        incrementSecurityEpoch: Bool
    ) -> VaultSessionLockBarrier {
        let capability = activeCapability
        let tasks = Array(sensitiveTasks.values)

        isUnlocked = false
        activeVaultID = nil
        activeCapability = nil
        systemInteractionCount = 0
        isSystemInteractionActive = false
        if incrementSecurityEpoch {
            securityEpoch &+= 1
        }

        // Revoke synchronously. Because capability key use is serialized under
        // the same lock, this returns only after an in-flight atomic key use has
        // ended; no later store operation can acquire the key.
        capability?.revoke()
        tasks.forEach { $0.cancel() }
        sensitiveTasks.removeAll()
        return VaultSessionLockBarrier(tasks: tasks)
    }

    /// Test and shutdown boundary that also observes registered task cleanup.
    func lockAndWait() async {
        let barrier = lock()
        await barrier.wait()
    }
}

/// The sole application path for destructive vault deletion. It holds the
/// service's one-use authorization across session revocation and guarantees the
/// grant is released on cancellation or any pre-commit failure.
@MainActor
enum VaultDeletionSessionCoordinator {
    static func deleteVault(
        service: VaultUnlockService,
        session: VaultSession,
        currentPasscode: String,
        expectedVaultID: UUID
    ) async throws {
        let authorization = try await service.authorizeVaultDeletion(
            currentPasscode: currentPasscode,
            expectedVaultID: expectedVaultID
        )
        do {
            let proof = try await session.revokeAndDrainForVaultDeletion(authorization)
            try await service.deleteVault(
                authorization: authorization,
                revocationProof: proof
            )
        } catch {
            await service.cancelVaultDeletionAuthorization(authorization)
            throw error
        }
    }
}


