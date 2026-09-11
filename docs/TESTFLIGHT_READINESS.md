# KeyHollow TestFlight Readiness

## Already prepared in source

- Native iOS target: KeyHollow
- Bundle identifier: `com.keyhollow.app`
- Minimum iOS version: 17.0
- Version: 1.0; latest accepted internal binary is Build 39
- Build 40 is the next source candidate for Backup Verification Center device
  validation. It has not been signed, uploaded, processed, accepted, or assigned
  to any tester group. A live App Store Connect check on 2026-09-10 showed Build
  39 as the newest upload and no Build 40 record. The release workflow must
  still repeat its API-backed build-number check immediately before release.
- Reproducible XcodeGen project generation with a pinned XcodeGen release and
  pinned Xcode 26.0.1 (`17A400`) release toolchain. The merged runner correction
  places both privileged release jobs on `macos-15` and makes them fail before
  authentication unless the ARM64 runner, iOS 26.0 SDK, and matching available
  runtime are all present.
- Release archive configuration present
- Full simulator CI, security/lifecycle tests, and Swift CodeQL
- Photos permission strings
- Apple privacy manifest and standard cryptography export declaration
- Draft privacy policy, support page, and App Store metadata
- App icon asset catalog with a 1024x1024 source image

## Required from the Apple Developer account

These cannot be stored or guessed in source control and must be supplied through Xcode/App Store Connect:

1. Active Apple Developer Program membership. **Complete.**
2. Apple Developer Team `P38X56QHU9`. **Confirmed.**
3. Registration of `com.keyhollow.app`. **Complete.**
4. Apple Distribution certificate and App Store provisioning profiles for the
   app and thumbnail extension. **The prior set delivered Build 39. A replacement
   certificate, exportable P12, and both exact profiles are validated locally
   and installed in the protected environment for Build 40. End-to-end signing
   verification remains pending.**
5. App Store Connect record for KeyHollow (Apple ID `6807022780`). **Complete.**
6. App Store Connect API access and upload key for the cloud release workflow.
   **Replacement key `W3UF745JN4` is installed in the protected environment and
   passed read-only authentication. Prior key `JD6P6X8C9A` remains active until
   the complete cutover is proven.**

## Required product assets before external TestFlight/App Store review

- Publish the included privacy-policy draft at a final HTTPS URL.
- Publish the included support draft at a final HTTPS URL and add the support contact.
- Review and enter the included App Store metadata draft.
- App Store screenshots.
- Age rating answers.
- App privacy questionnaire answers.
- Encryption/export-compliance confirmation based on the final cryptographic implementation.

## Internal TestFlight path

1. Merge an explicitly approved reviewed revision through protected `main`.
2. Require the exact merged commit to pass the full `KeyHollow iOS Build`
   workflow, including tests, architecture/privacy/release gates, and CodeQL.
3. Run `Verify KeyHollow Release Signing` from that exact `main` commit and
   approve its protected `production-testflight` environment gate. It must
   authenticate, archive, sign, export, and validate without uploading.
4. After the first preflight passes, remove the repository-scoped production
   credential fallbacks and require the same no-upload preflight to pass again.
5. Explicitly authorize the full 40-character commit and unused build number.
6. Dispatch `Upload KeyHollow to TestFlight` from that exact `main` commit.
7. Require approval in the protected `production-testflight` environment before
   signing secrets are exposed.
8. Verify App Store Connect processing and assignment only to the authorized
   internal group.
9. Complete `DEVICE_TEST_PLAN.md` on the TestFlight-delivered binary. Any
   failure returns to a new pull request and a new exact-commit validation.
10. Retain the prior distribution certificate until replacement-signed Build 40
    processes, installs, and launches successfully. Revoke prior API key
    `JD6P6X8C9A` only as the final credential-cutover action.

## Build 40 candidate gate

- The certificate-chain-corrected Build 40 preparation is merged through exact
  `main` commit `015823d3ee69d8e52a668800ce9ee35d001221a8`, whose complete main-push
  CI run passed. The remaining `codesign` extraction correction is release
  infrastructure, verifier coverage, and documentation only; it does not
  change application-runtime behavior.
- `CURRENT_PROJECT_VERSION` must be exactly `40` for both the KeyHollow app and
  the KeyHollow Vault Thumbnail extension.
- Build 40 was absent from App Store Connect on 2026-09-10 and remains
  provisional until the release workflow repeats that check immediately before
  upload.
- `main` protection, the `production-testflight` environment, its exact-main
  deployment policy, required-reviewer gate, and random release guard are live.
- All eight production credentials plus the environment-only guard are present
  in the protected environment. Do not dispatch the upload workflow until the
  two-pass no-upload preflight validates the signing material and proves there
  is no repository-secret fallback.
- Protected no-upload run
  [#34556497300](https://github.com/Frankbell84/KeyHollow/actions/runs/34556497300)
  passed every source, CI, environment, architecture, privacy, identity, and App
  Store authentication gate, then failed before signing-material installation
  because its `macos-26-arm64` image lacked the iOS 26.0 runtime required by
  Xcode 26.0.1. It signed and uploaded nothing. The isolated correction aligns
  both privileged workflows with the proven `macos-15` runner and adds an early
  fail-closed runtime check.
- Protected no-upload run
  [#34561820231](https://github.com/Frankbell84/KeyHollow/actions/runs/34561820231)
  proved the corrected runner, completed App Store Connect authentication and
  the unsigned archive, and then failed closed before signed export. The P12
  imported successfully with one signing leaf and its ordinary CA chain, but
  the workflow counted all three certificates as potential signers. The
  isolated correction selects one non-CA leaf while still requiring one valid
  code-signing identity, the pinned fingerprint, exact profiles, and all
  post-export checks. The failed run signed and uploaded nothing.
- Protected no-upload run
  [#34566854574](https://github.com/Frankbell84/KeyHollow/actions/runs/34566854574)
  passed all gates through signed export and validation of both code
  signatures. It then failed safely at the first of the two post-export leaf-
  certificate extraction commands because the optional
  `codesign --extract-certificates` output prefix was separated by a space
  instead of bound with `=`. The final exact-leaf comparisons therefore did not
  complete. Cleanup passed; the no-upload workflow could not publish, and
  nothing was uploaded or retained. The isolated correction changes only those
  two option bindings and adds exact-command regression coverage before another
  rehearsal.
- The first distribution is `KeyHollow Internal` only. Family expansion needs
  a separate decision after the Backup Verification device checks pass.

## External TestFlight gate

Do not invite external testers until:

- first-vault setup works on device;
- two or more independent passcodes demonstrably open different vaults;
- Copy and Move behavior has been verified with Apple Photos;
- no Face ID/Touch ID/device-passcode substitute path exists;
- background/app-switcher protection is verified;
- passcode rotation and vault deletion pass real-device testing;
- wrong-passcode throttling is tested;
- no plaintext media leakage is found in the app container;
- KDF performance is benchmarked on the oldest supported iPhone;
- all CI build/security tests are green.

## App Store release gate

Before marketing KeyHollow as a secure/privacy vault product, complete an independent security review of the KDF, key wrapping, vault discovery model, encrypted storage, lifecycle handling, and photo import/delete transaction behavior. Security marketing must accurately state limitations and must not promise absolute coercion, forensic, or compromised-device resistance.
