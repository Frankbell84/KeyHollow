# Folder-aware portable backup v2

Status: implementation contract for the isolated folder-aware portable-backup
feature. Automated tests and the physical-device acceptance work in
`DEVICE_TEST_PLAN.md` remain required before release.

“V2” names the product capability, not the public archive container. The
`.khvault` magic, public header, container version, content-chunk framing, and
payload-prefix version remain exactly version 1. Folder preservation is an
authenticated inner-catalog extension.

## Compatibility contract

| Authenticated catalog | Folder behavior |
| --- | --- |
| v1 | Legacy photo-only archive. Restore supported; recovered items appear at vault root. |
| v2 | Legacy photo/general-file archive. Restore supported; recovered items appear at vault root. |
| v3 | Bounded photo/general-file archive. Restore supported; recovered items appear at vault root. |
| v4 | Requires exactly one authenticated `folderManifest` entry at `folders/manifest.khm`; restore preserves its validated hierarchy and item membership. |

New exports use catalog v4 when a nonempty Folder Presentation hierarchy is
included. A source with no folders and no folder memberships has nothing to
preserve and may continue to use catalog v3. Catalog v1-v3 archives never
infer hierarchy from filenames or other unauthenticated metadata. Their
contents restore at root.

## Ownership and dependency boundary

| Concern | Owner |
| --- | --- |
| Folder records, parent relationships, item membership, manifest validation, and persistent folder store | `KeyHollowFolderPresentationAddOn` |
| Hierarchy navigation and destination policy | `KeyHollowNestedFolderAddOn` |
| Authenticated photo and general-file UUID inventories | Their existing stores and application bridges |
| Translation between the folder store and portable transfer | Application composition through `FolderPresentationPortableTransferBridge` |
| Archive framing, catalog roles and limits, opaque ciphertext transport, staging, verification orchestration, and restore journal | `KeyHollowTransferCore` |

TransferCore must not import Folder Presentation or Nested Folder. Its folder
seam consists only of opaque authenticated manifest ciphertext, sanitized
counts, and neutral `(photo | generalFile, UUID)` item references. Nested
Folder owns no persistence and does not participate in export or restore.

## Export contract

1. Authenticate the selected unlocked vault and obtain the already-validated
   photo and general-file UUID inventories.
2. At the application boundary, load the authenticated Folder Presentation
   manifest from
   `Application Support/KeyHollow/FolderPresentationData/<source-vault-UUID>`.
3. Reuse the folder store's hierarchy validation and require every membership
   to reference an authenticated archived photo or general-file UUID.
4. Remove the `thumbnails` collection. Folder thumbnails are derived cache,
   not user-authored hierarchy, and must never enter a portable backup.
5. Encode the portable manifest within the 8 MiB plaintext limit and reseal it
   with the existing Folder Presentation manifest cryptographic domain. Pass
   only its ciphertext, sanitized counts, and neutral references to
   TransferCore.
6. Emit catalog v4 with exactly one `folderManifest` entry at the canonical
   storage name `folders/manifest.khm`, then reopen and fully self-verify the
   completed archive before it can be shared.

Any invalid hierarchy, dangling or unarchived membership, duplicate reference,
size violation, source mutation, authentication failure, or self-verification
failure aborts the export and removes temporary output. The source vault and
its Folder Presentation store remain unchanged.

## Verification and restore validation

The outer reader first authenticates the unchanged version-1 archive framing
and every content chunk. It then validates the authenticated catalog, canonical
storage names, declared lengths, and SHA-256 digests before the staged payload
is exposed to vault-level validation.

For catalog v4, application composition supplies the folder bridge. The bridge
opens the staged manifest using access derived from the restored vault key,
loads it through `VaultFolderPresentationStore`, and requires:

- a valid, bounded, acyclic hierarchy;
- an empty `thumbnails` collection;
- unique memberships whose item kind and UUID exist in the authenticated photo
  or general-file inventories; and
- counts and neutral references matching the catalog validation result.

