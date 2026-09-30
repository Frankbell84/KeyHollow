# Gallery refactor device checkpoint — Build 60

This candidate brings the accumulated gallery refactor to a physical iPhone
before further changes to imports, bulk operations and media lifetime
coordination. It does not claim that the whole gallery split is finished.
The owner authorized implementation, validation, merges and Internal delivery
through this test point on 2026-09-30.

## Scope

Since accepted Build 59, six focused stages separated catalog/location values,
thumbnail processing and caching, image-page presentation, gallery controls,
folder interactions/commands and the full-screen media viewer's layout.
The composition file falls from 3,270 to 2,119 lines. Existing oversized files
have frozen, decreasing ceilings; new first-party source defaults to 500 lines.
No new size exception, feature, archive format or storage schema is included.

The accepted source remains Build 59 at
`030172bb8750ccadb19b2cee6d922812d6278295` until the owner reports device results.
Build 60 is an Internal-only candidate. PR #106 records final source and delivery
evidence; do not substitute a pre-packaging CI run for the final candidate or
the exact merged-main run required by the protected release workflow.

## Before testing

Install the new build through TestFlight once it is available to KeyHollow
Internal. Confirm **1.0 (60)**. Install over the existing app; do not delete it
or erase the current vault. Use a small set of disposable test items and keep
the existing encrypted backup. Copy is sufficient for this checkpoint's import
test; removing originals from Apple Photos is not necessary.

## Device checks

1. **Video close:** Open portrait and landscape videos. Close with Done and a
   downward swipe from the content area, then reopen. Confirm there is no extra
   fullscreen thumbnail or Play Full Screen prompt and the swipe does not
   accidentally open the phone's Control Center.
2. **Images and lock:** Open images, swipe between them, zoom and return to
   normal size, save one copy to Photos and close. Background the app with
   media open, return and unlock normally. Repeat with a video playing.
3. **Catalog and thumbnails:** Scroll a populated gallery quickly, search,
   change sorting and clear the search. Thumbnails must stay with the correct
   items, including when returning from a folder or media viewer.
4. **Folders and selection:** Create and rename a disposable test folder.
   Move photo-only, file-only and mixed selections into it, back to root and
   into another folder. Cancel some dialogs. Delete only an empty disposable
   test folder. Confirm the content stays in its expected location.
5. **Existing operations:** Copy a test photo and import a test file into a
   folder, rename an item, export a file and dismiss the share sheet. Lock and
   reopen the app. Confirm folders, names and contents remain correct.

Report crashes, missing or misplaced content, wrong thumbnails, stuck busy
indicators, failed dismissal or unlock problems. A failure returns to a focused
fix and a newly verified test candidate. Passing this checkpoint accepts these
accumulated refactors, not the deferred two-phone transfer/failure matrix or a
new feature. Further gallery decomposition remains ahead of feature expansion.

## Delivery record

App Store Connect's iOS Builds and all-status Build Uploads lists showed 59
latest with no 60 on 2026-09-30 before changing both product build numbers.
The live upload guard must repeat that check; this observation is not a reserved
build number. Final CI, signing, upload and Internal availability belong in
[PR #106](https://github.com/Frankbell84/KeyHollow/pull/106).
