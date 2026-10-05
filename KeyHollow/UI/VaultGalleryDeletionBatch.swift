/// Counts selected deletions across the two stores. The caller retains typed
/// record routing, the session task, catalog refresh and selection cleanup.
@MainActor
struct VaultGalleryDeletionBatch {
    private let deletedCount: Int
    private let failedCount: Int

    var message: String {
        if deletedCount > 0, failedCount == 0 {
            let noun = deletedCount == 1 ? "item" : "items"
            return "Deleted \(deletedCount) \(noun) from this vault."
        } else if deletedCount > 0 {
            return "Deleted \(deletedCount) selected items. \(failedCount) items could not be removed."
        } else {
            return "The selected items could not be deleted from the vault."
        }
    }

    static func perform(
        photoCount: Int,
        fileCount: Int,
        deletePhotos: @MainActor () async throws -> Bool,
        deleteFiles: @MainActor () async throws -> Bool
    ) async -> Self? {
        do {
            let photos = try await deleting(count: photoCount, using: deletePhotos)
            let files = try await deleting(count: fileCount, using: deleteFiles)
            return Self(
                deletedCount: photos.deletedCount + files.deletedCount,
                failedCount: photos.failedCount + files.failedCount
            )
        } catch {
            return nil
        }
    }

    private static func deleting(
        count: Int,
        using operation: @MainActor () async throws -> Bool
    ) async throws -> Self {
        guard count > 0 else { return Self(deletedCount: 0, failedCount: 0) }
        do {
            if try await operation() {
                return Self(deletedCount: count, failedCount: 0)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // An ordinary store failure does not prevent the other store's batch.
        }
        return Self(deletedCount: 0, failedCount: count)
    }
}
