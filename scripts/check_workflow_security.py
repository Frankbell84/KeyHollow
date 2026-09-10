#!/usr/bin/env python3
"""Fail closed when GitHub Actions release controls drift from policy.

This checker deliberately uses only the Python standard library.  It is not a
general YAML linter; it enforces the small, security-sensitive workflow surface
that KeyHollow intentionally supports.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIRECTORY = ROOT / ".github" / "workflows"
EXPECTED_WORKFLOWS = {
    "ios-build.yml",
    "testflight-beta.yml",
    "testflight.yml",
}
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
ACTION_REFERENCE = re.compile(
    r"^\s*(?:-\s*)?uses:\s*([^\s#]+)(?:\s+#.*)?$", re.MULTILINE
)
SECRET_REFERENCE = re.compile(r"secrets\.([A-Z0-9_]+)")

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
    pattern = re.compile(rf"^ {{{spaces}}}([A-Za-z0-9_-]+):(?:\s|$)")
    for line in section.splitlines()[1:]:
        match = pattern.match(line)
        if match:
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


def contains_line(text: str, pattern: str) -> bool:
    return re.search(pattern, text, re.MULTILINE) is not None


def require(violations: list[str], condition: bool, message: str) -> None:
    if not condition:
        violations.append(message)


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

    for body in run_script_bodies(text):
        require(
            violations,
            "${{ inputs." not in body and "${{ github.event." not in body,
            f"{name}: untrusted expression is interpolated directly into a run script",
        )

    for line in text.splitlines():
        if "${{ secrets." not in line:
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
        "python3 scripts/check_workflow_security.py",
        "python3 scripts/check_release_hygiene.py",
        "python3 scripts/check_architecture_boundaries.py",
        "node scripts/verify_testflight_build_number.mjs --self-test",
        "python3 scripts/verify_release_source.py --self-test",
        "python3 scripts/verify_release_environment.py --self-test",
        "python3 scripts/check_privacy_manifest.py",
        "bash scripts/install_xcodegen.sh",
    ):
        require(
            violations,
            command in text,
            f"{name}: required validation command is missing: {command}",
        )
    return violations


def audit_testflight(text: str, release_source: str) -> list[str]:
    name = "testflight.yml"
    violations = audit_generic(name, text)
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
            "always()",
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
        text.count("runs-on: macos-26") == 1,
        f"{name}: delivery must use the reviewed macOS runner image",
    )
    require(
        violations,
        "DEVELOPER_DIR: /Applications/Xcode_26.0.1.app/Contents/Developer" in text
        and "test \"$(xcodebuild -version | sed -n '1p')\" = 'Xcode 26.0.1'"
        in text,
        f"{name}: delivery must select and verify the reviewed Xcode toolchain",
    )
    for required in (
        "EXPECTED_COMMIT_SHA: ${{ inputs.expected_commit_sha }}",
        "[[ ! \"$EXPECTED_COMMIT_SHA\" =~ ^[0-9a-f]{40}$ ]]",
        "[[ \"$EXPECTED_COMMIT_SHA\" != \"$GITHUB_SHA\" ]]",
        "[[ \"$(git rev-parse HEAD)\" != \"$GITHUB_SHA\" ]]",
        "python3 scripts/check_workflow_security.py",
        "python3 scripts/verify_release_source.py",
        "python3 scripts/verify_release_environment.py",
        "python3 scripts/check_release_hygiene.py",
        "python3 scripts/check_architecture_boundaries.py",
        "node scripts/verify_testflight_build_number.mjs --self-test",
        "python3 scripts/check_privacy_manifest.py",
        "bash scripts/install_xcodegen.sh",
    ):
        require(
            violations,
            required in text,
            f"{name}: required release control is missing: {required}",
        )

    referenced_secrets = set(SECRET_REFERENCE.findall(text))
    require(
        violations,
        referenced_secrets == PRODUCTION_SECRETS,
        f"{name}: production secret set drifted: {sorted(referenced_secrets)}",
    )
    guard_reference = "${{ secrets.PRODUCTION_RELEASE_GUARD }}"
    first_secret_reference = text.find("secrets.")
    guard_reference_index = text.find(guard_reference)
    guard_secret_name_index = text.find("secrets.PRODUCTION_RELEASE_GUARD")
    environment_check_index = text.find(
        "python3 scripts/verify_release_environment.py"
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
        environment_check_index > guard_reference_index
        and all(
            match.start() == guard_secret_name_index
            or match.start() > environment_check_index
            for match in SECRET_REFERENCE.finditer(text)
        ),
        f"{name}: no signing/API secret may be referenced before environment verification",
    )
    require(
        violations,
        "${{ inputs.build_number }}" not in "\n".join(run_script_bodies(text)),
        f"{name}: build-number input must reach scripts through env, not interpolation",
    )
    require(
        violations,
        "REQUESTED_BUILD_NUMBER: ${{ inputs.build_number }}" in text
        and 'node scripts/verify_testflight_build_number.mjs "$REQUESTED_BUILD_NUMBER"'
        in text,
        f"{name}: build-number guard must consume its input through the environment",
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
        '"head_sha": args.commit',
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
    for required in (
        'ENVIRONMENT_NAME = "production-testflight"',
        'TRUSTED_BRANCH = "main"',
        '"custom_branch_policies": True',
        '"protected_branches": False',
        'policy_names != [TRUSTED_BRANCH]',
        "PRODUCTION_RELEASE_GUARD",
        "deployment-branch-policies?per_page=100",
        'trusted_branch.get("protected") is not True',
    ):
        require(
            violations,
            required in environment_source,
            f"verify_release_environment.py: required policy is missing: {required}",
        )
    return violations


def audit_retired_beta(text: str) -> list[str]:
    name = "testflight-beta.yml"
    violations = audit_generic(name, text)
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
    violations: list[str] = []
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
    release_path = ROOT / "scripts" / "verify_release_source.py"
    release_source = (
        release_path.read_text(encoding="utf-8") if release_path.is_file() else ""
    )
    hygiene_path = ROOT / "scripts" / "check_release_hygiene.py"
    hygiene_source = (
        hygiene_path.read_text(encoding="utf-8") if hygiene_path.is_file() else ""
    )
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
    pinned = "uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"
    assert not any("not pinned" in item for item in audit_generic("fixture", pinned))

    unpinned = "uses: actions/checkout@v6"
    assert any("not pinned" in item for item in audit_generic("fixture", unpinned))

    injected = "steps:\n  - run: echo '${{ inputs.value }}'\n"
    assert any(
        "interpolated directly" in item for item in audit_generic("fixture", injected)
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

    assert permission_blocks("permissions: {}\n") == [{"__inline__": "{}"}]
    assert permission_blocks("permissions:\n  contents: read\n") == [
        {"contents": "read"}
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
        "environment/branch-gated, and the retired beta path is fail-closed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
