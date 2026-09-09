# Encrypted Video Support Boundary

Encrypted Video Support adds first-class playback and bounded gallery
thumbnails for videos already stored by General File Support. This phase is an
adapter and presentation feature, not a new storage format.

## Compatibility invariants

- A video remains an ordinary `VaultGeneralFileRecord` backed by the existing
  General File Support encrypted blob. Folder membership, selection, deletion,
  export, and presentation metadata continue to reference that same record.
- There is no record migration, manifest migration, second encrypted store, or
  archive conversion.
- The `.khvault` container, backup, export, and restore formats do not change.
  Existing archives remain byte-compatible with this phase.
- Initial playback is limited to non-empty QuickTime `MOV` files and MPEG-4
  `MP4` or `M4V` files whose original size is at most 100 MB
  (`100 * 1_024 * 1_024` bytes), preserving the existing ingress ceiling.
- Media validation also rejects source tracks beyond an 8,192-pixel dimension
  or 7,680-by-4,320 total pixel envelope before thumbnail frame decoding.
- A recognized non-video content type is authoritative over a misleading file
  extension. Only records whose content-type metadata is absent may use the
  conservative `.mov`, `.mp4`, or `.m4v` extension fallback, and they still
  must pass media validation.
- Larger files, incremental decryption, and streaming playback require a later
  encrypted-storage design review. They are not silently introduced here.

## Module ownership

`KeyHollowEncryptedVideoAddOn` is an independently compiled, dependency-free
static library. It owns only:

- conservative classification from immutable display-name, content-type, and
  byte-count metadata;
- a local-file-only playback descriptor and asynchronous media validation;
- one reference-restricted asset factory that applies
  `AVAssetReferenceRestrictions.forbidAll` before validation, frame decoding,
  or playback can resolve container references;
- native video-player presentation with AirPlay, external-screen playback, and
  Picture in Picture disabled, plus terminal player-memory teardown;
- one-frame, orientation-correct, bounded thumbnail rendering.

The add-on never receives or imports a vault session, unlock service, vault
key, general-file record or store, folder store, transfer coordinator,
security-scoped ingress capability, file manager, network client, or remote
service SDK.

The application composition layer owns record lookup, authentication,
decryption, protected temporary plaintext, encrypted thumbnail persistence,
and every cleanup decision. It passes the add-on only immutable metadata and a
validated local file URL.

## One shared cold full-payload lane

Files-origin image thumbnails and video thumbnails must share the existing
`VaultGeneralFileThumbnailPipeline` permit. A video-specific thumbnail
coordinator, semaphore, or parallel plaintext lane is forbidden.

- Encrypted thumbnail-cache hits bypass the full-payload permit.
- A cold miss waits for the single shared permit and then rechecks the encrypted
  cache, so queued duplicate work can become a cache hit.
- Authentication and full-payload preparation, bounded image or video
  rendering, temporary-plaintext cleanup, and encrypted thumbnail persistence
  all remain inside that permit.
- Video plaintext is deleted before the bounded JPEG crosses into Folder
  Presentation and before the permit is released.
- Cancellation while queued or rendering must not leave a permit occupied, a
  media decoder running, or plaintext behind.
- Each gallery request runs as an awaited session-sensitive operation. A lock
  revokes access synchronously, cancels that work, and returns a cleanup barrier
  that production lock/background paths await.

This keeps the accepted Build 38 cache-hit fast path responsive while bounding
the combined Files-origin image/video cold workload to one full payload at a
time.

## Plaintext lifetime and playback cleanup

The app prepares exactly one authenticated General File Support export for an
explicit playback request. Prepared plaintext has the shortest practical
lifetime and is never treated as a durable cache.

1. The app creates the prepared export and constructs a local-only playback
   handoff.
2. The handoff asynchronously validates the AV asset. Playability and required
   media properties must succeed before active playback is published.
3. The app-owned playback coordinator retains the only cleanup handle while
   preparation or playback is active.
4. Cleanup is idempotent. Validation failure, ordinary failure, and task
   cancellation await deletion directly. UI lifecycle callbacks revoke
   playback synchronously; the session-registered worker then awaits deletion.
   Manual lock paths await the returned cleanup barrier, and background locking
   gives that same barrier an iOS background-task window before ending it.
   `lockAndWait()` remains the explicit test/shutdown terminal boundary.
   Active-vault replacement also awaits the prior worker before proceeding.
5. The player independently pauses, replaces its current item with `nil`, and
   releases player state when its surface disappears. It acknowledges the
   release lease only after its monitoring task and AV asset references unwind.
   The app cannot delete plaintext while the player still owns a decoder or
   file handle; a player that tries to mount after dismissal is rejected.
6. Protected playback explicitly disables AirPlay, automatic external-screen
   playback, and Picture in Picture so media cannot outlive the locked in-app
   surface through a system playback route.

No plaintext URL is persisted in a manifest, thumbnail cache, user default,
log, network request, or archive. Normal background locking is not suspended
for playback.

## Malformed media fails closed

Classification only decides whether a record may attempt the video path; it
does not establish that bytes are playable. Empty, oversized, mismatched,
missing, malformed, unsupported, or unplayable media must leave active
playback unset, discard any prepared plaintext, and return a controlled error.

Thumbnail failure or cancellation must discard plaintext and must not persist
partial or invalid thumbnail data. The gallery falls back to the normal video
or file icon, remains usable, and preserves the encrypted source record.

## Thumbnail bounds

Validation first checks natural, transformed presentation, and coded-frame
metadata and rejects zero, non-finite, over-8,192-dimension, or over-8K source
tracks. The renderer then requests one frame through
`AVAssetImageGenerator`, applies the preferred track transform, and sets a
maximum output width and height of 512 pixels before decoding. It rejects zero
or oversized output dimensions and rejects encoded JPEG data larger than 2 MB
(`2 * 1_024 * 1_024` bytes).

Rendering checks cooperative cancellation before and after asynchronous work.
Its cancellation handler calls `cancelAllCGImageGeneration()` so scrolling,
locking, or leaving the gallery cannot leave decoder work running.

## Required delivery and device gates

All of the following evidence is required before this feature may be merged or
delivered:

1. The architecture-boundary, release-hygiene, build-number, and diff-integrity
   gates pass without weakening any Build 38 guard.
2. Project generation succeeds, the independent add-on compiles with warnings
   treated as errors, and focused policy, handoff, renderer, cleanup, routing,
   shared-lane, and malformed-media tests pass.
3. The complete iOS test suite and a clean Release build pass on the exact
   source revision on a supported Mac/Xcode host.
4. Swift CodeQL completes successfully on that same revision.
5. A physical supported iPhone validates `MOV`, `MP4`, and `M4V` playback;
   orientation and audio; size and type boundaries; rapid image/video gallery
   scrolling; cancellation; and plaintext cleanup after dismissal, lock,
   backgrounding, view disappearance, vault switching, malformed media, and
   failure.
6. Existing photo, Files-origin image, non-video file, folder, selection,
   deletion, export, backup, restore, and `.khvault` regression coverage
   remains green.

A signed upload, tester-group change, TestFlight delivery, feature-branch
merge, or App Store review action remains a separate explicit approval. Passing
the technical gates alone does not authorize any of those actions.
