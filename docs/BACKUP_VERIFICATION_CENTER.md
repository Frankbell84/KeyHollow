# Backup Verification Center

Backup Verification Center is roadmap add-on #2. It lets a user select a local
`.khvault` file and authenticate its complete supported contents with the
separate recovery code, without installing the vault or changing any existing
vault.

## Scope

This phase is intentionally local and read-only.

- Reuse the authenticated archive reader, payload extractor, catalog checks,
  photo validation, and supplemental general-file validation already owned by
  `KeyHollowTransferCore`.
- Return a sanitized immutable report containing only payload-catalog and
  compatibility information, authenticated content counts, source creation
  time, and explicit legacy-size warnings.
- Copy a user-selected archive into the existing protected, disposable
  `.khvault` ingress area before verification.
- Cancel verification and remove protected staging when the app locks,
  backgrounds, the user leaves, or an error occurs.
- State clearly that the current portable format preserves photos and general
  files but not Folder Presentation names or membership.

This phase does not add installation, restore, local vault unlock, recovery-code
reuse, persistent verification history, sync, cloud storage, accounts, backup
destinations, automatic scheduling, archive-format changes, or a second parser
or cryptographic path.

## Module mapping

| Responsibility | Current owner | Additive change |
| --- | --- | --- |
| Container authentication and payload validation | `KeyHollowTransferCore` | Add one verify-and-discard facade over the existing restore validator. |
| Protected Files-provider ingress | `KeyHollowFileRecognitionAddOn` | Reuse the established copy boundary and add checked, reference-owned cleanup plus canonical crash-debris recovery. |
| General-file archive authentication | App composition through `GeneralFilePortableTransferBridge` | Reuse unchanged. |
| Sanitized report model and presentation | New `KeyHollowBackupVerificationAddOn` | Accept no vault key, ciphertext, store, staging URL, install capability, or recovery credential. |
| File picker, recovery-code lifetime, cancellation, and lock handling | Application composition layer | Coordinate existing modules and publish only the sanitized report. |
| Vault installation and local LowKey creation | Existing import/unlock flow | Remain separate and unchanged. |

## Security invariants

1. `ValidatedPortableVaultRestore` never crosses the TransferCore/application
   boundary because it contains recovered vault material.
2. Verification always relinquishes and deletes extracted staging before a
   report is returned.
3. The recovery code is used only as a portable-archive credential and is
   cleared after success, failure, cancellation, lock, or dismissal.
4. A successful report cannot install a vault, write a local credential, create
   a restore transaction, or expose a vault key.
5. Wrong credentials, tampering, truncation, malformed catalogs, unsupported
   versions, symlinks, and topology changes fail closed.
6. Legacy v1/v2 compatibility is reported honestly. Content that receives only
   outer-container and per-entry authentication is never described as fully
   opened or migrated.

## Implemented checkpoint

- `KeyHollowTransferCore` now exposes one verify-and-discard facade over the
  existing restore validator. It does not expose the secret-bearing validated
  restore object and refuses to return a report when checked staging cleanup
  fails.
- `KeyHollowBackupVerificationAddOn` is an independently compiled, dependency-
  free static target containing only immutable report values, presentation
  policy, and the read-only report view.
- The application owns the Files picker, recovery-code lifetime, progress,
  cancellation, accessibility focus, and mapping from the TransferCore report.
- File Recognition now keeps ingress cleanup attached to every copied value,
  preserves live copies across concurrent operations, and removes only stale
  canonical UUID directories when a later ingress begins.
- The locked home screen and unlocked vault menu both expose the same local,
  read-only verification flow. Existing import remains a separate operation.
- No vault format, encryption primitive, persistent store, install transaction,
  local LowKey, sync behavior, account behavior, or release state changed.

## Required validation

- Valid v1, v2, and v3 payload catalogs, using authentic encrypted store-backed
  content for the legacy-version compatibility cases.
- Photo-only, file-only, mixed-content, and video-as-general-file archives.
- Wrong recovery code, corruption, truncation, cleanup failure, and the existing
  shared validator's malformed-catalog, unsupported-version, staged-mutation,
  topology, and symlink rejection coverage.
- Cancellation, picker dismissal, replacement, lock/background cleanup, and
  crash-debris convergence with no success report before checked cleanup.
- Repeated verification with identical reports, unchanged source bytes, no
  credential-store or restore-journal capability, and no installed vault.
- Independent add-on compilation under strict concurrency and warnings as
  errors, complete simulator/security/lifecycle tests, and Swift CodeQL.

All repository-local architecture, release-hygiene, workflow-security, privacy,
source/environment, build-number, script-syntax, and patch-integrity gates pass
on Windows. Exact-source macOS/Xcode compilation and runtime tests remain
mandatory before merge consideration.

## Future boundary

The architecture addendum's Backup & Sync Center is a separate future module
covering destinations, devices, status history, recovery information, and
optional account services. It must not be folded into this local verification
phase. Search, nested folders, import progress, cross-vault references,
Break-in Reports, App Icon Camouflage, and Vault Escape Hatch also remain
separate later work.
