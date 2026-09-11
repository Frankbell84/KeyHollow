import Foundation

/// Identifies the protected store that owns an item without granting access to
/// that store. The source is part of identity so a photo and a general file
/// with the same UUID remain distinct navigation targets.
public enum VaultMediaNavigationSource: Hashable, Sendable {
    case photo
    case generalFile
}

public struct VaultMediaNavigationID: Hashable, Identifiable, Sendable {
    public let source: VaultMediaNavigationSource
    public let rawValue: UUID

    public init(source: VaultMediaNavigationSource, rawValue: UUID) {
        self.source = source
        self.rawValue = rawValue
    }

    public var id: Self { self }
}

public enum VaultMediaNavigationKind: Hashable, Sendable {
    case image
    case video

    public var accessibilityName: String {
        switch self {
        case .image:
            "Image"
        case .video:
            "Video"
        }
    }
}

/// Immutable, presentation-only metadata for one compatible media item. The
/// application owns all authentication, decryption, and payload lifetimes.
public struct VaultMediaNavigationItem: Identifiable, Hashable, Sendable {
    public let id: VaultMediaNavigationID
    public let kind: VaultMediaNavigationKind
    public let title: String

    public init(
        id: VaultMediaNavigationID,
        kind: VaultMediaNavigationKind,
        title: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
    }

    public var accessibilityTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
    }
}

public enum VaultMediaNavigationDirection: Equatable, Sendable {
    case previous
    case next
}

public enum VaultMediaNavigationQueueError: Error, Equatable, Sendable {
    case emptyQueue
    case duplicateItemID(VaultMediaNavigationID)
    case selectionNotFound(VaultMediaNavigationID)
}

/// An immutable snapshot of the compatible media in one visible gallery
/// location. It carries metadata only: no payload, storage location, or security
/// capability can be retained by the navigation add-on.
public struct VaultMediaNavigationQueue: Equatable, Sendable {
    public let items: [VaultMediaNavigationItem]
    public let selectedID: VaultMediaNavigationID

    private let selectedIndex: Int

    public init(
        items: [VaultMediaNavigationItem],
        selectedID: VaultMediaNavigationID
    ) throws {
        guard !items.isEmpty else {
            throw VaultMediaNavigationQueueError.emptyQueue
        }

        var seenIDs = Set<VaultMediaNavigationID>()
        for item in items where !seenIDs.insert(item.id).inserted {
            throw VaultMediaNavigationQueueError.duplicateItemID(item.id)
        }

        guard let selectedIndex = items.firstIndex(where: { $0.id == selectedID }) else {
            throw VaultMediaNavigationQueueError.selectionNotFound(selectedID)
        }

        self.init(
            validatedItems: items,
            selectedIndex: selectedIndex
        )
    }

    private init(
        validatedItems: [VaultMediaNavigationItem],
        selectedIndex: Int
    ) {
        self.items = validatedItems
        self.selectedIndex = selectedIndex
        self.selectedID = validatedItems[selectedIndex].id
    }

    public var currentItem: VaultMediaNavigationItem {
        items[selectedIndex]
    }

    /// Zero-based index for collection coordination.
    public var currentIndex: Int { selectedIndex }

    /// One-based position for visible and spoken presentation.
    public var currentPosition: Int { selectedIndex + 1 }

    public var count: Int { items.count }

    public var previousItem: VaultMediaNavigationItem? {
        item(in: .previous)
    }

    public var nextItem: VaultMediaNavigationItem? {
        item(in: .next)
    }

    public var canNavigatePrevious: Bool { previousItem != nil }

    public var canNavigateNext: Bool { nextItem != nil }

    public var accessibilityLabel: String {
        "\(currentItem.accessibilityTitle), \(currentItem.kind.accessibilityName)"
    }

    public var accessibilityPosition: String {
        "\(currentPosition) of \(count)"
    }

    public func item(
        in direction: VaultMediaNavigationDirection
    ) -> VaultMediaNavigationItem? {
        let destinationIndex: Int
        switch direction {
        case .previous:
            destinationIndex = selectedIndex - 1
        case .next:
            destinationIndex = selectedIndex + 1
        }

        guard items.indices.contains(destinationIndex) else { return nil }
        return items[destinationIndex]
    }

    /// Returns a new queue at the requested item. Invalid selection attempts
    /// fail without mutating the current snapshot.
    public func selecting(
        _ id: VaultMediaNavigationID
    ) throws -> VaultMediaNavigationQueue {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw VaultMediaNavigationQueueError.selectionNotFound(id)
        }
        return VaultMediaNavigationQueue(
            validatedItems: items,
            selectedIndex: index
        )
    }

    /// Returns nil at a boundary instead of wrapping to another item.
    public func selecting(
        _ direction: VaultMediaNavigationDirection
    ) -> VaultMediaNavigationQueue? {
        guard item(in: direction) != nil else { return nil }
        return VaultMediaNavigationQueue(
            validatedItems: items,
            selectedIndex: direction == .previous
                ? selectedIndex - 1
                : selectedIndex + 1
        )
    }

    /// Removes presentation metadata only. If the active item is removed, the
    /// item that followed it is preferred, then the preceding item. Nil means
    /// no navigable media remains and the application should dismiss.
    public func removing(
        _ id: VaultMediaNavigationID
    ) -> VaultMediaNavigationQueue? {
        guard let removedIndex = items.firstIndex(where: { $0.id == id }) else {
            return self
        }

        var remainingItems = items
        remainingItems.remove(at: removedIndex)
        guard !remainingItems.isEmpty else { return nil }

        if id == selectedID {
            return VaultMediaNavigationQueue(
                validatedItems: remainingItems,
                selectedIndex: min(removedIndex, remainingItems.count - 1)
            )
        }

        // The current item is guaranteed to remain because IDs are unique.
        let remainingSelectionIndex = removedIndex < selectedIndex
            ? selectedIndex - 1
            : selectedIndex
        return VaultMediaNavigationQueue(
            validatedItems: remainingItems,
            selectedIndex: remainingSelectionIndex
        )
    }
}
