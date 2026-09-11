# Production release controls

The production TestFlight workflow is intentionally fail-closed. A reference to
an environment name is not sufficient by itself: GitHub can create a missing
environment without protection rules. KeyHollow therefore verifies the live
environment policy before any signing or App Store Connect credential is used.

## Required GitHub configuration

Before the next production upload:

1. Create the environment named exactly `production-testflight`.
2. Set its deployment branches to **Selected branches and tags**, then add one
   branch rule named exactly `main`. Do not add a wildcard or tag rule.
3. Add a nonempty, randomly generated environment secret named
   `PRODUCTION_RELEASE_GUARD`.
4. Populate or safely rotate these credentials in that environment:
   - `APP_STORE_CONNECT_API_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_BASE64`
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `BUILD_CERTIFICATE_BASE64`
   - `BUILD_PROVISION_PROFILE_BASE64`
   - `KEYCHAIN_PASSWORD`
   - `P12_PASSWORD`
   - `THUMBNAIL_PROVISION_PROFILE_BASE64`
5. Protect `main`: require a pull request, require the exact `build-and-test`,
   `CodeQL (Swift)`, and GitHub Advanced Security `CodeQL` checks, require the
   branch to be current, and require conversation resolution. Apply the rule to
   administrators and prevent force pushes and branch deletion.
6. Neutralize the historical `delivery/v2-beta` push uploader before making any
   further push to that branch.
7. After every environment credential has been entered, run the manual
   `Verify KeyHollow Release Signing` workflow on an exact successful `main`
   commit. This preflight must authenticate, archive, export, and validate the
   signed product without uploading or publishing it.
8. Only after that first preflight passes, remove the repository-scoped copies
   of the eight production credentials, then rerun the same preflight. The
   second run must prove no release path can fall back to repository-scoped
   production secrets. The retired beta credential is outside this cutover and
   requires its own explicit cleanup decision.
9. Keep replaced Apple credentials available through the rollback window. Do
   not retire a prior distribution certificate until its replacement-signed
   build is processed, installed, launched, and device-tested successfully.
   Revoke the prior App Store Connect API key only as the final credential-
   cutover action. Build 40 completed this sequence on 2026-09-11.

Configure a required environment reviewer so every release job pauses before
signing secrets are exposed. While Frank is the sole release operator, make
Frank the required reviewer and leave prevention of self-review disabled so the
authorized job can be approved. When a real independent reviewer is available,
make that reviewer required and enable prevention of self-review. Never enable
prevention of self-review while only the initiating operator can approve.

While Frank is the repository's sole reviewer and code owner, require pull
requests but require zero approvals. Do not require code-owner review, stale-
approval dismissal, or approval of the most recent push until an independent
reviewer is available: GitHub does not allow a pull-request author to approve
their own change. `CODEOWNERS` still records ownership of sensitive paths.

## Enforced in the repository

- External actions are allowlisted and pinned to full commit SHAs.
- Broad XcodeGen source trees accept only reviewed source types, exact metadata,
  and assets declared by their catalog metadata; stray resources and symlinks fail.
- CI has read-only token permissions except for the CodeQL result upload.
- Production upload is manual, serialized, and restricted to `main`.
- The merged Build 40 runner correction places both privileged release jobs on
  the same `macos-15-arm64` image family and pinned Xcode 26.0.1 build as
  validation CI. They fail before App Store authentication unless the runner
  architecture, iOS 26.0 SDK, and matching available runtime are all exact.
- The selected commit must be a lowercase 40-character SHA and must equal the
  checked-out workflow commit.
- The same SHA must have a successful complete CI run produced by a push to
  `main`; pull-request or manually dispatched CI evidence is rejected.
- The live `production-testflight` environment must exist and expose exactly the
  `main` deployment branch policy, exactly one required reviewer
  (`Frankbell84`) with self-review allowed, and no administrator bypass; GitHub
  must also report `main` as protected.
- Release-policy API checks send the workflow token only to their exact
  `https://api.github.com` endpoints and reject redirects or response-URL drift.
