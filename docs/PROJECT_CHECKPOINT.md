# KeyHollow Development Checkpoint

**Updated:** September 6, 2026
**Purpose:** Durable restart point for roadmap add-on #4 after its module
boundary passed and its isolated playback integration entered validation.

## Executive status

- Hardened `main` is exact commit `3dc0f4a`.
- Build 35 passed internal physical-device testing and is testing in both
  `KeyHollow Internal` and `Family`.
- Release PR #41 is merged, post-merge build/tests and Swift CodeQL passed, and
  rollback tag `checkpoint/post-build-35-export-parity` identifies the hardened
  baseline.
- App Store review state was not changed.
- Roadmap add-on #2, Backup Verification Center, remains intentionally deferred.
- Roadmap add-on #3, General File Support, is complete. Its encrypted import,
  `.khvault` round trip, unified gallery, secure image preview, selection, and
  individual general-file export behavior are hardened through Build 35.
- Roadmap add-on #4, Encrypted Video Support, has a validated compiled boundary
  and validated app-composed playback. Bounded encrypted-at-rest video
  thumbnails are the next isolated milestone.

## Numbering clarification

The earlier folder/presentation work was historically called "Phase 4." It is
already complete and must not be confused with roadmap add-on #4, Encrypted
Video Support. Future status entries should use **roadmap add-on #4** for video
work and **Folder Presentation** for the completed historical phase.

## Compiled modular baseline

- `KeyHollowCryptoCore` owns cryptographic primitives and Argon2id.
- `KeyHollowVaultCore` owns passcode policy, key derivation, locators,
  credential envelopes, and opaque vault persistence.
- `KeyHollowPhotoCore` owns encrypted photo records and storage.
- `KeyHollowTransferCore` owns `.khvault` streaming, validation, restore,
  journaling, and rollback.
- `KeyHollowPhotosAdapter` owns the narrow Apple Photos boundary.
- File Recognition, General File Support, Folder Presentation, Secure Preview,
  Encrypted Video, and Gallery UI are separately compiled targets with strict
  concurrency and warnings treated as errors where required.
- Protected core targets do not import add-ons. Concrete feature wiring remains
  in the application composition layer.

## Verified hardening evidence

- Local release-hygiene gate: passed.
- Local architecture-boundary gate: passed.
- Local TestFlight build-number guard self-test: passed.
- Exact post-merge CI run #266 for `3dc0f4a`: passed.
- Complete Mac simulator build/test job: passed.
- Swift CodeQL: passed with no failed security gate.
- Simulator and security-test artifacts: retained and unexpired.
- CI actions: pinned to exact commits; artifact uploader is the Node 24
  generation.
- Encrypted-video boundary run #267 passed the complete Mac build/test job and
  Swift CodeQL at exact commit `1c02979f989d296eaadc52becec6b45dcdf29ff1`.
- Encrypted-video playback run #268 passed the complete Mac build/test job and
  Swift CodeQL at exact commit `37f0e2cc8e0a9842b4bce633e0410812fb738cf1`.
- Feature branch `feature/encrypted-video-support` now has two exact validated
  checkpoints; no production or TestFlight state has changed.

## Roadmap add-on #4 entry requirements

1. Implement video behavior in its own independently compiled add-on target.
2. Keep vault keys, authenticated session ownership, encrypted stores, and
   `.khvault` formats outside the video module.
3. Reuse narrow existing general-file access only through explicit immutable
   metadata and revocable operations owned by the app composition layer.
4. Bound accepted video types and sizes before decoding or playback.
5. Keep any decrypted playback file protected, excluded from backup, scoped to
   the active authenticated session, and deleted on dismissal, lock,
   background interruption, cancellation, and failure.
6. Produce encrypted-at-rest video thumbnails without changing protected source
   content or existing gallery behavior.
7. Preserve existing vaults and byte-compatible `.khvault` export/import.
8. Prove add-on removal leaves the protected core and existing non-video paths
   operational.

## Required gates

1. Isolated feature branch and draft review.
2. Narrow-interface, capability-lifetime, and dependency-direction review.
3. Architecture and release-hygiene enforcement updated to pin the new module.
4. Unit tests for type/size policy, thumbnail bounds, temporary-file cleanup,
   cancellation, locking, malformed input, and non-video routing.
5. Complete simulator build, unit, lifecycle, transfer, security, and launch
   tests with warnings treated as errors.
6. Swift CodeQL with no unresolved findings.
7. Guarded TestFlight delivery from a separately reviewed delivery branch.
8. Physical-iPhone playback, interruption, background-lock, low-storage,
   export/restore, and data-integrity testing.
9. Explicit owner approval before merge.

## Current blockers and next action

There is no modular or security blocker. Windows cannot run the Apple simulator,
so exact-source Mac compilation and tests remain a required remote CI gate as
before. The current action is to add bounded video-thumbnail rendering inside
the video module, encrypt only the generated thumbnail through Folder
Presentation, and prove temporary plaintext cleanup and existing-gallery
regressions. Do not change TestFlight groups, production delivery, or App Store
review state without the required later approvals.
