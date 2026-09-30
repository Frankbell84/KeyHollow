"""Presentation routing probes; payload and lifetime ownership stay in composition."""

import re


ROUTES = {
    "dismiss": "beginMediaNavigationDismissal()",
    "toggleChrome": "toggleMediaChrome()",
    "saveImage": "saveCurrentMediaImage()",
    "delete": "deleteCurrentMedia()",
}
VIEWER_INPUTS = (
    "VaultGalleryMediaViewer(",
    "queue: queue",
    "isNavigationEnabled: !isSavingPreview && !isDeletingMedia "
    "&& !isClosingMediaNavigation && !isMediaImageZoomed "
    "&& isMediaNavigationContentReady(queue)",
    "isBusy: isSavingPreview || isDeletingMedia || isClosingMediaNavigation",
    "isChromeVisible: isMediaChromeVisible",
    "isImageSaveEnabled: imagePreview.active?.id == queue.selectedID",
    "previewMessage: $previewMessage",
    "onSelectionChange: selectMediaNavigationItem",
    "mediaNavigationActiveContent(item)",
    "Color.black.ignoresSafeArea()",
)
PRESENTATION = (
    "queue: queue",
    "isNavigationEnabled: isNavigationEnabled",
    "onSelectionChange: onSelectionChange",
    "onDismissalRequested: { perform(.dismiss) }",
    "guard VaultMediaChromeInteractionPolicy.acceptsContentTap("
    "for: queue.currentItem.kind) else { return } perform(.toggleChrome)",
    ".safeAreaInset(edge: .top, spacing: 0) { "
    "if queue.currentItem.kind == .video { toolbar } }",
    ".overlay(alignment: .top) { "
    "if isChromeVisible && queue.currentItem.kind == .image { toolbar "
    ".transition(.move(edge: .top).combined(with: .opacity)) } }",
    ".animation(.easeInOut(duration: 0.2), value: isChromeVisible)",
    "get: { previewMessage != nil }",
    "set: { if !$0 { previewMessage = nil } }",
    'Button("OK") { previewMessage = nil }',
    'Text(previewMessage ?? "")',
)
TOOLBAR = (
    'Button("Done") { perform(.dismiss) } .disabled(isBusy)',
    "if isBusy { ProgressView() .tint(.white) } "
    "else if queue.currentItem.kind == .image",
    'Button { perform(.saveImage) } label: { Image(systemName: "square.and.arrow.down") } '
    '.accessibilityLabel("Save to Photos") .disabled(!isImageSaveEnabled)',
    'Button(role: .destructive) { perform(.delete) } label: { Image(systemName: "trash") } '
    '.accessibilityLabel("Delete from Vault") .disabled(isBusy)',
    "Text(queue.currentItem.accessibilityTitle)",
    "Text(queue.accessibilityPosition)",
)
LOADING_INPUTS = (
    "VaultGalleryMediaLoadState(",
    "isFailed: failedMediaID == item.id",
    "isInteractionDisabled: isSavingPreview || isDeletingMedia || isClosingMediaNavigation",
    "onRetry: { retryMediaNavigationItem(item.id) }",
)
LOADING = (
    "if isFailed",
    'Button("Try Again") { onRetry() } .buttonStyle(.borderedProminent) '
    ".disabled(isInteractionDisabled)",
    '} else { ProgressView("Opening…")',
)


def media_violations(owner, gallery, executable, body):
    compact = lambda text: re.sub(r"\s+", "", text)
    section = lambda source, anchor: body(source, anchor, preserve_string_literals=True) or ""
    sections = (
        (section(gallery, "private var mediaNavigationViewer:"), VIEWER_INPUTS),
        (section(owner, "var body:"), PRESENTATION),
        (section(owner, "private var toolbar:"), TOOLBAR),
        (section(gallery, "private func mediaNavigationLoadState("), LOADING_INPUTS),
        (section(owner, "struct VaultGalleryMediaLoadState:"), LOADING),
    )
    owner = executable(owner)
    errors = []
    for code, requirements in sections:
        for required in requirements:
            if compact(required) not in compact(code):
                errors.append(f"gallery media presentation lost {required}")
    for action, operation in ROUTES.items():
        if compact(f"case .{action}: {operation}") not in compact(sections[0][0]):
            errors.append(f"gallery media action lost composition route: {action}")
    if set(re.findall(r"perform\(\.(\w+)\)", compact(owner))) != set(ROUTES):
        errors.append("gallery media presentation intent inventory changed")
    if (owner.count("VaultMediaNavigationPager(") != 1
            or owner.count("activeContent(item)") != 1
            or sections[4][0].count("onRetry()") != 1
            or sections[4][0].count("ProgressView(") != 1):
        errors.append("media viewer must retain one active payload and one failed/opening route")
    if re.search(r"\b(?:Task|async|UIImage|Data|VaultImagePreviewCoordinator|"
                 r"VaultVideoPlaybackCoordinator|VaultEncryptedVideoPlayerSession|"
                 r"VaultEncryptedVideoPlayerView|VaultMediaImagePage)\b|"
                 r"@(State|StateObject|ObservedObject|EnvironmentObject)\b", owner):
        errors.append("media presentation gained payload, operation or lifecycle authority")
    return errors


def media_probe_violations(sources, executable, body):
    owner = sources.get("Photos/VaultGalleryMediaViewer.swift", "")
    gallery = sources.get("Photos/VaultGalleryView.swift", "")
    errors = media_violations(owner, gallery, executable, body)
    if errors:
        return errors
    # Mutate the real source with whitespace-tolerant anchors; no copied fixture.
    def remove(source, anchor, start=0):
        pattern = r"\s*".join(re.escape(char) for char in anchor if not char.isspace())
        return source[:start] + re.sub(pattern, "", source[start:], count=1)

    for anchor in (*VIEWER_INPUTS, *LOADING_INPUTS,
                   *(f"case .{action}: {route}" for action, route in ROUTES.items())):
        start = gallery.index("private func mediaNavigationLoadState(") if anchor in LOADING_INPUTS else 0
        changed = remove(gallery, anchor, start)
        if changed == gallery or not media_violations(owner, changed, executable, body):
            errors.append(f"media self-test accepted missing composition input: {anchor}")
    for anchor in (*PRESENTATION, *TOOLBAR, *LOADING, "activeContent(item)"):
        changed = remove(owner, anchor)
        if changed == owner or not media_violations(changed, gallery, executable, body):
            errors.append(f"media self-test accepted missing presentation protection: {anchor}")
    for addition in ("let task: Task<Void, Never>", "@State var retainedImage: UIImage?"):
        if not media_violations(owner + "\n" + addition, gallery, executable, body):
            errors.append("media self-test accepted new task/payload authority")
    return errors
