# DoomPB — M3-06: Textured wall columns and vanilla lighting

> **Task:** `M3-06` · **Milestone:** M3 — Geometry & First Walls (`v0.3.0`, **not yet released**)
> **Agent:** OpenCode Desktop, DeepSeek V4.1 Flash 1017, reasoning High
> **Target:** native PureBasic **6.41**, Windows x64; Linux x64 `NOT RUN` unless actually compiled and executed
> **Project:** DoomPB, GPL-2.0-only; owner-provided Ultimate Doom 1.9ud IWAD is strictly local
> **Primary reference:** `../doom-original/linuxdoom-1.10`, pinned commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> **Prerequisite:** M3-05 has been accepted **and committed**; verify branch/HEAD and working tree, do not assume a commit SHA
> **Status:** implementation assignment, not evidence of completed work

## 1. Mission

Replace M3-05's solid-color debug wall tiers with **actual 8-bit wall textures sourced from the owner's IWAD**, using the exact geometry, 320×200 framebuffer and online visibility spans already produced by M3-04/M3-05. Implement classic per-column texture-coordinate calculation, vertical stepping, offsets/pegging and **vanilla-scale COLORMAP lighting**. Keep the old debug-color mode fully functional and pixel-identical.

The owner must be able to view a deterministic static player-one perspective with recognizable textured **middle, upper and lower wall tiers** on E1M1, E1M2 and E4M1. This milestone is not full Doom rendering: black background/portal openings remain until M4 implements floors, ceilings, sky, sprites and masked wall textures.

**Do not** claim completion merely because a texture appears somewhere on screen. Require correct alignment, wrapping, clipping, tier selection, lighting, stable hashes and visual owner review.

### Explicit non-goals

- No M3-07 release/version bump; `--version` remains `DoomPB 0.2.0`.
- No M4 plane/flat/sky/sprite/weapon renderer, gameplay, animations, sound, movement or camera controls.
- No two-sided **masked middle textures** in the final framebuffer yet; these require deferred back-to-front drawseg/sprite-style clipping. Detect and report them; do not silently draw them as opaque walls or accidentally overwrite portals.
- No PWAD overlay support, new render backend, GPU renderer, SDL wrapper, floating-point coordinate replacement or modern texture filtering.
- No arbitrary 3D geometry modernization, broad refactors or unrequested commits/tags/pushes.

## 2. Required reading and initial state

Read these files **in the current repository**, not just a previous session summary:

1. `AGENTS.md` — including Context7 MCP rules and Git safety.
2. `docs/DEVELOPMENT_PLAN.md`, M3 Definition of Done; `docs/PORTING_NOTES.md`; `README.md` and current `CHANGELOG.md`.
3. `src/Core/{Fixed,Angle,TrigTables}.pbi`; `src/Renderer/{Geometry,Projection,Camera,WallView,BSP,ClipSegs,WallVisibility,WallProject,WallDraw,RenderMain}.pbi`.
4. `src/Graphics/{TextureDefs,Texture,PNames,Colormap,Palette,FrameBuffer,Video}.pbi`; actual flat catalog and `src/Map/{MapTypes,MapLevel,MapDecode,MapLoader}.pbi`.
5. `src/DoomPB.pb`, four `scripts/build.*`/`test.*` entry points, `tests/unit/wall_projection_tests.pb`, `tests/integration/m3_wall_render_tests.pb` and owner-IWAD counterpart.
6. Pinned original C files described in section 3 below.

Initial commands:

```powershell
git status --short --branch
git log -6 --oneline
git tag --list
Get-ChildItem src/Renderer, src/Graphics, tests/unit, tests/integration
```

Confirm the M3-05 commit is present on `dev`, verify the checked-out source and current test runner. If status shows unrelated or concurrent changes, **preserve them**; do not reset, clean or silently overwrite. Record pre-existing untracked task files as owner material. Present a short implementation plan and actual API inventory before coding.

### Documentation lookup (Context7)

Use the configured Context7 MCP **when looking up non-project APIs**, with a real resolve/query call and a focused topic (PureBasic 6.41 memory, typed pointers/structures, array layout, integer shifts, `PeekA`, `PokeA`, `AllocateMemory`, `FreeMemory`, image/GUI). The previously found `/websites/purebasic` is a possible result, **not proof that the specific 6.41 API is indexed**. If Context7 is missing, incomplete or lacks an exact version, record the result, consult official PureBasic documentation and installed CHM and use tiny real PB 6.41 compiler probes. Never invent MCP responses or trust another BASIC dialect. Keep private WAD bytes, local paths, credentials and graphics out of remote documentation prompts. Exact Doom semantics are determined from pinned original C, not Context7.

