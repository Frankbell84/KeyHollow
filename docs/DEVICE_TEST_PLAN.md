# KeyHollow Real-Device Security Test Plan

This checklist must be executed on a physical iPhone before external TestFlight distribution.

## Install and first launch

- Install a signed development/TestFlight build on a clean device.
- Confirm first launch offers first-vault setup and does not expose any vault count.
- Create a Standard 8-digit vault and verify successful entry.
- Lock and confirm the same passcode reopens the same vault.
- Confirm an incorrect 8–20 digit passcode shows only the generic failure state.
- Confirm passcodes shorter than 8 digits cannot be submitted or used to create a vault.
- Confirm repeated digits, ascending/descending sequences, and repeated short patterns are rejected during creation and passcode changes.

## Multiple vaults

- From the locked home screen, tap **Create New Vault** without unlocking an existing vault.
- Confirm the action opens new-vault setup without displaying a vault list, vault count, or any existing-vault details.
- From Vault A, create Vault B with a different passcode.
- Import distinct photos into A and B.
- Lock KeyHollow.
- Confirm Passcode A opens only A and Passcode B opens only B.
- Confirm neither vault UI reveals the existence, passcode length, name, count, or contents of the other vault.
- Create vaults using 8, 10, 12, 16, and custom-length passcodes.

## Brute-force throttling

- Enter enough invalid passcodes to trigger each configured delay tier.
- Verify a known valid vault passcode does not erase global failed-guess history.
- Verify the throttle eventually decays according to policy.
- Verify the lock screen does not reveal whether a guessed locator existed.

## Copy to Vault

- Select one photo and Copy to Vault.
- Confirm the encrypted vault copy appears and opens.
- Confirm the original remains in Apple Photos.
- Repeat with multiple photos and limited Photos permission.

## Move to Vault

- Select one photo and Move to Vault.
- Confirm KeyHollow encrypts and verifies the vault copy before requesting deletion from Photos.
- Approve deletion and confirm the original is removed from Photos while the vault copy remains readable.
- Deny/cancel deletion and confirm KeyHollow reports the operation as copied, not moved.
- Test a mixed batch where one item cannot be represented by a deletable asset identifier; verify KeyHollow deletes none of the originals for that batch and treats it as copied.

## Photo integrity and tamper behavior

- Import photos of different sizes/orientations.
- Force-quit and reopen; confirm gallery and images decrypt correctly.
- Confirm encrypted thumbnails reload correctly.
- Modify/corrupt a test vault blob in a development environment and verify authentication fails closed rather than displaying partial/corrupt plaintext.

## Background and app-switcher privacy

- Open a sensitive photo and send KeyHollow to the background.
- Confirm the active vault session is destroyed.
- Confirm the app-switcher preview shows only the opaque KeyHollow privacy shield and never the photo/gallery.
- Return to KeyHollow and confirm a passcode is required again.
- Repeat during photo import, gallery view, and full-screen photo view.

## Device authentication exclusion

- Confirm there is no Face ID prompt anywhere in the app.
- Confirm there is no Touch ID prompt on supported hardware.
- Confirm the iPhone device passcode cannot substitute for a KeyHollow vault passcode.
- Confirm Keychain access used by KeyHollow does not present a biometric/device-passcode unlock path to the user.

## Passcode change

- Change Vault A's passcode using the current passcode.
- Confirm the old passcode no longer opens the vault.
- Confirm the new passcode opens the same photos with no re-import required.
- Confirm attempting to change to a passcode already associated with another vault fails without revealing why.

## Vault deletion

- Delete a non-final vault only after current-passcode verification and explicit DELETE confirmation.
- Confirm its passcode no longer opens anything.
- Confirm its encrypted photo directory is removed.
- Confirm other vaults are unchanged.
- Delete the final vault and confirm KeyHollow returns to first-vault setup.

## Permissions and interruptions

- Test Photos permission states: full, limited, denied, and changed in Settings while KeyHollow is installed.
- Interrupt imports by backgrounding the app.
- Force-quit during import and verify no committed manifest entry points to missing plaintext/ciphertext data.
- Test low-storage behavior and verify operations fail without falsely reporting success.

