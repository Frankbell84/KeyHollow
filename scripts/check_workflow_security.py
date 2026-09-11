#!/usr/bin/env python3
"""Fail closed when GitHub Actions release controls drift from policy.

This checker deliberately uses only the Python standard library.  It is not a
general YAML linter; it enforces the small, security-sensitive workflow surface
that KeyHollow intentionally supports.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIRECTORY = ROOT / ".github" / "workflows"
EXPECTED_WORKFLOWS = {
    "ios-build.yml",
    "release-signing-preflight.yml",
    "testflight-beta.yml",
    "testflight.yml",
}
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
ACTION_REFERENCE = re.compile(
    r"^\s*(?:-\s*)?uses:\s*([^\s#]+)(?:\s+#.*)?$", re.MULTILINE
)
SECRET_REFERENCE = re.compile(r"secrets\.([A-Z0-9_]+)")
BRACKET_SECRET_REFERENCE = re.compile(
    r"secrets\s*\[\s*(['\"])([A-Z0-9_]+)\1\s*]",
    re.IGNORECASE,
)

APPROVED_ROTATION_BINDINGS = {
    "EXPECTED_API_KEY_ID": "W3UF745JN4",
    "EXPECTED_API_ISSUER_ID": "ba45844d-8147-4d78-932b-bfdbbbc55dc0",
    "EXPECTED_SIGNING_CERTIFICATE_SHA1": (
        "7E2342E196D2A56E95A05BCBDD473FE3799B7EDD"
    ),
    "EXPECTED_APP_PROFILE_UUID": "b9a24dc9-04a3-40e1-b0e3-fe7538e6e341",
    "EXPECTED_THUMBNAIL_PROFILE_UUID": "c9564b6f-22cd-490b-9f59-f91e98a4a065",
}

EXPECTED_CERTIFICATE_COMPARISONS = [
    (
        'if ! cmp -s "$RUNNER_TEMP/keyhollow-distribution.cer" '
        '"$APP_CERTIFICATE_DIRECTORY/cert0"; then'
    ),
    (
        'if ! cmp -s "$RUNNER_TEMP/keyhollow-distribution.cer" '
        '"$THUMBNAIL_CERTIFICATE_DIRECTORY/cert0"; then'
    ),
]

EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS = [
    (
        'codesign --display '
        '--extract-certificates="$APP_CERTIFICATE_DIRECTORY/cert" '
        '"$SIGNED_APP_PATH"'
    ),
    (
        'codesign --display '
        '--extract-certificates="$THUMBNAIL_CERTIFICATE_DIRECTORY/cert" '
        '"$SIGNED_EXTENSION_PATH"'
    ),
]

COMMON_CLEANUP_REQUIREMENTS = (
    "if: always()",
    'KEYCHAIN_PATH="$RUNNER_TEMP/keyhollow-signing.keychain-db"',
    'security lock-keychain "$KEYCHAIN_PATH"',
    'security delete-keychain "$KEYCHAIN_PATH"',
    'PROFILE_DIRECTORY="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"',
    '"$RUNNER_TEMP/keyhollow-distribution.p12"',
    '"$RUNNER_TEMP/keyhollow-distribution.pem"',
    '"$RUNNER_TEMP/keyhollow-distribution.cer"',
    '"$RUNNER_TEMP/keyhollow-app.mobileprovision"',
    '"$RUNNER_TEMP/keyhollow-thumbnail.mobileprovision"',
    '"$RUNNER_TEMP/keyhollow-app-profile.plist"',
    '"$RUNNER_TEMP/keyhollow-thumbnail-profile.plist"',
    '"$RUNNER_TEMP/keyhollow-signed-app-profile.plist"',
    '"$RUNNER_TEMP/keyhollow-signed-thumbnail-profile.plist"',
    '"$PROFILE_DIRECTORY/$EXPECTED_APP_PROFILE_UUID.mobileprovision"',
    '"$PROFILE_DIRECTORY/$EXPECTED_THUMBNAIL_PROFILE_UUID.mobileprovision"',
)

WORKFLOW_CLEANUP_REQUIREMENTS = {
    "release-signing-preflight.yml": (
        "build/PreflightExportOptions.plist",
        '"$RUNNER_TEMP/keyhollow-preflight-ipa"',
        '"$RUNNER_TEMP/keyhollow-signed-app-certificates"',
        '"$RUNNER_TEMP/keyhollow-signed-thumbnail-certificates"',
        "build/KeyHollowPreflight.xcarchive",
        "build/preflight-export",
    ),
    "testflight.yml": (
        "build/ExportOptions.plist",
        '"$RUNNER_TEMP/keyhollow-signed-ipa"',
        '"$RUNNER_TEMP/keyhollow-app-codesign-certificates"',
        '"$RUNNER_TEMP/keyhollow-thumbnail-codesign-certificates"',
        "build/KeyHollow.xcarchive",
        "build/export",
        '"$HOME/.appstoreconnect/private_keys/AuthKey_${EXPECTED_API_KEY_ID}.p8"',
    ),
}

CLEANUP_RUN_BODY_SHA256 = {
    "release-signing-preflight.yml": (
        "3a863f63db09420d1eac529a5521425d1f28b00f167d89462a3d48b88a392674"
    ),
    "testflight.yml": (
        "a833e4348a802b96d1cbba7ce6c7e0b3fa486b5cb511e45f9094869a801c2fda"
    ),
}

SIGNING_SECRET_UNSET_COMMAND = (
    "unset BUILD_CERTIFICATE_BASE64 BUILD_PROVISION_PROFILE_BASE64 "
    "THUMBNAIL_PROVISION_PROFILE_BASE64 P12_PASSWORD KEYCHAIN_PASSWORD"
)

SIGNING_IMPORT_COMMAND = (
    'security import "$CERTIFICATE_PATH" -P "$P12_PASSWORD" -x '
    '-T /usr/bin/codesign -t agg -f pkcs12 -k "$KEYCHAIN_PATH"'
)

SIGNING_LEAF_EXTRACTION_COMMAND = (
    'openssl pkcs12 -in "$CERTIFICATE_PATH" -clcerts -nokeys '
    '-passin env:P12_PASSWORD -out "$SIGNING_CERTIFICATE_PEM"'
)

SIGNING_IDENTITY_LIST_COMMAND = (
    'IDENTITY_LIST=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH")'
)

SIGNING_VALID_IDENTITY_COUNT_COMMAND = (
    "VALID_IDENTITY_COUNT=$(printf '%s\\n' \"$IDENTITY_LIST\" | awk "
    "'$1 ~ /^[0-9]+\\)$/ && length($2) == 40 && $2 ~ /^[0-9A-Fa-f]+$/ "
    "{ count += 1 } END { print count + 0 }')"
)

SIGNING_MATCHING_IDENTITY_COUNT_COMMAND = (
    "IDENTITY_MATCH_COUNT=$(printf '%s\\n' \"$IDENTITY_LIST\" | awk "
    "-v expected=\"$SIGNING_CERTIFICATE_SHA1\" "
    "'$1 ~ /^[0-9]+\\)$/ && toupper($2) == expected "
    "{ count += 1 } END { print count + 0 }')"
)

STRICT_SIGNING_TEARDOWN_REQUIREMENTS = (
    'test -e "$KEYCHAIN_PATH"',
    'security lock-keychain "$KEYCHAIN_PATH"',
    'security delete-keychain "$KEYCHAIN_PATH"',
    'test ! -e "$KEYCHAIN_PATH"',
    'security list-keychains -d user | grep -Fq "$KEYCHAIN_PATH"',
)

TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND = (
    'node scripts/verify_testflight_build_number.mjs "$REQUESTED_BUILD_NUMBER"'
)

ENVIRONMENT_VERIFIER_REQUIREMENTS = (
    'ENVIRONMENT_NAME = "production-testflight"',
    'TRUSTED_BRANCH = "main"',
    'REQUIRED_REVIEWER_LOGIN = "Frankbell84"',
    'GITHUB_API_ORIGIN = "https://api.github.com"',
    'environment.get("can_admins_bypass") is not False',
    'expected_rule_types = ["branch_policy", "required_reviewers"]',
    'required_reviewers_rule.get("prevent_self_review") is not False',
    'reviewer.get("login") != REQUIRED_REVIEWER_LOGIN',
    'reviewer.get("type") != "User"',
    '"custom_branch_policies": True',
    '"protected_branches": False',
    'policy_names != [TRUSTED_BRANCH]',
    "PRODUCTION_RELEASE_GUARD",
    "deployment-branch-policies?per_page=100",
    'trusted_branch.get("protected") is not True',
    "validate_github_api_url(url, repository)",
    "if url not in release_api_urls(repository)",
    "urllib.request.build_opener(RejectRedirectHandler())",
    "validate_github_api_url(response.geturl(), repository)",
)

# Git stores these sources with LF endings; canonicalizing CRLF permits the
# same byte-level content check in a Windows checkout with core.autocrlf=true.
PRIVILEGED_SOURCE_SHA256 = {
    "scripts/verify_release_source.py": (
        "8a11cd7c11b9363f83d2dfd4f9ca7efa59c46664fc6ea2219c5d9582201da6cd"
    ),
    "scripts/verify_release_environment.py": (
        "82e97606c07844a680245c0d27004f8c24a5c1749768c8850338e4b52848f6c4"
    ),
    "scripts/verify_testflight_build_number.mjs": (
        "93d71d853ff682e46bef08409d5e2939fa1723684880625a0151fd25d04374ce"
    ),
    "scripts/verify_signing_material.py": (
        "7c970933dca9b419190140080d21ce43344baec1672efb04eba55332b4254bd4"
    ),
    "scripts/check_release_hygiene.py": (
        "9ff597ee8db1228de2e91df3863a34e83c73305b2f00fe08faf5a931929cdee3"
    ),
    "scripts/check_architecture_boundaries.py": (
        "6de4a7ce013c4be80d851e1dec9a98b77d638ed401582f7645279a11149f1c4c"
    ),
    "scripts/check_privacy_manifest.py": (
        "c8c255c8d6465aafd04f941daa4bee3fa0f3a9881390032666f3eb38fa0c979a"
    ),
    "scripts/install_xcodegen.sh": (
        "232f0b11e50aba390d23206692ba3c3ec9e72fa83af2dd30876bc3486188ee9d"
    ),
    "project.yml": (
        "4bb01a4915eb25fcb1a954f2042743b74cb85109507d80b252f4ff19ba1c1375"
    ),
}

# Complete normalized workflow fingerprints are the final fail-closed guard
# against YAML constructs that the deliberately small structural parser does
# not interpret (for example aliases, quoted keys, or comment-based spoofing).
# Path.read_text() applies universal-newline normalization before these values
# are calculated, so the pins remain stable in LF and CRLF checkouts.
RELEASE_WORKFLOW_SHA256: dict[str, str] = {
    "ios-build.yml": (
        "9554afac60a5dc035799c25f30231f7685484025501d2cea25258c19d2a2e304"
    ),
    "release-signing-preflight.yml": (
        "d082072d96e0694b37e0ce220044efe6a43e8df4b696c6f9c9ff67a72e75c165"
    ),
    "testflight-beta.yml": (
        "2aed9c97ea63adecbb29632b24e0286d20eb6812ea4aeb337880b16a2669e326"
    ),
    "testflight.yml": (
        "02611b0c5b3a31097abaca1cc49d34f7ba2e4b3218c7faf0339a1f86187efc8c"
    ),
}

RELEASE_CONCURRENCY_ENTRIES = [
    ("group", "keyhollow-production-testflight"),
    ("cancel-in-progress", "false"),
]

RELEASE_JOB_ENTRIES = [
    (
        "if",
        "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
    ),
    ("runs-on", "macos-15"),
    ("timeout-minutes", "30"),
    ("environment", "production-testflight"),
    ("env", ""),
    ("steps", ""),
]

RELEASE_TOOLCHAIN_COMMAND_LINES = [
    "set -euo pipefail",
    "test \"$(uname -m)\" = 'arm64'",
    "test \"$(xcodebuild -version | sed -n '1p')\" = 'Xcode 26.0.1'",
    "test \"$(xcodebuild -version | sed -n '2p')\" = 'Build version 17A400'",
    "test \"$(xcrun --sdk iphoneos --show-sdk-version)\" = '26.0'",
    (
        "python3 -I -c 'import json, subprocess, sys; runtimes = "
        "json.loads(subprocess.check_output([\"xcrun\", \"simctl\", \"list\", "
        "\"runtimes\", \"available\", \"-j\"])); available = any(runtime.get("
        "\"identifier\") == \"com.apple.CoreSimulator.SimRuntime.iOS-26-0\" and "
        "runtime.get(\"isAvailable\") for runtime in runtimes.get(\"runtimes\", "
        "[])); print(\"Verified available iOS 26.0 runtime.\" if available else "
        "\"Required iOS 26.0 runtime is unavailable.\"); sys.exit(0 if available "
        "else 1)'"
    ),
]

FORBIDDEN_XCODEGEN_EXECUTION_KEYS = {
    "preGenCommand",
    "postGenCommand",
    "preBuildScripts",
    "postCompileScripts",
    "postBuildScripts",
    "buildToolPlugins",
    "buildRules",
    "preActions",
    "postActions",
    "preAction",
    "postAction",
}

PREFLIGHT_STEP_NAMES = [
    "Checkout",
    "Verify workflow security",
    "Verify selected production commit",
    "Verify pinned Xcode toolchain",
    "Verify exact-source CI succeeded",
    "Verify protected production environment",
    "Verify release hygiene",
    "Verify architecture boundaries",
    "Test signing-material verifier",
    "Test TestFlight build-number guard",
    "Verify privacy manifest",
    "Verify production identity",
    "Install XcodeGen",
    "Generate Xcode project",
    "Verify App Store Connect authentication",
    "Archive KeyHollow without signing",
    "Verify archived build and privacy manifest",
    "Install and verify cloud-signing material",
    "Create fingerprint-bound export options",
    "Export signed IPA without uploading",
    "Verify signed IPA and exact signing material",
    "Remove temporary signing material",
]

# The no-upload preflight is the most privileged non-publishing workflow.  Its
# executable bodies are pinned as reviewed units below so adding *any* shell,
# Python, Node, or network-capable command fails closed.  The values are filled
# from the reviewed workflow by maintainers whenever that workflow is changed.
PREFLIGHT_RUN_BODY_SHA256 = {
    "Verify workflow security": "6fb924cbeaaaeb9e4eaa88a1dd819a5d63a553df4aa9febe4216c2d5ce0e75b6",
    "Verify selected production commit": "f79d9bc2ae4d477cc5927d7c3bed7bbb93eb8292bc31cafef2e70d3053de8faf",
    "Verify pinned Xcode toolchain": "d2738fe0838201c38d5bad975b7d63ddfa4d05fe9cc95ffbec701a1b9aa38d88",
    "Verify exact-source CI succeeded": "06d2a54e800c67827d496f4fef62257c73309dcd89a08d23bc8a86abe526daef",
    "Verify protected production environment": "c71086227ac10e021aa621ce7337839856e65e4816ff73e34c8860bdc90927af",
    "Verify release hygiene": "d4109ac97876499508b699a43ab8ef561dafc8b0e7e2d59ed524120e768fca16",
    "Verify architecture boundaries": "d81975f9454f112ce3ad9334ad8a1a55387239e717771d4f8f264ac9e4c70f67",
    "Test signing-material verifier": "e33cffa19ef0dc72f849bb7caade1fc62886265280316c72cfe79169d85208b9",
    "Test TestFlight build-number guard": "4777c00970067209fb710f30d6c6c8769af5c0318e8470a31f6a140ee38dfcc8",
    "Verify privacy manifest": "7fdf0fab1f1b85dbb52ff3b26271e4ceb33e7b74ac2451c5d7a6b88fd3435e45",
    "Verify production identity": "56876a66f9e9fcd8694d359f2b89a3f2c9fa6e2681c9236dd1ca22d6ba8a1c03",
    "Install XcodeGen": "eff4eba980e3da81c56fa187333d420a74b0b26390057c64bd11e2080ea1eea3",
    "Generate Xcode project": "bdda8fc016233561ae1373260c36558e5d4c306a823ed94687bc0fcd9073ba5c",
    "Verify App Store Connect authentication": "e09d3052df83a2838fb58b0fdd565569d9a5ea44ea371252b006f8adeb01e0e2",
    "Install and verify cloud-signing material": "7a7177375bd4bcb5a4417386a9dee1c6088803ac554c4e105e1c51929da9d190",
    "Archive KeyHollow without signing": "f049352141029cc0612d4498aab86ed29670cd38df175f2950fd2947a1e768d9",
    "Verify archived build and privacy manifest": "bfc8a654774502496e9edf9407f21f5516e6d6e372e1211555afb4fc31517175",
    "Create fingerprint-bound export options": "4aeb8c14cd1b15da9a6eb8d55528446b62180842687ecb8d0a8018ec85324869",
    "Export signed IPA without uploading": "405927b26839f3a3891eb3974f58bf7decb1b9341a4877a5daa05f78fd8c6975",
    "Verify signed IPA and exact signing material": "bcf5f5e512034f69221d97cff4ef1a18f2c5b5cdd3078a5bce2325191062dc3a",
    "Remove temporary signing material": "3a863f63db09420d1eac529a5521425d1f28b00f167d89462a3d48b88a392674",
}

PREFLIGHT_STEP_ENVIRONMENT = {
    "Verify selected production commit": [
        ("EXPECTED_COMMIT_SHA", "${{ inputs.expected_commit_sha }}"),
    ],
    "Verify exact-source CI succeeded": [
        ("GITHUB_TOKEN", "${{ github.token }}"),
    ],
    "Verify protected production environment": [
        ("GITHUB_TOKEN", "${{ github.token }}"),
        ("PRODUCTION_RELEASE_GUARD", "${{ secrets.PRODUCTION_RELEASE_GUARD }}"),
    ],
    "Verify App Store Connect authentication": [
        (
            "APP_STORE_CONNECT_API_KEY_ID",
            "${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}",
        ),
        (
            "APP_STORE_CONNECT_API_ISSUER_ID",
            "${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}",
        ),
        (
            "APP_STORE_CONNECT_API_KEY_BASE64",
            "${{ secrets.APP_STORE_CONNECT_API_KEY_BASE64 }}",
        ),
        ("APP_STORE_CONNECT_APP_ID", "6807022780"),
    ],
    "Install and verify cloud-signing material": [
        (
            "BUILD_CERTIFICATE_BASE64",
            "${{ secrets.BUILD_CERTIFICATE_BASE64 }}",
        ),
        (
            "BUILD_PROVISION_PROFILE_BASE64",
            "${{ secrets.BUILD_PROVISION_PROFILE_BASE64 }}",
        ),
        (
            "THUMBNAIL_PROVISION_PROFILE_BASE64",
            "${{ secrets.THUMBNAIL_PROVISION_PROFILE_BASE64 }}",
        ),
        ("P12_PASSWORD", "${{ secrets.P12_PASSWORD }}"),
        ("KEYCHAIN_PASSWORD", "${{ secrets.KEYCHAIN_PASSWORD }}"),
    ],
}

PREFLIGHT_EXPLICIT_BASH_STEPS = {
    "Verify selected production commit",
    "Verify pinned Xcode toolchain",
    "Verify production identity",
}

PREFLIGHT_STEP_KEYS = {
    "Checkout": ["uses", "with"],
    "Verify selected production commit": ["shell", "env", "run"],
    "Verify pinned Xcode toolchain": ["shell", "run"],
    "Verify exact-source CI succeeded": ["env", "run"],
    "Verify protected production environment": ["env", "run"],
    "Verify production identity": ["shell", "run"],
    "Verify App Store Connect authentication": ["env", "run"],
    "Install and verify cloud-signing material": ["env", "run"],
    "Remove temporary signing material": ["if", "run"],
}

PREFLIGHT_LITERAL_RUN_STEPS = {
    "Verify selected production commit",
    "Verify pinned Xcode toolchain",
    "Verify production identity",
    "Verify App Store Connect authentication",
    "Install and verify cloud-signing material",
    "Archive KeyHollow without signing",
    "Verify archived build and privacy manifest",
    "Create fingerprint-bound export options",
    "Export signed IPA without uploading",
    "Verify signed IPA and exact signing material",
    "Remove temporary signing material",
}

TESTFLIGHT_STEP_NAMES = [
    "Checkout",
    "Verify workflow security",
    "Verify selected production commit",
    "Verify pinned Xcode toolchain",
    "Verify exact-source CI succeeded",
    "Verify protected production environment",
    "Verify release hygiene",
    "Verify architecture boundaries",
    "Test TestFlight build-number guard",
    "Test signing-material guard",
    "Verify privacy manifest",
    "Verify production identity",
    "Install XcodeGen",
    "Generate Xcode project",
    "Verify build number against App Store Connect",
    "Archive KeyHollow",
    "Verify archived build, privacy, and module hygiene",
    "Install cloud-signing material",
    "Create export options",
    "Export signed IPA",
    "Verify signed IPA",
    "Remove signing authority before external actions",
    "Retain verified signed IPA artifact",
    "Upload verified IPA to App Store Connect",
    "Remove temporary signing material",
]

TESTFLIGHT_RUN_BODY_SHA256 = {
    "Verify workflow security": "6fb924cbeaaaeb9e4eaa88a1dd819a5d63a553df4aa9febe4216c2d5ce0e75b6",
    "Verify selected production commit": "f79d9bc2ae4d477cc5927d7c3bed7bbb93eb8292bc31cafef2e70d3053de8faf",
    "Verify pinned Xcode toolchain": "d2738fe0838201c38d5bad975b7d63ddfa4d05fe9cc95ffbec701a1b9aa38d88",
    "Verify exact-source CI succeeded": "06d2a54e800c67827d496f4fef62257c73309dcd89a08d23bc8a86abe526daef",
    "Verify protected production environment": "c71086227ac10e021aa621ce7337839856e65e4816ff73e34c8860bdc90927af",
    "Verify release hygiene": "d4109ac97876499508b699a43ab8ef561dafc8b0e7e2d59ed524120e768fca16",
    "Verify architecture boundaries": "d81975f9454f112ce3ad9334ad8a1a55387239e717771d4f8f264ac9e4c70f67",
    "Test TestFlight build-number guard": "4777c00970067209fb710f30d6c6c8769af5c0318e8470a31f6a140ee38dfcc8",
    "Test signing-material guard": "e33cffa19ef0dc72f849bb7caade1fc62886265280316c72cfe79169d85208b9",
    "Verify privacy manifest": "7fdf0fab1f1b85dbb52ff3b26271e4ceb33e7b74ac2451c5d7a6b88fd3435e45",
    "Verify production identity": "2207e185353a7bc29b750fa4ad73e912f5c41e06c63cb428bee3f1654ab8ad65",
    "Install XcodeGen": "eff4eba980e3da81c56fa187333d420a74b0b26390057c64bd11e2080ea1eea3",
    "Generate Xcode project": "bdda8fc016233561ae1373260c36558e5d4c306a823ed94687bc0fcd9073ba5c",
    "Verify build number against App Store Connect": "7f2fc20f1403958d6c69c221918f43e8f5699e216469086b0b9394da70257e60",
    "Install cloud-signing material": "b4c9ffc324d1634f9ffedd7592ca38e6df965ad8f74f7a6431b688902b353697",
    "Archive KeyHollow": "98be0d5be0e7437ee93dfa382665382b31caee427a431f7fba183c8246f4d1e5",
    "Verify archived build, privacy, and module hygiene": "29c7753fd75f215395de6817c17b39a0cd01a5d8700aa4ce4fb76b4de514bf24",
    "Create export options": "df05193769e7bc473e502e6c37d5fb3c24c7b74aa7505e54592543e28d2f2f41",
    "Export signed IPA": "f25870e6b7d7ae047bcb5a7a99cf2a474847b8cdba573f355eba54116441cecf",
    "Verify signed IPA": "510690b1f0cbaff57385f8ca2632542bc83a06e0741dca14306df0a3de969294",
    "Remove signing authority before external actions": "69faaf48ecdfc42c24bd77cf88678e031554008a7c39ca1158276abacc1f4357",
    "Upload verified IPA to App Store Connect": "c9191138720ffc3f367df809ed2c65a0ca18f20d54c8951196ebbd1df5ee02d0",
    "Remove temporary signing material": "a833e4348a802b96d1cbba7ce6c7e0b3fa486b5cb511e45f9094869a801c2fda",
}

TESTFLIGHT_ACTION_BLOCK_SHA256 = {
    "Checkout": "ebe8fbcb24c2294e18bb4a28fdffcb20b2e9869acd5d6d5c70188171e5d75aac",
    "Retain verified signed IPA artifact": (
        "847cc2f63c4d91e5d39c28e66f4b6f26e53b65c77440aaf094804d1a7b81a119"
    ),
}

TESTFLIGHT_STEP_ENVIRONMENT = {
    "Verify selected production commit": [
        ("EXPECTED_COMMIT_SHA", "${{ inputs.expected_commit_sha }}"),
    ],
    "Verify exact-source CI succeeded": [
        ("GITHUB_TOKEN", "${{ github.token }}"),
    ],
    "Verify protected production environment": [
        ("GITHUB_TOKEN", "${{ github.token }}"),
        ("PRODUCTION_RELEASE_GUARD", "${{ secrets.PRODUCTION_RELEASE_GUARD }}"),
    ],
    "Verify production identity": [
        ("REQUESTED_BUILD_NUMBER", "${{ inputs.build_number }}"),
    ],
    "Verify build number against App Store Connect": [
        (
            "APP_STORE_CONNECT_API_KEY_ID",
            "${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}",
        ),
        (
            "APP_STORE_CONNECT_API_ISSUER_ID",
            "${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}",
        ),
        (
            "APP_STORE_CONNECT_API_KEY_BASE64",
            "${{ secrets.APP_STORE_CONNECT_API_KEY_BASE64 }}",
        ),
        ("APP_STORE_CONNECT_APP_ID", "6807022780"),
        ("REQUESTED_BUILD_NUMBER", "${{ inputs.build_number }}"),
    ],
    "Install cloud-signing material": [
        (
            "BUILD_CERTIFICATE_BASE64",
            "${{ secrets.BUILD_CERTIFICATE_BASE64 }}",
        ),
        (
            "BUILD_PROVISION_PROFILE_BASE64",
            "${{ secrets.BUILD_PROVISION_PROFILE_BASE64 }}",
        ),
        (
            "THUMBNAIL_PROVISION_PROFILE_BASE64",
            "${{ secrets.THUMBNAIL_PROVISION_PROFILE_BASE64 }}",
        ),
        ("P12_PASSWORD", "${{ secrets.P12_PASSWORD }}"),
        ("KEYCHAIN_PASSWORD", "${{ secrets.KEYCHAIN_PASSWORD }}"),
    ],
    "Upload verified IPA to App Store Connect": [
        (
            "APP_STORE_CONNECT_API_KEY_ID",
            "${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}",
        ),
        (
            "APP_STORE_CONNECT_API_ISSUER_ID",
            "${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}",
        ),
        (
            "APP_STORE_CONNECT_API_KEY_BASE64",
            "${{ secrets.APP_STORE_CONNECT_API_KEY_BASE64 }}",
        ),
        ("APP_STORE_CONNECT_APP_ID", "6807022780"),
        ("REQUESTED_BUILD_NUMBER", "${{ inputs.build_number }}"),
    ],
}

TESTFLIGHT_EXPLICIT_BASH_STEPS = {
    "Verify selected production commit",
    "Verify pinned Xcode toolchain",
    "Verify production identity",
    "Verify signed IPA",
}

TESTFLIGHT_STEP_KEYS = {
    "Checkout": ["uses", "with"],
    "Verify selected production commit": ["shell", "env", "run"],
    "Verify pinned Xcode toolchain": ["shell", "run"],
    "Verify exact-source CI succeeded": ["env", "run"],
    "Verify protected production environment": ["env", "run"],
    "Verify production identity": ["shell", "env", "run"],
    "Verify build number against App Store Connect": ["env", "run"],
    "Install cloud-signing material": ["env", "run"],
    "Verify signed IPA": ["shell", "run"],
    "Retain verified signed IPA artifact": ["if", "uses", "with"],
    "Upload verified IPA to App Store Connect": ["env", "run"],
    "Remove temporary signing material": ["if", "run"],
}

TESTFLIGHT_LITERAL_RUN_STEPS = {
    "Verify selected production commit",
    "Verify pinned Xcode toolchain",
    "Verify production identity",
    "Verify build number against App Store Connect",
    "Install cloud-signing material",
    "Archive KeyHollow",
    "Verify archived build, privacy, and module hygiene",
    "Create export options",
    "Export signed IPA",
    "Verify signed IPA",
    "Remove signing authority before external actions",
    "Upload verified IPA to App Store Connect",
    "Remove temporary signing material",
}

ALLOWED_ACTIONS = {
    "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803",
    "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
    "github/codeql-action/init@cdf488f595d80d6e07e03d4674febd5ab45fa938",
    "github/codeql-action/analyze@cdf488f595d80d6e07e03d4674febd5ab45fa938",
}
PRODUCTION_SECRETS = {
    "APP_STORE_CONNECT_API_ISSUER_ID",
    "APP_STORE_CONNECT_API_KEY_BASE64",
    "APP_STORE_CONNECT_API_KEY_ID",
    "BUILD_CERTIFICATE_BASE64",
    "BUILD_PROVISION_PROFILE_BASE64",
    "KEYCHAIN_PASSWORD",
    "P12_PASSWORD",
    "PRODUCTION_RELEASE_GUARD",
    "THUMBNAIL_PROVISION_PROFILE_BASE64",
}
EXPECTED_CODEOWNERS = {
    "/.github/CODEOWNERS @Frankbell84",
    "/.github/workflows/ @Frankbell84",
    "/scripts/ @Frankbell84",
    "/project.yml @Frankbell84",
    "/SECURITY.md @Frankbell84",
    "/KeyHollow/Security/ @Frankbell84",
    "/KeyHollow/Session/ @Frankbell84",
    "/KeyHollow/Storage/ @Frankbell84",
    "/KeyHollow/Transfer/ @Frankbell84",
    "/KeyHollow/Photos/ @Frankbell84",
    "/KeyHollow/ThirdParty/ @Frankbell84",
    "/KeyHollow/AddOns/ @Frankbell84",
    "/KeyHollow/Resources/PrivacyInfo.xcprivacy @Frankbell84",
    "/KeyHollowVaultThumbnailExtension/ @Frankbell84",
    "/KeyHollowTests/ @Frankbell84",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run checker regression tests without inspecting the repository.",
    )
    return parser.parse_args()


def indentation(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def top_level_section(text: str, name: str) -> str | None:
    lines = text.splitlines()
    start: int | None = None
    for index, line in enumerate(lines):
        if line == f"{name}:":
            start = index
            break
    if start is None:
        return None

    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line and not line.startswith((" ", "\t", "#")):
            end = index
            break
    return "\n".join(lines[start:end])


def direct_child_keys(section: str, spaces: int) -> list[str]:
    keys: list[str] = []
    pattern = re.compile(
        rf"^ {{{spaces}}}([A-Za-z0-9_-]+):(?:\s*(.*?))?\s*$"
    )
    for line in section.splitlines()[1:]:
        if (
            not line.strip()
            or line.lstrip().startswith("#")
            or indentation(line) != spaces
        ):
            continue
        match = pattern.fullmatch(line)
        if match is None:
            keys.append("__INVALID_CHILD__")
            continue
        value = (match.group(2) or "").lstrip()
        if value.startswith(("{", "[", "&", "*")):
            keys.append("__INVALID_CHILD__")
            continue
        keys.append(match.group(1))
    return keys


def permission_blocks(text: str) -> list[dict[str, str]]:
    lines = text.splitlines()
    blocks: list[dict[str, str]] = []
    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)permissions:\s*(.*)$", line)
        if match is None:
            continue
        base_indent = len(match.group(1))
        inline = match.group(2).strip()
        if inline:
            blocks.append({"__inline__": inline})
            continue

        block: dict[str, str] = {}
        for child in lines[index + 1 :]:
            if not child.strip() or child.lstrip().startswith("#"):
                continue
            if indentation(child) <= base_indent:
                break
            child_match = re.match(
                r"^\s+([A-Za-z0-9_-]+):\s*([A-Za-z-]+)\s*$", child
            )
            if child_match:
                block[child_match.group(1)] = child_match.group(2)
        blocks.append(block)
    return blocks


def run_script_bodies(text: str) -> list[str]:
    lines = text.splitlines()
    bodies: list[str] = []
    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)(?:-\s+)?run:\s*(.*)$", line)
        if match is None:
            continue
        base_indent = indentation(line)
        value = match.group(2).strip()
        if value not in {"|", ">", "|-", ">-", "|+", ">+"}:
            bodies.append(value)
            continue
        body: list[str] = []
        for child in lines[index + 1 :]:
            if child.strip() and indentation(child) <= base_indent:
                break
            body.append(child)
        bodies.append("\n".join(body))
    return bodies


def nonisolated_python_invocations(text: str) -> list[str]:
    invocations: list[str] = []
    for body in run_script_bodies(text):
        for line in body.splitlines():
            for match in re.finditer(
                r"(?<![A-Za-z0-9_.-])python3(?=\s|$)", line
            ):
                suffix = line[match.end() :]
                if re.match(r"\s+-I(?:\s|$)", suffix) is None:
                    invocations.append(line.strip())
    return invocations


def workflow_step_blocks(text: str) -> list[tuple[str, str]]:
    """Return ordered ``(name, block)`` pairs for ordinary GitHub steps.

    Security-sensitive workflows deliberately forbid YAML aliases and unusual
    step syntax, so their six-space ``- name:`` entries are an unambiguous
    boundary we can validate without adding a YAML dependency.
    """

    lines = text.splitlines()
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = re.fullmatch(r" {6}- name:\s*(\S(?:.*\S)?)\s*", line)
        if match:
            starts.append((index, match.group(1)))

    blocks: list[tuple[str, str]] = []
    for position, (start, name) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        blocks.append((name, "\n".join(lines[start:end]).rstrip()))
    return blocks


def step_run_body(block: str) -> str | None:
    bodies = run_script_bodies(block)
    if len(bodies) != 1:
        return None
    body = bodies[0]
    # Remove YAML indentation while preserving the reviewed command text.
    nonempty = [line for line in body.splitlines() if line.strip()]
    if not nonempty:
        return ""
    leading = min(indentation(line) for line in nonempty)
    return "\n".join(line[leading:] for line in body.splitlines()).rstrip()


def step_run_scalar_style(block: str) -> str | None:
    run_lines = re.findall(r"^ {8}run:\s*(.*?)\s*$", block, re.MULTILINE)
    if len(run_lines) != 1:
        return None
    value = run_lines[0]
    if value == "|":
        return "literal"
    if value in {">", "|-", "|+", ">-", ">+", ""}:
        return "forbidden"
    return "inline"


def body_sha256(body: str) -> str:
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def canonical_source_sha256(data: bytes) -> str | None:
    canonical = data.replace(b"\r\n", b"\n")
    if b"\r" in canonical or b"\x00" in canonical:
        return None
    return hashlib.sha256(canonical).hexdigest()


def audit_privileged_source_payloads(
    payloads: dict[str, bytes | None], expected_hashes: dict[str, str]
) -> list[str]:
    violations: list[str] = []
    for relative_path, expected_digest in expected_hashes.items():
        payload = payloads.get(relative_path)
        actual_digest = canonical_source_sha256(payload) if payload is not None else None
        require(
            violations,
            actual_digest == expected_digest,
            f"{relative_path}: privileged verifier source hash drifted",
        )
    return violations


def audit_privileged_source_hashes(root: Path = ROOT) -> list[str]:
    payloads = {
        relative_path: (path.read_bytes() if path.is_file() else None)
        for relative_path in PRIVILEGED_SOURCE_SHA256
        for path in [root / relative_path]
    }
    return audit_privileged_source_payloads(payloads, PRIVILEGED_SOURCE_SHA256)


def audit_release_workflow_payloads(
    payloads: dict[str, str | None], expected_hashes: dict[str, str]
) -> list[str]:
    violations: list[str] = []
    for workflow_name, expected_digest in expected_hashes.items():
        payload = payloads.get(workflow_name)
        actual_digest = body_sha256(payload) if payload is not None else None
        require(
            violations,
            actual_digest == expected_digest,
            f"{workflow_name}: normalized full-workflow hash drifted",
        )
    return violations


def audit_project_execution_surface(text: str) -> list[str]:
    violations: list[str] = []
    for key in sorted(FORBIDDEN_XCODEGEN_EXECUTION_KEYS):
        require(
            violations,
            re.search(
                rf"^\s*(?:-\s*)?{re.escape(key)}:\s*", text, re.MULTILINE
            )
            is None,
            f"project.yml: executable XcodeGen surface is forbidden: {key}",
        )
    return violations


def is_reviewed_run_body(
    step_name: str, body: str | None, approved_hashes: dict[str, str]
) -> bool:
    return body is not None and body_sha256(body) == approved_hashes.get(step_name)


def is_reviewed_preflight_body(step_name: str, body: str | None) -> bool:
    return is_reviewed_run_body(step_name, body, PREFLIGHT_RUN_BODY_SHA256)


def exact_step_inventory(text: str, expected_names: list[str]) -> bool:
    steps = workflow_step_blocks(text)
    return (
        [name for name, _ in steps] == expected_names
        and len(re.findall(r"^ {6}-\s+", text, re.MULTILINE)) == len(steps)
    )


def collapse_shell_continuations(text: str) -> str:
    return re.sub(r"\\\s*\n\s*", "", text)


def named_step_block(text: str, step_name: str) -> str | None:
    matches = [block for name, block in workflow_step_blocks(text) if name == step_name]
    return matches[0] if len(matches) == 1 else None


def release_toolchain_step_is_exact(text: str) -> bool:
    block = named_step_block(text, "Verify pinned Xcode toolchain")
    body = step_run_body(block) if block is not None else None
    return body is not None and body.splitlines() == RELEASE_TOOLCHAIN_COMMAND_LINES


def signing_secrets_unset_before_validator(step_block: str) -> bool:
    collapsed = collapse_shell_continuations(step_block)
    unset_index = collapsed.find(SIGNING_SECRET_UNSET_COMMAND)
    validator_index = collapsed.find(
        "python3 -I scripts/verify_signing_material.py ", unset_index + 1
    )
    return (
        unset_index >= 0
        and validator_index > unset_index
        and collapsed.count(SIGNING_SECRET_UNSET_COMMAND) == 1
    )


def testflight_artifact_step_is_fail_closed(step_block: str | None) -> bool:
    if step_block is None:
        return False
    keys = re.findall(
        r"^ {8}([A-Za-z0-9_-]+):(?:\s|$)", step_block, re.MULTILINE
    )
    return (
        keys == ["if", "uses", "with"]
        and "        if: success()" in step_block
        and "          if-no-files-found: error" in step_block
    )


def testflight_signing_teardown_is_fail_closed(
    step_block: str | None,
) -> bool:
    if step_block is None:
        return False
    return (
        all(required in step_block for required in STRICT_SIGNING_TEARDOWN_REQUIREMENTS)
        and "::warning::" not in step_block
        and "|| true" not in step_block
    )


def testflight_final_build_recheck_is_exact(step_block: str | None) -> bool:
    if step_block is None:
        return False
    body = step_run_body(step_block)
    if body is None or body.count(TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND) != 1:
        return False
    identity_index = body.find(
        'if [[ "$APP_STORE_CONNECT_API_KEY_ID" != "$EXPECTED_API_KEY_ID"'
    )
    recheck_index = body.find(TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND)
    key_path_index = body.find(
        'API_KEY_PATH="$API_KEY_DIRECTORY/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"'
    )
    decode_index = body.find(
        'printf \'%s\' "$APP_STORE_CONNECT_API_KEY_BASE64" | base64 --decode'
    )
    upload_index = body.find("xcrun altool")
    return (
        0
        <= identity_index
        < recheck_index
        < key_path_index
        < decode_index
        < upload_index
    )


def direct_mapping_entries(
    text: str, *, header: str, header_spaces: int, entry_spaces: int
) -> list[tuple[str, str]]:
    lines = text.splitlines()
    header_line = " " * header_spaces + f"{header}:"
    header_indexes = [index for index, line in enumerate(lines) if line == header_line]
    if not header_indexes:
        return []
    if len(header_indexes) != 1:
        return [("__DUPLICATE_SECTION__", str(len(header_indexes)))]

    entries: list[tuple[str, str]] = []
    for line in lines[header_indexes[0] + 1 :]:
        if line.strip() and indentation(line) <= header_spaces:
            break
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(
            rf" {{{entry_spaces}}}([A-Za-z_][A-Za-z0-9_]*):\s*(\S(?:.*\S)?)\s*",
            line,
        )
        if match:
            entries.append((match.group(1), match.group(2)))
        elif indentation(line) == entry_spaces:
            entries.append(("__INVALID_ENTRY__", line.strip()))
    return entries


def direct_key_value_entries(text: str, *, spaces: int) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for line in text.splitlines():
        if (
            not line.strip()
            or line.lstrip().startswith("#")
            or indentation(line) != spaces
        ):
            continue
        match = re.fullmatch(
            rf" {{{spaces}}}([A-Za-z0-9_-]+):\s*(.*?)\s*",
            line,
        )
        if match:
            entries.append((match.group(1), match.group(2)))
        else:
            entries.append(("__INVALID_ENTRY__", line.strip()))
    return entries


def named_job_block(text: str, job_name: str) -> str | None:
    lines = text.splitlines()
    starts = [
        index
        for index, line in enumerate(lines)
        if line == f"  {job_name}:"
    ]
    if len(starts) != 1:
        return None
    start = starts[0]
    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line.strip() and indentation(line) <= 2:
            end = index
            break
    return "\n".join(lines[start:end]).rstrip()


def contains_line(text: str, pattern: str) -> bool:
    return re.search(pattern, text, re.MULTILINE) is not None


def require(violations: list[str], condition: bool, message: str) -> None:
    if not condition:
        violations.append(message)


def matching_command_lines(text: str, marker: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if marker in line]


def audit_release_secret_boundary(name: str, text: str) -> list[str]:
    violations: list[str] = []
    referenced_secrets = set(SECRET_REFERENCE.findall(text))
    require(
        violations,
        referenced_secrets == PRODUCTION_SECRETS,
        f"{name}: production secret set drifted: {sorted(referenced_secrets)}",
    )
    secret_bindings = re.findall(
        r"^\s+([A-Z][A-Z0-9_]*):\s*\$\{\{\s*secrets\.([A-Z0-9_]+)\s*}}\s*$",
        text,
        re.MULTILINE,
    )
    require(
        violations,
        bool(secret_bindings)
        and all(environment_name == secret_name for environment_name, secret_name in secret_bindings),
        f"{name}: every protected secret must retain its exact environment-variable name",
    )

    guard_reference = "${{ secrets.PRODUCTION_RELEASE_GUARD }}"
    first_secret_reference = text.find("secrets.")
    guard_reference_index = text.find(guard_reference)
    guard_secret_name_index = text.find("secrets.PRODUCTION_RELEASE_GUARD")
    commit_check_index = text.find(
        '[[ "$EXPECTED_COMMIT_SHA" != "$GITHUB_SHA" ]]'
    )
    release_source_index = text.find("python3 -I scripts/verify_release_source.py")
    environment_check_index = text.find(
        "python3 -I scripts/verify_release_environment.py"
    )
    require(
        violations,
        first_secret_reference == guard_secret_name_index
        and guard_reference_index >= 0
        and text.count(guard_reference) == 1,
        f"{name}: the environment-only guard must be the first and sole guard secret",
    )
    require(
        violations,
        0 <= commit_check_index
        < release_source_index
        < guard_reference_index
        < environment_check_index,
        f"{name}: exact commit, source, and protected-environment gates are out of order",
    )
    require(
        violations,
        environment_check_index > guard_reference_index
        and all(
            match.start() == guard_secret_name_index
            or match.start() > environment_check_index
            for match in SECRET_REFERENCE.finditer(text)
        ),
        f"{name}: no signing/API secret may be referenced before environment verification",
    )
    return violations


def audit_release_job_structure(
    name: str, text: str, *, job_name: str
) -> list[str]:
    violations: list[str] = []
    top_level_entries = direct_key_value_entries(text, spaces=0)
    require(
        violations,
        [key for key, _ in top_level_entries]
        == ["name", "on", "permissions", "concurrency", "jobs"],
        f"{name}: top-level key inventory or ordering drifted",
    )
    concurrency = top_level_section(text, "concurrency")
    require(
        violations,
        len(re.findall(r"^concurrency:\s*$", text, re.MULTILINE)) == 1
        and concurrency is not None
        and direct_key_value_entries(concurrency, spaces=2)
        == RELEASE_CONCURRENCY_ENTRIES,
        f"{name}: concurrency must retain the exact serialized production policy",
    )

    job = named_job_block(text, job_name)
    require(
        violations,
        job is not None
        and direct_key_value_entries(job, spaces=4) == RELEASE_JOB_ENTRIES,
        f"{name}: release-job keys or scalar values drifted",
    )
    require(
        violations,
        not contains_line(text, r"^\s+(?:strategy|matrix|defaults):"),
        f"{name}: strategy, matrix, and nested defaults are forbidden for release jobs",
    )
    require(
        violations,
        not contains_line(text, r"^\s*(?:BASH_ENV|PYTHONPATH):"),
        f"{name}: interpreter startup hooks are forbidden in release workflows",
    )
    require(
        violations,
        not contains_line(
            text,
            r"^\s*(?:-\s+)?(?:[A-Za-z0-9_-]+|['\"][^'\"]+['\"]):\s*[\[{]",
        ),
        f"{name}: flow-style YAML mappings and sequences are forbidden",
    )
    return violations


def audit_approved_rotation(name: str, text: str) -> list[str]:
    """Pin release jobs to the locally reviewed 2026 Apple rotation."""

    violations: list[str] = []
    for variable, value in APPROVED_ROTATION_BINDINGS.items():
        exact_binding = rf"^      {re.escape(variable)}: {re.escape(value)}$"
        require(
            violations,
            len(re.findall(exact_binding, text, re.MULTILINE)) == 1,
            f"{name}: approved rotation binding drifted: {variable}",
        )

    collapsed = collapse_shell_continuations(text)
    api_pair = (
        'if [[ "$APP_STORE_CONNECT_API_KEY_ID" != "$EXPECTED_API_KEY_ID" || '
        '"$APP_STORE_CONNECT_API_ISSUER_ID" != "$EXPECTED_API_ISSUER_ID" ]]; then'
    )
    certificate_check = (
        'if [[ "$SIGNING_CERTIFICATE_SHA1" != '
        '"$EXPECTED_SIGNING_CERTIFICATE_SHA1" ]]; then'
    )
    profile_pair = (
        'if [[ "$NORMALIZED_APP_PROFILE_UUID" != "$EXPECTED_APP_PROFILE_UUID" || '
        '"$NORMALIZED_THUMBNAIL_PROFILE_UUID" != '
        '"$EXPECTED_THUMBNAIL_PROFILE_UUID" ]]; then'
    )
    expected_api_checks = 2 if name == "testflight.yml" else 1
    for label, comparison, expected_count in (
        ("API key and issuer", api_pair, expected_api_checks),
        ("distribution certificate", certificate_check, 1),
        ("provisioning profiles", profile_pair, 1),
    ):
        require(
            violations,
            collapsed.count(comparison) == expected_count,
            f"{name}: exact approved {label} comparison is missing or duplicated",
        )

    api_indexes = [
        match.start() for match in re.finditer(re.escape(api_pair), collapsed)
    ]
    certificate_index = collapsed.find(certificate_check)
    profile_index = collapsed.find(profile_pair)
    comparison_indexes = (
        [api_indexes[0], certificate_index, profile_index, api_indexes[1]]
        if len(api_indexes) == 2
        else [*api_indexes, certificate_index, profile_index]
    )
    require(
        violations,
        len(api_indexes) == expected_api_checks
        and all(index >= 0 for index in comparison_indexes)
        and comparison_indexes == sorted(comparison_indexes),
        f"{name}: approved API, certificate, and profile checks are out of order",
    )
    return violations


def audit_cleanup_step(name: str, cleanup_step: str | None) -> list[str]:
    violations: list[str] = []
    require(
        violations,
        cleanup_step is not None,
        f"{name}: temporary signing-material cleanup step is missing",
    )
    if cleanup_step is None:
        return violations

    cleanup_keys = re.findall(
        r"^ {8}([A-Za-z0-9_-]+):(?:\s|$)", cleanup_step, re.MULTILINE
    )
    require(
        violations,
        cleanup_keys == ["if", "run"],
        f"{name}: cleanup step may not receive secrets or additional capabilities",
    )

    cleanup_body = step_run_body(cleanup_step)
    require(
        violations,
        cleanup_body is not None
        and body_sha256(cleanup_body) == CLEANUP_RUN_BODY_SHA256.get(name),
        f"{name}: reviewed cleanup command body drifted",
    )

    cleanup_requirements = (
        *COMMON_CLEANUP_REQUIREMENTS,
        *WORKFLOW_CLEANUP_REQUIREMENTS.get(name, ()),
    )
    for required in cleanup_requirements:
        require(
            violations,
            required in cleanup_step,
            f"{name}: cleanup no longer removes or protects {required}",
        )
    require(
        violations,
        cleanup_step.count("rm -f") >= 2 and cleanup_step.count("rm -rf") == 1,
        f"{name}: cleanup deletion commands drifted",
    )
    return violations


def audit_environment_verifier_source(source: str) -> list[str]:
    violations: list[str] = []
    for required in ENVIRONMENT_VERIFIER_REQUIREMENTS:
        require(
            violations,
            required in source,
            f"verify_release_environment.py: required policy is missing: {required}",
        )
    return violations


def audit_signing_pipeline(
    name: str, text: str, *, export_options_path: str
) -> list[str]:
    violations: list[str] = []
    validator_command = "python3 -I scripts/verify_signing_material.py"
    validator_indexes = [
        match.start() for match in re.finditer(re.escape(validator_command), text)
    ]
    require(
        violations,
        len(validator_indexes) == 3,
        f"{name}: signing verifier must run exactly as self-test, preinstall, and post-export",
    )

    for required in (
        "python3 -I scripts/verify_signing_material.py --self-test",
        SIGNING_IMPORT_COMMAND,
        SIGNING_LEAF_EXTRACTION_COMMAND,
        "LEAF_CERTIFICATE_COUNT=$(awk '/-----BEGIN CERTIFICATE-----/",
        '[[ "$LEAF_CERTIFICATE_COUNT" != 1 ]]',
        'CERTIFICATE_SUBJECT=$(openssl x509 -in "$SIGNING_CERTIFICATE_PEM" -noout -subject -nameopt RFC2253)',
        '[[ "$CERTIFICATE_SUBJECT" != *"CN=Apple Distribution:"* || "$CERTIFICATE_SUBJECT" != *"OU=$TEAM_ID"* ]]',
        'SIGNING_CERTIFICATE_DER="$RUNNER_TEMP/keyhollow-distribution.cer"',
        'SIGNING_CERTIFICATE_SHA1=$(shasum -a 1 "$SIGNING_CERTIFICATE_DER"',
        '[[ ! "$SIGNING_CERTIFICATE_SHA1" =~ ^[0-9A-F]{40}$ ]]',
        SIGNING_IDENTITY_LIST_COMMAND,
        SIGNING_VALID_IDENTITY_COUNT_COMMAND,
        '[[ "$VALID_IDENTITY_COUNT" != 1 ]]',
        SIGNING_MATCHING_IDENTITY_COUNT_COMMAND,
        '[[ "$IDENTITY_MATCH_COUNT" != 1 ]]',
        "unset IDENTITY_LIST",
        '--certificate-der "$SIGNING_CERTIFICATE_DER"',
        '--app-profile-plist "$APP_PROFILE_PLIST"',
        '--thumbnail-profile-plist "$THUMBNAIL_PROFILE_PLIST"',
        'APP_PROFILE_UUID=$(/usr/libexec/PlistBuddy -c \'Print :UUID\' "$APP_PROFILE_PLIST")',
        'THUMBNAIL_PROFILE_UUID=$(/usr/libexec/PlistBuddy -c \'Print :UUID\' "$THUMBNAIL_PROFILE_PLIST")',
        'echo "APP_PROFILE_UUID=$APP_PROFILE_UUID" >> "$GITHUB_ENV"',
        'echo "THUMBNAIL_PROFILE_UUID=$THUMBNAIL_PROFILE_UUID" >> "$GITHUB_ENV"',
        'echo "SIGNING_CERTIFICATE_SHA1=$SIGNING_CERTIFICATE_SHA1" >> "$GITHUB_ENV"',
        '--expected-app-uuid "$APP_PROFILE_UUID"',
        '--expected-thumbnail-uuid "$THUMBNAIL_PROFILE_UUID"',
        'codesign --verify --deep --strict --verbose=2 "$SIGNED_APP_PATH"',
        'codesign --verify --strict --verbose=2 "$SIGNED_EXTENSION_PATH"',
    ):
        require(
            violations,
            required in text,
        f"{name}: required signing control is missing: {required}",
        )

    require(
        violations,
        matching_command_lines(text, "security import ")
        == [SIGNING_IMPORT_COMMAND],
        f"{name}: PKCS#12 identity import must use the canonical aggregate type exactly once",
    )

    require(
        violations,
        matching_command_lines(text, "openssl pkcs12 ")
        == [SIGNING_LEAF_EXTRACTION_COMMAND],
        f"{name}: the PKCS#12 archive must yield exactly one canonical non-CA signing certificate",
    )

    require(
        violations,
        matching_command_lines(text, "security find-identity ")
        == [SIGNING_IDENTITY_LIST_COMMAND]
        and matching_command_lines(text, "VALID_IDENTITY_COUNT=")
        == [SIGNING_VALID_IDENTITY_COUNT_COMMAND]
        and matching_command_lines(text, "IDENTITY_MATCH_COUNT=")
        == [SIGNING_MATCHING_IDENTITY_COUNT_COMMAND],
        f"{name}: the isolated keychain must contain one valid identity and it must match the approved leaf",
    )

    require(
        violations,
        'security find-certificate -a -p "$KEYCHAIN_PATH"' not in text,
        f"{name}: aggregate keychain certificate enumeration must not confuse chain certificates with signing identities",
    )

    require(
        violations,
        " -A " not in text,
        f"{name}: signing private key must not grant access to every process",
    )

    expected_destination_binding = (
        "/usr/libexec/PlistBuddy -c 'Add :destination string export' "
        f"{export_options_path}"
    )
    destination_bindings = matching_command_lines(
        text, "Add :destination string"
    )
    require(
        violations,
        destination_bindings == [expected_destination_binding],
        f"{name}: export destination must be explicitly and solely local",
    )

    expected_certificate_binding = (
        "/usr/libexec/PlistBuddy -c \"Add :signingCertificate string "
        f"$SIGNING_CERTIFICATE_SHA1\" {export_options_path}"
    )
    certificate_bindings = matching_command_lines(
        text, "Add :signingCertificate string"
    )
    require(
        violations,
        certificate_bindings == [expected_certificate_binding],
        f"{name}: export must bind exactly the validated certificate fingerprint",
    )

    expected_profile_bindings = [
        (
            "/usr/libexec/PlistBuddy -c \"Add :provisioningProfiles:"
            "com.keyhollow.app string $APP_PROFILE_UUID\" "
            f"{export_options_path}"
        ),
        (
            "/usr/libexec/PlistBuddy -c \"Add :provisioningProfiles:"
            "com.keyhollow.app.vault-thumbnail string $THUMBNAIL_PROFILE_UUID\" "
            f"{export_options_path}"
        ),
    ]
    profile_bindings = matching_command_lines(
        text, "Add :provisioningProfiles:com.keyhollow"
    )
    require(
        violations,
        profile_bindings == expected_profile_bindings,
        f"{name}: export must bind exactly the two validated provisioning-profile UUIDs",
    )

    for forbidden in (
        "Add :signingCertificate string Apple Distribution",
        "Add :provisioningProfiles:com.keyhollow.app string KeyHollow App Store",
        "Add :provisioningProfiles:com.keyhollow.app.vault-thumbnail string KeyHollow Vault Thumbnail App Store",
        "PROFILE_NAME",
    ):
        require(
            violations,
            forbidden not in text,
            f"{name}: display-name or generic signing binding is forbidden: {forbidden}",
        )

    require(
        violations,
        text.count('--certificate-der "') == 2
        and text.count('--expected-app-uuid "$APP_PROFILE_UUID"') == 1
        and text.count('--expected-thumbnail-uuid "$THUMBNAIL_PROFILE_UUID"') == 1,
        f"{name}: signing verifier arguments drifted from preinstall/post-export policy",
    )
    require(
        violations,
        text.count("codesign --display") == 2
        and text.count("--extract-certificates") == 2
        and text.count("cmp -s") == 2
        and text.count("-exportArchive") == 1,
        f"{name}: app and extension leaf certificates must both be verified exactly",
    )

    require(
        violations,
        matching_command_lines(
            collapse_shell_continuations(text), "codesign --display"
        )
        == EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS,
        f"{name}: certificate extraction must bind each output prefix to the reviewed codesign option and target",
    )

    require(
        violations,
        matching_command_lines(text, "cmp -s")
        == EXPECTED_CERTIFICATE_COMPARISONS,
        f"{name}: app and extension certificate comparisons must use the imported DER as the fixed left operand",
    )

    install_step_name = (
        "Install and verify cloud-signing material"
        if name == "release-signing-preflight.yml"
        else "Install cloud-signing material"
    )
    install_step = named_step_block(text, install_step_name)
    require(
        violations,
        install_step is not None,
        f"{name}: exact signing-material installation step is missing",
    )
    if install_step is not None:
        require(
            violations,
            signing_secrets_unset_before_validator(install_step),
            f"{name}: all signing secrets must be unset together before the repository validator runs",
        )

    if len(validator_indexes) == 3:
        fingerprint_index = text.find("SIGNING_CERTIFICATE_SHA1=$(shasum")
        profile_copy_index = text.find('cp "$APP_PROFILE_PATH"')
        uuid_index = text.find("APP_PROFILE_UUID=$(")
        certificate_binding_index = text.find(expected_certificate_binding)
        export_index = text.find("-exportArchive")
        signature_index = text.find(
            'codesign --verify --deep --strict --verbose=2 "$SIGNED_APP_PATH"'
        )
        certificate_compare_index = text.find("cmp -s", validator_indexes[2])
        require(
            violations,
            0 <= validator_indexes[0]
            < fingerprint_index
            < validator_indexes[1]
            < uuid_index
            < profile_copy_index
            < certificate_binding_index
            < export_index
            < signature_index
            < validator_indexes[2]
            < certificate_compare_index,
            f"{name}: signing self-test, validation, binding, export, and verification order drifted",
        )

    violations.extend(
        audit_cleanup_step(
            name, named_step_block(text, "Remove temporary signing material")
        )
    )
    return violations


def preflight_publication_markers(text: str) -> list[str]:
    lowered = text.lower()
    forbidden = (
        "actions/upload-artifact@",
        "actions/upload-pages-artifact@",
        "xcrun altool",
        "--upload-app",
        "--upload-package",
        "itmstransporter",
        "notarytool",
        "gh release",
        "git push",
        "git tag",
        "npm publish",
        "docker push",
        "fastlane deliver",
        "fastlane pilot",
        "destination string upload",
        "-allowprovisioningupdates",
        "curl -x post",
        "curl --request post",
        "curl ",
        "wget ",
        "scp ",
        "sftp ",
        "rsync ",
        "gh api",
        "gh workflow",
    )
    return [marker for marker in forbidden if marker in lowered]


def audit_generic(name: str, text: str) -> list[str]:
    violations: list[str] = []

    require(
        violations,
        "\t" not in text,
        f"{name}: tabs are forbidden in security-sensitive YAML",
    )
    require(
        violations,
        not contains_line(text, r"^\s*(?:---|\.\.\.)\s*$"),
        f"{name}: multiple YAML documents are forbidden",
    )
    require(
        violations,
        not contains_line(text, r"(?:^|[\s{[,])(?:&|\*)[A-Za-z0-9_-]+|^\s*<<:"),
        f"{name}: YAML anchors, aliases, and merge keys are forbidden",
    )
    require(
        violations,
        not contains_line(text, r"^\s*continue-on-error:"),
        f"{name}: continue-on-error could hide a failed release gate",
    )

    for forbidden in (
        "pull_request_target:",
        "workflow_run:",
        "repository_dispatch:",
        "issue_comment:",
        "schedule:",
    ):
        require(
            violations,
            forbidden not in text,
            f"{name}: forbidden trigger or escalation surface {forbidden}",
        )

    require(
        violations,
        not contains_line(text, r"^\s*(?:container|services):"),
        f"{name}: container/service images are outside the approved supply chain",
    )
    require(
        violations,
        "brew install" not in text,
        f"{name}: unpinned Homebrew installation is forbidden",
    )

    for action in ACTION_REFERENCE.findall(text):
        if action.startswith("./"):
            continue
        reference = action.rsplit("@", 1)[-1] if "@" in action else ""
        require(
            violations,
            FULL_SHA.fullmatch(reference) is not None,
            f"{name}: action is not pinned to a lowercase 40-hex SHA: {action}",
        )
        require(
            violations,
            action in ALLOWED_ACTIONS,
            f"{name}: action is outside the reviewed allowlist: {action}",
        )

    checkout_count = len(
        re.findall(r"^\s*uses:\s*actions/checkout@", text, re.MULTILINE)
    )
    credentials_disabled = len(
        re.findall(r"^\s*persist-credentials:\s*false\s*$", text, re.MULTILINE)
    )
    require(
        violations,
        checkout_count == credentials_disabled,
        f"{name}: every checkout must explicitly disable persisted credentials",
    )

    require(
        violations,
        BRACKET_SECRET_REFERENCE.search(text) is None,
        f"{name}: bracket-style secret references are forbidden",
    )

    for body in run_script_bodies(text):
        require(
            violations,
            "${{" not in body,
            f"{name}: GitHub expressions may not be interpolated directly into a run script",
        )

    require(
        violations,
        not nonisolated_python_invocations(text),
        f"{name}: every Python invocation must use isolated mode (-I)",
    )

    for line in text.splitlines():
        if not re.search(r"\$\{\{\s*secrets(?:\.|\s*\[)", line):
            continue
        require(
            violations,
            re.match(
                r"^\s+[A-Z][A-Z0-9_]*:\s*\$\{\{\s*secrets\.[A-Z0-9_]+\s*}}\s*$",
                line,
            )
            is not None,
            f"{name}: secrets may only enter a shell step through an explicit env key",
        )

    return violations


def audit_ios_build(text: str) -> list[str]:
    name = "ios-build.yml"
    violations = audit_generic(name, text)
    violations.extend(
        audit_release_workflow_payloads(
            {name: text}, {name: RELEASE_WORKFLOW_SHA256[name]}
        )
    )
    on_section = top_level_section(text, "on")
    jobs_section = top_level_section(text, "jobs")

    require(
        violations,
        len(re.findall(r"^on:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level on section",
    )
    require(
        violations,
        len(re.findall(r"^jobs:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level jobs section",
    )
    require(violations, on_section is not None, f"{name}: missing on section")
    if on_section is not None:
        require(
            violations,
            direct_child_keys(on_section, 2) == ["push", "pull_request"],
            f"{name}: only push and pull_request triggers are permitted",
        )
        require(
            violations,
            len(re.findall(r"^\s{4}branches:\s*\[main]\s*$", on_section, re.MULTILINE))
            == 2,
            f"{name}: push and pull_request must both target main only",
        )

    require(violations, jobs_section is not None, f"{name}: missing jobs section")
    if jobs_section is not None:
        require(
            violations,
            direct_child_keys(jobs_section, 2) == ["build-and-test", "codeql"],
            f"{name}: expected exactly the build-and-test and codeql jobs",
        )

    require(
        violations,
        permission_blocks(text)
        == [
            {"contents": "read"},
            {"actions": "read", "contents": "read", "security-events": "write"},
        ],
        f"{name}: permissions drifted from read-only CI plus CodeQL upload",
    )
    require(
        violations,
        re.findall(r"^\s*if:\s*(.+?)\s*$", text, re.MULTILINE)
        == ["always()", "always()"],
        f"{name}: only the two diagnostic artifact steps may use conditions",
    )
    require(
        violations,
        not SECRET_REFERENCE.search(text),
        f"{name}: validation CI must not receive repository or environment secrets",
    )
    require(
        violations,
        text.count("runs-on: macos-15") == 2,
        f"{name}: both jobs must use the reviewed macOS runner image",
    )
    require(
        violations,
        text.count("DEVELOPER_DIR: /Applications/Xcode_26.0.1.app/Contents/Developer")
        == 2,
        f"{name}: both jobs must select the reviewed Xcode toolchain",
    )
    for command in (
        "python3 -I scripts/check_workflow_security.py",
        "python3 -I scripts/check_release_hygiene.py",
        "python3 -I scripts/check_architecture_boundaries.py",
        "node scripts/verify_testflight_build_number.mjs --self-test",
        "python3 -I scripts/verify_release_source.py --self-test",
        "python3 -I scripts/verify_release_environment.py --self-test",
        "python3 -I scripts/verify_signing_material.py --self-test",
        "python3 -I scripts/check_privacy_manifest.py",
        "bash scripts/install_xcodegen.sh",
    ):
        require(
            violations,
            command in text,
            f"{name}: required validation command is missing: {command}",
        )
    return violations


def audit_testflight_step_surface(text: str) -> list[str]:
    """Pin the production upload job's complete executable step surface."""

    name = "testflight.yml"
    violations: list[str] = []
    steps = workflow_step_blocks(text)
    step_names = [step_name for step_name, _ in steps]
    action_steps = set(TESTFLIGHT_ACTION_BLOCK_SHA256)
    require(
        violations,
        exact_step_inventory(text, TESTFLIGHT_STEP_NAMES),
        f"{name}: step inventory or ordering drifted",
    )

    expected_job_environment = [
        ("TEAM_ID", "P38X56QHU9"),
        (
            "DEVELOPER_DIR",
            "/Applications/Xcode_26.0.1.app/Contents/Developer",
        ),
        *list(APPROVED_ROTATION_BINDINGS.items()),
    ]
    require(
        violations,
        direct_mapping_entries(
            text, header="env", header_spaces=4, entry_spaces=6
        )
        == expected_job_environment,
        f"{name}: job environment must contain only the reviewed team, toolchain, and rotation bindings",
    )
    require(
        violations,
        set(TESTFLIGHT_RUN_BODY_SHA256)
        == set(TESTFLIGHT_STEP_NAMES) - action_steps
        and action_steps == {"Checkout", "Retain verified signed IPA artifact"},
        f"{name}: reviewed step-body inventory is incomplete",
    )

    for step_name, block in steps:
        direct_entries = direct_key_value_entries(block, spaces=8)
        step_keys = [key for key, _ in direct_entries]
        require(
            violations,
            step_keys == TESTFLIGHT_STEP_KEYS.get(step_name, ["run"]),
            f"{name}: keys drifted in step {step_name}",
        )
        env_entries = direct_mapping_entries(
            block, header="env", header_spaces=8, entry_spaces=10
        )
        require(
            violations,
            env_entries == TESTFLIGHT_STEP_ENVIRONMENT.get(step_name, []),
            f"{name}: environment bindings drifted in step {step_name}",
        )
        shells = [value for key, value in direct_entries if key == "shell"]
        expected_shells = (
            ["bash"] if step_name in TESTFLIGHT_EXPLICIT_BASH_STEPS else []
        )
        require(
            violations,
            shells == expected_shells,
            f"{name}: interpreter drifted in step {step_name}",
        )

        if step_name in action_steps:
            require(
                violations,
                step_run_scalar_style(block) is None
                and not run_script_bodies(block)
                and body_sha256(block)
                == TESTFLIGHT_ACTION_BLOCK_SHA256.get(step_name),
                f"{name}: reviewed action block drifted in step {step_name}",
            )
            continue

        expected_run_style = (
            "literal" if step_name in TESTFLIGHT_LITERAL_RUN_STEPS else "inline"
        )
        body = step_run_body(block)
        require(
            violations,
            step_run_scalar_style(block) == expected_run_style,
            f"{name}: run scalar style drifted in step {step_name}",
        )
        require(
            violations,
            not ACTION_REFERENCE.findall(block)
            and is_reviewed_run_body(
                step_name, body, TESTFLIGHT_RUN_BODY_SHA256
            ),
            f"{name}: reviewed command body drifted in step {step_name}",
        )
    return violations


