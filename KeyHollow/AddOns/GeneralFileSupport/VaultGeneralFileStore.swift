import Foundation

private final class GeneralFileManifestTransaction: @unchecked Sendable {
    private let lock = NSRecursiveLock()

    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private final class WeakGeneralFileManifestTransaction {
    weak var value: GeneralFileManifestTransaction?

    init(_ value: GeneralFileManifestTransaction) {
        self.value = value
    }
}

private final class GeneralFileManifestTransactionRegistry: @unchecked Sendable {
    static let shared = GeneralFileManifestTransactionRegistry()

    private let lock = NSLock()
    private var transactions: [String: WeakGeneralFileManifestTransaction] = [:]

    func transaction(for root: URL) -> GeneralFileManifestTransaction {
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path
        lock.lock()
        defer { lock.unlock() }

        if let existing = transactions[key]?.value {
            return existing
        }
        transactions = transactions.filter { $0.value.value != nil }
        let transaction = GeneralFileManifestTransaction()
        transactions[key] = WeakGeneralFileManifestTransaction(transaction)
        return transaction
    }
}

private enum GeneralFileTemporarySessionError: Error {
    case invalidRoot
}

final class GeneralFileTemporarySession: @unchecked Sendable {
    let identifier: String

    private let root: URL
    private let fileManager: FileManager
    private let registry: GeneralFileTemporarySessionRegistry

    fileprivate init(
        identifier: String,
        root: URL,
        fileManager: FileManager,
        registry: GeneralFileTemporarySessionRegistry
    ) {
        self.identifier = identifier
        self.root = root
        self.fileManager = fileManager
        self.registry = registry
    }

    func directoryName(for operationID: UUID) -> String {
        "\(identifier)--\(operationID.uuidString.lowercased())"
    }

    deinit {
        registry.endSession(identifier, at: root, fileManager: fileManager)
    }
}

/// Serializes cleanup for stores sharing the same system temporary directory.
/// Every transient directory is owned by one live store session. A new store
/// removes only directories whose owning session is no longer registered, so
/// another store's prepared plaintext remains valid while either that store or
/// a prepared-export value still owns the session.
fileprivate final class GeneralFileTemporarySessionRegistry: @unchecked Sendable {
    static let shared = GeneralFileTemporarySessionRegistry()

    private static let containerNames = [
        "KeyHollowGeneralFileImports",
        "KeyHollowGeneralFileExports"
    ]

    private let lock = NSLock()
    private var activeSessionIdentifiersByRoot: [String: Set<String>] = [:]

    func beginSession(
        at root: URL,
        fileManager: FileManager
    ) throws -> GeneralFileTemporarySession {
        lock.lock()
        defer { lock.unlock() }

        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let rootValues = try root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else {
            throw GeneralFileTemporarySessionError.invalidRoot
        }

        let rootKey = root.standardizedFileURL.resolvingSymlinksInPath().path
        let activeIdentifiers = activeSessionIdentifiersByRoot[rootKey] ?? []
        for containerName in Self.containerNames {
            let container = root.appendingPathComponent(containerName, isDirectory: true)
            if fileManager.fileExists(atPath: container.path) {
                let values = try container.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    throw GeneralFileTemporarySessionError.invalidRoot
                }
            } else {
                try fileManager.createDirectory(
                    at: container,
                    withIntermediateDirectories: false,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
            }
            try Self.protectAndExclude(container, fileManager: fileManager)
            try purgeOrphanedDirectories(
                in: container,
                preserving: activeIdentifiers,
                fileManager: fileManager
            )
        }

        let identifier = UUID().uuidString.lowercased()
        var updatedIdentifiers = activeIdentifiers
        updatedIdentifiers.insert(identifier)
        activeSessionIdentifiersByRoot[rootKey] = updatedIdentifiers
        return GeneralFileTemporarySession(
            identifier: identifier,
            root: root,
            fileManager: fileManager,
            registry: self
        )
    }

    func endSession(
        _ identifier: String,
        at root: URL,
        fileManager: FileManager
    ) {
        lock.lock()
        defer { lock.unlock() }

        for containerName in Self.containerNames {
            let container = root.appendingPathComponent(containerName, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: container,
                includingPropertiesForKeys: nil
            ) else { continue }
            for child in children where Self.ownerIdentifier(for: child) == identifier {
                try? fileManager.removeItem(at: child)
            }
        }

        let rootKey = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard var identifiers = activeSessionIdentifiersByRoot[rootKey] else { return }
        identifiers.remove(identifier)
        if identifiers.isEmpty {
            activeSessionIdentifiersByRoot.removeValue(forKey: rootKey)
        } else {
            activeSessionIdentifiersByRoot[rootKey] = identifiers
        }
    }

    private func purgeOrphanedDirectories(
        in container: URL,
        preserving activeIdentifiers: Set<String>,
        fileManager: FileManager
    ) throws {
        let children = try fileManager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: nil
        )
        for child in children {
            guard let owner = Self.ownerIdentifier(for: child),
                  activeIdentifiers.contains(owner) else {
                try fileManager.removeItem(at: child)
                continue
            }
        }
    }

