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
GITHUB_API_ORIGIN = "https://api.github.com"


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


def release_runs_api_url(repository: str, workflow: str, commit: str) -> str:
    if REPOSITORY_PATTERN.fullmatch(repository) is None:
        raise ValueError("GitHub repository identifier is invalid")
    owner, repository_name = repository.split("/", maxsplit=1)
    if owner in {".", ".."} or repository_name in {".", ".."}:
        raise ValueError("GitHub repository identifier is invalid")
    if (
        re.fullmatch(r"[A-Za-z0-9_.-]+", workflow) is None
        or workflow in {".", ".."}
    ):
        raise ValueError("Workflow identifier is invalid")
    if SHA_PATTERN.fullmatch(commit) is None:
        raise ValueError("Release commit must be a full lowercase SHA")

    query = urllib.parse.urlencode(
        {"head_sha": commit, "status": "completed", "per_page": 100}
    )
    encoded_workflow = urllib.parse.quote(workflow, safe="")
    return (
        f"{GITHUB_API_ORIGIN}/repos/{repository}/actions/workflows/"
        f"{encoded_workflow}/runs?{query}"
    )


def validate_github_api_url(
    url: Any, repository: str, workflow: str, commit: str
) -> str:
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

    expected_url = release_runs_api_url(repository, workflow, commit)
    if url != expected_url:
        raise ValueError("GitHub API URL is not the approved exact-source endpoint")
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


def fetch_json(
    url: str,
    token: str,
    repository: str,
    workflow: str,
    commit: str,
    *,
    opener: Any | None = None,
) -> Any:
    safe_url = validate_github_api_url(url, repository, workflow, commit)
    request = urllib.request.Request(
        safe_url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "KeyHollow-release-source-verifier",
        },
        method="GET",
    )
    safe_opener = opener or urllib.request.build_opener(RejectRedirectHandler())
    with safe_opener.open(request, timeout=30) as response:
        response_url = validate_github_api_url(
            response.geturl(), repository, workflow, commit
        )
        if response_url != safe_url:
            raise ValueError("GitHub API response URL changed unexpectedly")
        return json.load(response)


def self_test() -> int:
    commit = "a" * 40
    repository = "Frankbell84/KeyHollow"
    workflow = "ios-build.yml"
    approved_url = release_runs_api_url(repository, workflow, commit)
    assert (
        validate_github_api_url(approved_url, repository, workflow, commit)
        == approved_url
    )

    unsafe_urls: list[Any] = [
        None,
        approved_url.replace("https://", "http://", 1),
        approved_url.replace("api.github.com", "api.github.com.example.test", 1),
        approved_url.replace("api.github.com", "user@api.github.com", 1),
        approved_url.replace("api.github.com", "api.github.com:443", 1),
        f"{approved_url}#fragment",
        approved_url.replace("status=completed", "status=success", 1),
        approved_url.replace("ios-build.yml", "testflight.yml", 1),
        approved_url.replace(repository, "another-owner/KeyHollow", 1),
        f"{GITHUB_API_ORIGIN}/repos/{repository}/actions/secrets",
    ]
    for unsafe_url in unsafe_urls:
        try:
            validate_github_api_url(unsafe_url, repository, workflow, commit)
        except ValueError:
            pass
        else:
            raise AssertionError(
                f"unsafe GitHub API URL was accepted: {unsafe_url!r}"
            )

    for unsafe_repository in ("missing-owner", "../KeyHollow", "Frankbell84/.."):
        try:
            release_runs_api_url(unsafe_repository, workflow, commit)
        except ValueError:
            pass
        else:
            raise AssertionError(
                f"unsafe GitHub repository was accepted: {unsafe_repository!r}"
            )

    for unsafe_workflow in ("../ios-build.yml", ".", ".."):
        try:
            release_runs_api_url(repository, unsafe_workflow, commit)
        except ValueError:
            pass
        else:
            raise AssertionError(
                f"unsafe GitHub workflow was accepted: {unsafe_workflow!r}"
            )

    class FakeResponse:
        def __init__(self, response_url: Any, payload: Any) -> None:
            self.response_url = response_url
            self.payload = payload

        def __enter__(self) -> FakeResponse:
            return self

        def __exit__(self, *args: Any) -> None:
            del args

        def geturl(self) -> Any:
            return self.response_url

        def read(self, *args: Any) -> bytes:
            del args
            return json.dumps(self.payload).encode("utf-8")

    class FakeOpener:
        def __init__(self, response: FakeResponse) -> None:
            self.response = response
            self.requests: list[urllib.request.Request] = []

        def open(
            self, request: urllib.request.Request, timeout: int
        ) -> FakeResponse:
            assert timeout == 30
            self.requests.append(request)
            return self.response

    fake_payload = {"workflow_runs": []}
    rejecting_opener = FakeOpener(FakeResponse(approved_url, fake_payload))
    try:
        fetch_json(
            unsafe_urls[2],
            "self-test-token",
            repository,
            workflow,
            commit,
            opener=rejecting_opener,
        )
    except ValueError:
        pass
    else:
        raise AssertionError("fetch_json accepted an untrusted GitHub API origin")
    assert rejecting_opener.requests == []

    fake_opener = FakeOpener(FakeResponse(approved_url, fake_payload))
    assert (
        fetch_json(
            approved_url,
            "self-test-token",
            repository,
            workflow,
            commit,
            opener=fake_opener,
        )
        == fake_payload
    )
    assert len(fake_opener.requests) == 1
    assert fake_opener.requests[0].full_url == approved_url
    assert fake_opener.requests[0].get_method() == "GET"
    assert fake_opener.requests[0].get_header("Authorization") == (
        "Bearer self-test-token"
    )

    for unexpected_response_url in (
        approved_url.replace("api.github.com", "example.test", 1),
        approved_url.replace("status=completed", "status=success", 1),
    ):
        try:
            fetch_json(
                approved_url,
                "self-test-token",
                repository,
                workflow,
                commit,
                opener=FakeOpener(
                    FakeResponse(unexpected_response_url, fake_payload)
                ),
            )
        except ValueError:
            pass
        else:
            raise AssertionError(
                "unexpected GitHub API response URL was accepted: "
                f"{unexpected_response_url!r}"
            )

    redirect_handler = RejectRedirectHandler()
    try:
        redirect_handler.redirect_request(
            urllib.request.Request(approved_url),
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
    repository_parts = args.repository.split("/", maxsplit=1)
    if (
        REPOSITORY_PATTERN.fullmatch(args.repository) is None
        or any(part in {".", ".."} for part in repository_parts)
    ):
        print("GitHub repository identifier is invalid.", file=sys.stderr)
        return 1
    if (
        not re.fullmatch(r"[A-Za-z0-9_.-]+", args.workflow)
        or args.workflow in {".", ".."}
    ):
        print("Workflow identifier is invalid.", file=sys.stderr)
        return 1

    try:
        url = release_runs_api_url(args.repository, args.workflow, args.commit)
        payload = fetch_json(
            url, token, args.repository, args.workflow, args.commit
        )
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
