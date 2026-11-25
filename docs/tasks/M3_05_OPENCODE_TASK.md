# DoomPB — M3-05: Wall Projection & Solid-Color Columns

> - **Task ID:** `M3-05`
> - **Milestone:** M3 — Geometry & First Walls (`v0.3.0`, not yet released)
> - **Status:** Implementation assignment; no result or test PASS is implied by this document
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017, Reasoning **High**
> - **Primary development target:** Windows x64, native **PureBasic 6.41**
> - **Linux:** `NOT RUN` until actually compiled and exercised on Linux x64
> - **Repository:** `DoomPB`, development branch `dev`
> - **Pinned primary reference:** `../doom-original/linuxdoom-1.10`, commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Legal:** GPL-2.0-only; no commercial WAD/pixels/screenshots in source or Git
> - **Prerequisites:** accepted/committed M3-01…M3-04, tag `v0.2.0`; verify current Git rather than assuming HEAD
> - **Required reading:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md` (M3), `docs/PORTING_NOTES.md`, this task, and actual code/tests of M3-04.

## 1. Goal and acceptance boundary

Build the **first real, deterministic 320×200 palettized wall frame** using DoomPB's own PureBasic software rendering. Consume the **ordered, occlusion-clipped** `WallSpan` records from M3-04; project wall heights vertically by porting the relevant vanilla Doom `r_segs.c` / `r_main.c` fixed-point calculations; rasterize **solid-color** (not textured) wall tiers into the existing M1 `FrameBuffer`. Provide an opt-in local preview that opens the first wall-only frame of E1M1 without copying commercial art into the repo.

The milestone succeeds only after actual code compilation, passing tests, and a reproducible **nonempty** frame with plausibly projected walls. A trace/hash or a static pre-generated picture is **not** a substitute for runtime wall drawing.

This stage is **not** full `drawseg_t`, the original texturing `R_RenderSegLoop`, flats, ceilings, sky, lighting/COLORMAP, sprites, camera movement, or gameplay. The intentionally false-color preview will have a uniform background and colored wall faces; it is **not** a visually faithful Doom frame yet. Textured columns are M3-06; M3 release is M3-07. Keep application version `0.2.0`.

### Concrete scope

- True horizontal projection and occlusion were implemented in M3-04. **Do not duplicate** `R_AddLine`, `R_CheckBBox`, BSP, `solidsegs`, or the forward/inverse angle tables.
- New work: view height (`viewz`), wall distance, scale at first/last column, fixed-point scale stepping, front/back height offsets, vertical top/bottom edges, tier classification, column clipping, direct framebuffer drawing, deterministic frame diagnostics and an explicitly requested preview mode.
- Use the existing `FrameBuffer.pbi`/`Video.pbi` (320×200 indices and M1 palette presentation). Do not introduce SDL, a graphics engine, image generation, GPU shaders, or runtime trig.
- `WallVisibilityBuild` remains the authoritative source of ordered visible `WallSpan` data, including `FirstX`/`LastX` **inclusive** and associated map IDs. It must remain behaviorally unchanged and pass M3-04 golden tests.
- Document deliberate non-rendering omissions rather than pretending the original `R_StoreWallRange`/`drawseg_t` pipeline was fully ported.

## 2. Start-up audit (mandatory before editing)

1. `git status --short --branch`, `git log -5 --oneline`, `git tag --list`; confirm M3-04 actually committed and no unexpected staged work. Preserve all user changes.
2. Read the project's files, **not merely descriptions**:
   - `src/Renderer/WallVisibility.pbi` (`WallVisibilityBuild`, `WallVisibilityGetSpan`, `WallVisibilityGetStats`, `WallSpan`).
   - `src/Renderer/Projection.pbi`, `ClipSegs.pbi`, `Camera.pbi`, `BSP.pbi`, `Geometry.pbi`.
   - `src/Core/Fixed.pbi`, `Angle.pbi`, `TrigTables.pbi`, `TrigTablesData.pbi`.
   - `src/Map/MapLevel.pbi`, `MapDecode.pbi`, `MapTypes.pbi`.
   - `src/Graphics/FrameBuffer.pbi`, `Palette.pbi`, `Video.pbi`.
   - `src/DoomPB.pb` CLI and `scripts/{build,test}.{ps1,sh}`.
3. Examine pinned C source and its real declarations/callers: `r_segs.c` (`R_StoreWallRange`, `R_RenderSegLoop`; `HEIGHTBITS=12`), `r_main.c` (`R_ScaleFromGlobalAngle`, `R_SetupFrame`), `r_bsp.c` (`R_AddLine`, `R_ClearDrawSegs`, `R_Subsector`), `r_defs.h` (`drawseg_t`), `r_state.h`, `r_draw.c`, `r_plane.c` (ceiling/floor clipping defaults), `p_mobj.c` (`P_SpawnPlayer`), `p_local.h` (`VIEWHEIGHT=41*FRACUNIT`). Record exact names/ranges, not guessed APIs.
4. Comply with **Context7 policy in AGENTS.md**. Query configured Context7 for relevant PureBasic API details when available; be explicit if `/websites/purebasic` is not an exact 6.41-specific index. Official docs and installed 6.41 CHM/compiler probes are fallback. Never claim a Context7 lookup without actually using it.
5. Present a short implementation plan, main invariants, affected files and independent tests before writing production code.

## 3. Reference C semantics that must guide the implementation

### 3.1 `R_ScaleFromGlobalAngle` (`r_main.c`)

Use the actual source algorithm, including **BAM unsigned wrap**, `finesine` indices, and saturations. In C pseudocode (explanatory, not copy-paste PB):

```text
anglea = ANG90 + (visangle - viewangle)     // modulo 2^32
angleb = ANG90 + (visangle - rw_normalangle)
sinea  = finesine[anglea >> ANGLETOFINESHIFT]
sineb  = finesine[angleb >> ANGLETOFINESHIFT]
num    = FixedMul(projection, sineb) << detailshift   // detailshift = 0 here
den    = FixedMul(rw_distance, sinea)
if den > (num >> 16):
    scale = FixedDiv(num, den)
    clamp scale to [256, 64*FRACUNIT]
