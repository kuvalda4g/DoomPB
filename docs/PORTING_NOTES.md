# Porting notes

This document records **verified facts** about the DoomPB port. It must not
contain guesses, invented upstream commit hashes or copied game data.

## Milestone status

| Milestone | State | Notes |
|---|---|---|
| M0 — repository and reproducible build | complete | first commit `9f84d5d5a3dcbf66be9596fe5299a1209715735b`; CLI, build/test scripts, license and documentation |
| M1 - WAD loader and `TITLEPIC` | complete in working tree | M1-01 committed as `1e5f7d5`, M1-02 as `e5aad2b`, M1-03 as `b7067f6`; M1-04 and version `0.1.0` are in the working tree pending owner commit/tag; TITLEPIC visually verified on Windows x64; Linux x64 NOT RUN |
| M2 - Resources and map loading | complete on Windows x64; `v0.2.0` prepared | M2-01 committed as `53ca2db`, M2-02 as `96c793a`, M2-03 as `117708d`, M2-04 as `4020984`, M2-05 as `2fb2481`, M2-06 as `2f170c1`; M2-07 integration/version changes are in the working tree pending owner commit/tag; renderer pending; Linux x64 NOT RUN |
| M3 - Geometry and first walls | in progress: M3-01, M3-02, M3-03 and M3-04 | signed 16.16 math (M3-01), BAM angles/tables/geometry primitives (M3-02), deterministic fixed-camera BSP traversal/trace (M3-03) and exact 320-column projection + headless solid/pass wall clipping + source-faithful `R_AddLine` visibility + full `R_CheckBBox` online occlusion (M3-04) implemented and tested in the working tree; `drawsegs`/vertical projection/textured walls/planes remain M3-05+; `v0.3.0` NOT prepared; Linux x64 NOT RUN |

Release status for `0.1.0`: Windows x64 build and runtime are verified. Linux
x64 compilation/runtime remains **NOT RUN**. The `v0.1.0` commit and annotated
tag are owner-controlled and have not been created.

`src/DoomPB.pb`, `src/Core/Endian.pbi` and `src/WAD/WAD.pbi` are original
PureBasic code written for DoomPB. The WAD container parsing reproduces the
fields and semantics of the original C structures/functions listed below; no C
source text was copied.

## Upstream reference

- Repository: <https://github.com/id-Software/DOOM>
- Reference tree: `linuxdoom-1.10/`
- Commit SHA: `a77dfb96cb91780ca334d0d4cfd86957558007e0` (branch `master`,
  commit date 2024-01-16, subject "Add GPL information").
- Local clone: `../doom-original/` (sibling of this repository, not part of it).
  Verified with `git -C ../doom-original rev-parse HEAD`; `linuxdoom-1.10/` is
  present in that checkout.

Secondary reference (behaviour/portability clarification only):
<https://github.com/chocolate-doom/chocolate-doom>

## Verified build environment (M0)

- Compiler: PureBasic 6.41 (Windows — x64), located through the standard
  `Program Files\PureBasic\Compilers\pbcompiler.exe` installation path.
- `pbcompiler --version` prints
  `PureBasic 6.41 (Windows - x64) - (c) 2026 Fantaisie Software`.
- Observed compiler behaviour: `pbcompiler --version` and `pbcompiler --help`
  exit with status `1` even though they succeed. The build scripts therefore
  treat the version banner as informational only, and use the exit status of
  `--check` (0 on success) and of a real build to decide success.
- Console output from a PureBasic program requires `OpenConsole()`; without it
  `PrintN()` produced no output in testing. Console executables are built with
  `--console`.

Linux compilation has **not** been executed in this cycle; the equivalent Bash
scripts exist but remain unverified until a host with a Linux PureBasic 6.41
installation is available.

## Intentional differences from original Doom (M0)

- **Command line interface.** DoomPB uses its own minimal CLI (`--version`,
  `--help`, `--iwad <path> --dump-info`). Original Doom used positional
  arguments (`-iwad`, `-file`, …) plus a response-file mechanism; those are
  planned for later milestones and are not implemented.
- **Console bootstrap.** The executable is a console program that prints status
  text. Original Doom is a fullscreen game application. This remains a scaffold
  until the renderer and game loop exist.
- No lump payload loading, `PLAYPAL`, `TITLEPIC`, renderer or game loop exist
  yet. Do not treat this build as a playable port.

## M1-01 — WAD header and directory parser

Original C symbols consulted (Linux Doom 1.10, commit
`a77dfb96cb91780ca334d0d4cfd86957558007e0`):

- `wadinfo_t` (`w_wad.h`): `identification[4]`, `numlumps`, `infotableofs`
  — 12-byte header.
- `filelump_t` (`w_wad.h`): `filepos`, `size`, `name[8]` — 16-byte directory
  entry.
- `lumpinfo_t` (`w_wad.h`): `name[8]`, `handle`, `position`, `size`.
- `W_AddFile` (`w_wad.c`): opens the file, reads the header, accepts `IWAD` or
  `PWAD`, applies `LONG()` byte-order conversion, reads the directory, copies
  names with `strncpy`.
- `W_InitMultipleFiles`, `numlumps`, `lumpinfo` (`w_wad.c`): global directory
  storage and lifetime.

Port mapping:

- `wadinfo_t` / `filelump_t` field decoding → `WADOpen()` in
  `src/WAD/WAD.pbi`, using explicit little-endian helpers from
  `src/Core/Endian.pbi`. No PureBasic structure is cast over file bytes.
- `lumpinfo_t` → `WADLump`: raw signed `Position`, raw signed `Size`, eight raw
  `NameBytes`, plus a sanitized `DisplayName` for diagnostics.
- Directory lifetime → indexed `gWAD_Lumps` array, released by `WADClose()` and
  by every failed `WADOpen()`.

Safety hardening — differences from the original C code (all stricter):

- Header and directory reads are checked for short reads; the original ignored
  `read()` return values.
- Header length, exact case-sensitive magic, nonnegative count/offset and
  directory bounds are validated **before** seeking or allocating. The original
  performed no validation at all.
- `directory_size = Int64(count) * 16` and `directory_end = Int64(offset) + size`
  are computed in 64-bit arithmetic before allocation.
- Nonempty entries must satisfy `position >= 0` and
  `Int64(position) + Int64(size) <= file_size`.
- Negative entry sizes or (for nonempty entries) negative positions are
  rejected instead of being trusted as `int`.
- A safety cap of 1,000,000 directory entries prevents enormous allocations; no
  known Doom WAD is anywhere near it.
- Zero-length markers (`F_START`, `F_END`, …) are accepted with any recorded
  position, including negative or past EOF. The raw position is preserved but
  never used to seek or read.
- The directory is read through a single reusable 16-byte buffer, so memory use
  is proportional to the directory, not to the WAD file.
- The WAD file handle is closed before `WADOpen()` returns; payload loading
  (M1-02) will reopen by path or keep a handle under a later ownership model.
- For `numlumps = 0`, any nonnegative `infotableofs` is accepted and ignored
  (the field is unused); negative values are still rejected.
- The container format is never validated by hashing the file.

Verified behaviour:

- Local Ultimate Doom 1.9ud (`data/DOOM.WAD`, MD5
  `c4fe9fd920207691a9f493668e0a2083`, 12,408,292 bytes) is accepted as `IWAD`
  with 2,306 lumps and directory offset 12,371,396.
- Synthetic tests `T01`–`T16` plus endian checks pass in a real compiled
  executable (`tests/unit/wad_header_tests.pb`).

## M1-02 — lump lookup and payload reading

Original C symbols consulted (same pinned revision):

- `W_CheckNumForName` (`w_wad.c`): copies up to eight bytes with `strncpy`,
  forces a terminator, uppercases the query, compares two 32-bit words and scans
  the directory backwards.
- `W_GetNumForName` (`w_wad.c`): calls the check and terminates with `I_Error`
  when the name is absent.
- `W_LumpLength` (`w_wad.c`): returns the directory size.
- `W_ReadLump` (`w_wad.c`): reopens the reloadable file by `reloadname`, seeks,
  reads the whole lump and reports a short read. `lumpinfo_t` stores the
  position, size and optional handle.

Port mapping:

- `W_CheckNumForName` → `WADFindLump()` in `src/WAD/WAD.pbi`.
- `W_GetNumForName` fatal exit → not ported: DoomPB returns `-1` with an
  actionable `WADLastError()` message instead of terminating the process.
- `W_LumpLength` → existing `WADLumpSize()`.
- `W_ReadLump` → `WADReadLump()`; the zone cache (`W_CacheLumpNum`) is not
  ported in this milestone.

Lookup semantics:

- The query is normalized with ASCII `a`–`z` → `A`–`Z` only. Empty queries and
  characters outside printable ASCII (32–126) are rejected with `-1` and an
  error message; this is stricter than `strupr()` on arbitrary locale bytes.
- Exactly eight bytes are compared. Shorter queries are NUL-padded; queries
  longer than eight bytes use their first eight bytes, as `strncpy` does.
- The directory is scanned from the last entry to the first, so the later
  duplicate wins, including zero-length markers.
- Stored name bytes are never modified. A malformed directory that stores a
  lowercase name does not match an uppercased query, matching the raw-byte
  comparison of the reference; the raw bytes remain available through
  `WADLumpRawNameHex()`.
- Lookup performs no I/O and does not read payload bytes.

Payload-read semantics:

- `WADReadLump(Index, Destination, Capacity)` uses a caller-owned buffer.
  `Capacity` must be nonnegative and at least the lump size; only the lump size
  is written. The function never allocates a substitute buffer.
- Capacity is not used for allocation, so very large capacity values are
  harmless. Bytes are copied verbatim, without string conversion or a
  terminator.
- Zero-length markers succeed without opening or seeking the file and accept a
  null destination.
- Every nonempty read reopens the WAD read-only by the saved path, checks that
  `Lof()` still equals the size captured by `WADOpen()`, revalidates
  `Int64(position) + Int64(size)` against the current length, verifies
  `Loc()` after `FileSeek()`, reads in 16 MB chunks and verifies every
  `ReadData()` count. The temporary handle is closed on every success and
  failure path.
- Validation failures are detected before the first payload byte is written.
  A short read after transfer has begun may leave the destination partially
  modified; this is documented and reported as an error.
- A file replaced with different bytes of exactly the same size cannot be
  detected by these checks.

Safety hardening compared with the original:

- Invalid indices, null destinations, negative capacity and undersized buffers
  are controlled errors instead of calls that would abort the process.
- A changed file length after parsing is rejected before any seek or read.
- Payload reads are chunked, so the single `ReadData()` 2 GB limit is never
  approached and no size is truncated silently.

Verified behaviour:

- `tests/unit/wad_lump_tests.pb` covers L01–L20 plus the lowercase-stored-name
  compatibility case (X01) with synthetic fixtures and canary bytes.
- The M1-01 suite remains unchanged and continues to pass.

## M1-03 — PLAYPAL and Doom patch decoding

Original C symbols consulted (same pinned revision):

- `patch_t` (`r_defs.h`): signed 16-bit width, height, leftoffset, topoffset and
  a 32-bit `columnofs[width]` table relative to the patch start.
- `post_t` / `column_t` (`r_defs.h`): `topdelta`, `length`, optional pad bytes and
  a `0xFF` topdelta terminator.
- `V_DrawPatch` (`v_video.c`): applies `leftoffset`/`topoffset` at draw time,
  walks each column, copies `length` pixels from `column + 3`, and advances by
  `length + 4`; a `0xFF` topdelta ends the column.
- `D_PageDrawer` (`d_main.c`): draws a full page with `V_DrawPatch(0, 0, ...)`.
- `PLAYPAL` use (`d_main.c` / `I_SetPalette`): raw 768-byte RGB palettes. No
  palette conversion is performed by DoomPB at decode time.

Port mapping:

- `src/Graphics/Palette.pbi` decodes in-memory `PLAYPAL` bytes into a
  caller-owned `PaletteSet` (count plus owned RGB block).
- `src/Graphics/Patch.pbi` decodes in-memory Doom pictures into a caller-owned
  `PatchImage` with separate row-major pixel-index and opacity planes.

Palette semantics and ownership:

- `PLAYPAL` must be a nonzero multiple of 768 bytes; up to 256 palettes are
  accepted (the cap is 196,608 bytes) and the known IWAD contains 14.
- Channels are copied exactly: no VGA 0–63 scaling, gamma, clipping, BGR swap
  or palette blending.
- `PaletteDecode` resets the result first, owns the RGB allocation and leaves
  the structure empty on failure. `PaletteReset` frees the allocation and keeps
  the structure reusable.
- Palette and color indices are validated; rejected access does not write to
  the caller's channel destinations.

Patch semantics:

- Input is never overlaid with a native structure; header fields are decoded
  explicitly as little-endian 16/32-bit values.
- Decoded pixels are row-major; transparency is stored only in the separate
  mask plane (0 transparent, 1 opaque). Transparent pixel bytes are zero. Pixel
  value 255 is an ordinary opaque palette index.
- `leftoffset`/`topoffset` are decoded as signed 16-bit values and preserved;
  they are not applied during decoding. Only vanilla absolute `topdelta`
  semantics are implemented; tall-patch relative offsets are out of scope.
