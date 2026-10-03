import Foundation
import KeyHollowFolderPresentationAddOn
import KeyHollowGeneralFileSupportAddOn

/// Per-import policy, consumed only inside the gallery's registered session task.
/// Retains one fallback count, never URLs, stores, sessions, tasks or operations.
@MainActor
struct VaultGalleryFileImport {
    private var rootFallbackCount = 0

    mutating func place(
        _ record: VaultGeneralFileRecord,
        destination: VaultImportDestination,
        move: (VaultPresentedContentReference, UUID) async throws -> Void
    ) async throws {
        let placed = try await destination.place(
            VaultPresentedContentReference(kind: .generalFile, id: record.id),
            move: move
        )
        if !placed { rootFallbackCount += 1 }
    }

    static func perform(
        importFiles: @MainActor (inout Self) async throws -> VaultGeneralFileImportResult,
        isCurrent: () -> Bool,
        reload: () async -> Void
    ) async -> String? {
        var batch = Self()
        do {
            let outcome = try await importFiles(&batch)
            guard !Task.isCancelled, isCurrent() else { return nil }
            await reload()
            return GeneralFileImportPresentation.message(for: outcome)
                + VaultImportDestination.recoveryMessage(rootCount: batch.rootFallbackCount)
        } catch is CancellationError {
            return nil
        } catch {
            return "The selected files could not be imported into this vault."
        }
    }
}
