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
- Enter the known correct vault passcode once and require the same vault to
  reopen without a generic wrong-passcode message, a second attempt, or an app
  relaunch.
- Repeat during photo import, gallery view, full-screen photo view, and active
  encrypted-video playback.

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

## Unified Media Navigation candidate

Run these checks only after the isolated feature branch has passed its automated
review gates and a separately authorized Internal TestFlight build is available.
Completing this written plan does not itself record a pass.

- In the vault root, open a Photos-origin image, a Files-origin image, and an
  encrypted video from several different grid positions. Confirm each viewer
  starts on the item that was tapped, presents the correct media type, and
  reports the correct title and one-based position in the compatible-media
  sequence.
- Swipe forward and backward through mixed portrait images, landscape images,
  screenshots, Files-origin images, and supported videos. Confirm every item
  preserves aspect ratio, transitions in visible-grid order, and never wraps at
  the first or last item.
- While a video is playing, drag its native timeline/scrubber horizontally.
  Confirm playback seeks without changing pages; then swipe in the upper video
  region and confirm normal page navigation still works.
- Place compatible media into two different folders. Open and navigate from the
  vault root and from each folder; confirm navigation never crosses between the
  root, either folder, or another hidden location.
- Tap a PDF and another unsupported non-media file. Confirm both continue to use
  the established file-management route and do not enter the swipe queue.
- Rapidly alternate forward and backward swipes while image and video content is
  loading. Confirm stale content never replaces the newest selection, playback
  does not overlap, controls remain responsive, and the viewer can always be
  dismissed.
- Move repeatedly between image and video pages, then dismiss, lock, background,
  and force-quit during loading and playback. Confirm the privacy shield appears,
  re-entry requires the LowKey, audio stops, and no prior media flashes after
  unlock.
- Save the active Photos-origin and Files-origin images from the viewer. Dismiss
  a supported video and confirm its established grid selection/context export
  route still works. Delete an active middle item and confirm the following
  compatible item becomes current; delete a final item and confirm the viewer
  dismisses safely. Confirm actions never target an adjacent item.
- Exercise corrupt or unreadable image/video fixtures and a low-storage video
  preparation failure. Confirm the failure is scoped to the active item, does
  not expose partial content, replaces the loading spinner with an actionable
  failure state, and leaves retry, dismissal, deletion, and adjacent navigation
  safe.
- Enable VoiceOver. Confirm it announces the active title, Image or Video kind,
  position such as "2 of 7," and usable Previous item and Next item controls;
  confirm unavailable boundary controls are reported as unavailable.
- Repeat the accepted mixed 26-item performance case. Scroll the gallery, open
  and dismiss media repeatedly, and swipe through at least seven consecutive
  items. Reject the candidate for new gallery lag, swipe hitching, runaway memory
  growth, a crash, missing thumbnails, or delayed cleanup symptoms.

## Vault Catalog Search candidate

Run these checks only after the isolated feature branch has passed its automated
review gates and a separately authorized Internal TestFlight build is available.
Search is limited to display names in the current visible location.

- At vault root, search for part of a root-level photo name, Files-origin image
  name, video name, document name, and folder name. Confirm only matching tiles
  remain, every result keeps its established thumbnail/icon and metadata layout,
  and clearing the query restores the exact accepted order without flicker.
- Enter a folder and repeat the mixed-media search. Confirm results come only
  from that folder, root items and other folders never appear, and moving back
  to root clears the query rather than applying a hidden stale filter.
- Search using different letter case, an unaccented spelling for a title with
  accents, and full-width characters for an ordinary-width title. Confirm the
  intended item matches. Enter two terms in reverse order and confirm both terms
  must be present; confirm a one-term near miss does not appear.
- Enter a query with no matches. Confirm the dedicated **No Results** state is
  shown, the vault is not described as empty, clearing remains available, and
  no item, folder, or count is changed.