- Posts are applied in source order, so later overlapping posts overwrite
  earlier values. Zero-length posts are accepted when the cursor advances.
- Validation limits: dimensions 1–4096, decoded pixels at most 16,777,216,
  non-null input, 64-bit offset/size arithmetic, column offsets outside the
  header table and inside the input, complete post headers and bodies,
  terminator presence, and `topdelta + length <= height` before any write.
- Allocation failure and any malformed input release both partial planes and
  clear the decoded metadata. `PatchReset` releases both planes; the decoded
  image never borrows the source buffer, so the input may be freed immediately.

Intentional differences from the original renderer:

- The original trusts WAD data and performs unchecked reads/seeks. DoomPB
  validates every offset, post and destination write and reports errors.
- Column offsets pointing inside the patch header/table are rejected. Known
  vanilla pictures point after the table; this is stricter than the original.
- Zero-initializing transparent pixel bytes is a decoder choice; the mask is
  authoritative for transparency.

Verified behaviour:

- `tests/unit/wad_graphics_tests.pb` covers P01–P10 and G01–G24: 34 cases,
  197 assertions, real compiled executable.
- Local Ultimate Doom 1.9ud (`data/DOOM.WAD`, MD5
  `c4fe9fd920207691a9f493668e0a2083`): `PLAYPAL` raw FNV-1a64
  `0872FFC746616E5A`, decoded count 14; `TITLEPIC` raw FNV-1a64
  `5F1254C1156A681E`, decoded 320×200 with offsets 0/0, 64,000 opaque pixels,
  pixel FNV-1a64 `19C7668B2DF19A1A` and mask FNV-1a64 `C68BF664EFA3E525`.
- A separate PowerShell decoder (different implementation) produced the same
  dimensions, opaque count, corner pixels and pixel checksum; its mask value is
  identical modulo a leading-zero formatting artefact. This is a structural and
  checksum cross-check, not proof of pixel-perfect equivalence with a renderer.

## M1-04 — framebuffer and TITLEPIC presentation

Original C behavior consulted (same pinned revision):

- `V_DrawPatch` (`v_video.c`): post `topdelta` is an absolute row, pixels start
  at `column + 3`, the next post is `length + 4` bytes later, and `leftoffset` /
  `topoffset` are applied only at draw time.
- `D_PageDrawer` (`d_main.c`): draws a page with `V_DrawPatch(0, 0, ...)`.
- Palette usage (`d_main.c` / `I_SetPalette`): palette 0 is the normal display
  palette and channels are raw 0–255 RGB.
- No original C code exists for window creation in this port; `Video.pbi` is a
  modern PureBasic presentation adapter, not an engine algorithm.

Framebuffer (`src/Graphics/FrameBuffer.pbi`):

- Authoritative data is a contiguous row-major plane of 8-bit palette indices,
  classic size 320x200. The module has no window, image or OS dependency.
- `FrameBuffer` is caller-owned and zero-initialized once. `FrameBufferCreate`
  owns the plane, `FrameBufferReset` frees it and is idempotent; failed creation
  leaves an empty framebuffer.
- `FrameBufferBlitPatch` composites a decoded patch through its opacity mask:
  mask 0 leaves the destination unchanged, mask 1 copies the index verbatim
  (including 255). Coordinates are clipped at all four edges; fully offscreen
  blits are successful no-ops. `LeftOffset`/`TopOffset` are not applied here.
- Caps: dimensions 1–4096, at most 16,777,216 pixels. Indices are validated to
  0–255; all writes are bounds-checked.
- Conversion emits canonical RGBA (`R, G, B, 255`) and accepts a palette index
  plus caller-owned destination/capacity. No VGA scaling, gamma or BGR swap is
  applied. `FrameBufferScaleNearestRGBA` maps each source pixel to an exact
  `Scale x Scale` block; it is CPU-side and testable without a GUI.

Presentation (`src/Graphics/Video.pbi`):

- A centered window with an inner client area of 960x600 displays a 320x200
  source at exact 3x nearest-neighbour. `ImageGadget()` owns the visible image.
- RGBA upload respects `DrawingBufferPitch()`, the reported pixel format and
  `#PB_PixelFormat_ReversedY`; unsupported formats fall back to `Plot()`.
- `WaitWindowEvent()` blocks until `#PB_Event_CloseWindow`; there is no busy
  loop and no upload on idle events. Image, window and RGBA resources are
  released on normal close and every failure path.
- The process remains a console application, so `--show-title` also leaves the
  console attached. This is intentional for the diagnostic messages.

CLI:

- `DoomPB --iwad <path> --show-title` loads only `PLAYPAL` and `TITLEPIC` via
  the existing WAD APIs, decodes into `PaletteSet`/`PatchImage`, composites into
  the framebuffer, presents the window and exits 0 after it closes.
- Missing/empty/corrupt resources or graphics failures exit 1 with a diagnostic.
  Bad syntax, duplicate options or conflicting actions exit 2. No other option
  opens a window.

Intentional differences and limitations:

- The 960x600 display is square-pixel 8:5, not the historical CRT 4:3 stretch.
  No aspect-ratio correction is implemented in M1-04.
- Presentation is static (one upload per window). It is not yet a
  high-performance gameplay renderer.
- No Win32 window handles, SDL, OpenGL, DLL wrapper or image library is used.
- No screenshot, image export or commercial asset is produced by the code or
  tests.

Verified behaviour:

- `tests/unit/wad_display_tests.pb` covers F01–F24: 24 cases, 199 assertions.
- Local Ultimate Doom integration (read-only): `PLAYPAL` decodes to 14 palettes;
  `TITLEPIC` is 320x200 with 64,000 opaque pixels, pixel FNV-1a64
  `19C7668B2DF19A1A` and mask FNV-1a64 `C68BF664EFA3E525`.
- Programmatic Windows check: the window titled `DoomPB - TITLEPIC (M1-04)`
  reports a 960x600 client area, closes through WM_CLOSE with exit code 0, and
  a second launch behaves identically.
- Visible-window review: **PASS**. A client-area capture showed the correct
  Ultimate Doom title screen, correct RGB colours, no artifacts, exact 3x
  nearest-neighbour blocks and no cropping. The local capture is kept only in
  the ignored `build/` directory and must not be committed or published.

## M2-01 — COLORMAP and PNAMES resource tables

Original C symbols consulted (same pinned revision):

- `R_InitColormaps` (`r_data.c`): reads the whole `COLORMAP` lump and
  256-byte-aligns the buffer for the light-table lookups.
- `R_InitTextures` (`r_data.c`): reads the signed count from `PNAMES`, copies
  each eight-byte name with `strncpy`, resolves it through
  `W_CheckNumForName`, and uses the numeric position as the patch lookup index.
- `W_LumpLength` / `W_ReadLump`: source of the raw payload bytes.

Port mapping:

- `src/Graphics/Colormap.pbi` → `ColormapSet`, `ColormapDecode`,
  `ColormapCount`, `ColormapLookup`, `ColormapReset`, `ColormapLastError`.
- `src/Graphics/PNames.pbi` → `PNamesTable`, `PNamesDecode`, `PNamesCount`,
  `PNamesRawNameByte`, `PNamesDisplayName`, `PNamesReset`, `PNamesLastError`.

COLORMAP semantics:

- The payload is a sequence of 256-byte tables of palette indices. Every byte
  is copied unchanged; entries are never recalculated from `PLAYPAL`.
- Length must be positive and exactly divisible by 256; up to 256 tables
  (65,536 bytes) are accepted. Map and palette indices are bounds-checked.
- Map 32 (grayscale) and map 33 (extra dark) are ordinary tables from the
  decoder's point of view; no lighting formula is applied.

PNAMES semantics:

- The signed little-endian count is followed by that many eight-byte raw names.
  Order, duplicates, NUL padding, embedded NULs, lowercase bytes and high bytes
  are preserved.
- Counts above 65,536, negative counts, short headers and tables whose declared
  bytes do not fit are rejected. Trailing bytes after the declared names are
  accepted and ignored for compatibility.
- Name resolution against the WAD is deliberately deferred to M2-02; no
  `PatchDecode` or texture assembly happens here.
- Display strings stop at NUL and replace bytes outside 32–126 with `.`; raw
  access is limited to byte offsets 0..7.

Ownership and failure policy:

- Both result structures are caller-owned and zero-initialized once. The
  decoder owns a private copy of the bytes; it never borrows the input buffer.
- `Reset` frees the copy, is idempotent and leaves the structure reusable.
- A failed replacement clears the previous decoded data. Both modules report
  actionable text through their `LastError` functions.

Intentional differences from the original:

- The C code trusts the lump size/count and performs little validation. DoomPB
  rejects null pointers, negative/zero lengths, partial tables, negative counts,
  oversized counts and truncated name arrays.
- The original 256-byte alignment of `colormaps` is an engine rendering detail;
  this decoder stores the same bytes in a normal PureBasic allocation. No
  alignment-dependent consumer exists yet.
- PNAMES entries are not resolved eagerly, avoiding cross-module coupling and
  repeated WAD lookups.

Verified behaviour:

- `tests/unit/wad_resource_tests.pb` covers C01–C13 and N01–N15 (28 synthetic
  cases) plus synthetic WAD integration I01–I03.
- Local Ultimate Doom 1.9ud integration: `COLORMAP` is 8,704 bytes / 34 maps
  (raw/decoded FNV-1a64 `01377C69B4BFFA05`); `PNAMES` is 2,812 bytes with 351
  names, `4 + 351*8 = 2,812` and no trailing bytes (FNV-1a64
  `A928B2617C343C48`). No payload tables or name lists are printed.
- `--show-title` still opens the 960x600 TITLEPIC window and exits 0.

## M2-02 — TEXTURE1/TEXTURE2 definitions and PNAMES resolution

Original C symbols consulted (same pinned revision):

- `mappatch_t` / `maptexture_t` (`r_data.c`): on-disk name, masked, width,
  height, obsolete columndirectory, patchcount and 10-byte placements.
- `R_InitTextures`: reads TEXTURE1 first and TEXTURE2 afterwards, preserves
  definition order and patch order, and resolves each referenced PNAMES entry
  through `W_CheckNumForName`.
- `R_CheckTextureNumForName`: case-insensitive `strncasecmp` over eight bytes,
  scanning from the first definition. This is the opposite precedence from
  `WADFindLump`, which returns the last matching directory entry.

Port mapping:

- `src/Graphics/TextureDefs.pbi`:
  - `TextureDefsDecode/Reset/Count/GetNameByte/DisplayName/GetProperties/GetPatch`
    for one TEXTURE1 or TEXTURE2 lump.
  - `TextureCatalogDecode/Reset/Count/GetProperties/GetPatch/FindName/Resolve/
    InvalidateResolved/GetResolvedPatchLump` for TEXTURE1 plus optional TEXTURE2.

Format and validation:

- The 4-byte signed count and 32-bit offsets are read explicitly; definitions
  are never overlaid with native structures.
- Every definition preserves eight raw name bytes, raw masked and obsolete
  columndirectory values, signed width/height, patch count and all five signed
  16-bit placement fields. The obsolete field is never dereferenced.
- Directory order is preserved; offsets need not be sorted and may legally
  overlap or repeat. Patch placements remain back-to-front source order.
- Limits: 65,536 definitions per lump, width/height 1..4096, 1,024 patches per
  texture, 65,536 total patches. Negative counts/offsets/dimensions/patch counts,
  truncated tables or headers, offsets inside the directory table, patch data
  past EOF and non-positive dimensions are rejected with contextual errors.
- Empty definition sets (count 0) are valid. `TEXTURE2` is optional; when present
  it must decode successfully or the whole catalog is cleared.

Resolution:

- Only PNAMES entries actually referenced by a placement are resolved. Unused
  missing entries do not fail resolution.
- A negative or out-of-range PNAMES index, an empty/nonprintable/embedded-NUL
  name, a missing WAD lump or a zero-length patch is an explicit error.
- Canonical names are passed to the existing `WADFindLump`, so duplicate patch
  lumps follow last-match precedence. No PNAMES bytes are modified.
- Resolution is atomic: failure clears every resolved index. A successful call
  stores WAD directory indices only (no payload pointers).
- Resolved indices belong to the current WAD session. `WADClose()`/`WADOpen()`
  invalidates them logically; callers use `TextureCatalogInvalidateResolved()`
  or resolve again.
- Texture-name lookup is first-match and ASCII case-insensitive across
  TEXTURE1 then TEXTURE2, matching `R_CheckTextureNumForName`. The `"-"`
  no-texture sentinel is not interpreted by this API.

Intentional differences from the original:

- The original trusts offsets, counts and dimensions; DoomPB validates all of
  them and caps resource usage.
- PNAMES resolution is explicit and atomic instead of deferred fatal errors in
  the renderer path.
- No texture composition, column lookup generation, caching or rendering is
  performed in this module.

Verified behaviour:

- `tests/unit/wad_texture_defs_tests.pb` covers D01–D20 (20 synthetic binary
  cases), R01–R10 (10 resolution cases) and I01–I03 (3 synthetic WAD
  integration cases).
