# KeyHollow Repository Working Agreement

These rules apply to every person or automation working in this repository.
They exist to keep KeyHollow recoverable across computers and to protect the
stable privacy core while the product grows.

## Canonical history and synchronization

- GitHub is the canonical source of truth for shared KeyHollow code and history.
- Before changing code, confirm the intended repository, remote, current branch,
  upstream branch, and working-tree status.
- Refresh remote references and synchronize safely before beginning work. Never
  discard, overwrite, or hide uncommitted user work in order to update a branch.
- If local work conflicts with the remote or cannot be synchronized safely,
  stop and report the conflict and every unpushed local change.

## Recoverable delivery

- Keep each stage focused and reviewable on its own branch.
- After a stage has a working build and passes the appropriate tests, create a
  clear commit and push it through the normal branch and pull-request workflow.
- Report the branch, verification performed, and any remaining local or remote
  work. Do not leave completed work only on one machine.
- Never force-push, rewrite shared history, or silently discard, replace, or
  diverge from another contributor's changes.

## Core protection and modular additions

- Preserve a clean, compartmentalized core. Security, storage, session, photo,
  transfer, and UI responsibilities should communicate through narrow,
  explicit, testable interfaces.
- Treat the behaviors in `docs/RELEASE_BEHAVIOR_BASELINE.md` as regression
  requirements unless an intentional product change is separately approved.
- Add-ons and future features must be isolated from the core behind narrow
  interfaces. They must not bypass core security rules, tightly couple unrelated
  modules, or make the local vault flow dependent on an optional feature.
- Prefer dependency injection and temporary test storage over production-mode
  flags or duplicated implementations when a test seam is required.
- Keep every stage buildable. Run the relevant unit, UI, integration, and
  security checks before sharing it, in proportion to the risk of the change.
- Do not begin the next architectural stage while the current stage is failing
  or its behavior is not documented and recoverable.

## Maintainable source and bounded growth

- Follow the responsibility/module plan before adding behavior. Keep one clear
  owner, narrow interfaces and private state; moving code must not weaken lock,
  cancellation, cleanup or compatibility guarantees.
- First-party source files have a 500-line default review limit, including
  tests and tooling. The architecture gate enforces it through
  `scripts/check_source_size.py`. Do not compress formatting, remove useful
  comments or scatter one responsibility merely to satisfy a number.
- Existing oversized files are recorded cleanup debt in
  `scripts/source_size_limits.json`. They may not grow; reduce their recorded
  ceiling when extracting responsibilities. Never add a new file to the legacy
  list or raise a legacy ceiling to make CI pass.
- If a cohesive responsibility genuinely cannot fit, document the alternatives,
  why splitting would be worse, the exact per-file ceiling and tests, and obtain
  explicit review of that exception. Use only the policy's bounded `exceptions`
  entry, not a global limit increase. See `docs/GALLERY_REFACTOR.md`.
- Refactors preserve behavior and stay separate from features. Move architecture
  assertions and their negative probes with the owner; do not delete a security
  check because it referred to the old file. Inspect the diff for unrelated churn.
