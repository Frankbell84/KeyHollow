# Build 63: bulk operation device checkpoint

This refactor preserves the existing save/delete behavior. Use disposable
copies for deletion checks. Build 62 is the accepted rollback checkpoint.

1. In a folder containing photos and a file, select two photos and save to
   Photos. Confirm both arrive in iPhone Photos, the encrypted vault copies
   remain, the completion count is correct and selection closes.
2. Select a disposable photo and file together. Cancel the deletion confirmation
   first and verify both remain. Confirm deletion on a second attempt: only the
   selected items should disappear, the folder count should refresh, and
   unselected items should still open.
3. Repeat a single-item save/delete at the root and in a folder. Switch between
   root/folder and search views afterward; no stale selection should remain.
4. If Photos permission is denied, saving should show the existing Settings
   explanation, keep selection and leave vault copies intact. Restore permission
   before checking a successful save. This does not require deleting originals.
5. Background/lock during a larger save, unlock and verify no stale completion
   appears and ordinary gallery actions still work. A photo already handed to
   iOS may finish saving; this checkpoint does not promise rollback of that save.
6. Smoke-test Files import/export and portrait/landscape media close. These
   lifetimes are unchanged and must remain functional.

Automated tests cover injected store failures and cancellation that cannot be
reliably forced on an iPhone. Device acceptance does not establish the deferred
two-phone transfer/failure matrix or authorize wider distribution.
