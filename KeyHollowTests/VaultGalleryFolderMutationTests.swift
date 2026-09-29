import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowCryptoCore
import KeyHollowFolderPresentationAddOn

final class VaultGalleryFolderMutationTests: XCTestCase {
    @MainActor
    func testCreateRenameAndReparentReturnFreshMetadataWithoutReplacingIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let created = try await VaultGalleryFolderMutation.saveName(
            name: "Parent", renaming: nil, parentID: nil
        ).perform(using: fixture.store)
        let parent = try XCTUnwrap(created.folders.first)
        let nested = try await VaultGalleryFolderMutation.saveName(
            name: "Child", renaming: nil, parentID: parent.id
        ).perform(using: fixture.store)
        let child = try XCTUnwrap(nested.folders.first { $0.parentID == parent.id })
        let renamed = try await VaultGalleryFolderMutation.saveName(
            name: "Renamed", renaming: child.id, parentID: nil
        ).perform(using: fixture.store)
        let renamedChild = try XCTUnwrap(renamed.folders.first { $0.id == child.id })
        XCTAssertEqual(renamedChild.name, "Renamed")
        XCTAssertEqual(renamedChild.parentID, parent.id)
        XCTAssertEqual(renamedChild.createdAt, child.createdAt)

        let moved = try await VaultGalleryFolderMutation.moveFolder(
            id: child.id, parentID: nil
        ).perform(using: fixture.store)
        XCTAssertNil(moved.folders.first { $0.id == child.id }?.parentID)
        XCTAssertEqual(moved.folders.count, 2)
    }

    @MainActor
    func testTypedItemAndBatchMovesThenFolderDeletionPreserveContentsAndParentPlacement() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let parent = try await fixture.store.createFolder(named: "Parent")
        let child = try await fixture.store.createFolder(named: "Child", in: parent.id)
        let descendant = try await fixture.store.createFolder(named: "Descendant", in: child.id)
        let shared = UUID()
        let photo = VaultPresentedContentReference(kind: .photo, id: shared)
        let file = VaultPresentedContentReference(kind: .generalFile, id: shared)

        let single = try await VaultGalleryFolderMutation.moveItem(
            photo, folderID: child.id
        ).perform(using: fixture.store)
        XCTAssertEqual(single.memberships, [.init(item: photo, folderID: child.id)])
        let batch = try await VaultGalleryFolderMutation.moveSelection(
            [photo, file], folderID: child.id
        ).perform(using: fixture.store)
        XCTAssertEqual(Set(batch.memberships.map(\.item)), [photo, file])
        XCTAssertTrue(batch.memberships.allSatisfy { $0.folderID == child.id })

        let deleted = try await VaultGalleryFolderMutation.deleteFolder(id: child.id)
            .perform(using: fixture.store)
        XCTAssertFalse(deleted.folders.contains { $0.id == child.id })
        XCTAssertEqual(deleted.folders.first { $0.id == descendant.id }?.parentID, parent.id)
        XCTAssertEqual(Set(deleted.memberships.map(\.item)), [photo, file])
        XCTAssertTrue(deleted.memberships.allSatisfy { $0.folderID == parent.id })
        let root = try await VaultGalleryFolderMutation.moveSelection([photo, file], folderID: nil)
            .perform(using: fixture.store)
        XCTAssertTrue(root.memberships.isEmpty)
        XCTAssertEqual(root.folders, deleted.folders)
    }

    @MainActor
    func testMissingDestinationAndDuplicateNameKeepTheEncryptedManifestIntact() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let folder = try await fixture.store.createFolder(named: "Existing")
        let before = try Data(contentsOf: fixture.manifestURL)
        let invalidMove = VaultGalleryFolderMutation.moveItem(
            .init(kind: .photo, id: UUID()), folderID: UUID()
        )
        do {
            _ = try await invalidMove.perform(using: fixture.store)
            XCTFail("A missing destination must reject the move")
        } catch {
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .folderNotFound)
            XCTAssertEqual(invalidMove.failureMessage(for: error),
                           "The item could not be moved. Protected vault contents were not changed.")
        }
        do {
            _ = try await VaultGalleryFolderMutation.saveName(
                name: folder.name, renaming: nil, parentID: nil
            ).perform(using: fixture.store)
            XCTFail("A duplicate sibling name must be rejected")
        } catch {
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .duplicateFolderName)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.manifestURL), before)
    }

    @MainActor
    func testCanceledTaskCannotCommitOrReturnAFreshManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.createFolder(named: "Existing")
        let before = try Data(contentsOf: fixture.manifestURL)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VaultGalleryFolderMutation.saveName(
                name: "Canceled", renaming: nil, parentID: nil
            ).perform(using: fixture.store)
        }
        do {
            _ = try await task.value
            XCTFail("Canceled mutations must propagate cancellation")
        } catch is CancellationError {
            // The composition task must retain its cancellation-specific exit.
        }
        XCTAssertEqual(try Data(contentsOf: fixture.manifestURL), before)
    }

    @MainActor
    func testRevokedAccessCannotWriteFolderMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let existing = try await fixture.store.createFolder(named: "Existing")
        let before = try Data(contentsOf: fixture.manifestURL)
        fixture.access.revoke()
        do {
            _ = try await VaultGalleryFolderMutation.deleteFolder(id: existing.id)
                .perform(using: fixture.store)
            XCTFail("A revoked store must not accept the operation")
        } catch AccessError.revoked {
            // Expected; the adapter must use the authenticated store's checks.
        }
        XCTAssertEqual(try Data(contentsOf: fixture.manifestURL), before)
    }

    func testOperationSpecificFailureMessagesPreserveExistingRecoveryGuidance() {
        let save = VaultGalleryFolderMutation.saveName(name: "Name", renaming: nil, parentID: nil)
        let move = VaultGalleryFolderMutation.moveFolder(id: UUID(), parentID: nil)
        let delete = VaultGalleryFolderMutation.deleteFolder(id: UUID())
        let cases: [(VaultGalleryFolderMutation, VaultFolderPresentationStore.StoreError, String)] = [
            (save, .duplicateFolderName, "A folder with that name already exists."),
            (save, .invalidFolderName, "Use a folder name between 1 and 80 characters."),
            (save, .folderDepthLimitReached, "This folder would exceed the maximum folder depth."),
            (move, .duplicateFolderName, "That location already contains a folder with this name."),
            (move, .folderDepthLimitReached, "That move would exceed the maximum folder depth."),
            (delete, .duplicateFolderName, "Move or rename the conflicting child folder before deleting this folder."),
            (delete, .folderDepthLimitReached, "The folder could not be removed without exceeding the folder depth limit."),
        ]
        for (mutation, error, expected) in cases {
            XCTAssertEqual(mutation.failureMessage(for: error), expected)
        }
        XCTAssertEqual(save.failureMessage(for: AccessError.revoked), "The encrypted folder could not be saved.")
        XCTAssertEqual(move.failureMessage(for: AccessError.revoked),
                       "The folder could not be moved. Protected vault contents were not changed.")
        XCTAssertEqual(delete.failureMessage(for: AccessError.revoked),
                       "The folder could not be deleted. Protected vault contents were not changed.")
        XCTAssertEqual(VaultGalleryFolderMutation.moveSelection([], folderID: nil)
            .failureMessage(for: AccessError.revoked),
            "The selected items could not be moved. Protected vault contents were not changed.")
    }

    private struct Fixture {
        let root: URL
        let access: TestAccess
        let store: VaultFolderPresentationStore
        var manifestURL: URL { root.appendingPathComponent("manifest.khm") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("GalleryFolderMutation-\(UUID())", isDirectory: true)
            access = TestAccess()
            store = try VaultFolderPresentationStore(
                vaultID: access.vaultID, access: access, storageRoot: root
            )
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    private enum AccessError: Error { case revoked }

    private final class TestAccess: VaultFolderPresentationCryptographicAccess, @unchecked Sendable {
        let vaultID = UUID()
        private let key = SymmetricKey(size: .bits256)
        private let lock = NSLock()
        private var revoked = false

        func checkAccess() throws {
            lock.lock()
            defer { lock.unlock() }
            if revoked { throw AccessError.revoked }
        }

        func revoke() {
            lock.lock()
            revoked = true
            lock.unlock()
        }

        func seal(_ plaintext: Data, for purpose: VaultFolderPresentationKeyPurpose) throws -> Data {
            try checkAccess()
            return try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
        }

        func open(_ ciphertext: Data, for purpose: VaultFolderPresentationKeyPurpose) throws -> Data {
            try checkAccess()
            return try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
        }

        private func derivedKey(for purpose: VaultFolderPresentationKeyPurpose) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: key,
                salt: Data(purpose.cryptographicDomain.utf8), info: Data(), outputByteCount: 32)
        }
    }
}
