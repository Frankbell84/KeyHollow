# Nested Folder Hierarchy

Nested Folder Hierarchy was the next file-management refinement after the
physically accepted Build 48 catalog search and sorting baseline. The mapping
and compatibility contract below were completed before implementation began.
The hierarchy and Files-style nested move picker are now part of accepted
Internal Build 53 source `1bf0907f4713b925a777240ecb5ece61b530d5bc`.
Builds 49 through 52 remain historical unaccepted candidates because of later
release-blocking presentation or lifecycle defects; Build 52 specifically was
rejected after its background-video re-entry failure. Build 48 is retained as
the prior accepted rollback/comparison reference. No Family, external
TestFlight, App Store expansion, or portable-archive format change is authorized
by the hierarchy work or by Build 53 acceptance.

That remains the historical Build 53 boundary. Folder-aware portable backup v2
is a separately authorized follow-on. It consumes Folder Presentation's
already-authenticated hierarchy through application composition and does not
expand Nested Folder's responsibilities.

## Product boundary

- Allow a folder to contain child folders and mixed Photos-origin and
  Files-origin items.
- Keep search and sorting scoped to the currently open folder. Recursive search
  is deliberately excluded from the first hierarchy release.
- Keep folders ahead of items, retain the existing normalized grid, and add a
  bounded breadcrumb path for navigation.
- Continue rejecting `.khvault` files as ordinary vault content. A portable
  backup is never an active vault inside another vault.
- In the Build 53 hierarchy phase, do not change photo storage, general-file
  storage, vault credentials, cryptography, media loading, or the portable
  archive format. The later portable-backup feature is governed independently
  by `FOLDER_AWARE_PORTABLE_BACKUP.md`.

## Current-code mapping

| Concern | Current owner | Required additive change |
| --- | --- | --- |
| Folder records, item membership, encrypted manifest | `KeyHollowFolderPresentationAddOn` | Add versioned parent relationships, independently validate every persisted hierarchy, and commit transactional hierarchy mutations |
| Breadcrumb, current-location navigation, descendant, and destination policy | New `KeyHollowNestedFolderAddOn` | Pure bounded metadata-policy module with no manifest, storage, key, or mutation access |
| Grid, search, sort, selection, move, and navigation wiring | Application composition plus `KeyHollowGalleryUI` | Map FolderPresentation records into neutral NestedFolder descriptors, build one immutable current-location snapshot, and route mutations back through FolderPresentation |
| Photos and general files | Existing protected stores | No change; encrypted payloads never move when presentation membership changes |
| Build 53 portable `.khvault` behavior | `KeyHollowTransferCore` | No format change in the hierarchy release; catalog v1-v3 restore content at root |
| Folder-aware portable-backup follow-on | Application composition plus Folder Presentation and `KeyHollowTransferCore` | The app bridge validates and supplies opaque folder-manifest ciphertext; TransferCore owns neutral catalog/staging mechanics and imports neither folder add-on |

The new policy add-on may receive only immutable folder identifiers, bounded
display names, parent identifiers, timestamps, and stable ordinals. It must not
receive a vault identifier, key, session, encrypted manifest, record, store,
URL, ciphertext, plaintext payload, thumbnail bytes, archive parser, or
mutation closure. `KeyHollowFolderPresentationAddOn` and
`KeyHollowNestedFolderAddOn` do not import each other. FolderPresentation owns
its persisted-manifest validation independently; the application composition
layer performs the one-way mapping into NestedFolder metadata for UI policy and
sends approved mutations back through the FolderPresentation store.

## Compatibility contract

The accepted manifest is version one and contains flat folder records plus item
memberships. Hierarchy support must use an explicitly versioned manifest
revision rather than silently adding fields that an older build could decode,
ignore, and later overwrite.

- Current builds decode version-one manifests as a root-only hierarchy.
- A hierarchy-bearing save writes version two only after validation succeeds.
- Version one remains writable while no parent relationships exist, avoiding an
  unnecessary migration merely because the app was opened or an item was moved.
