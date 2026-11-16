# Porting notes

This document records **verified facts** about the DoomPB port. It must not
contain guesses, invented upstream commit hashes or copied game data.

## Milestone status

| Milestone | State | Notes |
|---|---|---|
| M0 — repository and reproducible build | complete | first commit `9f84d5d5a3dcbf66be9596fe5299a1209715735b`; CLI, build/test scripts, license and documentation |
| M1 - WAD loader and `TITLEPIC` | complete in working tree | M1-01 committed as `1e5f7d5`, M1-02 as `e5aad2b`, M1-03 as `b7067f6`; M1-04 and version `0.1.0` are in the working tree pending owner commit/tag; TITLEPIC visually verified on Windows x64; Linux x64 NOT RUN |
| M2 - Resources and map loading | complete on Windows x64; `v0.2.0` prepared | M2-01 committed as `53ca2db`, M2-02 as `96c793a`, M2-03 as `117708d`, M2-04 as `4020984`, M2-05 as `2fb2481`, M2-06 as `2f170c1`; M2-07 integration/version changes are in the working tree pending owner commit/tag; renderer pending; Linux x64 NOT RUN |

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
