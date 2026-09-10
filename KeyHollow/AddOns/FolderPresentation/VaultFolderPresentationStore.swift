import Foundation

private final class FolderManifestTransaction: @unchecked Sendable {
    private let lock = NSRecursiveLock()

    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private final class WeakFolderManifestTransaction {
    weak var value: FolderManifestTransaction?

    init(_ value: FolderManifestTransaction) {
        self.value = value
    }
}

private final class FolderManifestTransactionRegistry: @unchecked Sendable {
    static let shared = FolderManifestTransactionRegistry()

    private let lock = NSLock()
    private var transactions: [String: WeakFolderManifestTransaction] = [:]

    func transaction(for root: URL) -> FolderManifestTransaction {
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path
        lock.lock()
        defer { lock.unlock() }

        if let existing = transactions[key]?.value {
            return existing
        }
        transactions = transactions.filter { $0.value.value != nil }
        let transaction = FolderManifestTransaction()
        transactions[key] = WeakFolderManifestTransaction(transaction)
        return transaction
    }
}

public actor VaultFolderPresentationStore {
    public enum StoreError: Error, Equatable {
        case accessMismatch
        case duplicateFolderName
        case folderLimitReached
        case folderNotFound
        case invalidFolderName
        case invalidManifest
        case invalidStorageRoot
        case manifestCommitStateUnknown
        case membershipLimitReached
        case thumbnailLimitReached
        case verificationFailed
    }

    public static let maximumFolderNameLength = 80
    public static let maximumThumbnailByteCount = 2 * 1_024 * 1_024
    public static let maximumManifestByteCount = 8 * 1_024 * 1_024
    public static let legacyMaximumManifestByteCount = 33_554_432
    public static let maximumFolderCount = 10_000
    public static let maximumMembershipCount = 20_000
    public static let maximumStoredThumbnailCount = 20_000

    private static let sealedBoxOverheadByteCount: UInt64 = 28
    private static let collisionLocale = Locale(identifier: "en_US_POSIX")

    private let fileManager: FileManager
    private let root: URL
    private let access: any VaultFolderPresentationCryptographicAccess
    private let manifestTransaction: FolderManifestTransaction
    private let manifestCommitDidComplete: @Sendable () throws -> Void

    public init(
        vaultID: UUID,
        access: any VaultFolderPresentationCryptographicAccess,
        storageRoot: URL? = nil
    ) throws {
        try self.init(
            vaultID: vaultID,
            access: access,
            storageRoot: storageRoot,
            manifestCommitDidComplete: {}
        )
    }

    init(
        vaultID: UUID,
        access: any VaultFolderPresentationCryptographicAccess,
        storageRoot: URL? = nil,
        manifestCommitDidComplete: @escaping @Sendable () throws -> Void
    ) throws {
        guard access.vaultID == vaultID else { throw StoreError.accessMismatch }
        let fileManager = FileManager.default
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
                .appendingPathComponent("KeyHollow/FolderPresentationData", isDirectory: true)
                .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
        }

        let manifestTransaction = FolderManifestTransactionRegistry.shared.transaction(
            for: resolvedRoot
        )
        self.fileManager = fileManager
        self.root = resolvedRoot
        self.access = access
        self.manifestTransaction = manifestTransaction
        self.manifestCommitDidComplete = manifestCommitDidComplete

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

    public func loadManifest() throws -> VaultFolderPresentationManifest {
        try manifestTransaction.withLock {
            try Task.checkCancellation()
            try access.checkAccess()
            guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }
            let ciphertext = try readCiphertext(
                at: manifestURL,
                maximumPlaintextByteCount: UInt64(Self.legacyMaximumManifestByteCount),
                invalidError: .invalidManifest
            )
            let plaintext = try access.open(ciphertext, for: .manifest)
            guard plaintext.count <= Self.legacyMaximumManifestByteCount else {
                throw StoreError.invalidManifest
            }
            try Task.checkCancellation()
            let manifest = try JSONDecoder().decode(
                VaultFolderPresentationManifest.self,
                from: plaintext
            )
            try validate(manifest)
            return manifest
        }
    }

