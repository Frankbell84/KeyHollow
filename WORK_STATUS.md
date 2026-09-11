# KeyHollow Work Status

Updated: 2026-09-10

This is the authoritative operational resume point. Historical Build 38
evidence remains in `docs/PROJECT_CHECKPOINT.md`.

## Provenance

- Current local release-runner correction branch:
  `hardening/build40-runner-platform`, rooted exactly from `origin/main` at
  `569a5ef343c8a368676b054ef48443823d10fdd5`.
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
- The latest accepted product remains version 1.0, Build 39.
- Frank verified Build 39 in App Store Connect and assigned it only to
  `KeyHollow Internal`.
- Encrypted Video Support, post-Build-39 hardening, and Backup Verification
  Center are now in `main` through `de170c3`.
- This isolated source candidate sets both product targets to Build 40. Build 40
  was checked live in App Store Connect on 2026-09-10: Build 39 was the newest
  upload and no Build 40 record existed. Build 40 has not been signed, uploaded,
  processed, accepted, assigned to testers, or submitted for review. The
  release workflow must repeat its API-backed build-number check immediately
  before any upload.

## Current task

Correct the privileged release runner from exact merged Build 40 `main` without
changing application behavior, archive format, signing identities, or upload
logic. Keep the correction limited to both protected release workflows, their
fail-closed verifier, and current operational documentation. Then repeat the
protected no-upload signing rehearsal before any credential deletion or upload.

## Completed work

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

## Blockers

There is no open P1/P2 review finding, known production-code defect, active
Git-helper blocker, or failed required repository check on the merged Backup
Verification Center implementation.

Release remains blocked at the no-upload signing rehearsal, but the major
external control gap has been closed.
On 2026-09-10, `main` protection and the `production-testflight` environment
were configured and verified live. The environment is exact-`main` only, has a
required reviewer with administrator bypass disabled, and contains the random
`PRODUCTION_RELEASE_GUARD`, a fresh CI-only `KEYCHAIN_PASSWORD`, and the three
App Store Connect API secrets. Replacement API key `W3UF745JN4` authenticated
successfully through both a direct read-only request and the repository's
Build-40/latest-39 lookup. Prior key `JD6P6X8C9A` remains active as a rollback
credential until the complete cutover is proven.

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
authentication. Build 40 remains only a candidate even though App Store Connect
showed the number unused on 2026-09-10. Physical-device Backup Verification
testing remains mandatory after any separately approved Internal upload.

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
three. It produced no signed IPA and performed no upload. The isolated local
correction extracts exactly one non-CA leaf, still requires exactly one valid
code-signing identity matching the pinned fingerprint, and leaves every profile,
export, post-export, and cleanup gate intact. It requires its own protected PR,
PR CI, merged-main CI, and fresh no-upload rehearsal.

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
7. **Deferred intentionally:** removal of repository-scoped production
   credentials only after every environment copy passes the first protected
   no-upload preflight. The same preflight must pass again after removal.
8. **Complete:** a required environment reviewer so the release pauses before secrets are
   exposed. While Frank is the sole operator, Frank remains the reviewer and
   self-review prevention stays off; when an independent reviewer is available,
   require that reviewer and enable self-review prevention.

GitHub does not reveal stored secret values. If the original repository-scoped
values were not retained outside GitHub, recreate or rotate the relevant Apple
credentials and provisioning material rather than weakening the environment-
only boundary.

## Next action

1. Review and publish the isolated certificate-chain verifier correction through
   a normal pull request; require complete PR CI, merge only the approved exact
   head, and require complete main-push CI. No application-runtime source may
   change.
2. Run `Verify KeyHollow Release Signing` on the corrected exact merged-main
   commit. It must authenticate to App Store Connect, create the unsigned
   archive, install and validate the replacement signing material, export and
   inspect the signed IPA, and finish without an upload or publication action.
3. **Complete for candidate preparation:** App Store Connect showed Build 39 as
   the newest upload and no Build 40 record on 2026-09-10. The release workflow
   must repeat this check immediately before upload.
4. Only after that first preflight passes, remove the eight repository-scoped
   production-credential copies and rerun the same preflight. The second run
   must prove the protected environment is the only credential source.
5. Only if Build 40 is unused, obtain explicit
   authorization naming the full merged-main SHA, Build 40, and
   `KeyHollow Internal` only.
6. Verify the signed workflow, retained IPA digest, App Store Connect processing,
   and Internal-only assignment; then execute the Backup Verification section of
   `docs/DEVICE_TEST_PLAN.md` on a physical iPhone.
7. Retain the prior Apple Distribution certificate until the replacement has
   produced a processed Build 40 that installs and launches successfully. Keep
   API key `JD6P6X8C9A` available through the entire rollback window and revoke
   it only as the final credential-cutover action.
8. Do not expand to Family or external testers without a separate decision after
   the Internal checks pass.

## Frank's decisions required

Frank's action-time decision is required for:

- Publishing and merging the exact Build 40 release-preparation revision after
  all gates pass.
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
