# Changelog

All notable changes to DoomPB are recorded here. The project is licensed under
GPL-2.0-only; commercial Doom game data is never included.

## [Unreleased] — M4-01 visplanes + real flats (partial M4)

M4-01 adds the first M4 slice in the existing online M3 pipeline while application
version `0.3.0` and prior M1/M2/M3 APIs/outputs stay intact. It collects online
visplanes at subsector entry (`R_FindPlane`), checks/widens/splits emitted spans
(`R_CheckPlane`), marks floor/ceiling bands before clip mutation, builds spans and
draws real 64x64 `FlatLoad` floors/ceilings after the textured wall pass using
source-formula `R_MapPlane`/`R_DrawSpan`, `zlight[16][128]` and `COLORMAP`.
`F_SKY1` is recognized/normalized/deferred with band/pixel counts and never loaded
or drawn as a flat. The opt-in `--show-planes <ExMy>` preview combines walls,
floors/ceilings and deferred sky background at 3x for E1M1/E1M2/E4M1.

### Added

- `src/Renderer/Planes.pbi`: visplane frame, source-order Find/CheckPlane, 322-
  column top/bottom boards, pre-clip MarkCeiling/MarkFloor, subsector eligibility,
  sky resolution, timeline visits.
- `src/Renderer/PlaneFill.pbi`, `PlaneDraw.pbi`: exact MakeSpans open/close order
  with sentinels, bounded row-span trace, 16.16 row cache and inclusive span draw.
- `src/Renderer/PlaneMapping.pbi`, `PlaneFlatCache.pbi`: yslope/distscale/base
  scales, checked planeheight/light row, 16x128 zlight map indexes, used-only
  owning flat image cache.
- `src/Renderer/PlaneRenderMain.pbi`: transactional combined wall+flat frame,
  explicit 0/1 64,000-byte coverage audit, owned private frame discarded on error,
  optional span trace, counters and FNV result.
- `--show-planes` CLI wiring plus `DoomPB - Textured Walls + Flats` window title.
- `scripts/gen_plane_golden.py` independent integer oracle → tracked synthetic
  fixture `tests/fixtures/m4_plane_golden.pbi`; P02 synthetic map builder.
- `tests/unit/plane_render_tests.pb` PL01–PL60, `tests/integration/m4_plane_tests.pb`
  PI01–PI03, optional `tests/integration/m4_plane_iwad_tests.pb` PI04; wired
  `-PlaneTest`/`-PlaneIntegrationTest`/`-PlaneIwadTest` and Bash equivalents.

### Verified (Windows x64, PureBasic 6.41)

- PL01–PL60: 60 cases, 211 assertions, 0 failures.
- PI01–PI03: 3 cases, 76 assertions, 0 failures; full synthetic frame hashes
  `59E2505D8A6CAD85` (PI01) and `CE2C4D994F5EDF3A` (PI02) match the independent
  oracle byte-for-byte; legacy M3-06 synthetic hash preserved.
- PI04 owner: 1 case, 150 assertions, 0 failures; IWAD 12,408,292 bytes/MD5
  `c4fe9fd920207691a9f493668e0a2083` read-only unchanged. Combined floor/ceiling/
  sky counters: E1M1 floor 25695/ceiling 25937/sky 0, E1M2 24660/24982/0, E4M1
  22644/11516/1191 deferred sky pixels. New combined raw hashes
  `B6C3BD9880758292`, `D32BD22FF01A9BBB`, `0AFA2E970F9C08C8` are **NOT LOCKED**.
  Frozen M3-04 span/counter and M3-05 debug hashes preserved; historical M3-06
  textured hashes unchanged (NOT LOCKED).
- Full Windows regression scripts run **211/211 checks** without an IWAD and
  **291/291 checks** with the owner IWAD, both exit 0; seven `--show-planes`
  CLI smoke cases (13 assertions) pass alongside every prior suite.
- Real GUI M4-01 previews E1M1/E1M2/E4M1: verified 960x600 client area, clean
  window close exit 0, and `PrintWindow` client captures visually show real
  textured floors/ceilings and deferred black `F_SKY1` background with no
  observed wall overwrite/striping. Screenshots live only in ignored temp
  storage and are never tracked.

### Known gaps / deviations

- No M4-02 sky pixel texture, sprites, masked-midtexture back-to-front overlay or
  gameplay; combined preview is a partial M4 development slice.
- Plane bottom padding cells are `0` (top sentinel `0xFF` unchanged) instead of
  source-uninitialized values; documented safe test surface.
- Lower-tier fill clamp uses the pre-column clip snapshot consistent with the
  frozen M3 wall rasterizer; documented difference from source ordering.
- Linux x64 runtime **NOT RUN**; Bash scripts are syntax-only under Git Bash.
- New owner combined hashes are not accepted goldens without independent
  same-camera source comparison.

## [0.3.0] - 2026-11-27 (prepared; owner commit/tag pending)

M3-07 closes Windows x64 integration of M3-01 through M3-06 as a truthful
**wall-only textured preview** release scope. Application version `0.3.0` was
prepared only after mandatory smoke/regression/resource/GUI gates; owner staging,
commit and annotated tag remain pending. M3-01, M3-02, M3-03, M3-04, M3-05, M3-06
and M3-07 modules/tests are in the working tree. M3-04 produces headless, owned
numeric screen-column visibility intervals and counters. M3-05 adds checked static
viewz, exact `R_StoreWallRange`/`R_ScaleFromGlobalAngle` vertical projection and
12-bit interpolation, a transactional 320x200 wall-only frame with one-color
middle/upper/lower tiers and an opt-in player-start preview. M3-06 turns those
tiers into composed wall-texture columns with exact horizontal coordinates/width
masks, `dc_iscale` vertical stepping, pegging texturemids and vanilla
`scalelight[16][48]` `COLORMAP` lighting. M3-07 adds the synthetic MR01-MR36 +
RI01-RI03 release matrix, optional real-IWAD RI04, BEN01 timing and wired build/
test targets, preserving the older debug/textured fixture layers. Complete vanilla
`drawseg_t`, masked midtexture back-to-front drawing, visplanes/flats/sky, sprites,
gameplay/audio/saves/demos and verified Linux x64 remain later or unverified work.


### Added

- `src/Core/Fixed.pbi`: dependency-free signed 16.16 arithmetic (`FixedMul`,
  early-saturating `FixedDiv`, checked `FixedDiv2Checked`, checked integer/map
  conversions, arithmetic floor extraction and explicit low-32 wrap) reproducing
  Linux Doom 1.10 `m_fixed.c` observable behaviour without `I_Error` or C UB.
- `tests/unit/fixed_math_tests.pb`: FM01–FM40 plus FI01–FI03 synthetic cases with
  independent floor/guarded/double oracles, a fixed LCG seed and deterministic
  repeatability (43 cases, 318 assertions).
- `tests/integration/m3_fixed_iwad_tests.pb`: optional read-only FI04 bridge that
  converts signed E1M1/E1M2/E4M1 vertex coordinates and sector heights to 16.16
  and verifies reproducibility (REPORT ONLY / NOT RUN without a WAD path).
- `-FixedTest` / `--fixed-test` build targets; optional `-FixedIwadTest` /
  `--fixed-iwad-test`; both test runners execute the new suites.
- `DoomPB.pb` includes the math module without changing CLI or gameplay logic.

- `src/Core/Angle.pbi`: raw unsigned 32-bit BAM constants, modulo-2^32
  add/subtract/negate, fine-index `(raw>>19)&8191`, signed-bit transport
  documentation and a Quad angle result carrier for `ANG180`/`ANG270`.
