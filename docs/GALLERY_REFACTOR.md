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
PR #101 merged with explicit owner authorization as
`d75a5f0037c11639d00957b8e235b428a969fcad`; the merged source tree exactly matches
that passing checkpoint. Build 59 remains the installed accepted binary.

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

At `e507513668bbc03b63a2068ade232a3cf8d639ac`, PR #102 passed its native build,
458 unit tests and 3 launch tests in CI `36582963782`, including all seven
location tests. Swift CodeQL subsequently passed; PR #102 merged as
`4613e9aced6bf6f4b855e370e3c131f7ea8d611b` with the same source tree. The exact
merged main also passed both CI jobs in `36585812456`.

## Third extraction: gallery controls

Branch `codex/gallery-presentation-controls` builds on the preserved second
checkpoint. `VaultGalleryHeaderControls` (126 lines) owns the header and menu;
`VaultGallerySearchControls` (71 lines) owns the search/sort controls and their
existing labels; `VaultGallerySelectionControls` (85 lines) owns the bulk
action bar. The gallery falls from 2,546 to 2,378 lines.

These remain app-owned presentation adapters with no public add-on API change.
The header and selection views receive display summaries and emit typed intent;
the search view receives only text/sort bindings and its query-empty flag.
They receive no records, IDs, stores, session, keys, tasks or mutation services.
Composition retains the existing operation handlers, import destination and
security-epoch capture, confirmation dialogs and awaited lock-cleanup barrier.

The original layouts, labels, accessibility modifiers and availability rules
are preserved after explicit display-value/action substitution. A reverse
source comparison confirms the remaining gallery operation code is unchanged.
Ownership/import checks and moved presentation assertions accompany the views;
negative probes reject unknown intents and missing action routes. The existing
selection, lifecycle, security and launch suite remains required in native CI.
Physical verification must include header/menu actions, Back/Lock, selecting
and deselecting, search/sort/clear, mixed selection and confirmation dialogs.
This checkpoint does not add product behavior or establish device acceptance.

At `8dbb6ce7bd038c030dc151e1c3b30b50f0f5cc11`, PR #103 passed native build,
458 unit tests, 3 launch tests and Swift CodeQL in CI `36585530978`. It merged
as `de249a7a06bfec318e2e9ef45ac242816afe1846`, with the same source tree.

## Fourth extraction: decoded thumbnail cache

Branch `codex/gallery-thumbnail-cache` begins at the third checkpoint's merge.
`UI/VaultGalleryThumbnailCache.swift` owns the two decoded-image dictionaries
and the existing retention policy. The app-owned value receives typed item
identities and `UIImage` values, without records, stores, keys, sessions, loading
closures or task authority. Its state stays private behind cache operations.
The existing retention policy remains in `KeyHollowGalleryUI`; no compiled
module dependency or public add-on interface changes.

The gallery falls from 2,378 to 2,317 lines. It still owns protected loading,
the decoding actors and shared thumbnail pipeline, session-barrier registration,
cancellation checks and post-load vault checks. A vault reset clears both
image dictionaries and retention state at the original point before loading.
The cache preserves the 96-image shared budget, visible-tile protection and
least-recently-used hidden eviction. Photo and file catalog pruning remain
separate so one catalog refresh cannot remove the other's decoded images.

A reverse source comparison covers every cache substitution and confirms all
other composition code is unchanged. Ownership/import checks forbid protected
storage, session, network, task and record authority in the cache; mutation
probes enforce composition wiring and the reset barrier. Ten focused native
tests cover typed UUID collisions, shared/default budgets, visible-tile pressure,
reappearance order, independent catalog pruning, stale visibility, reset and
image-reference release, and independent value copies. Existing retention,
thumbnail concurrency, lifecycle and media tests remain required in CI.
Physical acceptance still requires the gallery regression checklist below.

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