## 3. Original Doom source correspondence

| C source / symbols | Behavior to preserve or explicitly document |
|---|---|
| `r_segs.c:R_StoreWallRange` | `rw_normalangle`, original `rw_angle1`, `rw_distance`, `rw_offset`, `rw_centerangle`, `worldtop/worldbottom/worldhigh/worldlow`, texturemid and pegging |
| `r_segs.c:R_RenderSegLoop` | One texturecolumn per screen X; independent middle/top/bottom clipping and stepping, `maskedtexturecol` deferred |
| `r_main.c:R_ScaleFromGlobalAngle` | Existing M3-05 scale calculation; do not replace with a new approximation |
| `r_main.c:R_ExecuteSetViewSize` | `scalelight[LIGHTLEVELS][MAXLIGHTSCALE]` setup for 320-column full-detail view |
| `r_main.h` | `LIGHTLEVELS=16`, `LIGHTSEGSHIFT=4`, `MAXLIGHTSCALE=48`, `LIGHTSCALESHIFT=12`, `NUMCOLORMAPS=32` |
| `r_data.c:R_InitTextures`, `R_GetColumn`, `R_GenerateComposite` | Texture definitions, patch composition, texturewidthmask (highest power of two ≤ width, minus one), source-column behavior |
| `r_draw.c:R_DrawColumn` | Vertical `frac`, `fracstep`, inclusive `[dc_yl,dc_yh]`, 16.16 stepping and palette remap through `dc_colormap` |
| `r_defs.h`, `doomdata.h` | Seg and sidedef offsets, line flags `ML_DONTPEGTOP`/`ML_DONTPEGBOTTOM`, eight-byte names |
| `r_bsp.c:R_AddLine` | Already handled by M3-04; **do not** create another visibility calculation |

Record precisely which C functions were inspected, and which branches are deliberately deferred. Do not invent Doom function names. Important original formulas and their signed/unsigned interpretation:

```c
/* r_segs.c: wall-relative horizontal position */
offsetangle = rw_normalangle - rw_angle1;
if (offsetangle > ANG180) offsetangle = -offsetangle;
if (offsetangle > ANG90)  offsetangle = ANG90;
rw_offset = FixedMul(hyp, finesine[offsetangle >> ANGLETOFINESHIFT]);
if (rw_normalangle - rw_angle1 < ANG180) rw_offset = -rw_offset;
rw_offset += sidedef->textureoffset + curline->offset;
rw_centerangle = ANG90 + viewangle - rw_normalangle;

/* r_segs.c: per-pixel-column horizontal sample */
angle = (rw_centerangle + xtoviewangle[rw_x]) >> ANGLETOFINESHIFT;
texturecolumn = rw_offset - FixedMul(finetangent[angle], rw_distance);
texturecolumn >>= FRACBITS;

/* r_draw.c: vertical sample */
dc_iscale = 0xffffffffu / (unsigned)rw_scale;
frac = dc_texturemid + (dc_yl - centery) * dc_iscale;
source_row = (frac >> FRACBITS) & 127;
```

Original `r_data.c` selects horizontal source column using `col & texturewidthmask[tex]`, **not** a generic modulo by texture width. Reproduce for vanilla-compatible dimensions; define and test safe behavior for nonstandard dimensions and malformed assets. Note that original `r_draw.c` uses a hard-coded vertical `&127`: this cannot be blindly used to read past a short composed `TextureImage` plane. See section 6.5 for the mandatory safe policy.

## 4. Existing design contracts — reuse, do not rewrite

- `WallVisibilityBuild` emits chronological `WallSpan` records (`Subsector`, `Seg`, `Linedef`, `Side`, `FrontSector`, `BackSector`, `FirstX`, `LastX`, `Kind`). **Do not sort, deduplicate or re-run BSP**; no changes to M3-04 hashes or clipping algorithm.
- `WallProjectSpanChecked` already creates `WallSpanPlan` including view/normal/seg angles, distance, scale, world heights, tier flags and vertical interpolation. Extend through narrow helpers, not a second renderer geometry formula.
- `WallRenderFrame` + `WallDraw` implement the **existing** solid-color `--show-walls` mode. Preserve all its functions, palette indices and golden hashes. Prefer a separate `TexturedWallRenderFrame`/mode; if sharing code, preserve legacy output exactly.
- `TextureCatalog` resolves first-match texture names and PNAMES patch references against the currently open WAD. `TextureCompose` creates caller-owned **row-major 8-bit pixels and opacity mask**; `TextureImageReset` releases these buffers. Composite bytes are already sufficient for CPU column sampling; do not copy the original renderer's pointer-based column-cache layout wholesale.
- `ColormapDecode` stores exact 256-byte lookup tables. Use `ColormapLookup` or a checked/prevalidated fast path, preserving access bounds and table identity.
- `FrameBuffer` holds a 320×200 **palette-index** plane. Use its existing buffer and `VideoShowFramebuffer` (3× nearest-neighbor); no RGB texture storage or GPU filtering.
- Use existing map accessors; sidedef `TextureOffset`/`RowOffset`, seg `Offset` and floor/ceiling heights are **map units**; convert to signed 16.16 exactly where original renderer requires.
- `WallRenderPlayerStartView` identifies the single player-one THING and static floor+41 unit view height. Reuse it; do not infer another camera when absent.