- With a nonempty query, enter selection mode, choose individual results, then
  use **Select All**. Confirm the count and selection circles cover only visible
  filtered items. Export, move, and delete disposable selected fixtures and
  confirm no hidden nonmatching item is affected.
- From filtered results, open a Photos-origin image, Files-origin image, and
  supported video. Swipe forward and backward and confirm navigation contains
  only compatible matching media in visible order. Confirm PDFs and unsupported
  files still use the established file-management route.
- Search by a folder name, enter that folder, return to root, change vaults,
  lock, background, and force-quit. Confirm the query clears at each scope or
  security transition, the privacy shield and relock behavior are unchanged,
  and no previous-vault text or result flashes after unlock.
- Repeat the accepted mixed 26-item performance case while typing, clearing,
  scrolling, selecting, opening, and dismissing results. Reject the candidate
  for input lag, thumbnail churn, gallery hitching, increased open/swipe delay,
  a crash, or runaway memory growth.
- Re-run imports from Photos and Files, folder creation/moves, Backup
  Verification, image zoom/swipe, encrypted-video playback/fullscreen, and
  non-photo export. Confirm an active or recently cleared search does not alter
  those accepted paths.

## Vault Catalog Sorting candidate

Run these checks only after the isolated feature branch has passed its automated
review gates and a separately authorized Internal TestFlight build is available.
Sorting is limited to already-visible presentation metadata in the current
location.

- At vault root, confirm **Vault Order** exactly preserves the accepted baseline:
  folders by name and mixed items newest-first.
- Exercise **Newest First**, **Oldest First**, **Name A–Z**, and **Name Z–A**
  with root folders plus Photos-origin images, Files-origin images, videos, and
  documents. Confirm folders remain ahead of items and every tile keeps its
  established thumbnail/icon, title, size, and selection-circle alignment.
- Use titles that differ by case, accents, full-width characters, and embedded
  numbers such as `Item 2` and `Item 10`. Confirm name order is natural and
  stable without tiles jumping between recompositions.
- Enter a folder and repeat every order. Return to root and confirm the chosen
  presentation order remains active without changing folder membership.
- Apply a search under every order. Confirm clearing search restores the same
  chosen order, **Select All** includes only visible results, and no hidden item
  is exported, moved, or deleted.
- Open a filtered or sorted image/video and swipe in both directions. Confirm
  the media queue follows the visible order and never crosses the current
  folder boundary. Confirm PDFs and unsupported files retain the file route.
- Lock, background, switch vaults, and force-quit while sorted. Confirm no prior
  vault title flashes, no protected metadata is persisted by the sort policy,
  and a fresh launch returns safely to **Vault Order**.
- Repeat the accepted mixed 26-item performance case while changing order,
  searching, scrolling, selecting, opening media, importing, and dismissing.
  Reject the candidate for thumbnail churn, input lag, gallery hitching,
  increased open/swipe delay, a crash, or runaway memory growth.
- Re-run folder moves, Backup Verification, image zoom/swipe, encrypted-video
  playback/fullscreen, Photos and Files import progress, and non-photo export.
  Confirm catalog ordering does not alter any accepted path.

## Nested Folder Hierarchy candidate

Run these checks only after the isolated feature branch has passed its automated
review gates and a separately authorized Internal TestFlight build is available.
The hierarchy is presentation metadata; protected photo and file ciphertext
must not move when folders or items are reorganized.

- Open a Build 48 vault containing root folders, Photos-origin images,
  Files-origin images, videos, PDFs, and other files. Confirm every preexisting
  folder and item appears at root exactly as before without a conversion prompt,
  duplicate, missing tile, or changed thumbnail.
- Create a child folder, a grandchild, and a deeper path up to eight levels.
  Confirm each folder opens in place, **Back** goes to the immediate parent, and
  the breadcrumb can return directly to any ancestor or the vault root.
- Attempt to create a ninth level. Confirm KeyHollow rejects it with a clear
  bounded-depth message and the existing tree remains unchanged.
