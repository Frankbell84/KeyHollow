#!/usr/bin/env python3
"""Validate KeyHollow App Store provisioning material without exposing secrets."""

from __future__ import annotations

import argparse
import copy
import hashlib
import plistlib
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


TEAM_ID = "P38X56QHU9"
APP_IDENTIFIER = f"{TEAM_ID}.com.keyhollow.app"
THUMBNAIL_IDENTIFIER = f"{TEAM_ID}.com.keyhollow.app.vault-thumbnail"
UUID_PATTERN = re.compile(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
)


class SigningMaterialError(ValueError):
    """Raised when signing material is not safe for production use."""


@dataclass(frozen=True)
class ProfileSummary:
    name: str
    uuid: str
    expiration: datetime


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--certificate-der", type=Path)
    parser.add_argument("--app-profile-plist", type=Path)
    parser.add_argument("--thumbnail-profile-plist", type=Path)
    parser.add_argument("--expected-app-uuid")
    parser.add_argument("--expected-thumbnail-uuid")
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SigningMaterialError(message)


def utc_datetime(value: Any, field: str, label: str) -> datetime:
    require(isinstance(value, datetime), f"{label}: {field} is not a date")
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def validate_profile(
    profile: Any,
    *,
    label: str,
    expected_application_identifier: str,
    certificate_der: bytes,
    now: datetime,
    expected_uuid: str | None = None,
) -> ProfileSummary:
    require(isinstance(profile, dict), f"{label}: profile root is not a dictionary")

    name = profile.get("Name")
    require(
        isinstance(name, str)
        and bool(name.strip())
        and "\n" not in name
        and "\r" not in name,
        f"{label}: profile name is missing or unsafe",
    )

    uuid = profile.get("UUID")
    require(
        isinstance(uuid, str) and UUID_PATTERN.fullmatch(uuid) is not None,
        f"{label}: profile UUID is not canonical",
    )
    if expected_uuid is not None:
        require(
            uuid.lower() == expected_uuid.lower(),
            f"{label}: embedded profile UUID does not match the installed profile",
        )

    require(
        profile.get("TeamIdentifier") == [TEAM_ID],
        f"{label}: TeamIdentifier must contain only {TEAM_ID}",
    )
    require(
        profile.get("ApplicationIdentifierPrefix") == [TEAM_ID],
        f"{label}: ApplicationIdentifierPrefix must contain only {TEAM_ID}",
    )
    platforms = profile.get("Platform")
    require(
        isinstance(platforms, list) and "iOS" in platforms,
        f"{label}: profile is not valid for iOS",
    )

    creation = utc_datetime(profile.get("CreationDate"), "CreationDate", label)
    expiration = utc_datetime(profile.get("ExpirationDate"), "ExpirationDate", label)
    require(
        creation <= now + timedelta(minutes=10),
        f"{label}: profile creation date is unexpectedly in the future",
    )
    require(expiration > now, f"{label}: profile is expired")
    require(expiration > creation, f"{label}: expiration must follow creation")

    time_to_live = profile.get("TimeToLive")
    require(
        type(time_to_live) is int and time_to_live > 0,
        f"{label}: TimeToLive is missing or invalid",
    )
    require(
        "ProvisionedDevices" not in profile,
        f"{label}: device-bound profile is not App Store distribution material",
    )
    require(
        "ProvisionsAllDevices" not in profile
        or profile["ProvisionsAllDevices"] is False,
        f"{label}: enterprise profile is not App Store distribution material",
    )

    developer_certificates = profile.get("DeveloperCertificates")
    require(
        isinstance(developer_certificates, list)
        and len(developer_certificates) == 1
        and isinstance(developer_certificates[0], bytes),
        f"{label}: exactly one DER signing certificate is required",
    )
    require(
        developer_certificates[0] == certificate_der,
        f"{label}: embedded signing certificate does not match the imported P12",
    )

    entitlements = profile.get("Entitlements")
    require(isinstance(entitlements, dict), f"{label}: entitlements are missing")
    require(
        entitlements.get("application-identifier")
        == expected_application_identifier,
        f"{label}: application identifier does not match the expected bundle",
    )
    require(
        entitlements.get("com.apple.developer.team-identifier") == TEAM_ID,
        f"{label}: entitlement team identifier must be {TEAM_ID}",
    )
    require(
        entitlements.get("get-task-allow") is False,
        f"{label}: distribution profile must disable get-task-allow",
    )
    require(
        entitlements.get("beta-reports-active") is True,
        f"{label}: distribution profile must enable beta reports",
    )

    return ProfileSummary(name=name, uuid=uuid, expiration=expiration)


