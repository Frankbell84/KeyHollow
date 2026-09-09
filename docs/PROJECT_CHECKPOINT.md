# KeyHollow Development Checkpoint

**Updated:** September 9, 2026
**Purpose:** Durable restart point after the accepted Build 38 gallery
performance release and before roadmap add-on #4, Encrypted Video Support.

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
  existing vault compatibility.
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

## Roadmap order from this checkpoint

1. **Encrypted Video Support (roadmap add-on #4).** Adapt the already validated
   modular video concepts onto a fresh branch from current `main`.
2. **Backup Verification Center (roadmap add-on #2).** Add read-only archive
   health/authenticity reporting over the existing authenticated validator;
   do not add an install operation or another unlock route.
3. **Unified media navigation.** Add swipe navigation through compatible media
   after video behavior is settled so photos, Files-origin images, and videos
   can share one deliberately designed pager.
4. **Catalog and organization refinements.** Metadata/details editing,
   authenticated search/sort, cycle-safe nested folders, honest import progress,
   and—only if still useful—lightweight cross-vault references rather than
   recursively embedding complete `.khvault` archives.
5. **Later security and migration add-ons.** Break-in Reports / Intruder
   Capture, App Icon Camouflage, and the Vault Escape Hatch share extension.
6. **Architecture Addendum program.** Secure manifest/policy and Protected View;
   Direct and Advanced Transfer; Backup/Sync; Identity/Recovery; Legacy Center;
   Secure Threads; Hollow Workspace; integrity/sealing; and later organization,
   intelligence, and automation capabilities. Each remains a separately mapped
   module, not authorization for a broad rewrite.

## Encrypted Video integration rule

The historical `feature/encrypted-video-support` branch contains three useful,
previously green milestones: compiled module boundary (`1c02979`), secure
playback (`37f0e2c`), and bounded encrypted-at-rest thumbnails (`dcef6d5`), with
evidence recorded at `c56edff`. That branch predates the accepted Build 38
gallery, folders, and performance behavior and must not be merged wholesale.

Create a fresh feature branch from current `main`. First map the historical
video diff against the current target graph and gallery contracts. Transfer or
rewrite only the isolated video target, policy, coordinators, and tests, then
adapt current gallery wiring deliberately. Preserve existing vaults and
byte-compatible `.khvault` behavior.

## Required gates for the next add-on

1. Fresh isolated feature branch and draft review.
2. Narrow-interface, capability-lifetime, and dependency-direction review.
3. Architecture and release-hygiene checks before and after implementation.
4. Tests for accepted types and size policy, thumbnail bounds, temporary-file
   cleanup, cancellation, locking, malformed input, and non-video routing.
5. Complete Mac simulator build, unit, lifecycle, transfer, security, and launch
   tests with warnings treated as errors.
6. Swift CodeQL with no unresolved findings.
7. Guarded TestFlight delivery from a separately reviewed delivery branch.
8. Physical-iPhone playback, interruption/background lock, low-storage,
   thumbnail, export/restore, and data-integrity testing.
9. Explicit owner approval before signed upload, tester-group changes, merge,
   or App Store review action.

## Current blockers and decisions

There is no known code, modularity, security, performance, delivery, or roadmap
blocker. Windows cannot run the Apple simulator, so the Mac CI and physical
iPhone gates remain mandatory. No owner decision is required to begin the
already-approved isolated Encrypted Video adaptation. Signed delivery, tester
assignment, feature merge, and App Store review remain later explicit decision
boundaries.

## Resume instruction

Fetch `origin/main` and verify it contains merge commit `3df3e1c` plus accepted
head `d85c338`. Read this file, `WORK_STATUS.md`,
`docs/ARCHITECTURE_BOUNDARIES.md`, and `docs/ADDON_RELEASE_POLICY.md`. Start the
Encrypted Video work on a new branch from that verified baseline. Do not reuse
or wholesale merge the historical video, general-file, folder, performance, or
delivery branches.