    private static func ownerIdentifier(for url: URL) -> String? {
        let name = url.lastPathComponent
        guard let separator = name.range(of: "--"),
              separator.lowerBound != name.startIndex else {
            return nil
        }
        return String(name[..<separator.lowerBound])
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

public actor VaultGeneralFileStore {
    public enum StoreError: Error, Equatable {
        case accessMismatch
        case batchTooLarge
        case emptyFile
        case fileTooLarge
        case invalidManifest
        case manifestCommitStateUnknown
        case protectedFileType
        case sourceUnavailable
        case storedFileLimitReached
        case unsupportedItem
        case verificationFailed
        case invalidStorageRoot
    }

    /// A bounded first release avoids large plaintext/ciphertext copies causing
    /// memory pressure. Video receives its own streaming add-on later.
    public static let maximumFileByteCount: UInt64 = 100 * 1_024 * 1_024
    public static let maximumBatchCount = 50
    public static let maximumStoredFileCount = 10_000
    public static let maximumManifestByteCount = 8 * 1_024 * 1_024
    public static let legacyMaximumManifestByteCount = 33_554_432
    /// New names stay compact for broad Files-provider compatibility. The
    /// persisted limit remains larger so pre-hardening Unicode names produced
    /// by the historical 180-character rule keep loading.
    public static let maximumNormalizedDisplayNameByteCount = 180
    public static let maximumPersistedDisplayNameByteCount = 1_024
    public static let maximumContentTypeIdentifierByteCount = 255
    public static let maximumPersistedContentTypeIdentifierByteCount = 4_096

    private static let sealedBoxOverheadByteCount: UInt64 = 28

    private static let protectedExtensions: Set<String> = [
        "app", "bat", "cmd", "com", "command", "dmg", "exe", "ipa",
        "khvault", "msi", "pkg", "sh"
    ]

    private let fileManager: FileManager
    private let root: URL
    private let temporaryRoot: URL
    private let vaultID: UUID
    private let access: any VaultGeneralFileCryptographicAccess
    private let manifestTransaction: GeneralFileManifestTransaction
    private let temporarySession: GeneralFileTemporarySession
    private let manifestCommitDidComplete: @Sendable () throws -> Void

    public init(
        vaultID: UUID,
        access: any VaultGeneralFileCryptographicAccess,
        storageRoot: URL? = nil,
        temporaryRoot: URL? = nil
    ) throws {
        try self.init(
            vaultID: vaultID,
            access: access,
            storageRoot: storageRoot,
            temporaryRoot: temporaryRoot,
            manifestCommitDidComplete: {}
        )
    }

    init(
        vaultID: UUID,
        access: any VaultGeneralFileCryptographicAccess,
        storageRoot: URL? = nil,
        temporaryRoot: URL? = nil,
        manifestCommitDidComplete: @escaping @Sendable () throws -> Void
    ) throws {
        guard access.vaultID == vaultID else { throw StoreError.accessMismatch }
        let fileManager = FileManager.default
        let resolvedTemporaryRoot = (
            temporaryRoot ?? fileManager.temporaryDirectory
        ).standardizedFileURL
        let resolvedRoot: URL

        if let storageRoot {
            resolvedRoot = storageRoot.standardizedFileURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolvedRoot = appSupport
                .appendingPathComponent("KeyHollow/GeneralFileData", isDirectory: true)
                .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
        }

        let manifestTransaction = GeneralFileManifestTransactionRegistry.shared.transaction(
            for: resolvedRoot
        )
        try manifestTransaction.withLock {
            try fileManager.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
            let rootValues = try resolvedRoot.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard rootValues.isDirectory == true,
                  rootValues.isSymbolicLink != true else {
                throw StoreError.invalidStorageRoot
            }
            try Self.protectAndExclude(resolvedRoot, fileManager: fileManager)
        }
        let temporarySession: GeneralFileTemporarySession
        do {
            temporarySession = try GeneralFileTemporarySessionRegistry.shared.beginSession(
                at: resolvedTemporaryRoot,
                fileManager: fileManager
            )
        } catch GeneralFileTemporarySessionError.invalidRoot {
            throw StoreError.invalidStorageRoot
        }

        self.fileManager = fileManager
        self.root = resolvedRoot
        self.temporaryRoot = resolvedTemporaryRoot
        self.vaultID = vaultID
        self.access = access
        self.manifestTransaction = manifestTransaction
        self.temporarySession = temporarySession
        self.manifestCommitDidComplete = manifestCommitDidComplete
    }

    public func loadManifest() throws -> VaultGeneralFileManifest {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            try access.checkAccess()
            guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }

            let ciphertext = try readCiphertext(
                at: manifestURL,
                maximumPlaintextByteCount: UInt64(Self.legacyMaximumManifestByteCount),
                oversizedError: .invalidManifest
            )
            let plaintext = try access.open(ciphertext, for: .manifest)
            try Task.checkCancellation()
            guard plaintext.count <= Self.legacyMaximumManifestByteCount else {
                throw StoreError.invalidManifest
            }
            let manifest = try JSONDecoder().decode(VaultGeneralFileManifest.self, from: plaintext)
            try Self.validateManifest(manifest)
            return manifest
        }
    }

