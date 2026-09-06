import Foundation

/// Presentation-only selection state spanning both protected content stores.
/// It owns references, never plaintext or storage capabilities.
public struct VaultGallerySelection: Equatable, Sendable {
    public enum Item: Hashable, Sendable {
        case photo(UUID)
        case generalFile(UUID)
    }

    public private(set) var items: Set<Item> = []

    public init() {}

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    public func contains(_ item: Item) -> Bool {
        items.contains(item)
    }

    public func containsAll(_ visibleItems: [Item]) -> Bool {
        let visible = Set(visibleItems)
        return !visible.isEmpty && items == visible
    }

    public mutating func toggle(_ item: Item) {
        if items.contains(item) {
            items.remove(item)
        } else {
            items.insert(item)
        }
    }

    public mutating func toggleAll(_ visibleItems: [Item]) {
        let visible = Set(visibleItems)
        if !visible.isEmpty, items == visible {
            items.removeAll()
        } else {
            items = visible
        }
    }

    public mutating func selectOnly(_ item: Item) {
        items = [item]
    }

    public mutating func remove(_ item: Item) {
        items.remove(item)
    }

    public mutating func reconcile(validItems: [Item]) {
        items.formIntersection(Set(validItems))
    }

    public mutating func clear() {
        items.removeAll()
    }
}
