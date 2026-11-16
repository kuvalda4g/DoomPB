# DoomPB

DoomPB is an independent, native source port of the original Doom engine written
in **PureBasic**. The goal is to reproduce the behaviour of id Software's
**Linux Doom 1.10** — software renderer, fixed-point arithmetic, 35 Hz game
ticks and WAD compatibility — rather than to reimagine it.

> **Status: `0.1.0` — milestone M1 complete on Windows x64; M2 in progress.**
> The executable validates a WAD, looks up and reads lumps, decodes `PLAYPAL`
> and Doom patches, composites titles and wall textures, and presents `TITLEPIC`
> in a native 960x600 window at 3x nearest-neighbour. M2 adds `COLORMAP`,
> `PNAMES`, `TEXTURE1`/`TEXTURE2`, composite wall textures, flat/sprite
> namespaces, bounds-checked decoders for all ten vanilla map lumps, and a
> validated level loader with cross-reference/BSP checks. The world renderer and
> gameplay are still pending. Linux x64 runtime is **NOT RUN**.

## Legal notice

DoomPB is not affiliated with or endorsed by id Software or ZeniMax Media.
No Doom game data is included or distributed with this project. Playing the
game will require a **legally obtained** copy of *The Ultimate Doom* (`DOOM.WAD`,
version 1.9ud) or another compatible IWAD that you own. Commercial WAD files
must never be committed to this repository.

## Requirements

- **PureBasic 6.41** (full edition) with its command line compiler
  (`pbcompiler`).
- **Windows x64** is the primary development and verification target for
  `0.1.0`. **Linux x64** is a required target for 1.0; the Bash scripts exist
  but Linux runtime remains **NOT RUN** in this release.
- No third-party libraries, SDL, C/C++ engine or external game runtime.

## Building

The build scripts locate the compiler through, in order: an explicit argument,
the `PB_COMPILER` environment variable, `PATH`, then standard PureBasic
installation directories. No developer-specific absolute paths are stored in the
repository.

### Windows (PowerShell)

```powershell
# Syntax check only
./scripts/build.ps1 -Check

# Full build -> build/DoomPB.exe
./scripts/build.ps1

# Build the synthetic WAD unit tests -> build/DoomPB-WadTests.exe
./scripts/build.ps1 -Test

# Build the lookup/payload tests -> build/DoomPB-WadLumpTests.exe
./scripts/build.ps1 -LumpTest

# Build the palette/patch decoder tests -> build/DoomPB-WadGraphicsTests.exe
./scripts/build.ps1 -GraphicsTest

# Build the framebuffer/presentation tests -> build/DoomPB-WadDisplayTests.exe
./scripts/build.ps1 -DisplayTest

# Build the COLORMAP/PNAMES tests -> build/DoomPB-WadResourceTests.exe
./scripts/build.ps1 -ResourceTest

# Build the TEXTURE1/TEXTURE2 tests -> build/DoomPB-WadTextureDefsTests.exe
./scripts/build.ps1 -TextureDefTest

# Build the composite texture tests -> build/DoomPB-WadCompositeTests.exe
./scripts/build.ps1 -CompositeTest

# Build the flat/sprite tests -> build/DoomPB-WadFlatSpriteTests.exe
./scripts/build.ps1 -FlatSpriteTest

# Build the vanilla map binary tests -> build/DoomPB-WadMapTypesTests.exe
./scripts/build.ps1 -MapTypesTest

# Build the map loader/validation tests -> build/DoomPB-WadMapLoaderTests.exe
./scripts/build.ps1 -MapLoaderTest

# Explicit compiler selection
./scripts/build.ps1 -CompilerPath 'C:\Program Files\PureBasic\Compilers\pbcompiler.exe'
```

### Linux (Bash)

