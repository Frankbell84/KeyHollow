import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import KeyHollow
@testable import KeyHollowCatalogSearchAddOn
@testable import KeyHollowGalleryUI
@testable import KeyHollowGeneralFileSupportAddOn
@testable import KeyHollowMediaNavigationAddOn
@testable import KeyHollowPhotoCore

final class VaultGalleryPresentationTests: XCTestCase {
    func testFolderDestinationTitlesRemainUnambiguous() {
        let root = VaultFolderPathPresentation.destinationTitle(path: [])
        let folderNamedRoot = VaultFolderPathPresentation.destinationTitle(
            path: ["Vault Root"]
        )
        let slashName = VaultFolderPathPresentation.destinationTitle(path: ["A / B"])
        let nestedPath = VaultFolderPathPresentation.destinationTitle(path: ["A", "B"])

        XCTAssertEqual(root, "Vault Root")
        XCTAssertEqual(folderNamedRoot, "Vault Root › Vault Root")
        XCTAssertNotEqual(root, folderNamedRoot)
        XCTAssertNotEqual(slashName, nestedPath)
    }

    func testFolderDestinationTitlesEscapePathDelimiterAndEscapeCharacter() {
        XCTAssertEqual(
            VaultFolderPathPresentation.destinationTitle(path: ["A › B", "C\\D"]),
            "Vault Root › A \\› B › C\\\\D"
        )
    }

    func testMoveDestinationCatalogShowsOnlyOneFolderLevelAtATime() {
        let alpha = UUID()
        let zulu = UUID()
        let nested = UUID()
        let catalog = VaultMoveDestinationCatalog(
            folders: [
                VaultMoveDestinationFolder(id: zulu, parentID: nil, name: "Zulu"),
                VaultMoveDestinationFolder(id: nested, parentID: alpha, name: "Nested"),
                VaultMoveDestinationFolder(id: alpha, parentID: nil, name: "Alpha"),
            ],
            rootIsValid: true,
            validFolderIDs: [alpha, zulu, nested]
        )

        XCTAssertEqual(catalog.childFolders(of: nil).map(\.id), [alpha, zulu])
        XCTAssertEqual(catalog.childFolders(of: alpha).map(\.id), [nested])
        XCTAssertEqual(catalog.title(for: nil), "Vault Root")
        XCTAssertEqual(catalog.title(for: nested), "Nested")
    }

    func testMoveDestinationCatalogSeparatesBrowsingFromMovePermission() {
        let currentFolder = UUID()
        let childDestination = UUID()
        let catalog = VaultMoveDestinationCatalog(
            folders: [
                VaultMoveDestinationFolder(
                    id: currentFolder,
                    parentID: nil,
                    name: "Current"
                ),
                VaultMoveDestinationFolder(
                    id: childDestination,
                    parentID: currentFolder,
                    name: "Child"
                ),
            ],
            rootIsValid: true,
            validFolderIDs: [childDestination]
        )

        XCTAssertFalse(catalog.canMove(to: currentFolder))
        XCTAssertTrue(catalog.canBrowse(folderID: currentFolder))
        XCTAssertTrue(catalog.canMove(to: childDestination))
        XCTAssertTrue(catalog.canMove(to: nil))
    }

    func testMoveDestinationCatalogBuildsSingleAndMultiItemPermissions() {
        let first = UUID()
        let second = UUID()
        let folders = [
            VaultMoveDestinationFolder(id: first, parentID: nil, name: "First"),
            VaultMoveDestinationFolder(id: second, parentID: nil, name: "Second"),
        ]

        let rootItem = VaultMoveDestinationCatalog(
            folders: folders,
            currentFolderIDs: [nil]
        )
        XCTAssertFalse(rootItem.canMove(to: nil))
        XCTAssertTrue(rootItem.canMove(to: first))
        XCTAssertTrue(rootItem.canMove(to: second))

        let sameFolderBatch = VaultMoveDestinationCatalog(
            folders: folders,
            currentFolderIDs: [first, first]
        )
        XCTAssertTrue(sameFolderBatch.canMove(to: nil))
        XCTAssertFalse(sameFolderBatch.canMove(to: first))
        XCTAssertTrue(sameFolderBatch.canMove(to: second))

        let mixedLocationBatch = VaultMoveDestinationCatalog(
            folders: folders,
            currentFolderIDs: [nil, first]
        )
        XCTAssertTrue(mixedLocationBatch.canMove(to: nil))
        XCTAssertTrue(mixedLocationBatch.canMove(to: first))
        XCTAssertTrue(mixedLocationBatch.canMove(to: second))
    }

