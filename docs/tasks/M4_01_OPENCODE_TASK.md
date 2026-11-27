# DoomPB — M4-01: Visplanes, textured floors & ceilings

> **Task:** `M4-01` · **Milestone:** M4 — Full Software Renderer (`v0.4.0`, not started/released)
> **Agent:** OpenCode Desktop · DeepSeek V4.1 Flash 1017 · Reasoning High
> **Target:** native PureBasic **6.41**, Windows x64; Linux x64 `NOT RUN` unless actually built/executed there
> **Project:** DoomPB · GPL-2.0-only · owner-provided commercial IWAD stays local and ignored
> **Reference:** `../doom-original/linuxdoom-1.10`, pinned `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> **Prerequisite:** M3-07 accepted and `v0.3.0` committed/tagged by the owner; independently verify Git state
> **Status:** implementation specification, **not evidence that code/tests have been run**

## 1. Mission and exact scope

Implement the first part of Doom's **visplane** world rendering: collect floor/ceiling visible intervals during the **same ordered BSP/wall pass**, merge/split visplanes using the original rules, convert intervals into horizontal row spans, sample 64×64 `FLAT` resources using vanilla fixed-point texture mapping, apply original distance/sector `zlight` via the already decoded `COLORMAP`, and draw them into a **320×200 palettized framebuffer** after the wall pass.

Provide a new **opt-in static preview** showing the **existing real textured walls plus actual floor and ceiling flats** in E1M1, E1M2 and E4M1, without changing the old `--show-walls` or `--show-textured-walls` outputs. As in M3, derive the camera from the canonical player-one THING, and display at 3× nearest-neighbour. The new mode should make the previous black floor/ceiling regions into real surfaces where a non-sky visplane is present.

**Important:** This is not a "paint nonzero/black gaps" post-process. The original `r_bsp.c:R_Subsector` selects `floorplane` and `ceilingplane` before processing its segs, `r_segs.c:R_StoreWallRange` invokes `R_CheckPlane`, and `R_RenderSegLoop` marks plane rows **before it updates** `ceilingclip`/`floorclip`. An implementation derived only from the final framebuffer, or only from an unordered collection of emitted `WallSpan` objects, cannot meet this contract. Reuse/extend the existing **online** M3-04 traversal and M3-06 textured-column pipeline, preserving the exact order of subsector, seg, clipping, wall and plane side effects.

### Explicit non-goals

- **No rendered sky** in M4-01. Recognize and collect `F_SKY1` visplanes, normalize their identity as Doom does, but leave their pixels untouched/background and report `SkyDeferred`; sky drawing/`skytexture` is M4-02. Do not sample `F_SKY1` as an ordinary 64×64 flat or conceal missing sky with another flat.
- No masked two-sided middle texture back-to-front pass, sprites, weapon overlay, full vanilla `drawseg_t`, HUD, animation/flat translations, scrolling sectors, gameplay/physics, moving camera, sound, or engine loop.
- No low-detail render mode, arbitrary viewport resizing or general graphics backend rewrite: canonical **320×200**, full-detail, static view; presentation is 960×600 nearest-neighbour.
- No PWAD overlays, multi-IWAD cache shortcuts, new third-party runtime, SDL/GPU renderer or floating-point replacement of vanilla projection math.
- **No release/version change**: `--version` must remain `DoomPB 0.3.0`; do not create `v0.4.0`, commit, tag or push.

## 2. Required reading and first actions

Read the actual current checkout, not only the previous session summary:

1. `AGENTS.md` (especially Context7, original-code fidelity, licensing, Git and whitespace rules).
2. `docs/DEVELOPMENT_PLAN.md` M3/M4; `docs/PORTING_NOTES.md`; `README.md`; `CHANGELOG.md`.
3. `src/Core/Fixed.pbi`, `Angle.pbi`, `TrigTables.pbi`; `src/Renderer/Geometry.pbi`, `Camera.pbi`, `Projection.pbi`, `BSP.pbi`, `ClipSegs.pbi`, `WallVisibility.pbi`, `WallView.pbi`, `WallProject.pbi`.
4. `src/Renderer/TexturedWallDraw.pbi`, `TexturedRenderMain.pbi`, `WallTextureMapping.pbi`, `WallTextureCache.pbi`, `WallLighting.pbi`, legacy `WallDraw.pbi` and `RenderMain.pbi`.
5. `src/Graphics/Flat.pbi`, `Colormap.pbi`, `Palette.pbi`, `FrameBuffer.pbi`, `Video.pbi`; map/sector/sidedef/seg access in `src/Map/`; `src/DoomPB.pb`.
6. `scripts/build.ps1`, `build.sh`, `test.ps1`, `test.sh`; existing M3-04/M3-05/M3-06/M3-07 test suites and synthetic fixtures.
7. The *pinned original C* references in §3, plus the exact implementation of `R_Subsector` and `R_RenderPlayerView` for call ordering.

Before editing, record the actual output of:

```powershell
 git status --short --branch
 git log -6 --oneline
 git tag --list
 git describe --tags --exact-match 2>$null
 .\build\DoomPB.exe --version