- `src/Core/TrigTables.pbi` + generated `TrigTablesData.pbi`: exact pinned
  `finetangent` (4096), `finesine` (10240) and `tantoangle` (2049) values in an
  immutable DataSection, validated indexes, the original cosine sine-offset
  alias and checked `DoomSlopeDivChecked` with unsigned shift-before-division
  semantics.
- `src/Renderer/Geometry.pbi`: checked equivalent primitives for
  `R_PointToAngle`/`R_PointToAngle2`, `R_PointToDist`, `R_PointOnSide` and
  `R_PointOnSegSide`; explicit origins, unsigned BAM branches, original fixed
  products/sign shortcut/tie rules and documented overflow/coincident policies.
- Developer-only generators `scripts/gen_trig_tables.py` and
  `scripts/gen_geometry_golden.py`; tracked numeric table data and generated
  golden fixture, buildable without the local C tree at build/runtime.
- `tests/unit/angle_geometry_tests.pb`: AG01-AG48 (48 cases, 277 assertions)
  covering BAM constants/wrap/indexing, whole-table shape/samples/full hashes,
  cosine alias, SlopeDiv edge/oracle cases, all eight angle octants, distances,
  node/seg sides, synthetic map bridge and error/repeat stability.
- `tests/integration/m3_geometry_tests.pb`: I01-I03 (3 cases, 40 assertions)
  covering dependency-free composition, stable immutable tables, synthetic map
  conversions and a 15-operation deterministic snapshot.
- `tests/integration/m3_geometry_iwad_tests.pb`: optional read-only I04 for
  E1M1/E1M2/E4M1 sample counts and non-reconstructable canonical geometry
  checksums.
- `-GeometryTest`, `-GeometryIntegrationTest`, `-GeometryIwadTest` PowerShell
  targets and `--geometry-test`, `--geometry-integration-test`,
  `--geometry-iwad-test` Bash targets; both test runners execute the new suites.

- `src/Renderer/Camera.pbi`: caller-owned fixed `BspCamera` with signed 16.16 X/Y,
  raw unsigned BAM heading in `.q`, checked map-unit/fixed creation, transactional
  setters, idempotent empty reset and read-only accessors. No simulation/renderer
  globals are mutated.
- `src/Renderer/BSP.pbi`: deterministic, iterative `R_RenderBSPNode`-equivalent
  traversal from a ready validated `MapLevel`; original near-before-far order via
  the existing exact point-on-node geometry; owned chronological
  `SUBSECTOR`/`SEG` trace with stable leaf/seg/sector/linedef/side links; explicit
  bounded LIFO stack, 1,000,000-event and 4,000,000-work caps, checked growing
  storage, transactional reset and deterministic shared-DAG repetition.
- Deliberately deferred `R_CheckBBox`/viewangletox/clipangle/solidsegs occlusion:
  the far child is always traversed, occlusion-skip counter stays zero, and the
  trace is documented as a chronological BSP walk rather than a visible-surface
  list. No wall projection, drawsegs, textured columns, planes or sprites.
- `tests/unit/bsp_traversal_tests.pb`: B01-B48 (48 cases, 669 assertions) covering
  null/unready/corrupt roots, zero-node root, side ties/signed/diagonal partitions,
  nested order, last-node roots, child encoding, absolute seg ranges/interleaving,
  links/sentinels, rejected invalid ranges/cycles, a 300-node deep iterative chain,
  an independent recursive LIFO oracle, heading neutrality, camera exactness/raw
  BAM/overflow, geometry failure cleanup, repeatability/lifetime/reset/accessors,
  deterministic DAG repetition and controlled exponential-DAG budget exhaustion.
- `tests/integration/m3_bsp_tests.pb`: I01-I03 (3 cases, 87 assertions) through the
  real synthetic WAD/MapLevel APIs: full nested trace/order/links; WADClose,
  level-reset, distinct map load/reload, reopen, repeat reset, failed-build
  cleanup; malformed node rejection, late geometry and DAG budget failures with
  unchanged camera/level and valid recovery.
- `tests/integration/m3_bsp_iwad_tests.pb`: optional read-only I04 for a legal
  owner IWAD; player-one THING fixed camera, complete E1M1/E1M2/E4M1 cull-free
  traces, duplicate/missing checks, repeat hashes and before/after size+MD5
  unchanged verification.
- `-BspTest`, `-BspIntegrationTest`, `-BspIwadTest` PowerShell targets;
  `--bsp-test`, `--bsp-integration-test`, `--bsp-iwad-test` Bash targets.
  `scripts/test.ps1` gains optional `-IwadPath`; `scripts/test.sh` gains optional
  `IWAD_PATH`. With a path they run read-only M3-03 I04 and `--map-info`
  E1M1/E1M2/E4M1 CLI checks; without one I04 reports NOT RUN.
- `src/DoomPB.pb` includes Camera/BSP for compile coverage only; CLI, version and
  ordinary startup remain unchanged.
- README/PORTING_NOTES/DEVELOPMENT_PLAN/CHANGELOG document the M3-03 trace as a
  non-rendering capability, its deferred occlusion boundary, ownership/budget/DAG
  policy and observed results.

- `src/Renderer/Projection.pbi`: immutable owned equivalent of
  `R_InitTextureMapping` for the canonical 320-column logical view; normalized
  4096 `viewangletox`, retained 4096 pre-fencepost entries for diagnostics, 321
  `xtoviewangle`, original focal `10477766`/constants and raw unsigned
  `clipangle` `0x20080000`; explicit checked table indexes and idempotent reset.
- `src/Renderer/ClipSegs.pbi`: owned equivalent of `R_ClearClipSegs`,
  `R_ClipSolidWallSegment`, `R_ClipPassWallSegment`; inclusive column posts,
  original left-to-right emission order, fixed two sentinels, checked real-post
  insertion/consolidation, pre-reserved transactional growth and caps; supports
  independently tested widths 1..320.
- `src/Renderer/WallVisibility.pbi`: source-faithful `R_AddLine` with exact raw
  unsigned angle wrap, strict backface/FOV/zero-pixel reject order, catalog-aware
  or canonical-raw SOLID/PASS/empty-trigger classification, and owned ordered
  `WallSpan` records; full `R_CheckBBox`/`WallBoxPosition`; online near-first
  iterative BSP walk where far boxes run only after real occlusion exists, with
  distinct bbox/occlusion counters and transactional result reset/failure.
- Deterministic fixture generators `scripts/gen_projection_golden.py` and
  tracked `tests/fixtures/m3_projection_golden.pbi`; an independent Python oracle
  for all 4096 normalized/4096 pre/inverse 321 entries and canonical FNV hashes.
- `tests/unit/wall_clipping_tests.pb`: WC01-WC52 covering projection constants/
  whole tables/pre/inverse/manual tangent fenceposts, sentinel clipping in tiny
  frames, solid/pass emission, adjacent/overlap/repeat growth, independent
  reference `R_AddLine`, stricter left/right tie helpers, classification/identity
  fallback/catalog routes, all 48 checkcoord bytes plus reachable boxpos,
  occluded/visible/behind/vs-cardinal bboxes, online walk order/pruning/zero-leaf/
  failure/recovery and deterministic lifetime counters.
- `tests/integration/m3_wall_clip_tests.pb`: I01-I03 fresh synthetic ten-lump
  PWADs through real WAD/MapLevel APIs; near SOLID occludes far leaf; unchanged
  M3-03 cull-free chronologies/hashes versus M3-04 SOLID occlusion and PASS
  control; A->B->A reload/direction-change/Reset/repeat and corrupt-edge
  transactional failure/recovery with identical restored fingerprint.
