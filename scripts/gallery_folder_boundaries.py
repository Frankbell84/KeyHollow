"""Ownership and session-task probes for the extracted gallery folder flow."""

import re


MUTATION_CALLS = (
    "presentationStore.renameFolder(id: folderID, to: name)",
    "presentationStore.createFolder(named: name, in: parentID)",
    "presentationStore.moveFolder(id: id, to: parentID)",
    "presentationStore.move(item, to: folderID)",
    "presentationStore.move(items, to: folderID)",
    "presentationStore.deleteFolder(id: id)",
)
COMPOSITION_ROUTES = {
    "saveFolderName": "folderActions.nameMutation(parentID: activeFolderID)",
    "moveFolder": "VaultGalleryFolderMutation.moveFolder(id: folder.id, parentID: parentID)",
    "move": "VaultGalleryFolderMutation.moveItem(item, folderID: folderID)",
    "moveSelectedItems": "VaultGalleryFolderMutation.moveSelection(items, folderID: folderID)",
    "deleteFolder": "VaultGalleryFolderMutation.deleteFolder(id: folder.id)",
}


def folder_violations(actions, mutation, gallery, executable, body):
    errors = []
    actions = executable(actions)
    mutation = executable(mutation)
    gallery = executable(gallery)
    compact = lambda text: re.sub(r"\s+", "", text)
    for field in ("folderBeingRenamed", "isEditorPresented", "pendingDeletion", "moveRequest"):
        if not re.search(r"private(?:\(set\))?\s+var\s+" + field + r"\b", actions):
            errors.append(f"folder interaction must keep private ownership of {field}")
    if re.search(r"\b(?:Task|async|VaultSession|VaultAccessCapability)\b", actions):
        errors.append("folder dialog state gained task/session authority")
    if re.search(r"\b(?:Task|VaultSession|VaultAccessCapability)\b|@(State|Published)", mutation):
        errors.append("folder metadata adapter gained task/session/state authority")
    for call in MUTATION_CALLS:
        if compact(call) not in compact(mutation):
            errors.append(f"folder adapter lost existing store dispatch: {call}")
    if "return try await presentationStore.loadManifest()" not in mutation:
        errors.append("folder mutations must return the store's refreshed manifest")

    for method, route in COMPOSITION_ROUTES.items():
        operation = body(gallery, f"private func {method}(") or ""
        task = body(operation, "session.startSensitiveTask") or ""
        if compact(route) not in compact(operation):
            errors.append(f"folder composition lost captured route: {method}")
        required = (
            "defer { isWorking = false }",
            "folderManifest = try await mutation.perform(using: presentationStore)",
            "catch is CancellationError { return }",
            "message = mutation.failureMessage(for: error)",
        )
        if any(compact(value) not in compact(task) for value in required):
            errors.append(f"{method}: mutation/refresh/cancellation must stay inside the session task")
        if not ("!isWorking" in operation and "isWorking = true" in operation
                and "if taskID == nil { isWorking = false }" in operation):
            errors.append(f"{method}: busy and refused-task handling changed")
    for anchor in (".task(id: session.activeVaultID)", ".onChange(of: session.securityEpoch)"):
        if "folderActions.reset()" not in (body(gallery, anchor) or ""):
            errors.append(f"folder dialogs must reset with {anchor}")
    return errors


def folder_probe_violations(sources, executable, body):
    actions = sources.get("UI/VaultGalleryFolderActions.swift", "")
    mutation = sources.get("UI/VaultGalleryFolderMutation.swift", "")
    gallery = sources.get("Photos/VaultGalleryView.swift", "")
    errors = folder_violations(actions, mutation, gallery, executable, body)
    if errors:
        return errors
    for call in (*MUTATION_CALLS, "return try await presentationStore.loadManifest()"):
        changed = mutation.replace(call, "", 1)
        if not folder_violations(actions, changed, gallery, executable, body):
            errors.append(f"folder self-test accepted missing dispatch: {call}")
    for method, route in COMPOSITION_ROUTES.items():
        start = gallery.index(f"private func {method}(")
        end = gallery.find("private func ", start + 1)
        part = gallery[start:end]
        for anchor in (route, "session.startSensitiveTask", "catch is CancellationError",
                       "if taskID == nil { isWorking = false }"):
            changed = gallery[:start] + part.replace(anchor, "", 1) + gallery[end:]
            if changed == gallery or not folder_violations(actions, mutation, changed, executable, body):
                errors.append(f"folder self-test accepted {method} without {anchor}")
    for field in ("folderBeingRenamed", "isEditorPresented", "pendingDeletion", "moveRequest"):
        changed = re.sub(r"private(?:\(set\))? var " + field, "var " + field, actions)
        if not folder_violations(changed, mutation, gallery, executable, body):
            errors.append(f"folder self-test accepted writable {field}")
    if not folder_violations(actions, mutation, gallery.replace("folderActions.reset()", ""), executable, body):
        errors.append("folder self-test accepted missing lifecycle reset")
    return errors
