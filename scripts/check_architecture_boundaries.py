#!/usr/bin/env python3
"""Fail CI when platform UI or remote-service concerns leak into the core."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "KeyHollow"
PROJECT_FILE = ROOT / "project.yml"
ADDON_ROOT = SOURCE_ROOT / "AddOns"
BACKUP_VERIFICATION_ROOT = ADDON_ROOT / "BackupVerification"
ENCRYPTED_VIDEO_ROOT = ADDON_ROOT / "EncryptedVideo"
MEDIA_NAVIGATION_ROOT = ADDON_ROOT / "MediaNavigation"
THUMBNAIL_EXTENSION_ROOT = ROOT / "KeyHollowVaultThumbnailExtension"

PRESENTATION_FILES = {
    "KeyHollow/App/KeyHollowApp.swift",
    "KeyHollow/Photos/SecurePhotoPicker.swift",
    "KeyHollow/Photos/VaultGalleryView.swift",
}
PRESENTATION_PREFIXES = (
    "KeyHollow/UI/",
    "KeyHollow/AddOns/EncryptedVideo/",
    "KeyHollow/AddOns/BackupVerification/",
    "KeyHollow/AddOns/MediaNavigation/",
    "KeyHollow/AddOns/SecurePreview/",
)

UI_FRAMEWORKS = {
    "AVFoundation",
    "AVKit",
    "Photos",
    "PhotosUI",
    "SwiftUI",
    "UIKit",
    "UniformTypeIdentifiers",
}
REMOTE_SDKS = {
    "AWSCore",
    "AWSS3",
    "Alamofire",
    "AppCenter",
    "Firebase",
    "GoogleSignIn",
    "Mixpanel",
    "RevenueCat",
    "Sentry",
    "Segment",
    "Supabase",
}
CORE_PREFIXES = (
    "KeyHollow/Security/",
    "KeyHollow/Session/",
    "KeyHollow/Storage/",
    "KeyHollow/Transfer/",
)
CORE_PHOTO_FILES = {
    "KeyHollow/Photos/VaultPhotoModels.swift",
    "KeyHollow/Photos/VaultPhotoStore.swift",
}
CRYPTO_MODULE_PREFIXES = ("KeyHollow/ThirdParty/Argon2id/",)
CRYPTO_MODULE_FILES = {"KeyHollow/Security/CryptoBox.swift"}
VAULT_MODULE_FILES = {
    "KeyHollow/Security/KeyDerivation.swift",
    "KeyHollow/Security/PasscodePolicy.swift",
    "KeyHollow/Security/VaultEnvelope.swift",
    "KeyHollow/Security/VaultLocator.swift",
    "KeyHollow/Storage/VaultStore.swift",
}
PHOTO_MODULE_FILES = {
    "KeyHollow/Photos/VaultPhotoCryptographicAccess.swift",
    "KeyHollow/Photos/VaultPhotoModels.swift",
    "KeyHollow/Photos/VaultPhotoStore.swift",
}
PHOTOS_ADAPTER_FILES = {
    "KeyHollow/Photos/PhotoLibraryAdapter.swift",
}
TRANSFER_MODULE_FILES = {
    "KeyHollow/Transfer/PortableArchiveContainer.swift",
    "KeyHollow/Transfer/PortableArchiveSecurity.swift",
    "KeyHollow/Transfer/PortableArchivePayload.swift",
    "KeyHollow/Transfer/PortableVaultRestoreTransactionJournal.swift",
    "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift",
}
GALLERY_UI_MODULE_FILES = {
    "KeyHollow/UI/VaultGalleryGridView.swift",
    "KeyHollow/UI/VaultGalleryTilePresentation.swift",
    "KeyHollow/UI/VaultFolderPresentationViews.swift",
    "KeyHollow/UI/VaultGallerySelection.swift",
}
FILE_RECOGNITION_PREFIX = "KeyHollow/AddOns/FileRecognition/"
BACKUP_VERIFICATION_PREFIX = "KeyHollow/AddOns/BackupVerification/"
GENERAL_FILE_SUPPORT_PREFIX = "KeyHollow/AddOns/GeneralFileSupport/"
SECURE_PREVIEW_PREFIX = "KeyHollow/AddOns/SecurePreview/"
ENCRYPTED_VIDEO_PREFIX = "KeyHollow/AddOns/EncryptedVideo/"
MEDIA_NAVIGATION_PREFIX = "KeyHollow/AddOns/MediaNavigation/"
ENCRYPTED_VIDEO_MODULE_FILES = {
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoPlayerView.swift",
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoPolicy.swift",
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoThumbnailRenderer.swift",
}
BACKUP_VERIFICATION_MODULE_FILES = {
    "KeyHollow/AddOns/BackupVerification/BackupVerificationReport.swift",
    "KeyHollow/AddOns/BackupVerification/BackupVerificationReportView.swift",
}
MEDIA_NAVIGATION_MODULE_FILES = {
    "KeyHollow/AddOns/MediaNavigation/VaultMediaNavigationModels.swift",
    "KeyHollow/AddOns/MediaNavigation/VaultMediaNavigationPager.swift",
}
MEDIA_NAVIGATION_IMPORTS = {
    "KeyHollow/AddOns/MediaNavigation/VaultMediaNavigationModels.swift": {
        "Foundation",
    },
    "KeyHollow/AddOns/MediaNavigation/VaultMediaNavigationPager.swift": {
        "SwiftUI",
    },
}
BACKUP_VERIFICATION_IMPORTS = {
    "KeyHollow/AddOns/BackupVerification/BackupVerificationReport.swift": {
        "Foundation",
    },
    "KeyHollow/AddOns/BackupVerification/BackupVerificationReportView.swift": {
        "Foundation",
        "SwiftUI",
    },
}
ENCRYPTED_VIDEO_IMPORTS = {
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoPlayerView.swift": {
        "AVFoundation",
        "AVKit",
        "Foundation",
        "SwiftUI",
    },
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoPolicy.swift": {
        "AVFoundation",
        "CoreGraphics",
        "Foundation",
        "UniformTypeIdentifiers",
    },
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoThumbnailRenderer.swift": {
        "AVFoundation",
        "CoreGraphics",
        "Foundation",
        "ImageIO",
        "UniformTypeIdentifiers",
    },
}
SECURITY_SCOPED_INGRESS_PREFIXES = (
    FILE_RECOGNITION_PREFIX,
    GENERAL_FILE_SUPPORT_PREFIX,
)


def relative(file: Path) -> str:
    return file.relative_to(ROOT).as_posix()


def is_presentation(path: str) -> bool:
    return path in PRESENTATION_FILES or path.startswith(PRESENTATION_PREFIXES)


def _mask_swift_range(
    output: list[str], source: str, start: int, end: int
) -> None:
    for index in range(start, min(end, len(source))):
        if source[index] not in "\r\n":
            output[index] = " "


def sanitized_swift_source(
    source: str, *, mask_string_literals: bool
) -> str:
    """Masks Swift comments and optionally string literals without moving text.

    The scanner understands nested block comments plus ordinary, multiline,
    and pound-delimited raw strings. Keeping every character position stable
    lets later brace/slice checks use indices from this executable view against
    the original source without a second, divergent parser.
    """

    output = list(source)
    index = 0
    source_length = len(source)

    while index < source_length:
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            if end < 0:
                end = source_length
            _mask_swift_range(output, source, index, end)
            index = end
            continue

        if source.startswith("/*", index):
            depth = 1
            end = index + 2
            while end < source_length and depth > 0:
                if source.startswith("/*", end):
                    depth += 1
                    end += 2
                elif source.startswith("*/", end):
                    depth -= 1
                    end += 2
                else:
                    end += 1
            _mask_swift_range(output, source, index, end)
            index = end
            continue

        pound_end = index
        while pound_end < source_length and source[pound_end] == "#":
            pound_end += 1
        if pound_end < source_length and source[pound_end] == '"':
            quote_length = 3 if source.startswith('"""', pound_end) else 1
            delimiter = '"' * quote_length + "#" * (pound_end - index)
            end = pound_end + quote_length
            while end < source_length:
                if source.startswith(delimiter, end):
                    end += len(delimiter)
                    break
                if pound_end == index and source[end] == "\\":
                    end = min(end + 2, source_length)
                else:
                    end += 1
            if mask_string_literals:
                _mask_swift_range(output, source, index, end)
            index = end
            continue

        index += 1

    return "".join(output)


def swift_without_comments(source: str) -> str:
    return sanitized_swift_source(source, mask_string_literals=False)


def swift_executable_text(source: str) -> str:
    return sanitized_swift_source(source, mask_string_literals=True)


def imports(source: str) -> set[str]:
    executable = swift_executable_text(source)
    return set(
        re.findall(
            r"(?m)^(?:@preconcurrency\s+)?import\s+([A-Za-z0-9_]+)\s*$",
            executable,
        )
    )


def noncanonical_swift_imports(source: str) -> list[str]:
    executable = swift_executable_text(source)
    statements: set[str] = set()
    canonical = re.compile(
        r"(?:@preconcurrency\s+)?import\s+[A-Za-z0-9_]+"
    )
    attribute_only = re.compile(
        r"@[A-Za-z_][A-Za-z0-9_]*(?:\s*\([^)]*\))?"
    )

    lines = executable.splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if re.search(r"\bimport\b", stripped) is None:
            continue
        if canonical.fullmatch(stripped) is None:
            statements.add(stripped)
        preceding_attributes: list[str] = []
        preceding_index = index - 1
        while preceding_index >= 0:
            preceding = lines[preceding_index].strip()
            if attribute_only.fullmatch(preceding) is None:
                break
            preceding_attributes.insert(0, preceding)
            preceding_index -= 1
        if preceding_attributes:
            statements.add(" ".join((*preceding_attributes, stripped)))

    return sorted(statements)


def contains_in_order(source: str, markers: tuple[str, ...]) -> bool:
    source = swift_executable_text(source)
    cursor = 0
    for marker in markers:
        position = source.find(marker, cursor)
        if position < 0:
            return False
        cursor = position + len(marker)
    return True


