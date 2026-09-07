import CryptoKit
import Foundation
import XCTest
import KeyHollowCryptoCore
import KeyHollowGeneralFileSupportAddOn
@testable import KeyHollow

@MainActor
final class VaultVideoPlaybackCoordinatorTests: XCTestCase {
    func testPreparedVideoUsesAuthenticatedTemporaryFileAndDismissRemovesIt() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.MOV")
        let coordinator = VaultVideoPlaybackCoordinator()

        try await coordinator.prepare(record, using: fixture.store)

        let playbackURL = try XCTUnwrap(coordinator.active?.playback.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playbackURL.path))
        XCTAssertEqual(coordinator.active?.source, record)

        await coordinator.dismissAndWait()

        XCTAssertNil(coordinator.active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playbackURL.path))
    }

    func testUnsupportedPreparedFileIsRemovedOnValidationFailure() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.pdf")
        let coordinator = VaultVideoPlaybackCoordinator()

        do {
            try await coordinator.prepare(record, using: fixture.store)
            XCTFail("Expected a non-video record to be rejected")
        } catch {
            XCTAssertNil(coordinator.active)
        }

        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testCancelledPreparationLeavesNoPlaintextOrActivePlayback() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.mp4")
        let coordinator = VaultVideoPlaybackCoordinator()
        let task = Task { @MainActor in
            try await coordinator.prepare(record, using: fixture.store)
        }

        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertNil(coordinator.active)
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testRepeatedDismissalIsIdempotent() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Evidence.m4v")
        let coordinator = VaultVideoPlaybackCoordinator()

        try await coordinator.prepare(record, using: fixture.store)
        await coordinator.dismissAndWait()
        await coordinator.dismissAndWait()

        XCTAssertNil(coordinator.active)
        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }

    func testFailedVideoThumbnailDecodeRemovesPreparedPlaintext() async throws {
        let fixture = try VideoPlaybackFixture()
        defer { fixture.cleanup() }
        let record = try await fixture.importFile(named: "Malformed.mp4")
        let coordinator = VaultVideoThumbnailCoordinator()

        do {
            _ = try await coordinator.render(record, using: fixture.store)
            XCTFail("Expected malformed media to fail thumbnail decoding")
        } catch {
            // AVFoundation owns the concrete malformed-media error.
        }

        XCTAssertTrue(fixture.preparedPlaintextFiles().isEmpty)
    }
}

private struct VideoPlaybackFixture {
    let root: URL
    let sourceRoot: URL
    let temporaryRoot: URL
    let store: VaultGeneralFileStore

    init() throws {
        let vaultID = UUID()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VideoPlaybackCoordinatorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        temporaryRoot = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        store = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: VideoPlaybackTestAccess(vaultID: vaultID),
            storageRoot: root.appendingPathComponent("Store", isDirectory: true),
            temporaryRoot: temporaryRoot
        )
    }

    func importFile(named name: String) async throws -> VaultGeneralFileRecord {
        let sourceURL = sourceRoot.appendingPathComponent(name)
        try Data(repeating: 0x2a, count: 1_024).write(to: sourceURL, options: .atomic)
        return try await store.importFile(at: sourceURL)
    }

    func preparedPlaintextFiles() -> [URL] {
        let exportRoot = temporaryRoot.appendingPathComponent(
            "KeyHollowGeneralFileExports",
            isDirectory: true
        )
        guard let enumerator = FileManager.default.enumerator(
            at: exportRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class VideoPlaybackTestAccess:
    VaultGeneralFileCryptographicAccess,
    @unchecked Sendable
{
    let vaultID: UUID
    private let key = SymmetricKey(size: .bits256)

    init(vaultID: UUID) {
        self.vaultID = vaultID
    }

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    private func derivedKey(for purpose: VaultGeneralFileKeyPurpose) -> SymmetricKey {
        let domain: String
        switch purpose {
        case .manifest:
            domain = "manifest"
        case .file(let id):
            domain = "file.\(id.uuidString.lowercased())"
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(domain.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}