- Local Ultimate Doom 1.9ud: `TEXTURE1` 9,234 bytes and `TEXTURE2` 8,036 bytes
  are both present; 287 definitions total, 980 patch placements, all 980
  resolved; first texture is 24x72 with 2 patches; metadata FNV-1a64
  `FF132795FFDEA1DB`.
- The M1 suites, `--show-title` and the `0.1.0` version remain unchanged.

## M2-03 — composite wall textures

Original C symbols consulted (same pinned revision):

- `R_GenerateComposite`: walks texture patches in definition order, clips
  placement columns to the texture and composites cached columns.
- `R_DrawColumnInCache`: clips a patch column against the texture height using
  the placement origin and post topdelta.
- `R_GenerateLookup` / `R_GetColumn`: original column-oriented lookup/caching
  representation, consulted only to keep semantics clear.
- `texpatch_t` / `texture_t`: placement origin, PNAMES index and ordered patch
  list from M2-02.

Port mapping:

- `src/Graphics/Texture.pbi`: `TextureImage`, `TextureCompose`,
  `TextureImageReset`, `TextureImageGetPixel`, `TextureImageIsOpaque`,
  `TextureImageOpaqueCount`, `TextureLastError`.

Composition semantics:

- Output is a row-major 8-bit palette-index plane plus a separate opacity mask,
  owned by the caller-facing `TextureImage`.
- Placements are processed in definition order. Opaque source pixels overwrite
  destination pixels and set mask=1; transparent pixels leave both untouched.
- Signed placement origins are clipped on all four edges. A placement entirely
  outside the texture is a successful no-op.
- `PatchImage.LeftOffset/TopOffset` are internal patch alignment and are never
  applied again to a texture placement.
- Uncovered pixels are index 0 with mask 0. Palette index 255 is an ordinary
  opaque index. No COLORMAP, RGB, alpha, filtering or scaling is applied.
- Source patch lumps are read with `WADReadLump`, decoded with `PatchDecode`,
  and released immediately. The output does not alias WAD or patch buffers.

Validation and failure policy:

- Requires a valid catalog, a valid texture index and an open WAD.
- Rechecks width/height and the 16,777,216-pixel budget before allocating two
  planes. Catalog dimension/patch caps still apply from M2-02.
- Unresolved patches, zero-length lumps, malformed patch payloads and allocation
  failures are controlled errors. Partial output is freed and the result is
  left empty. Repeated compose/reset is safe.
- Resolved WAD indices are valid for the current WAD session only. After
  `WADClose()`/`WADOpen()`, callers must invalidate and re-resolve.

Intentional differences from the original:

- The original builds column lookup tables and a cached-column composite; DoomPB
  builds a straightforward row-major plane+mask for this milestone. This is a
  logical per-pixel equivalent, not a claim of bitwise equivalence with
  `R_GetColumn` or of pixel-perfect future rendering.
- The original trusts texture/patch data; DoomPB validates indices, sizes,
  decoded patch data and pixel budgets.
- No persistent texture/patch cache is introduced. Patches are decoded per
  placement for correctness and simplicity.

Verified behaviour:

- `tests/unit/wad_composite_tests.pb` covers X01–X30: 30 cases, 141
  assertions.
- Local Ultimate Doom 1.9ud: all 287 resolved textures compose successfully
  (0 failures) across 980 placements; total opaque pixels 3,595,870.
- Samples: single-patch texture index 2, 128x128, 1 patch, 16,384 opaque,
  FNV-1a64 `19B3B7BBB6ABA081`; multi-patch index 0, 24x72, 2 patches, 1,728
  opaque, `4B883C3FBD63C982`; sparse index 4, 128x128, 1 patch, 11,838 opaque,
  `35F45DEFF60309BA`. Repeated composition of index 0 produced an identical
  checksum.
- The test suite asserts hand-computed exact pixel layouts for single, clipped,
  overlapping, sparse and offset cases, providing an independent expected
  reference rather than relying only on self-derived hashes.

## M2-04 — flat and sprite namespaces, sprite frame metadata

Original C symbols consulted (same pinned revision):

- `R_InitFlats` / `R_FlatNumForName` (`r_data.c`): `firstflat = F_START + 1`,
  `lastflat = F_END - 1`, inclusive index range, markers excluded.
- `R_InitSpriteLumps` (`r_data.c`): `S_START + 1 .. S_END - 1`; patch width and
  signed offsets are read for metadata.
- `R_InstallSpriteLump` / `R_InitSpriteDefs` (`r_things.c`): frame bytes
  `'A'..'A'+28`, rotations `0..8`, `rot=0` versus explicit-rotation conflicts,
  duplicate-slot rejection, paired frame/rotation with horizontal flip, and
  contiguous-frame/complete-rotation validation.
- `spriteframe_t` / `spritedef_t` (`r_defs.h`).

Port mapping:

- `src/Graphics/Flat.pbi`: `FlatCatalog`, `FlatCatalogBuild/Reset/Count/
  GetEntry/NameByte/DisplayName/FindName`, `FlatDecode`, `FlatLoad`,
  `FlatImage`, `FlatImageReset/GetPixel`, `FlatLastError`.
- `src/Graphics/Sprite.pbi`: `SpriteCatalog`, `SpriteCatalogBuild/Reset/Count/
  GetEntry/NameByte/DisplayName/GetPatchInfo`, `SpriteBuildFrames`,
  `SpriteFrameSet`, `SpriteFrameGet/Reset`, `SpriteLastError`.

Flat semantics:

- Markers are found with `WADFindLump` (last duplicate marker wins) and excluded
  from the catalog; interior entries retain physical directory order and
  absolute WAD indices.
- Nested zero-length markers inside the outer range (for example `F1_START` /
  `F1_END` in Ultimate Doom) remain catalog metadata, matching vanilla's
  inclusive flat index space. Only outer `F_START`/`F_END` delimit the range.
- A flat must be exactly 4,096 bytes. Decoding copies the payload into private
  64x64 row-major storage. Palette index 255 is valid.
- Empty ranges are valid. Missing or reversed markers fail discovery. Wrong-size
  interior entries stay inspectable and fail at decode.
- Catalog lookup is namespace-constrained and returns the last matching flat in
  the range. Vanilla `R_FlatNumForName` performs a global WAD lookup and
  subtracts `firstflat`; this differs only for unusual cross-namespace name
  collisions.

Sprite semantics:

- Markers are excluded and all interior lumps keep raw eight-byte names,
  absolute WAD directory indices and sizes. No name re-resolution occurs, so a
  duplicate name elsewhere cannot redirect a catalog entry.
- Frame byte range is 0..28 (`'A'..'A'+28`); rotation is 0..8 (byte `'0'..'8'`).
  Noncanonical names are exposed as metadata but fail strict assembly only when
  their four-byte ID is requested.
- Rotation 0 fills all eight views and conflicts with explicit rotations.
  Explicit rotations require all eight slots; duplicate slots are rejected.
- A nonzero byte 6 requests a secondary frame/rotation pair in bytes 6/7 using
  the same WAD lump with flip=1. A nonzero byte 7 with zero byte 6 is an
  incomplete pair and is rejected.
- Frames from 0 through the highest frame must be contiguous. Missing frames or
  rotations fail only the requested frame set; the catalog remains usable.
- Frame sets own absolute WAD indices/flip bytes and never point into WAD data.
  Rebuild catalogs and frame sets after `WADClose()`/`WADOpen()`.

Intentional differences from the original:

- The original calls `I_Error` for incomplete groups; DoomPB returns structured
  errors and leaves the catalog intact.
- The original stores sprite lump offsets relative to `firstspritelump`; DoomPB
  stores absolute WAD directory indices.
- Multi-WAD `modifiedgame` patching is out of scope; only the single open WAD is
  consulted.
- `F_SKY1` remains ordinary flat metadata; sky semantics belong to the renderer.

Verified behaviour:

- `tests/unit/wad_flat_sprite_tests.pb` covers F01–F16, S01–S20 and I01–I03:
  39 cases, 300 assertions.
- Local Ultimate Doom: `F_START`=2193, `F_END`=2305, 111 interior entries
  (107 valid 4096-byte flats plus nested zero-length markers). Sample decoded
  flat checksums: `914C601BD4AD6095`, `FFCB6128B1528C61`, `2AB2327A75132B68`.
- `S_START`=1068, `S_END`=1833, 764 interior sprite entries. Twenty inspected
  headers were valid; 40/40 sampled IDs built strict frame sets; one decoded
  sprite measured 114x83 with 9,462 pixels.
- `--show-title` and the `0.1.0` CLI remain unchanged.

## M2-05 — vanilla map binary structures

Original C symbols consulted (same pinned revision):

- `doomdata.h`: `ML_*`, `mapvertex_t`, `mapthing_t`, `maplinedef_t`,
  `mapsidedef_t`, `mapseg_t`, `mapsubsector_t`, `mapnode_t`, `mapsector_t`,
  `NF_SUBSECTOR`.
- `p_setup.c`: `P_LoadThings`, `P_LoadLineDefs`, `P_LoadSideDefs`,
  `P_LoadVertexes`, `P_LoadSegs`, `P_LoadSubsectors`, `P_LoadNodes`,
  `P_LoadSectors`, `P_LoadBlockMap`, `P_SetupLevel` REJECT assignment.
- `p_maputl.c` / `p_sight.c` used only to confirm BLOCKMAP/REJECT meaning.

Port mapping:

- `src/Map/MapTypes.pbi`: native record structures and format constants.
  Native layouts are intentionally not packed on-disk copies.
- `src/Map/MapDecode.pbi`: THINGS/LINEDEFS/SIDEDEFS/VERTEXES/SEGS/SSECTORS/
  NODES/SECTORS decoders plus REJECT.
- `src/Map/Blockmap.pbi`: BLOCKMAP header, unsigned word offsets and checked
  blocklist accessors.

Fixed-record semantics:

- Exact disk strides: 10, 14, 30, 4, 12, 4, 28, 26 bytes. A payload must be a
  nonnegative exact multiple; partial trailing bytes are rejected. Empty tables
  (length 0) are valid and getters reject indexes.
- 16-bit fields are decoded explicitly. Signed fields are sign-extended;
  LINEDEF flags, vertex/sector/seg indexes, SEGS.angle, SSECTORS counts, and NODE
  children remain unsigned. LINEDEF `sidenum[1] = -1` remains signed.
- SIDEDEF top/bottom/middle names and SECTOR floor/ceiling pics are independent
  raw eight-byte arrays. No NUL assumption, uppercasing or text resolution.
- NODE bboxes keep top/bottom/left/right order. Raw children are preserved;
  helpers expose `NF_SUBSECTOR` and `raw & 0x7FFF`. `0x8000` is subsector 0 and
  `0xFFFF` is flagged subsector 32767. No BSP traversal occurs here.
- Records are stored as native arrays; results are independent of the input
  buffer and WAD lifetime. Caps: 65,536 records per type.
- Cross-lump references (vertex/side/sector ranges, BSP child ranges, blockmap
  line numbers, REJECT size vs sector count) are deliberately deferred to M2-06
  and implemented there.

REJECT:

- Raw bytes are copied into owned storage; an empty lump is valid.
- `MapRejectGetBit` takes the sector count explicitly, requires 0 < N <= 65536,
  validates both sector indexes and reads bit `from*N + to`, LSB-first.
- Missing/truncated matrix bytes are explicit errors; a clear 0 bit is distinct
  from a failed lookup.

BLOCKMAP:

- Header is originX/originY signed 16-bit and width/height unsigned 16-bit.
  Offsets are **word offsets** from the lump start, never sign-extended.
- Decode validates: even length, header size, positive dimensions, cell cap
  (1,048,576), offset table bounds, every referenced list starting at/after the
  table, a zero dummy word, a 0xFFFF terminator within the lump, and a 16,000,000
  word scan budget. Shared/out-of-order offsets are allowed; trailing
  unreferenced whole words are ignored.
- The original `P_LoadBlockMap` merely byte-swaps and trusts the data. DoomPB is
  deliberately stricter for malformed offsets/lists.
- No line-index validation against LINEDEFS is performed here.

Verified behaviour:

- `tests/unit/wad_map_types_tests.pb` covers M01–M48 plus I01–I03: 51 cases,
  190 assertions.
- Local Ultimate Doom maps decode read-only (lump order verified by index):
  - E1M1 (marker 7): THINGS 1430/143, LINEDEFS 6804/486, SIDEDEFS 19980/666,
    VERTEXES 1880/470, SEGS 8964/747, SSECTORS 956/239, NODES 6664/238,
    SECTORS 2288/88, REJECT 968 bytes (minimum 968), BLOCKMAP 36x23/828 cells.
  - E1M2 (marker 18): THINGS 262, LINEDEFS 1033, SIDEDEFS 1323, VERTEXES 942,
    SEGS 1463, SSECTORS 448, NODES 447, SECTORS 200, REJECT 5000 (minimum 5000),
    BLOCKMAP 42x31/1302 cells.
  - E4M1 (marker 304): THINGS 141, LINEDEFS 471, SIDEDEFS 642, VERTEXES 439,
    SEGS 695, SSECTORS 196, NODES 195, SECTORS 81, REJECT 821 (minimum 821),
    BLOCKMAP 18x9/162 cells.
