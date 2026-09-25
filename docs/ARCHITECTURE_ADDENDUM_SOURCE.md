# KeyHollow Architecture Addendum — recovered source

## Provenance

This is a text recovery of the user-supplied `KeyHollow_Architecture_Addendum.docx`,
attached on 2026-09-07 to **Continue KeyHollow iOS setup**
(task `01a0549d-0969-7f01-9063-52a344831373`, turn
`01a07bca-bb32-7342-a9ba-c78aca8008f3`). The source task remains on the N150.

Recovered on 2026-09-24 local time from the successful, untruncated document
extraction recorded in that task: 156 paragraphs and two tables. The original
Word file was not copied to Ryzen or re-opened; this is not a binary-verified
copy. Paragraph text and table cells below are preserved; Word styling is
represented as Markdown and extracted tables follow the paragraphs.

The user's accompanying request was to map every proposal against the current
codebase before implementation and to avoid a broad rewrite. These are
historical product proposals, not evidence that features exist or authorization
to implement, release, or change security behavior. Newer explicit user
decisions take precedence. Proposed engineering sequence and current status
belong in [the dependency plan](ROADMAP_DEPENDENCY_PLAN.md), not in this source.

## Recovered document

## KeyHollow Architecture Addendum

Supplemental Modules & Capability Expansion
EXTEND, DO NOT REBUILD

### 1. Purpose & Non-Disruption Directive

This is a supplemental design addendum to the existing KeyHollow application, architecture, codebase, feature set, and roadmap. It is NOT a complete specification of KeyHollow and must not be treated as a replacement architecture.

The existing foundational core remains authoritative. New capabilities should be layered into the current modular structure. Do not rewrite working modules merely to accommodate this document. For every item, first map it to the existing codebase and classify it as: (A) enhancement to an existing module, (B) new optional module, or (C) future module / forward-compatible provision.

### 2. Cross-Cutting Principles

- Encryption before transport: encrypted containers should leave KeyHollow already encrypted wherever the container model applies.

- Accounts enable services, not ownership: local vault use, import and export remain possible without an account. Accounts enable Direct Transfer, sync, device management, legacy services and similar server-assisted capabilities.

- Policy travels with the Hollow: an authenticated secure manifest carries KeyHollow-specific rules independently of the payload file's ordinary metadata.

- User control: users choose disclosure, devices, sync scope, backup destinations and optional policies.

- No silent destruction: conflicting versions are preserved and presented for resolution; deletion should support an appropriate recovery/grace mechanism.

- No hidden recovery backdoor: recovery methods are user-selected and must not secretly give KeyHollow plaintext access.

- Transparency: users can see material sync, backup, policy, verification and security state.

### 3. Hollow / Encrypted File Capability Matrix

- Create & encrypt

- View / decrypt when authorized

- Import

- Export / save

- Move / duplicate

- Edit permitted metadata

- Tag / categorize / organize

- Search

- Backup / restore

- Sync to selected trusted devices

- Version & conflict preservation

- Soft-delete / grace recovery

- Direct Transfer

- Advanced Transfer

- Apply access policies

- Seal / integrity verification

- Archive

- Legacy assignment

- Controlled communication thread

### 4. Secure Manifest & Programmable Policy

Do not depend on editable JPEG/PDF/etc. metadata to enforce KeyHollow behavior. Store policy in an authenticated manifest belonging to the encrypted Hollow/container. Compatible KeyHollow clients interpret and enforce that policy.

- Export allowed / View Only

- Available-from date/time

- Expiration date/time or duration

- Recipient/device binding where enabled

- Location policy where supported

- Protected View requirement

- Dynamic watermark requirement

- Transfer restrictions

- Integrity/seal data

- Policy version and audit identifiers

Policy governs KeyHollow behavior, not physics. Once content is legitimately displayed, another camera can reproduce it. Product claims must distinguish in-app enforcement from absolute copy prevention.

### 5. Controlled Access & Protected View

- View Only / No Export removes KeyHollow save, share and extraction paths while active.

- Time-limited viewing.

- Optional recipient/device binding.

- Dynamic forensic watermark rendered over protected content while it is visible.