```bash
# Syntax check only
./scripts/build.sh --check

# Full build -> build/DoomPB
./scripts/build.sh

# Build the synthetic WAD unit tests -> build/DoomPB-WadTests
./scripts/build.sh --test

# Build the lookup/payload tests -> build/DoomPB-WadLumpTests
./scripts/build.sh --lump-test

# Build the palette/patch decoder tests -> build/DoomPB-WadGraphicsTests
./scripts/build.sh --graphics-test

# Build the framebuffer/presentation tests -> build/DoomPB-WadDisplayTests
./scripts/build.sh --display-test

# Build the COLORMAP/PNAMES tests -> build/DoomPB-WadResourceTests
./scripts/build.sh --resource-test

# Build the TEXTURE1/TEXTURE2 tests -> build/DoomPB-WadTextureDefsTests
./scripts/build.sh --texture-def-test

# Build the composite texture tests -> build/DoomPB-WadCompositeTests
./scripts/build.sh --composite-test

# Build the flat/sprite tests -> build/DoomPB-WadFlatSpriteTests
./scripts/build.sh --flat-sprite-test

# Build the vanilla map binary tests -> build/DoomPB-WadMapTypesTests
./scripts/build.sh --map-types-test

# Build the map loader/validation tests -> build/DoomPB-WadMapLoaderTests
./scripts/build.sh --map-loader-test

# Explicit compiler selection
PB_COMPILER=/opt/purebasic/compilers/pbcompiler ./scripts/build.sh
```

## Testing

The test scripts run a real syntax check, a real build, all ten synthetic WAD
test suites (header/directory, lump lookup/payload, PLAYPAL/patch decoding,
framebuffer/presentation, COLORMAP/PNAMES, TEXTURE1/TEXTURE2 definitions,
composite wall textures, flat/sprite namespaces, vanilla map binaries and map
loader/cross-reference validation), and smoke tests against the produced
executable. They need no game data and no graphical display; no window is
opened by the automated suite.

```powershell
./scripts/test.ps1     # Windows
```

```bash
./scripts/test.sh      # Linux
```

A test run fails with a non-zero exit code if any check fails.

## Command line

```text
DoomPB --version                         Print the version and exit.
DoomPB --help                            Print usage information and exit.
DoomPB --iwad <path> --dump-info         Print WAD header/directory metadata.
DoomPB --iwad <path> --lump-info <name>  Print one lump's index, offset and size.
DoomPB --iwad <path> --show-title        Show TITLEPIC in a 3x window.
DoomPB --iwad <path> --map-info <ExMy>   Load and validate a vanilla map.
DoomPB                                   Print the bootstrap status and exit.
```

`--dump-info` prints only container metadata (type, file size, lump count,
directory offset). `--lump-info` performs the same case-insensitive,
last-duplicate-wins name lookup as the WAD API and prints metadata only.
`--show-title` loads `PLAYPAL` and `TITLEPIC`, decodes them, composites into the
indexed framebuffer and opens a native window with a 960x600 client area
(320x200 at exact 3x nearest-neighbour). The window blocks until it is closed;
closing it exits with code 0. `--map-info <ExMy>` loads the marker plus the ten
canonical map lumps through the M2-06 loader, runs cross-reference/BSP/REJECT/
BLOCKMAP validation and prints counts and diagnostics only. None of these
options prints lump contents. A missing or malformed WAD, a missing lump, an
invalid map or a graphics failure is reported with a non-zero exit code.

| Exit code | Meaning |
|---|---|
| `0` | Success |
| `1` | WAD could not be opened or is invalid, or the lump was not found |
| `2` | Usage error (unknown option, missing value, conflicting actions) |

## WAD API

`src/WAD/WAD.pbi` exposes the container readers used by later milestones:

```text
WADFindLump(Name)                     -> zero-based index, or -1
WADReadLump(Index, Destination, Cap)  -> #True / #False
```

- Lookup compares exactly eight raw name bytes. The query is ASCII-uppercased
  (`a`–`z` only), shorter names are NUL-padded, longer queries use their first
  eight bytes, and the last matching directory entry wins. Stored name bytes are
  never rewritten.
