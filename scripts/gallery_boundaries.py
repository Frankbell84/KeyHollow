"""Checks for gallery responsibilities extracted from the composition view."""

import re
import runpy


OWNERS = {
    "VaultGalleryContentItem": "Photos/VaultGalleryContentSnapshot.swift",
    "VaultGalleryOpenRoute": "Photos/VaultGalleryContentSnapshot.swift",
    "VaultGalleryContentSnapshot": "Photos/VaultGalleryContentSnapshot.swift",
    "VaultGalleryLocationSnapshot": "Photos/VaultGalleryLocationSnapshot.swift",
    "VaultGeneralFileThumbnailPipelineHooks": "Photos/VaultGeneralFileThumbnailPipeline.swift",
    "VaultGeneralFileThumbnailPipeline": "Photos/VaultGeneralFileThumbnailPipeline.swift",
    "VaultMediaImagePage": "Photos/VaultMediaImagePage.swift",
    "VaultGalleryHeaderControls": "Photos/VaultGalleryHeaderControls.swift",
    "VaultGallerySearchControls": "Photos/VaultGallerySearchControls.swift",
    "VaultGallerySelectionControls": "Photos/VaultGallerySelectionControls.swift",
    "VaultGalleryThumbnailCache": "UI/VaultGalleryThumbnailCache.swift",
    "VaultGalleryFolderActions": "UI/VaultGalleryFolderActions.swift",
    "VaultGalleryMoveRequest": "UI/VaultGalleryFolderActions.swift",
    "VaultGalleryMoveTarget": "UI/VaultGalleryFolderActions.swift",
    "VaultGalleryFolderMutation": "UI/VaultGalleryFolderMutation.swift",
}
IMPORTS = {
    "UI/VaultGalleryFolderActions.swift": {
        "Foundation", "KeyHollowFolderPresentationAddOn", "KeyHollowGalleryUI",
        "KeyHollowNestedFolderAddOn",
    },
    "UI/VaultGalleryFolderMutation.swift": {"Foundation", "KeyHollowFolderPresentationAddOn"},
    "UI/VaultGalleryThumbnailCache.swift": {"UIKit", "KeyHollowGalleryUI"},
    "Photos/VaultGalleryHeaderControls.swift": {"SwiftUI"},
    "Photos/VaultGallerySearchControls.swift": {"SwiftUI", "KeyHollowCatalogSearchAddOn"},
    "Photos/VaultGallerySelectionControls.swift": {"SwiftUI", "KeyHollowGalleryUI"},
    "Photos/VaultGalleryLocationSnapshot.swift": {
        "Foundation", "KeyHollowCatalogSearchAddOn", "KeyHollowFolderPresentationAddOn",
        "KeyHollowGalleryUI", "KeyHollowGeneralFileSupportAddOn",
        "KeyHollowNestedFolderAddOn", "KeyHollowPhotoCore",
    },
    "Photos/VaultGalleryContentSnapshot.swift": {
        "Foundation", "KeyHollowCatalogSearchAddOn", "KeyHollowEncryptedVideoAddOn",
        "KeyHollowGalleryUI", "KeyHollowGeneralFileSupportAddOn",
        "KeyHollowMediaNavigationAddOn", "KeyHollowPhotoCore", "KeyHollowSecurePreviewAddOn",
    },
    "Photos/VaultGeneralFileThumbnailPipeline.swift": {
        "Foundation", "KeyHollowEncryptedVideoAddOn", "KeyHollowFolderPresentationAddOn",
        "KeyHollowGeneralFileSupportAddOn", "KeyHollowSecurePreviewAddOn",
    },
    "Photos/VaultMediaImagePage.swift": {
        "SwiftUI", "UIKit", "KeyHollowMediaNavigationAddOn", "KeyHollowSecurePreviewAddOn",
    },
}


