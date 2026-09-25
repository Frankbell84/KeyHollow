import Foundation
import KeyHollowFolderPresentationAddOn

/// Captured before opening a picker; navigation and a later unlock cannot
/// redirect an in-flight import into another folder or vault session.
struct VaultImportDestination: Equatable {
    let vaultID: UUID
    let securityEpoch: UInt64
    let folderID: UUID?

    func matches(vaultID: UUID?, securityEpoch: UInt64) -> Bool {
        self.vaultID == vaultID && self.securityEpoch == securityEpoch
    }

    /// Content has already been encrypted and verified by its owning store.
    /// A metadata failure preserves that copy at root and keeps the original.
    @MainActor
    func place(
        _ item: VaultPresentedContentReference,
        move: (VaultPresentedContentReference, UUID) async throws -> Void
    ) async throws -> Bool {
        try Task.checkCancellation()
        guard let folderID else { return true }
        do {
            try await move(item, folderID)
            try Task.checkCancellation()
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return false
        }
    }

    static func recoveryMessage(rootCount: Int) -> String {
        guard rootCount > 0 else { return "" }
        return " \(rootCount) imported items could not be placed in the chosen folder and remain at Vault Root. Their originals were kept. Use Select then Move to organize them."
    }
}