- Reads use a caller-owned destination buffer (`AllocateMemory`/`FreeMemory`).
  The caller guarantees `Capacity`, which must be nonnegative and at least the
  lump size. Only the lump size is written, including arbitrary binary bytes.
- Zero-length markers succeed without I/O and accept a null destination.
- Each nonempty read reopens the WAD read-only, rejects a changed file size,
  revalidates 64-bit bounds and closes the handle on every path. A short read
  may leave the destination partially modified and is reported as an error.

## Graphics API

The decoders operate on caller-loaded byte buffers and do not depend on WAD
globals, so they can be reused by a future lump cache.

```text
PaletteDecode(Bytes, Length, *PaletteSet)  -> #True / #False
PaletteReset(*PaletteSet)
PaletteCount(*PaletteSet)                  -> palette count
PaletteGetRGB(*PaletteSet, Palette, Color, *R, *G, *B)

PatchDecode(Bytes, Length, *PatchImage)    -> #True / #False
PatchReset(*PatchImage)
PatchPixelAt(*PatchImage, X, Y)            -> index, or -1
PatchOpaqueAt(*PatchImage, X, Y)           -> 0/1, or -1
```

- `PaletteSet` and `PatchImage` are caller-owned structures; zero-initialize
  them once (`ClearStructure`). `PaletteDecode`/`PatchDecode` own their internal
  buffers and replace previous data. `Reset` frees the buffers and leaves the
  structure reusable. A failed decode leaves the result empty.
- `PLAYPAL` is a sequence of 768-byte palettes (256 RGB triples). Channels are
  returned as stored, without VGA scaling or gamma. The decoder accepts up to
  256 palettes and rejects zero, negative or non-multiple-of-768 lengths.
- A patch becomes a row-major 8-bit palette-index plane plus a separate opaque
  mask (`0` transparent, `1` opaque). Pixel value 255 is an ordinary index.
  Signed `leftoffset`/`topoffset` are preserved but not applied during decoding.
  Vanilla absolute `topdelta` semantics are used; tall-patch relative offsets
  are out of scope. Dimensions are limited to 4096 and 16,777,216 pixels.
- Malformed offsets, posts, dimensions and truncations are rejected with an
  actionable error; partial output is released. `PatchLastError()` and
  `PaletteLastError()` report the last failure.

## Resource tables (M2-01)

`src/Graphics/Colormap.pbi` decodes lighting/effect translation tables:

```text
ColormapDecode(*Bytes, Length, *ColormapSet)  -> #True / #False
ColormapReset(*ColormapSet)
ColormapCount(*ColormapSet)
ColormapLookup(*ColormapSet, Map, PaletteIndex) -> 0..255 or -1
```

- The lump is a sequence of 256-byte tables of palette indices, not RGB.
  Bytes are copied verbatim; no table is synthesized or modified.
- Length must be a nonzero multiple of 256; up to 256 tables are accepted.
- Both map and palette indices are bounds-checked. The known Ultimate Doom
  `COLORMAP` has 34 tables (8,704 bytes).

`src/Graphics/PNames.pbi` decodes the ordered wall-patch name table:

```text
PNamesDecode(*Bytes, Length, *PNamesTable)    -> #True / #False
PNamesReset(*PNamesTable)
PNamesCount(*PNamesTable)
PNamesRawNameByte(*PNamesTable, NameIndex, ByteOffset)
PNamesDisplayName(*PNamesTable, NameIndex)
```

- A signed 32-bit count is followed by that many eight-byte raw names.
- Order and duplicates are preserved; bytes are never uppercased or Unicode
  converted. NUL padding and embedded NUL bytes are kept.
- Counts above 65,536 and tables whose declared bytes do not fit are rejected.
  Trailing bytes after the declared names are accepted and ignored.