else:
    scale = 64*FRACUNIT
```

The shifted indices should be proved valid for spans admitted by the M3-04 viewport; **do not mask away** out-of-domain values in a way that hides defects. Use checked arithmetic / explicit wrap consistent with M3-01/02. Do not replace the algorithm with `projection/distance` or floating-point `cos`.

`Projection.pbi` already fixes the classic view to **320×200**, `centerx=160`, `centery=100`, `centerxfrac=160*FRACUNIT`, `detailshift=0` and `projection=centerxfrac`. Reuse those constants/accessors; don't create another drifting projection table.

### 3.2 Initial wall distance and scale (`R_StoreWallRange`)

For each emitted `WallSpan`, resolve its `Seg`, sidedef, linedef and front/back sectors using the validated MapLevel APIs. Read the segment's stored angle as a 16-bit vanilla value with the **verified** encoding convention; do not confuse its raw map angle with BAM. The normal is `rw_normalangle = segangle + ANG90`. The reference angle `rw_angle1` is the original view-to-seg-v1 angle (before FOV clipping) and **must be recomputed** from the original v1 for this calculation, not inferred from the truncated span endpoints.

```text
rw_normalangle = segangle + ANG90
absolute offsetangle = angular separation of rw_normalangle and rw_angle1
clamp offsetangle to ANG90
distangle = ANG90 - offsetangle
hyp = R_PointToDist(seg.v1.x, seg.v1.y) relative to camera
distance = FixedMul(hyp, finesine[distangle >> 19])
scale1 = R_ScaleFromGlobalAngle(viewangle + xtoviewangle[firstX])
scale2 = R_ScaleFromGlobalAngle(viewangle + xtoviewangle[lastX])
if lastX > firstX:
    scaleStep = (scale2-scale1)/(lastX-firstX)  // C integer truncates toward zero
else:
    scaleStep = 0; scale2 = scale1             // deterministic 1-column policy
