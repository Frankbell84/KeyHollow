# Retired V2 Beta Isolation Boundary

This file records a historical experiment. It is not a current release path.
The production application already contains the reviewed encrypted-vault
transfer implementation, and `.github/workflows/testflight-beta.yml` is
intentionally disabled.

## Repository boundary

- Production remains on protected `main`.
- Historical `integration/v2-encrypted-vault-transfer` and `delivery/v2-beta`
  branches are reference material only. They must not upload, sign, or be
  merged wholesale.
- The remote `delivery/v2-beta` branch must be neutralized or removed through a
  separately authorized repository-maintenance change because a workflow is
  evaluated from the branch that contains it.

## Device boundary

- V1 bundle identifier: `com.keyhollow.app`
- V2 beta bundle identifier: `com.keyhollow.app.beta`
- V2 display name: `KeyHollow Beta`

The separate bundle identifier gives the beta its own application container,
preferences, Keychain access group, and local vault storage. Installing or
deleting KeyHollow Beta must not upgrade, replace, or delete the production
KeyHollow app or its vaults.

The production TestFlight workflow is restricted to `main`. There is no active
beta upload workflow. A future side-by-side beta requires a new review of the
app and embedded-extension identifiers, entitlements, provisioning profiles,
Keychain access, local containers, release environment, and exact-source CI
binding before any signing secret is made available to it.

## Requirements before any future beta is reintroduced

1. Existing V1 unit, security, launch, Copy, Move, and lifecycle tests remain
   green on the V2 integration branch.
2. All portable-archive tamper, hostile-input, collision, cancellation, and
   rollback tests pass.
3. Export and import receive an isolated user interface with clear recovery
   credential, progress, cancellation, storage, and no-source-deletion rules.
4. Repeated `.khvault` transfers succeed between two physical iPhones.
5. Forced termination is tested at every export and import commit boundary.
6. Large-vault testing demonstrates bounded memory and sufficient-storage
   failure handling.
7. The beta release workflow is manual-only, environment-protected, bound to a
   full exact-commit CI/CodeQL success, and independently reviewed before use.
8. Reintroduction follows `docs/ADDON_RELEASE_POLICY.md`; historical branch
   state is never treated as release evidence.
