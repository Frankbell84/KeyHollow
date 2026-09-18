import CryptoKit
import Foundation
import KeyHollowPhotoCore

enum PortableArchivePayloadError: Error, Equatable {
    case alreadyFinished
    case destinationExists
    case digestMismatch(String)
    case duplicateEntry(String)
    case invalidCatalog
    case invalidCatalogLength
    case invalidEntry(String)
    case invalidMagic
    case missingEntry(String)
    case sourceChanged(String)
    case truncatedPayload
    case unexpectedPayloadData
    case unsupportedVersion
}

enum PortableArchivePayloadFormat {
    static let magic = Data([0x4b, 0x48, 0x50, 0x41, 0x59, 0x4c, 0x44, 0x00])
    static let currentVersion: UInt32 = 1
    static let prefixByteCount = 16
    static let maximumCatalogByteCount = 16 * 1_024 * 1_024
    static let maximumPhotoCount = 10_000
    static let maximumSupplementalFileCount = 10_000
    static let maximumFolderCount = 10_000
    static let maximumFolderMembershipCount = 20_000
    static let maximumEntryCount = 2 + (maximumPhotoCount * 2) + maximumSupplementalFileCount
    static let maximumFolderAwareEntryCount = maximumEntryCount + 1
    static let aeadOverheadByteCount: UInt64 = 28
    static let maximumPhotoManifestByteCount: UInt64 = 16 * 1_024 * 1_024
    static let maximumSupplementalManifestByteCount: UInt64 = 8 * 1_024 * 1_024
    static let maximumFolderManifestByteCount: UInt64 = 8 * 1_024 * 1_024
    static let maximumPhotoOriginalByteCount: UInt64 = 100 * 1_024 * 1_024
    static let maximumThumbnailByteCount: UInt64 = 4 * 1_024 * 1_024
    static let maximumSupplementalBlobByteCount: UInt64 = 100 * 1_024 * 1_024
    static let maximumEntryByteCount = maximumSupplementalBlobByteCount
        + aeadOverheadByteCount
    static let maximumTotalByteCount: UInt64 = 10 * 1_024 * 1_024 * 1_024
    // Catalog v1/v2 was already shipped with these structural ceilings. Keep
    // accepting them so Build 39 exports do not become unreadable; v3 applies
    // the tighter policy above to newly bounded archives.
    static let legacyMaximumCatalogByteCount = 33_554_432
    static let legacyMaximumEntryCount = 200_001
    static let legacyMaximumEntryByteCount: UInt64 = 1_099_511_627_776
    static let legacyMaximumTotalByteCount: UInt64 = 4_398_046_511_104
    static let fileReadByteCount = 1_048_576
    static let sha256ByteCount = 32

    static func maximumCiphertextByteCount(
        for role: PortableArchivePayloadEntryRole
    ) -> UInt64 {
        let plaintextLimit: UInt64
        switch role {
        case .manifest:
            plaintextLimit = maximumPhotoManifestByteCount
        case .original:
            plaintextLimit = maximumPhotoOriginalByteCount
        case .thumbnail:
            plaintextLimit = maximumThumbnailByteCount
        case .supplementalManifest:
            plaintextLimit = maximumSupplementalManifestByteCount
        case .supplementalBlob:
            plaintextLimit = maximumSupplementalBlobByteCount
        case .folderManifest:
            plaintextLimit = maximumFolderManifestByteCount
        }
        return plaintextLimit + aeadOverheadByteCount
    }

    static func checkedTotalByteCount(
        adding byteCount: UInt64,
        to currentTotal: UInt64,
        maximum: UInt64 = maximumTotalByteCount
    ) throws -> UInt64 {
        let (newTotal, overflow) = currentTotal.addingReportingOverflow(byteCount)
        guard !overflow, newTotal <= maximum else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        return newTotal
    }

    static func maximumCatalogByteCount(forCatalogVersion version: Int) -> Int {
        version >= PortableArchivePayloadCatalog.currentVersion
            ? maximumCatalogByteCount
            : legacyMaximumCatalogByteCount
    }
}

enum PortableArchivePayloadEntryRole: String, Codable, Sendable {
    case manifest
    case original
    case thumbnail
    case supplementalManifest
    case supplementalBlob
    case folderManifest
}

struct PortableArchivePayloadEntry: Codable, Equatable, Sendable {
    let storageName: String
    let role: PortableArchivePayloadEntryRole
    let ciphertextByteCount: UInt64
    let ciphertextSHA256: Data
}

public struct PortableArchivePayloadCatalog: Codable, Equatable, Sendable {
    static let legacyPhotoOnlyVersion = 1
    static let legacyGeneralFileVersion = 2
    static let currentVersion = 3
    static let folderHierarchyVersion = 4
    static let maximumSupportedVersion = folderHierarchyVersion

