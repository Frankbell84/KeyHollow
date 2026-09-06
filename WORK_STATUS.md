# KeyHollow Work Status

Updated: 2026-09-05
Branch: `feature/folder-presentation-addon`
Pull request: [#35](https://github.com/Frankbell84/KeyHollow/pull/35) (draft)

## Current task

Production Build 30 was signed and uploaded from the exact reviewed commit.
Frank's device feedback found a Phase 4 presentation inconsistency: photo tiles
can appear visually distorted and do not carry the filename-and-size footer used
by general-file tiles. The isolated correction is implemented locally and is
under remote Mac validation. Build 30 is fully processed and now testing in
both `KeyHollow Internal` and `Family`. App Store review remains untouched.

## Completed work

- Began from verified remote `main` at merged General File Support commit
  `bbd6bfa`; no completed feature or delivery branch was reused.
- Preserved the compiled core modules and the independently compiled File
  Recognition and General File Support add-ons.
- Removed the General File Support actor-initializer warnings by resolving file
  locations and dependencies locally before assigning actor-owned state. No
  storage path, encryption, import, export, or deletion behavior changed.
- Made warnings-as-errors mandatory for every registered first-party add-on and
  extended the architecture gate to enforce that rule for future add-ons.
- Updated all artifact-upload workflow pins from the deprecated Node 20 action
  to the exact reviewed Node 24 action commit.
- Made simulator selection architecture-specific after the first remote run
  exposed Xcode's harmless multiple-destination warning; future runs now select
  the runner's exact architecture instead of accepting Xcode's first match.
- Refreshed the modularization plan and durable project checkpoint to reflect
  the completed modular baseline, merged add-ons, validated Build 29, and the
  exact Phase 4 entry requirements.
- Preserved the deferred presentation requirement: images imported through
  Files receive encrypted thumbnail parity during the folder/presentation phase.
- Merged the preflight cleanup through PR #34 and published the annotated
  `checkpoint/pre-phase-4-clean-baseline` rollback tag at `69154ff`.
- Created `feature/folder-presentation-addon` directly from that clean tagged
  checkpoint.
- Added the first independently compiled Phase 4 module:
  `KeyHollowFolderPresentationAddOn`.
- Defined neutral photo/general-file references, folder membership records, and
  scoped cryptographic access without importing either protected content store.
- Added an encrypted presentation store whose folder deletion and reconciliation
  operations cannot delete protected photos or general files.
- Added authenticated local thumbnail persistence as opaque bytes so image
  generation and decoding remain outside the module.
- Added folder lifecycle, input validation, encrypted-at-rest thumbnail,
  reconciliation, and vault-access mismatch tests.
- Opened draft PR #35 so all remote Mac and security gates run before UI
  composition begins.
- Added the visible one-level folder gallery milestone locally: encrypted
  folder creation/rename, root and folder navigation, item counts, and folder
  tiles live entirely in app presentation and the independent add-on.
- Added move destinations for both protected photo references and encrypted
  general-file references. Moving never decrypts, copies, or changes protected
  content.
- Folder deletion explicitly returns membership references to the vault root;
  it cannot delete photos or files.
- Folder-scoped photo selection preserves the established save/delete behavior
  without selecting hidden photos from another folder.
- Added reconciliation after protected-store refreshes so stale presentation
  membership and thumbnail metadata are removed without touching content.
- Added regression coverage proving moves between folders and back to the root
  maintain at most one membership per item.

## Test and build status

- Architecture boundary gate: passed locally.
- Release-hygiene gate: passed locally.
- TestFlight build-number guard self-test: passed locally.
- Whitespace and obsolete-status audit: passed locally.
- Final merged-baseline CI run [#216](https://github.com/Frankbell84/KeyHollow/actions/runs/33986912069)
  at `7fb5487`: passed.
- Mac simulator build and complete regression/security suite: passed in 6m49s.
- Both first-party add-ons compiled under strict concurrency with
  warnings-as-errors; no add-on diagnostics remained.
- Deterministic architecture-specific simulator selection removed the prior
  multiple-destination warning.
- Artifact uploads through the pinned Node 24 action: passed; simulator and
  security-test artifacts were produced with recorded SHA-256 digests.
- Swift CodeQL: passed with no failed security gate.
- PR #34 merged into `main` as `69154ff`; all required checks were green.
- Phase 4 inherits that green baseline.
- Phase 4 architecture boundary gate: passed locally.
- Phase 4 release-hygiene gate: passed locally.
- Phase 4 whitespace audit: passed locally.
- Thumbnail-composition architecture and release-hygiene gates: passed locally.
- Thumbnail-composition build-number guard self-test: passed locally.
- Thumbnail-composition diff integrity check: passed locally.
- Remote Phase 4 run [#222](https://github.com/Frankbell84/KeyHollow/actions/runs/33992220446)
  rejected `b55e40a` at compile time because the optional general-file content
  type was not explicitly unwrapped before creating `UTType`. The architecture
  and hygiene steps passed; tests did not run after the compiler stopped.
- The thumbnail path now safely requires a non-nil content type before image
  preview work begins. Files without a declared image type remain accessible
  through their normal generic tile and are never guessed from untrusted bytes.
- Corrected Phase 4 run [#223](https://github.com/Frankbell84/KeyHollow/actions/runs/33993203704)
  at `55366a2`: passed in 23m31s.
- Mac simulator build and complete regression/security suite: passed in 6m34s.
- Swift CodeQL: passed in 22m46s with no failed security gate.
- Security-test and simulator artifacts were produced with recorded SHA-256
  digests.
- Prepared and pushed the exact reviewed release commit `1cc359d` (`Prepare
  guarded Phase 4 Build 30`) on `feature/folder-presentation-addon`.
- Created `delivery/folder-presentation-addon` at that exact commit; the
  delivery branch contains no unreviewed source changes.
- Frank requested that this update also be made available to the `Family`
  TestFlight group for broader feedback.
- Frank confirmed Build 30's file-image thumbnails render, then identified that
  photo and file tiles still use visibly different sizing and metadata rules.
- Added one shared square gallery-tile surface so photo and general-file tiles
  use the same media region, filename treatment, size/detail line, and footer.
- Corrected file-image thumbnail generation to respect image orientation before
  calculating dimensions, preventing portrait and rotated images from being
  stretched.
- Added optional photo display-name and stored-size metadata. New imports retain
  this information; existing manifests and older `.khvault` archives remain
  compatible because missing metadata decodes cleanly.
- Existing photo records display their import date when their historical stored
  size is unavailable; no protected photo is decrypted merely to populate UI.
- Added regression coverage for legacy photo-record decoding, normalized stored
  metadata, and orientation-preserving thumbnail dimensions.
- Verified in App Store Connect that Build 30 is `Complete` / `Ready to Submit`
  and remains assigned to `KeyHollow Internal`.
- App Store Connect was checked directly after approval: Build 29 is the latest
  completed production upload, so Build 30 is the next unused number.
- Updated both the app and embedded thumbnail extension to Build 30.
- Replaced the stale prior-feature workflow exception with the exact guarded
  `delivery/folder-presentation-addon` branch; ordinary feature branches remain
  unable to upload production builds.
- Definitive Phase 4 run [#219](https://github.com/Frankbell84/KeyHollow/actions/runs/33989008013)
  at `802252d`: passed in 28m43s.
- Mac simulator build and complete regression/security suite: passed in 7m37s.
- Swift CodeQL: passed in 27m04s with no failed security gate.
- Simulator and test artifacts were produced with recorded SHA-256 digests.
- Authenticated general-file preview read, scoped folder-presentation access,
  presentation-aware vault cleanup, and the gallery thumbnail view seam were
  checkpointed and pushed as `57ed011`.
- Completed root-gallery composition for images imported through Files: the app
  first loads an authenticated encrypted presentation thumbnail, otherwise it
  decrypts only the selected manifest record, creates a bounded 512-pixel JPEG,
  and stores that preview in the independent encrypted presentation add-on.
- Added cancellation checks to authenticated general-file reads and a strict
  2 MiB presentation-thumbnail ceiling with regression coverage.
- Ordered presentation-store initialization before file records appear so a
  fast first render cannot skip thumbnail generation.
- Visible-folder architecture boundary gate: passed locally.
- Visible-folder release-hygiene gate: passed locally.
- Visible-folder build-number guard self-test: passed locally.
- Visible-folder diff integrity check: passed locally.
- Visible-folder CI run [#225](https://github.com/Frankbell84/KeyHollow/actions/runs/33994826801)
  at `0739769`: passed in 23m14s.
- Mac simulator build and complete regression/security suite: passed in 5m31s.
- Swift CodeQL: passed in 22m33s with no failed security gate.
- Security-test and simulator artifacts were produced with recorded SHA-256
  digests.
- Final Build 30 source-validation run
  [#227](https://github.com/Frankbell84/KeyHollow/actions/runs/33997419767)
  at `1cc359d`: passed in 19m53s.
- Mac simulator build and complete regression/security suite: passed in 9m02s.
- Swift CodeQL: passed in 19m08s with no failed security gate.
- Simulator artifact `9978590186` was recorded with SHA-256 digest
  `2900d9ab5f7e5efa6c357c6a73fcbd90636d1c27916eddfb8f55e6b38c72bcfc`.
- Security-test artifact `9978590860` was recorded with SHA-256 digest
  `133bd4e54a73936dbefe39889f5bcd2a136e008270830dbfd46b22a444da4916`.
- Guarded TestFlight upload run
  [#40](https://github.com/Frankbell84/KeyHollow/actions/runs/33998469992)
  completed successfully in 2m16s from `delivery/folder-presentation-addon`.
- Release hygiene, production identity, build-number verification, project
  generation, cloud signing, archive, archive/module hygiene, signed IPA
  export, Apple upload, artifact retention, and signing-material cleanup all
  passed.
- The only upload-run notice was a hosted-runner Homebrew trust warning for an
  existing `aws/tap`; it did not affect the app, signing, archive, or upload.
- Gallery-parity architecture boundary gate: passed locally.
- Gallery-parity release-hygiene gate: passed locally.
- Gallery-parity TestFlight build-number guard self-test: passed locally.
- Gallery-parity whitespace/diff integrity check: passed locally.
- First gallery-parity CI run
  [#230](https://github.com/Frankbell84/KeyHollow/actions/runs/33999150470)
  at `4469e19`: the app and simulator build passed, 105 of 106 unit tests
  passed, and all launch tests passed. The new orientation test alone failed
  because its synthetic image inherited the simulator's 3x screen scale while
  asserting 1x dimensions.
- The test fixture now fixes its renderer to an explicit 1x scale so it measures
  orientation behavior deterministically across simulator devices. The
  production thumbnail implementation was not weakened or changed.

## Blockers

- Full iOS compilation and unit tests require the remote Mac CI gate.

## Next action

Commit and push the deterministic test-fixture correction, then require the
complete Phase 4 Mac simulator and Swift security gates. Build 30 is already
testing with both intended groups. Any corrected follow-up build must receive a
separate guarded delivery checkpoint.

## Frank's decision required

- Frank explicitly approved this Phase 4 TestFlight delivery and requested the
  `Family` group receive Build 30.
- Build 30 is now `Testing` in both `KeyHollow Internal` and `Family`, with
  automatic tester notification enabled.
- No decision is required for the gallery parity correction; Frank explicitly
  requested proportional thumbnails and matching image metadata footers.
- Device feedback and the later merge decision remain pending.
- Any App Store review change remains out of scope without separate explicit
  approval.
