# DoomPB — M3-04: Screen projection, wall clipping and BSP occlusion

> - **Task ID:** `M3-04`
> - **Milestone:** M3 — Geometry & First Walls; `v0.3.0` is **not** complete
> - **Status:** Implementation assignment, **not** an implementation report
> - **Coding agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017, Reasoning **High**
> - **Compiler:** PureBasic **6.41**, full edition; primary verification on Windows x64
> - **Linux x64:** `NOT RUN` unless compiled and executed there on a real Linux installation
> - **License:** GPL-2.0-only; local commercial IWAD is read-only and must never be committed
> - **Pinned reference:** `../doom-original` at `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M3-03 implementation accepted and committed on `dev`; **verify** current state
> - **Read first:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md` (M3), `docs/PORTING_NOTES.md`, this task, actual code/tests

## 1. Objective

Implement the **headless front-end of the classic Doom wall-rendering pipeline** at the original logical viewport width (320 columns). Combine exact angle-to-screen lookup tables, an ordered list of solid occlusion spans, the source-faithful `R_AddLine` wall classification, and `R_CheckBBox` into one bounded, testable near-to-far BSP traversal.

The result is a deterministic ordered collection of **visible wall-column intervals**, each tied to its source `seg`/`subsector`, plus counters for visited nodes/leaves, considered/rejected segments and skipped far branches. This is **not** a pixel renderer, a `drawseg_t` implementation or a list of every wall on the map.

Acceptance criteria:

1. `viewangletox[4096]`, `xtoviewangle[321]`, `clipangle` and center/projection constants match original Doom `R_InitTextureMapping` behavior for the supported viewport.
2. `R_ClearClipSegs`, solid/pass wall clipping, and the original inclusive interval boundaries are correct; repeated, adjacent and overlapping spans are handled safely.
3. `R_AddLine` preserves angular backface/FOV filtering and the original solid/pass/skip classification, without attempting textured drawing.
4. An **online** BSP walker processes near-side leaves and their segs **before** testing the far-side bounding box against the updated occlusion state.
5. Full `R_CheckBBox` supports camera-inside-box and covered/uncovered cases with a conservative policy for arithmetic uncertainty.
6. Synthetic and real-IWAD tests pass, existing M3-03 `BspTraceBuild` behavior remains unchanged, all earlier tests pass, and version remains `0.2.0`.

Do not confuse these three outputs: (a) M3-03 cull-free BSP trace, (b) M3-04 visibility/column-range trace, and (c) M3-05+ actual rendered pixels. Keep names, counters and documentation distinct.

### 1.1 Explicit non-goals

- **No** `R_StoreWallRange` drawing, `drawseg_t` scale calculations, vertical wall projection, framebuffer pixels, textures/column stepping, plane/visplane rendering, sky, sprites or COLORMAP lighting.
- **No** game loop, controls, player physics, animated textures, new PWAD overlay system or new viewport/UI subsystem.
- **No** arbitrary aspect ratios, widescreen, variable-resolution modes or FOV controls. Classic **320-column logical viewport** first; treat 960x600 TITLEPIC presentation as a separate pre-existing feature.
- **No** changes to `BspTraceBuild` semantics (full cull-free near/far trace), and no silent repurposing of old hashes or assertions.
- **No** tagging `v0.3.0`, changing application version from `0.2.0`, or implementing M3-05.
- **No** auto `git add`, `commit`, `push` or `tag`.

## 2. Inspection and short implementation plan — mandatory before changes

1. Execute `git status --short --branch`, `git log -5 --oneline`, `git tag --list`, `git diff --stat`, `git diff --cached --stat`. Confirm M3-03 is committed; report if not. Preserve user changes and the task document.
2. Read **real** signatures and ownership rules for:
   - `src/Core/Fixed.pbi`, `Angle.pbi`, `TrigTables.pbi`, `TrigTablesData.pbi`;
   - `src/Renderer/Geometry.pbi`, `Camera.pbi`, `BSP.pbi` (`BspTraceBuild`, `BspCameraGet`);
   - `src/Map/MapTypes.pbi`, `MapLevel.pbi`, `MapDecode.pbi`, `MapLoader.pbi`, `MapValidate.pbi`;
   - `src/Graphics/TextureDefs.pbi` (only if choosing a catalog-aware texture identity adapter);
   - `src/DoomPB.pb`, `scripts/{build,test}.{ps1,sh}`, relevant M2/M3 tests.
