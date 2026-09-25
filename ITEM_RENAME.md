# R1: rename existing items

Candidate implementation, not yet device-accepted. Long-press a gallery item
and select Rename. Files and videos expose their basename with the original
final extension shown separately. Photos edit their stored display name. Import
remains immediate; renaming does not touch source originals or media playback.
This deliberately expands the earlier settings-only file editing surface.

## Ownership and concurrency

The separately compiled ItemRename add-on receives only strings, bindings and
actions. The app's VaultItemRenameCoordinator captures the session epoch and
registers one sensitive task for preparation, editing, mutation and refresh.
The store owns the sole persisted name; there is no new schema, root, key,
catalog version, title override, tag store or network dependency.

Each owner authenticates a manifest and hashes exactly that ciphertext into
an opaque, nonpersistent snapshot. Rename rereads under the existing shared
manifest transaction lock, compares the snapshot, resolves the canonical item,
and replaces only its name. Any intervening owner-manifest write conflicts,
including unrelated imports. A deleted item cannot be resurrected. Photo cache
generations are invalidated through the existing mutation path.

Validation rejects empty/period-only names, control characters, separators,
colons and names longer than 180 UTF-8 bytes, including the retained extension.
No edit is silently truncated. Historical long names remain readable. Storage
also validates edits independently of the UI, including exact file extension
preservation. Duplicate display names are permitted; existing export deduplication
chooses safe distinct filenames. File type metadata stays authoritative.

## Cancellation and durable outcome

Before replacement, sealing must succeed through the live capability. The last
cancellation/access check immediately before the encrypted commit path is the
authorization point: revocation before this check prevents replacement. An
already authorized encrypted replacement can finish after later revocation.
The atomic filesystem replacement is the durable commit point. The session's
lock barrier drains the task before another session or deletion can proceed.

Revocation clears editor bindings synchronously, finishes the input stream and
cancels the task. Preparation, save and refresh check the captured epoch and
capability; late results cannot publish into a different unlock. User cancellation
ends editing; Save disables cancellation while its commit is in flight. Lock
always remains effective. A cancellation label is never proof of rollback.

Pre-commit failures preserve the old manifest. If replacement reports failure,
the existing authenticated durable-winner recovery distinguishes a committed
name from a failed attempt. An unreadable winner reports indeterminate state,
retains content, and asks for lock/reopen; it never deletes blobs speculatively.

## Verification

`VaultItemRenameTests` covers validation/Unicode/legacy names, file type and byte
preservation, safe duplicate exports, stale two-store edits, deletion, pre/post
replacement faults and unreadable winners. Real store operations exercise
revocation before and after replacement. Coordinator tests cover invalid-name
retry, cancellation, editing lock, delayed preparation, vault switching and late
commit completion. These are test definitions until native CI passes.

The transfer suite separately exports, verifies and installs a nested-folder
archive containing renamed photo/file records. It checks fresh vault identity,
names, bytes and hierarchy alongside the existing legacy v1-v4 regression suite.

Physical iPhone acceptance remains required:

- Rename a photo, portrait video, landscape video and document in a nested folder.
- Search for the new name and use both name sort directions.
- Open photos/videos and close with Done or the accepted content swipe.
- Move an item, export a document, then lock/reopen and check names and locations.
- Begin an edit, background the app, unlock and verify the unsaved draft is gone.
- Export, verify and restore a test backup on the same phone; check new names,
  media and folders. Keep the original vault until inspection is complete.

This does not complete the deferred two-phone transfer or broader failure matrix.
