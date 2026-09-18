import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowCryptoCore
@testable import KeyHollowFolderPresentationAddOn
@testable import KeyHollowTransferCore

final class FolderPresentationPortableTransferBridgeTests: XCTestCase {
    func testArchiveInventoryStripsThumbnailCacheAndRoundTripsOrganization() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let parent = try await fixture.store.createFolder(named: "Parent")
        let child = try await fixture.store.createFolder(named: "Child", in: parent.id)
        let photoID = UUID()
        let fileID = UUID()
        let photo = VaultPresentedContentReference(kind: .photo, id: photoID)
        let file = VaultPresentedContentReference(kind: .generalFile, id: fileID)
        try await fixture.store.move(Set([photo, file]), to: child.id)
        try await fixture.store.storeThumbnail(Data("cache".utf8), for: file)

        let bridge = FolderPresentationPortableTransferBridge(access: fixture.access)
        let inventory = try await bridge.authenticatedArchiveInventory(
            vaultID: fixture.vaultID,
            sourceRootOverride: fixture.sourceRoot,
            validPhotoIDs: [photoID],
            validGeneralFileIDs: [fileID]
        )

        XCTAssertEqual(inventory.folderCount, 2)
        XCTAssertEqual(inventory.membershipCount, 2)
        XCTAssertEqual(inventory.referencedItems, Set([
            PortableVaultFolderItemReference(kind: .photo, id: photoID),
            PortableVaultFolderItemReference(kind: .generalFile, id: fileID)
        ]))
        let ciphertext = try XCTUnwrap(inventory.manifestCiphertext)
        let plaintext = try fixture.access.open(ciphertext, for: .manifest)
        let archivedManifest = try JSONDecoder().decode(
            VaultFolderPresentationManifest.self,
            from: plaintext
        )
        XCTAssertEqual(archivedManifest.folders, [parent, child])
        XCTAssertEqual(archivedManifest.memberships.count, 2)
        XCTAssertTrue(archivedManifest.thumbnails.isEmpty)

        let stagedRoot = fixture.root.appendingPathComponent("staged-folders", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagedRoot,
            withIntermediateDirectories: false
        )
        try ciphertext.write(
            to: stagedRoot.appendingPathComponent("manifest.khm"),
            options: .atomic
        )
        let validated = try await FolderPresentationPortableTransferBridge()
            .validateStagedContent(
                at: stagedRoot,
                sourceVaultID: fixture.vaultID,
                vaultKey: fixture.vaultKey,
                validPhotoIDs: [photoID],
                validGeneralFileIDs: [fileID]
            )
        XCTAssertEqual(validated.folderCount, 2)
        XCTAssertEqual(validated.membershipCount, 2)
        XCTAssertEqual(validated.referencedItems, inventory.referencedItems)
    }

    func testArchiveInventoryRejectsDanglingMembershipInsteadOfFlatteningIt() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let folder = try await fixture.store.createFolder(named: "Private")
        let missingPhoto = VaultPresentedContentReference(kind: .photo, id: UUID())
        try await fixture.store.move(missingPhoto, to: folder.id)

        do {
            _ = try await FolderPresentationPortableTransferBridge(access: fixture.access)
                .authenticatedArchiveInventory(
                    vaultID: fixture.vaultID,
                    sourceRootOverride: fixture.sourceRoot,
                    validPhotoIDs: [],
                    validGeneralFileIDs: []
                )
            XCTFail("Expected dangling membership rejection")
        } catch {
            XCTAssertEqual(
                error as? VaultFolderPresentationStore.StoreError,
                .invalidManifest
            )
        }
    }

    func testArchiveInventoryRejectsReferenceWhoseKindDoesNotMatchContent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let folder = try await fixture.store.createFolder(named: "Private")
        let sharedID = UUID()
        try await fixture.store.move(
            VaultPresentedContentReference(kind: .photo, id: sharedID),
            to: folder.id
        )

        do {
            _ = try await FolderPresentationPortableTransferBridge(access: fixture.access)
                .authenticatedArchiveInventory(
                    vaultID: fixture.vaultID,
                    sourceRootOverride: fixture.sourceRoot,
                    validPhotoIDs: [],
                    validGeneralFileIDs: [sharedID]
                )
            XCTFail("A photo membership was accepted as a general-file reference")
        } catch {
            XCTAssertEqual(
                error as? VaultFolderPresentationStore.StoreError,
                .invalidManifest
            )
        }
    }

    func testEmptyFolderIsPreservedAsAuthenticatedOrganization() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let folder = try await fixture.store.createFolder(named: "Empty")
        let inventory = try await FolderPresentationPortableTransferBridge(
            access: fixture.access
        ).authenticatedArchiveInventory(
            vaultID: fixture.vaultID,
            sourceRootOverride: fixture.sourceRoot,
            validPhotoIDs: [],
            validGeneralFileIDs: []
        )

        XCTAssertEqual(inventory.folderCount, 1)
        XCTAssertEqual(inventory.membershipCount, 0)
        XCTAssertTrue(inventory.referencedItems.isEmpty)
        let ciphertext = try XCTUnwrap(inventory.manifestCiphertext)
        let plaintext = try fixture.access.open(ciphertext, for: .manifest)
        let manifest = try JSONDecoder().decode(
            VaultFolderPresentationManifest.self,
            from: plaintext
        )
        XCTAssertEqual(manifest.folders, [folder])
        XCTAssertTrue(manifest.memberships.isEmpty)
        XCTAssertTrue(manifest.thumbnails.isEmpty)
    }

    func testMissingFolderStoreProducesLegacyCompatibleEmptyInventory() async throws {
        let fixture = try Fixture(createStore: false)
        defer { fixture.cleanup() }

        let inventory = try await FolderPresentationPortableTransferBridge(
            access: fixture.access
        ).authenticatedArchiveInventory(
            vaultID: fixture.vaultID,
            sourceRootOverride: fixture.sourceRoot,
            validPhotoIDs: [],
            validGeneralFileIDs: []
        )

        XCTAssertNil(inventory.manifestCiphertext)
        XCTAssertEqual(inventory.folderCount, 0)
        XCTAssertEqual(inventory.membershipCount, 0)
        XCTAssertTrue(inventory.referencedItems.isEmpty)
    }
}

private struct Fixture {
    let root: URL
    let sourceRoot: URL
    let vaultID: UUID
    let vaultKey: SymmetricKey
    let access: TestFolderAccess
    let store: VaultFolderPresentationStore

    init(createStore: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "folder-transfer-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        vaultID = UUID()
        vaultKey = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        access = TestFolderAccess(vaultID: vaultID, vaultKey: vaultKey)
        if createStore {
            store = try VaultFolderPresentationStore(
                vaultID: vaultID,
                access: access,
                storageRoot: sourceRoot
            )
        } else {
            let unusedRoot = root.appendingPathComponent("unused", isDirectory: true)
            store = try VaultFolderPresentationStore(
                vaultID: vaultID,
                access: access,
                storageRoot: unusedRoot
            )
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct TestFolderAccess: VaultFolderPresentationCryptographicAccess {
    let vaultID: UUID
    let vaultKey: SymmetricKey

    func checkAccess() throws {}

    func seal(
        _ plaintext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(
        _ ciphertext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    private func derivedKey(for purpose: VaultFolderPresentationKeyPurpose) -> SymmetricKey {
        let label = "keyhollow.addon.\(purpose.cryptographicDomain)"
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: vaultKey,
            salt: Data(label.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}
