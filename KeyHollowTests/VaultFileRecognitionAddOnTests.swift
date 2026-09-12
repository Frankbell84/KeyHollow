import Foundation
import XCTest
import KeyHollowFileRecognitionAddOn
import UIKit

final class VaultFileRecognitionAddOnTests: XCTestCase {
    private let recognizer = KHVaultFileRecognizer()

    func testIngressCopiesRecognizedFileWhileSourceRemainsUntouched() throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VaultFileIngressTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("Family Backup.khvault")
        let original = Data("authenticated encrypted test container".utf8)
        try original.write(to: sourceURL, options: .atomic)

        let staged = try XCTUnwrap(KHVaultFileIngress().stageIfRecognized(sourceURL))
        defer { staged.discard() }

        XCTAssertEqual(staged.displayName, sourceURL.lastPathComponent)
        XCTAssertEqual(staged.byteCount, UInt64(original.count))
        XCTAssertNotEqual(staged.url, sourceURL)
        XCTAssertEqual(try Data(contentsOf: staged.url), original)
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        let stagedValues = try staged.url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        XCTAssertEqual(stagedValues.isRegularFile, true)
        XCTAssertNotEqual(stagedValues.isSymbolicLink, true)
        XCTAssertEqual(stagedValues.fileSize, original.count)
    }

    func testIngressReportsMonotonicByteProgressThroughCompletion() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Progress-\(UUID().uuidString).khvault"
        )
        let original = Data(repeating: 0xA5, count: 2_500_000)
        try original.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let recorder = IngressProgressRecorder()
        let staged = try XCTUnwrap(
            KHVaultFileIngress().stageIfRecognized(sourceURL) { progress in
                recorder.append(progress)
            }
        )
        defer { staged.discard() }

        let updates = recorder.values
        XCTAssertGreaterThan(updates.count, 2)
        XCTAssertEqual(updates.first?.completedByteCount, 0)
        XCTAssertEqual(updates.last?.completedByteCount, UInt64(original.count))
        XCTAssertTrue(updates.allSatisfy { $0.totalByteCount == UInt64(original.count) })
        XCTAssertEqual(
            updates.map(\.completedByteCount),
            updates.map(\.completedByteCount).sorted()
        )
        XCTAssertEqual(try Data(contentsOf: staged.url), original)
    }

    func testCheckedDiscardFailsClosedAndCanRetry() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Checked-Discard-\(UUID().uuidString).khvault"
        )
        try Data("authenticated encrypted test container".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let staged = try XCTUnwrap(
            KHVaultFileIngress().stageIfRecognized(sourceURL)
        )
        XCTAssertThrowsError(
            try staged.discardChecked(using: FailingRemovalFileManager())
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.url.path))

        XCTAssertNoThrow(try staged.discardChecked())
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path))
        XCTAssertNoThrow(try staged.discardChecked())
    }

    func testReleasingLastStagedValueRemovesIngressCopy() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Lease-Release-\(UUID().uuidString).khvault"
        )
        try Data("authenticated encrypted test container".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        var staged: StagedVaultFile? = try XCTUnwrap(
            KHVaultFileIngress().stageIfRecognized(sourceURL)
        )
        let stagedURL = try XCTUnwrap(staged?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))

        staged = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testNextIngressRemovesOnlyCanonicalAbandonedCopies() throws {
        let stagingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowPortableImports",
            isDirectory: true
        )
        let abandonedRoot = stagingRoot.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: true
        )
        let unrelatedRoot = stagingRoot.appendingPathComponent(
            "unrelated-test-fixture",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: abandonedRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: unrelatedRoot,
            withIntermediateDirectories: true
        )
        try Data("stale encrypted copy".utf8).write(
            to: abandonedRoot.appendingPathComponent("Selected.khvault")
        )
        defer {
            try? FileManager.default.removeItem(at: abandonedRoot)
            try? FileManager.default.removeItem(at: unrelatedRoot)
        }

        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Abandoned-Recovery-\(UUID().uuidString).khvault"
        )
        try Data("replacement encrypted test container".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let staged = try XCTUnwrap(
            KHVaultFileIngress().stageIfRecognized(sourceURL)
        )
        defer { staged.discard() }

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedRoot.path))
    }

    func testSecondIngressPreservesEveryLiveLease() throws {
        let firstSource = FileManager.default.temporaryDirectory.appendingPathComponent(
            "First-Live-\(UUID().uuidString).khvault"
        )
        let secondSource = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Second-Live-\(UUID().uuidString).khvault"
        )
        try Data("first encrypted test container".utf8).write(to: firstSource)
        try Data("second encrypted test container".utf8).write(to: secondSource)
        defer {
            try? FileManager.default.removeItem(at: firstSource)
            try? FileManager.default.removeItem(at: secondSource)
        }

        let ingress = KHVaultFileIngress()
        let first = try XCTUnwrap(ingress.stageIfRecognized(firstSource))
        defer { first.discard() }
        let second = try XCTUnwrap(ingress.stageIfRecognized(secondSource))
        defer { second.discard() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
    }

    func testStagedValueCopiesRetainOneCleanupLeaseUntilFinalRelease() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Shared-Lease-\(UUID().uuidString).khvault"
        )
        try Data("authenticated encrypted test container".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        var first: StagedVaultFile? = try XCTUnwrap(
            KHVaultFileIngress().stageIfRecognized(sourceURL)
        )
        var second = first
        let stagedURL = try XCTUnwrap(first?.url)

        first = nil
        withExtendedLifetime(second) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        }

        second = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testCheckedDiscardTreatsOutOfBandRemovalAsSuccess() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Out-Of-Band-Removal-\(UUID().uuidString).khvault"
        )
        try Data("authenticated encrypted test container".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let staged = try XCTUnwrap(
            KHVaultFileIngress().stageIfRecognized(sourceURL)
        )
        try FileManager.default.removeItem(at: staged.url.deletingLastPathComponent())

        XCTAssertNoThrow(try staged.discardChecked())
        XCTAssertNoThrow(try staged.discardChecked())
    }

    func testCrashRecoveryPreservesCanonicalNamedNonDirectories() throws {
        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "KeyHollowPortableImports",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )

        let abandonedDirectory = stagingRoot.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: true
        )
        let canonicalFile = stagingRoot.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: false
        )
        let canonicalLink = stagingRoot.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: false
        )
        let externalTarget = fileManager.temporaryDirectory.appendingPathComponent(
            "Ingress-Link-Target-\(UUID().uuidString)"
        )
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent(
            "Crash-Recovery-\(UUID().uuidString).khvault"
        )
        try fileManager.createDirectory(
            at: abandonedDirectory,
            withIntermediateDirectories: false
        )
        let fileContents = Data("canonical regular file".utf8)
        let targetContents = Data("external link target".utf8)
        try fileContents.write(to: canonicalFile)
        try targetContents.write(to: externalTarget)
        try fileManager.createSymbolicLink(
            at: canonicalLink,
            withDestinationURL: externalTarget
        )
        try Data("replacement encrypted test container".utf8).write(to: sourceURL)
        defer {
            try? fileManager.removeItem(at: abandonedDirectory)
            try? fileManager.removeItem(at: canonicalFile)
            try? fileManager.removeItem(at: canonicalLink)
            try? fileManager.removeItem(at: externalTarget)
            try? fileManager.removeItem(at: sourceURL)
        }

        let staged = try XCTUnwrap(
            KHVaultFileIngress().stageIfRecognized(sourceURL)
        )
        defer { staged.discard() }

        XCTAssertFalse(fileManager.fileExists(atPath: abandonedDirectory.path))
        XCTAssertEqual(try Data(contentsOf: canonicalFile), fileContents)
        XCTAssertEqual(try Data(contentsOf: externalTarget), targetContents)
        let linkValues = try canonicalLink.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(linkValues.isSymbolicLink, true)
    }

    func testIngressRejectsEmptyVaultFile() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Empty-\(UUID().uuidString).khvault"
        )
        _ = FileManager.default.createFile(atPath: sourceURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        XCTAssertThrowsError(try KHVaultFileIngress().stageIfRecognized(sourceURL)) { error in
            XCTAssertEqual(error as? VaultFileIngressError, .unsupportedFile)
        }
    }

    func testIngressRejectsDirectoryWithVaultExtension() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Directory-\(UUID().uuidString).khvault",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceURL,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        XCTAssertThrowsError(try KHVaultFileIngress().stageIfRecognized(sourceURL)) { error in
            XCTAssertEqual(error as? VaultFileIngressError, .unsupportedFile)
        }
    }

    func testIngressRejectsSymbolicLinkWithVaultExtension() throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VaultFileIngressSymlinkTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let target = sourceRoot.appendingPathComponent("target.khvault")
        let symbolicLink = sourceRoot.appendingPathComponent("linked.khvault")
        try Data("encrypted target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: symbolicLink,
            withDestinationURL: target
        )

        XCTAssertThrowsError(try KHVaultFileIngress().stageIfRecognized(symbolicLink)) { error in
            XCTAssertEqual(error as? VaultFileIngressError, .unsupportedFile)
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("encrypted target".utf8))
    }

    func testIngressIgnoresUnrelatedFileWithoutCreatingAStagedCopy() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "NotAVault-\(UUID().uuidString).zip"
        )

        XCTAssertNil(try KHVaultFileIngress().stageIfRecognized(sourceURL))
    }

    func testRecognizesKHVaultFileURL() {
        let url = URL(fileURLWithPath: "/tmp/Family Backup.khvault")

        XCTAssertEqual(recognizer.recognize(url), RecognizedVaultFile(url: url))
    }

    func testRecognizesExtensionCaseInsensitively() {
        let url = URL(fileURLWithPath: "/tmp/Backup.KHVAULT")

        XCTAssertEqual(recognizer.recognize(url)?.url, url)
    }

    func testRejectsUnrelatedFileType() {
        let url = URL(fileURLWithPath: "/tmp/Backup.zip")

        XCTAssertNil(recognizer.recognize(url))
    }

    func testRejectsRemoteURL() {
        let url = URL(string: "https://example.com/Backup.khvault")!

        XCTAssertNil(recognizer.recognize(url))
    }

    func testRejectsFilenameThatOnlyContainsKHVaultText() {
        let url = URL(fileURLWithPath: "/tmp/Backup.khvault.txt")

        XCTAssertNil(recognizer.recognize(url))
    }

    func testApplicationDeclaresKHVaultDocumentHandler() throws {
        let documentTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes")
                as? [[String: Any]]
        )
        let keyHollowType = try XCTUnwrap(documentTypes.first { declaration in
            (declaration["LSItemContentTypes"] as? [String])?
                .contains("com.keyhollow.encrypted-vault") == true
        })

        XCTAssertEqual(keyHollowType["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(keyHollowType["LSHandlerRank"] as? String, "Owner")
        XCTAssertNil(keyHollowType["CFBundleTypeIconFiles"])
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool,
            true
        )
    }

    func testDocumentHandlerUsesTheExportedKHVaultType() throws {
        let exportedTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations")
                as? [[String: Any]]
        )
        let exportedType = try XCTUnwrap(exportedTypes.first { declaration in
            declaration["UTTypeIdentifier"] as? String ==
                "com.keyhollow.encrypted-vault"
        })
        let conformances = try XCTUnwrap(exportedType["UTTypeConformsTo"] as? [String])
        let tags = try XCTUnwrap(exportedType["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try XCTUnwrap(tags["public.filename-extension"] as? [String])
        XCTAssertNil(exportedType["UTTypeIcons"])
        XCTAssertTrue(conformances.contains("public.content"))
        XCTAssertTrue(conformances.contains("public.data"))
        XCTAssertEqual(extensions, ["khvault"])
    }
    func testDedicatedThumbnailExtensionIsEmbeddedAndNarrowlyRegistered() throws {
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let extensionURL = plugInsURL.appendingPathComponent(
            "KeyHollowVaultThumbnail.appex",
            isDirectory: true
        )
        let extensionBundle = try XCTUnwrap(Bundle(url: extensionURL))
        let extensionDeclaration = try XCTUnwrap(
            extensionBundle.object(forInfoDictionaryKey: "NSExtension")
                as? [String: Any]
        )
        let attributes = try XCTUnwrap(
            extensionDeclaration["NSExtensionAttributes"] as? [String: Any]
        )

        XCTAssertEqual(
            extensionDeclaration["NSExtensionPointIdentifier"] as? String,
            "com.apple.quicklook.thumbnail"
        )
        XCTAssertEqual(
            attributes["QLSupportedContentTypes"] as? [String],
            ["com.keyhollow.encrypted-vault"]
        )
        XCTAssertEqual(attributes["QLThumbnailMinimumDimension"] as? Int, 1)
        XCTAssertNotNil(
            UIImage(
                named: "KeyHollowVaultIcon",
                in: extensionBundle,
                compatibleWith: nil
            ),
            "The packaged thumbnail extension must expose the approved icon asset"
        )
    }
}

private final class IngressProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [VaultFileIngressProgress] = []

    var values: [VaultFileIngressProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: VaultFileIngressProgress) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}

private final class FailingRemovalFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}