- All three real BLOCKMAPs pass the strict list validation.
- The application remains version 0.1.0; TITLEPIC and CLI are unchanged.

## M2-06 — map loader, cross-reference validation and BSP integrity

Original C symbols consulted (same pinned revision):

- `p_setup.c`: `P_SetupLevel`, `P_LoadThings`, `P_LoadLineDefs`,
  `P_LoadSideDefs`, `P_LoadVertexes`, `P_LoadSegs`, `P_LoadSubsectors`,
  `P_LoadNodes`, `P_LoadSectors`, `P_LoadBlockMap`, `P_GroupLines`, and the
  REJECT length rule `(numSectors*numSectors+7)>>3`.
- `doomdata.h`: record layouts and `NF_SUBSECTOR`.
- `r_defs.h`: `line_t`, `seg_t`, `subsector_t`, `node_t`, `sector_t` fields used
  by the original grouping pass (frontsector/backsector, numlines/lines).

Port mapping:

- `src/Map/MapLoader.pbi`: `MapCanonicalName`, `MapLevelLoad`.
- `src/Map/MapValidate.pbi`: `MapValidateLevel`, `MapLevelValidateResources`.
- `src/Map/MapLevel.pbi`: owned level object, reset/readiness and derived-link
  accessors.

Loading semantics:

- The loader uses the currently open WAD. `MapCanonicalName` accepts only four
  ASCII characters in `E#M#` form and returns uppercase; `MAPxx` is outside the
  M2-06 scope. The marker is located with `WADFindLump` (last duplicate wins),
  must be zero-length, and the following ten directory entries must match the
  canonical names byte-for-byte in order.
- Each payload is read into a temporary buffer through the M2-05 decoders and
  released immediately. The level owns only decoded records and integer arrays;
  it remains valid after the WAD is closed.
- Load is transactional. Every failure path (open, name, marker, order, decode,
  validation) calls `MapLevelReset`, so a failed load never leaves a partially
  ready level. Reset is idempotent and reuses the same object.

Validation and derived data:

- SIDEDEF sectors must be in `0..NumSectors-1`. LINEDEF vertex and side indices
  are checked; a back side of `-1` stays a sentinel; `ML_TWOSIDED` requires a
  real back side. SEGS vertices, linedefs and sides (0/1) are checked, with the
  front sector taken from the selected side and the back sector from the other
  side of a two-sided line. Subsector ranges must be nonempty and inside SEGS;
  the subsector sector comes from its first seg (as in the original grouping).
- Sector membership follows `P_GroupLines`: a two-pass prefix build followed by
  a flat fill. A back sector equal to the front sector is not added twice. The
  original `sector->lines[]` front/back restriction is preserved.
- BSP children are range-checked first (`NF_SUBSECTOR` leaf index against
  `NumSubsectors`, otherwise node index against `NumNodes`). Reachability is an
  iterative DFS from node `NumNodes-1` with explicit node/slot stacks and
  three-state coloring. Cycles are hard errors; unreachable nodes/subsectors
  are diagnostics only. A zero-node map is accepted only with exactly one
  subsector and is reported as a subsector root.
- REJECT must have at least `(N*N+7)/8` bytes; extra padding is preserved.
  BLOCKMAP width/height are read from the validated decoder and every referenced
  line index must be inside LINEDEFS.
- `MapLevelValidateResources` is a separate optional step. It checks flats and
  wall texture names against already decoded catalogs, skipping the `-`/all-NUL
  wall sentinels and rejecting embedded NUL or nonprintable names. It does not
  retain catalog pointers.

Intentional differences and limits:

- Link derivation is explicit rather than storing raw C pointers. Index arrays
  preserve the same front/back ordering used by the original grouping. Only the
  fields required for validation and later rendering are derived.
- The original loader trusts indices and can crash on corrupt maps. DoomPB
  rejects the map before publishing a level. The validator also rejects BSP
  cycles, which the original traversal would loop on (or overflow the stack).
- The loader does not build the renderer's `sector_t` bounding boxes, sound
  chains, or thing spawn state; those belong to later milestones.
- `MAPxx` maps and PWAD overrides are not claimed by M2-06.

Verified behaviour:

- `tests/unit/wad_map_loader_tests.pb` covers L01–L52 plus I01–I03: 55 cases,
  167 assertions, 0 failures.
- Real Ultimate Doom integration (read-only, `--map-info`):
  - E1M1 (marker 7): 143/486/666/470/747/239/238/88 records; REJECT 968/968;
    BLOCKMAP 36x23, 828 cells; root node 237; 238/238 nodes and 239/239
    subsectors reachable.
  - E1M2 (marker 18): 262/1033/1323/942/1463/448/447/200; REJECT 5000/5000;
    BLOCKMAP 42x31, 1302 cells; root node 446; full reachability.
  - E4M1 (marker 304): 141/471/642/439/695/196/195/81; REJECT 821/821;
    BLOCKMAP 18x9, 162 cells; root node 194; full reachability.
- `scripts/test.ps1`: 60/60 checks pass on Windows x64 with PureBasic 6.41.
- At M2-06 acceptance the application version remained 0.1.0; Linux x64 is
  NOT RUN.

## M2-07 — integration, acceptance and v0.2.0 preparation

Original C symbols consulted (same pinned revision):

- `r_data.c`: `R_InitTextures`, `R_InitFlats`, `R_InitColormaps`,
  `R_GenerateComposite` (composite composition and namespace rules).
- `r_things.c`: sprite naming/frame conventions used only to validate metadata.
- `p_setup.c`: `P_SetupLevel`, `P_GroupLines` (already ported; re-checked for
  resource binding and sector membership semantics).
- `doomdata.h`: eight-byte names and map record layouts.

Integration model:

- `tests/integration/m2_release_tests.pb` uses only existing public APIs:
  `WADOpen`/lookup/read, `PNamesDecode`, `TextureCatalogDecode`/`Resolve`/
  `InvalidateResolved`, `TextureCompose`, `FlatCatalogBuild`/`FlatLoad`,
  `SpriteCatalogBuild`/`BuildFrames`, `MapLevelLoad`, `MapLevelValidateResources`
  and the M2-06 accessors. No second parser or duplicated decoder exists.
- Resource binding is a distinct post-load step. The validator now reports the
  map name, sector/sidedef index and field (`floor`/`ceiling`, `upper`/`lower`/
  `middle`), and rejects the `-`/empty sentinels only when they are canonical
  (NUL/space padding). Embedded NUL followed by printable text is an error.
- A `MapLevel` records its canonical name for diagnostics and keeps owning all
  decoded records and derived indices; it does not retain WAD or catalog
  pointers.
- Catalog resolution remains explicit and caller-controlled. After `WADClose`
  or a reopen, a composed image and a loaded level stay valid, but
  `TextureCompose` requires an open WAD and any old resolved WAD indices must be
  invalidated with `TextureCatalogInvalidateResolved` before `Resolve` is run
  again. This is documented caller responsibility, not automatic detection.
- Canonical metadata checksums are FNV-1a64 over explicit little-endian fields
  (counts, REJECT/BLOCKMAP sizes, BSP root/reachability, selected links and
  sector membership). Pointers, native structure bytes and padding never enter
  the hash.

Verified behaviour (Windows x64, PureBasic 6.41):

- `tests/integration/m2_release_tests.pb` without a WAD argument: 35 cases,
  221 assertions, 0 failures (E01-E32, I01-I03).
- With the local Ultimate Doom 1.9ud IWAD (read-only): 36 cases, 240
  assertions, 0 failures.
- Real resources: 287/287 wall textures composed, 3,595,870 opaque pixels; 111
  interior flats; 764 sprite entries; sample `TROO` frame metadata and a patch
  decode pass.
- `MapLevelValidateResources` with both catalogs:
  - E1M1: 176 flat references, 22 distinct; 633 wall references, 34 distinct.
  - E1M2: 400 flat references, 28 distinct; 1,341 wall references, 59 distinct.
  - E4M1: 162 flat references, 13 distinct; 538 wall references, 17 distinct.
- Stable metadata hashes: E1M1 `8FE25C30E64E2F6A`, E1M2 `631D1179C1497612`,
  E4M1 `3798753D4323FB3D`. Synthetic E1M1 two-load hash:
  `8132798E3BE20DD4`.
- Full `scripts/test.ps1`: 64/64 checks; all M1/M2 regression suites green
  (96/694, 31/191, 33/165, 30/141, 39/300, 51/190, 55/167, 35/221 plus I04).
- `--version` prints `DoomPB 0.2.0`; `--help`, `--dump-info`, `--lump-info`,
  `--map-info E1M1/E1M2/E4M1` and `--show-title` (960x600, close exits 0) pass.

Intentional differences and limits at 0.2.0:

- Single WAD only; no PWAD overlay or multi-WAD directory.
- `LumpCache.pbi` is deferred. The original renderer column cache and sector
  bounding boxes are not required for M2 acceptance and remain M3/M4 work.
- Texture composition uses row-major pixel and mask planes rather than the
  original column-cache structures; visible results are equivalent for M2's
  resource validation.
- `F_SKY1` is treated as a normal flat name for binding; sky rendering is M4.
- Linux x64 build/runtime is **NOT RUN**. `bash -n` is not treated as Linux
  validation.

## M3-01 — fixed-point 16.16 arithmetic

Original C symbols consulted (same pinned revision):

- `m_fixed.h`: `FRACBITS 16`, `FRACUNIT (1 << FRACBITS)`, `typedef int fixed_t`
  (signed 32-bit, 16.16 interpretation), declarations of `FixedMul`, `FixedDiv`
  and `FixedDiv2`.
- `m_fixed.c`:
  - `FixedMul`: `return ((long long)a * (long long)b) >> FRACBITS;`
  - `FixedDiv`: early guard `if ((abs(a)>>14) >= abs(b)) return (a^b)<0 ?
    MININT : MAXINT; return FixedDiv2(a, b);`
  - `FixedDiv2`: active implementation is the `double` form
    `c = ((double)a)/((double)b)*FRACUNIT;` with `I_Error` when
    `c >= 2147483648.0 || c < -2147483648.0`, then a `fixed_t` cast. The `#if 0`
    integer shift form is inactive.
- Consumers inspected only as context: `p_maputl.c` (`FixedDiv(num,den)`,
  `FixedMul` slope/intercept, `abs`), `r_main.c`
  (`FixedDiv(dy,dx)>>DBITS`, `scale = FixedDiv(projection,z)`) and `r_segs.c`
  (`FixedDiv`, `FixedMul` projections).
- Map-unit conversions in `p_setup.c`: `vertex->x = SHORT(..)<<FRACBITS`,
  `sector floorheight/ceilingheight = SHORT(..)<<FRACBITS`, node bbox and seg
  angle/offset `<<16`. The M2 decoders store those C SHORT fields as signed
  `.l` map-unit integers; conversion is M3-01 work.

Port mapping (`src/Core/Fixed.pbi`):

- `fixed_t` → `.l` signed 32-bit; `#FRACBITS/#FRACUNIT/#FIXED_MIN/#FIXED_MAX`.
- `FixedMul` → `FixedMul(A.l, B.l)`.
- `FixedDiv` → `FixedDiv(A.l, B.l)`.
- `FixedDiv2` → **checked** `FixedDiv2Checked(A.l, B.l, *Result.Long)`; no
  unchecked fatal API exists.
- `SHORT(..)<<FRACBITS` integer conversion → `FixedFromIntChecked(Value.q,
  *Result.Long)`.
- Renderer integer extraction → `FixedToIntFloor(Value.l)` (arithmetic `>>16`).
- Optional diagnostic → `FixedToIntTrunc(Value.l)`, explicitly truncation toward
  zero, never a substitute for the original shift.
- Explicit narrow policy → `FixedWrap32Low(Value.q)`.
- Diagnostics → `FixedLastError()`.

Verified PureBasic 6.41 integer semantics from disposable compiler probes:

- Assigning a `.l` pair product to a `.q` destination evaluates the product in
  64-bit exactly; production still widens each operand explicitly.
- `>>` on signed `.q`/`.l` is an **arithmetic** shift: the sign bit is preserved,
  `-1 >>16 = -1`, `-65537 >>16 = -2`.
- `/` truncates toward zero: `-65537 / 65536 = -1`, `65536 / -3 = -21845`.
- `%` returns a remainder with the dividend's sign: `-65537 % 65536 = -1`.
- Assignment of an out-of-range `.q` to `.l` truncates the low 32 bits
  (`$100000000 → 0`, `-140737488355328 → 0`), but production does not rely on
  this: `FixedWrap32Low` masks `$FFFFFFFF` and reinterprets `$80000000..` with
  two's-complement sign semantics.
- Assignment of a `double` to `.l` **rounds** (`-65535.99997 → -65536`);
  `Int()` truncates toward zero (`-65535.99997 → -65535`, `-123.75 → -123`).
  `Int()` is used only in the test-only double oracle, never in production.

Semantics implemented:

