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
ENCRYPTED_VIDEO_MODULE_FILES = {
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoPlayerView.swift",
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoPolicy.swift",
    "KeyHollow/AddOns/EncryptedVideo/VaultEncryptedVideoThumbnailRenderer.swift",
}
BACKUP_VERIFICATION_MODULE_FILES = {
    "KeyHollow/AddOns/BackupVerification/BackupVerificationReport.swift",
    "KeyHollow/AddOns/BackupVerification/BackupVerificationReportView.swift",
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


def imports(source: str) -> set[str]:
    return set(
        re.findall(
            r"(?m)^(?:@preconcurrency\s+)?import\s+([A-Za-z0-9_]+)\s*$",
            source,
        )
    )


def contains_in_order(source: str, markers: tuple[str, ...]) -> bool:
    cursor = 0
    for marker in markers:
        position = source.find(marker, cursor)
        if position < 0:
            return False
        cursor = position + len(marker)
    return True


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
    violations: list[str] = []
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
    for required in (
        "public actor VaultSecureImageProcessor",
        "kCGImageSourceShouldCacheImmediately: true",
        "preview?.displayImage.image",
        "fileprivate init(image: UIImage)",
    ):
        if required not in secure_preview_source:
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
        if obsolete in secure_preview_source:
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

        if path.startswith(SECURE_PREVIEW_PREFIX):
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
                if forbidden_symbol in source:
                    violations.append(
                        f"{path}: secure-preview add-on directly references protected "
                        f"capability {forbidden_symbol}"
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
        "import KeyHollowEncryptedVideoAddOn" in gallery_source
        or "VaultEncryptedVideoThumbnailRenderer.render(" in gallery_source
    )
    video_playback_integration_active = (
        "VaultVideoPlaybackCoordinator" in gallery_source
        or "case .videoPlayback:" in gallery_source
        or "VaultEncryptedVideoPlayerView(" in gallery_source
    )
    for required in (
        "import KeyHollowGalleryUI",
        "import KeyHollowSecurePreviewAddOn",
        "VaultGalleryGridView(",
        "VaultGalleryItemTileView(",
        "VaultSecureImagePreviewView(",
        "case .imagePreview:",
        "case .fileManagement:",
        "data = try await generalFileStore.loadFile(record)",
        "generalFileStore.prepareExport(files)",
        "GeneralFileShareSheet(urls: prepared.urls)",
        'Label("Export to Files", systemImage: "square.and.arrow.up")',
        'Label("Export Files", systemImage: "square.and.arrow.up")',
        'Label("Move", systemImage: "folder")',
        "presentationStore.move(items, to: folderID)",
        "selectedPresentedReferences",
        "let snapshot = makeVisibleGallerySnapshot()",
        "VaultGalleryContentSnapshot",
        "sourceByID: snapshot.sourceByID",
        "folders: visibleGalleryFolders",
        "items: snapshot.presentations",
        "priority: .utility",
        "actor VaultGeneralFileThumbnailPipeline",
        "private var waiters: [PermitWaiter]",
        "@State private var thumbnailImageProcessor = VaultSecureImageProcessor()",
        "@State private var previewImageProcessor = VaultSecureImageProcessor()",
        "@State private var generalFileThumbnailPipeline = VaultGeneralFileThumbnailPipeline()",
        "let renderedImage = try await generalFileThumbnailPipeline.image(",
        "cacheMissImageProcessor.prepareThumbnail(",
        "previewImageProcessor.preparePreview(",
        "session.cancelSensitiveTask(previewTaskID)",
        "await session.performSensitiveTask { capability in",
    ):
        if required not in gallery_source:
            violations.append(
                f"KeyHollow/Photos/VaultGalleryView.swift: unified gallery "
                f"composition is missing {required!r}"
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
            if re.search(pattern, gallery_source) is None:
                violations.append(
                    "KeyHollow/Photos/VaultGalleryView.swift: encrypted-video "
                    f"playback lifecycle integration is missing {requirement}"
                )
        if re.search(
            r"try\s+await\s+videoPlayback\.(?:run|prepare)\(",
            gallery_source,
        ) is None:
            violations.append(
                "KeyHollow/Photos/VaultGalleryView.swift: video playback must "
                "enter through the app-owned coordinator"
            )

        open_route_start = match_position(
            r"\bvar\s+openRoute\s*:\s*VaultGalleryOpenRoute\b",
            gallery_source,
        )
        open_route_end = gallery_source.find(
            "private static func",
            open_route_start,
        )
        open_route_source = gallery_source[
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
                r"await\s+videoPlayback\.dismissAndWait\s*\(",
                "active-vault change",
            ),
            (
                r"\.onChange\s*\(\s*of\s*:\s*session\.securityEpoch\b",
                r"videoPlayback\.dismiss\s*\(",
                "session security epoch",
            ),
            (
                r"\.onDisappear\b",
                r"videoPlayback\.dismiss\s*\(",
                "gallery disappearance",
            ),
        ):
            lifecycle_match = re.search(lifecycle_pattern, gallery_source)
            lifecycle_window = (
                gallery_source[
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
                    f"{lifecycle_name} must revoke and clean up video playback"
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
    ):
        if obsolete in gallery_source:
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

