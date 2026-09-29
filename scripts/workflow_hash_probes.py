"""Mutation probes for workflow integrity and reviewed execution boundaries.

Callbacks keep the production hash logic owned by the security checker. This
helper is hash-verified there before loading; it has no release authority.
"""


def check_hash_guards(
    canonical_source_sha256,
    body_sha256,
    audit_privileged_source_payloads,
    audit_release_workflow_payloads,
    privileged_source_hashes,
    release_workflow_hashes,
):
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
        for relative_path in privileged_source_hashes
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
        for workflow_name in release_workflow_hashes
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


def check_execution_guards(
    audit_project_execution_surface, FORBIDDEN_XCODEGEN_EXECUTION_KEYS,
    nonisolated_python_invocations,
):
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
