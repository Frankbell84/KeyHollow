import CryptoKit
import Foundation
import KeyHollowCryptoCore
import KeyHollowFolderPresentationAddOn
import KeyHollowTransferCore

/// App-composition adapter between the independently compiled folder
/// presentation add-on and TransferCore's opaque folder-manifest seam.
/// Presentation thumbnails are disposable caches and are never archived.
struct FolderPresentationPortableTransferBridge: PortableVaultFolderContentProviding {
    private let access: (any VaultFolderPresentationCryptographicAccess)?

    init(access: (any VaultFolderPresentationCryptographicAccess)? = nil) {
        self.access = access
    }

    func authenticatedArchiveInventory(
        vaultID: UUID,
        sourceRootOverride: URL?,
        validPhotoIDs: Set<UUID>,
        validGeneralFileIDs: Set<UUID>
    ) async throws -> PortableVaultFolderArchiveInventory {
        guard let access, access.vaultID == vaultID else {
            throw VaultFolderPresentationStore.StoreError.accessMismatch
        }
        try access.checkAccess()
        let storageRoot = try Self.storageRoot(
            vaultID: vaultID,
            override: sourceRootOverride
        )
        guard FileManager.default.fileExists(atPath: storageRoot.path) else {
            return .empty
        }
        let store = try VaultFolderPresentationStore(
            vaultID: vaultID,
            access: access,
            storageRoot: storageRoot
        )
        let manifest = try await store.loadManifest()
        guard !manifest.folders.isEmpty else {
            guard manifest.memberships.isEmpty else {
                throw VaultFolderPresentationStore.StoreError.invalidManifest
            }
            return .empty
        }

        let references = try Self.references(
            in: manifest,
            validPhotoIDs: validPhotoIDs,
            validGeneralFileIDs: validGeneralFileIDs
        )
        let portableManifest = VaultFolderPresentationManifest(
            version: manifest.version,
            folders: manifest.folders,
            memberships: manifest.memberships,
            thumbnails: []
        )
        let plaintext = try JSONEncoder().encode(portableManifest)
        guard plaintext.count <= VaultFolderPresentationStore.maximumManifestByteCount else {
            throw VaultFolderPresentationStore.StoreError.invalidManifest
        }
        let ciphertext = try access.seal(plaintext, for: .manifest)
        return PortableVaultFolderArchiveInventory(
            manifestCiphertext: ciphertext,
            folderCount: portableManifest.folders.count,
            membershipCount: portableManifest.memberships.count,
            referencedItems: references
        )
    }

    func validateStagedContent(
        at rootURL: URL,
        sourceVaultID: UUID,
        vaultKey: SymmetricKey,
        validPhotoIDs: Set<UUID>,
        validGeneralFileIDs: Set<UUID>
    ) async throws -> PortableVaultFolderValidation {
        let store = try VaultFolderPresentationStore(
            vaultID: sourceVaultID,
            access: PortableFolderPresentationAccess(
                vaultID: sourceVaultID,
                vaultKey: vaultKey
            ),
            storageRoot: rootURL
        )
        let manifest = try await store.loadManifest()
        guard !manifest.folders.isEmpty,
              manifest.thumbnails.isEmpty else {
            throw VaultFolderPresentationStore.StoreError.invalidManifest
        }
        let references = try Self.references(
            in: manifest,
            validPhotoIDs: validPhotoIDs,
            validGeneralFileIDs: validGeneralFileIDs
        )
        return PortableVaultFolderValidation(
            folderCount: manifest.folders.count,
            membershipCount: manifest.memberships.count,
            referencedItems: references
        )
    }

    private static func references(
        in manifest: VaultFolderPresentationManifest,
        validPhotoIDs: Set<UUID>,
        validGeneralFileIDs: Set<UUID>
    ) throws -> Set<PortableVaultFolderItemReference> {
        var references = Set<PortableVaultFolderItemReference>()
        references.reserveCapacity(manifest.memberships.count)
        for membership in manifest.memberships {
            let reference: PortableVaultFolderItemReference
            switch membership.item.kind {
            case .photo:
                guard validPhotoIDs.contains(membership.item.id) else {
                    throw VaultFolderPresentationStore.StoreError.invalidManifest
                }
                reference = PortableVaultFolderItemReference(
                    kind: .photo,
                    id: membership.item.id
                )
            case .generalFile:
                guard validGeneralFileIDs.contains(membership.item.id) else {
                    throw VaultFolderPresentationStore.StoreError.invalidManifest
                }
                reference = PortableVaultFolderItemReference(
                    kind: .generalFile,
                    id: membership.item.id
                )
            }
            guard references.insert(reference).inserted else {
                throw VaultFolderPresentationStore.StoreError.invalidManifest
            }
        }
        return references
    }

    private static func storageRoot(vaultID: UUID, override: URL?) throws -> URL {
        if let override { return override.standardizedFileURL }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent(
                "KeyHollow/FolderPresentationData",
                isDirectory: true
            )
            .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
            .standardizedFileURL
    }
}

private struct PortableFolderPresentationAccess: VaultFolderPresentationCryptographicAccess {
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
