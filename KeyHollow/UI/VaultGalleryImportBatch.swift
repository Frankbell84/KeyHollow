import Foundation
import KeyHollowFolderPresentationAddOn
import KeyHollowPhotosAdapter

enum VaultImportMode {
    case copy
    case move
}

/// A batch snapshot, consumed only inside the composition's registered task.
/// It retains counts and source identifiers, never payloads, stores or tasks.
struct VaultGalleryImportBatch {
    let mode: VaultImportMode
    let total: Int
    private(set) var importedCount = 0
    private(set) var failedCount = 0
    private(set) var identifiersToDelete: [String] = []
    private(set) var rootFallbackCount = 0

    init(mode: VaultImportMode, total: Int) {
        self.mode = mode
        self.total = total
    }

    mutating func recordFailure() {
        failedCount += 1
    }

    /// Encryption/verification must finish before placement or eligibility to
    /// delete an original. Canceled work and stale successful completions
    /// cannot publish a new batch snapshot.
    @MainActor
    func importing(
        sourceAssetIdentifier: String?,
        destination: VaultImportDestination,
        encrypt: () async throws -> VaultPresentedContentReference,
        move: (VaultPresentedContentReference, UUID) async throws -> Void,
        isCurrent: () -> Bool
    ) async -> Self? {
        var progress = self
        do {
            let item = try await encrypt()
            let placed = try await destination.place(item, move: move)
            try Task.checkCancellation()
            guard isCurrent() else { return nil }
            progress.importedCount += 1
            if !placed { progress.rootFallbackCount += 1 }
            if placed, progress.mode == .move, let identifier = sourceAssetIdentifier {
                progress.identifiersToDelete.append(identifier)
            }
        } catch is CancellationError {
            return nil
        } catch {
            progress.failedCount += 1
        }
        return progress
    }

    var shouldOfferOriginalDeletion: Bool {
        mode == .move && importedCount > 0
    }

    var allImportedItemsAreDeletable: Bool {
        identifiersToDelete.count == importedCount
    }

    /// A nil result leaves any existing gallery-refresh message untouched.
    /// The caller alone owns the iOS deletion prompt and its lifecycle barrier.
    func completionMessage(moveResult: PhotoMoveResult = .copiedOnly) -> String? {
        var message: String?
        if shouldOfferOriginalDeletion {
            switch moveResult {
            case .deleted:
                message = importResultMessage(action: "Moved")
            case .copiedOnly:
                let base = importResultMessage(action: "Encrypted")
                message = rootFallbackCount > 0
                    ? "\(base) Originals were kept because folder placement was incomplete."
                    : "\(base) iOS did not delete every original, so KeyHollow treats this batch as copied."
            }
        } else if importedCount > 0 {
            message = importResultMessage(action: "Copied")
        } else if failedCount > 0 {
            let noun = failedCount == 1 ? "item" : "items"
            message = "No items were imported. \(failedCount) selected \(noun) could not be read or exceeded the 100 MB video limit."
        }
        if rootFallbackCount > 0 {
            message = (message ?? "")
                + VaultImportDestination.recoveryMessage(rootCount: rootFallbackCount)
        }
        return message
    }

    private func importResultMessage(action: String) -> String {
        let noun = importedCount == 1 ? "item" : "items"
        if failedCount > 0 {
            let failedNoun = failedCount == 1 ? "item" : "items"
            return "\(action) \(importedCount) \(noun) into KeyHollow. \(failedCount) \(failedNoun) could not be imported."
        }
        return "\(action) \(importedCount) \(noun) into KeyHollow."
    }
}