- Create the same folder name under two different parents and confirm both are
  allowed. Attempt the same case- or Unicode-equivalent name beside an existing
  sibling and confirm it is rejected without changing either branch.
- Use a folder tile's **Move Folder** action. Move it to root, into another
  branch, and back. Confirm invalid destinations—its current parent, itself, and
  every descendant—are unavailable, and the move never duplicates or loses a
  child folder or item.
- Place direct photos, files, and child folders in a disposable folder, then
  delete that folder. Confirm its direct items and child folders move to the
  deleted folder's parent in one result; no protected content is deleted.
  Repeat with a deliberate child-name collision and confirm deletion fails
  unchanged until the conflict is renamed or moved.
- In root and at multiple nested levels, exercise search, every sort order,
  individual selection, **Select All**, item move, export, delete, image zoom,
  image/video swipe, video fullscreen, and non-media opening. Confirm every
  operation remains limited to the current visible location and media never
  crosses a folder boundary.
- Lock, background, change vaults, force-quit, and relaunch from several nested
  levels and during folder creation, move, and deletion. Confirm the privacy
  shield and relock behavior are unchanged, no prior-vault path flashes, and a
  committed hierarchy reopens intact.
- As the historical Build 53 check, verify and restore a maintained catalog
  v1-v3 `.khvault` backup. Confirm verification states that this legacy archive
  does not preserve folders, restore places recovered content at root, and a
  `.khvault` file cannot be imported as ordinary content or treated as an active
  vault inside a vault. Test the separately authorized catalog-v4 follow-on
  under **Folder-aware portable backup v2** below.
- Repeat the accepted mixed 26-item performance case across several nested
  locations. Reject the candidate for new scroll lag, thumbnail churn, delayed
  folder opening, input lag, a crash, runaway memory growth, or data loss.

## Build 50 move picker and portrait-video fullscreen refinement

Run these checks only after the focused refinement has passed automated review
gates and a separately authorized Internal TestFlight build is available. This
phase changes presentation and player-controller lifecycle only; it must not
change hierarchy metadata, encrypted payloads, archive formats, or secure
cleanup behavior.

- At vault root, select one item and then several mixed image/file items. Tap
  `Move` and confirm a dedicated destination screen opens instead of a long
  pop-up menu. Require only immediate child-folder names at each level, with no
  repeated full paths or indistinguishable truncated rows.
- Drill through a branch at least three levels deep, use Back to return one
  level, and use `Cancel`. Confirm Cancel changes no membership. Repeat and use
  the explicit `Move Here` button; confirm exactly the selected items move once
  and the destination opens with the expected thumbnails, titles, and counts.
- From an item already inside a folder, confirm `Move Here` is unavailable for
  its current location but that location remains browsable when it contains a
  valid deeper destination. Confirm vault root is available when moving out of
  a folder and unavailable when the item is already at root.
- Create identical folder names under two different parents and an eight-level
  hierarchy. Navigate by local folder names and confirm every branch remains
  unambiguous. Move an item to the deepest valid location and confirm a ninth
  level remains prohibited by the established hierarchy policy.
- Use `Move Folder` on a disposable branch. Confirm the moving folder and all
  descendants are unavailable, while an otherwise unavailable intermediate
  folder remains browsable when it contains a valid destination. Move the
  branch to root, into another branch, and back; confirm no duplicate, missing
  child, cycle, depth overflow, or protected-content change.
- Play portrait `.mov` and `.mp4` fixtures. Enter and exit native fullscreen at
  least five times while paused and while playing. Reject any flash, black
  surface, unexpected dismissal, restart, zoom/crop error, duplicated audio, or
  need to reopen the video.
- While a portrait video is fullscreen, rotate portrait to landscape and back,
  seek, pause, and resume. Confirm the same player and playback time survive the
  transition and the inline surface returns correctly. Repeat with square and
  landscape videos to protect the accepted path.
