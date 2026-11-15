# Changelog

All notable changes to DoomPB are recorded here. The project is licensed under
GPL-2.0-only; commercial Doom game data is never included.

## [Unreleased]

Milestone M2 in progress. The application version remains `0.1.0`; this section
is not a `0.2.0` release note.

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

### Verified

- Windows x64, PureBasic 6.41: complete suite passes with 44/44 script checks.
- New resource tests: 28 synthetic cases plus 3 integration cases.
- New texture-definition tests: 20 binary cases, 10 resolution cases and
  3 integration cases (165 assertions).
- Local Ultimate Doom `COLORMAP`: 8,704 bytes, 34 maps.
- Local `PNAMES`: 2,812 bytes, 351 names, no trailing bytes.
- Local textures: `TEXTURE1` 9,234 bytes, `TEXTURE2` 8,036 bytes, 287
  definitions, 980 placements, all resolved.
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
