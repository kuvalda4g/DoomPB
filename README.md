# DoomPB

DoomPB is an independent, native source port of the original Doom engine written
in **PureBasic**. The goal is to reproduce the behaviour of id Software's
**Linux Doom 1.10** — software renderer, fixed-point arithmetic, 35 Hz game
ticks and WAD compatibility — rather than to reimagine it.

> **Status: `0.0.1` — M0, M1-01 and M1-02 complete; M1-03 in progress.**
> The executable can validate a WAD, look up lumps, read raw payloads, decode
> `PLAYPAL` palettes and decode Doom picture/patch lumps into indexed pixels
> plus a transparency mask. Presenting `TITLEPIC` in a window (M1-04), the
> renderer and gameplay are not implemented yet.

## Legal notice

DoomPB is not affiliated with or endorsed by id Software or ZeniMax Media.
No Doom game data is included or distributed with this project. Playing the
game will require a **legally obtained** copy of *The Ultimate Doom* (`DOOM.WAD`,
version 1.9ud) or another compatible IWAD that you own. Commercial WAD files
must never be committed to this repository.

## Requirements

- **PureBasic 6.41** (full edition) with its command line compiler
  (`pbcompiler`).
- **Windows x64** is the primary development target. **Linux x64** is a required
  target for 1.0; the Bash scripts currently run only where a Linux PureBasic
  installation is available.
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

# Explicit compiler selection
PB_COMPILER=/opt/purebasic/compilers/pbcompiler ./scripts/build.sh
```

## Testing

The test scripts run a real syntax check, a real build, all three synthetic WAD
test suites (header/directory, lump lookup/payload and PLAYPAL/patch decoding),
and smoke tests against the produced executable. They need no game data and no
graphical display.

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
DoomPB                                   Print the bootstrap status and exit.
```

`--dump-info` prints only container metadata (type, file size, lump count,
directory offset). `--lump-info` performs the same case-insensitive,
last-duplicate-wins name lookup as the WAD API and prints metadata only. Neither
option prints lump contents. A missing or malformed WAD, or a missing lump, is
reported with a non-zero exit code.

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

`PLAYPAL` and patch decoding are implemented in `src/Graphics/`; presenting
`TITLEPIC` in a window belongs to M1-04 and is **not implemented yet**.

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

## Repository layout

```text
src/        PureBasic sources (DoomPB.pb is the entry point)
src/Core/   shared primitives (little-endian decoding, later fixed-point math)
src/WAD/    WAD container reader, name lookup and payload reads
src/Graphics/ PLAYPAL palette decoding and Doom patch decoding
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