    let version: Int
    let entries: [PortableArchivePayloadEntry]

    func validate(encodedCatalogByteCount: Int? = nil) throws {
        let usesCurrentLimits = version >= Self.currentVersion
        let maximumEntryCount: Int
        if version >= Self.folderHierarchyVersion {
            maximumEntryCount = PortableArchivePayloadFormat.maximumFolderAwareEntryCount
        } else if usesCurrentLimits {
            maximumEntryCount = PortableArchivePayloadFormat.maximumEntryCount
        } else {
            maximumEntryCount = PortableArchivePayloadFormat.legacyMaximumEntryCount
        }
        let maximumTotalByteCount = usesCurrentLimits
            ? PortableArchivePayloadFormat.maximumTotalByteCount
            : PortableArchivePayloadFormat.legacyMaximumTotalByteCount
        guard (Self.legacyPhotoOnlyVersion...Self.maximumSupportedVersion).contains(version),
              !entries.isEmpty,
              entries.count <= maximumEntryCount else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        if let encodedCatalogByteCount {
            guard encodedCatalogByteCount > 0,
                  encodedCatalogByteCount <= PortableArchivePayloadFormat
                    .maximumCatalogByteCount(forCatalogVersion: version) else {
                throw PortableArchivePayloadError.invalidCatalogLength
            }
        }

        var names = Set<String>()
        var manifestCount = 0
        var originalCount = 0
        var thumbnailCount = 0
        var supplementalManifestCount = 0
        var supplementalBlobCount = 0
        var folderManifestCount = 0
        var totalByteCount: UInt64 = 0

        for entry in entries {
            try Self.validateStorageName(entry.storageName, role: entry.role)
            guard names.insert(entry.storageName).inserted else {
                throw PortableArchivePayloadError.duplicateEntry(entry.storageName)
            }
            let maximumEntryByteCount = usesCurrentLimits
                ? PortableArchivePayloadFormat.maximumCiphertextByteCount(for: entry.role)
                : PortableArchivePayloadFormat.legacyMaximumEntryByteCount
            guard entry.ciphertextByteCount >= 28,
                  entry.ciphertextByteCount <= maximumEntryByteCount,
                  entry.ciphertextSHA256.count == PortableArchivePayloadFormat.sha256ByteCount else {
                throw PortableArchivePayloadError.invalidEntry(entry.storageName)
            }

            totalByteCount = try PortableArchivePayloadFormat.checkedTotalByteCount(
                adding: entry.ciphertextByteCount,
                to: totalByteCount,
                maximum: maximumTotalByteCount
            )

            if entry.role == .manifest {
                manifestCount += 1
            } else if entry.role == .original {
                originalCount += 1
            } else if entry.role == .thumbnail {
                thumbnailCount += 1
            } else if entry.role == .supplementalManifest {
                supplementalManifestCount += 1
            } else if entry.role == .supplementalBlob {
                supplementalBlobCount += 1
            } else if entry.role == .folderManifest {
                folderManifestCount += 1
            }
        }

        let hasValidFolderManifestCount = version >= Self.folderHierarchyVersion
            ? folderManifestCount == 1
            : folderManifestCount == 0
        guard manifestCount == 1,
              entries.first?.role == .manifest,
              entries.first?.storageName == "manifest.khm",
              supplementalManifestCount <= 1,
              supplementalBlobCount == 0 || supplementalManifestCount == 1,
              version >= Self.legacyGeneralFileVersion
                || (supplementalManifestCount == 0 && supplementalBlobCount == 0),
              hasValidFolderManifestCount else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        if usesCurrentLimits {
            guard originalCount == thumbnailCount,
                  originalCount <= PortableArchivePayloadFormat.maximumPhotoCount,
                  supplementalBlobCount
                    <= PortableArchivePayloadFormat.maximumSupplementalFileCount else {
                throw PortableArchivePayloadError.invalidCatalog
            }
        }
    }

    static func forExport(entries: [PortableArchivePayloadEntry]) throws
        -> PortableArchivePayloadCatalog {
        let includesFolderManifest = entries.contains { $0.role == .folderManifest }
        let requestedVersion = includesFolderManifest
            ? Self.folderHierarchyVersion
            : Self.currentVersion
        let current = PortableArchivePayloadCatalog(
            version: requestedVersion,
            entries: entries
        )
        if let encoded = try? JSONEncoder().encode(current),
           encoded.count <= PortableArchivePayloadFormat.maximumCatalogByteCount,
           (try? current.validate(encodedCatalogByteCount: encoded.count)) != nil {
            return current
        }

        guard !includesFolderManifest else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        let legacy = PortableArchivePayloadCatalog(
            version: Self.legacyGeneralFileVersion,
            entries: entries
        )
        let encodedLegacy = try JSONEncoder().encode(legacy)
        try legacy.validate(encodedCatalogByteCount: encodedLegacy.count)
        return legacy
    }