- `tests/integration/m3_wall_clip_iwad_tests.pb`: optional read-only I04 builds
  decoded PNAMES/TEXTURE1/TEXTURE2 and F_START/F_END catalogs, reuses one classic
  projection, loads E1M1/E1M2/E4M1 with player-one THING cameras, cross-checks
  cull-free reachable totals, audits every span against decoded seg/line/side/
  sector identity and recomputes catalog-aware SOLID/PASS kind, then verifies
  counters/bbox breakdown/live occlusion/repeat+Reset fingerprints and
  unchanged size/MD5.
- `-WallClippingTest`, `-WallClippingIntegrationTest`, `-WallClippingIwadTest`
  PowerShell targets and `--wall-clipping-test`,
  `--wall-clipping-integration-test`, `--wall-clipping-iwad-test` Bash targets;
  `scripts/test.ps1` and `scripts/test.sh` run WC01-WC52, synthetic I01-I03 and
  optional real-IWAD I04, with `-IwadPath`/`IWAD_PATH` adding the read-only pass.
- `src/DoomPB.pb` compile-only includes Projection/ClipSegs/WallVisibility; CLI,
  version `0.2.0` and ordinary startup remain unchanged.
- README/PORTING_NOTES/DEVELOPMENT_PLAN/CHANGELOG document M3-04 as headless
  screen-column visibility, source/safety deviations, deferred drawseg/pixel/
  vertical/textured work and observed results.

- `src/Renderer/WallView.pbi`: caller-owned M3-03 `BspCamera` plus checked signed
  16.16 static `ViewZ`; floor map units are converted to fixed and
  `VIEWHEIGHT=41*FRACUNIT` added with signed64 bounds before any publish;
  transactional fixed/map-unit setters, idempotent reset, read-only accessors.
- `src/Renderer/WallProject.pbi`: dependency-checked equivalent of `r_segs.c`
  `R_StoreWallRange`/`r_main.c` `R_ScaleFromGlobalAngle`: seg raw `SHORT<<16`
  BAM conversion, normal/offset/dist angles, `R_PointToDist`/finesine distance,
  scale1/scale2/step clamp, front/back heights, closed-door/SKY1/wrong-side
  overrides, catalog-aware flat/middle tier presence, original 12-bit
  `topfrac`/`bottomfrac`/pix edges and numeric per-span `WallSpanPlan`. Ordinary
  signed 16.16 arithmetic stays source-exact; C signed-overflow sites use
  documented low32 helpers; `abs(INT32_MIN)`, negative scale indexes, endpoint
  scale-step overflow and coincident seg-v1/camera are diagnosed; single-column
  scale2=scale1/step=0 policy preserved. No texture/flat/sky/light/sprite pixels.
- `src/Renderer/WallDraw.pbi`: M3-05 bounded rasterizer of `R_RenderSegLoop` into
  the existing 320x200 indexed `FrameBuffer`: 320 ceilingclip/floorclip arrays
  initialized -1/200, exact `(topfrac+HEIGHTUNIT-1)>>12` / `bottomfrac>>12`
  inclusive contracts, source tier clip/mark branches, pixhigh/pixlow increments
  only in active two-sided tiers; one-sided middle closes column to 200/-1.
  Solid debug palette indices background `0`/middle `176`/upper `252`/lower `96`;
  one contiguous clip allocation, no allocation in the column loop; canonical
  FNV-1a64 over exact 64,000 row-major bytes with fixed 16 uppercase hex text.
- `src/Renderer/RenderMain.pbi`: `WallPlayerSubsectorChecked` bounded original
  `R_PointInSubsector` equivalent incl zero-node root; `WallRenderPlayerStartView`
  exact-one player `type=1`, signed16 x/y checked fixed, original
  `ANG45*(angle/45)` unsigned wrap, derived floor sector and static
  `floor+41` viewz; transactional `WallRenderFrame` reads M3-04 ordered spans as
  sole authority, builds one plan per span, draws into a private plane and only
  publishes/releases the caller target after whole-frame success; failure leaves
  target byte state unchanged and frees clip/plans/frame; one metadata + one
  clip + one frame allocation (Allocations=3 on owner maps), no target/map/
  catalog/view retention, idempotent result Reset and read-only stats/hash/plan
  accessors.
- `src/Graphics/Video.pbi`: `VideoShowFramebuffer` accepts an optional custom
  `Title.s` for the preview window; the existing default TITLEPIC window title,
  size, 3x nearest-neighbour client and close/release path remain unchanged.
- `src/DoomPB.pb`: opt-in `--iwad <path> --show-walls <ExMy>` static player-start
  wall-only preview at 3x with coarse counters and canonical hash; existing
  `--show-title`/`--map-info`/`--lump-info`/`--dump-info`/`--version`/`--help`/
  no-argument paths and exit codes unchanged (conflict diagnostics name the new
  exclusive option); version `0.2.0`.
- Independent generator `scripts/gen_wall_projection_golden.py` and tracked
  synthetic-only numeric fixture `tests/fixtures/m3_wall_projection_golden.pbi`
  (A/B/E/T/C spans, plans, sample palette rows, frame hashes); generator consumes
  only pinned numeric tables and separate integer formulas, never production
  output. Deterministic double regeneration SHA256
  `CE4607EC1D93D734875EE48C5602AB75FD499FC80AA622607DB9E62093F53198`.
- `tests/unit/wall_projection_tests.pb`: WP01-WP56 **56 cases / 738 assertions**,
  unit fixture support with explicit SEGS raw angle, exact projection/distance/
  scale/heights/tiers/sky/closed-door/wrong-side/flats/absent-middle, five
  scalar scene oracles, sample rows/hashes, headed/viewz alternations, all
  documented arithmetic edges, transactional budgets/reset/lifetime/canonical
  zero-padded text/repeat identity.
- `tests/integration/m3_wall_render_tests.pb`: WI01-WI03 **3 cases / 147
  assertions**, real synthetic ten-lump `MapLevel` path through M3-04 visibility,
  M3-05 plans and transactional frames; independent 64,000-byte FNV, palette
  audit, tier reconciliation, occlusion crossing, portal gaps, y=0/199 bounds,
  malformed seg/coincident divide/invalid viewz/budget/invalid pixels/recovery,
  A-B-A caller target lifetime, ANG45 noncommutative hash and canonical text.
- `tests/integration/m3_wall_render_iwad_tests.pb`: optional WI04 **1 case / 288
  assertions**, E1M1/E1M2/E4M1 catalogs/validation/player-start camera with
  independent equivalent THING/leaf/floor/viewz, unchanged M3-04 span/counter
  fingerprints, three repeated compiled frames, exact independent FNV and
  palette-indices audit, allocations/boundaries, before/after MD5/size unchanged.
- `-WallProjectionTest`, `-WallRenderIntegrationTest`, `-WallRenderIwadTest`
  PowerShell targets; `--wall-projection-test`, `--wall-render-integration-test`,
  `--wall-render-iwad-test` Bash targets. `scripts/test.ps1`/`test.sh` run
  WP01-WP56, WI01-WI03 and optional WI04 after all prior suites; `-IwadPath`/
  `IWAD_PATH` runs WI04 read-only and now wires the pre-existing M2 owner-I04
  mode once rather than both synthetic+owner modes.