## 5. Deliverables and recommended boundaries

Choose final filenames after inspecting existing includes and naming conventions. Recommended minimal additions:

| File | Responsibility |
|---|---|
| `src/Renderer/WallTextureCache.pbi` | Per-frame or per-IWAD used-texture catalog, precomposed owned images, width-mask/height metadata, load/reset/invalidation; no per-column I/O |
| `src/Renderer/WallTextureMapping.pbi` | Narrow checked helpers for `rw_offset`, texel column, texturemid/pegging, vertical source sample; pure and independently testable |
| `src/Renderer/WallLighting.pbi` | Vanilla 320-column `scalelight` table selection and COLORMAP index lookup; no RGB conversion |
| `src/Renderer/TexturedWallDraw.pbi` | Draw middle/upper/lower textured columns into row-major indexed framebuffer using M3-05 tier bounds |
| `src/Renderer/TexturedRenderMain.pbi` | Orchestrate texture cache, WallSpanPlan, colormap, private-frame publication, stats/hashes |
| `src/DoomPB.pb` | Explicit new `--show-textured-walls <ExMy>` mode (or equivalent distinct flag, document choice), preserve old CLI |
| `tests/unit/wall_texture_tests.pb` | WT01–WT60 synthetic tests, no IWAD |
| `tests/integration/m3_wall_texture_tests.pb` | TI01–TI03 synthetic end-to-end tests |
| `tests/integration/m3_wall_texture_iwad_tests.pb` | Optional TI04 real IWAD E1M1/E1M2/E4M1 |
| `scripts/gen_wall_texture_golden.py` | Independent numeric/color mapping oracle/golden generator with no commercial bytes |
| `tests/fixtures/m3_wall_texture_golden.pbi` | Synthetic test-only vectors/hashes; generated from independent oracle |

File naming is guidance, not a reason for unnecessary abstractions. A compact solution is acceptable if tests/ownership are equally clear. Never create empty placeholder modules or duplicate M2 texture parsing. New source files require GPL-2.0-only SPDX and appropriate upstream attribution. `src/DoomPB.pb` includes M3-06 source in compiler-verifiable order with no duplicate procedures.

## 6. Implementation requirements

### 6.1. Texture and material resolution

1. Read wall names from the **correct sidedef for the seg's side** (`side 0/1` mapping already derived by M2/M3-04). Preserve eight-byte canonical slot handling, `-`/all-NUL absence where appropriate and first-match behavior in `TextureCatalogFindName`.
2. Resolve upper/lower/middle **only where the corresponding tier actually requires a wall texture**. Never treat `-` as a real texture. Two-sided masked middle slot may exist but must be **deferred**, not painted as a normal opaque middle tier.
3. Preserve original distinction of texture catalog index 0 versus no texture. Do not assume catalog index `0` means absent; use explicit validity/presence booleans.
4. Validate `TextureCatalogResolve` against the currently open WAD. If the WAD is closed/reopened or source changes, invalidate and re-resolve indices before composing. No stale `lumpIndex` reuse.
5. Prefer composing **only unique textures referenced by visible supported tiers**, not blindly copying all WAD textures. Optional one-time all-texture verification is fine in a separate test.
6. Cache owns composed images until rendering finishes. Distinct slots must never shallow-copy owning `TextureImage` structs and double-free. Reset and failure paths free every allocation exactly once. Cache has no retained borrowed MapLevel/WAD buffer/pointer after finalization.
7. No WAD I/O, new texture composition, `AllocateMemory` or `ReAllocateMemory` inside per-column/per-pixel loops. Count allocations and peak cache bytes; apply checked reasonable memory/work budgets.
8. Validate mask/pixels plane pointers, dimensions, pixel count, opaque flags and every index before reads. Palette index `255` remains a valid source color, never a transparency sentinel.

### 6.2. Horizontal texture-column coordinate