    static func validateStorageName(
        _ name: String,
        role: PortableArchivePayloadEntryRole
    ) throws {
        guard !name.isEmpty,
              name.utf8.count <= 255,
              name != ".",
              name != "..",
              !name.contains("\\"),
              !name.contains("\0"),
              !name.hasPrefix("/"),
              !name.hasSuffix("/") else {
            throw PortableArchivePayloadError.invalidEntry(name)
        }

        let expectedExtension: String
        switch role {
        case .manifest:
            guard name == "manifest.khm" else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khm"
        case .original:
            guard !name.contains("/") else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khp"
        case .thumbnail:
            guard !name.contains("/") else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "kht"
        case .supplementalManifest:
            guard name == "supplemental/manifest.khm" else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khm"
        case .supplementalBlob:
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 2,
                  components[0] == "supplemental",
                  !components[1].isEmpty,
                  components[1] != ".",
                  components[1] != ".." else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khf"
        case .folderManifest:
            guard name == "folders/manifest.khm" else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khm"
        }

        let leaf = String(name.split(separator: "/").last ?? "")
        guard URL(fileURLWithPath: leaf).lastPathComponent == leaf,
              URL(fileURLWithPath: leaf).pathExtension.lowercased() == expectedExtension else {
            throw PortableArchivePayloadError.invalidEntry(name)
        }
    }
}

public struct PortableVaultSupplementalArchiveEntry: Sendable {
    public let storageName: String
    public let sourceURL: URL

    public init(storageName: String, sourceURL: URL) {
        self.storageName = storageName
        self.sourceURL = sourceURL
    }
}

public struct PortableVaultSupplementalArchiveInventory: Sendable {
    public let manifestURL: URL?
    public let entries: [PortableVaultSupplementalArchiveEntry]
    public let itemCount: Int
    public let itemIDs: Set<UUID>

    public init(
        manifestURL: URL?,
        entries: [PortableVaultSupplementalArchiveEntry],
        itemCount: Int,
        itemIDs: Set<UUID> = []
    ) {
        self.manifestURL = manifestURL
        self.entries = entries
        self.itemCount = itemCount
        self.itemIDs = itemIDs
    }

    public static let empty = PortableVaultSupplementalArchiveInventory(
        manifestURL: nil,
        entries: [],
        itemCount: 0,
        itemIDs: []
    )
}

public enum PortableVaultFolderItemKind: String, Codable, Hashable, Sendable {
    case photo
    case generalFile
}

public struct PortableVaultFolderItemReference: Codable, Hashable, Sendable {
    public let kind: PortableVaultFolderItemKind
    public let id: UUID

