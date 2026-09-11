#!/usr/bin/env python3
"""Fail closed unless the production GitHub environment is release-safe."""

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
REQUIRED_REVIEWER_LOGIN = "Frankbell84"
GITHUB_API_ORIGIN = "https://api.github.com"
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

    if environment.get("can_admins_bypass") is not False:
        errors.append("environment administrator bypass must be disabled")

    deployment_policy = environment.get("deployment_branch_policy")
    if (
        not isinstance(deployment_policy, dict)
        or deployment_policy.get("protected_branches") is not False
        or deployment_policy.get("custom_branch_policies") is not True
    ):
        errors.append("environment must use custom deployment branch policies")

    protection_rules = environment.get("protection_rules")
    required_reviewers_rule: dict[str, Any] | None = None
    if not isinstance(protection_rules, list):
        errors.append("environment protection rules are missing or malformed")
    elif any(
        not isinstance(rule, dict) or not isinstance(rule.get("type"), str)
        for rule in protection_rules
    ):
        errors.append("environment protection rules are malformed")
    else:
        rule_types = [rule["type"] for rule in protection_rules]
        expected_rule_types = ["branch_policy", "required_reviewers"]
        if sorted(rule_types) != sorted(expected_rule_types):
            errors.append(
                "environment protection rules must contain exactly one "
                "branch_policy rule and one required_reviewers rule"
            )
        reviewer_rules = [
            rule for rule in protection_rules if rule["type"] == "required_reviewers"
        ]
        if len(reviewer_rules) == 1:
            required_reviewers_rule = reviewer_rules[0]

    if required_reviewers_rule is not None:
        if required_reviewers_rule.get("prevent_self_review") is not False:
            errors.append("required reviewer must be allowed to approve their own run")
        reviewers = required_reviewers_rule.get("reviewers")
        if not isinstance(reviewers, list) or len(reviewers) != 1:
            errors.append(
                f"required reviewers must contain exactly {REQUIRED_REVIEWER_LOGIN}"
            )
        else:
            reviewer_entry = reviewers[0]
            if not isinstance(reviewer_entry, dict):
                errors.append("required reviewer entry is malformed")
            else:
                if reviewer_entry.get("type") != "User":
                    errors.append("required reviewer must be a GitHub User")
                reviewer = reviewer_entry.get("reviewer")
                if (
                    not isinstance(reviewer, dict)
                    or reviewer.get("login") != REQUIRED_REVIEWER_LOGIN
                    or reviewer.get("type") != "User"
                ):
                    errors.append(
                        f"required reviewer must be exactly {REQUIRED_REVIEWER_LOGIN}"
                    )

    if not isinstance(branch_policies, dict):
        errors.append("branch-policy response is not an object")
        return errors
    policies = branch_policies.get("branch_policies")
    total_count = branch_policies.get("total_count")
    if (
        not isinstance(policies, list)
        or not isinstance(total_count, int)
        or isinstance(total_count, bool)
        or total_count != len(policies)
    ):
        errors.append("branch-policy response is incomplete or malformed")
        return errors

    policy_names: list[str] = []
    for policy in policies:
        if not isinstance(policy, dict) or not isinstance(policy.get("name"), str):
            errors.append("branch-policy entry is malformed")
            continue
        if policy.get("type") != "branch":
            errors.append("deployment policies must be branch policies")
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


def release_api_urls(repository: str) -> tuple[str, str, str]:
    if REPOSITORY_PATTERN.fullmatch(repository) is None:
        raise ValueError("GitHub repository identifier is invalid")
    owner, repository_name = repository.split("/", maxsplit=1)
    if owner in {".", ".."} or repository_name in {".", ".."}:
        raise ValueError("GitHub repository identifier is invalid")
    environment_url = (
        f"{GITHUB_API_ORIGIN}/repos/{repository}/environments/{ENVIRONMENT_NAME}"
    )
    branch_policies_url = (
        f"{environment_url}/deployment-branch-policies?per_page=100"
    )
    trusted_branch_url = (
        f"{GITHUB_API_ORIGIN}/repos/{repository}/branches/{TRUSTED_BRANCH}"
    )
    return environment_url, branch_policies_url, trusted_branch_url


