# KeyHollow Work Status

Updated: 2026-09-10

This is the authoritative operational resume point. Historical Build 38
evidence remains in `docs/PROJECT_CHECKPOINT.md`.

## Provenance

- Current branch: `feature/backup-verification-center`
- Published phase-entry checkpoint: `6abc6ed`.
- Exact protected-main baseline:
  `0cdf04acce06fd402780eb2857e977a6872fe572`
- Baseline tree:
  `8da1ef0a7d7264ecc1e78382ff8e59ac8b75e2ee`
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
- Product version remains 1.0, Build 39.
- Frank verified Build 39 in App Store Connect and assigned it only to
  `KeyHollow Internal`.
- Encrypted Video Support and the post-Build-39 hardening revision are now in
  `main` through `0cdf04a`.
- No binary has been signed, uploaded, assigned to testers, or submitted from
  this new feature branch.

## Current task

Implement roadmap add-on #2, Backup Verification Center, as a read-only local
`.khvault` authenticity and recoverability check. Reuse TransferCore's existing
authenticated archive validator, immediately discard its protected staging,
and expose only a sanitized immutable report to the independently compiled
add-on and its UI. Do not install a vault, create a second transfer path, treat
the recovery code as a local LowKey, add cloud/sync/account behavior, change the
archive format, or alter release state.

## Completed work

Implementation and local hardening are complete pending exact-source CI:

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

These Windows checks cannot compile Swift or run iOS tests. Exact-source
macOS/Xcode 26.0.1 compilation, strict-concurrency diagnostics, the complete
XCTest/security/lifecycle suite, packaged-resource verification, Darwin
filesystem behavior, and Swift CodeQL remain mandatory. Build 39's green
evidence proves the released base, not this new hardening diff.

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

There is no known engineering or Git-helper blocker to beginning the isolated
feature. Windows cannot compile Swift or run the iOS suite, so exact-source
macOS/Xcode CI remains mandatory after implementation. Physical-device testing
remains mandatory before any later TestFlight acceptance or wider rollout.

## Required external GitHub controls

Before the next production TestFlight upload, Frank must verify or configure:

1. Environment named exactly `production-testflight`.
2. Custom deployment policy allowing only the exact `main` branch.
3. A nonempty environment-only `PRODUCTION_RELEASE_GUARD` secret.
4. These eight production secrets in that environment:
   - `APP_STORE_CONNECT_API_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_BASE64`
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `BUILD_CERTIFICATE_BASE64`
   - `BUILD_PROVISION_PROFILE_BASE64`
   - `KEYCHAIN_PASSWORD`
   - `P12_PASSWORD`
   - `THUMBNAIL_PROVISION_PROFILE_BASE64`
5. Protected `main` requiring pull requests, complete CI and CodeQL,
   stale-review dismissal, conversation resolution, and code-owner review,
   with force pushes and branch deletion disabled.
6. Neutralization or removal of the historical remote `delivery/v2-beta`
   uploader before that branch is touched again.
7. Removal of repository-scoped production credentials only after environment
   copies and the release guard are entered and validated.
8. A trusted environment reviewer only if a real second reviewer is available;
   do not prevent self-review without one.

## Next action

1. Commit and publish the exact implementation checkpoint on the isolated
   feature branch.
2. Open a draft review and run exact-head macOS/Xcode compilation, the complete
   XCTest/security/lifecycle suite, packaged-resource verification, and Swift
   CodeQL.
3. Correct only evidence-backed branch issues, then publish an exact green-head
   status checkpoint for review.
4. Stop before merge, signing, upload, tester assignment, or release action.

## Frank's decisions required

Frank confirmed Backup Verification Center follows Encrypted Video Support and
approved beginning this next step. That approval covers isolated design,
implementation, tests, a draft review, and CI; it does not authorize merge,
signed upload, tester assignment, or App Store action.

Frank's action-time decision is required for:

- Approving and merging the exact Backup Verification Center revision into
  `main` after all gates pass.
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
