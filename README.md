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

Native iOS implementation is in active development. Build 52 from exact
protected `main` commit `0dfc5a1faa5fd0664ead1df1d7ed5b5a43f1498e` is the
accepted device-tested Internal baseline. It includes the accepted Vault
Catalog Search, Vault Catalog Sorting, Nested Folder Hierarchy, Files-style
nested move picker, and stable portrait-video playback session. Build 48 is
retained as rollback/comparison evidence, and Build 51 remains preserved as a
failed portrait-playback candidate. No Family, external TestFlight, or App
Store release is implied by this Internal acceptance.