- Use stored **original** un-clipped seg endpoint angle (`ReferenceAngle` or equivalent), segment angle `SHORT << 16` to BAM, `NormalAngle`, `Distance`, view heading and `ProjectionGetXToViewAngle()`; do not recompute from clipped screen endpoints.
- Implement `rw_offset` exactly as `R_StoreWallRange`: compute BAM subtraction/wrap, conditional sign/clamp, `finesine` lookup and signed 16.16 `FixedMul`, then add signed 16.16 sidedef and seg offsets. Do not conflate `SEGS.offset` with `SIDEDEFS.textureoffset`.
- For each screen column use `rw_centerangle + xtoviewangle[x]`, `finetangent` lookup and fixed multiply/subtract as C. No floats, `ATan2`, linear texture-X interpolation or screen-space fake scrolling.
- Apply **vanilla width mask**, not `% Width`: `mask = highest_power_of_two_not_exceeding_width - 1`; `wrappedColumn = rawColumn & mask` in signed/unsigned 32-bit-consistent semantics. Test width 64, 96, 128, 256, negative and extremely large raw columns. Keep every actual lookup in `0..Width-1`.
- Use `.q` for intermediate validations; explicitly document the sites that intentionally reproduce 32-bit low bits, signed arithmetic shift or clamp, versus sites that reject unsupported overflow. Never depend on undefined C signed overflow or accidental PureBasic promotion.

### 6.3. Vertical mapping and tier alignment

- Reproduce `dc_iscale = 0xFFFFFFFF / unsigned(rw_scale)` (scale is strictly positive); test quotient boundary/rounding. Use `frac = dc_texturemid + (dc_yl-centery)*dc_iscale` with original 16.16 low32/shift behavior; advance once per painted Y, including inclusive last row.
- Calculate **middle**, **upper** and **lower** `dc_texturemid` using `r_segs.c:R_StoreWallRange`, actual texture height and sidedef `rowoffset`, preserving `ML_DONTPEGTOP` and `ML_DONTPEGBOTTOM` semantics. Keep sky adjacency hack and world-height adjustments from M3-05. Tests must distinguish pegged and non-pegged columns.
- Preserve shared `ceilingclip`/`floorclip` across chronological `WallSpanPlan`s; reuse exact M3-05 source-tier boundary/mark-only branches and `pixhigh/pixlow` steps. Drawing pixels must **not** alter underlying visibility order or try to fill sky/flat/portal gaps.
- Support one-column spans, upper-only, lower-only, combined upper/lower, closed doors, occluded columns and out-of-frame edge candidates. Never draw a two-sided midtexture as a solid middle wall.
- Bound all writes to `x=0..319`, `y=0..199`, and `palette index 0..255`. Validate target untouched on failure.

### 6.4. Vanilla COLORMAP lighting

- Decode `COLORMAP` through existing `ColormapDecode`; require at least **32×256** valid bytes for classic wall lighting, even if the lump has more tables. Palette #0 remains default for GUI presentation.
- For the canonical 320-wide, detailshift=0 viewport, preserve `scalelight[16][48]` selection, `LIGHTSEGSHIFT=4`, `LIGHTSCALESHIFT=12`, and source integer truncation. Reconstruct `startmap`, `level = startmap - j*SCREENWIDTH/(viewwidth<<detailshift)/DISTMAP` (`DISTMAP=2`) and clamp to 0..31.
- Determine light tier from front-sector lightlevel and orientation: source `horizontal -> lightnum--`, `vertical -> lightnum++`, clamp 0..15; no arbitrary shading constants. Use `scale >> 12`, clamp 0..47, then map source texel via `colormap[lightTable][texel]`.
- No runtime RGB shading, bilinear filtering, color interpolation or direct changes to source `TextureImage` pixels. `fixedcolormap`, extra light flashes, sector dynamic lighting and gamma outside static MVP are deferred/documented; static `extralight=0`.
- Provide tests against independent table calculations for sectors with different lightlevels, vertical/horizontal/diagonal lines, minimum/maximum scales and actual owned `COLORMAP` bytes.

### 6.5. Transparency, height and non-128 source rows — safety contract

The original `R_DrawColumn` computes `source_row = (frac >> 16) & 127`, indexing a column source created by `R_GetColumn`; DoomPB's M2 composed pixels are stored in a **bounded row-major plane of `Width*Height`**. Blindly reading row 127 from a height 64 image would be invalid.

Required policy:

1. For ordinary **128-high opaque** wall textures, exactly reproduce `&127`, including negative `frac` and wrap, and compare with independent C-equivalent tests.
2. For non-128 texture heights, use an **explicit documented safe policy**, e.g. a virtual 128-row column constructed outside the pixel loop with proven bounded mapping to source rows. Establish this policy from original `R_GetColumn`/composite behavior where possible. If exact byte behavior cannot be established, label the divergence and use a deterministic checked fallback; **never** read past the composed plane.
3. Respect the source opacity mask: it is **not** a palette value. For a required opaque wall tier, decide upfront whether uncovered source texels should trigger a checked diagnostic/rejection or an explicitly tested safe fallback. Do **not** silently substitute palette index zero or use 255 as transparent. Keep true translucent/masked wall overlays deferred.
4. Add synthetic height tests (32/64/72/128/256), mismatched and corrupt masks, negative fractional coordinates, large step sizes, transparency holes and all valid palette indices.
5. For the owner's genuine IWAD, count textures that require a non-128 or mask fallback and include these counts in the report. Do not claim exact vanilla compatibility for cases supported only by a safe alternative.

### 6.6. Orchestration, modes, ownership and hashes

- Separate **existing** `--show-walls <ExMy>` (M3-05 debug colors) from new **opt-in** `--show-textured-walls <ExMy>` (M3-06). Do not modify M3-05 frame checksums, arguments, exit codes or title behavior. New option must be mutually exclusive with `--dump-info`, `--map-info`, `--show-title`, etc.
- Reuse the existing WAD→PLAYPAL/PNAMES/TEXTURE1/2→flat catalog→validated `MapLevel`→`Projection`→player-one `WallView`→`WallVisibilityResult` startup pipeline. Add `COLORMAP` and cached composed textures, without a duplicate map loader or a speculative second BSP pass.
- Render into a private 64,000-byte palette-index framebuffer; **publish target only on full success**. Failure leaves the owner's previous target pixel buffer byte-for-byte unchanged, frees private resources and emits precise map/seg/tier/texture/column diagnostics.
- Derived numeric result retains only copied metadata and hash; no unowned pointers to texture cache, WAD, MapLevel or framebuffer after reset. `Close`, `Reset`, reopen and repeated frame generation must be deterministic and memory-safe.
- Hash exactly 320×200 row-major **palette bytes**, FNV-1a64 offset 14695981039346656037 (signed `.q` form if needed), prime 1099511628211; publish 16 uppercase hex digits with leading zeros. No GUI/RGBA/scaling bytes in authoritative hash.
- Render at least three times per map (fresh / repeated / Reset and rebuilt), and compare full pixel buffers as well as hash. Check no uninitialized pixel bytes, write overrun, out-of-frame columns or per-pixel allocation.
- Keep optional GUI title clear: `DoomPB - Textured Walls - E1M1` or equivalent; show at 3× nearest-neighbor by reusing `VideoShowFramebuffer` and PLAYPAL, not rescaling original bitmap assets.
- Recheck source 320×200 vs produced 960×600 using the existing nearest-neighbor RGBA converter. The prior M3-05 PrintWindow images showed possible edge pixels; distinguish **raw framebuffer correctness** from window-system capture effects without blaming projection unless a raw mismatch is proven.
- Do not commit PrintWindow captures, DOOM.WAD bytes, extracted textures or proprietary pixel golden images. Store only hashes, counts, synthetic fixtures and numerical metrics.

## 7. Required tests: WT01–WT60

Use **60 individually named synthetic cases**. These test IDs/categories are mandatory; assertion counts are determined by executed tests, **not fabricated**. Prefer independently computed expected values and source-derived vectors instead of snapshotting the first result from the production implementation.

