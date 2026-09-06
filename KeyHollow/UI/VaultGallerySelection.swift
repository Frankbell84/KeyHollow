import Foundation

/// Presentation-only selection state spanning both protected content stores.
/// It owns references, never plaintext or storage capabilities.
struct VaultGallerySelection: Equatable {
    enum Item: Hashable {
        case photo(UUID)
        case generalFile(UUID)
    }

    private(set) var items: Set<Item> = []

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    func contains(_ item: Item) -> Bool {
        items.contains(item)
    }

    func containsAll(_ visibleItems: [Item]) -> Bool {
        let visible = Set(visibleItems)
        return !visible.isEmpty && items == visible
    }

    mutating func toggle(_ item: Item) {
        if items.contains(item) {
            items.remove(item)
        } else {
            items.insert(item)
        }
    }

    mutating func toggleAll(_ visibleItems: [Item]) {
        let visible = Set(visibleItems)
        if !visible.isEmpty, items == visible {
            items.removeAll()
        } else {
            items = visible
        }
    }

    mutating func selectOnly(_ item: Item) {
        items = [item]
    }

    mutating func remove(_ item: Item) {
        items.remove(item)
    }

    mutating func reconcile(validItems: [Item]) {
        items.formIntersection(Set(validItems))
    }

    mutating func clear() {
        items.removeAll()
    }
}
