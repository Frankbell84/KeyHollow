# KeyHollow

KeyHollow is a native iOS privacy application built around multiple independent encrypted vaults for photos and general files. A valid passcode opens only the vault associated with that passcode; the normal locked interface does not enumerate other vaults.

## Product principle

**One keypad. Multiple private vaults.**

## Security-first V1

- Native Swift / SwiftUI
- Local-only encrypted photo and general-file storage
- Independent cryptographic key material per vault
- Authenticated encryption for stored content, metadata, and thumbnails
- iOS Keychain and Data Protection where appropriate
- Automatic lock when the app leaves the foreground
- No Face ID, Touch ID, or Apple device-passcode fallback for vault unlock
- No cloud backend in V1
- No analytics or advertising SDKs in the secure application path
- No plaintext vault index exposed by the UI
- Copy-to-vault and verified move-to-vault import modes
- Unified three-column gallery with encrypted folder organization
- Reference-restricted playback and bounded encrypted thumbnails for in-limit videos
- Read-only local verification of portable encrypted vault backups without installation
- Unified image/video swipe navigation with bounded active-payload loading
- Current-location vault catalog search and stable presentation-only sorting
- No claims of absolute coercion or forensic resistance

## Engineering rule

KeyHollow is a security product first. Cryptographic design, key derivation, secure storage, import/export behavior, caches, thumbnails, backups, logging, and lifecycle handling must be threat-modeled before release. Production security claims require independent review.

## Status

Build 59 is the Rename candidate in [PR #96](https://github.com/Frankbell84/KeyHollow/pull/96).
Its final checks and delivery evidence are recorded there. It is not yet
device-accepted; the delivered baseline remains Build 58 below.

Build 58 was delivered from `36b63e06fae92615fc5b24988ef123355f8b4bf0`.
The user reported successful current-folder imports and a one-iPhone encrypted
backup/verify/restore test. It was assigned to both existing TestFlight
groups, KeyHollow Internal and Family, at the user's explicit request.
[PR #94](https://github.com/Frankbell84/KeyHollow/pull/94) records the exact build,
CI, delivery, distribution, and scoped acceptance evidence. Two-device transfer
and the extended device failure matrix remain unverified. Build 53 remains the
recorded accepted rollback; no App Store release is implied.

See [WORK_STATUS.md](WORK_STATUS.md) for the current resume point. The
[dependency and compatibility plan](docs/ROADMAP_DEPENDENCY_PLAN.md) maps the
user's [Architecture Addendum](docs/ARCHITECTURE_ADDENDUM_SOURCE.md) to the
current implementation and proposes small testable stages. It is a planning
document, not a claim that the proposed capabilities already exist.