A v4 archive cannot be verified or restored without this bridge. The reader
does not silently discard folder data or downgrade the archive. Verification
reports may expose only authenticated folder and membership counts; they must
not expose folder names, folder identifiers, item identifiers, keys, paths,
manifest plaintext, or install capability.

## Transactional installation and rollback

Restore always creates a fresh destination vault identifier and preserves the
restored vault key inside a new device-bound LowKey credential. Before commit,
the installer preflights that none of the three candidate destination roots
exists, even when an archive does not carry one of the optional content types.
This matches the journal's fail-closed rollback scope and prevents recovery
from touching preexisting data:

- the photo-vault root for the fresh vault identifier;
- `GeneralFileData/<fresh-vault-UUID>`; and
- `FolderPresentationData/<fresh-vault-UUID>`.

After immediate staged-payload revalidation, one authenticated rollback journal
covers the complete operation. The staged supplemental directory, folder
directory, and remaining photo root are moved to their corresponding final
locations without replacement. The new credential is published only after all
required ciphertext moves succeed, and the journal is removed last.

Cancellation or failure before commit removes staging. A rejected LowKey does
not consume the validated restore. A failure during commit, credential
publication, or startup recovery removes every destination root owned by that
transaction and removes only the matching new credential. Existing vaults and
unrelated credentials remain unchanged. A forged or malformed journal fails
closed rather than deleting paths named by untrusted data.

## Limits and security properties

Catalog v4 keeps the current 16 MiB catalog and 10 GiB declared-ciphertext
ceilings. It permits at most 10,000 folders, 20,000 unique memberships, and an
8 MiB folder-manifest plaintext (plus the fixed inner AES-GCM overhead). With
the existing photo and general-file ceilings, the maximum catalog-entry count
is 30,003.

Folder names and membership are protected twice in transit: first by the
existing Folder Presentation authenticated encryption and then by the archive
content encryption. The public header contains no folder metadata. The folder
manifest's canonical path and role exist only inside the encrypted catalog.
No plaintext hierarchy, media, filenames, recovery credential, or key may be
written to logs, previews, ordinary temporary storage, or reports.

## Automated coverage map

- `PortableArchivePayloadTests` owns catalog-v4 selection, the canonical folder
  role/path, v1-v3 rejection of folder entries, current bounds, and the rule
  that a v4 export cannot fall back to a legacy catalog.
- `FolderPresentationPortableTransferBridgeTests` owns authenticated hierarchy
  round trip, neutral membership mapping, thumbnail-cache removal, dangling
  membership rejection, and the empty/missing-store compatibility path.
- `EncryptedVaultTransferCoordinatorTests` owns end-to-end nested mixed-content
  round trip, missing-bridge cleanup, destination collision, staged mutation,
  legacy preflight behavior, self-verification, and transactional restore.
- `PortableVaultVerificationReportTests` and
  `VaultBackupVerificationAddOnTests` own verify-and-discard cleanup, sanitized
  report shape, and the distinct v4-preserved versus v1-v3-root compatibility
  disclosures.

## Required acceptance coverage

- round-trip empty folders, duplicate names under different parents, the
  maximum supported nesting depth, root items, and mixed photo/general-file
  memberships;
- verify that no Folder Presentation thumbnail cache enters the archive and
  that destination thumbnails regenerate normally;
- restore maintained v1, v2, and v3 fixtures with all recovered items at root;
- reject a missing, duplicate, misnamed, oversized, tampered, or undecryptable
  v4 folder manifest and every dangling, wrong-kind, duplicate, or unarchived
  membership;
- demonstrate that read-only verification returns only sanitized counts and
  leaves no staging, credential, journal, installed vault, or source mutation;
- force termination at every directory-move, credential-publication, and
  journal-removal boundary and prove recovery converges to either a complete
  new vault or no new vault; and
- keep independent module-boundary checks proving TransferCore imports neither
  Folder Presentation nor Nested Folder.