```

**Careful:** `r_segs.c` declares `rw_normalangle`, `rw_angle1` and original `angle_t` values, with 32-bit wrap and `abs` usage that may be undefined for `INT_MIN`. Adopt explicit documented safe behavior for these edges; do not silently change ordinary supported cases. `R_PointToDist` at coincidence and near-zero distances requires a checked policy. In particular, never divide by zero or index outside a table. Clamp only where original explicitly clamps; if an exceptional geometry case is unsupported, return a reproducible diagnostic without corrupting the frame.

### 3.3 Height projection (`r_segs.c`)

Vanilla uses 16.16 world heights and a **12-bit vertical interpolation domain**:

```text
worldtop    = front.ceilingheight - viewz
worldbottom = front.floorheight - viewz
worldhigh   = back.ceilingheight - viewz   // when back exists
worldlow    = back.floorheight - viewz

HEIGHTBITS = 12; HEIGHTUNIT = 4096
worldtop >>= 4; worldbottom >>= 4      // original downshift; not float /16
 topstep  = -FixedMul(scaleStep, worldtop)
 topfrac  = (centeryfrac >> 4) - FixedMul(worldtop, scale1)
 bottomstep = -FixedMul(scaleStep, worldbottom)
 bottomfrac = (centeryfrac >> 4) - FixedMul(worldbottom, scale1)

for x in [firstX..lastX]:
    yl = (topfrac + HEIGHTUNIT - 1) >> HEIGHTBITS  // ceil edge
    yh = bottomfrac >> HEIGHTBITS                 // floor edge
    clamp yl/yh with ceilingclip[x], floorclip[x]
    draw only inclusive y-range(s) that really belong to wall tiers
    scale += scaleStep; topfrac += topstep; bottomfrac += bottomstep