def validate_github_api_url(url: Any, repository: str) -> str:
    if not isinstance(url, str):
        raise ValueError("GitHub API URL must be a string")
    try:
        parsed = urllib.parse.urlsplit(url)
        port = parsed.port
    except ValueError as error:
        raise ValueError("GitHub API URL is invalid") from error

    if (
        parsed.scheme != "https"
        or parsed.hostname != "api.github.com"
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
        or parsed.fragment
    ):
        raise ValueError("GitHub API URL must use the trusted HTTPS origin")

    if url not in release_api_urls(repository):
        raise ValueError("GitHub API URL is not an approved release-policy endpoint")
    return url


class RejectRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        request: urllib.request.Request,
        file_pointer: Any,
        code: int,
        message: str,
        headers: Any,
        new_url: str,
    ) -> None:
        del request, file_pointer, code, message, headers, new_url
        raise ValueError("GitHub API redirects are forbidden")


def fetch_json(url: str, token: str, repository: str) -> Any:
    safe_url = validate_github_api_url(url, repository)
    request = urllib.request.Request(
        safe_url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "KeyHollow-release-environment-verifier",
        },
    )
    opener = urllib.request.build_opener(RejectRedirectHandler())
    with opener.open(request, timeout=30) as response:
        response_url = validate_github_api_url(response.geturl(), repository)
        if response_url != safe_url:
            raise ValueError("GitHub API response URL changed unexpectedly")
        return json.load(response)


