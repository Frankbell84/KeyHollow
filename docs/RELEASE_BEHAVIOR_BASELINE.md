# KeyHollow Release Behavior Baseline

This document freezes the user-visible and security-relevant behavior of the
KeyHollow 1.0 Build 11 release before later architectural cleanup. Refactors
must preserve this behavior unless a separately reviewed product change says
otherwise.

## Vault identity and access

- A new vault requires an acceptable 8–20 digit LowKey. Predictable patterns
  such as repeated or sequential digits are rejected.
- Each accepted LowKey creates one independent vault with a random vault ID and
  random data-encryption key.
- A LowKey opens only its matching vault. The locked interface does not list
  existing vaults or reveal their count.
- The locked interface always offers creation of another independent vault.
- Face ID, Touch ID, and the device PIN are not alternate vault credentials.

## Lifecycle and persistence

- Vault creation is complete only after its authenticated credential envelope
  has been written successfully. A later service instance must detect and open
  the completed vault.
- Locking clears the active vault ID and active key from the in-memory session.
- Changing a LowKey rewraps the same random vault key. It does not create a new
  vault or re-encrypt the photo library.
- A failed LowKey change must leave the original vault accessible and must not
  replace another vault's credential.
- Deleting a vault first removes its credential envelope, then removes that
  vault's encrypted photo directory. Other vaults remain accessible.
- A wrong LowKey or a mismatched expected vault ID cannot change or delete a
  vault.

## Photos and app lifecycle

- Imported originals, thumbnails, and the manifest are stored only as
  authenticated ciphertext.
- Copy preserves the source in Photos. Move verifies the encrypted vault copy
  before asking iOS to delete the source.
- The app locks on a true background transition. A system Photos or Files
  handoff must not be mistaken for leaving the app while that interaction is
  active.
- Selected vault photos can be saved back to Photos or deleted from the open
  vault; unselected encrypted items remain intact.

## Portable encrypted vaults

- Export operates only on the currently open vault and leaves its local source
  unchanged.
- A `.khvault` archive is authenticated and encrypted with a separate recovery
  code. That recovery code never unlocks the normal local keypad.
- Restore validates and stages the complete archive before installing a new
  local vault identity and LowKey wrapper.
- Backup Verification authenticates the same archive contents through the same
  validator but always discards staging and returns only a read-only summary. It
  cannot install a vault or turn the recovery code into a local LowKey.
- The current payload-catalog version preserves protected photos and general files but
  not Folder Presentation names or membership metadata. Export and import both
  disclose that restored items appear at the new vault's top level.
- Wrong recovery codes, tampering, truncation, path traversal, credential
  collision, cancellation, or an interrupted restore must fail closed without
  exposing plaintext or replacing an existing vault.

## Approved later gallery and folder behavior

- The unified gallery selects photos and general files by distinct typed
  references even when their UUID values match.
- A selected photo-only, file-only, or mixed batch can move to an existing
  folder. A selection already inside a folder can move to the vault root or a
  different folder.
- Batch movement changes only encrypted Folder Presentation membership
  metadata with one authenticated manifest write. It never copies, decrypts,
  rewrites, or deletes protected photo or general-file content.
- A missing destination or failed membership write leaves the prior folder
  assignments and protected content unchanged.

## Unified media navigation candidate

The isolated Unified Media Navigation feature branch contains the following
locally hardened additive candidate behavior. It is not part of the accepted
release baseline until its review, CI, merged-main, signed-build, and
physical-device gates pass:

- A Photos-origin image, Files-origin image, or supported encrypted video opens
  at its position in the compatible-media order of the currently visible vault
  root or folder.
- Horizontal navigation stays within that immutable location snapshot and does
  not wrap beyond its first or last item. PDFs and other non-media files retain
  their existing file-management route.
- Photo and general-file identifiers include their source as part of identity,
  so equal UUID values cannot alias one another.
- The navigation add-on receives immutable identity, kind, and display-title
  metadata only. It does not receive a vault session, key, protected store,
  ciphertext, plaintext payload, local file location, or archive capability.
- The pager constructs presentation for the active item only. Authentication,
  decryption, generation control, prior-item cleanup, saving, deletion, lock and
  background handling, and protected temporary-file lifetime remain owned by
  the application composition layer.
- Image replacement waits for the UIKit presentation surface to clear its image
  reference. Video replacement continues to wait for player release and
  protected-export removal. Save and delete temporarily disable page navigation
  and dismissal so a prior operation cannot overlap or publish into a new item.
- VoiceOver presentation includes the current title, media kind, position, and
  boundary-aware previous and next controls.

This section records candidate intent and implementation scope only. It does not
record CI, build, TestFlight, or device-test acceptance.

## Automated Stage One evidence

- `VaultLifecycleBaselineTests` covers create, persistence across service
  recreation, session lock, unlock, LowKey change, deletion, encrypted-photo
  cleanup, rejected creation, duplicate LowKeys, cross-vault mutation attempts,
  and continued access to unaffected vaults.
- Existing crypto, photo-store, archive, restore-transaction, lifecycle-policy,
  and launch tests remain part of the required release suite.
- Later architecture work should add coverage thresholds and expand device/UI
  testing for PhotoKit failures, background cancellation, large batches, and
  memory pressure; those are explicitly outside this baseline-only stage.
