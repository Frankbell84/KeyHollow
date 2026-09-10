import Foundation

public struct VaultGeneralFileImportResult: Equatable, Sendable {
    public let importedCount: Int
    public let failedCount: Int

    public init(importedCount: Int, failedCount: Int) {
        self.importedCount = importedCount
        self.failedCount = failedCount
    }
}

public struct VaultGeneralFileRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let importedAt: Date
    public let displayName: String
    public let contentTypeIdentifier: String?
    public let originalByteCount: UInt64
    public let blobName: String

    public init(
        id: UUID,
        importedAt: Date,
        displayName: String,
        contentTypeIdentifier: String?,
        originalByteCount: UInt64,
        blobName: String
    ) {
        self.id = id
        self.importedAt = importedAt
        self.displayName = displayName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.originalByteCount = originalByteCount
        self.blobName = blobName
    }
}

public struct VaultGeneralFileManifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public var files: [VaultGeneralFileRecord]

    public init(version: Int, files: [VaultGeneralFileRecord]) {
        self.version = version
        self.files = files
    }

    public static var empty: VaultGeneralFileManifest {
        VaultGeneralFileManifest(version: currentVersion, files: [])
    }
}

/// Authenticated ciphertext inventory exposed through the add-on boundary for
/// portable-vault transfer. The transfer layer never receives plaintext files.
public struct VaultGeneralFileArchiveInventory: Sendable {
    public let manifest: VaultGeneralFileManifest
    public let manifestURL: URL?
    public let blobURLsByName: [String: URL]

    public init(
        manifest: VaultGeneralFileManifest,
        manifestURL: URL?,
        blobURLsByName: [String: URL]
    ) {
        self.manifest = manifest
        self.manifestURL = manifestURL
        self.blobURLsByName = blobURLsByName
    }
}

public enum VaultGeneralFileKeyPurpose: Sendable {
    case manifest
    case file(UUID)

    public var cryptographicDomain: String {
        switch self {
        case .manifest:
            "general-files.manifest.v1"
        case .file(let id):
            "general-files.blob.v1.\(id.uuidString.lowercased())"
        }
    }
}

/// The add-on can authenticate encrypted data while the unlocked session keeps
/// exclusive ownership of the vault key and revocation lifecycle.
public protocol VaultGeneralFileCryptographicAccess: Sendable {
    var vaultID: UUID { get }

    func checkAccess() throws
    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data
    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data

    /// Opens authenticated bytes and synchronously consumes them while a
    /// revocable implementation still owns its access lifetime. The fixed
    /// `Void` result avoids returning decrypted bytes across this boundary.
    func open(
        _ ciphertext: Data,
        for purpose: VaultGeneralFileKeyPurpose,
        consuming consumer: (Data) throws -> Void
    ) throws
}

public struct PreparedGeneralFileExport: Identifiable, Sendable {
    public let id: UUID
    public let urls: [URL]
    let rootURL: URL
    /// Keeps this export's transient ownership registered even if the store
    /// that prepared it leaves its lifecycle while a share sheet still holds
    /// the exported URLs.
    private let temporarySession: GeneralFileTemporarySession

    init(
        id: UUID,
        urls: [URL],
        rootURL: URL,
        temporarySession: GeneralFileTemporarySession
    ) {
        self.id = id
        self.urls = urls
        self.rootURL = rootURL
        self.temporarySession = temporarySession
    }
}