- `FixedMul`: both operands widened to signed `.q`; product exact; arithmetic
  `>> FRACBITS` reproduces C flooring of a negative quotient (not truncation);
  out-of-range 32-bit floor is explicit low-32 two's-complement wrap. Golden:
  `1×-1=-1`, `-1×-1=0`, `32768×-32768=-16384`, `65536×65536=65536`,
  `INT32_MAX×INT32_MAX=-65536`, `INT32_MIN×INT32_MIN=0`,
  `INT32_MIN×FRACUNIT=INT32_MIN`, `INT32_MAX×65537=-2147450882` (low bits
  `80007FFE`), `INT32_MIN×65537=2147450880` (low bits `7FFF8000`).
- `FixedDiv`: magnitudes made nonnegative using widened `.q` negation, avoiding
  C's undefined `abs(INT_MIN)`; guard `(magnitudeA >> 14) >= magnitudeB`
  evaluated before any quotient; sign mismatch exactly
  `(A ! B) < 0` chooses `#FIXED_MIN`, otherwise `#FIXED_MAX`. Zero denominator
  is always guard-true. Outside the guard, the exact integer quotient
  `(A*FRACUNIT)/B` truncates toward zero and stays inside signed32.
  Golden: `65536/65536=65536`, `65536/32768=131072`, `1/3=21845`, `1/-3=-21845`,
  `16383/1=1073676288`, `16384/1=2147483647` (early conservative saturation
  although the true quotient 1073741824 fits), `-16384/1=INT32_MIN`,
  `0/0=INT32_MAX`, `123/0=INT32_MAX`, `-123/0=INT32_MIN`,
  `INT32_MIN/1=INT32_MIN`, `INT32_MIN/INT32_MIN=65536`.
- `FixedDiv2Checked`: b=0 → `#False`; null output → `#False`; quotient
  `> #FIXED_MAX` or `< #FIXED_MIN` → `#False` (the original calls `I_Error` in the
  corresponding active-double condition). On failure `*Result` is untouched; on
  success the result is written and `FixedLastError()` is cleared. The exact
  signed32 minimum `-2147483648` is **valid** (`-32768/1` accepted). Parity of
  the integer quotient/predicate with the active `double` formula and `Int()`
  truncation is checked over explicit boundaries and 10,000 deterministic
  inputs; no mismatch was observed.
- FixedDiv non-guard versus active `double`: the guard restricts the quotient
  magnitude below ~2^30, and the minimum distance of a rational result to an
  integer boundary (`1/|b|` in quotient units) is larger than the double ULP at
  that magnitude (`~2^-6/|b|`); truncation cannot change the integer result, so
  the exact integer path matches the original for all in-range pairs. Differential
  tests confirm this empirically.
- `FixedFromIntChecked`: bounded input `[-32768, 32767]` before multiplying, so
  huge Quad inputs cannot overflow the `.q` product; `Value*65536` in `.q` then
  post-checked `#FIXED_MIN.. #FIXED_MAX`; `-32768` succeeds to `-2147483648`,
  `+32767` succeeds to `2147418112`, `+32768`/`-32769` fail with result intact.
- `FixedToIntFloor` uses arithmetic `>>16`: `-1→-1`, `-65537→-2`.
  `FixedToIntTrunc` uses `/`: `-1→0`, `-65537→-1`, `-32768→0`.

Intentional differences from original Doom (all safety choices):

- C `abs(INT_MIN)` UB and the signed-left-shift UB in the inactive `FixedDiv2`
  form are never used. Widened magnitudes and multiplication are defined.
- C's implementation-defined narrowing of an out-of-range `long long` to `int`
  in `FixedMul` is replaced by the explicit low-32 two's-complement wrap needed by
  the target Doom implementation. `FixedMul` still does not saturate.
- The active C `FixedDiv2` uses `double` and `I_Error`; DoomPB exports only a
  checked integer-equivalent helper that reports failure safely and leaves the
  caller's result unchanged. The integer path was verified against the double
  predicate/truncation, including parity reasoning above.
- The C code divides with zero denominators only after the FixedDiv guard; the
  checked helper explicitly rejects direct b=0 before division.
- Conversion validates the wide input before the 64-bit multiply; the C loader
  only ever receives signed SHORT fields.
- This module adds no trigonometry, angle tables, geometry, BSP, renderer,
  gameplay or platform dependency. Those remain M3-02/M3 onward.

Verified behaviour (Windows x64, PureBasic 6.41):

- `tests/unit/fixed_math_tests.pb`: 43 cases, 318 assertions, 0 failures
  (FM01–FM40 plus FI01–FI03). Includes the exhaustive pair set `[-32,32]` (4,225
  operations) against a division/remainder floor oracle, and 10,000 deterministic
  division inputs with documented seed `0x12345678` plus mandatory boundary,
  threshold, sign-crossing and zero-denominator vectors against an independent
  guarded oracle and the active double predicate/truncation.
- `tests/integration/m3_fixed_iwad_tests.pb` without a path: FI04 **NOT RUN**,
  exit 0. With the owner's local Ultimate Doom 1.9ud (read-only `data/DOOM.WAD`):
  1 case, 32 assertions, 0 failures; all vertex/sector fields of E1M1, E1M2 and
  E4M1 converted successfully and repeated identically. Measured canonical
  converted-value FNV-1a64 checksums: E1M1 `2F223DE65E071C67`, E1M2
  `9EAE6406696A7858`, E4M1 `BF869A8E7D528B9A`. Counts printed were
  E1M1 470 vertexes / 88 sectors / 1,116 converted fields; E1M2 942 / 200 / 2,284;
  E4M1 439 / 81 / 1,040. No coordinate lists, level tables or payload bytes are
  printed, stored or committed.
- `src/Core/Fixed.pbi` compiles standalone (`pbcompiler --check` exit 0) and in
  `src/DoomPB.pb`; the application remains version `0.2.0`.
- `scripts/test.ps1` on Windows x64, PureBasic 6.41: 73/73 checks passed.
  Without a WAD argument, all previous M0/M1/M2 suites remain green at their
  existing totals (M1 header/lump/graphics/display 17/146, 21/152, 34/197,
  24/199; M2 resources/texture-def/composite/flat-sprite/map-types/map-loader/
  integration 31/191, 33/165, 30/141, 39/300, 51/190, 55/167, 35/221; M2 I04
  NOT RUN), plus the new M3 suite 43/318 and the optional M3 FI04 harness 0/0
  (NOT RUN). That is 413 synthetic cases / 2,387 assertions with 0 failures.
  Separate read-only owner-IWAD runs: M2 integration 36/240 (0 failures) and
  M3 FI04 1/32 (0 failures); with those optional cases the combined observed
  figures are 415 cases / 2,438 assertions.
- CLI regression: `--version` prints `DoomPB 0.2.0`; `--map-info` for E1M1,
  E1M2 and E4M1 exits 0 with the existing metadata; `--show-title` was opened
  programmatically against the local IWAD: window title
  `DoomPB - TITLEPIC (M1-04)`, 960x600 client area, WM_CLOSE exit 0.

Milestone status note: M3-01 implements the math foundation only. M3 as a whole
(angles/tables, geometry, BSP, wall rendering, v0.3.0) is **not** complete and no
`v0.3.0` tag/release exists.

## M3-02 — BAM angles, exact trig tables and geometry primitives

Original C symbols consulted (same pinned revision
`a77dfb96cb91780ca334d0d4cfd86957558007e0`):

- `tables.h`: `FINEANGLES 8192`, `FINEMASK (FINEANGLES-1)`,
  `ANGLETOFINESHIFT 19`, `finesine[5*FINEANGLES/4]` (10240 effective),
  `finecosine` pointer = `&finesine[FINEANGLES/4]` (offset 2048),
  `finetangent[FINEANGLES/2]` (4096), `ANG45/ANG90/ANG180/ANG270`,
  `SLOPERANGE 2048`, `SLOPEBITS 11`, `DBITS = FRACBITS-SLOPEBITS` (5),
  `typedef unsigned angle_t`, `tantoangle[SLOPERANGE+1]` (2049) and the
  `SlopeDiv(unsigned num, unsigned den)` declaration.
- `tables.c`: the complete literal `finetangent`, `finesine` and `tantoangle`
  arrays and `SlopeDiv`: `if (den < 512) return SLOPERANGE;`
  `ans = (num<<3)/(den>>8); return ans <= SLOPERANGE ? ans : SLOPERANGE;`.
- `r_main.c`: `R_PointOnSide`, `R_PointOnSegSide`, `R_PointToAngle`,
  `R_PointToAngle2`, `R_PointToDist`; view state `viewx`/`viewy` was declared in
  `r_state.h` and `R_PointToAngle2` mutates those globals.
- `r_defs.h`: `vertex_t` fixed `x/y`, `node_t` fixed `x/y/dx/dy`, and `seg_t`
  vertex pointers plus derived `offset`. `r_bsp.c` consumers: wall-angle calls
  `R_PointToAngle(line->v1->x, line->v1->y)` and `R_PointOnSide(viewx,viewy,bsp)`
  at node traversal; `p_maputl.c` game-side helpers were inspected only to
  confirm they are a distinct function family and were not ported.
- `r_main.h`: declarations of all five consulted renderer-side functions.

Port mapping:

- `src/Core/Angle.pbi`:
  - `BamWrap32`, `BamAdd`, `BamSubtract`, `BamNegate` preserve exact low-32
    unsigned BAM arithmetic, including `0xFFFFFFFF + 1 -> 0` and unsigned
    negation of a half-turn.
  - `BamFineIndex` computes `(raw >> 19) & 8191` only after low-32 normalization;
    `ANG90 -> 2048`, `ANG180 -> 4096`, `ANG270 -> 6144`, `0xFFFFFFFF -> 8191`.
  - `BamRawInUnsignedDomain` is informational only; any negative or oversized
    Quad raw input is documented as low-32 normalized rather than rejected.
  - `BamAngleValue.Raw.q` is the checked output carrier so `ANG180`/`ANG270` are
    not ambiguous signed-positive `.l` values and zero remains a valid result.
- `src/Core/TrigTables.pbi` and generated `src/Core/TrigTablesData.pbi`:
  - Exact pinned values in an immutable DataSection, read through
    bounds-checked `TrigTangentChecked`, `TrigSineChecked`, `TrigCosineChecked`,
    `TrigTanToAngleChecked`; `BamSin`/`BamCos` are infallible index-mapped helpers.
  - Cosine is only the original sine offset `FINEANGLES/4`; no fourth table is
    generated. Sine index range 0..10239, cosine/fine index 0..8191, tangent
    0..4095 and tantoangle 0..2048 are all enforced.
  - `DoomSlopeDivChecked(num.q,den.q,*Result.Long)` accepts exactly the original
    **unsigned 32-bit** argument domain 0..4294967295; negative or above-2^32
    Quad inputs are rejected with an untouched output. `den < 512` returns 2048
    first. `num << 3` deliberately masks the low 32 bits (C unsigned shift
    wraparound), `den >> 8` is unsigned, the division is unsigned64 exact, and
    the result is capped at `SLOPERANGE`.
- `src/Renderer/Geometry.pbi`:
  - `GeometryPointToAngleChecked(viewX,viewY,x,y,*BamAngleValue)` uses the exact
    eight-octant `x>=0/y>=0/x>y` branches, `ANG90-1`, `ANG180-1`, `ANG270-1`,
    unsigned `-tantoangle` and modulo-2^32 sums.
  - `GeometryPointToAngle2Checked(x1,y1,x2,y2)` is the same computation with an
    explicit origin; unlike C `R_PointToAngle2` it does not mutate global
    `viewx/viewy` state. Numerically it equals the C wrapper for all tested
    vectors, including nonzero origins.
  - `GeometryPointToDistChecked` retains `dx/dy = abs(x-viewx/y-viewy)`, larger-
    first swap, guarded `FixedDiv(dy,dx) >> DBITS` (5), unsigned
    `(tantoangle + ANG90) >> 19`, and `FixedDiv(dx, finesine[index])`. For the
    valid fixed domain the index lies 0..2048 and the cosine lies in
    sine[2048..3072]; no floating `sqrt`, `Sin()` or `ATan2()` is used.
  - `GeometryPointOnNodeSideChecked` and `GeometryPointOnSegSideChecked` share
    the original node/seg fast-path body: vertical/horizontal `<=` boundaries,
    direction-sign answers, XOR sign-bit shortcut, `FixedMul(lineDY>>16, dx)` /
    `FixedMul(dy, lineDX>>16)` and back side 1 on an exact `right == left` tie.
    The seg form derives `ldx=v2x-v1x`, `ldy=v2y-v1y` first, then uses v1 as the
    origin, preserving endpoint order.
- Provenance/generation:
  - `scripts/gen_trig_tables.py` is a one-time developer-only generator, not a
    build/test dependency. It reads the local pinned `tables.c` (no absolute
    repository path), validates count/first/last and hashes against the pinned
    reference, and emits only numeric `Data.l` values plus license/provenance
    text into tracked `TrigTablesData.pbi`.
  - `scripts/gen_geometry_golden.py` uses a separate Python integer oracle over
    that pinned source and emits only numeric expectations into tracked
    `tests/fixtures/m3_geometry_golden.pbi`. Both generated files build from an
    ordinary checkout without the original C tree.

