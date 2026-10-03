import Foundation
import KeyHollowFolderPresentationAddOn
import KeyHollowGeneralFileSupportAddOn

/// The gallery's Files batch policy, executed inside its registered session task.
/// Operations are nonescaping; this owner retains no URLs, stores, session or task.
@MainActor
enum VaultGalleryFileImport {
    static func perform(
        destination: VaultImportDestination,
        importFiles: @MainActor (
            _ recordDidImport: (VaultGeneralFileRecord) async throws -> Void,
            _ progressDidChange: (GeneralFileImportProgressState) -> Void
        ) async throws -> VaultGeneralFileImportResult,
        move: (VaultPresentedContentReference, UUID) async throws -> Void,
        progressDidChange: (GeneralFileImportProgressState) -> Void,
        isCurrent: () -> Bool,
        reload: () async -> Void
    ) async -> String? {
        var rootFallbackCount = 0
        do {
            let outcome = try await importFiles(
                { record in
                    let placed = try await destination.place(
                        VaultPresentedContentReference(kind: .generalFile, id: record.id),
                        move: move
                    )
                    if !placed { rootFallbackCount += 1 }
                },
                { progressDidChange($0) }
            )
            guard !Task.isCancelled, isCurrent() else { return nil }
            await reload()
            return GeneralFileImportPresentation.message(for: outcome)
                + VaultImportDestination.recoveryMessage(rootCount: rootFallbackCount)
        } catch is CancellationError {
            return nil
        } catch {
            return "The selected files could not be imported into this vault."
        }
    }
}