- README/PORTING_NOTES/DEVELOPMENT_PLAN/CHANGELOG document M3-05 module/C
  correspondence, fixed/edge derivation, sky/missing-texture policy, ownership/
  lifetime, actual frame hashes/counters, GUI visual status, cumulative totals
  and remaining textured/plane/sprite/gameplay gaps.

M3-06 textured wall columns and vanilla lighting:

- `src/Renderer/WallTextureMapping.pbi`: checked source helpers for exact
  `rw_offset` (`offsetangle` unsigned comparisons/clamp/sign, `finesine` lookup,
  signed fixed product and separate `SIDEDEFS.textureoffset`/`SEGS.offset`
  additions), `rw_centerangle`, per-X `finetangent` texturecolumn, vanilla width
  mask (highest power of two ≤ width − 1), unsigned `&` wrap, `dc_iscale =
  0xFFFFFFFF / unsigned(scale)`, 16.16 `frac` start/advance, exact `&127` rows for
  ≥128 heights and bounded modulo-height source rows for <128 heights, one-sided/
  upper/lower pegged `dc_texturemid` helpers and uncovered-mask reporting.
- `src/Renderer/WallTextureCache.pbi`: one entry per distinct visible painted-tier
  TextureCatalog index, each owning an embedded M2-composed `TextureImage`
  pixel+mask plane through existing `TextureCompose`; first/duplicate-name
  catalog resolution, side 0/1 top/bottom-then-middle field selection, canonical
  absent `-`/all-NUL and original index-0 NoTexture handling, tier-flag gating,
  masked two-sided middles detected/counted but not composed/painted, checked
  width-mask/height metadata, exact unique-count entries and budgeted allocation,
  transactional reset/failure cleanup, no borrowed WAD/map/catalog pointer after
  build, explicit reopen invalidation contract (no stale lump index reuse).
- `src/Renderer/WallLighting.pbi`: pinned `LIGHTLEVELS=16`, `LIGHTSEGSHIFT=4`,
  `MAXLIGHTSCALE=48`, `LIGHTSCALESHIFT=12`, `NUMCOLORMAPS=32`, `DISTMAP=2`;
  classic full-detail 320-column `startmap=(15-i)*4` / `level=startmap-j/2`
  truncation/clamp table, front-sector light row with source horizontal (`--`)/
  vertical (`++`) corrections and 0..15 clamp, `scale>>12` 0..47 column index,
  `colormap[map][texel]` mapping; ≥32-table `COLORMAP` gate; numeric map indexes
  not borrowed table pointers; `extralight=0`; dynamic/fixedcolormap deferred.
- `src/Renderer/TexturedWallDraw.pbi`: M3-05 tier/clip ordering byte-for-byte,
  replacing solid palette indices with composed texels mapped through
  `scalelight`; inclusive `dc_yl..dc_yh`, shared ceiling/floor clip, per-X scale/
  topfrac/bottomfrac steps, one-sided middle closes 200/-1, upper pixhigh / lower
  pixlow steps, only clip side effects for deferred planes/markfloor/sky/sprites;
  bounded source column/row/palette/screen checks; mask=0 uncovered texels use the
  M2 composed index-0/mask-0 policy routed through COLORMAP and counted; 255 stays
  opaque; no per-column/per-pixel allocation; atomic tally publication per span.
- `src/Renderer/TexturedRenderMain.pbi`: transactional textured frame orchestration
  using M3-04 spans as sole authority and one M3-05 `WallSpanPlan` per span; builds
  used-texture cache and 16×48 light table, creates one `WallTextureSpanPlan`
  per span carrying numeric texture slots/heights/masks/pegging mids/raw offset/
  center/light row, one 2,560-byte clip and one private 64,000-byte background frame;
  target publication only on whole-frame success, failure frees every private/cache/
  metadata resource and leaves caller target bytes unchanged; result owns numeric
  copied plans/counters/hash only; no MapLevel/WAD/catalog/cache/frame/table/texture
  pointer retained; canonical FNV-1a64/16 uppercase hex over exact palette bytes.
- `src/DoomPB.pb`: opt-in `--iwad <path> --show-textured-walls <ExMy>` loads the
  existing WAD→PLAYPAL/PNAMES/TEXTURE1/2/flat catalog→validated map→projection→
  player-one view→M3-04 visibility→M3-05 plans pipeline plus `COLORMAP` and cache,
  renders one textured 320x200 frame at 3x, prints detailed counters/hash; old
  `--show-walls` debug mode remains pixel/hash identical; conflicts, help, usage and
  exit codes extended while old behavior/version `0.2.0` stay unchanged.
- Independent generator `scripts/gen_wall_texture_golden.py` and tracked
  synthetic-only `tests/fixtures/m3_wall_texture_golden.pbi`: published geometry
  oracle plus separate integer/material/scalelight/COLORMAP formulas compute
  TI01/TI02 full 64,000-byte frames, hashes, independent M3-04 span fingerprints,
  samples, span/62-field plan vectors, cache/types/counters; no commercial bytes or
  production renderer output.
- `tests/unit/wall_texture_tests.pb`: WT01-WT60 **60 cases / 545 assertions**, all
  required catalog/side selection/null/malformed/duplicate/reopen/cache ownership/
  mask/offset/column/iscale/frac/row/peg/tier/portal/closed-door/clip/COLORMAP/
  scalelight/lights/scale-index/mapping/masked-ordering/frame-rollback/FNV/legacy
  and nearest-neighbour categories with synthetic oracles.
- `tests/integration/m3_wall_texture_tests.pb`: TI01-TI03 **3 cases / 116
  assertions** through real self-authored WAD/texture/COLORMAP/map APIs; full
  synthetic frames/hashes/samples/plans/counters equal independent fixtures, A-B-A
  reopened cache invalidation, stale-patch rejection, repeats/reset, late failure
  rollback, missing TEXTURE1/PNAMES/COLORMAP recovery.
- `tests/integration/m3_wall_texture_iwad_tests.pb`: optional TI04 **1 case / 128
  assertions** E1M1/E1M2/E4M1 read-only, real texture pixels/counters, repeat full
  plane byte equality, M3-04/M3-05 fingerprints preserved; stable new hashes are
  printed `NOT LOCKED` pending independent C-equivalent sampling (visual/repeat
  evidence only).
- `tests/integration/wall_texture_support.pbi`: synthetic PWAD/texture/patch/
  COLORMAP/map builders with optional `IncludeTextures`/`IncludeColormap` flags for
  malformed tests; existing callers default unchanged.
- `-WallTextureTest`, `-WallTextureIntegrationTest`, `-WallTextureIwadTest`
  PowerShell targets; `--wall-texture-test`, `--wall-texture-integration-test`,
  `--wall-texture-iwad-test` Bash targets appended after all existing M3-05 suites,
  preserving prior selectors. `-IwadPath`/`IWAD_PATH` adds TI04 read-only.
- README/PORTING_NOTES/DEVELOPMENT_PLAN/CHANGELOG document M3-06 C correspondence,
  mapping/mask/short-height/masked-deferral/lighting limits, cache lifetime/reopen,
  actual tests/hashes/counters and Windows PASS/Linux NOT RUN.

### Verified

- Windows x64, PureBasic 6.41: fixed math suite 43 cases / 318 assertions / 0
  failures; optional FI04 with the owner's local IWAD 1 case / 32 assertions / 0
  failures.
- M3-02 angle/geometry suite 48 cases / 277 assertions / 0 failures; synthetic
  integration I01-I03 3 cases / 40 assertions / 0 failures; optional owner-IWAD
  I04 1 case / 29 assertions / 0 failures for E1M1/E1M2/E4M1.
