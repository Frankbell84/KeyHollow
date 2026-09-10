import Foundation
import CryptoKit

private final class PhotoManifestTransaction: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0

    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    func currentGeneration() -> UInt64 {
        withLock { generation }
    }

    @discardableResult
    func recordMutation() -> UInt64 {
        withLock {
            generation &+= 1
            return generation
        }
    }
}

private final class WeakPhotoManifestTransaction {
    weak var value: PhotoManifestTransaction?

    init(_ value: PhotoManifestTransaction) {
        self.value = value
    }
}

private final class PhotoManifestTransactionRegistry: @unchecked Sendable {
    static let shared = PhotoManifestTransactionRegistry()

    private let lock = NSLock()
    private var transactions: [String: WeakPhotoManifestTransaction] = [:]

    func transaction(for root: URL) -> PhotoManifestTransaction {
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path
        lock.lock()
        defer { lock.unlock() }

        if let existing = transactions[key]?.value {
            return existing
        }
        transactions = transactions.filter { $0.value.value != nil }
        let transaction = PhotoManifestTransaction()
        transactions[key] = WeakPhotoManifestTransaction(transaction)
        return transaction
    }
}

public actor VaultPhotoStore {
    public enum StoreError: Error, Equatable {
        case invalidManifest
        case originalTooLarge
        case photoLimitReached
        case thumbnailTooLarge
        case verificationFailed
        case manifestCommitStateUnknown
        case accessMismatch
        case invalidStorageRoot
    }

    public static let maximumOriginalByteCount: UInt64 = 100 * 1_024 * 1_024
    public static let maximumThumbnailByteCount: UInt64 = 4 * 1_024 * 1_024
    public static let maximumManifestByteCount = 16 * 1_024 * 1_024
    public static let maximumPhotoCount = 10_000
    public static let legacyMaximumManifestByteCount = 33_554_432

    private let fileManager = FileManager.default
    private let root: URL
    private let vaultID: UUID
    private let access: any VaultPhotoCryptographicAccess
    private let manifestTransaction: PhotoManifestTransaction
    private let manifestCommitDidComplete: @Sendable () throws -> Void
    private let ciphertextReadDidComplete: @Sendable (URL) -> Void
    private var cachedRecordsByID: [UUID: VaultPhotoRecord] = [:]
    private var cachedManifestGeneration: UInt64?

    public init(vaultID: UUID, vaultKey: SymmetricKey, storageRoot: URL? = nil) throws {
        try self.init(
            vaultID: vaultID,
            access: DirectVaultPhotoAccess(vaultID: vaultID, vaultKey: vaultKey),
            storageRoot: storageRoot
        )
    }

    public init(
        vaultID: UUID,
        access: any VaultPhotoCryptographicAccess,
        storageRoot: URL? = nil
    ) throws {
        try self.init(
            vaultID: vaultID,
            access: access,
            storageRoot: storageRoot,
            manifestCommitDidComplete: {},
            ciphertextReadDidComplete: { _ in }
        )
    }

    init(
        vaultID: UUID,
        access: any VaultPhotoCryptographicAccess,
        storageRoot: URL? = nil,
        manifestCommitDidComplete: @escaping @Sendable () throws -> Void,
        ciphertextReadDidComplete: @escaping @Sendable (URL) -> Void = { _ in }
    ) throws {
        guard access.vaultID == vaultID else { throw StoreError.accessMismatch }
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
                .appendingPathComponent("KeyHollow/PhotoData", isDirectory: true)
                .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
        }

        let manifestTransaction = PhotoManifestTransactionRegistry.shared.transaction(
            for: resolvedRoot
        )
        self.root = resolvedRoot
        self.vaultID = vaultID
        self.access = access
        self.manifestTransaction = manifestTransaction
        self.manifestCommitDidComplete = manifestCommitDidComplete
        self.ciphertextReadDidComplete = ciphertextReadDidComplete

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
    }

    public func loadManifest() throws -> VaultPhotoManifest {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            try access.checkAccess()
            let target = manifestURL
            guard fileManager.fileExists(atPath: target.path) else {
                cache(.empty)
                return .empty
            }

            let ciphertext = try readCiphertext(
                at: target,
                maximumPlaintextByteCount: UInt64(Self.legacyMaximumManifestByteCount),
                oversizedError: .invalidManifest
            )
            let plaintext = try access.open(ciphertext, for: .manifest)
            try Task.checkCancellation()

            guard plaintext.count <= Self.legacyMaximumManifestByteCount else {
                throw StoreError.invalidManifest
            }
            let manifest = try JSONDecoder().decode(VaultPhotoManifest.self, from: plaintext)
            try Self.validateManifest(manifest)
            cache(manifest)
            return manifest
        }
    }

    /// Returns the authenticated manifest used by portable export and ensures
    /// that even a vault with no photos has an encrypted manifest on disk.
    /// The exclusive hard-link commit prevents a second store instance from
    /// replacing a manifest that won the same creation race.
    public func prepareArchiveManifest() throws -> VaultPhotoManifest {
        try withManifestMutationLock {
            try prepareArchiveManifestLocked()
        }
    }

    private func prepareArchiveManifestLocked() throws -> VaultPhotoManifest {
        let manifest = try loadManifest()
        let target = manifestURL
        guard !fileManager.fileExists(atPath: target.path) else { return manifest }

        try Self.validateManifest(manifest)
        let plaintext = try JSONEncoder().encode(manifest)
        guard plaintext.count <= Self.maximumManifestByteCount else {
            throw StoreError.invalidManifest
        }
        let ciphertext = try access.seal(plaintext, for: .manifest)
        try Task.checkCancellation()

        let pending = root
            .appendingPathComponent(".pending-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("khmtmp")
        defer { try? fileManager.removeItem(at: pending) }

        do {
            try ciphertext.write(to: pending, options: [.atomic, .completeFileProtection])
            try Self.protectAndExclude(pending, fileManager: fileManager)
            try fileManager.linkItem(at: pending, to: target)
            recordManifestMutation(manifest)
            return manifest
        } catch {
            // Another store may have committed first. Authenticate and use
            // that winner rather than overwriting it or trusting our cache.
            if fileManager.fileExists(atPath: target.path) {
                cachedRecordsByID.removeAll(keepingCapacity: true)
                let durable = try loadDurableManifestForCommitRecovery()
                recordManifestMutation(durable)
                return durable
            }
            throw error
        }
    }

    public func importPhoto(
        originalData: Data,
        thumbnailData: Data,
        displayName: String? = nil
    ) throws -> VaultPhotoRecord {
        try manifestTransaction.withLock {
            try importPhotoLocked(
                originalData: originalData,
                thumbnailData: thumbnailData,
                displayName: displayName
            )
        }
    }

    private func importPhotoLocked(
        originalData: Data,
        thumbnailData: Data,
        displayName: String?
    ) throws -> VaultPhotoRecord {
        try Task.checkCancellation()
        guard UInt64(originalData.count) <= Self.maximumOriginalByteCount else {
            throw StoreError.originalTooLarge
        }
        guard UInt64(thumbnailData.count) <= Self.maximumThumbnailByteCount else {
            throw StoreError.thumbnailTooLarge
        }
        var manifest = try loadManifest()
        guard manifest.photos.count < Self.maximumPhotoCount else {
            throw StoreError.photoLimitReached
        }
        let id = UUID()
        let blobName = randomName(extension: "khp")
        let thumbnailName = randomName(extension: "kht")
        let record = VaultPhotoRecord(
            id: id,
            importedAt: Date(),
            blobName: blobName,
            thumbnailName: thumbnailName,
            displayName: Self.normalizedDisplayName(displayName),
            originalByteCount: UInt64(originalData.count)
        )

        let originalCiphertext = try access.seal(originalData, for: .photo(id))
        let thumbnailCiphertext = try access.seal(thumbnailData, for: .thumbnail(id))
        try Task.checkCancellation()

        let originalURL = root.appendingPathComponent(blobName)
        let thumbnailURL = root.appendingPathComponent(thumbnailName)

        var preserveNewBlobsOnFailure = false
        do {
            try secureWrite(originalCiphertext, to: originalURL)
            try Task.checkCancellation()
            try secureWrite(thumbnailCiphertext, to: thumbnailURL)

            let verifiedOriginal = try access.open(
                readCiphertext(
                    at: originalURL,
                    maximumPlaintextByteCount: Self.maximumOriginalByteCount,
                    oversizedError: .originalTooLarge
                ),
                for: .photo(id)
            )
            let verifiedThumbnail = try access.open(
                readCiphertext(
                    at: thumbnailURL,
                    maximumPlaintextByteCount: Self.maximumThumbnailByteCount,
                    oversizedError: .thumbnailTooLarge
                ),
                for: .thumbnail(id)
            )
            try Task.checkCancellation()

            guard verifiedOriginal == originalData,
                  verifiedThumbnail == thumbnailData else {
                throw StoreError.verificationFailed
            }

            try withManifestMutationLock {
                manifest.photos.insert(record, at: 0)
                try Self.validateGrowthManifest(manifest)
                do {
                    try saveManifest(manifest)
                } catch {
                    switch recoverManifestCommit(for: record) {
                    case .committed(let durable):
                        recordManifestMutation(durable)
                    case .notReferenced:
                        throw error
                    case .unknown:
                        preserveNewBlobsOnFailure = true
                        throw StoreError.manifestCommitStateUnknown
                    }
                }
            }
            return record
        } catch {
            if !preserveNewBlobsOnFailure {
                try? fileManager.removeItem(at: originalURL)
                try? fileManager.removeItem(at: thumbnailURL)
            }
            throw error
        }
    }

    public func loadPhoto(_ record: VaultPhotoRecord) throws -> Data {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            let canonical = try canonicalRecord(id: record.id)
            let ciphertext = try readCiphertext(
                at: root.appendingPathComponent(canonical.blobName),
                maximumPlaintextByteCount: Self.maximumOriginalByteCount,
                oversizedError: .originalTooLarge
            )
            let plaintext = try access.open(ciphertext, for: .photo(canonical.id))
            try Task.checkCancellation()
            guard UInt64(plaintext.count) <= Self.maximumOriginalByteCount,
                  canonical.originalByteCount == nil
                    || canonical.originalByteCount == UInt64(plaintext.count) else {
                throw StoreError.verificationFailed
            }
            return plaintext
        }
    }

    public func loadThumbnail(_ record: VaultPhotoRecord) throws -> Data {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            let canonical = try canonicalRecord(id: record.id)
            let ciphertext = try readCiphertext(
                at: root.appendingPathComponent(canonical.thumbnailName),
                maximumPlaintextByteCount: Self.maximumThumbnailByteCount,
                oversizedError: .thumbnailTooLarge
            )
            let plaintext = try access.open(ciphertext, for: .thumbnail(canonical.id))
            try Task.checkCancellation()
            guard UInt64(plaintext.count) <= Self.maximumThumbnailByteCount else {
                throw StoreError.verificationFailed
            }
            return plaintext
        }
    }

    public func delete(_ record: VaultPhotoRecord) throws {
        try delete([record])
    }

    public func delete(_ records: [VaultPhotoRecord]) throws {
        guard !records.isEmpty else { return }

        let recordIDs = Set(records.map(\.id))
        guard recordIDs.count == records.count else { throw StoreError.invalidManifest }
        try withManifestMutationLock {
            var manifest = try loadManifest()
            let canonicalRecords = manifest.photos.filter { recordIDs.contains($0.id) }
            guard canonicalRecords.count == recordIDs.count else {
                throw StoreError.invalidManifest
            }
            manifest.photos.removeAll { recordIDs.contains($0.id) }
            try saveManifest(manifest)
            for record in canonicalRecords {
                try? fileManager.removeItem(at: root.appendingPathComponent(record.blobName))
                try? fileManager.removeItem(at: root.appendingPathComponent(record.thumbnailName))
            }
        }
    }

    public static func destroyVaultData(vaultID: UUID, storageRoot: URL? = nil) throws {
        let fileManager = FileManager.default
        let photoDataRoot: URL
        if let storageRoot {
            photoDataRoot = storageRoot
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            photoDataRoot = appSupport
                .appendingPathComponent("KeyHollow/PhotoData", isDirectory: true)
        }
        let target = photoDataRoot
            .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
            .standardizedFileURL
        let transaction = PhotoManifestTransactionRegistry.shared.transaction(for: target)
        try transaction.withLock {
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            transaction.recordMutation()
        }
    }

    private var manifestURL: URL {
        root.appendingPathComponent("manifest.khm")
    }

    private func saveManifest(_ manifest: VaultPhotoManifest) throws {
        try Task.checkCancellation()
        try Self.validateManifest(manifest)
        let plaintext = try JSONEncoder().encode(manifest)
        guard plaintext.count <= Self.legacyMaximumManifestByteCount else {
            throw StoreError.invalidManifest
        }
        let ciphertext = try access.seal(plaintext, for: .manifest)
        try Task.checkCancellation()
        do {
            try secureReplaceManifest(ciphertext)
        } catch {
            let commitError = error
            guard let durable = try? loadDurableManifestForCommitRecovery() else {
                throw StoreError.manifestCommitStateUnknown
            }
            guard durable.version == manifest.version,
                  durable.photos == manifest.photos else {
                throw commitError
            }
        }
        recordManifestMutation(manifest)
    }

    /// Applies protection and backup exclusion before the manifest becomes
    /// visible. Once the same-volume rename/replace commits, no later metadata
    /// operation can fail and leave a manifest referencing rolled-back blobs.
    private func secureReplaceManifest(_ data: Data) throws {
        let pending = root
            .appendingPathComponent(".pending-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("khmtmp")
        defer { try? fileManager.removeItem(at: pending) }

        try data.write(to: pending, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(pending, fileManager: fileManager)
        if fileManager.fileExists(atPath: manifestURL.path) {
            _ = try fileManager.replaceItemAt(
                manifestURL,
                withItemAt: pending,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: pending, to: manifestURL)
        }
        try manifestCommitDidComplete()
    }

    private enum ManifestCommitRecovery {
        case committed(VaultPhotoManifest)
        case notReferenced
        case unknown
    }

    /// A same-volume replace may have committed even when its API reports an
    /// error. Authenticate the durable winner before deciding whether rollback
    /// is safe; an unreadable winner must retain both encrypted blobs.
    private func recoverManifestCommit(
        for intendedRecord: VaultPhotoRecord
    ) -> ManifestCommitRecovery {
        do {
            let durable = try loadDurableManifestForCommitRecovery()
            if durable.photos.contains(intendedRecord) {
                return .committed(durable)
            }
            let referencesNewStorage = durable.photos.contains { record in
                record.id == intendedRecord.id
                    || record.blobName == intendedRecord.blobName
                    || record.thumbnailName == intendedRecord.thumbnailName
                    || record.blobName == intendedRecord.thumbnailName
                    || record.thumbnailName == intendedRecord.blobName
            }
            return referencesNewStorage ? .unknown : .notReferenced
        } catch {
            return .unknown
        }
    }

    /// Deliberately ignores task cancellation: once a commit call has thrown,
    /// cleanup safety depends on authenticating what actually reached disk.
    private func loadDurableManifestForCommitRecovery() throws -> VaultPhotoManifest {
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
        let manifest = try JSONDecoder().decode(VaultPhotoManifest.self, from: plaintext)
        try Self.validateManifest(manifest)
        return manifest
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(url, fileManager: fileManager)
    }

    private func randomName(extension fileExtension: String) -> String {
        "\(UUID().uuidString.lowercased()).\(fileExtension)"
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
              fileSize >= 28 else {
            throw StoreError.invalidManifest
        }
        guard UInt64(fileSize) <= maximumPlaintextByteCount + 28 else {
            throw oversizedError
        }
        let ciphertext = try Data(contentsOf: url, options: [.mappedIfSafe])
        ciphertextReadDidComplete(url)
        let postReadValues = try URL(fileURLWithPath: url.path).resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard postReadValues.isRegularFile == true,
              postReadValues.isSymbolicLink != true,
              postReadValues.fileSize == fileSize,
              ciphertext.count == fileSize else {
            throw StoreError.invalidManifest
        }
        guard UInt64(ciphertext.count) <= maximumPlaintextByteCount + 28 else {
            throw oversizedError
        }
        return ciphertext
    }

    private func withManifestMutationLock<T>(
        _ operation: () throws -> T
    ) rethrows -> T {
        try manifestTransaction.withLock(operation)
    }

    private static func validateManifest(_ manifest: VaultPhotoManifest) throws {
        guard manifest.version == VaultPhotoManifest.currentVersion else {
            throw StoreError.invalidManifest
        }

        var ids = Set<UUID>()
        var storageNames = Set<String>()
        for record in manifest.photos {
            guard ids.insert(record.id).inserted,
                  storageNames.insert(record.blobName).inserted,
                  storageNames.insert(record.thumbnailName).inserted,
                  isSafeStorageName(record.blobName, extension: "khp"),
                  isSafeStorageName(record.thumbnailName, extension: "kht") else {
                throw StoreError.invalidManifest
            }
        }
    }

    private static func validateGrowthManifest(_ manifest: VaultPhotoManifest) throws {
        guard manifest.photos.count <= maximumPhotoCount else {
            throw StoreError.photoLimitReached
        }
        let encoded = try JSONEncoder().encode(manifest)
        guard encoded.count <= maximumManifestByteCount else {
            throw StoreError.photoLimitReached
        }
    }

    private func canonicalRecord(id: UUID) throws -> VaultPhotoRecord {
        try manifestTransaction.withLock {
            let generation = manifestTransaction.currentGeneration()
            if cachedManifestGeneration == generation,
               let record = cachedRecordsByID[id] {
                return record
            }
            _ = try loadManifest()
            guard let record = cachedRecordsByID[id] else {
                throw StoreError.invalidManifest
            }
            return record
        }
    }

    private func cache(
        _ manifest: VaultPhotoManifest,
        generation: UInt64? = nil
    ) {
        cachedRecordsByID = Dictionary(
            uniqueKeysWithValues: manifest.photos.map { ($0.id, $0) }
        )
        cachedManifestGeneration = generation ?? manifestTransaction.currentGeneration()
    }

    private func recordManifestMutation(_ manifest: VaultPhotoManifest) {
        let generation = manifestTransaction.recordMutation()
        cache(manifest, generation: generation)
    }

    private static func isSafeStorageName(_ name: String, extension expected: String) -> Bool {
        !name.isEmpty
            && name.utf8.count <= 255
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
            && URL(fileURLWithPath: name).lastPathComponent == name
            && URL(fileURLWithPath: name).pathExtension.lowercased() == expected
    }

    private static func normalizedDisplayName(_ displayName: String?) -> String? {
        guard let displayName else { return nil }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(255))
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

