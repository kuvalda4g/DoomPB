# DoomPB

DoomPB is an independent, native source port of the original Doom engine written
in **PureBasic**. The goal is to reproduce the behaviour of id Software's
**Linux Doom 1.10** — software renderer, fixed-point arithmetic, 35 Hz game
ticks and WAD compatibility — rather than to reimagine it.

> **Status: `0.2.0` — milestone M2 complete on Windows x64 (prepared, owner commit/tag pending).**
> The executable validates a WAD, looks up and reads lumps, decodes `PLAYPAL`,
> `COLORMAP`, `PNAMES`, `TEXTURE1`/`TEXTURE2`, composites titles and wall
> textures, reads flats and sprite metadata, and presents `TITLEPIC` in a native
> 960x600 window at 3x nearest-neighbour. M2 adds bounds-checked decoders for all
> ten vanilla map lumps, a validated level loader with cross-reference/BSP/REJECT/
> BLOCKMAP checks, and end-to-end resource binding of map flats and wall
> textures. The M3-01 signed 16.16 fixed-point math module, the M3-02 raw BAM
> angle model, exact vanilla sine/tangent/atan tables and checked geometry
> primitives (`R_PointToAngle`, `R_PointToDist`, `R_PointOnSide`,
> `R_PointOnSegSide`) are implemented and tested in the working tree. M3-03 adds
> a caller-owned fixed camera and a deterministic iterative BSP traversal with an
> owned chronological `SUBSECTOR`/`SEG` trace: original near-to-far order, no
> recursion, explicit work stack/event budgets and transactional cleanup. It
> deliberately does **not** implement `R_CheckBBox`/FOV/solidsegs culling and
> does **not** render walls, planes or sprites; screen projection, wall clipping/
> textured columns and the world renderer remain M3-04+. Gameplay, UI and audio
> are still pending, M3 as a whole is not complete and `v0.3.0` is not prepared.
> The application version remains `0.2.0`. Linux x64 runtime is **NOT RUN**. No
> Git tag exists until the owner creates it.

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

# Build the M2 end-to-end integration tests -> build/DoomPB-M2IntegrationTests.exe
./scripts/build.ps1 -IntegrationTest

# Build the M3-01 fixed-point math tests -> build/DoomPB-FixedMathTests.exe
./scripts/build.ps1 -FixedTest

# Build the optional M3-01 fixed-point IWAD tests -> build/DoomPB-M3FixedIwadTests.exe
./scripts/build.ps1 -FixedIwadTest

# Build the M3-02 angle/geometry tests -> build/DoomPB-AngleGeometryTests.exe
./scripts/build.ps1 -GeometryTest

# Build the M3-02 synthetic geometry integration tests -> build/DoomPB-M3GeometryTests.exe
./scripts/build.ps1 -GeometryIntegrationTest

# Build the optional M3-02 geometry IWAD tests -> build/DoomPB-M3GeometryIwadTests.exe
./scripts/build.ps1 -GeometryIwadTest

# Build the M3-03 BSP traversal tests -> build/DoomPB-BspTraversalTests.exe
./scripts/build.ps1 -BspTest

# Build the M3-03 synthetic WAD/level/camera/trace integration tests -> build/DoomPB-M3BspTests.exe
./scripts/build.ps1 -BspIntegrationTest

# Build the optional M3-03 real-IWAD BSP tests -> build/DoomPB-M3BspIwadTests.exe
./scripts/build.ps1 -BspIwadTest

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

# Build the M2 end-to-end integration tests -> build/DoomPB-M2IntegrationTests
./scripts/build.sh --integration-test

# Build the M3-01 fixed-point math tests -> build/DoomPB-FixedMathTests
./scripts/build.sh --fixed-test

# Build the optional M3-01 fixed-point IWAD tests -> build/DoomPB-M3FixedIwadTests
./scripts/build.sh --fixed-iwad-test

# Build the M3-02 angle/geometry tests -> build/DoomPB-AngleGeometryTests
./scripts/build.sh --geometry-test

# Build the M3-02 synthetic geometry integration tests -> build/DoomPB-M3GeometryTests
./scripts/build.sh --geometry-integration-test

