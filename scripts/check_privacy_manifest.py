#!/usr/bin/env python3
"""Validate KeyHollow's privacy declaration and its packaged app resource."""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path
from typing import Any
from xml.parsers.expat import ExpatError


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_RELATIVE_PATH = Path("KeyHollow/Resources/PrivacyInfo.xcprivacy")
MANIFEST_PATH = ROOT / MANIFEST_RELATIVE_PATH
PROJECT_PATH = ROOT / "project.yml"

EXPECTED_TOP_LEVEL_KEYS = {
    "NSPrivacyTracking",
    "NSPrivacyCollectedDataTypes",
    "NSPrivacyAccessedAPITypes",
}
# CA92.1 covers the app-only unlock-attempt state stored in UserDefaults.
# E174.1 covers the free-space preflight before staging a selected vault file.
# 35F9.1 covers elapsed-time measurement for the short-lived, in-app deletion
# authorization timer. The derived value is never sent off-device.
# C617.1 and 3B52.1 cover metadata reads within KeyHollow's container and on
# documents a person explicitly selected through the system document picker.
EXPECTED_ACCESSED_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"E174.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1", "3B52.1"},
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate the source privacy manifest and, when supplied, the copy "
            "packaged at the root of a built KeyHollow.app bundle."
        )
    )
    parser.add_argument(
        "--app-bundle",
        type=Path,
        help="Path to a built KeyHollow.app directory whose manifest must match.",
    )
    return parser.parse_args()


def load_plist(path: Path, label: str, violations: list[str]) -> dict[str, Any] | None:
    if not path.is_file():
        violations.append(f"{label}: missing {path}")
        return None

    try:
        payload = plistlib.loads(path.read_bytes())
    except (OSError, ValueError, ExpatError, plistlib.InvalidFileException) as error:
        violations.append(f"{label}: invalid property list ({error})")
        return None

    if not isinstance(payload, dict):
        violations.append(f"{label}: root value must be a dictionary")
        return None
    return payload


def validate_payload(
    payload: dict[str, Any],
    label: str,
    violations: list[str],
) -> None:
    actual_keys = set(payload)
    if actual_keys != EXPECTED_TOP_LEVEL_KEYS:
        violations.append(
            f"{label}: expected top-level keys {sorted(EXPECTED_TOP_LEVEL_KEYS)}, "
            f"got {sorted(actual_keys)}"
        )

    if payload.get("NSPrivacyTracking") is not False:
        violations.append(f"{label}: NSPrivacyTracking must be false")

    if payload.get("NSPrivacyCollectedDataTypes") != []:
        violations.append(
            f"{label}: NSPrivacyCollectedDataTypes must be an empty array"
        )

    accessed = payload.get("NSPrivacyAccessedAPITypes")
    if not isinstance(accessed, list):
        violations.append(f"{label}: NSPrivacyAccessedAPITypes must be an array")
        return

    actual_accessed_apis: dict[str, set[str]] = {}
    for index, declaration in enumerate(accessed):
        declaration_label = f"{label}: NSPrivacyAccessedAPITypes[{index}]"
        if not isinstance(declaration, dict):
            violations.append(f"{declaration_label} must be a dictionary")
            continue
        if set(declaration) != {
            "NSPrivacyAccessedAPIType",
            "NSPrivacyAccessedAPITypeReasons",
        }:
            violations.append(
                f"{declaration_label} contains missing or unexpected keys"
            )

        category = declaration.get("NSPrivacyAccessedAPIType")
        reasons = declaration.get("NSPrivacyAccessedAPITypeReasons")
        if not isinstance(category, str):
            violations.append(f"{declaration_label} has an invalid API category")
            continue
        if category in actual_accessed_apis:
            violations.append(f"{declaration_label} duplicates {category}")
            continue
        if not isinstance(reasons, list) or not all(
            isinstance(reason, str) for reason in reasons
        ):
            violations.append(f"{declaration_label} has an invalid reasons array")
            continue
        if len(reasons) != len(set(reasons)):
            violations.append(f"{declaration_label} contains duplicate reasons")
        actual_accessed_apis[category] = set(reasons)

    if actual_accessed_apis != EXPECTED_ACCESSED_APIS:
        violations.append(
            f"{label}: required-reason declarations changed; expected "
            f"{EXPECTED_ACCESSED_APIS}, got {actual_accessed_apis}"
        )


def app_target_body(project: str) -> str | None:
    match = re.search(
        r"(?ms)^  KeyHollow:\s*$\n(?P<body>.*?)(?=^  [A-Za-z0-9_]+:\s*$|^schemes:\s*$)",
        project,
    )
    return match.group("body") if match else None


def validate_project_wiring(violations: list[str]) -> None:
    try:
        project = PROJECT_PATH.read_text(encoding="utf-8")
    except OSError as error:
        violations.append(f"project.yml: could not read project spec ({error})")
        return

    target = app_target_body(project)
    if target is None:
        violations.append("project.yml: application target KeyHollow is missing")
        return

    sources_match = re.search(
        r"(?ms)^    sources:\s*$\n(?P<body>.*?)(?=^    [A-Za-z0-9_]+:\s*$)",
        target,
    )
    if sources_match is None:
        violations.append("project.yml: KeyHollow sources block is missing")
        return
    sources = sources_match.group("body")

    broad_source_match = re.search(
        r"(?ms)^      - path: KeyHollow\s*$\n(?P<body>.*?)(?=^      - |\Z)",
        sources,
    )
    exclusion_pattern = r"(?m)^          - Resources/PrivacyInfo\.xcprivacy\s*$"
    resource_pattern = (
        r"(?m)^      - path: KeyHollow/Resources/PrivacyInfo\.xcprivacy\s*$\n"
        r"^        buildPhase: resources\s*$"
    )
    if broad_source_match is None or re.search(
        exclusion_pattern,
        broad_source_match.group("body"),
    ) is None:
        violations.append(
            "project.yml: KeyHollow's broad source entry must exclude "
            "Resources/PrivacyInfo.xcprivacy"
        )
    if len(re.findall(resource_pattern, sources)) != 1:
        violations.append(
            "project.yml: KeyHollow must declare exactly one explicit "
            "PrivacyInfo.xcprivacy resources build-phase entry"
        )
    if sources.count("PrivacyInfo.xcprivacy") != 2:
        violations.append(
            "project.yml: KeyHollow sources must reference PrivacyInfo.xcprivacy "
            "only as the broad-source exclusion and explicit resource"
        )


def main() -> int:
    args = parse_arguments()
    violations: list[str] = []

    source_payload = load_plist(MANIFEST_PATH, "source manifest", violations)
    if source_payload is not None:
        validate_payload(source_payload, "source manifest", violations)
    validate_project_wiring(violations)

    if args.app_bundle is not None:
        app_bundle = args.app_bundle.resolve()
        if not app_bundle.is_dir():
            violations.append(f"app bundle: missing directory {app_bundle}")
        else:
            packaged_path = app_bundle / "PrivacyInfo.xcprivacy"
            packaged_payload = load_plist(
                packaged_path,
                "packaged manifest",
                violations,
            )
            if packaged_payload is not None:
                validate_payload(packaged_payload, "packaged manifest", violations)
                if source_payload is not None and packaged_payload != source_payload:
                    violations.append(
                        "packaged manifest: contents do not match the reviewed "
                        "source manifest"
                    )

    if violations:
        print("Privacy manifest violations:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    message = (
        "Privacy manifest passed: source declaration and XcodeGen resource "
        "wiring are exact."
    )
    if args.app_bundle is not None:
        message += " The packaged app manifest matches."
    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
