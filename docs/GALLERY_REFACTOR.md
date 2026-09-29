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

## Second extraction: current-location metadata

The first checkpoint at `fc2386850ff3fc2299add1449e9e49556db3e484` passed native
build, the full regression/security suite, packaged-resource checks and Swift
CodeQL in [CI 36558435050](https://github.com/Frankbell84/KeyHollow/actions/runs/36558435050).
PR #101 is ready for review; its merge remains pending explicit authorization.

Branch `codex/gallery-location-snapshot` extracts `VaultGalleryLocationSnapshot`
from that tested checkpoint. This 232-line app-owned value captures photo/file
records, folder metadata, the active location, query, sort order and the existing
depth bound. It owns only derived folder counts, breadcrumbs, visible content,
search/order, move-destination values and empty-state text. The composition
creates it on demand; it does not retain a new observable state owner.

The gallery falls from 2,728 to 2,546 lines. Calculation bodies are preserved;
the existing store depth constant is supplied as a value by composition.
Protected stores, session access, writes, imports, sensitive tasks, media
lifetimes and lock/cancellation handling retain their previous owners.
No compiled module dependencies or public add-on interfaces change.

The moved architecture assertions now run against the location owner. Negative
probes reject missing immutable inputs, altered query wiring, task authority
and missing composition inputs. Seven focused native regression tests cover
typed-ID collisions, root/parent/child isolation, direct counts, ordered media
and selection, bounded breadcrumbs, move permissions, snapshot value isolation
and existing empty-state behavior. These native tests require macOS CI; a local
static pass is not a substitute. Existing oversized tests do not grow.

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
