# KeyHollow Work Status

Updated: 2026-09-06
Branch: `fix/unified-folder-gallery`
Parent release source: `2eaf852` (Build 32)

## Current task

The isolated unified-folder correction is implemented, remotely validated, and
uploaded from exact immutable source `7503a68` as Build 33. GitHub's complete
signed-delivery workflow passed; Apple is now processing the upload. Build 33
must be assigned only to `KeyHollow Internal` after processing. `Family`
remains on Build 30, and production merge and App Store review remain untouched.

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
- Replaced the separate photo and general-file gallery loops with one
  source-neutral presentation collection ordered by import time rather than
  protected-store kind.
- Replaced the two tile implementations with one shared tile: a square clipped
  media viewport, fixed 56-point metadata footer, middle-truncated title, file
  size, and one top-right selection overlay position.
- Normalized image naming across import sources by hiding image extensions while
  retaining extensions for non-image files.
- Preserved protected-store routing for open, save, move, and delete actions;
  this presentation correction does not change encrypted content ownership.
- Added regression tests for cross-source image naming, non-image filename
  retention, source-neutral ordering, fixed tile metrics, and thumbnail
  orientation.
- Strengthened architecture enforcement so the two obsolete gallery renderers
  cannot silently return.
- Committed the complete correction as `c88fbf7` and published it to the
  isolated `fix/unified-folder-gallery` branch.
