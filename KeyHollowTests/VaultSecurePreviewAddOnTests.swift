import Foundation
import UIKit
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
        XCTAssertEqual(preview.displayImage.image.cgImage?.width, 1)
        XCTAssertEqual(preview.displayImage.image.cgImage?.height, 1)
    }

    @MainActor
    func testSecureImageSurfaceDoesNotAdoptAttachedImageDimensions() {
        let surface = VaultSecureAspectFitImageView()
        surface.image = UIGraphicsImageRenderer(
            size: CGSize(width: 640, height: 480)
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }

        XCTAssertEqual(surface.intrinsicContentSize.width, UIView.noIntrinsicMetric)
        XCTAssertEqual(surface.intrinsicContentSize.height, UIView.noIntrinsicMetric)
    }

    @MainActor
    func testProcessorBoundsAndPreparesGalleryThumbnailOffViewPath() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 800, height: 400),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        }
        let sourceData = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
        let processor = VaultSecureImageProcessor()

        let prepared = try await processor.prepareThumbnail(from: sourceData)

        XCTAssertEqual(prepared.renderedImage.image.cgImage?.width, 512)
        XCTAssertEqual(prepared.renderedImage.image.cgImage?.height, 256)
        XCTAssertFalse(prepared.encodedData.isEmpty)
    }
}
