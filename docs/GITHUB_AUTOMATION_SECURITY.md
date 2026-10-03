# GitHub automation security

The Pages workflow is checked into `.github/workflows/pages.yml` so GitHub's
full-length action SHA policy can cover publishing as well as iOS automation.
The prior GitHub-generated branch publisher referenced mutable action tags.

## Public-site boundary

- Pull requests build the root README/Jekyll site with read-only repository and
  Pages access. They cannot deploy. Required iOS CI still audits the complete
  workflow inventory and exact normalized workflow fingerprints.
- Only a push to main or a manual run on main in `Frankbell84/KeyHollow` can
  deploy. The deployment consumes the successful build's artifact from the
  same run; it does not check out or execute repository code.
- Only deployment receives `pages: write` and `id-token: write`, through the
  separate `github-pages` environment. Pages has no signing secrets, App Store
  access, or connection to `production-testflight`.
- Checkout does not persist credentials. The artifact expires after one day.
  Main deployments are serialized without cancelling an active publication.
- The existing root, default Jekyll theme, domain and HTTPS behavior are
  preserved. CI checks the home, work-status, privacy, terms and support pages.

Action commits were verified against GitHub's official action repositories.
The upload-pages-artifact v4 composite also pins its nested upload-artifact
action. The Jekyll action is the same commit as the previous publisher. Its
vendor-owned implementation references the versioned Docker image
`ghcr.io/actions/jekyll-build-pages:v1.0.13`; the action SHA policy does not
make that transitive image reference immutable. GitHub-hosted runner images
also remain managed by GitHub. Do not describe this as a fully hermetic build.

## Activation and verification

After the candidate passes its Pages build and existing required CI, change
Settings > Pages > Source from **Deploy from a branch** to **GitHub Actions**.
Merge the tested candidate, verify its main deployment and live entry points,
then enable **Require actions to be pinned to a full-length commit SHA** in
Settings > Actions > General. Run the same main Pages workflow once under the
new policy and record the run and settings evidence in the pull request.

Do not relax the action policy to accommodate a newly unpinned action. Review
and pin its implementation, including composite actions, through a tested PR.
Repository settings are live GitHub state; this document alone does not prove
that activation or enforcement has occurred.

This stage changes automation and documentation only. Build 61 remains the
accepted iPhone binary. It does not authorize a new upload or distribution.
