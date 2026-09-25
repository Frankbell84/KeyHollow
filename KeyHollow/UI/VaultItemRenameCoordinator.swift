import Foundation
import Combine
import KeyHollowPhotoCore
import KeyHollowGeneralFileSupportAddOn
import KeyHollowItemRenameAddOn

/// Keeps the editor and its mutation inside one registered sensitive task,
/// including the time spent waiting for the user. Lock clears bindings
/// synchronously and drains any already authorized encrypted replacement.
@MainActor
final class VaultItemRenameCoordinator: ObservableObject {
    struct PreparedRename: Sendable {
        let policy: ItemRenamePolicy
        let commit: @Sendable (String) async throws -> Void
    }

    @Published var draft = ""
    @Published private(set) var retainedExtension = ""
    @Published private(set) var error: String?
    @Published private(set) var isPresented = false
    @Published private(set) var isSaving = false
    @Published private(set) var isActive = false
    private var generation: UUID?
    private var taskID: UUID?
    private var submissions: AsyncStream<String>.Continuation?

    func begin(photoStore: VaultPhotoStore, id: UUID, session: VaultSession,
               finished: @escaping @MainActor (String?) async -> Void) {
        begin(session: session, prepare: {
            let snapshot = try await photoStore.renameSnapshot(for: id)
            return PreparedRename(
                policy: ItemRenamePolicy(displayName: snapshot.record.displayName ?? "", preservesExtension: false),
                commit: { _ = try await photoStore.rename(snapshot, to: $0) }
            )
        }, finished: finished)
    }

    func begin(fileStore: VaultGeneralFileStore, id: UUID, session: VaultSession,
               finished: @escaping @MainActor (String?) async -> Void) {
        begin(session: session, prepare: {
            let snapshot = try await fileStore.renameSnapshot(for: id)
            return PreparedRename(
                policy: ItemRenamePolicy(displayName: snapshot.record.displayName, preservesExtension: true),
                commit: { _ = try await fileStore.rename(snapshot, to: $0) }
            )
        }, finished: finished)
    }

    func begin(session: VaultSession,
               prepare: @escaping @Sendable () async throws -> PreparedRename,
               finished: @escaping @MainActor (String?) async -> Void) {
        guard !isActive, let context = session.activeVaultContext() else { return }
        let identifier = UUID()
        let epoch = session.securityEpoch
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        generation = identifier
        submissions = continuation
        isActive = true
        taskID = session.startSensitiveTask(onSessionRevocation: { [weak self] in
            self?.clear(identifier)
        }) { [weak self] capability in
            guard let self else { return }
            defer { self.clear(identifier) }
            @MainActor func isCurrent() -> Bool {
                !Task.isCancelled && !capability.isRevoked && self.generation == identifier
                    && session.securityEpoch == epoch && session.activeVaultID == context.id
            }
            do {
                guard isCurrent() else { return }
                let prepared = try await prepare()
                guard isCurrent() else { return }
                self.draft = prepared.policy.initialName
                self.retainedExtension = prepared.policy.retainedExtension
                self.isPresented = true
                for await draft in stream {
                    guard isCurrent() else { return }
                    let completeName: String
                    do {
                        completeName = try prepared.policy.completeName(for: draft)
                    } catch {
                        self.error = error.localizedDescription
                        self.isSaving = false
                        continue
                    }
                    try await prepared.commit(completeName)
                    guard isCurrent() else { return }
                    self.isPresented = false
                    self.draft = ""
                    self.retainedExtension = ""
                    await finished(nil)
                    return
                }
            } catch {
                guard isCurrent() else { return }
                self.isPresented = false
                self.draft = ""
                self.retainedExtension = ""
                await finished(Self.failureMessage(error))
            }
        }
        if taskID == nil { clear(identifier) }
    }

    func save() {
        guard isPresented, !isSaving else { return }
        isSaving = true
        error = nil
        submissions?.yield(draft)
    }

    func cancel(in session: VaultSession) {
        if let taskID { session.cancelSensitiveTask(taskID) }
        if let generation { clear(generation) }
    }

    private func clear(_ identifier: UUID) {
        guard generation == identifier else { return }
        submissions?.finish()
        submissions = nil
        generation = nil
        taskID = nil
        draft = ""
        retainedExtension = ""
        error = nil
        isPresented = false
        isSaving = false
        isActive = false
    }

    private static func failureMessage(_ error: Error) -> String {
        if (error as? VaultPhotoStore.StoreError) == .renameConflict
            || (error as? VaultGeneralFileStore.StoreError) == .renameConflict {
            return "The vault changed while Rename was open. Open Rename again to use the current item."
        }
        if (error as? VaultPhotoStore.StoreError) == .manifestCommitStateUnknown
            || (error as? VaultGeneralFileStore.StoreError) == .manifestCommitStateUnknown {
            return "The saved name could not be confirmed. Lock and reopen the vault to check it before trying again. Your encrypted content has been retained."
        }
        return "The name could not be saved. Check the current name before trying again."
    }
}