def audit_testflight(text: str, release_source: str) -> list[str]:
    name = "testflight.yml"
    violations = audit_generic(name, text)
    violations.extend(
        audit_release_workflow_payloads(
            {name: text}, {name: RELEASE_WORKFLOW_SHA256[name]}
        )
    )
    violations.extend(audit_testflight_step_surface(text))
    violations.extend(
        audit_release_job_structure(name, text, job_name="archive-and-upload")
    )
    on_section = top_level_section(text, "on")
    jobs_section = top_level_section(text, "jobs")

    require(
        violations,
        len(re.findall(r"^on:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level on section",
    )
    require(
        violations,
        len(re.findall(r"^jobs:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level jobs section",
    )
    require(violations, on_section is not None, f"{name}: missing on section")
    if on_section is not None:
        require(
            violations,
            direct_child_keys(on_section, 2) == ["workflow_dispatch"],
            f"{name}: production delivery must be manual only",
        )
        require(
            violations,
            direct_child_keys(on_section, 6)
            == ["build_number", "expected_commit_sha"],
            f"{name}: production inputs must be build number and exact commit only",
        )

    require(violations, jobs_section is not None, f"{name}: missing jobs section")
    if jobs_section is not None:
        require(
            violations,
            direct_child_keys(jobs_section, 2) == ["archive-and-upload"],
            f"{name}: expected exactly one production delivery job",
        )

    require(
        violations,
        permission_blocks(text) == [{"actions": "read", "contents": "read"}],
        f"{name}: production token permissions must remain read-only",
    )
    require(
        violations,
        re.findall(r"^\s*if:\s*(.+?)\s*$", text, re.MULTILINE)
        == [
            "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
            "success()",
            "always()",
        ],
        f"{name}: only the main dispatch gate and two cleanup/artifact conditions are permitted",
    )
    require(
        violations,
        "if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'"
        in text,
        f"{name}: delivery job must be bound to a manual main-branch dispatch",
    )
    artifact_step = named_step_block(text, "Retain verified signed IPA artifact")
    require(
        violations,
        testflight_artifact_step_is_fail_closed(artifact_step),
        f"{name}: signed IPA artifact must be success-only and fail if the IPA is missing",
    )
    require(
        violations,
        "APP_STORE_CONNECT_API_KEY_PATH" not in text,
        f"{name}: upload-key paths must not be propagated through GITHUB_ENV",
    )
    require(
        violations,
        "environment: production-testflight" in text,
        f"{name}: production delivery must use the protected environment",
    )
    require(
        violations,
        "group: keyhollow-production-testflight" in text
        and "cancel-in-progress: false" in text,
        f"{name}: production uploads must be serialized without cancellation",
    )
    require(
        violations,
        text.count("runs-on: macos-15") == 1,
        f"{name}: delivery must use the reviewed macOS runner image",
    )
    require(
        violations,
        "DEVELOPER_DIR: /Applications/Xcode_26.0.1.app/Contents/Developer" in text
        and release_toolchain_step_is_exact(text),
        f"{name}: delivery must select and verify the reviewed Xcode toolchain",
    )
    for required in (
        "EXPECTED_COMMIT_SHA: ${{ inputs.expected_commit_sha }}",
        "[[ ! \"$EXPECTED_COMMIT_SHA\" =~ ^[0-9a-f]{40}$ ]]",
        "[[ \"$EXPECTED_COMMIT_SHA\" != \"$GITHUB_SHA\" ]]",
        "[[ \"$(git rev-parse HEAD)\" != \"$GITHUB_SHA\" ]]",
        "python3 -I scripts/check_workflow_security.py",
        "python3 -I scripts/verify_release_source.py",
        "python3 -I scripts/verify_release_environment.py",
        "python3 -I scripts/check_release_hygiene.py",
        "python3 -I scripts/check_architecture_boundaries.py",
        "node scripts/verify_testflight_build_number.mjs --self-test",
        "python3 -I scripts/verify_signing_material.py --self-test",
        "python3 -I scripts/check_privacy_manifest.py",
        "bash scripts/install_xcodegen.sh",
    ):
        require(
            violations,
            required in text,
            f"{name}: required release control is missing: {required}",
        )

    violations.extend(audit_release_secret_boundary(name, text))
    violations.extend(audit_approved_rotation(name, text))
    require(
        violations,
        "${{ inputs.build_number }}" not in "\n".join(run_script_bodies(text)),
        f"{name}: build-number input must reach scripts through env, not interpolation",
    )
    initial_build_check = named_step_block(
        text, "Verify build number against App Store Connect"
    )
    final_upload_step = named_step_block(
        text, "Upload verified IPA to App Store Connect"
    )
    initial_build_check_body = (
        step_run_body(initial_build_check) if initial_build_check is not None else None
    )
    require(
        violations,
        text.count(TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND) == 2
        and initial_build_check_body is not None
        and initial_build_check_body.count(TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND) == 1
        and testflight_final_build_recheck_is_exact(final_upload_step),
        f"{name}: build number must be checked once early and once immediately before P8 creation/upload",
    )
    violations.extend(
        audit_signing_pipeline(
            name,
            text,
            export_options_path="build/ExportOptions.plist",
        )
    )
    signed_verification_index = text.find("- name: Verify signed IPA")
    final_certificate_compare_index = text.rfind("cmp -s")
    signing_teardown_index = text.find(
        "- name: Remove signing authority before external actions"
    )
    artifact_index = text.find("- name: Retain verified signed IPA artifact")
    upload_step_index = text.find(
        "- name: Upload verified IPA to App Store Connect"
    )
    upload_index = text.find("xcrun altool")
    require(
        violations,
        text.count("xcrun altool") == 1
        and text.count("--upload-app") == 1
        and 0
        <= signed_verification_index
        < final_certificate_compare_index
        < signing_teardown_index
        < artifact_index
        < upload_step_index
        < upload_index,
        f"{name}: verification and strict signing teardown must precede every external action",
    )
    signing_teardown = named_step_block(
        text, "Remove signing authority before external actions"
    )
    require(
        violations,
        testflight_signing_teardown_is_fail_closed(signing_teardown),
        f"{name}: pre-external signing-authority teardown must remain fail-closed",
    )

    release_requirements = (
        'TRUSTED_EVENT = "push"',
        'TRUSTED_BRANCH = "main"',
        "REPOSITORY_PATTERN.fullmatch(args.repository)",
        'run.get("head_sha") == commit',
        'run.get("status") == "completed"',
        'run.get("conclusion") == "success"',
        'run.get("event") == TRUSTED_EVENT',
        'run.get("head_branch") == TRUSTED_BRANCH',
        '{"head_sha": commit, "status": "completed", "per_page": 100}',
        "actions/workflows/",
    )
    for required in release_requirements:
        require(
            violations,
            required in release_source,
            f"verify_release_source.py: required exact-source rule is missing: {required}",
        )

    environment_source_path = ROOT / "scripts" / "verify_release_environment.py"
    environment_source = (
        environment_source_path.read_text(encoding="utf-8")
        if environment_source_path.is_file()
        else ""
    )
    violations.extend(audit_environment_verifier_source(environment_source))
    return violations


def audit_preflight_step_surface(text: str) -> list[str]:
    """Keep the non-publishing preflight's executable surface exact."""

    name = "release-signing-preflight.yml"
    violations: list[str] = []
    steps = workflow_step_blocks(text)
    step_names = [step_name for step_name, _ in steps]
    require(
        violations,
        exact_step_inventory(text, PREFLIGHT_STEP_NAMES),
        f"{name}: step inventory or ordering drifted",
    )

    expected_job_environment = [
        ("TEAM_ID", "P38X56QHU9"),
        (
            "DEVELOPER_DIR",
            "/Applications/Xcode_26.0.1.app/Contents/Developer",
        ),
        *list(APPROVED_ROTATION_BINDINGS.items()),
    ]
    require(
        violations,
        direct_mapping_entries(
            text, header="env", header_spaces=4, entry_spaces=6
        )
        == expected_job_environment,
        f"{name}: job environment must contain only the reviewed team, toolchain, and rotation bindings",
    )
    require(
        violations,
        not contains_line(text, r"^\s+defaults:"),
        f"{name}: workflow defaults may not override the reviewed shell",
    )

    require(
        violations,
        set(PREFLIGHT_RUN_BODY_SHA256)
        == set(PREFLIGHT_STEP_NAMES) - {"Checkout"},
        f"{name}: reviewed run-body inventory is incomplete",
    )

    for step_name, block in steps:
        direct_entries = direct_key_value_entries(block, spaces=8)
        step_keys = [key for key, _ in direct_entries]
        require(
            violations,
            step_keys == PREFLIGHT_STEP_KEYS.get(step_name, ["run"]),
            f"{name}: keys drifted in step {step_name}",
        )
        env_entries = direct_mapping_entries(
            block, header="env", header_spaces=8, entry_spaces=10
        )
        require(
            violations,
            env_entries == PREFLIGHT_STEP_ENVIRONMENT.get(step_name, []),
            f"{name}: environment bindings drifted in step {step_name}",
        )

        shells = [value for key, value in direct_entries if key == "shell"]
        expected_shells = ["bash"] if step_name in PREFLIGHT_EXPLICIT_BASH_STEPS else []
        require(
            violations,
            shells == expected_shells,
            f"{name}: interpreter drifted in step {step_name}",
        )

        if step_name == "Checkout":
            checkout_block = (
                "      - name: Checkout\n"
                "        uses: actions/checkout@"
                "d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0\n"
                "        with:\n"
                "          persist-credentials: false"
            )
            require(
                violations,
                len(run_script_bodies(block)) == 0
                and ACTION_REFERENCE.findall(block)
                == [
                    "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"
                ]
                and block == checkout_block,
                f"{name}: checkout step gained executable or unreviewed capability",
            )
            continue

        expected_run_style = (
            "literal" if step_name in PREFLIGHT_LITERAL_RUN_STEPS else "inline"
        )
        require(
            violations,
            step_run_scalar_style(block) == expected_run_style,
            f"{name}: run scalar style drifted in step {step_name}",
        )
        body = step_run_body(block)
        require(
            violations,
            not ACTION_REFERENCE.findall(block)
            and is_reviewed_preflight_body(step_name, body),
            f"{name}: reviewed command body drifted in step {step_name}",
        )
    return violations


def audit_release_signing_preflight(
    text: str, build_number_source: str
) -> list[str]:
    name = "release-signing-preflight.yml"
    violations = audit_generic(name, text)
    violations.extend(
        audit_release_workflow_payloads(
            {name: text}, {name: RELEASE_WORKFLOW_SHA256[name]}
        )
    )
    violations.extend(
        audit_release_job_structure(name, text, job_name="sign-without-upload")
    )
    violations.extend(audit_preflight_step_surface(text))
    on_section = top_level_section(text, "on")
    concurrency_section = top_level_section(text, "concurrency")
    jobs_section = top_level_section(text, "jobs")
    main_dispatch_gate = (
        "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'"
    )

    require(
        violations,
        len(re.findall(r"^on:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level on section",
    )
    require(
        violations,
        len(re.findall(r"^jobs:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level jobs section",
    )
    require(violations, on_section is not None, f"{name}: missing on section")
    if on_section is not None:
        require(
            violations,
            direct_child_keys(on_section, 2) == ["workflow_dispatch"],
            f"{name}: signing preflight must be manual only",
        )
        require(
            violations,
            direct_child_keys(on_section, 6) == ["expected_commit_sha"],
            f"{name}: preflight input must be the exact commit only",
        )

    require(
        violations,
        concurrency_section is not None
        and direct_child_keys(concurrency_section, 2)
        == ["group", "cancel-in-progress"]
        and "group: keyhollow-production-testflight" in concurrency_section
        and "cancel-in-progress: false" in concurrency_section,
        f"{name}: preflight must share the serialized production concurrency gate",
    )
    require(violations, jobs_section is not None, f"{name}: missing jobs section")
    if jobs_section is not None:
        require(
            violations,
            direct_child_keys(jobs_section, 2) == ["sign-without-upload"],
            f"{name}: expected exactly one non-uploading signing job",
        )

    require(
        violations,
        permission_blocks(text) == [{"actions": "read", "contents": "read"}],
        f"{name}: preflight token permissions must remain read-only",
    )
    require(
        violations,
        re.findall(r"^\s*if:\s*(.+?)\s*$", text, re.MULTILINE)
        == [main_dispatch_gate, "always()"],
        f"{name}: only the main dispatch gate and cleanup condition are permitted",
    )
    require(
        violations,
        text.count(f"if: {main_dispatch_gate}") == 1,
        f"{name}: preflight job must be bound to a manual main-branch dispatch",
    )
    require(
        violations,
        text.count("environment: production-testflight") == 1,
        f"{name}: preflight must use the protected production environment",
    )
    require(
        violations,
        text.count("runs-on: macos-15") == 1
        and text.count("timeout-minutes: 30") == 1,
        f"{name}: preflight must use the reviewed bounded macOS runner",
    )
    require(
        violations,
        text.count(
            "DEVELOPER_DIR: /Applications/Xcode_26.0.1.app/Contents/Developer"
        )
        == 1
        and release_toolchain_step_is_exact(text),
        f"{name}: preflight must select and verify the reviewed Xcode toolchain",
    )

    checkout_action = (
        "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"
    )
    require(
        violations,
        ACTION_REFERENCE.findall(text) == [checkout_action],
        f"{name}: checkout must be the preflight's only external action",
    )
    for required in (
        "EXPECTED_COMMIT_SHA: ${{ inputs.expected_commit_sha }}",
        "[[ ! \"$EXPECTED_COMMIT_SHA\" =~ ^[0-9a-f]{40}$ ]]",
        "[[ \"$EXPECTED_COMMIT_SHA\" != \"$GITHUB_SHA\" ]]",
        "[[ \"$(git rev-parse HEAD)\" != \"$GITHUB_SHA\" ]]",
        "python3 -I scripts/check_workflow_security.py",
        "python3 -I scripts/verify_release_source.py",
        "python3 -I scripts/verify_release_environment.py",
        "python3 -I scripts/check_release_hygiene.py",
        "python3 -I scripts/check_architecture_boundaries.py",
        "python3 -I scripts/verify_signing_material.py --self-test",
        "node scripts/verify_testflight_build_number.mjs --self-test",
        "python3 -I scripts/check_privacy_manifest.py",
        "bash scripts/install_xcodegen.sh",
        "node scripts/verify_testflight_build_number.mjs --auth-only",
        "CODE_SIGNING_ALLOWED=NO",
    ):
        require(
            violations,
            required in text,
            f"{name}: required preflight control is missing: {required}",
        )

    violations.extend(audit_release_secret_boundary(name, text))
    violations.extend(audit_approved_rotation(name, text))
    violations.extend(
        audit_signing_pipeline(
            name,
            text,
            export_options_path="build/PreflightExportOptions.plist",
        )
    )

    publication_markers = preflight_publication_markers(text)
    require(
        violations,
        not publication_markers,
        f"{name}: publication capability is forbidden: {publication_markers}",
    )
    require(
        violations,
        build_number_source.count("fetch(") == 1
        and "const response = await fetch(nextURL, {" in build_number_source
        and 'redirect: "error"' in build_number_source
        and "validateBuildLookupURL(candidateNextURL, appID)" in build_number_source
        and 'APP_STORE_CONNECT_ORIGIN = "https://api.appstoreconnect.apple.com"'
        in build_number_source
        and "method:" not in build_number_source,
        "verify_testflight_build_number.mjs: auth-only preflight lookup must remain GET-only and origin-pinned",
    )
    return violations


def audit_retired_beta(text: str) -> list[str]:
    name = "testflight-beta.yml"
    violations = audit_generic(name, text)
    violations.extend(
        audit_release_workflow_payloads(
            {name: text}, {name: RELEASE_WORKFLOW_SHA256[name]}
        )
    )
    on_section = top_level_section(text, "on")
    jobs_section = top_level_section(text, "jobs")

    require(
        violations,
        len(re.findall(r"^on:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level on section",
    )
    require(
        violations,
        len(re.findall(r"^jobs:\s*$", text, re.MULTILINE)) == 1,
        f"{name}: expected exactly one top-level jobs section",
    )
    require(violations, on_section is not None, f"{name}: missing on section")
    if on_section is not None:
        require(
            violations,
            direct_child_keys(on_section, 2) == ["workflow_dispatch"],
            f"{name}: retired beta stub may only expose a manual no-op trigger",
        )
    require(violations, jobs_section is not None, f"{name}: missing jobs section")
    if jobs_section is not None:
        require(
            violations,
            direct_child_keys(jobs_section, 2) == ["retired"],
            f"{name}: retired beta stub must contain exactly one inert job",
        )

    require(
        violations,
        permission_blocks(text) == [{"__inline__": "{}"}],
        f"{name}: retired beta workflow must receive no token permissions",
    )
    require(
        violations,
        contains_line(text, r"^\s+if:\s*\$\{\{\s*false\s*}}\s*$"),
        f"{name}: retired beta job must have an unconditional false guard",
    )
    for forbidden in (
        "secrets.",
        "uses:",
        "xcodebuild",
        "xcrun",
        "altool",
        "app-store-connect",
        "delivery/v2-beta",
    ):
        require(
            violations,
            forbidden not in text,
            f"{name}: retired beta stub contains delivery capability: {forbidden}",
        )
    require(
        violations,
        "exit 1" in text,
        f"{name}: retired beta diagnostic step must fail if its job ever executes",
    )
    return violations


def audit_repository() -> list[str]:
    violations = audit_privileged_source_hashes()
    workflow_paths = sorted(
        path
        for path in WORKFLOW_DIRECTORY.iterdir()
        if path.is_file() and path.suffix in {".yml", ".yaml"}
    )
    names = {path.name for path in workflow_paths}
    if names != EXPECTED_WORKFLOWS:
        violations.append(
            "workflow inventory drifted: "
            f"expected {sorted(EXPECTED_WORKFLOWS)}, found {sorted(names)}"
        )

    texts = {
        path.name: path.read_text(encoding="utf-8") for path in workflow_paths
    }
    violations.extend(
        audit_release_workflow_payloads(texts, RELEASE_WORKFLOW_SHA256)
    )
    release_path = ROOT / "scripts" / "verify_release_source.py"
    release_source = (
        release_path.read_text(encoding="utf-8") if release_path.is_file() else ""
    )
    build_number_path = ROOT / "scripts" / "verify_testflight_build_number.mjs"
    build_number_source = (
        build_number_path.read_text(encoding="utf-8")
        if build_number_path.is_file()
        else ""
    )
    hygiene_path = ROOT / "scripts" / "check_release_hygiene.py"
    hygiene_source = (
        hygiene_path.read_text(encoding="utf-8") if hygiene_path.is_file() else ""
    )
    project_path = ROOT / "project.yml"
    project_source = (
        project_path.read_text(encoding="utf-8") if project_path.is_file() else ""
    )
    violations.extend(audit_project_execution_surface(project_source))
    for required in (
        'SOURCE_SUFFIXES = {".swift", ".c", ".h"}',
        "ASSET_CATALOGS = {",
        "EXACT_NON_SOURCE_FILES = {",
        "audit_source_trees(ROOT)",
        "asset file is not declared by Contents.json",
        "symlinks are forbidden",
    ):
        if required not in hygiene_source:
            violations.append(
                f"check_release_hygiene.py: source-tree allowlist is missing: {required}"
            )

    if "ios-build.yml" in texts:
        violations.extend(audit_ios_build(texts["ios-build.yml"]))
    if "release-signing-preflight.yml" in texts:
        violations.extend(
            audit_release_signing_preflight(
                texts["release-signing-preflight.yml"], build_number_source
            )
        )
    if "testflight.yml" in texts:
        violations.extend(audit_testflight(texts["testflight.yml"], release_source))
    if "testflight-beta.yml" in texts:
        violations.extend(audit_retired_beta(texts["testflight-beta.yml"]))

    codeowners_path = ROOT / ".github" / "CODEOWNERS"
    if not codeowners_path.is_file():
        violations.append(".github/CODEOWNERS: sensitive-path ownership is missing")
    else:
        actual_codeowners = {
            line.strip()
            for line in codeowners_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        if actual_codeowners != EXPECTED_CODEOWNERS:
            violations.append(
                ".github/CODEOWNERS: sensitive-path ownership entries drifted"
            )
    return violations


def self_test() -> int:
    privileged_fixture = b"#!/usr/bin/env python3\nprint('reviewed')\n"
    privileged_expected = {
        "scripts/reviewed.py": canonical_source_sha256(privileged_fixture)
    }
    assert isinstance(privileged_expected["scripts/reviewed.py"], str)
    assert audit_privileged_source_payloads(
        {"scripts/reviewed.py": privileged_fixture}, privileged_expected
    ) == []
    assert audit_privileged_source_payloads(
        {"scripts/reviewed.py": privileged_fixture + b"print('injected')\n"},
        privileged_expected,
    )
    assert audit_privileged_source_payloads(
        {"scripts/reviewed.py": None}, privileged_expected
    )
    assert canonical_source_sha256(privileged_fixture.replace(b"\n", b"\r\n")) == (
        privileged_expected["scripts/reviewed.py"]
    )
    assert canonical_source_sha256(privileged_fixture + b"\rmutation") is None

    privileged_payloads = {
        relative_path: f"reviewed:{relative_path}\n".encode("utf-8")
        for relative_path in PRIVILEGED_SOURCE_SHA256
    }
    privileged_fixture_hashes = {
        relative_path: canonical_source_sha256(payload)
        for relative_path, payload in privileged_payloads.items()
    }
    assert audit_privileged_source_payloads(
        privileged_payloads, privileged_fixture_hashes
    ) == []
    for relative_path in privileged_payloads:
        mutated_payloads = dict(privileged_payloads)
        mutated_payloads[relative_path] += b"injected\n"
        assert any(
            violation.startswith(f"{relative_path}:")
            for violation in audit_privileged_source_payloads(
                mutated_payloads, privileged_fixture_hashes
            )
        )

    workflow_fixture = "name: Reviewed\non: workflow_dispatch\npermissions: {}\njobs: {}\n"
    workflow_expected = {"fixture.yml": body_sha256(workflow_fixture)}
    assert audit_release_workflow_payloads(
        {"fixture.yml": workflow_fixture}, workflow_expected
    ) == []
    for workflow_mutation in (
        "\nexit 0",
        "\necho ok # python3 -I scripts/check_workflow_security.py",
        "\n- run: curl https://example.invalid",
        "\n# comment-only semantic drift",
    ):
        assert audit_release_workflow_payloads(
            {"fixture.yml": workflow_fixture + workflow_mutation},
            workflow_expected,
        )

    workflow_payloads = {
        workflow_name: f"name: reviewed-{workflow_name}\n"
        for workflow_name in RELEASE_WORKFLOW_SHA256
    }
    workflow_fixture_hashes = {
        workflow_name: body_sha256(payload)
        for workflow_name, payload in workflow_payloads.items()
    }
    assert audit_release_workflow_payloads(
        workflow_payloads, workflow_fixture_hashes
    ) == []
    for workflow_name in workflow_payloads:
        mutated_workflows = dict(workflow_payloads)
        mutated_workflows[workflow_name] += "steps: [{run: injected}]\n"
        assert any(
            violation.startswith(f"{workflow_name}:")
            for violation in audit_release_workflow_payloads(
                mutated_workflows, workflow_fixture_hashes
            )
        )

    assert audit_project_execution_surface("targets:\n  App:\n") == []
    for execution_key in FORBIDDEN_XCODEGEN_EXECUTION_KEYS:
        assert audit_project_execution_surface(
            f"targets:\n  App:\n    {execution_key}: injected\n"
        )

    assert nonisolated_python_invocations(
        "steps:\n  - run: python3 -I scripts/reviewed.py"
    ) == []
    assert nonisolated_python_invocations(
        "steps:\n  - run: python3 scripts/reviewed.py"
    )

    pinned = "uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"
    assert not any("not pinned" in item for item in audit_generic("fixture", pinned))

    unpinned = "uses: actions/checkout@v6"
    assert any("not pinned" in item for item in audit_generic("fixture", unpinned))

    injected = "steps:\n  - run: echo '${{ inputs.value }}'\n"
    assert any(
        "interpolated directly" in item for item in audit_generic("fixture", injected)
    )

    bracket_input = "steps:\n  - run: echo \"${{ inputs['value'] }}\"\n"
    assert any(
        "interpolated directly" in item
        for item in audit_generic("fixture", bracket_input)
    )
    bracket_context = (
        "steps:\n  - run: echo \"${{ github['event']['issue']['title'] }}\"\n"
    )
    assert any(
        "interpolated directly" in item
        for item in audit_generic("fixture", bracket_context)
    )

    bracket_secret = (
        "steps:\n"
        "  - env:\n"
        "      VALUE: ${{ secrets['BUILD_CERTIFICATE_BASE64'] }}\n"
        "    run: printf '%s\\n' \"$VALUE\"\n"
    )
    assert any(
        "bracket-style secret" in item
        for item in audit_generic("fixture", bracket_secret)
    )

    safe_env = (
        "steps:\n"
        "  - env:\n"
        "      VALUE: ${{ inputs.value }}\n"
        "    run: printf '%s\\n' \"$VALUE\"\n"
    )
    assert not any(
        "interpolated directly" in item for item in audit_generic("fixture", safe_env)
    )

    rotation_fixture = "\n".join(
        [
            *(f"      {key}: {value}" for key, value in APPROVED_ROTATION_BINDINGS.items()),
            (
                'if [[ "$APP_STORE_CONNECT_API_KEY_ID" != "$EXPECTED_API_KEY_ID" || '
                '"$APP_STORE_CONNECT_API_ISSUER_ID" != "$EXPECTED_API_ISSUER_ID" ]]; then'
            ),
            (
                'if [[ "$SIGNING_CERTIFICATE_SHA1" != '
                '"$EXPECTED_SIGNING_CERTIFICATE_SHA1" ]]; then'
            ),
            (
                'if [[ "$NORMALIZED_APP_PROFILE_UUID" != "$EXPECTED_APP_PROFILE_UUID" || '
                '"$NORMALIZED_THUMBNAIL_PROFILE_UUID" != '
                '"$EXPECTED_THUMBNAIL_PROFILE_UUID" ]]; then'
            ),
        ]
    )
    assert audit_approved_rotation("fixture", rotation_fixture) == []
    changed_rotation = rotation_fixture
    for value in APPROVED_ROTATION_BINDINGS.values():
        changed_rotation = changed_rotation.replace(value, "UNREVIEWED", 1)
    assert any(
        "rotation binding drifted" in item
        for item in audit_approved_rotation("fixture", changed_rotation)
    )
    missing_identity_check = rotation_fixture.replace(
        'if [[ "$SIGNING_CERTIFICATE_SHA1" != '
        '"$EXPECTED_SIGNING_CERTIFICATE_SHA1" ]]; then',
        "",
    )
    assert any(
        "distribution certificate comparison" in item
        for item in audit_approved_rotation("fixture", missing_identity_check)
    )

    environment_source_fixture = "\n".join(ENVIRONMENT_VERIFIER_REQUIREMENTS)
    assert audit_environment_verifier_source(environment_source_fixture) == []
    for required in (
        'REQUIRED_REVIEWER_LOGIN = "Frankbell84"',
        'environment.get("can_admins_bypass") is not False',
        'expected_rule_types = ["branch_policy", "required_reviewers"]',
        'required_reviewers_rule.get("prevent_self_review") is not False',
        'reviewer.get("login") != REQUIRED_REVIEWER_LOGIN',
        "urllib.request.build_opener(RejectRedirectHandler())",
        "validate_github_api_url(response.geturl(), repository)",
    ):
        assert audit_environment_verifier_source(
            environment_source_fixture.replace(required, "", 1)
        )

    exact_certificates = "\n".join(EXPECTED_CERTIFICATE_COMPARISONS)
    assert matching_command_lines(exact_certificates, "cmp -s") == (
        EXPECTED_CERTIFICATE_COMPARISONS
    )
    for comparison_mutation in (
        exact_certificates.replace(
            '"$RUNNER_TEMP/keyhollow-distribution.cer"',
            '"$APP_CERTIFICATE_DIRECTORY/cert0"',
            1,
        ),
        exact_certificates.replace("/cert0", "/cert1", 1),
        exact_certificates.replace(
            EXPECTED_CERTIFICATE_COMPARISONS[0],
            (
                'if ! cmp -s "$APP_CERTIFICATE_DIRECTORY/cert0" '
                '"$RUNNER_TEMP/keyhollow-distribution.cer"; then'
            ),
            1,
        ),
        EXPECTED_CERTIFICATE_COMPARISONS[0],
        exact_certificates + "\n" + EXPECTED_CERTIFICATE_COMPARISONS[0],
    ):
        assert matching_command_lines(
            comparison_mutation, "cmp -s"
        ) != EXPECTED_CERTIFICATE_COMPARISONS

    exact_certificate_extractions = "\n".join(
        EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS
    )
    assert matching_command_lines(
        collapse_shell_continuations(exact_certificate_extractions),
        "codesign --display",
    ) == EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS
    multiline_certificate_extractions = (
        "codesign --display \\\n"
        '  --extract-certificates="$APP_CERTIFICATE_DIRECTORY/cert" \\\n'
        '  "$SIGNED_APP_PATH"\n'
        "codesign --display \\\n"
        '  --extract-certificates="$THUMBNAIL_CERTIFICATE_DIRECTORY/cert" \\\n'
        '  "$SIGNED_EXTENSION_PATH"'
    )
    assert matching_command_lines(
        collapse_shell_continuations(multiline_certificate_extractions),
        "codesign --display",
    ) == EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS
    for extraction_mutation in (
        exact_certificate_extractions.replace(
            '--extract-certificates=', '--extract-certificates ', 1
        ),
        exact_certificate_extractions.replace(
            '--extract-certificates="$APP_CERTIFICATE_DIRECTORY/cert" ',
            '--extract-certificates ',
            1,
        ),
        exact_certificate_extractions.replace(
            '$APP_CERTIFICATE_DIRECTORY/cert',
            '$THUMBNAIL_CERTIFICATE_DIRECTORY/cert',
            1,
        ),
        exact_certificate_extractions.replace(
            '"$SIGNED_APP_PATH"', '"$SIGNED_EXTENSION_PATH"', 1
        ),
        EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS[0],
        exact_certificate_extractions
        + "\n"
        + EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS[0],
    ):
        assert matching_command_lines(
            collapse_shell_continuations(extraction_mutation),
            "codesign --display",
        ) != EXPECTED_CODESIGN_CERTIFICATE_EXTRACTIONS

    assert matching_command_lines(
        SIGNING_IMPORT_COMMAND, "security import "
    ) == [SIGNING_IMPORT_COMMAND]
    for import_mutation in (
        SIGNING_IMPORT_COMMAND.replace("-t agg", "-t cert", 1),
        SIGNING_IMPORT_COMMAND.replace(" -x ", " ", 1),
        SIGNING_IMPORT_COMMAND + "\n" + SIGNING_IMPORT_COMMAND,
    ):
        assert matching_command_lines(
            import_mutation, "security import "
        ) != [SIGNING_IMPORT_COMMAND]

    assert matching_command_lines(
        SIGNING_LEAF_EXTRACTION_COMMAND, "openssl pkcs12 "
    ) == [SIGNING_LEAF_EXTRACTION_COMMAND]
    for extraction_mutation in (
        SIGNING_LEAF_EXTRACTION_COMMAND.replace(" -clcerts", "", 1),
        SIGNING_LEAF_EXTRACTION_COMMAND.replace(" -nokeys", "", 1),
        SIGNING_LEAF_EXTRACTION_COMMAND.replace(
            "-passin env:P12_PASSWORD", "-passin pass:plaintext", 1
        ),
        SIGNING_LEAF_EXTRACTION_COMMAND + "\n" + SIGNING_LEAF_EXTRACTION_COMMAND,
    ):
        assert matching_command_lines(
            extraction_mutation, "openssl pkcs12 "
        ) != [SIGNING_LEAF_EXTRACTION_COMMAND]

    identity_commands = "\n".join(
        (
            SIGNING_IDENTITY_LIST_COMMAND,
            SIGNING_VALID_IDENTITY_COUNT_COMMAND,
            SIGNING_MATCHING_IDENTITY_COUNT_COMMAND,
        )
    )
    assert matching_command_lines(
        identity_commands, "security find-identity "
    ) == [SIGNING_IDENTITY_LIST_COMMAND]
    assert matching_command_lines(
        identity_commands, "VALID_IDENTITY_COUNT="
    ) == [SIGNING_VALID_IDENTITY_COUNT_COMMAND]
    assert matching_command_lines(
        identity_commands, "IDENTITY_MATCH_COUNT="
    ) == [SIGNING_MATCHING_IDENTITY_COUNT_COMMAND]
    for identity_mutation in (
        identity_commands.replace('"$KEYCHAIN_PATH"', '"login.keychain-db"', 1),
        identity_commands.replace("length($2) == 40", "length($2) > 0", 1),
        identity_commands.replace(
            '-v expected="$SIGNING_CERTIFICATE_SHA1"', "", 1
        ),
        identity_commands + "\n" + SIGNING_IDENTITY_LIST_COMMAND,
    ):
        assert (
            matching_command_lines(identity_mutation, "security find-identity ")
            != [SIGNING_IDENTITY_LIST_COMMAND]
            or matching_command_lines(identity_mutation, "VALID_IDENTITY_COUNT=")
            != [SIGNING_VALID_IDENTITY_COUNT_COMMAND]
            or matching_command_lines(identity_mutation, "IDENTITY_MATCH_COUNT=")
            != [SIGNING_MATCHING_IDENTITY_COUNT_COMMAND]
        )

    cleanup_fixture = "\n".join(
        [
            "      - name: Remove temporary signing material",
            "        if: always()",
            "        run: |",
            *(
                f"          {line}"
                for line in (
                    *COMMON_CLEANUP_REQUIREMENTS,
                    *WORKFLOW_CLEANUP_REQUIREMENTS[
                        "release-signing-preflight.yml"
                    ],
                    "rm -f one",
                    "rm -f two",
                    "rm -rf three",
                )
            ),
        ]
    )
    assert not any(
        "cleanup no longer removes" in item
        for item in audit_cleanup_step(
            "release-signing-preflight.yml", cleanup_fixture
        )
    )
    assert any(
        "cleanup no longer removes" in item
        for item in audit_cleanup_step(
            "release-signing-preflight.yml",
            cleanup_fixture.replace(
                '"$RUNNER_TEMP/keyhollow-distribution.p12"', "", 1
            ),
        )
    )
    assert any(
        "additional capabilities" in item
        for item in audit_cleanup_step(
            "release-signing-preflight.yml",
            cleanup_fixture.replace(
                "        run: |",
                "        env:\n"
                "          APP_STORE_CONNECT_API_KEY_ID: "
                "${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}\n"
                "        run: |",
                1,
            ),
        )
    )

    reviewed_body_name = "Verify workflow security"
    reviewed_body = "python3 -I scripts/check_workflow_security.py"
    assert is_reviewed_preflight_body(reviewed_body_name, reviewed_body)
    for injected_command in (
        "python3 -c 'import urllib.request'",
        "node -e 'fetch(process.env.DESTINATION)'",
        "bash -c 'curl https://example.invalid'",
        "curl https://example.invalid",
    ):
        assert not is_reviewed_preflight_body(
            reviewed_body_name, f"{reviewed_body}\n{injected_command}"
        )

    testflight_body_fixtures = {
        "Install cloud-signing material": "security import reviewed-certificate",
        "Verify signed IPA": "codesign --verify reviewed-app",
    }
    testflight_fixture_hashes = {
        step_name: body_sha256(body)
        for step_name, body in testflight_body_fixtures.items()
    }
    assert is_reviewed_run_body(
        "Install cloud-signing material",
        testflight_body_fixtures["Install cloud-signing material"],
        testflight_fixture_hashes,
    )
    assert not is_reviewed_run_body(
        "Install cloud-signing material",
        testflight_body_fixtures["Install cloud-signing material"]
        + "\npython3 -c 'publish()'",
        testflight_fixture_hashes,
    )
    assert not is_reviewed_run_body(
        "Verify signed IPA",
        testflight_body_fixtures["Verify signed IPA"] + "\nexit 0",
        testflight_fixture_hashes,
    )

    ordered_testflight_fixture = "\n".join(
        f"      - name: {step_name}"
        for step_name in ["Verify signed IPA", "Cleanup"]
    )
    assert exact_step_inventory(
        ordered_testflight_fixture, ["Verify signed IPA", "Cleanup"]
    )
    assert not exact_step_inventory(
        ordered_testflight_fixture.replace(
            "      - name: Cleanup",
            "      - name: Injected\n      - name: Cleanup",
        ),
        ["Verify signed IPA", "Cleanup"],
    )

    literal_run_fixture = (
        "      - name: Signing\n"
        "        run: |\n"
        "          security import reviewed"
    )
    inline_run_fixture = (
        "      - name: Check\n"
        "        run: python3 -I scripts/check_workflow_security.py"
    )
    assert step_run_scalar_style(literal_run_fixture) == "literal"
    assert step_run_scalar_style(inline_run_fixture) == "inline"
    assert step_run_scalar_style(
        literal_run_fixture.replace("        run: |", "        run: >", 1)
    ) == "forbidden"
    assert step_run_scalar_style(
        inline_run_fixture.replace(
            "run: python3 -I scripts/check_workflow_security.py", "run: >", 1
        )
    ) == "forbidden"

    toolchain_fixture = (
        "      - name: Verify pinned Xcode toolchain\n"
        "        shell: bash\n"
        "        run: |\n"
        + "\n".join(f"          {line}" for line in RELEASE_TOOLCHAIN_COMMAND_LINES)
    )
    assert release_toolchain_step_is_exact(toolchain_fixture)
    for command in RELEASE_TOOLCHAIN_COMMAND_LINES[1:]:
        assert not release_toolchain_step_is_exact(
            toolchain_fixture.replace(f"          {command}", f"          # {command}", 1)
        )
    assert not release_toolchain_step_is_exact(
        toolchain_fixture.replace("iOS-26-0", "iOS-26-1", 1)
    )

    release_structure_fixture = (
        "name: fixture\n"
        "on:\n"
        "permissions:\n"
        "concurrency:\n"
        "  group: keyhollow-production-testflight\n"
        "  cancel-in-progress: false\n"
        "jobs:\n"
        "  archive-and-upload:\n"
        "    if: github.event_name == 'workflow_dispatch' && "
        "github.ref == 'refs/heads/main'\n"
        "    runs-on: macos-15\n"
        "    timeout-minutes: 30\n"
        "    environment: production-testflight\n"
        "    env:\n"
        "    steps:"
    )
    assert audit_release_job_structure(
        "fixture", release_structure_fixture, job_name="archive-and-upload"
    ) == []
    structure_mutations = (
        (
            "    environment: production-testflight",
            "    environment: unprotected # environment: production-testflight",
        ),
        (
            "    runs-on: macos-15",
            "    runs-on: self-hosted # runs-on: macos-15",
        ),
        (
            "    env:",
            "    strategy:\n      matrix:\n        lane: [release]\n    env:",
        ),
        (
            "  group: keyhollow-production-testflight",
            "  group: unreviewed # group: keyhollow-production-testflight",
        ),
        (
            "  cancel-in-progress: false",
            "  cancel-in-progress: true # cancel-in-progress: false",
        ),
        (
            "permissions:\nconcurrency:",
            "permissions:\n"
            "defaults:\n"
            "  run:\n"
            "    shell: bash\n"
            "concurrency:",
        ),
        (
            "permissions:\nconcurrency:",
            "permissions:\n"
            "env:\n"
            "  BASH_ENV: injected\n"
            "  PYTHONPATH: injected\n"
            "concurrency:",
        ),
        (
            "    env:",
            "    defaults:\n      run:\n        shell: bash\n    env:",
        ),
    )
    for original, replacement in structure_mutations:
        assert audit_release_job_structure(
            "fixture",
            release_structure_fixture.replace(original, replacement, 1),
            job_name="archive-and-upload",
        )

    trigger_fixture = "on:\n  workflow_dispatch:\n"
    assert direct_child_keys(trigger_fixture, 2) == ["workflow_dispatch"]
    for injected_trigger in (
        '  "schedule":\n',
        "  'pull_request_target':\n",
        '  "schedule": [{cron: "* * * * *"}]\n',
    ):
        assert "__INVALID_CHILD__" in direct_child_keys(
            trigger_fixture + injected_trigger, 2
        )
    jobs_fixture = "jobs:\n  reviewed:\n"
    assert direct_child_keys(jobs_fixture, 2) == ["reviewed"]
    assert "__INVALID_CHILD__" in direct_child_keys(
        jobs_fixture
        + '  "publish": {runs-on: ubuntu-latest, steps: [{run: echo injected}]}\n',
        2,
    )

    inventory_lines: list[str] = []
    for step_name in PREFLIGHT_STEP_NAMES:
        inventory_lines.append(f"      - name: {step_name}")
        if step_name == "Checkout":
            inventory_lines.append(
                "        uses: actions/checkout@"
                "d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0"
            )
            inventory_lines.append("        with:")
            inventory_lines.append("          persist-credentials: false")
        else:
            if step_name in PREFLIGHT_EXPLICIT_BASH_STEPS:
                inventory_lines.append("        shell: bash")
            inventory_lines.append("        run: echo reviewed")
    inventory_fixture = "\n".join(inventory_lines)
    inventory_violations = audit_preflight_step_surface(inventory_fixture)
    assert not any("step inventory" in item for item in inventory_violations)
    assert not any("interpreter drifted" in item for item in inventory_violations)
    assert any(
        "step inventory" in item
        for item in audit_preflight_step_surface(
            inventory_fixture + "\n      - name: Injected\n        run: curl bad"
        )
    )
    assert any(
        "interpreter drifted" in item
        for item in audit_preflight_step_surface(
            inventory_fixture.replace("        shell: bash", "        shell: python", 1)
        )
    )
    assert any(
        "keys drifted" in item
        for item in audit_preflight_step_surface(
            inventory_fixture.replace(
                "        run: echo reviewed",
                "        working-directory: unreviewed\n        run: echo reviewed",
                1,
            )
        )
    )

    signing_unset_fixture = (
        "unset \\\n"
        "  BUILD_CERTIFICATE_BASE64 \\\n"
        "  BUILD_PROVISION_PROFILE_BASE64 \\\n"
        "  THUMBNAIL_PROVISION_PROFILE_BASE64 \\\n"
        "  P12_PASSWORD \\\n"
        "  KEYCHAIN_PASSWORD\n"
        "python3 -I scripts/verify_signing_material.py --certificate-der cert"
    )
    assert signing_secrets_unset_before_validator(signing_unset_fixture)
    assert not signing_secrets_unset_before_validator(
        signing_unset_fixture.replace("  P12_PASSWORD \\\n", "", 1)
    )
    assert not signing_secrets_unset_before_validator(
        signing_unset_fixture.replace(
            "python3 -I scripts/verify_signing_material.py --certificate-der cert",
            "",
        )
    )

    artifact_fixture = (
        "      - name: Upload signed IPA artifact\n"
        "        if: success()\n"
        "        uses: actions/upload-artifact@reviewed\n"
        "        with:\n"
        "          if-no-files-found: error"
    )
    assert testflight_artifact_step_is_fail_closed(artifact_fixture)
    assert not testflight_artifact_step_is_fail_closed(
        artifact_fixture.replace("if-no-files-found: error", "if-no-files-found: warn")
    )
    assert not testflight_artifact_step_is_fail_closed(
        artifact_fixture.replace("        if: success()\n", "")
    )

    strict_teardown_fixture = "\n".join(STRICT_SIGNING_TEARDOWN_REQUIREMENTS)
    assert testflight_signing_teardown_is_fail_closed(strict_teardown_fixture)
    for required in STRICT_SIGNING_TEARDOWN_REQUIREMENTS:
        assert not testflight_signing_teardown_is_fail_closed(
            strict_teardown_fixture.replace(required, "", 1)
        )
    assert not testflight_signing_teardown_is_fail_closed(
        strict_teardown_fixture + "\nsecurity delete-keychain path || true"
    )
    assert not testflight_signing_teardown_is_fail_closed(
        strict_teardown_fixture + "\necho '::warning::ignored failure'"
    )

    final_build_recheck_fixture = (
        "      - name: Upload verified IPA to App Store Connect\n"
        "        run: |\n"
        "          if [[ \"$APP_STORE_CONNECT_API_KEY_ID\" != "
        "\"$EXPECTED_API_KEY_ID\" ]]; then\n"
        "            exit 1\n"
        "          fi\n"
        f"          {TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND}\n"
        "          API_KEY_PATH=\"$API_KEY_DIRECTORY/"
        "AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8\"\n"
        "          printf '%s' \"$APP_STORE_CONNECT_API_KEY_BASE64\" | "
        "base64 --decode > \"$API_KEY_PATH\"\n"
        "          xcrun altool --upload-app"
    )
    assert testflight_final_build_recheck_is_exact(final_build_recheck_fixture)
    assert not testflight_final_build_recheck_is_exact(
        final_build_recheck_fixture.replace(
            f"          {TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND}\n", "", 1
        )
    )
    assert not testflight_final_build_recheck_is_exact(
        final_build_recheck_fixture.replace(
            f"          {TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND}\n",
            f"          {TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND}\n"
            f"          {TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND}\n",
            1,
        )
    )
    assert not testflight_final_build_recheck_is_exact(
        final_build_recheck_fixture.replace(
            f"          {TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND}\n"
            "          API_KEY_PATH=",
            "          API_KEY_PATH=",
            1,
        )
        + f"\n          {TESTFLIGHT_BUILD_NUMBER_CHECK_COMMAND}"
    )

    assert permission_blocks("permissions: {}\n") == [{"__inline__": "{}"}]
    assert permission_blocks("permissions:\n  contents: read\n") == [
        {"contents": "read"}
    ]

    assert preflight_publication_markers("xcodebuild -exportArchive archive") == []
    assert preflight_publication_markers("xcrun altool --upload-app") == [
        "xcrun altool",
        "--upload-app",
    ]

    secret_fixture_lines = [
        'if [[ "$EXPECTED_COMMIT_SHA" != "$GITHUB_SHA" ]]',
        "run: python3 -I scripts/verify_release_source.py",
        "  PRODUCTION_RELEASE_GUARD: ${{ secrets.PRODUCTION_RELEASE_GUARD }}",
        "run: python3 -I scripts/verify_release_environment.py",
    ]
    secret_fixture_lines.extend(
        f"  {secret}: ${{{{ secrets.{secret} }}}}"
        for secret in sorted(PRODUCTION_SECRETS - {"PRODUCTION_RELEASE_GUARD"})
    )
    secret_fixture = "\n".join(secret_fixture_lines)
    assert audit_release_secret_boundary("fixture", secret_fixture) == []
    misplaced_secret_fixture = (
        "  BUILD_CERTIFICATE_BASE64: "
        "${{ secrets.BUILD_CERTIFICATE_BASE64 }}\n"
        + secret_fixture
    )
    assert any(
        "first and sole guard secret" in item
        for item in audit_release_secret_boundary(
            "fixture", misplaced_secret_fixture
        )
    )

    binding_fixture = (
        "  /usr/libexec/PlistBuddy -c \"Add :provisioningProfiles:"
        "com.keyhollow.app string $APP_PROFILE_UUID\" build/ExportOptions.plist\n"
        "  ignored\n"
    )
    assert matching_command_lines(
        binding_fixture, "Add :provisioningProfiles:com.keyhollow"
    ) == [
        "/usr/libexec/PlistBuddy -c \"Add :provisioningProfiles:"
        "com.keyhollow.app string $APP_PROFILE_UUID\" build/ExportOptions.plist"
    ]
    print("Workflow-security checker self-test passed.")
    return 0


def main() -> int:
    args = parse_arguments()
    if args.self_test:
        return self_test()

    self_test()
    violations = audit_repository()
    if violations:
        print("Workflow security violations:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    print(
        "Workflow security passed: actions are SHA-pinned, CI is read-only, "
        "sensitive paths have owners, production delivery is exact-source/main/"
        "environment/branch/signing-gated, the release-signing preflight cannot "
        "publish, and the retired beta path is fail-closed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