    /// Authenticates the manifest and every referenced encrypted blob before
    /// exposing their ciphertext URLs to the portable-transfer module.
    public func authenticatedArchiveInventory() throws -> VaultGeneralFileArchiveInventory {
        try manifestTransaction.withLock {
            let manifest = try validateAllEncryptedFiles()
            guard !manifest.files.isEmpty else {
                return VaultGeneralFileArchiveInventory(
                    manifest: manifest,
                    manifestURL: nil,
                    blobURLsByName: [:]
                )
            }

            return VaultGeneralFileArchiveInventory(
                manifest: manifest,
                manifestURL: manifestURL,
                blobURLsByName: Dictionary(uniqueKeysWithValues: manifest.files.map { record in
                    (record.blobName, root.appendingPathComponent(record.blobName, isDirectory: false))
                })
            )
        }
    }

    /// Verifies that every persisted record has one safe, authenticated blob.
    /// Decrypted bytes exist only transiently in memory and are never written.
    public func validateAllEncryptedFiles(
        progress: (@Sendable (_ completedItemCount: Int, _ totalItemCount: Int) -> Void)? = nil
    ) throws -> VaultGeneralFileManifest {
        try manifestTransaction.withLock {
            let manifest = try loadManifest()
            var recordIDs = Set<UUID>()
            var blobNames = Set<String>()
            var completedItemCount = 0
            progress?(completedItemCount, manifest.files.count)

            for record in manifest.files {
                try Task.checkCancellation()
                guard recordIDs.insert(record.id).inserted,
                      blobNames.insert(record.blobName).inserted,
                      Self.isSafeBlobName(record.blobName) else {
                    throw StoreError.invalidManifest
                }
                let ciphertext = try readCiphertext(
                    at: root.appendingPathComponent(record.blobName, isDirectory: false),
                    maximumPlaintextByteCount: Self.maximumFileByteCount,
                    oversizedError: .fileTooLarge
                )
                let plaintext = try access.open(ciphertext, for: .file(record.id))
                guard UInt64(plaintext.count) == record.originalByteCount else {
                    throw StoreError.verificationFailed
                }
                completedItemCount += 1
                progress?(completedItemCount, manifest.files.count)
            }
            return manifest
        }
    }

