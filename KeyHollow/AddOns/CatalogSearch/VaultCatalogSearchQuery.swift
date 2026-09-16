import Foundation

/// Immutable, presentation-only matching policy for the visible vault catalog.
/// The add-on receives display text only; it never receives protected records,
/// storage capabilities, URLs, ciphertext, or plaintext payloads.
public struct VaultCatalogSearchQuery: Equatable, Sendable {
    public static let maximumQueryCharacterCount = 256
    public static let maximumCandidateCharacterCount = 1_024

    public let rawValue: String
    private let normalizedTerms: [String]

    public init(_ rawValue: String) {
        let boundedValue = String(
            rawValue.prefix(Self.maximumQueryCharacterCount)
        )
        self.rawValue = boundedValue
        normalizedTerms = Self.normalized(boundedValue)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    public var isEmpty: Bool {
        normalizedTerms.isEmpty
    }

    public func matches(_ candidate: String) -> Bool {
        guard !normalizedTerms.isEmpty else { return true }

        let boundedCandidate = String(
            candidate.prefix(Self.maximumCandidateCharacterCount)
        )
        let normalizedCandidate = Self.normalized(boundedCandidate)
        return normalizedTerms.allSatisfy {
            normalizedCandidate.contains($0)
        }
    }

    private static func normalized(_ value: String) -> String {
        let stableLocale = Locale(identifier: "en_US_POSIX")
        return value
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive,
                ],
                locale: stableLocale
            )
            .lowercased(with: stableLocale)
    }
}
