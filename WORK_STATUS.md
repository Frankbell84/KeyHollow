# KeyHollow Work Status

Updated: 2026-09-07
Branch: `delivery/gallery-grid-normalization`
Parent validation head: `85e8d9e` (closed gallery-grid validation checkpoint)

## Current task

Prepare the twice-validated unified-gallery grid correction as the next isolated
Internal-only TestFlight release candidate. Reserve the next unused Apple build
number, synchronize both app targets, restrict production upload permission to
the exact delivery branch, and complete all exact-source release gates. Stop
before the signed upload; do not alter `Family`, merge state, or App Store review
state.

## Completed work

- App Store Connect authoritatively shows Build 36 as the latest completed
  upload; Build 37 is unused and available for this release candidate.
- Created isolated release branch `delivery/gallery-grid-normalization` from the
  closed validated correction head `85e8d9e`. No build-number or production-
  workflow source has been changed yet.
- Frank physically confirmed that Build 36 folders work and selected photos and
  files can be moved successfully.
- Build 36 screenshots exposed one remaining presentation defect: folders,
  screenshots, photos, and non-photo files can produce unequal tile heights;
  the grid centers shorter cells within the row, making row tops and selection
  indicators appear staggered.
- Confirmed the correction belongs entirely to the independently compiled
  `KeyHollowGalleryUI` module. Protected storage, encryption, authenticated
  folder membership, and the accepted batch-move operation do not need changes.
- Approved visual contract: every item uses the same fixed media viewport and
  metadata footer. Images preserve their original aspect ratio with aspect-fill
  cropping inside that viewport; the underlying full image is never resized or
  altered.
- Created and pushed isolated branch `fix/gallery-grid-normalization` from the
  exact Build 36 delivery head before modifying implementation source.
- Rebuilt the shared tile surface around a neutral square viewport whose size
  cannot be influenced by a portrait, landscape, screenshot, or placeholder's
  intrinsic dimensions. Image content remains aspect-fill and clipped only for
  its thumbnail presentation.
- Removed the folder-only `GeometryReader` layout and routed folders through
  the same shared media viewport and fixed 56-point metadata footer used by
  every photo and general-file tile.
- Set all three grid columns to explicit top alignment and centralized column
  count and spacing with the existing tile metrics, eliminating implicit
  vertical centering of shorter cells.
- Extended gallery regression coverage for the centralized three-column
  geometry and strengthened the architecture gate to reject a return to
  variable folder geometry or a non-top-aligned grid.
- Local release hygiene, architecture enforcement, build-number guard self-
  test, and whitespace/diff checks passed. Exact-source Mac compilation, full
  regression/security tests, and Swift CodeQL were then required remotely.