- Pinned table verification: `finetangent` 4096 / `6E300CFD277525E1`,
  `finesine` 10240 / `ADD266F0CB7B06B6`, `tantoangle` 2049 /
  `56213612F87A0F4A`; runtime DataSection whole-array hashes match, and a separate
  Python oracle over the pinned source confirms table samples and algorithm
  vectors.
- Owner IWAD canonical geometry checksums: E1M1 `0DCDBF94926A3A32`, E1M2
  `A0CE3E0A0142A80E`, E4M1 `B7D9E25BCA4CF7B5`; repeated loads identical.
- `scripts/test.ps1`: observed 86/86 checks at the M3-02 increment; all prior
  M0/M1/M2/M3-01 suites rerun green (464 synthetic cases / 2,704 assertions);
  owner-IWAD runs M2 integration 36/240, M3-01 FI04 1/32 and M3-02 I04 1/29.
  `--version` prints `DoomPB 0.2.0`, `--help`, `--dump-info`, `--lump-info`,
  `--map-info` and `--show-title` remain available. Linux x64 NOT RUN.

- M3-03, Windows x64 PureBasic 6.41: B01-B48 **48 cases / 669 assertions / 0
  failures**; synthetic I01-I03 **3 cases / 87 assertions / 0 failures**; optional
  owner-IWAD I04 **1 case / 45 assertions / 0 failures**. The owner Ultimate Doom
  1.9ud `DOOM.WAD` (12,408,292 bytes, MD5 `c4fe9fd920207691a9f493668e0a2083`)
  stayed unchanged before/after read-only runs.
- M3-03 real cull-free traces (player-start camera): E1M1 239 subsectors / 747
  segs / 986 events / 238 nodes / FNV-1a64 `E45EF6B5D6BF7660`; E1M2 448 / 1,463 /
  1,911 / 447 / `33F4DA57BA294E8A`; E4M1 196 / 695 / 891 / 195 /
  `251409E7266F6A9`. Duplicate/missing subsector and seg occurrences are 0/0 in
  every map; occlusion skips 0; repeated traces identical.
- Full regression rerun: prior synthetic totals remain green at 464/2,704; new
  BSP unit/integration totals make the synthetic/non-IWAD observed total **515
  cases / 3,460 assertions / 0 failures**. Optional owner-IWAD runs add M2
  integration 36/240, M3-01 FI04 1/32, M3-02 I04 1/29 and M3-03 I04 1/45: combined
  observed **519 cases / 3,585 assertions / 0 failures**.
- `scripts/test.ps1`: without an IWAD path **101/101 checks pass**; with
  `-IwadPath` for the legal local IWAD **117/117 checks pass**, including read-only
  I04 and `--map-info E1M1/E1M2/E4M1`. `build.sh`/`test.sh` mirror the flags and
  Git Bash `bash -n` passes; Linux x64 runtime remains NOT RUN.
- CLI regression: `--version` = `DoomPB 0.2.0` exit 0; `--dump-info` prints a
  12,408,292-byte IWAD with 2,306 lumps; `--lump-info PLAYPAL` index 0/offset 12/
  size 10,752;
  `--map-info` E1M1/E1M2/E4M1 exit 0; `--show-title` opened
  `DoomPB - TITLEPIC (M1-04)` at 960x600, accepted WM_CLOSE and exited 0.

- M3-04, Windows x64 PureBasic 6.41: WC01-WC52 **52 cases / 474 assertions / 0
  failures**; synthetic WAD/level/camera/visibility I01-I03 **3 cases / 115
  assertions / 0 failures**; optional owner-IWAD catalog-aware I04 **1 case / 117
  assertions / 0 failures**. The owner Ultimate Doom 1.9ud `DOOM.WAD`
  (12,408,292 bytes, MD5 `c4fe9fd920207691a9f493668e0a2083`) stayed unchanged
  before/after read-only runs; PNAMES 351, textures 287, flats 111 decoded and
  resolved.
- Projection oracle verified all 4096 normalized `viewangletox`, 4096 retained
  pre-fencepost and 321 `xtoviewangle` entries; focal length `10477766`
  (`0x9FE0C6`), clipangle `0x20080000`; canonical FNV-1a64 hashes normalized
  `F45B52285F25D5DF`, pre `EAE596370F96286A`, inverse `4EC83D702DA4CD32`.
- Synthetic integration fingerprints (measured equality with explicit expected
  tuples): I01 two-leaf SOLID `60A24EC7D48916B4`; I02 quad SOLID
  `5EEDC66C4BB96932`, PASS control `6CD6B90817A62A89`; I03 ANG180 visible
  `874812E8D8EFE267`. The unchanged M3-03 cull-free quad traces remain distinct
  from the M3-04 visibility fingerprints.
- M3-04 real online visibility (player-start camera, catalog-aware):
  - E1M1: 35 spans / 49 online nodes / 32 leaves / 103 segs; solid/pass
    candidates 23/15; backface 41, FOV left/right 24/0, zero-width 0, empty 0;
    bboxes 49 = visible/occluded/unknown 31/18/0; clip growth ranges/spans 1/0,
    allocations 5, work items 260; span FNV `74B485154CE29B0B`; counters FNV
    `7ADB45DBF2611B77`.
  - E1M2: 54 spans / 69 nodes / 42 leaves / 151 segs; candidates 42/33;
    backface 62, FOV 9/0, zero-width 5; bboxes 41/28/0; growth 1/0, allocations
    5, work 360; span FNV `8AC0627513C4B619`; counters FNV `83CAB0E1049B850A`.
  - E4M1: 69 spans / 49 nodes / 40 leaves / 159 segs; candidates 26/55;
    backface 65, FOV 2/0, zero-width 10, empty 1; bboxes 39/10/0; growth 1/1,
    allocations 6, work 276; span FNV `9FD0B15A0F33197E`; counters FNV
    `CCAA2442EB270717`.
  All three cull-free cross-checks retain E1M1 238/239/747, E1M2 447/448/1,463,
  E4M1 195/196/695 node/leaf/seg totals with zero trace occlusion; each online
  pass reports positive live occlusion and fewer leaf visits, every span passes
  decoded source-identity/kind audit, and repeat/explicit-Reset Builds reproduce
  identical span+counter fingerprints.
- Full regression rerun after M3-04 (observed): the ten individual M1/M2 WAD
  executables re-measured 17/146, 21/152, 34/197, 24/199, 31/191, 33/165, 30/141,
  39/300, 51/190 and 55/167; their sum is **335 cases / 1,848 assertions**. The
  earlier report's 375/1,668 aggregate was a manual report arithmetic error only;
  no suite expectation/production code changed. Before adding the new suites the
  rerun reproduced the M3-03 baseline exactly: prior synthetic/non-IWAD suites
  **515 cases / 3,460 assertions / 0 failures** and prior suites including
  optional owner-IWAD runs **519 cases / 3,585 assertions**. Adding M3-04
  WC01-WC52 (52/474) and synthetic I01-I03 (3/115) gives the synthetic observed
  total **570 cases / 4,049 assertions / 0 failures**. Optional owner-IWAD runs
  add M2 I04 1/19, M3-01 FI04 1/32, M3-02 I04 1/29, M3-03 I04 1/45 and M3-04 I04
  1/117: combined observed all suites **575 cases / 4,291 assertions / 0
  failures**. No old suite count/assertion expectation or M3-03 hash was changed.
