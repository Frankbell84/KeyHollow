"""Bulk save/delete policy and authenticated composition regression probes."""

import re


SAVE_PATH = "UI/VaultGalleryPhotoSaveBatch.swift"
DELETE_PATH = "UI/VaultGalleryDeletionBatch.swift"
GALLERY_PATH = "Photos/VaultGalleryView.swift"


def bulk_violations(sources, executable, body):
    save, delete, gallery = (executable(sources.get(path, ""))
                             for path in (SAVE_PATH, DELETE_PATH, GALLERY_PATH))
    compact = lambda text: re.sub(r"\s+", "", text)
    errors = []

    def require(code, values, label):
        for value in values:
            if compact(value) not in compact(code):
                errors.append(f"{label}: missing {value}")

    def ordered(code, values, label):
        remaining = compact(code)
        for value in values:
            index = remaining.find(compact(value))
            if index < 0:
                errors.append(f"{label}: ordering lost at {value}")
                break
            remaining = remaining[index + len(compact(value)):]

    for code in (save, delete):
        if re.search(r"\b(?:VaultSession|VaultAccessCapability|VaultPhotoStore|"
                     r"VaultGeneralFileStore|VaultFolderPresentationStore|FileManager|"
                     r"PhotoLibrarySaveService|Data|URL)\b|Task\s*\{|Task\.detached|"
                     r"@escaping|@(State|Published|Observable)", code):
            errors.append("bulk policy gained payload, task, session or store authority")
    require(save, (
        "@MainActor enum VaultGalleryPhotoSaveBatch",
        "let message: String", "let clearSelection: Bool",
        "save: @MainActor (VaultPhotoRecord) async throws -> PhotoLibrarySaveResult",
    ), "photo-save value boundary")
    save_operation = body(save, "static func perform(") or ""
    ordered(save_operation, (
        "for photo in photos {", "guard !Task.isCancelled else { return nil }",
        "switch try await save(photo)", "case .saved:", "savedCount += 1",
        "case .permissionDenied:", "permissionDenied = true", "case .failed:",
        "failedCount += 1", "catch { failedCount += 1 }", "if permissionDenied { break }",
        "guard !Task.isCancelled else { return nil }", "if permissionDenied {",
        "clearSelection: false", "else if savedCount > 0", "clearSelection: true",
        "clearSelection: false",
    ), "sequential photo-save cancellation/result policy")
    require(delete, (
        "@MainActor struct VaultGalleryDeletionBatch", "private let deletedCount: Int",
        "private let failedCount: Int", "deletePhotos: @MainActor () async throws -> Bool",
        "deleteFiles: @MainActor () async throws -> Bool",
    ), "deletion value boundary")
    ordered(body(delete, "static func perform(") or "", (
        "let photos = try await deleting(count: photoCount, using: deletePhotos)",
        "let files = try await deleting(count: fileCount, using: deleteFiles)",
        "deletedCount: photos.deletedCount + files.deletedCount",
        "failedCount: photos.failedCount + files.failedCount", "catch { return nil }",
    ), "typed deletion group order")
    ordered(body(delete, "private static func deleting(") or "", (
        "guard count > 0 else { return Self(deletedCount: 0, failedCount: 0) }",
        "if try await operation()", "return Self(deletedCount: count, failedCount: 0)",
        "catch is CancellationError { throw CancellationError() }", "catch {",
        "return Self(deletedCount: 0, failedCount: count)",
    ), "deletion cancellation and ordinary failure policy")

    save_handler = body(gallery, "private func savePhotos(") or ""
    require(save_handler, ("guard let store, !photos.isEmpty, !isWorking else { return }",
                           "isWorking = true"), "photo-save admission")
    save_task = body(save_handler, "session.startSensitiveTask") or ""
    ordered(save_task, (
        "session.beginSystemPhotoOperation()",
        "defer { session.endSystemPhotoOperation() isWorking = false }",
        "let completion = await VaultGalleryPhotoSaveBatch.perform(photos)",
        "let decryptedPhoto = try await store.loadPhoto(photo)",
        "return await PhotoLibrarySaveService.savePhoto(decryptedPhoto)",
        "guard let completion else { return }", "message = completion.message",
        "if completion.clearSelection { leaveSelectionMode() }",
    ), "registered photo-save payload/handoff lifetime")
    delete_handler = body(gallery, "private func deleteSelectedItems(") or ""
    require(delete_handler, (
        "let photos = selectedPhotoRecords", "let files = selectedGeneralFileRecords",
        "guard !photos.isEmpty || !files.isEmpty, !isWorking else { return }",
        "isWorking = true",
    ), "selected deletion admission")
    delete_task = body(delete_handler, "session.startSensitiveTask") or ""
    ordered(delete_task, (
        "defer { isWorking = false }",
        "guard let completion = await VaultGalleryDeletionBatch.perform(",
        "photoCount: photos.count", "fileCount: files.count",
        "deletePhotos: { guard let store else { return false }",
        "try await store.delete(photos)", "return true",
        "deleteFiles: { guard let generalFileStore else { return false }",
        "try await generalFileStore.delete(files)", "return true", ") else { return }",
        "if let store { try? await reload(using: store) }",
        "if let generalFileStore {",
        "generalFileRecords = (try? await generalFileStore.loadManifest().files) ?? generalFileRecords",
        "await reconcilePresentationStore()", "guard !Task.isCancelled else { return }",
        "leaveSelectionMode()", "message = completion.message",
    ), "registered deletion and refresh/selection ordering")
    return errors