def load_plist(path: Path, label: str) -> dict[str, Any]:
    try:
        with path.open("rb") as stream:
            payload = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise SigningMaterialError(f"{label}: could not read profile plist: {error}") from error
    require(isinstance(payload, dict), f"{label}: profile plist is not a dictionary")
    return payload


def validate_material(
    *,
    certificate_der: bytes,
    app_profile: dict[str, Any],
    thumbnail_profile: dict[str, Any],
    now: datetime,
    expected_app_uuid: str | None = None,
    expected_thumbnail_uuid: str | None = None,
) -> tuple[ProfileSummary, ProfileSummary]:
    require(bool(certificate_der), "signing certificate is empty")
    app = validate_profile(
        app_profile,
        label="app profile",
        expected_application_identifier=APP_IDENTIFIER,
        certificate_der=certificate_der,
        now=now,
        expected_uuid=expected_app_uuid,
    )
    thumbnail = validate_profile(
        thumbnail_profile,
        label="thumbnail profile",
        expected_application_identifier=THUMBNAIL_IDENTIFIER,
        certificate_der=certificate_der,
        now=now,
        expected_uuid=expected_thumbnail_uuid,
    )
    require(
        app.uuid.lower() != thumbnail.uuid.lower(),
        "app and thumbnail profiles must be distinct",
    )
    return app, thumbnail


def valid_fixture(
    *, application_identifier: str, uuid: str, certificate_der: bytes, now: datetime
) -> dict[str, Any]:
    return {
        "Name": f"Fixture {uuid[:8]}",
        "UUID": uuid,
        "TeamIdentifier": [TEAM_ID],
        "ApplicationIdentifierPrefix": [TEAM_ID],
        "Platform": ["iOS"],
        "CreationDate": now - timedelta(minutes=1),
        "ExpirationDate": now + timedelta(days=365),
        "TimeToLive": 365,
        "DeveloperCertificates": [certificate_der],
        "Entitlements": {
            "application-identifier": application_identifier,
            "com.apple.developer.team-identifier": TEAM_ID,
            "get-task-allow": False,
            "beta-reports-active": True,
        },
    }