# Build the optional M3-02 geometry IWAD tests -> build/DoomPB-M3GeometryIwadTests
./scripts/build.sh --geometry-iwad-test

# Build the M3-03 BSP traversal tests -> build/DoomPB-BspTraversalTests
./scripts/build.sh --bsp-test

# Build the M3-03 synthetic WAD/level/camera/trace integration tests -> build/DoomPB-M3BspTests
./scripts/build.sh --bsp-integration-test

# Build the optional M3-03 real-IWAD BSP tests -> build/DoomPB-M3BspIwadTests
./scripts/build.sh --bsp-iwad-test

# Explicit compiler selection
PB_COMPILER=/opt/purebasic/compilers/pbcompiler ./scripts/build.sh
```

## Testing

The test scripts run a real syntax check, a real build, the synthetic WAD/map
suites (header/directory, lump lookup/payload, PLAYPAL/patch decoding,
framebuffer/presentation, COLORMAP/PNAMES, TEXTURE1/TEXTURE2 definitions,
composite wall textures, flat/sprite namespaces, vanilla map binaries, map
loader/cross-reference validation and M2 end-to-end resource/map integration),
the M3-01 fixed-point suite, the M3-02 BAM angle/exact-table/geometry suite,
the M3-02 synthetic geometry integration suite, the M3-03 BSP traversal suite
(B01-B48), its synthetic WAD/level/camera/trace integration (I01-I03) and all
optional IWAD harnesses (NOT RUN without a supplied path), plus smoke tests
against the produced executable. They need no game data and no graphical display
for the synthetic suite; no window is opened by the automated suite without an
explicit IWAD path. `--show-title` remains an owner/gui interactive check.

```powershell
./scripts/test.ps1     # Windows; synthetic only, optional IWAD I04 NOT RUN

./scripts/test.ps1 -IwadPath 'D:\path\to\legally-owned\DOOM.WAD'
# Windows; adds read-only M3-03 E1M1/E1M2/E4M1 I04 and --map-info CLI checks
```

```bash
./scripts/test.sh      # Linux; synthetic only, optional IWAD I04 NOT RUN

IWAD_PATH=/path/to/legally-owned/DOOM.WAD ./scripts/test.sh
# Linux; adds read-only M3-03 E1M1/E1M2/E4M1 I04 and --map-info CLI checks
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

## M2 integration and release acceptance (M2-07)

`tests/integration/m2_release_tests.pb` orchestrates the existing M1/M2 APIs
without duplicating parsers. It covers 32 synthetic scenarios (E01-E32) plus
three lifecycle integration cases (I01-I03):

- WAD directory -> `PNAMES`/`TEXTURE1`/`TEXTURE2` -> resolved patches ->
  composed wall textures; flat namespaces and `FlatLoad`; sprite frame metadata
  and paired-flip handling.
- Ten-lump map load, cross-reference/BSP/REJECT/BLOCKMAP validation, and the
  actual `MapLevelValidateResources` call with both catalogs.
- `TEXTURE1` first-definition precedence, last-match patch lumps, namespace
  isolation, malformed patch/flat/PNAMES/TEXTURE failure paths.
- Ownership after `WADClose`, explicit `TextureCatalogInvalidateResolved` after
  reopen, fresh resolution on WAD B, and deterministic A -> B -> A results.
- Canonical FNV-1a64 metadata checksums built only from explicit
  little-endian fields (never pointers, padding or structure bytes).
- Legacy CLI smoke checks (`--version`, `--help`, `--dump-info`, `--lump-info`)
  and documented failure exit codes.

Passing an optional WAD path runs I04 against a legal local IWAD read-only:

```text
DoomPB-M2IntegrationTests.exe <path-to-DOOM.WAD>
```

I04 decodes `PLAYPAL`/`COLORMAP`, resolves all 287 wall textures, composes them
(3,595,870 opaque pixels on the known 1.9ud fixture), builds 111 interior flats
and 764 sprite entries, then loads E1M1/E1M2/E4M1 and calls
`MapLevelValidateResources` with both catalogs. It reports reference/distinct
counts and stable metadata checksums. The IWAD is never modified, and no game
content or reconstructed images are written.

