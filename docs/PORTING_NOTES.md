# Porting notes

This document records **verified facts** about the DoomPB port. It must not
contain guesses, invented upstream commit hashes or copied game data.

## Milestone status

| Milestone | State | Notes |
|---|---|---|
| M0 — repository and reproducible build | in progress | CLI skeleton, build/test scripts, license and documentation |
| M1 — WAD loader and `TITLEPIC` | not started | — |

No original engine algorithm has been ported yet. `src/DoomPB.pb` is original
code written for DoomPB; it does not derive from id Software sources.

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
  `--help`). Original Doom used positional arguments (`-iwad`, `-file`, …) plus
  a response-file mechanism; those are planned for later milestones and are not
  implemented.
- **Console bootstrap.** The M0 executable is a console program that prints
  status text. Original Doom is a fullscreen game application. This is a
  scaffold only and will be replaced by the game entry point.
- No WAD parsing, no `PLAYPAL`, no `TITLEPIC`, no renderer and no game loop
  exist yet. Do not treat this build as a playable port.

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
