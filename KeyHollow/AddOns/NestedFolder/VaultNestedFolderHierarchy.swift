import Foundation

public struct VaultNestedFolderDescriptor: Identifiable, Hashable, Sendable {
    public static let maximumNameCharacterCount = 80

    public let id: UUID
    public let parentID: UUID?
    public let name: String
    public let createdAt: Date
    public let stableOrdinal: Int

    public init(
        id: UUID,
        parentID: UUID?,
        name: String,
        createdAt: Date,
        stableOrdinal: Int
    ) {
        self.id = id
        self.parentID = parentID
        self.name = String(name.prefix(Self.maximumNameCharacterCount))
        self.createdAt = createdAt
        self.stableOrdinal = stableOrdinal
    }

    func replacingParent(with parentID: UUID?) -> Self {
        Self(
            id: id,
            parentID: parentID,
            name: name,
            createdAt: createdAt,
            stableOrdinal: stableOrdinal
        )
    }
}

public enum VaultNestedFolderPolicyError: Error, Equatable, Sendable {
    case cycle
    case duplicateFolderID
    case duplicateSiblingName
    case folderLimitExceeded
    case folderNotFound
    case invalidDepth
    case invalidName
    case invalidParent
    case selfParent
}

/// Bounded, metadata-only folder policy. This add-on cannot access vault keys,
/// stores, URLs, payloads, thumbnails, or archive data.
public struct VaultNestedFolderHierarchy: Sendable {
    public static let maximumFolderCount = 10_000
    public static let maximumDepth = 8

    public let folders: [VaultNestedFolderDescriptor]

    private let foldersByID: [UUID: VaultNestedFolderDescriptor]

    public init(
        folders: [VaultNestedFolderDescriptor],
        maximumDepth: Int = Self.maximumDepth
    ) throws {
        guard folders.count <= Self.maximumFolderCount else {
            throw VaultNestedFolderPolicyError.folderLimitExceeded
        }
        guard maximumDepth > 0, maximumDepth <= Self.maximumDepth else {
            throw VaultNestedFolderPolicyError.invalidDepth
        }

        var indexed: [UUID: VaultNestedFolderDescriptor] = [:]
        indexed.reserveCapacity(folders.count)
        for folder in folders {
            guard indexed.updateValue(folder, forKey: folder.id) == nil else {
                throw VaultNestedFolderPolicyError.duplicateFolderID
            }
            guard Self.isValidName(folder.name) else {
                throw VaultNestedFolderPolicyError.invalidName
            }
        }

        var siblingNames: [UUID?: Set<String>] = [:]
        for folder in folders {
            if let parentID = folder.parentID {
                guard parentID != folder.id else {
                    throw VaultNestedFolderPolicyError.selfParent
                }
                guard indexed[parentID] != nil else {
                    throw VaultNestedFolderPolicyError.invalidParent
                }
            }
            let collisionKey = Self.nameCollisionKey(folder.name)
            guard siblingNames[folder.parentID, default: []].insert(collisionKey).inserted else {
                throw VaultNestedFolderPolicyError.duplicateSiblingName
            }
        }

        for folder in folders {
            var visited = Set<UUID>()
            var cursor: UUID? = folder.id
            var depth = 0
            while let folderID = cursor {
                guard visited.insert(folderID).inserted else {
                    throw VaultNestedFolderPolicyError.cycle
                }
                depth += 1
                guard depth <= maximumDepth else {
                    throw VaultNestedFolderPolicyError.invalidDepth
                }
                cursor = indexed[folderID]?.parentID
            }
        }

        self.folders = folders
        self.foldersByID = indexed
    }

    public func children(of parentID: UUID?) -> [VaultNestedFolderDescriptor] {
        folders
            .filter { $0.parentID == parentID }
            .sorted(by: Self.stableOrder)
    }

    /// Returns the root-to-leaf folder path. The vault root is not synthesized.
    public func breadcrumb(to folderID: UUID) throws -> [VaultNestedFolderDescriptor] {
        guard foldersByID[folderID] != nil else {
            throw VaultNestedFolderPolicyError.folderNotFound
        }
        var path: [VaultNestedFolderDescriptor] = []
        var cursor: UUID? = folderID
        while let currentID = cursor {
            guard let folder = foldersByID[currentID] else {
                throw VaultNestedFolderPolicyError.invalidParent
            }
            path.append(folder)
            cursor = folder.parentID
        }
        return path.reversed()
    }

    public func movingFolder(
        id folderID: UUID,
        to parentID: UUID?
    ) throws -> [VaultNestedFolderDescriptor] {
        guard let folder = foldersByID[folderID] else {
            throw VaultNestedFolderPolicyError.folderNotFound
        }
        guard folder.parentID != parentID else { return folders }
        if let parentID {
            guard foldersByID[parentID] != nil else {
                throw VaultNestedFolderPolicyError.invalidParent
            }
            guard parentID != folderID else {
                throw VaultNestedFolderPolicyError.selfParent
            }
        }

        let moved = folders.map {
            $0.id == folderID ? $0.replacingParent(with: parentID) : $0
        }
        return try Self(folders: moved).folders
    }

    public func validParentDestinations(
        for folderID: UUID
    ) throws -> [UUID?] {
        guard let folder = foldersByID[folderID] else {
            throw VaultNestedFolderPolicyError.folderNotFound
        }
        var candidates: [UUID?] = [nil]
        candidates.append(contentsOf: folders
            .sorted(by: Self.stableOrder)
            .map { Optional($0.id) })

        return candidates.filter { candidate in
            guard candidate != folder.parentID else { return false }
            return (try? movingFolder(id: folderID, to: candidate)) != nil
        }
    }

    private static func stableOrder(
        _ lhs: VaultNestedFolderDescriptor,
        _ rhs: VaultNestedFolderDescriptor
    ) -> Bool {
        if lhs.stableOrdinal != rhs.stableOrdinal {
            return lhs.stableOrdinal < rhs.stableOrdinal
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isValidName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty
            && normalized == name
            && normalized.count <= VaultNestedFolderDescriptor.maximumNameCharacterCount
            && normalized.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func nameCollisionKey(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}
