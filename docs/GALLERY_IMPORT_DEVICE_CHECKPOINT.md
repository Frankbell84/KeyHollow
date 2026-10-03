# Gallery import batch checkpoint — Build 61

Build 60 was accepted by the owner on 2026-10-03. This next Internal candidate
isolates Photos-origin photo/video import accounting and original-deletion
eligibility. It preserves behavior; gallery decomposition remains unfinished.
Files import, bulk operations and media lifetime coordination are unchanged.

The app and thumbnail extension both specify 61. Before packaging, App Store
Connect's iOS Builds and all-status Build Uploads showed 60 latest with no 61
on 2026-10-03. The protected workflow repeats this check before uploading.
Exact CI, signing, upload and Internal availability belong in this stage's PR.
Build 60 remains the accepted checkpoint until the owner reports device results.

## Device check

Install **1.0 (61)** through TestFlight over the existing app. Keep the existing
vault and encrypted backup. Use small disposable photos/videos for these checks;
do not use irreplaceable originals when testing Move.

1. **Copy into a folder:** Create a temporary folder and copy a small mixed
   selection of a photo and a video from Photos. Both must appear in that folder,
   open normally, and remain in Apple Photos. Repeat at Vault Root.
2. **Move and decline deletion:** Move disposable photo/video items into a folder.
   Decline the iOS original-deletion prompt. The encrypted items must remain
   usable and the result should explain that originals were kept as copies.
3. **Move and allow deletion:** For a separate disposable selection, allow the
   iOS deletion prompt. Confirm the encrypted copies open and stay in their
   chosen location. Do not empty Recently Deleted during this check.
4. **Cancel and lock:** Cancel the picker without importing, then import again.
   Background the app, return and unlock. Check for stuck busy indicators and
   confirm imported items, names and locations remain correct.
5. **Gallery smoke check:** Scroll, search, open images/videos, use Done and the
   content-area downward swipe, and import a test file from Files into a folder.

If a system permission or unavailable Photos original prevents a step, report
what happened rather than changing permissions solely to complete the list.
Folder disappearance, placement failure, missing source IDs and cancellation at
the operation boundary have automated coverage; no destructive vault setup is
needed to simulate these on the phone.

Report crashes, missing/misplaced items, removed originals after declining the
prompt, unexpected messages, stuck progress or unlock trouble. Passing this
checkpoint accepts this import-policy extraction, not the deferred two-phone
transfer/failure matrix or completion of the full gallery split.
