import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowGeneralFileSupportAddOn
@testable import KeyHollowTransferCore
@testable import KeyHollowPhotoCore
@testable import KeyHollowVaultCore

final class PortableArchivePayloadTests: XCTestCase {
    func testLegacyPhotoOnlyCatalogRemainsSupported() throws {
        let legacy = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.legacyPhotoOnlyVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: Data(
                        repeating: 0x11,
                        count: PortableArchivePayloadFormat.sha256ByteCount
                    )
                )
            ]
        )

        XCTAssertNoThrow(try legacy.validate())
    }

    func testLegacyCatalogVersionsKeepShippedSizePolicyWhileV3RejectsIt() throws {
        let digest = Data(
            repeating: 0x11,
            count: PortableArchivePayloadFormat.sha256ByteCount
        )
        let legacySizedPhotoEntries = [
            PortableArchivePayloadEntry(
                storageName: "manifest.khm",
                role: .manifest,
                ciphertextByteCount: 28,
                ciphertextSHA256: digest
            ),
            PortableArchivePayloadEntry(
                storageName: "legacy.khp",
                role: .original,
                ciphertextByteCount:
                    PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .original) + 1,
                ciphertextSHA256: digest
            ),
            PortableArchivePayloadEntry(
                storageName: "legacy.kht",
                role: .thumbnail,
                ciphertextByteCount: 28,
                ciphertextSHA256: digest
            )
        ]

        XCTAssertNoThrow(
            try PortableArchivePayloadCatalog(
                version: PortableArchivePayloadCatalog.legacyPhotoOnlyVersion,
                entries: legacySizedPhotoEntries
            ).validate()
        )
        XCTAssertNoThrow(
            try PortableArchivePayloadCatalog(
                version: PortableArchivePayloadCatalog.legacyGeneralFileVersion,
                entries: legacySizedPhotoEntries
            ).validate()
        )
        XCTAssertThrowsError(
            try PortableArchivePayloadCatalog(
                version: PortableArchivePayloadCatalog.currentVersion,
                entries: legacySizedPhotoEntries
            ).validate()
        ) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidEntry("legacy.khp"))
        }

        let legacyGeneralFileEntries = [
            PortableArchivePayloadEntry(
                storageName: "manifest.khm",
                role: .manifest,
                ciphertextByteCount: 28,
                ciphertextSHA256: digest
            ),
            PortableArchivePayloadEntry(
                storageName: "supplemental/manifest.khm",
                role: .supplementalManifest,
                ciphertextByteCount: 28,
                ciphertextSHA256: digest
            ),
            PortableArchivePayloadEntry(
                storageName: "supplemental/legacy.khf",
                role: .supplementalBlob,
                ciphertextByteCount:
                    PortableArchivePayloadFormat.maximumCiphertextByteCount(
                        for: .supplementalBlob
                    ) + 1,
                ciphertextSHA256: digest
            )
        ]
        XCTAssertNoThrow(
            try PortableArchivePayloadCatalog(
                version: PortableArchivePayloadCatalog.legacyGeneralFileVersion,
                entries: legacyGeneralFileEntries
            ).validate()
        )
        XCTAssertThrowsError(
            try PortableArchivePayloadCatalog(
                version: PortableArchivePayloadCatalog.currentVersion,
                entries: legacyGeneralFileEntries
            ).validate()
        ) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .invalidEntry("supplemental/legacy.khf")
            )
        }
    }

    func testLegacyV2CatalogKeepsShippedCatalogEnvelopeWhileV3RejectsIt() throws {
        let entries = [entry(storageName: "manifest.khm", role: .manifest)]
        let legacyCatalog = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.legacyGeneralFileVersion,
            entries: entries
        )
        let currentCatalog = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: entries
        )
        let legacyOnlyCatalogSize = PortableArchivePayloadFormat.maximumCatalogByteCount + 1

        XCTAssertNoThrow(
            try legacyCatalog.validate(encodedCatalogByteCount: legacyOnlyCatalogSize)
        )
        XCTAssertThrowsError(
            try currentCatalog.validate(encodedCatalogByteCount: legacyOnlyCatalogSize)
        ) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalogLength)
        }
    }

    func testExporterUsesV3ForCurrentDataAndV2OnlyForLegacySizedData() throws {
        let currentEntries = [entry(storageName: "manifest.khm", role: .manifest)]
        XCTAssertEqual(
            try PortableArchivePayloadCatalog.forExport(entries: currentEntries).version,
            PortableArchivePayloadCatalog.currentVersion
        )

        let legacyEntries = [
            entry(storageName: "manifest.khm", role: .manifest),
            entry(
                storageName: "legacy.khp",
                role: .original,
                ciphertextByteCount:
                    PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .original) + 1
            ),
            entry(storageName: "legacy.kht", role: .thumbnail)
        ]
        XCTAssertEqual(
            try PortableArchivePayloadCatalog.forExport(entries: legacyEntries).version,
            PortableArchivePayloadCatalog.legacyGeneralFileVersion
        )
    }

    func testPayloadSourcePreservesLegacySizedLocalEntryWithV2Catalog() throws {
        let sourceRoot = temporaryURL(label: "legacy-sized-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )

        try minimumCiphertext().write(
            to: sourceRoot.appendingPathComponent("manifest.khm")
        )
        try minimumCiphertext().write(
            to: sourceRoot.appendingPathComponent("legacy.khp")
        )
        let legacyThumbnailByteCount = PortableArchivePayloadFormat
            .maximumCiphertextByteCount(for: .thumbnail) + 1
        try createSparseFile(
            at: sourceRoot.appendingPathComponent("legacy.kht"),
            byteCount: legacyThumbnailByteCount
        )
        let photo = VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            blobName: "legacy.khp",
            thumbnailName: "legacy.kht"
        )

        let source = try PortableArchivePayloadSource.create(
            rootURL: sourceRoot,
            manifest: VaultPhotoManifest(
                version: VaultPhotoManifest.currentVersion,
                photos: [photo]
            )
        )

        XCTAssertEqual(
            source.catalog.version,
            PortableArchivePayloadCatalog.legacyGeneralFileVersion
        )
        XCTAssertEqual(source.catalog.entries.count, 3)
        let thumbnailEntry = try XCTUnwrap(
            source.catalog.entries.first { $0.storageName == "legacy.kht" }
        )
        XCTAssertEqual(thumbnailEntry.role, .thumbnail)
        XCTAssertEqual(thumbnailEntry.ciphertextByteCount, legacyThumbnailByteCount)
    }

    func testLegacyV1AndV2PayloadsStillExtractEndToEnd() throws {
        let fixture = try preparedFixture()
        let ciphertext = Data(repeating: 0x41, count: 28)

        for version in [
            PortableArchivePayloadCatalog.legacyPhotoOnlyVersion,
            PortableArchivePayloadCatalog.legacyGeneralFileVersion
        ] {
            let archiveURL = temporaryURL(label: "legacy-v\(version)")
                .appendingPathExtension("khvault")
            let stagingURL = temporaryURL(label: "legacy-v\(version)-staging")
            defer {
                try? FileManager.default.removeItem(at: archiveURL)
                try? FileManager.default.removeItem(at: stagingURL)
            }
            let catalog = PortableArchivePayloadCatalog(
                version: version,
                entries: [
                    PortableArchivePayloadEntry(
                        storageName: "manifest.khm",
                        role: .manifest,
                        ciphertextByteCount: UInt64(ciphertext.count),
                        ciphertextSHA256: Data(SHA256.hash(data: ciphertext))
                    )
                ]
            )
            let writer = try PortableArchiveContainerWriter(
                destinationURL: archiveURL,
                preparedArchive: fixture.prepared
            )
            try writeRawPayload(catalog: catalog, fileBytes: ciphertext, to: writer)
            try writer.finish()

            let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
            let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)
            _ = try reader.streamAuthenticatedContent(
                credential: fixture.credential,
                keyDeriver: TestPayloadKeyDeriver()
            ) { chunk in
                try extractor.receive(chunk)
            }
            let staged = try extractor.finish()
            XCTAssertEqual(staged.catalog.version, version)
            XCTAssertEqual(
                try Data(contentsOf: stagingURL.appendingPathComponent("manifest.khm")),
                ciphertext
            )
            staged.discard()
        }
    }

    func testEncryptedVaultPayloadRoundTripsWithoutPlaintextMedia() async throws {
        let sourceRoot = temporaryURL(label: "source")
        let archiveURL = temporaryURL(label: "archive").appendingPathExtension("khvault")
        let stagingURL = temporaryURL(label: "staging")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: stagingURL)
        }

        let vaultID = UUID()
        let vaultKeyData = Data(repeating: 0x6d, count: 32)
        let vaultKey = SymmetricKey(data: vaultKeyData)
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: vaultKey,
            storageRoot: sourceRoot
        )
        let originalMarker = Data("KEYHOLLOW-NEVER-EXPORT-PLAINTEXT-ORIGINAL".utf8)
        let thumbnailMarker = Data("KEYHOLLOW-NEVER-EXPORT-PLAINTEXT-THUMBNAIL".utf8)
        _ = try await store.importPhoto(
            originalData: originalMarker,
            thumbnailData: thumbnailMarker
        )

        let manifest = try await store.loadManifest()
        let source = try PortableArchivePayloadSource.create(
            rootURL: sourceRoot,
            manifest: manifest
        )
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        let prepared = try EncryptedVaultArchiveHeader.prepare(
            vaultPayload: VaultPayload(
                vaultID: vaultID,
                vaultKey: vaultKeyData,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            credential: credential,
            keyDeriver: TestPayloadKeyDeriver()
        )

        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: prepared
        )
        try PortableArchivePayloadWriter.write(source: source, to: writer)
        try writer.finish()

        let archiveBytes = try Data(contentsOf: archiveURL)
        XCTAssertNil(archiveBytes.range(of: originalMarker))
        XCTAssertNil(archiveBytes.range(of: thumbnailMarker))
        for entry in source.catalog.entries {
            XCTAssertNil(archiveBytes.range(of: Data(entry.storageName.utf8)))
        }

        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)
        let secrets = try reader.streamAuthenticatedContent(
            credential: credential,
            keyDeriver: TestPayloadKeyDeriver()
        ) { chunk in
            try extractor.receive(chunk)
        }
        let staged = try extractor.finish()

        XCTAssertEqual(secrets.vaultKey, vaultKeyData)
        XCTAssertEqual(staged.catalog, source.catalog)
        for entry in source.catalog.entries {
            XCTAssertEqual(
                try Data(contentsOf: sourceRoot.appendingPathComponent(entry.storageName)),
                try Data(contentsOf: stagingURL.appendingPathComponent(entry.storageName))
            )
        }
        staged.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testCatalogRejectsTraversalAndDuplicateStorageNames() {
        let digest = Data(
            repeating: 0x11,
            count: PortableArchivePayloadFormat.sha256ByteCount
        )
        let traversal = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "../escape.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                )
            ]
        )
        XCTAssertThrowsError(try traversal.validate())

        let duplicate = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "same.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "same.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                )
            ]
        )
        XCTAssertThrowsError(try duplicate.validate()) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .duplicateEntry("same.khp")
            )
        }
    }

    func testCatalogRejectsEntryAndAggregateSizeExhaustion() {
        let digest = Data(
            repeating: 0x11,
            count: PortableArchivePayloadFormat.sha256ByteCount
        )
        let oversizedEntry = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: PortableArchivePayloadFormat.maximumEntryByteCount + 1,
                    ciphertextSHA256: digest
                )
            ]
        )

        XCTAssertThrowsError(try oversizedEntry.validate()) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .invalidEntry("manifest.khm")
            )
        }

        var excessiveTotalEntries = [
            PortableArchivePayloadEntry(
                storageName: "manifest.khm",
                role: .manifest,
                ciphertextByteCount: 28,
                ciphertextSHA256: digest
            ),
            PortableArchivePayloadEntry(
                storageName: "supplemental/manifest.khm",
                role: .supplementalManifest,
                ciphertextByteCount: 28,
                ciphertextSHA256: digest
            )
        ]
        excessiveTotalEntries.append(contentsOf: (0..<103).map { index in
            PortableArchivePayloadEntry(
                storageName: "supplemental/file-\(index).khf",
                role: .supplementalBlob,
                ciphertextByteCount: PortableArchivePayloadFormat.maximumEntryByteCount,
                ciphertextSHA256: digest
            )
        })
        let excessiveTotal = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: excessiveTotalEntries
        )

        XCTAssertThrowsError(try excessiveTotal.validate()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }
    }

    func testCatalogEnforcesRoleSpecificLimitsAndPhotoPairs() {
        let digest = Data(
            repeating: 0x11,
            count: PortableArchivePayloadFormat.sha256ByteCount
        )
        let oversizedThumbnail = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "photo.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "photo.kht",
                    role: .thumbnail,
                    ciphertextByteCount: PortableArchivePayloadFormat
                        .maximumCiphertextByteCount(for: .thumbnail) + 1,
                    ciphertextSHA256: digest
                )
            ]
        )
        XCTAssertThrowsError(try oversizedThumbnail.validate()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidEntry("photo.kht"))
        }

        let unpairedPhoto = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "orphan.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                )
            ]
        )
        XCTAssertThrowsError(try unpairedPhoto.validate()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }
    }

    func testCatalogAcceptsExactMaximumAndRejectsNextByteForEveryEntryRole() {
        let roles: [PortableArchivePayloadEntryRole] = [
            .manifest,
            .original,
            .thumbnail,
            .supplementalManifest,
            .supplementalBlob
        ]

        for role in roles {
            let maximum = PortableArchivePayloadFormat.maximumCiphertextByteCount(for: role)
            let exact = catalogTestingBoundary(for: role, ciphertextByteCount: maximum)
            XCTAssertNoThrow(
                try exact.catalog.validate(),
                "The exact \(role) ciphertext ceiling must remain valid"
            )

            let excessive = catalogTestingBoundary(
                for: role,
                ciphertextByteCount: maximum + 1
            )
            XCTAssertThrowsError(try excessive.catalog.validate()) { error in
                XCTAssertEqual(
                    error as? PortableArchivePayloadError,
                    .invalidEntry(excessive.testedStorageName),
                    "The \(role) ciphertext ceiling accepted one extra byte"
                )
            }
        }
    }

    func testCatalogRejectsCiphertextBelowAEADMinimumForEveryEntryRole() {
        let roles: [PortableArchivePayloadEntryRole] = [
            .manifest,
            .original,
            .thumbnail,
            .supplementalManifest,
            .supplementalBlob
        ]

        for role in roles {
            let undersized = catalogTestingBoundary(
                for: role,
                ciphertextByteCount: PortableArchivePayloadFormat.aeadOverheadByteCount - 1
            )
            XCTAssertThrowsError(try undersized.catalog.validate()) { error in
                XCTAssertEqual(
                    error as? PortableArchivePayloadError,
                    .invalidEntry(undersized.testedStorageName),
                    "The \(role) entry accepted ciphertext below the AES-GCM envelope minimum"
                )
            }
        }
    }

    func testArchiveLimitsStayAlignedWithEncryptedStoreLimits() {
        let overhead = PortableArchivePayloadFormat.aeadOverheadByteCount

        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumPhotoManifestByteCount,
            UInt64(VaultPhotoStore.maximumManifestByteCount)
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumPhotoOriginalByteCount,
            VaultPhotoStore.maximumOriginalByteCount
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumThumbnailByteCount,
            VaultPhotoStore.maximumThumbnailByteCount
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumPhotoCount,
            VaultPhotoStore.maximumPhotoCount
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumSupplementalManifestByteCount,
            UInt64(VaultGeneralFileStore.maximumManifestByteCount)
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumSupplementalBlobByteCount,
            VaultGeneralFileStore.maximumFileByteCount
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumSupplementalFileCount,
            VaultGeneralFileStore.maximumStoredFileCount
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .manifest),
            UInt64(VaultPhotoStore.maximumManifestByteCount) + overhead
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .original),
            VaultPhotoStore.maximumOriginalByteCount + overhead
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .thumbnail),
            VaultPhotoStore.maximumThumbnailByteCount + overhead
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .supplementalManifest),
            UInt64(VaultGeneralFileStore.maximumManifestByteCount) + overhead
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .supplementalBlob),
            VaultGeneralFileStore.maximumFileByteCount + overhead
        )
        XCTAssertEqual(
            PortableArchivePayloadFormat.maximumEntryByteCount,
            max(
                VaultPhotoStore.maximumOriginalByteCount,
                VaultGeneralFileStore.maximumFileByteCount
            ) + overhead
        )
    }

    func testCatalogAcceptsExactCountCeilingsAndRejectsEveryNextItem() {
        let maximumShape = catalog(
            photoCount: PortableArchivePayloadFormat.maximumPhotoCount,
            supplementalFileCount: PortableArchivePayloadFormat.maximumSupplementalFileCount
        )
        XCTAssertEqual(
            maximumShape.entries.count,
            PortableArchivePayloadFormat.maximumEntryCount
        )
        XCTAssertNoThrow(try maximumShape.validate())

        var excessiveEntryCount = maximumShape.entries
        excessiveEntryCount.append(
            entry(storageName: "supplemental/entry-overflow.khf", role: .supplementalBlob)
        )
        XCTAssertEqual(
            excessiveEntryCount.count,
            PortableArchivePayloadFormat.maximumEntryCount + 1
        )
        XCTAssertThrowsError(
            try PortableArchivePayloadCatalog(
                version: PortableArchivePayloadCatalog.currentVersion,
                entries: excessiveEntryCount
            ).validate()
        ) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }

        let excessivePhotos = catalog(
            photoCount: PortableArchivePayloadFormat.maximumPhotoCount + 1,
            supplementalFileCount: 0
        )
        XCTAssertLessThanOrEqual(
            excessivePhotos.entries.count,
            PortableArchivePayloadFormat.maximumEntryCount
        )
        XCTAssertThrowsError(try excessivePhotos.validate()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }

        let excessiveSupplementalFiles = catalog(
            photoCount: 0,
            supplementalFileCount: PortableArchivePayloadFormat.maximumSupplementalFileCount + 1
        )
        XCTAssertLessThanOrEqual(
            excessiveSupplementalFiles.entries.count,
            PortableArchivePayloadFormat.maximumEntryCount
        )
        XCTAssertThrowsError(try excessiveSupplementalFiles.validate()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }
    }

    func testCatalogAcceptsExactAggregateLimitAndRejectsNextByte() {
        let exact = supplementalCatalog(
            totalCiphertextByteCount: PortableArchivePayloadFormat.maximumTotalByteCount
        )
        XCTAssertNoThrow(try exact.validate())

        let excessive = supplementalCatalog(
            totalCiphertextByteCount: PortableArchivePayloadFormat.maximumTotalByteCount + 1
        )
        XCTAssertThrowsError(try excessive.validate()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }
    }

    func testPayloadSourceRejectsSymbolicLinkBeforeHashing() throws {
        let sourceRoot = temporaryURL(label: "symlink-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )

        let inaccessibleTarget = sourceRoot.appendingPathComponent("inaccessible-target")
        try Data(repeating: 0x41, count: Int(PortableArchivePayloadFormat.aeadOverheadByteCount))
            .write(to: inaccessibleTarget)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: inaccessibleTarget.path
        )
        let manifestLink = sourceRoot.appendingPathComponent("manifest.khm")
        try FileManager.default.createSymbolicLink(
            at: manifestLink,
            withDestinationURL: inaccessibleTarget
        )

        XCTAssertThrowsError(
            try PortableArchivePayloadSource.create(
                rootURL: sourceRoot,
                manifest: .empty
            )
        ) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .missingEntry("manifest.khm")
            )
        }
    }

    func testPayloadSourceRejectsSparseEntryBeyondLegacyEnvelopeBeforeHashing() throws {
        let sourceRoot = temporaryURL(label: "sparse-oversized-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )

        try minimumCiphertext().write(
            to: sourceRoot.appendingPathComponent("manifest.khm")
        )
        try minimumCiphertext().write(
            to: sourceRoot.appendingPathComponent("oversized.kht")
        )
        let oversizedURL = sourceRoot.appendingPathComponent("oversized.khp")
        try createSparseFile(
            at: oversizedURL,
            byteCount: PortableArchivePayloadFormat.legacyMaximumEntryByteCount + 1
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: oversizedURL.path
        )
        let photo = VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            blobName: "oversized.khp",
            thumbnailName: "oversized.kht"
        )

        XCTAssertThrowsError(
            try PortableArchivePayloadSource.create(
                rootURL: sourceRoot,
                manifest: VaultPhotoManifest(
                    version: VaultPhotoManifest.currentVersion,
                    photos: [photo]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .invalidEntry("oversized.khp")
            )
        }
    }

    func testArchiveTotalAccumulatorFailsClosedOnLimitAndOverflow() throws {
        XCTAssertEqual(
            try PortableArchivePayloadFormat.checkedTotalByteCount(
                adding: 1,
                to: PortableArchivePayloadFormat.maximumTotalByteCount - 1
            ),
            PortableArchivePayloadFormat.maximumTotalByteCount
        )
        XCTAssertThrowsError(
            try PortableArchivePayloadFormat.checkedTotalByteCount(
                adding: 1,
                to: PortableArchivePayloadFormat.maximumTotalByteCount
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }
        XCTAssertThrowsError(
            try PortableArchivePayloadFormat.checkedTotalByteCount(
                adding: UInt64.max,
                to: 1
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }
    }

    func testExtractorRejectsOversizedCatalogBeforeCreatingStagingDirectory() throws {
        let stagingURL = temporaryURL(label: "oversized-catalog-staging")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        var exactPrefix = PortableArchivePayloadFormat.magic
        exactPrefix.appendPayloadLittleEndianForTesting(
            PortableArchivePayloadFormat.currentVersion
        )
        exactPrefix.appendPayloadLittleEndianForTesting(
            UInt32(PortableArchivePayloadFormat.legacyMaximumCatalogByteCount)
        )
        let exactExtractor = try PortableArchivePayloadExtractor(
            stagingURL: temporaryURL(label: "exact-catalog-staging")
        )
        XCTAssertNoThrow(try exactExtractor.receive(exactPrefix))
        exactExtractor.cancel()

        var prefix = PortableArchivePayloadFormat.magic
        prefix.appendPayloadLittleEndianForTesting(PortableArchivePayloadFormat.currentVersion)
        prefix.appendPayloadLittleEndianForTesting(
            UInt32(PortableArchivePayloadFormat.legacyMaximumCatalogByteCount + 1)
        )
        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)

        XCTAssertThrowsError(try extractor.receive(prefix)) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalogLength)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testExtractorCheckedCleanupFailsClosedAndCanRetry() throws {
        let stagingURL = temporaryURL(label: "checked-extractor-cleanup")
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true
        )
        try Data("partially extracted ciphertext".utf8).write(
            to: stagingURL.appendingPathComponent("partial.khc")
        )

        XCTAssertThrowsError(
            try extractor.discardChecked(removing: { _ in
                throw CocoaError(.fileWriteUnknown)
            })
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))

        XCTAssertNoThrow(try extractor.discardChecked())
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        XCTAssertNoThrow(try extractor.discardChecked())
    }

    func testPayloadWriterDetectsSourceChangedAfterCatalogCreation() async throws {
        let sourceRoot = temporaryURL(label: "source-change")
        let archiveURL = temporaryURL(label: "source-change-archive")
            .appendingPathExtension("khvault")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: archiveURL)
        }

        let key = SymmetricKey(size: .bits256)
        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: key,
            storageRoot: sourceRoot
        )
        let record = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        let manifest = try await store.loadManifest()
        let source = try PortableArchivePayloadSource.create(
            rootURL: sourceRoot,
            manifest: manifest
        )

        let changedURL = sourceRoot.appendingPathComponent(record.blobName)
        var changed = try Data(contentsOf: changedURL)
        changed[changed.startIndex] ^= 0x01
        try changed.write(to: changedURL, options: .atomic)

        let fixture = try preparedFixture()
        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: fixture.prepared
        )
        XCTAssertThrowsError(
            try PortableArchivePayloadWriter.write(source: source, to: writer)
        ) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .sourceChanged(record.blobName)
            )
        }
        writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testDigestMismatchRemovesStagingDirectory() throws {
        let fixture = try preparedFixture()
        let archiveURL = temporaryURL(label: "bad-digest").appendingPathExtension("khvault")
        let stagingURL = temporaryURL(label: "bad-digest-staging")
        defer {
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: stagingURL)
        }

        let ciphertext = Data(repeating: 0x44, count: 28)
        let catalog = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: UInt64(ciphertext.count),
                    ciphertextSHA256: Data(
                        repeating: 0xff,
                        count: PortableArchivePayloadFormat.sha256ByteCount
                    )
                )
            ]
        )
        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: fixture.prepared
        )
        try writeRawPayload(catalog: catalog, fileBytes: ciphertext, to: writer)
        try writer.finish()

        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)
        XCTAssertThrowsError(
            try reader.streamAuthenticatedContent(
                credential: fixture.credential,
                keyDeriver: TestPayloadKeyDeriver()
            ) { chunk in
                try extractor.receive(chunk)
            }
        ) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .digestMismatch("manifest.khm")
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testTruncatedInnerPayloadCannotBecomeStagedVault() throws {
        let fixture = try preparedFixture()
        let archiveURL = temporaryURL(label: "truncated-inner").appendingPathExtension("khvault")
        let stagingURL = temporaryURL(label: "truncated-inner-staging")
        defer {
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: stagingURL)
        }

        let partialCiphertext = Data(repeating: 0x22, count: 28)
        let catalog = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 56,
                    ciphertextSHA256: Data(
                        repeating: 0x33,
                        count: PortableArchivePayloadFormat.sha256ByteCount
                    )
                )
            ]
        )
        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: fixture.prepared
        )
        try writeRawPayload(catalog: catalog, fileBytes: partialCiphertext, to: writer)
        try writer.finish()

        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)
        try reader.streamAuthenticatedContent(
            credential: fixture.credential,
            keyDeriver: TestPayloadKeyDeriver()
        ) { chunk in
            try extractor.receive(chunk)
        }
        XCTAssertThrowsError(try extractor.finish()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .truncatedPayload)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    private func writeRawPayload(
        catalog: PortableArchivePayloadCatalog,
        fileBytes: Data,
        to writer: PortableArchiveContainerWriter
    ) throws {
        let encodedCatalog = try JSONEncoder().encode(catalog)
        var prefix = PortableArchivePayloadFormat.magic
        prefix.appendPayloadLittleEndianForTesting(PortableArchivePayloadFormat.currentVersion)
        prefix.appendPayloadLittleEndianForTesting(UInt32(encodedCatalog.count))
        try writer.append(prefix)
        try writer.append(encodedCatalog)
        try writer.append(fileBytes)
    }

    private func catalogTestingBoundary(
        for role: PortableArchivePayloadEntryRole,
        ciphertextByteCount: UInt64
    ) -> (catalog: PortableArchivePayloadCatalog, testedStorageName: String) {
        let testedStorageName: String
        let entries: [PortableArchivePayloadEntry]

        switch role {
        case .manifest:
            testedStorageName = "manifest.khm"
            entries = [
                entry(
                    storageName: testedStorageName,
                    role: .manifest,
                    ciphertextByteCount: ciphertextByteCount
                )
            ]
        case .original:
            testedStorageName = "boundary.khp"
            entries = [
                entry(storageName: "manifest.khm", role: .manifest),
                entry(
                    storageName: testedStorageName,
                    role: .original,
                    ciphertextByteCount: ciphertextByteCount
                ),
                entry(storageName: "boundary.kht", role: .thumbnail)
            ]
        case .thumbnail:
            testedStorageName = "boundary.kht"
            entries = [
                entry(storageName: "manifest.khm", role: .manifest),
                entry(storageName: "boundary.khp", role: .original),
                entry(
                    storageName: testedStorageName,
                    role: .thumbnail,
                    ciphertextByteCount: ciphertextByteCount
                )
            ]
        case .supplementalManifest:
            testedStorageName = "supplemental/manifest.khm"
            entries = [
                entry(storageName: "manifest.khm", role: .manifest),
                entry(
                    storageName: testedStorageName,
                    role: .supplementalManifest,
                    ciphertextByteCount: ciphertextByteCount
                )
            ]
        case .supplementalBlob:
            testedStorageName = "supplemental/boundary.khf"
            entries = [
                entry(storageName: "manifest.khm", role: .manifest),
                entry(storageName: "supplemental/manifest.khm", role: .supplementalManifest),
                entry(
                    storageName: testedStorageName,
                    role: .supplementalBlob,
                    ciphertextByteCount: ciphertextByteCount
                )
            ]
        }

        return (
            PortableArchivePayloadCatalog(
                version: PortableArchivePayloadCatalog.currentVersion,
                entries: entries
            ),
            testedStorageName
        )
    }

    private func catalog(
        photoCount: Int,
        supplementalFileCount: Int
    ) -> PortableArchivePayloadCatalog {
        var entries = [entry(storageName: "manifest.khm", role: .manifest)]
        entries.reserveCapacity(1 + (photoCount * 2) + 1 + supplementalFileCount)

        for index in 0..<photoCount {
            entries.append(entry(storageName: "photo-\(index).khp", role: .original))
            entries.append(entry(storageName: "photo-\(index).kht", role: .thumbnail))
        }
        if supplementalFileCount > 0 {
            entries.append(
                entry(storageName: "supplemental/manifest.khm", role: .supplementalManifest)
            )
            for index in 0..<supplementalFileCount {
                entries.append(
                    entry(
                        storageName: "supplemental/file-\(index).khf",
                        role: .supplementalBlob
                    )
                )
            }
        }

        return PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: entries
        )
    }

    private func supplementalCatalog(
        totalCiphertextByteCount: UInt64
    ) -> PortableArchivePayloadCatalog {
        let fixedByteCount = PortableArchivePayloadFormat.aeadOverheadByteCount * 2
        precondition(totalCiphertextByteCount > fixedByteCount)
        var remaining = totalCiphertextByteCount - fixedByteCount
        var entries = [
            entry(storageName: "manifest.khm", role: .manifest),
            entry(storageName: "supplemental/manifest.khm", role: .supplementalManifest)
        ]
        var index = 0

        while remaining > 0 {
            let byteCount = min(
                remaining,
                PortableArchivePayloadFormat.maximumCiphertextByteCount(for: .supplementalBlob)
            )
            precondition(byteCount >= PortableArchivePayloadFormat.aeadOverheadByteCount)
            entries.append(
                entry(
                    storageName: "supplemental/aggregate-\(index).khf",
                    role: .supplementalBlob,
                    ciphertextByteCount: byteCount
                )
            )
            remaining -= byteCount
            index += 1
        }

        return PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: entries
        )
    }

    private func entry(
        storageName: String,
        role: PortableArchivePayloadEntryRole,
        ciphertextByteCount: UInt64 = PortableArchivePayloadFormat.aeadOverheadByteCount
    ) -> PortableArchivePayloadEntry {
        PortableArchivePayloadEntry(
            storageName: storageName,
            role: role,
            ciphertextByteCount: ciphertextByteCount,
            ciphertextSHA256: Data(
                repeating: 0x11,
                count: PortableArchivePayloadFormat.sha256ByteCount
            )
        )
    }

    private func minimumCiphertext() -> Data {
        Data(
            repeating: 0x22,
            count: Int(PortableArchivePayloadFormat.aeadOverheadByteCount)
        )
    }

    private func createSparseFile(at url: URL, byteCount: UInt64) throws {
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.truncate(atOffset: byteCount)
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func preparedFixture() throws -> (
        prepared: PreparedEncryptedVaultArchive,
        credential: PortableArchiveCredential
    ) {
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        let prepared = try EncryptedVaultArchiveHeader.prepare(
            vaultPayload: VaultPayload(
                vaultID: UUID(),
                vaultKey: Data(repeating: 0x51, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            credential: credential,
            keyDeriver: TestPayloadKeyDeriver()
        )
        return (prepared, credential)
    }

    private func temporaryURL(label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyHollow-\(label)-\(UUID().uuidString)")
    }
}

private struct TestPayloadKeyDeriver: PortableArchiveKeyDeriving {
    func deriveWrappingKey(
        credential: PortableArchiveCredential,
        parameters: PortableArchiveKDFParameters
    ) throws -> SymmetricKey {
        try parameters.validate()
        var input = try credential.keyMaterial()
        input.append(parameters.salt)
        return SymmetricKey(data: SHA256.hash(data: input))
    }
}

private extension Data {
    mutating func appendPayloadLittleEndianForTesting<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}