def ownership_violations(sources, executable, imports):
    violations = []
    code = {path: executable(source) for path, source in sources.items()}
    for name, owner in OWNERS.items():
        definitions = [path for path, text in code.items()
                       if re.search(rf"\b(?:struct|enum|actor|class|extension)\s+{name}\b", text)]
        if definitions != [owner]:
            violations.append(f"{name}: must remain owned only by {owner}; found {definitions}")
    for owner, allowed in IMPORTS.items():
        if imports(sources.get(owner, "")) != allowed:
            violations.append(f"{owner}: reviewed imports changed")
        text = code.get(owner, "")
        forbidden = ["VaultSession", "VaultAccessCapability", "URLSession", "SymmetricKey", "VaultUnlockService"]
        if owner != "Photos/VaultGeneralFileThumbnailPipeline.swift":
            forbidden += ["VaultPhotoStore", "VaultGeneralFileStore", "FileManager"]
            if owner != "UI/VaultGalleryFolderMutation.swift":
                forbidden.append("VaultFolderPresentationStore")
        if re.search(r"\b(?:" + "|".join(forbidden) + r")\b", text):
            violations.append(f"{owner}: extracted responsibility gained protected storage/session/network authority")
        if re.search(r"\b(?:public|open)\s+(?:struct|class|actor|enum|func|var|let)\b", text):
            violations.append(f"{owner}: app-only extraction must not widen the public API")
    return violations


def gallery_ownership_violations(root, executable, imports, body):
    sources = {path.relative_to(root).as_posix(): path.read_text(encoding="utf-8")
               for path in sorted(root.rglob("*.swift"))}
    violations = ownership_violations(sources, executable, imports)
    # Probe the same executable-source scanner used by the production checker.
    fixtures = {path: "\n".join(f"import {module}" for module in sorted(modules))
                for path, modules in IMPORTS.items()}
    for name, owner in OWNERS.items():
        fixtures[owner] += f"\nstruct {name} {{}}"
    if ownership_violations(fixtures, executable, imports):
        violations.append("gallery ownership self-test: valid fixture rejected")
    duplicate = dict(fixtures)
    duplicate["Photos/VaultGalleryView.swift"] = "struct VaultGalleryContentSnapshot {}"
    if not ownership_violations(duplicate, executable, imports):
        violations.append("gallery ownership self-test: duplicate owner accepted")
    removed = dict(fixtures)
    removed["Photos/VaultMediaImagePage.swift"] = removed["Photos/VaultMediaImagePage.swift"].replace(
        "struct VaultMediaImagePage {}", "// struct VaultMediaImagePage {}")
    if not ownership_violations(removed, executable, imports):
        violations.append("gallery ownership self-test: comment spoof accepted")
    coupled = dict(fixtures)
    coupled["Photos/VaultMediaImagePage.swift"] += "\nlet store: VaultGeneralFileStore"
    if not ownership_violations(coupled, executable, imports):
        violations.append("gallery ownership self-test: store authority accepted")
    image_owner = "Photos/VaultMediaImagePage.swift"
    for label, mutated in (
        ("public API", fixtures[image_owner].replace("struct ", "public struct ")),
        ("unreviewed import", fixtures[image_owner] + "\nimport KeyHollowVaultCore"),
    ):
        if not ownership_violations({**fixtures, image_owner: mutated}, executable, imports):
            violations.append(f"gallery ownership self-test: {label} accepted")
    relocated = dict(fixtures)
    relocated["Photos/Other.swift"] = relocated.pop(image_owner)
    if not ownership_violations(relocated, executable, imports):
        violations.append("gallery ownership self-test: moved owner accepted")
    violations.extend(location_probe_violations(sources, executable))
    violations.extend(controls_probe_violations(sources, executable))
    violations.extend(thumbnail_cache_probe_violations(sources, executable))
    folder_checks = runpy.run_path(str(root.parent / "scripts/gallery_folder_boundaries.py"))
    violations.extend(folder_checks["folder_probe_violations"](sources, executable, body))
    return violations