    func testMoveDestinationCatalogKeepsDuplicateNamesScopedByFolderID() {
        let left = UUID()
        let right = UUID()
        let leftShared = UUID()
        let rightShared = UUID()
        let catalog = VaultMoveDestinationCatalog(
            folders: [
                VaultMoveDestinationFolder(id: left, parentID: nil, name: "Left"),
                VaultMoveDestinationFolder(id: right, parentID: nil, name: "Right"),
                VaultMoveDestinationFolder(id: leftShared, parentID: left, name: "Shared"),
                VaultMoveDestinationFolder(id: rightShared, parentID: right, name: "Shared"),
            ],
            rootIsValid: true,
            validFolderIDs: [left, right, leftShared, rightShared]
        )

        XCTAssertEqual(catalog.childFolders(of: left).map(\.id), [leftShared])
        XCTAssertEqual(catalog.childFolders(of: right).map(\.id), [rightShared])
        XCTAssertEqual(catalog.title(for: leftShared), "Shared")
        XCTAssertEqual(catalog.title(for: rightShared), "Shared")
        XCTAssertNotEqual(leftShared, rightShared)
    }

    func testMoveDestinationCatalogSupportsEightLevelDrillDown() {
        let identifiers = (0..<8).map { _ in UUID() }
        let folders = identifiers.enumerated().map { offset, identifier in
            VaultMoveDestinationFolder(
                id: identifier,
                parentID: offset == 0 ? nil : identifiers[offset - 1],
                name: "Level \(offset + 1)"
            )
        }
        let catalog = VaultMoveDestinationCatalog(
            folders: folders,
            rootIsValid: true,
            validFolderIDs: Set(identifiers)
        )

        var parentID: UUID?
        for expectedID in identifiers {
            let children = catalog.childFolders(of: parentID)
            XCTAssertEqual(children.map(\.id), [expectedID])
            XCTAssertTrue(catalog.canBrowse(folderID: expectedID))
            parentID = expectedID
        }
        XCTAssertTrue(catalog.childFolders(of: parentID).isEmpty)
    }

    func testMoveDestinationCatalogDisablesEntireForbiddenSubtree() {
        let forbiddenParent = UUID()
        let forbiddenChild = UUID()
        let validSibling = UUID()
        let catalog = VaultMoveDestinationCatalog(
            folders: [
                VaultMoveDestinationFolder(
                    id: forbiddenParent,
                    parentID: nil,
                    name: "Source"
                ),
                VaultMoveDestinationFolder(
                    id: forbiddenChild,
                    parentID: forbiddenParent,
                    name: "Source Child"
                ),
                VaultMoveDestinationFolder(
                    id: validSibling,
                    parentID: nil,
                    name: "Destination"
                ),
            ],
            rootIsValid: false,
            validFolderIDs: [validSibling]
        )

        XCTAssertFalse(catalog.canBrowse(folderID: forbiddenParent))
        XCTAssertFalse(catalog.canBrowse(folderID: forbiddenChild))
        XCTAssertTrue(catalog.canBrowse(folderID: validSibling))
        XCTAssertFalse(catalog.canMove(to: nil))
    }

    func testMoveDestinationCatalogTerminatesOnMalformedCycle() {
        let first = UUID()
        let second = UUID()
        let catalog = VaultMoveDestinationCatalog(
            folders: [
                VaultMoveDestinationFolder(id: first, parentID: second, name: "First"),
                VaultMoveDestinationFolder(id: second, parentID: first, name: "Second"),
            ],
            rootIsValid: false,
            validFolderIDs: []
        )

        XCTAssertFalse(catalog.canBrowse(folderID: first))
        XCTAssertFalse(catalog.canBrowse(folderID: second))
    }

