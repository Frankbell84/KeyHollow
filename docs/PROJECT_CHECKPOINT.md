# Historical KeyHollow Build 38 Checkpoint

**Updated:** September 9, 2026
**Purpose:** Frozen historical evidence for the accepted Build 38 gallery
performance release. This is not the current resume point or release policy.
Use `WORK_STATUS.md` for current work and `docs/ADDON_RELEASE_POLICY.md` for the
mandatory release sequence.

## Executive status

- A post-power-loss recovery audit found no interrupted Git operation, lock, or
  reachable repository corruption. The checkpoint branch was aligned with its
  pushed commit at recovery start, and the accepted Build 38 baseline remains
  intact.
- Current merged baseline is `main` at `3df3e1c`, which merged release PR #48
  and contains exact accepted head `d85c338`.
- Build 38 passed all seven required physical-iPhone acceptance scenarios and
  is `Testing` in both `KeyHollow Internal` and `Family`.
- Build 37 is superseded because it reproduced gallery scrolling and image-open
  lag at only 26 mixed items. Build 38 corrects that presentation/loading
  regression without a protected-data migration or archive-format change.
- App Store review state was not changed.
- Roadmap add-on #3, General File Support, is complete and hardened.
- Folder Presentation, historically called "Phase 4," is complete and hardened.
  It must not be confused with roadmap add-on #4.
- Roadmap add-on #4, Encrypted Video Support, is next.
- Roadmap add-on #2, Backup Verification Center, remains deliberately deferred
  until Encrypted Video closes and is confirmed as the following add-on.

## Compiled modular baseline

- `KeyHollowCryptoCore` owns cryptographic primitives and Argon2id.
- `KeyHollowVaultCore` owns passcode policy, key derivation, locators,
  credential envelopes, and opaque vault persistence.
- `KeyHollowPhotoCore` owns encrypted photo records and storage.
- `KeyHollowTransferCore` owns `.khvault` streaming, validation, restore,
  journaling, and rollback.
- `KeyHollowPhotosAdapter` owns the narrow Apple Photos boundary.
- File Recognition, General File Support, Folder Presentation, Secure Preview,
  and Gallery UI are separately compiled targets.
- The gallery module receives immutable display metadata, typed identifiers,
  and action closures; it does not own vault keys, ciphertext, protected stores,
  or portable archive formats.
- The app composition layer owns concrete feature wiring. Protected core
  targets do not import add-ons.

## Accepted functional baseline

- Photos and general files import directly into one unified three-column vault
  gallery with normalized, aspect-preserving thumbnails and consistent labels.
- Photo-library images and Files-origin images use the same secure image-opening
  experience. Non-image files use the protected file-management route.
- Mixed photo/file selection, select all, deletion, individual export, folder
  creation/navigation, and batch moves are operational.
- Mixed photo/file `.khvault` export and restore preserve general files and
  existing vault compatibility. The current archive version does not preserve
  Folder Presentation names or membership; both transfer screens disclose that
  restored items appear at the new vault's top level.
- Warm and cold mixed-gallery scrolling, repeated image opening, dismissal and
  lock recovery, folder navigation and moves, non-image routing, and the largest
  representative image all passed physical-device validation in Build 38.

## Verified hardening evidence

- Main CI run
  [#295](https://github.com/Frankbell84/KeyHollow/actions/runs/34156666679)
  passed its Mac build/test, Swift CodeQL, and Pages jobs at exact merged
  baseline `3df3e1c` after the outage.
- Final acceptance-head CI run
  [#294](https://github.com/Frankbell84/KeyHollow/actions/runs/34154622765)
  passed at exact commit `d85c338`.
- Mac simulator build, complete regression/security and launch suite, packaged
  thumbnail verification, and artifact uploads passed with zero annotations.
- Swift CodeQL passed with zero annotations.
- Simulator artifact `10030685984` has SHA-256 digest
  `7bc3a46c027ddefe3e356f96095955022d868a178b7c97612cea7218864b4f96`.
- Security-test artifact `10030690480` has SHA-256 digest
  `6086c720dfd8d0c32eb3a0b184f9c8e07b6ff2a0415a9b160790149ba0ea1488`.
- Local architecture-boundary, release-hygiene, build-number guard, and diff
  integrity checks passed before merge.
- Refreshed remote ancestry verifies accepted head `d85c338` is contained in
  merged `origin/main` at `3df3e1c`.

## Historical scope boundary

The roadmap, Encrypted Video integration instructions, release branch model,
and resume directions that originally followed this checkpoint were consumed
by later work and intentionally removed. Build 39 supersedes this operationally.
The evidence above remains useful for provenance only; it must never override
the current status, architecture contract, or protected-main release policy.