| ID | Required focus |
|---|---|
| WT01 | Valid texture catalog/first-match binding and index-zero identity |
| WT02 | Absent `-`/all-NUL slots versus valid texture name |
| WT03 | Correct seg-side → sidedef → upper/lower/middle selection |
| WT04 | Fail on invalid/embedded NUL, missing or unreadable required resource |
| WT05 | Duplicate texture names, deterministic TEXTURE1/TEXTURE2 precedence |
| WT06 | Duplicate PNAMES patch resolution and reopen invalidation |
| WT07 | Used-texture cache uniqueness: repeated spans share one composed image |
| WT08 | Correct ownership/reset with no double-free or borrowed WAD pointers |
| WT09 | Composition failure leaves cache/target safely recoverable |
| WT10 | Compose before WAD close; read owned pixels after close |
| WT11 | Unsigned BAM normalangle + original unclipped reference-angle usage |
| WT12 | `offsetangle` signed/unsigned comparisons and `> ANG90` clamp |
| WT13 | Correct signed fixed-point `rw_offset` and seg-side offsets |
| WT14 | Separate SIDEDEFS.textureoffset and SEGS.offset contributions |
| WT15 | Horizontal column calculation for center and adjacent x positions |
| WT16 | Lookup wrap: 64-wide texture, positive/negative columns |
| WT17 | Vanilla width mask for 96-wide texture differs from modulo 96 |
| WT18 | Width-mask edge for 128/256-wide textures |
| WT19 | Overflow/negative offset diagnostics, no accidental OOB lookup |
| WT20 | `rw_centerangle` + `xtoviewangle` boundary/angle index behavior |
| WT21 | `dc_iscale = 0xFFFFFFFF / scale`, exact truncation |
| WT22 | Initial `frac` around `centery=100`, signed16.16 and negative |
| WT23 | Advance `frac` for each inclusive source row |
| WT24 | 128-row source `&127` wrap for positive/negative frac |
| WT25 | 32-high source safe fallback, deterministic and bounded |
| WT26 | 64-high source safe fallback, deterministic and bounded |
| WT27 | 72-high source safe fallback, deterministic and bounded |
| WT28 | 256-high source safe fallback, documented difference if any |
| WT29 | Opaque mask including palette index 0/255 |
| WT30 | Transparent-mask hole safely rejected or explicitly handled |
| WT31 | One-sided middle alignment with default peg |
| WT32 | One-sided middle `ML_DONTPEGBOTTOM` alignment |
| WT33 | Middle sidedef `rowoffset` (including negative) |
| WT34 | Two-sided upper default peg versus `ML_DONTPEGTOP` |
| WT35 | Two-sided lower default peg versus `ML_DONTPEGBOTTOM` |
| WT36 | Upper+lower tiers in one column, no accidental middle fill |
| WT37 | Open portal/mark-only branches preserve black gap |
| WT38 | Closed door front/back heights and clip updates |
| WT39 | One-column wall span with scaleStep=0 |
| WT40 | Ceiling/floor clip overlap; no out-of-bounds writes |
| WT41 | Full 32-table COLORMAP decoding/availability gate |
| WT42 | 16×48 scalelight index calculation vs independent oracle |
| WT43 | Horizontal versus vertical wall lighting correction |
| WT44 | Diagonal line neither horizontal nor vertical correction |
| WT45 | Bright/dark front sector light levels, valid clamping |
| WT46 | `rw_scale >> 12` selected column light-index boundaries |
| WT47 | Mapped palette sample includes 0 and 255 |
| WT48 | Repeated lighting does not mutate source composed textures |
| WT49 | Missing/truncated COLORMAP yields error/rollback |
| WT50 | Fallback/policy counters for short or irregular textures |
| WT51 | Two-sided masked middle detected and **deferred**, not opaque |
| WT52 | Deterministic ordered spans, no BSP re-walk or sort |
| WT53 | Multi-span same screen column shared clip state |
| WT54 | FrameBuffer 320×200, strictly bounded read/write |
| WT55 | Commit-on-success private target, previous frame unchanged on late error |
| WT56 | Reset/rebuild does not change a full 64,000-byte synthetic frame |
| WT57 | FNV-1a64 canonical byte stream, leading-zero formatting |
| WT58 | Cache and renderer have no per-column/per-pixel allocations |
| WT59 | Legacy debug mode produces the **exact M3-05** synthetic hashes |
| WT60 | CLI/GUI nearest-neighbor and 320→960 scale equality |

Some tests may combine several assertions; test names and actual count must remain explicit in output. Never weaken an assertion, alter a frozen M3-05 golden or update expected data just because production produced a different value. A regression requires root-cause analysis with pinned C and independent oracle.

## 8. Synthetic integration: TI01–TI03

- **TI01 — Synthetic WAD resources → textured wall frame:** create self-authored small PNAMES, TEXTURE1, patches (including multiple patch composition), COLORMAP, flats, ten-lump level; load through production APIs; render a one-sided middle and assert exact numeric coordinates, palette samples, lighting, checksum and full 320×200 pixel plane against an **independent Python/source-derived** oracle.
- **TI02 — Two-sided wall geometry:** near solid, farther pass portal, upper and lower tiers, differing heights, horizontal/vertical/diagonal lighting and exact peg offsets. Compare rendered column samples and intact portal holes; assert M3-04 visibility hashes unchanged; check no per-column allocation or out-of-bounds pixel.
- **TI03 — Ownership and failure/reopen:** A→B→A WAD lifecycle, texture cache invalidation, no stale patch indices, reset/repeated frames, malformed missing textures/COLORMAP, rollback on late failure, all buffers freed and deterministic hashes.

No synthetic integration should depend on a commercial WAD or display. Generator `scripts/gen_wall_texture_golden.py` must be deterministic, portable, documented and able to regenerate fixtures byte-for-byte; run it twice and compare output hashes. Do not use production rendering output as sole oracle.

## 9. Optional owner-IWAD integration: TI04

