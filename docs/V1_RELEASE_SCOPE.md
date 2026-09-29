# Local release scope and gap closure

Updated 2026-09-29. This is the current product-scope checkpoint. The user
authorized closing gaps in the original add-ons 1-7 while preserving code
quality. Hollow Notes and the broader Architecture Addendum remain outside
this release. The dependency plan and foundation contract supply engineering
constraints, not permission to substitute another feature list.

## Goal and provenance

Complete the local privacy suite without a KeyHollow account, cloud service,
or subscription. Original source: the N150 task **Continue KeyHollow iOS
setup**, ID `01a0549d-0969-7f01-9063-52a344831373`, on 2026-09-04. The user's
scope instruction was: "include 1 through 7 in the release we are doing, so
that the next release 8 through 10 turns on the subscription model."

The original discussion called these Release 2 and Release 3; the current
conversation calls the local launch V1. The seven commitments, rather than
that historical numbering, define scope. Items 8-10 are optional encrypted
cloud backup, multi-device sync, and subscriptions for the later release.

## Audited commitments

Audited against Build 59 source `030172bb8750ccadb19b2cee6d922812d6278295`.
Implementation is not equivalent to complete physical-device acceptance.

| Original add-on | Present | Gap / closure condition |
| --- | --- | --- |
| 1. `.khvault` recognition | Files open-in routes to protected import. | No new core capability identified; retain valid/invalid, locked/unlocked and source-preservation regression checks. |
| 2. Backup Verification Center | Read-only verification, contents, size, version, vault creation and verification dates. | Display the authenticated archive export date already stored in `PortableArchiveSecrets.exportedAt`; keep all three dates distinct. No new archive format is needed. |
| 3. General File Support | Encrypted import/export/delete for supported documents, audio and other files. | Preserve the bounded 50-file selection and 100 MiB per-file behavior until the separately reviewed large-file stage. No arbitrary preview/creator features are added to this commitment. |
| 4. Video Support | In-limit import, playback, encrypted thumbnails and export; accepted viewer repairs. | Large-video streaming and storage safeguards remain unimplemented. Review resource limits, encrypted storage, seeking, cancellation, cleanup and backup compatibility before lifting the current 100 MiB ceiling. |
| 5. Vault Organization | Nested folders, rename, moves, sorting and current-location name search. | Deliver tags with complete persistence, backup, restore, deletion and locked-state behavior. Define bounded filtering with this stage; recursive/global/OCR search was not an established launch requirement. Folders satisfy the original "folders or albums" choice. |
| 6. Expanded Bulk Controls | Individual selection, Select All, bulk move/delete and type-specific export. | Add range selection and consistent progress plus safe user cancellation for long operations. Selection must use the visible sorted/filtered snapshot; committed work must be reported honestly when canceled. |
| 7. Guided Device-to-Device Transfer | Manual encrypted export, verification and restore; source retained. | Guide sending via Files/AirDrop, receiving, restore and destination verification before optional cleanup. Keep sources by default. Real two-phone acceptance remains deferred because only one phone is available. No account/pairing service is required. |

The user reported Build 58 current-folder import and same-phone backup success,
and Build 59 Rename success. PRs #94 and #96 retain exact delivery evidence.
These reports do not establish the full legacy, tamper, interruption,
low-storage or two-device matrix. Do not silently convert deferred tests into
passing results or remove them from release acceptance.

## Engineering sequence

This order is an implementation recommendation within the authorized scope.
Each row is a separate reviewable stage, not one combined feature PR.

1. Reconcile Build 59 acceptance, freeze this scope, and align the PR checklist
   with the existing protected-main-first release policy (documentation only).
2. Close the backup-date gap using the existing authenticated field. Test
   legacy/current archives and distinguish vault, backup and verification dates.
3. Complete tags and bounded filtering. Apply the foundation contract's real
   metadata owner and portable-data requirements with this first consumer;
   do not build an unused generic framework. Confirm the filter behavior in
   the stage design before implementation.
4. Complete range selection and long-operation controls against the settled
   visible catalog. Reuse session task ownership and existing storage commits.
5. Complete the large-video design and implementation as separately reviewable
   sub-stages. Preserve historical readers and data, establish measured memory
   and disk bounds, and cover backup/restore before claiming completion.
6. Finish the guided transfer experience using the final data behavior. Complete
   real two-phone validation when hardware is available, then close the full
   release regression and failure matrix for the final candidate.

No stage requires cloud, subscriptions, Notes, camera/scanner, Legacy or
messaging. Adding a requirement or deferring an original commitment must be
recorded explicitly; it must not emerge from an assistant recommendation.

## Maintainability and churn controls

Existing automated gates enforce architecture boundaries, workflow security,
release hygiene and privacy manifests. Native CI compiles independently owned
add-ons with strict concurrency/warnings as errors, runs regression tests and
Swift CodeQL. Protected-main and exact-source release gates remain mandatory.
These checks do not prove readable or appropriately sized code.

Manual review must therefore also establish:

- One behavior change and one clear owner per feature stage; only necessary
  integration edits, with no unrelated formatting, renames or refactors.
- Small cohesive policies/coordinators for new behavior. The already large
  gallery and transfer coordinator are integration points, not default homes
  for more business logic. Extract only the responsibility this stage needs;
  avoid a broad rewrite or arbitrary line-count target.
- Reuse existing encrypted storage, validation, lock/cancellation and cleanup
  contracts. Do not duplicate validators, introduce global mutable state or
  bypass core rules to make a test pass.
- For any persisted data change, review its owner and complete compatibility,
  export/restore, deletion, interruption and recovery behavior in the same
  stage. Never claim a safe downgrade without evidence.
- Tests demonstrate behavior and failure boundaries, rather than mirroring
  implementation. Do not relax checkers to accommodate a boundary violation.
- Inspect the final diff for accidental churn and record exact CI evidence,
  device evidence and remaining limitations. Do not begin the next
  architectural stage while this one is failing or unrecoverable.

The [add-on release policy](ADDON_RELEASE_POLICY.md) controls merge, signing,
upload and device acceptance. Source approval and distribution are distinct.
The current delivery checkpoint is [WORK_STATUS.md](../WORK_STATUS.md).