3. Verify `git -C ../doom-original rev-parse HEAD` equals pinned SHA; inspect **actual C**, not copied prose:
   - `linuxdoom-1.10/r_main.c`: `FIELDOFVIEW`, `R_InitTextureMapping`, `R_ExecuteSetViewSize`, `R_RenderPlayerView`;
   - `linuxdoom-1.10/r_bsp.c`: `R_ClearClipSegs`, `R_ClipSolidWallSegment`, `R_ClipPassWallSegment`, `R_AddLine`, `R_CheckBBox`, `R_Subsector`, `R_RenderBSPNode`;
   - `linuxdoom-1.10/r_defs.h`, `r_state.h`, `r_main.h`, `r_segs.c`, `tables.h`, `m_fixed.c` and `m_bbox.h`.
4. Follow the documentation policy in `AGENTS.md`: use configured **Context7 MCP** for suitable external API documentation, if available, and report the actual library ID/topic or the failure. For PureBasic-specific ambiguities prefer official docs/local installed `.chm` and disposable PB 6.41 compiler probes. C source is authoritative for Doom semantics; Context7 is not a substitute.
5. Present a short plan listing exact files, APIs, allocation strategy, projection table oracle, classification rules, online walker integration, test categories and source deviations **before** coding.

Historical baseline from the M3-03 owner report (**rerun, don't merely quote**): synthetic 515 cases / 3,460 assertions; with optional legal IWAD tests 519 / 3,585; `scripts/test.ps1` 101/101 without IWAD or 117/117 with IWAD; Windows x64 compiler 6.41; Linux runtime NOT RUN. Confirm actual repository values.

## 3. Module boundaries and data model

Use a small, cohesive architecture. Suggested files (adapt to actual conventions without unrelated refactoring):

```text
src/Renderer/Projection.pbi             # 320-column tables and clipangle
src/Renderer/ClipSegs.pbi               # owned solid ranges and wall-span outputs
src/Renderer/WallVisibility.pbi         # R_AddLine, R_CheckBBox, online BSP walk
 tests/unit/wall_clipping_tests.pb      # WC01–WC52
 tests/integration/m3_wall_clip_tests.pb
 tests/integration/m3_wall_clip_iwad_tests.pb  # optional owner IWAD
```

Separate `WallClassifier.pbi` is allowed if it clarifies dependencies; **do not create empty placeholder modules** for M3-05. Keep `Camera.pbi`, `Geometry.pbi` and `MapLevel.pbi` as reusable dependencies.

Suggested conceptual API (**not guaranteed PureBasic syntax**):

```text
ProjectionInitClassic(*Projection) -> bool             # deterministic, owned immutable tables
ProjectionReset(*Projection) -> bool
ProjectionGetViewAngleToX(*Projection, FineIndex, *X) -> bool
ProjectionGetXToViewAngle(*Projection, ScreenX, *BamRaw) -> bool
ProjectionGetClipAngle(*Projection, *BamRaw) -> bool

ClipStateBeginFrame(*State, Width=320) -> bool           # two sentinels, empty visible spans
ClipSolidSegment(*State, First, Last, SourceSeg, ...) -> bool
ClipPassSegment(*State, First, Last, SourceSeg, ...) -> bool
ClipStateGetRange(*State, ...) / GetWallSpan(...) -> bool
ClipStateReset(*State) -> bool

WallVisibilityBuild(*Level, *Camera, *Projection, *Result) -> bool
WallVisibilityGetSpan(*Result, Index, *Fields...) -> bool
WallVisibilityGetStats(*Result, *Counters...) -> bool
WallVisibilityReset(*Result) -> bool
WallVisibilityLastError() -> string
```

Exact exported names are flexible. Document all return and ownership conventions. Prefer index-backed, immutable output records and checked accessors over borrowed raw pointers. `WallSpan` should contain **at least** `SubsectorIndex`, `SegIndex`, `FirstX`, `LastX` (**inclusive**), `WallKind` (`SOLID` or `PASS`), and optionally a source linedef/side index. Do not store pixels, game textures, or unowned WAD pointers.

### 3.1 Lifetime and transaction rules

- Caller zero-initializes each owner; reset is idempotent and frees only allocations it owns.
- On any failed `Init`/`BeginFrame`/`Build`, result is valid-and-empty or explicitly invalidated according to a documented uniform policy; never leave partially published spans/occlusion state or corrupt existing `MapLevel`/camera.
- A successful result remains readable after `WADClose`, `MapLevelReset` and subsequent map loads, because it owns only numeric diagnostics/spans.
- Projection tables may be precomputed once and reused; they must not depend on mutable IWAD or camera pointers.
- Bound all allocations, index math and traversal work. Use checked 64-bit intermediates for bytes and record totals. **No recursion**, arbitrary pointer indexing, or unbounded `while` scans.
- Aim to avoid allocations per processed seg. Initial capacity and bounded geometric growth are fine; record allocations/growth counts. Avoid large fixed allocations where a small preallocated frame state suffices.
- Keep pure clipping functions independently testable without `MapLevel`, graphical window or WAD.
- No unused `goto` through nested `Select`/`While` blocks: the project has encountered PureBasic pointer corruption associated with that control-flow pattern. Use structured flags/cleanup or top-level exits.

## 4. Exact C reference: projection and angle semantics

The original `r_main.c` has `#define FIELDOFVIEW 2048`, `FINEANGLES 8192`, `ANGLETOFINESHIFT 19`, and `FINEMASK 8191`. Its 320-wide logical viewport has `viewwidth=320`, `centerx=160`, `centerxfrac=160*FRACUNIT`, `projection=centerxfrac` (all **logical 320** columns, not the 960 display pixels).

`R_InitTextureMapping` performs these operations in this order:

1. `focallength = FixedDiv(centerxfrac, finetangent[FINEANGLES/4 + FIELDOFVIEW/2])` (index **3072**).
2. For fine indices `i=0..4095`, if `finetangent[i] > 2*FRACUNIT`, assign `-1`; if `< -2*FRACUNIT`, assign `viewwidth+1`; otherwise compute `t=FixedMul(finetangent[i],focallength)` and `(centerxfrac-t+FRACUNIT-1)>>FRACBITS`, then clamp to `[-1,viewwidth+1]`. Retain the original integer operation order, conservative `FixedDiv` and truncation semantics.
3. For screen x `0..viewwidth` (321 elements), scan the **pre-fencepost** `viewangletox` until it stops being `>x` and assign `xtoviewangle[x]=(i<<ANGLETOFINESHIFT)-ANG90`, as an unsigned BAM angle.
4. Finally normalize the fenceposts: `-1→0`, `viewwidth+1→viewwidth` in `viewangletox`. The C source has an additional local `t` computation in this loop that is unused; document whether it is omitted.
5. `clipangle=xtoviewangle[0]`. Preserve the exact raw BAM representation and signed/unsigned distinctions.

Treat index 4095 and x=320 as valid endpoints. The C `while (viewangletox[i]>x)` is **not bounds-checked**; in PureBasic make an explicit bounded scan and report unexpected table invalidity rather than reading past the array. Do **not** switch to a continuous `tan()` projection or change thresholds/ceil rule. Tests must validate table *contents*, not just a few output samples.

The canonical implementation is **single viewport width 320** for M3-04. If the existing project already has a proven width abstraction, a narrowly bounded second width may be tested, but never sacrifice fidelity of width 320 or silently claim all viewport sizes are supported.

## 5. Solidseg range representation and sentinel invariants

The original `R_ClearClipSegs` creates two sorted sentinel intervals:

```text
[-0x7FFFFFFF, -1]       [viewwidth, +0x7FFFFFFF]
```

Track **inclusive** ends, like original Doom. Initially the drawable domain `[0..viewwidth-1]` is unoccluded. The state must maintain:

- Strict sorted order; adjacent or overlapping solid intervals are merged (after successful solid clipping), preserving sentinel coverage.
- Two sentinels are never accidentally deleted or excluded; all user-facing wall spans satisfy `0 <= FirstX <= LastX < viewwidth`.
- The first and last column (0, 319), exact interval adjacency, and single-column spans are supported.
- A pass wall may emit visible subspans but **must not modify** `solidsegs` at all.
- A solid wall emits each still-uncovered subspan in left-to-right order and **then** expands/merges the occlusion list so later walls cannot re-emit those pixels.
- An already fully occluded span emits nothing. `ClipStateGetRange` never returns dangling memory.
- A zero-length/invalid/inverted/out-of-range segment is either a documented no-op or an error according to explicit API contract; **never** silently convert `x1==x2` into a one-column wall. In `R_AddLine`, the C projection uses `[x1,x2-1]`.

Upstream uses `MAXSEGS=32` fixed clip posts and pointer arithmetic; DoomPB should use a **safe bounded** container with deterministic insertion/removal and a checked capacity error rather than reproduce a possible out-of-bounds write. Hard cap and allocation budgets should be explicit. Avoid quadratic behavior where possible; the width 320 makes the number of disjoint real screen intervals small, but tests must still cover growth and merging.

### 5.1 R_ClipSolidWallSegment

Reproduce the fragment emission and merge order from `r_bsp.c` (first/last inclusive), including:

- no intersection with existing posts → emit whole range and insert sorted post;
- partially occluded prefix, middle or suffix → emit only uncovered fragments;
- adjacent posts that touch the new solid interval → merge into one;
- full covering of several posts → consolidate without stale intervals;
- a segment already hidden by a post → no new output.

Prefer a simple, demonstrably equivalent checked interval algorithm to pointer-heavy `goto crunch` while preserving **observable span order and state**. Prove equivalence using an independent oracle for all small-width interval combinations and selected original C vectors.

### 5.2 R_ClipPassWallSegment

Same uncovered-fragment emission but no state changes. Test pass→pass overlap, pass→solid and solid→pass order; the final visible ranges must reflect **only** earlier solid walls as occluders.

## 6. R_AddLine: segment angle test, FOV and classification

Implement a headless source-faithful equivalent of `R_AddLine(seg_t*)` using M2 validated, caller-owned records and M3-02 geometry APIs. Process each seg in its subsector's original order. Required steps:

1. Resolve `seg` endpoints to fixed-point via `FixedFromIntChecked`; consult `MapLevel` links for linedef/front/back sector and sidedef. Respect segment orientation (`Side=0/1`) and canonical front/back, including one-sided sentinel `-1`.
2. `angle1=R_PointToAngle(v1)`, `angle2=R_PointToAngle(v2)` with explicit camera position. `span=(angle1-angle2) mod 2^32`. **Reject if `span>=ANG180`** (exact equality matters). Preserve the first *global* `angle1` if any later phase needs it.
3. Subtract camera heading from both angles with unsigned BAM wrap. Clip left/right against `clipangle` using source `tspan`, `2*clipangle`, strict inequality boundaries and unsigned subtraction. This is **not** a floating-point FOV test.
4. Convert fine angles after adding `ANG90` with unsigned wrap and `>>19`, then read `viewangletox`; if `x1==x2`, reject; otherwise pass `[x1, x2-1]` as the candidate **inclusive** interval. Test and diagnose unexpected ordering/ranges rather than creating inverted intervals.
5. Classify the seg like original `R_AddLine`: no backsector or closed opening → **SOLID**; open backsector with unequal floor/ceiling heights → **PASS**; otherwise possible empty trigger line → **SKIP** only if floor/ceiling texture **identity** and light levels match and the seg's middle texture is absent; other two-sided lines → **PASS**.
6. Feed SOLID/PASS candidate to the clip-state routines. Emit **ordered visible fragments** with original seg/subsector identity and classification; do not draw pixels, create `drawseg_t` or change map data.

### 6.1 Texture equality and no-middle-texture

The C renderer compares **resolved texture/flat indices**, not raw memory bytes. M2 decoded resource catalogs and map name binding must be inspected before choosing an identity strategy:

- Prefer a safe catalog-aware identity lookup where readily available. Otherwise, on already validated vanilla single-IWAD input, document a narrowly defined canonical 8-byte name comparison that is case-insensitive only if the actual WAD/catalog semantics justify it. Do not treat a malformed name as an empty slot.
- Recognize canonical `-` and all-NUL *no texture* slots per M2 validation; **do not** interpret an embedded NUL, unknown name, arbitrary hyphen prefix or missing catalog as a silent no-texture slot.
- Do not drop `ML_TWOSIDED` walls solely based on flag; use actual validated front/back sector linkage. Protect against a missing back sidedef.
- Ensure the selected sidedef is the **seg's** side, not necessarily linedef side 0.
- `F_SKY1` is an ordinary resolved flat for this non-drawing task; rendering the sky stays in M4.
- If a required identity is unavailable, return an explicit diagnostic or choose documented conservative PASS behavior that cannot falsely mark an opaque wall; do **not** invent a texture ID.

### 6.2 Original function nuances

- `R_AddLine` backface test precedes solidity checks; preserve order.
- Original door/window decisions compare **sector heights** and may produce a SOLID span for a two-sided wall.
- Same floor/ceiling and lighting with a visible midtexture is **not** an empty trigger line; it remains PASS.
- Current `MapLevel` stores signed map-height units rather than runtime 16.16 sector heights. Comparing heights directly in map units is equivalent *for these comparisons*, but offsets requiring arithmetic must be checked.
- A seg facing away must not add solid coverage regardless of whether its linedef is one-sided.

## 7. R_CheckBBox with live solidsegs

The original `R_CheckBBox(fixed_t* bspcoord)` in `r_bsp.c` uses the 12×4 `checkcoord` table, camera-relative box position, `R_PointToAngle`, the same `clipangle`/`viewangletox` as walls, and **current** solidseg coverage. Implement it now, with original case order:

1. Interpret bbox fields as `{BOXTOP,BOXBOTTOM,BOXLEFT,BOXRIGHT}` from `MapNode` (not the left/right/top/bottom order of a guessed struct). Convert signed map-unit values to fixed safely.
2. `boxx = 0 if cameraX<=left; 1 if cameraX<right; else 2`. `boxy = 0 if cameraY>=top; 1 if cameraY>bottom; else 2`. `boxpos=(boxy<<2)+boxx`. Original `boxpos==5` (camera inside box) immediately returns **POTENTIALLY_VISIBLE**.
3. Select two bbox corners using the **exact** `checkcoord` lookup for the appropriate boxpos. Handle source placeholder/unreachable positions without out-of-bounds reads.
4. Compute both camera-relative BAM corner angles, subtract camera heading, calculate `span` and apply the original `span>=ANG180` rule (which may conservatively preserve visibility).
5. Perform the same left/right clipping as `R_AddLine`, project with `viewangletox`, and apply the original `sx2--` inclusive right boundary.
6. Test whether one solidseg post fully covers the projected span. Only then return **OCCLUDED**; otherwise return **POTENTIALLY_VISIBLE**.

Implement a conservative tri-state helper if needed: `VISIBLE / OCCLUDED / UNKNOWN`. For genuine arithmetic/edge uncertainty, **do not silently cull**: visit the far branch, record fallback reason/counter, or reject the whole build with a clear diagnostic if the input violates required invariants. False positives (extra work) are acceptable in safe fallback; false negatives (missing geometry) are not.

**Crucial timing:** when a node is encountered, traverse the camera-near child, process its segs and update `solidsegs`, **then** evaluate the far child's bbox. A `BspTrace` computed earlier has already traversed both sides and cannot implement `R_CheckBBox` correctly by simple postfiltering.

## 8. Integrated online BSP visibility walk

Create a separate **iterative**, explicit-stack online walk resembling the control flow of `R_RenderBSPNode`, using the validated root from `MapLevelGetBspRoot` and the exact `GeometryPointOnNodeSideChecked` from M3-02:

```text
frame:
  initialize projection and clip sentinels
  push BSP root
  while stack not empty:
    node enter: determine near side; schedule far-check AFTER near completion
    leaf: process segs in firstseg..firstseg+numsegs-1 with R_AddLine-equivalent
    far-check: test far bbox with current solidsegs; if visible, descend far
  publish ordered source-identifiable visible fragments + counters
```

An explicit frame state machine is recommended (`ENTER_NODE`, `VISIT_NEAR`, `CHECK_FAR`, `VISIT_LEAF`) to avoid incorrectly evaluating bbox before near occluders. No recursion. Reuse M3-03's root encoding and safety concepts but **do not mutate** its trace API or force a full precomputed trace.

Require:

- Zero-node/one-subsector root handling like M3-03.
- Correct `$8000` subsector flag and `$7FFF` index with bounded access.
- Guard against invalid, shared, stale or cyclic graph edges even if M2 validation normally rejects cycles; work/event limits protect against exponential DAGs.
- Non-overlapping, ordered wall fragments; segmentation may cause several visible fragments for one source seg. Do not equate visible-fragment count with seg count.
- `OcclusionSkips` counts only actually pruned far child visits (not rejected backfaces or FOV-filtered segs). Additional counters for `BackfaceRejects`, `FovRejects`, `PixelWidthRejects`, `EmptyLineRejects`, `SolidCandidates`, `PassCandidates`, `EmittedFragments`, `BboxTests`, `BboxUnknown` are useful if bounded.
- Frame result is deterministic for the same map/camera and all intermediate tables are immutable. The camera heading must affect angular clipping even though M3-03's cull-free order depends only on position.
- No per-frame redraw, window, image data, new CLI command, or networking.

## 9. Source equivalence and independently checkable oracles

Establish independent **test-only** reference computations; do not validate production code only against itself.

- For projection, build a compact reference in Python or stand-alone original-derived C at test/generation time. Use the exact source `FixedMul/FixedDiv`, integer wrap and table values; validate all 4096 `viewangletox` entries, all 321 `xtoviewangle` entries, and `clipangle` via a canonical little-endian field hash and explicit sample values. A few samples are **not sufficient**. Do not invent expected hashes before running the oracle.
- For clipping, implement an independent small-domain bitmap reference (e.g. logical widths 8/16/32 for test-only `ClipState` logic), or compare an independently coded deterministic interval implementation; **never** use image/game assets as fixtures. Validate emitted fragment **order** as well as union coverage and final `solidsegs`.
- For `R_AddLine`, use a test-only translation of C branching and exact golden vectors for wrapped angles, threshold ties, SOLID/PASS/SKIP and `[x1,x2-1]` behavior.
- For bbox, exercise all geometrically reachable `checkcoord` positions and camera-on-edge ties; compare to an independent C/Python branch translation for controlled intervals.
- For online BSP, compare a small **recursive test-only** oracle which processes near leaves/seg clips and far checks in the correct order, against the production iterative walk. Do not use the existing precomputed `BspTrace` as the oracle for occluded walks.
- Ensure generated fixture scripts are deterministic and path-independent. If a committed golden fixture is needed, store **only numeric checksums/counters** or original synthetic data, not IWAD-derived asset dumps.

## 10. Required synthetic unit test matrix — WC01–WC52

Each test identifier must have a real runnable assertion; several assertions per case are encouraged. Adapt names only if test harness conventions require, and report exact numbers.

### 10.1 Projection (WC01–WC12)

| ID | Required coverage |
|---|---|
| WC01 | Projection object reset, default 320 width, repeated init reproducibility |
| WC02 | `FIELDOFVIEW=2048`, focal index 3072 and center/projection constants |
| WC03 | Table lengths: 4096/321, checked first/last indexed access |
| WC04 | `focallength` against independent original-divide oracle |
| WC05 | Selected negative/zero/positive tangent projection values |
| WC06 | Strict `>+2*FRACUNIT` and `<-2*FRACUNIT` boundaries |
| WC07 | Pre-fencepost table retained for inverse lookup computation |
| WC08 | Post-fencepost `-1→0`, `viewwidth+1→viewwidth` order |
| WC09 | All 4096 forward entries compared to test-only reference/hash |
| WC10 | All 321 inverse entries compared to test-only reference/hash |
| WC11 | `clipangle` matches inverse x=0 and unsigned BAM representation |
| WC12 | Invalid table access, null pointer, repeated reset/reinit and no stale errors |

### 10.2 Solid/pass interval clipping (WC13–WC26)

| ID | Required coverage |
|---|---|
| WC13 | Initial sentinels and empty visible coverage |
| WC14 | First and last drawable columns; one-column SOLID |
| WC15 | Disjoint SOLID intervals: sorted insertion and visible output order |
| WC16 | Adjacent SOLID intervals coalesce at inclusive endpoints |
| WC17 | Nested SOLID fully covered: no fragment emission |
| WC18 | Overlapping SOLID: visible prefix only |
| WC19 | Overlapping SOLID: visible suffix only |
| WC20 | SOLID fills gap between two intervals and merges both |
| WC21 | SOLID spanning multiple occluders emits each uncovered gap |
| WC22 | PASS on empty state emits span but adds no occluder |
| WC23 | PASS overlapping SOLID emits only visible gap and does not mutate clips |
| WC24 | PASS then PASS, PASS then SOLID, SOLID then PASS chronology |
| WC25 | Tiny-width exhaustive/seeded bitmap-oracle comparison |
| WC26 | Bad ranges/budget/OOM/reset preserve invariants and output contract |

### 10.3 AddLine and classification (WC27–WC39)

| ID | Required coverage |
|---|---|
| WC27 | Camera +X, -X, +Y, -Y facing with exact BAM wrap |
| WC28 | Backface rejection `span==ANG180` and both sides of threshold |
| WC29 | Left FOV edge clipping and strict inequality tie |
| WC30 | Right FOV edge clipping and strict inequality tie |
| WC31 | Outside FOV rejected before any clip-state mutation |
| WC32 | `x1==x2` pixel-width rejection; `[x1,x2-1]` inclusive endpoint |
| WC33 | One-sided linedef with valid middle texture → SOLID |
| WC34 | Closed two-sided door via ceiling/floor overlap → SOLID |
| WC35 | Two-sided window with different floor height → PASS |
| WC36 | Two-sided window with different ceiling height → PASS |
| WC37 | Identical planes/light and absent middle texture → SKIP |
| WC38 | Same planes/light but present middle texture → PASS; differences in lighting/texture identity → PASS |
| WC39 | Seg side 1 orientation, derived front/back links, bad/missing name handling |

### 10.4 Bounding boxes and integrated walk (WC40–WC52)

| ID | Required coverage |
|---|---|
| WC40 | `checkcoord` mapping for each reachable camera-box region |
| WC41 | Camera exactly on left/right/top/bottom bbox boundary |
| WC42 | Camera inside bbox (`boxpos=5`) always conservatively visible |
| WC43 | No occlusion posts: far bbox preserved unless genuinely outside FOV |
| WC44 | Bbox completely behind FOV: safe rejection with independent oracle |
| WC45 | Bbox projected range fully covered by one solidseg → OCCLUDED |
| WC46 | Bbox partially covered, multiple clips, fencepost single pixel → VISIBLE |
| WC47 | Concrete two-leaf BSP: near SOLID occludes far child only **after** near visits |
| WC48 | Near PASS wall does not occlude far branch |
| WC49 | Deeper near/far order; test-only recursive-online oracle equivalence |
| WC50 | Zero-node one-subsector map and empty/subsector root edge handling |
| WC51 | Corrupt child/bbox/delta, DAG/work/event caps: deterministic safe failure or conservative fallback |
| WC52 | Transactional failure, old result lifetime after MapLevel/WAD reset, repeated build determinism |

Use synthetic maps and fabricated names, not commercial fixture bytes. At least one synthetic BSP test must produce a **nonzero** `OcclusionSkips` value. Validate that every emitted span's seg index belongs to a loaded subsector and every span falls in `[0..319]`.

## 11. Required integration tests — I01–I03 plus optional I04

**I01 — Independent pipeline smoke:** compile a fresh entry point including only the relevant resource/map/math/projection/clipping modules, construct a legal synthetic 10-lump map, set a fixed camera, run the full online visible walk, and validate its counters/spans against an independent oracle. No window or legal commercial WAD needed.

**I02 — Occlusion chronology:** construct at least three synthetic subsectors and a valid BSP where the near wall covers the far bbox. Compare: (a) previous full cull-free `BspTraceBuild`, (b) M3-04 online visibility with actual `BboxTests`, `OcclusionSkips>0`, and (c) a no-occlusion control case (near PASS or different camera). The old M3-03 trace remains identical to its prior golden fixture.

**I03 — Lifecycle and failure recovery:** A→B→A synthetic WAD/reload, camera direction change, Build/Reset/rebuild, intentionally corrupt the map or occlusion cap, recover after failure, verify numeric spans/hashes without stale pointers. Validate `WADClose` and source-level reset survival. No invented expected hash; compute from a reproducible independent test oracle.

**I04 — Owner-IWAD, optional/read-only:** when an explicit `data/DOOM.WAD` or supplied legal path exists, process **E1M1, E1M2, E4M1** with a deterministic camera (prefer corresponding player-one THING coordinates/heading as M3-03 I04 did). Confirm `MapLevelLoad`, `MapLevelValidateResources` if catalogs are used, projected ranges, source identity, span bounds, deterministic repeated output, error-free completion and **at least one demonstrably valid occlusion scenario** (synthetic is sufficient; do not invent that a specific real camera must cull). Report aggregate counters and FNV hashes, not WAD contents or coordinates lists. Verify IWAD unchanged. If not provided, I04 `NOT RUN` with exit code 0.

Use the existing scripts' optional `-IwadPath` / `IWAD_PATH` convention rather than introducing a breaking command syntax. New test suite names should follow `-WallClippingTest`, `-WallClippingIntegrationTest`, `-WallClippingIwadTest` or equivalently clear flags on both Windows and Linux scripts.

## 12. Regression, CLI and platform matrix

Mandatory commands (adapt flags to current script syntax only after inspection):

```powershell
# Windows x64 / PureBasic 6.41 — actual verification
./scripts/build.ps1 -Check
./scripts/build.ps1
./scripts/build.ps1 -WallClippingTest
./scripts/build.ps1 -WallClippingIntegrationTest
./scripts/build.ps1 -WallClippingIwadTest
./scripts/test.ps1
./scripts/test.ps1 -IwadPath data/DOOM.WAD   # only with owner-provided local IWAD

# CLI smoke (adjust executable path only if existing build uses another name)
./build/DoomPB.exe --version
./build/DoomPB.exe --help
./build/DoomPB.exe --iwad data/DOOM.WAD --map-info E1M1
./build/DoomPB.exe --iwad data/DOOM.WAD --show-title
```

- Rerun **every existing** M1, M2, M3-01, M3-02 and M3-03 regression suite; do not silently overwrite baseline expectations or weaken assertions.
- Preserve `--version` = `DoomPB 0.2.0` and all previous CLI options and error exit codes. TITLEPIC must still show 960×600 window with 320×200 source if GUI smoke is available; state if a visual check could not be performed.
- Check `scripts/build.sh` and `scripts/test.sh` through `bash -n` if Bash exists. This **does not** count as Linux compile/runtime validation.
- Explicitly distinguish `PASS`, `FAIL`, `NOT RUN` for Windows syntax/build/tests/CLI, Linux syntax/build/runtime and optional IWAD.
- Preserve all copyright/license headers and source/tool attribution. No asset distribution, embedded IWAD samples or hidden test network calls.

## 13. Documentation updates and scope discipline

Update only appropriate existing files (as needed):

- `README.md`: state M3-04 headless projection/occlusion availability; no claim of first rendered wall.
- `CHANGELOG.md`: **Unreleased** M3-04 work, without bumping `0.2.0`.
- `docs/PORTING_NOTES.md`: exact C correspondence, the inverse table's pre-fencepost ordering, clipping invariants, `R_CheckBBox` deferral now resolved for the headless walker, named safety deviations, texture identity policy and benchmark limitations.
- `docs/DEVELOPMENT_PLAN.md`: tick only the portions of M3 really complete. Leave visible textured-wall and release criteria incomplete.
- `scripts/build.ps1`, `build.sh`, `test.ps1`, `test.sh`: integrate test targets and optional IWAD flags while keeping old usage compatible.
- `src/DoomPB.pb`: compile-only `XIncludeFile` of new production modules if it does not trigger unintended startup work. No new CLI command is mandatory.

Avoid modifying original `src/Renderer/BSP.pbi` unless a small backwards-compatible change is essential and independently tested. Do not change any old M3-03 expected full-trace hashes because M3-04 adds a **separate** visible-walk feature.

## 14. Git, whitespace and security acceptance

Before editing and before reporting, inspect:

```bash
git status --short --branch
git diff --stat
git diff --check
git diff --cached --check
git diff --cached --stat
git status --short
```

Also inspect each new **untracked** file for trailing whitespace, mixed newlines and generated content that `git diff --check` cannot see. Follow repository `.gitattributes`, do not add trailing whitespace exceptions. Do not commit `data/`, `build/`, `DOOM.WAD`, source-derived graphics, binaries, screenshots, secrets or vendor documentation.

Do not stage or commit without owner permission. If Git status is not as expected, stop potentially conflicting edits and report; do not reset/clean/rebase to make it look clean.

## 15. Acceptance checklist and reporting template

All of the following are required for `READY FOR OWNER ACCEPTANCE` on Windows x64:

- [ ] M3-03 confirmed committed and pinned C reference inspected.
- [ ] Actual Context7 / official documentation / compiler lookup recorded honestly.
- [ ] Exact original projection mapping and all entries verified via independent oracle.
- [ ] Solid and pass clipping tested with inclusive bounds and safe checked state.
- [ ] `R_AddLine` projects/classifies source segs, preserving original branch behavior.
- [ ] Online near-to-far BSP and `R_CheckBBox` use live solidsegs; at least one positive occlusion test.
- [ ] Original cull-free M3-03 trace stays unchanged.
- [ ] 52 named synthetic tests and I01–I03 all PASS; optional I04 correctly PASS or NOT RUN.
- [ ] Previous tests, main build, CLI smoke and relevant actual Windows PB 6.41 compiler checks PASS.
- [ ] `git diff --check` and audits PASS; no commercial assets or unrelated changes.
- [ ] Docs updated truthfully; version still `0.2.0`, **no** release tag/commit.

Final report (give **measured results**, not placeholders):

```text
Task / milestone: M3-04 only
Git baseline / branch / M3-03 commit verification:
OS / compiler / Linux status:
Original C commit, symbols and relevant deviations:
Documentation lookup: Context7 USED / NO MATCH / UNAVAILABLE / NOT NEEDED; official/local fallback:
Files created / modified:
Projection constants / 4096 + 321 full-array checksums / clipangle:
Solid / pass interval invariants and reference-oracle results:
R_AddLine orientation / FOV / SOLID-PASS-SKIP behavior:
R_CheckBBox online timing / culling-vs-conservative fallback:
WallSpan fields, counts, ownership, limits and lifecycle:
WC01–WC52 cases / assertions / failures:
I01–I03 cases / assertions / failures:
I04 owner-IWAD result, E1M1/E1M2/E4M1 counters and hashes:
Previous regression and script totals (observed):
Syntax check / build / CLI smoke (commands + exit codes):
Linux build/runtime: PASS / FAIL / NOT RUN (reason):
Git diff, whitespace, license and IWAD resource audit:
Known risks and M3-05 prerequisites:
Release decision: READY FOR OWNER ACCEPTANCE / BLOCKED:
Suggested next task:
```

**Success:** deterministic, bounded, headless **screen-space wall intervals with real near-first BSP occlusion**, not a screenshot or rendered frame. Once the owner accepts M3-04, proceed later to **M3-05 — Wall Projection & Solid-Color Columns**. Do not begin it in this task.
