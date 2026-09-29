# Gallery responsibility split and growth controls

2026-09-29: the user prioritized splitting the gallery and preventing excessive
file growth before further features. The modular plan remains authoritative;
file length is a review guard, not a substitute for cohesive responsibilities.
The backup-date implementation is retained separately in draft PR #100 and is
not included in this refactor. PR #99 contains the release-scope documentation.

## First extraction

Starting source: accepted Build 59 main
`030172bb8750ccadb19b2cee6d922812d6278295`.

| Owner | Responsibility | Boundary preserved |
| --- | --- | --- |
| `Photos/VaultGalleryContentSnapshot.swift` | Typed photo/file routing, immutable catalog ordering and filtered media snapshots | Receives records and returns presentation values; no session or storage mutation capability. |
| `Photos/VaultGeneralFileThumbnailPipeline.swift` | Shared serialized cold-thumbnail lane and cache-hit handling | Same actor, permit, queued cancellation, original loading and checked plaintext lifetime; no additional lane or session owner. |
| `Photos/VaultMediaImagePage.swift` | Observable image surface, placeholder, delayed loading and retry presentation | Uses the existing image coordinator and release callbacks; no protected store or key access. |
| `Photos/VaultGalleryView.swift` | Current screen composition and remaining operation coordination | Keeps existing private state, task ownership, foreground/lock handling and image/video coordinators. |

The first three bodies are moved without behavior changes. Only the image-page
type changes from file-private to app-internal visibility so the composition
view can use it; no public module API or mutable gallery state is exposed.
This reduces the composition file from 3,270 to 2,728 lines. It remains oversized
debt; this checkpoint does not claim the whole gallery decomposition is finished.
Follow-up extractions should address cohesive catalog/folder, import, bulk and
media coordination responsibilities in bounded reviews before feature growth.
Avoid simply moving the entire problem into a giant view model.

## Enforced prevention

The existing architecture CI gate invokes `check_source_size.py` and checks
all first-party Swift/Python/JavaScript/shell source under the application,
extension, tests and scripts. Only the existing vendored Argon2id subtree is
excluded. New files default to 500 physical lines. This intentionally counts
comments and blank lines; do not game it by reducing readability.

`source_size_limits.json` records existing oversized files with exact ceilings.
Growth fails; shrinking a legacy file requires lowering its ceiling, and
crossing below 500 requires removing its allowance. These are frozen debts,
not approved architecture targets. New files must never be added as legacy.

The user allows an exception when there is no sound modular alternative. Such
an exception requires an explicit per-file reason and maximum in `exceptions`,
review of the rejected split alternatives, and appropriate tests. It cannot
be a wildcard, permanent permission to grow or a global relaxation. Policy and
checker changes remain covered by the existing `/scripts/` code ownership.
Automated checks cannot judge the merit of a rationale: that remains review work.

`gallery_boundaries.py` enforces unique ownership of the extracted types, exact
reviewed imports, no session/key/network authority, and no storage authority
in catalog or image presentation. Existing thumbnail checks move with their
owner; image/video lifetime checks remain at composition. Checker self-tests
exercise oversized growth, stale allowances, missing rationale, duplicate
owners, comment spoofing, forbidden store access and removed thumbnail guards.

The workflow-security checker pins the new helpers and size policy as well as
the architecture checker. Its hash mutation probes move intact to their own
small file, verified before loading, while hash enforcement stays in the
security owner. Both existing checker files shrink; no size exception is used.

## Verification and release

No archive format, storage schema, build number or user-visible feature changes.
Existing catalog/presentation, media navigation, thumbnail concurrency,
cancellation, secure preview and video lifecycle tests must pass in native CI,
together with all architecture/privacy/workflow/release checks and CodeQL.
No native result or device acceptance is claimed until exact-source CI and
physical testing complete. Physical checks should revisit fast scrolling,
folder/search/sort/selection, photo/video paging, portrait/landscape dismissal,
retry, import/export and background/lock cleanup. Preserve source originals.

Later gallery stages remain separate reviewable changes; no tags, bulk-control
expansion, large-video format, transfer wizard or Notes code enters this stage.