- Exit fullscreen, swipe video to image to video, and dismiss normally. Repeat
  while locking, backgrounding, and force-quitting inline and fullscreen.
  Confirm audio stops, the privacy shield remains opaque, re-entry requires the
  expected authentication, and temporary protected playback files are cleaned
  only by the established terminal release boundary.
- Complete a core smoke pass covering search, every sort order, selection,
  image zoom/swipe, video swipe/fullscreen, Photos and Files imports, general-
  file export, folder deletion/reparenting, and Backup Verification. Reject any
  new thumbnail churn, scroll lag, incorrect folder mutation, crash, or
  plaintext-residue symptom.

## Build 51 portrait-video playback correction

Run these checks on the Build 51 Internal candidate. Build 50 demonstrated that
native fullscreen could retain AVKit's controls while losing its attached
player, producing a black surface and an inert Play button. Reject Build 51 if
that state occurs even once.

- Open both portrait `.mov` and `.mp4` fixtures. While paused, enter native
  fullscreen, wait for the transition to settle, press Play, and confirm video
  appears and playback time advances. Repeat while the video is already
  playing and require uninterrupted picture, sound, and time continuity.
- Perform at least five enter/exit cycles per fixture. In fullscreen, pause,
  resume, seek forward and backward, rotate portrait to landscape and back,
  and use the native controls after every transition. Confirm the same player
  remains responsive and the inline surface restores at the same playback time.
- Repeat with square and landscape fixtures, then swipe video to image to video.
  Confirm the accepted media-navigation behavior, zoom, chrome, and native
  playback controls do not regress.
- Lock and unlock, background and foreground, dismiss normally, and force-quit
  from both inline and fullscreen playback. Confirm privacy shielding and
  authentication remain intact, audio stops when expected, and protected
  temporary playback files are removed only through the established owner-
  release boundary.

## Build 52 stable portrait playback session (failed candidate)

These checks governed the stable-session repair packaged as Build 52. Build 51
was already a failed candidate: retaining the player during representable
dismantle was not enough because playback ownership still followed a transient
SwiftUI task and an embedded child controller still initiated fullscreen. The
same rejection standard remains useful evidence: a blank player, inert Play
control, duplicate modal, automatic reopen loop, or protected-file cleanup race
is a failure if it occurs even once.

Build 52 resolved the blank-player path but later failed acceptance because
backgrounding during encrypted-video playback could leave a correct passcode
unable to reopen the vault until relaunch. Preserve the checks below as prior
evidence; they do not constitute Build 52 acceptance.

- Open portrait `.mov` and `.mp4` fixtures from the gallery. Confirm KeyHollow
  presents one native full-screen AVKit player after the viewer-root transition
  settles. Pause before pressing Play, wait several seconds, then press Play;
  picture, audio, controls, and playback time must all respond normally.
- Use AVKit **Done**. Confirm it returns to the same selected video page and a
  clear `Play Full Screen` control, without dismissing the outer image/video
  pager and without automatically reopening AVKit. Press the explicit control
  and require the same playback session to reopen normally.
- Repeat the open, pause, Done, and explicit-reopen cycle at least ten times on
  each portrait fixture. Include rapid but valid taps after each completed
  transition. Require one modal at a time, no skipped response, no black or
  blank surface, no inert control, and no duplicated audio.
- While playing, seek forward and backward, rotate portrait to landscape and
  back, pause, resume, use Done, and reopen. Repeat with square and landscape
  fixtures to protect the accepted paths.
- After Done, swipe video to image to video in both directions and use image
  zoom. Confirm the outer pager preserves the selected item, thumbnails and
  adjacent media remain stable, and returning to a video gives one explicit
  playback route rather than a stale AVKit surface.
- Dismiss the outer viewer while AVKit is open and while its presentation or
  dismissal animation is settling. Repeat while locking, backgrounding,
  changing vaults, and triggering session replacement. Confirm new presentation
  is rejected immediately, audio pauses, and the UI never resurrects the player.
