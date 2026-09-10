#!/usr/bin/env python3
"""Fail CI when source trees could silently package unreviewed files."""

from __future__ import annotations

import argparse
import fnmatch
import json
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
IGNORED_DIRECTORIES = {".git", "build", "DerivedData", "__pycache__"}
BANNED_NAMES = {".DS_Store", "Thumbs.db"}
BANNED_PATTERNS = ("*.bak", "*.orig", "*.rej", "*.swp", "*.tmp", "*~")
SOURCE_SUFFIXES = {".swift", ".c", ".h"}
ASSET_FILE_SUFFIXES = {".png", ".jpg", ".jpeg", ".pdf", ".svg", ".heic"}
ASSET_CONTAINER_SUFFIXES = {".xcassets", ".appiconset", ".imageset"}
ASSET_CATALOGS = {
    Path("KeyHollow/Resources/Assets.xcassets"),
    Path("KeyHollowVaultThumbnailExtension/Resources/Assets.xcassets"),
}
EXACT_NON_SOURCE_FILES = {
    Path("KeyHollow/Resources/Info.plist"),
    Path("KeyHollow/Resources/PrivacyInfo.xcprivacy"),
    Path("KeyHollow/ThirdParty/Argon2id/LICENSE"),
    Path("KeyHollowVaultThumbnailExtension/Info.plist"),
}
SOURCE_ROOTS = {
    Path("KeyHollow"),
    Path("KeyHollowVaultThumbnailExtension"),
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def referenced_asset_names(payload: Any) -> list[str]:
    names: list[str] = []
    if isinstance(payload, dict):
        for key, value in payload.items():
            if key == "filename" and isinstance(value, str):
                names.append(value)
            else:
                names.extend(referenced_asset_names(value))
    elif isinstance(payload, list):
        for value in payload:
            names.extend(referenced_asset_names(value))
    return names


def audit_asset_catalog(repository_root: Path, relative_root: Path) -> list[str]:
    catalog = repository_root / relative_root
    violations: list[str] = []
    if catalog.is_symlink():
        return [f"{relative_root.as_posix()}: asset catalog cannot be a symlink"]
    if not catalog.is_dir():
        return [f"{relative_root.as_posix()}: required asset catalog is missing"]

    referenced_files: set[Path] = set()
    contents_files: set[Path] = set()
    for path in sorted(catalog.rglob("*")):
        relative = path.relative_to(repository_root)
        if path.is_symlink():
            violations.append(f"{relative.as_posix()}: symlinks are forbidden")
            continue
        if path.is_dir():
            if path.suffix not in ASSET_CONTAINER_SUFFIXES:
                violations.append(
                    f"{relative.as_posix()}: unreviewed asset-container type"
                )
            continue
        if path.name != "Contents.json":
            continue

        contents_files.add(relative)
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            violations.append(f"{relative.as_posix()}: invalid asset metadata ({error})")
            continue
        if not isinstance(payload, dict):
            violations.append(f"{relative.as_posix()}: asset metadata must be an object")
            continue
        for filename in referenced_asset_names(payload):
            candidate = path.parent / filename
            try:
                resolved_relative = candidate.relative_to(repository_root)
            except ValueError:
                violations.append(
                    f"{relative.as_posix()}: asset filename escapes the repository"
                )
                continue
            if not is_relative_to(resolved_relative, relative_root):
                violations.append(
                    f"{relative.as_posix()}: asset filename escapes its catalog"
                )
                continue
            if Path(filename).is_absolute() or ".." in Path(filename).parts:
                violations.append(
                    f"{relative.as_posix()}: asset filename contains an unsafe path"
                )
                continue
            referenced_files.add(resolved_relative)
            if candidate.suffix.lower() not in ASSET_FILE_SUFFIXES:
                violations.append(
                    f"{resolved_relative.as_posix()}: unreviewed asset file type"
                )
            if not candidate.is_file() or candidate.is_symlink():
                violations.append(
                    f"{resolved_relative.as_posix()}: referenced asset is missing or unsafe"
                )

    for path in sorted(catalog.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(repository_root)
        if relative not in contents_files and relative not in referenced_files:
            violations.append(
                f"{relative.as_posix()}: asset file is not declared by Contents.json"
            )
    return violations


def audit_source_trees(repository_root: Path) -> list[str]:
    violations: list[str] = []
    for relative_root in sorted(SOURCE_ROOTS):
        source_root = repository_root / relative_root
        if source_root.is_symlink():
            violations.append(f"{relative_root.as_posix()}: source root is a symlink")
            continue
        if not source_root.is_dir():
            violations.append(f"{relative_root.as_posix()}: source root is missing")
            continue
        for path in sorted(source_root.rglob("*")):
            relative = path.relative_to(repository_root)
            if path.is_symlink():
                violations.append(f"{relative.as_posix()}: symlinks are forbidden")
                continue
            if not path.is_file():
                continue
            if any(is_relative_to(relative, catalog) for catalog in ASSET_CATALOGS):
                continue
            if relative in EXACT_NON_SOURCE_FILES:
                continue
            if path.suffix.lower() in SOURCE_SUFFIXES and "Resources" not in relative.parts:
                continue
            violations.append(
                f"{relative.as_posix()}: unreviewed file in an XcodeGen source tree"
            )

    for catalog in sorted(ASSET_CATALOGS):
        violations.extend(audit_asset_catalog(repository_root, catalog))
    return violations


def audit_general_hygiene(repository_root: Path) -> list[str]:
    violations: list[str] = []
    for path in repository_root.rglob("*"):
        relative_parts = path.relative_to(repository_root).parts
        if any(part in IGNORED_DIRECTORIES for part in relative_parts):
            continue
        if path.is_dir() and path.name == "xcuserdata":
            violations.append(f"{path.relative_to(repository_root).as_posix()}: user data")
            continue
        if not path.is_file():
            continue
        if path.name in BANNED_NAMES or any(
            fnmatch.fnmatch(path.name, pattern) for pattern in BANNED_PATTERNS
        ):
            violations.append(
                f"{path.relative_to(repository_root).as_posix()}: temporary file"
            )

    project_path = repository_root / "project.yml"
    if not project_path.is_file():
        violations.append("project.yml: project definition is missing")
        return violations
    project = project_path.read_text(encoding="utf-8")
    for abandoned_marker in ("CFBundleTypeIconFiles", "UTTypeIcons:"):
        if abandoned_marker in project:
            violations.append(
                f"project.yml: abandoned icon attempt remains ({abandoned_marker})"
            )

    legacy_icons = repository_root / "KeyHollow" / "Resources" / "DocumentIcons"
    if legacy_icons.exists() and any(legacy_icons.iterdir()):
        violations.append(
            "KeyHollow/Resources/DocumentIcons: unused legacy icon assets remain"
        )
    return violations


def write_fixture(root: Path) -> None:
    files = {
        Path("project.yml"): "name: Fixture\n",
        Path("KeyHollow/App/App.swift"): "struct App {}\n",
        Path("KeyHollow/Resources/PrivacyInfo.xcprivacy"): "privacy\n",
        Path("KeyHollow/ThirdParty/Argon2id/LICENSE"): "license\n",
        Path("KeyHollow/Resources/Assets.xcassets/Contents.json"): '{"info": {}}',
        Path(
            "KeyHollow/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
        ): '{"images": [{"filename": "AppIcon.png"}]}',
        Path(
            "KeyHollow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        ): "image",
        Path("KeyHollowVaultThumbnailExtension/ThumbnailProvider.swift"): "class T {}\n",
        Path(
            "KeyHollowVaultThumbnailExtension/Resources/Assets.xcassets/Contents.json"
        ): '{"info": {}}',
        Path(
            "KeyHollowVaultThumbnailExtension/Resources/Assets.xcassets/"
            "KeyHollowVaultIcon.imageset/Contents.json"
        ): '{"images": [{"filename": "Icon.png"}]}',
        Path(
            "KeyHollowVaultThumbnailExtension/Resources/Assets.xcassets/"
            "KeyHollowVaultIcon.imageset/Icon.png"
        ): "image",
    }
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="keyhollow-release-hygiene-") as name:
        root = Path(name)
        write_fixture(root)
        assert audit_source_trees(root) == []

        stray = root / "KeyHollow" / "App" / "private-notes.txt"
        stray.write_text("must not be packaged", encoding="utf-8")
        assert any("unreviewed file" in item for item in audit_source_trees(root))
        stray.unlink()

        unreferenced = (
            root
            / "KeyHollow"
            / "Resources"
            / "Assets.xcassets"
            / "AppIcon.appiconset"
            / "orphan.png"
        )
        unreferenced.write_text("image", encoding="utf-8")
        assert any("not declared" in item for item in audit_source_trees(root))

    print("Release-hygiene checker self-test passed.")
    return 0


def main() -> int:
    args = parse_arguments()
    if args.self_test:
        return self_test()

    self_test()
    violations = audit_general_hygiene(ROOT) + audit_source_trees(ROOT)
    if violations:
        print("Release hygiene violations:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    print(
        "Release hygiene passed: no editor debris, temporary files, abandoned "
        "document-icon attempts, or unreviewed source-tree resources are present."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
