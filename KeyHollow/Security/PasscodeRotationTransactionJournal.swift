import CryptoKit
import Foundation
import KeyHollowCryptoCore
import KeyHollowVaultCore

enum PasscodeRotationTransactionError: Error, Equatable {
    case invalidJournal
    case invalidJournalKeyData
    case recoveryIncomplete
}

enum PasscodeRotationJournalKeySchedule {
    static func key(devicePepper: Data) throws -> SymmetricKey {
        guard devicePepper.count == 32 else {
            throw PasscodeRotationTransactionError.invalidJournalKeyData
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: devicePepper),
            salt: Data("keyhollow.passcode-rotation-journal.v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}

struct PasscodeRotationTransactionRecord: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let transactionID: UUID
    let vaultID: UUID
    let oldLocator: String
    let newLocator: String
    let oldEnvelopeSHA256: Data
    let newEnvelopeSHA256: Data

    init(
        transactionID: UUID = UUID(),
        vaultID: UUID,
        oldLocator: String,
        newLocator: String,
        oldEnvelopeSHA256: Data,
        newEnvelopeSHA256: Data
    ) {
        version = Self.currentVersion
        self.transactionID = transactionID
        self.vaultID = vaultID
        self.oldLocator = oldLocator
        self.newLocator = newLocator
        self.oldEnvelopeSHA256 = oldEnvelopeSHA256
        self.newEnvelopeSHA256 = newEnvelopeSHA256
    }

    func validate() throws {
        guard version == Self.currentVersion,
              oldLocator != newLocator,
              Self.isValidLocator(oldLocator),
              Self.isValidLocator(newLocator),
              oldEnvelopeSHA256.count == 32,
              newEnvelopeSHA256.count == 32 else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
    }

    private static func isValidLocator(_ locator: String) -> Bool {
        locator.utf8.count == 64
            && locator.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
    }
}

enum PasscodeRotationRecoveryOutcome: Equatable {
    case originalRetained
    case replacementCommitted
}

/// Authenticated, device-local intent log for the two-file passcode rotation.
/// Recovery never needs a passcode or stores a vault key: it authenticates the
/// expected envelopes by digest and converges to exactly one credential path.
struct PasscodeRotationTransactionJournal {
    private static let fileExtension = "khctxn"
    private static let maximumJournalByteCount: UInt64 = 64 * 1_024

    private let root: URL
    private let authenticationKey: SymmetricKey
    private let fileManager = FileManager.default

    static func recoveryRequired(rootOverride: URL? = nil) throws -> Bool {
        let fileManager = FileManager.default
        let root = try resolvedRoot(override: rootOverride, createApplicationSupport: false)
        guard fileManager.fileExists(atPath: root.path) else { return false }
        try validateRoot(root, fileManager: fileManager)
        return try !fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ).isEmpty
    }

    init(authenticationKey: SymmetricKey, rootOverride: URL? = nil) throws {
        self.authenticationKey = authenticationKey
        root = try Self.resolvedRoot(
            override: rootOverride,
            createApplicationSupport: true
        )
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try Self.validateRoot(root, fileManager: fileManager)
        try Self.protectAndExclude(root, fileManager: fileManager)
    }

    func begin(
        vaultID: UUID,
        oldLocator: String,
        oldEnvelope: VaultEnvelope,
        newLocator: String,
        newEnvelope: VaultEnvelope
    ) throws -> PasscodeRotationTransactionRecord {
        let record = PasscodeRotationTransactionRecord(
            vaultID: vaultID,
            oldLocator: oldLocator,
            newLocator: newLocator,
            oldEnvelopeSHA256: Self.digest(oldEnvelope),
            newEnvelopeSHA256: Self.digest(newEnvelope)
        )
        try record.validate()

        let target = url(for: record)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let encoded = try JSONEncoder().encode(record)
        let sealed = try CryptoBox.seal(encoded, using: authenticationKey)
        guard UInt64(sealed.count) <= Self.maximumJournalByteCount else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        try sealed.write(to: target, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(target, fileManager: fileManager)
        return record
    }

    func finish(_ record: PasscodeRotationTransactionRecord) throws {
        try record.validate()
        let target = url(for: record)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    func recoverAll(credentialStore: any VaultCredentialStoring) async throws {
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        for url in urls {
            let record = try loadRecord(at: url)
            _ = try await recover(record, credentialStore: credentialStore)
        }
    }

    func recover(
        _ record: PasscodeRotationTransactionRecord,
        credentialStore: any VaultCredentialStoring
    ) async throws -> PasscodeRotationRecoveryOutcome {
        try record.validate()

        let oldEnvelope = try await readEnvelope(
            locator: record.oldLocator,
            credentialStore: credentialStore
        )
        let newEnvelope = try await readEnvelope(
            locator: record.newLocator,
            credentialStore: credentialStore
        )
        let originalMatches = oldEnvelope.map {
            Self.digest($0) == record.oldEnvelopeSHA256
        } ?? false
        let replacementMatches = newEnvelope.map {
            Self.digest($0) == record.newEnvelopeSHA256
        } ?? false

        guard oldEnvelope == nil || originalMatches else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        if newEnvelope != nil, !replacementMatches {
            // A race populated the requested new locator with an unrelated
            // credential. If the authenticated original still exists, preserve
            // both and discard only this uncommitted rotation intent.
            guard originalMatches else {
                throw PasscodeRotationTransactionError.invalidJournal
            }
            try finish(record)
            return .originalRetained
        }

        if replacementMatches {
            if originalMatches {
                do {
                    try await credentialStore.delete(locator: record.oldLocator)
                } catch {
                    throw PasscodeRotationTransactionError.recoveryIncomplete
                }
            }
            let replacementRemains = try await expectedEnvelopeExists(
                locator: record.newLocator,
                digest: record.newEnvelopeSHA256,
                credentialStore: credentialStore
            )
            let originalRemains = try await credentialExists(
                locator: record.oldLocator,
                credentialStore: credentialStore
            )
            guard replacementRemains, !originalRemains else {
                throw PasscodeRotationTransactionError.recoveryIncomplete
            }
        } else {
            // The process stopped before the replacement became durable. The
            // original credential remains the single valid route to the vault.
            guard originalMatches else {
                throw PasscodeRotationTransactionError.recoveryIncomplete
            }
        }

        try finish(record)
        return replacementMatches ? .replacementCommitted : .originalRetained
    }

    private func loadRecord(at url: URL) throws -> PasscodeRotationTransactionRecord {
        guard url.pathExtension == Self.fileExtension else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              UInt64(fileSize) <= Self.maximumJournalByteCount else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let sealed = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard sealed.count == fileSize else {
            throw PasscodeRotationTransactionError.invalidJournal
        }

        let plaintext: Data
        do {
            plaintext = try CryptoBox.open(sealed, using: authenticationKey)
        } catch {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let record: PasscodeRotationTransactionRecord
        do {
            record = try JSONDecoder().decode(PasscodeRotationTransactionRecord.self, from: plaintext)
            try record.validate()
        } catch {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        guard url.deletingPathExtension().lastPathComponent
            == record.transactionID.uuidString.lowercased() else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        return record
    }

    private func readEnvelope(
        locator: String,
        credentialStore: any VaultCredentialStoring
    ) async throws -> VaultEnvelope? {
        let envelope: VaultEnvelope?
        do {
            envelope = try await credentialStore.read(locator: locator)
        } catch {
            throw PasscodeRotationTransactionError.recoveryIncomplete
        }
        return envelope
    }

    private func expectedEnvelopeExists(
        locator: String,
        digest: Data,
        credentialStore: any VaultCredentialStoring
    ) async throws -> Bool {
        let envelope = try await readEnvelope(
            locator: locator,
            credentialStore: credentialStore
        )
        return envelope.map { Self.digest($0) == digest } ?? false
    }

    private func credentialExists(
        locator: String,
        credentialStore: any VaultCredentialStoring
    ) async throws -> Bool {
        do {
            return try await credentialStore.read(locator: locator) != nil
        } catch {
            throw PasscodeRotationTransactionError.recoveryIncomplete
        }
    }

    private func url(for record: PasscodeRotationTransactionRecord) -> URL {
        root
            .appendingPathComponent(
                record.transactionID.uuidString.lowercased(),
                isDirectory: false
            )
            .appendingPathExtension(Self.fileExtension)
    }

    static func digest(_ envelope: VaultEnvelope) -> Data {
        var version = Int64(envelope.version).littleEndian
        var canonical = Swift.withUnsafeBytes(of: &version) { Data($0) }
        canonical.append(envelope.sealedPayload)
        return Data(SHA256.hash(data: canonical))
    }

    private static func resolvedRoot(
        override: URL?,
        createApplicationSupport: Bool
    ) throws -> URL {
        if let override { return override.standardizedFileURL }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createApplicationSupport
        )
        return appSupport
            .appendingPathComponent("KeyHollow/PasscodeRotationTransactions", isDirectory: true)
            .standardizedFileURL
    }

    private static func validateRoot(_ root: URL, fileManager: FileManager) throws {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
    }

    private static func protectAndExclude(_ url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(values)
    }
}

enum VaultDeletionJournalKeySchedule {
    static func key(devicePepper: Data) throws -> SymmetricKey {
        guard devicePepper.count == 32 else {
            throw PasscodeRotationTransactionError.invalidJournalKeyData
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: devicePepper),
            salt: Data("keyhollow.vault-deletion-journal.v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}

struct VaultDeletionTransactionRecord: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let transactionID: UUID
    let vaultID: UUID
    let credentialLocator: String
    let credentialEnvelopeSHA256: Data

    init(
        transactionID: UUID = UUID(),
        vaultID: UUID,
        credentialLocator: String,
        credentialEnvelopeSHA256: Data
    ) {
        version = Self.currentVersion
        self.transactionID = transactionID
        self.vaultID = vaultID
        self.credentialLocator = credentialLocator
        self.credentialEnvelopeSHA256 = credentialEnvelopeSHA256
    }

    func validate() throws {
        guard version == Self.currentVersion,
              credentialLocator.utf8.count == 64,
              credentialLocator.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }),
              credentialEnvelopeSHA256.count == 32 else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
    }
}

enum VaultDeletionRecoveryOutcome: Equatable {
    case credentialRetained
    case credentialDestroyed
}

enum VaultDeletionRecoveryError: Error, Equatable {
    /// Credential absence was positively observed, but encrypted-data or
    /// journal cleanup did not reach a durable terminal state.
    case credentialDestroyedCleanupIncomplete
}

/// Records vault deletion before the credential is removed. If deletion
/// commits but encrypted-directory cleanup is interrupted, startup can safely
/// retry only after authenticating that the expected credential is absent.
struct VaultDeletionTransactionJournal {
    private static let fileExtension = "khdtxn"
    private static let maximumJournalByteCount: UInt64 = 64 * 1_024

    private let root: URL
    private let authenticationKey: SymmetricKey
    private let fileManager = FileManager.default

    static func recoveryRequired(rootOverride: URL? = nil) throws -> Bool {
        let fileManager = FileManager.default
        let root = try resolvedRoot(override: rootOverride, createApplicationSupport: false)
        guard fileManager.fileExists(atPath: root.path) else { return false }
        try validateRoot(root, fileManager: fileManager)
        return try !fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ).isEmpty
    }

    init(authenticationKey: SymmetricKey, rootOverride: URL? = nil) throws {
        self.authenticationKey = authenticationKey
        root = try Self.resolvedRoot(
            override: rootOverride,
            createApplicationSupport: true
        )
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try Self.validateRoot(root, fileManager: fileManager)
        try Self.protectAndExclude(root, fileManager: fileManager)
    }

    func begin(
        vaultID: UUID,
        credentialLocator: String,
        credentialEnvelope: VaultEnvelope
    ) throws -> VaultDeletionTransactionRecord {
        let record = VaultDeletionTransactionRecord(
            vaultID: vaultID,
            credentialLocator: credentialLocator,
            credentialEnvelopeSHA256: PasscodeRotationTransactionJournal.digest(
                credentialEnvelope
            )
        )
        try record.validate()

        let target = url(for: record)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let encoded = try JSONEncoder().encode(record)
        let sealed = try CryptoBox.seal(encoded, using: authenticationKey)
        guard UInt64(sealed.count) <= Self.maximumJournalByteCount else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        try sealed.write(to: target, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(target, fileManager: fileManager)
        return record
    }

    func finish(_ record: VaultDeletionTransactionRecord) throws {
        try record.validate()
        let target = url(for: record)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    func recoverAll(
        credentialStore: any VaultCredentialStoring,
        cleanup: @Sendable (UUID) throws -> Void
    ) async throws {
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        for url in urls {
            let record = try loadRecord(at: url)
            _ = try await recover(
                record,
                credentialStore: credentialStore,
                cleanup: cleanup
            )
        }
    }

    func recover(
        _ record: VaultDeletionTransactionRecord,
        credentialStore: any VaultCredentialStoring,
        cleanup: @Sendable (UUID) throws -> Void
    ) async throws -> VaultDeletionRecoveryOutcome {
        try record.validate()
        let envelope: VaultEnvelope?
        do {
            envelope = try await credentialStore.read(locator: record.credentialLocator)
        } catch {
            throw PasscodeRotationTransactionError.recoveryIncomplete
        }

        if let envelope {
            guard PasscodeRotationTransactionJournal.digest(envelope)
                == record.credentialEnvelopeSHA256 else {
                throw PasscodeRotationTransactionError.invalidJournal
            }
            // Credential removal did not commit. Preserve the vault and data.
            try finish(record)
            return .credentialRetained
        }

        do {
            try cleanup(record.vaultID)
            try finish(record)
        } catch {
            // Credential absence was authenticated above. Keep the journal so
            // cleanup is retried before the app becomes usable, while allowing
            // callers to distinguish this committed deletion from an unknown
            // credential-store read failure.
            throw VaultDeletionRecoveryError.credentialDestroyedCleanupIncomplete
        }
        return .credentialDestroyed
    }

    private func loadRecord(at url: URL) throws -> VaultDeletionTransactionRecord {
        guard url.pathExtension == Self.fileExtension else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              UInt64(fileSize) <= Self.maximumJournalByteCount else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let sealed = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard sealed.count == fileSize else {
            throw PasscodeRotationTransactionError.invalidJournal
        }

        let plaintext: Data
        do {
            plaintext = try CryptoBox.open(sealed, using: authenticationKey)
        } catch {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        let record: VaultDeletionTransactionRecord
        do {
            record = try JSONDecoder().decode(VaultDeletionTransactionRecord.self, from: plaintext)
            try record.validate()
        } catch {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        guard url.deletingPathExtension().lastPathComponent
            == record.transactionID.uuidString.lowercased() else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
        return record
    }

    private func url(for record: VaultDeletionTransactionRecord) -> URL {
        root
            .appendingPathComponent(
                record.transactionID.uuidString.lowercased(),
                isDirectory: false
            )
            .appendingPathExtension(Self.fileExtension)
    }

    private static func resolvedRoot(
        override: URL?,
        createApplicationSupport: Bool
    ) throws -> URL {
        if let override { return override.standardizedFileURL }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createApplicationSupport
        )
        return appSupport
            .appendingPathComponent("KeyHollow/VaultDeletionTransactions", isDirectory: true)
            .standardizedFileURL
    }

    private static func validateRoot(_ root: URL, fileManager: FileManager) throws {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw PasscodeRotationTransactionError.invalidJournal
        }
    }

    private static func protectAndExclude(_ url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(values)
    }
}