    public init(kind: PortableVaultFolderItemKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// Authenticated folder metadata supplied by the independently compiled
/// presentation add-on. The ciphertext is already sealed with the vault's
/// scoped folder-manifest key; TransferCore treats it as opaque bytes.
public struct PortableVaultFolderArchiveInventory: Sendable {
    public let manifestCiphertext: Data?
    public let folderCount: Int
    public let membershipCount: Int
    public let referencedItems: Set<PortableVaultFolderItemReference>

    public init(
        manifestCiphertext: Data?,
        folderCount: Int,
        membershipCount: Int,
        referencedItems: Set<PortableVaultFolderItemReference>
    ) {
        self.manifestCiphertext = manifestCiphertext
        self.folderCount = folderCount
        self.membershipCount = membershipCount
        self.referencedItems = referencedItems
    }

    public static let empty = PortableVaultFolderArchiveInventory(
        manifestCiphertext: nil,
        folderCount: 0,
        membershipCount: 0,
        referencedItems: []
    )
}

fileprivate enum PortableArchivePayloadEntrySource: Sendable {
    case file(URL)
    case data(Data)
}

struct PortableArchivePayloadSource: Sendable {
    let catalog: PortableArchivePayloadCatalog
    private let sourcesByStorageName: [String: PortableArchivePayloadEntrySource]

    static func create(
        rootURL: URL,
        manifest: VaultPhotoManifest
    ) throws -> PortableArchivePayloadSource {
        guard manifest.version == VaultPhotoManifest.currentVersion else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        try validateSourceRoot(rootURL)

        var requestedEntries: [(String, PortableArchivePayloadEntryRole)] = [
            ("manifest.khm", .manifest)
        ]
        for photo in manifest.photos {
            requestedEntries.append((photo.blobName, .original))
            requestedEntries.append((photo.thumbnailName, .thumbnail))
        }

        return try create(requestedEntries.map { entry in
            (
                entry.0,
                entry.1,
                PortableArchivePayloadEntrySource.file(
                    rootURL.appendingPathComponent(entry.0, isDirectory: false)
                )
            )
        })
    }

    static func create(
        photoRootURL: URL,
        photoManifest: VaultPhotoManifest,
        supplementalInventory: PortableVaultSupplementalArchiveInventory,
        folderInventory: PortableVaultFolderArchiveInventory = .empty
    ) throws -> PortableArchivePayloadSource {
        guard photoManifest.version == VaultPhotoManifest.currentVersion,
              supplementalInventory.itemCount >= 0,
              folderInventory.folderCount >= 0,
              folderInventory.membershipCount >= 0 else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        try validateSourceRoot(photoRootURL)

        var requestedEntries: [(
            String,
            PortableArchivePayloadEntryRole,
            PortableArchivePayloadEntrySource
        )] = [
            (
                "manifest.khm",
                .manifest,
                .file(photoRootURL.appendingPathComponent("manifest.khm", isDirectory: false))
            )
        ]
        for photo in photoManifest.photos {
            requestedEntries.append((
                photo.blobName,
                .original,
                .file(photoRootURL.appendingPathComponent(photo.blobName, isDirectory: false))
            ))
            requestedEntries.append((
                photo.thumbnailName,
                .thumbnail,
                .file(photoRootURL.appendingPathComponent(photo.thumbnailName, isDirectory: false))
            ))
        }

        if supplementalInventory.itemCount == 0 {
            guard supplementalInventory.manifestURL == nil,
                  supplementalInventory.entries.isEmpty else {
                throw PortableArchivePayloadError.invalidCatalog
            }
        } else {
            guard let manifestURL = supplementalInventory.manifestURL,
                  supplementalInventory.entries.count == supplementalInventory.itemCount else {
                throw PortableArchivePayloadError.missingEntry("supplemental/manifest.khm")
            }
            requestedEntries.append((
                "supplemental/manifest.khm",
                .supplementalManifest,
                .file(manifestURL)
            ))
            for entry in supplementalInventory.entries {
                requestedEntries.append((
                    "supplemental/\(entry.storageName)",
                    .supplementalBlob,
                    .file(entry.sourceURL)
                ))
            }
        }

        if let manifestCiphertext = folderInventory.manifestCiphertext {
            guard folderInventory.folderCount > 0,
                  folderInventory.folderCount <= PortableArchivePayloadFormat.maximumFolderCount,
                  folderInventory.membershipCount
                    <= PortableArchivePayloadFormat.maximumFolderMembershipCount,
                  folderInventory.membershipCount == folderInventory.referencedItems.count else {
                throw PortableArchivePayloadError.invalidCatalog
            }
            requestedEntries.append((
                "folders/manifest.khm",
                .folderManifest,
                .data(manifestCiphertext)
            ))
        } else {
            guard folderInventory.folderCount == 0,
                  folderInventory.membershipCount == 0,
                  folderInventory.referencedItems.isEmpty else {
                throw PortableArchivePayloadError.invalidCatalog
            }
        }
        return try create(requestedEntries)
    }

    private static func create(
        _ requestedEntries: [(
            String,
            PortableArchivePayloadEntryRole,
            PortableArchivePayloadEntrySource
        )]
    ) throws -> PortableArchivePayloadSource {
        guard !requestedEntries.isEmpty,
              requestedEntries.count
                <= PortableArchivePayloadFormat.legacyMaximumEntryCount else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        var entries: [PortableArchivePayloadEntry] = []
        var sourcesByStorageName: [String: PortableArchivePayloadEntrySource] = [:]
        var totalByteCount: UInt64 = 0
        entries.reserveCapacity(requestedEntries.count)
        for (storageName, role, source) in requestedEntries {
            try PortableArchivePayloadCatalog.validateStorageName(storageName, role: role)
            let byteCount: UInt64
            switch source {
            case .file(let fileURL):
                let properties = try fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
                )
                guard properties.isRegularFile == true,
                      properties.isSymbolicLink != true,
                      let fileSize = properties.fileSize,
                      fileSize >= 28 else {
                    throw PortableArchivePayloadError.missingEntry(storageName)
                }
                byteCount = UInt64(fileSize)
            case .data(let data):
                guard data.count >= 28 else {
                    throw PortableArchivePayloadError.missingEntry(storageName)
                }
                byteCount = UInt64(data.count)
            }
            guard byteCount <= PortableArchivePayloadFormat.legacyMaximumEntryByteCount else {
                throw PortableArchivePayloadError.invalidEntry(storageName)
            }

            // Reject an oversized local source set before spending I/O hashing
            // the entry that would cross the archive-wide ceiling.
            totalByteCount = try PortableArchivePayloadFormat.checkedTotalByteCount(
                adding: byteCount,
                to: totalByteCount,
                maximum: PortableArchivePayloadFormat.legacyMaximumTotalByteCount
            )
            let digest: Data
            switch source {
            case .file(let fileURL):
                digest = try Self.hashFile(
                    fileURL,
                    expectedByteCount: byteCount,
                    storageName: storageName
                )
            case .data(let data):
                digest = Data(SHA256.hash(data: data))
            }
            entries.append(
                PortableArchivePayloadEntry(
                    storageName: storageName,
                    role: role,
                    ciphertextByteCount: byteCount,
                    ciphertextSHA256: digest
                )
            )
            guard sourcesByStorageName.updateValue(source, forKey: storageName) == nil else {
                throw PortableArchivePayloadError.duplicateEntry(storageName)
            }
        }

        let catalog = try PortableArchivePayloadCatalog.forExport(entries: entries)
        return PortableArchivePayloadSource(
            catalog: catalog,
            sourcesByStorageName: sourcesByStorageName
        )
    }

    fileprivate func source(for storageName: String) throws
        -> PortableArchivePayloadEntrySource {
        guard let source = sourcesByStorageName[storageName] else {
            throw PortableArchivePayloadError.missingEntry(storageName)
        }
        return source
    }

    private static func validateSourceRoot(_ rootURL: URL) throws {
        let properties = try rootURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard properties.isDirectory == true,
              properties.isSymbolicLink != true else {
            throw PortableArchivePayloadError.invalidCatalog
        }
    }

    fileprivate static func hashFile(
        _ fileURL: URL,
        expectedByteCount: UInt64? = nil,
        storageName: String? = nil
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        var readByteCount: UInt64 = 0

        while let data = try handle.read(
            upToCount: PortableArchivePayloadFormat.fileReadByteCount
        ), !data.isEmpty {
            try Task.checkCancellation()
            let (newCount, overflow) = readByteCount.addingReportingOverflow(
                UInt64(data.count)
            )
            guard !overflow else {
                throw PortableArchivePayloadError.sourceChanged(
                    storageName ?? fileURL.lastPathComponent
                )
            }
            if let expectedByteCount, newCount > expectedByteCount {
                throw PortableArchivePayloadError.sourceChanged(
                    storageName ?? fileURL.lastPathComponent
                )
            }
            readByteCount = newCount
            hasher.update(data: data)
        }
        if let expectedByteCount, readByteCount != expectedByteCount {
            throw PortableArchivePayloadError.sourceChanged(
                storageName ?? fileURL.lastPathComponent
            )
        }
        return Data(hasher.finalize())
    }
}

enum PortableArchivePayloadWriter {
    static func write(
        source: PortableArchivePayloadSource,
        to containerWriter: PortableArchiveContainerWriter
    ) throws {
        try source.catalog.validate()
        let encodedCatalog = try JSONEncoder().encode(source.catalog)
        try source.catalog.validate(encodedCatalogByteCount: encodedCatalog.count)

        var prefix = PortableArchivePayloadFormat.magic
        prefix.appendPayloadLittleEndian(PortableArchivePayloadFormat.currentVersion)
        prefix.appendPayloadLittleEndian(UInt32(encodedCatalog.count))
        try containerWriter.append(prefix)
        try containerWriter.append(encodedCatalog)

        for entry in source.catalog.entries {
            try Task.checkCancellation()
            var hasher = SHA256()
            var writtenByteCount: UInt64 = 0

            switch try source.source(for: entry.storageName) {
            case .file(let fileURL):
                let handle = try FileHandle(forReadingFrom: fileURL)
                do {
                    while let data = try handle.read(
                        upToCount: PortableArchivePayloadFormat.fileReadByteCount
                    ), !data.isEmpty {
                        try append(
                            data,
                            for: entry,
                            writtenByteCount: &writtenByteCount,
                            hasher: &hasher,
                            to: containerWriter
                        )
                    }
                    try handle.close()
                } catch {
                    try? handle.close()
                    throw error
                }
            case .data(let data):
                try append(
                    data,
                    for: entry,
                    writtenByteCount: &writtenByteCount,
                    hasher: &hasher,
                    to: containerWriter
                )
            }

            guard writtenByteCount == entry.ciphertextByteCount,
                  Data(hasher.finalize()) == entry.ciphertextSHA256 else {
                throw PortableArchivePayloadError.sourceChanged(entry.storageName)
            }
        }
    }

