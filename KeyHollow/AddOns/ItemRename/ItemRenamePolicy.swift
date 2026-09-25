import Foundation

/// Presentation-only naming rules. Storage owners independently enforce their
/// mutation boundary; this module never receives a store, key or revision token.
public struct ItemRenamePolicy: Sendable {
    public let initialName: String
    public let retainedExtension: String
    private let preservesExtension: Bool

    public init(displayName: String, preservesExtension: Bool) {
        self.preservesExtension = preservesExtension
        let suffix = preservesExtension ? (displayName as NSString).pathExtension : ""
        retainedExtension = suffix.isEmpty ? "" : "." + suffix
        initialName = suffix.isEmpty ? displayName : String(displayName.dropLast(suffix.count + 1))
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case empty, unsafe, tooLong, changesType

        public var errorDescription: String? {
            switch self {
            case .empty: "Enter a name containing more than spaces or periods."
            case .unsafe: "Use a name without slashes, colons or control characters."
            case .tooLong: "This name is too long. Use a shorter name."
            case .changesType: "Keep this file without an extension to preserve its type."
            }
        }
    }

    public func completeName(for draft: String) throws -> String {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))).isEmpty else {
            throw ValidationError.empty
        }
        guard draft.rangeOfCharacter(from: .controlCharacters) == nil,
              !draft.contains(where: { "/\\:".contains($0) }) else { throw ValidationError.unsafe }
        let name = draft + retainedExtension
        guard name.utf8.count <= 180 else { throw ValidationError.tooLong }
        if preservesExtension && retainedExtension.isEmpty && !(name as NSString).pathExtension.isEmpty {
            throw ValidationError.changesType
        }
        return name
    }
}