- Build 48 encountering a future version-two folder manifest must fail closed
  in the presentation layer. The protected photo and general-file stores remain
  operational and unchanged; an older build must never flatten or rewrite the
  hierarchy unknowingly.
- No portable archive version changes occurred in the Build 53 hierarchy
  phase. Catalog v1-v3 therefore retain their explicit root-level restore
  behavior.

The separately versioned follow-on adds catalog v4 inside the unchanged
version-1 outer archive and payload framing. Catalog v4 carries exactly one
authenticated Folder Presentation manifest at `folders/manifest.khm`.
Application composition validates its hierarchy and cross-checks neutral
photo/general-file membership references; TransferCore treats the manifest as
opaque ciphertext. Folder thumbnail caches are excluded. Nested Folder remains
a pure UI-policy module with no archive, key, store, or persistence access.

Before implementation, tests must prove version-one decoding, deterministic
version-two encoding, failed-migration rollback, interrupted commit recovery,
and preservation of a previously valid authenticated manifest.

## Bounded hierarchy rules

- Maximum folder count remains 10,000.
- Maximum nesting depth is 8, including the first folder below the vault root.
- Each folder has at most one parent; the vault root is represented by `nil`,
  never by a synthetic persisted folder.
- Every parent must exist. Self-parenting, cycles, orphan edges, duplicate
  folder identifiers, and paths exceeding the depth limit are invalid.
- Names remain normalized and bounded to 80 characters. Duplicate-name checks
  apply among siblings, not across unrelated branches.
- Traversal is iterative and bounded by the folder count. No unbounded recursive
  walk is permitted for validation, breadcrumbs, deletion, or destination lists.
- Moving a folder into itself or any descendant is rejected before persistence.

## Mutation and deletion behavior

- Moving files or photos keeps the existing single authenticated membership
  update; payload ciphertext does not move.
- Moving a folder changes only its validated parent relationship.
- Creating a child folder validates the destination, sibling-name uniqueness,
  resulting depth, encoded-manifest size, and access capability before commit.
- Deleting a folder never deletes content. Its direct items return to the
  deleted folder's parent, and its direct child folders are reparented there.
  The complete change is one authenticated transaction or it does not publish.
- Removing the final hierarchy edge may safely return the manifest to the flat
  representation only if rollback and interruption tests prove the transition.

## Search, sorting, selection, and media behavior

- Build 47 search filters only the current location.
- Build 48 sorting orders the current location and continues to keep folders
  ahead of items.
- `Select All` selects only visible content items. Folder tiles are not silently
  included in export, deletion, or media queues.
- Image/video navigation follows the visible ordered item snapshot and never
  crosses a folder boundary.
- Moving selected items offers only valid destinations and excludes no-op or
  inaccessible paths.

## Required implementation and release gates

1. Start an isolated feature branch from exact accepted Build 48 source
   `fd2f39f079f3dca853f09e2d67caa8a5cd2eab5c`.
2. Add the independently compiled `KeyHollowNestedFolderAddOn` with strict
   concurrency, warnings as errors, architecture allowlists, and no dependency
   edge to or from `KeyHollowFolderPresentationAddOn`.
3. Add FolderPresentation persistence tests for cycles, depth, sibling
   collisions, deletion reparenting, and hostile manifests, plus pure
   NestedFolder policy tests for deterministic breadcrumbs and destinations.
4. Add encrypted-store tests covering v1 compatibility, v2 migration,
   cancellation, commit-state recovery, size limits, and access revocation.
5. Add application tests for search, sort, selection, media queues, folder
   moves, lock/background, vault replacement, and add-on removal.
6. Pass every gate in `docs/ADDON_RELEASE_POLICY.md`, followed by a separately
   authorized Internal TestFlight build and physical-device acceptance.

## Deliberate exclusions

Recursive/global search, folder metadata editing beyond rename, favorites,
albums, cross-vault references, active vaults inside vaults, cloud sync,
sharing services, analytics, and account systems remain separate proposals.
Folder-aware portable backup is also separate from the accepted hierarchy
phase, but now has its own isolated implementation contract in
`FOLDER_AWARE_PORTABLE_BACKUP.md`; it must not be treated as a Nested Folder
feature.