    private static func append(
        _ data: Data,
        for entry: PortableArchivePayloadEntry,
        writtenByteCount: inout UInt64,
        hasher: inout SHA256,
        to containerWriter: PortableArchiveContainerWriter
    ) throws {
        try Task.checkCancellation()
        let (newCount, overflow) = writtenByteCount.addingReportingOverflow(
            UInt64(data.count)
        )
        guard !overflow,
              newCount <= entry.ciphertextByteCount else {
            throw PortableArchivePayloadError.sourceChanged(entry.storageName)
        }
        writtenByteCount = newCount
        hasher.update(data: data)
        try containerWriter.append(data)
    }
}

final class PortableArchiveStagedPayload {
    let directoryURL: URL
    let catalog: PortableArchivePayloadCatalog

    private var ownsDirectory = true

    fileprivate init(directoryURL: URL, catalog: PortableArchivePayloadCatalog) {
        self.directoryURL = directoryURL
        self.catalog = catalog
    }

    deinit {
        if ownsDirectory {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func discard() {
        try? discardChecked()
    }

    /// Verification uses this checked boundary so a success report is never
    /// published while its extracted staging directory is known to remain.
    /// Best-effort callers retain ownership after failure, allowing `deinit`
    /// to make one final cleanup attempt.
    func discardChecked(
        removing removeItem: (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        }
    ) throws {
        guard ownsDirectory else { return }
        do {
            try removeItem(directoryURL)
        } catch {
            let cocoaError = error as NSError
            guard cocoaError.domain == NSCocoaErrorDomain,
                  cocoaError.code == NSFileNoSuchFileError else {
                throw error
            }
        }
        ownsDirectory = false
    }

    func commit(
        to destinationURL: URL,
        generalFileDestinationURL: URL? = nil,
        folderPresentationDestinationURL: URL? = nil
    ) throws {
        guard ownsDirectory else {
            throw PortableArchivePayloadError.alreadyFinished
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw PortableArchivePayloadError.destinationExists
        }
        if let generalFileDestinationURL {
            guard !FileManager.default.fileExists(atPath: generalFileDestinationURL.path) else {
                throw PortableArchivePayloadError.destinationExists
            }
        }
        if let folderPresentationDestinationURL {
            guard !FileManager.default.fileExists(
                atPath: folderPresentationDestinationURL.path
            ) else {
                throw PortableArchivePayloadError.destinationExists
            }
        }

        let hasSupplementalContent = catalog.entries.contains {
            $0.role == .supplementalManifest
        }
        let hasFolderManifest = catalog.entries.contains { $0.role == .folderManifest }
        guard hasSupplementalContent == (generalFileDestinationURL != nil),
              hasFolderManifest == (folderPresentationDestinationURL != nil) else {
            throw PortableArchivePayloadError.invalidCatalog
        }

        // Validation and installation are intentionally separate so the user
        // can choose a fresh local LowKey. Revalidate the private staging tree
        // at the ownership transition so authenticated catalog bytes cannot be
        // replaced, removed, linked, or supplemented between those phases.
        try validateForCommit()

        if let generalFileDestinationURL {
            let stagedGeneralFiles = directoryURL.appendingPathComponent(
                "supplemental",
                isDirectory: true
            )
            guard FileManager.default.fileExists(atPath: stagedGeneralFiles.path) else {
                throw PortableArchivePayloadError.missingEntry("supplemental/manifest.khm")
            }
            try FileManager.default.moveItem(
                at: stagedGeneralFiles,
                to: generalFileDestinationURL
            )
        }
        if let folderPresentationDestinationURL {
            let stagedFolderPresentation = directoryURL.appendingPathComponent(
                "folders",
                isDirectory: true
            )
            guard FileManager.default.fileExists(atPath: stagedFolderPresentation.path) else {
                throw PortableArchivePayloadError.missingEntry("folders/manifest.khm")
            }
            try FileManager.default.moveItem(
                at: stagedFolderPresentation,
                to: folderPresentationDestinationURL
            )
        }
        try FileManager.default.moveItem(at: directoryURL, to: destinationURL)
        ownsDirectory = false
    }

    private func validateForCommit() throws {
        try catalog.validate()
        let fileManager = FileManager.default
        let rootValues = try directoryURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else {
            throw PortableArchivePayloadError.invalidCatalog
        }

        var expectedRootNames = Set<String>()
        var expectedNestedNames: [String: Set<String>] = [:]
        for entry in catalog.entries {
            let components = entry.storageName.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            if components.count == 1 {
                expectedRootNames.insert(String(components[0]))
            } else {
                guard components.count == 2 else {
                    throw PortableArchivePayloadError.invalidEntry(entry.storageName)
                }
                let directoryName = String(components[0])
                expectedRootNames.insert(directoryName)
                expectedNestedNames[directoryName, default: []].insert(
                    String(components[1])
                )
            }
        }

        let rootItems = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ],
            options: []
        )
        guard Set(rootItems.map(\.lastPathComponent)) == expectedRootNames else {
            throw PortableArchivePayloadError.unexpectedPayloadData
        }

        for itemURL in rootItems {
            let values = try itemURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw PortableArchivePayloadError.invalidEntry(itemURL.lastPathComponent)
            }
            if let expectedNames = expectedNestedNames[itemURL.lastPathComponent] {
                guard !expectedNames.isEmpty,
                      values.isDirectory == true else {
                    throw PortableArchivePayloadError.invalidEntry(
                        itemURL.lastPathComponent
                    )
                }
            } else {
                guard values.isRegularFile == true else {
                    throw PortableArchivePayloadError.invalidEntry(itemURL.lastPathComponent)
                }
            }
        }