- Raw access is limited to offsets 0..7; display strings stop at NUL and
  sanitize nonprintable bytes.

Both result structures are caller-owned and zero-initialized once; the decoder
owns a private copy, `Reset` frees it, and a failed decode leaves the result
empty. Neither decoder reopens a WAD or borrows the caller's input buffer.

## Texture definitions (M2-02)

`src/Graphics/TextureDefs.pbi` decodes `TEXTURE1` and optional `TEXTURE2`
definitions and resolves referenced patch names:

```text
TextureDefsDecode(*Bytes, Length, *TextureDefs)
TextureDefsReset(*TextureDefs) / TextureDefsCount / TextureDefsDisplayName
TextureDefsGetProperties(*Defs, Index, *Width, *Height, *Masked,
                         *ColumnDir, *PatchCount)
TextureDefsGetPatch(*Defs, TextureIndex, PatchIndex, *OriginX, *OriginY,
                    *PNameIndex, *StepDir, *ColorMap)

TextureCatalogDecode(*T1, T1Length, *T2, T2Length, HasT2, *Catalog)
TextureCatalogReset / Count / GetProperties / GetPatch / DisplayName
TextureCatalogFindName(*Catalog, Name)
TextureCatalogResolve(*Catalog, *PNamesTable)
TextureCatalogInvalidateResolved(*Catalog)
TextureCatalogGetResolvedPatchLump(*Catalog, TextureIndex, PatchIndex)
```

- Definitions preserve eight raw name bytes, signed width/height, raw
  `masked`, obsolete `columndirectory`, patch count and every signed 10-byte
  placement (origin, PNAMES index, stepdir, colormap). `columndirectory` is
  never dereferenced.
- `TEXTURE2` is optional: absent is success, present but malformed is failure.
  Definitions are concatenated in source order, TEXTURE1 first.
- Limits: 65,536 definitions per lump, dimensions 1..4096, 1,024 patches per
  texture and 65,536 patches total. Negative counts, truncated directories,
  offsets inside the directory, invalid dimensions and truncated placements are
  rejected.
- Texture-name lookup is eight-byte ASCII case-insensitive and scans from the
  first definition, matching `R_CheckTextureNumForName()`.
- Only referenced PNAMES entries are resolved. Resolution checks each index,
  builds the canonical patch name, calls `WADFindLump()` (last duplicate lump
  wins), rejects zero-length patches and stores only a WAD index. It is atomic:
  a failure clears all resolved indices.
- Resolved indices are tied to the currently open WAD. After `WADClose()` or
  `WADOpen()`, call `TextureCatalogInvalidateResolved()` or resolve again.
- Result structures are caller-owned and zero-initialized once; all metadata is
  privately copied. `Reset` frees it, is idempotent and is safe after failures.

## Composite wall textures (M2-03)

`src/Graphics/Texture.pbi` assembles a resolved texture definition into an owned
indexed image:

```text
TextureCompose(*Catalog, TextureIndex, *Output)
TextureImageReset(*Output)
TextureImageGetPixel(*Output, X, Y)
TextureImageIsOpaque(*Output, X, Y)
TextureImageOpaqueCount(*Output)
TextureLastError()
```

- Output is a row-major 8-bit palette-index plane plus a separate opacity mask.
  Uncovered pixels are index 0 with mask 0. Palette index 255 remains opaque.
- Patch placements are applied in definition order. Later opaque pixels
  overwrite earlier pixels; transparent source pixels leave the destination and
  mask unchanged.
- Signed `originx`/`originy` place the patch; negative and overflowing positions
  are clipped safely on all four sides. Patch internal `LeftOffset`/`TopOffset`
  are never applied again.
- The source patch is read through the existing WAD API, decoded with
  `PatchDecode`, and released immediately. The output never aliases WAD
  payloads or decoded patch buffers.
- A failed compose frees partial allocations and leaves the output empty.
  Repeated compose/reset is safe.
