# Gallery Files import checkpoint — Build 62

Build 61 was accepted by the owner on 2026-10-03. This Internal candidate
isolates Files import placement and completion policy while preserving behavior.
The encrypted importer, Photos policy, bulk operations and media lifetime are
unchanged. Gallery decomposition is still in progress.

The app and thumbnail extension both specify 62. Before packaging, App Store
Connect's iOS Builds and all-status Build Uploads showed 61 latest with no 62
on 2026-10-03. The protected workflow repeats the check before upload. Exact
CI, signing, upload and Internal availability belong in this stage's PR.
Build 61 remains accepted until the owner reports this device check's results.

## Device check

Install **1.0 (62)** through TestFlight over the existing app. Keep the existing
vault and encrypted backup. Use small disposable files already in Files.

1. **Import into a folder:** Open a temporary vault folder and import a small
   PDF, text file, image and video from Files. Confirm each appears in that
   folder, opens normally and remains available in Files. Repeat a small import
   at Vault Root and check that the items stay there.
2. **Progress and results:** Import a few files together. Confirm the progress
   finishes, the message reports the expected count and the gallery refreshes.
   If convenient, include an unsupported disposable item such as a vault backup;
   supported files should still import and the result should explain omissions.
   Do not create oversized or executable files solely for this check.
3. **Cancel and unlock:** Open the Files picker and cancel it, then import again.
   Background the app, return and unlock. Check for stuck busy indicators,
   missing items, wrong-folder placement or stale completion messages.
4. **Gallery smoke check:** Search and scroll; open an image and video, check
   portrait/landscape Done and the content-area downward swipe. Copy a small
   photo from Photos into the temporary folder and confirm its original remains.

Folder disappearance, placement failure and cancellation at the operation
boundary have automated coverage; no destructive vault setup is needed to
simulate these on the phone. Report unavailable Files-provider items or system
permission issues as observed rather than altering permissions to finish a step.

Report crashes, missing/misplaced items, removed originals, unexpected messages,
stuck progress or unlock trouble. Passing accepts this Files policy extraction;
it does not complete the gallery split or the deferred two-phone matrix.
