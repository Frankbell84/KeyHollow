import Foundation
import XCTest
@testable import KeyHollowSecurePreviewAddOn

final class VaultSecurePreviewAddOnTests: XCTestCase {
    func testImageContentTypeUsesImagePreview() {
        let descriptor = VaultSecurePreviewDescriptor(
            displayName: "scan.bin",
            contentTypeIdentifier: "public.png",
            originalByteCount: 68
        )

        XCTAssertEqual(VaultSecurePreviewPolicy.kind(for: descriptor), .image)
    }

    func testImageExtensionIsSafeFallbackWhenMetadataIsMissing() {
        let descriptor = VaultSecurePreviewDescriptor(
            displayName: "evidence.JPEG",
            contentTypeIdentifier: nil,
            originalByteCount: 68
        )

        XCTAssertEqual(VaultSecurePreviewPolicy.kind(for: descriptor), .image)
    }

    func testNonImageFileDoesNotEnterImageDecoder() {
        let descriptor = VaultSecurePreviewDescriptor(
            displayName: "evidence.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            originalByteCount: 1_024
        )

        XCTAssertEqual(VaultSecurePreviewPolicy.kind(for: descriptor), .unsupported)
    }

    func testEncodedImageBoundaryRejectsEmptyAndOversizedPayloads() {
        XCTAssertFalse(VaultSecurePreviewPolicy.allowsEncodedImageByteCount(0))
        XCTAssertTrue(VaultSecurePreviewPolicy.allowsEncodedImageByteCount(1))
        XCTAssertTrue(VaultSecurePreviewPolicy.allowsEncodedImageByteCount(
            VaultSecurePreviewPolicy.maximumEncodedImageByteCount
        ))
        XCTAssertFalse(VaultSecurePreviewPolicy.allowsEncodedImageByteCount(
            VaultSecurePreviewPolicy.maximumEncodedImageByteCount + 1
        ))
    }

    func testPreviewRejectsEmptyAndInvalidImageData() {
        XCTAssertThrowsError(
            try VaultSecureImagePreview(
                id: UUID(),
                displayName: "empty.png",
                originalData: Data()
            )
        ) { error in
            XCTAssertEqual(error as? VaultSecureImagePreviewError, .emptyPayload)
        }

        XCTAssertThrowsError(
            try VaultSecureImagePreview(
                id: UUID(),
                displayName: "invalid.png",
                originalData: Data("not an image".utf8)
            )
        ) { error in
            XCTAssertEqual(error as? VaultSecureImagePreviewError, .invalidImage)
        }
    }

    func testPreviewAcceptsValidatedImageAndPreservesIdentity() throws {
        let id = UUID()
        let onePixelPNG = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))

        let preview = try VaultSecureImagePreview(
            id: id,
            displayName: "Evidence",
            originalData: onePixelPNG
        )

        XCTAssertEqual(preview.id, id)
        XCTAssertEqual(preview.displayName, "Evidence")
        XCTAssertEqual(preview.originalData, onePixelPNG)
    }
}