        for (directoryName, expectedNames) in expectedNestedNames {
            let nestedURL = directoryURL.appendingPathComponent(
                directoryName,
                isDirectory: true
            )
            let nestedItems = try fileManager.contentsOfDirectory(
                at: nestedURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: []
            )
            guard Set(nestedItems.map(\.lastPathComponent)) == expectedNames else {
                throw PortableArchivePayloadError.unexpectedPayloadData
            }
            for itemURL in nestedItems {
                let values = try itemURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true else {
                    throw PortableArchivePayloadError.invalidEntry(itemURL.lastPathComponent)
                }
            }
        }

        for entry in catalog.entries {
            try Task.checkCancellation()
            let entryURL = directoryURL.appendingPathComponent(
                entry.storageName,
                isDirectory: false
            )
            let values = try entryURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let fileSize = values.fileSize,
                  fileSize >= 0,
                  UInt64(fileSize) == entry.ciphertextByteCount else {
                throw PortableArchivePayloadError.invalidEntry(entry.storageName)
            }
            let digest = try PortableArchivePayloadSource.hashFile(
                entryURL,
                expectedByteCount: entry.ciphertextByteCount,
                storageName: entry.storageName
            )
            guard digest == entry.ciphertextSHA256 else {
                throw PortableArchivePayloadError.digestMismatch(entry.storageName)
            }
        }
    }
}

