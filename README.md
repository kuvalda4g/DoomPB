# DoomPB

DoomPB is an independent, native source port of the original Doom engine written
in **PureBasic**. The goal is to reproduce the behaviour of id Software's
**Linux Doom 1.10** — software renderer, fixed-point arithmetic, 35 Hz game
ticks and WAD compatibility — rather than to reimagine it.

> **Status: `0.1.0` — milestone M1 complete on Windows x64.**
> The executable validates a WAD, looks up and reads lumps, decodes `PLAYPAL`
> and Doom patches, composites them into an indexed software framebuffer and
> presents `TITLEPIC` in a native 960x600 window at 3x nearest-neighbour.
> The title screen was visually verified. Linux x64 runtime is **NOT RUN**.
> Gameplay, the world renderer and release tagging beyond the owner-controlled
> `v0.1.0` step are not implemented yet.

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

# Explicit compiler selection
PB_COMPILER=/opt/purebasic/compilers/pbcompiler ./scripts/build.sh
```

## Testing

The test scripts run a real syntax check, a real build, all four synthetic WAD
test suites (header/directory, lump lookup/payload, PLAYPAL/patch decoding and
framebuffer/presentation), and smoke tests against the produced executable.
They need no game data and no graphical display; no window is opened by the
automated suite.

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
DoomPB                                   Print the bootstrap status and exit.
```

`--dump-info` prints only container metadata (type, file size, lump count,
directory offset). `--lump-info` performs the same case-insensitive,
last-duplicate-wins name lookup as the WAD API and prints metadata only.
`--show-title` loads `PLAYPAL` and `TITLEPIC`, decodes them, composites into the
indexed framebuffer and opens a native window with a 960x600 client area
(320x200 at exact 3x nearest-neighbour). The window blocks until it is closed;
closing it exits with code 0. None of these options prints lump contents. A
missing or malformed WAD, a missing lump or a graphics failure is reported with
a non-zero exit code.

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