- Watermark identifies the receiving account/device/session using KeyHollow-specific identifiers rather than exposing sensitive hardware identifiers.

- Respond to supported screen recording/mirroring state; obscure sensitive content when backgrounded/app-switcher snapshots are produced.

- Optional sender toggle: Private Environment Required.

#### Private Environment Required - Experimental

This may consider supported risk signals such as screen capture, mirroring/external displays and detectable nearby-device conditions. Nearby-device discovery must never be marketed as camera detection: Bluetooth/UWB/network observations cannot reliably establish that another phone is photographing the display. Treat this as optional friction/risk signaling, not a guarantee.

### 6. Direct Transfer - Core User Feature

Direct Transfer is KeyHollow-to-KeyHollow delivery for ordinary users and is separate from Advanced Transfer. Networking complexity should be hidden.

- Account required for KeyHollow-operated Direct Transfer services.

- Simple recipient/pairing experience; QR or pairing codes may be evaluated.

- Transfer preserves the authenticated Hollow policy.

- Receiving KeyHollow enforces compatible policies.

- Third-party export/import remains available without requiring an account.

### 7. Advanced Transfer - Power User Module

Advanced Transfer exposes reusable Secure Destinations rather than repeatedly asking for protocol details.

Do not include plain FTP. Add FTPS or SMB only if demonstrated demand justifies the maintenance/security surface. Advanced fields may include host, port, authentication, remote path/bucket, keys/tokens, certificate validation, timeout and overwrite behavior. Credentials belong in platform-secure credential storage.

### 8. Hollow Workspace - Future Major Upgrade

Hollow Workspace creates private content inside KeyHollow so it can enter the secure pipeline at creation rather than being created in ordinary storage first.

- Hollow Notes - first/easiest creator.

- Hollow Camera - capture directly into KeyHollow without saving to the normal photo reel unless explicitly exported.

- Hollow Scanner - document capture using the camera pipeline.

- Hollow Audio - secure recording.

- Hollow Video - later due to storage/processing complexity.

Browser and email are outside the first Workspace wave and are only long-range ecosystem possibilities.

### 9. Identity

- Hybrid identity model.

- No account required for core/offline ownership, import or export.

- Accounts provide services and continuity.

- Device-first trust: trusted devices act for the account identity.

- Account users can securely enroll/recover a new device.

- Privacy modes may include anonymous/private, connected and future organizational/enterprise modes.

- Sender controls identity disclosure, subject to security identifiers necessary for the selected service.

### 10. Sync, Backup & Archive

Sync, backup and archive are distinct concepts and remain distinct in architecture and UI.

- Conflicts: preserve both versions and ask; never silently overwrite.

- Deletion: soft delete / grace period where architecture permits.

- User chooses which Hollows sync to which trusted devices.

- Trusted devices are full-featured by default; account users may customize device roles/permissions.

- Backup framework: one engine, many destinations.

- Encrypted backup packages may be stored wherever the user chooses.

- Account services may add automated backup / KeyHollow-hosted storage without requiring plaintext access.

- Dedicated Backup & Sync Center: device, destination, status, history and recovery information.

- Never hide material data-state information from the user.

### 11. Search

- Search Hollow names and metadata.

- Search notes and permitted textual content.

- OCR-based document/image text search where enabled.

- Semantic/intelligent search may come later with privacy-preserving architecture.

- Global search requires elevated authentication.

- Search always respects access levels and locked-state boundaries.

- Two result modes: Standard may show snippets; Private shows titles/minimal information.

### 12. Recovery

Recovery is user-defined. KeyHollow supplies tools but maintains no hidden decryption backdoor.

- Recovery key

- Trusted-contact recovery

- Encrypted recovery package

- Future methods only if they preserve the no-backdoor principle

- All methods optional/user-selectable

### 13. Legacy Center

Legacy is a dedicated account-service module, not merely a recovery toggle. Rules may differ by Hollow/folder and recipient.

- Per-Hollow / per-folder legacy rules and access levels.

- Multiple designated recipients.

- Optional check-ins/activity awareness and configurable verification/heartbeat conditions.

- Prefer guided/multi-signal logic; absence alone must not be interpreted as death.

