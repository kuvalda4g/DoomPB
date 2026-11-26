# DoomPB — M3-07: Integration, acceptance and v0.3.0 preparation

> **Task:** `M3-07` · **Milestone:** M3 — Geometry & First Walls (`v0.3.0`, not released yet)
> **Agent:** OpenCode Desktop · DeepSeek V4.1 Flash 1017 · Reasoning High
> **Platform:** PureBasic **6.41**, Windows x64; Linux x64 is **NOT RUN** unless genuinely built and executed there
> **Project:** DoomPB · GPL-2.0-only · single local, legally owned IWAD; no commercial resources in Git
> **Primary upstream:** `../doom-original/linuxdoom-1.10` at `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> **Prerequisite:** M3-06 accepted **and committed** by the owner; verify the actual Git HEAD, branch, index and worktree
> **Meaning:** release-preparation **assignment**, not a report or evidence of any tests having run

## 1. Objective and release scope

Close the **Windows x64** integration of M3-01 through M3-06, prove that the existing subsystems form one reproducible, read-only, static textured-wall rendering pipeline, and prepare a reviewable **DoomPB v0.3.0** changeset. This is the integration-and-release milestone; do **not** start M4, rewrite the renderer or add gameplay features.

The deliverable is a native PureBasic executable which, using an owner-provided legal `DOOM.WAD`, loads the validated map, initializes resources, creates a static player-one view, computes the online near-to-far BSP visibility, projects and clips wall spans, and renders **middle, upper and lower textured wall tiers with vanilla static `COLORMAP` lighting** into a deterministic indexed 320×200 framebuffer. Existing CLI and graphical previews must remain functional.

**M3 v0.3.0 is not a playable Doom engine.** Its scope is wall-only previews. Black/unrendered floors, ceilings, sky and portal gaps are intentional; there is no sprite renderer, complete `drawseg_t`, masked two-sided middle-texture overlay pass, animation, interactive movement, thinker/physics loop, music or sound. Never market or document it as complete world rendering.

### Release decision policy

- **Verify before bumping**: baseline Git, full regressions, three real map previews, resource/lifetime handling, deterministic data, absence of commercial assets, release docs and version-specific CLI checks must all pass.
- **Independent comparison:** actively attempt source-independent real-IWAD sampling and, where technically feasible, an original-C-equivalent reference image from the **same** view. Synthetic fixture equality and repeated owner hashes are useful but **do not** prove full visual equivalence to the C engine.
- If the real-IWAD reference cannot be established, keep owner textured frame hashes **NOT LOCKED**, explain why, report the exact remaining comparison gap, and do not check off that comparison as complete. Do not manufacture hashes or compare views with mismatched camera/palette/FOV.
- **CPU timing** is a real M3 roadmap gap. Measure wall-frame render costs on Windows; report environment, sampling method, minimum/median/p95 if stable, and pre-loop allocation counts. Do not claim a specific FPS from this wall-only preview.
- If a **mandatory core gate fails** or an unresolved bug compromises correctness, leave version `0.2.0` and report **BLOCKED**. If the core gates pass but a roadmap criterion remains unverified, document it explicitly as **PARTIAL / owner acceptance required**, not as an invented PASS. Do not silently mark the entire M3 checklist complete. Version `0.3.0` may be prepared with a truthful scoped release note only if the core release gates pass and the outstanding reference-comparison limitation is openly identified for owner decision.
- All Git staging, commits, tags, pushes and release publication are **owner-controlled**. Never perform them yourself.

## 2. First steps: discover and report actual repository state

Read, in the current repository:

1. `AGENTS.md`, especially Context7 MCP, compiler, licensing, whitespace and Git safety rules.
2. `docs/DEVELOPMENT_PLAN.md` M3 scope/checklist, `docs/PORTING_NOTES.md`, `README.md`, `CHANGELOG.md`, `.gitignore`.
3. `src/DoomPB.pb`, `scripts/build.ps1`, `build.sh`, `test.ps1`, `test.sh`; all current M3 test executables, not only the new ones.
4. `src/Core/{Fixed,Angle,TrigTables}.pbi` and actual generated original trig table data.
5. `src/Graphics/{Palette,Colormap,PNames,Patch,TextureDefs,Texture,Flat,FrameBuffer,Video}.pbi`.
6. `src/Map/{MapTypes,MapDecode,MapLevel,MapLoader,MapValidate}.pbi` and original BSP/links contracts.
7. `src/Renderer/{Geometry,Camera,BSP,Projection,ClipSegs,WallVisibility,WallView,WallProject,WallDraw,RenderMain,WallTextureMapping,WallTextureCache,WallLighting,TexturedWallDraw,TexturedRenderMain}.pbi`.
8. Existing synthetic fixtures and generators, especially M3-03–M3-06, and the optional owner-IWAD tests.

Initial commands, from the repository root (adapt to the actual shell):

```powershell
git status --short --branch
git log -7 --oneline
git tag --list
git diff --stat
git diff --cached --stat
git -C ../doom-original rev-parse HEAD
Get-ChildItem docs/tasks, tests/integration, tests/unit, scripts
```

Confirm M3-06 exists as a commit on `dev` and that `v0.3.0` **does not already exist**. Do not assume an old SHA or clean tree. Treat the supplied `docs/tasks/M3_07_OPENCODE_TASK.md` as owner-provided material if untracked; preserve concurrent staged and unstaged changes. Never `git clean`, `reset --hard`, force checkout or silently rewrite owner edits. If `0.3.0` already exists, inspect it and report a conflict rather than silently preparing a second release.

Before editing, present a short plan with: actual API signatures; audit gaps; proposed files; new tests; reference-comparison strategy; benchmark method; exact release gates; version/doc update order.

### Documentation and Context7

Follow `AGENTS.md`. When a library/tool/PureBasic API requires lookup, actually invoke available Context7 `resolve-library-id` and focused `query-docs` if configured. `/websites/purebasic` appeared in earlier reports, but do **not** assume exact 6.41 version coverage. Fall back to the installed PureBasic 6.41 CHM, official documentation and disposable compiler probes. Record `USED / NO MATCH / UNAVAILABLE / NOT NEEDED` with exact real topic and evidence. Never send WAD bytes, private paths, game graphics, credentials or proprietary snippets to external documentation tools. Original Doom behavior comes from pinned local C, not a documentation search engine.

## 3. Source equivalence matrix: inspect only needed code

| Upstream source and symbols | Integration behavior to audit |
|---|---|
| `m_fixed.c`: `FixedMul`, `FixedDiv`, `FixedDiv2` | 16.16, early saturation, signed/unsigned edge rules; keep M3-01 behavior |
| `tables.c`, `tables.h`, `r_main.c`: `SlopeDiv`, `R_PointToAngle`, `R_PointToDist`, `R_PointOnSide` | Exact numeric tables, BAM wrap, geometry and octant semantics |
| `r_main.c`: `R_InitTextureMapping`, `R_ScaleFromGlobalAngle`, `R_SetupFrame` | 320-wide projection tables, clipangle, scale and camera view |
| `r_bsp.c`: `R_RenderBSPNode`, `R_CheckBBox`, `R_AddLine`, `R_ClipSolidWallSegment`, `R_ClipPassWallSegment` | Near/far online ordering and live occlusion; debug cull-free trace remains separate |
| `r_segs.c`: `R_StoreWallRange`, `R_RenderSegLoop` | Per-span projection, 12-bit wall edge interpolation, tiers/pegging/clip order |
| `r_draw.c`: `R_DrawColumn` | Indexed 8-bit samples, exact row stepping/inclusive screen bounds |
| `r_data.c`: `R_InitTextures`, `R_GetColumn`, `R_GenerateComposite`, `R_InitColormaps` | Catalog/patch resolution, width masks, composed-image/cache and lighting lifetime |
| `p_setup.c`, `doomdata.h`, `p_mobj.c`: `P_SpawnPlayer` | Ten-lump map, subsector/sector links, player-one X/Y/angle/floor+41 view |

Do not implement an additional parser, visibility algorithm or texture composer merely to satisfy the table. Use independent reference logic **only inside test tools/oracles**; actual production must reuse existing M1/M2/M3 modules.

## 4. Required end-to-end pipeline and modes

The working path is conceptually:

```text
WADOpen(user path, read-only)
  -> PLAYPAL / COLORMAP / PNAMES / TEXTURE1 and optional TEXTURE2
  -> TextureCatalogDecode + Resolve; flat catalog; other required resources
  -> MapLevelLoad(ExMy) + cross-reference / BSP / REJECT / BLOCKMAP checks
  -> MapLevelValidateResources
  -> ProjectionInitClassic(320x200)
  -> WallRenderPlayerStartView (unique player-one THING, original ANG45 heading)
  -> WallVisibilityBuild (near-first BSP + R_CheckBBox + solid/pass intervals)
  -> WallProject/WallSpanPlan (exact fixed16/BAM geometry and tier boundaries)
  -> used-texture cache via TextureCompose while WAD is valid
  -> COLORMAP/scalelight and textured per-column rendering
  -> private indexed FrameBuffer -> success-only publish -> canonical FNV-1a64
  -> WADClose / release/catalog cache cleanup / optional window presentation