    func testCatalogSearchFiltersVisibleSnapshotAndMediaQueue() throws {
        let importedAt = Date(timeIntervalSinceReferenceDate: 800)
        let photo = VaultPhotoRecord(
            id: UUID(),
            importedAt: importedAt,
            blobName: "photo.khp",
            thumbnailName: "photo.kht",
            displayName: "Family 2026.HEIC",
            originalByteCount: 2_048
        )
        let video = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: importedAt.addingTimeInterval(-1),
            displayName: "Family 2026.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 4_096,
            blobName: "video.khg"
        )
        let document = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: importedAt.addingTimeInterval(-2),
            displayName: "Family 2026.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            originalByteCount: 8_192,
            blobName: "document.khg"
        )
        let unrelated = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: importedAt.addingTimeInterval(-3),
            displayName: "Receipt.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            originalByteCount: 1_024,
            blobName: "receipt.khg"
        )

        let filtered = VaultGalleryContentSnapshot(items: [
            .generalFile(unrelated),
            .generalFile(document),
            .generalFile(video),
            .photo(photo),
        ]).filtering(with: VaultCatalogSearchQuery("2026 family"))

        XCTAssertEqual(filtered.presentations.count, 3)
        XCTAssertEqual(filtered.presentations.map(\.title), [
            "Family 2026",
            "Family 2026.mp4",
            "Family 2026.pdf",
        ])
        let queue = try filtered.mediaNavigationQueue(
            startingAt: VaultGalleryContentItem.photo(photo).mediaNavigationID
        )
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.items.map(\.title), [
            "Family 2026",
            "Family 2026.mp4",
        ])
    }

    func testCatalogSortOrderControlsVisibleItemsAndMediaQueue() throws {
        let older = Date(timeIntervalSinceReferenceDate: 700)
        let newer = Date(timeIntervalSinceReferenceDate: 800)
        let alpha = VaultPhotoRecord(
            id: UUID(),
            importedAt: older,
            blobName: "alpha.khp",
            thumbnailName: "alpha.kht",
            displayName: "Alpha.HEIC",
            originalByteCount: 1_024
        )
        let zulu = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: newer,
            displayName: "Zulu.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 2_048,
            blobName: "zulu.khg"
        )

        let snapshot = VaultGalleryContentSnapshot(
            items: [.generalFile(zulu), .photo(alpha)],
            sortOrder: .nameAscending
        )

        XCTAssertEqual(snapshot.presentations.map(\.title), ["Alpha", "Zulu.mp4"])
        let queue = try snapshot.mediaNavigationQueue(
            startingAt: VaultGalleryContentItem.photo(alpha).mediaNavigationID
        )
        XCTAssertEqual(queue.items.map(\.title), ["Alpha", "Zulu.mp4"])
    }

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

    func testSelectionTransferModeExposesTheMatchingSaveAndExportPath() {
        let photoID = UUID()
        let fileID = UUID()
        var selection = VaultGallerySelection()

        XCTAssertEqual(selection.transferMode, .none)

        selection.toggle(.photo(photoID))
        XCTAssertEqual(selection.transferMode, .photos)

        selection.toggle(.generalFile(fileID))
        XCTAssertEqual(selection.transferMode, .mixed)

        selection.toggle(.photo(photoID))
        XCTAssertEqual(selection.transferMode, .generalFiles)
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

    func testMovieFileUsesVideoFallbackIcon() {
        XCTAssertEqual(
            GeneralFilePresentation.iconName(for: "public.mpeg-4"),
            "video"
        )
    }

    func testPhotosAndFilesOriginImagesUseTheSameSecurePreviewRoute() {
        let photo = VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            blobName: "photo.khp",
            thumbnailName: "photo.kht",
            displayName: "Evidence.HEIC",
            originalByteCount: 2_048
        )
        let fileImage = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Evidence.HEIC",
            contentTypeIdentifier: "public.heic",
            originalByteCount: 2_048,
            blobName: "file.khg"
        )

        XCTAssertEqual(VaultGalleryContentItem.photo(photo).openRoute, .imagePreview)
        XCTAssertEqual(
            VaultGalleryContentItem.generalFile(fileImage).openRoute,
            .imagePreview
        )
    }

    func testNonImageFileKeepsFileManagementRoute() {
        let file = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Evidence.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            originalByteCount: 2_048,
            blobName: "file.khg"
        )

        XCTAssertEqual(
            VaultGalleryContentItem.generalFile(file).openRoute,
            .fileManagement
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

    func testGallerySnapshotMapsTwentySixMixedItemsOnceWithStableLookup() {
        let sharedSourceID = UUID()
        var photos: [VaultPhotoRecord] = []
        var files: [VaultGeneralFileRecord] = []
        photos.reserveCapacity(13)
        files.reserveCapacity(13)

        for index in 0..<13 {
            let sourceID = index == 0 ? sharedSourceID : UUID()
            let photoImportedAt = Date(
                timeIntervalSinceReferenceDate: TimeInterval(100 + index)
            )
            let fileImportedAt = Date(
                timeIntervalSinceReferenceDate: TimeInterval(200 + index)
            )

            photos.append(VaultPhotoRecord(
                id: sourceID,
                importedAt: photoImportedAt,
                blobName: "photo-\(index).khp",
                thumbnailName: "photo-\(index).kht",
                displayName: "Photo \(index).HEIC",
                originalByteCount: UInt64(1_000 + index)
            ))
            files.append(VaultGeneralFileRecord(
                id: sourceID,
                importedAt: fileImportedAt,
                displayName: "File \(index).jpg",
                contentTypeIdentifier: "public.jpeg",
                originalByteCount: UInt64(2_000 + index),
                blobName: "file-\(index).khg"
            ))
        }
        let snapshot = VaultGalleryContentSnapshot(
            items: photos.map(VaultGalleryContentItem.photo)
                + files.map(VaultGalleryContentItem.generalFile)
        )

        XCTAssertEqual(snapshot.presentations.count, 26)
        XCTAssertEqual(snapshot.orderedSources.count, 26)
        XCTAssertEqual(snapshot.sourceByID.count, 26)
        XCTAssertEqual(snapshot.selectableItems.count, 26)
        let importedDates = snapshot.presentations.map { $0.importedAt }
        XCTAssertEqual(
            importedDates,
            importedDates.sorted(by: >)
        )
        for presentation in snapshot.presentations {
            XCTAssertEqual(snapshot.sourceByID[presentation.id]?.id, presentation.id)
        }
        XCTAssertNotNil(
            snapshot.sourceByID[VaultGallerySelection.Item.photo(sharedSourceID)]
        )
        XCTAssertNotNil(
            snapshot.sourceByID[VaultGallerySelection.Item.generalFile(sharedSourceID)]
        )
    }

    func testSupportedGeneralFileVideoUsesPlaybackRoute() {
        let video = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Family Clip.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 4_096,
            blobName: "video.khg"
        )

        XCTAssertEqual(
            VaultGalleryContentItem.generalFile(video).openRoute,
            .videoPlayback
        )
    }

    func testMediaNavigationIdentityKeepsPhotoAndFileWithSharedUUIDDistinct() throws {
        let sharedID = UUID()
        let importedAt = Date(timeIntervalSinceReferenceDate: 300)
        let photo = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: sharedID,
            importedAt: importedAt,
            blobName: "photo.khp",
            thumbnailName: "photo.kht",
            displayName: "Shared.jpg",
            originalByteCount: 1_024
        ))
        let file = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: sharedID,
            importedAt: importedAt.addingTimeInterval(-1),
            displayName: "Shared.jpg",
            contentTypeIdentifier: "public.jpeg",
            originalByteCount: 1_024,
            blobName: "file.khg"
        ))
        let snapshot = VaultGalleryContentSnapshot(items: [photo, file])

        XCTAssertNotEqual(photo.mediaNavigationID, file.mediaNavigationID)
        XCTAssertEqual(snapshot.mediaNavigationItems.count, 2)
        XCTAssertEqual(snapshot.mediaNavigationSourceByID.count, 2)
        XCTAssertEqual(
            snapshot.mediaNavigationSourceByID[photo.mediaNavigationID],
            photo
        )
        XCTAssertEqual(
            snapshot.mediaNavigationSourceByID[file.mediaNavigationID],
            file
        )
    }

    func testMediaNavigationPreservesVisibleGalleryOrdering() {
        let oldestPhoto = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 100),
            blobName: "old.khp",
            thumbnailName: "old.kht",
            displayName: "Old.jpg",
            originalByteCount: 100
        ))
        let newestVideo = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Newest.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 300,
            blobName: "new.khg"
        ))
        let middleImage = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 200),
            displayName: "Middle.png",
            contentTypeIdentifier: "public.png",
            originalByteCount: 200,
            blobName: "middle.khg"
        ))
        let snapshot = VaultGalleryContentSnapshot(
            items: [oldestPhoto, newestVideo, middleImage]
        )

        XCTAssertEqual(
            snapshot.mediaNavigationItems.map(\.id),
            [
                newestVideo.mediaNavigationID,
                middleImage.mediaNavigationID,
                oldestPhoto.mediaNavigationID
            ]
        )
    }

    func testMediaNavigationIncludesPhotosFileImagesAndSupportedVideos() {
        let photo = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            blobName: "photo.khp",
            thumbnailName: "photo.kht",
            displayName: "Photo.heic",
            originalByteCount: 300
        ))
        let fileImage = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 200),
            displayName: "Image.jpeg",
            contentTypeIdentifier: "public.jpeg",
            originalByteCount: 200,
            blobName: "image.khg"
        ))
        let video = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 100),
            displayName: "Clip.mov",
            contentTypeIdentifier: "com.apple.quicktime-movie",
            originalByteCount: 100,
            blobName: "video.khg"
        ))
        let snapshot = VaultGalleryContentSnapshot(items: [video, photo, fileImage])

        XCTAssertEqual(
            snapshot.mediaNavigationItems.map(\.id),
            [
                photo.mediaNavigationID,
                fileImage.mediaNavigationID,
                video.mediaNavigationID
            ]
        )
        XCTAssertEqual(
            snapshot.mediaNavigationItems.map(\.kind),
            [.image, .image, .video]
        )
    }

    func testMediaNavigationExcludesNonMediaFiles() {
        let photo = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 200),
            blobName: "photo.khp",
            thumbnailName: "photo.kht",
            displayName: "Photo.jpg",
            originalByteCount: 200
        ))
        let pdf = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Document.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            originalByteCount: 300,
            blobName: "document.khg"
        ))
        let snapshot = VaultGalleryContentSnapshot(items: [pdf, photo])

        XCTAssertEqual(snapshot.mediaNavigationItems.map(\.id), [photo.mediaNavigationID])
        XCTAssertNil(snapshot.mediaNavigationSourceByID[pdf.mediaNavigationID])
    }

    func testMediaNavigationQueueUsesOnlyTheSuppliedVisibleFolderSnapshot() throws {
        let rootPhoto = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 400),
            blobName: "root.khp",
            thumbnailName: "root.kht",
            displayName: "Root.jpg",
            originalByteCount: 400
        ))
        let folderPhoto = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            blobName: "folder.khp",
            thumbnailName: "folder.kht",
            displayName: "Folder.jpg",
            originalByteCount: 300
        ))
        let folderVideo = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 200),
            displayName: "Folder.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 200,
            blobName: "folder-video.khg"
        ))
        let visibleFolderSnapshot = VaultGalleryContentSnapshot(
            items: [folderVideo, folderPhoto]
        )

        let queue = try visibleFolderSnapshot.mediaNavigationQueue(
            startingAt: folderPhoto.mediaNavigationID
        )

        XCTAssertEqual(
            queue.items.map(\.id),
            [folderPhoto.mediaNavigationID, folderVideo.mediaNavigationID]
        )
        XCTAssertFalse(queue.items.map(\.id).contains(rootPhoto.mediaNavigationID))
    }

    func testMediaNavigationQueueStartsAtTappedVisibleItem() throws {
        let newest = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            blobName: "newest.khp",
            thumbnailName: "newest.kht",
            displayName: "Newest.jpg",
            originalByteCount: 300
        ))
        let tapped = VaultGalleryContentItem.generalFile(VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 200),
            displayName: "Tapped.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: 200,
            blobName: "tapped.khg"
        ))
        let oldest = VaultGalleryContentItem.photo(VaultPhotoRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 100),
            blobName: "oldest.khp",
            thumbnailName: "oldest.kht",
            displayName: "Oldest.jpg",
            originalByteCount: 100
        ))
        let snapshot = VaultGalleryContentSnapshot(items: [oldest, newest, tapped])

        let queue = try snapshot.mediaNavigationQueue(
            startingAt: tapped.mediaNavigationID
        )

        XCTAssertEqual(queue.selectedID, tapped.mediaNavigationID)
        XCTAssertEqual(queue.currentItem.id, tapped.mediaNavigationID)
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertEqual(queue.currentPosition, 2)
    }

    func testImageDeclarationKeepsPreviewPrecedenceOverVideoFilename() {
        let image = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Misleading.mp4",
            contentTypeIdentifier: "public.jpeg",
            originalByteCount: 4_096,
            blobName: "image.khg"
        )

        XCTAssertEqual(
            VaultGalleryContentItem.generalFile(image).openRoute,
            .imagePreview
        )
    }

    func testBroadMovieDeclarationStaysOnFileManagementRoute() {
        let video = VaultGeneralFileRecord(
            id: UUID(),
            importedAt: Date(timeIntervalSinceReferenceDate: 300),
            displayName: "Unclassified.mp4",
            contentTypeIdentifier: "public.movie",
            originalByteCount: 4_096,
            blobName: "video.khg"
        )

        XCTAssertEqual(
            VaultGalleryContentItem.generalFile(video).openRoute,
            .fileManagement
        )
    }

    func testSharedTileGeometryIsFixedForEveryItemKind() {
        XCTAssertEqual(VaultGalleryTileMetrics.columnCount, 3)
        XCTAssertEqual(VaultGalleryTileMetrics.gridSpacing, 3)
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