- Opened isolated draft PR
  [#36](https://github.com/Frankbell84/KeyHollow/pull/36) against `main` so the
  complete Phase 4 history and unified-gallery correction receive the same
  mandatory validation gates.
- Created and published immutable delivery branch
  `delivery/unified-folder-gallery` at exact validated source `7503a68`.
- Dispatched the explicitly approved Build 33 upload from that exact branch;
  no refactor work or later branch commit entered the delivery.

## Test and build status

- Final Build 33 release-source validation run
  [#245](https://github.com/Frankbell84/KeyHollow/actions/runs/34036637111)
  at exact commit `7503a68`: passed in 18m18s.
- Mac simulator build and complete regression/security suite: passed in 10m23s.
- Swift CodeQL: passed in 18m11s with no failed security gate.
- Simulator artifact `9990518475` was recorded with SHA-256 digest
  `21c2c2208e44ef8a425207bb0979aa6aaf5692c6dcba9a69c3e17d8f200f987c`.
- Security-test artifact `9990520799` was recorded with SHA-256 digest
  `995abcc419904a207d9262ab5343a461121bb4f7c15ed1cd67aa5dd720fce052`.
- Guarded TestFlight upload run
  [#43](https://github.com/Frankbell84/KeyHollow/actions/runs/34038901100)
  completed successfully in 3m13s from exact source `7503a68`.
- Release hygiene, production identity, unused Build 33 verification, project
  generation, cloud signing, archive/module hygiene, signed IPA export, Apple
  upload, artifact retention, and signing-material cleanup all passed.
- Signed IPA artifact `9991092156` was retained with SHA-256 digest
  `7b63698317436d02657eefc30853fc0ebcc0363ce6d675159427bc084cc98389`.
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
- Unified-folder architecture boundary gate: passed locally.
- Unified-folder release-hygiene gate: passed locally.
- TestFlight build-number guard self-test: passed locally.
- Unified-folder whitespace audit: passed locally.
- Unified-folder validation run
  [#243](https://github.com/Frankbell84/KeyHollow/actions/runs/34033056486)
  at branch head `7862ec9` and exact code commit `c88fbf7`: passed in 21m00s.
- Mac simulator build, complete regression and launch suite, release hygiene,
  architecture enforcement, build-number guard, and packaged-thumbnail checks:
  passed in 6m20s.
- Swift CodeQL: passed in 20m51s with no failed security gate.
- Simulator artifact `9989340664` was recorded with SHA-256 digest
  `0bb1c9562fcac8d6a42a1690fd54d6860f277c379293087e4db38a30e3a8d52d`.
- Security-test artifact `9989342373` was recorded with SHA-256 digest
  `757da37170a960f0008ed02994eb26aa5351ad1cb028845387d963714af8fa88`.
- App Store Connect was checked immediately before release preparation: Build
  32 is complete and no Build 33 exists.
- Reserved Build 33 for the unified-gallery correction and synchronized the app
  and embedded thumbnail extension build numbers.
- Restricted the signed upload workflow to `main` or the exact immutable
  `delivery/unified-folder-gallery` branch.
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
- Corrected gallery-parity CI run
  [#231](https://github.com/Frankbell84/KeyHollow/actions/runs/34000437184)
  at `1d4fb12`: passed.
- Mac simulator build, all 106 unit tests, launch tests, release hygiene,
  architecture enforcement, build-number guard, and packaged-thumbnail checks:
  passed in 8m16s.
- Swift CodeQL: passed in 17m26s with no failed security gate.
- Security-test artifact `9979413820` was recorded with SHA-256 digest
  `d67efc8fb12bf710184edcf98994a828d3bdc45a11bbd48c1701435043fbc954`.
- The exact validated correction commit is `1d4fb12`; it has not been uploaded
  to TestFlight and is not present in Build 30.
- Frank explicitly approved the separate Build 31 TestFlight delivery after the
  distinction between Build 30 and the corrected source candidate was clarified.
- Updated the app and embedded thumbnail extension together to Build 31 and
  limited the production upload workflow to the new exact delivery branch,
  `delivery/gallery-parity-correction`.
- Exact Build 31 release-source run
  [#233](https://github.com/Frankbell84/KeyHollow/actions/runs/34001565564)
  at `bc045e4`: passed.
- Mac simulator build, all 106 unit tests, launch tests, release hygiene,
  architecture enforcement, build-number guard, and packaged-thumbnail checks:
  passed in 9m28s.
- Swift CodeQL: passed with no failed security gate.
- Simulator artifact `9979760402` was recorded with SHA-256 digest
  `2a382575cdc4bca6fe7031373a2fdcab9e616e478bffa84034accff83bc31d38`.
- Security-test artifact `9979762432` was recorded with SHA-256 digest
  `417493a49b58c9cd767e770327c6228ecf340ea7faef8f1043d5dd77bc63aab6`.
- Guarded TestFlight upload run
  [#41](https://github.com/Frankbell84/KeyHollow/actions/runs/34002768326)
  completed successfully in 2m15s from exact release commit `bc045e4`.
- Release hygiene, production identity, unused Build 31 verification, cloud
  signing, archive/module hygiene, signed IPA export, Apple upload, artifact
  retention, and signing-material cleanup all passed.
- Apple finished processing Build 31. It is `Ready to Submit` and already
  assigned to `KeyHollow Internal`; no App Store review state was changed.
- Added one presentation-only selection model that represents both photo and
  general-file records without owning plaintext or storage capabilities.
- General-file tiles now participate in selection mode with the same tap,
  checkmark, accessibility state, and long-press `Select` entry as photo tiles.
- `Select All`, `Deselect All`, the header count, and Delete now cover every
  visible photo and general file while each deletion remains routed to its own
  protected store.
- `Save to Photos` remains intentionally scoped to selected photo-store records;
  it is disabled for file-only selections.
- Added regression tests proving mixed selection/counting and kind-safe
  reconciliation even when a photo and general file share the same UUID.
- Mixed-selection CI run
  [#237](https://github.com/Frankbell84/KeyHollow/actions/runs/34003421923)
  at exact commit `1fd4338`: passed in 23m10s.
- Mac simulator build, complete unit and launch suite, release hygiene,
  architecture enforcement, build-number guard, and packaged-thumbnail checks:
  passed in 6m47s.
- Swift CodeQL: passed in 22m25s with no failed security gate.
- Simulator artifact `9980259722` was recorded with SHA-256 digest
  `3401edb24ad7a332bdb1011581f4dbaa81fdf02f5f4282789b85f520f066e7ef`.
- Security-test artifact `9980261496` was recorded with SHA-256 digest
  `dcd9c205ed94a952149615a0fb8e8c16d3715b8fa5de152bc80b61cbcb544dab`.
- Frank explicitly approved the next guarded TestFlight delivery as Build 32.
- Updated the app and embedded thumbnail extension together to Build 32 and
  limited production upload permission to the exact immutable branch
  `delivery/mixed-gallery-selection`.

## Blockers

- No engineering, validation, signing, or upload blocker remains.
- Apple processing and Internal-group availability are pending external state.

## Next action

Monitor App Store Connect until Build 33 finishes processing, then confirm it is
assigned only to `KeyHollow Internal`. Keep `Family`, merge, and App Store review
untouched pending separate approval and device feedback.

## Frank's decision required

- Frank explicitly approved this Phase 4 TestFlight delivery and requested the
  `Family` group receive Build 30.
- Build 30 is now `Testing` in both `KeyHollow Internal` and `Family`, with
  automatic tester notification enabled.
- Frank explicitly approved the separate Build 31 TestFlight upload.
- Build 31 is processed and assigned only to `KeyHollow Internal`; Frank's
  device feedback requires a selection correction before any `Family` rollout.
- Frank explicitly approved the guarded Build 32 TestFlight upload for device
  verification.
- Frank approved beginning the unified folder-gallery correction.
- Frank explicitly approved the next Internal-only TestFlight upload; Build 33
  is the verified next unused number.
- Build 33 was uploaded successfully from exact approved source `7503a68`; no
  further upload decision is pending while Apple processes it.
- Any TestFlight upload after Build 33, `Family` rollout, merge, or App Store
  review change still requires its own decision after corrected visual and
  automated evidence.
- Any App Store review change remains out of scope without separate explicit
  approval.
