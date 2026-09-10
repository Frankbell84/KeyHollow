# KeyHollow Work Status

Updated: 2026-09-10

This is the authoritative operational resume point. Historical Build 38
evidence remains in `docs/PROJECT_CHECKPOINT.md`.

## Provenance

- Current branch: `hardening/post-build39-baseline`
- Hardening start commit:
  `73471b6ef72308d737d205f0c0258f590df72948`
- Published hardening implementation commit:
  `15d73abedb191e3d0e63b7da68d1a13e70ae10d0`
- Published checkpoint immediately before the PR-phase status commit:
  `6e60b9daf8b0f345200fa0cc01d5d2663adc2c4c`
- The local branch and `origin/hardening/post-build39-baseline` are synchronized
  at that exact checkpoint with no ahead/behind difference.
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
- Refreshed `origin/main` is
  `3df3e1c729d1829a6aa3f534c9014ba4ee3af2a6`, the accepted Build 38 merge.
  Build 39 and this hardening revision are not merged into `main`.
- No binary has been signed, uploaded, assigned to testers, or submitted from
  this hardening branch.

## Current task

Move the completed post-Build-39 hardening revision into formal review and
obtain exact-head macOS/Xcode, XCTest, packaged-resource, and Swift CodeQL
evidence. Feature work remains frozen. Any CI correction must stay on this
branch and repeat the full review cycle.

## Completed work

The published hardening implementation now includes:

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

Repository checks found no reachable Git corruption. `git fsck` reported only
ordinary unreachable objects and a zero-byte empty worktree `refs` directory
warning; neither affects reachable source history. The temporary
`.helper-test` directory was verified empty and removed non-recursively.

These Windows checks cannot compile Swift or run iOS tests. Exact-source
macOS/Xcode 26.0.1 compilation, strict-concurrency diagnostics, the complete
XCTest/security/lifecycle suite, packaged-resource verification, Darwin
filesystem behavior, and Swift CodeQL remain mandatory. Build 39's green
evidence proves the released base, not this new hardening diff.

No GitHub Actions, Xcode, XCTest, or CodeQL result exists yet for the PR-phase
head containing this checkpoint.

## Git helper status

The `libiconv-2.dll` popup came from Codex's bundled Git HTTPS helper, not from
the KeyHollow repository.

- Host-level `GIT_EXEC_PATH` now points to the installed system Git helper
  directory:
  `C:\Users\Cynfox\AppData\Local\Programs\Git\mingw64\libexec\git-core`
- System Git at
  `C:\Users\Cynfox\AppData\Local\Programs\Git\cmd\git.exe`
  successfully completed GitHub `ls-remote`, fetch, and push operations.
- Use that explicit system Git executable for network work in the current
  Codex process.
- Fully quit and reopen Codex later to confirm that a fresh process inherits
  the persistent helper routing; no machine reboot is required.
- The bundled Git helper files now exist but bundled HTTPS remains unproven.
  Leave them untouched. If a fresh Codex process still fails, refresh the
  complete managed runtime with Codex closed rather than copying more DLLs.

This is an environment-tooling issue, not repository or KeyHollow source
corruption.

## Blockers

There is no failing local static gate or open P1/P2 review finding.

Remaining proof and external-control blockers are:

- The exact PR head must pass the complete
  macOS/Xcode/XCTest/resource/CodeQL workflow.
- GitHub's live production environment, branch protection, required checks,
  code-owner review, and secret placement cannot be proven by repository files.
- Physical-device regression testing is required after a future TestFlight
  build.
- External TestFlight and App Store prerequisites remain incomplete.

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

1. Open a pull request from the current published
   `hardening/post-build39-baseline` head into refreshed `main` at
   `3df3e1c729d1829a6aa3f534c9014ba4ee3af2a6`.
2. Require that exact head to pass Xcode generation and compilation, the
   complete simulator test suite, packaged-resource checks, and Swift CodeQL.
3. Resolve any CI finding on this branch and repeat the full review/gate cycle.
4. After a green exact revision, obtain Frank's explicit approval before merge.
5. Require the eventual merged `main` commit to pass the same complete gates.
6. Stop before signed upload, tester assignment, or App Store action until a
   full commit SHA, unused build number, and tester group are authorized.

## Frank's decisions required

No further decision is required for the completed local hardening or its
publication to the assigned branch.

Frank's action-time decision is required for:

- Approving and merging the exact hardening revision into `main`.
- Creating or changing GitHub environments, branch protection, reviewers, or
  secrets.
- Retiring or deleting historical remote release branches or secrets.
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