```

Verify the **actual** `v0.3.0` release commit/tag (or report any discrepancy), index/worktree state, and pre-existing owner task file. Never overwrite concurrent edits, reset, clean, rebase or stage without authorization. If the baseline is different, adapt only after describing it. Present a short API inventory and implementation plan before coding.

### Documentation lookup: Context7

Use the configured Context7 MCP *for unfamiliar/version-sensitive PureBasic and external APIs*, with actual resolve/query calls where appropriate (candidate `/websites/purebasic` is **not** evidence of an exact PureBasic 6.41 match). Useful focused topics: typed memory, pointers, arrays, `AllocateMemory`, `FreeMemory`, `CopyMemory`, `PeekA`, `PokeA`, compiler guards and window/bitmap APIs. When Context7 lacks an exact reliable match, fall back to official documentation, local PureBasic 6.41 CHM/help and tiny disposable compile/run probes. **Pinned Doom C is authoritative for engine formulas.** Do not send IWAD bytes, pixels, credentials or private filesystem paths to remote docs tools. In the report use `Context7 USED (actual library ID/topic)`, `NO MATCH`, `UNAVAILABLE` or `NOT NEEDED` truthfully.

## 3. Pinned original Doom correspondence

| Original file and symbols | Required observation / preservation |
|---|---|
| `r_bsp.c:R_Subsector` | Enter subsector, choose `floorplane` when floorheight `< viewz`; choose `ceilingplane` when ceilingheight `> viewz` **or** its pic is the sky; then handle ordered segs. No plane for wrong-side ordinary surface. |
| `r_bsp.c:R_RenderBSPNode` | Near side first, conditional far side after the current occlusion state; M3-04 implementation must remain the visibility authority. |
| `r_segs.c:R_StoreWallRange` | `R_CheckPlane` for current floor/ceiling before entering `R_RenderSegLoop`; `markfloor`/`markceiling` decisions, sky-hack and wrong-side checks. |
| `r_segs.c:R_RenderSegLoop` | Compute `yl/yh` and mark `top[x]`, `bottom[x]` **before** per-tier clip mutations; same ceiling/floor clip arrays; inclusive ranges. |
| `r_plane.c:R_ClearPlanes` | Initialize `ceilingclip=-1`, `floorclip=viewheight`; reset visplanes; `cachedheight`; compute `basexscale/baseyscale` for heading. |
| `r_plane.c:R_FindPlane` | Key `(height,picnum,lightlevel)`; for sky normalize `height=0, lightlevel=0`; initial `top=0xFF`, `minx=320`, `maxx=-1`. |
| `r_plane.c:R_CheckPlane` | Intersection/union bounds; extend existing plane iff overlap `top` is unset; otherwise **split into new visplane with the same key**. |
| `r_plane.c:R_MakeSpans` | Close/open horizontal spans from adjacent columns' top/bottom; proper `x-1`, `minx-1` and `maxx+1` sentinel handling. |
| `r_plane.c:R_MapPlane` | Exact fixed-point distance/steps/start texel coordinates and row-specific `zlight` selection; row cache keyed by plane height. |
| `r_plane.c:R_DrawPlanes` | Draw valid regular flats after walls; skip/record sky pixels in this task, without trying to draw them as flats. |
| `r_draw.c:R_DrawSpan` | Inclusive `[x1,x2]`, 64×64 tiled row-major texel: `((yfrac>>10)&4032)+((xfrac>>16)&63)`; apply `COLORMAP`, then advance `xfrac/yfrac`. |
| `r_main.c:R_ExecuteSetViewSize` | `yslope[y]` uses half-pixel center bias, `distscale[x]` and canonical full-detail projection; no alternative perspective approximation. |
| `r_main.c:R_InitLightTables` | `zlight[16][128]`, `LIGHTZSHIFT=20`, `DISTMAP=2`, `NUMCOLORMAPS=32`; sector light + `extralight=0`, not the walls' `scalelight[16][48]`. |
| `r_defs.h` | `visplane_t` has padded access around column `[0..319]`; reproduce logical sentinels with safe allocated storage, not unchecked C-style pointer OOB. |
| `r_data.c`, `r_sky.c` | Flat resources vs sky identity; no sky pixels until M4-02. |

Do not invent a source correspondence or silently "fix" a vanilla algorithm. Document safe deviations (bounded indices, explicit arithmetic wrap, memory caps) and compare them with the original semantics. `R_DrawSpanLow` and non-full-detail settings are out of scope.

## 4. Architecture and proposed modules

The following are **recommended**, not mandatory names. First inspect the real repository to avoid duplicated APIs or include cycles:

- `src/Renderer/Visplanes.pbi`: frame-owned visplane records, find/check/split, guarded column top/bottom bands, row span emission, bounds and counters.
- `src/Renderer/PlaneMapping.pbi`: classic 320×200 fixed-point lookup setup (`yslope`, `distscale`, `basexscale`, `baseyscale`), mapping from plane spans to 64×64 flat coordinates, `zlight` table/index calculation.
- `src/Renderer/PlaneDraw.pbi`: bounded palette-index flat sampler/`COLORMAP` remapping and horizontal span writer.
- `src/Renderer/PlaneRenderMain.pbi`: opt-in single-pass integration with the M3 online wall traversal/drawing, flat cache/ownership, private-frame commit, stats/hash.
- If a shared online traversal/plane-record hook is needed in `WallVisibility.pbi`, `TexturedWallDraw.pbi` or `TexturedRenderMain.pbi`, implement the **smallest well-tested extension**, prefer an optional typed recorder/context, and preserve the existing APIs' old output when disabled. Do not introduce a second inconsistent BSP traversal, reorder `WallSpan`s or change M3-04 occlusion semantics.

The new plan must identify and validate four chronological events:

1. **Subsector entry** — obtain the canonical front sector, test plane eligibility, `FindPlane` for ceiling and floor (including F_SKY1 identity), without drawing any pixels.
2. **Wall-span setup** — given the *currently selected* front-plane handles, apply existing `MarkFloor` / `MarkCeiling` decisions and `CheckPlane` to the emitted inclusive screen-x interval.
3. **Per-column** — using the **same clip state and height interpolants** as textured wall rendering, record floor/ceiling visplane bands *before* updating clip and drawing wall tiers. Preserve source `yl/yh`, `pixhigh/pixlow` and mark-only branch order.
4. **After wall pass** — turn all recorded non-sky visplanes into horizontal spans (`MakeSpans`), cache actual used flats, render them with the proper `zlight`, and publish a single complete framebuffer.

The M3-04 `WallVisibilityBuild` currently returns **only emitted `WallSpan`s**, not every visited subsector plane context. If this is insufficient, extend the **online producer** or share its internal visit callbacks; **do not** fabricate planes from black pixels or assume all planes correspond 1:1 with an emitted wall span. Document how subsectors with zero wall spans, empty/trigger lines, portals and repeated front sectors are handled.

### Stateful contracts

- Follow existing `Magic`/`Ready`/Reset patterns; distinguish uninitialized, invalid and empty states, use `.l` for game values, `.q` for wide intermediates, `.i` for native pointers.
- Frame-local visplanes, row-span starts, flat cache and light tables are exclusively owned and released on failure/success; no raw pointer into an open WAD or `FlatCatalog` is stored in a published result.
- Set clear **bounded budgets** (example: at most 1,024 visplanes; 320×200 surface, checked span emission cap and flat bytes), with informative errors rather than unchecked writes. Vanilla's `MAXVISPLANES=128` is a source reference; a larger guarded port cap is acceptable if documented, not silently unlimited.
- The canonical output remains 64,000 palette bytes; palette index **0 is a valid texel**, never infer visibility from `pixel != 0`. Provide an explicit wall/plane coverage audit or equivalent verified masks.
- No heap allocation, WAD read, `FlatLoad` or `COLORMAP` decode inside per-x/per-pixel loops. Preload or cache the required flats while WAD is open. Document cache invalidation after `WADClose` or switching IWAD A→B→A.
- All errors must leave the caller's previous target framebuffer **unchanged byte-for-byte**. Build in a new private plane and swap/publish only on full success. Preserve failure diagnostics through cleanup and make Reset idempotent.

## 5. Visplane identity, splitting and guarded ranges

Required:

- Key regular visplanes by canonical **fixed-height, flat ID, sector lightlevel**. A sky visplane uses `(height=0, sky flat ID, lightlevel=0)` as in `R_FindPlane`; do **not** merge distinct ordinary flats just because their names look similar.
- Use the existing `FlatCatalog` namespace resolution and M2 canonical 8-byte name rules; `F_SKY1` is a **special identity**, not a 4096-byte ordinary flat. Flat ID/index `0` is a legitimate flat, unlike the historic wall NoTexture index-0 quirk.
- Initialize top[x] to sentinel `0xFF`; make safe logical pads for x=-1 and x=320, or explicit branches with matching original behavior. No unchecked array indexing. Validate top/bottom as 0..199 and top≤bottom before emitting a drawable band.
- Reproduce `FindPlane` lookup/duplicate ordering and `CheckPlane` overlap test. Splitting must preserve plane identity and create independent top/bottom storage. Repeated plane occurrences may merge horizontally only if their used x range does not collide.
- Do not discard empty visplanes prematurely if it changes subsequent identity/split ordering. Keep deterministic creation order and counters (`Find`, `Reuse`, `Merge`, `Split`, `Empty`, `SkyDeferred`, `Spans`, `Pixels`).
- Reject malformed invalid spans, negative/overflowing indices, exhausted budgets and impossible row bands without partial publication.

## 6. Exact flat projection and span drawing

Keep the **existing Doom integer semantics**: fixed 16.16, BAM-32 and the pinned trig tables; no runtime `Sin()`, `Cos()` or `ATan2()` replacement.

- Precompute canonical `yslope[y]` with source `dy = abs(((y-100)<<16) + FRACUNIT/2)` and numerator `(320/2)*FRACUNIT`; protect from bad values but do **not** "correct" the half-pixel center offset.
- `distscale[x] = FixedDiv(FRACUNIT, abs(finecosine[xtoviewangle[x] >> ANGLETOFINESHIFT]))`, preserving exact array bounds and unsigned BAM indexing.
- At frame clear: `angle=(viewangle-ANG90)>>ANGLETOFINESHIFT`; `basexscale=FixedDiv(finecosine[angle], centerxfrac)`; `baseyscale=-FixedDiv(finesine[angle], centerxfrac)`.
- For each regular visplane `planeheight=abs(plane.height-viewz)` with checked 32-bit semantics; per row reuse cached `(distance=FixedMul(planeheight,yslope[y]), xstep=FixedMul(distance,basexscale), ystep=FixedMul(distance,baseyscale))` **only while the height matches**.
- For inclusive x range `[x1,x2]`: `length=FixedMul(distance,distscale[x1])`; angle from `viewangle+xtoviewangle[x1]`; `ds_xfrac=viewx + FixedMul(finecosine[angle],length)`; `ds_yfrac=-viewy - FixedMul(finesine[angle],length)`; advance xfrac/yfrac once per painted pixel with the original low32 semantics.
- For 64×64 flats: source spot `((yfrac >> 10) & (63*64)) + ((xfrac >> 16) & 63)`. Read from `FlatImage` (validated exactly 4096 bytes) and write `COLORMAP[lighttable][sourceIndex]`. Source index 0/255 are ordinary palette values.
- Plane light row `light=(sector lightlevel >> LIGHTSEGSHIFT)+extralight`, clamp 0..15; `zlight[16][128]` from original `R_InitLightTables`, `LIGHTZSHIFT=20`, `DISTMAP=2`, table indexes 0..31, distance-based select. Do not use wall scale lighting for planes.
- No drawing across invalid plane pixels, one-sided walls or unrecorded gaps. Sky regions remain background, explicitly counted. Define correct handling of view horizon, negative coordinates, extreme plane heights, zero/edge distance and overflow without CPU exceptions or out-of-bounds reads.
- Original `R_DrawPlanes` runs **after** the wall pass; ensure flat drawing never overwrites an explicitly painted wall pixel. Compare against independently tracked wall-coverage regions, not only framebuffer colors.

## 7. Resource integration and new preview

- Use `FlatCatalogBuild`, `FlatCatalogFindName`, `FlatLoad`, `FlatImageReset` already in M2. Preserve their strict 64×64/4096-byte contract, last-duplicate WAD semantics and read-only loading. Maintain no WAD dependencies in hot loops.
- Only load flats actually used by visible non-sky visplanes. Cache by resolved flat ID; no double-free/shallow copy of owning `FlatImage` structures. Reset must release exactly once.
- Use existing valid `PLAYPAL`, `COLORMAP`, map, camera, `Projection`, `WallVisibility`, wall texture cache and framebuffer rather than implementing parallel decoders.
- Introduce **`--show-planes <ExMy>`** as opt-in preview: `DoomPB.exe --iwad data/DOOM.WAD --show-planes E1M1`. Distinct title such as `DoomPB - Textured Walls + Flats - E1M1`. A simple alternate descriptive option name is permissible if consistently documented and tested.
- Require the original `--show-title`, `--show-walls`, `--show-textured-walls`, `--map-info`, `--dump-info`, `--lump-info`, `--help`, `--version` and no-argument bootstrap to behave identically. No new flag should silently change legacy render defaults, output bytes or return codes.
- CLI errors: missing IWAD/path returns existing failure code 1; missing option values or conflicting render modes return usage 2; success 0. Do not read the owner's IWAD in commands that do not ask for it.
- Keep GUI 320×200 logical and 960×600 client nearest-neighbour. Do not treat `PrintWindow`'s decorative/chrome pixels as authoritative raw-frame evidence.
- Return deterministic stats and a canonical FNV-1a64 of **all 64,000 row-major palette bytes**, matching existing algorithm; test independent re-hash, repeat loads/resets and cross-run repeatability.

## 8. Test requirements: PL01–PL60 and integration

Create `tests/unit/plane_render_tests.pb`, `tests/integration/m4_plane_tests.pb`, optional `tests/integration/m4_plane_iwad_tests.pb`, and synthetic independent fixture/generator only if useful. Naming may follow local conventions but IDs below are required. **Do not invent outcomes or change expected values to match production bugs.** All synthetic fixtures must be original and contain no retail IWAD material.

| Test IDs | Required coverage |
|---|---|
| PL01–PL05 | Initialize/reset/ownership, 320×200 limits, invalid pointers/empty state, top=0xFF & pad sentinels. |
| PL06–PL10 | `FindPlane` exact key, reuse across sectors, sky height/light normalization, non-sky distinct key, flat ID 0. |
| PL11–PL15 | `CheckPlane` disjoint merge, overlapping used column causes split, boundary x=0/319, cap failure/rollback, creation order. |
| PL16–PL20 | Subsectors with/without legal floor/ceiling, wall-free/empty lines, portals, near/far chronological plane assignment. |
| PL21–PL25 | `MarkFloor`/`MarkCeiling` before clip updates, one-sided closure, upper/lower tiers, mark-only branches, closed doors. |
| PL26–PL30 | `R_MakeSpans`: open/close on adjacent columns, same-row merge, top/bottom edges, x+1 sentinels, duplicate/empty bands. |
| PL31–PL35 | `yslope` half-pixel horizon, `distscale`, basexscale/baseyscale, heading quadrants, signed/unsigned BAM boundaries. |
| PL36–PL40 | `R_MapPlane` planeheight/row cache/x-y coordinates, 16.16 overflow policies, step order and row wrapping. |
| PL41–PL45 | 64×64 flat spot bit formula, x/y negative wrap, palette 0 and 255 valid, inclusive horizontal `[x1,x2]`, row bounds. |
| PL46–PL50 | `zlight[16][128]` from independent oracle, sector lighting clamps, distance index/clamp, COLORMAP remap, sky skip. |
| PL51–PL55 | Cache uniqueness/load-before-close/A→B→A invalidation, missing/truncated flat/colormap, memory caps, transactional target rollback. |
| PL56–PL60 | Legacy wall pixel preservation, numeric event chronology, independent full-plane FNV repeatability, no hot-loop allocations, 3× nearest-neighbour/CLI smoke. |

**Synthetic PI01–PI03:**

- **PI01:** single sector, simple closed room, deterministic front floor+ceiling, known flat textures and lighting, exact independently calculated span rows/pixels/full 64,000-byte hash, no sky.
- **PI02:** multi-sector height/light changes, two-sided portals, sky on a ceiling, multiple repeated/split visplanes, wall/plane coverage audit, exactly correct skip for sky and complete tier clipping; original-independent numeric golden samples/hashes.
- **PI03:** resource lifecycle A→B→A WADs, repeated draw/reset, late malformed visplane/flat/colormap/limit failure with target byte-for-byte preserved; legacy mode hashes unchanged. At least one test must exercise zero emitted `WallSpan`s yet valid subsector/plane contexts.

**Optional owner-IWAD PI04:**

- With legally owned `data/DOOM.WAD`, render player-start **E1M1, E1M2, E4M1** read-only; report wall, floor, ceiling, sky-deferred pixel counts, #visplanes reused/split, flat cache stats, no OOB/invalid indices and per-map raw frame hashes.
- Confirm real flat pixels appear in at least E1M1 and E1M2, and validate frame coverage using explicit marks (never assume palette index zero indicates an unpainted pixel).
- Compare **M3-04**, **M3-05** and **M3-06** frozen fingerprints / hashes with their known baselines; old textured `E1M1=183BA53FCECECBC8`, `E1M2=835A0339A38B190E`, `E4M1=03B5C8CFA517FC7E` are historical **NOT LOCKED** observations. Do not freeze new owner frame goldens until independently verified, and do not assume matching visual thumbnails proves C-equivalence.
- Check owner IWAD size/MD5 **before and after**: 12,408,292 bytes and `c4fe9fd920207691a9f493668e0a2083` for the user's Ultimate Doom 1.9ud file. Never alter/copy/stage WAD payloads, extracted sprites/flats/textures or window captures.
- Without an IWAD path the optional harness must report **`NOT RUN`, 0 cases/0 assertions, exit 0**, not a fake PASS.

### Independent oracle

Create a **separate** small integer-only Python oracle/fixture for `Find/CheckPlane`, `MakeSpans`, `yslope`, `distscale`, `MapPlane`, `zlight` and spot addressing, rather than deriving expected arrays solely from the PureBasic output. Keep the fixtures small, source-independent, deterministic and entirely synthetic. Source C and numeric tables provide formulas and constants; do not embed commercial graphics or substitute rendered output as its own reference. Check fixture regeneration is byte-stable.

## 9. Build, test, compatibility and performance

Extend **both** PowerShell and Bash build/test entry points with focused targets, e.g. `-PlaneTest`, `-PlaneIntegrationTest`, `-PlaneIwadTest` / `--plane-test`, `--plane-integration-test`, `--plane-iwad-test`. Preserve all previous flags and their exact exit-code interpretation. Test runners must tally **per executable** and avoid counting both M2 synthetic (`35/221`) and M2 owner (`36/240`) in the same cumulative mode.

**Historical M3-07 regression baseline only (not new totals):**

| Mode | Cases | Assertions | Failures | Windows script checks |
|---|---:|---:|---:|---:|
| Without IWAD | **732** | **6,106** | 0 | 175/175 |
| Owner-IWAD | **740** | **6,913** | 0 | 239/239 |

Expected new tests are **60 unit cases + 3 synthetic integrations + 1 optional owner integration**, but agents must report the **actual** per-executable cases/assertions and recalculate overall totals; don't fabricate fixed assertion counts or change earlier tests' semantics. Preserve version `0.3.0` and run previous M1/M2/M3 checks. Use the real PureBasic 6.41 compiler for `scripts/build.ps1 -Check`, main executable, new test harnesses and full scripts.

Check determinism, memory budgets, cold/warm timings **if measurable** with the existing M3 BEN01 QPC methodology, but don't claim a universal FPS result. No heap allocations, WAD I/O or flat loading inside pixel loops. Zero leaked resources on errors must be supported by lifecycle tests/probes rather than guessed.

Linux must remain **NOT RUN** unless there is a genuine Linux x64 PureBasic compile and executable run. `bash -n` under Git Bash is syntax-only; do not promote it to Linux PASS.

### Manual GUI review

Open and close new E1M1/E1M2/E4M1 windows; verify 960×600 client area and actual floor/ceiling textures where present; verify deferred sky stays as background. Check visually that wall surfaces are not overwritten by planes, portal gaps are not falsely filled, horizon/tier boundaries look consistent and no unexplained stripes appear. Window smoke and human visual inspection are different evidence levels from raw framebuffer hashes; report precisely which was performed.

## 10. Acceptance gates and blocker policy

All **mandatory** gates must pass before reporting `READY FOR OWNER ACCEPTANCE`:

1. Exact source-backed integration order: subsector -> `FindPlane`, wall span -> `CheckPlane`, mark rows before clip mutations, floor/ceiling drawing after walls.
2. Regular flats are real `FlatLoad` 64×64 data remapped through original `zlight`; sky is detected/deferred (never incorrectly textured).
3. Synthetic independent oracle verifies arithmetic, plane range split, span extraction, texture address and lighting; no product-only oracle or guessed golden.
4. Explicit wall coverage remains unchanged in the new combined mode; old M3-04/M3-05/M3-06 APIs, hashes and CLI presentation remain intact.
5. New PL01–PL60 + PI01–PI03, full historical regression, real Windows PB 6.41 compile/build, failure/rollback/memory tests PASS; owner PI04 optional and transparently reported.
6. Checked bounds and no memory corruption, no per-pixel malloc/IO, no resource leaks, stable raw hashes under repeated runs.
7. Correct docs, GPL-2.0-only attribution, no commercial data/tracked binaries, `git diff --check=0`, staged state disclosed, no unapproved Git mutations.

If the **plane context cannot be obtained correctly from the existing online M3 pipeline**, do not fake an approximate implementation that fills black pixels. Refactor the shared visit/event plumbing minimally and retest, or declare `BLOCKED` and explain. If owner IWAD is missing, mark PI04 NOT RUN; synthetic mandatory tests may still pass. An independent original-C **same-camera full-image** comparison is desirable but may stay `REFERENCE UNAVAILABLE` and must not be misrepresented as PASS. Version remains 0.3.0 throughout; **never start M4-02** in this task.

## 11. Documentation, diff audit, and final report

Update `README.md` (explicit wall+flat preview and sky/masked/sprite gaps), `CHANGELOG.md` under **Unreleased M4-01** (do not change historical tagged v0.3.0 text), `docs/DEVELOPMENT_PLAN.md` M4 checklist with partial truthful status, and `docs/PORTING_NOTES.md` with source correlations, algebra and deviations, plane identities/splits, flat cache and ownership, deterministic fixture details, benchmark data and verification gaps. Any new doc should have a clear purpose; don't create arbitrary duplicates.

Run and disclose:

```powershell
 git diff --check
 git diff --cached --check
 git status --short --branch
 git diff --stat
 git diff --name-status
 git ls-files -- '*.wad' '*.WAD' '*.iwad' '*.IWAD' '*.png' '*.exe' 'data/**' 'build/**'
