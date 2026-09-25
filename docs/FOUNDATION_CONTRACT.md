# Content, module, and lifecycle contract

Design completed 2026-09-25 (America/Port-au-Prince) against Build 58 source
`36b63e06fae92615fc5b24988ef123355f8b4bf0`. This is a documentation design,
not an implemented format or a claim of completed feature tests.

It resolves the shared questions identified in the
[dependency plan](ROADMAP_DEPENDENCY_PLAN.md). Product proposals remain those in
the [user's addendum](ARCHITECTURE_ADDENDUM_SOURCE.md). Feature selection below
is an engineering recommendation under the stated preference for build quality.

## Outcome

1. Keep existing content identity and title ownership. Do not migrate current
   data to create a general framework.
2. Introduce a bounded module inventory only with the first feature that adds
   separately owned persistent data. Its backup, restore, deletion and lock
   behavior must be delivered together.
3. Keep descriptive metadata, enforced access policy and recipient delivery
   separate. Titles/tags are not prerequisites for protected sharing.
4. Prefer one complete local change without a format migration as the first
   implementation: **rename existing items while preserving file type**.
   Tags are excluded from that first candidate. This recommendation follows
   the comparison below; it is not the addendum's prescribed order.

The shared design is finished at the ownership/protocol-boundary level. A new
wire encoding, numeric catalog version, backend, identity protocol and policy
semantics are intentionally not allocated until their actual consumer is
selected. None is needed for the recommended rename-only candidate.

## D1 — content identity is scoped, typed and independent of names

The logical reference is `(vault instance, content owner, item UUID)` while
working locally. A portable reference inside one authenticated vault archive is
`(content owner, item UUID)`; the archive supplies the scope. A filename, path,
tag, content hash or account identity must never substitute for that reference.

| Operation | Identity rule |
| --- | --- |
| Rename / move / change descriptive metadata | Preserve owner, item UUID, blob names and encryption domain. Folder membership continues to reference the same item. |
| Duplicate | Allocate a new item UUID; copy/remap permitted metadata explicitly. A duplicate does not grant permissions forbidden by its source policy. This is a future feature. |
| Whole-vault restore | Retain archived item IDs and typed relationships within a fresh local vault instance. Do not embed the source installation's vault ID in new item references. |
| Restore the same archive twice | Produce independent local vault instances, even when contained item UUIDs and restored vault keys match. Neither is automatically a sync peer. |
| Later new content type | Register a stable, versioned owner identity; preserve current `photo` and `generalFile` meanings. Do not relabel existing video files as a new storage type. |
| Future sync / recipient delivery | Use separately designed replica, revision and delivery identities. Do not infer device trust or shared edit history from a restored vault key or equal item UUIDs. |

Keep the current enums and wire values until a new owner actually exists. A
future registry is compiled/allowlisted by the app; archives cannot load code,
register arbitrary handlers or choose filesystem roots. Mapping a new owner
into gallery/backup is an application-composition responsibility, not an import
from the cryptographic core into an add-on.

Evidence: `FolderPresentationModels.swift` and `PortableArchivePayload.swift`
use typed UUID references; `ValidatedPortableVaultRestore` in
`EncryptedVaultTransferCoordinator.swift` creates a fresh destination vault ID
while retaining the recovered vault key. These are current behaviors to preserve.

## D2 — each datum has one owner

| Datum | Authoritative owner / rule |
| --- | --- |
| Existing item's display name | Its existing photo or general-file record. Add a narrow mutation operation to that store; no second writable title in a metadata add-on. |
| Content type, blob identity and byte count | Existing content store. A display-name edit cannot change these or re-encrypt the payload. |
| Folder name and membership | FolderPresentation. Renaming an item is not a folder operation. |
| Future tags and descriptions | A separately encrypted metadata module keyed by D1 references. It may refer to content but cannot own its bytes or change access policy. |
| Search text and thumbnails | Derived values/cache, rebuilt from authorized owners. No new authoritative title or tag copy in the search module. |
| Access policy | A distinct authenticated policy owner with its own schema, authority and content/revision binding. User-editable tags/descriptions cannot grant permissions. |
| Integrity seal / history | Explicit revision/history responsibility. Ordinary AEAD authentication is not an assertion about author identity, historical order or the truth of content. |

For a future editor spanning name and tags, do not promise one atomic Save
across independent stores without a transaction. Prefer separate explicit
operations initially; if a combined Save is selected, design and test its
cross-owner transaction before exposing it. Neither option permits silent
partial success. A future title override requires a new product/design decision;
it is not part of this contract.

## D3 — extend portable storage only for a real new module

**Selected direction for a future persistent add-on:** retain existing catalog
v1-v4 decoding and existing photo/file/folder paths; extend a reviewed newer
catalog with a bounded, authenticated inventory of extra modules. Avoid a
separate ad hoc archive role and restore special case for every future add-on.
Do not rewrite legacy archives or lift their historical/current limits as part
of introducing a module.

The logical inventory entry contains a registered owner ID, module schema
version, bounded entry inventory and ciphertext byte counts/digests. Content
references belong to the module's authenticated manifest and are validated
against the authenticated content inventory. These are conceptual fields, not
an approved serialized schema. Choose the exact encoding/version and publish
test vectors in the first module PR before permitting that writer.

Rules for that first module implementation:

- All declared user-authored data and access policies are required. An unknown
  owner/schema or absent required handler fails verification/restore before
  installation. Do not introduce an "optional" flag that permits silent loss.
  Regenerable caches are excluded by their producer before export.
- Keep the existing public `.khvault` container/header version unless a separate
  reviewed need requires changing it. Adding catalog semantics alone does not
  justify changing cryptography or the file extension.
- Owner IDs map to fixed canonical entry names through trusted local code.
  Reject duplicate owners/entries, traversal, links, aliases, inconsistent
  counts, unreferenced payloads and dangling/wrong-kind item references.
- Bound the registry, each manifest/entry and the aggregate. Retain the current
  new-export ceilings (including 16 MiB catalog and 10 GiB aggregate ciphertext)
  unless separately justified. A module's allowance is part of the aggregate,
  not an extra allowance per handler. Preserve version-specific legacy limits.
- Every producer returns an immutable inventory or a revision that can be
  checked for source changes. Revalidate staged bytes and module relationships;
  fail/retry a changing source instead of publishing a mixed-generation result.
- Reopen and fully verify the completed export before exposing it for sharing.
  The source remains intact on rejection. Read-only verification uses the same
  validators but always discards staging and cannot install credentials.
- The first transport implementation must carry actual supported user data
  from a real module. No empty plugin framework, arbitrary extension loader,
  or migration of already valid blobs is required in advance.

Current evidence: `PortableArchivePayload.swift` accepts one supplemental
manifest and a dedicated v4 folder manifest; it is not yet this module system.
`GeneralFilePortableTransferBridge.swift` and
`FolderPresentationPortableTransferBridge.swift` show the existing composition
pattern to extend. Tags need this work if stored in the separate owner chosen
in D2. Renaming an existing display-name field does not.

## D4 — compatibility is directional

| Data and client combination | Required behavior |
| --- | --- |
| Existing vault / new rename-only implementation | Same models and on-disk versions. Existing encrypted records remain readable; only the chosen display-name value changes. |
| New rename-only backup / existing v1-v4-capable reader | Existing schema can represent the edit. Prove readability and name preservation with fixtures; do not claim an old binary was tested without running it. |
| Historical v1-v4 backup / new module-capable reader | Preserve existing decode, validation, bounds and root/folder behavior; missing undeclared new metadata means the old archive has none. |
| New module archive / Build 58 reader | The newer catalog must be rejected as unsupported rather than misread as v4. No implicit downgrade export that strips data or policy. |
| Known catalog / unknown declared owner or owner schema | Authenticate and reject without installation or modification. Keeping the original opaque archive is allowed; claiming a complete restore is not. |
| Old writer / newer local module data | Unsupported until proven preservation or an explicit write barrier exists. Successful decode alone is insufficient: old load-modify-save/delete/export may lose information. |

For a new local module root, an older app has no module-aware write barrier.
Do not promise safe downgrade over that installation. Preserve the prior binary
and pre-upgrade recovery material as a supported recovery route, and document
the limits of that route. A new client must validate required module presence;
it cannot quietly normalize a broken module away.

No change in this design renames `.khvault` to `.lowkey` or adds a format writer.

## D5 — installation and deletion cover every owned root

A new persistent module registers its trusted root resolver and validation/
cleanup participant in application composition. Transfer operates through
neutral, narrow interfaces; it does not import the module's implementation.
Untrusted archive names or journal fields cannot supply absolute target paths.

The restore sequence is:

1. Authenticate, bound and validate the archive and all declared modules.
2. Allocate a fresh destination vault instance. Preflight every destination
   root and credential condition before any installation side effect.
3. Durably record the transaction-owned destination roots using trusted root
   IDs, not paths provided by the archive. Version the journal when extending
   its semantics and continue to recover historical journals by their rules.
4. Revalidate staged bytes immediately before committing; install all required
   ciphertext without replacing existing roots.
5. Publish only the matching new credential after all required roots commit.
6. Finish the journal last. A failure or restart recovers/removes only that
   transaction's roots and matching credential. Unknown/forged journals fail
   closed; incomplete cleanup retains recoverable state rather than reporting
   that rollback succeeded.

Adding a module also requires vault-deletion cleanup after authorization,
revocation and task draining. The new root must not become an orphan just
because backup restore knows about it. Current evidence is the three-root
`PortableVaultRestoreTransactionJournal` and the deletion coordinator in
`VaultSession.swift`; a fourth root is a reviewed transaction extension.

## D6 — lock, mutation and error outcomes are explicit

- Capture the active vault capability and session epoch before presenting an
  editor. Resolve the requested typed item through its canonical owner at
  commit; never trust a stale UI record as the complete replacement record.
- Serialize read-modify-write using the owner's existing manifest transaction.
  Compare a nonpersistent opaque expected-state token derived from the
  authenticated manifest ciphertext snapshot to prevent stale edits overwriting
  another writer. This token is local optimistic concurrency, not a new
  persisted sync revision.
- Register sensitive work and editor cleanup with the existing session task/
  revocation mechanism. Revocation rejects new authorized operations and clears
  editor/search plaintext; late completion cannot publish into a later session.
- The implementation must specify the commit-versus-lock linearization point
  and prove it with barriers. An encrypted replacement already authorized and
  committed may survive a subsequent cancellation; a cancellation label must
  never be treated as proof that nothing reached disk. No new plaintext work
  may begin after revocation. Drain authorized in-flight work before another
  session can expose its results or vault deletion can remove its storage.
- Reuse durable-winner recovery when replace/move reports an error after
  committing. Return committed, not committed, conflict or indeterminate as
  appropriate. An indeterminate result retains data and reloads after valid
  unlock; it must not trigger destructive speculative rollback.
- Mutations preserve unrelated fields, existing cryptographic domains, blob
  paths, source originals and folder memberships. Apply size/encoding limits
  before serialization and allocation. Do not silently truncate an edit.

Evidence: both content stores already serialize manifest operations and inspect
the authenticated durable manifest after ambiguous replacement errors. Photo
storage also tracks cache generations. `VaultSession` supplies revocable
capabilities, sensitive tasks and a lock barrier. The new mutation must use
and test these behaviors rather than introducing an independent lifecycle.

## D7 — owner backup and restricted delivery are different products

The current backup restores a vault key and its content. It is an owner recovery
artifact, not a way to enforce recipient View Only access. A restricted recipient
must not receive the owner vault key or an unrestricted backup as the delivery
mechanism.

Before Direct Transfer/Protected View, design a recipient-specific content-key
envelope and authenticated binding of recipient/device, content revision and
policy version through a separate delivery service. Keep backup decoding intact.
Specify sender authorization, replay handling, device enrollment/revocation,
offline/time semantics and unsupported-policy rejection before implementation.
Local vault access stays account-free; account recovery does not silently confer
vault decryption. Advanced Transfer can move an owner-encrypted archive without
creating this recipient-policy system.

Policy enforcement must cover view, save, share, duplicate, backup/export and
creator/transfer routes. An unknown restriction denies the governed operation.
Content already legitimately revealed cannot be guaranteed uncopiable. Camera
detection, clock guarantees and experimental environment signals are not
established by this design; feature-specific platform/threat review remains
required. A label such as Maximum cannot promise unimplemented protection.

## Candidate comparison and first implementation recommendation

These comparisons use current code and the user's preference for build quality.
They are relative engineering assessments, not time estimates or user priorities.

| Candidate from the addendum | Added foundations needed now | Migration / test burden | Result |
| --- | --- | --- | --- |
| Edit existing item names (§3) | Narrow store mutation, expected-state check, lifecycle-aware editor; preserve extension/type | No new persistent owner, catalog or journal; two stores and media classification still need regression tests; one-phone acceptance possible | **Recommended first implementation R1**: useful and bounded, with no speculative shared framework |
| Titles plus tags (§3) | Names above plus new metadata owner, module catalog, root/journal/deletion integration, multi-owner Save semantics | New persistent data and portability/downgrade obligations; one-phone restore tests plus later cross-device matrix | Separate T1 milestone after R1 or independently selected; not prerequisite for sharing |
| Hollow Notes (§8) | Editor, content creation/save boundary, mutable-content/identity semantics, protected draft cleanup; decide general-file representation versus new owner | Existing general files may store text, but safe content replacement is not an existing public store operation; do not assume creation equals editing | Good first Workspace candidate after its ingestion/edit contract; not required for R1 |
| Local Backup Center (§10) | Status/receipt ownership, truthful verification history and scope; first destination adds credentials/network adapter | Existing Verify Backup already covers a one-archive report; a new screen alone would repeat it. Durable history adds backup/deletion decisions | Independent useful branch once status/history scope is selected |
| Advanced Transfer (§7) | Secure destination adapter, credentials, host/certificate trust, interruption and overwrite/retry semantics | Can carry existing archives without new content format, but introduces network/platform dependencies and destination acceptance | Independent path; not an identity prerequisite and not required before local edits |
| Direct Transfer / Protected View (§4-6) | Optional identity/device trust plus recipient envelope/policy contract from D7 | Highest security/protocol surface among these candidates; requires two-device acceptance currently deferred | Design separately; titles/tags do not unlock or authorize it |

R1 is recommended because it changes an existing authoritative value without
inventing a data store or migrating every vault. It is not justified as a
foundation that magically enables every later feature. If product value favors
a different candidate, use that row's prerequisites; do not claim the code
dictates one universal product order.

### R1 scope: rename while preserving file type

There is a concrete coupling to protect: general-file export derives its output
filename from `displayName`, and encrypted-video classification falls back to
that name's extension when a content type is unavailable. A careless rename
could therefore break playback or exported-file recognition.

The proposed first implementation must:

- Keep `displayName` authoritative in the current content store. Expose an
  explicit Rename item action through a small independently compiled UI/policy
  add-on and application coordinator; add-on code cannot directly persist data.
- For a general file/video, edit the base name while preserving its exact
  existing extension. Keep its content-type identifier unchanged. Extensionless
  files remain extensionless. Do not provide type conversion through Rename.
- Preserve the existing photo storage identity/type; editing its display name
  never rewrites JPEG data or exports differently encoded content.
- Limit newly entered names to 180 UTF-8 bytes including preserved extension,
  matching the stricter general-file normalization boundary; reject empty,
  dot-only, colon, control/path-separator inputs and over-limit names visibly
  instead of silently changing them. Retain historical longer valid names until
  explicitly edited.
- Reject stale expected-state tokens/deleted items and reload current data.
  Do not add tags, descriptions, a new catalog version, a new root, network
  services, or content duplication to this candidate.

This UI surface changes the older general-file plan's settings-only editing
location deliberately. Record that focused product change in the implementation
PR; keep import immediate and preserve the accepted gallery/video behavior.

### Concrete acceptance cases (not tests already run)

| ID | Test / expected result | Owner |
| --- | --- | --- |
| R1-01 | Rename photo, video and general file; only authenticated display names change. UUIDs, blob ciphertext, folder membership and source originals stay byte-for-byte unchanged. | Content stores + composition |
| R1-02 | Two store instances edit a stale manifest snapshot; stale edit returns conflict, preserves the winner and unrelated import/delete updates, and invalidates/reloads the photo cache correctly. | Store transaction tests |
| R1-03 | Empty/control/separator input, Unicode boundaries, combined filename+extension length and historical long names follow the explicit rules above. Duplicate visible names remain permitted; export produces safe distinct filenames. | Rename policy + general-file export |
| R1-04 | A supported video with absent content-type metadata stays classified/playable after rename; its extension remains intact. Present but invalid/unsupported declared types remain rejected, never promoted by a filename edit. PDF/audio/image export keeps the correct extension and original bytes. | Video policy + export regression |
| R1-05 | Cancel before commit, lock at each mutation barrier, switch vault, and delete the selected item. No stale success/UI data crosses sessions; the documented commit outcome matches durable storage. | Session/coordinator tests |
| R1-06 | Inject pre-replacement error, post-replacement error and unreadable durable winner. Preserve old data or the committed value as observed; indeterminate state never deletes content or claims a successful rollback. | Store fault injection |
| R1-07 | Rename in a nested folder; export/verify/restore to a fresh vault. Names, bytes and hierarchy survive; old v1-v4 fixtures still restore. Verify-only never installs a credential. | Transfer and folder bridge tests |
| R1-08 | Build/TestFlight regression: search updated name, sort, open photo/video, close with Done/swipe, move, export, lock/reopen and one-phone backup round trip. No changes to video fullscreen presentation or import flow. | Native UI + physical iPhone |
| F-01 | First future module archive: unknown/duplicate owner/schema, invalid path, missing required handler/payload and dangling references reject without installation. Limits checked before expensive work. | Future module/catalog tests |
| F-02 | Restore each old catalog and old journal; inject interruption before/after each future root and credential step; preserve unrelated vaults and recover only transaction-owned roots. | Future transaction tests |
| F-03 | Future module: lock/edit/delete/export races cannot lose required metadata; deleting a vault also cleans the module. An old-client downgrade is blocked/documented unless preservation is proved. | Future lifecycle/compatibility tests |
| F-04 | Future restricted delivery: no owner vault key; wrong/revoked recipient, replay, unknown policy and alternate export/duplicate paths reject appropriately. Two-device acceptance remains required. | Future delivery/security tests |

R1-01–08 are the bounded implementation handoff. F-01–04 are release conditions
only for features that actually introduce those boundaries; they do not require
building those services as part of R1. Existing native regression/CodeQL and
protected release gates still apply to the eventual feature binary.

## Status and handoff

P1's shared ownership, identity, compatibility, module participation and
lifecycle decisions are recorded here, along with a source-backed candidate
comparison. The next proposed code stage is R1, on a separate feature branch
after this documentation review. No feature code or test binary was changed.
The user can choose another mapped candidate without requiring tags first.
