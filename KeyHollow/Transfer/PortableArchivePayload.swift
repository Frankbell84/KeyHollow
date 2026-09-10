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
    static let maximumEntryCount = 2 + (maximumPhotoCount * 2) + maximumSupplementalFileCount
    static let aeadOverheadByteCount: UInt64 = 28
    static let maximumPhotoManifestByteCount: UInt64 = 16 * 1_024 * 1_024
    static let maximumSupplementalManifestByteCount: UInt64 = 8 * 1_024 * 1_024
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

    let version: Int
    let entries: [PortableArchivePayloadEntry]

    func validate(encodedCatalogByteCount: Int? = nil) throws {
        let usesCurrentLimits = version >= Self.currentVersion
        let maximumEntryCount = usesCurrentLimits
            ? PortableArchivePayloadFormat.maximumEntryCount
            : PortableArchivePayloadFormat.legacyMaximumEntryCount
        let maximumTotalByteCount = usesCurrentLimits
            ? PortableArchivePayloadFormat.maximumTotalByteCount
            : PortableArchivePayloadFormat.legacyMaximumTotalByteCount
        guard (Self.legacyPhotoOnlyVersion...Self.currentVersion).contains(version),
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
            }
        }

        guard manifestCount == 1,
              entries.first?.role == .manifest,
              entries.first?.storageName == "manifest.khm",
              supplementalManifestCount <= 1,
              supplementalBlobCount == 0 || supplementalManifestCount == 1,
              version >= Self.legacyGeneralFileVersion
                || (supplementalManifestCount == 0 && supplementalBlobCount == 0) else {
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
        let current = PortableArchivePayloadCatalog(
            version: Self.currentVersion,
            entries: entries
        )
        if let encoded = try? JSONEncoder().encode(current),
           encoded.count <= PortableArchivePayloadFormat.maximumCatalogByteCount,
           (try? current.validate(encodedCatalogByteCount: encoded.count)) != nil {
            return current
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

    public init(
        manifestURL: URL?,
        entries: [PortableVaultSupplementalArchiveEntry],
        itemCount: Int
    ) {
        self.manifestURL = manifestURL
        self.entries = entries
        self.itemCount = itemCount
    }

    public static let empty = PortableVaultSupplementalArchiveInventory(
        manifestURL: nil,
        entries: [],
        itemCount: 0
    )
}

struct PortableArchivePayloadSource: Sendable {
    let catalog: PortableArchivePayloadCatalog
    private let sourceURLsByStorageName: [String: URL]

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
                rootURL.appendingPathComponent(entry.0, isDirectory: false)
            )
        })
    }

    static func create(
        photoRootURL: URL,
        photoManifest: VaultPhotoManifest,
        supplementalInventory: PortableVaultSupplementalArchiveInventory
    ) throws -> PortableArchivePayloadSource {
        guard photoManifest.version == VaultPhotoManifest.currentVersion,
              supplementalInventory.itemCount >= 0 else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        try validateSourceRoot(photoRootURL)

        var requestedEntries: [(String, PortableArchivePayloadEntryRole, URL)] = [
            (
                "manifest.khm",
                .manifest,
                photoRootURL.appendingPathComponent("manifest.khm", isDirectory: false)
            )
        ]
        for photo in photoManifest.photos {
            requestedEntries.append((
                photo.blobName,
                .original,
                photoRootURL.appendingPathComponent(photo.blobName, isDirectory: false)
            ))
            requestedEntries.append((
                photo.thumbnailName,
                .thumbnail,
                photoRootURL.appendingPathComponent(photo.thumbnailName, isDirectory: false)
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
            requestedEntries.append(("supplemental/manifest.khm", .supplementalManifest, manifestURL))
            for entry in supplementalInventory.entries {
                requestedEntries.append((
                    "supplemental/\(entry.storageName)",
                    .supplementalBlob,
                    entry.sourceURL
                ))
            }
        }
        return try create(requestedEntries)
    }

    private static func create(
        _ requestedEntries: [(String, PortableArchivePayloadEntryRole, URL)]
    ) throws -> PortableArchivePayloadSource {
        guard !requestedEntries.isEmpty,
              requestedEntries.count
                <= PortableArchivePayloadFormat.legacyMaximumEntryCount else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        var entries: [PortableArchivePayloadEntry] = []
        var sourceURLsByStorageName: [String: URL] = [:]
        var totalByteCount: UInt64 = 0
        entries.reserveCapacity(requestedEntries.count)
        for (storageName, role, fileURL) in requestedEntries {
            try PortableArchivePayloadCatalog.validateStorageName(storageName, role: role)
            let properties = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard properties.isRegularFile == true,
                  properties.isSymbolicLink != true,
                  let fileSize = properties.fileSize,
                  fileSize >= 28 else {
                throw PortableArchivePayloadError.missingEntry(storageName)
            }
            guard UInt64(fileSize)
                    <= PortableArchivePayloadFormat.legacyMaximumEntryByteCount else {
                throw PortableArchivePayloadError.invalidEntry(storageName)
            }

            // Reject an oversized local source set before spending I/O hashing
            // the entry that would cross the archive-wide ceiling.
            totalByteCount = try PortableArchivePayloadFormat.checkedTotalByteCount(
                adding: UInt64(fileSize),
                to: totalByteCount,
                maximum: PortableArchivePayloadFormat.legacyMaximumTotalByteCount
            )

            let digest = try Self.hashFile(
                fileURL,
                expectedByteCount: UInt64(fileSize),
                storageName: storageName
            )
            entries.append(
                PortableArchivePayloadEntry(
                    storageName: storageName,
                    role: role,
                    ciphertextByteCount: UInt64(fileSize),
                    ciphertextSHA256: digest
                )
            )
            guard sourceURLsByStorageName.updateValue(fileURL, forKey: storageName) == nil else {
                throw PortableArchivePayloadError.duplicateEntry(storageName)
            }
        }

        let catalog = try PortableArchivePayloadCatalog.forExport(entries: entries)
        return PortableArchivePayloadSource(
            catalog: catalog,
            sourceURLsByStorageName: sourceURLsByStorageName
        )
    }

    fileprivate func sourceURL(for storageName: String) throws -> URL {
        guard let url = sourceURLsByStorageName[storageName] else {
            throw PortableArchivePayloadError.missingEntry(storageName)
        }
        return url
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
            let fileURL = try source.sourceURL(for: entry.storageName)
            let handle = try FileHandle(forReadingFrom: fileURL)
            var hasher = SHA256()
            var writtenByteCount: UInt64 = 0

            do {
                while let data = try handle.read(
                    upToCount: PortableArchivePayloadFormat.fileReadByteCount
                ), !data.isEmpty {
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
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            guard writtenByteCount == entry.ciphertextByteCount,
                  Data(hasher.finalize()) == entry.ciphertextSHA256 else {
                throw PortableArchivePayloadError.sourceChanged(entry.storageName)
            }
        }
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
        guard ownsDirectory else { return }
        try? FileManager.default.removeItem(at: directoryURL)
        ownsDirectory = false
    }

    func commit(
        to destinationURL: URL,
        generalFileDestinationURL: URL? = nil
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
        var expectedSupplementalNames = Set<String>()
        for entry in catalog.entries {
            let components = entry.storageName.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            if components.count == 1 {
                expectedRootNames.insert(String(components[0]))
            } else {
                expectedRootNames.insert(String(components[0]))
                expectedSupplementalNames.insert(String(components[1]))
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
            if itemURL.lastPathComponent == "supplemental" {
                guard !expectedSupplementalNames.isEmpty,
                      values.isDirectory == true else {
                    throw PortableArchivePayloadError.invalidEntry("supplemental")
                }
            } else {
                guard values.isRegularFile == true else {
                    throw PortableArchivePayloadError.invalidEntry(itemURL.lastPathComponent)
                }
            }
        }

        if !expectedSupplementalNames.isEmpty {
            let supplementalURL = directoryURL.appendingPathComponent(
                "supplemental",
                isDirectory: true
            )
            let supplementalItems = try fileManager.contentsOfDirectory(
                at: supplementalURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: []
            )
            guard Set(supplementalItems.map(\.lastPathComponent))
                    == expectedSupplementalNames else {
                throw PortableArchivePayloadError.unexpectedPayloadData
            }
            for itemURL in supplementalItems {
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
        try? currentEntryHandle?.close()
        if !relinquishedStagingDirectory {
            try? FileManager.default.removeItem(at: stagingURL)
        }
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
        isFinished = true
        try? currentEntryHandle?.close()
        currentEntryHandle = nil
        buffer.removeAll(keepingCapacity: false)
        try? FileManager.default.removeItem(at: stagingURL)
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