```

Use actual verified module APIs and ordering. Keep the existing `--show-walls` debug-color path and `--show-textured-walls` textured path *independent* where the current implementation separates them; M3-07 must not accidentally replace one with the other. Source images or WAD-backed indexes must never be accessed after the corresponding WAD directory is invalidated.

Required CLI smoke (preserve existing exit codes: normal `0`, resource/runtime failure `1`, usage `2`):

```powershell
.\build\DoomPB.exe --version
.\build\DoomPB.exe --help
.\build\DoomPB.exe --iwad data\DOOM.WAD --dump-info
.\build\DoomPB.exe --iwad data\DOOM.WAD --lump-info PLAYPAL
.\build\DoomPB.exe --iwad data\DOOM.WAD --map-info E1M1
.\build\DoomPB.exe --iwad data\DOOM.WAD --show-title
.\build\DoomPB.exe --iwad data\DOOM.WAD --show-walls E1M1
.\build\DoomPB.exe --iwad data\DOOM.WAD --show-textured-walls E1M1
```

The last three are GUI operations; inspect the actual **960×600** client and close normally. Repeat `--map-info`, debug and textured previews for **E1M2 and E4M1**. Verify no-argument behavior and malformed/duplicate/conflicting flags with correct exit codes. Do not run GUI tests headlessly while reporting them as observed windows; where a display is unavailable say `NOT RUN`.

Do not require an IWAD for compile-only tests, version/help or independent synthetic suite. The owner IWAD must remain byte-for-byte untouched. Do not print/persist image payloads, coordinates or extracted textures into tracked or public files.

## 5. Integration audit: enforce existing contracts

Audit, fix **only demonstrated defects**, and add focused checks for the following:

1. **Fixed-point and BAM:** original tabular arithmetic; 32-bit overflow/wrap/checked failures do not drift from M3-01/M3-02.
2. **Map/renderer bridge:** derived sector links and seg sides are read from validated `MapLevel`; root node is the final node, zero-node BSP uses its documented special case; no pointer to freed map buffers.
3. **BSP and visibility:** M3-03 cull-free trace remains deterministic; M3-04 online visibility handles far BBox **after** near segments have changed solid clips. No sorting, deduplication, second speculative cull pass or accidental permutation of `WallSpan` records.
4. **Projection:** canonical `viewangletox`, `xtoviewangle`, `clipangle`, 320×200 constants, screen inclusive ranges, single-pixel spans and both screen edges.
5. **Vertical tiers:** `R_ScaleFromGlobalAngle`; `topfrac`/`bottomfrac`, `pixhigh`/`pixlow`, shared `ceilingclip`/`floorclip`; no inverted/negative length writes; one-sided closed columns and two-sided upper/lower portal gaps.
6. **Texturing:** texture selection via correct sidedef; `rw_offset`, `rw_centerangle`, `texturecolumn`, native texture width-mask (not universal modulo), `dc_iscale`, `dc_texturemid`, `rowoffset` and one-sided/upper/lower pegging flags. Preserve the corrected M3-06 formulas.
7. **Lighting:** `scalelight[16][48]`, colormap indexes `0..31`, light row horizontal/vertical corrections, `extralight=0` static contract, palette index `0` as a color and `255` as an opaque texel.
8. **Deferred work:** detect masked two-sided middle slots; do not paint them as opaque walls or claim a deferred masked pass. Non-128 height (<128 modulo-height bounded fallback; >=128 vanilla `&127`) and mask-hole behavior remain explicitly documented deviations, never hidden by a hash update.
9. **Frame ownership:** failed render must preserve the target framebuffer byte-for-byte; a successful frame owns its committed 64,000 palette bytes, and numeric result metadata does not keep references to freed map/WAD/texture-cache memory.
10. **Reopen and reset:** A→B→A on synthetic WADs re-resolves patch indices; caches never silently reuse stale WAD indexes. Repeated map/viewport renders do not leak references, double free or mutate the source IWAD.
11. **Presentation:** indexed raw 320×200 pixels versus actual 3× nearest-neighbor conversion are distinct verification layers. Do not infer pixel identity from a `PrintWindow` capture, which may include compositor/scaling edge effects.
12. **Performance:** no per-pixel/per-column allocation, `TextureCompose`, file I/O or unnecessary rebuild inside inner draw loop. If necessary, add *test-only* instrumentation rather than an unnecessary production-level profiling framework.

Critical: use the actual result types (`WallVisibilityResult`, `WallSpanPlan`, `FrameBuffer`, texture-cache record, `ColormapSet`) rather than inventing function signatures. Maintain original signedness semantics for `.l` and use `.q` for checked calculations; do not turn the renderer into floating point.

## 6. Independent visual and numeric reference policy

Existing M3-06 synthetic golden fixture pairs are valid prior evidence. **Do not regenerate or edit their expected values merely because production output differs.** First isolate a real source bug versus a wrong independent oracle; review the pinned C lines and rerun the native compiler/test harnesses.

### Frozen older references: never silently change

| Layer | E1M1 | E1M2 | E4M1 |
|---|---|---|---|
| M3-04 visible-span FNV-1a64 | `74B485154CE29B0B` | `8AC0627513C4B619` | `9FD0B15A0F33197E` |
| M3-04 counter FNV-1a64 | `7ADB45DBF2611B77` | `83CAB0E1049B850A` | `CCAA2442EB270717` |
| M3-05 debug framebuffer FNV-1a64 | `4A923E4D357C7BD1` | `0C9627E5C2FD8D35` | `9AEB8BDD16834359` |

M3-06 synthetic TI01/TI02 full textured frame hashes: `119A71B79384D465` and `F05D55B8FE8C07EB`; their independent M3-04 span fingerprints `3EE9969A4FF10052`, `2FAA660491199243`. These should remain unchanged unless a separately justified bug is fixed and the original source/oracle independently demonstrates why.

### Owner real-IWAD measurements (historical; NOT LOCKED)

| Map | Observed M3-06 textured frame FNV-1a64 | Evidence status |
|---|---|---|
| E1M1 | `183BA53FCECECBC8` | Stable, NOT LOCKED |
| E1M2 | `835A0339A38B190E` | Stable, NOT LOCKED |
| E4M1 | `03B5C8CFA517FC7E` | Stable, NOT LOCKED |

These three hashes are **regression observations**, not independent C-verified goldens. Recompute FNV over the *exact 64,000 row-major 8-bit palette bytes* independently of the renderer's reported hash; test A→B→A and identical camera inputs. Print hashes, pixel counts and other small numerical summaries only. Do not place actual IWAD texture pixels, screenshots or WAD-derived sampled data arrays in the repository.

### Source-independent owner comparison: required attempt

1. Establish a reproducible player-one view (map name, THING ID, map units, BAM angle, viewz, projection, resolution, lighting assumptions), but **do not publish private details** if they disclose original resources unnecessarily.
2. Use pinned original source formulas (`r_segs.c`, `r_draw.c`, `r_data.c`, `r_main.c`) in a **separate test-only oracle** for a meaningful selection of real visible spans, columns and rows. Ideally implement an independent reference using C original-compatible logic and local owner IWAD. Keep sampled outputs ephemeral and report only mismatches, bounded counts and fingerprints.
3. Compare original texture/patch composition and width masking, classic `rw_offset`/`texturecolumn`, unsigned scale and `dc_iscale`, pegging + `rowoffset`, vertical texel addressing, `COLORMAP` lighting and resulting palette indexes. Include examples with <128-height textures and explicit divergence handling.
4. If a whole C-reference image is available, compare equivalent **wall-only** frames under identical camera/projection/occlusion assumptions. A complete vanilla Doom screenshot also contains planes/sprites, so raw full-frame hashes are **not** directly comparable to DoomPB's wall-only output.
5. Distinguish: `INDEPENDENT REAL SAMPLE PASS`, `C FRAME COMPARISON PASS`, `REFERENCE UNAVAILABLE`, or `DIVERGENCE FOUND`. Do **not** call owner hashes `LOCKED` based only on repeated PB builds or Python fixtures derived from PB outputs.
6. If authoritative reference work would exceed the scoped release task, document precise unresolved cases and a follow-up M4+ item; do not silently modify the M3 checklist checkbox or invent equivalent evidence.

### Presentation identity check

For a wholly synthetic 320×200 indexed framebuffer, convert it using `FrameBufferScaleNearestRGBA` at 3× and inspect deterministic 3×3 blocks and 960×600 bounds. This tests software conversion, **not** a desktop compositor or screenshot. Check raw framebuffer and mapped RGBA separately; avoid writing owner game images as tracked golden fixtures.

## 7. CPU timing and allocation audit (previously unmeasured)

Create a small, independent benchmark in `tests/integration/` or `scripts/` (e.g. `m3_release_benchmark.pb` or similar) only if existing M3 harnesses cannot provide repeatable timing. Real executions only.

- Environment: Windows build/CPU, PB compiler version, release/debug mode, 320×200, scene/map, cold vs warm caches, number of runs, warmup count.
- Separate **I/O and patch-composition warmup** from frame-only performance; report both a cold end-to-end wall-render cost and warmed frame-only render cost where feasible. Wall-only preview is not a complete game frame.
- Use a documented monotonic high-resolution measurement available through verified PB 6.41 APIs or Windows platform adapter; if resolution is too low, batch repeat frames and divide, record the batch size. Never fabricate sub-millisecond timings from an inadequate clock.
- Repeat sufficient times (e.g. warmup 20, measured 100+) and report min/median/p95 or state why unavailable; note CPU/load variance. Avoid a hard FPS performance threshold not agreed by the owner.
- Verify **zero allocation/composition/WAD I/O inside the per-column hot loop** using actual counters/instrumentation; report observed outer allocations and texture composition counts. No request for an elaborate profiler or permanent benchmarking CLI.
- Tests should not fail merely due to host performance variation; hard-fail only real functionality/budget regressions, hangs, OOB writes, allocation failures or non-determinism.

## 8. New M3-07 tests (synthetic by default)

Add a release-specific test harness if necessary (recommended `tests/integration/m3_release_tests.pb`, and optional `m3_release_iwad_tests.pb`). Prefer existing test scaffolding and only add `-M3ReleaseTest` / `--m3-release-test` (and optional owner-IWAD target) to build scripts if needed; inspect actual conventions. No new public CLI flags are mandatory.

Target **36 distinct synthetic cases MR01–MR36**, plus **three integration cases RI01–RI03** and optional **RI04** using the owner's legal IWAD. Cases may share helpers, but every case must have individually reported assertions. Do not assert predicted totals before running. A release regression may reference existing fixture checks rather than duplicating thousands of old test assertions.

### MR01–MR36: focused synthetic acceptance matrix

| ID | Required check |
|---|---|
| MR01 | Module include dependency and API signature smoke; no circular includes |
| MR02 | Default `--version` expectation stays 0.2.0 **until** gates pass |
| MR03 | Original fine-angle/geometry/table constants unaffected |
| MR04 | FixedMul/FixedDiv sign/overflow integration spot checks |
| MR05 | Canonical 320×200 projection/table fingerprints unchanged |
| MR06 | BSP leaf/near-first ordering and zero-node root convention |
| MR07 | M3-03 trace ownership, cull-free semantics and reset |
| MR08 | M3-04 solidsegs sentinel and inclusive interval boundaries |
| MR09 | Online far-BBox visibility checked only after near work |
| MR10 | Backface/FOV one-pixel and x=0/319 edge behavior |
| MR11 | M3-04 span/counter fingerprints preserved, not silently changed |
| MR12 | WallSpanPlan scale/HEIGHTBITS=12 deterministic interpolation |
| MR13 | One-sided middle tier and clip close semantics |
| MR14 | Two-sided upper/lower/hole clipping chronology |
| MR15 | Middle pegging default vs ML_DONTPEGBOTTOM with rowoffset |
| MR16 | Upper default vs ML_DONTPEGTOP with sky-hack cases |
| MR17 | Lower default vs ML_DONTPEGBOTTOM with rowoffset |
| MR18 | TextureCatalog first-match, index-zero absence, canonical `-`/NUL |
| MR19 | Negative/edge texture columns and vanilla width mask 64/96/128/256 |
| MR20 | Vertical `dc_iscale`/texel sampling exact stepping at y=0/199 |
| MR21 | Non-128 height bounded policy and short-height fallback counts |
| MR22 | Mask0/opaque index0/opaque index255 distinct source semantics |
| MR23 | 16×48 scalelight source formula, light row and scale clamp |
| MR24 | COLORMAP index mapping with synthetic, known palette bytes |
| MR25 | Detect masked two-sided middle; never fill portal opaquely |
| MR26 | Reuse composed texture from cache; no duplicate ownership/free |
| MR27 | Renderer rejects absent/unresolved/corrupt resources safely |
| MR28 | Failed map/texture/colormap render preserves existing target bytes |
| MR29 | Repeated Build/Reset/WADClose releases all owned memory |
| MR30 | Synthetic WAD A→B→A invalidates and re-resolves patch WAD indices |
| MR31 | Debug-color raw frame unchanged by textured-mode runs |
| MR32 | Synthetic textured fixture/full-plane hash independent oracle |
| MR33 | Raw 320×200 FNV-1a64 over exact 64,000 byte palette plane |
| MR34 | Nearest-neighbor 3× conversion: every source pixel 3×3 exact |
| MR35 | Zero per-column allocation/WAD reads/texture composition instrumentation |
| MR36 | CLI parser: unchanged success/usage/runtime failure codes and exclusive modes |

### RI01–RI03 synthetic full-pipeline integration

- **RI01:** synthetic WAD → catalog/map → `WallVisibilityBuild` → M3-05 debug frame → M3-06 textured frame. Compare old fingerprints, new independent fixture hashes, exact 64,000 byte length, masks and clip order; verify both modes are usable.
- **RI02:** multiple-surface two-sided scene (upper/lower + holes), line directions, pegging, COLORMAP and indexed 3× presentation. Include a masked middle slot; verify it is deferred and does not fill the portal.
- **RI03:** malformed texture or COLORMAP, then recover with a valid synthetic WAD and A→B→A. Confirm no stale references, no partial frame publication, unchanged previous target, idempotent reset and no memory overrun.

### RI04 optional owner IWAD (all three maps)

- Report `NOT RUN` with 0 cases/assertions if no owner IWAD was explicitly supplied or accessible. This is **not** a PASS. The synthetic suite must still work without the IWAD.
- Verify size/MD5 read-only if matching the known GOG Ultimate Doom 1.9ud local file (12,408,292 bytes, `c4fe9fd920207691a9f493668e0a2083`), but do not reject other legal compatible IWADs based solely on a different checksum.
- Actual calls for E1M1, E1M2 and E4M1: maps and resource validation; original player-one static view; M3-04 span counts/fingerprints; M3-05 debug frames/fingerprints; M3-06 textured full-plane/independent recomputed FNV; optional independent C-equivalent texel sample comparison.
- Compare old reported textured hashes as **observations**; if they differ, investigate C source/inputs before changing any fixture. Keep them `NOT LOCKED` unless independent verification justifies otherwise.
- Repeat frames with fresh and reused objects and after reset. Verify source WAD size/MD5 unchanged, no real resource bytes included in reports or Git.
- If a GUI is available, actually open/close the three textured windows and the legacy debug/title windows. Distinguish smoke, manual owner visual check, and independent frame-level equivalence.

## 9. Historical baseline, accounting rules and commands

**Verified M3-06 report baseline (prior evidence, rerun; not a result of M3-07):**

| Existing full test set | Cases | Assertions | Failures |
|---|---:|---:|---:|
| Without owner IWAD | **692** | **5,595** | 0 |
| With owner IWAD | **699** | **6,253** | 0 |

The historical `scripts/test.ps1` statuses are **148/148** checks without IWAD, **193/193** with owner-IWAD. The 60 WT cases now have **545** assertions (not the old 537); do not regress to the earlier counts.

These are **historical values only**, so rerun and capture actual per-executable cases/assertions/failures/exit codes. Avoid the previous reporting mistake: M2's synthetic `35/221` and owner mode `36/240` are **alternatives**; in owner totals use `36/240` *instead of* the synthetic row, never add both. Count optional `I04` executables **only when actually executed** with a WAD path; `NOT RUN` contributes zero.

Use real commands; adapt compiler discovery to the repository scripts:

```powershell
.\scripts\build.ps1 -Check
.\scripts\build.ps1
.\scripts\test.ps1
.\scripts\test.ps1 -IwadPath data\DOOM.WAD
.\build\DoomPB.exe --version
```

Run **all** pre-existing M1, M2, M3-01 … M3-06 tests as well as MR/RI tests. Capture real compiler banner (`PureBasic 6.41 (Windows - x64)` if matched), check/build and script exit codes, per-executable numbers and aggregate arithmetic. New tests change totals; **do not publish guessed new total numbers**. Script check totals may grow; do not preserve old expected 148/193 artificially by skipping new gates.

For Linux, `bash -n` under **Git Bash** is a syntax-only check and is *not* Linux runtime testing. Use `NOT RUN` when no Linux PB 6.41 build and actual executable/test run occurred. If `bash` is a WSL stub or absent, record the exact condition. Do not mask failures.

## 10. Version 0.3.0, docs and release artifacts — after technical gates

Release preparation order:

1. Prove baseline old regressions, new synthetic release cases and selected owner-IWAD maps; diagnose/fix demonstrated integration bugs and rerun all affected suites. Do not stage/commit/tag.
2. Measure CPU costs and examine pre-loop allocation/texture composition counts; write an honest limited wall-frame performance note.
3. Attempt independent real-IWAD C-equivalent texel sampling; either prove independent agreement or label precise `NOT LOCKED / REFERENCE UNAVAILABLE` comparison gaps. Disclose any mismatches; do not freeze until justified.
4. Check required Windows GUI smoke, existing CLI exit codes and static render visual clarity. Report unresolved uncertainty separately from confirmed defects.
5. **Only if mandatory gates pass**, set `#DoomPB_Version = "0.3.0"` in `src/DoomPB.pb` and update any version expectations. Do not modify the tagged `v0.2.0` history.
6. Update `README.md`, `CHANGELOG.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md` with actual scope/results/limitations and owner-pending commit/tag. Update additional existing docs only if needed; do not invent mandatory `docs/TESTING.md` or `docs/COMPATIBILITY.md` files if absent.
7. Rebuild and rerun **entire** regression after the version change and docs/script edits; recheck `--version`, `--help`, `--map-info`, `--show-title`, `--show-walls`, `--show-textured-walls`. No references to version 0.2.0 should remain in active current-version claims (historical changelog entries must remain accurate).
8. Recheck Git diff, staged state, synthetic fixture cleanliness, license, secrets, commercial resource exclusion and owner WAD untouched; leave a reviewable worktree for owner acceptance.