def self_test() -> int:
    test_repository = "Frankbell84/KeyHollow"
    approved_urls = release_api_urls(test_repository)
    assert len(approved_urls) == 3
    for approved_url in approved_urls:
        assert validate_github_api_url(approved_url, test_repository) == approved_url

    unsafe_urls: list[Any] = [
        None,
        approved_urls[0].replace("https://", "http://", 1),
        approved_urls[0].replace("api.github.com", "api.github.com.example.test", 1),
        approved_urls[0].replace("api.github.com", "user@api.github.com", 1),
        approved_urls[0].replace("api.github.com", "api.github.com:443", 1),
        f"{approved_urls[0]}#fragment",
        f"{approved_urls[0]}?unexpected=true",
        approved_urls[0].replace(ENVIRONMENT_NAME, "another-environment", 1),
        approved_urls[2].replace(f"/{TRUSTED_BRANCH}", "/release", 1),
        f"{GITHUB_API_ORIGIN}/repos/{test_repository}/actions/secrets",
    ]
    for unsafe_url in unsafe_urls:
        try:
            validate_github_api_url(unsafe_url, test_repository)
        except ValueError:
            pass
        else:
            raise AssertionError(f"unsafe GitHub API URL was accepted: {unsafe_url!r}")

    for unsafe_repository in ("missing-owner", "../KeyHollow", "Frankbell84/.."):
        try:
            release_api_urls(unsafe_repository)
        except ValueError:
            pass
        else:
            raise AssertionError(
                f"unsafe GitHub repository was accepted: {unsafe_repository!r}"
            )

    try:
        fetch_json(unsafe_urls[2], "self-test-token", test_repository)
    except ValueError:
        pass
    else:
        raise AssertionError("fetch_json accepted an untrusted GitHub API origin")

    redirect_handler = RejectRedirectHandler()
    try:
        redirect_handler.redirect_request(
            urllib.request.Request(approved_urls[0]),
            None,
            302,
            "Found",
            {},
            "https://example.test/token-capture",
        )
    except ValueError as error:
        assert "redirects are forbidden" in str(error)
    else:
        raise AssertionError("GitHub API redirect was accepted")

    valid_environment = {
        "name": ENVIRONMENT_NAME,
        "can_admins_bypass": False,
        "protection_rules": [
            {"id": 1, "type": "branch_policy"},
            {
                "id": 2,
                "type": "required_reviewers",
                "prevent_self_review": False,
                "reviewers": [
                    {
                        "type": "User",
                        "reviewer": {
                            "login": REQUIRED_REVIEWER_LOGIN,
                            "id": 1,
                            "type": "User",
                        },
                    }
                ],
            },
        ],
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
    assert (
        policy_errors(
            {
                **valid_environment,
                "protection_rules": list(
                    reversed(valid_environment["protection_rules"])
                ),
            },
            valid_branches,
            valid_trusted_branch,
        )
        == []
    )

    def assert_environment_error(environment: Any, expected: str) -> None:
        errors = policy_errors(environment, valid_branches, valid_trusted_branch)
        assert any(expected in error for error in errors), errors

    assert policy_errors({}, valid_branches, valid_trusted_branch)
    assert_environment_error(
        {
            **valid_environment,
            "deployment_branch_policy": None,
        },
        "custom deployment branch policies",
    )
    assert_environment_error(
        {
            key: value
            for key, value in valid_environment.items()
            if key != "can_admins_bypass"
        },
        "administrator bypass",
    )
    assert_environment_error(
        {**valid_environment, "can_admins_bypass": True},
        "administrator bypass",
    )
    assert_environment_error(
        {**valid_environment, "protection_rules": [{"type": "branch_policy"}]},
        "exactly one branch_policy rule and one required_reviewers rule",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [valid_environment["protection_rules"][1]],
        },
        "exactly one branch_policy rule and one required_reviewers rule",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [
                *valid_environment["protection_rules"],
                {"id": 3, "type": "wait_timer", "wait_timer": 0},
            ],
        },
        "exactly one branch_policy rule and one required_reviewers rule",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [
                valid_environment["protection_rules"][0],
                {
                    **valid_environment["protection_rules"][1],
                    "reviewers": [],
                },
            ],
        },
        f"exactly {REQUIRED_REVIEWER_LOGIN}",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [
                valid_environment["protection_rules"][0],
                {
                    key: value
                    for key, value in valid_environment["protection_rules"][1].items()
                    if key != "prevent_self_review"
                },
            ],
        },
        "allowed to approve their own run",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [
                valid_environment["protection_rules"][0],
                {
                    **valid_environment["protection_rules"][1],
                    "prevent_self_review": True,
                },
            ],
        },
        "allowed to approve their own run",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [
                valid_environment["protection_rules"][0],
                {
                    **valid_environment["protection_rules"][1],
                    "reviewers": [
                        {
                            "type": "User",
                            "reviewer": {
                                "login": "someone-else",
                                "type": "User",
                            },
                        }
                    ],
                },
            ],
        },
        f"exactly {REQUIRED_REVIEWER_LOGIN}",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [
                valid_environment["protection_rules"][0],
                {
                    **valid_environment["protection_rules"][1],
                    "reviewers": [
                        {
                            "type": "Team",
                            "reviewer": {
                                "login": REQUIRED_REVIEWER_LOGIN,
                                "type": "Team",
                            },
                        }
                    ],
                },
            ],
        },
        "must be a GitHub User",
    )
    assert_environment_error(
        {
            **valid_environment,
            "protection_rules": [
                valid_environment["protection_rules"][0],
                {
                    **valid_environment["protection_rules"][1],
                    "reviewers": [
                        *valid_environment["protection_rules"][1]["reviewers"],
                        {
                            "type": "User",
                            "reviewer": {
                                "login": "someone-else",
                                "type": "User",
                            },
                        },
                    ],
                },
            ],
        },
        f"exactly {REQUIRED_REVIEWER_LOGIN}",
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
        {"total_count": True, "branch_policies": valid_branches["branch_policies"]},
        valid_trusted_branch,
    )
    assert policy_errors(
        valid_environment,
        {"total_count": 1, "branch_policies": [{"name": TRUSTED_BRANCH}]},
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
    base_url, branch_url, trusted_branch_url = release_api_urls(repository)
    try:
        environment = fetch_json(base_url, token, repository)
        branches = fetch_json(branch_url, token, repository)
        trusted_branch = fetch_json(trusted_branch_url, token, repository)
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
        f"may deploy, that branch is protected, {REQUIRED_REVIEWER_LOGIN} is the "
        "sole required reviewer with self-review allowed, administrator bypass is "
        "disabled, and the environment-only release guard is present."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
