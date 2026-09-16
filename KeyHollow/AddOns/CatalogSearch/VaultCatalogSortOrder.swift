import Foundation

/// Immutable, presentation-only ordering policy for already-visible catalog
/// metadata. The add-on receives bounded display titles, dates, and stable
/// ordinals only; it never receives protected records, identifiers, storage
/// capabilities, URLs, ciphertext, or plaintext payloads.
public enum VaultCatalogSortOrder: String, CaseIterable, Equatable, Hashable, Sendable {
    case vaultOrder
    case newestFirst
    case oldestFirst
    case nameAscending
    case nameDescending

    public func orderedOffsets(
        for descriptors: [VaultCatalogSortDescriptor]
    ) -> [Int] {
        descriptors.enumerated().sorted { first, second in
            if precedes(first.element, second.element) {
                return true
            }
            if precedes(second.element, first.element) {
                return false
            }
            return first.offset < second.offset
        }.map { $0.offset }
    }

    private func precedes(
        _ first: VaultCatalogSortDescriptor,
        _ second: VaultCatalogSortDescriptor
    ) -> Bool {
        switch self {
        case .vaultOrder:
            return first.stableOrdinal < second.stableOrdinal

        case .newestFirst:
            if first.timestamp != second.timestamp {
                return first.timestamp > second.timestamp
            }
            return compareNamesThenOrdinal(first, second, ascending: true)

        case .oldestFirst:
            if first.timestamp != second.timestamp {
                return first.timestamp < second.timestamp
            }
            return compareNamesThenOrdinal(first, second, ascending: true)

        case .nameAscending:
            let nameOrder = first.normalizedTitle.compare(
                second.normalizedTitle,
                options: [.numeric],
                locale: Self.stableLocale
            )
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return compareDatesThenOrdinal(first, second)

        case .nameDescending:
            let nameOrder = first.normalizedTitle.compare(
                second.normalizedTitle,
                options: [.numeric],
                locale: Self.stableLocale
            )
            if nameOrder != .orderedSame {
                return nameOrder == .orderedDescending
            }
            return compareDatesThenOrdinal(first, second)
        }
    }

    private func compareNamesThenOrdinal(
        _ first: VaultCatalogSortDescriptor,
        _ second: VaultCatalogSortDescriptor,
        ascending: Bool
    ) -> Bool {
        let nameOrder = first.normalizedTitle.compare(
            second.normalizedTitle,
            options: [.numeric],
            locale: Self.stableLocale
        )
        if nameOrder != .orderedSame {
            return ascending
                ? nameOrder == .orderedAscending
                : nameOrder == .orderedDescending
        }
        return first.stableOrdinal < second.stableOrdinal
    }

    private func compareDatesThenOrdinal(
        _ first: VaultCatalogSortDescriptor,
        _ second: VaultCatalogSortDescriptor
    ) -> Bool {
        if first.timestamp != second.timestamp {
            return first.timestamp > second.timestamp
        }
        return first.stableOrdinal < second.stableOrdinal
    }

    private static let stableLocale = Locale(identifier: "en_US_POSIX")
}

public struct VaultCatalogSortDescriptor: Equatable, Sendable {
    public static let maximumTitleCharacterCount = 1_024

    public let title: String
    public let timestamp: Date
    public let stableOrdinal: Int
    fileprivate let normalizedTitle: String

    public init(title: String, timestamp: Date, stableOrdinal: Int) {
        let boundedTitle = String(
            title.prefix(Self.maximumTitleCharacterCount)
        )
        self.title = boundedTitle
        self.timestamp = timestamp
        self.stableOrdinal = stableOrdinal
        normalizedTitle = boundedTitle
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive,
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
