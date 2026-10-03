"""Pages-only permission and deployment boundaries, loaded after hash verification.

The existing workflow checker owns parsing, action pins and complete workflow
fingerprints. This module describes the separate public-site delivery surface;
it never changes the iOS release policy or loads credentials.
"""


DEPLOY_CONDITION = (
    "github.repository == 'Frankbell84/KeyHollow' && "
    "github.ref == 'refs/heads/main' && "
    "(github.event_name == 'push' || github.event_name == 'workflow_dispatch')"
)


def audit_pages(text, audit_generic, named_job_block, entries, permission_blocks):
    violations = audit_generic("pages.yml", text)

    def expect(condition, message):
        if not condition:
            violations.append(f"pages.yml: {message}")

    expect(permission_blocks(text) == [
        {"__inline__": "{}"},
        {"contents": "read", "pages": "read"},
        {"pages": "write", "id-token": "write"},
    ], "only the deployment job may write Pages or request an OIDC token")
    expect(entries(text, spaces=2)[-2:] == [
        ("build-pages", ""), ("deploy-pages", ""),
    ], "Pages must retain the separate build and deployment jobs")
    build = named_job_block(text, "build-pages") or ""
    deploy = named_job_block(text, "deploy-pages") or ""
    expect(entries(build, spaces=4) == [
        ("runs-on", "ubuntu-24.04"), ("timeout-minutes", "10"),
        ("permissions", ""), ("steps", ""),
    ], "the build must remain unprivileged and separate from deployment")
    expect(entries(deploy, spaces=4) == [
        ("if", DEPLOY_CONDITION), ("needs", "build-pages"),
        ("runs-on", "ubuntu-24.04"), ("timeout-minutes", "10"),
        ("permissions", ""), ("environment", ""), ("steps", ""),
    ], "deployment requires the same run's successful build and a trusted main event")
    expect("      name: github-pages\n" in deploy + "\n",
           "deployment must use the github-pages environment")
    expect("actions/checkout@" not in deploy and "run:" not in deploy,
           "deployment must not check out or execute repository code")
    expect("secrets" not in text and "production-testflight" not in text,
           "Pages must not consume release credentials or the release environment")
    return violations


def check_pages_guards(text, audit_generic, named_job_block, entries, permission_blocks):
    """Exercise policy failures independently of the whole-workflow fingerprint."""
    def audit(candidate):
        return audit_pages(candidate, audit_generic, named_job_block, entries,
                           permission_blocks)

    assert audit(text) == []
    mutations = (
        ("permissions: {}", "permissions:\n  contents: write"),
        ("      pages: read", "      pages: write"),
        ("      pages: write\n      id-token: write", "      pages: write"),
        (DEPLOY_CONDITION, "always()"),
        ("github.ref == 'refs/heads/main'", "github.ref != 'refs/heads/main'"),
        ("    needs: build-pages\n", ""),
        ("      name: github-pages", "      name: production-testflight"),
        ("        id: deployment", "        run: echo injected\n        id: deployment"),
        ("          persist-credentials: false", "          persist-credentials: true"),
        ("actions/jekyll-build-pages@44a6e6beabd48582f863aeeb6cb2151cc1716697",
         "actions/jekyll-build-pages@v1"),
        ("  pull_request:", "  pull_request_target:"),
        ("    needs: build-pages", "    needs: build-pages\n    if: always()"),
        ("    steps:\n", "    env:\n      KEY: ${{ secrets.RELEASE_KEY }}\n    steps:\n"),
    )
    for before, after in mutations:
        assert before in text
        assert audit(text.replace(before, after, 1)), before
