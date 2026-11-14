# DoomPB

DoomPB is an independent, native source port of the original Doom engine written
in **PureBasic**. The goal is to reproduce the behaviour of id Software's
**Linux Doom 1.10** — software renderer, fixed-point arithmetic, 35 Hz game
ticks and WAD compatibility — rather than to reimagine it.

> **Status: `0.0.1` (milestone M0 — bootstrap only).**
> This build contains no WAD loader, renderer or gameplay. It only provides the
> repository skeleton, the CLI entry point and a reproducible build/test setup.

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

# Explicit compiler selection
./scripts/build.ps1 -CompilerPath 'C:\Program Files\PureBasic\Compilers\pbcompiler.exe'
```

### Linux (Bash)

```bash
# Syntax check only
./scripts/build.sh --check

# Full build -> build/DoomPB
./scripts/build.sh

# Explicit compiler selection
PB_COMPILER=/opt/purebasic/compilers/pbcompiler ./scripts/build.sh
```

## Testing

The test scripts run a real syntax check, a real build and smoke tests against
the produced executable. They need no game data and no graphical display.

```powershell
./scripts/test.ps1     # Windows
```

```bash
./scripts/test.sh      # Linux
```

A test run fails with a non-zero exit code if any check fails.

## Command line

```text
DoomPB --version     Print the version and exit.
DoomPB --help        Print usage information and exit.
DoomPB               Print the bootstrap status and exit.
```

| Exit code | Meaning |
|---|---|
| `0` | Success |
| `2` | Usage error (unknown option or too many arguments) |

Planned options such as `--iwad`, `--file`, `--list-lumps` and `--dump-info` are
**not implemented yet**; they arrive with the WAD loader in milestone M1.

## Repository layout

```text
src/        PureBasic sources (DoomPB.pb is the entry point)
scripts/    build/test scripts for Windows (PowerShell) and Linux (Bash)
docs/       development plan, porting notes and task descriptions
build/      generated executables (ignored by Git)
local-data/ game data you own, e.g. DOOM.WAD (ignored by Git)
```

## License

DoomPB is licensed under the **GNU General Public License version 2 only**
(`GPL-2.0-only`). See [LICENSE](LICENSE). Ported engine code will retain the
original id Software copyright and license notices.
