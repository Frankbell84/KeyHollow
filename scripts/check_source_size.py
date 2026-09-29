#!/usr/bin/env python3
"""Keep first-party source files bounded; recorded legacy debt may only shrink."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "scripts/source_size_limits.json"
DEFAULT_LIMIT = 500
SOURCE_ROOTS = (
    "KeyHollow", "KeyHollowTests", "KeyHollowLaunchTests",
    "KeyHollowVaultThumbnailExtension", "scripts",
)
EXTENSIONS = {".swift", ".py", ".js", ".mjs", ".sh", ".ps1"}


def source_paths(root: Path) -> list[Path]:
    return sorted(
        path
        for name in SOURCE_ROOTS
        for path in (root / name).rglob("*")
        if path.is_file() and path.suffix in EXTENSIONS
        and not path.relative_to(root).as_posix().startswith("KeyHollow/ThirdParty/Argon2id/")
    )


def validate(sizes: dict[str, int], policy: dict) -> list[str]:
    errors: list[str] = []
    if (
        not isinstance(policy, dict)
        or set(policy) != {"version", "legacy", "exceptions"}
        or type(policy.get("version")) is not int
        or policy["version"] != 1
    ):
        return ["source-size policy has an unsupported schema"]
    legacy, exceptions = policy["legacy"], policy["exceptions"]
    if not isinstance(legacy, dict) or not isinstance(exceptions, dict):
        return ["source-size policy entries must be per-file mappings"]
    if legacy.keys() & exceptions.keys():
        errors.append("a source cannot be both legacy debt and an exception")
    for kind, entries in (("legacy", legacy), ("exceptions", exceptions)):
        for path, entry in entries.items():
            if path not in sizes:
                errors.append(f"{path}: remove stale {kind} entry")
                continue
            if not isinstance(entry, dict) or set(entry) != {"maximum", "reason"}:
                errors.append(f"{path}: require a bounded maximum and written reason")
                continue
            limit, reason = entry["maximum"], entry["reason"]
            if (
                type(limit) is not int or limit <= DEFAULT_LIMIT
                or not isinstance(reason, str) or not reason.strip()
            ):
                errors.append(f"{path}: invalid source-size allowance")
                continue
            if sizes[path] > limit:
                errors.append(f"{path}: {sizes[path]} lines exceed recorded ceiling {limit}; split responsibilities")
            elif sizes[path] <= DEFAULT_LIMIT:
                errors.append(f"{path}: remove allowance now that the source fits {DEFAULT_LIMIT} lines")
            elif kind == "legacy" and sizes[path] < limit:
                errors.append(f"{path}: lower legacy ceiling from {limit} to {sizes[path]}")
    for path, size in sizes.items():
        if path not in legacy and path not in exceptions and size > DEFAULT_LIMIT:
            errors.append(f"{path}: {size} lines exceed {DEFAULT_LIMIT}; split by responsibility or review a justified exception")
    return errors


def self_test() -> None:
    base = {"version": 1, "legacy": {}, "exceptions": {}}
    assert not validate({"small.swift": 500}, base)
    assert validate({"new.swift": 501}, base)
    debt = {
        **base,
        "legacy": {"old.swift": {"maximum": 700, "reason": "Recorded debt"}},
    }
    assert not validate({"old.swift": 700}, debt)
    assert validate({"old.swift": 701}, debt)
    assert validate({"old.swift": 650}, debt)  # Ratchet must be updated downward.
    assert validate({"old.swift": 500}, debt)  # Allowance must be removed.
    assert validate({}, debt)
    exception = {
        **base,
        "exceptions": {
            "special.swift": {
                "maximum": 520, "reason": "Reviewed cohesive responsibility",
            },
        },
    }
    assert not validate({"special.swift": 510}, exception)
    assert validate({"special.swift": 521}, exception)
    exception["exceptions"]["special.swift"]["reason"] = ""
    assert validate({"special.swift": 510}, exception)
    assert validate({}, {"version": 2, "legacy": {}, "exceptions": {}})


def main() -> int:
    self_test()
    try:
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        sizes = {
            p.relative_to(ROOT).as_posix(): len(p.read_text(encoding="utf-8").splitlines())
            for p in source_paths(ROOT)
        }
        errors = validate(sizes, policy)
    except (OSError, UnicodeError, ValueError, TypeError) as error:
        errors = [f"could not validate source-size policy: {error}"]
    if errors:
        print("Source-size violations:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Source-size self-tests and limits passed: new files <= 500 lines; legacy debt cannot grow.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
