import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import KeyHollow
@testable import KeyHollowGalleryUI
@testable import KeyHollowGeneralFileSupportAddOn
@testable import KeyHollowPhotoCore

final class VaultGalleryPresentationTests: XCTestCase {
    func testGalleryModuleContractUsesImmutableSourceNeutralValues() {
        let itemID = UUID()
        let importedAt = Date(timeIntervalSinceReferenceDate: 500)
        let item = VaultGalleryPresentationItem(
            id: .generalFile(itemID),
            importedAt: importedAt,
            displayName: "Evidence.pdf",
            originalByteCount: 8_192,
            isImage: false,
            fallbackTitle: "File",
            iconName: "doc",
            accessibilityKind: "Encrypted file"
        )
        let folder = VaultGalleryFolder(
            id: UUID(),
            name: "Records",
            itemCount: 1
        )

        XCTAssertEqual(item.id, .generalFile(itemID))
        XCTAssertEqual(item.importedAt, importedAt)
        XCTAssertEqual(item.title, "Evidence.pdf")
        XCTAssertEqual(item.detail, "8 KB")
        XCTAssertEqual(item.iconName, "doc")
        XCTAssertFalse(item.isImage)
        XCTAssertEqual(item.accessibilityKind, "Encrypted file")
        XCTAssertEqual(folder.name, "Records")
        XCTAssertEqual(folder.itemCount, 1)
    }

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
        let item = VaultGalleryContentItem.photo(decoded).presentationItem
        XCTAssertEqual(item.title, "Photo")
        XCTAssertFalse(item.detail.isEmpty)
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
        let item = VaultGalleryContentItem.photo(record).presentationItem
        XCTAssertEqual(item.title, "IMG_2735")
        XCTAssertEqual(item.detail, "2 KB")
    }

    func testImageDisplayNamesMatchAcrossPhotosAndFiles() {
        let importedAt = Date(timeIntervalSinceReferenceDate: 200)
        let photo = VaultPhotoRecord(
            id: UUID(),
            importedAt: importedAt,
            blobName: "photo.khp",
            thumbnailName: "photo.kht",
            displayName: "IMG_4130.HEIC",
            originalByteCount: 710_000
        )
        let file = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: importedAt,
            displayName: "IMG_4130.HEIC",
            contentTypeIdentifier: "public.heic",
            originalByteCount: 710_000,
            blobName: "file.khg"
        )

        let photoItem = VaultGalleryContentItem.photo(photo).presentationItem
        let fileItem = VaultGalleryContentItem.generalFile(file).presentationItem

        XCTAssertEqual(photoItem.title, "IMG_4130")
        XCTAssertEqual(fileItem.title, photoItem.title)
        XCTAssertEqual(fileItem.detail, photoItem.detail)
        XCTAssertTrue(fileItem.isImage)
    }

    func testNonImageFileKeepsExtension() {
        let record = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Proposal.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            originalByteCount: 4_096,
            blobName: "file.khg"
        )

        XCTAssertEqual(
            VaultGalleryContentItem.generalFile(record).presentationItem.title,
            "Proposal.pdf"
        )
    }

    func testSourceNeutralOrderUsesImportTimeInsteadOfStoreKind() {
        let olderPhoto = VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 100),
            blobName: "photo.khp",
            thumbnailName: "photo.kht",
            displayName: "Older.JPG",
            originalByteCount: 100
        )
        let newerFile = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 200),
            displayName: "Newer.png",
            contentTypeIdentifier: "public.png",
            originalByteCount: 200,
            blobName: "file.khg"
        )
        let items = [
            VaultGalleryContentItem.photo(olderPhoto),
            VaultGalleryContentItem.generalFile(newerFile)
        ].sorted(by: VaultGalleryContentItem.sourceNeutralOrder)

        XCTAssertEqual(items.map(\.presentationItem.title), ["Newer", "Older"])
    }

    func testSharedTileGeometryIsFixedForEveryItemKind() {
        XCTAssertEqual(VaultGalleryTileMetrics.mediaAspectRatio, 1)
        XCTAssertEqual(VaultGalleryTileMetrics.footerHeight, 56)
        XCTAssertEqual(VaultGalleryTileMetrics.selectionInset, 8)
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