def thumbnail_cache_probe_violations(sources, executable):
    cache = executable(sources.get("UI/VaultGalleryThumbnailCache.swift", ""))
    gallery = executable(sources.get("Photos/VaultGalleryView.swift", ""))
    compact = lambda text: re.sub(r"\s+", "", text)
    cache_requirements = (
        "private var photos: [UUID: UIImage] = [:]",
        "private var generalFiles: [UUID: UIImage] = [:]",
        "private var retention: VaultGalleryThumbnailRetentionPolicy<VaultGallerySelection.Item>",
        "init(maximumCount: Int = 96)",
        "self = Self(maximumCount: retention.maximumCount)",
    )
    gallery_requirements = (
        "@State private var thumbnailCache = VaultGalleryThumbnailCache()",
        "thumbnailCache[item.id]",
        "thumbnailCache.markVisible(item.id)",
        "thumbnailCache.markHidden(item.id)",
        "thumbnailCache.retainPhotos(withIDs: validIDs)",
        "thumbnailCache.retainGeneralFiles(withIDs: validIDs)",
        "thumbnailCache.retainKnownItems(known)",
        "thumbnailCache.insert(rendered.image, for: .photo(record.id))",
        "thumbnailCache.insert(renderedImage.image, for: .generalFile(record.id))",
    )

    def check(cache_code, gallery_code):
        errors = []
        for code, requirements in ((cache_code, cache_requirements),
                                   (gallery_code, gallery_requirements)):
            if any(compact(value) not in compact(code) for value in requirements):
                errors.append("gallery thumbnail cache ownership/wiring changed")
        if re.search(r"\b(?:Task|async|Data|VaultPhotoRecord|VaultGeneralFileRecord)\b|@(State|Published)", cache_code):
            errors.append("thumbnail cache gained loading/task/record authority")
        if re.search(r"\b(?:thumbnails|generalFileThumbnails|thumbnailRetention)\b", gallery_code):
            errors.append("gallery regained duplicate thumbnail state")
        reset_start = gallery_code.find(".task(id: session.activeVaultID)")
        reset_end = gallery_code.find("await session.performSensitiveTask", reset_start)
        if not (0 <= reset_start < reset_end and
                "thumbnailCache.removeAll()" in gallery_code[reset_start:reset_end]):
            errors.append("vault reset must clear images and retention before loading")
        return errors

    errors = check(cache, gallery)
    if errors:
        return errors
    for value in cache_requirements:
        if not check(compact(cache).replace(compact(value), "", 1), gallery):
            errors.append(f"thumbnail cache self-test accepted missing {value}")
    for value in (*gallery_requirements, "thumbnailCache.removeAll()"):
        # Keep the lifecycle marker readable for the reset-specific assertion.
        mutated = re.sub(re.escape(value).replace(r"\ ", r"\s+"), "", gallery, count=1)
        if mutated == gallery or not check(cache, mutated):
            errors.append(f"thumbnail cache self-test accepted missing {value}")
    for addition in ("let task: Task<Void, Never>", "let record: VaultPhotoRecord"):
        if not check(cache + "\n" + addition, gallery):
            errors.append("thumbnail cache self-test accepted protected loading authority")
    if not check(cache, gallery + "\nvar thumbnails: [UUID: UIImage]"):
        errors.append("thumbnail cache self-test accepted duplicate composition state")
    return errors