Independent verification of the pinned tables (computed locally from the actual
checkout, not copied from an agent assumption):

| Array | Count | First | Last | Full LE32 FNV-1a64 |
|---|---|---|---|---|
| `finetangent` | 4096 | -170910304 | 170910304 | `6E300CFD277525E1` |
| `finesine` | 10240 | 25 | 65535 | `ADD266F0CB7B06B6` |
| `tantoangle` | 2049 | 0 | 536870912 | `56213612F87A0F4A` |

The three generated table hashes match exactly. The PureBasic runtime recomputes
all three whole-array hashes from the DataSection values (tests AG12-AG14), and
the separate Python extraction/oracle produced the same counts, endpoints and
hashes. `finesine[0]` is historically 25 and `finesine[4096]` -25; these rounding
oddities are preserved rather than "corrected" to 0.

Verified PureBasic 6.41 semantics from disposable compile-only probes before
production code:

- Hex constants `$80000000`, `$C0000000`, `$FFFFFFFF` are Quad literals in this
  context: raw values 2147483648, 3221225472, 4294967295 and nonnegative.
- `Data.l` stores 32-bit signed values; `Data.q`/`PeekQ` stores/reads 64-bit
  values; a `DataSection` label address via `?Label` is usable as a plain pointer
  (`Global *p = ?Label`); native-type suffixes on pointer parameters are rejected
  (`.Quad` invalid), so raw-Quad output uses `BamAngleValue` structure access.
- Bitwise `!` is XOR on Quads; `& $80000000` tests bit 31; `>>` on a nonnegative
  Quad is the required logical shift for unsigned angle indexing.
- Assigning an expression to an existing variable via a type suffix creates a
  "different type" declaration error; all rare `.q -> .l` narrowing is written
  as its own `.l` protected variable only after a proven in-domain check.

Numerical results cross-checked against the independent oracle:

- `SlopeDiv`: den 0/511 -> 2048 guard; 0/512 -> 0; 256/512 -> 1024;
  511/512 -> 2044 and 512/512 -> 2048 cap boundary; 65535/65536 -> 2047 and
  65536/65536 -> 2048; 100000/512 -> 2048; 1000/12345 -> 166 (the alternative
  `(num*2048)/den` formula would incorrectly give 165); 0xFFFFFFFF/0xFFFFFFFF
  -> exact unsigned 256; `1073741824<<3` and `0xFFFFFFFF<<3` reproduce C's
  low-32 shift wrap (0 and 4294967288 respectively). 100 documented-seed pairs
  match a separate test-only division oracle and repeat their checksum.
- `R_PointToAngle*`: coincident -> 0; +X -> 0; +Y -> `0x3FFFFFFF` (ANG90-1);
  -X -> `0x7FFFFFFF` (ANG180-1); -Y -> `0xC0000000` (ANG270);
  +/+ tie -> `0x1FFFFFFF` (ANG45-1); +/- -> `0xE0000000`; -/+ -> `0x60000000`;
  -/- -> `0x9FFFFFFF`; one-LSB perturbations move exactly between those branch
  boundaries; nonzero view vectors match the pure four-coordinate wrapper.
- `R_PointToDist`: +X/+Y/-X/-Y axis at 65536 -> 65537 (the historical cosine
  65535 vs numerator quotient); four 45-degree diagonals -> 92717; 65536/32768
  and swapped -> 73271; fractional 1/1 -> 1, 3/1 ->3 and 1/3 ->3; negative
  quadrant -> 679962; nonzero views -> 400006/185435; large vectors under the
  conservative guard -> 2147483647 (saturation), reproduces exactly.
- Point-on-side: vertical +dy boundary -> back 1, vertical -dy boundary -> front
  0 because of the direction sign; horizontal positive/negative dx orientations
  match the original sign answers; non-axis exact-on-line tie -> back 1;
  one-LSB above/below lines -> front/back as the fixed products dictate;
  30 fixture vectors evaluated through both node and seg wrappers.

Safety differences from the original (documented, not silent approximations):

- C `x - viewx`/`y - viewy` signed overflow, `-x` of INT32_MIN, `abs(INT32_MIN)`,
  and signed left shifts are C undefined behavior. DoomPB computes deltas in
  widened `.q`, **rejects** deltas outside `[-2147483648,2147483647]` with a
  diagnostic and an untouched output. A delta exactly INT32_MIN is supported by
  using its nonnegative unsigned magnitude 2147483648 for octant comparison and
  `SlopeDiv`; for distance that magnitude uses an explicit widened replica of
  FixedDiv's guard/formula (signs are necessarily nonnegative there). This is a
  defined policy where C has no defined reference; ordinary fixed-domain vectors
  still call the accepted M3-01 `FixedDiv` unchanged.
- Identical point in `R_PointToDist` would read a hugely out-of-domain
  `tantoangle` index after `FixedDiv(0,0) -> MAX` and `>>5`. DoomPB returns fixed
  distance **0** with success and no table access. AG38/I01 lock this policy.
- `SlopeDiv` never receives signed values in Doom's legitimate callers; the
  checked API rejects negative/oversized Quad input instead of performing C
  unsigned conversion silently, while exact unsigned values remain accepted.
- Every table index is checked before `Peek`; invalid accesses return `#False`
  with an unchanged output and `TrigLastError()`. The original trusts indexes.
- `R_PointToAngle2`'s global `viewx/viewy` mutation is intentionally not ported;
  see the explicit-origin wrapper above. No renderer-global angle state exists.
- The tables are immutable generated DataSection data, not a runtime floating
  generator, a DLL, downloaded JSON, or mutable heap arrays. No table setup
  occurs per call; generator scripts are not executed at build/runtime.

Intentional limits of M3-02: no BSP tree traversal (`R_RenderBSPNode`),
`R_CheckBBox`, wall/texture projection, `R_InitTextureMapping`, viewangletox,
xtoviewangle, FOV/lighting tables, visible columns, camera, gameplay or
collision port. These remain M3-03 onward.

Verified behaviour (Windows x64, PureBasic 6.41):

- `tests/unit/angle_geometry_tests.pb`: AG01-AG48, 48 cases / 277 assertions,
  0 failures; full table hashes, table samples, cosine alias, SlopeDiv, octant
  vectors, distances, node/seg sides, synthetic map bridge and error/repeat
  cases all pass.
- `tests/integration/m3_geometry_tests.pb`: I01-I03, 3 cases / 40 assertions,
  0 failures; module composition without WAD/map/video, stable DataSection
  tables, synthetic map conversion and a 15-operation snapshot hash
  `4CFC5269DCED92AB` that repeats after intentional failures and clears errors.
- `tests/integration/m3_geometry_iwad_tests.pb` without a path: I04 **NOT RUN**,
  exit 0. With the owner's local Ultimate Doom 1.9ud (`data/DOOM.WAD`,
  read-only): 1 case / 29 assertions / 0 failures; E1M1/E1M2/E4M1 load through
  the existing M2 API. Sampled counts and canonical geometry checksums:
  - E1M1: 470 vertexes / 238 nodes; sampled 32 vertexes / 17 nodes; 132 converted
    fields; 51 side calls (31 front/20 back) / 4 angles / 4 distances; failures 0;
    FNV-1a64 `0DCDBF94926A3A32` (printed `Hex()` omits the leading zero).
  - E1M2: 942 / 447; sampled 61 / 30; 242 converted; 90 sides (50/40), 4 angles,
    4 distances; failures 0; `A0CE3E0A0142A80E`.
  - E4M1: 439 / 195; sampled 30 / 15; 120 converted; 45 sides (15/30), 4 angles,
    4 distances; failures 0; `B7D9E25BCA4CF7B5`.
  Repeated loads produce identical hashes and counts. No coordinates, raw arrays,
  full maps, graphics or WAD bytes are printed or stored.
- `scripts/test.ps1`: observed 86/86 checks pass. All prior M0/M1/M2/M3-01
  regression executables rerun green: observed synthetic totals 464 cases /
  2,704 assertions / 0 failures (prior 413/2,387 plus M3-02 48/277 and 3/40).
  Separate optional read-only owner-IWAD runs add M2 integration 36/240,
  M3-01 FI04 1/32 and M3-02 I04 1/29 (combined observed 467 cases / 2,784
  assertions).
- M3-01 original conversion checksums remain identical (E1M1
  `2F223DE65E071C67`, E1M2 `9EAE6406696A7858`, E4M1 `BF869A8E7D528B9A`).
- CLI regression `DoomPB 0.2.0`: `--version`, `--help`, `--dump-info`,
  `--lump-info PLAYPAL`, `--map-info E1M1/E1M2/E4M1` all exit 0 with existing
  metadata; `--show-title` against the local IWAD opens
  `DoomPB - TITLEPIC (M1-04)`, 960x600 client area, closes through WM_CLOSE and
  exits 0.
- Windows compiler: `PureBasic 6.41 (Windows - x64) - (c)2026 Fantaisie
  Software`. Linux compiler/runtime: **NOT RUN**. `bash -n` for `build.sh` and
  `test.sh` passed in Git Bash as shell syntax only, not Linux validation.
- Documentation lookup: Context7 was attempted. Resolved PureBasic entry
  `/websites/purebasic`; a focused query returned official-doc-derived snippets
  for signed `>>` (arithmetic, sign-preserving) and `DataSection`/`Data.l` type
  declarations. PureBasic 6.41 help/local compiler probes verified the more
  unusual `?label`, `Data.q`, XOR and Quad pointer constraints. C `tables.c`/
  `r_main.c` remain authoritative for Doom numbers; Context7 was not used to
  override engine semantics.

## M3-03 — deterministic fixed-camera BSP traversal and trace

Original C symbols consulted (same pinned revision
`a77dfb96cb91780ca334d0d4cfd86957558007e0`, local `../doom-original/linuxdoom-1.10`):

- `r_bsp.c`: `R_RenderBSPNode(int bspnum)`, `R_Subsector(int num)`,
  `R_CheckBBox(fixed_t *bspcoord)`, `R_AddLine(seg_t *line)`,
  `R_ClearClipSegs(void)`, `R_ClipSolidWallSegment`, `cliprange_t solidsegs[]`.
- `r_main.c`: `R_PointOnSide`, `R_PointInSubsector` root convention
  (`numnodes - 1`, zero-node `subsectors[0]`), `R_RenderPlayerView` calls
  `R_RenderBSPNode (numnodes-1)`, and fixed `viewx/viewy` renderer globals.
- `r_defs.h`: `node_t` fixed `x/y/dx/dy`, bbox order, children; `subsector_t`
  `sector`, `numlines`, `firstline`; `seg_t` `v1/v2`, `angle`, `offset`,
  `sidedef`, `linedef`, `frontsector`, `backsector`.
- `doomdata.h`: `mapsubsector_t`, `mapsubsector_t.firstseg`, `mapnode_t`
  unsigned `children[2]`, `NF_SUBSECTOR 0x8000`.
- `tables.h`: `BAM` representation reused through the existing `Angle.pbi`.
- `p_maputl.c`/`p_sight.c` `REJECT`/`BLOCKMAP` were inspected only to confirm they
  are separate visibility/collision mechanisms and were not consulted by this
  traversal.

Port mapping:

- `src/Renderer/Camera.pbi`:
  - caller-owned `BspCamera` (`Magic`, `Ready`, `.l` fixed X/Y, `.q` raw Heading);
  - `BspCameraSetMapUnits` converts signed C-SHORT map units through
    `FixedFromIntChecked`; `BspCameraSetFixed` accepts signed32 fixed_t directly;
  - `BspCameraReset/Get/LastError`; the header stores canonical raw unsigned BAM
    `0..$FFFFFFFF` for `ANG180`/`ANG270`; setters are transactional.
- `src/Renderer/BSP.pbi`:
  - `R_RenderBSPNode` recursion replaced by an explicit LIFO stack of raw 16-bit
    child values; push far child first then near child, so near subtree completes
    first exactly like C recursion. Root comes from validated `MapLevelGetBspRoot`.
  - `R_PointOnSide(viewx,viewy,node)` side selection reuses the already tested
    `GeometryPointOnNodeSideChecked`, including vertical/horizontal `<=` ties,
    XOR sign shortcut and `right == left` back-side tie.
  - `R_Subsector` leaf work emits one `SUBSECTOR` event with the derived sector,
    then one `SEG` event per canonical increasing
    `firstseg..firstseg+numsegs-1`; resolved linedef, side, front and back sector
    links come from the M2 validated accessors. Planes/sprites from `R_Subsector`
    are deferred to M4.
- `src/DoomPB.pb` includes Camera/BSP only for compile-time coverage; startup does
  not load a map, create a camera or start graphics/traversal.

Event schema and ownership:

- `BspTrace` owns a deep-copied array of `BspEvent` records; it never retains a
  `MapLevel`, stack or WAD pointer and remains readable after `MapLevelReset()` or
  `WADClose()`.
- `BSP_EventSubsector` (0): `Subsector`, `Sector` derived; `Seg`, `Linedef`, `Side`,
  `FrontSector`, `BackSector` = documented `-1` sentinels.
