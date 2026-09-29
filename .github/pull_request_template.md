## Scope

- [ ] This review has one purpose and does not mix architecture work with feature expansion.
- [ ] This change contains no customer-facing feature, or the feature is an independently compiled `KeyHollow<Feature>AddOn` under `KeyHollow/AddOns/<Feature>`.
- [ ] The change names its release-scope item; new behavior has a clear owner, and the diff contains no unrelated refactoring or formatting churn.

## Mandatory architecture contract

- [ ] The add-on exposes narrow interfaces and minimum value types.
- [ ] The protected core does not import or depend on the add-on.
- [ ] Concrete wiring is confined to the application composition layer.
- [ ] Platform, network, cloud, analytics, advertising, and purchase SDKs remain outside the local vault core.
- [ ] Existing vault data and `.khvault` compatibility are preserved, or a versioned migration is separately reviewed.
- [ ] Failure, cancellation, interruption, and removal leave the protected core and source data intact.

## Required evidence before merge

- [ ] Architecture boundary enforcement passed.
- [ ] Complete simulator build and regression/security test suite passed.
- [ ] Swift CodeQL completed with no unresolved security findings.
- [ ] Relevant behavior, compatibility, interruption and cleanup tests passed; limitations and required device tests are recorded.
- [ ] The final diff was reviewed for maintainability and unnecessary coupling, including growth of existing large files.
- [ ] The exact reviewed revision was explicitly approved for protected-main merge.

## After merge, before feature acceptance

Follow `docs/ADDON_RELEASE_POLICY.md`; a merge alone does not authorize upload.
For documentation-only changes, signing/upload/device steps are not applicable.

- [ ] Full CI and Swift CodeQL passed on the exact merged-main commit.
- [ ] No-upload signing preflight passed on that exact commit.
- [ ] The exact source and build number were authorized for protected TestFlight upload.
- [ ] Apple processed the binary and the authorized tester group received it.
- [ ] Physical-iPhone feature, core-regression and data-integrity results are recorded, with any outstanding cases explicit.
- [ ] Accepted source is unchanged; a fix goes through a new reviewed PR. Broader distribution requires separate authorization.
