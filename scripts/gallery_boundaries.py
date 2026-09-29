"""Checks for gallery responsibilities extracted from the composition view."""

import re


OWNERS = {
    "VaultGalleryContentItem": "Photos/VaultGalleryContentSnapshot.swift",
    "VaultGalleryOpenRoute": "Photos/VaultGalleryContentSnapshot.swift",
    "VaultGalleryContentSnapshot": "Photos/VaultGalleryContentSnapshot.swift",
    "VaultGeneralFileThumbnailPipelineHooks": "Photos/VaultGeneralFileThumbnailPipeline.swift",
    "VaultGeneralFileThumbnailPipeline": "Photos/VaultGeneralFileThumbnailPipeline.swift",
    "VaultMediaImagePage": "Photos/VaultMediaImagePage.swift",
}
IMPORTS = {
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
            forbidden += ["VaultPhotoStore", "VaultGeneralFileStore", "VaultFolderPresentationStore", "FileManager"]
        if re.search(r"\b(?:" + "|".join(forbidden) + r")\b", text):
            violations.append(f"{owner}: extracted responsibility gained protected storage/session/network authority")
        if re.search(r"\b(?:public|open)\s+(?:struct|class|actor|enum|func|var|let)\b", text):
            violations.append(f"{owner}: app-only extraction must not widen the public API")
    return violations


def gallery_ownership_violations(root, executable, imports):
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