- `BSP_EventSeg` (1): `Subsector` owner leaf, absolute `Seg`, **`Sector` = owning
  leaf's derived sector**, `Linedef`, `Side` (0/1), actual `FrontSector`, actual
  `BackSector` (one-sided = `-1`). M3-04 consumers can fetch vertex/direction and
  texture fields from the unchanged owned MapLevel using these stable indices.
- `BspTraceBuild` resets the target trace first. Any null/unready input, root/child/
  seg corruption, record-range failure, `FixedFromIntChecked`/geometry error,
  stack/work/event budget exhaustion or OOM calls `BspTraceReset` and preserves
  the failure text; no partial event list is exposed. Camera and MapLevel are
  never mutated.
- `BspTraceReset` is idempotent, accepts a zero-initialized caller structure, makes
  a valid empty trace (Count 0, Magic valid, no owned storage), frees ownership on
  a recognized object, and rejects an unrecognized Magic or unexplained pointer
  rather than freeing arbitrary memory.
- `BspTraceCount` returns 0 for a valid empty trace and -1 for an unrecognized
  object; reading a valid count does not erase a build failure diagnostic.
  Successful `Build`/`Reset` clear stale error state. `BspTraceGet` validates the
  index, copies any non-null requested field and rejects negative/count-boundary
  indexes without partial writes.

Determinism, safety and limits:

- No `R_CheckBBox` or screen-space culling occurs. `viewangletox`, FOV
  `clipangle`, `R_ClearClipSegs` evolving `solidsegs` and `R_AddLine` clipping do
  not exist yet, so a naive `R_CheckBBox` would be incomplete and could hide valid
  geometry. **The far child is always traversed**; `OcclusionSkips` counter is
  therefore always zero in M3-03. The trace is a chronological BSP walk, **not** a
  visible-surface list. `R_CheckBBox` remains deferred to M3-04 or a later
  explicitly assigned projection/occlusion step.
- Explicit stack capacity is node count + 2 (or 1 for a subsector root); a valid
  acyclic graph's current path cannot exceed node count and LIFO pending siblings
  fit that bound (deep 300-node synthetic chain tested). Every push/pop/item index
  is checked; no recursive call, no infinite loop.
- Work cap is 4,000,000 push/pop items and event cap is 1,000,000 records; initial
  event allocation is bounded to `subCount+segCount` (at least 2), growth doubles
  up to the cap only on capacity exhaustion with checked 64-bit byte arithmetic.
  A 20-node cycle-free doubling DAG accepted by M2 terminates at its event budget
  with an empty trace (no hang/OOM).
- On-disk child encoding: `NF_SUBSECTOR ($8000)` leaf high bit and `$7FFF` index
  mask; nonleaf node references must stay below `$8000` in canonical vanilla
  encoding. Defensive checks reject a node root at/above `$8000`, a subsector root
  on a node map, a subsector root without exactly one subsector, and invalid
  root/leaf/node child indices. M2 already validated ordinary vanilla maps; these
  traversal-side checks cover externally corrupted ready memory.
- Shared-child DAG policy: M2 rejects cycles but permits non-cyclic sharing.
  M3-03 **reproduces repeated node/leaf occurrences deterministically** like the
  original recursion, under the hard visit budgets, instead of silently
  deduplicating. This is documented and tested (B47 deterministic repetition;
  B48 budget exhaustion).
- Counters: visited nodes/subsectors, emitted segs/events, work items,
  occlusion skips. No global sorting/deduplication, no REJECT/BLOCKMAP visibility
  classification, no emission of every sector linedef; only the subsector SEGS
  range is authoritative.

Verified behaviour (Windows x64, PureBasic 6.41):
`PureBasic 6.41 (Windows - x64) - (c) 2026 Fantaisie Software`.

- `tests/unit/bsp_traversal_tests.pb`: B01–B48, **48 cases / 669 assertions / 0
  failures**. Test-only original tiny map records built through the M2 decoders and
  `MapValidateLevel`; no WAD/video dependency. B32 compares the production iterative
  trace against a separate test-only recursive reference interpreter. B31 traverses
  a 300-node/301-subsector deep chain with 602 events and explicit work counters;
  B40/B47/B48 prove repeatability, deterministic DAG repetition and controlled
  exponential-DAG budget failure.
- `tests/integration/m3_bsp_tests.pb`: I01–I03, **3 cases / 87 assertions / 0
  failures**. Self-created ten-lump PWADs through the real WAD/MapLevel APIs; I01
  nested-tree full order and links; I02 WADClose/level-reset/reload/reopen/repeat
  reset and failed-build cleanup; I03 malformed node rejection by the real loader,
  late geometry overflow and doubling-DAG trace-budget failure, unchanged
  camera/level and successful recovery.
- `tests/integration/m3_bsp_iwad_tests.pb`: without path I04 **NOT RUN** exit 0.
  With owner Ultimate Doom 1.9ud (`data/DOOM.WAD`, read-only): **1 case / 45
  assertions / 0 failures**, file size 12,408,292 and MD5
  `c4fe9fd920207691a9f493668e0a2083` unchanged before/after. Camera from the first
  validated player-one THING start (`P_SpawnPlayer` heading `ANG45*(angle/45)`);
  culling disabled:
  - E1M1: 239 subsector events / 747 seg events / 986 total; 238 nodes visited;
    239/747 leaf/seg counters; duplicate/missing subs 0/0, segs 0/0, occlusion
    skips 0; FNV-1a64 canonical trace `E45EF6B5D6BF7660`.
  - E1M2: 448 / 1,463 / 1,911; 447 nodes; 448/1,463; 0 duplicates/missing;
    `33F4DA57BA294E8A`.
  - E4M1: 196 / 695 / 891; 195 nodes; 196/695; 0 duplicates/missing;
    `251409E7266F6A9`.
  Repeated loads produce identical hashes/counts. Only coarse totals and
  non-reconstructable hashes are printed; no coordinates, WAD payloads, graphics,
  textures, sprites or screenshots are stored.
- Full regression rerun after M3-03 (observed, not predicted):
  - synthetic/non-IWAD: previous 464 cases / 2,704 assertions remain green; adding
    B01–B48 (48/669) and I01–I03 (3/87) gives **515 cases / 3,460 assertions**, 0
    failures.
  - owner-IWAD optional runs: M2 integration 36/240, M3-01 FI04 1/32, M3-02 I04
    1/29 and M3-03 I04 1/45; combined all synthetic plus optional observed total
    **519 cases / 3,585 assertions**, 0 failures.
  - `scripts/test.ps1`: without an owner path **101/101 checks pass**; with
    `-IwadPath <legal IWAD>` (read-only optional I04 and `--map-info`
    E1M1/E1M2/E4M1 CLI checks) **117/117 checks pass**.
  - CLI regression `DoomPB 0.2.0`: `--version`, `--help`, startup, usage errors,
    `--dump-info` (2,306 lumps / 12,408,292 bytes), `--lump-info PLAYPAL` (index 0,
    offset 12, size 10,752), `--map-info E1M1/E1M2/E4M1` all exit 0;
    `--show-title` against the local legal IWAD opened window title
    `DoomPB - TITLEPIC (M1-04)` at 960x600, accepted WM_CLOSE and exited 0 with
    `TITLEPIC: 320x200 -> 960x600 (3x nearest-neighbour)`.
- `build.sh`/`test.sh` additions mirror the Windows flags; Git Bash `bash -n`
  returned 0 for both. Linux x64 compilation/runtime remains **NOT RUN**; Bash
  syntax is not treated as Linux validation.
- Documentation lookup: **Context7 USED**. Resolved `/websites/purebasic` and used
  focused official-documentation-derived queries for `Dim`/local arrays,
  `AllocateMemory`/`FreeMemory`/`ReAllocateMemory`/`CopyMemory`, `PokeL`/`PeekL`/
  `PokeQ`, `SizeOf`, structure pointer fields, procedure syntax/scoping,
  `DeleteDirectory` return/pattern and `Fingerprint`/`UseMD5Fingerprint`.
  The pinned C source remained authoritative for Doom semantics; the real
  PureBasic 6.41 compiler rejected invented `Int64()` and helped verify
  `Protected Dim`, pointer-array element access and typed pointer syntax. Official
  local `PureBasic.chm` and real compiler probes were fallbacks for behavior not
  returned by Context7.

Intentional differences from original Doom (all safety/diagnostic choices):

- C recursion is replaced by an explicit bounded stack; the observed leaf/seg
  order is deliberately identical to recursive `R_RenderBSPNode` (proven by B32).
- `R_CheckBBox` is **not ported or approximated** at M3-03; no speculative FOV/
  bbox culling is substituted. This is a scope deferral, not a final visibility
  algorithm claim.
- Original C signed `x-node->x`/`y-node->y` overflow is undefined; DoomPB rejects
  the overflow via the already documented `GeometryPointOnNodeSideChecked` policy
  before publishing a trace. Node map-unit conversion is checked and exact.
- Original root `-1` is represented by M2's explicit zero-node/subssector-0 root
  convention; node maps use `nodeCount-1` from `MapLevelGetBspRoot`, never node 0.
- The original uses global renderer `viewx/viewy`/`viewangle`; DoomPB carries them
  in a caller-owned camera and never mutates renderer/simulation globals.
- M3-03 deliberately does not emit `drawsegs`, wall ranges, plane/sprite work,
  screen columns or occlusion state; it is a non-rendering developer trace.
- A valid acyclic shared-child DAG is traversed with repeated occurrences under
  hard budgets instead of being silently collapsed; cycles remain M2-hard errors.
- All index/budget/geometry/OOM failures are diagnostics with transactional empty
  output; original C would trust malformed data and could recurse unboundedly.

Milestone/limits note: M3-03 implements BSP traversal only. Screen projection,
`R_InitTextureMapping`/viewangletox, solid wall clipping, drawsegs, textured
columns, `R_CheckBBox` occlusion and `v0.3.0` are **not** complete. Application
version remains `0.2.0`; no tag/commit was created by this task.

## M3-04 — screen projection, wall clipping and online occlusion

Original C symbols consulted (same pinned revision
`a77dfb96cb91780ca334d0d4cfd86957558007e0`, local `../doom-original/linuxdoom-1.10`):

- `r_main.c`: `R_InitTextureMapping` (`focallength`, `viewangletox[4096]`,
  `xtoviewangle[viewwidth+1]`, `clipangle`), `FIELDOFVIEW 2048`/`FINEANGLES 8192`/
  `ANGLETOFINESHIFT 19`, `R_ExecuteSetViewSize` full-view defaults
  (`viewwidth=320`, `viewheight=200`, `centerx=160`, `centery=100`,
  `centerxfrac=160*FRACUNIT`, `projection=centerxfrac`), tangents/FixedMul/
  FixedDiv and the xtoviewangle bounded scan.
- `r_bsp.c`: `R_ClearClipSegs`, `R_ClipSolidWallSegment`, `R_ClipPassWallSegment`,
  `R_AddLine`, `R_CheckBBox` (including `checkcoord[12][4]`), `R_Subsector`,
  `R_RenderBSPNode`; `solidsegs`/`newend`, `MAXSEGS 32` sentinels and crunches.
- `r_state.h`: `viewangletox`, `xtoviewangle`, `clipangle`, `solidsegs`.
- `r_defs.h`: `cliprange_t {first,last}`, `node_t` fixed origin/direction and
  `bbox[2][4] {TOP,BOTTOM,LEFT,RIGHT}`, `seg_t` `v1/v2`, `sidedef`, `linedef`,
  `frontsector`, `backsector`, `subsector_t` sector/numlines/firstline.
- `r_main.h`/`tables.c`: `FINEANGLES`, `FINEMASK`, `ANGLETOFINESHIFT`, exact
  `finetangent` source data reused by the existing `TrigTables.pbi`.
- `p_mobj.c`: `P_SpawnPlayer` heading rule
  `ANG45*(mthing->angle/45)` reused only by the optional I04 camera selection.
  No gameplay/movement/input was ported.
- `doomdata.h`: unsigned node child encoding `NF_SUBSECTOR $8000`, `$7FFF` leaf
  mask and SHORT bbox/seg/sector map fields, already reused by M2/M3.

Port mapping:

- `src/Renderer/Projection.pbi`:
  - `ProjectionInitClassic` reproduces the original operation order: focal
    `FixedDiv(centerxfrac, finetangent[3072])`, 4096 tangent fenceposts with
    strict `>2*FRACUNIT`/`<-2*FRACUNIT` sentinel values and
    `(centerxfrac-t+FRACUNIT-1)>>FRACBITS` ceil/clamp, bounded normalized scan,
    then `clipangle=xtoviewangle[0]` as a raw `.q` unsigned BAM value.
  - Owned normalized 4096 table plus retained pre-fencepost 4096 table and 321
    inverse entries; immutable for reuse, idempotent reset, transactional Init.
  - Public checked accessors `ProjectionGetViewAngleToX/PreViewAngleToX/
    XToViewAngle/ClipAngle/Constants/TableCounts`; no global renderer arrays.