The `CHANGELOG.md` release section should be similar to:

```text
## [0.3.0] - <actual release-preparation date> (prepared; owner commit/tag pending)
```

Document: static 320×200 textured wall-only renderer, canonical 3× GUI previews, 16.16/BAM/trig, online BSP visibility, middle/upper/lower textures, `COLORMAP` lighting; all tested scopes. Explicitly document **NO** floors, ceilings, sky, sprite/weapon overlay, masked midtexture back-to-front pass, gameplay, audio, PWAD overlays or verified Linux x64. Highlight documented <128-height and mask-hole deviations and any unfinished reference comparison. Avoid saying "game engine complete", "visplanes ready" or "bit-identical to vanilla Doom" without separate evidence.

Version gate failure policy: if any mandatory renderer/regression/resource/CLI gate fails, **do not** bump, or revert only this task's bump before reporting `BLOCKED`. If optional reference equivalence cannot be independently established, clearly report `PARTIAL` and leave original roadmap reference-comparison item unchecked; release-version readiness is an explicit owner decision, not a hidden inference from repeated hashes.

## 11. Git, whitespace, licensing and resource safety

- `git diff --check` and `git diff --cached --check` must both return `0`. Inspect **both** staged and unstaged snapshots; remember a staged version may become stale if further edits are made. **Never** perform `git add`, `git commit`, `git push`, `git tag` or force operations without owner approval.
- Check each new/untracked `.pb`, `.pbi`, `.md`, `.py`, `.ps1`, `.sh` for trailing spaces/tabs, mixed CRLF/LF, invalid UTF-8, accidentally saved binaries and unexpected generated caches. `git diff --check` alone ignores untracked content.
- Keep `AGENTS.md`, owner task files, source copyright headers and full `GPL-2.0-only` LICENSE intact. Document GPL and original id Software source attribution for new code.
- Confirm `data/DOOM.WAD`, `*.wad`, `*.iwad`, `build/`, screenshots, captures, textures, extracted source pixels, `.exe`/`.dll`, temporary test files and `__pycache__` are excluded. Use `git status --ignored` / `git ls-files` checks if needed; do not commit real IWAD assets or sample arrays.
- Owner screenshots remain ignored/private; synthetic numeric fixtures and **non-reconstructable hashes** are okay. Do not upload local data or engine-derived game graphics to external services.
- Record any pre-existing staged or unstaged files; don't claim worktree/index clean if it is not. Verify `git diff --cached --stat` **without modifying it**.

