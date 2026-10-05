import KeyHollowPhotoCore
import KeyHollowPhotosAdapter

/// Sequential save policy. The caller owns decryption and the Photos handoff;
/// no decrypted payload, store or session survives in this value.
@MainActor
enum VaultGalleryPhotoSaveBatch {
    struct Completion: Sendable {
        let message: String
        let clearSelection: Bool
    }

    static func perform(
        _ photos: [VaultPhotoRecord],
        save: @MainActor (VaultPhotoRecord) async throws -> PhotoLibrarySaveResult
    ) async -> Completion? {
        var savedCount = 0
        var failedCount = 0
        var permissionDenied = false

        for photo in photos {
            guard !Task.isCancelled else { return nil }
            do {
                switch try await save(photo) {
                case .saved:
                    savedCount += 1
                case .permissionDenied:
                    permissionDenied = true
                case .failed:
                    failedCount += 1
                }
            } catch {
                failedCount += 1
            }
            if permissionDenied { break }
        }

        guard !Task.isCancelled else { return nil }
        if permissionDenied {
            return Completion(
                message: "Allow KeyHollow to add photos in iPhone Settings, then try again.",
                clearSelection: false
            )
        } else if savedCount > 0 {
            let noun = savedCount == 1 ? "photo" : "photos"
            let message: String
            if failedCount > 0 {
                message = "Saved \(savedCount) \(noun) to Photos. \(failedCount) selected photos could not be decrypted or saved."
            } else {
                message = "Saved \(savedCount) \(noun) to Photos. The encrypted vault copies were kept."
            }
            return Completion(message: message, clearSelection: true)
        } else {
            return Completion(
                message: "The selected photos could not be authenticated, decrypted, or saved.",
                clearSelection: false
            )
        }
    }
}
