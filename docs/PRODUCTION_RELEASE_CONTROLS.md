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
4. Copy these existing credentials into that environment:
   - `APP_STORE_CONNECT_API_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_BASE64`
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `BUILD_CERTIFICATE_BASE64`
   - `BUILD_PROVISION_PROFILE_BASE64`
   - `KEYCHAIN_PASSWORD`
   - `P12_PASSWORD`
   - `THUMBNAIL_PROVISION_PROFILE_BASE64`
5. Protect `main`: require a pull request, the complete KeyHollow iOS Build and
   CodeQL checks, stale-review dismissal, conversation resolution, and code-owner
   review. Prevent force pushes and branch deletion.
6. Neutralize the historical `delivery/v2-beta` push uploader before making any
   further push to that branch.
7. After the protected environment has been validated, remove the repository-
   scoped copies of the production credentials and the retired beta credential.
   Do not delete the repository copies until the environment copies have been
   entered and checked.

If the GitHub plan and repository visibility support environment reviewers, add
a trusted reviewer and disable self-review. Do not enable prevention of
self-review when no second trusted reviewer exists, because that would make a
legitimate release impossible.

## Enforced in the repository

- External actions are allowlisted and pinned to full commit SHAs.
- Broad XcodeGen source trees accept only reviewed source types, exact metadata,
  and assets declared by their catalog metadata; stray resources and symlinks fail.
- CI has read-only token permissions except for the CodeQL result upload.
- Production upload is manual, serialized, and restricted to `main`.
- The selected commit must be a lowercase 40-character SHA and must equal the
  checked-out workflow commit.
- The same SHA must have a successful complete CI run produced by a push to
  `main`; pull-request or manually dispatched CI evidence is rejected.
- The live `production-testflight` environment must exist and expose exactly the
  `main` deployment branch policy, and GitHub must report `main` as protected.
- The environment-only sentinel must be present before any signing/API secret is
  referenced.
- The retired beta workflow has no token permissions, no secrets, no actions,
  and an unconditional false job guard.
- Sensitive release, cryptographic, storage, transfer, privacy, and project
  configuration paths are assigned to `@Frankbell84` in `CODEOWNERS`.

`CODEOWNERS` records responsibility, but GitHub only enforces its review rule
when branch protection is configured to require code-owner approval.
