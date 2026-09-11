# Unified Media Navigation

Unified Media Navigation is the next approved roadmap add-on after Encrypted
Video Support and Backup Verification Center. It provides one swipeable viewer
for compatible media in the currently visible vault location while preserving
the existing management route for PDFs and other non-media files.

This phase extends the accepted Build 40 architecture. It does not rebuild the
gallery, change encrypted storage, migrate vault data, or revise the
`.khvault` format.

## Current-code mapping

| Existing capability | Current owner | Additive change | Dependency | Risk |
| --- | --- | --- | --- | --- |
| Source-neutral, deterministically ordered gallery items | `KeyHollowGalleryUI` plus app composition | Map the current visible snapshot into immutable media-navigation descriptors | Typed photo and general-file identifiers | Low |
| Photos-origin and Files-origin image preview | `KeyHollowSecurePreviewAddOn` plus app-owned loading | Reuse the existing bounded image preparation path for the active page only | Active unlocked-session task | Moderate lifecycle risk |
| Encrypted video playback | `KeyHollowEncryptedVideoAddOn` plus `VaultVideoPlaybackCoordinator` | Reuse the existing local-only player and require prior player/plaintext release before page replacement | Existing protected export lifetime | Moderate lifecycle risk |
| Folder-scoped gallery | `KeyHollowFolderPresentationAddOn` plus app composition | Build each navigation queue from the current root or current folder snapshot only | Existing folder membership metadata | Low |
| PDFs and other unsupported files | Existing file-management route | Leave routing unchanged and exclude these records from the swipe queue | Existing type policies | Low |
| Navigation presentation and paging rules | New `KeyHollowMediaNavigationAddOn` | Own immutable descriptors, typed selection, boundaries, position text, accessibility, and swipe presentation | SwiftUI only; no protected store dependency | Low |

## Module boundary

`KeyHollowMediaNavigationAddOn` may receive only immutable typed identifiers,
media kind, display title, an opaque builder for the active presentation
surface, and navigation action closures. It does not receive or retain that
surface's protected payload. It must not receive a vault key, session,
encrypted record, store,
ciphertext, plaintext bytes, file URL, transfer capability, folder store, or
archive parser.

The app composition layer remains responsible for mapping records, authenticating
and decrypting the selected item, starting and canceling sensitive tasks,
serializing image/video transitions, saving, deleting, and lifecycle cleanup.
Protected core modules never import the add-on.

## Loading and cleanup rules

- Open on the tapped media item in the current visible-grid order.
- Keep navigation inside the current root or folder snapshot.
- Load only the active full-resolution payload. Adjacent pages may use existing
  bounded encrypted-thumbnail results but never eagerly decrypt originals.
- A page change invalidates the prior generation before new work starts.
- Image tasks are canceled and the UIKit image surface must acknowledge that it
  cleared its image reference before a new full payload is published.
- Video transitions await AVPlayer release and deletion of the prepared
  plaintext export before preparing the next full payload.
- Rapid swipes may finish background work, but stale generations can never
  publish over the newest selection.
- Save and delete operations temporarily disable dismissal and page navigation;
  lifecycle cancellation invalidates their generation and observes registered
  sensitive-task cleanup.
- Dismissal, locking, backgrounding, vault replacement, and session revocation
  cancel work and release image, player, file, and task lifetimes.

## Deliberate exclusions

This phase does not add document paging, PDF rendering, metadata editing,
search, sort controls, nested folders, import-progress UI, cross-vault
references, account services, or any Architecture Addendum service module.
Those remain separately reviewed work. Search remains the first low-risk
catalog refinement after this approved navigation phase.

## Acceptance criteria

1. A tapped Photos-origin image, Files-origin image, or supported encrypted
   video opens at the correct position in the current visible order.
2. Horizontal swipes move among compatible media without wrapping at the first
   or last item.
3. PDFs and other non-media files keep the existing file-management behavior.
4. Photo and file records with the same UUID remain distinct.
5. No navigation crosses from a folder into the vault root or another folder.
6. Exactly one active full plaintext payload is retained at a time, with an
   explicit image-surface or video-player release acknowledgement before
   replacement.
7. Image-to-video and video-to-image transitions complete prior cleanup before
   publishing the next full payload.
8. Rapid swipes, corrupt media, deletion, dismissal, lock, backgrounding, vault
   switching, and session replacement fail closed and leave the user able to
   exit the viewer.
9. Save and delete actions target the currently displayed item. Deleting the
   final item dismisses; otherwise selection advances safely.
10. VoiceOver announces the title, media kind, position, and navigation
    controls.
11. Existing vaults and `.khvault` archives remain byte-format compatible.
12. The compiled-module, simulator, lifecycle/security, CodeQL, exact-main,
    signing-preflight, and physical-device gates in
    `docs/ADDON_RELEASE_POLICY.md` all pass before distribution expands.

## Device validation focus

Use the existing mixed 26-item performance case, including Photos-origin
images, Files-origin images, portrait and landscape media, encrypted videos,
and non-media files. Exercise rapid forward/back swiping, repeated open and
dismiss, save/delete on the active page, lock/background during image and video
loading, low-storage video preparation, folder boundaries, and corrupt-media
failure. Confirm gallery scrolling and thumbnail responsiveness remain at the
accepted Build 40 level.