## 12. Acceptance criteria checklist

- [ ] M3-06 owner commit and actual `dev`/HEAD/index verified; pre-existing edits preserved.
- [ ] Pinned upstream inspected where relevant; Context7 lookup honestly reported if used.
- [ ] Whole WAD→resource→map→camera→BSP/visibility→projection→texture/cache/light→frame works with real PB 6.41 build.
- [ ] No second renderer/decoder; legacy M3-03/M3-04/M3-05 behavior remains unchanged.
- [ ] M3-04 frozen visibility/counter hashes and M3-05 frozen debug frame hashes remain identical.
- [ ] M3-06 synthetic independent fixtures, WT01–WT60 and TI01–TI03 remain PASS; full old regressions pass.
- [ ] M3-07 MR01–MR36 and RI01–RI03 run and pass with actual case/assertion numbers.
- [ ] Optional RI04 reports PASS with owner path, or honest NOT RUN; E1M1/E1M2/E4M1 inspected when owner IWAD available.
- [ ] Real owner textured hashes independently recomputed; any C-equivalent comparison gap labeled rather than silently locked.
- [ ] All GUI/CLI behaviors and exit codes checked; raw 320×200/3× scale semantics distinguished.
- [ ] A→B→A, cache invalidation, full reset, malformed input rollback and read-only IWAD tests pass.
- [ ] Actual Windows CPU/frame timing (or precisely explained NOT RUN) and no inner-column allocations documented; roadmap checkbox reflects reality.
- [ ] Release scope describes exact walls-only limitations; Linux runtime `NOT RUN` if true.
- [ ] Version bump and documentation applied only after mandatory gates; **post-bump** build and tests repeated.
- [ ] Git unstaged/staged/untracked whitespace/resources/license audit PASS; no agent staging/commit/tag/push.