**Only run if a legal owner-provided IWAD path exists**. The known local fixture is `data/DOOM.WAD` (Ultimate Doom 1.9ud), MD5 `c4fe9fd920207691a9f493668e0a2083`, size 12,408,292 bytes; this identifies **one** revision and must not exclude all other legal IWADs.

1. Verify WAD identity before/after, read-only, without writing game bytes, screenshots or decoded texture pixels into repository.
2. Load and validate E1M1, E1M2, E4M1; derive original player-one spawn X/Y/heading/viewz; create unchanged M3-04 visibility spans and M3-05 wall plans.
3. Compose each **used** visible wall texture while WAD indices are valid; validate dimensions, masks, names and memory budgets. Log counts of composed images, cache hits, short/non-128 textures, masked-midtexture skips and invalid/safe-fallback texels, without dumping pixels or WAD sections.
4. Generate textured frames for all three maps, verify color/textured pixels appear, detailed middle/upper/lower counters, no out-of-frame accesses and no corrupt index read. Ensure same 64,000-byte frame/hash on multiple independent runs.
5. Demonstrate **non-equality** of textured frame to debug-color frame where expected; simultaneously rerun the debug mode and verify these frozen M3-05 hashes: E1M1 `4A923E4D357C7BD1`; E1M2 `0C9627E5C2FD8D35`; E4M1 `9AEB8BDD16834359`.
6. Verify unchanged M3-04 span/counter hash pairs: E1M1 `74B485154CE29B0B` / `7ADB45DBF2611B77`, E1M2 `8AC0627513C4B619` / `83CAB0E1049B850A`, E4M1 `9FD0B15A0F33197E` / `CCAA2442EB270717`.
7. Lock **new** textured frame goldens only after independently reviewing C-equivalent sampling on selected positions, running the Python oracle, full-buffer repeatability and visually inspecting a real window. Include clear report distinction between "stable" and "visually source-correct".
8. GUI smoke: `--iwad data/DOOM.WAD --show-textured-walls E1M1/E1M2/E4M1` should open 960×600 windows, close normally and exit 0. In a manual visual review check texture alignment at corners, seams, pegging, upper/lower bands, portals, walls near camera, and no garbled pixels.
9. If no legal IWAD is available, report **TI04 NOT RUN**, do not mark it PASS, do not invent hashes, and keep all synthetic tests passing.

## 10. Verification, builds and cumulative test accounting

Extend **both** build/test platforms' scripts, preserving all existing options. Suggested PowerShell selectors `-WallTextureTest`, `-WallTextureIntegrationTest`, `-WallTextureIwadTest`; Bash selectors `--wall-texture-test`, `--wall-texture-integration-test`, `--wall-texture-iwad-test`. Check the scripts' existing design before choosing exact names.

Required actions on Windows x64 with the installed **PureBasic 6.41**:

```powershell
./scripts/build.ps1 -Check
./scripts/build.ps1
# Build/check each new unit, integration and IWAD harness using new script selectors.
./scripts/test.ps1
./scripts/test.ps1 -IwadPath data/DOOM.WAD  # only when legal local file is present
./build/DoomPB.exe --version
./build/DoomPB.exe --help
./build/DoomPB.exe --iwad data/DOOM.WAD --map-info E1M1
./build/DoomPB.exe --iwad data/DOOM.WAD --show-walls E1M1
./build/DoomPB.exe --iwad data/DOOM.WAD --show-textured-walls E1M1

git diff --check
git diff --cached --check
git status --short
git diff --stat
```

Run actual `pbcompiler ... --check` and executable builds for every new test harness. Verify CLI exit codes (`0` success, `1` runtime error, `2` invalid arguments), absence of mode conflicts and stable old `--show-title` 960×600 behavior. An `--check` success is NOT a successful build; Git Bash `bash -n` is NOT a Linux build/run.

**Verified prior M3-05 baseline to preserve**, not a prediction of new totals:

- Without IWAD: **629 cases / 4,934 assertions / 0 failures**.
- With owner-IWAD (replace M2 synthetic 35/221 by owner 36/240; do not double-count): **635 cases / 5,464 assertions / 0 failures**.
- PowerShell script: **131/131 checks** without owner IWAD; **165/165 checks** with owner IWAD.
- M3-05 unit/integration: WP01–WP56 **56/738**, WI01–WI03 **3/147**, optional WI04 **1/288**.

Do not hardcode expected **new** case/assertion/check counts. Report actual per-executable outputs and sum exactly once. Clearly distinguish optional IWAD NOT RUN from PASS and provide zero failures only if observed. Do not silently change previous suite expectations/hashes to compensate for regression.

### Git safety