    /// Returns one authenticated file in memory for an explicitly selected
    /// record. Presentation adapters use this narrow path for previews without
    /// receiving storage locations or cryptographic keys.
    public func loadFile(_ record: VaultGeneralFileRecord) throws -> Data {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            let manifest = try loadManifest()
            let canonical = try Self.canonicalRecords(for: [record], in: manifest)[0]
            let ciphertext = try readCiphertext(
                at: root.appendingPathComponent(canonical.blobName, isDirectory: false),
                maximumPlaintextByteCount: Self.maximumFileByteCount,
                oversizedError: .fileTooLarge
            )
            let plaintext = try access.open(ciphertext, for: .file(canonical.id))
            try Task.checkCancellation()
            guard UInt64(plaintext.count) == canonical.originalByteCount else {
                throw StoreError.verificationFailed
            }
            return plaintext
        }
    }

    public func importFile(at sourceURL: URL) throws -> VaultGeneralFileRecord {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            try access.checkAccess()
            var manifest = try loadManifest()
            guard manifest.files.count < Self.maximumStoredFileCount else {
                throw StoreError.storedFileLimitReached
            }
            let staged = try stageSourceFile(sourceURL)
            defer { try? fileManager.removeItem(at: staged.rootURL) }

            let plaintext = try Data(contentsOf: staged.fileURL, options: [.mappedIfSafe])
            try Task.checkCancellation()
            let id = UUID()
            let blobName = "\(UUID().uuidString.lowercased()).khf"
            let record = VaultGeneralFileRecord(
                id: id,
                importedAt: Date(),
                displayName: safeDisplayName(sourceURL.lastPathComponent),
                contentTypeIdentifier: staged.contentTypeIdentifier.flatMap {
                    $0.utf8.count <= Self.maximumContentTypeIdentifierByteCount ? $0 : nil
                },
                originalByteCount: UInt64(plaintext.count),
                blobName: blobName
            )
            let ciphertext = try access.seal(plaintext, for: .file(id))
            let blobURL = root.appendingPathComponent(blobName)

            var preserveNewBlobOnFailure = false
            do {
                try secureWrite(ciphertext, to: blobURL)
                let verified = try access.open(
                    readCiphertext(
                        at: blobURL,
                        maximumPlaintextByteCount: Self.maximumFileByteCount,
                        oversizedError: .fileTooLarge
                    ),
                    for: .file(id)
                )
                try Task.checkCancellation()
                guard verified == plaintext else { throw StoreError.verificationFailed }

                manifest.files.insert(record, at: 0)
                try Self.validateGrowthManifest(manifest)
                do {
                    try saveManifest(manifest)
                } catch {
                    switch recoverManifestCommit(for: record) {
                    case .committed:
                        break
                    case .notReferenced:
                        throw error
                    case .unknown:
                        preserveNewBlobOnFailure = true
                        throw StoreError.manifestCommitStateUnknown
                    }
                }
                return record
            } catch {
                if !preserveNewBlobOnFailure {
                    try? fileManager.removeItem(at: blobURL)
                }
                throw error
            }
        }
    }

    public func importFiles(at sourceURLs: [URL]) throws -> VaultGeneralFileImportResult {
        try access.checkAccess()
        guard sourceURLs.count <= Self.maximumBatchCount else {
            throw StoreError.batchTooLarge
        }

        var importedCount = 0
        var failedCount = 0
        for sourceURL in sourceURLs {
            try Task.checkCancellation()
            do {
                _ = try importFile(at: sourceURL)
                importedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedCount += 1
            }
        }
        return VaultGeneralFileImportResult(
            importedCount: importedCount,
            failedCount: failedCount
        )
    }

    public func prepareExport(_ records: [VaultGeneralFileRecord]) throws -> PreparedGeneralFileExport {
        try manifestTransaction.withLock {
            try access.checkAccess()
            guard !records.isEmpty else { throw StoreError.unsupportedItem }
            try Task.checkCancellation()
            let manifest = try loadManifest()
            let canonicalRecords = try Self.canonicalRecords(for: records, in: manifest)

            let exportID = UUID()
            let exportRoot = temporaryRoot
                .appendingPathComponent("KeyHollowGeneralFileExports", isDirectory: true)
                .appendingPathComponent(
                    temporarySession.directoryName(for: exportID),
                    isDirectory: true
                )
            try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
            try Self.protectAndExclude(exportRoot, fileManager: fileManager)

            do {
                var urls: [URL] = []
                var usedNames: Set<String> = []
                for record in canonicalRecords {
                    try Task.checkCancellation()
                    let ciphertext = try readCiphertext(
                        at: root.appendingPathComponent(record.blobName),
                        maximumPlaintextByteCount: Self.maximumFileByteCount,
                        oversizedError: .fileTooLarge
                    )
                    let name = uniqueName(
                        for: record.displayName,
                        usedNames: &usedNames,
                        in: exportRoot
                    )
                    let target = exportRoot.appendingPathComponent(name, isDirectory: false)
                    try access.open(ciphertext, for: .file(record.id), consuming: { plaintext in
                        try Task.checkCancellation()
                        guard UInt64(plaintext.count) == record.originalByteCount else {
                            throw StoreError.verificationFailed
                        }
                        try secureWrite(plaintext, to: target)
                        try Task.checkCancellation()
                    })
                    try Task.checkCancellation()
                    urls.append(target)
                }
                return PreparedGeneralFileExport(
                    id: exportID,
                    urls: urls,
                    rootURL: exportRoot,
                    temporarySession: temporarySession
                )
            } catch {
                try? fileManager.removeItem(at: exportRoot)
                throw error
            }
        }
    }

    public func discardExport(_ export: PreparedGeneralFileExport) {
        let expectedRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileExports", isDirectory: true)
            .appendingPathComponent(
                temporarySession.directoryName(for: export.id),
                isDirectory: true
            )
            .standardizedFileURL
        guard export.rootURL.standardizedFileURL == expectedRoot else { return }
        try? fileManager.removeItem(at: expectedRoot)
    }

    public func delete(_ records: [VaultGeneralFileRecord]) throws {
        try manifestTransaction.withLock {
            try access.checkAccess()
            guard !records.isEmpty else { return }
            var manifest = try loadManifest()
            let canonicalRecords = try Self.canonicalRecords(for: records, in: manifest)
            let ids = Set(canonicalRecords.map(\.id))
            manifest.files.removeAll { ids.contains($0.id) }
            try saveManifest(manifest)

            for record in canonicalRecords {
                try? fileManager.removeItem(at: root.appendingPathComponent(record.blobName))
            }
        }
    }

    public static func destroyVaultData(vaultID: UUID, storageRoot: URL? = nil) throws {
        let fileManager = FileManager.default
        let dataRoot: URL
        if let storageRoot {
            dataRoot = storageRoot
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            dataRoot = appSupport.appendingPathComponent(
                "KeyHollow/GeneralFileData",
                isDirectory: true
            )
        }
        let target = dataRoot.appendingPathComponent(
            vaultID.uuidString.lowercased(),
            isDirectory: true
        ).standardizedFileURL
        let transaction = GeneralFileManifestTransactionRegistry.shared.transaction(for: target)
        try transaction.withLock {
            guard fileManager.fileExists(atPath: target.path) else { return }
            try fileManager.removeItem(at: target)
        }
    }

    private var manifestURL: URL { root.appendingPathComponent("manifest.khm") }

    private static func isSafeBlobName(_ name: String) -> Bool {
        !name.isEmpty
            && name.utf8.count <= 255
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
            && URL(fileURLWithPath: name).lastPathComponent == name
            && URL(fileURLWithPath: name).pathExtension.lowercased() == "khf"
    }

    private static func validateManifest(_ manifest: VaultGeneralFileManifest) throws {
        guard manifest.version == VaultGeneralFileManifest.currentVersion else {
            throw StoreError.invalidManifest
        }

        var ids = Set<UUID>()
        var blobNames = Set<String>()
        for record in manifest.files {
            guard ids.insert(record.id).inserted,
                  blobNames.insert(record.blobName).inserted,
                  isSafeBlobName(record.blobName),
                  !record.displayName.isEmpty,
                  record.displayName.utf8.count <= maximumPersistedDisplayNameByteCount,
                  record.originalByteCount > 0,
                  record.originalByteCount <= maximumFileByteCount,
                  (record.contentTypeIdentifier?.utf8.count ?? 0)
                    <= maximumPersistedContentTypeIdentifierByteCount else {
                throw StoreError.invalidManifest
            }
        }
    }

    private static func validateGrowthManifest(
        _ manifest: VaultGeneralFileManifest
    ) throws {
        guard manifest.files.count <= maximumStoredFileCount else {
            throw StoreError.storedFileLimitReached
        }
        let encoded = try JSONEncoder().encode(manifest)
        guard encoded.count <= maximumManifestByteCount else {
            throw StoreError.storedFileLimitReached
        }
    }

    private static func canonicalRecords(
        for requestedRecords: [VaultGeneralFileRecord],
        in manifest: VaultGeneralFileManifest
    ) throws -> [VaultGeneralFileRecord] {
        var recordsByID: [UUID: VaultGeneralFileRecord] = [:]
        for record in manifest.files {
            guard recordsByID.updateValue(record, forKey: record.id) == nil else {
                throw StoreError.invalidManifest
            }
        }

        var requestedIDs = Set<UUID>()
        return try requestedRecords.map { requested in
            guard requestedIDs.insert(requested.id).inserted,
                  let canonical = recordsByID[requested.id] else {
                throw StoreError.invalidManifest
            }
            return canonical
        }
    }

    private func saveManifest(_ manifest: VaultGeneralFileManifest) throws {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            try Self.validateManifest(manifest)
            let plaintext = try JSONEncoder().encode(manifest)
            guard plaintext.count <= Self.legacyMaximumManifestByteCount else {
                throw StoreError.invalidManifest
            }
            let ciphertext = try access.seal(plaintext, for: .manifest)
            try Task.checkCancellation()
            do {
                try commitManifestCiphertext(ciphertext)
            } catch {
                let commitError = error
                guard let durable = try? loadDurableManifestForCommitRecovery() else {
                    throw StoreError.manifestCommitStateUnknown
                }
                guard durable == manifest else { throw commitError }
            }
        }
    }

    private func commitManifestCiphertext(_ ciphertext: Data) throws {
        let temporaryURL = root.appendingPathComponent(
            ".manifest-\(UUID().uuidString.lowercased()).pending",
            isDirectory: false
        )
        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try ciphertext.write(to: temporaryURL, options: [.completeFileProtection])
        try Self.protectAndExclude(temporaryURL, fileManager: fileManager)
        if fileManager.fileExists(atPath: manifestURL.path) {
            _ = try fileManager.replaceItemAt(
                manifestURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: manifestURL)
        }
        shouldRemoveTemporary = false
        try manifestCommitDidComplete()
    }

    private enum ManifestCommitRecovery {
        case committed
        case notReferenced
        case unknown
    }

    /// `replaceItemAt` can commit and still report an error. Authenticate the
    /// durable winner before deciding whether the new encrypted blob is safe
    /// to remove.
    private func recoverManifestCommit(
        for intendedRecord: VaultGeneralFileRecord
    ) -> ManifestCommitRecovery {
        do {
            let durable = try loadDurableManifestForCommitRecovery()
            if durable.files.contains(intendedRecord) {
                return .committed
            }
            let referencesNewStorage = durable.files.contains { record in
                record.id == intendedRecord.id || record.blobName == intendedRecord.blobName
            }
            return referencesNewStorage ? .unknown : .notReferenced
        } catch {
            return .unknown
        }
    }

    /// Cancellation cannot short-circuit this reread: cleanup safety depends
    /// on an authenticated answer after the commit API has thrown.
    private func loadDurableManifestForCommitRecovery() throws -> VaultGeneralFileManifest {
        try access.checkAccess()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }
        let ciphertext = try readCiphertext(
            at: manifestURL,
            maximumPlaintextByteCount: UInt64(Self.legacyMaximumManifestByteCount),
            oversizedError: .invalidManifest
        )
        let plaintext = try access.open(ciphertext, for: .manifest)
        guard plaintext.count <= Self.legacyMaximumManifestByteCount else {
            throw StoreError.invalidManifest
        }
        let manifest = try JSONDecoder().decode(VaultGeneralFileManifest.self, from: plaintext)
        try Self.validateManifest(manifest)
        return manifest
    }

    private func stageSourceFile(_ sourceURL: URL) throws -> (
        rootURL: URL,
        fileURL: URL,
        contentTypeIdentifier: String?
    ) {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let values: URLResourceValues
        do {
            values = try sourceURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isPackageKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .typeIdentifierKey
            ])
        } catch {
            throw StoreError.sourceUnavailable
        }

        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isPackage != true,
              values.isSymbolicLink != true else { throw StoreError.unsupportedItem }
        guard !Self.protectedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw StoreError.protectedFileType
        }

        if let sourceSize = values.fileSize {
            let byteCount = UInt64(max(sourceSize, 0))
            guard byteCount > 0 else { throw StoreError.emptyFile }
            guard byteCount <= Self.maximumFileByteCount else { throw StoreError.fileTooLarge }
        }

        let stagingRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileImports", isDirectory: true)
            .appendingPathComponent(
                temporarySession.directoryName(for: UUID()),
                isDirectory: true
            )
        let stagedURL = stagingRoot.appendingPathComponent("incoming", isDirectory: false)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try Self.protectAndExclude(stagingRoot, fileManager: fileManager)

        do {
            var coordinationError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) {
                coordinatedURL in
                do {
                    try fileManager.copyItem(at: coordinatedURL, to: stagedURL)
                } catch {
                    copyError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
            let stagedValues = try stagedURL.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard stagedValues.isRegularFile == true,
                  stagedValues.isSymbolicLink != true,
                  let stagedSize = stagedValues.fileSize else {
                throw StoreError.unsupportedItem
            }
            guard stagedSize > 0 else { throw StoreError.emptyFile }
            guard UInt64(stagedSize) <= Self.maximumFileByteCount else {
                throw StoreError.fileTooLarge
            }
            try Self.protectAndExclude(stagedURL, fileManager: fileManager)
            return (stagingRoot, stagedURL, values.typeIdentifier)
        } catch let error as StoreError {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw StoreError.sourceUnavailable
        }
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(url, fileManager: fileManager)
    }

    private func readCiphertext(
        at url: URL,
        maximumPlaintextByteCount: UInt64,
        oversizedError: StoreError
    ) throws -> Data {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize >= Int(Self.sealedBoxOverheadByteCount) else {
            throw StoreError.invalidManifest
        }
        let maximumCiphertextByteCount = maximumPlaintextByteCount
            + Self.sealedBoxOverheadByteCount
        guard UInt64(fileSize) <= maximumCiphertextByteCount else {
            throw oversizedError
        }

        let ciphertext = try Data(contentsOf: url, options: [.mappedIfSafe])
        let postReadValues = try URL(fileURLWithPath: url.path).resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard postReadValues.isRegularFile == true,
              postReadValues.isSymbolicLink != true,
              postReadValues.fileSize == fileSize,
              ciphertext.count == fileSize,
              UInt64(ciphertext.count) <= maximumCiphertextByteCount else {
            throw StoreError.invalidManifest
        }
        return ciphertext
    }

    private func safeDisplayName(_ proposed: String) -> String {
        let leaf = URL(fileURLWithPath: proposed).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
        return Self.boundedUTF8Prefix(
            leaf.isEmpty ? "Vault File" : leaf,
            maximumBytes: Self.maximumNormalizedDisplayNameByteCount
        )
    }

    private func uniqueName(
        for proposed: String,
        usedNames: inout Set<String>,
        in directory: URL
    ) -> String {
        let safe = safeDisplayName(proposed)
        let url = URL(fileURLWithPath: safe)
        let fileExtension = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = safe
        var suffix = 2
        while usedNames.contains(Self.exportNameCollisionKey(candidate))
            || fileManager.fileExists(
                atPath: directory.appendingPathComponent(candidate, isDirectory: false).path
            ) {
            let suffixText = " \(suffix)"
            let extensionText = fileExtension.isEmpty || fileExtension.utf8.count > 32
                ? ""
                : ".\(fileExtension)"
            let reservedByteCount = suffixText.utf8.count + extensionText.utf8.count
            let boundedBase = Self.boundedUTF8Prefix(
                base,
                maximumBytes: max(
                    1,
                    Self.maximumNormalizedDisplayNameByteCount - reservedByteCount
                )
            )
            candidate = "\(boundedBase)\(suffixText)\(extensionText)"
            suffix += 1
        }
        usedNames.insert(Self.exportNameCollisionKey(candidate))
        return candidate
    }

    private static func exportNameCollisionKey(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    private static func boundedUTF8Prefix(_ value: String, maximumBytes: Int) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        var result = value
        while result.utf8.count > maximumBytes, !result.isEmpty {
            result.removeLast()
        }
        return result.isEmpty ? "Vault File" : result
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