- The environment-only sentinel must be present before any signing/API secret is
  referenced.
- The manual `release-signing-preflight.yml` workflow is bound to the protected
  environment and exact `main` source. It authenticates with App Store Connect,
  creates an unsigned archive, then exports and inspects the signed IPA, and
  contains no upload, publication, tester-assignment, or App Store mutation
  step.
- Both release paths finish the unsigned archive and archive/privacy checks
  before exposing signing material. The raw P12 is deleted immediately after
  its exact keychain identity is validated, and the imported private key is
  marked non-extractable; cleanup retains an always-run fixed-path fallback.
- The production workflow retains a signed IPA artifact only after the signed
  product is verified and the temporary signing authority has been removed.
  Artifact retention must itself succeed before the App Store Connect key is
  installed or any upload begins, so failed or unverified output is never
  published and an artifact failure cannot follow an accepted Apple upload.
- The App Store Connect private key is decoded only inside the final upload
  step and an exit trap removes it whether the upload succeeds or fails; the
  always-run cleanup retains a fixed-path fallback.
- The retired beta workflow has no token permissions, no secrets, no actions,
  and an unconditional false job guard.
- Sensitive release, cryptographic, storage, transfer, privacy, and project
  configuration paths are assigned to `@Frankbell84` in `CODEOWNERS`.

`CODEOWNERS` records responsibility. Its approval gate should be enabled when a
real independent reviewer is available, not while doing so would deadlock the
sole owner.

## Live control status (2026-09-11)

The following controls are now configured and were verified against GitHub:

- `main` is protected. Pull requests, the exact required CI and CodeQL checks,
  an up-to-date branch, and conversation resolution are required; administrator
  bypass, force pushes, and branch deletion are disabled.
- The `production-testflight` environment exists and accepts deployments only
  from the exact `main` branch.
- Frank is the required environment reviewer. Self-review prevention remains
  disabled while Frank is the sole release operator, and administrator bypass
  is disabled.
- The environment contains the nonempty random
  `PRODUCTION_RELEASE_GUARD` sentinel. Its value was generated directly for the
  environment and was not written to source, local files, or operational notes.
- The environment contains a newly generated random `KEYCHAIN_PASSWORD`. This
  value protects only the temporary CI keychain and is not tied to the Apple
  Distribution certificate.
- The environment contains the three App Store Connect API secrets for
  replacement key `W3UF745JN4`. A direct read-only API request and the
  repository's authenticated build lookup both succeeded with that key. Legacy
  key `JD6P6X8C9A` was revoked on 2026-09-11 after Build 40 device acceptance.