- `scripts/test.ps1`: without an IWAD path **116/116 checks pass**; with
  `-IwadPath` for the legal local IWAD **138/138 checks pass**, including read-only
  M3-03/M3-04 I04 and `--map-info E1M1/E1M2/E4M1`. `build.sh`/`test.sh` mirror
  the new flags and Git Bash `bash -n` passes; Linux x64 compilation/runtime
  remains NOT RUN.
- Main `src/DoomPB.pb --check` and build exit 0; CLI `--version` still
  `DoomPB 0.2.0`; unknown option exit 2, missing WAD exit 1 and
  `--show-title`/`--dump-info` conflict exit 2 behaved unchanged in smoke tests.

- M3-05, Windows x64 PureBasic 6.41: WP01-WP56 **56 cases / 738 assertions / 0
  failures**; synthetic WI01-WI03 **3 cases / 147 assertions / 0 failures**;
  optional owner-IWAD WI04 **1 case / 288 assertions / 0 failures**. The owner
  Ultimate Doom 1.9ud `DOOM.WAD` (12,408,292 bytes, MD5
  `c4fe9fd920207691a9f493668e0a2083`) remained unchanged before/after read-only
  runs; PNAMES 351, textures 287, flats 111.
- Independent fixture generator double run byte-identical SHA256
  `CE4607EC1D93D734875EE48C5602AB75FD499FC80AA622607DB9E62093F53198`;
  synthetic frame goldens A `2090BE09430C7B25`, B `72685823901A3A25`, E
  `B226A1443E08AB25`, T `D758954693568DA5`, C `4D32B97402CD3925`; sample
  columns/rows/plans all independently generated. A production subsector
  output-order bug was root-caused/fixed without changing fixture expectations.
- Locked WI04 owner frame hashes: E1M1 `4A923E4D357C7BD1`, E1M2
  `0C9627E5C2FD8D35`, E4M1 `9AEB8BDD16834359`; each independently full-plane
  re-hashed, reproduced by three in-harness frames and two separate executable
  invocations, and source/M3-04 preconditioned. Preserved M3-04 owner
  fingerprints: E1M1 span/counters `74B485154CE29B0B`/`7ADB45DBF2611B77`; E1M2
  `8AC0627513C4B619`/`83CAB0E1049B850A`; E4M1
  `9FD0B15A0F33197E`/`CCAA2442EB270717`. Camera/view equivalence was asserted.
- M3-05 owner map frame counters: E1M1 35 spans/1,080 processed/748 draw ranges,
  12,368 painted = middle 9,234 + upper 2,071 + lower 1,063, background 51,632,
  clipped/empty 625/481; E1M2 54/1,422/883, 14,358 = 12,311+400+1,647,
  background 49,642, clipped/empty 916/539; E4M1 69/836/584, 28,649 =
  26,349+2,047+253, background 35,351, clipped/empty 198/291; every frame
  Allocations=3, OutOfFrameColumns=0, all four palette kinds nonzero, tier and
  background bytes reconcile to 64,000.
- Full regression rerun (actual executable outputs): no owner IWAD **629 cases /
  4,934 assertions / 0 failures**, `scripts/test.ps1` **131/131 checks exit 0**.
  With owner IWAD, replacing the M2 synthetic run by its one owner-I04 mode
  36/240 and adding actual M3-01/M3-02/M3-03/M3-04/M3-05 I04 counts
  1/32, 1/29, 1/45, 1/117, 1/288 gives **635 cases / 5,464 assertions / 0
  failures**, `scripts/test.ps1 -IwadPath data/DOOM.WAD` **165/165 checks exit
  0**. Existing M1/M2/M3-01..04 expectations/hashes were not weakened.
- GUI visual inspection (Windows, owner IWAD): rebuilt `--show-walls
  E1M1/E1M2/E4M1`, 960x600 3x client captured via occlusion-safe PrintWindow,
  inspected, `WM_CLOSE` accepted, each exit 0. Observed coherent debug-color
  wall fields: black background (index 0) above/below/portal gaps, red middle
  faces (176), magenta upper strips (252), grey lower bands/wedges (96) in
  correct tier order/perspective, crisp nearest-neighbour columns, no texturing/
  lighting/sky/flats/sprites, no unexpected inverted/wrong-side artifacts. Captures
  stayed ignored in `build/` and no commercial pixels were committed/published.
- `scripts/test.sh` mirrors new targets/optional WI04 and M2 owner-I04 single-run
  mode; Git Bash 5.2.37 `bash -n` returned **0/0** (syntax only). Linux x64
  compilation/runtime remains **NOT RUN**; Windows-only evidence reported.
- No per-column heap growth or crash was observed; per-frame allocation count
  stayed 3; explicit failure paths preserved target bytes in unit/integration
  probes; no temporary DBG instrumentation remained in production/test sources.

- M3-06, Windows x64 PureBasic 6.41: WT01-WT60 **60 cases / 545 assertions / 0
  failures**; synthetic TI01-TI03 **3 cases / 116 assertions / 0 failures**;
  optional owner-IWAD TI04 **1 case / 128 assertions / 0 failures**. Owner Ultimate
  Doom 1.9ud `DOOM.WAD` (12,408,292 bytes, MD5
  `c4fe9fd920207691a9f493668e0a2083`) stayed unchanged before/after read-only runs.
- Independent generator `gen_wall_texture_golden.py` double run produced identical
  SHA256 `5A8B9E76622BB828DD42EF1E789FB315E6AF1D4D1560FE9877C85D3137445CE3`
  and matched the tracked fixture byte-for-byte. Synthetic full-pipeline frames
  match the fixture: TI01 hash `119A71B79384D465`, TI02 `F05D55B8FE8C07EB`;
  independent M3-04 span fingerprints TI01 `3EE9969A4FF10052`, TI02
  `2FAA660491199243` are asserted unchanged by the integration harness.
- Owner stable textured full-plane hashes (repeated byte-identical, independent
  full-plane re-FNV, frozen M3-04/M3-05 preconditions preserved): E1M1
  `183BA53FCECECBC8`, E1M2 `835A0339A38B190E`, E4M1 `03B5C8CFA517FC7E`. These
  remain printed **NOT LOCKED** pending independent C-equivalent sampling; GUI
  visual and repeat evidence are not sufficient for locking by themselves.
- M3-06 owner counters: E1M1 spans 35 / columns 1,080 / middle/upper/lower
  9,234/2,071/1,063 / masked middles 0 / short textures 2 / bounded short-row
  fallbacks 1,932 / uncovered 0 / allocations 21 / nonzero bytes 12,275; E1M2
  54/1,422, 12,311/400/1,647, masked 0, short 1, fallbacks 218, uncovered 0,
  allocations 29, nonzero 14,305; E4M1 69/836, 26,349/2,047/253, masked 0, short 0,
  fallbacks 0, uncovered 0, allocations 15, nonzero 27,987. All three report
  OutOfFrameColumns=0.
- Legacy preservation on the rebuilt main executable: `--show-walls` E1M1
  `4A923E4D357C7BD1`, E1M2 `0C9627E5C2FD8D35`, E4M1 `9AEB8BDD16834359` (each
  independently re-hashed by the 64,000-byte frame audit); frozen M3-04 pairs
  E1M1 `74B485154CE29B0B`/`7ADB45DBF2611B77`, E1M2
  `8AC0627513C4B619`/`83CAB0E1049B850A`, E4M1
  `9FD0B15A0F33197E`/`CCAA2442EB270717` all preserved.