    @discardableResult
    public func createFolder(named proposedName: String) throws -> VaultFolderRecord {
        try manifestTransaction.withLock {
            let name = try normalizedFolderName(proposedName)
            let collisionKey = Self.folderNameCollisionKey(name)
            var manifest = try loadManifest()
            guard manifest.folders.count < Self.maximumFolderCount else {
                throw StoreError.folderLimitReached
            }
            guard !manifest.folders.contains(where: {
                Self.folderNameCollisionKey($0.name) == collisionKey
            }) else { throw StoreError.duplicateFolderName }

            let folder = VaultFolderRecord(id: UUID(), name: name, createdAt: Date())
            manifest.folders.append(folder)
            try validateGrowth(
                from: nil,
                to: manifest,
                limitError: .folderLimitReached
            )
            try saveManifest(manifest)
            return folder
        }
    }

    public func renameFolder(id: UUID, to proposedName: String) throws {
        try manifestTransaction.withLock {
            let name = try normalizedFolderName(proposedName)
            let collisionKey = Self.folderNameCollisionKey(name)
            var manifest = try loadManifest()
            let originalManifest = manifest
            guard let index = manifest.folders.firstIndex(where: { $0.id == id }) else {
                throw StoreError.folderNotFound
            }
            guard !manifest.folders.contains(where: {
                $0.id != id && Self.folderNameCollisionKey($0.name) == collisionKey
            }) else { throw StoreError.duplicateFolderName }

            manifest.folders[index].name = name
            try validateGrowth(
                from: originalManifest,
                to: manifest,
                limitError: .folderLimitReached
            )
            try saveManifest(manifest)
        }
    }

    /// Deleting a folder returns its content references to the root gallery. It
    /// never deletes content from either protected store.
    public func deleteFolder(id: UUID) throws {
        try manifestTransaction.withLock {
            var manifest = try loadManifest()
            guard manifest.folders.contains(where: { $0.id == id }) else {
                throw StoreError.folderNotFound
            }
            manifest.folders.removeAll { $0.id == id }
            manifest.memberships.removeAll { $0.folderID == id }
            try saveManifest(manifest)
        }
    }

    public func move(_ item: VaultPresentedContentReference, to folderID: UUID?) throws {
        try move(Set([item]), to: folderID)
    }