All new tests/fixtures must be fully synthetic numeric or synthetic pixel arrays (not pieces of commercial Doom images). No WAD or extracted resource data, captures, executable output, generated PNG, CHM, external model API key or other commercial/private bytes may be committed. Prefer ignored `build/` for local rendered captures; leave them on user's machine. No unrelated refactors, license changes or destructive Git commands. **Do not `git add`, `commit`, `push`, or `tag` without owner approval**, even when checks pass. Keep `v0.3.0` uncreated.

## 11. Documentation expectations

Update only relevant sections of `README.md`, `CHANGELOG.md`, `docs/PORTING_NOTES.md` and `docs/DEVELOPMENT_PLAN.md`:

- Explicit new textured-preview CLI and existing debug-preview CLI.
- Accurate readiness scope: walls yes, **floors/ceilings/sky/sprites/masked midtextures no**. M3-06 completion does not itself authorize M3-07 or version bump.
- Actual files, original C correspondences, signed arithmetic and lighting details, cache lifetime and WAD reopening contract.
- Width-mask and non-128 texture-height policies with precise divergence notes, mask-hole policy, fixedcolormap/lighting limitations.
- Actual tests/case/assertion totals and golden hashes; distinguish Windows PASS from Linux NOT RUN.
- Include any required notices/attribution; avoid embedding owner-owned source resources.

## 12. Acceptance checklist

- [ ] Git baseline and M3-05 commit verified; no concurrent user edits overwritten.
- [ ] Context7 consulted for API questions, with actual result/fallback accurately reported.
- [ ] Exact C column coordinate, `dc_iscale`, vertical mapping/pegging and 320-column light-map algorithm implemented.
- [ ] Existing TextureCatalog/TextureCompose/COLORMAP/FrameBuffer reused; no new image engine.
- [ ] Non-128 dimensions, negative coordinates and opacity holes have bounded documented behavior.
- [ ] No per-column WAD read, patch compose, allocation or unsafe raw pointer retention.
- [ ] Two-sided masked midtextures are explicitly deferred, not treated as opaque walls.
- [ ] `--show-textured-walls` operates without replacing `--show-walls`; CLI conflicts validated.
- [ ] WT01–WT60, TI01–TI03 pass with real builds; optional TI04 honestly PASS or NOT RUN.
- [ ] Owner IWAD: E1M1/E1M2/E4M1 render real texture pixels and show credible perspective/pegging in actual GUI.
- [ ] M3-04 and M3-05 golden hashes preserved; full regression passes; sums independently verified.
- [ ] Private framebuffer publication/rollback tested; deterministic hashes and cleanup proven.
- [ ] `git diff --check` and untracked whitespace/resource/license audits PASS; staged state disclosed separately.
- [ ] No M3-07 work, no version bump, no staging/commit/push/tag.

If the core textured wall path cannot meet these criteria, report **BLOCKED** with exact unmet checks; do not label it READY. If all M3-06 requirements are observed, report **READY FOR OWNER ACCEPTANCE (M3-06 only)**. No source or tests can be considered verified on Linux without real Linux compiler/run evidence.

## 13. Final report template

Provide a **detailed technical report** with these headings, accurate command exits and measured evidence:

```text
Task / milestone: M3-06 only
Git branch, HEAD, M3-05 commit, initial/final staged + worktree state:
Windows environment and exact PureBasic compiler banner:
Linux status: PASS / FAIL / NOT RUN (what was actually done):
Pinned upstream SHA and exact C symbols inspected:
Documentation: Context7 USED (real library ID/topic) / NO MATCH / UNAVAILABLE / NOT NEEDED; official fallback:
Files created / modified:
Design: texture cache ownership, image composition and WADClose/reopen:
Texture selection/column mapping, width masks and arithmetic:
Vertical stepping and pegging per tier:
COLORMAP lighting constants and independent calculations:
Non-128 height, transparency and malformed-input policies:
Masked middle textures deferred: detection and counts:
WT01–WT60: cases / assertions / failures / command exits:
TI01–TI03: cases / assertions / failures / deterministic hashes:
TI04 (optional): PASS / FAIL / NOT RUN; E1M1/E1M2/E4M1 frame hashes and pixel counts:
Legacy M3-04/M3-05 fingerprints and regression:
Aggregate tests: without owner IWAD / with owner IWAD (no double count):
Actual scripts/test.ps1 checks; syntax/build/GUI smoke results:
Raw framebuffer vs scaled-window check:
Git diff/whitespace/license/commercial-asset audit:
Known limitations, source deviations, memory budgets and CPU measurements (if measured):
Release decision: READY FOR OWNER ACCEPTANCE / BLOCKED for M3-06 only
Suggested next task: M3-07 integration and v0.3.0 preparation (do not begin)
```

Stop at M3-06. Owner decides acceptance and commit separately.