```

For two-sided walls, follow original `pixhigh/pixlow` edge calculations and rounding/tie rules for upper and lower tiers. Port necessary parts of `R_RenderSegLoop` **without** sampling WAD texture pixels. Preserve shared clipping semantics: `ceilingclip[x]` starts `-1`, `floorclip[x]` starts `viewheight=200`. A one-sided middle wall closes the column (`ceilingclip[x]=200`, `floorclip[x]=-1`) after drawing; two-sided tiers update only the proper boundary. Do **not** fill pass-through portal openings with a solid rectangle.

Sky special case: vanilla adjusts front `worldtop` if **both ceiling flats are `F_SKY1`**. Reproduce the geometry boundary rule where its references can be safely resolved; do not draw sky itself (M4). `ceilingplane`, `floorplane`, `R_CheckPlane`, `R_AddSprites`, masked midtextures, lighting and sprite silhouettes are outside M3-05; document their absence. For absent/invalid wall texture names, use M2/M3-04 validated catalog semantics and explain whether the **debug geometry** is drawn or omitted: don't silently confuse `'-'` with a valid texture.

### 3.4 Renderer ordering and limitations

`WallVisibilityBuild` returns visible fragments **in near-to-far processing order** after live BSP/solid clipping. Draw fragments in that order and use per-column vertical clipping to preserve front/back tier interactions. **Never** sort spans globally by distance, x, seg ID, or sector. `WallSpan.Kind` identifies `SOLID` vs `PASS` **occlusion classification**, not necessarily the number of upper/lower/middle tiers. A PASS fragment is not a transparent wall surface; it can contain visible upper/lower tiers while leaving a portal hole.

The M3-04 first/last X coordinates are inclusive. Endpoints `0`, `319` and `firstX==lastX` are valid. Bounds-check X/Y and all buffer lengths before writing. Do not allow writing past 64,000 bytes of framebuffer pixels.

## 4. Suggested modules and ownership/API design

Follow current project conventions and adapt names only after inspecting existing APIs; document actual names in the report. Suggested additions:

| File | Purpose / boundary |
|---|---|
| `src/Renderer/WallProject.pbi` | Stateless checked distance/scale/height calculations; testable without WAD or window |
| `src/Renderer/WallDraw.pbi` | Bounded solid-color vertical spans into `FrameBuffer` and two clipping arrays |
| `src/Renderer/RenderMain.pbi` | Frame orchestrator: validated level + camera + viewz + existing visibility + render result |
| `tests/unit/wall_projection_tests.pb` | WP01–WP56 unit cases |
| `tests/integration/m3_wall_render_tests.pb` | WI01–WI03 synthetic integrated frames |
| `tests/integration/m3_wall_render_iwad_tests.pb` | Optional WI04 real IWAD and preview-data checks |
| `scripts/gen_wall_projection_golden.py` | Independently computed small synthetic numeric golden fixture; deterministic generation |
| `tests/fixtures/m3_wall_projection_golden.pbi` | Numeric-only reference values/hashes; **no game assets** |

If fewer files are more maintainable, consolidate responsibly. Do not write source not needed for M3-05; no renderer-side column cache or replacement of M2 texture composition.

### 4.1 Camera, view height, and static player start

`BspCamera` from M3-03 owns only `X.l`, `Y.l`, `Heading.q`. **Do not silently mutate its meaning or break camera tests.** Define a separate checked view-height parameter or a new renderer-specific wrapper (e.g. `WallView {Camera.BspCamera, ViewZ.l}`). `ViewZ` is signed **16.16**, not raw map units. Allow explicit viewz for unit tests. When deriving from an owner IWAD, locate player-one THING (`type=1`) and its floor sector using a bounded point-in-subsector walk with existing `GeometryPointOnNodeSideChecked` and `MapLevelGetBspRoot` (or another demonstrably correct existing location helper). A zero-node/one-subsector root is supported. `viewz = floorheight*FRACUNIT + 41*FRACUNIT`, validated against `.l` range; the **41** comes from `VIEWHEIGHT` in `p_local.h`. Player heading follows the original `ANG45 * (thing.angle / 45)` integer-quantization convention in `p_mobj.c`; do not approximate with runtime trig. Report the camera coordinates/heading only if appropriate for local logs; no raw lump copying.

If player-one THING is absent, duplicated ambiguously, outside valid BSP coordinates, or viewz overflows, fail with a specific diagnostic. Never guess floor=0, spawn heading, or a sector index to force an image. The preview may also support caller-specified fixed camera state as a test API; avoid unnecessary CLI expansion.

### 4.2 Result and framebuffer contracts

- Framebuffer stays **320×200, row-major, 8-bit palette indices**. Reuse `FrameBufferCreate/Reset/Clear/GetPixel` and `VideoShowFramebuffer` rather than inventing an image layout.
- Stable **debug palette-index contract** with distinctive values for background, one-sided/middle, upper and lower wall faces. Choose non-overlapping indices and document values; no COLORMAP/lighting dependency. No copyrighted source pixels are copied to the frame in this stage, though optional local presentation may use the user's PLAYPAL to display the indices.
- A result may own compact `WallDrawSegment`/drawseg-like numeric metadata (`x1`, `x2`, `scale1`, `scale2`, `scaleStep`, segment and sector references). Do **not** claim a complete vanilla `drawseg_t`: silhouette/masked/sprite clipping fields are still pending. Cap allocations/work using checked `.q` size arithmetic. No allocation per column.
- Build **transactionally**. Prefer a temporary 64 KB framebuffer plus staging metadata; on error leave the caller's existing valid frame untouched, reset temporary owned allocations, and return a precise error. Successful render replaces the prior frame and clears stale diagnostics. Multiple render/reset cycles must not leak, double-free or retain stale level/WAD pointers.
- Expose read-only diagnostics: input span count, processed columns, middle/upper/lower drawn pixels, clipped/empty columns, draw-range count, emitted wall metadata and deterministic frame hash. Distinguish **zero rendered pixels** (failure on an expected visible fixture) from a valid intentionally empty synthetic scene.
- Frame hash: FNV-1a64 over **exact 64,000 row-major palette bytes**, with explicit canonical byte order, then emit fixed-width uppercase 16 hex digits; do not hash memory addresses, padding or metadata that changes between processes. Keep separate metadata hash if useful.
- Never permanently cache `*Level` pointers in draw records intended to outlive `MapLevelReset`; copy numeric IDs and values only.

## 5. Minimal preview CLI / GUI mode

Add an **opt-in** command without changing existing CLI semantics:

```text
DoomPB --iwad data/DOOM.WAD --show-walls E1M1
```

- Validate argument counts and map identifier exactly like existing `--map-info`; preserve existing exit codes: 0 success, 1 load/render/runtime error, 2 usage/conflicting arguments.
- Read local IWAD and necessary `PLAYPAL`/M2 catalogs using existing loaders and validators. No implicit WAD opening on no-arg startup; no network use.
- Use static player-one starting camera (section 4.1) and generate **new pixels** through M3-05 software renderer; display via `VideoShowFramebuffer` at existing 3x nearest-neighbor presentation (source 320×200, client 960×600). Title must explicitly say **wall-only / debug colors / M3-05** so nobody mistakes it for a completed game.
- The frame can be prepared before opening the window. Closing the window exits normally and releases resources. The GUI smoke test may close via `WM_CLOSE` as in M1; distinguish verified process/window test from manual **visual inspection** and from a screenshot. **Do not fabricate a screenshot or claim visual PASS based only on a console hash.**
- Preview E1M1 is mandatory when owner IWAD and graphical desktop are available. E1M2/E4M1 should render for integration and may use the same CLI when practical. If no licensed IWAD/GUI, still run all synthetic headless tests and report optional preview `NOT RUN` instead of pretending it passed.
- Never commit a preview capture, copied WAD bytes, RGBA extraction, PNG, BMP, or game art. A local temporary capture for owner inspection is allowed only if kept outside Git and not distributed.

### Smoke test commands (adjust to actual script interface)

```powershell
./scripts/build.ps1 -Check
./scripts/build.ps1
./scripts/test.ps1
./scripts/test.ps1 -IwadPath data/DOOM.WAD
./build/DoomPB.exe --version
./build/DoomPB.exe --iwad data/DOOM.WAD --map-info E1M1
./build/DoomPB.exe --iwad data/DOOM.WAD --show-title
./build/DoomPB.exe --iwad data/DOOM.WAD --show-walls E1M1
```

## 6. Required unit test matrix: WP01–WP56

Create **56 separately reported test cases**, not merely 56 assertions. Every case must be deterministic, compiler-executed and assert concrete independently derived values/semantics. Suggested allocation:

| ID | Required test |
|---|---|
| WP01 | Constants: 320×200, 16.16 and `HEIGHTBITS=12`; source-to-port correspondence |
| WP02 | Basic checked view-height setter/getter and reset without WAD |
| WP03 | `viewz` conversion from signed map floor plus 41 units; 64-bit overflow checks |
| WP04 | Negative floor/ceiling/viewz differences, correct sign and shift behavior |
| WP05 | BAM `rw_normalangle=segangle+ANG90`, signed vs raw unsigned transport |
| WP06 | Map SEGS raw 16-bit angle → BAM conversion; 0,90,180,270 and wrap |
| WP07 | Original v1 angle, not FOV-truncated span endpoint, drives distance |
| WP08 | Angular separation/`offsetangle` wrap near 0/180/360 |
| WP09 | `distangle` clamp at ANG90 with exact boundary equality |
| WP10 | `GeometryPointToDistChecked` (hyp) and `FixedMul` distance golden values |
| WP11 | Coincident/near-zero vertex distance: deterministic safe diagnostic |
| WP12 | Positive and negative coordinate pairs, all four cardinal facings |
| WP13 | `R_ScaleFromGlobalAngle` ordinary fixed-point reference vectors |
| WP14 | Scale lower clamp at 256 |
| WP15 | Scale upper clamp at 64*65536 |
| WP16 | `den > num>>16` strict-comparison branch, including equality |
| WP17 | Valid sine/tangent indices with exact table values and bounds |
| WP18 | `viewangle + xtoviewangle[0]` correct leftmost BAM wrapping |
| WP19 | Same for x=319; no off-by-one inverse lookup |
| WP20 | Full one-span `[0,319]` start/end scale and step golden record |
| WP21 | Single-column `[x,x]`: `scale1==scale2`, `scaleStep=0` |
| WP22 | Two-column span: C division truncation in signed scaleStep |
| WP23 | Long span fixed-step accumulation equals independent column oracle |
| WP24 | Ceiling edge formula: topfrac 12-bit ceil rounding (positive) |
| WP25 | Ceiling edge negative values and arithmetic right shift |
| WP26 | Floor edge formula: bottomfrac 12-bit floor rounding |
| WP27 | Exactly equal edge/tie and zero-height face handling |
| WP28 | Height near renderer/INT32 limit, no silent overflow/UB |
| WP29 | `ceilingclip=-1`, `floorclip=200` initialization on each frame |
| WP30 | One-sided middle wall writes correct inclusive vertical pixels |
| WP31 | One-sided wall closes column clip after drawing |
| WP32 | Two-sided portal with same heights leaves wall center empty |
| WP33 | Two-sided upper wall when back ceiling is lower |
| WP34 | Two-sided lower wall when back floor is higher |
| WP35 | Both upper and lower tiers in one column; visible opening remains |
| WP36 | Closed door / `backceiling<=frontfloor` geometry |
| WP37 | Opposite closed door / `backfloor>=frontceiling` geometry |
| WP38 | Sky-to-sky `worldtop=worldhigh` boundary special case |
| WP39 | `F_SKY1` one-sided/two-sided mismatch should not trigger sky hack |
| WP40 | Absent `'-'` wall texture slot; no invented source pixels |
| WP41 | Catalog-resolved middle/top/bottom slot semantics and sentinel handling |
| WP42 | Per-column vertical clipping prevents overwriting nearer tier pixels |
| WP43 | PASS type does not fill portal opening or solid-occlude full screen |
| WP44 | `firstX=0,lastX=319` and bottom row y=199 safely writable |
| WP45 | Invalid negative/out-of-range X rejected, no buffer mutation |
| WP46 | Invalid Y range/empty interval safely clipped/skipped |
| WP47 | Distinct stable debug indices for middle/upper/lower/background |
| WP48 | FrameBuffer row-major direct byte checks and `GetPixel` agreement |
| WP49 | Exact 64,000-byte FNV-1a64 hash repeated twice |
| WP50 | Different headings or viewz produce differing justified frame hashes |
| WP51 | Input span ordering preserved, no sorting or mistaken deduplication |
| WP52 | Corrupt level indices, unready camera/projection and null result rejected |
| WP53 | Transactional frame result: failed build leaves previous frame unchanged |
| WP54 | Repeated render/reset/load cycles and valid buffer ownership |
| WP55 | No allocation in per-column hot path; counters/limits checked |
| WP56 | Independent original-C/Python numeric oracle agrees at sample columns |

Give each WP case a failure message that identifies camera, seg, x/y, reference value and observed value as relevant; avoid dumping game assets. Where a synthetic fixture intentionally triggers an unsupported arithmetic edge, assert the documented failure/diagnostic, not a fabricated Doom-equivalent output.

## 7. Integration tests WI01–WI04

### WI01 — Minimal single-sector synthetic WAD (no commercial files)

Create/extend a small valid **ten-lump** synthetic WAD or a validated synthetic `MapLevel`, one-sided visible wall, explicit camera and viewz. Run `MapLevel` → `WallVisibilityBuild` → `WallProject` → `FrameBuffer`. Assertions: nonzero drawn wall pixels, bounding row/column controls, frame hash from an **independent** golden reference, repeated-build identity; no background-only false PASS. Test one-column and wide segments.

### WI02 — Two-sided and partially occluded synthetic room

Build a scene with front solid wall, farther portal/upper/lower tiers and overlapping screen ranges. Compare ordered `WallSpan` IDs/X intervals against M3-04 golden data and rendered upper/lower/middle rows against independent per-column expected rows. Far wall must not paint over near wall; portal opening stays background until a farther valid wall fills it. Test tiny wall and boundary at y=0/199.

### WI03 — Errors, reinitialization, lifetime and end-to-end CLI

Induce malformed map references, near-zero division, invalid viewz, allocation/work cap, invalid pixel coordinates, missing palette, repeated WAD A→B→A and reuse of caller frame. Check transactional recovery and deterministic noncommutative hashes. Keep old commands `--show-title`, `--map-info`, `--lump-info`, `--dump-info`, `--version`, `--help` and the no-argument path unchanged.

### WI04 — Optional owner's Ultimate Doom 1.9ud

Only with owner-provided local legal `data/DOOM.WAD` (read-only; known identification MD5 `c4fe9fd920207691a9f493668e0a2083`; 12,408,292 bytes; 2306 lumps). Exercise E1M1/E1M2/E4M1 and at least player-one spawn for each map. Require:

- Verified M2 resource catalogs, `MapLevelValidateResources`, M3-04 `WallVisibilityBuild` and **nonzero** visible spans.
- Actual painted pixel counts >0; at least two distinctive palette indices including background; stable frame hash over 320×200; repeated independent invocations agree. Check no out-of-bounds/heap problems and no WAD modification.
- Preserve M3-04 **span/counter hashes** where the same camera/catalog conditions apply; if they differ, investigate and document rather than silently changing M3-04 tests. Known M3-04 owner-IWAD span hashes for its previous camera setup: E1M1 `74B485154CE29B0B`, E1M2 `8AC0627513C4B619`, E4M1 `9FD0B15A0F33197E`; camera equivalence must be verified before using as goldens.
- New frame-hash expected values are **not supplied here**. Derive independently from pinned C-equivalent math/synthetic checks and real compiled renderer, document the derivation, then lock as tests. Do not invent hashes or simply copy a faulty program's first output into an expected fixture.
- If desktop GUI available, open `--show-walls E1M1` and visually confirm walls vs blank/color block, wrong-side perspective and column artifacts; report exactly what was observed. Window-smoke without visual inspection is a separate weaker status.
- If IWAD not present, report WI04 `NOT RUN`; other three tests remain mandatory.

## 8. Independent reference and hash policy

1. A small Python golden generator may parse **numbers only** from pinned C tables, or compute independent integer formulas for synthetic shapes. Its expected values must not be sourced from the new PB renderer's own output.
2. Where the original C arithmetic relies on implementation-defined behavior, document a fixed-width PB policy consistent with M3-01/02; cross-check normal inputs with a separately compiled minimal C oracle when possible. No `Sin`, `Cos`, `sqrt` or floating-point replacement in production.
3. Verify fixed-point rounding precisely: negative arithmetic `>>`, two's-complement 32-bit wrap, threshold comparisons, height ceil/floor boundaries, and C integer divide truncation toward zero.
4. Use a canonical row-major FNV-1a64 over **palette indices**, not RGBA, pointer data, structures, debug strings or GUI pixels. State FNV offset/prime and byte-feed order. Keep 16-digit uppercase hex, including leading zeros.
5. A reference picture or screenshot can be used locally by the owner for inspection; **never copy commercial pixels into committed fixtures**. Synthetic numeric fixtures and hashes are safe to track.
6. Avoid accidental regression: after modifying the generator, rerun it and verify identical output without Git diff or timestamp-only updates.

## 9. Script integration and full regression

Add explicit `build.ps1` / `build.sh` targets such as `-WallProjectionTest`, `-WallRenderIntegrationTest`, `-WallRenderIwadTest` and equivalent `--wall-projection-test` / `--wall-render-integration-test` / `--wall-render-iwad-test`; use the project's actual conventions. Update `test.ps1` / `test.sh` to run new compiled harnesses after all existing suites. Optional `-IwadPath` or `IWAD_PATH` should invoke WI04 only when the owner supplied a path.

**Last accepted M3-04 baseline from the owner's audit (not a predicted M3-05 result):**

| Mode | Cases | Assertions | Failures |
|---|---:|---:|---:|
| All synthetic/no owner IWAD | **570** | **4,049** | 0 |
| With optional owner-IWAD tests (replace rather than double-count M2 integration mode) | **575** | **4,291** | 0 |
| `scripts/test.ps1 -IwadPath data/DOOM.WAD` checks | **138/138** | — | 0 |

**Do not repeat old incorrect M3-04 totals** (`610/3,869` or `615/4,111`) or double-count M2 synthetic + owner modes. New expected totals are to be computed **from executable output**, not guessed by hand.

Required checks:

- `pbcompiler src/DoomPB.pb --check` real Windows 6.41 compiler: command/exit/output.
- All newly touched/new harness syntax checks, real builds and execution: command/exit and observed `cases/assertions/failures`.
- Full existing test suite + CLI smoke, with and without owner IWAD; include `--show-walls` window smoke and manual visual status separately.
- `bash -n scripts/build.sh scripts/test.sh` when Bash available; Git Bash syntax is **not** Linux compilation. Linux executable/runtime `NOT RUN` unless verified on Linux x64 with installed PureBasic.
- WAD input is read-only. No per-pixel GUI interaction required for headless suites. No new toolchain dependency or silently broken Linux script switches.

## 10. Documentation and implementation boundaries

Update `README.md`, `CHANGELOG.md` (under `Unreleased` M3-05; **do not release 0.3.0**), `docs/DEVELOPMENT_PLAN.md` M3 status, and `docs/PORTING_NOTES.md` with:

- Correspondence between original C symbols and new PureBasic helpers, with upstream commit.
- Mathematical derivation, fixed-point/12-bit rounding, explicit edge handling, optional debug-tier color policy, sky boundary caveat, missing texture policy.
- Ownership/lifetime for framebuffer, ordered spans and draw records; GUI-only vs headless behavior.
- Actual observed hashes, test totals and Windows build status; Linux runtime `NOT RUN` if not tested.
- Precisely what's missing: texture columns, light tables/COLORMAP, visplanes/flats, sky drawing, sprites, movement/gameplay, complete vanilla `drawseg_t`.

No unrelated refactor of M1/M2/M3-01…04. Preserve 6.41 syntax and user modifications. Keep generated binaries, temporary screenshots, user IWAD and absolute local paths out of Git. Inspect license of any imported code and preserve attribution.

## 11. Final checks and owner handoff

Run, at minimum:

```powershell
git status --short --branch
./scripts/build.ps1 -Check
./scripts/build.ps1
./scripts/test.ps1
./scripts/test.ps1 -IwadPath data/DOOM.WAD   # if the owner's IWAD is available
git diff --check
git diff --stat
git diff --cached --check
git status --short
```

Check **new untracked text** for trailing spaces/tabs and blank lines at EOF (not covered by `git diff --check` until staged); normalize LF where repository policy permits. Verify that the generated golden fixture is deterministic, and that `data/`, `build/`, commercial WAD and screenshot outputs remain ignored. If someone else has staged content concurrently, preserve it and report the unexpected index state rather than updating or removing it silently.

**No `git add`, `commit`, `push`, or tags** unless the owner explicitly authorizes those operations. If a blocker remains, say `BLOCKED` and do not claim success; otherwise `READY FOR OWNER ACCEPTANCE`. M3-06 is not part of this task.

### Required final report template

```text
Task/milestone: M3-05 only; READY FOR OWNER ACCEPTANCE / BLOCKED
Git branch, HEAD and M3-04 commit status; staged/unstaged/untracked state:
Windows OS, exact PureBasic 6.41 version; Linux: PASS/FAIL/NOT RUN:
Original pinned C commit, files and symbols inspected:
Documentation lookup: Context7 USED / NO MATCH / UNAVAILABLE; official/CHM/compiler fallback:
Files created/changed (production, tests, scripts, docs):
Math: normal angle, distance, scale1/scale2/step, height interpolation; exact edge policies:
Camera/viewz/player-one floor lookup and BAM heading:
Wall tiers, PASS holes, per-column clipping, debug colors, unchanged M3-04 input:
Ownership, rollback, memory limits, allocations per column:
WP01–WP56: real cases/assertions/failures:
WI01–WI03: real cases/assertions/failures:
WI04: PASS/FAIL/NOT RUN; maps, drawn pixels, frame hashes, repeatability:
GUI preview: process/window smoke and manual visual check, clearly separated:
Independent golden oracle and checksum derivation:
Earlier regression suites and new cumulative totals, without/with owner IWAD:
Full build/test script checks, commands and exit codes:
CLI --version/--help/--show-title/--map-info/--show-walls exit codes:
Git diff, cached/untracked whitespace audit, resources/licensing audit:
Known deviations/limitations, Linux gap and next M3-06 prerequisites:
No commit/stage/push/tag; version still 0.2.0:
```

**Final objective:** a real, locally viewable **wall-only E1M1 scene** in DoomPB's own 8-bit framebuffer, with numeric and framebuffer regression evidence, while every prior test continues to pass.