HEADER_ROUTES = {
    "cancelSelection": "leaveSelectionMode()",
    "toggleSelectAll": "toggleSelectAll(visibleItemIDs)",
    "lock": "lockVaultAndFinishCleanup()",
    "back": "leaveSelectionMode() activeFolderID = locationSnapshot.activeFolder?.parentID",
    "beginSelection": "isSelecting = true",
    "importContent": (
        "guard let vaultID = session.activeVaultID else { return } "
        "importDestination = VaultImportDestination(vaultID: vaultID, "
        "securityEpoch: session.securityEpoch, folderID: activeFolderID) "
        "showingImportOptions = true"
    ),
    "newFolder": "requestNewFolder()",
    "newVault": "showingNewVault = true",
    "importVault": "showingEncryptedImport = true",
    "exportVault": "showingEncryptedExport = true",
    "verifyBackup": "showingBackupVerification = true",
    "vaultFiles": "showingVaultFiles = true",
    "securitySettings": "showingSecuritySettings = true",
}
SELECTION_ROUTES = {
    "savePhotos": "saveSelectedPhotos()",
    "exportFiles": "exportSelectedGeneralFiles()",
    "move": "requestSelectionMove()",
    "delete": "showingDeleteSelectionConfirmation = true",
}
CONTROL_INPUTS = (
    "allVisibleSelected: selection.containsAll(visibleItemIDs)",
    "selectionUnavailable: visibleItemIDs.isEmpty || isWorking",
    "importUnavailable: isWorking || !contentStoresLoaded || presentationStore == nil",
    "isAtRoot: activeFolderID == nil",
    "transferMode: selection.transferMode",
    "isSelectionEmpty: selection.isEmpty",
    "hasMoveDestination: locationSnapshot.hasSelectionMoveDestination",
    "searchText: $searchText",
    "catalogSortOrder: $catalogSortOrder",
    "isQueryEmpty: locationSnapshot.activeCatalogSearchQuery.isEmpty",
)
CONTROL_PRESENTATION = {
    "Header": (".disabled(selectionUnavailable)", ".disabled(importUnavailable)",
               ".disabled(isWorking)", '.accessibilityIdentifier("vault-verify-backup")'),
    "Search": ('TextField("Search this location", text: $searchText)',
               'Picker("Sort", selection: $catalogSortOrder)',
               '.accessibilityLabel("Sort vault items")'),
    "Selection": ('Label("Export Files", systemImage: "square.and.arrow.up")',
                  ".disabled(isSelectionEmpty || isWorking)",
                  ".disabled(isSelectionEmpty || !hasMoveDestination || isWorking)"),
}


def control_routes_violations(control, composition, routes):
    compact = lambda text: re.sub(r"\s+", "", text)
    errors = []
    if set(re.findall(r"perform\(\.(\w+)\)", compact(control))) != set(routes):
        errors.append("gallery control intent inventory changed")
    for action, operation in routes.items():
        if compact(f"case .{action}: {operation}") not in compact(composition):
            errors.append(f"gallery control lost composition-owned action {action}")
    return errors


def controls_probe_violations(sources, executable):
    errors = []
    composition = executable(sources.get("Photos/VaultGalleryView.swift", ""))
    compact = lambda text: re.sub(r"\s+", "", text)
    for value in CONTROL_INPUTS:
        if compact(value) not in compact(composition):
            errors.append(f"gallery control input changed: {value}")
    for name, requirements in CONTROL_PRESENTATION.items():
        source = sources.get(f"Photos/VaultGallery{name}Controls.swift", "")
        code = executable(source)
        if re.search(r"\b(?:Task|async|VaultPhotoRecord|VaultGeneralFileRecord)\b|@(State\w*|Environment\w*|ObservedObject)", code):
            errors.append(f"gallery {name} controls gained data/task/state authority")
        for requirement in requirements:
            if requirement not in source:
                errors.append(f"gallery {name} controls lost presentation: {requirement}")
        routes = {"Header": HEADER_ROUTES, "Selection": SELECTION_ROUTES}.get(name)
        if routes is None:
            continue
        errors.extend(control_routes_violations(code, composition, routes))
        # Mutate the actual production wiring; comments/strings cannot satisfy
        # action routing because both inputs use the executable Swift scanner.
        for action, operation in routes.items():
            fragment = compact(f"case .{action}: {operation}")
            mutated = compact(composition).replace(fragment, "", 1)
            if not control_routes_violations(code, mutated, routes):
                errors.append(f"control self-test accepted missing route {action}")
        mutated = re.sub(r"perform\(\.(\w+)\)", "perform(.unknown)", compact(code), count=1)
        if not control_routes_violations(mutated, composition, routes):
            errors.append(f"control self-test accepted unknown {name} intent")
    return errors