- `src/Renderer/ClipSegs.pbi`:
  - `ClipStateBeginFrame` reproduces `R_ClearClipSegs` inclusive posts
    `[-0x7FFFFFFF,-1]`, `[viewwidth,+0x7FFFFFFF]` and drawable domain
    `0..viewwidth-1`.
  - `ClipSolidSegment` reproduces the original scan/order: uncovered left-to-right
    subspans are published before the solid interval expands/merges posts; later
    walls cannot re-emit covered pixels. `ClipPassSegment` publishes uncovered
    subspans without modifying occlusion.
  - Owned checked ranges/spans instead of C fixed `solidsegs` and pointers:
    initial capacity 4/64, doubling growth, 1024 range / 1,000,000 span caps;
    every index, capacity, byte budget and inclusive domain is checked.
- `src/Renderer/WallVisibility.pbi`:
  - `R_AddLine` order preserved exactly: `angle1=R_PointToAngle(v1)`,
    `angle2=R_PointToAngle(v2)`, unsigned `span=angle1-angle2`, strong backface
    `span>=ANG180`, `rw_angle1` only as consumed context, unsigned
    `angle -= viewangle`; strong left `tspan=angle1+clipangle > 2*clipangle` then
    adjusted `tspan>=span` reject else `angle1=clipangle`; strong right
    `tspan=clipangle-angle2 > 2*clipangle` then same reject else
    `angle2=-clipangle`; fine indexes `(angle+ANG90)>>19`; x1/x2
    `viewangletox` access; `x1==x2` no-op; inclusive `[x1,x2-1]`.
  - Left/right branches and exact tie boundaries are factored public checked
    helpers `WallApplyLeftClip`/`WallApplyRightClip`, tested independently.
  - Classification order: missing back sector -> SOLID; back ceiling <= front
    floor or back floor >= front ceiling -> SOLID closed door; unequal planes ->
    PASS; equal planes+light with catalog-aware/resolved identical flats and
    `midtexture==0` -> original non-publishing empty trigger skip; otherwise PASS.
    Heights use signed map-unit LONG comparisons exactly (original values are
    FRACUNIT multiples; no invented fixed arithmetic).
  - Optional decoded `FlatCatalog`/`TextureCatalog` route reproduces the original
    resolved index equality including first-texture-index-0 absence quirk. On a
    structurally validated map without catalogs, a narrow canonical raw 8-byte
    comparison is used; malformed flat slot -> not identical (conservative PASS)
    and malformed middle slot -> present (conservative PASS), so no false
    transparency or invented catalog index.
  - `R_CheckBBox`: `boxx <=left / <right / else`, `boxy >=top / >bottom / else`,
    `boxpos=(boxy<<2)+boxx`, boxpos 5 visible; exact corner indexes per row;
    camera-relative BAM angles; `span>=ANG180` conservative visible; same
    clipangle strict branches; `viewangletox` columns; `sx2--`, live post scan.
    Exact checkcoord bytes for all 12 rows; unreachable placeholder/trailing rows
    return UNKNOWN/VISIBLE rather than the original degenerate zero-corner cull.
  - Online walk: bounded explicit LIFO stack; node far `R_CheckBBox` is scheduled
    beneath the near child and runs only after all near segs updated live posts;
    OCCLUDED prunes the far visit, VISIBLE/UNKNOWN pushes it. Result owns deep-
    copied ordered `WallSpan` records and distinct counters.
- `src/DoomPB.pb`: compile-only includes Projection/ClipSegs/WallVisibility.
  Ordinary CLI/startup still does not load a map or run this traverse.

Deviations from original C (intentional safety/diagnostic, all documented):

- The original `viewangletox` ends normalized in place and has no separate
  pre-fencepost copy. DoomPB keeps both owned tables: the public one is normalized
  byte-for-byte, the pre copy is diagnostic-only; no observable lookup changes.
- Original `solidsegs` sentinel extension/deletion and `goto crunch` pointer
  compaction are replaced by checked real-post insertion/consolidation between
  two fixed sentinels. Emitted subspans/order and screen-domain union coverage are
  identical; only private container representation differs. Tiny widths 1..320
  are support/test scope for the interval module; the production shim requires
  320.
- Original C trusts `viewangletox` indexes, malformed bboxes, textures/flats and
  pointers. DoomPB validates every index/range and returns explicit diagnostics.
  Fixed conversion/table/camera-relative uncertainty in `R_CheckBBox` falls back
  conservatively to VISIBLE/UNKNOWN and is counted, never silently culls geometry.
- Catalog-aware identity is the preferred original route; canonical raw fallback
  is conservative and cannot infer any texture/flat number. This is a documented
  resource-availability adaptation, not approximate physics/render math.
- C recursion is replaced by an explicit stack; the observed online leaf/seg
  chronology, near-before-far and occlusion timing are published in this order
  and independently oracle-tested. M3-03's separate cull-free `BspTraceBuild` is
  unchanged.
- M3-04 does not `R_StoreWallRange`, emit `drawsegs`, compute vertical wall
  projection, step textured columns, build visplanes, render sky/sprites/COLORMAP
  pixels or write a framebuffer. It is headless numeric screen-column visibility.

Verified behaviour (Windows x64, PureBasic 6.41):
`PureBasic 6.41 (Windows - x64) - (c) 2026 Fantaisie Software`.

- Projection fixture oracle (`scripts/gen_projection_golden.py`, pinned
  `tables.c`): all 4096 normalized `viewangletox`, all 4096 pre-fencepost and all
  321 `xtoviewangle` entries verified; focal length `10477766` (`0x9FE0C6`),
  clipangle `0x20080000`; FNV-1a64 normalized `F45B52285F25D5DF`, pre
  `EAE596370F96286A`, inverse `4EC83D702DA4CD32`. Operation reuses the canonical
  projection once and does not mutate tables per frame.
- `tests/unit/wall_clipping_tests.pb`: WC01-WC52, **52 cases / 474 assertions / 0
  failures**. Independent reference `R_AddLine`, clip bitmap/interval oracle and
  recursive online walker oracles; strict left/right ties, all checkcoord bytes/
  reachable boxpos, 16 disjoint-column growth, 70 PASS emissions, deterministic
  150-op frame, catalog-aware/fallback identity, zero-node root, corrupt edge/DAG/
  budget failures, result lifetime/reset/recovery and counter reconciliation.
  No commercial data or pixels are involved.
- `tests/integration/m3_wall_clip_tests.pb`: I01-I03, **3 cases / 115 assertions /
  0 failures**. Fresh synthetic ten-lump PWADs through real WAD/MapLevel APIs.
  I01 two-leaf SOLID `[0,319]` fingerprint `60A24EC7D48916B4`; I02 unchanged
  cull-free quad chronology versus M3-04 SOLID occlusion `5EEDC66C4BB96932` and
  four PASS `[0,319]` fragments in 3,2,1,0 order `6CD6B90817A62A89`; I03 A->B->A
  reload/direction change (ANG180 wrapped left candidate `[177,319]`
  `874812E8D8EFE267`)/Reset/repeat and corrupted-root-edge transactional failure
  then restored-edge original fingerprint.
- `tests/integration/m3_wall_clip_iwad_tests.pb`: without path I04 **NOT RUN**
  exit 0. With owner Ultimate Doom 1.9ud (`data/DOOM.WAD`, read-only):
  **1 case / 117 assertions / 0 failures**, file size 12,408,292 and MD5
  `c4fe9fd920207691a9f493668e0a2083` unchanged before/after. Decoded PNAMES 351,
  textures 287 (resolved), flats 111; one 320x200 center 160,100 projection.
  Player-one THING cameras; cull-free cross-check totals reused (E1M1 238 nodes/
  239 leaves/747 segs; E1M2 447/448/1,463; E4M1 195/196/695) with zero trace
  occlusion. Online catalog-aware:
  - E1M1: 35 spans / 49 nodes / 32 leaves / 103 segs; candidates 23/15; backface
    41, FOV left/right 24/0, zero-width 0, empty 0; bboxes 31/18/0; growth 1/0,
    allocations 5, work 260; span FNV `74B485154CE29B0B`; counters
    `7ADB45DBF2611B77`.
  - E1M2: 54 / 69 / 42 / 151; candidates 42/33; backface 62, FOV 9/0,
    zero-width 5; bboxes 41/28/0; growth 1/0, allocations 5, work 360; span FNV
    `8AC0627513C4B619`; counters `83CAB0E1049B850A`.
  - E4M1: 69 / 49 / 40 / 159; candidates 26/55; backface 65, FOV 2/0,
    zero-width 10, empty 1; bboxes 39/10/0; growth 1/1, allocations 6, work 276;
    span FNV `9FD0B15A0F33197E`; counters `CCAA2442EB270717`.
  Every span matched decoded seg/line/side/front sector and recomputed
  catalog-aware SOLID/PASS kind; all online passes reported positive live
  occlusion and fewer leaves than cull-free; duplicate/Reset Builds identical;
  no coordinates, WAD payloads, textures, graphics or screenshots printed/stored.
- Counter semantics: `SolidCandidates`/`PassCandidates` count each processed
  seg's R_AddLine SOLID/PASS classification outcomes, **not** `WallSpan` records.
  Depending on live occlusion a candidate emits 0..n uncovered inclusive
  fragments, following original ClipSolid/PASS order. `EmittedFragments` equals
  the published span count; candidates plus every reject outcome class
  (empty/backface/FOV/zero-width) reconcile `ProcessedSegs`. Owner counters do
  not equate candidates with spans: E1M1 23/15 -> 35 spans; E1M2 42/33 -> 54;
  E4M1 26/55 -> 69 (fully covered candidates emit no fragment).
- Full regression rerun after M3-04 (observed, not predicted):
  - the ten individual M1/M2 WAD executable outputs re-measured 17/146, 21/152,
    34/197, 24/199, 31/191, 33/165, 30/141, 39/300, 51/190 and 55/167; their
    column sum is **335 cases / 1,848 assertions / 0 failures**, matching the
    M2-07 task baseline. The earlier M3-04 final report's 375/1,668 aggregate was
    a manual transcription/arithmetic error in the report only (not in any suite
    output, expected total or saved docs); it is corrected here without changing
    suite expectations or production code.
  - the actual rerun before adding the new suites reproduced the M3-03 baseline
    exactly: prior synthetic/non-IWAD suites at **515 cases / 3,460 assertions /
    0 failures**, and prior suites including optional owner-IWAD runs at **519
    cases / 3,585 assertions**. All prior suite executables ran green; no old
    expected suite count/assertion or trace hash was weakened or rewritten.
  - adding M3-04 WC01-WC52 (52/474) and synthetic I01-I03 (3/115) gives **570
    cases / 4,049 assertions / 0 failures**.
  - optional owner-IWAD runs: M2 I04 1/19, M3-01 FI04 1/32, M3-02 I04 1/29,
    M3-03 I04 1/45 and M3-04 I04 1/117; combined observed **575 cases / 4,291
    assertions / 0 failures**.
  - `scripts/test.ps1`: without an owner path **116/116 checks pass**; with
    `-IwadPath <legal IWAD>` (read-only M3-03/M3-04 I04 and `--map-info`
    E1M1/E1M2/E4M1 CLI checks) **138/138 checks pass**.
  - `build.sh`/`test.sh` mirror the new targets/optional I04; Git Bash `bash -n`
    returned 0 for both. Linux x64 compilation/runtime remains **NOT RUN**.
  - Main `src/DoomPB.pb --check` and build exit 0; `--version` remains
    `DoomPB 0.2.0`; existing smoke diagnostics/exit codes unchanged.
- Documentation lookup: **Context7 USED**. Real MCP calls resolved
  `/websites/purebasic` and returned official-doc-derived snippets for structure
  pointer fields, `SizeOf`, `PokeL`/`PokeQ` and memory allocation/free behavior.
  Official local `PureBasic.chm` plus disposable real compiler probes were
  fallbacks for comparisons in `Check(...)`, typed pointer alignment of the
  21-output stats call and unsigned `.q` angle transport. The pinned C source
  remained authoritative for Doom algorithms; Context7 was not used to override
  engine semantics.

Milestone/limits note: M3-04 completes only headless projection/clipping/visibility
integration; `R_StoreWallRange`, `drawsegs`, vertical wall projection, textured/
single-color column drawing, planes, sky/sprites, a framebuffer frame hash and
`v0.3.0` are **not** complete. Application version remains `0.2.0`; no tag/commit
was created by this task.

## Compatibility conventions adopted so far

- WAD and other binary data will be read field by field with explicit
  little-endian helpers; PureBasic structures are never overlaid on untrusted
  file bytes.
- 32-bit game-format integers use `.l`; 64-bit bounds/intermediate calculations
  use `.q`; native addresses use `.i` or typed pointers.
- Fixed-point arithmetic stays 16.16 (`FRACBITS = 16`, `FRACUNIT = 65536`); it
  will not be replaced with floating point in gameplay code.
- Duplicate lump names keep the original ordering and last-match lookup rule;
  zero-length marker lumps are valid.

## Handling of game data

No commercial IWAD/PWAD content, extracted graphics, sounds or music is stored in
this repository. `*.wad`, `*.WAD`, `local-data/` and `data/` are excluded by
`.gitignore`.