    /// Changes membership for one mixed selection with a single authenticated
    /// manifest write. The referenced photo and file ciphertext never moves.
    public func move(
        _ items: Set<VaultPresentedContentReference>,
        to folderID: UUID?
    ) throws {
        try manifestTransaction.withLock {
            try access.checkAccess()
            guard !items.isEmpty else { return }
            var manifest = try loadManifest()
            let originalManifest = manifest
            if let folderID,
               !manifest.folders.contains(where: { $0.id == folderID }) {
                throw StoreError.folderNotFound
            }
            manifest.memberships.removeAll { items.contains($0.item) }
            if let folderID {
                let orderedItems = items.sorted {
                    if $0.kind.rawValue != $1.kind.rawValue {
                        return $0.kind.rawValue < $1.kind.rawValue
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
                manifest.memberships.append(contentsOf: orderedItems.map {
                    VaultFolderMembership(item: $0, folderID: folderID)
                })
            }
            if manifest.memberships.count > originalManifest.memberships.count,
               manifest.memberships.count > Self.maximumMembershipCount {
                throw StoreError.membershipLimitReached
            }
            try validateGrowth(
                from: originalManifest,
                to: manifest,
                limitError: .membershipLimitReached
            )
            try saveManifest(manifest)
        }
    }

    public func folderID(for item: VaultPresentedContentReference) throws -> UUID? {
        try loadManifest().memberships.first(where: { $0.item == item })?.folderID
    }

    /// Stores opaque, locally generated thumbnail bytes. Image decoding and
    /// resizing remain presentation-adapter concerns outside this module.
    public func storeThumbnail(
        _ plaintext: Data,
        for item: VaultPresentedContentReference
    ) throws {
        try manifestTransaction.withLock {
            try access.checkAccess()
            guard !plaintext.isEmpty,
                  plaintext.count <= Self.maximumThumbnailByteCount else {
                throw StoreError.verificationFailed
            }
            var manifest = try loadManifest()
            let originalManifest = manifest
            let previous = manifest.thumbnails.first(where: { $0.item == item })
            let blobName = "\(UUID().uuidString.lowercased()).kht"
            let blobURL = try thumbnailURL(for: blobName)
            let ciphertext = try access.seal(plaintext, for: .thumbnail(item))

            var preserveNewBlobOnFailure = false
            do {
                try secureWrite(ciphertext, to: blobURL)
                let reopened = try access.open(
                    readCiphertext(
                        at: blobURL,
                        maximumPlaintextByteCount: UInt64(Self.maximumThumbnailByteCount),
                        invalidError: .verificationFailed
                    ),
                    for: .thumbnail(item)
                )
                guard !reopened.isEmpty,
                      reopened.count <= Self.maximumThumbnailByteCount,
                      reopened == plaintext else {
                    throw StoreError.verificationFailed
                }

                manifest.thumbnails.removeAll { $0.item == item }
                manifest.thumbnails.append(
                    VaultPresentationThumbnailRecord(item: item, blobName: blobName)
                )
                if previous == nil,
                   manifest.thumbnails.count > Self.maximumStoredThumbnailCount {
                    throw StoreError.thumbnailLimitReached
                }
                try validateGrowth(
                    from: previous == nil ? nil : originalManifest,
                    to: manifest,
                    limitError: .thumbnailLimitReached
                )
                do {
                    try saveManifest(manifest)
                } catch {
                    switch recoverThumbnailManifestCommit(
                        item: item,
                        blobName: blobName
                    ) {
                    case .committed:
                        break
                    case .notReferenced:
                        throw error
                    case .unknown:
                        preserveNewBlobOnFailure = true
                        throw StoreError.manifestCommitStateUnknown
                    }
                }
                if let previous {
                    try? fileManager.removeItem(at: thumbnailURL(for: previous.blobName))
                }
            } catch {
                if !preserveNewBlobOnFailure {
                    try? fileManager.removeItem(at: blobURL)
                }
                throw error
            }
        }
    }

    public func loadThumbnail(for item: VaultPresentedContentReference) throws -> Data? {
        try manifestTransaction.withLock {
            let manifest = try loadManifest()
            guard let record = manifest.thumbnails.first(where: { $0.item == item }) else {
                return nil
            }
            let ciphertext = try readCiphertext(
                at: thumbnailURL(for: record.blobName),
                maximumPlaintextByteCount: UInt64(Self.maximumThumbnailByteCount),
                invalidError: .verificationFailed
            )
            let plaintext = try access.open(ciphertext, for: .thumbnail(item))
            try Task.checkCancellation()
            guard !plaintext.isEmpty,
                  plaintext.count <= Self.maximumThumbnailByteCount else {
                throw StoreError.verificationFailed
            }
            return plaintext
        }
    }

    /// Removes references to deleted content without touching either content
    /// store. Orphaned presentation thumbnails are removed only after the new
    /// manifest is durably written.
    public func reconcile(validItems: Set<VaultPresentedContentReference>) throws {
        try manifestTransaction.withLock {
            var manifest = try loadManifest()
            let removedThumbnails = manifest.thumbnails.filter { !validItems.contains($0.item) }
            manifest.memberships.removeAll { !validItems.contains($0.item) }
            manifest.thumbnails.removeAll { !validItems.contains($0.item) }
            try saveManifest(manifest)
            for record in removedThumbnails {
                try? fileManager.removeItem(at: thumbnailURL(for: record.blobName))
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
                "KeyHollow/FolderPresentationData",
                isDirectory: true
            )
        }
        let target = dataRoot.appendingPathComponent(
            vaultID.uuidString.lowercased(),
            isDirectory: true
        ).standardizedFileURL
        let transaction = FolderManifestTransactionRegistry.shared.transaction(for: target)
        try transaction.withLock {
            guard fileManager.fileExists(atPath: target.path) else { return }
            try fileManager.removeItem(at: target)
        }
    }

    private var manifestURL: URL { root.appendingPathComponent("manifest.khm") }

    private func normalizedFolderName(_ proposed: String) throws -> String {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= Self.maximumFolderNameLength,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw StoreError.invalidFolderName
        }
        return name
    }

    private func validate(_ manifest: VaultFolderPresentationManifest) throws {
        guard manifest.version == VaultFolderPresentationManifest.currentVersion else {
            throw StoreError.invalidManifest
        }

        var folderIDs = Set<UUID>()
        var folderNameKeys = Set<String>()
        for folder in manifest.folders {
            let normalizedName = try normalizedFolderName(folder.name)
            guard folderIDs.insert(folder.id).inserted,
                  folderNameKeys.insert(Self.folderNameCollisionKey(normalizedName)).inserted else {
                throw StoreError.invalidManifest
            }
        }

        guard Set(manifest.memberships.map(\.item)).count == manifest.memberships.count,
              manifest.memberships.allSatisfy({ folderIDs.contains($0.folderID) }),
              Set(manifest.thumbnails.map(\.item)).count == manifest.thumbnails.count,
              Set(manifest.thumbnails.map(\.blobName)).count == manifest.thumbnails.count,
              manifest.thumbnails.allSatisfy({ Self.isSafeThumbnailName($0.blobName) }) else {
            throw StoreError.invalidManifest
        }
    }

    private static func folderNameCollisionKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: collisionLocale)
            .precomposedStringWithCanonicalMapping
    }

    private static func isSafeThumbnailName(_ name: String) -> Bool {
        !name.isEmpty
            && name.utf8.count <= 255
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
            && URL(fileURLWithPath: name).lastPathComponent == name
            && URL(fileURLWithPath: name).pathExtension.lowercased() == "kht"
    }

    /// Existing authenticated manifests can exceed the current growth policy.
    /// Mutations that do not grow their encoded representation remain available
    /// so users can rename down, move/delete content, and migrate legacy data.
    private func validateGrowth(
        from original: VaultFolderPresentationManifest?,
        to candidate: VaultFolderPresentationManifest,
        limitError: StoreError
    ) throws {
        let encoded = try JSONEncoder().encode(candidate)
        guard encoded.count <= Self.legacyMaximumManifestByteCount else {
            throw StoreError.invalidManifest
        }
        guard encoded.count <= Self.maximumManifestByteCount else {
            if let original {
                let originalCount = try JSONEncoder().encode(original).count
                guard encoded.count <= originalCount else { throw limitError }
            } else {
                throw limitError
            }
            return
        }
    }

    private func saveManifest(_ manifest: VaultFolderPresentationManifest) throws {
        try manifestTransaction.withLock {
            try validate(manifest)
            try Task.checkCancellation()
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

    /// A manifest replace may commit before reporting an error. Only an
    /// authenticated durable manifest can authorize rollback of the new blob.
    private func recoverThumbnailManifestCommit(
        item: VaultPresentedContentReference,
        blobName: String
    ) -> ManifestCommitRecovery {
        do {
            let durable = try loadDurableManifestForCommitRecovery()
            if durable.thumbnails.contains(where: {
                $0.item == item && $0.blobName == blobName
            }) {
                return .committed
            }
            return durable.thumbnails.contains(where: { $0.blobName == blobName })
                ? .unknown
                : .notReferenced
        } catch {
            return .unknown
        }
    }

    /// Cancellation cannot short-circuit the post-error safety check.
    private func loadDurableManifestForCommitRecovery() throws
        -> VaultFolderPresentationManifest {
        try access.checkAccess()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }
        let ciphertext = try readCiphertext(
            at: manifestURL,
            maximumPlaintextByteCount: UInt64(Self.legacyMaximumManifestByteCount),
            invalidError: .invalidManifest
        )
        let plaintext = try access.open(ciphertext, for: .manifest)
        guard plaintext.count <= Self.legacyMaximumManifestByteCount else {
            throw StoreError.invalidManifest
        }
        let manifest = try JSONDecoder().decode(
            VaultFolderPresentationManifest.self,
            from: plaintext
        )
        try validate(manifest)
        return manifest
    }

    private func thumbnailURL(for blobName: String) throws -> URL {
        guard Self.isSafeThumbnailName(blobName) else {
            throw StoreError.invalidManifest
        }
        return root.appendingPathComponent(blobName, isDirectory: false)
    }

    private func readCiphertext(
        at url: URL,
        maximumPlaintextByteCount: UInt64,
        invalidError: StoreError
    ) throws -> Data {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize >= Int(Self.sealedBoxOverheadByteCount) else {
            throw invalidError
        }

        let maximumCiphertextByteCount = maximumPlaintextByteCount
            + Self.sealedBoxOverheadByteCount
        guard UInt64(fileSize) <= maximumCiphertextByteCount else {
            throw invalidError
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
            throw invalidError
        }
        return ciphertext
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(url, fileManager: fileManager)
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
