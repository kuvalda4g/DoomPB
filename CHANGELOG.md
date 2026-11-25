# Changelog

All notable changes to DoomPB are recorded here. The project is licensed under
GPL-2.0-only; commercial Doom game data is never included.

## [Unreleased] - M3 math, BAM angle, geometry, BSP traversal, screen projection/wall clipping

M3 is not complete; the application version remains `0.2.0`. No tag or release
is created for this increment. M3-01, M3-02, M3-03 and M3-04 modules/tests are
in the working tree; drawsegs/one-color column drawing, vertical wall projection,
textured rendering and planes remain later M3-05+ steps. M3-04 produces headless,
owned numeric screen-column visibility intervals and counters, not rendered
walls or a frame.

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
