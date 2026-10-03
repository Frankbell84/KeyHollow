"""Import publication, original-deletion and session-ownership regression probes."""

import re


def import_violations(batch, gallery, executable, body):
    batch, gallery = executable(batch), executable(gallery)
    compact = lambda text: re.sub(r"\s+", "", text)
    errors = []
    for field in ("importedCount", "failedCount", "identifiersToDelete", "rootFallbackCount"):
        if f"private(set) var {field}" not in batch:
            errors.append(f"import batch lost private result ownership: {field}")
    if re.search(r"\b(?:VaultSession|VaultAccessCapability|VaultPhotoStore|VaultGeneralFileStore|"
                 r"VaultFolderPresentationStore|PhotoLibraryDeletionService|Data|URL)\b|"
                 r"Task\s*\{|Task\.detached|@escaping|@(State|Published)", batch):
        errors.append("import batch gained retained payload, task, session or store authority")
    operation = body(batch, "func importing(") or ""
    ordered = (
        "let item = try await encrypt()",
        "let placed = try await destination.place(item, move: move)",
        "try Task.checkCancellation()",
        "guard isCurrent() else { return nil }",
        "progress.importedCount += 1",
        "if !placed { progress.rootFallbackCount += 1 }",
        "if placed, progress.mode == .move, let identifier = sourceAssetIdentifier",
        "progress.identifiersToDelete.append(identifier)",
        "catch is CancellationError { return nil }",
        "catch { progress.failedCount += 1 }",
        "return progress",
    )
    remaining = compact(operation)
    for required in ordered:
        target = compact(required)
        index = remaining.find(target)
        if index < 0:
            errors.append(f"import verification/publication ordering lost: {required}")
            break
        remaining = remaining[index + len(target):]
    for required in ("mode == .move && importedCount > 0",
                     "identifiersToDelete.count == importedCount"):
        if compact(required) not in compact(batch):
            errors.append("original deletion eligibility changed")

    handler = body(gallery, "private func handleImportEvent(") or ""
    for kind, store_call in (("photo", "store.importPhoto("),
                             ("video", "generalFileStore.importFile(at: video.fileURL)")):
        start = handler.find(f"case .{kind}(let {kind}):")
        end = handler.find("case .", start + 1)
        route = handler[start:end]
        task = body(route, "await session.performSensitiveTask") or ""
        requirements = (
            "guard let progress = importProgress", "session.activeVaultID == capability.vaultID",
            "!Task.isCancelled", "let updated = await progress.importing(",
            f"sourceAssetIdentifier: {kind}.sourceAssetIdentifier", "destination: destination",
            store_call, "try await presentationStore.move(item, to: folderID)",
            "destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch)",
            "if let updated { importProgress = updated }",
        )
        if start < 0 or any(compact(x) not in compact(task) for x in requirements):
            errors.append(f"{kind} import must remain within its session task and captured destination")
    finished = handler[handler.find("case .finished:"):]
    if "await finishImport(progress)" not in (body(finished, "await session.performSensitiveTask") or ""):
        errors.append("import finalization escaped the session barrier")
    finish = body(gallery, "private func finishImport(") or ""
    guarded = body(finish, "if progress.shouldOfferOriginalDeletion") or ""
    deletion = body(guarded, "if progress.allImportedItemsAreDeletable") or ""
    if not all(x in deletion for x in ("session.beginSystemPhotoOperation()",
            "await PhotoLibraryDeletionService.deleteOriginals(", "progress.identifiersToDelete",
            "session.endSystemPhotoOperation()", "!Task.isCancelled, session.hasActiveAccess")):
        errors.append("original deletion lost batch eligibility or lifecycle guards")
    if "progress.completionMessage(moveResult: moveResult)" not in finish:
        errors.append("import results must use the batch presentation policy")
    if "importProgress = nil" not in (body(gallery, ".task(id: session.activeVaultID)") or ""):
        errors.append("vault change must discard the import snapshot")
    return errors


def import_probe_violations(sources, executable, body):
    batch = sources.get("UI/VaultGalleryImportBatch.swift", "")
    gallery = sources.get("Photos/VaultGalleryView.swift", "")
    check = lambda b, g: import_violations(b, g, executable, body)
    errors = check(batch, gallery)
    if errors:
        return errors
    for anchor in ("try Task.checkCancellation()", "guard isCurrent() else { return nil }",
                   "placed, progress.mode == .move", "catch is CancellationError",
                   "identifiersToDelete.count == importedCount", "private(set)"):
        if not check(batch.replace(anchor, "", 1), gallery):
            errors.append(f"import self-test accepted missing batch guard: {anchor}")
    for anchor in ("await session.performSensitiveTask", "if let updated { importProgress = updated }",
                   "session.activeVaultID == capability.vaultID",
                   "destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch)"):
        start = gallery.index("private func handleImportEvent(")
        end = gallery.index("private func finishImport(", start)
        part = gallery[start:end].replace(anchor, "")
        if not check(batch, gallery[:start] + part + gallery[end:]):
            errors.append(f"import self-test accepted missing composition guard: {anchor}")
    for anchor in ("if progress.shouldOfferOriginalDeletion", "if progress.allImportedItemsAreDeletable",
                   "await finishImport(progress)", "importProgress = nil"):
        if not check(batch, gallery.replace(anchor, "")):
            errors.append(f"import self-test accepted missing lifecycle guard: {anchor}")
    for forbidden in ("let payload: Data", "let session: VaultSession", "Task { }", "@escaping"):
        if not check(batch + "\n" + forbidden, gallery):
            errors.append(f"import self-test accepted forbidden authority: {forbidden}")
    return errors