LOCATION_FIELDS = {
    "records": "[VaultPhotoRecord]",
    "generalFileRecords": "[VaultGeneralFileRecord]",
    "folderManifest": "VaultFolderPresentationManifest",
    "activeFolderID": "UUID?",
    "searchText": "String",
    "catalogSortOrder": "VaultCatalogSortOrder",
    "maximumFolderDepth": "Int",
}
LOCATION_EXPRESSIONS = (
    "VaultCatalogSearchQuery(searchText)",
    "sortOrder: catalogSortOrder",
    "makeVisibleGallerySnapshot().filtering(with: activeCatalogSearchQuery)",
    "visibleGalleryFolders.filter { query.matches($0.name) }",
    "maximumDepth: maximumFolderDepth",
)


def location_snapshot_violations(source, composition, executable):
    violations = []
    code = executable(source)
    compact = lambda text: re.sub(r"\s+", "", text)
    for field, kind in LOCATION_FIELDS.items():
        if compact(f"private let {field}: {kind}") not in compact(code):
            violations.append(f"gallery location must capture immutable {field}")
    if re.search(r"\b(?:Task|async|mutating|ObservableObject)\b|@(State|Published)", code):
        violations.append("gallery location gained task or mutable observable authority")
    for expression in LOCATION_EXPRESSIONS:
        if compact(expression) not in compact(code):
            violations.append(f"gallery location calculation changed: {expression}")
    if 'return "No Results"' not in source:
        violations.append("gallery location lost the existing empty-search presentation")
    arguments = [
        f"{field}: {field}" for field in LOCATION_FIELDS if field != "maximumFolderDepth"
    ] + ["maximumFolderDepth: VaultFolderPresentationStore.maximumFolderDepth"]
    construction = "VaultGalleryLocationSnapshot(" + ",".join(arguments) + ")"
    if compact(construction) not in compact(executable(composition)):
        violations.append("gallery location must receive current metadata and the store's depth bound")
    return violations


def location_probe_violations(sources, executable):
    source = sources.get("Photos/VaultGalleryLocationSnapshot.swift", "")
    composition = sources.get("Photos/VaultGalleryView.swift", "")
    violations = location_snapshot_violations(source, composition, executable)
    if violations:
        return violations
    for anchor in (*LOCATION_EXPRESSIONS, 'return "No Results"', "private let records"):
        mutated = source.replace(anchor, "", 1)
        if not location_snapshot_violations(mutated, composition, executable):
            violations.append(f"gallery location self-test accepted removal: {anchor}")
    if not location_snapshot_violations(source + "\nlet task: Task<Void, Never>", composition, executable):
        violations.append("gallery location self-test accepted task ownership")
    for anchor in ("records: records", "VaultFolderPresentationStore.maximumFolderDepth"):
        mutated = composition.replace(anchor, "", 1)
        if not location_snapshot_violations(source, mutated, executable):
            violations.append(f"gallery location self-test accepted unwired input: {anchor}")
    return violations


