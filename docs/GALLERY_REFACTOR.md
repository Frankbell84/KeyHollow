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

PR #104 at `39ee1bb99b010f3855f2b3c3c9e1eaacd8f4af81` passed native build,
468 unit tests, 3 launch tests and Swift CodeQL in CI `36620610539`. It merged
as `1132dab6ed6bf42533577b6ca18ea41fac621224` with the same source tree; the
merged main also passed both jobs in `36623496994`.

## Fifth extraction: folder interactions and metadata commands

Branch `codex/gallery-folder-actions` starts from that verified merge.
`UI/VaultGalleryFolderActions.swift` owns transient editor/deletion state and
immutable item, selection and folder move requests. Only the name draft is
directly writable by a UI binding. The value derives permissions from the
current immutable location snapshot, retains typed photo/file identity, and
has no session, task, store or mutation callback. Vault and security-epoch
resets clear its state at the same points as before.

`UI/VaultGalleryFolderMutation.swift` is a captured metadata command and error
presentation adapter. It takes the existing authenticated folder store for
one call, applies the same store operation and returns its refreshed manifest.
It has no independent task, session, key, retained store or content-store
access. The same compiled Folder Presentation implementation remains the
sole owner of folder persistence, validation, authorization and encryption.
No add-on module or public API changes.

The gallery falls from 2,317 to 2,216 lines. Composition still registers each
sensitive task, captures intent before starting it, handles busy/refused-task
state and cancellation, publishes the returned manifest, clears selections
and updates the active location. Move and editor sheet/alert ordering stays
unchanged. Non-folder operation bodies remain unchanged under the reviewed
source-substitution comparison. Import/media cleanup stays with its prior owner.

Seven interaction tests cover name normalization/capture, absent folders,
typed-ID collisions, immutable batch destinations, empty/invalid destinations,
subtree exclusion and reset. Six command tests use temporary encrypted storage
to cover every dispatch, preserved identities/memberships, failed writes,
cancellation, revocation and the existing recovery messages. The full native
suite and security scan remain required; exact results are recorded in the PR.

`gallery_folder_boundaries.py` carries the moved batch-store assertion and
negative probes for dispatch, registered task ownership, busy/refused-task
handling, cancellation, private dialog state and lifecycle reset. The new
helper is hash-pinned. Existing project-execution and isolated-Python probes
move intact into the already verified workflow probe helper; production
security enforcement and pre-execution hash verification stay in the checker.
Both oversized checker ceilings shrink, and no size allowance is raised.

PR #105 at `e6e8dc33ab0a5ec7fe05449cb24f0319fc722e80` passed native build,
481 unit tests, 3 launch tests and Swift CodeQL in CI `36630405835`. Its merge
`f22eb9ca601ea501dda36adb335b19fb4cc3a38a` has exactly the same source tree;
the merged main also passed both jobs in `36633714901`.

## Sixth extraction: media viewer presentation

Branch `codex/gallery-media-presentation` separates the full-screen viewer's
layout, toolbar and failed/opening state into `VaultGalleryMediaViewer.swift`
(149 lines). The gallery falls from 2,216 to 2,119 lines. The new app-owned views
receive queue metadata, display/availability flags, the existing alert binding,
typed actions and an active-content builder. The existing pager still invokes
that builder only for the current item. No public add-on interface changes.

Composition retains every operation and lifetime owner: image/video state,
payload preparation, surface attachment/release, task registration, generation
checks, readiness, saving/deletion, dismissal and lock/background cleanup.
The image/video content bodies and all non-presentation operations are unchanged.
The new views do not receive stores, sessions, decoded images, keys or media
coordinators. The permanent video toolbar and image-only fading overlay retain
their positions, styles, gesture policy, accessibility and disabled conditions.

The moved architecture assertions now check both the presentation and its
composition inputs. Negative probes remove action routes, readiness/busy guards,
video Done placement, image chrome policy and retry wiring, and reject a new
task or retained image in the view. Existing media navigation, gesture, image
and video lifetime tests remain required in native CI. This pure presentation
move adds no new state machine that would justify duplicate runtime tests.

The new checker helper is hash-pinned. Existing action-pinning and direct-input
interpolation probes move intact into the already verified workflow probe
helper. Production security checks and verification before helper execution
remain in their original owner. Both oversized checker ceilings decrease;
no new legacy allowance or size exception is introduced.

The owner authorized continuing focused refactor stages and delivery through
an iPhone test build. Exact CI/merge results remain in each PR. Physical testing
must still revisit portrait/landscape video close and swipe behavior, photo
paging/zoom/save, retry, deletion and lock/background cleanup before acceptance.

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