- The catalog must be resolved against the currently open WAD. After
  `WADClose()`/`WADOpen()`, invalidate and re-resolve the catalog.
- This is a logical row-major composition. It does not port the original
  column-cache representation or `R_GetColumn`; M3/M4 may add renderer-specific
  column access separately.

## Flats and sprites (M2-04)

`src/Graphics/Flat.pbi` discovers the vanilla flat namespace and decodes
64x64 indexed flats:

```text
FlatCatalogBuild / Reset / Count / GetEntry / NameByte / DisplayName / FindName
FlatDecode(*Bytes, Length, *FlatImage)
FlatLoad(*Catalog, RelativeIndex, *FlatImage)
FlatImageGetPixel(*FlatImage, X, Y)
FlatImageReset / FlatLastError
```

- `F_START`/`F_END` are found with the existing last-match WAD lookup and
  excluded from the catalog. The interior range is preserved in directory
  order; nested zero-length markers inside the range remain visible as metadata,
  matching vanilla's inclusive index space.
- A flat payload must be exactly 4,096 bytes. It is copied into owned storage,
  row-major 64x64, with no header, mask, RGB conversion or scaling. Index 255 is
  valid.
- Flat name lookup is namespace-constrained and the last matching flat in the
  range wins. Vanilla `R_FlatNumForName` uses a global WAD lookup minus
  `firstflat`; the two differ only for unusual cross-namespace name collisions.
- Empty ranges are valid (count 0). Missing or reversed markers fail clearly.
  Wrong-size interior entries are rejected at decode.

`src/Graphics/Sprite.pbi` discovers the vanilla sprite namespace and assembles
strict frame/rotation tables:

```text
SpriteCatalogBuild / Reset / Count / GetEntry / NameByte / DisplayName
SpriteCatalogGetPatchInfo(*Catalog, Index, *Width, *Height, *Left, *Top)
SpriteBuildFrames(*Catalog, SpriteID, *FrameSet)
SpriteFrameGet(*FrameSet, FrameIndex, Rotation1To8, *WadIndex, *Flip)
SpriteFrameSetReset / SpriteLastError
```

- `S_START`/`S_END` markers are excluded; every interior lump retains its raw
  eight-byte name, absolute WAD directory index and size in physical order.
  Catalog lookup never re-resolves names through `WADFindLump`, so duplicate
  names elsewhere cannot redirect an entry.
- Names follow vanilla `R_InstallSpriteLump`: bytes 0..3 are the sprite ID,
  byte 4 is frame `A`..`A`+28 (0..28), byte 5 is rotation `0`..`8`; a nonzero
  byte 6 starts a second frame/rotation pair in bytes 6/7 using the same lump
  with horizontal flip.
- Rotation 0 fills all eight views and conflicts with explicit rotations.
  Explicit rotations require all eight slots. Duplicate slots, mixed rot=0,
  incomplete rotations and missing intermediate frames fail strict frame
  assembly for the requested ID, without invalidating the catalog.
- Patch header metadata (`width`, `height`, signed `leftoffset`/`topoffset`) is
  read only after a size check; full post decoding remains the job of the
  existing `PatchDecode`.
- Frame sets store absolute WAD indices and flip flags, not payload pointers.
  Catalog indices are tied to the current WAD and require an explicit rebuild
  after `WADClose()`/`WADOpen()`.

## Vanilla map binary decoders (M2-05)

`src/Map/MapTypes.pbi` defines exact-sized native records (not packed overlays),
magnitudes and constants (`NF_SUBSECTOR`, `ML_*`). `src/Map/MapDecode.pbi`
decodes the eight fixed-record lumps plus REJECT; `src/Map/Blockmap.pbi` handles
BLOCKMAP.

