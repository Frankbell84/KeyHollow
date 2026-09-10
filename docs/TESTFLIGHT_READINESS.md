# KeyHollow TestFlight Readiness

## Already prepared in source

- Native iOS target: KeyHollow
- Bundle identifier: `com.keyhollow.app`
- Minimum iOS version: 17.0
- Version: 1.0; latest accepted internal binary is Build 39
- Reproducible XcodeGen project generation with a pinned XcodeGen release and
  pinned Xcode 26.0.1 release toolchain
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
   app and thumbnail extension. **Complete for internal delivery.**
5. App Store Connect record for KeyHollow (Apple ID `6807022780`). **Complete.**
6. App Store Connect API access and upload key for the cloud release workflow.
   **Complete for internal delivery.**

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
3. Explicitly authorize the full 40-character commit and unused build number.
4. Dispatch `Upload KeyHollow to TestFlight` from that exact `main` commit.
5. Require approval in the protected `production-testflight` environment before
   signing secrets are exposed.
6. Verify App Store Connect processing and assignment only to the authorized
   internal group.
7. Complete `DEVICE_TEST_PLAN.md` on the TestFlight-delivered binary. Any
   failure returns to a new pull request and a new exact-commit validation.

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