- After each terminal path, confirm privacy shielding and reauthentication are
  unchanged. Exercise a disposable video through repeated open/dismiss cycles
  and confirm the protected temporary export is retained while replay remains
  available, then removed only after AVKit and its player item are fully
  detached. Confirm external playback and Picture in Picture remain unavailable.
- During playback and while paused, check Control Center and the lock screen;
  KeyHollow's protected media must not publish a Now Playing card or remote
  controls. Long-press a paused frame and confirm iOS does not expose visual
  lookup, subject lifting, or copy/analyze affordances.

## Build 53 background-video unlock regression

Run these checks on the next unused Internal build after the bounded lifecycle
repair and its automated missing-callback, session-barrier, correct-passcode,
and plaintext-cleanup tests pass. Reject Build 53 if any cycle requires a second
passcode attempt, a delay beyond normal unlock work, force-quit, or relaunch.

- Open encrypted portrait `.mov` and `.mp4` fixtures, enter native fullscreen,
  start playback, and confirm picture, audio, controls, and playback time are
  advancing. Send KeyHollow fully to the background, wait for the app-switcher
  state to settle, then return.
- Require the opaque privacy shield during transition and the locked keypad on
  return. Enter the known correct KeyHollow passcode exactly once. It must open
  the same vault normally without `Passcode not recognized`, a secure-operation
  retry message, a second attempt, or an app relaunch.
- Repeat at least ten cycles across active playback, paused playback, full-screen
  entry, AVKit **Done**, explicit replay, and presentation/dismissal transitions.
  Include portrait, square, and landscape video fixtures.
- After every cycle, require audio to stop on background, no player or modal to
  resurrect, the prior vault contents to remain intact, and the video to reopen
  through one fresh playback route. In a development build, also confirm the
  retired player has no item and the protected temporary export is removed.
- Enter one deliberate wrong passcode, observe only the generic failure state,
  then enter the correct passcode once. The genuine failure must not poison or
  mislabel the following successful unlock.

## Folder-aware portable backup v2

Run these checks only after the feature branch's automated archive, bridge,
module-boundary, and rollback tests pass. Use disposable vaults and maintained
fixtures. Complete the primary round trip between two physical iPhones.

- On device A, create root-level photos and general files plus an eight-level
  folder branch, empty folders, the same folder name under two different
  parents, and mixed photo/general-file memberships at several levels. Record
  exact hierarchy, membership, root placement, item readability, and source
  archive-independent SHA-256 values where available.
- Export the vault and require catalog v4, exactly one authenticated
  `folderManifest`, the expected folder and membership counts, and no source
  folder, membership, item, LowKey, or session change. Confirm a source with no
  folders or memberships may instead produce catalog v3.
- Inspect only with the approved development tooling. Confirm the public
  `.khvault` header, container, content-chunk framing, and payload prefix remain
  version 1; `folders/manifest.khm` is named only inside the encrypted catalog,
  and no plaintext folder name, membership, item identifier, or Folder
  Presentation thumbnail cache is visible.
- Verify the v4 archive without installing it. Require exact authenticated
  folder and membership counts, and confirm the report exposes no folder name,
  folder/item identifier, path, vault key, recovery code, manifest plaintext,
  staging handle, or installation capability. The source archive and all local
  vaults must remain unchanged after repeated verification and cancellation.
- Transfer the archive to device B through the supported Files flow, enter the
  recovery code, choose a new noncolliding LowKey, and restore. Require a fresh
  destination vault identifier, the exact recorded hierarchy and memberships,
  all root items still at root, empty folders intact, and every photo/general
  file readable. Recalculate representative content hashes where practical.
- Confirm no archived Folder Presentation thumbnail cache was installed.
  Browse the restored hierarchy and require thumbnails to regenerate normally
  without missing items, changed hierarchy, plaintext residue, or persistent
  growth proportional to a second cache copy.
