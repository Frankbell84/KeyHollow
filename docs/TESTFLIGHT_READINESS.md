# KeyHollow TestFlight Readiness

## Already prepared in source

- Native iOS target: KeyHollow
- Bundle identifier: `com.keyhollow.app`
- Minimum iOS version: 17.0
- Version: 1.0; latest accepted internal binary is Build 40
- Build 40 was produced from exact `main` commit
  `54bd2d6887f3ca0e476339fce05e90dd59ba963f`, processed and validated by App
  Store Connect, assigned only to `KeyHollow Internal`, and successfully
  installed and device-tested by Frank.
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
   app and thumbnail extension. **Complete. Replacement certificate
   `4RU4X6GAGU`, its exportable P12, and both exact profiles passed protected
   preflight, Build 40 upload, post-export verification, and the final post-
   cutover preflight. Legacy certificate `2P45VCTJVL` is revoked.**
5. App Store Connect record for KeyHollow (Apple ID `6807022780`). **Complete.**
6. App Store Connect API access and upload key for the cloud release workflow.
   **Complete. Replacement key `W3UF745JN4` is installed in the protected
   environment and passed authentication after cutover. Legacy key
   `JD6P6X8C9A` is revoked.**

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
10. Retain prior credentials until the replacement-signed build processes,
    installs, launches, and passes device testing. Build 40 completed this
    sequence; legacy certificate `2P45VCTJVL` was revoked first and legacy API
    key `JD6P6X8C9A` was revoked last.

## Build 40 acceptance evidence

- PR [#56](https://github.com/Frankbell84/KeyHollow/pull/56) merged the exact
  reviewed head `426768238433017ea11773220c3f61378d3f7cd3` as exact `main`
  commit `54bd2d6887f3ca0e476339fce05e90dd59ba963f`. PR CI run
  [#34569439188](https://github.com/Frankbell84/KeyHollow/actions/runs/34569439188)
  and merged-main CI run
  [#34595760793](https://github.com/Frankbell84/KeyHollow/actions/runs/34595760793)
  passed all required checks.
- Protected preflight
  [#34598236304](https://github.com/Frankbell84/KeyHollow/actions/runs/34598236304)
  first passed end to end. After all eight repository-scoped production-secret
  copies were removed, preflight
  [#34600941660](https://github.com/Frankbell84/KeyHollow/actions/runs/34600941660)
  proved environment-only operation.
- Protected upload
  [#34602241254](https://github.com/Frankbell84/KeyHollow/actions/runs/34602241254)
  completed with Apple's `UPLOAD SUCCEEDED` result. App Store Connect reports
  Build 40 as validated and assigned only to `KeyHollow Internal`; no Family or
  external assignment was made.
- Frank installed and device-tested Build 40 successfully, including the Backup
  Verification flow.
- Legacy certificate `2P45VCTJVL` and legacy API key `JD6P6X8C9A` were revoked
  after device acceptance. Replacement certificate `4RU4X6GAGU` and key
  `W3UF745JN4` remain active.
- Final post-cutover preflight
  [#34610956286](https://github.com/Frankbell84/KeyHollow/actions/runs/34610956286)
  passed all 25 steps, including App Store Connect authentication, exact source,
  protected-environment policy, architecture and privacy gates, replacement-
  only signing, signed-IPA inspection, and cleanup. It uploaded or retained
  nothing.
- The legacy-signed Build 39 binary is not a dependable rollback after
  certificate revocation. Rollback now means producing a new higher-numbered
  build from an approved source revision using the protected replacement
  credentials.

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