```

Audit **untracked** files for whitespace/LF/BOM, SPDX and commercial/binary payloads (normal `git diff --check` does **not** include untracked content). Do not run `git add`, `commit`, `push`, `tag`, `reset`, `clean` or merge. Do not include local `DOOM.WAD`, generated screenshots, extracted game art or full original C tree in Git.

Final report must contain:

- Task, actual branch/HEAD/tags, initial/final staged and worktree state.
- Windows OS and exact PureBasic 6.41 compiler; Linux `NOT RUN` unless actually verified.
- Original C source symbols/commit and actual Context7 query/fallback details.
- Created/modified files and API/ownership/event-sequence architecture.
- Visplane find/reuse/split, plane captures, regular/sky counts, `zlight`, cache and memory budgets; explicit negative/zero-index policies.
- Per-new executable PL/PI actual cases, assertions, failures and exit codes; all previous regression per-executable totals; script checks with/without owner IWAD.
- E1M1/E1M2/E4M1 actual floor/ceiling/sky counts, full raw frame hashes (NOT LOCKED without independent source), visual smoke details, legacy hash preservation.
- Timing/allocations if measured, error injection and A→B→A rollback evidence.
- Known deviations, missing work for M4-02+, and a truthful decision: `READY FOR OWNER ACCEPTANCE`, `PARTIAL` or `BLOCKED`.

**Stop after M4-01. Do not change version 0.3.0, stage, commit, tag, push or begin sky/sprites/gameplay.**