- Restore maintained catalog v1, v2, and v3 fixtures. Require their verification
  reports to disclose the compatibility limitation and every recovered item to
  appear at vault root. Never infer folders from filenames or other metadata.
- Using disposable tamper copies, alter, remove, duplicate, misname, truncate,
  or oversize the v4 folder manifest and exercise invalid hierarchy, dangling,
  duplicate, wrong-kind, and unarchived membership fixtures. Each must fail
  closed before a report or LowKey prompt and leave no installed or partial
  vault. Do not create ad hoc “legacy” fixtures on device.
- Reject a LowKey that already resolves to an existing vault and then choose a
  valid LowKey. Confirm the first rejection does not consume the validated
  restore and neither attempt changes the existing vault.
- With development fault injection, force termination before and after each
  photo-root, supplemental-root, folder-root, credential-publication, and
  journal-removal boundary. Relaunch after every stop. Require startup recovery
  to converge to either one complete new vault or no new vault, with no partial
  `GeneralFileData/<vault-UUID>` or
  `FolderPresentationData/<vault-UUID>`, no stale matching credential/journal,
  and no deletion or mutation of any preexisting vault.
- Repeat cancellation, background, lock, insufficient-space, and force-quit
  cases during protected ingress, authentication, extraction, folder
  validation, and precommit LowKey entry. Confirm protected staging is removed
  on terminal paths, a rejected LowKey remains retryable, privacy shielding is
  opaque, and the next clean import succeeds.

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
- Confirm the report's photo count, general-file count, authenticated folder
  count, authenticated membership count, source creation date, payload-catalog
  version, and compatibility limitations match the selected archive. The
  selected backup filename may appear; confirm the report does not display a
  LowKey, recovery code, vault key, archived-item filenames, folder names,
  folder/item identifiers, paths, manifest plaintext, or item contents.
- For catalog v4, confirm the report says authenticated hierarchy and item
  placement are preserved. For catalog v1-v3, confirm it says folder names and
  memberships were not archived and a restore places recovered content at
  vault root. A folderless current export may legitimately report catalog v3.
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
- Choose a valid `.khvault` from Files and confirm the selection advances into
  protected staging instead of being reported as a canceled file selection.
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
- Cover a photo-only archive, a general-file-only archive, a mixed archive, an
  archive containing a video imported as a general file, and a catalog-v4
  archive with nested and empty folders plus mixed memberships. Use maintained
  v1, v2, and v3 fixtures to confirm their limitations are reported accurately;
  do not fabricate replacement fixtures on the device.
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

## Build 43 viewer and gallery refinement

- Select several photos in the system picker and tap **Add**. Require immediate
  haptic confirmation, a visible "Encrypting N of M" progress bar that advances
  after each protected write, a responsive cancel-free processing state, and a
  clear completion response. Repeat with one item and the 50-item selection
  limit.
- Play a supported encrypted video inline, enter and exit native fullscreen at
  least five times, rotate while fullscreen, seek, pause, resume, and then
  dismiss normally. Reject any stopped playback, black surface, duplicated
  audio, cleanup alert, or need to reopen the video.
- Confirm the media viewer fully covers the gallery presentation, video-control
  taps do not reveal KeyHollow's action header, and AVKit's fullscreen control
  remains unobstructed in portrait and landscape.
- Open portrait, landscape, screenshot, Files-origin image, and video items.
  Confirm the action header overlays rather than resizes media, disappears
  after three seconds, returns on tap and after a swipe, and that no permanent
  arrow footer remains. Confirm VoiceOver Previous/Next and adjustable actions
  still navigate without wrapping.
- With more than 96 mixed items, slowly scroll from top to bottom and back,
  then repeat quickly. Once a visible thumbnail appears, it must remain visible
  until its tile leaves the viewport. Reject placeholder flicker, already-
  loaded thumbnails disappearing, stalled visible tiles, runaway memory, or
  scrolling worse than the accepted Build 42 baseline.
