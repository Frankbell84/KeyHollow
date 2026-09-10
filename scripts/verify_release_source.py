#!/usr/bin/env python3
"""Fail closed unless the exact release commit has a successful full CI run."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
TRUSTED_EVENT = "push"
TRUSTED_BRANCH = "main"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--workflow", default="ios-build.yml")
    return parser.parse_args()


def successful_exact_run(payload: Any, commit: str) -> int | None:
    if not isinstance(payload, dict):
        return None
    runs = payload.get("workflow_runs")
    if not isinstance(runs, list):
        return None
    for run in runs:
        if not isinstance(run, dict):
            continue
        if (
            run.get("head_sha") == commit
            and run.get("status") == "completed"
            and run.get("conclusion") == "success"
            and run.get("event") == TRUSTED_EVENT
            and run.get("head_branch") == TRUSTED_BRANCH
            and isinstance(run.get("id"), int)
        ):
            return run["id"]
    return None


def self_test() -> int:
    commit = "a" * 40
    valid_run = {
        "id": 42,
        "head_sha": commit,
        "status": "completed",
        "conclusion": "success",
        "event": "push",
        "head_branch": "main",
    }
    assert successful_exact_run({"workflow_runs": [valid_run]}, commit) == 42
    assert successful_exact_run({"workflow_runs": [valid_run]}, "b" * 40) is None
    assert successful_exact_run(
        {"workflow_runs": [{**valid_run, "conclusion": "failure"}]}, commit
    ) is None
    assert successful_exact_run(
        {"workflow_runs": [{**valid_run, "event": "workflow_dispatch"}]}, commit
    ) is None
    assert successful_exact_run(
        {"workflow_runs": [{**valid_run, "event": "pull_request"}]}, commit
    ) is None
    assert successful_exact_run(
        {"workflow_runs": [{**valid_run, "head_branch": "feature/untrusted"}]},
        commit,
    ) is None
    assert successful_exact_run({"workflow_runs": "invalid"}, commit) is None
    print("Release-source verifier self-test passed.")
    return 0


def main() -> int:
    args = parse_arguments()
    if args.self_test:
        return self_test()

    token = os.environ.get("GITHUB_TOKEN")
    if not args.repository or not args.commit or not token:
        print(
            "GITHUB_REPOSITORY, GITHUB_SHA, and GITHUB_TOKEN are required.",
            file=sys.stderr,
        )
        return 1
    if SHA_PATTERN.fullmatch(args.commit) is None:
        print("Release commit must be a full lowercase SHA.", file=sys.stderr)
        return 1
    if REPOSITORY_PATTERN.fullmatch(args.repository) is None:
        print("GitHub repository identifier is invalid.", file=sys.stderr)
        return 1
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.workflow):
        print("Workflow identifier is invalid.", file=sys.stderr)
        return 1

    query = urllib.parse.urlencode(
        {"head_sha": args.commit, "status": "completed", "per_page": 100}
    )
    workflow = urllib.parse.quote(args.workflow, safe="")
    url = (
        f"https://api.github.com/repos/{args.repository}/actions/workflows/"
        f"{workflow}/runs?{query}"
    )
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "KeyHollow-release-source-verifier",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except (OSError, ValueError, urllib.error.HTTPError) as error:
        print(f"Could not verify exact-source CI evidence: {error}", file=sys.stderr)
        return 1

    run_id = successful_exact_run(payload, args.commit)
    if run_id is None:
        print(
            "No successful completed KeyHollow iOS Build main-branch push run "
            f"exists for the exact release commit {args.commit}.",
            file=sys.stderr,
        )
        return 1

    print(f"Verified successful exact-source CI run {run_id} for {args.commit}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