- Opened isolated draft review
  [#45](https://github.com/Frankbell84/KeyHollow/pull/45) against `main` for the
  presentation-only correction; it remains unmerged and has not changed any
  TestFlight group or App Store review state.
- Exact implementation-source validation run
  [#279](https://github.com/Frankbell84/KeyHollow/actions/runs/34108714858)
  passed every mandatory gate at commit `5036c8b`.
- Mac simulator build, complete regression/security and launch suites, release
  hygiene, architecture enforcement, build-number guard, and packaged-
  thumbnail verification passed in 11m24s.
- Swift CodeQL passed in 30m50s with no failed security gate.
- Simulator artifact `10013806986` was recorded with SHA-256 digest
  `b4928b82d967a56c696c2cbcd365f55325b02c4deb487873b1e48c46caae4ed4`.
- Security-test artifact `10013814113` was recorded with SHA-256 digest
  `13d9c769bdca1635bc324fbd2cb8caa15279b767d6698b6aa5613751d3e2e45f`.
- Exact documentation-head reproducibility run
  [#280](https://github.com/Frankbell84/KeyHollow/actions/runs/34111719875)
  passed every mandatory gate at commit `74c44d4`.
- Reproducibility Mac simulator build, complete regression/security and launch
  suites, release hygiene, architecture enforcement, build-number guard, and
  packaged-thumbnail verification passed in 7m56s.
- Reproducibility Swift CodeQL passed in 26m30s with no failed security gate.
- Simulator artifact `10014857665` was recorded with SHA-256 digest
  `cfa52b51c9a5e4424c2e4eeaaeeb68714f76207cee71b5d9e21ca95b4db0097e`.
- Security-test artifact `10014860871` was recorded with SHA-256 digest
  `b29f44e593cc440711e8a1a50370957b095af25f059c27b6c2d99c21070645fc`.
- Frank's physical-device report confirmed that selected gallery items cannot
  currently be moved to an existing folder; screenshots show the selection
  count is correct while the toolbar omits a folder action.
- Paused Encrypted Video Support delivery after its implementation commit
  `dcef6d5` passed exact-source Mac build/tests and Swift CodeQL. Its evidence is
  preserved on `feature/encrypted-video-support` at `c56edff`; no video work is
  mixed into this correction.
- Created `fix/batch-move-to-folder` directly from exact hardened `origin/main`
  commit `3dc0f4a` so the correction can be reviewed, tested, delivered, and
  merged independently.
- Confirmed the existing Folder Presentation store owns only encrypted folder
  membership metadata and already supports both photo and general-file
  references. The missing behavior is the narrow batch operation and unified
  gallery composition, not a storage migration or encrypted-content move.
- Backup Verification Center remains next after this correction and Encrypted
  Video Support close; no work on that add-on has begun.
- Added a visible multi-select Move menu alongside save/export and delete. At
  the vault root it lists every folder; inside a folder it also offers Vault
  Root and excludes the current destination.
- Added a source-neutral selected-reference bridge so photo-only, file-only,
  video-file, and mixed selections all use the same folder-membership path.
- Added an atomic batch move to `KeyHollowFolderPresentationAddOn`. It validates
  the destination first, removes prior memberships for the complete set, and
  writes the new encrypted manifest once without touching protected content.
- Preserved the existing single-item move surface by routing it through the
  same batch operation, eliminating parallel implementations.
- Added regression tests for mixed photo/file movement, return to the vault
  root, and failure against a missing destination with an unchanged manifest.
- Strengthened the architecture gate and durable behavior baseline so removal
  of the selection Move action or reintroduction of content-moving behavior is
  review-visible.
- Local release hygiene, architecture enforcement, build-number guard self-
  test, and whitespace/diff checks passed. Exact-source Mac compilation, full
  regression/security tests, and Swift CodeQL are required next.
- Opened isolated draft review
  [#43](https://github.com/Frankbell84/KeyHollow/pull/43) against `main`; it
  remains non-mergeable and contains only the correction and its status
  checkpoint.
- Exact-source validation run
  [#270](https://github.com/Frankbell84/KeyHollow/actions/runs/34074994541)
  passed every mandatory gate at implementation commit `fac2eb1`.
- Release hygiene, architecture enforcement, build-number guard, project
  generation, simulator compilation, packaged-thumbnail verification, and the
  complete unit/launch/security suite passed in the 5m55s build-and-test job.
- Swift CodeQL passed in 26m01s with no failed security gate or unresolved
  finding.
- Security-test artifact `10001823710` recorded SHA-256 digest
  `5e61cf7f1785147b5272d9179e8948c36e0852f4e8ca1780999fa35f250c0efe`.
- Simulator artifact `10001822388` recorded SHA-256 digest
  `4120a1d0a2b9e5ca0d9bb2c51de1fa869deb9dd65932ee2e14911aa0e78f6286`.
- Final documentation-head reproducibility run
  [#274](https://github.com/Frankbell84/KeyHollow/actions/runs/34076597749)
  passed every mandatory gate at exact branch head `6117aa2`.
- The repeated simulator build, complete unit/launch/security suite, release
  hygiene, architecture enforcement, build-number guard, and packaged-thumbnail
  check passed in 9m44s. Swift CodeQL passed in 23m27s with no failed gate.
- Reproducibility security-test artifact `10002441788` recorded SHA-256 digest
  `3fda0124213ddb613d268fb607e1c7ec5edd494ed13b0d44dc264ce13354b924`.
- Reproducibility simulator artifact `10002439591` recorded SHA-256 digest
  `da7ce041dd25837f5b106fcbeead41ff15e74c76984163ca152bfe197d1c461a`.
- Created `delivery/batch-move-to-folder` directly from that exact green head;
  no implementation source changed during the branch transition.
- Reserved Build 36 and synchronized `CURRENT_PROJECT_VERSION` for both the app
  and embedded vault-thumbnail extension.
- Replaced the obsolete Build 35 delivery exception with only the exact
  `delivery/batch-move-to-folder` branch. Feature and unrelated delivery
  branches remain unable to invoke the signed upload workflow.
- Opened isolated draft release review
  [#44](https://github.com/Frankbell84/KeyHollow/pull/44) from the exact Build 36
  delivery branch. The review remains non-mergeable and no tester group or App
  Store review state was changed.
- Exact Build 36 release-source validation run
  [#275](https://github.com/Frankbell84/KeyHollow/actions/runs/34100902710)
  passed every mandatory gate at commit `2668da4`.
- Build 36 project generation, simulator compilation, release hygiene,
  architecture enforcement, build-number guard, packaged-thumbnail check, and
  the complete unit/launch/security suite passed in 8m37s.
- Swift CodeQL passed in 24m27s with no failed security gate or unresolved
  finding.
- Build 36 security-test artifact `10010697401` recorded SHA-256 digest
  `5186b6404be7215e9853fd3c41cfde527f3f637433dbec74646d47755ec5ca77`.
- Build 36 simulator artifact `10010694262` recorded SHA-256 digest
  `b5014f949890dd2d5bf1c201abc94c112d23f41d8e5bd4beae315c878302b180`.
- Final Build 36 evidence-head reproducibility run
  [#276](https://github.com/Frankbell84/KeyHollow/actions/runs/34103379382)
  passed every mandatory gate at exact delivery head `9b3d353`.
- The repeated complete build/test suite passed in 7m53s, and Swift CodeQL
  passed in 18m11s with no failed security gate or unresolved finding.
- Final-head security-test artifact `10011633718` recorded SHA-256 digest
  `dacf08acc7c6b46a2087b81a5b1064aef349776d3c10fa5e0e3645956aae673b`.
- Final-head simulator artifact `10011630800` recorded SHA-256 digest
  `1886eead573fe4de0d9e24ad88ea932dc3a43b6db14455d0af7efd29b5a0fac6`.
- After Frank's explicit authorization, guarded TestFlight workflow
  [#46](https://github.com/Frankbell84/KeyHollow/actions/runs/34105375436)
  successfully archived, signed, validated, and uploaded Build 36 from exact
  green head `9b3d353` in 3m52s.
- No `Family` assignment, merge, or App Store review action was performed.
- App Store Connect completed processing Build 36 and lists it as `Ready to
  Submit` in exactly the `KeyHollow Internal` group. `Family` is not attached.
- Frank confirmed that unified swipe navigation across Photo-library images and
  image files belongs in a separate later build; Build 36 remains limited to
  the folder-move correction.

- Created `feature/general-file-export-parity` directly from merged Build 34
  baseline `ec25031`; no release branch or production state is being changed.
- Confirmed the secure general-file export and temporary-file cleanup engine
  already exist in `KeyHollowGeneralFileSupportAddOn`. The functional gap is
  limited to missing export controls in the unified gallery composition layer.
- Added source-aware selection actions: photo-only selections save to Photos,
  file-only selections export through the system share sheet, and mixed
  selections present both choices without crowding the bottom action bar.
- Added `Export to Files` to each general-file gallery context menu and a visible
  per-row export button in Vault Files, so individual export no longer depends
  on discovering a long-press action.
- Reused the authenticated `prepareExport` boundary and guaranteed temporary
  plaintext cleanup after the system interaction; the encrypted store and vault
  transfer formats remain unchanged.
- Extracted the system share-sheet adapter into one app-owned presentation
  component, removing duplicate routing risk while keeping UIKit outside every
  protected module.
- Added regression coverage for photo-only, file-only, mixed, and empty
  selection transfer modes, plus architecture markers that fail if unified
  general-file export wiring is removed.
- Opened draft PR #40 against `main` with an exact implementation checkpoint and
  explicit evidence checklist; the branches report no merge conflict.
- Remote validation run
  [#257](https://github.com/Frankbell84/KeyHollow/actions/runs/34050577957)
  passed every required gate at exact application source commit `2a0ce9f` and
  evidence head `adb3575` in 25m39s.
- Mac simulator compilation, packaged-thumbnail verification, the complete
  unit/launch/security suite, release hygiene, architecture enforcement, and
  the build-number guard all passed in the 9m43s build-and-test job.
- Swift CodeQL passed in 23m46s with no failed security gate.
- Security-test artifact `9994572552` was recorded with SHA-256 digest
  `7a0bdc712ade36168c041873e2524404e47f083fd559645af8c5428357d2500d`.
- Simulator artifact `9994570329` was recorded with SHA-256 digest
  `2c55f7c2699eb199ba2c18fa7d9ace72cb0cd39aaf2863cf7682ede881292623`.
- Final documentation-head reproducibility run
  [#258](https://github.com/Frankbell84/KeyHollow/actions/runs/34052071992)
  passed every required gate at head `eb1b01c` in 27m12s; the exact application
  implementation remained `2a0ce9f`.
- The repeated Mac build, complete unit/launch/security suite, release hygiene,
  architecture enforcement, build-number guard, and packaged-thumbnail check
  passed in 6m29s. Swift CodeQL passed in 27m03s.
- Reproducibility security-test artifact `9994938931` was recorded with SHA-256
  digest `3999176ae22ce53cee09c6d23698b1d0db3b10cccb449b4f34a2e09714bad70f`.
- Reproducibility simulator artifact `9994937192` was recorded with SHA-256
  digest `b7fb68d4aaf7de375414eb5ee72c3bcda6793bd14bce5657cd3b65b3077cfb48`.
- Created `delivery/general-file-export-parity` from the exact validated review
  head `eb1b01c`; production, TestFlight, tester groups, and App Store review
  state remain unchanged.
- Reserved Build 35 and synchronized `CURRENT_PROJECT_VERSION` for both the app
  and embedded vault-thumbnail extension.
- Replaced the obsolete Build 34 delivery-branch exception with the exact
  `delivery/general-file-export-parity` branch. Feature and unrelated delivery
  branches remain unable to invoke the signed upload job.
- Build 35 release-source architecture, release-hygiene, build-number self-test,
  and diff-integrity gates passed locally.
- Opened draft release review
  [#41](https://github.com/Frankbell84/KeyHollow/pull/41) against `main`; it
  remains a non-mergeable draft with TestFlight, physical-device, merge, and
  App Store evidence explicitly unchecked.
- Exact Build 35 release-source run
  [#259](https://github.com/Frankbell84/KeyHollow/actions/runs/34054030844)
  passed at release checkpoint `dd337d6` in 31m18s.
- Mac simulator compilation, packaged-thumbnail verification, complete
  unit/launch/security suite, release hygiene, architecture enforcement, and
  build-number guard passed in 6m06s.
- Swift CodeQL passed in 31m18s with no failed security gate or annotation.
- Build 35 security-test artifact `9995497594` recorded SHA-256 digest
  `f4426d66c3b227ba752758634c06dd29c9a7b26d4b9beb80aa014226184491bd`.
- Build 35 simulator artifact `9995496170` recorded SHA-256 digest
  `0d8f69c3fa8978b6d40a0bfd647c985d32c883b7acab48cd5caf6fce0ea2e0c4`.
- Final documentation-head reproducibility run
  [#260](https://github.com/Frankbell84/KeyHollow/actions/runs/34055783323)
  passed at head `dc5f539`; build/tests passed in 5m48s and Swift CodeQL passed
  in 27m43s.
- Frank explicitly approved dispatching the guarded signed Build 35 TestFlight
  upload after the full release-source and reproducibility evidence passed.
- Guarded TestFlight upload run
  [#45](https://github.com/Frankbell84/KeyHollow/actions/runs/34058831705)
  completed successfully in 2m46s from exact branch head `d5b816b`.
- The upload workflow independently confirmed Build 35 was unused in App Store
  Connect before installing signing material. Release hygiene, production
  identity, project generation, cloud signing, archive/module hygiene, signed
  IPA export, Apple upload, artifact retention, and signing-material cleanup all
  passed.
- Signed Build 35 IPA artifact `9996841104` recorded SHA-256 digest
  `3db8cf453f9f2c6ea0a51c5eece3b3f1a62de18382b8ec0974e59982f4f87fbe`.
- Apple finished processing Build 35. Its upload status is `Complete`, its
  TestFlight status is `Ready to Submit`, and the upload date is September 6,
  2026 at 4:46 PM EDT.
- App Store Connect automatically lists `KeyHollow Internal` for Build 35.
  `Family` is not attached, and no tester-group action was taken during this
  verification.
- Frank physically tested Internal Build 35 and confirmed the general-file
  export behavior works.
- Frank explicitly approved Build 35 `Family` rollout, PR #41 merge, and
  post-merge hardening of the exact accepted source.
- Added Build 35 to the `Family` TestFlight group with automatic tester
  notification and focused guidance covering individual general-file export,
  mixed-content opening and selection, encrypted vault transfer, metadata, and
  layout regressions. App Store Connect now reports Build 35 as `Testing` in
  both `KeyHollow Internal` and `Family`.
- Created `feature/secure-unified-file-preview` directly from hardened checkpoint
  `0d86997`; the validated gallery and release branches remain untouched.
- Mapped the existing routing seam: Photos-origin images use the full-screen
  decrypted viewer, while all general-file taps currently open the management
  queue regardless of type.
- Added the independently compiled, dependency-free
  `KeyHollowSecurePreviewAddOn` under strict concurrency with warnings treated
  as errors.
- Added one source-neutral image-preview policy and viewer for Photos-origin and
  Files-origin encrypted images; image detection uses declared type with a safe
  filename-extension fallback.
- Kept authentication, decryption, encrypted stores, session control, saving,
  and deletion in the application composition shell. The add-on receives only
  bounded immutable metadata, validated in-memory image bytes, and action
  closures; it has no disk, network, key, session, or store capability.
- Added encoded-size and decoded-pixel ceilings before the viewer accepts an
  image, and clear the lifecycle-owned preview when the sheet closes or the
  active vault session changes.
- Removed the obsolete app-owned photo viewer and routed both image origins
  through the same preview surface. PDFs and other non-image files continue to
  open the existing file-management surface.
- Added policy, invalid-payload, validated-image, cross-source routing, and
  non-image routing regression coverage.
- Strengthened the architecture gate to pin exact module ownership, require a
  dependency-free target and narrow import allowlist, reject protected stores,
  keys, sessions, disk, and network capabilities, and prevent the obsolete
  viewer from returning.
- Published exact implementation commit `228f927` to
  `feature/secure-unified-file-preview` and opened isolated draft PR
  [#38](https://github.com/Frankbell84/KeyHollow/pull/38), stacked directly on
  the validated gallery-hardening branch so the review contains only this
  phase's two commits and seven changed files.
- Remote validation run
  [#251](https://github.com/Frankbell84/KeyHollow/actions/runs/34044991236)
  passed every Mac build, test, packaging, and security gate at that exact
  source commit.
- Created `delivery/secure-unified-file-preview` directly from the validated
  feature head. The application source remains exact commit `228f927`; the later
  commit is evidence-only status documentation.
- Reserved Build 34 and synchronized `CURRENT_PROJECT_VERSION` for both the app
  and embedded vault-thumbnail extension.
- Replaced the obsolete Build 33 delivery-branch exception with the exact
  `delivery/secure-unified-file-preview` branch. Feature and unrelated delivery
  branches remain unable to run the signed upload workflow.
- Opened draft release review
  [#39](https://github.com/Frankbell84/KeyHollow/pull/39) against `main` so the
  full Build 34 source is exercised by the mandatory Mac and security workflows.
- Exact Build 34 release-source run
  [#252](https://github.com/Frankbell84/KeyHollow/actions/runs/34046844487)
  passed the Mac build, complete unit/launch/security suite, packaged-thumbnail
  verification, and Swift CodeQL at release commit `4f865b6`.
- Guarded TestFlight upload run
  [#44](https://github.com/Frankbell84/KeyHollow/actions/runs/34048323420)
  completed successfully from exact release commit `4f865b6`.
- The upload workflow independently confirmed Build 34 was unused in App Store
  Connect before installing signing material. Release hygiene, production
  identity, project generation, cloud signing, archive/module hygiene, signed
  IPA export, Apple upload, artifact retention, and signing-material cleanup all
  passed.
- Apple finished processing Build 34. It is `Ready to Submit` and assigned only
  to `KeyHollow Internal`; `Family`, merge, production, and App Store review
  state were not changed.
- Frank completed the physical-device acceptance gate on Internal Build 34:
  Photos-origin and Files-origin images both open correctly in the secure image
  viewer, while non-image files continue to open through the file-management
  route.
- Frank confirmed the Build 33 folder/file UI is solid on a physical iPhone;
  that exact behavior is frozen as the hardening baseline.
- Replaced all photo, general-file, and folder storage records at the compiled
  gallery boundary with immutable `VaultGalleryPresentationItem` and
  `VaultGalleryFolder` values.
- Kept the storage-backed routing union private to the application composition
  layer; only opaque typed IDs, normalized display metadata, and action closures
  now cross into `KeyHollowGalleryUI`.
- Removed every content/add-on dependency from the `KeyHollowGalleryUI` target;
  it now compiles as a dependency-free static library with strict concurrency
  and warnings-as-errors.
- Strengthened CI to pin the module's exact source ownership, require the neutral
  folder/item contract, reject generic storage-model bypasses, reject any target
  dependency, and preserve the protected-capability/import denylist.
- Added module-contract regression coverage for immutable item/folder values and
  retained the mixed-selection, naming, ordering, geometry, and thumbnail tests.
- Remote run #248 proved the architecture rules before the Apple compile, then
  caught one application-shell integration error: the photo branch of the new
  presentation mapper did not explicitly return its immutable value. The fix is
  an explicit return only; it changes no storage, UI, or security behavior.
- Corrected run #249 passed the Apple compile, complete unit/launch/security
  suite, packaged thumbnail verification, and Swift CodeQL at exact source
  commit `1d423c8`.
- Created `refactor/gallery-ui-module` directly from exact validated Build 33
  source `7503a68`; no delivery or production branch was modified.
- Added `KeyHollowGalleryUI` as an independently compiled static library under
  strict concurrency with warnings treated as errors.
- Removed the gallery grid, shared tile renderers, folder tiles, and selection
  model from the application target so those sources compile only in the new
  module.
- Replaced the app-owned `LazyVGrid` with a module-owned grid that receives only
  immutable gallery folder/item values and view-building closures.
- Kept authenticated sessions, encrypted stores, cryptographic capabilities,
  transfer coordination, plaintext, and networking out of the UI module.
- Extended architecture enforcement to require the module target, app-source
  exclusions, explicit composition, a narrow import allowlist, and the absence
  of protected capability symbols.
- Updated gallery regression tests to compile against the extracted module
  directly.
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

## Test and build status

- General-file export parity architecture gate: passed locally.
- Release hygiene and TestFlight build-number guard self-test: passed locally.
- Diff whitespace validation: passed locally.
- Build 35 release-source run
  [#259](https://github.com/Frankbell84/KeyHollow/actions/runs/34054030844)
  at exact release checkpoint `dd337d6`: passed.
- Mac compile, package verification, complete unit/launch/security suite,
  architecture and release gates: passed in 6m06s.
- Swift CodeQL build and vulnerability analysis: passed in 31m18s with no
  failed security gate or annotation.
- Guarded Build 35 TestFlight upload run
  [#45](https://github.com/Frankbell84/KeyHollow/actions/runs/34058831705):
  passed every release, signing, archive, Apple-upload, retention, and cleanup
  step in 2m46s.
- Secure-preview architecture, release-hygiene, build-number, and diff-integrity
  gates: passed locally.
- Secure-preview validation run
  [#251](https://github.com/Frankbell84/KeyHollow/actions/runs/34044991236)
  at exact source commit `228f927`: passed.
- Mac project generation, independent secure-preview target compilation,
  simulator build, complete unit/launch/security suite, release hygiene,
  architecture enforcement, build-number guard, and packaged-thumbnail
  verification: passed.
- Swift CodeQL build and vulnerability analysis: passed with no failed security
  gate.
- Simulator artifact `9992900450` recorded SHA-256 digest
  `3d5b8fd6059d5bdb45aa60f295c4a1787fd4d8e87aa0f15ee0ed9592389d7526`.
- Security-test artifact `9992901544` recorded SHA-256 digest
  `3b56b84c1c7f9a0e96cbfade803bfa12dd410faaace69bbd9dcc5a8756326183`.
- Build 34 release-source architecture, release-hygiene, build-number self-test,
  and diff-integrity gates: passed locally.
- Build 34 release-source validation run
  [#252](https://github.com/Frankbell84/KeyHollow/actions/runs/34046844487)
  at exact release commit `4f865b6`: passed.
- Simulator artifact `9993432906` recorded SHA-256 digest
  `033adaa055a29fdf7103198844f5260f6d2b0d1cc27ae2418b3ea2f2e8cc5e99`.
- Security-test artifact `9993433950` recorded SHA-256 digest
  `2cfb421da74cc7e94d1f04901ddd7f05fe3f911341b853533394b103faeadd3c`.
- Guarded Build 34 upload run
  [#44](https://github.com/Frankbell84/KeyHollow/actions/runs/34048323420):
  passed every release, signing, archive, upload, retention, and cleanup step.
- Signed IPA artifact `9993824241` recorded SHA-256 digest
  `e6bedb91499601abde59770253bac10982fb428ab05906b52993f149e9f38207`.
- App Store Connect: Build 34 processing complete, `Ready to Submit`, assigned
  only to `KeyHollow Internal`.
- Gallery UI module architecture boundary gate: passed locally.
- Gallery UI module release-hygiene gate: passed locally.
- Gallery UI module TestFlight build-number guard self-test: passed locally.
- Gallery UI module whitespace/diff integrity check: passed locally.
- Hardened source-neutral contract gate: passed locally.
- Dependency-free target/source-ownership gate: passed locally.
- Initial remote hardening run
  [#248](https://github.com/Frankbell84/KeyHollow/actions/runs/34042394691):
  architecture, hygiene, build-number, and project-generation gates passed; the
  simulator compile stopped at the missing explicit return before tests ran.
- Corrected remote hardening run
  [#249](https://github.com/Frankbell84/KeyHollow/actions/runs/34042716549)
  at exact source commit `1d423c8`: passed.
- Mac project generation, independently compiled gallery target, app/simulator
  build, complete unit and launch/security suite, release hygiene, architecture
  enforcement, build-number guard, and packaged-thumbnail verification: passed.
- Swift CodeQL build and vulnerability analysis: passed with no failed security
  gate.
- Simulator artifact `9992271568` recorded SHA-256 digest
  `af28b2ecdce95abb273070d844b31f0f938b57c78736a4da672178bac6e909ed`.
- Security-test artifact `9992272609` recorded SHA-256 digest
  `9fe0129b8be364321cbd027ef770e26d2db1e233708c2b5b9c556b64ec528e27`.
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

## Deferred roadmap additions

- **Break-in Reports / Intruder Capture:** optional, local-only records of
  failed access attempts. Design must avoid creating a plaintext vault-existence
  signal, must have bounded retention, and must not weaken lockout behavior.
- **App Icon Camouflage:** optional alternate icons such as calculator, notes,
  or stock-tracker styles. Before implementation, verify current App Store
  policy, make the setting reversible, and preserve an unambiguous recovery
  path for the owner.
- **Vault Escape Hatch migration:** an isolated iOS Share Extension that accepts
  only files the user explicitly shares from another app and hands them to a
  protected KeyHollow import path for immediate encryption. The extension must
  not enumerate vaults, retain plaintext, or possess a general vault-unlock
  capability. Competitor-specific three-step migration guides may be added as
  onboarding after each supported app's current export behavior is verified.
- These roadmap items begin only after the current gallery normalization,
  separate swipe-navigation correction, and already-planned security/backup
  work. None is part of the present release candidate.

## Blockers

- No known protected-data, folder-move, build, security-scan, upload, or tester-
  assignment blocker. The exact implementation and documentation heads are
  both green. Physical-device visual acceptance remains required before merge
  or wider rollout.

## Next action

Prepare the next unused Internal-only release source, verify its build number
against App Store Connect, and require exact-source Mac build/tests and Swift
CodeQL. Stop before dispatching the signed TestFlight upload for explicit
approval. Do not alter `Family`, merge, or App Store review state.

## Frank's decision required

- Frank approved the isolated gallery-normalization correction after confirming
  that the fixed thumbnail viewport will crop with preserved aspect ratio rather
  than stretch or alter images.
- Frank approved creating draft correction PR #43 and proceeding through the
  full review gates. Those gates are complete and green.
- Frank requested completion for testing. The isolated release source may be
  prepared and validated; dispatching the signed TestFlight upload will be
  confirmed at the final external-action boundary.
- Frank explicitly approved creating draft Build 36 release PR #44. The review
  exists and exact release-source CI is green. The signed upload, tester-group
  assignment, merge, and App Store review remain separate decisions.
- Frank explicitly authorized the signed Build 36 upload to `KeyHollow
  Internal`; guarded workflow #46 succeeded. `Family` rollout, merge, and App
  Store review remain separate decisions.
- Build 36 processing and Internal-only assignment are complete. Frank's
  physical-device acceptance is now required before merge; `Family` remains a
  separate later decision.
- Frank confirmed the missing image-swipe behavior should be corrected in a
  separate build rather than expanding Build 36.
- Frank requested that Break-in Reports / Intruder Capture, App Icon Camouflage,
  and the Vault Escape Hatch migration/share extension be retained as later
  add-ons. Their implementation order and detailed privacy/product design remain
  later decisions; none is authorized for the current release candidate.

- Frank explicitly approved creating draft Build 35 release PR #41. That review
  is open and its exact release-source CI is green.
- Frank explicitly approved the guarded Build 35 TestFlight upload after exact
  release-source and documentation-head CI passed.
- Build 35 upload approval is complete. `Family` rollout, merge, and any App
  Store review change still require separate explicit approval.
- Build 35's upload and processing are complete. App Store Connect automatically
  lists `KeyHollow Internal`; `Family` is not yet attached. Family rollout and
  merge were separate gates and are now explicitly approved after acceptance.
- Frank completed physical acceptance and explicitly approved both Build 35
  `Family` rollout and PR #41 merge, plus hardening of the merged baseline.
- Build 35 is now `Testing` in both `KeyHollow Internal` and `Family`; the
  approved tester-group rollout is complete.
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
- Frank approved resolving the remaining gallery-isolation caveat by extracting
  the presentation into its own compiled module.
- Frank approved hardening the current modular safety nets before any secure
  file-opening feature begins.
- Frank approved beginning the first secure unified-opening milestone.
- Frank explicitly approved the next Internal-only TestFlight delivery for the
  validated secure-preview milestone. Build 34 is processed and assigned only
  to `KeyHollow Internal`.
- Frank confirmed Build 34 passes physical-device preview routing and explicitly
  approved merging release PR #39.
- Frank explicitly approved adding Build 34 to the `Family` TestFlight group.
- Any TestFlight upload after Build 34, `Family` rollout, merge, or App Store
  review change still requires its own decision after corrected visual and
  automated evidence.
- Build 35 draft release review creation is complete; TestFlight upload, tester
  assignment, merge, and App Store submission remain separate later decisions.
- Any App Store review change remains out of scope without separate explicit
  approval.