```text
MapThingsDecode/Reset/Count/Get
MapLinedefsDecode/Reset/Count/Get
MapSidedefsDecode/Reset/Count/Get/NameByte/DisplayName
MapVertexesDecode/Reset/Count/Get
MapSegsDecode/Reset/Count/Get
MapSubsectorsDecode/Reset/Count/Get
MapNodesDecode/Reset/Count/Get/ChildIsSubsector/ChildIndex
MapSectorsDecode/Reset/Count/Get/NameByte/DisplayName
MapRejectDecode/Reset/Size/RawByte/GetBit
MapBlockmapDecode/Reset/Header/GetCell/GetLine
```

- Record strides: THINGS 10, LINEDEFS 14, SIDEDEFS 30, VERTEXES 4, SEGS 12,
  SSECTORS 4, NODES 28, SECTORS 26. Lengths must be exact multiples; partial
  trailing bytes are rejected. Zero-length tables are valid empties.
- Signed fields are sign-extended, unsigned fields (flags, vertex/sector words,
  seg angle, node children, subsector counts) keep all 16 bits. LINEDEF
  `sidenum[1] = -1` stays signed. All three SIDEDEF names and both SECTOR pic
  names keep raw eight-byte arrays.
- NODES preserve raw children and bbox order top/bottom/left/right. Helpers
  expose `NF_SUBSECTOR` and the masked child index without graph traversal.
- `REJECT` keeps an owned raw copy. `MapRejectGetBit` takes the sector count
  explicitly, validates indices and returns LSB-first matrix bits.
- `BLOCKMAP` uses unsigned 16-bit **word** offsets. Decode validates the header,
  every referenced list (zero dummy, 0xFFFF terminator), bounds and a work
  budget. Cells may share or reorder list offsets; trailing unreferenced words
  are allowed.
- Cross-lump reference validation (vertex/sector indices, BSP child ranges,
  REJECT size vs sectors, BLOCKMAP line ranges) is performed by the M2-06
  loader/validator described below.
- Result objects are caller-owned and zero-initialized once; decode owns private
  copies, Reset is idempotent, and failures clear previous output.
- Caps: 65,536 records/type, 1,048,576 blockmap cells and 16,000,000 scanned
  list words. These are project safety limits, not Doom format limits.

## Map loading and validation (M2-06)

`src/Map/MapLoader.pbi` assembles a level from the currently open WAD;
`src/Map/MapValidate.pbi` derives links and validates them;
`src/Map/MapLevel.pbi` owns the resulting object.

```text
MapCanonicalName(Name) -> "E#M#" or ""
MapLevelLoad(Name, *Level)              ; requires an open WAD
MapLevelReset(*Level)
MapLevelIsReady(*Level)
MapLevelGetLinedefLinks(*Level, Line, *Front, *Back)
MapLevelGetSegLinks(*Level, Seg, *Line, *Side, *Front, *Back)
MapLevelGetSubsectorSector(*Level, Subsector)
MapLevelGetBspRoot(*Level, *RootIsSubsector, *RootIndex)
MapLevelGetSectorLineCount(*Level, Sector)
MapLevelGetSectorLine(*Level, Sector, Ordinal, *LineIndex)
MapLevelValidateResources(*Level, *Flats, *Textures)   ; optional binding
```

- The map marker is found with the normal last-duplicate-wins lookup and must be
  zero-length. The next ten directory entries must be THINGS, LINEDEFS,
  SIDEDEFS, VERTEXES, SEGS, SSECTORS, NODES, SECTORS, REJECT, BLOCKMAP in that
  order, compared as raw eight-byte names.
- Only the `E#M#` form (four ASCII characters, case-insensitive) is accepted;
  `MAPxx` is outside M2-06. Load is transactional: any decode or validation
  failure resets the whole target level, and a successful load has no pointers
  into WAD buffers or resource catalogs.
- Reference checks cover linedef vertices and sidedefs, sidedef sectors,
  two-sided lines without a back side, seg vertices/linedefs/sides, nonempty
  subsector ranges, and BSP child/leaf indices. Zero nodes are allowed only with
  exactly one subsector; otherwise the root is the last node.
