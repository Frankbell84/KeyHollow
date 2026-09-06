import Foundation
import XCTest
import KeyHollowGeneralFileSupportAddOn
@testable import KeyHollowEncryptedVideoAddOn

final class VaultEncryptedVideoAddOnTests: XCTestCase {
    func testDeclaredMovieTypeUsesVideoRoute() {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "evidence.bin",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 1_024
        )

        XCTAssertEqual(VaultEncryptedVideoPolicy.kind(for: descriptor), .video)
    }

    func testSafeExtensionFallbackIsCaseInsensitiveWhenMetadataIsMissing() {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "Evidence.MOV",
            contentTypeIdentifier: nil,
            originalByteCount: 1_024
        )

        XCTAssertEqual(VaultEncryptedVideoPolicy.kind(for: descriptor), .video)
    }

    func testRecognizedNonVideoTypeOverridesMisleadingExtension() {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "renamed.mov",
            contentTypeIdentifier: "com.adobe.pdf",
            originalByteCount: 1_024
        )

        XCTAssertEqual(VaultEncryptedVideoPolicy.kind(for: descriptor), .unsupported)
    }

    func testUnsupportedExtensionDoesNotEnterVideoRoute() {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "notes.txt",
            contentTypeIdentifier: nil,
            originalByteCount: 1_024
        )

        XCTAssertEqual(VaultEncryptedVideoPolicy.kind(for: descriptor), .unsupported)
    }

    func testPlaybackSizeBoundaryMatchesExistingEncryptedIngress() {
        XCTAssertEqual(
            VaultEncryptedVideoPolicy.maximumPlaybackByteCount,
            VaultGeneralFileStore.maximumFileByteCount
        )
        XCTAssertFalse(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(0))
        XCTAssertTrue(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(1))
        XCTAssertTrue(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(
            VaultEncryptedVideoPolicy.maximumPlaybackByteCount
        ))
        XCTAssertFalse(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(
            VaultEncryptedVideoPolicy.maximumPlaybackByteCount + 1
        ))
    }

    func testPreparedPlaybackAcceptsOnlyLocalValidatedVideo() throws {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "clip.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 1_024
        )
        let id = UUID()
        let localURL = URL(fileURLWithPath: "/protected/temporary/clip.mp4")

        let prepared = try VaultPreparedVideoPlayback(
            id: id,
            descriptor: descriptor,
            fileURL: localURL
        )

        XCTAssertEqual(prepared.id, id)
        XCTAssertEqual(prepared.descriptor, descriptor)
        XCTAssertEqual(prepared.fileURL, localURL)
        XCTAssertThrowsError(
            try VaultPreparedVideoPlayback(
                id: id,
                descriptor: descriptor,
                fileURL: try XCTUnwrap(URL(string: "https://example.com/clip.mp4"))
            )
        ) { error in
            XCTAssertEqual(error as? VaultPreparedVideoPlaybackError, .invalidPlaybackURL)
        }
    }

    func testPreparedPlaybackRejectsUnsupportedDescriptor() {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "notes.txt",
            contentTypeIdentifier: "public.plain-text",
            originalByteCount: 32
        )

        XCTAssertThrowsError(
            try VaultPreparedVideoPlayback(
                id: UUID(),
                descriptor: descriptor,
                fileURL: URL(fileURLWithPath: "/protected/temporary/notes.txt")
            )
        ) { error in
            XCTAssertEqual(error as? VaultPreparedVideoPlaybackError, .unsupportedVideo)
        }
    }
}