- Legacy conditions are completely separate from billing status.

- A valid legacy plan established while entitled is versioned and preserved if the subscription later lapses.

- Billing lapse never triggers a legacy event.

- Future entitlement rules may govern editing/monitoring after lapse, but established user wishes must not simply disappear.

### 14. Hollow Communication / Secure Threads

Communication remains tightly bound to a Hollow/transfer rather than becoming an open-ended social messenger. Default behavior is restrictive.

- Send Only - deliver Hollow, optionally with a note; no conversation.

- Request Response - recipient may respond in a controlled context.

- Secure Thread - explicitly enabled two-way conversation attached to the Hollow.

- Replies only when permitted by transfer/thread policy.

- Authorized participants only.

- Configurable retention / expiration.

- Protected attachments remain governed Hollows rather than loose files.

- Optional/minimal read receipts, typing indicators and activity signals.

- User-configurable notifications.

- Standalone general-purpose Messenger is a future possibility, not a commitment.

### 15. Organization & Intelligence - Future

- Hollow templates (identity, home, vehicle, records, etc.) with useful defaults.

- Timeline/lifecycle view for permitted creation, additions, sealing, transfers and related events.

- Relationships between Hollows and related records.

- Automation rules, reminders and scheduled actions.

- Optional intelligent categorization/recommendations only when consistent with the privacy model.

### 16. Integrity & Higher-Security Concepts

- Cryptographic tamper/integrity verification.

- Sealed Hollow: changes invalidate the seal. This proves integrity since sealing, not truth of the original content.

- Minimal/local security history or audit events where useful.

- Recipient-bound access as an optional higher-security tier.

- Policy profiles such as Standard, Protected and Maximum, with granular Advanced customization behind the simple interface.

### 17. Developer Integration Instructions

- Map every item to the current KeyHollow codebase/roadmap before implementation.

- Classify as existing-module enhancement, new module, or future provision.

- Prefer additive interfaces/shared engines over duplicate implementations.

- Preserve current behavior unless an approved requirement explicitly changes it.

- Keep encryption/container logic, policy enforcement, transport, UI, identity/account services and persistence modular enough to evolve independently.

- For future capabilities, make only the minimum forward-compatible provision required today.

- Threat-model security-sensitive features and validate them against current platform APIs before finalizing product/security claims.

### 18. Implementation Buckets

### 19. Product Through-Line

This addendum extends KeyHollow toward programmable privacy: encryption protects the content; the portable container keeps it protected outside the app; policy governs what compatible KeyHollow clients permit; transport determines how it moves; identity/device trust determines who participates; and transparent backup, recovery and legacy systems preserve user control.

Existing KeyHollow brand direction remains compatible with this expansion: “Anything private. Put it in a Hollow. Send it as a .lowkey.” This document does not independently rename or override any file-format decision already established in the active project.

### 20. Handoff Requirement

The implementation model/developer should first audit this addendum against the CURRENT project state. Return a mapping of: existing capability → affected module → proposed additive change → dependencies → risk → recommended implementation phase. Do not begin a broad rewrite from this document. Where this addendum conflicts with newer approved project decisions, flag the conflict rather than silently replacing the newer implementation.

### Recovered table 1

| Type | Priority | Purpose |
| --- | --- | --- |
| SFTP / SSH | Primary | Servers, VPS, NAS and SSH infrastructure |
| WebDAV / HTTPS | Primary / follow-on | Self-hosted and compatible remote storage |
| S3-compatible | Follow-on | Object storage / private or cloud buckets |
| Custom HTTPS endpoint | Expert / later | APIs, automation and custom receivers |

### Recovered table 2

| Bucket | Meaning | Examples |
| --- | --- | --- |
| Integrate / near-term | Layer onto existing app where appropriate | .khvault import/export/file association; manifest groundwork; Direct Transfer; metadata/search foundations; backup/sync architecture where already planned |
| New modular capability | Discrete module without destabilizing core | Advanced Transfer; Protected View; Backup & Sync Center; Legacy Center; Secure Threads |
| Future major upgrade | Architect for compatibility, don't force into current release | Hollow Workspace; richer automation/intelligence; broader communications; later destination protocols |