def thumbnail_pipeline_violations(pipeline_source, match_position):
    violations = []
    load_or_generate_start = pipeline_source.find(
        "func loadOrGenerate<Value: Sendable>("
    )
    generate_thumbnail_start = pipeline_source.find(
        "private func generateThumbnail("
    )
    load_or_generate_source = pipeline_source[
        load_or_generate_start:generate_thumbnail_start
    ]
    image_entry_source = pipeline_source[:load_or_generate_start]
    generate_thumbnail_source = pipeline_source[generate_thumbnail_start:]
    cache_check = "if let cachedValue = try await loadCached()"
    cache_checks = [
        match.start()
        for match in re.finditer(re.escape(cache_check), load_or_generate_source)
    ]
    permit_position = load_or_generate_source.find(
        "guard await acquire() else { throw CancellationError() }"
    )
    generation_position = load_or_generate_source.find(
        "return try await generate()"
    )
    original_load_position = generate_thumbnail_source.find(
        "generalFileStore.loadFile(record)"
    )
    miss_prepare_position = generate_thumbnail_source.find(
        "cacheMissImageProcessor.prepareThumbnail("
    )
    for required in (
        "private let cachedThumbnailDecoder = VaultSecureImageProcessor()",
        "private let cacheMissImageProcessor = VaultSecureImageProcessor()",
        "cachedThumbnailDecoder.decodeThumbnail(",
        "catch let cancellation as CancellationError",
        "CheckedContinuation<Bool, Never>",
        "withTaskCancellationHandler",
        "cancelWaiter(id: waiterID)",
        "continuation.resume(returning: false)",
        "defer { release() }",
    ):
        if required not in pipeline_source:
            violations.append(
                "KeyHollow/Photos/VaultGeneralFileThumbnailPipeline.swift: general-file "
                f"thumbnail cache/miss isolation is missing {required!r}"
            )
    if not (
        load_or_generate_start >= 0
        and generate_thumbnail_start > load_or_generate_start
        and len(cache_checks) == 2
        and cache_checks[0] < permit_position < cache_checks[1]
        and cache_checks[1] < generation_position
        and 0 <= original_load_position < miss_prepare_position
        and "return try await loadOrGenerate(" in image_entry_source
        and "try await generateThumbnail(" in image_entry_source
        and pipeline_source.count("generateThumbnail(") == 2
    ):
        violations.append(
            "KeyHollow/Photos/VaultGeneralFileThumbnailPipeline.swift: encrypted thumbnail "
            "cache hits must bypass the full-payload permit, queued misses "
            "must recheck the cache, and original preparation must remain "
            "inside the bounded miss lane"
        )

    for required in (
        "import KeyHollowEncryptedVideoAddOn",
        "VaultEncryptedVideoPolicy.kind(",
        "VaultEncryptedVideoThumbnailRenderer.render(",
    ):
        if required not in pipeline_source:
            violations.append(
                "KeyHollow/Photos/VaultGeneralFileThumbnailPipeline.swift: encrypted-video "
                f"thumbnail integration is incomplete; missing {required!r}"
            )

    video_prepare_position = match_position(
        r"generalFileStore\.prepareExport\s*\(\s*\[\s*record\s*\]\s*\)",
        generate_thumbnail_source,
    )
    video_render_position = match_position(
        r"VaultEncryptedVideoThumbnailRenderer\.render\s*\(",
        generate_thumbnail_source,
    )
    video_cleanup_position = match_position(
        r"await\s+[A-Za-z_][A-Za-z0-9_\.]*discardExport\s*\(",
        generate_thumbnail_source,
        video_render_position,
    )
    video_store_position = match_position(
        r"presentationStore\.storeThumbnail\s*\(",
        generate_thumbnail_source,
        video_render_position,
    )
    if not (
        permit_position >= 0
        and 0 <= video_prepare_position < video_render_position
        and video_render_position < video_cleanup_position < video_store_position
    ):
        violations.append(
            "KeyHollow/Photos/VaultGeneralFileThumbnailPipeline.swift: video cold-thumbnail "
            "misses must prepare, render, clean up plaintext, and persist "
            "inside the existing VaultGeneralFileThumbnailPipeline permit"
        )

    for parallel_lane in (
        "videoThumbnails.render(",
        "videoThumbnailPipeline",
        "acquireVideoPermit",
        "videoThumbnailWaiters",
    ):
        if parallel_lane in pipeline_source:
            violations.append(
                "KeyHollow/Photos/VaultGeneralFileThumbnailPipeline.swift: video thumbnails "
                f"introduced a parallel full-payload lane ({parallel_lane})"
            )

    return violations


def thumbnail_probe_violations(source, match_position):
    violations = []
    if thumbnail_pipeline_violations(source, match_position):
        return ["thumbnail self-test: production fixture is invalid"]
    for anchor in (
        "guard await acquire() else { throw CancellationError() }",
        "defer { release() }",
        "cancelWaiter(id: waiterID)",
        "generalFileStore.loadFile(record)",
        "await generalFileStore.discardExport(prepared)",
    ):
        if anchor not in source:
            violations.append(f"thumbnail self-test: missing mutation anchor {anchor}")
        elif not thumbnail_pipeline_violations(source.replace(anchor, "", 1), match_position):
            violations.append(f"thumbnail self-test: missing protection was accepted: {anchor}")
    return violations
