# KeyHollow Work Status

Updated: 2026-09-18

This is the authoritative operational resume point. Historical Build 38
evidence remains in `docs/PROJECT_CHECKPOINT.md`.

## Latest checkpoint: Build 54 portrait-video dismissal

This checkpoint supersedes the older Build 54 preparation/approval steps below.
PR #88 merged as `5c998e4a67a90c0d492ef7ec49d31ecec81a4e42`.
Main CI #396 (`35405975479`), signing preflight #21 (`35407068071`),
and authorized Internal upload #64 (`35407486940`) passed. Apple completed
Build 54 processing and assigned it only to KeyHollow Internal; delivery UUID
is `dd08286a-55e9-400f-9772-8959d1575273`. Full evidence is in PR #88.

The user reports Build 54 works but portrait fullscreen video has no
discoverable close route, and requests downward-swipe dismissal. This is an
outstanding device defect, not unconditional acceptance of Build 54 or the
full folder-backup test matrix. Build 53 remains the accepted rollback.

The focused `codex/portrait-video-dismissal` repair restores AVKit's automatic
modal presentation instead of forcing generic UIKit fullscreen. Apple's
recommended presentation supplies the native fullscreen controls and
interactive dismissal while retaining the existing session-owned player,
replay, generation guards, and bounded terminal cleanup. See
https://developer.apple.com/videos/play/wwdc2019/503/ (fullscreen best practices).
No storage, cryptography, build number, or release-workflow change is included.
Required next evidence: exact-head macOS build/XCTest/CodeQL, review, and the
portrait-video dismissal device checks in `docs/DEVICE_TEST_PLAN.md` on a
separately packaged replacement Internal build. No device fix is claimed yet.

## Provenance

- Build 53 is the current accepted `KeyHollow Internal` baseline from exact
  signed binary source `1bf0907f4713b925a777240ecb5ece61b530d5bc`.