- Full regression rerun actual executable/script outputs: without owner IWAD
  **692 cases / 5,595 assertions / 0 failures**, `scripts/test.ps1` **148/148
  checks exit 0**; with owner IWAD (M2 synthetic replaced once by 36/240, plus
  existing I04 and TI04) **699 cases / 6,253 assertions / 0 failures**,
  `scripts/test.ps1 -IwadPath data/DOOM.WAD` **193/193 checks exit 0**. New totals
  were not hardcoded; old suite expectations/hashes were not weakened.
- Actual build/CLI evidence: `pbcompiler --check` and console build exit 0;
  each new harness syntax-check/build exit 0; `--version` `DoomPB 0.2.0` exit 0;
  `--help` exit 0; missing `--show-textured-walls` WAD exit 1; bare mode exit 2;
  mode conflicts exit 2 naming both wall options; legacy and textured preview
  windows opened 960x600 via 3x nearest-neighbour and accepted WM_CLOSE exit 0.
- GUI visual inspection (Windows, owner IWAD): textured captures for
  E1M1/E1M2/E4M1 were reviewed; coherent textured wall bands, perspective,
  seams/pegging and correct tier order observed, deferred black floors/sky/portal
  interiors remained, raw-text frame hash matched harness stability, stderr empty.
  Captures stayed ignored in `build/`; no commercial pixels were committed or
  printed. WT60 covers converter 320→960 equality; no pixel-level raw-vs-screen
  capture sampling was performed.
- `scripts/build.sh`/`test.sh` add the three new selectors and TI04 branch; Git
  Bash 5.2.37 `bash -n` actual **0/0** (syntax only). Linux x64 compiler/runtime
  remains **NOT RUN**; Windows-only evidence reported. CPU timing was not measured.
- No per-column/per-pixel allocation, WAD read or texture compose was observed in
  the textured path; total allocations reconcile to pre-loop frame/plan/table/
  clip/cache budgets. Explicit failure paths preserved target bytes. Temporary
  `DBG` instrumentation was replaced by failure-only `diagnostic:` messages.

- M3-07 synthetic release integration, Windows x64 PureBasic 6.41:
  MR01-MR36 + RI01-RI03 **39 cases / 444 assertions / 0 failures / exit 0**.
  Optional owner-IWAD RI04 **1 case / 149 assertions / 0 failures / exit 0**;
  no-argument mode reports **0 cases / 0 assertions / NOT RUN / exit 0**.
  BEN01 wall-only frame benchmark **1 case / 67 assertions / 0 failures /
  exit 0** under verified Windows QPC 10 MHz / 1 us resolution.
- Owner Ultimate Doom 1.9ud fixture (12,408,292 bytes, MD5
  `c4fe9fd920207691a9f493668e0a2083`) remained byte-for-byte unchanged across
  the M3-07 RI04 read-only run; only numerics/hashes/counters were printed.
- Frozen M3-04 span/counter fingerprints and M3-05 debug frame hashes remained
  reproduced for E1M1/E1M2/E4M1; synthetic TI01/TI02 fixture hashes remained
  `119A71B79384D465`/`F05D55B8FE8C07EB`.
- Owner textured FNV observations after full-plane independent recompute and
  byte-for-byte repeats stayed E1M1 `183BA53FCECECBC8`, E1M2
  `835A0339A38B190E`, E4M1 `03B5C8CFA517FC7E`; status remains **NOT LOCKED**.
  Independent raw-PATCH composition compared E1M1/E1M2 six and E4M1 four bounded
  textures with zero pixel/mask/opaque/width-mask mismatches; raw owner COLORMAP
  was exhaustively identical table-by-table for all three maps; E1M2/E4M1 bounded
  first-span column/row/lighting samples matched exactly, while E1M1 reports
  **NOT RUN** (reason 3: no safe one-sided first-span middle). A complete
  same-camera original-C wall-only image comparison remains **REFERENCE
  UNAVAILABLE**, so owner hashes are not claimed C-verified.
- Windows GUI smoke: TITLEPIC, M3-05 debug and M3-06 textured windows for
  E1M1/E1M2/E4M1 opened with exact **960x600 client area**, nonblank
  `PrintWindow`-captured content, normal `WM_CLOSE`, all exit 0. These are
  window/visual-presence checks; raw 320x200 indexed-byte identity is tested
  separately in synthetic conversion/frame checks. Captures stayed ignored.
- BEN01 separates cold end-to-end and warmed frame-only cost: cold 2 warmup +
  11 measured; warm textured 20 + 100 measured; warm debug 10 + 100 measured.
  Per-frame microseconds (min/median/p95/mean) vary per host/run; representative
  direct post-bump runs observed cold `7910/8136/8297/8126` and
  `8461/8528/8682/8547`, warm textured `5899/6103/6287/6168` and
  `6422/6628/6758/6634`, warm debug `369/390/399/389` and `370/389/405/390`. No
  FPS claim beyond a wall-only synthetic preview. Pre-column allocations observed 13 = cache 8 +
  five frame resources; composed unique textures 3, not per column/pixel.
- `scripts/build.ps1`/`build.sh` gain `-M3ReleaseTest` / `--m3-release-test`,
  `-M3ReleaseIwadTest` / `--m3-release-iwad-test` and `-M3ReleaseBenchmark` /
  `--m3-release-benchmark`; `scripts/test.ps1`/`test.sh` run those harnesses and
  owner RI04. Actual post-bump owner-path full script rerun: **239/239 checks
  pass, exit 0**; synthetic-only rerun **175/175 checks pass, exit 0** (with the
  new gates; historical 148/193 was not preserved artificially).
- Post-bump executable-level aggregate after the version/script/doc edits:
  synthetic **732 cases / 6,106 assertions / 0 failures**; owner mode
  **740 cases / 6,913 assertions / 0 failures** (M2 owner `36/240` replaces its
  synthetic `35/221`; optional harnesses counted only when actually executed;
  no double count). All per-executable exits were 0.
- Linux Bash syntax/runtime: the default Windows `bash.exe` is a WSL stub that
  failed launching `/bin/bash` (`execvpe /bin/bash failed`); Git Bash
  `5.2.37(1)-release (x86_64-pc-msys)` was then used and actual
  `bash -n scripts/build.sh`/`test.sh` both exited 0, which is a syntax-only
  check. No Linux PureBasic 6.41 build or Linux executable/test run occurred, so
  Linux x64 runtime remains **NOT RUN**, not a PASS.

## [0.2.0] - 2026-11-16

Milestone M2 is complete for the Windows x64 single-IWAD goal. The application
reports `0.2.0`; no Git tag exists until the owner creates it.

### Added

- `COLORMAP` decoder with raw 256-byte light/effect tables, indexed lookups,
  bounds checks and caller-owned storage (`src/Graphics/Colormap.pbi`).
- `PNAMES` decoder with signed count handling, raw eight-byte patch names,
  order/duplicate preservation and safe display helpers
  (`src/Graphics/PNames.pbi`).
- Synthetic C01-C13/N01-N15 test suite plus WAD integration I01-I03.
- `-ResourceTest` / `--resource-test` build target.
- `TEXTURE1`/`TEXTURE2` definition decoder preserving names, dimensions,
  flags and ordered patch placements (`src/Graphics/TextureDefs.pbi`).
- Explicit, atomic PNAMES-to-WAD resolution for referenced patches only, with
  first-match texture-name lookup and stale-index invalidation.
- Synthetic D01-D20/R01-R10 test suite plus integration I01-I03.
- `-TextureDefTest` / `--texture-def-test` build target.
- Composite wall-texture builder producing row-major palette indices plus a
  separate opacity mask, with signed clipping and ordered patch overwrites
  (`src/Graphics/Texture.pbi`).