- Lock, background, switch vaults, and dismiss during picker processing,
  thumbnail loading, image viewing, inline video, and fullscreen video. Confirm
  the privacy shield, session revocation, player/image release, temporary-file
  cleanup, and relock behavior remain unchanged.

## Integrated video viewer regression

- Open portrait and landscape MOV/MP4 videos from the gallery. Confirm one
  viewer opens, with native playback controls directly on the video and no
  enlarged thumbnail followed by a second player presentation. Play, pause,
  seek, and swipe sideways through video/image/video without stacked screens.
- Rotate to landscape. Done must remain visible above the video controls and
  return to the gallery. Start a downward swipe in the middle of the video
  (away from the top edge and bottom scrubber) and confirm it also closes.
  A short, canceled, sideways, or upward swipe must not close the viewer.
- Screen-edge Control Center/notification gestures remain owned by iOS. Open
  and dismiss Control Center, then confirm playback, Done and a content swipe
  still work. Scrubbing must neither close nor change the selected item.
- If using AVKit's optional fullscreen control, test native close and canceled
  dismissal as well. Repeat background/first-correct-passcode unlock while
  embedded, fullscreen, opening, switching pages, and closing. Reject lingering
  audio, stale frames, black/inert controls, or a blocked unlock.
- Repeat with VoiceOver using Done; reopen the same video after each close.

## Previous portrait-video dismissal regression

- On the replacement for Build 54, open a portrait MOV and MP4 and confirm
  fullscreen playback shows AVKit's close control when the controls are
  revealed by a tap. Close without rotating the phone or leaving the app.
- Swipe down on the video to dismiss and confirm playback stops and the gallery
  returns, with no "Play Full Screen" button, poster-only screen, or second
  dismissal required. Reopen from the gallery and repeat native close and
  swipe-down five times in portrait and landscape, including with
  controls hidden. Seek and horizontal gestures must not accidentally close.
- Start a downward dismissal and cancel it; confirm the player remains usable
  and can still close or resume. Background during a dismissal, return, and
  unlock with the first correct passcode. Confirm no black/inert player,
  lingering audio, stale video frame, or blocked unlock.
- Confirm the outer viewer closes with playback and ordinary gallery
  navigation and protected temporary-file cleanup still work. Repeat with
  VoiceOver using the native close control.

## Backup/container inspection

- Confirm KeyHollow encrypted storage directories/files carry complete file protection.
- Confirm protected vault data is excluded from ordinary backup as designed.
- Inspect the app container in a development environment and verify no plaintext photos, thumbnails, passcodes, keys, sensitive filenames, or manifest contents are persistently stored.
- For a catalog-v4 fixture, confirm the installed folder manifest remains
  authenticated ciphertext under `FolderPresentationData/<vault-UUID>`, no
  exported Folder Presentation thumbnail cache exists, and no folder name or
  membership appears in the public archive header, filesystem logs, previews,
  or verification report.

## Release gate

External TestFlight distribution should not begin until all critical items above pass or have a documented accepted risk. App Store security claims require the separate independent security review described in `SECURITY_ARCHITECTURE.md`.


## Current-folder import candidate

On the Internal candidate, open a nested disposable folder and use + to Copy
one photo and one video from Photos, then import a PDF and an image from Files.
All four must appear in that folder, open correctly, stay out of Vault Root,
and retain their folder after lock/unlock. Repeat a root import and a sibling
folder import; neither may change the earlier assignments. Verify an empty
folder shows the import button, picker cancellation adds nothing, and duplicate
folder names under different parents receive only the selected destination.
Use disposable Photos items for Move; source deletion must be requested only
after verified import and successful placement. Export/verify/restore the test
vault and confirm the new memberships survive. Background/lock during a batch
must retain already encrypted content and prevent stale picker results from
entering a later session. If placement fails, check the root-recovery message,
recoverable encrypted root copies, and preserved originals.
