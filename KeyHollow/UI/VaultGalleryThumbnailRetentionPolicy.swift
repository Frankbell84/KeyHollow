import Foundation

/// Tracks decoded gallery-thumbnail retention without owning image bytes.
///
/// Live tiles are never selected for eviction. This prevents cache pressure
/// from replacing an already-rendered thumbnail with a placeholder while the
/// user is looking at it. Hidden entries are evicted in least-recently-used
/// order, and a temporarily over-budget visible set is allowed until tiles
/// leave the viewport.
public struct VaultGalleryThumbnailRetentionPolicy<Key: Hashable & Sendable>: Sendable {
    public let maximumCount: Int

    private var visibleKeys: Set<Key> = []
    private var accessOrder: [Key] = []

    public init(maximumCount: Int) {
        precondition(maximumCount > 0)
        self.maximumCount = maximumCount
    }

    public mutating func markVisible(_ key: Key) {
        visibleKeys.insert(key)
        recordAccess(key)
    }

    public mutating func markHidden(_ key: Key) {
        visibleKeys.remove(key)
    }

    public mutating func recordAccess(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    public mutating func retainOnly(_ validKeys: Set<Key>) {
        visibleKeys.formIntersection(validKeys)
        accessOrder.removeAll { !validKeys.contains($0) }
    }

    /// Returns hidden cache entries that the owner should remove. If every
    /// cached entry is currently visible, no eviction is requested; the next
    /// `markHidden` call gives the owner a safe opportunity to trim.
    public mutating func evictionCandidates(
        cachedKeys: Set<Key>
    ) -> [Key] {
        accessOrder.removeAll { !cachedKeys.contains($0) }

        var retained = cachedKeys
        var evictions: [Key] = []
        while retained.count > maximumCount {
            guard let index = accessOrder.firstIndex(where: {
                retained.contains($0) && !visibleKeys.contains($0)
            }) else {
                break
            }

            let key = accessOrder.remove(at: index)
            retained.remove(key)
            evictions.append(key)
        }
        return evictions
    }

    public func isVisible(_ key: Key) -> Bool {
        visibleKeys.contains(key)
    }
}