final class PortableArchivePayloadExtractor {
    private let stagingURL: URL
    private var buffer = Data()
    private var expectedCatalogByteCount: Int?
    private var catalog: PortableArchivePayloadCatalog?
    private var currentEntryIndex = 0
    private var currentEntryRemainingByteCount: UInt64 = 0
    private var currentEntryWrittenByteCount: UInt64 = 0
    private var currentEntryHasher = SHA256()
    private var currentEntryHandle: FileHandle?
    private var isComplete = false
    private var isFinished = false
    private var relinquishedStagingDirectory = false

    init(stagingURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: stagingURL.path) else {
            throw PortableArchivePayloadError.destinationExists
        }
        self.stagingURL = stagingURL
    }

    deinit {
        try? discardChecked()
    }

    /// Removes a partially extracted payload and reports failure so callers
    /// can fail closed instead of losing the only cleanup signal. Ownership is
    /// retained after a failed removal, allowing a later retry or `deinit`.
    func discardChecked(
        removing removeItem: (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        }
    ) throws {
        guard !relinquishedStagingDirectory else { return }
        isFinished = true
        try? currentEntryHandle?.close()
        currentEntryHandle = nil
        buffer.removeAll(keepingCapacity: false)
        do {
            try removeItem(stagingURL)
        } catch {
            let cocoaError = error as NSError
            guard cocoaError.domain == NSCocoaErrorDomain,
                  cocoaError.code == NSFileNoSuchFileError else {
                throw error
            }
        }
        relinquishedStagingDirectory = true
    }

    func receive(_ data: Data) throws {
        guard !isFinished else {
            throw PortableArchivePayloadError.alreadyFinished
        }
        guard !isComplete || data.isEmpty else {
            failAndCleanUp()
            throw PortableArchivePayloadError.unexpectedPayloadData
        }
        guard !data.isEmpty else { return }

        buffer.append(data)
        do {
            try processAvailableBytes()
        } catch {
            failAndCleanUp()
            throw error
        }
    }

    func finish() throws -> PortableArchiveStagedPayload {
        guard !isFinished else {
            throw PortableArchivePayloadError.alreadyFinished
        }
        isFinished = true

        guard isComplete,
              buffer.isEmpty,
              currentEntryHandle == nil,
              let catalog else {
            failAndCleanUp()
            throw PortableArchivePayloadError.truncatedPayload
        }

        relinquishedStagingDirectory = true
        return PortableArchiveStagedPayload(directoryURL: stagingURL, catalog: catalog)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        failAndCleanUp()
    }

    private func processAvailableBytes() throws {
        if expectedCatalogByteCount == nil {
            guard buffer.count >= PortableArchivePayloadFormat.prefixByteCount else { return }
            let prefix = Data(buffer.prefix(PortableArchivePayloadFormat.prefixByteCount))
            guard prefix.prefix(PortableArchivePayloadFormat.magic.count)
                == PortableArchivePayloadFormat.magic else {
                throw PortableArchivePayloadError.invalidMagic
            }

            let versionRange = 8..<12
            let lengthRange = 12..<16
            let version = decodePayloadUInt32(Data(prefix[versionRange]))
            guard version == PortableArchivePayloadFormat.currentVersion else {
                throw PortableArchivePayloadError.unsupportedVersion
            }
            let catalogByteCount = Int(decodePayloadUInt32(Data(prefix[lengthRange])))
            guard catalogByteCount > 0,
                  catalogByteCount
                    <= PortableArchivePayloadFormat.legacyMaximumCatalogByteCount else {
                throw PortableArchivePayloadError.invalidCatalogLength
            }
            expectedCatalogByteCount = catalogByteCount
            buffer.removeFirst(PortableArchivePayloadFormat.prefixByteCount)
        }

        if catalog == nil {
            guard let expectedCatalogByteCount,
                  buffer.count >= expectedCatalogByteCount else { return }

            let encodedCatalog = Data(buffer.prefix(expectedCatalogByteCount))
            buffer.removeFirst(expectedCatalogByteCount)
            let decodedCatalog: PortableArchivePayloadCatalog
            do {
                decodedCatalog = try JSONDecoder().decode(
                    PortableArchivePayloadCatalog.self,
                    from: encodedCatalog
                )
            } catch {
                throw PortableArchivePayloadError.invalidCatalog
            }
            try decodedCatalog.validate(encodedCatalogByteCount: encodedCatalog.count)
            try createProtectedStagingDirectory()
            catalog = decodedCatalog
            try beginCurrentEntry()
        }

        while !isComplete, !buffer.isEmpty {
            try Task.checkCancellation()
            guard let catalog,
                  currentEntryIndex < catalog.entries.count,
                  let handle = currentEntryHandle else {
                throw PortableArchivePayloadError.invalidCatalog
            }

            let count = min(
                buffer.count,
                Int(min(currentEntryRemainingByteCount, UInt64(Int.max)))
            )
            guard count > 0 else {
                throw PortableArchivePayloadError.invalidCatalog
            }

            let data = Data(buffer.prefix(count))
            buffer.removeFirst(count)
            try handle.write(contentsOf: data)
            currentEntryHasher.update(data: data)
            currentEntryRemainingByteCount -= UInt64(count)
            currentEntryWrittenByteCount += UInt64(count)

            if currentEntryRemainingByteCount == 0 {
                try finishCurrentEntry()
            }
        }

        if isComplete, !buffer.isEmpty {
            throw PortableArchivePayloadError.unexpectedPayloadData
        }
    }

    private func createProtectedStagingDirectory() throws {
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = stagingURL
        try protectedURL.setResourceValues(values)
    }

    private func beginCurrentEntry() throws {
        guard let catalog else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        guard currentEntryIndex < catalog.entries.count else {
            isComplete = true
            return
        }

        let entry = catalog.entries[currentEntryIndex]
        let destinationURL = stagingURL.appendingPathComponent(
            entry.storageName,
            isDirectory: false
        )
        let parentURL = destinationURL.deletingLastPathComponent()
        if parentURL != stagingURL,
           !FileManager.default.fileExists(atPath: parentURL.path) {
            try FileManager.default.createDirectory(
                at: parentURL,
                withIntermediateDirectories: false,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedParentURL = parentURL
            try protectedParentURL.setResourceValues(values)
        }
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw PortableArchivePayloadError.invalidEntry(entry.storageName)
        }

        currentEntryHandle = try FileHandle(forWritingTo: destinationURL)
        currentEntryRemainingByteCount = entry.ciphertextByteCount
        currentEntryWrittenByteCount = 0
        currentEntryHasher = SHA256()
    }

    private func finishCurrentEntry() throws {
        guard let catalog,
              currentEntryIndex < catalog.entries.count,
              let handle = currentEntryHandle else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        let entry = catalog.entries[currentEntryIndex]
        try handle.synchronize()
        try handle.close()
        currentEntryHandle = nil

        guard currentEntryWrittenByteCount == entry.ciphertextByteCount,
              Data(currentEntryHasher.finalize()) == entry.ciphertextSHA256 else {
            throw PortableArchivePayloadError.digestMismatch(entry.storageName)
        }

        currentEntryIndex += 1
        try beginCurrentEntry()
    }

    private func failAndCleanUp() {
        try? discardChecked()
    }
}

private func decodePayloadUInt32(_ data: Data) -> UInt32 {
    precondition(data.count == 4)
    return data.enumerated().reduce(into: UInt32(0)) { result, element in
        result |= UInt32(element.element) << UInt32(element.offset * 8)
    }
}

private extension Data {
    mutating func appendPayloadLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
