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


def check_generic_execution_guards(audit_generic):
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


def check_environment_guards(audit_environment_verifier_source, ENVIRONMENT_VERIFIER_REQUIREMENTS):
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


def check_rotation_guards(audit_approved_rotation, APPROVED_ROTATION_BINDINGS):
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