def self_test() -> int:
    now = datetime(2026, 9, 10, tzinfo=timezone.utc)
    certificate_der = b"fixture-distribution-certificate"
    app = valid_fixture(
        application_identifier=APP_IDENTIFIER,
        uuid="11111111-1111-4111-8111-111111111111",
        certificate_der=certificate_der,
        now=now,
    )
    thumbnail = valid_fixture(
        application_identifier=THUMBNAIL_IDENTIFIER,
        uuid="22222222-2222-4222-8222-222222222222",
        certificate_der=certificate_der,
        now=now,
    )
    validate_material(
        certificate_der=certificate_der,
        app_profile=app,
        thumbnail_profile=thumbnail,
        now=now,
    )

    mutations: list[tuple[str, str, Any]] = [
        ("TeamIdentifier", "TeamIdentifier", ["WRONGTEAM"]),
        (
            "ApplicationIdentifierPrefix",
            "ApplicationIdentifierPrefix",
            ["WRONGTEAM"],
        ),
        ("platform", "Platform", ["macOS"]),
        (
            "future creation date",
            "CreationDate",
            now + timedelta(minutes=11),
        ),
        ("application identifier", "application-identifier", f"{TEAM_ID}.*"),
        (
            "entitlement team identifier",
            "com.apple.developer.team-identifier",
            "WRONGTEAM",
        ),
        ("debug entitlement", "get-task-allow", True),
        ("beta entitlement", "beta-reports-active", False),
        ("certificate", "DeveloperCertificates", [b"wrong-certificate"]),
        (
            "multiple certificates",
            "DeveloperCertificates",
            [certificate_der, b"another-certificate"],
        ),
        ("UUID", "UUID", "not-a-uuid"),
        ("device list", "ProvisionedDevices", ["device"]),
        ("enterprise", "ProvisionsAllDevices", True),
        ("malformed enterprise flag", "ProvisionsAllDevices", 1),
        ("boolean TimeToLive", "TimeToLive", True),
        ("nonpositive TimeToLive", "TimeToLive", 0),
        ("expiration", "ExpirationDate", now - timedelta(seconds=1)),
    ]
    entitlement_keys = {
        "application-identifier",
        "com.apple.developer.team-identifier",
        "get-task-allow",
        "beta-reports-active",
    }
    for label, key, value in mutations:
        invalid = copy.deepcopy(app)
        if key in entitlement_keys:
            invalid["Entitlements"][key] = value
        else:
            invalid[key] = value
        try:
            validate_material(
                certificate_der=certificate_der,
                app_profile=invalid,
                thumbnail_profile=thumbnail,
                now=now,
            )
        except SigningMaterialError:
            continue
        raise AssertionError(f"self-test did not reject invalid {label}")

    try:
        validate_material(
            certificate_der=certificate_der,
            app_profile=app,
            thumbnail_profile=thumbnail,
            now=now,
            expected_app_uuid="33333333-3333-4333-8333-333333333333",
        )
    except SigningMaterialError:
        pass
    else:
        raise AssertionError("self-test did not reject mismatched embedded UUID")

    try:
        validate_material(
            certificate_der=certificate_der,
            app_profile=app,
            thumbnail_profile=thumbnail,
            now=now,
            expected_thumbnail_uuid="33333333-3333-4333-8333-333333333333",
        )
    except SigningMaterialError:
        pass
    else:
        raise AssertionError(
            "self-test did not reject mismatched thumbnail embedded UUID"
        )

    duplicate_app = copy.deepcopy(app)
    duplicate_thumbnail = copy.deepcopy(thumbnail)
    duplicate_app["UUID"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    duplicate_thumbnail["UUID"] = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    try:
        validate_material(
            certificate_der=certificate_der,
            app_profile=duplicate_app,
            thumbnail_profile=duplicate_thumbnail,
            now=now,
        )
    except SigningMaterialError:
        pass
    else:
        raise AssertionError(
            "self-test did not reject case-variant duplicate profile UUIDs"
        )

    try:
        validate_material(
            certificate_der=b"",
            app_profile=app,
            thumbnail_profile=thumbnail,
            now=now,
        )
    except SigningMaterialError:
        pass
    else:
        raise AssertionError("self-test did not reject an empty certificate")

    print("Signing-material verifier self-test passed.")
    return 0


def main() -> int:
    args = parse_arguments()
    if args.self_test:
        return self_test()

    required_paths = {
        "--certificate-der": args.certificate_der,
        "--app-profile-plist": args.app_profile_plist,
        "--thumbnail-profile-plist": args.thumbnail_profile_plist,
    }
    missing = [name for name, value in required_paths.items() if value is None]
    if missing:
        print(f"Missing required arguments: {', '.join(missing)}", file=sys.stderr)
        return 2

    try:
        certificate_der = args.certificate_der.read_bytes()
        app, thumbnail = validate_material(
            certificate_der=certificate_der,
            app_profile=load_plist(args.app_profile_plist, "app profile"),
            thumbnail_profile=load_plist(
                args.thumbnail_profile_plist, "thumbnail profile"
            ),
            now=datetime.now(timezone.utc),
            expected_app_uuid=args.expected_app_uuid,
            expected_thumbnail_uuid=args.expected_thumbnail_uuid,
        )
    except (OSError, SigningMaterialError) as error:
        print(f"Signing material is not release-safe: {error}", file=sys.stderr)
        return 1

    fingerprint = hashlib.sha1(certificate_der).hexdigest().upper()
    print(
        "Verified production signing material: "
        f"certificate {fingerprint}; app profile {app.uuid} expires "
        f"{app.expiration.date().isoformat()}; thumbnail profile "
        f"{thumbnail.uuid} expires {thumbnail.expiration.date().isoformat()}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
