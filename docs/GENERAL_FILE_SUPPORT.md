# General File Support Add-on

General File Support is an independently compiled, local-only KeyHollow add-on.
It expands a vault beyond photos without changing the existing photo manifest,
photo blobs, credential envelopes, or outer `.khvault` version-one container
decoder.

## First release scope

- Import up to 50 regular files per selection from Apple's Files interface.
- Open the Files picker directly from the vault's primary import menu; the
  capability is not hidden inside security or overflow settings.
- Import the selected files immediately after Apple's picker closes, then
  refresh the same unified three-column Vault grid used by photos. There is no
  KeyHollow staging, review, or second confirmation screen.
- Canceling Apple's picker leaves the vault unchanged. `Vault Files` remains
  an alternate file-management path, not an intermediate import destination;
  the unified gallery also supports mixed selection, export, and deletion.
- Future metadata editing is intentionally decoupled from import and deferred
  to a post-import Vault Security/settings surface.
- Accept common documents, PDFs, audio, archives, text, and other data files.
- Encrypt the file bytes and authenticated metadata before committing the item
  to the add-on manifest.
- Show the authenticated display name, type, and size after unlock.
- Compose authenticated general-file records into the primary Vault screen so a
  file-only vault never appears empty; the photo and general-file manifests
  remain independently stored and compiled behind the presentation layer.
- Present photos and general files in one consistent square-tile grid with
  names and sizes. Files-origin images use encrypted thumbnails and the same
  secure image preview as photo imports; non-image files retain a type icon and
  open the dedicated file manager for file-specific actions.
- Select one or many files, export authenticated copies through the system share
  interface, or permanently delete their encrypted vault copies.
- Keep every source file unchanged during import.

The first release intentionally excludes packages, executable formats,
`.khvault` backups, empty files, and individual files larger than 100 MB.
Existing in-limit video files remain ordinary general-file records. The
separately compiled Encrypted Video add-on supplies bounded thumbnails and
playback without changing those records or the transfer format. Streaming
large-file encryption remains a later, separately reviewed storage design.

## Security and architecture boundaries

- Implementation lives in `KeyHollow/AddOns/GeneralFileSupport` and compiles as
  `KeyHollowGeneralFileSupportAddOn`.
- The add-on receives authenticated seal/open operations through
  `VaultGeneralFileCryptographicAccess`; it never receives or retains a vault
  key.
- The add-on owns the complete bounded batch-import operation. Each selected
  security-scoped URL is copied, encrypted, verified, and committed before the
  next item is processed; the UI receives only aggregate success/failure counts.
- The app session derives domain-separated keys and retains synchronous
  revocation ownership.
- Incoming files are copied from security-scoped URLs into protected temporary
  storage before encryption. The protected copy is removed after import.
- Blob names are random. File names, content types, sizes, and timestamps exist
  only inside the encrypted manifest.
- Exports are authenticated and written to protected temporary storage inside
  the session capability's revocation fence. Revocation waits for an in-flight
  bounded write, so no plaintext write can finish after access is revoked.
  Preparation failure or cancellation removes its partial export; a successful
  temporary export remains only for its explicit consumer and is removed when
  that consumer finishes.
- Interrupted import and export staging is purged the next time the encrypted
  file store opens, covering app termination before normal cleanup completes.
- Vault deletion invokes an injected add-on cleanup boundary after credential
  destruction, without making the protected vault core import the add-on.

## Transfer compatibility

The outer `.khvault` container, public header, and payload framing remain
version one. The authenticated inner payload catalog reader accepts legacy
photo-only catalog version one archives, while current exports emit catalog
version two. Catalog
version two adds a validated supplemental manifest and encrypted blob entries
for general files without changing existing photo records or the outer archive
decoder. Mixed photo/file exports and restores therefore preserve general
files, and legacy photo-only archives remain readable by current builds.
Catalog-version-two exports are not readable by older builds that recognize
only catalog version one.

The add-on remains subject to the independent gates in
`ADDON_RELEASE_POLICY.md`; the current implementation is merged and recorded
as complete and hardened.
