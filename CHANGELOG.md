# Changelog

All notable changes to DoomPB are recorded here. The project is licensed under
GPL-2.0-only; commercial Doom game data is never included.

## [Unreleased] - M3-01 fixed-point math foundation

M3 is not complete; the application version remains `0.2.0`. No tag or release
is created for this increment.

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

### Verified

- Windows x64, PureBasic 6.41: fixed math suite 43 cases / 318 assertions / 0
  failures; optional FI04 with the owner's local IWAD 1 case / 32 assertions / 0
  failures. `scripts/test.ps1` passes 73/73 checks; all existing M0/M1/M2 suites
  remain green, and `--version` (`DoomPB 0.2.0`), `--show-title` and `--map-info`
  remain unaffected. Linux x64 NOT RUN.

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
