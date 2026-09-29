import UIKit
import KeyHollowGalleryUI

/// Decoded thumbnail storage and retention, isolated from protected loading.
/// Composition supplies typed identities and clears this value on vault reset.
struct VaultGalleryThumbnailCache {
    private var photos: [UUID: UIImage] = [:]
    private var generalFiles: [UUID: UIImage] = [:]
    private var retention: VaultGalleryThumbnailRetentionPolicy<VaultGallerySelection.Item>

    // This matches the previous worst-case decoded-cache envelope (48 photo +
    // 48 Files-origin entries), but applies it as one source-neutral budget.
    init(maximumCount: Int = 96) {
        retention = VaultGalleryThumbnailRetentionPolicy(maximumCount: maximumCount)
    }

    subscript(id: VaultGallerySelection.Item) -> UIImage? {
        switch id {
        case .photo(let rawID):
            photos[rawID]
        case .generalFile(let rawID):
            generalFiles[rawID]
        }
    }

    mutating func insert(_ image: UIImage, for id: VaultGallerySelection.Item) {
        switch id {
        case .photo(let rawID):
            photos[rawID] = image
        case .generalFile(let rawID):
            generalFiles[rawID] = image
        }
        retention.recordAccess(id)
        trim()
    }

    mutating func markVisible(_ id: VaultGallerySelection.Item) {
        retention.markVisible(id)
        if cachedIDs.contains(id) {
            retention.recordAccess(id)
        }
    }

    mutating func markHidden(_ id: VaultGallerySelection.Item) {
        retention.markHidden(id)
        trim()
    }

    mutating func remove(_ id: VaultGallerySelection.Item) {
        switch id {
        case .photo(let rawID):
            photos.removeValue(forKey: rawID)
        case .generalFile(let rawID):
            generalFiles.removeValue(forKey: rawID)
        }
    }

    mutating func retainPhotos(withIDs validIDs: Set<UUID>) {
        photos = photos.filter { validIDs.contains($0.key) }
    }

    mutating func retainGeneralFiles(withIDs validIDs: Set<UUID>) {
        generalFiles = generalFiles.filter { validIDs.contains($0.key) }
    }

    /// Membership pruning is separate from each catalog's image pruning:
    /// refreshing one catalog must not discard the other catalog's images.
    mutating func retainKnownItems(_ known: Set<VaultGallerySelection.Item>) {
        retention.retainOnly(known)
    }

    mutating func removeAll() {
        self = Self(maximumCount: retention.maximumCount)
    }

    private var cachedIDs: Set<VaultGallerySelection.Item> {
        Set(photos.keys.map(VaultGallerySelection.Item.photo))
            .union(generalFiles.keys.map(VaultGallerySelection.Item.generalFile))
    }

    private mutating func trim() {
        for id in retention.evictionCandidates(cachedKeys: cachedIDs) {
            remove(id)
        }
    }
}