Known limitations at `0.2.0`: single-WAD operation, no PWAD overlay support, no
generic `LumpCache` or renderer-side column cache, no world rendering or
gameplay, and no Linux runtime validation. `F_SKY1` is accepted as an ordinary
flat for resource binding; sky rendering belongs to M4.

## Fixed camera and deterministic BSP traversal (M3-03)

`src/Renderer/Camera.pbi` carries the original renderer's fixed position and raw
BAM heading in a caller-owned structure without mutating game/renderer globals:

```text
BspCameraSetMapUnits(*Camera, X.q, Y.q, HeadingRaw.q)
BspCameraSetFixed(*Camera, X.l, Y.l, HeadingRaw.q)
BspCameraReset(*Camera)
BspCameraGet(*Camera, *X.Long, *Y.Long, *Heading.Quad)
BspCameraLastError()
```

- X/Y are signed 16.16 fixed-point `.l` values. Map-unit creation uses checked
  `FixedFromIntChecked` (signed C-SHORT domain) and is transactional.
- Heading is a canonical raw **unsigned** 32-bit BAM `.q` value in
  `0..$FFFFFFFF`, so `ANG180`/`ANG270` are stored as 2147483648/3221225472, not
  negative signed integers. M3-03 cull-free traversal depends only on X/Y; the
  heading is retained for later projection work.
- The camera owns no heap memory; `Reset` makes a reusable empty (not ready)
  object and is idempotent. It is not a player actor: no input, `viewz` or 35 Hz
  simulation state.

`src/Renderer/BSP.pbi` walks a **ready validated `MapLevel`** from that camera:

```text
BspTraceBuild(*Level.MapLevel, *Camera.BspCamera, *Trace.BspTrace)
BspTraceReset(*Trace.BspTrace)
BspTraceCount(*Trace.BspTrace)
BspTraceGet(*Trace, EventIndex, *Kind, *Subsector, *Seg, *Sector,
            *Linedef, *Side, *FrontSector, *BackSector)
BspTraceLastError()
```

- Root comes from `MapLevelGetBspRoot`: node maps use the last node index,
  zero-node/one-subsector maps use subsector 0 (the safe equivalent of original
  `R_RenderBSPNode(-1)`). Node 0 is never assumed.
- At each node the near child is chosen by the existing exact
  `GeometryPointOnNodeSideChecked`; near subtree is processed first, then the far
  subtree **always** in this phase. C recursion is replaced by an explicit bounded
  LIFO stack (`nodeCount+2` capacity); no recursive call or unbounded allocation.
- One chronological event stream: `SUBSECTOR` entry (derived sector, irrelevant
  fields `-1`) followed by one `SEG` event per canonical increasing
  `firstseg..firstseg+numsegs-1`, carrying absolute seg, owning leaf, derived
  sector, linedef, side and front/back sectors (`BackSector=-1` one-sided).
- The trace deep-copies every numeric event and never retains MapLevel/stack/WAD
  pointers; it survives `MapLevelReset`/`WADClose`. Builds are transactional: a
  null/unready/corrupt input, geometry overflow, stack/work/event budget
  exhaustion or OOM leaves a valid empty trace with diagnostics; camera/level are
  unchanged. Initial event storage is bounded by conventions `subCount+segCount`,
  with caps of 1,000,000 events and 4,000,000 stack push/pop work items.
- Non-cyclic shared-child DAG nodes are followed repeatedly under those budgets,
  matching original recursion's occurrences instead of silent deduplication;
  M2 still rejects cycles.
- **No `R_CheckBBox`/FOV/solidsegs occlusion**: `viewangletox`, `clipangle` and
  evolving `solidsegs` do not exist yet, so this trace is a chronological BSP walk
  rather than a visible-surface list and the counter reports zero occlusion skips.
  Absolute screen-space visibility must not be inferred from it. Wall projection,
  clipping, drawsegs and a faithful `R_CheckBBox` belong to later M3-04 work.
- `DoomPB.pb` includes the modules for compile coverage only; ordinary startup
  does not load a map, create a camera or start rendering traversal.

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
