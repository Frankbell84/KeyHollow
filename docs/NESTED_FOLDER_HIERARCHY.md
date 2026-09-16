# Nested Folder Hierarchy

Nested Folder Hierarchy is the next file-management refinement after the
physically accepted Build 48 catalog search and sorting baseline. The mapping
and compatibility contract below were completed before implementation began.
Implementation remains isolated on its feature branch and does not authorize a
build-number change, upload, merge, or tester expansion.

## Product boundary

- Allow a folder to contain child folders and mixed Photos-origin and
  Files-origin items.
- Keep search and sorting scoped to the currently open folder. Recursive search
  is deliberately excluded from the first hierarchy release.
- Keep folders ahead of items, retain the existing normalized grid, and add a
  bounded breadcrumb path for navigation.
- Continue rejecting `.khvault` files as ordinary vault content. A portable
  backup is never an active vault inside another vault.
- Do not change photo storage, general-file storage, vault credentials,
  cryptography, media loading, or the portable archive format.

## Current-code mapping

| Concern | Current owner | Required additive change |
| --- | --- | --- |
| Folder records, item membership, encrypted manifest | `KeyHollowFolderPresentationAddOn` | Add versioned parent relationships and transactional hierarchy mutations |
| Cycle, depth, descendant, breadcrumb, and destination policy | New `KeyHollowNestedFolderAddOn` | Pure bounded value-policy module with no storage or key access |
| Grid, search, sort, selection, move, and navigation wiring | Application composition plus `KeyHollowGalleryUI` | Build one immutable current-location snapshot and route folder actions through the existing stores |
| Photos and general files | Existing protected stores | No change; encrypted payloads never move when presentation membership changes |
| Portable `.khvault` backup | `KeyHollowTransferCore` | No format change; existing disclosure that folders are not preserved remains authoritative |

The new policy add-on may receive only immutable folder identifiers, bounded
display names, parent identifiers, timestamps, and stable ordinals. It must not
receive a vault identifier, key, session, encrypted manifest, record, store,
URL, ciphertext, plaintext payload, thumbnail bytes, archive parser, or
mutation closure.

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
- No portable archive version changes in this phase. Backup and restore retain
  their current, explicit root-level restore behavior.

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
   concurrency, warnings as errors, and architecture allowlists.
3. Add pure hierarchy tests covering cycles, depth, sibling collisions,
   deterministic breadcrumbs, moves, deletion reparenting, and hostile input.
4. Add encrypted-store tests covering v1 compatibility, v2 migration,
   cancellation, commit-state recovery, size limits, and access revocation.
5. Add application tests for search, sort, selection, media queues, folder
   moves, lock/background, vault replacement, and add-on removal.
6. Pass every gate in `docs/ADDON_RELEASE_POLICY.md`, followed by a separately
   authorized Internal TestFlight build and physical-device acceptance.

## Deliberate exclusions

Recursive/global search, folder metadata editing beyond rename, favorites,
albums, cross-vault references, active vaults inside vaults, folder-aware
portable backups, cloud sync, sharing services, analytics, and account systems
remain separate proposals. They must not be folded into this phase.