- Synthetic X01-X30 test suite and `-CompositeTest` / `--composite-test`
  build target.
- Flat namespace catalog and exact 4096-byte 64x64 indexed decoder
  (`src/Graphics/Flat.pbi`).
- Sprite namespace catalog with raw names, absolute WAD indices, patch header
  metadata and strict frame/rotation/flip assembly (`src/Graphics/Sprite.pbi`).
- Synthetic F01-F16/S01-S20 test suite, I01-I03 integration and
  `-FlatSpriteTest` / `--flat-sprite-test` build target.
- Bounds-checked decoders for THINGS, LINEDEFS, SIDEDEFS, VERTEXES, SEGS,
  SSECTORS, NODES, SECTORS, REJECT and BLOCKMAP, with native record types
  (`src/Map/MapTypes.pbi`, `MapDecode.pbi`, `Blockmap.pbi`).
- Synthetic M01-M48 map tests plus I01-I03 and `-MapTypesTest` /
  `--map-types-test` build target.
- Transactional vanilla map loader that locates the zero-length `E#M#` marker,
  verifies the adjacent ten-lump order and assembles an owned, validated level
  (`src/Map/MapLoader.pbi`, `src/Map/MapLevel.pbi`).
- Cross-reference validation for vertices, lines, sides, sectors, segs and
  subsectors, derived front/back links, per-sector line membership, iterative
  BSP reachability/cycle detection, REJECT size and BLOCKMAP line checks
  (`src/Map/MapValidate.pbi`).
- Optional flat/texture catalog binding and `--map-info <ExMy>` diagnostics.
- Synthetic L01-L52 map loader tests plus I01-I03 and `-MapLoaderTest` /
  `--map-loader-test` build target.
- Map/field-aware diagnostics for missing or malformed flat and wall-texture
  names (`E1M1 sector N floor flat ...`, `sidedef N upper texture ...`).
- M2 end-to-end integration suite (`tests/integration/m2_release_tests.pb`)
  with 32 synthetic scenarios (E01-E32), three lifecycle integration cases
  (I01-I03), optional real-IWAD I04, explicit reopen/invalidation checks and
  canonical FNV-1a64 metadata checksums.
- `-IntegrationTest` / `--integration-test` build target.

### Verified

- Windows x64, PureBasic 6.41: complete suite passes with 64/64 script checks.
- New M2 integration tests: 32 synthetic scenarios plus 3 lifecycle cases
  (35 cases, 221 assertions); optional I04 adds 1 case and 19 assertions.
- Real Ultimate Doom 1.9ud read-only integration: 287/287 wall textures
  composed (3,595,870 opaque pixels), 111 flats, 764 sprite entries,
  `MapLevelValidateResources` passed for E1M1, E1M2 and E4M1.
- New map loader tests: 52 format/validation cases plus 3 integration cases
  (167 assertions).
- Local Ultimate Doom maps load and validate read-only: E1M1, E1M2 and E4M1
  pass cross-reference, BSP reachability, REJECT-size and BLOCKMAP-line checks.
- New resource tests: 28 synthetic cases plus 3 integration cases.
- New texture-definition tests: 20 binary cases, 10 resolution cases and
  3 integration cases (165 assertions).
- New composite tests: 30 cases, 141 assertions.
- New flat/sprite tests: 16 flat cases, 20 sprite cases and 3 integration
  cases (300 assertions).
- New map binary tests: 48 format cases plus 3 integration cases (190
  assertions).
- Local Ultimate Doom `COLORMAP`: 8,704 bytes, 34 maps.
- Local `PNAMES`: 2,812 bytes, 351 names, no trailing bytes.
- Local textures: `TEXTURE1` 9,234 bytes, `TEXTURE2` 8,036 bytes, 287
  definitions, 980 placements, all resolved.
- All 287 resolved textures compose successfully with 0 failures and
  3,595,870 opaque pixels in total.
- Local flats: 111 interior entries (107 valid 4096-byte flats).
- Local sprites: 764 interior entries; 40/40 sampled frame sets built and one
  sprite decoded through `PatchDecode`.
- Local maps E1M1/E1M2/E4M1: all ten lumps decode in order; strict BLOCKMAP
  validation passes; REJECT sizes match the sector-count minimum.
- M1 regressions and `--show-title` remain green.
- Linux x64 runtime: **NOT RUN**.

## [0.1.0] - 2026-11-15

Milestone M1: WAD loader and TITLEPIC. This is the first milestone build; it is
not yet a playable game.

### Added

- Little-endian decoding helpers for 16/32-bit binary fields.
- Memory-safe WAD header and lump-directory parsing with 64-bit bounds checks,
  short-read detection, duplicate-name preservation and zero-length markers.
- Case-insensitive lump lookup with exact eight-byte semantics and
  last-duplicate-wins precedence.
- Caller-owned lump payload reads with a reopened file, size/range
  revalidation, bounded chunked I/O and cleanup on every path.
- `PLAYPAL` decoder: up to 256 palettes of 256 raw RGB triples, with indexed
  access and explicit failure states.
- Classic Doom picture/patch decoder producing row-major palette indices and a
  separate opacity mask, with strict validation of headers, columns, posts,
  terminators and dimensions.
- Platform-independent indexed software framebuffer with masked patch
  compositing, clipped blits, canonical RGBA conversion and CPU nearest-neighbour
  scaling.
- PureBasic window presentation via `ImageGadget`, respecting drawing-buffer
  pitch, pixel format and reversed rows, with a normal close/repaint event loop.
- CLI diagnostics: `--dump-info`, `--lump-info` and the interactive
  `--show-title`.
- Synthetic regression suites for WAD parsing, lookup/reads, PLAYPAL/patch
  decoding and framebuffer/presentation.

### Verified

- Windows x64, PureBasic 6.41: complete syntax/build/test suite passes.
- Script checks: 36/36.
- M1-01: 17/17 cases, 146/146 assertions.
- M1-02: 21/21 cases, 152/152 assertions.
- M1-03: 34/34 cases (P01-P10, G01-G24), 197/197 assertions.
- M1-04: 24/24 cases (F01-F24), 199/199 assertions.
- Ultimate Doom 1.9ud `data/DOOM.WAD` (MD5
  `c4fe9fd920207691a9f493668e0a2083`, 12,408,292 bytes): 2,306 lumps;
  `PLAYPAL` decodes to 14 palettes; `TITLEPIC` is 320x200 and displays at
  960x600 with palette 0.
- TITLEPIC visible-window review: PASS (correct image, colors, 3x scaling and
  framing; window closes with exit code 0).
- Linux x64 runtime: **NOT RUN** (no Linux PureBasic/display verification).

### Known limitations

- One WAD open at a time; PWAD overlays and multi-WAD merging are not
  implemented.
- No MD5/size-based IWAD recognition; the parser never rejects a legal IWAD just
  because its hash differs.
- The 960x600 display is exact square-pixel 8:5, not the historical CRT 4:3
  stretch.
- Static one-frame presentation only; no world renderer, game loop, input,
  audio, maps or gameplay.
- Windows x64 is verified; Linux x64 remains unverified.

## [0.0.1] - M0 bootstrap

Initial repository and build skeleton:

- GPL-2.0-only license, README and development documentation.
- PureBasic 6.41 console entry point with `--version` and `--help`.
- Reproducible Windows PowerShell and Linux Bash build/test scripts.
- Repository hygiene for commercial WADs, generated binaries and local data.