The replacement Apple Distribution certificate, exportable P12, and exact app
and thumbnail-extension App Store profiles have been validated locally. Their
four environment secrets—`BUILD_CERTIFICATE_BASE64`,
`BUILD_PROVISION_PROFILE_BASE64`, `P12_PASSWORD`, and
`THUMBNAIL_PROVISION_PROFILE_BASE64`—are present, so all nine expected
environment-secret names are installed. Repository-scoped fallback copies
were removed only after protected preflight
[#34598236304](https://github.com/Frankbell84/KeyHollow/actions/runs/34598236304)
passed. Protected preflight
[#34600941660](https://github.com/Frankbell84/KeyHollow/actions/runs/34600941660)
then proved that no release path can fall back to repository-scoped production
secrets.

The first protected no-upload attempt
[#34556497300](https://github.com/Frankbell84/KeyHollow/actions/runs/34556497300)
passed exact-source CI, live-environment, security, privacy, identity, project-
generation, and App Store authentication gates. It stopped at the unsigned
archive before signing material was installed because its `macos-26-arm64`
image lacked the iOS 26.0 runtime required by pinned Xcode 26.0.1. No signing,
export, upload, or publication occurred. PR #54 merged the isolated runner
correction as exact `main` commit
`95cd9f9deb2f99fe5f5962cc5ac96c2a47d12f33`, and complete main-push CI run
[#34560364159](https://github.com/Frankbell84/KeyHollow/actions/runs/34560364159)
passed.

Protected no-upload run
[#34561820231](https://github.com/Frankbell84/KeyHollow/actions/runs/34561820231)
then completed authentication and the unsigned archive before failing closed in
the signing-material install step. The P12 imported successfully; its one
signing leaf and ordinary CA chain produced three keychain certificates, while
the workflow incorrectly required one certificate total. No signed IPA or
upload was produced. The isolated correction selects exactly one non-CA leaf
from the P12 and independently requires exactly one valid code-signing identity
matching the approved fingerprint. It does not weaken the Apple-team, profile,
export, post-export, or cleanup checks.

PR #55 merged that leaf-selection correction as exact `main` commit
`015823d3ee69d8e52a668800ce9ee35d001221a8`; complete main-push CI run
[#34564973012](https://github.com/Frankbell84/KeyHollow/actions/runs/34564973012)
passed both required jobs with zero annotations. Protected no-upload run
[#34566854574](https://github.com/Frankbell84/KeyHollow/actions/runs/34566854574)
then passed every gate through signed IPA export and validation of both code
signatures. It stopped safely during the final leaf-certificate extraction
because the optional `codesign --extract-certificates` output prefix was passed
as a separate token instead of being attached with `=`. The imported approved
leaf and exact profiles had validated, and both products passed `codesign`
structural and designated-requirement checks; the final byte-for-byte proof that
each product used that exact leaf had not completed. Cleanup passed, the
preflight contained no upload capability, and nothing was uploaded or retained.
The follow-up correction is limited to the two extraction-option bindings plus
fail-closed regression coverage for their exact command forms.

The reviewed release-workflow source pins the approved rotation identities:
App Store Connect key `W3UF745JN4`, issuer
`ba45844d-8147-4d78-932b-bfdbbbc55dc0`, distribution-certificate SHA-1
`7E2342E196D2A56E95A05BCBDD473FE3799B7EDD`, app-profile UUID
`b9a24dc9-04a3-40e1-b0e3-fe7538e6e341`, and thumbnail-profile UUID
`c9564b6f-22cd-490b-9f59-f91e98a4a065`. These identifiers are public binding
metadata, not credential values. Any rotation requires an explicit reviewed
source change as well as replacement environment secrets.

## Build 40 cutover completion

- PR [#56](https://github.com/Frankbell84/KeyHollow/pull/56) merged the exact
  reviewed release-verifier head
  `426768238433017ea11773220c3f61378d3f7cd3` as exact `main` commit
  `54bd2d6887f3ca0e476339fce05e90dd59ba963f`. Its PR and merged-main CI runs
  passed all required checks.
- Replacement-only protected preflight
  [#34600941660](https://github.com/Frankbell84/KeyHollow/actions/runs/34600941660)
  passed before release.
- Protected upload
  [#34602241254](https://github.com/Frankbell84/KeyHollow/actions/runs/34602241254)
  produced the validated Build 40 binary, retained the verified IPA artifact,
  and assigned the build only to `KeyHollow Internal`. Frank installed and
  device-tested that binary successfully.
- The legacy Apple Distribution certificate `2P45VCTJVL` was revoked after
  device acceptance. Apple Developer then showed replacement certificate
  `4RU4X6GAGU` as the sole active Distribution certificate.
- Legacy App Store Connect API key `JD6P6X8C9A` was revoked last. Replacement
  key `W3UF745JN4` remained the sole active team key.
- Final protected no-upload preflight
  [#34610956286](https://github.com/Frankbell84/KeyHollow/actions/runs/34610956286)
  subsequently passed App Store Connect authentication, exact-source and live-
  environment gates, archive and privacy checks, replacement-only signing,
  signed-IPA verification, and cleanup. It uploaded or retained nothing.

The old-credential rollback path is closed. A source rollback must be delivered
as a new higher-numbered build using the active protected replacement set. If
that set is lost, revoked, or compromised, recovery must issue new credentials
and profiles through the same reviewed rotation process; it must never weaken
the protected environment or reuse revoked material.