## Backup Verification Center

Run these checks with a TestFlight-delivered candidate and disposable test
archives. Do not use the only copy of a real backup for tamper tests.

- Before testing, duplicate every archive and record each good source's name,
  byte size, SHA-256, catalog version, expected photo/file counts, and recovery
  code. Record existing vaults, root counts, folder membership, representative
  readable items, and iOS Settings' reported storage use for KeyHollow.

- From the locked home screen, open **Verify Backup**, select a valid current
  `.khvault`, enter its recovery code, and confirm progress is visible until a
  sanitized report appears.
- Confirm the report's photo count, general-file count, source creation date,
  payload-catalog version, and compatibility limitations match the selected
  archive. The selected backup filename may appear; confirm the report does not
  display a LowKey, recovery code, vault key, archived-item filenames, folder
  names, or item contents.
- Confirm the report states that current backups do not preserve folder names
  or folder membership and that a future restore places content at vault root.
- Lock or dismiss the report, reopen Backup Verification, verify the same
  archive again, and confirm the report is identical and the source archive is
  unchanged.
- Enter a wrong recovery code and confirm verification fails without installing
  a vault, unlocking a vault, or exposing whether any local vault matches.
  Confirm the recovery-code field is cleared before another attempt.
- Verify separate corrupted and truncated copies and confirm both fail closed
  without a success report or any change to existing vaults.
- Cancel the picker, replace one selected archive with another, and confirm the
  picker prevents selection of an unsupported item. If a Files provider offers
  a mislabeled unsupported item, confirm KeyHollow rejects it. Confirm no old
  filename, recovery code, report, or success state survives those transitions.
- Start verification of a representative large archive and cancel once during
  **Copying backup into protected storage...** and once during
  **Authenticating every file...**. Repeat
  those interruptions by backgrounding or locking KeyHollow and by force-
  quitting once in each stage. Confirm no success report appears, the app-
  switcher privacy shield is opaque, reopening requires the expected
  authentication, and a fresh verification can start normally.
- Unlock an existing vault, open Backup Verification from **Vault Security**,
  verify a valid archive, and confirm the open vault's contents, folder
  membership, LowKey, and session behavior are unchanged.
- Cover a photo-only archive, a general-file-only archive, a mixed archive, and
  an archive containing a video imported as a general file. If maintained
  legacy v1 and v2 fixtures are available, confirm their limitations are
  reported accurately; do not fabricate replacement fixtures on the device.
- Repeat verify/cancel at least five times. Confirm KeyHollow storage does not
  grow by approximately one archive per attempt; this is the physical-device
  proxy for checked ingress and extracted-staging cleanup.
- With less safe free space than a representative large archive requires,
  confirm selection fails for insufficient storage without a report, install,
  or vault mutation. Free space, relaunch, and verify a good archive normally.
- Recalculate every good source archive's SHA-256 and compare the recorded local
  vault, item, folder, and storage state. Require byte-identical sources and no
  new vault, LowKey, passcode behavior, item, or folder mutation.
- After verification tests, use the normal import flow on a disposable archive
  and confirm verification did not replace, bypass, or change that separate
  install path.
- Complete a core smoke pass: lock/unlock each existing vault; scroll the
  gallery; open a Photos-origin image, Files-origin image, non-image file, and
  video; move a mixed selection into and out of a folder; export a general file;
  export and restore a fresh disposable `.khvault`; then background an open
  image/video and confirm the privacy shield and relock. Reject any lag, crash,
  missing item, incorrect folder mutation, or plaintext-residue symptom.

## Backup/container inspection

- Confirm KeyHollow encrypted storage directories/files carry complete file protection.
- Confirm protected vault data is excluded from ordinary backup as designed.
- Inspect the app container in a development environment and verify no plaintext photos, thumbnails, passcodes, keys, sensitive filenames, or manifest contents are persistently stored.

## Release gate

External TestFlight distribution should not begin until all critical items above pass or have a documented accepted risk. App Store security claims require the separate independent security review described in `SECURITY_ARCHITECTURE.md`.
