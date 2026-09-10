import Foundation

/// Shared collision contract for any credential-store implementation used by
/// vault creation, passcode replacement, or portable restore.
public enum VaultCredentialStoreError: Error, Equatable {
    case locatorAlreadyExists
}

public actor VaultStore {
    public enum StoreError: Error, Equatable {
        case invalidEnvelopeFile
        case invalidLocator
        case invalidStorageRoot
    }

    public static let maximumEnvelopeByteCount: UInt64 = 64 * 1_024

    private let fileManager = FileManager.default
    private let root: URL

    public init(rootOverride: URL? = nil) throws {
        if let rootOverride {
            root = rootOverride.standardizedFileURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = appSupport.appendingPathComponent("KeyHollow/Vaults", isDirectory: true)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let rootValues = try root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else {
            throw StoreError.invalidStorageRoot
        }
        try Self.removeAbandonedPendingWrites(root, fileManager: fileManager)
        try Self.protectAndExclude(root, fileManager: fileManager)
    }

    public func hasAnyVaults() throws -> Bool {
        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try contents.contains { url in
            guard url.pathExtension == "khv",
                  Self.isValidLocator(url.deletingPathExtension().lastPathComponent) else {
                return false
            }
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
    }

    public func contains(locator: String) -> Bool {
        guard Self.isValidLocator(locator) else { return false }
        return fileManager.fileExists(atPath: root.appendingPathComponent(locator).appendingPathExtension("khv").path)
    }

    public func read(locator: String) throws -> VaultEnvelope? {
        let target = try url(for: locator)
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        let values = try target.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              UInt64(fileSize) <= Self.maximumEnvelopeByteCount else {
            throw StoreError.invalidEnvelopeFile
        }
        let data = try Data(contentsOf: target, options: [.mappedIfSafe])
        guard data.count == fileSize else {
            throw StoreError.invalidEnvelopeFile
        }
        return try JSONDecoder().decode(VaultEnvelope.self, from: data)
    }

    /// Creates a new credential without replacing any file that won a race for
    /// the same opaque locator. Portable restore uses this after its initial
    /// collision check so another vault can never be overwritten.
    public func writeIfAbsent(_ envelope: VaultEnvelope, locator: String) throws {
        let target = try url(for: locator)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw VaultCredentialStoreError.locatorAlreadyExists
        }
        let data = try JSONEncoder().encode(envelope)
        guard !data.isEmpty,
              UInt64(data.count) <= Self.maximumEnvelopeByteCount else {
            throw StoreError.invalidEnvelopeFile
        }
        let pending = root
            .appendingPathComponent(".pending-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("khvtmp")
        var linkedTarget = false
        defer { try? fileManager.removeItem(at: pending) }

        do {
            // Fully write and protect a hidden same-volume file, then create
            // the public locator with an exclusive hard link. The locator is
            // therefore either absent or a complete envelope, never partial.
            try data.write(to: pending, options: [.atomic, .completeFileProtection])
            try Self.protectAndExclude(pending, fileManager: fileManager)
            try fileManager.linkItem(at: pending, to: target)
            linkedTarget = true
            try Self.protectAndExclude(target, fileManager: fileManager)
        } catch {
            // If protection metadata fails after creation, do not leave a
            // partially committed credential behind.
            if linkedTarget {
                try? fileManager.removeItem(at: target)
            }
            if !linkedTarget, fileManager.fileExists(atPath: target.path) {
                throw VaultCredentialStoreError.locatorAlreadyExists
            }
            throw error
        }
    }

    public func delete(locator: String) throws {
        let target = try url(for: locator)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    private func url(for locator: String) throws -> URL {
        guard Self.isValidLocator(locator) else { throw StoreError.invalidLocator }
        return root.appendingPathComponent(locator).appendingPathExtension("khv")
    }

    private static func isValidLocator(_ locator: String) -> Bool {
        locator.utf8.count == 64
            && locator.unicodeScalars.allSatisfy { scalar in
                (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
            }
    }

    private static func removeAbandonedPendingWrites(
        _ root: URL,
        fileManager: FileManager
    ) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants]
        )
        for url in urls where (
            url.lastPathComponent.hasPrefix(".pending-")
                && url.pathExtension == "khvtmp"
        ) {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
    }

    private static func protectAndExclude(_ url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}