- BSP reachability is an iterative DFS with explicit node/slot stacks and
  three-state coloring, so deep trees cannot overflow the call stack and cycles
  are rejected. Unreachable nodes/subsectors are reported as diagnostics.
- `REJECT` must contain at least `ceil(sectors^2 / 8)` bytes. Every BLOCKMAP
  referenced linedef must be below `NumLinedefs`; the cell count is derived from
  the validated header.
- Derived links are caller-owned integer arrays: front/back sector per linedef,
  front/back sector per seg, sector per subsector and per-sector linedef
  membership (prefix offsets plus a flat list, deduplicating a back side that
  names the same sector). `MapLevelValidateResources` is optional and looks up
  flats and `-`/NUL-free wall texture names in already decoded catalogs.
- `--map-info <ExMy>` prints marker index, record counts, REJECT requirement,
  BLOCKMAP dimensions, BSP root and reachability, or exits 1 with a diagnostic.

## Framebuffer and presentation

`src/Graphics/FrameBuffer.pbi` is platform-independent and owns a row-major
8-bit palette-index plane:

```text
FrameBufferCreate(*Fb, Width, Height)
FrameBufferReset(*Fb)
FrameBufferClear(*Fb, PaletteIndex)
FrameBufferSetPixel(*Fb, X, Y, PaletteIndex)
FrameBufferGetPixel(*Fb, X, Y)
FrameBufferBlitPatch(*Fb, *PatchImage, X, Y)
FrameBufferConvertRGBA(*Fb, *PaletteSet, PaletteIndex, *Destination, Capacity)
FrameBufferScaleNearestRGBA(*Fb, *PaletteSet, PaletteIndex, Scale, *Destination, Capacity)
```

- `FrameBuffer` is caller-owned and zero-initialized once; `Create` owns the
  index plane, `Reset` frees it and is idempotent. Failed creation leaves an
  empty framebuffer.
- Patch blits honor the opaque mask: masked pixels never overwrite the
  destination. Clipping is safe at all four edges; a fully offscreen blit is a
  successful no-op. Patch origin offsets are metadata, not applied implicitly.
- Conversion emits canonical row-major RGBA bytes (`R, G, B, 255`) from palette
  0..255 values with no scaling, gamma or colour-space changes.
- `FrameBufferScaleNearestRGBA` maps every source pixel to an exact
  `Scale x Scale` block. The window uses scale 3, so 320x200 becomes 960x600.
  That is square-pixel 8:5, **not** the historical CRT 4:3 stretch.

`src/Graphics/Video.pbi` is the only module that touches window/image APIs. It
creates a centered native window, uploads the RGBA buffer respecting
`DrawingBufferPitch()`, `DrawingBufferPixelFormat()` and
`#PB_PixelFormat_ReversedY`, displays the image through `ImageGadget()` and
waits for `#PB_Event_CloseWindow` without a busy loop. All window, image and
RGBA resources are released on close and on every failure path. Automated tests
do not open a window; visual acceptance of the title screen remains an owner
check.

## Repository layout

```text
src/        PureBasic sources (DoomPB.pb is the entry point)
src/Core/   shared primitives (little-endian decoding, later fixed-point math)
src/WAD/    WAD container reader, name lookup and payload reads
src/Graphics/ decoders, indexed framebuffer and window presentation
tests/unit/ self-contained tests with synthetic, generated fixtures
scripts/    build/test scripts for Windows (PowerShell) and Linux (Bash)
docs/       development plan, porting notes and task descriptions
build/      generated executables (ignored by Git)
local-data/ game data you own, e.g. DOOM.WAD (ignored by Git)
```

## License

DoomPB is licensed under the **GNU General Public License version 2 only**
(`GPL-2.0-only`). See [LICENSE](LICENSE). Ported engine code will retain the
original id Software copyright and license notices.
