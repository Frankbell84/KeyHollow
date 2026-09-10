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
- Return a sanitized immutable report containing only archive format and
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
| Protected Files-provider ingress | `KeyHollowFileRecognitionAddOn` | Reuse unchanged. |
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

## Required validation

- Valid v1, v2, and v3 archives where existing fixtures support them.
- Photo-only, file-only, mixed-content, and video-as-general-file archives.
- Wrong recovery code, corruption, truncation, malformed catalog, unsupported
  version, staged mutation, and symlink rejection.
- Cancellation and lock/background cleanup with no retained extraction tree.
- Repeated verification with no credential-store write, restore journal, or
  installed vault.
- Independent add-on compilation under strict concurrency and warnings as
  errors, complete simulator/security/lifecycle tests, and Swift CodeQL.

## Future boundary

The architecture addendum's Backup & Sync Center is a separate future module
covering destinations, devices, status history, recovery information, and
optional account services. It must not be folded into this local verification
phase. Search, nested folders, import progress, cross-vault references,
Break-in Reports, App Icon Camouflage, and Vault Escape Hatch also remain
separate later work.
