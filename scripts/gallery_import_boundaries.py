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


def file_import_violations(owner, gallery, executable, body):
    owner, gallery = executable(owner), executable(gallery)
    compact = lambda text: re.sub(r"\s+", "", text)
    errors = []
    if "@MainActor\nenum VaultGalleryFileImport" not in owner or "importFiles: @MainActor (" not in owner:
        errors.append("Files import policy must remain a stateless main-actor owner")
    if re.search(r"\b(?:VaultSession|VaultAccessCapability|VaultPhotoStore|VaultGeneralFileStore|"
                 r"VaultFolderPresentationStore|FileManager|Data|URL)\b|"
                 r"Task\s*\{|Task\.detached|@escaping|@(State|Published|Observable)", owner):
        errors.append("Files import policy gained retained payload, task, session or store authority")
    operation = body(owner, "static func perform(") or ""
    ordered = (
        "var rootFallbackCount = 0", "let outcome = try await importFiles(",
        "let placed = try await destination.place(",
        "VaultPresentedContentReference(kind: .generalFile, id: record.id)",
        "move: move", "if !placed { rootFallbackCount += 1 }", "{ progressDidChange($0) }",
        "guard !Task.isCancelled, isCurrent() else { return nil }", "await reload()",
        "return GeneralFileImportPresentation.message(for: outcome)",
        "+ VaultImportDestination.recoveryMessage(rootCount: rootFallbackCount)",
        "catch is CancellationError { return nil }", "catch { return",
    )
    remaining = compact(operation)
    for required in ordered:
        target = compact(required)
        index = remaining.find(target)
        if index < 0:
            errors.append(f"Files import ordering or result guard lost: {required}")
            break
        remaining = remaining[index + len(target):]

    handler = body(gallery, "private func importGeneralFiles(") or ""
    for required in (
        "guard case .success(let urls) = result, !urls.isEmpty else { return }",
        "guard urls.count <= VaultGeneralFileStore.maximumBatchCount else",
        "guard let generalFileStore, let presentationStore, let destination = importDestination,",
        "destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch), !isWorking else { return }",
        "isWorking = true",
        "if taskID == nil { generalFileImportProgress = nil isWorking = false }",
    ):
        if compact(required) not in compact(handler):
            errors.append(f"Files import composition guard lost: {required}")
    task = body(handler, "session.startSensitiveTask") or ""
    for required in (
        "defer { generalFileImportProgress = nil isWorking = false }",
        "let resultMessage = await VaultGalleryFileImport.perform(",
        "destination: destination", "importFiles: { recordDidImport, progressDidChange in",
        "try await GeneralFileImportCoordinator.importFiles(",
        "at: urls, using: generalFileStore", "recordDidImport: recordDidImport",
        "progressDidChange: progressDidChange", "try await presentationStore.move(item, to: folderID)",
        "progressDidChange: { progress in generalFileImportProgress = progress }",
        "isCurrent: { destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch) }",
        "reload: { await reloadGeneralFiles() }", "if let resultMessage { message = resultMessage }",
    ):
        if compact(required) not in compact(task):
            errors.append(f"Files import escaped its registered task or callback wiring: {required}")
    if "rootFallbackCount" in handler or "GeneralFileImportPresentation.message" in handler:
        errors.append("Files import policy was duplicated in composition")
    if "session.endSystemInteraction() importGeneralFiles(result)" not in re.sub(r"\s+", " ", gallery):
        errors.append("Files picker must end its system handoff before starting import")
    return errors


def file_import_probe_violations(sources, executable, body):
    owner = sources.get("UI/VaultGalleryFileImport.swift", "")
    gallery = sources.get("Photos/VaultGalleryView.swift", "")
    check = lambda o, g: file_import_violations(o, g, executable, body)
    errors = check(owner, gallery)
    if errors:
        return errors
    for anchor in ("importFiles: @MainActor", "!Task.isCancelled,", "isCurrent()",
                   "await reload()", "catch is CancellationError",
                   "if !placed { rootFallbackCount += 1 }", "kind: .generalFile",
                   "move: move", "{ progressDidChange($0) }", "return nil"):
        if not check(owner.replace(anchor, "", 1), gallery):
            errors.append(f"Files import self-test accepted missing policy guard: {anchor}")
    start = gallery.index("private func importGeneralFiles(")
    end = gallery.index("private func reload(using", start)
    for anchor in ("!urls.isEmpty", "urls.count <= VaultGeneralFileStore.maximumBatchCount",
                   "!isWorking", "session.startSensitiveTask", "if taskID == nil",
                   "generalFileImportProgress = nil", "isWorking = false",
                   "recordDidImport: recordDidImport", "progressDidChange: progressDidChange",
                   "destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch)",
                   "reload: { await reloadGeneralFiles() }", "if let resultMessage"):
        part = gallery[start:end].replace(anchor, "")
        if not check(owner, gallery[:start] + part + gallery[end:]):
            errors.append(f"Files import self-test accepted missing composition guard: {anchor}")
    for forbidden in ("let source: URL", "let store: VaultGeneralFileStore",
                      "let session: VaultSession", "Task { }", "@escaping"):
        if not check(owner + "\n" + forbidden, gallery):
            errors.append(f"Files import self-test accepted forbidden authority: {forbidden}")
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