- PR [#85](https://github.com/Frankbell84/KeyHollow/pull/85) carried exact
  release head `c4a1d14d07ff6cf19932c355628a41fe5aad184c` through protected `main` as
  `1bf0907f4713b925a777240ecb5ece61b530d5bc`. PR CI run
  [#35307566629](https://github.com/Frankbell84/KeyHollow/actions/runs/35307566629)
  and exact-main CI run
  [#35308810509](https://github.com/Frankbell84/KeyHollow/actions/runs/35308810509)
  passed the complete build-and-test and Swift CodeQL gates.
- Protected no-upload signing preflight run
  [#35310336239](https://github.com/Frankbell84/KeyHollow/actions/runs/35310336239)
  passed for the exact protected-main source. Separately authorized upload run
  [#35310597859](https://github.com/Frankbell84/KeyHollow/actions/runs/35310597859)
  completed successfully. Retained IPA artifact `10532514544` is 2,422,453
  bytes and has SHA-256
  `5dea99deb68b7e493762dc63692ca4a08bc9a5766dd625c748e8eadc8173cb72`;
  Apple delivery UUID is `c3d28e79-6bf5-472c-9813-ee8e63664d9b`.
- App Store Connect processed Build 53 and assigned it to exactly
  `KeyHollow Internal`, with zero individual testers. Physical-iPhone testing
  confirmed that the formerly failing encrypted-video playback, background,
  return, and first correct-passcode unlock sequence now works. This acceptance
  records that reported regression result; it does not claim every extended
  permutation in `docs/DEVICE_TEST_PLAN.md` was exercised. No Family, external
  TestFlight, or App Store expansion is authorized.
- PR [#84](https://github.com/Frankbell84/KeyHollow/pull/84) merged the exact
  reviewed background-video unlock repair head
  `65e57bb8be8456474310e654126e1193dc13be7a` through protected `main` commit
  `925b5b539a72d0f8043d385d083b5b6293ecd19e`. PR CI run
  [#35304387976](https://github.com/Frankbell84/KeyHollow/actions/runs/35304387976)
  and exact merged-main CI run
  [#35305926384](https://github.com/Frankbell84/KeyHollow/actions/runs/35305926384)
  both passed.
- PR [#83](https://github.com/Frankbell84/KeyHollow/pull/83) merged the exact
  reviewed Build 52 release head
  `d2d2caa7cb5c0a89c899038f72983da7404a4d1f` through protected `main` commit
  `0dfc5a1faa5fd0664ead1df1d7ed5b5a43f1498e`; both resolve to exact tree
  `a60d448d81dded58e7cc6c366c8f9c7e7fdb2d1e`.
- PR CI run
  [#35277285149](https://github.com/Frankbell84/KeyHollow/actions/runs/35277285149)
  and exact merged-main CI run
  [#35279640351](https://github.com/Frankbell84/KeyHollow/actions/runs/35279640351)
  passed the complete build-and-test lane and Swift CodeQL.
- Protected Build 52 signing-only preflight run
  [#35282133029](https://github.com/Frankbell84/KeyHollow/actions/runs/35282133029)
  passed for the exact protected-main source without uploading or publishing.
  Separately authorized upload run
  [#35284768545](https://github.com/Frankbell84/KeyHollow/actions/runs/35284768545)
  then completed successfully. IPA artifact `10523584655` is 2,413,044 bytes
  and has SHA-256
  `4e62152e5a6f3c00fe4031c9f25c01fea9f5d228080c7f1279bfa13208c27f04`;
  Apple delivery UUID is `c1d1cc03-f011-41d9-8102-d7def57637d1`.
- App Store Connect completed processing Build 52, reports `Ready to Submit`,
  and assigns it only to `KeyHollow Internal`. Physical-device testing
  confirmed that the prior portrait-video blank-player defect was resolved,
  but subsequent testing found a separate release blocker: backgrounding while
  an encrypted video is playing can leave re-entry unable to complete with the
  correct passcode until KeyHollow is relaunched. Build 52 is therefore failed
  and unaccepted. It must not be expanded to Family, external TestFlight, or App
  Store review.
- Documentation-only commit
  `6c4a64218008fd697203d64aae6b9c4d2175d2bd` on
  `docs/build52-acceptance-record` was prepared before that blocker was found.
  This correction supersedes that false acceptance record; it must not be
  merged or cited as acceptance evidence.
- Build 48 is retained as the prior physically accepted rollback and comparison
  reference at exact protected `main` commit
  `fd2f39f079f3dca853f09e2d67caa8a5cd2eab5c`.
- PR [#82](https://github.com/Frankbell84/KeyHollow/pull/82) merged the exact
  reviewed stable playback-session repair head
  `fa9976e13ab15bac48edea37133a8ceed5d45f83` through protected `main` commit
  `837874744fcd31834fd9dba925212e4edf215b30`; both resolve to exact tree
  `6eaf8c95f8d65b0dd0975d8ded369b39f7656d59`.
- PR CI run
  [#35271954895](https://github.com/Frankbell84/KeyHollow/actions/runs/35271954895)
  passed the complete build-and-test lane and Swift CodeQL. Security-test
  artifact `10519203674` has SHA-256
  `722c543e6c86c57eb18c43c84e916361e4bc83cd1daae25300de5331fd98f0ce`;
  simulator artifact `10519588211` has SHA-256
  `253097fe5c684eef1ffa5f6eb5743fff42d5883f5141302ab1f4c1f3af7bdbea`.
- Exact merged-main CI run
  [#35274451814](https://github.com/Frankbell84/KeyHollow/actions/runs/35274451814)
  passed the complete build-and-test lane and Swift CodeQL. Security-test
  artifact `10520775506` has SHA-256
  `db96022b218ba6a6e74dd72f0eba1bcdb8d1fd878b19a8808400866c2dd5e0e4`;
  simulator artifact `10520540741` has SHA-256
  `1e3457f40908faa033f0b7a3a1461d421d42d400c1c5d25fd723fc72e0975731`.
- PR [#81](https://github.com/Frankbell84/KeyHollow/pull/81) merged the exact
  reviewed Build 51 packaging head
  `cb70f3c77d121b80b154faa24e58d38c3892d064` through protected `main` commit
  `9578136b74cbda7c5221c71cf7d357fa087b8a98`.
- Exact Build 51 merged-main CI run
  [#35244161231](https://github.com/Frankbell84/KeyHollow/actions/runs/35244161231)
  passed the complete build-and-test lane and Swift CodeQL. Security-test
  artifact `10507260985` has SHA-256
  `47e059b19ceb81dc52df29ca369540b231f50ba783faabcf2f254fac914c1899`;
  simulator artifact `10507550603` has SHA-256
  `52541bd7fccbad67246484867524cb788c58214573cb4bb835526cb3c479eab8`.
- Protected Build 51 signing-only preflight run
  [#35247024776](https://github.com/Frankbell84/KeyHollow/actions/runs/35247024776)
  passed for exact protected `main` commit
  `9578136b74cbda7c5221c71cf7d357fa087b8a98` without uploading or publishing.
  Separately authorized upload run
  [#35247583942](https://github.com/Frankbell84/KeyHollow/actions/runs/35247583942)
  then completed successfully. IPA artifact `10507434746` has SHA-256
  `47b424728ee819e7ea0168affc9e17ae9d001c5ec0e018499f9ccdfb0c5a5b88`;
  Apple delivery UUID is `08ef3a8e-5407-4328-b686-ed45b13c022d`.
  App Store Connect processed Build 51 and showed only `KeyHollow Internal`.
- Physical-device testing of the Internal Build 51 candidate reproduced the
  release blocker: a portrait video can still enter a blank AVKit surface with
  an inert Play control unless the user times actions around the transition.
  Build 51 is therefore failed and unaccepted; Build 48 was the accepted
  rollback and comparison baseline at that checkpoint and is retained as the
  prior reference.
- The repair is isolated to presentation ownership, not encryption or storage.
  It replaces the transient embedded-player lifecycle with one stable
  module-owned playback session, one viewer-root UIKit presentation anchor,
  direct modal full-screen AVKit presentation, explicit replay after Done, and
  ordered terminal release. Protected records, cryptography, archive formats,
  media payloads, hierarchy metadata, and ciphertext are unchanged.
- PR [#80](https://github.com/Frankbell84/KeyHollow/pull/80) merged the exact
  reviewed portrait-fullscreen correction head
  `00453af239719bd6b91006ab5ccbb34300edfdfd` through regular merge commit
  `99471fd64dd75fc13d0d14e9501f205a1aeba24f`; both trees are identical.
- Exact merged-main CI run
  [#35237468942](https://github.com/Frankbell84/KeyHollow/actions/runs/35237468942)
  passed the complete build-and-test lane and Swift CodeQL. Security-test
  artifact `10503947057` has SHA-256
  `816176222203a8ea9a2b2382b528d87f4b8a2617f95bdc74062c14d609bfa23c`;
  simulator artifact `10504571558` has SHA-256
  `9522fdb59ee15c9ddc4f9b03d295fffe1824dd5373df39dde538542fe076dd51`.
- PR [#79](https://github.com/Frankbell84/KeyHollow/pull/79) merged the exact
  reviewed Build 50 packaging head
  `45cb539c8193e6f172486a16758e76de5a0237b0` through regular merge commit
  `a0d10a6b0d2a4847f233286b4eed4836f54223fa`; both trees are identical.
- Exact Build 50 merged-main CI run
  [#35228643296](https://github.com/Frankbell84/KeyHollow/actions/runs/35228643296)
  passed the complete build-and-test lane and Swift CodeQL. Security-test
  artifact `10500103855` has SHA-256
  `5bd33079d4a58ca225f1a92934bb436eac4c4b1001ee90dfbccb4232ec19b1d9`;
  simulator artifact `10499779178` has SHA-256
  `3c33639c89738bf964a48c355fe707bd9f673ec2ec318a5c1f6de9e09b375c57`.
- Protected Build 50 signing-only preflight run
  [#35231273238](https://github.com/Frankbell84/KeyHollow/actions/runs/35231273238)
  passed for exact merged source without uploading or publishing. Separately
  authorized upload run
  [#35231747870](https://github.com/Frankbell84/KeyHollow/actions/runs/35231747870)
  then completed successfully. IPA artifact `10501691558` has SHA-256
  `1eceed16f385de2242080e569555adfa60574772c37db67efb338a4b5e86048c`.
  App Store Connect processed Build 50 and shows only `KeyHollow Internal`.
- Physical-device testing confirms the Files-style move picker and its nested
  navigation work. One release-blocking video defect remains: entering native
  fullscreen for a portrait video can leave AVKit's black player shell with an
  inert Play control. Build 50 therefore remains Internal-only and unaccepted.
- PR [#78](https://github.com/Frankbell84/KeyHollow/pull/78) merged the exact
  reviewed Build 50 refinement head
  `b84152cdd9d5888bfa39e82522e41e07f1b4f54c` through regular merge commit
  `1879ee1e8c517d320341a21c5e9b2c7bf92df4e5`.
- Exact merged-main CI run
  [#35222489038](https://github.com/Frankbell84/KeyHollow/actions/runs/35222489038)
  passed the complete build-and-test lane and Swift CodeQL. Security-test
  artifact `10498490395` has SHA-256
  `36855ae933c01d79824ce223362652233d0397852e007de19f30edad056f7e50`;
  simulator artifact `10498500477` has SHA-256
  `ba3f4e21e004da49cddc9d42a0aef3c7a591a68aa3a44b45ae2fab5d5f194e6a`.
- Protected signing-only preflight run
  [#35224624668](https://github.com/Frankbell84/KeyHollow/actions/runs/35224624668)
  verified that exact merged source, production signing material, the packaged
  privacy manifest, and both app signatures without uploading or publishing a
  build. Temporary signing material was removed by the workflow.
- PR [#77](https://github.com/Frankbell84/KeyHollow/pull/77) merged the exact
  reviewed Build 49 packaging head
  `77884e807178f59a7361e7625d99df58252909e9` through regular merge commit
  `df015ceab9d56ca1102b0e98d16aa1538b93f5b3`.
- Protected signing-only preflight run
  [#35205835726](https://github.com/Frankbell84/KeyHollow/actions/runs/35205835726)
  passed for exact Build 49 source without uploading or publishing. Separately
  authorized upload run
  [#35206603181](https://github.com/Frankbell84/KeyHollow/actions/runs/35206603181)
  then completed successfully, Apple processed Build 49, and App Store Connect
  shows only `KeyHollow Internal`.
- Physical-device testing confirmed that nested creation, navigation, and
  hierarchy persistence work, but found two release-blocking presentation
  defects: portrait videos can glitch during AVKit fullscreen transitions, and
  move destinations are flattened into a long-path menu that becomes ambiguous
  as soon as nested folders exist. Build 49 therefore was an unaccepted
  Internal test candidate at that checkpoint rather than the comparison
  baseline.
- Prior accepted source retained as a rollback/comparison reference: exact
  `main` commit
  `fd2f39f079f3dca853f09e2d67caa8a5cd2eab5c`.
- Build 48 completed exact-main CI in run
  [#35142349830](https://github.com/Frankbell84/KeyHollow/actions/runs/35142349830),
  protected signing-only preflight in run
  [#35145472764](https://github.com/Frankbell84/KeyHollow/actions/runs/35145472764),
  and the separately authorized Internal-only upload in run
  [#35146713445](https://github.com/Frankbell84/KeyHollow/actions/runs/35146713445).
  App Store Connect completed processing and shows only `KeyHollow Internal`.
  Frank physically tested Vault Catalog Sorting and confirmed that it works as
  intended. Build 48 was the accepted rollback and comparison baseline at that
  checkpoint and is retained as the prior reference.
- PR [#76](https://github.com/Frankbell84/KeyHollow/pull/76) merged the exact
  reviewed Nested Folder Hierarchy head
  `9bf85319f7cf3fe7c141908889723569db55eb54` through regular merge commit
  `32951baf7685672f05410641801a5c80980a74ac`.
- Exact merged-main CI run
  [#35160039341](https://github.com/Frankbell84/KeyHollow/actions/runs/35160039341)
  passed the complete build-and-test lane and Swift CodeQL. Security-test
  artifact `10473226011` has SHA-256
  `0547ecbcc4ffbfa245a7bdccfe1344eae74391f97e0e479d5ecdaadbef81d028`;
  simulator artifact `10472616756` has SHA-256
  `c3937c0afe5f2cb6d60f8951f61592ba5cdf4b77f9ca4799b2200211b4c84ead`.
- Protected signing-only preflight run
  [#35161736010](https://github.com/Frankbell84/KeyHollow/actions/runs/35161736010)
  verified that exact merged source, production signing material, the packaged
  privacy manifest, and both app signatures without uploading or publishing a
  build. Temporary signing material was removed by the workflow.
- Build 47 completed exact-main CI in run
  [#35124289873](https://github.com/Frankbell84/KeyHollow/actions/runs/35124289873),
  protected signing-only preflight in run
  [#35127204962](https://github.com/Frankbell84/KeyHollow/actions/runs/35127204962),
  and the separately authorized Internal-only upload in run
  [#35127821582](https://github.com/Frankbell84/KeyHollow/actions/runs/35127821582).
  App Store Connect completed processing and shows only `KeyHollow Internal`.
  Frank physically tested Vault Catalog Search and confirmed that it works.
- PR [#74](https://github.com/Frankbell84/KeyHollow/pull/74) merged the exact
  reviewed Vault Catalog Sorting head
  `a6f71053917b40f4f9b6bef236121d80c3670d98` through regular merge commit
  `aa950882db02bd40849df459acf3e2030b18ad6b`.
- Exact merged-main CI run
  [#35136592165](https://github.com/Frankbell84/KeyHollow/actions/runs/35136592165)
  passed the complete build-and-test lane and Swift CodeQL. Simulator artifact
  `10464031925` and security-test artifact `10463962186` were retained by the
  workflow.
- Build 46 completed protected signing and upload in workflow
  [#35101488529](https://github.com/Frankbell84/KeyHollow/actions/runs/35101488529),
  processed successfully in App Store Connect, and is assigned only to
  `KeyHollow Internal`.
- Frank physically tested Build 46 and confirmed Backup Verification, media
  swiping, and encrypted-video playback are all working correctly. Build 46 is
  the accepted baseline for subsequent add-ons.
- PR [#71](https://github.com/Frankbell84/KeyHollow/pull/71) merged the Build 46
  release candidate into `main`; merged-main CI run
  [#35097283447](https://github.com/Frankbell84/KeyHollow/actions/runs/35097283447)
  passed the full test suite and Swift CodeQL. Signing-only preflight run
  [#35099850522](https://github.com/Frankbell84/KeyHollow/actions/runs/35099850522)
  also passed before upload authorization.
- PR [#72](https://github.com/Frankbell84/KeyHollow/pull/72) merged the exact
  reviewed Vault Catalog Search head
  `0707c5a67e8d4383f544f8551ee2953f6d37447c` through regular merge commit
  `38fc86455832c298e6ea05d57e95b6ce23c48e56`.
- Exact merged-main CI run
  [#35112438984](https://github.com/Frankbell84/KeyHollow/actions/runs/35112438984)
  passed the complete build-and-test lane and Swift CodeQL with no annotations.
  Merged-main security-test artifact `10453536410` has SHA-256
  `54864a84f06c8fdcaf11af06c0d9042b6be284008fd6537989d8a2909ca1d740`;
  simulator artifact `10453616091` has SHA-256
  `62cfcac0365075a86cf447df0f660e92bd87ca12c273a1299f3228a718e41b9d`.
- Prior Build 40 accepted production source: exact `main` commit
  `54bd2d6887f3ca0e476339fce05e90dd59ba963f`.
- PR [#56](https://github.com/Frankbell84/KeyHollow/pull/56) merged the exact
  reviewed signing-verifier correction head
  `426768238433017ea11773220c3f61378d3f7cd3` through regular merge commit
  `54bd2d6887f3ca0e476339fce05e90dd59ba963f`.
- PR CI run
  [#34569439188](https://github.com/Frankbell84/KeyHollow/actions/runs/34569439188)
  and merged-main CI run
  [#34595760793](https://github.com/Frankbell84/KeyHollow/actions/runs/34595760793)
  passed all required checks.
- PR [#55](https://github.com/Frankbell84/KeyHollow/pull/55) merged the exact
  certificate-chain correction head
  `a8bb43aa44a434dc16f90b668e45eee548f187a9` through regular merge commit
  `015823d3ee69d8e52a668800ce9ee35d001221a8`.
- Exact merged-main CI run
  [#34564973012](https://github.com/Frankbell84/KeyHollow/actions/runs/34564973012)
  passed `build-and-test` and Swift CodeQL with zero annotations.
- PR [#53](https://github.com/Frankbell84/KeyHollow/pull/53) merged the exact
  approved Build 40 preparation head
  `ed7e2019f07caec7fac43489aed7184f8040303b` through regular merge commit
  `569a5ef343c8a368676b054ef48443823d10fdd5`.
- The merge tree `7782889f621f74be2b30a1eabf00a371ed4a6fe8` is
  byte-for-byte identical to the approved Build 40 preparation tree.
- Exact Build 40 merged-main CI run:
  [#34554039223](https://github.com/Frankbell84/KeyHollow/actions/runs/34554039223)
  passed `build-and-test` and Swift CodeQL with zero annotations.
- Published phase-entry checkpoint: `6abc6ed`.
- Published implementation checkpoint:
  `d6d87f39f0c5fee35f7cc05333955ef86046cb7e`.
- Published implementation-status head:
  `488efb5fb3387bc04916b9a7fd91d3196f4a4e90`.
- Fully green exact implementation-status-head CI run:
  [#34509180786](https://github.com/Frankbell84/KeyHollow/actions/runs/34509180786).
- PR [#52](https://github.com/Frankbell84/KeyHollow/pull/52) merged approved
  feature head `1978209680572cc807b21432b355730c5a487c27` through regular merge
  commit `de170c3e2f6a937362b39bc849302dd424476482`.
- The merge tree `79dfae6eafeb500700bfb807a69b2588201bafcf` is byte-for-byte
  identical to the approved feature tree.
- Exact Backup Verification merged-main CI run:
  [#34515909122](https://github.com/Frankbell84/KeyHollow/actions/runs/34515909122)
  passed build-and-test and Swift CodeQL with zero annotations in the KeyHollow
  workflow.
- Merged-main security-test artifact `10167947515`, SHA-256
  `0017fce1ad253b037463bdf9f775229242061fd8bff197d168c4756a754abf98`.
- Merged-main simulator artifact `10167944225`, SHA-256
  `405d532656e39f9665d0ba8d317ee68491129d6fc9a72b13165f9ee0fabc426f`.
- PR [#51](https://github.com/Frankbell84/KeyHollow/pull/51) merged the
  exact hardening head
  `b07842126ce4b7a2cf5c478a456fea2c49b38cc6` through a regular merge commit.
- The merge tree is byte-for-byte identical to the approved hardening tree.
- Exact merged-main CI run:
  [#34490248191](https://github.com/Frankbell84/KeyHollow/actions/runs/34490248191)
  passed build-and-test and Swift CodeQL with zero annotations and no new
  security alerts.
- Exact signed Build 39 source:
  `f654390ccf45bf7448952be787874a7c3e4f8206`
- Build 39 signed-upload workflow:
  [#34424283722](https://github.com/Frankbell84/KeyHollow/actions/runs/34424283722)
- Retained Build 39 IPA artifact: `10132108885`
- IPA SHA-256:
  `99a3ed152df2c5bb267e5950aab27db82e51e3d22e91981f1d3d15812ced72e1`
- The latest accepted Internal product is version 1.0, Build 53, built from
  exact signed binary source
  `1bf0907f4713b925a777240ecb5ece61b530d5bc`.
- Protected signed-upload workflow
  [#34602241254](https://github.com/Frankbell84/KeyHollow/actions/runs/34602241254)
  completed successfully. App Store Connect reports the binary as validated,
  and it is assigned only to `KeyHollow Internal`.
- Frank installed and exercised Build 40 on a physical iPhone and confirmed
  that the tested Backup Verification behavior works.
- Encrypted Video Support, post-Build-39 hardening, and Backup Verification
  Center are now in `main` through `de170c3`.
- Build 40 completed its protected release and credential cutover. Replacement-
  only post-cutover rehearsal
  [#34610956286](https://github.com/Frankbell84/KeyHollow/actions/runs/34610956286)
  passed authentication, archive, signing, exact-certificate/profile checks,
  and cleanup without uploading or retaining an artifact.

## Current task

Build 53 is the current accepted `KeyHollow Internal` baseline at exact signed
binary source `1bf0907f4713b925a777240ecb5ece61b530d5bc`. Its protected PR CI,
exact-main CI, no-upload signing preflight, signed upload, App Store Connect
processing, Internal-only assignment, and reported physical-iPhone regression
test all passed. The formerly failing video-playback, background, return, and
first correct-passcode unlock sequence now works.

Builds 49 through 52 remain historical Internal-only unaccepted candidates;
Build 52 remains rejected. The false documentation-only Build 52 acceptance
record at `6c4a64218008fd697203d64aae6b9c4d2175d2bd` remains superseded and must
not merge. Build 48 at
`fd2f39f079f3dca853f09e2d67caa8a5cd2eab5c` is retained as the prior accepted
rollback and comparison reference.

Protected records, cryptography, archive formats, media payloads, hierarchy
metadata, and ciphertext remain unchanged by the Build 53 repair. External
playback, Picture in Picture, system Now Playing publication, and paused-frame
visual analysis remain disabled. The next implementation change must be mapped
against this accepted modular baseline before work begins. Build 53 acceptance
does not authorize Family, external TestFlight, or App Store expansion.

Folder-aware portable backup v2 is now the active implementation task on
`feature/folder-aware-backup-v2`, based on accepted-main commit `a6ffe1b`. The
implementation preserves the shipped outer `.khvault` cryptographic framing
and adds authenticated inner catalog v4 folder metadata. It preserves nested
folder structure, memberships, timestamps, empty folders, and typed
photo/general-file references while intentionally excluding disposable
thumbnail caches. Legacy catalog v1-v3 archives remain root-level readable.
PR [#87](https://github.com/Frankbell84/KeyHollow/pull/87) merged the authorized
head `54cf209c9dc006c46c2f316571044b3275e80dd1` as protected-main commit
`58c42b7c552081c3f0c394ac0583e68d1a400d5e`. Their trees are identical.
The N150 handoff records the completed source audit with no actionable blockers.
Exact-head PR CI
[#393](https://github.com/Frankbell84/KeyHollow/actions/runs/35371461736)
and exact-main CI
[#394](https://github.com/Frankbell84/KeyHollow/actions/runs/35401354968)
passed build-and-test, XCTest, packaged-resource checks, artifact uploads, and
Swift CodeQL. The feature is not yet device-accepted or a TestFlight build.

The Ryzen checkpoint continuation independently verified the expected source,
clean checkout, branch/upstream, repository-local identity, and all four local
workflow-security, release-hygiene, architecture, and source-privacy checkers.
The approved shell path outside the restricted sandbox successfully pushed the
documentation checkpoint as the normal Windows user; restricted-sandbox
credential-store access remains unproven. The Ryzen cycle through exact-main
CI is complete. The original N150 task and checkout remain intact; task history
and host were not transferred.

## Build 54 candidate

Build 54 preparation is authorized on `codex/build54-internal-candidate`, based
on exact-main commit `58c42b7c552081c3f0c394ac0583e68d1a400d5e`. This candidate
changes only the app and thumbnail-extension build numbers from 53 to 54, the
matching reviewed project fingerprint in the workflow-security checker, and
this operational record; it introduces no further app implementation changes.
App Store Connect's iOS build and all-status upload lists were checked on
2026-09-18: Build 53 was latest and Build 54 was not listed. The protected
upload workflow must repeat its authenticated build-number check at upload time.

This candidate requires its own draft PR, complete exact-head CI and review,
explicit exact-head merge approval, exact-main CI, and no-upload signing
preflight. No Build 54 signing, upload, tester assignment, or device acceptance
is recorded here. Build 53 remains the accepted Internal rollback. Evidence
for this candidate's resulting SHA belongs in its PR to avoid creating another
source revision solely to record CI results.

## Unified Media Navigation candidate

- Preserve Photos-origin and general-file identity as separate typed namespaces
  even when UUID values collide.
- Build each navigation queue only from compatible images and videos in the
  already ordered current-root or current-folder gallery snapshot.
- Keep PDFs and other non-media files on the established file-management route.
- Construct only the active full-resolution page. Adjacent navigation entries
  remain immutable metadata and may reuse existing bounded thumbnails only.
- Keep authentication, decryption, sensitive-task generation checks, image and
  player cleanup, protected temporary exports, save/delete behavior, and
  lock/background/session-replacement handling in the application composition
  layer.
- Require automated pure-state, architecture, lifecycle, and integration tests
  plus the complete device checks in `docs/DEVICE_TEST_PLAN.md` before this
  candidate can become accepted behavior.

## Completed work

The following completion record applies to Backup Verification Center and its
inherited hardening, not the in-progress Unified Media Navigation candidate.
Implementation, local hardening, and exact-source CI are complete:

- Added a TransferCore verify-and-discard facade over the existing authenticated
  restore validator. It returns only primitive counts, source creation time,
  payload-catalog version, and explicit legacy limitations after checked
  extraction cleanup succeeds.
- Closed every post-extraction exit: export failure, export success,
  verification cancellation, validation failure, and partial extraction now
  cross checked cleanup, and a cleanup failure takes precedence over publishing
  success or a less actionable cancellation result.
- Added the independently compiled `KeyHollowBackupVerificationAddOn`, with no
  dependency on core, session, storage, transfer, or application targets.
- Added one application-owned verification flow reachable from both the locked
  home screen and the unlocked vault menu. It uses protected `.khvault` ingress,
  clears the recovery credential, reports progress, cancels on lifecycle
  transitions, and cannot install or unlock a vault.
- Hardened File Recognition staging with checked idempotent cleanup, shared
  reference ownership, active-operation preservation, and canonical-only stale
  ingress recovery after interruption or restart-and-retry.
- Restricted both transfer-working and file-ingress stale recovery to inactive,
  canonical, real directories; canonical-named regular files and symbolic links
  are preserved and covered by regression tests.
- Hardened manual and forced dismissal so protected work is canceled before
  ownership is released, while user-driven dismissal awaits terminal cleanup.
- Reused the same verification facade for the existing import preview so there
  is still one authenticated archive-validation path.
- Added current photo-only, file-only, mixed, and video-as-file coverage; legacy
  v1 photo and v2 general-file compatibility fixtures; wrong-credential,
  corrupted, truncated, cancellation, cleanup-failure, repeat/immutability,
  live-lease, and abandoned-ingress recovery tests.
- Added source-enforced gates for exact target ownership, allowed imports,
  sanitized report fields, verify-before-publish ordering, checked cleanup,
  lifecycle generation guards, background staging, and denial of install,
  unlock, export, credential-store, or direct-filesystem capabilities.

Phase entry was completed first:

- Re-fetched `origin/main`, verified the exact post-merge commit and tree, and
  created this single-purpose feature branch directly from that baseline.
- Reconciled the historical roadmap, later decisions, and architecture
  addendum. Frank's confirmed next feature is Backup Verification Center; the
  addendum's broader Backup & Sync Center remains later work.
- Mapped the safe reuse seam to
  `EncryptedVaultTransferCoordinator.stageAndValidateRestore`. The existing
  import screen already proves verify-then-discard behavior, but its
  `ValidatedPortableVaultRestore` contains recovered vault material and must
  never cross into the add-on or SwiftUI state.
- Selected an additive design: a TransferCore-owned verify-and-discard facade,
  a dependency-light compiled report/presentation add-on, and app-owned file
  ingress plus lifecycle coordination.
- Confirmed the report must disclose that current archives preserve photos and
  general files but not folder names or membership.
- The merged baseline remains modular and all local architecture, release,
  workflow-security, privacy, and release-verifier preflight checks pass.

The inherited published hardening implementation includes:

- Bounded archive catalogs, entries, frames, payloads, manifests, batches,
  filenames, content-type identifiers, and temporary working areas.
- Canonical path, regular-file, no-symlink, size, and authenticated-record
  validation across credential, photo, general-file, folder, and transfer
  storage.
- Authenticated, fail-closed transaction recovery for portable restore,
  passcode rotation, and vault deletion.
- Short-lived, one-use vault-deletion authorization tied to the authenticated
  vault, credential-mutation gate, live-session retirement, capability
  revocation, and sensitive-task cleanup barrier.
- Cancellation-safe vault creation, restore, unlock, reauthentication,
  passcode rotation, deletion, export, thumbnails, playback, and lifecycle
  transitions.
- Correct authentication-attempt accounting so cancellation and internal
  failures do not consume extra wrong-passcode strikes.
- Protected temporary plaintext lifetimes for file export, secure image open,
  thumbnails, and video playback, including lock/background cleanup.
- Commit-state recovery for encrypted manifests and coordinated mutation
  boundaries for multiple store instances.
- Module-internal construction of staged vault-file cleanup capabilities, with
  deletion confined to the ingress-owned temporary root.
- Fully isolated lifecycle-test roots for portable restore journals, restore
  staging, photo data, and general-file data.
- Apple privacy-manifest declarations and exact XcodeGen resource wiring for
  the required system APIs used by KeyHollow.
- Separately compiled add-on boundaries, strict concurrency,
  warnings-as-errors, source-tree allowlists, and expanded architecture gates.
- SHA-pinned GitHub Actions, read-only default permissions, exact source/build
  binding, protected-environment validation, and a fail-closed retired beta
  workflow.
- `CODEOWNERS` coverage for release, security, storage, transfer, privacy,
  project, add-on, and test boundaries.
- Replacement of the deprecated Node 20 artifact-uploader path with the pinned
  current artifact action.
- Expanded hostile-input, interruption, replay, expiry, rollback, recovery,
  compatibility, cancellation, cleanup, and lifecycle tests.
- The exact-head CI diagnosis identified no app-runtime or cryptographic
  defect. Commit `a4906c880bba3e9dc9cf3d2af607f3733b267801`
  makes two concurrent lifecycle-test tasks explicitly return their intended
  result and makes two test-only encryption helpers explicitly return their
  ciphertext, without changing production behavior, ordering, or encryption.
- The next exact-head run confirmed those files compile and link. It then
  exposed a test-oracle defect: after proving `lockAndWait()` revoked the
  session, the test tried to decrypt the presentation manifest through the
  deliberately revoked capability. The published correction preserves strict
  production revocation and instead verifies directly that cancelled work
  persisted no encrypted thumbnail blob.
- The same published correction removes a Swift 6 test warning by ensuring
  isolated `UserDefaults` cleanup obtains a fresh handle after the original is
  transferred to the unlock-limiter actor.
- Exact-head CI confirmed both of those corrections. Its next failure was an
  archive-test contradiction, not a production filesystem defect: the test
  treated an entry one byte above today's role limit as invalid even though the
  documented compatibility contract deliberately re-exports authenticated
  legacy local data within the shipped 1-TiB-per-entry envelope as catalog v2.
  Commit `437f4f2b0210daa98faadc439fbbc1c3770ba7f7` tests rejection
  at the true legacy envelope and adds source-level proof that a modest
  legacy-sized entry selects catalog v2. Production archive behavior was not
  weakened or changed.
- Exact-head run
  [#34469885087](https://github.com/Frankbell84/KeyHollow/actions/runs/34469885087)
  passed every preflight gate, simulator build, packaged-resource check, the
  complete security/lifecycle XCTest job, both artifact uploads, and Swift
  CodeQL. The pull-request security scan reported no new alerts and zero check
  annotations.
- Status-only checkpoint `f00687d7896be8f65b7dbdd29ab7bc9087b9d358`
  also completed the full exact-head workflow in
  [#34472545516](https://github.com/Frankbell84/KeyHollow/actions/runs/34472545516):
  build-and-test and Swift CodeQL passed with zero annotations, the separate
  pull-request security result reported no new alerts, and both required
  artifacts uploaded successfully.
- The Codex managed runtime was repaired reversibly after the repository CI
  became stable. The prior runtime and incomplete installer remain in dated
  quarantine, a fresh coherent runtime hydrated, and two clean application
  launches plus local, read-only remote, credential-manager, and authenticated
  no-change Git checks all passed.

No broad rewrite was required. The protected modular architecture continues to
hold, and independent compile/API and adversarial-security reviews found no
remaining P1/P2 blocker in the local revision.

## Archive compatibility

- The public `.khvault` header, outer container, payload prefix, streaming
  framing, key derivation, and encryption remain version one.
- Current readers accept the shipped photo-only catalog v1 and mixed-content
  catalog v2 limits so authenticated Build 39 archives remain recoverable.
- New bounded exports use authenticated catalog v3. It keeps the v2 layout but
  applies current item, role-size, catalog-size, and aggregate-size limits.
- Authenticated legacy local data that exceeds only the new limits can fall
  back to catalog v2 within the shipped compatibility envelope.
- Catalog-v3 exports are not readable by older builds that understand only v1
  and v2. This forward-compatibility boundary is explicit in
  `docs/GENERAL_FILE_SUPPORT.md` and
  `docs/ENCRYPTED_VAULT_ARCHIVE_SPEC.md`.
- Folder names and membership are still not included in the current archive;
  restored content lands at the new vault's top level, as disclosed in both
  transfer screens and documentation.

## Test and build status

Passed on the published Windows worktree:

- Architecture-boundary checker
- Release-hygiene checker and self-test
- Workflow-security checker and self-test
- Privacy-manifest checker
- Exact-release-source verifier self-test
- Production-environment verifier self-test
- TestFlight build-number verifier self-test
- Python syntax compilation for every release/security script
- Git whitespace and patch-integrity check
- Conflict-marker and tracked credential/private-key scans

The current Backup Verification Center implementation also passes every local
gate above, including the expanded architecture rules and Git patch-integrity
check. The new Swift test matrix is present but cannot execute on Windows.

Repository checks found no reachable Git corruption. `git fsck` reported only
ordinary unreachable objects and a zero-byte empty worktree `refs` directory
warning; neither affects reachable source history. The temporary
`.helper-test` directory was verified empty and removed non-recursively.

Windows still cannot reproduce the macOS/iOS toolchain locally. The exact PR
and merged-main evidence below prove the Backup Verification implementation.
Any Build 40 release-preparation head and its eventual merge commit must each
retain the same complete macOS workflow.

Draft PR #51 was opened from exact reviewed head
`42086651719f92e4001c26ef1e7b1e3c590bc0d6`. Its initial run
[#34464405249](https://github.com/Frankbell84/KeyHollow/actions/runs/34464405249)
was superseded and automatically cancelled when the required status checkpoint
advanced the PR head to `d48d27a87808caea8a014c8e851b5770a59d174a`.

The authoritative exact-checkpoint-head run
[#34464715632](https://github.com/Frankbell84/KeyHollow/actions/runs/34464715632)
passed preflight architecture, release-hygiene, workflow-security, privacy,
project generation, simulator build, and packaged-resource verification. Its
`build-and-test` job then failed while compiling test code because two
multi-statement `Task` closures did not explicitly return their result. The
same log reported one test-helper unused-result warning. Both sites and the
single analogous helper are corrected in the current working phase. No green
result is claimed until every required job completes on the final PR head.

The first replacement run
[#34466500108](https://github.com/Frankbell84/KeyHollow/actions/runs/34466500108)
on exact commit `a4906c880bba3e9dc9cf3d2af607f3733b267801`
passed all preflight gates, project generation, simulator compilation,
packaged-resource verification, and compiled and linked the complete test
bundle. It then ran 287 tests and failed when
`testLockAndWaitObservesRegisteredThumbnailCleanup` attempted post-lock access
through an intentionally revoked capability. The log also reported one Swift
6 test-only `UserDefaults` send-after-use warning. Both issues are corrected in
the current working phase. The failure does not justify weakening production
revocation, and no such production change was made.

The next replacement run
[#34468073067](https://github.com/Frankbell84/KeyHollow/actions/runs/34468073067)
on exact commit `239bd1da7a90327727882ddb669e44b9bcf370f9`
confirmed that the lifecycle test now passes and the Swift 6 `UserDefaults`
warning is gone. The complete suite reached 287 tests with one assertion
failure and no unexpected test crash: a sparse source only one byte above the
current photo limit was expected to fail before hashing, even though that size
is intentionally accepted for authenticated legacy-v2 re-export. Two
independent reviews confirmed Foundation reported the logical sparse-file size
correctly and that changing production to the current role limit would violate
the documented Build 39 compatibility contract. The test is therefore moved
to one byte above the 1-TiB legacy envelope, and a readable 4-MiB source-path
case now proves the intended v2 fallback without excessive CI work.

The authoritative correction-head run
[#34469885087](https://github.com/Frankbell84/KeyHollow/actions/runs/34469885087)
on exact commit `437f4f2b0210daa98faadc439fbbc1c3770ba7f7`
completed successfully. `build-and-test` passed all architecture, release,
workflow-security, privacy, build-number, source-evidence, environment,
simulator-build, packaged-resource, XCTest, and artifact-upload steps with zero
annotations. Swift CodeQL also passed; its separate security result reported
no new alerts in code changed by PR #51. Retained run artifacts are:

- `KeyHollow-Security-Tests` artifact `10149203692`, SHA-256
  `f403710fcd8a948987469843db456125704be84d9a01e858def0f9e5c95d0ea6`.
- `KeyHollow-Simulator` artifact `10149201668`, SHA-256
  `6d6e617edd61584bdadb8085c9120faf95a17b29be8c89b4b0a777b1a6fa57fc`.

The final status-only head
`f00687d7896be8f65b7dbdd29ab7bc9087b9d358` then completed
[#34472545516](https://github.com/Frankbell84/KeyHollow/actions/runs/34472545516)
successfully. Its build-and-test job, Swift CodeQL job, pull-request security
result, and both artifact uploads passed with zero annotations and no new
alerts.

The authoritative Backup Verification Center run
[#34509180786](https://github.com/Frankbell84/KeyHollow/actions/runs/34509180786)
on exact commit `488efb5fb3387bc04916b9a7fd91d3196f4a4e90` completed
successfully for PR #52 before merge. `build-and-test` passed every preflight gate,
project generation, simulator build, packaged-resource verification, the
complete security/lifecycle XCTest suite, and both artifact uploads. Swift
CodeQL passed; the separate pull-request security result reported no new alerts
in code changed by PR #52. All three check runs completed with zero annotations.
Retained run artifacts are:

- `KeyHollow-Security-Tests` artifact `10165399849`, SHA-256
  `d807f1abef8f8881b1679374cb07f756111e12f1f48a4e4e5503ea76d07379e7`.
- `KeyHollow-Simulator` artifact `10165393728`, SHA-256
  `64910e65840ca0af9a08ba043eccfe3b33c53cec96b079d1de98e07ab64ef4a1`.

PR #52 then merged through `de170c3e2f6a937362b39bc849302dd424476482`.
Exact main-push run
[#34515909122](https://github.com/Frankbell84/KeyHollow/actions/runs/34515909122)
passed `build-and-test` and Swift CodeQL. Both KeyHollow jobs completed with
zero annotations, and the retained artifacts and digests are recorded in
Provenance above.

The separate GitHub-managed dynamic Pages run
[#34515907787](https://github.com/Frankbell84/KeyHollow/actions/runs/34515907787)
also succeeded. Its one advisory says GitHub is forcing its managed
`actions/upload-artifact@v4` step from deprecated Node 20 to Node 24. That step
is not declared by a checked-in KeyHollow or iOS release workflow and does not
block Build 40; any Pages migration remains separate infrastructure work.

## Git helper status

The Codex managed-runtime/Git-helper repair is complete and durable across two
clean application launches.

- The previous complete runtime and incomplete installer were reversibly
  renamed to `codex-primary-runtime.quarantine-20260910` and
  `codex-runtime-install-3VSjvK.quarantine-20260910`; the stale installer's
  original name is absent.
- Codex hydrated fresh managed bundle `26.909.12148`. Its bundled Git is
  `2.53.0.windows.3`, and every required Git DLL is present in the canonical
  runtime location.
- No cross-version `GIT_EXEC_PATH` override or user-PATH mutation remains.
- Bundled Git local status passed, and bounded HTTPS `ls-remote` checks passed
  on both clean launches.
- Bundled Git Credential Manager `2.7.3` passed both direct and Git-dispatched
  version checks outside the restricted diagnostic sandbox.
- The final authenticated integration check used bundled Git to perform
  `push --dry-run` against the assigned remote branch. It exited zero with
  `Everything up-to-date`; the operation could not alter the remote.
- The two `0xe0434352` dialogs Frank dismissed were delayed results from two
  earlier direct GCM probes inside the restricted sandbox, where child-process
  creation was denied. They were not second-launch failures. No Git, HTTPS
  helper, or credential-manager process remained afterward, and no dialog
  recurred during the outside-sandbox authenticated test.
- The quarantine directories are intentionally retained as a recovery path.
  They must not be deleted without a separate explicit decision.

This was an environment-tooling failure, not repository or KeyHollow source
corruption, and it is no longer an active blocker.

## Release state

There is no open P1/P2 review finding, known production-code defect, active
Git-helper blocker, failed required repository check, or pending Build 40
release action.

On 2026-09-11, Build 40 completed the protected Internal-only release and
physical-device acceptance path. The replacement App Store Connect API key
`W3UF745JN4` and Apple Distribution certificate `4RU4X6GAGU` are the sole
active production credentials. Legacy key `JD6P6X8C9A` and legacy certificate
`2P45VCTJVL` were revoked only after Build 40 processed, installed, launched,
and passed device testing.

The replacement Apple Distribution certificate, exportable P12, and exact app
and thumbnail-extension App Store profiles have been generated, validated
locally, and installed in the protected environment. All nine expected
environment-secret names are present: the environment-only guard plus all eight
production credentials. The reviewed release source pins certificate SHA-1
`7E2342E196D2A56E95A05BCBDD473FE3799B7EDD`, app-profile UUID
`b9a24dc9-04a3-40e1-b0e3-fe7538e6e341`, and thumbnail-profile UUID
`c9564b6f-22cd-490b-9f59-f91e98a4a065`; these are public binding identifiers,
not secrets.

The first protected no-upload run
[#34556497300](https://github.com/Frankbell84/KeyHollow/actions/runs/34556497300)
proved the exact-main, CI, environment, hygiene, architecture, verifier, privacy,
identity, project-generation, and App Store Connect authentication gates. It
then stopped before signing-material installation, export, IPA validation, or
upload because GitHub's `macos-26-arm64` image `20260907.0351.1` did not contain
the iOS 26.0 runtime required by pinned Xcode 26.0.1. No binary was signed or
published. The isolated correction moves only the two privileged workflows to
the same `macos-15-arm64` image family already proven by exact-main CI and adds
fail-closed architecture, Xcode-build, SDK, and runtime checks before external
authentication. This failed rehearsal signed and published nothing; the runner
correction was later proven by the successful protected rehearsals listed
below.

PR #54 merged that runner correction as exact `main` commit
`95cd9f9deb2f99fe5f5962cc5ac96c2a47d12f33`; its complete main-push CI run
[#34560364159](https://github.com/Frankbell84/KeyHollow/actions/runs/34560364159)
passed both required jobs with zero annotations. The next protected no-upload
run
[#34561820231](https://github.com/Frankbell84/KeyHollow/actions/runs/34561820231)
then authenticated and completed the unsigned archive, but stopped safely while
installing signing material. The P12 imported successfully and contained one
signing leaf plus its normal certificate chain; the workflow incorrectly
required the isolated keychain to contain only one certificate total and saw
three. It produced no signed IPA and performed no upload. PR #55 merged the
isolated non-CA leaf correction as exact `main` commit
`015823d3ee69d8e52a668800ce9ee35d001221a8`; complete main-push CI run
[#34564973012](https://github.com/Frankbell84/KeyHollow/actions/runs/34564973012)
passed both required jobs with zero annotations.

Protected no-upload run
[#34566854574](https://github.com/Frankbell84/KeyHollow/actions/runs/34566854574)
then passed every source, CI, environment, hygiene, architecture, privacy,
identity, toolchain, App Store authentication, unsigned-archive, signing-
material, profile, signed-export, and code-signature gate. It failed safely in
the final post-export leaf-certificate extraction because the optional
`codesign --extract-certificates` prefix was separated by a space instead of
bound with `=`. Both products passed code-signature structural and designated-
requirement validation, but the final byte-for-byte proof that each used the
approved leaf did not complete. Cleanup passed, the workflow had no upload
capability, and nothing was uploaded or retained. PR
[#56](https://github.com/Frankbell84/KeyHollow/pull/56) merged the isolated
extraction correction. Protected no-upload run
[#34598236304](https://github.com/Frankbell84/KeyHollow/actions/runs/34598236304)
then passed end to end. After all eight repository-scoped production-secret
copies were removed, run
[#34600941660](https://github.com/Frankbell84/KeyHollow/actions/runs/34600941660)
proved environment-only operation. After legacy credential revocation, run
[#34610956286](https://github.com/Frankbell84/KeyHollow/actions/runs/34610956286)
proved the replacement credentials again. All three rehearsals had no upload or
publication capability and retained no artifact.

## Required external GitHub controls

Before the next production TestFlight upload, the following status applies:

1. **Complete:** environment named exactly `production-testflight`.
2. **Complete:** custom deployment policy allowing only the exact `main`
   branch.
3. **Complete:** a nonempty environment-only `PRODUCTION_RELEASE_GUARD`
   secret.
4. **Complete:** all eight production credentials and the environment-only
   guard are present in `production-testflight`. GitHub exposes names and update
   times, not stored values; the protected preflight must still prove the four
   signing values end to end.
5. **Complete:** protected `main` requiring pull requests, an up-to-date branch, conversation
   resolution, and the exact `build-and-test`, `CodeQL (Swift)`, and GitHub
   Advanced Security `CodeQL` checks, with administrator bypass, force pushes,
   and branch deletion disabled. While Frank is the sole reviewer, approvals,
   code-owner review, stale-approval dismissal, and latest-push approval remain
   off so GitHub cannot create a self-review deadlock.
6. **Contained:** the production workflow on `main` has retired the historical
   beta uploader with an unconditional false job. The historical remote
   `delivery/v2-beta` branch must not be pushed; removal remains a separately
   authorized cleanup action.
7. **Complete:** all eight repository-scoped production-credential copies were
   removed after the first successful rehearsal. Protected run
   [#34600941660](https://github.com/Frankbell84/KeyHollow/actions/runs/34600941660)
   then proved the protected environment is the only production credential
   source.
8. **Complete:** a required environment reviewer so the release pauses before secrets are
   exposed. While Frank is the sole operator, Frank remains the reviewer and
   self-review prevention stays off; when an independent reviewer is available,
   require that reviewer and enable self-review prevention.

GitHub does not reveal stored secret values. If the original repository-scoped
values were not retained outside GitHub, recreate or rotate the relevant Apple
credentials and provisioning material rather than weakening the environment-
only boundary.

## Next action

1. Preserve exact Build 53 signed binary source
   `1bf0907f4713b925a777240ecb5ece61b530d5bc` as the current accepted Internal
   baseline. Preserve exact Build 52 source
   `0dfc5a1faa5fd0664ead1df1d7ed5b5a43f1498e` only as failed-candidate evidence,
   and retain exact Build 48 source
   `fd2f39f079f3dca853f09e2d67caa8a5cd2eab5c` as the prior rollback/comparison
   reference.
2. Publish the Build 54 packaging candidate through a draft PR and require
   complete macOS build-and-test and Swift CodeQL for its exact head.
3. Review that exact diff and CI evidence, then obtain explicit authorization
   before marking the candidate ready or merging. Require build-and-test and
   Swift CodeQL again on the exact protected-main merge SHA.
4. Run the no-upload signing preflight on that exact main SHA, then obtain
   separate exact-SHA, Build 54, and Internal tester-group approval before
   upload. Recheck build-number availability in the protected upload workflow.
   Folder-aware backup v2 still requires the physical-device acceptance matrix
   in `docs/DEVICE_TEST_PLAN.md`; Build 53 remains the accepted rollback until
   acceptance. Keep the N150 intact unless separately authorized otherwise.
5. Do not expand the accepted build to Family, external TestFlight, or App Store
   review without a separate explicit decision and the corresponding release
   gates.

## Frank's decisions required

Frank's action-time decision is required for:

- Publishing or merging any revision that would supersede the accepted Build 53
  source baseline.
- Creating or changing GitHub environments, branch protection, reviewers, or
  secrets.
- Retiring or deleting historical remote release branches or secrets.
- Deleting the dated managed-runtime quarantine directories after the desired
  retention period.
- Authorizing a signed TestFlight upload by full commit SHA, unused build
  number, and tester group.
- Expanding a build from Internal to Family or external testers.
- Changing App Store review or production-release state.
- Final export-compliance classification. The existing
  `ITSAppUsesNonExemptEncryption = false` declaration must be confirmed against
  the final implementation and applicable requirements; source automation
  cannot make that legal determination.
- Publishing final privacy/support URLs, App Store metadata, screenshots, age
  rating, and privacy-questionnaire answers.
