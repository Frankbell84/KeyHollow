import CoreGraphics
import Foundation
import XCTest
import KeyHollowFolderPresentationAddOn
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

    func testThumbnailEnvelopeMatchesEncryptedPresentationStoreLimit() {
        XCTAssertEqual(
            VaultEncryptedVideoThumbnailRenderer.maximumEncodedByteCount,
            VaultFolderPresentationStore.maximumThumbnailByteCount
        )
        XCTAssertEqual(VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension, 512)
    }

    func testThumbnailEncodingProducesBoundedJPEG() throws {
        let image = try makeTestImage(width: 32, height: 20)

        let thumbnail = try VaultEncryptedVideoThumbnailRenderer.encodedThumbnail(
            from: image
        )

        XCTAssertEqual(thumbnail.pixelWidth, 32)
        XCTAssertEqual(thumbnail.pixelHeight, 20)
        XCTAssertFalse(thumbnail.jpegData.isEmpty)
        XCTAssertLessThanOrEqual(
            thumbnail.jpegData.count,
            VaultEncryptedVideoThumbnailRenderer.maximumEncodedByteCount
        )
    }

    func testOversizedDecodedThumbnailIsRejected() throws {
        let image = try makeTestImage(
            width: VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension + 1,
            height: 8
        )

        XCTAssertThrowsError(
            try VaultEncryptedVideoThumbnailRenderer.encodedThumbnail(from: image)
        ) { error in
            XCTAssertEqual(
                error as? VaultEncryptedVideoThumbnailError,
                .dimensionsTooLarge
            )
        }
    }

    func testMissingLocalVideoFailsThumbnailRendering() async throws {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "missing.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 1_024
        )
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: descriptor,
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "MissingVideo-\(UUID().uuidString).mp4"
            )
        )

        do {
            _ = try await VaultEncryptedVideoThumbnailRenderer.render(playback)
            XCTFail("Expected a missing local video to fail thumbnail rendering")
        } catch {
            // AVFoundation owns the concrete media-decoder error.
        }
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