**Decision:** `READY FOR OWNER ACCEPTANCE` (core release gates all PASS, with *explicit owner-decision items*), `PARTIAL / OWNER DECISION REQUIRED` (core PASS but milestone reference/performance criteria unresolved), or `BLOCKED` (core functional/safety gates fail). Never mislabel synthetic-only evidence as C-image equivalence. The owner decides whether to accept the documented v0.3.0 scope, commit and create an annotated `v0.3.0` tag.

## 13. Final technical report — required headings

```text
Task / milestone: M3-07 integration + v0.3.0 preparation
Git: branch, initial HEAD/M3-06 commit, index/worktree before and after; existing tags:
Windows OS / exact PureBasic compiler, real compiler/build commands and exits:
Linux compiler/runtime status (PASS / FAIL / NOT RUN; bash syntax separate):
Original upstream pinned SHA and C symbols inspected:
Documentation: Context7 USED / NO MATCH / UNAVAILABLE / NOT NEEDED; exact source/fallback:
Files created/modified, pre-existing owner material preserved:
Full integration topology and production API changes (if any):
WAD/map/camera/visibility/projected spans/texture cache/COLORMAP ownership:
Frame buffers, cleanup, A→B→A, rollback and malformed input results:
M3-04/M3-05 frozen numeric fingerprints, synthetic independent fixture results:
M3-06 real owner IWAD E1M1/E1M2/E4M1 repeat hashes (NOT LOCKED until independent proof):
Independent real-IWAD C-equivalent sampling / C image comparison: PASS / PARTIAL / NOT RUN and why:
Windows GUI window/size/close smoke and real visual observation:
Frame benchmark: cold/warm methodology, samples, min/median/p95, CPU/build; allocation counts:
MR01–MR36 and RI01–RI03: cases/assertions/failures/exits:
RI04 optional owner IWAD: PASS / FAIL / NOT RUN; actual counters:
All prior suite executable results (per-executable table):
Aggregate suites without IWAD vs with IWAD (M2 owner mode replaces synthetic; no double count):
Full scripts/test.ps1 checks and exact exit codes:
CLI --version/help/dump-info/lump-info/map-info/show-title/show-walls/show-textured-walls:
Version and CHANGELOG/README/PLAN/NOTES release wording, remaining M3 checkboxes:
Git diff --check/cached check, untracked audit, license and asset exclusion:
Known limitations, intentional C deviations, Linux and owner golden status:
Release decision: READY FOR OWNER ACCEPTANCE / PARTIAL-OWNER DECISION / BLOCKED:
Owner-only next steps: inspect staged diff, commit, annotated tag v0.3.0 (NOT performed):
```

**Stop at M3-07.** Do not implement M4, do not create a release or tag, do not push, and do not claim Windows evidence establishes Linux correctness.
