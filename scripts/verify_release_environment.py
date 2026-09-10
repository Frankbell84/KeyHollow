#!/usr/bin/env python3
"""Fail closed unless the production GitHub environment is branch-restricted."""

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


ENVIRONMENT_NAME = "production-testflight"
TRUSTED_BRANCH = "main"
REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--environment", default=ENVIRONMENT_NAME)
    return parser.parse_args()


def policy_errors(
    environment: Any, branch_policies: Any, trusted_branch: Any
) -> list[str]:
    errors: list[str] = []
    if not isinstance(environment, dict):
        return ["environment response is not an object"]
    if environment.get("name") != ENVIRONMENT_NAME:
        errors.append(f"environment name must be {ENVIRONMENT_NAME}")

    deployment_policy = environment.get("deployment_branch_policy")
    if deployment_policy != {
        "protected_branches": False,
        "custom_branch_policies": True,
    }:
        errors.append("environment must use custom deployment branch policies")

    protection_rules = environment.get("protection_rules")
    if not isinstance(protection_rules, list) or not any(
        isinstance(rule, dict) and rule.get("type") == "branch_policy"
        for rule in protection_rules
    ):
        errors.append("environment is missing its branch-policy protection rule")

    if not isinstance(branch_policies, dict):
        errors.append("branch-policy response is not an object")
        return errors
    policies = branch_policies.get("branch_policies")
    total_count = branch_policies.get("total_count")
    if not isinstance(policies, list) or total_count != len(policies):
        errors.append("branch-policy response is incomplete or malformed")
        return errors

    policy_names: list[str] = []
    for policy in policies:
        if not isinstance(policy, dict) or not isinstance(policy.get("name"), str):
            errors.append("branch-policy entry is malformed")
            continue
        policy_type = policy.get("type")
        if policy_type is not None and policy_type != "branch":
            errors.append("tag deployment policies are forbidden")
        policy_names.append(policy["name"])
    if policy_names != [TRUSTED_BRANCH]:
        errors.append(f"only the exact {TRUSTED_BRANCH} branch may deploy")

    if not isinstance(trusted_branch, dict):
        errors.append("trusted-branch response is not an object")
    elif (
        trusted_branch.get("name") != TRUSTED_BRANCH
        or trusted_branch.get("protected") is not True
    ):
        errors.append(f"{TRUSTED_BRANCH} must have GitHub branch protection")
    return errors


def fetch_json(url: str, token: str) -> Any:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "KeyHollow-release-environment-verifier",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def self_test() -> int:
    valid_environment = {
        "name": ENVIRONMENT_NAME,
        "protection_rules": [{"id": 1, "type": "branch_policy"}],
        "deployment_branch_policy": {
            "protected_branches": False,
            "custom_branch_policies": True,
        },
    }
    valid_branches = {
        "total_count": 1,
        "branch_policies": [{"id": 1, "name": TRUSTED_BRANCH, "type": "branch"}],
    }
    valid_trusted_branch = {"name": TRUSTED_BRANCH, "protected": True}
    assert policy_errors(valid_environment, valid_branches, valid_trusted_branch) == []
    assert policy_errors({}, valid_branches, valid_trusted_branch)
    assert policy_errors(
        {
            **valid_environment,
            "deployment_branch_policy": None,
            "protection_rules": [],
        },
        valid_branches,
        valid_trusted_branch,
    )
    assert policy_errors(
        valid_environment,
        {"total_count": 2, "branch_policies": valid_branches["branch_policies"]},
        valid_trusted_branch,
    )
    assert policy_errors(
        valid_environment,
        {
            "total_count": 2,
            "branch_policies": [
                {"name": TRUSTED_BRANCH, "type": "branch"},
                {"name": "release/*", "type": "branch"},
            ],
        },
        valid_trusted_branch,
    )
    assert policy_errors(
        valid_environment,
        {"total_count": 1, "branch_policies": [{"name": "*", "type": "tag"}]},
        valid_trusted_branch,
    )
    assert policy_errors(
        valid_environment,
        valid_branches,
        {"name": TRUSTED_BRANCH, "protected": False},
    )
    print("Release-environment verifier self-test passed.")
    return 0


def main() -> int:
    args = parse_arguments()
    if args.self_test:
        return self_test()

    token = os.environ.get("GITHUB_TOKEN")
    guard = os.environ.get("PRODUCTION_RELEASE_GUARD")
    if not args.repository or not token or not guard:
        print(
            "GITHUB_REPOSITORY, GITHUB_TOKEN, and the environment-only "
            "PRODUCTION_RELEASE_GUARD secret are required.",
            file=sys.stderr,
        )
        return 1
    if REPOSITORY_PATTERN.fullmatch(args.repository) is None:
        print("GitHub repository identifier is invalid.", file=sys.stderr)
        return 1
    if args.environment != ENVIRONMENT_NAME:
        print(f"Release environment must be {ENVIRONMENT_NAME}.", file=sys.stderr)
        return 1

    repository = args.repository
    environment_name = urllib.parse.quote(args.environment, safe="")
    base_url = (
        f"https://api.github.com/repos/{repository}/environments/{environment_name}"
    )
    branch_url = f"{base_url}/deployment-branch-policies?per_page=100"
    trusted_branch_url = (
        f"https://api.github.com/repos/{repository}/branches/{TRUSTED_BRANCH}"
    )
    try:
        environment = fetch_json(base_url, token)
        branches = fetch_json(branch_url, token)
        trusted_branch = fetch_json(trusted_branch_url, token)
    except (OSError, ValueError, urllib.error.HTTPError) as error:
        print(f"Could not verify production environment policy: {error}", file=sys.stderr)
        return 1

    errors = policy_errors(environment, branches, trusted_branch)
    if errors:
        print("Production environment policy is not release-safe:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        f"Verified {ENVIRONMENT_NAME}: only the exact {TRUSTED_BRANCH} branch "
        "may deploy, that branch is protected, and the environment-only release "
        "guard is present."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