def bulk_probe_violations(sources, executable, body):
    errors = bulk_violations(sources, executable, body)
    if errors:
        return errors
    mutations = {
        SAVE_PATH: (
            "@MainActor", "let clearSelection: Bool",
            "guard !Task.isCancelled else { return nil }",
            "if permissionDenied { break }", "catch {\n                failedCount += 1\n            }",
            "clearSelection: false", "clearSelection: true",
        ),
        DELETE_PATH: (
            "@MainActor", "private let deletedCount: Int", "private let failedCount: Int",
            "guard count > 0 else { return Self(deletedCount: 0, failedCount: 0) }",
            "throw CancellationError()", "failedCount: photos.failedCount + files.failedCount",
        ),
        GALLERY_PATH: (
            "VaultGalleryPhotoSaveBatch.perform(photos)",
            "return await PhotoLibrarySaveService.savePhoto(decryptedPhoto)",
            "if completion.clearSelection { leaveSelectionMode() }",
            "VaultGalleryDeletionBatch.perform(", "photoCount: photos.count",
            "fileCount: files.count", "try await store.delete(photos)",
            "try await generalFileStore.delete(files)",
        ),
    }
    for path, anchors in mutations.items():
        for anchor in anchors:
            if anchor not in sources[path]:
                errors.append(f"bulk probe missing mutation anchor: {anchor}")
            elif not bulk_violations({**sources, path: sources[path].replace(anchor, "", 1)}, executable, body):
                errors.append(f"bulk probe accepted missing protection: {anchor}")
    # Scope repeated lifecycle operations to these handlers, not another task.
    gallery = sources[GALLERY_PATH]
    for marker, next_marker in (
        ("private func savePhotos(", "private func deleteSelectedItems("),
        ("private func deleteSelectedItems(", "private func selectionItem("),
    ):
        start = gallery.index(marker)
        end = gallery.index(next_marker, start)
        handler = gallery[start:end]
        anchors = ["session.startSensitiveTask", "isWorking = false"]
        if "savePhotos" in marker:
            anchors += ["session.beginSystemPhotoOperation()", "session.endSystemPhotoOperation()"]
        else:
            anchors += ["await reconcilePresentationStore()", "guard !Task.isCancelled else { return }"]
        for anchor in anchors:
            mutated = gallery[:start] + handler.replace(anchor, "", 1) + gallery[end:]
            if mutated == gallery:
                errors.append(f"bulk probe did not mutate lifecycle anchor: {anchor}")
            if not bulk_violations({**sources, GALLERY_PATH: mutated}, executable, body):
                errors.append(f"bulk probe accepted missing lifecycle protection: {anchor}")
    # Removing only the final save guard must still be rejected after late success.
    save = sources[SAVE_PATH]
    index = save.rfind("guard !Task.isCancelled else { return nil }")
    late = save[:index] + save[index:].replace("guard !Task.isCancelled else { return nil }", "", 1)
    if not bulk_violations({**sources, SAVE_PATH: late}, executable, body):
        errors.append("bulk probe accepted late save publication after cancellation")
    for path in (SAVE_PATH, DELETE_PATH):
        for authority in ("let data: Data", "let store: VaultPhotoStore", "let task = Task {}"):
            if not bulk_violations({**sources, path: sources[path] + "\n" + authority}, executable, body):
                errors.append(f"bulk probe accepted new authority: {authority}")
    return errors