def swift_block_body(source: str, anchor: str) -> str | None:
    executable = swift_executable_text(source)
    anchor_position = executable.find(anchor)
    if anchor_position < 0:
        return None

    opening_brace = executable.find("{", anchor_position)
    if opening_brace < 0:
        return None

    depth = 0
    for index in range(opening_brace, len(executable)):
        character = executable[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return executable[opening_brace + 1:index]
    return None


def yaml_key_present(body: str, key: str) -> bool:
    return re.search(
        rf"(?m)^[ \t]+(?:{re.escape(key)}|['\"]{re.escape(key)}['\"])\s*:",
        body,
    ) is not None


def checker_probe_violations() -> list[str]:
    failures: list[str] = []

    string_delimiter_fixture = (
        'let endpoint = "https://example.invalid/path"; VaultSession()\n'
        'let raw = #"/* not a comment */"#; VaultPhotoStore()\n'
        "// imagePreview.dismiss()\n"
    )
    comment_free_fixture = swift_without_comments(string_delimiter_fixture)
    executable_fixture = swift_executable_text(string_delimiter_fixture)
    if "VaultSession()" not in comment_free_fixture:
        failures.append(
            "checker self-test: URL string hid executable code from comment stripping"
        )
    if "VaultPhotoStore()" not in comment_free_fixture:
        failures.append(
            "checker self-test: raw string hid executable code from comment stripping"
        )
    if "imagePreview.dismiss()" in executable_fixture:
        failures.append(
            "checker self-test: line-comment marker entered executable Swift text"
        )
    if contains_in_order(
        "// imagePreview.dismiss()\nvideoPlayback.dismiss()",
        ("imagePreview.dismiss()", "videoPlayback.dismiss()"),
    ):
        failures.append(
            "checker self-test: commented lifecycle marker satisfied ordering"
        )

    scoped_fixture = (
        "await session.performSensitiveTask { _ in\n"
        "    try await store.loadPhoto(record)\n"
        "}\n"
        "try await generalFileStore.loadFile(record)\n"
    )
    sensitive_body = swift_block_body(
        scoped_fixture, "await session.performSensitiveTask"
    )
    if sensitive_body is None or "store.loadPhoto(record)" not in sensitive_body:
        failures.append(
            "checker self-test: sensitive-task closure body was not recovered"
        )
    if sensitive_body is not None and "generalFileStore.loadFile(record)" in sensitive_body:
        failures.append(
            "checker self-test: out-of-scope payload load entered sensitive closure"
        )

    for alternate_import in (
        "@_implementationOnly import KeyHollowVaultCore",
        "@_implementationOnly\nimport KeyHollowVaultCore",
        "@_spi(Internal) import KeyHollowPhotoCore",
        "import struct Foundation.Data",
    ):
        if not noncanonical_swift_imports(alternate_import):
            failures.append(
                "checker self-test: alternate Swift import syntax was accepted: "
                f"{alternate_import}"
            )

    if not yaml_key_present(
        "    dependencies: [{target: KeyHollowVaultCore}]\n", "dependencies"
    ):
        failures.append(
            "checker self-test: inline target dependencies escaped detection"
        )
    if re.search(r"(?m)^[ \t]+<<\s*:", "    <<: [*protectedDefaults]\n") is None:
        failures.append(
            "checker self-test: YAML merge dependency surface escaped detection"
        )

    lifecycle_spoof_fixture = (
        "func attach() {\n"
        "    // guard !isFinished else { return false }\n"
        "    let permitted = true\n"
        "}\n"
    )
    lifecycle_spoof_body = swift_block_body(lifecycle_spoof_fixture, "func attach()")
    if lifecycle_spoof_body is None or "guard !isFinished" in lifecycle_spoof_body:
        failures.append(
            "checker self-test: commented image-lifecycle guard entered function scope"
        )

    string_anchor_fixture = (
        'let example = "private func saveCurrentMediaImage() { unsafe() }"\n'
    )
    if swift_block_body(
        string_anchor_fixture,
        "private func saveCurrentMediaImage()",
    ) is not None:
        failures.append(
            "checker self-test: string-literal function marker created a false scope"
        )

    surface_scope_fixture = (
        "public struct VaultSecureImageSurface: UIViewRepresentable {\n"
        "    let safeMetadata = true\n"
        "}\n"
        "let escapedPayload: Data? = nil\n"
    )
    surface_scope_body = swift_block_body(
        surface_scope_fixture,
        "public struct VaultSecureImageSurface: UIViewRepresentable",
    )
    if surface_scope_body is None or "Data" in surface_scope_body:
        failures.append(
            "checker self-test: code outside secure-image surface entered its scope"
        )

    return failures


def match_position(pattern: str, source: str, start: int = 0) -> int:
    match = re.search(pattern, source[start:])
    return start + match.start() if match else -1


def target_body(project: str, target: str) -> str | None:
    match = re.search(
        rf"(?ms)^  {re.escape(target)}:\s*$\n(?P<body>.*?)(?=^  [A-Za-z0-9_]+:\s*$|^schemes:\s*$)",
        project,
    )
    return match.group("body") if match else None


def main() -> int:
    violations = checker_probe_violations()
    swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))

    project = PROJECT_FILE.read_text(encoding="utf-8")
    app_target = target_body(project, "KeyHollow")
    if app_target is None:
        violations.append("project.yml: application target KeyHollow is missing")

    addon_modules: set[str] = set()
    if ADDON_ROOT.exists():
        for addon_directory in sorted(path for path in ADDON_ROOT.iterdir() if path.is_dir()):
            addon_sources = sorted(addon_directory.rglob("*.swift"))
            if not addon_sources:
                continue

            addon_name = addon_directory.name
            if re.fullmatch(r"[A-Z][A-Za-z0-9]*", addon_name) is None:
                violations.append(
                    f"KeyHollow/AddOns/{addon_name}: add-on directory must use UpperCamelCase"
                )
                continue

            target = f"KeyHollow{addon_name}AddOn"
            addon_modules.add(target)
            body = target_body(project, target)
            if body is None:
                violations.append(
                    f"KeyHollow/AddOns/{addon_name}: missing compiled target {target}"
                )
                continue

            if re.search(r"(?m)^    type:\s*library\.static\s*$", body) is None:
                violations.append(f"project.yml: {target} must be a static library")

            if "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES" not in body:
                violations.append(
                    f"project.yml: {target} must compile Swift warnings as errors"
                )

            source_marker = f"- path: KeyHollow/AddOns/{addon_name}"
            if source_marker not in body:
                violations.append(
                    f"project.yml: {target} must own {source_marker!r}"
                )

            dependency_marker = f"- target: {target}"
            if app_target is not None and dependency_marker not in app_target:
                violations.append(
                    f"project.yml: KeyHollow must compose {target} explicitly"
                )

            exclusion_marker = f"- AddOns/{addon_name}"
            if app_target is not None and exclusion_marker not in app_target:
                violations.append(
                    f"project.yml: KeyHollow must exclude {exclusion_marker!r} "
                    "so the add-on is compiled only in its own target"
                )
    thumbnail_target = target_body(project, "KeyHollowVaultThumbnailExtension")
    required_thumbnail_markers = (
        "type: app-extension",
        "- path: KeyHollowVaultThumbnailExtension",
        "- path: KeyHollowVaultThumbnailExtension/Resources/Assets.xcassets",
        "buildPhase: resources",
        "PRODUCT_BUNDLE_IDENTIFIER: com.keyhollow.app.vault-thumbnail",
        "APPLICATION_EXTENSION_API_ONLY: YES",
        "NSExtensionPointIdentifier: com.apple.quicklook.thumbnail",
        "- com.keyhollow.encrypted-vault",
        "- target: KeyHollowVaultThumbnailExtension",
        "embed: true",
    )
    if thumbnail_target is None:
        violations.append(
            "project.yml: isolated KeyHollowVaultThumbnailExtension target is missing"
        )
    else:
        for marker in required_thumbnail_markers[:-2]:
            if marker not in thumbnail_target:
                violations.append(
                    f"project.yml: thumbnail extension is missing {marker!r}"
                )
        if app_target is not None:
            for marker in required_thumbnail_markers[-2:]:
                if marker not in app_target:
                    violations.append(
                        f"project.yml: app embedding is missing {marker!r}"
                    )

    if "CFBundleTypeIconFiles" in project or "UTTypeIcons:" in project:
        violations.append(
            "project.yml: abandoned document-icon metadata must not coexist "
            "with the thumbnail extension"
        )

    thumbnail_sources = (
        sorted(THUMBNAIL_EXTENSION_ROOT.rglob("*.swift"))
        if THUMBNAIL_EXTENSION_ROOT.exists()
        else []
    )
    if [relative(path) for path in thumbnail_sources] != [
        "KeyHollowVaultThumbnailExtension/ThumbnailProvider.swift"
    ]:
        violations.append(
            "KeyHollowVaultThumbnailExtension: expected exactly ThumbnailProvider.swift"
        )

    for file in thumbnail_sources:
        source = file.read_text(encoding="utf-8")
        unexpected = imports(source) - {"QuickLookThumbnailing", "UIKit"}
        if unexpected:
            violations.append(
                f"{relative(file)}: thumbnail extension imports outside its allowlist: "
                f"{', '.join(sorted(unexpected))}"
            )
        for forbidden in (
            "request.fileURL",
            "Data(contentsOf:",
            "FileHandle",
            "CryptoKit",
            "KeyHollowCryptoCore",
            "KeyHollowVaultCore",
            "KeyHollowPhotoCore",
            "KeyHollowTransferCore",
            "URLSession",
        ):
            if forbidden in source:
                violations.append(
                    f"{relative(file)}: thumbnail extension must not access vault "
                    f"data or protected services ({forbidden})"
                )

    approved_app_icon = (
        ROOT
        / "KeyHollow"
        / "Resources"
        / "Assets.xcassets"
        / "AppIcon.appiconset"
        / "AppIcon.png"
    )
    thumbnail_icon = (
        THUMBNAIL_EXTENSION_ROOT
        / "Resources"
        / "Assets.xcassets"
        / "KeyHollowVaultIcon.imageset"
        / "KeyHollowVaultIcon.png"
    )
    if not thumbnail_icon.is_file():
        violations.append(
            "KeyHollowVaultThumbnailExtension: approved thumbnail icon is missing"
        )
    elif not approved_app_icon.is_file():
        violations.append("KeyHollow: approved app icon is missing")
    elif thumbnail_icon.read_bytes() != approved_app_icon.read_bytes():
        violations.append(
            "KeyHollowVaultThumbnailExtension: thumbnail icon must remain a "
            "byte-for-byte copy of the approved app icon"
        )

    legacy_icons = ROOT / "KeyHollow" / "Resources" / "DocumentIcons"
    if legacy_icons.exists() and any(legacy_icons.iterdir()):
        violations.append(
            "KeyHollow/Resources/DocumentIcons: legacy icon assets must be removed"
        )

    required_crypto_module_markers = (
        "KeyHollowCryptoCore:",
        "- path: KeyHollow/Security/CryptoBox.swift",
        "- path: KeyHollow/ThirdParty/Argon2id",
        "- target: KeyHollowCryptoCore",
        "- Security/CryptoBox.swift",
        "- ThirdParty/Argon2id",
    )
    for marker in required_crypto_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled crypto boundary is missing {marker!r}"
            )

    required_vault_module_markers = (
        "KeyHollowVaultCore:",
        "- path: KeyHollow/Security/KeyDerivation.swift",
        "- path: KeyHollow/Security/PasscodePolicy.swift",
        "- path: KeyHollow/Security/VaultEnvelope.swift",
        "- path: KeyHollow/Security/VaultLocator.swift",
        "- path: KeyHollow/Storage/VaultStore.swift",
        "- target: KeyHollowVaultCore",
        "- Security/KeyDerivation.swift",
        "- Security/PasscodePolicy.swift",
        "- Security/VaultEnvelope.swift",
        "- Security/VaultLocator.swift",
        "- Storage/VaultStore.swift",
    )
    for marker in required_vault_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled vault boundary is missing {marker!r}"
            )

    required_photo_module_markers = (
        "KeyHollowPhotoCore:",
        "- path: KeyHollow/Photos/VaultPhotoCryptographicAccess.swift",
        "- path: KeyHollow/Photos/VaultPhotoModels.swift",
        "- path: KeyHollow/Photos/VaultPhotoStore.swift",
        "- target: KeyHollowPhotoCore",
        "- Photos/VaultPhotoCryptographicAccess.swift",
        "- Photos/VaultPhotoModels.swift",
        "- Photos/VaultPhotoStore.swift",
    )
    for marker in required_photo_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled photo-storage boundary is missing {marker!r}"
            )

    required_photos_adapter_markers = (
        "KeyHollowPhotosAdapter:",
        "- path: KeyHollow/Photos/PhotoLibraryAdapter.swift",
        "- target: KeyHollowPhotosAdapter",
        "- Photos/PhotoLibraryAdapter.swift",
    )
    for marker in required_photos_adapter_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled Photos adapter boundary is missing {marker!r}"
            )

    required_transfer_module_markers = (
        "KeyHollowTransferCore:",
        "- path: KeyHollow/Transfer/PortableArchiveContainer.swift",
        "- path: KeyHollow/Transfer/PortableArchiveSecurity.swift",
        "- path: KeyHollow/Transfer/PortableArchivePayload.swift",
        "- path: KeyHollow/Transfer/PortableVaultRestoreTransactionJournal.swift",
        "- path: KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift",
        "- target: KeyHollowTransferCore",
        "- Transfer/PortableArchiveContainer.swift",
        "- Transfer/PortableArchiveSecurity.swift",
        "- Transfer/PortableArchivePayload.swift",
        "- Transfer/PortableVaultRestoreTransactionJournal.swift",
        "- Transfer/EncryptedVaultTransferCoordinator.swift",
    )
    for marker in required_transfer_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled transfer boundary is missing {marker!r}"
            )

    required_gallery_ui_markers = (
        "KeyHollowGalleryUI:",
        "- path: KeyHollow/UI/VaultGalleryGridView.swift",
        "- path: KeyHollow/UI/VaultGalleryTilePresentation.swift",
        "- path: KeyHollow/UI/VaultFolderPresentationViews.swift",
        "- path: KeyHollow/UI/VaultGallerySelection.swift",
        "- target: KeyHollowGalleryUI",
        "- UI/VaultGalleryGridView.swift",
        "- UI/VaultGalleryTilePresentation.swift",
        "- UI/VaultFolderPresentationViews.swift",
        "- UI/VaultGallerySelection.swift",
    )
    for marker in required_gallery_ui_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled gallery UI boundary is missing {marker!r}"
            )
    gallery_ui_target = target_body(project, "KeyHollowGalleryUI")
    if gallery_ui_target is None:
        violations.append("project.yml: KeyHollowGalleryUI target is missing")
    else:
        expected_sources = {
            "KeyHollow/UI/VaultGalleryGridView.swift",
            "KeyHollow/UI/VaultGalleryTilePresentation.swift",
            "KeyHollow/UI/VaultFolderPresentationViews.swift",
            "KeyHollow/UI/VaultGallerySelection.swift",
        }
        declared_sources = set(
            re.findall(r"(?m)^      - path: ([^\r\n]+)$", gallery_ui_target)
        )
        if declared_sources != expected_sources:
            violations.append(
                "project.yml: KeyHollowGalleryUI source ownership changed; "
                f"expected {sorted(expected_sources)}, got {sorted(declared_sources)}"
            )
        for marker in (
            "type: library.static",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES",
            "DEFINES_MODULE: YES",
            "SKIP_INSTALL: YES",
        ):
            if marker not in gallery_ui_target:
                violations.append(
                    f"project.yml: KeyHollowGalleryUI is missing {marker!r}"
                )
        if re.search(r"(?m)^    dependencies:\s*$", gallery_ui_target):
            violations.append(
                "project.yml: KeyHollowGalleryUI must remain dependency-free; "
                "compose storage and add-on capabilities in the application shell"
            )
        for forbidden_dependency in (
            "KeyHollowCryptoCore",
            "KeyHollowVaultCore",
            "KeyHollowPhotoCore",
            "KeyHollowTransferCore",
            "KeyHollowFolderPresentationAddOn",
            "KeyHollowGeneralFileSupportAddOn",
        ):
            if f"- target: {forbidden_dependency}" in gallery_ui_target:
                violations.append(
                    "project.yml: KeyHollowGalleryUI depends on protected/content "
                    f"module {forbidden_dependency} instead of immutable presentation values"
                )

    media_navigation_target = target_body(
        project,
        "KeyHollowMediaNavigationAddOn",
    )
    media_navigation_target_count = len(
        re.findall(r"(?m)^  KeyHollowMediaNavigationAddOn:\s*$", project)
    )
    if media_navigation_target is None:
        violations.append(
            "project.yml: KeyHollowMediaNavigationAddOn target is missing"
        )
    else:
        if media_navigation_target_count != 1:
            violations.append(
                "project.yml: expected exactly one "
                "KeyHollowMediaNavigationAddOn target, found "
                f"{media_navigation_target_count}"
            )

        expected_sources = {"KeyHollow/AddOns/MediaNavigation"}
        declared_sources = set(
            re.findall(
                r"(?m)^      - path: ([^\r\n]+)$",
                media_navigation_target,
            )
        )
        if declared_sources != expected_sources:
            violations.append(
                "project.yml: KeyHollowMediaNavigationAddOn source ownership "
                f"changed; expected {sorted(expected_sources)}, "
                f"got {sorted(declared_sources)}"
            )

        for marker in (
            "type: library.static",
            "platform: iOS",
            "PRODUCT_NAME: KeyHollowMediaNavigationAddOn",
            "SWIFT_STRICT_CONCURRENCY: complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES",
            "DEFINES_MODULE: YES",
            "SKIP_INSTALL: YES",
        ):
            if marker not in media_navigation_target:
                violations.append(
                    "project.yml: KeyHollowMediaNavigationAddOn is missing "
                    f"{marker!r}"
                )

        declared_dependencies = set(
            re.findall(
                r"(?m)^      - target: ([A-Za-z0-9_]+)\s*$",
                media_navigation_target,
            )
        )
        dependency_key_present = yaml_key_present(
            media_navigation_target, "dependencies"
        )
        dependency_alias_present = re.search(
            r"(?m)^[ \t]+<<\s*:",
            media_navigation_target,
        ) is not None
        if declared_dependencies or dependency_key_present or dependency_alias_present:
            violations.append(
                "project.yml: KeyHollowMediaNavigationAddOn must remain "
                "dependency-free with no dependency key or YAML merge alias; "
                "compose protected capabilities in the app "
                f"(found {sorted(declared_dependencies)})"
            )

    if app_target is not None:
        app_navigation_dependencies = re.findall(
            r"(?m)^      - target: KeyHollowMediaNavigationAddOn\s*$",
            app_target,
        )
        if len(app_navigation_dependencies) != 1:
            violations.append(
                "project.yml: KeyHollow must compose "
                "KeyHollowMediaNavigationAddOn exactly once"
            )

        app_navigation_exclusions = re.findall(
            r"(?m)^          - AddOns/MediaNavigation\s*$",
            app_target,
        )
        if len(app_navigation_exclusions) != 1:
            violations.append(
                "project.yml: KeyHollow must exclude AddOns/MediaNavigation "
                "exactly once so those sources compile only in the add-on"
            )

    media_navigation_tests_target = target_body(project, "KeyHollowTests")
    if media_navigation_tests_target is None:
        violations.append("project.yml: KeyHollowTests target is missing")
    else:
        test_navigation_wiring = re.findall(
            r"(?m)^      - target: KeyHollowMediaNavigationAddOn\s*$\n"
            r"^        link: false\s*$",
            media_navigation_tests_target,
        )
        if len(test_navigation_wiring) != 1:
            violations.append(
                "project.yml: KeyHollowTests must depend on "
                "KeyHollowMediaNavigationAddOn exactly once with link: false"
            )

    if project.count("        KeyHollowMediaNavigationAddOn: all") != 1:
        violations.append(
            "project.yml: KeyHollow scheme must build "
            "KeyHollowMediaNavigationAddOn exactly once"
        )

    media_navigation_sources = (
        {relative(path) for path in MEDIA_NAVIGATION_ROOT.rglob("*.swift")}
        if MEDIA_NAVIGATION_ROOT.exists()
        else set()
    )
    if media_navigation_sources != MEDIA_NAVIGATION_MODULE_FILES:
        violations.append(
            "KeyHollow/AddOns/MediaNavigation: source ownership changed; "
            f"expected {sorted(MEDIA_NAVIGATION_MODULE_FILES)}, "
            f"got {sorted(media_navigation_sources)}"
        )

    secure_preview_target = target_body(project, "KeyHollowSecurePreviewAddOn")
    if secure_preview_target is None:
        violations.append("project.yml: KeyHollowSecurePreviewAddOn target is missing")
    else:
        expected_sources = {"KeyHollow/AddOns/SecurePreview"}
        declared_sources = set(
            re.findall(r"(?m)^      - path: ([^\r\n]+)$", secure_preview_target)
        )
        if declared_sources != expected_sources:
            violations.append(
                "project.yml: KeyHollowSecurePreviewAddOn source ownership changed; "
                f"expected {sorted(expected_sources)}, got {sorted(declared_sources)}"
            )
        for marker in (
            "type: library.static",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES",
            "DEFINES_MODULE: YES",
            "SKIP_INSTALL: YES",
        ):
            if marker not in secure_preview_target:
                violations.append(
                    f"project.yml: KeyHollowSecurePreviewAddOn is missing {marker!r}"
                )
        if re.search(r"(?m)^    dependencies:\s*$", secure_preview_target):
            violations.append(
                "project.yml: KeyHollowSecurePreviewAddOn must remain dependency-free"
            )

    encrypted_video_target = target_body(project, "KeyHollowEncryptedVideoAddOn")
    encrypted_video_target_count = len(
        re.findall(r"(?m)^  KeyHollowEncryptedVideoAddOn:\s*$", project)
    )
    if encrypted_video_target is None:
        violations.append("project.yml: KeyHollowEncryptedVideoAddOn target is missing")
    else:
        if encrypted_video_target_count != 1:
            violations.append(
                "project.yml: expected exactly one KeyHollowEncryptedVideoAddOn "
                f"target, found {encrypted_video_target_count}"
            )

        expected_sources = {"KeyHollow/AddOns/EncryptedVideo"}
        declared_sources = set(
            re.findall(r"(?m)^      - path: ([^\r\n]+)$", encrypted_video_target)
        )
        if declared_sources != expected_sources:
            violations.append(
                "project.yml: KeyHollowEncryptedVideoAddOn source ownership changed; "
                f"expected {sorted(expected_sources)}, got {sorted(declared_sources)}"
            )

        for marker in (
            "type: library.static",
            "platform: iOS",
            "PRODUCT_NAME: KeyHollowEncryptedVideoAddOn",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES",
            "DEFINES_MODULE: YES",
            "SKIP_INSTALL: YES",
        ):
            if marker not in encrypted_video_target:
                violations.append(
                    f"project.yml: KeyHollowEncryptedVideoAddOn is missing {marker!r}"
                )

        declared_dependencies = set(
            re.findall(
                r"(?m)^      - target: ([A-Za-z0-9_]+)\s*$",
                encrypted_video_target,
            )
        )
        if (
            declared_dependencies
            or re.search(
                r"(?m)^    dependencies:\s*$",
                encrypted_video_target,
            )
        ):
            violations.append(
                "project.yml: KeyHollowEncryptedVideoAddOn must remain "
                "dependency-free; compose protected capabilities in the app "
                f"(found {sorted(declared_dependencies)})"
            )

    if app_target is not None:
        app_video_dependencies = re.findall(
            r"(?m)^      - target: KeyHollowEncryptedVideoAddOn\s*$",
            app_target,
        )
        if len(app_video_dependencies) != 1:
            violations.append(
                "project.yml: KeyHollow must compose "
                "KeyHollowEncryptedVideoAddOn exactly once"
            )

        app_video_exclusions = re.findall(
            r"(?m)^          - AddOns/EncryptedVideo\s*$",
            app_target,
        )
        if len(app_video_exclusions) != 1:
            violations.append(
                "project.yml: KeyHollow must exclude AddOns/EncryptedVideo "
                "exactly once so those sources compile only in the add-on"
            )

    tests_target = target_body(project, "KeyHollowTests")
    if tests_target is None:
        violations.append("project.yml: KeyHollowTests target is missing")
    else:
        test_video_wiring = re.findall(
            r"(?m)^      - target: KeyHollowEncryptedVideoAddOn\s*$\n"
            r"^        link: false\s*$",
            tests_target,
        )
        if len(test_video_wiring) != 1:
            violations.append(
                "project.yml: KeyHollowTests must depend on "
                "KeyHollowEncryptedVideoAddOn exactly once with link: false"
            )

    if project.count("        KeyHollowEncryptedVideoAddOn: all") != 1:
        violations.append(
            "project.yml: KeyHollow scheme must build "
            "KeyHollowEncryptedVideoAddOn exactly once"
        )

    encrypted_video_sources = (
        {relative(path) for path in ENCRYPTED_VIDEO_ROOT.rglob("*.swift")}
        if ENCRYPTED_VIDEO_ROOT.exists()
        else set()
    )
    if encrypted_video_sources != ENCRYPTED_VIDEO_MODULE_FILES:
        violations.append(
            "KeyHollow/AddOns/EncryptedVideo: source ownership changed; "
            f"expected {sorted(ENCRYPTED_VIDEO_MODULE_FILES)}, "
            f"got {sorted(encrypted_video_sources)}"
        )

    backup_verification_target = target_body(
        project,
        "KeyHollowBackupVerificationAddOn",
    )
    backup_verification_target_count = len(
        re.findall(r"(?m)^  KeyHollowBackupVerificationAddOn:\s*$", project)
    )
    if backup_verification_target is None:
        violations.append(
            "project.yml: KeyHollowBackupVerificationAddOn target is missing"
        )
    else:
        if backup_verification_target_count != 1:
            violations.append(
                "project.yml: expected exactly one "
                "KeyHollowBackupVerificationAddOn target, found "
                f"{backup_verification_target_count}"
            )

        expected_sources = {"KeyHollow/AddOns/BackupVerification"}
        declared_sources = set(
            re.findall(
                r"(?m)^      - path: ([^\r\n]+)$",
                backup_verification_target,
            )
        )
        if declared_sources != expected_sources:
            violations.append(
                "project.yml: KeyHollowBackupVerificationAddOn source ownership "
                f"changed; expected {sorted(expected_sources)}, "
                f"got {sorted(declared_sources)}"
            )

        for marker in (
            "type: library.static",
            "platform: iOS",
            "PRODUCT_NAME: KeyHollowBackupVerificationAddOn",
            "SWIFT_STRICT_CONCURRENCY: complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES",
            "DEFINES_MODULE: YES",
            "SKIP_INSTALL: YES",
        ):
            if marker not in backup_verification_target:
                violations.append(
                    "project.yml: KeyHollowBackupVerificationAddOn is missing "
                    f"{marker!r}"
                )

        if re.search(
            r"(?m)^    dependencies:\s*$",
            backup_verification_target,
        ):
            violations.append(
                "project.yml: KeyHollowBackupVerificationAddOn must remain "
                "dependency-free; compose protected capabilities in the app"
            )

    if app_target is not None:
        app_verification_dependencies = re.findall(
            r"(?m)^      - target: KeyHollowBackupVerificationAddOn\s*$",
            app_target,
        )
        if len(app_verification_dependencies) != 1:
            violations.append(
                "project.yml: KeyHollow must compose "
                "KeyHollowBackupVerificationAddOn exactly once"
            )

        app_verification_exclusions = re.findall(
            r"(?m)^          - AddOns/BackupVerification\s*$",
            app_target,
        )
        if len(app_verification_exclusions) != 1:
            violations.append(
                "project.yml: KeyHollow must exclude AddOns/BackupVerification "
                "exactly once so those sources compile only in the add-on"
            )

    if tests_target is not None:
        test_verification_wiring = re.findall(
            r"(?m)^      - target: KeyHollowBackupVerificationAddOn\s*$\n"
            r"^        link: false\s*$",
            tests_target,
        )
        if len(test_verification_wiring) != 1:
            violations.append(
                "project.yml: KeyHollowTests must depend on "
                "KeyHollowBackupVerificationAddOn exactly once with link: false"
            )

    if project.count("        KeyHollowBackupVerificationAddOn: all") != 1:
        violations.append(
            "project.yml: KeyHollow scheme must build "
            "KeyHollowBackupVerificationAddOn exactly once"
        )

    backup_verification_sources = (
        {
            relative(path)
            for path in BACKUP_VERIFICATION_ROOT.rglob("*.swift")
        }
        if BACKUP_VERIFICATION_ROOT.exists()
        else set()
    )
    if backup_verification_sources != BACKUP_VERIFICATION_MODULE_FILES:
        violations.append(
            "KeyHollow/AddOns/BackupVerification: source ownership changed; "
            f"expected {sorted(BACKUP_VERIFICATION_MODULE_FILES)}, "
            f"got {sorted(backup_verification_sources)}"
        )

    general_file_models_source = (
        SOURCE_ROOT / "AddOns" / "GeneralFileSupport" / "GeneralFileModels.swift"
    ).read_text(encoding="utf-8")
    general_file_store_source = (
        SOURCE_ROOT / "AddOns" / "GeneralFileSupport" / "VaultGeneralFileStore.swift"
    ).read_text(encoding="utf-8")
    general_file_adapter_source = (
        SOURCE_ROOT / "UI" / "VaultGeneralFilePresentation.swift"
    ).read_text(encoding="utf-8")
    session_source = (
        SOURCE_ROOT / "Session" / "VaultSession.swift"
    ).read_text(encoding="utf-8")

    if "consuming consumer: (Data) throws -> Void" not in general_file_models_source:
        violations.append(
            "KeyHollow/AddOns/GeneralFileSupport/GeneralFileModels.swift: "
            "plaintext export must retain a fixed-Void consuming access boundary"
        )

    prepare_export_start = general_file_store_source.find(
        "public func prepareExport("
    )
    prepare_export_end = general_file_store_source.find(
        "public func discardExport(", prepare_export_start
    )
    prepare_export_source = general_file_store_source[
        prepare_export_start:prepare_export_end
    ]
    consuming_open_position = prepare_export_source.find(
        "try access.open(ciphertext, for: .file(record.id), consuming:"
    )
    protected_write_position = prepare_export_source.find(
        "try secureWrite(plaintext, to: target)"
    )
    if not (
        prepare_export_start >= 0
        and prepare_export_end > prepare_export_start
        and 0 <= consuming_open_position < protected_write_position
        and "try Task.checkCancellation()" in prepare_export_source[
            protected_write_position:
        ]
        and re.search(
            r"\blet\s+plaintext\s*=\s*try\s+access\.open\s*\(",
            prepare_export_source,
        ) is None
    ):
        violations.append(
            "KeyHollow/AddOns/GeneralFileSupport/VaultGeneralFileStore.swift: "
            "authenticated export validation and protected plaintext writing "
            "must remain inside the revocation-fenced consuming boundary"
        )

    for required in (
        "capability.consumeOpenedScopedData(",
        "consuming consumer: (Data) throws -> Void",
    ):
        if required not in general_file_adapter_source:
            violations.append(
                "KeyHollow/UI/VaultGeneralFilePresentation.swift: session "
                f"general-file access is missing export fence {required!r}"
            )

    scoped_consumer_start = session_source.find(
        "func consumeOpenedScopedData("
    )
    scoped_consumer_end = session_source.find(
        "private func scopedKey(", scoped_consumer_start
    )
    scoped_consumer_source = session_source[
        scoped_consumer_start:scoped_consumer_end
    ]
    if not (
        scoped_consumer_start >= 0
        and scoped_consumer_end > scoped_consumer_start
        and scoped_consumer_source.find("try withKey { vaultKey in")
        < scoped_consumer_source.find("let plaintext = try CryptoBox.open(")
        < scoped_consumer_source.find("try consumer(plaintext)")
    ):
        violations.append(
            "KeyHollow/Session/VaultSession.swift: scoped plaintext must be "
            "opened and synchronously consumed while the capability lock is held"
        )

    awaited_sensitive_start = session_source.find(
        "func performSensitiveTask("
    )
    awaited_sensitive_end = session_source.find(
        "func cancelSensitiveTask(", awaited_sensitive_start
    )
    awaited_sensitive_source = session_source[
        awaited_sensitive_start:awaited_sensitive_end
    ]
    sensitive_register_position = awaited_sensitive_source.find(
        "sensitiveTasks[id] = task"
    )
    sensitive_await_position = awaited_sensitive_source.find(
        "await task.value"
    )
    if not (
        awaited_sensitive_start >= 0
        and awaited_sensitive_end > awaited_sensitive_start
        and 0 <= sensitive_register_position < sensitive_await_position
        and "await withTaskCancellationHandler" in awaited_sensitive_source
        and "task.cancel()" in awaited_sensitive_source
    ):
        violations.append(
            "KeyHollow/Session/VaultSession.swift: awaited sensitive work "
            "must register before execution, propagate cancellation, and await cleanup"
        )

    cancel_and_wait_start = session_source.find(
        "func cancelSensitiveTaskAndWait("
    )
    protected_task_start = session_source.find(
        "func startProtectedTask(",
        cancel_and_wait_start,
    )
    cancel_and_wait_source = session_source[
        cancel_and_wait_start:protected_task_start
    ]
    if not (
        cancel_and_wait_start >= 0
        and protected_task_start > cancel_and_wait_start
        and 0 <= cancel_and_wait_source.find("task.cancel()")
        < cancel_and_wait_source.find("await task.value")
    ):
        violations.append(
            "KeyHollow/Session/VaultSession.swift: per-task dismissal must "
            "cancel and then await terminal cleanup"
        )

    lock_start = session_source.find("func lock() -> VaultSessionLockBarrier")
    lock_end = session_source.find("func lockAndWait() async", lock_start)
    lock_source = session_source[lock_start:lock_end]
    lock_and_wait_source = session_source[lock_end:]
    if not (
        "struct VaultSessionLockBarrier: Sendable" in session_source
        and "func wait() async" in session_source
        and lock_start >= 0
        and lock_end > lock_start
        and lock_source.find("capability?.revoke()")
        < lock_source.find("tasks.forEach { $0.cancel() }")
        < lock_source.find("return VaultSessionLockBarrier(tasks: tasks)")
        and "let barrier = lock()" in lock_and_wait_source
        and "await barrier.wait()" in lock_and_wait_source
    ):
        violations.append(
            "KeyHollow/Session/VaultSession.swift: locking must revoke and "
            "cancel synchronously, return captured task handles, and expose an "
            "awaitable terminal-cleanup barrier"
        )

    app_lifecycle_source = (
        SOURCE_ROOT / "App" / "KeyHollowApp.swift"
    ).read_text(encoding="utf-8")
    for required in (
        "lockForLifecycleTransition()",
        "let barrier = session.lock()",
        "UIApplication.shared.beginBackgroundTask(",
        "await self.barrier.wait()",
        "UIApplication.shared.endBackgroundTask(",
    ):
        if required not in app_lifecycle_source:
            violations.append(
                "KeyHollow/App/KeyHollowApp.swift: background locking must "
                f"protect and await sensitive cleanup; missing {required!r}"
            )

    secure_preview_source = (
        SOURCE_ROOT / "AddOns" / "SecurePreview" / "VaultSecureImagePreview.swift"
    ).read_text(encoding="utf-8")
    secure_preview_executable = swift_executable_text(secure_preview_source)
    for required in (
        "public actor VaultSecureImageProcessor",
        "kCGImageSourceShouldCacheImmediately: true",
        "preview?.displayImage.image",
        "fileprivate init(image: UIImage)",
    ):
        if required not in secure_preview_executable:
            violations.append(
                "KeyHollow/AddOns/SecurePreview/VaultSecureImagePreview.swift: "
                f"prepared-image performance boundary is missing {required!r}"
            )
    for obsolete in (
        "UIImage(data: preview.originalData)",
        "UIImage(data: preview?.originalData)",
        "public init(image: UIImage)",
        "public init(id: UUID, displayName: String, originalData: Data)",
    ):
        if obsolete in secure_preview_executable:
            violations.append(
                "KeyHollow/AddOns/SecurePreview/VaultSecureImagePreview.swift: "
                "full-resolution image decoding returned to the SwiftUI view body"
            )

    gallery_grid_source = (
        SOURCE_ROOT / "UI" / "VaultGalleryGridView.swift"
    ).read_text(encoding="utf-8")
    for required in (
        "folders: [VaultGalleryFolder]",
        "items: [VaultGalleryPresentationItem]",
        "(VaultGalleryFolder) -> FolderContent",
        "(VaultGalleryPresentationItem) -> ItemContent",
    ):
        if required not in gallery_grid_source:
            violations.append(
                "KeyHollow/UI/VaultGalleryGridView.swift: source-neutral UI "
                f"contract is missing {required!r}"
            )
    for bypass in (
        "Folder: Identifiable",
        "Item: Identifiable",
        "VaultPhotoRecord",
        "VaultGeneralFileRecord",
        "VaultFolderRecord",
    ):
        if bypass in gallery_grid_source:
            violations.append(
                "KeyHollow/UI/VaultGalleryGridView.swift: storage-model bypass "
                f"entered the grid contract ({bypass})"
            )

    for required in (
        "spacing: VaultGalleryTileMetrics.gridSpacing",
        "alignment: .top",
        "count: VaultGalleryTileMetrics.columnCount",
    ):
        if required not in gallery_grid_source:
            violations.append(
                "KeyHollow/UI/VaultGalleryGridView.swift: normalized top-aligned "
                f"grid contract is missing {required!r}"
            )

    folder_tile_source = (
        SOURCE_ROOT / "UI" / "VaultFolderPresentationViews.swift"
    ).read_text(encoding="utf-8")
    if "VaultGalleryTileSurface(" not in folder_tile_source:
        violations.append(
            "KeyHollow/UI/VaultFolderPresentationViews.swift: folder tiles must "
            "use the shared normalized gallery tile surface"
        )
    if "GeometryReader" in folder_tile_source:
        violations.append(
            "KeyHollow/UI/VaultFolderPresentationViews.swift: variable folder "
            "geometry returned"
        )

    gallery_tile_source = (
        SOURCE_ROOT / "UI" / "VaultGalleryTilePresentation.swift"
    ).read_text(encoding="utf-8")
    if ".background(Color(uiColor: .secondarySystemBackground))" not in gallery_tile_source:
        violations.append(
            "KeyHollow/UI/VaultGalleryTilePresentation.swift: tile metadata must "
            "retain its non-blurring system background"
        )
    if ".background(.ultraThinMaterial)" in gallery_tile_source:
        violations.append(
            "KeyHollow/UI/VaultGalleryTilePresentation.swift: per-tile live blur "
            "returned to the scrolling grid"
        )

    file_ingress_source = (
        SOURCE_ROOT / "AddOns" / "FileRecognition" / "VaultFileRecognizer.swift"
    ).read_text(encoding="utf-8")
    if re.search(
        r"public\s+init\s*\(\s*url:\s*URL,\s*displayName:\s*String,\s*byteCount:",
        file_ingress_source,
    ):
        violations.append(
            "KeyHollow/AddOns/FileRecognition/VaultFileRecognizer.swift: "
            "staged-vault cleanup capabilities must not be publicly constructible"
        )
    if not contains_in_order(
        file_ingress_source,
        (
            "private let cleanupLease: StagedVaultFileCleanupLease",
            "directoryLease: VaultFileIngressDirectoryLease",
            "cleanupLease = StagedVaultFileCleanupLease(directoryLease: directoryLease)",
            "public func discard(using fileManager: FileManager = .default)",
            "try? discardChecked(using: fileManager)",
            "public func discardChecked(using fileManager: FileManager = .default) throws",
            "try cleanupLease.discardChecked(using: fileManager)",
            "private final class StagedVaultFileCleanupLease: @unchecked Sendable",
            "private let cleanupRoot: URL",
            "private var directoryLease: VaultFileIngressDirectoryLease?",
            "deinit",
            "try? discardChecked()",
            "func discardChecked(using fileManager: FileManager = .default) throws",
            "guard ownsCleanupRoot else { return }",
            "try fileManager.removeItem(at: cleanupRoot)",
            "cocoaError.code == NSFileNoSuchFileError",
            "ownsCleanupRoot = false",
            "directoryLease = nil",
            "fileprivate final class VaultFileIngressDirectoryRegistry: @unchecked Sendable",
            "try removeAbandonedItems(",
            "preserving: activeIdentifiersByRoot[rootKey] ?? []",
            "guard Self.isCanonicalIngressIdentifier(name)",
            "!activeIdentifiers.contains(name)",
            "let itemValues = try itemURL.resourceValues(forKeys:",
            "guard itemValues.isDirectory == true",
            "itemValues.isSymbolicLink != true",
            "try fileManager.removeItem(at: itemURL)",
            "let directoryLease = try VaultFileIngressDirectoryRegistry.shared.acquire(",
            "let importRoot = directoryLease.directoryURL",
            "directoryLease: directoryLease",
        ),
    ):
        violations.append(
            "KeyHollow/AddOns/FileRecognition/VaultFileRecognizer.swift: "
            "checked staged-vault cleanup must remain idempotent and bound to "
            "the ingress-owned lease root"
        )
    if "try? fileManager.removeItem(at: cleanupRoot)" in file_ingress_source:
        violations.append(
            "KeyHollow/AddOns/FileRecognition/VaultFileRecognizer.swift: "
            "best-effort cleanup must delegate to discardChecked instead of "
            "bypassing the checked cleanup contract"
        )
    if "removeItem(at: url.deletingLastPathComponent())" in file_ingress_source:
        violations.append(
            "KeyHollow/AddOns/FileRecognition/VaultFileRecognizer.swift: "
            "staged-vault cleanup must not derive a deletion target from a public URL"
        )

    payload_source = (
        SOURCE_ROOT / "Transfer" / "PortableArchivePayload.swift"
    ).read_text(encoding="utf-8")
    extractor_start = payload_source.find("final class PortableArchivePayloadExtractor")
    extractor_end = payload_source.find(
        "private func decodePayloadUInt32",
        extractor_start,
    )
    extractor_source = payload_source[extractor_start:extractor_end]
    if not contains_in_order(
        extractor_source,
        (
            "deinit",
            "try? discardChecked()",
            "func discardChecked(",
            "guard !relinquishedStagingDirectory else { return }",
            "try removeItem(stagingURL)",
            "cocoaError.code == NSFileNoSuchFileError",
            "relinquishedStagingDirectory = true",
            "private func failAndCleanUp()",
            "try? discardChecked()",
        ),
    ):
        violations.append(
            "KeyHollow/Transfer/PortableArchivePayload.swift: partial archive "
            "extraction must retain ownership after failed checked cleanup and "
            "retry cleanup on best-effort failure paths"
        )
    if "try? FileManager.default.removeItem(at: stagingURL)" in extractor_source:
        violations.append(
            "KeyHollow/Transfer/PortableArchivePayload.swift: extractor cleanup "
            "must delegate to the checked ownership boundary"
        )

    transfer_coordinator_source = (
        SOURCE_ROOT / "Transfer" / "EncryptedVaultTransferCoordinator.swift"
    ).read_text(encoding="utf-8")
    working_registry_start = transfer_coordinator_source.find(
        "fileprivate final class PortableArchiveWorkingDirectoryRegistry"
    )
    working_registry_end = transfer_coordinator_source.find(
        "/// Validation results are immutable.",
        working_registry_start,
    )
    working_registry_source = transfer_coordinator_source[
        working_registry_start:working_registry_end
    ]
    if not contains_in_order(
        working_registry_source,
        (
            "guard Self.isCanonicalWorkingIdentifier(name)",
            "!activeIdentifiers.contains(name)",
            "let itemValues = try itemURL.resourceValues(forKeys:",
            "guard itemValues.isDirectory == true",
            "itemValues.isSymbolicLink != true",
            "try FileManager.default.removeItem(at: itemURL)",
        ),
    ):
        violations.append(
            "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: stale "
            "working cleanup must remove only inactive canonical real directories"
        )
    export_start = transfer_coordinator_source.find("public func exportVault(")
    restore_start = transfer_coordinator_source.find(
        "public func stageAndValidateRestore(",
        export_start,
    )
    export_source = transfer_coordinator_source[export_start:restore_start]
    validation_end = transfer_coordinator_source.find(
        "/// Authenticates an archive through the restore validator",
        restore_start,
    )
    restore_source = transfer_coordinator_source[restore_start:validation_end]
    if not contains_in_order(
        restore_source,
        (
            "let extractor = try PortableArchivePayloadExtractor(",
            "try extractor.discardChecked()",
            "throw EncryptedVaultTransferError.archiveCleanupFailed",
            "try stagedPayload.discardChecked()",
            "throw EncryptedVaultTransferError.archiveCleanupFailed",
        ),
    ):
        violations.append(
            "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: restore "
            "validation must surface failed checked cleanup before and after "
            "payload extraction completes"
        )
    if (
        "defer { verified.discard() }" in export_source
        or export_source.count("try verified.discardChecked()") < 2
        or export_source.find("try verified.discardChecked()")
        > export_source.find("exportSucceeded = true")
    ):
        violations.append(
            "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: export "
            "verification staging must be removed through checked cleanup on "
            "both failure and success paths before success is published"
        )
    verification_start = transfer_coordinator_source.find(
        "public func verifyArchive("
    )
    verification_end = transfer_coordinator_source.find(
        "static func validate(",
        verification_start,
    )
    verification_source = transfer_coordinator_source[
        verification_start:verification_end
    ]
    for required in (
        "public struct PortableVaultVerificationReport: Equatable, Sendable",
        "public func verifyArchive(",
        "let restore = try await stageAndValidateRestore(",
        "restore.discard()",
        "try discardStaging(restore)",
        "try Task.checkCancellation()",
        "report = PortableVaultVerificationReport(",
        "return report",
    ):
        if required not in transfer_coordinator_source:
            violations.append(
                "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: "
                f"verify-and-discard facade is missing {required!r}"
            )
    if not (
        verification_start >= 0
        and verification_end > verification_start
        and verification_source.find("stageAndValidateRestore(")
        < verification_source.find("restore.discard()")
        < verification_source.find("try discardStaging(restore)")
        < verification_source.find("return report")
    ):
        violations.append(
            "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: "
            "backup verification must validate, arm cleanup, and only then "
            "publish a sanitized report"
        )
    if verification_source.count("try discardStaging(restore)") < 2:
        violations.append(
            "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: "
            "verification cancellation and success must both cross the checked "
            "staging-cleanup boundary"
        )
    for forbidden_verification_capability in (
        "PortableVaultCredentialStoring",
        "VaultStore",
        "PortableVaultRestoreTransactionJournal",
        "installValidatedPortableVault(",
        "commit(",
    ):
        if forbidden_verification_capability in verification_source:
            violations.append(
                "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: "
                "verify-and-discard facade gained persistence/install capability "
                f"{forbidden_verification_capability}"
            )
    for forbidden_result_field in (
        "vaultID:",
        "vaultKey:",
        "payload:",
        "staging",
        "archiveURL:",
    ):
        report_start = transfer_coordinator_source.find(
            "public struct PortableVaultVerificationReport"
        )
        report_end = transfer_coordinator_source.find("}\n", report_start)
        report_source = transfer_coordinator_source[report_start:report_end]
        if forbidden_result_field in report_source:
            violations.append(
                "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: "
                "sanitized verification report exposes forbidden field "
                f"{forbidden_result_field!r}"
            )

    verification_ui_source = (
        SOURCE_ROOT / "UI" / "BackupVerificationCenterView.swift"
    ).read_text(encoding="utf-8")
    for required in (
        "import KeyHollowBackupVerificationAddOn",
        "import KeyHollowFileRecognitionAddOn",
        "import KeyHollowTransferCore",
        "KHVaultFileIngress().stageIfRecognized(",
        "session.startProtectedTask",
        "EncryptedVaultTransferCoordinator().verifyArchive(",
        "BackupVerificationReport(",
        "try selectedArchive.discardChecked()",
        "throw BackupVerificationCoordinatorError.ingressCleanupFailed",
        "discardSelectedArchive()",
        "private func discardSelectedArchiveChecked() throws",
        "private static func discardChecked(_ archive: StagedVaultFile) -> Bool",
        "activePickerRequestID",
        "filePickerDidDismiss",
        "Task.detached(priority: .userInitiated)",
        "await session.cancelSensitiveTaskAndWait(taskID)",
    ):
        if required not in verification_ui_source:
            violations.append(
                "KeyHollow/UI/BackupVerificationCenterView.swift: "
                f"read-only verification composition is missing {required!r}"
            )

    verification_action_start = verification_ui_source.find(
        "private func verifyBackup()"
    )
    verification_action_end = verification_ui_source.find(
        "private func finishProtectedOperation(",
        verification_action_start,
    )
    verification_action_source = verification_ui_source[
        verification_action_start:verification_action_end
    ]
    if not (
        verification_action_start >= 0
        and verification_action_end > verification_action_start
        and 0
        <= verification_action_source.find(
            "EncryptedVaultTransferCoordinator().verifyArchive("
        )
        < verification_action_source.find(
            "let sanitizedReport = BackupVerificationReport("
        )
        < verification_action_source.find("try selectedArchive.discardChecked()")
        < verification_action_source.find("guard activeOperationID == operationID")
        < verification_action_source.find("report = sanitizedReport")
    ):
        violations.append(
            "KeyHollow/UI/BackupVerificationCenterView.swift: successful backup "
            "verification must authenticate, sanitize, complete checked ingress "
            "cleanup, and only then publish the report"
        )
    for forbidden_install_capability in (
        "stageAndValidateRestore(",
        "installValidatedPortableVault(",
        "installRestore(",
        "completeUnlock(",
        "ValidatedPortableVaultRestore",
        "PortableVaultRestoreInstaller",
        "PortableVaultRestoreTransactionJournal",
        "PortableVaultCredentialStoring",
        "VaultUnlockService",
        "preparePortableArchive(",
        "FileManager",
        "Data(contentsOf:",
        "copyItem(",
        "moveItem(",
        "removeItem(",
    ):
        if forbidden_install_capability in verification_ui_source:
            violations.append(
                "KeyHollow/UI/BackupVerificationCenterView.swift: read-only "
                "verification UI gained install/unlock capability "
                f"{forbidden_install_capability}"
            )

    import_ui_source = (
        SOURCE_ROOT / "UI" / "EncryptedVaultImportView.swift"
    ).read_text(encoding="utf-8")
    import_validation_start = import_ui_source.find(
        "private func validateArchive()"
    )
    import_install_start = import_ui_source.find(
        "private func installRestore()",
        import_validation_start,
    )
    import_validation_source = import_ui_source[
        import_validation_start:import_install_start
    ]
    if (
        import_validation_start < 0
        or import_install_start <= import_validation_start
        or "EncryptedVaultTransferCoordinator().verifyArchive("
        not in import_validation_source
        or "stageAndValidateRestore(" in import_validation_source
    ):
        violations.append(
            "KeyHollow/UI/EncryptedVaultImportView.swift: pre-install summary "
            "must use the verify-and-discard facade; only the final installation "
            "step may receive ValidatedPortableVaultRestore"
        )

    for file in swift_files:
        path = relative(file)
        source = file.read_text(encoding="utf-8")
        imported = imports(source)

        for alternate_import in noncanonical_swift_imports(source):
            violations.append(
                f"{path}: noncanonical Swift import syntax is forbidden: "
                f"{alternate_import}"
            )

        if (
            path.endswith("VaultVideoThumbnailCoordinator.swift")
            or "VaultVideoThumbnailCoordinator" in source
        ):
            violations.append(
                f"{path}: video thumbnails must use the shared "
                "VaultGeneralFileThumbnailPipeline full-payload lane, not a "
                "standalone coordinator or semaphore"
            )

        if path.startswith("KeyHollow/AddOns/") and "KeyHollow" in imported:
            violations.append(
                f"{path}: add-on module imports the application target instead of a narrow interface"
            )

        if path.startswith(FILE_RECOGNITION_PREFIX):
            unexpected = imported - {"Foundation"}
            if unexpected:
                violations.append(
                    f"{path}: file-recognition add-on imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path.startswith(BACKUP_VERIFICATION_PREFIX):
            expected_imports = BACKUP_VERIFICATION_IMPORTS.get(path)
            if expected_imports is None or imported != expected_imports:
                violations.append(
                    f"{path}: backup-verification imports changed; expected "
                    f"{sorted(expected_imports or set())}, got {sorted(imported)}"
                )

            for forbidden_capability in (
                "VaultSession",
                "VaultUnlockService",
                "VaultAccessCapability",
                "VaultPhotoRecord",
                "VaultPhotoStore",
                "VaultGeneralFileRecord",
                "VaultGeneralFileStore",
                "VaultFolderRecord",
                "VaultFolderPresentationStore",
                "PortableArchiveCredential",
                "ValidatedPortableVaultRestore",
                "EncryptedVaultTransferCoordinator",
                "KHVaultFileIngress",
                "StagedVaultFile",
                "CryptoBox",
                "SymmetricKey",
                "FileManager",
                "FileHandle",
                "URLSession",
                "Data(contentsOf:",
                "startAccessingSecurityScopedResource",
                "stageAndValidateRestore(",
                "installValidatedPortableVault(",
            ):
                if forbidden_capability in source:
                    violations.append(
                        f"{path}: backup-verification add-on directly references "
                        f"protected capability {forbidden_capability}"
                    )

        if (
            "startAccessingSecurityScopedResource" in source
            and not path.startswith(SECURITY_SCOPED_INGRESS_PREFIXES)
        ):
            violations.append(
                f"{path}: security-scoped file access must remain inside an "
                "approved file-ingress add-on"
            )

        if (
            "KeyHollowPortableImports" in source
            and not path.startswith(FILE_RECOGNITION_PREFIX)
        ):
            violations.append(
                f"{path}: incoming vault staging must remain inside the "
                "file-recognition add-on"
            )

        if path in CRYPTO_MODULE_FILES or path.startswith(CRYPTO_MODULE_PREFIXES):
            unexpected = imported - {"CryptoKit", "Foundation"}
            if unexpected:
                violations.append(
                    f"{path}: crypto module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in VAULT_MODULE_FILES:
            unexpected = imported - {
                "CryptoKit",
                "Foundation",
                "KeyHollowCryptoCore",
                "Security",
            }
            if unexpected:
                violations.append(
                    f"{path}: vault module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in PHOTO_MODULE_FILES:
            unexpected = imported - {
                "CryptoKit",
                "Foundation",
                "KeyHollowCryptoCore",
            }
            if unexpected:
                violations.append(
                    f"{path}: photo-storage module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in PHOTOS_ADAPTER_FILES:
            unexpected = imported - {
                "Foundation",
                "Photos",
                "PhotosUI",
                "UIKit",
            }
            if unexpected:
                violations.append(
                    f"{path}: Photos adapter imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in TRANSFER_MODULE_FILES:
            unexpected = imported - {
                "CryptoKit",
                "Foundation",
                "KeyHollowCryptoCore",
                "KeyHollowPhotoCore",
                "KeyHollowVaultCore",
                "Security",
            }
            if unexpected:
                violations.append(
                    f"{path}: transfer module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in GALLERY_UI_MODULE_FILES:
            unexpected = imported - {
                "Foundation",
                "SwiftUI",
                "UIKit",
            }
            if unexpected:
                violations.append(
                    f"{path}: gallery UI imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )
            for forbidden_symbol in (
                "VaultSession",
                "VaultUnlockService",
                "VaultPhotoRecord",
                "VaultPhotoStore",
                "VaultGeneralFileRecord",
                "VaultGeneralFileStore",
                "VaultFolderRecord",
                "VaultFolderPresentationStore",
                "EncryptedVaultTransferCoordinator",
                "SymmetricKey",
                "URLSession",
            ):
                if re.search(rf"\b{forbidden_symbol}\b", source):
                    violations.append(
                        f"{path}: gallery UI directly references protected "
                        f"capability {forbidden_symbol}"
                    )

        if path.startswith(MEDIA_NAVIGATION_PREFIX):
            media_navigation_comment_free = swift_without_comments(source)
            media_navigation_executable = swift_executable_text(source)
            expected_imports = MEDIA_NAVIGATION_IMPORTS.get(path)
            if expected_imports is None or imported != expected_imports:
                violations.append(
                    f"{path}: media-navigation imports changed; expected "
                    f"{sorted(expected_imports or set())}, got {sorted(imported)}"
                )

            for forbidden_symbol in (
                "VaultSession",
                "VaultUnlockService",
                "VaultAccessCapability",
                "VaultPhotoRecord",
                "VaultPhotoStore",
                "VaultGeneralFileRecord",
                "VaultGeneralFileStore",
                "VaultFolderRecord",
                "VaultFolderPresentationStore",
                "EncryptedVaultTransferCoordinator",
                "CryptoBox",
                "SymmetricKey",
                "FileManager",
                "FileHandle",
                "URLSession",
                "startAccessingSecurityScopedResource",
                "originalData",
                "plaintext",
                "ciphertext",
                "fileURL",
            ):
                if re.search(
                    rf"\b{re.escape(forbidden_symbol)}\b",
                    media_navigation_comment_free,
                ):
                    violations.append(
                        f"{path}: media-navigation add-on directly references "
                        f"protected capability {forbidden_symbol}"
                    )

            for forbidden_pattern, forbidden_name in (
                (r"\b(?:Data|URL)\s*\(", "payload/URL construction"),
                (
                    r":\s*(?:Data|URL)(?:[?!<\[\],\s\)])",
                    "payload/URL storage or parameter",
                ),
                (r"->\s*(?:Data|URL)\b", "payload/URL return value"),
            ):
                if re.search(forbidden_pattern, media_navigation_comment_free):
                    violations.append(
                        f"{path}: media-navigation add-on exposes "
                        f"{forbidden_name} instead of immutable metadata"
                    )

            if path.endswith("VaultMediaNavigationModels.swift"):
                for required in (
                    "public enum VaultMediaNavigationSource",
                    "public let source: VaultMediaNavigationSource",
                    "public let rawValue: UUID",
                    "var seenIDs = Set<VaultMediaNavigationID>()",
                    "case duplicateItemID(VaultMediaNavigationID)",
                    "case selectionNotFound(VaultMediaNavigationID)",
                    "guard items.indices.contains(destinationIndex) else { return nil }",
                    "guard !remainingItems.isEmpty else { return nil }",
                    "selectedIndex: min(removedIndex, remainingItems.count - 1)",
                    "public var accessibilityPosition: String",
                ):
                    if required not in media_navigation_executable:
                        violations.append(
                            f"{path}: typed, immutable, non-wrapping media queue "
                            f"is missing {required!r}"
                        )

            if path.endswith("VaultMediaNavigationPager.swift"):
                for required in (
                    "private let isNavigationEnabled: Bool",
                    "isNavigationEnabled: Bool = true",
                    "self.isNavigationEnabled = isNavigationEnabled",
                    "activeContent(queue.currentItem)",
                    ".id(queue.currentItem.id)",
                    ".accessibilityAdjustableAction",
                    "handleDrag(value, viewportHeight: geometry.size.height)",
                    "isAvailable: queue.canNavigatePrevious",
                    "isAvailable: queue.canNavigateNext",
                    "isAvailable: Bool",
                    "videoControlExclusionMinimumHeight: CGFloat = 140",
                    "videoControlExclusionHeightRatio: CGFloat = 0.24",
                ):
                    if required not in media_navigation_executable:
                        violations.append(
                            f"{path}: active-only, busy-aware media pager is missing "
                            f"{required!r}"
                        )

                pager_body = swift_block_body(
                    source,
                    "public struct VaultMediaNavigationPager<ActiveContent: View>: View",
                )
                drag_body = swift_block_body(
                    pager_body or "",
                    "private func handleDrag(",
                )
                navigate_body = swift_block_body(
                    pager_body or "",
                    "private func navigate(_ direction: VaultMediaNavigationDirection)",
                )
                navigation_button_body = swift_block_body(
                    pager_body or "",
                    "private func navigationButton(",
                )
                if not (
                    pager_body is not None
                    and pager_body.count("private func navigationButton(") == 1
                    and pager_body.count("isAvailable: Bool") == 1
                    and navigation_button_body is not None
                    and contains_in_order(
                        navigation_button_body,
                        (
                            "Button",
                            "navigate(direction)",
                            ".disabled(!isNavigationEnabled || !isAvailable)",
                        ),
                    )
                ):
                    violations.append(
                        f"{path}: both navigation arrows must share a button "
                        "implementation that disables selection while busy or "
                        "when the adjacent queue position is unavailable"
                    )
                if not (
                    pager_body is not None
                    and drag_body is not None
                    and contains_in_order(
                        drag_body,
                        (
                            "guard isNavigationEnabled else { return }",
                            "if queue.currentItem.kind == .video",
                            "let excludedHeight = max(",
                            "VaultMediaNavigationPagerMetrics.videoControlExclusionMinimumHeight",
                            "VaultMediaNavigationPagerMetrics.videoControlExclusionHeightRatio",
                            "guard value.startLocation.y < viewportHeight - excludedHeight else",
                            "let horizontalDistance = value.translation.width",
                            "let verticalDistance = value.translation.height",
                            "guard abs(horizontalDistance) >= VaultMediaNavigationPagerMetrics.minimumSwipeDistance",
                            "abs(horizontalDistance) > abs(verticalDistance)",
                            "VaultMediaNavigationPagerMetrics.horizontalDominanceRatio",
                            "navigate(horizontalDistance < 0 ? .next : .previous)",
                        ),
                    )
                    and drag_body.count(
                        "guard isNavigationEnabled else { return }"
                    ) == 1
                    and drag_body.count(
                        "guard value.startLocation.y < viewportHeight - excludedHeight else"
                    ) == 1
                ):
                    violations.append(
                        f"{path}: page drags must stop while media work is busy and "
                        "must reserve the lower native-video-control region before "
                        "evaluating a horizontal page gesture"
                    )

                if not (
                    navigate_body is not None
                    and contains_in_order(
                        navigate_body,
                        (
                            "guard isNavigationEnabled else { return }",
                            "guard let destination = queue.item(in: direction) else { return }",
                            "onSelectionChange(destination.id)",
                        ),
                    )
                    and navigate_body.count(
                        "guard isNavigationEnabled else { return }"
                    ) == 1
                ):
                    violations.append(
                        f"{path}: arrow, accessibility, and swipe navigation must "
                        "all enter one busy-aware, non-wrapping selection gate"
                    )
                for eager_page_path in (
                    "TabView(",
                    "ForEach(queue.items",
                    "queue.items.map",
                ):
                    if eager_page_path in media_navigation_executable:
                        violations.append(
                            f"{path}: pager must build only the active payload; "
                            f"found eager page path {eager_page_path!r}"
                        )

        if path.startswith(SECURE_PREVIEW_PREFIX):
            secure_preview_comment_free = swift_without_comments(source)
            secure_preview_file_executable = swift_executable_text(source)
            unexpected = imported - {
                "CoreFoundation",
                "Foundation",
                "ImageIO",
                "SwiftUI",
                "UIKit",
                "UniformTypeIdentifiers",
            }
            if unexpected:
                violations.append(
                    f"{path}: secure-preview add-on imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )
            for forbidden_symbol in (
                "VaultSession",
                "VaultUnlockService",
                "VaultPhotoRecord",
                "VaultPhotoStore",
                "VaultGeneralFileRecord",
                "VaultGeneralFileStore",
                "VaultFolderRecord",
                "VaultFolderPresentationStore",
                "EncryptedVaultTransferCoordinator",
                "SymmetricKey",
                "FileManager",
                "URLSession",
                "Data(contentsOf:",
            ):
                if forbidden_symbol in secure_preview_comment_free:
                    violations.append(
                        f"{path}: secure-preview add-on directly references protected "
                        f"capability {forbidden_symbol}"
                    )

            if path.endswith("VaultSecureImagePreview.swift"):
                surface_anchor = (
                    "public struct VaultSecureImageSurface: UIViewRepresentable"
                )
                surface_body = swift_block_body(
                    source,
                    surface_anchor,
                )
                make_coordinator_body = swift_block_body(
                    surface_body or "",
                    "public func makeCoordinator() -> Coordinator",
                )
                make_surface_body = swift_block_body(
                    surface_body or "",
                    "public func makeUIView(context: Context) -> UIImageView",
                )
                update_surface_body = swift_block_body(
                    surface_body or "",
                    "public func updateUIView(_ imageView: UIImageView, context: Context)",
                )
                dismantle_surface_body = swift_block_body(
                    surface_body or "",
                    "public static func dismantleUIView(",
                )
                coordinator_body = swift_block_body(
                    surface_body or "",
                    "public final class Coordinator",
                )
                attach_body = swift_block_body(
                    coordinator_body or "",
                    "fileprivate func attachIfAllowed() -> Bool",
                )
                release_body = swift_block_body(
                    coordinator_body or "",
                    "fileprivate func release()",
                )

                for required in (
                    "private let renderedImage: VaultSecureRenderedImage",
                    "private let onImageWillAttach: () -> Bool",
                    "private let onImageReleased: () -> Void",
                    "onImageWillAttach: @escaping () -> Bool = { true }",
                    "onImageReleased: @escaping () -> Void = {}",
                ):
                    if (
                        surface_body is None
                        or required not in secure_preview_file_executable
                        or required not in surface_body
                    ):
                        violations.append(
                            f"{path}: observable, rendered-image-only UIKit surface "
                            f"is missing {required!r}"
                        )

                if secure_preview_file_executable.count(surface_anchor) != 1:
                    violations.append(
                        f"{path}: expected exactly one VaultSecureImageSurface "
                        "declaration"
                    )

                if not (
                    make_coordinator_body is not None
                    and contains_in_order(
                        make_coordinator_body,
                        (
                            "Coordinator(",
                            "onImageWillAttach: onImageWillAttach",
                            "onImageReleased: onImageReleased",
                        ),
                    )
                ):
                    violations.append(
                        f"{path}: secure image surface must pass both lifecycle "
                        "callbacks into its UIKit coordinator"
                    )

                if not (
                    make_surface_body is not None
                    and contains_in_order(
                        make_surface_body,
                        (
                            "let imageView = UIImageView()",
                            "imageView.contentMode = .scaleAspectFit",
                            "if context.coordinator.attachIfAllowed()",
                            "imageView.image = renderedImage.image",
                            "return imageView",
                        ),
                    )
                    and make_surface_body.count(
                        "imageView.image = renderedImage.image"
                    ) == 1
                ):
                    violations.append(
                        f"{path}: UIKit image attachment must be approved before "
                        "the rendered image enters the presentation surface"
                    )

                if not (
                    update_surface_body is not None
                    and contains_in_order(
                        update_surface_body,
                        (
                            "imageView.image = context.coordinator.isAttached",
                            "? renderedImage.image",
                            ": nil",
                        ),
                    )
                ):
                    violations.append(
                        f"{path}: SwiftUI updates must not reattach a rendered image "
                        "after the surface lease has been rejected or released"
                    )

                if not (
                    dismantle_surface_body is not None
                    and contains_in_order(
                        dismantle_surface_body,
                        (
                            "imageView.image = nil",
                            "coordinator.release()",
                        ),
                    )
                    and dismantle_surface_body.count("imageView.image = nil") == 1
                    and dismantle_surface_body.count("coordinator.release()") == 1
                ):
                    violations.append(
                        f"{path}: dismantling must synchronously clear UIImageView "
                        "ownership before acknowledging surface release"
                    )

                if not (
                    attach_body is not None
                    and contains_in_order(
                        attach_body,
                        (
                            "guard !isAttached, onImageWillAttach() else { return false }",
                            "isAttached = true",
                            "return true",
                        ),
                    )
                    and attach_body.count("onImageWillAttach()") == 1
                    and release_body is not None
                    and contains_in_order(
                        release_body,
                        (
                            "guard isAttached else { return }",
                            "isAttached = false",
                            "onImageReleased()",
                        ),
                    )
                    and release_body.count("onImageReleased()") == 1
                ):
                    violations.append(
                        f"{path}: the surface coordinator must reject duplicate or "
                        "late attachment and emit exactly one release acknowledgement"
                    )

                surface_executable = surface_body or ""
                for forbidden_pattern, forbidden_name in (
                    (
                        r"\b(?:VaultSession|VaultUnlockService|VaultAccessCapability)\b",
                        "vault/session capability",
                    ),
                    (
                        r"\b(?:VaultPhotoStore|VaultGeneralFileStore|VaultFolderPresentationStore)\b",
                        "storage capability",
                    ),
                    (
                        r"\b(?:CryptoBox|SymmetricKey|FileManager|FileHandle|URLSession)\b",
                        "crypto, filesystem, or network capability",
                    ),
                    (
                        r"\b(?:Data|NSData|NSMutableData|CFData|URL|NSURL|InputStream|OutputStream|originalData|plaintext|ciphertext)\b",
                        "payload or location capability",
                    ),
                    (
                        r"\b(?:VaultSecureImagePreview|VaultSecurePreparedThumbnail|VaultSecureImageProcessor|VaultSecureImageDecoder|CGImageSource|CGImageDestination|PHPhotoLibrary|PHAsset|PhotoLibrarySaveService)\b",
                        "decode or persistence capability",
                    ),
                    (
                        r"\bstartAccessingSecurityScopedResource\b",
                        "security-scoped file access",
                    ),
                ):
                    if re.search(forbidden_pattern, surface_executable):
                        violations.append(
                            f"{path}: VaultSecureImageSurface gained forbidden "
                            f"{forbidden_name}"
                        )

        if path.startswith(ENCRYPTED_VIDEO_PREFIX):
            expected_imports = ENCRYPTED_VIDEO_IMPORTS.get(path)
            if expected_imports is None or imported != expected_imports:
                violations.append(
                    f"{path}: encrypted-video imports changed; expected "
                    f"{sorted(expected_imports or set())}, got {sorted(imported)}"
                )

            for forbidden_capability in (
                "VaultSession",
                "VaultUnlockService",
                "VaultPhotoRecord",
                "VaultPhotoStore",
                "VaultGeneralFileRecord",
                "VaultGeneralFileStore",
                "VaultFolderRecord",
                "VaultFolderPresentationStore",
                "EncryptedVaultTransferCoordinator",
                "CryptoBox",
                "SymmetricKey",
                "FileManager",
                "FileHandle",
                "URLSession",
                "Data(contentsOf:",
                "startAccessingSecurityScopedResource",
                "prepareExport(",
                "discardExport(",
            ):
                if forbidden_capability in source:
                    violations.append(
                        f"{path}: encrypted-video add-on directly references "
                        f"protected capability {forbidden_capability}"
                    )

            if path.endswith("VaultEncryptedVideoPolicy.swift"):
                for required in (
                    "maximumPlaybackByteCount: UInt64 = 100 * 1_024 * 1_024",
                    "maximumSourcePixelDimension: CGFloat = 8_192",
                    "maximumSourcePixelCount: CGFloat = 7_680 * 4_320",
                    'Set<String> = ["m4v", "mov", "mp4"]',
                    "fileURL.isFileURL",
                    "public func validatePlayable() async throws",
                    "try Task.checkCancellation()",
                    "asset.load(.isPlayable)",
                    "asset.loadTracks(withMediaType: .video)",
                    "track.load(.isSelfContained)",
                    "track.load(.isDecodable)",
                    "track.load(.naturalSize)",
                    "track.load(.preferredTransform)",
                    "track.load(.formatDescriptions)",
                    "CMVideoFormatDescriptionGetDimensions(",
                    "allowsSourceDimensions(",
                    "func makeRestrictedAsset() -> AVURLAsset",
                    "AVURLAssetReferenceRestrictionsKey",
                    "AVAssetReferenceRestrictions.forbidAll.rawValue",
                ):
                    if required not in source:
                        violations.append(
                            f"{path}: bounded, local, fail-closed playback "
                            f"policy is missing {required!r}"
                        )

            if path.endswith("VaultEncryptedVideoThumbnailRenderer.swift"):
                for required in (
                    "maximumPixelDimension = 512",
                    "maximumEncodedByteCount = 2 * 1_024 * 1_024",
                    "appliesPreferredTrackTransform = true",
                    "maximumSize = CGSize(",
                    "width <= maximumPixelDimension",
                    "height <= maximumPixelDimension",
                    "jpegData.count <= VaultEncryptedVideoThumbnailRenderer.maximumEncodedByteCount",
                    "try Task.checkCancellation()",
                    "withTaskCancellationHandler",
                    "cancelAllCGImageGeneration()",
                    "let asset = playback.makeRestrictedAsset()",
                ):
                    if required not in source:
                        violations.append(
                            f"{path}: bounded, cancellation-aware thumbnail "
                            f"renderer is missing {required!r}"
                        )

            if path.endswith("VaultEncryptedVideoPlayerView.swift"):
                for required in (
                    "AVPlayerItem(asset: playback.makeRestrictedAsset())",
                    "item.status",
                    "AVPlayerItem.failedToPlayToEndTimeNotification",
                    ".map { _ in () }",
                    "onPlayerWillAttach",
                    "onPlayerReleased",
                    "player.allowsExternalPlayback = false",
                    "player.usesExternalPlaybackWhileExternalScreenIsActive = false",
                    "controller.allowsPictureInPicturePlayback = false",
                    "controller.canStartPictureInPictureAutomaticallyFromInline = false",
                    "VaultRestrictedVideoPlayerView",
                ):
                    if required not in source:
                        violations.append(
                            f"{path}: reference-restricted playback, runtime "
                            f"failure handling, or release acknowledgement is missing {required!r}"
                        )
                if "AVPlayerItem(url:" in source:
                    violations.append(
                        f"{path}: URL-based player creation bypasses the "
                        "reference-restricted asset factory"
                    )
                if source.count("onPlayerReleased()") != 1:
                    violations.append(
                        f"{path}: the player release lease must be acknowledged "
                        "exactly once, after the monitoring routine returns"
                    )
                terminal_release = re.search(
                    r"let\s+didAcquirePlayerLease\s*=\s*await\s+"
                    r"installAndMonitorPlayer\s*\(\s*\).*?"
                    r"if\s+didAcquirePlayerLease\s*\{\s*"
                    r"(?:\/\/[^\n]*\n\s*)*onPlayerReleased\s*\(\s*\)",
                    source,
                    re.DOTALL,
                )
                if terminal_release is None:
                    violations.append(
                        f"{path}: release acknowledgement must occur only after "
                        "the player-monitoring routine has fully returned"
                    )

        leaked_ui = imported & UI_FRAMEWORKS
        if leaked_ui and not is_presentation(path) and path not in PHOTOS_ADAPTER_FILES:
            violations.append(
                f"{path}: UI/system-photo frameworks outside the presentation adapter: "
                f"{', '.join(sorted(leaked_ui))}"
            )

        leaked_remote = imported & REMOTE_SDKS
        if leaked_remote:
            violations.append(
                f"{path}: remote SDK entered the local-only app core: "
                f"{', '.join(sorted(leaked_remote))}"
            )

        is_core = path.startswith(CORE_PREFIXES) or path in CORE_PHOTO_FILES
        if is_core:
            leaked_addons = imported & addon_modules
            if leaked_addons:
                violations.append(
                    f"{path}: protected core imports add-on modules: "
                    f"{', '.join(sorted(leaked_addons))}"
                )

            for forbidden_symbol in (
                "PHPhotoLibrary",
                "PhotosPicker",
                "UIApplication",
                "UIViewController",
            ):
                if re.search(rf"\b{forbidden_symbol}\b", source):
                    violations.append(
                        f"{path}: core code directly references {forbidden_symbol}"
                    )

            if re.search(r"\bURLSession\b", source):
                violations.append(f"{path}: core code introduced a network session")

    gallery_file = SOURCE_ROOT / "Photos" / "VaultGalleryView.swift"
    gallery_source = gallery_file.read_text(encoding="utf-8")
    gallery_executable = swift_executable_text(gallery_source)
    image_preview_coordinator_file = (
        SOURCE_ROOT / "Photos" / "VaultImagePreviewCoordinator.swift"
    )
    if not image_preview_coordinator_file.is_file():
        violations.append(
            "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: app-owned "
            "image lifetime coordinator is missing"
        )
    else:
        image_preview_coordinator_source = (
            image_preview_coordinator_file.read_text(encoding="utf-8")
        )
        expected_image_coordinator_imports = {
            "Combine",
            "Foundation",
            "KeyHollowMediaNavigationAddOn",
            "KeyHollowSecurePreviewAddOn",
        }
        actual_image_coordinator_imports = imports(
            image_preview_coordinator_source
        )
        image_preview_coordinator_code = swift_without_comments(
            image_preview_coordinator_source
        )
        image_preview_coordinator_executable = swift_executable_text(
            image_preview_coordinator_source
        )
        if actual_image_coordinator_imports != expected_image_coordinator_imports:
            violations.append(
                "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: imports "
                f"changed; expected {sorted(expected_image_coordinator_imports)}, "
                f"got {sorted(actual_image_coordinator_imports)}"
            )

        for required in (
            "@Published private(set) var active: ActiveVaultImagePreview?",
            "private var generation: UInt64 = 0",
            "private var operation: PreviewOperation?",
            "typealias SurfaceReleaseWaitObserver = @Sendable () async -> Void",
            "let (operationGeneration, previousOperation) = beginNewGeneration()",
            "try await previousOperation.task.value",
            "try await withTaskCancellationHandler",
            "operation?.task.cancel()",
            "operation?.lifetime.finish()",
            "func dismissAndWait() async",
            "func imageWillAttach(_ id: VaultMediaNavigationID) -> Bool",
            "func imageDidRelease(_ id: VaultMediaNavigationID)",
            "await lifetime.wait()",
            "await lifetime.waitForSurfaceRelease()",
            "try Task.checkCancellation()",
            "private let lock = NSLock()",
            "private var isSurfaceAttached = false",
            "private var surfaceReleaseWaiters: [CheckedContinuation<Void, Never>] = []",
            "pendingWaiters.forEach { $0.resume() }",
        ):
            if required not in image_preview_coordinator_executable:
                violations.append(
                    "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: "
                    f"revocable image lifetime is missing {required!r}"
                )

        prepare_body = swift_block_body(
            image_preview_coordinator_source,
            "func prepare(",
        )
        image_will_attach_body = swift_block_body(
            image_preview_coordinator_source,
            "func imageWillAttach(_ id: VaultMediaNavigationID) -> Bool",
        )
        image_did_release_body = swift_block_body(
            image_preview_coordinator_source,
            "func imageDidRelease(_ id: VaultMediaNavigationID)",
        )
        run_body = swift_block_body(
            image_preview_coordinator_source,
            "private func run(",
        )
        lifetime_body = swift_block_body(
            image_preview_coordinator_source,
            "private final class VaultImagePreviewLifetime",
        )
        begin_surface_body = swift_block_body(
            lifetime_body or "",
            "func beginSurfaceUse() -> Bool",
        )
        end_surface_body = swift_block_body(
            lifetime_body or "",
            "func endSurfaceUse()",
        )
        wait_surface_body = swift_block_body(
            lifetime_body or "",
            "func waitForSurfaceRelease() async",
        )
        finish_lifetime_body = swift_block_body(
            lifetime_body or "",
            "func finish()",
        )

        if not (
            prepare_body is not None
            and contains_in_order(
                prepare_body,
                (
                    "let (operationGeneration, previousOperation) = beginNewGeneration()",
                    "if let previousOperation",
                    "try await previousOperation.task.value",
                    "try requireCurrent(operationGeneration)",
                    "let lifetime = VaultImagePreviewLifetime(",
                    "let task: Task<Void, Error> = Task",
                    "operation = PreviewOperation(",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: image "
                "replacement must await the prior operation's terminal surface "
                "release before it constructs or publishes a new image lifetime"
            )

        if not (
            image_will_attach_body is not None
            and contains_in_order(
                image_will_attach_body,
                (
                    "guard let operation, operation.id == id else { return false }",
                    "return operation.lifetime.beginSurfaceUse()",
                ),
            )
            and image_will_attach_body.count("beginSurfaceUse()") == 1
            and image_did_release_body is not None
            and contains_in_order(
                image_did_release_body,
                (
                    "guard let operation, operation.id == id else { return }",
                    "operation.lifetime.endSurfaceUse()",
                ),
            )
            and image_did_release_body.count("endSurfaceUse()") == 1
        ):
            violations.append(
                "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: surface "
                "attach/release callbacks must be ID-scoped to the current image "
                "operation"
            )

        run_catch_position = (run_body or "").find("} catch {")
        run_success_body = (
            (run_body or "")[:run_catch_position]
            if run_catch_position >= 0
            else ""
        )
        run_failure_body = (
            (run_body or "")[run_catch_position:]
            if run_catch_position >= 0
            else ""
        )
        if not (
            run_body is not None
            and run_catch_position >= 0
            and run_body.count("try requireCurrent(operationGeneration)") == 3
            and run_body.count("await lifetime.waitForSurfaceRelease()") == 2
            and contains_in_order(
                run_success_body,
                (
                    "try requireCurrent(operationGeneration)",
                    "let originalData = try await loadOriginalData()",
                    "try requireCurrent(operationGeneration)",
                    "let preview = try await processor.preparePreview(",
                    "try requireCurrent(operationGeneration)",
                    "active = ActiveVaultImagePreview(id: id, preview: preview)",
                    "activeGeneration = operationGeneration",
                    "await waitForDismissal(lifetime)",
                    "await lifetime.waitForSurfaceRelease()",
                    "try Task.checkCancellation()",
                    "clearActiveIfOwned(by: operationGeneration)",
                ),
            )
            and contains_in_order(
                run_failure_body,
                (
                    "await lifetime.waitForSurfaceRelease()",
                    "clearActiveIfOwned(by: operationGeneration)",
                    "throw error",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: success and "
                "failure completion must both await UIKit surface release after "
                "the dismissal lifetime and before clearing or returning"
            )

        if not (
            begin_surface_body is not None
            and contains_in_order(
                begin_surface_body,
                (
                    "lock.lock()",
                    "defer { lock.unlock() }",
                    "guard !isFinished, !isSurfaceAttached else { return false }",
                    "isSurfaceAttached = true",
                    "return true",
                ),
            )
            and end_surface_body is not None
            and contains_in_order(
                end_surface_body,
                (
                    "lock.lock()",
                    "guard isSurfaceAttached else",
                    "isSurfaceAttached = false",
                    "let pendingWaiters = surfaceReleaseWaiters",
                    "surfaceReleaseWaiters.removeAll()",
                    "lock.unlock()",
                    "pendingWaiters.forEach { $0.resume() }",
                ),
            )
            and wait_surface_body is not None
            and contains_in_order(
                wait_surface_body,
                (
                    "if isSurfaceAttachedSnapshot()",
                    "await surfaceReleaseWaitObserver()",
                    "await withCheckedContinuation",
                    "if !isSurfaceAttached",
                    "continuation.resume()",
                    "surfaceReleaseWaiters.append(continuation)",
                ),
            )
            and finish_lifetime_body is not None
            and contains_in_order(
                finish_lifetime_body,
                (
                    "lock.lock()",
                    "guard !isFinished else",
                    "isFinished = true",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: image "
                "lifetime leases must reject late attachment, publish release "
                "only after detachment, and resolve waiters under the lock"
            )

        for forbidden_capability in (
            "VaultSession",
            "VaultUnlockService",
            "VaultPhotoRecord",
            "VaultPhotoStore",
            "VaultGeneralFileRecord",
            "VaultGeneralFileStore",
            "EncryptedVaultTransferCoordinator",
            "CryptoBox",
            "SymmetricKey",
            "FileManager",
            "FileHandle",
            "URLSession",
            "Data(contentsOf:",
            "startAccessingSecurityScopedResource",
        ):
            if forbidden_capability in image_preview_coordinator_code:
                violations.append(
                    "KeyHollow/Photos/VaultImagePreviewCoordinator.swift: "
                    "image lifetime coordinator bypasses its injected loader "
                    f"boundary ({forbidden_capability})"
                )

    general_files_view_source = (
        SOURCE_ROOT / "UI" / "VaultGeneralFilesView.swift"
    ).read_text(encoding="utf-8")

    gallery_task_start = gallery_source.find(".task(id: session.activeVaultID)")
    gallery_task_end = gallery_source.find(
        ".onChange(of: session.securityEpoch)", gallery_task_start
    )
    gallery_task_source = gallery_source[gallery_task_start:gallery_task_end]
    photo_import_start = gallery_source.find("private func handleImportEvent(")
    photo_import_end = gallery_source.find(
        "private func finishImport(", photo_import_start
    )
    photo_import_source = gallery_source[photo_import_start:photo_import_end]
    photo_thumbnail_start = gallery_source.find(
        "private func loadThumbnailIfNeeded(_ record: VaultPhotoRecord)"
    )
    photo_thumbnail_end = gallery_source.find(
        "private func loadGeneralFileThumbnailIfNeeded(", photo_thumbnail_start
    )
    photo_thumbnail_source = gallery_source[
        photo_thumbnail_start:photo_thumbnail_end
    ]
    general_export_start = gallery_source.find(
        "private func exportGeneralFiles("
    )
    general_export_end = gallery_source.find(
        "private func savePhotos(", general_export_start
    )
    general_export_source = gallery_source[
        general_export_start:general_export_end
    ]
    if not (
        gallery_task_start >= 0
        and gallery_task_end > gallery_task_start
        and "await session.performSensitiveTask" in gallery_task_source
        and "initializeStores(expectedVaultID:" in gallery_task_source
        and photo_import_start >= 0
        and photo_import_end > photo_import_start
        and "case .photo(let photo):" in photo_import_source
        and "await session.performSensitiveTask" in photo_import_source
        and "try await store.importPhoto(" in photo_import_source
        and photo_thumbnail_start >= 0
        and photo_thumbnail_end > photo_thumbnail_start
        and "await session.performSensitiveTask" in photo_thumbnail_source
        and "try? await store.loadThumbnail(record)" in photo_thumbnail_source
        and ".sheet(isPresented: $showingVaultFiles, onDismiss:" in gallery_source
        and "session.startSensitiveTask { _ in\n                await reloadGeneralFiles()"
        in gallery_source
        and general_export_start >= 0
        and general_export_end > general_export_start
        and "session.startSensitiveTask" in general_export_source
        and "await waitForGeneralFileExportDismissal()" in general_export_source
        and "await generalFileStore.discardExport(prepared)" in general_export_source
        and "session.cancelSensitiveTask(taskID)" in general_export_source
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: every store mutation, "
            "plaintext thumbnail/load, manifest refresh, and prepared-export "
            "cleanup must remain registered with the vault-session barrier"
        )

    general_files_initialization_start = general_files_view_source.find(
        ".task(id: session.activeVaultID)"
    )
    general_files_initialization_end = general_files_view_source.find(
        "private var navigationTitle", general_files_initialization_start
    )
    general_files_initialization_source = general_files_view_source[
        general_files_initialization_start:general_files_initialization_end
    ]
    general_files_initializer_start = general_files_view_source.find(
        "private func initializeStore("
    )
    general_files_initializer_end = general_files_view_source.find(
        "private func importSelectedFiles(", general_files_initializer_start
    )
    general_files_initializer_source = general_files_view_source[
        general_files_initializer_start:general_files_initializer_end
    ]
    if not (
        general_files_initialization_start >= 0
        and general_files_initialization_end > general_files_initialization_start
        and "await session.performSensitiveTask" in general_files_initialization_source
        and general_files_initializer_start >= 0
        and general_files_initializer_end > general_files_initializer_start
        and "let loadedRecords = try await created.loadManifest().files"
        in general_files_initializer_source
        and "currentContext.access === capability"
        in general_files_initializer_source
        and "try Task.checkCancellation()" in general_files_initializer_source
    ):
        violations.append(
            "KeyHollow/UI/VaultGeneralFilesView.swift: initial manifest loading "
            "must remain registered with the vault-session barrier and must not "
            "publish decrypted metadata after capability revocation"
        )

    if not (
        "lockVaultAndFinishCleanup()" in gallery_source
        and "let barrier = session.lock()" in gallery_source
        and "await barrier.wait()" in gallery_source
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: manual locking must "
            "await the captured sensitive-cleanup barrier"
        )

    security_settings_source = (
        SOURCE_ROOT / "UI" / "VaultSecuritySettingsView.swift"
    ).read_text(encoding="utf-8")
    root_view_source = (
        SOURCE_ROOT / "UI" / "RootView.swift"
    ).read_text(encoding="utf-8")
    additional_vault_setup_source = (
        SOURCE_ROOT / "UI" / "AdditionalVaultSetupView.swift"
    ).read_text(encoding="utf-8")
    unlock_service_source = (
        SOURCE_ROOT / "Security" / "VaultUnlockService.swift"
    ).read_text(encoding="utf-8")
    portable_restore_root_markers = (
        "private let generalFileStorageRootOverride: URL?",
        "private let portableRestoreJournalRootOverride: URL?",
        "private let portableRestoreWorkingRootOverride: URL?",
        "workingRootOverride: portableRestoreWorkingRootOverride",
        "journalRootOverride: portableRestoreJournalRootOverride",
        "photoDataRootOverride: photoStorageRootOverride",
        "generalFileDataRootOverride: generalFileStorageRootOverride",
    )
    if any(
        marker not in unlock_service_source
        for marker in portable_restore_root_markers
    ) or any(
        unlock_service_source.count(marker) < 2
        for marker in (
            "journalRootOverride: portableRestoreJournalRootOverride",
            "photoDataRootOverride: photoStorageRootOverride",
            "generalFileDataRootOverride: generalFileStorageRootOverride",
        )
    ) or len(
        re.findall(
            r"PortableVaultRestoreTransactionJournal\.recoveryRequired\(\s*"
            r"journalRootOverride:\s*portableRestoreJournalRootOverride\s*\)",
            unlock_service_source,
        )
    ) < 2:
        violations.append(
            "KeyHollow/Security/VaultUnlockService.swift: portable restore "
            "install and startup recovery must share injectable journal, "
            "working, photo, and general-file roots"
        )
    session_source = (
        SOURCE_ROOT / "Session" / "VaultSession.swift"
    ).read_text(encoding="utf-8")
    deletion_coordinator_start = session_source.find(
        "enum VaultDeletionSessionCoordinator"
    )
    deletion_coordinator_source = session_source[deletion_coordinator_start:]
    coordinator_authorize_position = deletion_coordinator_source.find(
        "service.authorizeVaultDeletion("
    )
    coordinator_revoke_position = deletion_coordinator_source.find(
        "session.revokeAndDrainForVaultDeletion("
    )
    coordinator_commit_position = deletion_coordinator_source.find(
        "service.deleteVault("
    )
    revocation_start = session_source.find("func revokeAndDrainForVaultDeletion(")
    revocation_end = session_source.find(
        "private func combinedBarrier(", revocation_start
    )
    revocation_source = session_source[revocation_start:revocation_end]
    revocation_lock_position = revocation_source.find("let barrier = lock()")
    revocation_wait_position = revocation_source.find("await barrier.wait()")
    revocation_proof_position = revocation_source.find("return proof")
    deletion_commit_start = unlock_service_source.find(
        "func deleteVault(\n        authorization: VaultDeletionAuthorization,"
    )
    deletion_commit_end = unlock_service_source.find(
        "private func checkCredentialLookupAllowed", deletion_commit_start
    )
    deletion_commit_source = unlock_service_source[
        deletion_commit_start:deletion_commit_end
    ]
    deletion_proof_check_position = deletion_commit_source.find(
        "revocationProof.authorizationID == authorization.authorizationID"
    )
    deletion_journal_position = deletion_commit_source.find(
        "transaction = try journal.begin("
    )
    if not (
        "VaultDeletionSessionCoordinator.deleteVault(" in security_settings_source
        and "service.deleteVault(" not in security_settings_source
        and "func revokeAndDrainForVaultDeletion(" in session_source
        and 0 <= coordinator_authorize_position
        < coordinator_revoke_position
        < coordinator_commit_position
        and 0 <= revocation_lock_position
        < revocation_wait_position
        < revocation_proof_position
        and "revocationProof: VaultSession.VaultDeletionRevocationProof" in unlock_service_source
        and "func deleteVault(currentPasscode:" not in unlock_service_source
        and 0 <= deletion_proof_check_position < deletion_journal_position
    ):
        violations.append(
            "KeyHollow/UI/VaultSecuritySettingsView.swift: destructive vault "
            "shutdown must require session-revocation proof after awaiting the "
            "sensitive-cleanup barrier"
        )

    credential_flow_registrations = (
        (
            "KeyHollow/UI/RootView.swift LockView",
            root_view_source,
            "private func submit()",
            "private struct KeyHollowLockMark",
            "service.unlock(passcode:",
        ),
        (
            "KeyHollow/UI/RootView.swift InitialVaultSetup",
            root_view_source,
            "private func create()",
            "enum SecurityEpochCredentialPolicy",
            "service.createVault(passcode:",
        ),
        (
            "KeyHollow/UI/AdditionalVaultSetupView.swift",
            additional_vault_setup_source,
            "private func createVault()",
            "\n}",
            "service.createVault(passcode:",
        ),
        (
            "KeyHollow/UI/VaultSecuritySettingsView.swift passcode change",
            security_settings_source,
            "private func changePasscode()",
            "private func sanitize(",
            "service.changePasscode(",
        ),
    )
    for label, source, start_marker, end_marker, operation_marker in credential_flow_registrations:
        start = source.find(start_marker)
        end = source.find(end_marker, start + len(start_marker))
        flow = source[start:end]
        if not (
            start >= 0
            and end > start
            and operation_marker in flow
            and "session.startProtectedTask {" in flow
            and "session.authorizeUnlockCompletion()" in flow
            and "session.completeUnlock(" in flow
        ):
            violations.append(
                f"{label}: passcode/KDF/key-bearing credential work must remain "
                "registered with the vault-session protected-task barrier"
            )

    credential_service_cancellation_boundaries = (
        (
            "VaultUnlockService.createVault",
            "func createVault(passcode:",
            "/// Gives a fully validated portable vault",
            (
                "let unlockKey = try deriveUnlockKey(passcode: passcode)",
                "try Task.checkCancellation()",
                "let locatorAlreadyExists = await store.contains(locator: locator)",
                "try Task.checkCancellation()",
                "let created = try VaultEnvelope.create(using: unlockKey)",
                "try Task.checkCancellation()",
                "try await store.writeIfAbsent(created.envelope, locator: locator)",
            ),
        ),
        (
            "VaultUnlockService.installValidatedPortableVault",
            "func installValidatedPortableVault(",
            "func unlock(passcode:",
            (
                "let unlockKey = try deriveUnlockKey(passcode: newPasscode)",
                "try Task.checkCancellation()",
                "let locatorAlreadyExists = await store.contains(locator: locator)",
                "try Task.checkCancellation()",
                "let installer = try PortableVaultRestoreInstaller(",
                "try Task.checkCancellation()",
                "let payload = try await installer.install(",
                "catch is CancellationError",
            ),
        ),
        (
            "VaultUnlockService.changePasscode",
            "func changePasscode(",
            "/// Authenticates a deletion request",
            (
                "let current = try await authenticateExistingVault(",
                "try Task.checkCancellation()",
                "let newKey = try deriveUnlockKey(passcode: newPasscode)",
                "try Task.checkCancellation()",
                "let replacementLocatorAlreadyExists = await store.contains(locator: newLocator)",
                "try Task.checkCancellation()",
                "let replacement = try VaultEnvelope.seal(",
                "try Task.checkCancellation()",
                "journal = try passcodeRotationJournal()",
                "try Task.checkCancellation()",
                "transaction = try journal.begin(",
            ),
        ),
        (
            "VaultUnlockService.authenticateExistingVault",
            "private func authenticateExistingVault(",
            "private func deriveUnlockKey(",
            (
                "let unlockKey = try deriveUnlockKey(passcode: passcode)",
                "try Task.checkCancellation()",
                "let persistedEnvelope = try await store.read(locator: locator)",
                "try Task.checkCancellation()",
                "let payload = try envelope.open(using: unlockKey)",
                "try Task.checkCancellation()",
                "await limiter.recordSuccess()",
                "try Task.checkCancellation()",
                "catch is CancellationError",
                "catch VaultUnlockError.invalidCredentials",
            ),
        ),
    )
    for label, start_marker, end_marker, markers in credential_service_cancellation_boundaries:
        start = unlock_service_source.find(start_marker)
        end = unlock_service_source.find(end_marker, start + len(start_marker))
        operation_source = unlock_service_source[start:end]
        if not (
            start >= 0
            and end > start
            and contains_in_order(operation_source, markers)
        ):
            violations.append(
                f"KeyHollow/Security/VaultUnlockService.swift: {label} must "
                "honor lifecycle cancellation before its first durable mutation "
                "and must not charge cancellation as an authentication failure"
            )

    transfer_coordinator_source = (
        SOURCE_ROOT / "Transfer" / "EncryptedVaultTransferCoordinator.swift"
    ).read_text(encoding="utf-8")
    restore_installer_start = transfer_coordinator_source.find("public func install(")
    restore_installer_end = transfer_coordinator_source.find(
        "public func recoverInterruptedInstalls()", restore_installer_start
    )
    restore_installer_source = transfer_coordinator_source[
        restore_installer_start:restore_installer_end
    ]
    if not (
        restore_installer_start >= 0
        and restore_installer_end > restore_installer_start
        and contains_in_order(
            restore_installer_source,
            (
                "let credentialAlreadyExists = await credentialStore.contains(locator: locator)",
                "try Task.checkCancellation()",
                "guard !credentialAlreadyExists else",
                "let envelope = try VaultEnvelope.seal(",
                "try Task.checkCancellation()",
                "let transaction = try transactionJournal.begin(",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift: "
            "portable restore must honor cancellation after credential lookup "
            "and immediately before the journaled install begins"
        )
    video_thumbnail_integration_active = (
        "import KeyHollowEncryptedVideoAddOn" in gallery_executable
        or "VaultEncryptedVideoThumbnailRenderer.render(" in gallery_executable
    )
    video_playback_integration_active = (
        "VaultVideoPlaybackCoordinator" in gallery_executable
        or "case .videoPlayback:" in gallery_executable
        or "VaultEncryptedVideoPlayerView(" in gallery_executable
    )
    for required in (
        "import KeyHollowGalleryUI",
        "import KeyHollowMediaNavigationAddOn",
        "import KeyHollowSecurePreviewAddOn",
        "VaultGalleryGridView(",
        "VaultGalleryItemTileView(",
        "VaultMediaNavigationPager(",
        "case .imagePreview:",
        "case .fileManagement:",
        "generalFileStore.loadFile(record)",
        "generalFileStore.prepareExport(files)",
        "GeneralFileShareSheet(urls: prepared.urls)",
        'Label("Export to Files", systemImage: "square.and.arrow.up")',
        'Label("Export Files", systemImage: "square.and.arrow.up")',
        'Label("Move", systemImage: "folder")',
        "presentationStore.move(items, to: folderID)",
        "selectedPresentedReferences",
        "let snapshot = makeVisibleGallerySnapshot()",
        "VaultGalleryContentSnapshot",
        "galleryItemCell(item, snapshot: snapshot)",
        "folders: visibleGalleryFolders",
        "items: snapshot.presentations",
        "priority: .utility",
        "actor VaultGeneralFileThumbnailPipeline",
        "private var waiters: [PermitWaiter]",
        "@State private var thumbnailImageProcessor = VaultSecureImageProcessor()",
        "@State private var previewImageProcessor = VaultSecureImageProcessor()",
        "@State private var generalFileThumbnailPipeline = VaultGeneralFileThumbnailPipeline()",
        "@StateObject private var imagePreview = VaultImagePreviewCoordinator()",
        "let renderedImage = try await generalFileThumbnailPipeline.image(",
        "cacheMissImageProcessor.prepareThumbnail(",
        "try await imagePreview.prepare(",
        "retiringTask?.cancel()",
        "await imagePreview.dismissAndWait()",
        "await session.performSensitiveTask { capability in",
    ):
        if required not in gallery_source:
            violations.append(
                f"KeyHollow/Photos/VaultGalleryView.swift: unified gallery "
                f"composition is missing {required!r}"
            )

    for required in (
        "VaultMediaNavigationID(source: .photo, rawValue: record.id)",
        "VaultMediaNavigationID(source: .generalFile, rawValue: record.id)",
        "case .fileManagement:\n            return nil",
        "orderedSources.compactMap(\\.mediaNavigationItem)",
        "uniqueKeysWithValues: orderedSources.compactMap { source in",
        "try VaultMediaNavigationQueue(",
        "items: mediaNavigationItems",
        "@State private var mediaNavigationQueue: VaultMediaNavigationQueue?",
        "@State private var mediaNavigationSources: [VaultMediaNavigationID: VaultGalleryContentItem] = [:]",
        "@State private var mediaNavigationGeneration: UInt64 = 0",
        "@State private var mediaNavigationTask: Task<Void, Never>?",
        "@State private var failedMediaID: VaultMediaNavigationID?",
        "@State private var isDeletingMedia = false",
        "@State private var isSavingPreview = false",
        "@State private var imageSaveTaskID: UUID?",
        "@StateObject private var imagePreview = VaultImagePreviewCoordinator()",
        "@StateObject private var videoPlayback = VaultVideoPlaybackCoordinator()",
        "get: { mediaNavigationQueue != nil }",
        ".interactiveDismissDisabled()",
        "onSelectionChange: selectMediaNavigationItem",
        "mediaNavigationActiveContent(item)",
        "VaultSecureImageSurface(",
        "imagePreview.imageWillAttach(item.id)",
        "imagePreview.imageDidRelease(item.id)",
    ):
        if required not in gallery_executable:
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: source-aware, "
                "single-surface media navigation is missing "
                f"{required!r}"
            )

    media_viewer_body = swift_block_body(
        gallery_source,
        "private var mediaNavigationViewer: some View",
    )
    media_toolbar_body = swift_block_body(
        gallery_source,
        "private func mediaNavigationToolbar(",
    )
    media_active_content_body = swift_block_body(
        gallery_source,
        "private func mediaNavigationActiveContent(",
    )
    media_load_state_body = swift_block_body(
        gallery_source,
        "private func mediaNavigationLoadState(",
    )
    if not (
        media_viewer_body is not None
        and contains_in_order(
            media_viewer_body,
            (
                "VaultMediaNavigationPager(",
                "queue: queue",
                "isNavigationEnabled: !isSavingPreview",
                "&& !isDeletingMedia",
                "&& !isClosingMediaNavigation",
                "onSelectionChange: selectMediaNavigationItem",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: the pager must disable "
            "all navigation while image save, active deletion, or terminal "
            "dismissal work owns the current selection"
        )

    if not (
        media_toolbar_body is not None
        and contains_in_order(
            media_toolbar_body,
            (
                "Button(",
                "action: beginMediaNavigationDismissal",
                ".disabled(",
                "isSavingPreview",
                "|| isDeletingMedia",
                "|| isClosingMediaNavigation",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: the visible Done action "
            "must be disabled while image save, deletion, or dismissal is active"
        )

    if not (
        media_active_content_body is not None
        and contains_in_order(
            media_active_content_body,
            (
                "case .image:",
                "if let active = imagePreview.active",
                "active.id == item.id",
                "VaultSecureImageSurface(",
                "renderedImage: active.preview.displayImage",
                "onImageWillAttach:",
                "imagePreview.imageWillAttach(item.id)",
                "onImageReleased:",
                "imagePreview.imageDidRelease(item.id)",
            ),
        )
        and media_active_content_body.count("VaultSecureImageSurface(") == 1
        and "Image(uiImage:" not in media_active_content_body
        and "VaultSecureImagePreviewView(" not in media_active_content_body
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: unified images must use "
            "exactly one observable VaultSecureImageSurface wired to the "
            "app-owned image lifetime coordinator"
        )

    if not (
        media_load_state_body is not None
        and contains_in_order(
            media_load_state_body,
            (
                "if failedMediaID == item.id",
                "Button(",
                "retryMediaNavigationItem(item.id)",
                "} else",
                "ProgressView(",
            ),
        )
        and media_load_state_body.count("retryMediaNavigationItem(item.id)") == 1
        and media_load_state_body.count("ProgressView(") == 1
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: failed media opens must "
            "replace the opening spinner with one retry route"
        )

    gallery_tap_start = gallery_executable.find(
        "private func handleGalleryItemTap("
    )
    gallery_tap_end = gallery_executable.find(
        "private func thumbnail(", gallery_tap_start
    )
    gallery_tap_source = gallery_executable[gallery_tap_start:gallery_tap_end]
    if not (
        gallery_tap_start >= 0
        and gallery_tap_end > gallery_tap_start
        and contains_in_order(
            gallery_tap_source,
            (
                "case .imagePreview, .videoPlayback:",
                "openMediaNavigation(startingAt: item, snapshot: snapshot)",
                "case .fileManagement:",
                "showingVaultFiles = true",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: image and video taps "
            "must share media navigation while non-media files retain the "
            "file-management route"
        )

    media_open_start = gallery_executable.find(
        "private func openMediaNavigation("
    )
    media_select_start = gallery_executable.find(
        "private func selectMediaNavigationItem(", media_open_start
    )
    media_retry_start = gallery_executable.find(
        "private func retryMediaNavigationItem(", media_select_start
    )
    media_prepare_start = gallery_executable.find(
        "private func prepareSelectedMedia(", media_retry_start
    )
    media_image_start = gallery_executable.find(
        "private func prepareMediaImage(", media_prepare_start
    )
    media_video_start = gallery_executable.find(
        "private func prepareMediaVideo(", media_image_start
    )
    media_current_start = gallery_executable.find(
        "private func isCurrentMediaSelection(", media_video_start
    )
    media_delete_photo_start = gallery_executable.find(
        "private func delete(_ record: VaultPhotoRecord)", media_current_start
    )

    media_open_source = gallery_executable[media_open_start:media_select_start]
    media_select_source = gallery_executable[media_select_start:media_retry_start]
    media_retry_source = gallery_executable[media_retry_start:media_prepare_start]
    media_prepare_source = gallery_executable[media_prepare_start:media_image_start]
    media_image_source = gallery_executable[media_image_start:media_video_start]
    media_video_source = gallery_executable[media_video_start:media_current_start]
    media_current_source = gallery_executable[
        media_current_start:media_delete_photo_start
    ]

    if not (
        media_open_start >= 0
        and media_select_start > media_open_start
        and contains_in_order(
            media_open_source,
            (
                "guard !isWorking",
                "!isSavingPreview",
                "!isDeletingMedia",
                "!isClosingMediaNavigation",
                "let item = source.mediaNavigationItem",
                "mediaNavigationQueue = try snapshot.mediaNavigationQueue(",
                "startingAt: item.id",
                "mediaNavigationSources = snapshot.mediaNavigationSourceByID",
                "prepareSelectedMedia(id: item.id)",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: viewer opening must "
            "publish one immutable visible-location queue and its typed source "
            "map before preparing the selected item"
        )

    if not (
        media_select_start >= 0
        and media_prepare_start > media_select_start
        and contains_in_order(
            media_select_source,
            (
                "guard !isSavingPreview",
                "!isDeletingMedia",
                "!isClosingMediaNavigation",
                "let selectedQueue = try? queue.selecting(id)",
                "mediaNavigationQueue = selectedQueue",
                "failedMediaID = nil",
                "prepareSelectedMedia(id: id)",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: adjacent selection must "
            "advance the immutable metadata queue before payload preparation"
        )

    if not (
        media_retry_start >= 0
        and media_prepare_start > media_retry_start
        and contains_in_order(
            media_retry_source,
            (
                "guard !isSavingPreview",
                "!isDeletingMedia",
                "!isClosingMediaNavigation",
                "mediaNavigationQueue?.selectedID == id",
                "previewMessage = nil",
                "failedMediaID = nil",
                "prepareSelectedMedia(id: id)",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: retry must be current-item "
            "scoped, blocked by save/delete/dismiss work, clear the failure, and "
            "re-enter the normal preparation pipeline"
        )

    if not (
        media_prepare_start >= 0
        and media_image_start > media_prepare_start
        and contains_in_order(
            media_prepare_source,
            (
                "failedMediaID = nil",
                "mediaNavigationGeneration &+= 1",
                "let generation = mediaNavigationGeneration",
                "let retiringTask = mediaNavigationTask",
                "mediaNavigationTask = nil",
                "retiringTask?.cancel()",
                "imagePreview.dismiss()",
                "videoPlayback.dismiss()",
                "mediaNavigationTask = Task { @MainActor in",
                "await retiringTask.value",
                "await imagePreview.dismissAndWait()",
                "await videoPlayback.dismissAndWait()",
                "guard !Task.isCancelled",
                "isCurrentMediaSelection(id, generation: generation)",
                "switch descriptor.kind",
                "case .image:",
                "await prepareMediaImage(",
                "case .video:",
                "await prepareMediaVideo(",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: media replacement must "
            "revoke both payload types, await the retiring lifetime, revalidate "
            "typed selection, and only then prepare the new active payload"
        )

    media_image_sensitive_body = swift_block_body(
        media_image_source,
        "await session.performSensitiveTask",
    )
    if not (
        media_image_start >= 0
        and media_video_start > media_image_start
        and media_image_source.count("await session.performSensitiveTask { _ in") == 1
        and media_image_sensitive_body is not None
        and media_image_source.count("try await imagePreview.prepare(") == 2
        and media_image_sensitive_body.count("try await imagePreview.prepare(") == 2
        and media_image_source.count("try await store.loadPhoto(record)") == 1
        and media_image_sensitive_body.count("try await store.loadPhoto(record)") == 1
        and media_image_source.count(
            "try await generalFileStore.loadFile(record)"
        ) == 1
        and media_image_sensitive_body.count(
            "try await generalFileStore.loadFile(record)"
        ) == 1
        and media_image_source.count("failedMediaID = descriptor.id") == 2
        and contains_in_order(
            media_image_source,
            (
                "case .photo(let record):",
                "try await imagePreview.prepare(",
                "loadOriginalData: {",
                "try await store.loadPhoto(record)",
                "case .generalFile(let record):",
                "try await imagePreview.prepare(",
                "loadOriginalData: {",
                "try await generalFileStore.loadFile(record)",
                "catch VaultPhotoStore.StoreError.originalTooLarge",
                "guard isCurrentMediaSelection(",
                "failedMediaID = descriptor.id",
                "catch",
                "guard isCurrentMediaSelection(",
                "failedMediaID = descriptor.id",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: photo and Files-origin "
            "images must load through injected closures inside one session "
            "sensitive task and the app-owned image lifetime coordinator"
        )

    media_video_sensitive_body = swift_block_body(
        media_video_source,
        "await session.performSensitiveTask",
    )
    if not (
        media_video_start >= 0
        and media_current_start > media_video_start
        and media_video_source.count("await session.performSensitiveTask { _ in") == 1
        and media_video_sensitive_body is not None
        and media_video_source.count(
            "try await videoPlayback.prepare(record, using: generalFileStore)"
        ) == 1
        and media_video_sensitive_body.count(
            "try await videoPlayback.prepare(record, using: generalFileStore)"
        ) == 1
        and media_video_source.count("failedMediaID = descriptor.id") == 2
        and contains_in_order(
            media_video_source,
            (
                "guard case .generalFile(let record) = source",
                "if isCurrentMediaSelection(descriptor.id, generation: generation)",
                "failedMediaID = descriptor.id",
                "await session.performSensitiveTask { _ in",
                "try await videoPlayback.prepare(record, using: generalFileStore)",
                "catch",
                "guard isCurrentMediaSelection(",
                "failedMediaID = descriptor.id",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: video payloads must enter "
            "through the app-owned playback coordinator inside a session "
            "sensitive task"
        )

    if not (
        media_current_start >= 0
        and media_delete_photo_start > media_current_start
        and contains_in_order(
            media_current_source,
            (
                "!Task.isCancelled",
                "mediaNavigationGeneration == generation",
                "mediaNavigationQueue?.selectedID == id",
                "!isClosingMediaNavigation",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: asynchronous media "
            "publication must reject cancellation, stale generation, stale "
            "selection, and closing presentation state"
        )

    pipeline_start = gallery_source.find(
        "actor VaultGeneralFileThumbnailPipeline {"
    )
    pipeline_end = gallery_source.find(
        "/// Application composition coordinator", pipeline_start
    )
    pipeline_source = gallery_source[pipeline_start:pipeline_end]
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
                "KeyHollow/Photos/VaultGalleryView.swift: general-file "
                f"thumbnail cache/miss isolation is missing {required!r}"
            )
    if not (
        load_or_generate_start >= 0
        and generate_thumbnail_start > load_or_generate_start
        and len(cache_checks) == 2
        and cache_checks[0] < permit_position < cache_checks[1]
        and cache_checks[1] < generation_position
        and original_load_position < miss_prepare_position
        and "return try await loadOrGenerate(" in image_entry_source
        and "try await generateThumbnail(" in image_entry_source
        and pipeline_source.count("generateThumbnail(") == 2
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: encrypted thumbnail "
            "cache hits must bypass the full-payload permit, queued misses "
            "must recheck the cache, and original preparation must remain "
            "inside the bounded miss lane"
        )

    if video_thumbnail_integration_active:
        for required in (
            "import KeyHollowEncryptedVideoAddOn",
            "VaultEncryptedVideoPolicy.kind(",
            "VaultEncryptedVideoThumbnailRenderer.render(",
        ):
            if required not in gallery_source:
                violations.append(
                    "KeyHollow/Photos/VaultGalleryView.swift: encrypted-video "
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
            and video_prepare_position < video_render_position
            and video_render_position < video_cleanup_position < video_store_position
        ):
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: video cold-thumbnail "
                "misses must prepare, render, clean up plaintext, and persist "
                "inside the existing VaultGeneralFileThumbnailPipeline permit"
            )

        for parallel_lane in (
            "videoThumbnails.render(",
            "videoThumbnailPipeline",
            "acquireVideoPermit",
            "videoThumbnailWaiters",
        ):
            if parallel_lane in gallery_source:
                violations.append(
                    "KeyHollow/Photos/VaultGalleryView.swift: video thumbnails "
                    f"introduced a parallel full-payload lane ({parallel_lane})"
                )

    video_playback_coordinator_file = (
        SOURCE_ROOT / "Photos" / "VaultVideoPlaybackCoordinator.swift"
    )
    if video_playback_coordinator_file.exists():
        video_playback_coordinator_source = (
            video_playback_coordinator_file.read_text(encoding="utf-8")
        )
        for pattern, requirement in (
            (
                r"private\s*\(\s*set\s*\)\s+var\s+active\b",
                "private-set active playback state",
            ),
            (
                r"prepareExport\s*\(\s*\[\s*record\s*\]\s*\)",
                "one-record authenticated export preparation",
            ),
            (
                r"try\s+await\s+playback\.validatePlayable\s*\(\s*\)",
                "default fail-closed media validator",
            ),
            (
                r"try\s+await\s+validatePlayable\s*\(\s*playback\s*\)",
                "invocation of the injected media validator",
            ),
            (
                r"try\s+Task\.checkCancellation\s*\(\s*\)",
                "cooperative cancellation checks",
            ),
            (
                r"func\s+dismissAndWait\s*\(\s*\)\s*async\b",
                "awaitable terminal cleanup",
            ),
            (
                r"active\s*=\s*nil\b",
                "active playback revocation",
            ),
            (
                r"func\s+playerWillAttach\s*\(",
                "player attachment lease",
            ),
            (
                r"func\s+playerDidRelease\s*\(",
                "player release acknowledgement",
            ),
            (
                r"await\s+lifetime\.waitForPlayerRelease\s*\(\s*\)",
                "decoder-release cleanup barrier",
            ),
        ):
            if re.search(pattern, video_playback_coordinator_source) is None:
                violations.append(
                    "KeyHollow/Photos/VaultVideoPlaybackCoordinator.swift: "
                    f"plaintext-lifecycle boundary is missing {requirement}"
                )

        validation_position = match_position(
            r"try\s+await\s+validatePlayable\s*\(\s*playback\s*\)",
            video_playback_coordinator_source,
        )
        active_publications = [
            match.start()
            for match in re.finditer(
                r"(?m)^[ \t]*active[ \t]*=[ \t]*ActiveVaultVideoPlayback\s*\(",
                video_playback_coordinator_source,
            )
        ]
        if not (
            validation_position >= 0
            and active_publications
            and validation_position < active_publications[0]
        ):
            violations.append(
                "KeyHollow/Photos/VaultVideoPlaybackCoordinator.swift: "
                "malformed media must fail closed before active playback is published"
            )

        discard_call_count = len(
            re.findall(
                r"\bdiscardExport\s*\(",
                video_playback_coordinator_source,
            )
        )
        awaited_discard_count = len(
            re.findall(
                r"\bawait\s+[A-Za-z_][A-Za-z0-9_]*"
                r"(?:\.[A-Za-z_][A-Za-z0-9_]*)*"
                r"\.discardExport\s*\(",
                video_playback_coordinator_source,
            )
        )
        if discard_call_count < 2 or awaited_discard_count != discard_call_count:
            violations.append(
                "KeyHollow/Photos/VaultVideoPlaybackCoordinator.swift: "
                "preparation failure and active-session teardown must both "
                "await prepared-plaintext cleanup"
            )

        if video_playback_coordinator_source.count(
            "await lifetime.waitForPlayerRelease()"
        ) < 2:
            violations.append(
                "KeyHollow/Photos/VaultVideoPlaybackCoordinator.swift: "
                "success and failure cleanup must both wait for an attached "
                "player to release its decoder/file handle"
            )

        for forbidden_capability in (
            "CryptoBox",
            "SymmetricKey",
            "FileManager",
            "FileHandle",
            "URLSession",
            "Data(contentsOf:",
            "startAccessingSecurityScopedResource",
        ):
            if forbidden_capability in video_playback_coordinator_source:
                violations.append(
                    "KeyHollow/Photos/VaultVideoPlaybackCoordinator.swift: "
                    "playback coordinator bypasses its narrow store boundary "
                    f"({forbidden_capability})"
                )

    image_save_body = swift_block_body(
        gallery_source,
        "private func saveCurrentMediaImage()",
    )
    image_save_sensitive_body = swift_block_body(
        image_save_body or "",
        "session.startSensitiveTask",
    )
    playback_failure_body = swift_block_body(
        gallery_source,
        "private func handleMediaPlaybackFailure(",
    )
    if not (
        image_save_body is not None
        and image_save_sensitive_body is not None
        and image_save_body.count("session.startSensitiveTask") == 1
        and image_save_body.count("PhotoLibrarySaveService.savePhoto(") == 1
        and image_save_sensitive_body.count(
            "PhotoLibrarySaveService.savePhoto("
        ) == 1
        and contains_in_order(
            image_save_body,
            (
                "guard !isSavingPreview",
                "!isDeletingMedia",
                "!isClosingMediaNavigation",
                "let selectedID = mediaNavigationQueue?.selectedID",
                "let active = imagePreview.active",
                "active.id == selectedID",
                "let saveGeneration = mediaNavigationGeneration",
                "let preview = active.preview",
                "isSavingPreview = true",
                "let taskID = session.startSensitiveTask",
                "imageSaveTaskID = taskID",
                "if taskID == nil { isSavingPreview = false }",
            ),
        )
        and contains_in_order(
            image_save_sensitive_body,
            (
                "session.beginSystemPhotoOperation()",
                "defer",
                "session.endSystemPhotoOperation()",
                "if mediaNavigationGeneration == saveGeneration",
                "imageSaveTaskID = nil",
                "isSavingPreview = false",
                "let result = await PhotoLibrarySaveService.savePhoto(",
                "preview.originalData",
                "guard isCurrentMediaSelection(",
                "selectedID",
                "generation: saveGeneration",
                "switch result",
            ),
        )
        and "imageSaveTaskID = taskID" not in image_save_sensitive_body
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: image saving must be one "
            "session-tracked task whose UI/result publication remains bound to "
            "the captured generation and selected item"
        )

    if not (
        playback_failure_body is not None
        and contains_in_order(
            playback_failure_body,
            (
                "guard mediaNavigationQueue?.selectedID == id",
                "!isClosingMediaNavigation",
                "videoPlayback.dismiss()",
                "failedMediaID = id",
                "previewMessage =",
            ),
        )
    ):
        violations.append(
            "KeyHollow/Photos/VaultGalleryView.swift: runtime video failures "
            "must dismiss playback and publish retryable failure state only for "
            "the current selection"
        )

    if video_playback_integration_active:
        if not video_playback_coordinator_file.exists():
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: playback routing "
                "started before VaultVideoPlaybackCoordinator.swift exists"
            )
        for pattern, requirement in (
            (
                r"(?m)^import\s+KeyHollowEncryptedVideoAddOn\s*$",
                "encrypted-video module import",
            ),
            (
                r"case\s+\.videoPlayback\s*:",
                "video playback route",
            ),
            (
                r"VaultVideoPlaybackCoordinator\s*\(\s*\)",
                "app-owned playback coordinator",
            ),
            (
                r"VaultEncryptedVideoPlayerView\s*\(",
                "module-owned player surface",
            ),
            (
                r"await\s+videoPlayback\.dismissAndWait\s*\(\s*\)",
                "awaited playback cleanup",
            ),
            (
                r"videoPlayback\.dismiss\s*\(\s*\)",
                "synchronous lifecycle revocation",
            ),
            (
                r"onPlayerWillAttach\s*:\s*\{",
                "player attachment acknowledgement wiring",
            ),
            (
                r"onPlayerReleased\s*:\s*\{",
                "player release acknowledgement wiring",
            ),
        ):
            if re.search(pattern, gallery_executable) is None:
                violations.append(
                    "KeyHollow/Photos/VaultGalleryView.swift: encrypted-video "
                    f"playback lifecycle integration is missing {requirement}"
                )
        if re.search(
            r"try\s+await\s+videoPlayback\.(?:run|prepare)\(",
            gallery_executable,
        ) is None:
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: video playback must "
                "enter through the app-owned coordinator"
            )

        open_route_start = match_position(
            r"\bvar\s+openRoute\s*:\s*VaultGalleryOpenRoute\b",
            gallery_executable,
        )
        open_route_end = gallery_executable.find(
            "private static func",
            open_route_start,
        )
        open_route_source = gallery_executable[
            open_route_start:open_route_end
            if open_route_start >= 0 and open_route_end > open_route_start
            else open_route_start
        ]
        image_route_position = open_route_source.find(
            "VaultSecurePreviewPolicy.kind("
        )
        video_route_position = open_route_source.find(
            "VaultEncryptedVideoPolicy.kind("
        )
        if not 0 <= image_route_position < video_route_position:
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: open routing must "
                "preserve image-before-video precedence"
            )

        for lifecycle_pattern, cleanup_pattern, lifecycle_name in (
            (
                r"\.task\s*\(\s*id\s*:\s*session\.activeVaultID\s*\)",
                r"await\s+resetMediaNavigationAndWait\s*\(",
                "active-vault change",
            ),
            (
                r"\.onChange\s*\(\s*of\s*:\s*session\.securityEpoch\b",
                r"cancelMediaNavigationForLifecycle\s*\(",
                "session security epoch",
            ),
            (
                r"\.onDisappear\b",
                r"cancelMediaNavigationForLifecycle\s*\(",
                "gallery disappearance",
            ),
        ):
            lifecycle_match = re.search(lifecycle_pattern, gallery_executable)
            lifecycle_window = (
                gallery_executable[
                    lifecycle_match.start():lifecycle_match.start() + 900
                ]
                if lifecycle_match
                else ""
            )
            if (
                lifecycle_match is None
                or re.search(cleanup_pattern, lifecycle_window) is None
            ):
                violations.append(
                    "KeyHollow/Photos/VaultGalleryView.swift: "
                    f"{lifecycle_name} must enter the unified media cleanup path"
                )

        media_dismiss_start = gallery_executable.find(
            "private func beginMediaNavigationDismissal()"
        )
        media_delete_start = gallery_executable.find(
            "private func deleteCurrentMedia()", media_dismiss_start
        )
        media_reset_start = gallery_executable.find(
            "private func resetMediaNavigationAndWait()", media_delete_start
        )
        media_cancel_start = gallery_executable.find(
            "private func cancelMediaNavigationForLifecycle()", media_reset_start
        )
        media_clear_start = gallery_executable.find(
            "private func clearMediaNavigationState()", media_cancel_start
        )
        post_media_clear_start = gallery_executable.find(
            "private var selectedPhotoRecords", media_clear_start
        )

        media_dismiss_source = gallery_executable[
            media_dismiss_start:media_delete_start
        ]
        media_delete_source = gallery_executable[
            media_delete_start:media_reset_start
        ]
        media_reset_source = gallery_executable[media_reset_start:media_cancel_start]
        media_cancel_source = gallery_executable[media_cancel_start:media_clear_start]
        media_clear_source = gallery_executable[
            media_clear_start:post_media_clear_start
        ]

        if not (
            media_dismiss_start >= 0
            and media_delete_start > media_dismiss_start
            and contains_in_order(
                media_dismiss_source,
                (
                    "guard mediaNavigationQueue != nil",
                    "!isSavingPreview",
                    "!isDeletingMedia",
                    "!isClosingMediaNavigation",
                    "isClosingMediaNavigation = true",
                    "mediaNavigationGeneration &+= 1",
                    "let dismissalGeneration = mediaNavigationGeneration",
                    "let retiringTask = mediaNavigationTask",
                    "mediaNavigationTask = nil",
                    "retiringTask?.cancel()",
                    "imagePreview.dismiss()",
                    "videoPlayback.dismiss()",
                    "mediaNavigationTask = Task { @MainActor in",
                    "await retiringTask.value",
                    "await imagePreview.dismissAndWait()",
                    "await videoPlayback.dismissAndWait()",
                    "guard mediaNavigationGeneration == dismissalGeneration else { return }",
                    "clearMediaNavigationState()",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: interactive media "
                "dismissal must revoke both payloads immediately, await both "
                "terminal lifetimes, reject a stale generation, and only then "
                "clear presentation state"
            )

        media_delete_sensitive_body = swift_block_body(
            media_delete_source,
            "await session.performSensitiveTask",
        )
        if not (
            media_delete_start >= 0
            and media_reset_start > media_delete_start
            and media_delete_source.count(
                "await session.performSensitiveTask { _ in"
            ) == 1
            and media_delete_sensitive_body is not None
            and media_delete_source.count("try await store.delete(record)") == 1
            and media_delete_sensitive_body.count(
                "try await store.delete(record)"
            ) == 1
            and media_delete_source.count(
                "try await generalFileStore.delete([record])"
            ) == 1
            and media_delete_sensitive_body.count(
                "try await generalFileStore.delete([record])"
            ) == 1
            and contains_in_order(
                media_delete_source,
                (
                    "guard !isDeletingMedia",
                    "!isSavingPreview",
                    "!isClosingMediaNavigation",
                    "isDeletingMedia = true",
                    "let deletingID = queue.selectedID",
                    "let retiringTask = mediaNavigationTask",
                    "mediaNavigationTask = nil",
                    "retiringTask?.cancel()",
                    "imagePreview.dismiss()",
                    "videoPlayback.dismiss()",
                    "await retiringTask.value",
                    "await imagePreview.dismissAndWait()",
                    "await videoPlayback.dismissAndWait()",
                    "guard !Task.isCancelled",
                    "mediaNavigationQueue?.selectedID == deletingID",
                    "await session.performSensitiveTask { _ in",
                    "mediaNavigationSources.removeValue(forKey: deletingID)",
                    "queue.removing(deletingID)",
                    "mediaNavigationQueue = remainingQueue",
                    "prepareSelectedMedia(id: remainingQueue.selectedID)",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: deleting the active "
                "item must finish image/video plaintext lifetimes before store "
                "mutation, preserve typed selection guards, and advance or "
                "dismiss the immutable queue"
            )

        if not (
            media_reset_start >= 0
            and media_cancel_start > media_reset_start
            and contains_in_order(
                media_reset_source,
                (
                    "mediaNavigationGeneration &+= 1",
                    "let retiringTask = mediaNavigationTask",
                    "let retiringSaveTaskID = imageSaveTaskID",
                    "mediaNavigationTask = nil",
                    "imageSaveTaskID = nil",
                    "retiringTask?.cancel()",
                    "mediaNavigationQueue = nil",
                    "imagePreview.dismiss()",
                    "videoPlayback.dismiss()",
                    "if let retiringSaveTaskID",
                    "await session.cancelSensitiveTaskAndWait(retiringSaveTaskID)",
                    "await retiringTask.value",
                    "await imagePreview.dismissAndWait()",
                    "await videoPlayback.dismissAndWait()",
                    "isSavingPreview = false",
                    "clearMediaNavigationState()",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: active-vault reset "
                "must revoke navigation first and await both terminal payload "
                "lifetimes before clearing state"
            )

        if not (
            media_cancel_start >= 0
            and media_clear_start > media_cancel_start
            and contains_in_order(
                media_cancel_source,
                (
                    "mediaNavigationGeneration &+= 1",
                    "mediaNavigationTask?.cancel()",
                    "mediaNavigationTask = nil",
                    "if let imageSaveTaskID",
                    "session.cancelSensitiveTask(imageSaveTaskID)",
                    "self.imageSaveTaskID = nil",
                    "mediaNavigationQueue = nil",
                    "mediaNavigationSources = [:]",
                    "isSavingPreview = false",
                    "imagePreview.dismiss()",
                    "videoPlayback.dismiss()",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: synchronous lock or "
                "disappearance cleanup must revoke queue, task, source map, "
                "image preview, and video playback together"
            )

        if not (
            media_clear_start >= 0
            and post_media_clear_start > media_clear_start
            and contains_in_order(
                media_clear_source,
                (
                    "mediaNavigationTask = nil",
                    "if let imageSaveTaskID",
                    "session.cancelSensitiveTask(imageSaveTaskID)",
                    "self.imageSaveTaskID = nil",
                    "mediaNavigationQueue = nil",
                    "mediaNavigationSources = [:]",
                    "isSavingPreview = false",
                    "imagePreview.dismiss()",
                    "videoPlayback.dismiss()",
                ),
            )
        ):
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: terminal media state "
                "clearing must not retain either payload coordinator"
            )

    for obsolete in (
        "LazyVGrid(columns:",
        "ForEach(visibleFolders)",
        "ForEach(visibleGalleryItems)",
        "VaultGeneralFileTileView(",
        "thumbnailCell(",
        "DecryptedPhotoView(",
        "visibleGalleryContentItems.first(where:",
        "private let thumbnailImageProcessor = VaultSecureImageProcessor()",
        "private let previewImageProcessor = VaultSecureImageProcessor()",
        "VaultSecureImagePreviewView(",
        "@State private var activeImagePreview",
        "@State private var preparedImagePreview",
        "@State private var previewTaskID",
        "private func openImage(",
        "private func openVideo(",
        "private func clearActiveImagePreview(",
    ):
        if obsolete in gallery_executable:
            violations.append(
                f"KeyHollow/Photos/VaultGalleryView.swift: parallel gallery "
                f"presentation path returned ({obsolete})"
            )

    if violations:
        print("Architecture boundary violations:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    print(
        "Architecture boundaries passed: KeyHollowVaultThumbnailExtension, "
        "KeyHollowCryptoCore, "
        "KeyHollowVaultCore, KeyHollowPhotoCore, KeyHollowPhotosAdapter, and "
        "KeyHollowTransferCore remain separately compiled; KeyHollowGalleryUI "
        "owns the visible gallery without protected capabilities; "
        "KeyHollowMediaNavigationAddOn remains metadata-only, active-payload-only, "
        "busy-aware, native-video-control-aware, and independently compiled; "
        "unified image presentation retains observable UIKit release, late-attach "
        "rejection, session-tracked saves, and retryable failure state; "
        "KeyHollowEncryptedVideoAddOn remains capability-free and independently "
        "compiled; KeyHollowBackupVerificationAddOn remains report-only and "
        "independently compiled; registered add-ons remain independently compiled; "
        "and core storage, "
        "cryptography, session, and transfer code "
        "remain free of UI, Photos, network, and remote SDK concerns."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

