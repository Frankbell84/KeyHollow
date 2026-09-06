import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import KeyHollow
@testable import KeyHollowPhotoCore

final class VaultGalleryPresentationTests: XCTestCase {
    func testMixedGallerySelectionCountsPhotosAndGeneralFiles() {
        let photoID = UUID()
        let fileID = UUID()
        let visible: [VaultGallerySelection.Item] = [
            .generalFile(fileID),
            .photo(photoID)
        ]
        var selection = VaultGallerySelection()

        selection.toggleAll(visible)

        XCTAssertEqual(selection.count, 2)
        XCTAssertTrue(selection.contains(.photo(photoID)))
        XCTAssertTrue(selection.contains(.generalFile(fileID)))
        XCTAssertTrue(selection.containsAll(visible))

        selection.toggleAll(visible)

        XCTAssertTrue(selection.isEmpty)
    }

    func testMixedGallerySelectionReconcilesDeletedRecordsByKind() {
        let sharedID = UUID()
        let removedID = UUID()
        var selection = VaultGallerySelection()
        selection.toggle(.photo(sharedID))
        selection.toggle(.generalFile(sharedID))
        selection.toggle(.generalFile(removedID))

        selection.reconcile(validItems: [
            .photo(sharedID),
            .generalFile(sharedID)
        ])

        XCTAssertEqual(selection.count, 2)
        XCTAssertTrue(selection.contains(.photo(sharedID)))
        XCTAssertTrue(selection.contains(.generalFile(sharedID)))
        XCTAssertFalse(selection.contains(.generalFile(removedID)))
    }

    func testPhotoRecordMetadataRemainsBackwardCompatible() throws {
        struct LegacyPhotoRecord: Encodable {
            let id: UUID
            let importedAt: Date
            let blobName: String
            let thumbnailName: String
        }

        let legacy = LegacyPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 100),
            blobName: "original.khp",
            thumbnailName: "thumbnail.kht"
        )
        let decoded = try JSONDecoder().decode(
            VaultPhotoRecord.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertNil(decoded.displayName)
        XCTAssertNil(decoded.originalByteCount)
        XCTAssertEqual(VaultPhotoPresentationMetadata.title(for: decoded), "Photo")
        XCTAssertFalse(VaultPhotoPresentationMetadata.detail(for: decoded).isEmpty)
    }

    func testPhotoStorePersistsSanitizedPresentationMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowGalleryPresentationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(size: .bits256),
            storageRoot: root
        )
        let original = Data(repeating: 0x42, count: 2_048)
        let record = try await store.importPhoto(
            originalData: original,
            thumbnailData: Data(repeating: 0x24, count: 64),
            displayName: "  IMG_2735.HEIC  "
        )

        XCTAssertEqual(record.displayName, "IMG_2735.HEIC")
        XCTAssertEqual(record.originalByteCount, UInt64(original.count))
        XCTAssertEqual(VaultPhotoPresentationMetadata.title(for: record), "IMG_2735.HEIC")
        XCTAssertEqual(VaultPhotoPresentationMetadata.detail(for: record), "2 KB")
    }

    @MainActor
    func testThumbnailRendererPreservesOrientedAspectRatio() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 80, height: 40),
            format: format
        )
        let source = renderer.image {
            UIColor.systemBlue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        let cgImage = try XCTUnwrap(source.cgImage)
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        XCTAssertEqual(
            VaultGalleryThumbnailRenderer.orientedPixelSize(for: rotated),
            CGSize(width: 40, height: 80)
        )
        let data = try XCTUnwrap(
            VaultGalleryThumbnailRenderer.jpegData(from: rotated, maximumDimension: 40)
        )
        let thumbnail = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(thumbnail.width, 20)
        XCTAssertEqual(thumbnail.height, 40)
    }
}
