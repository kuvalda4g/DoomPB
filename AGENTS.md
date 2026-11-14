# DoomPB — AI Agent Instructions

> Scope: repository-wide instructions for OpenCode, Kilo Code, and other coding agents.
> Project: a native source port of the original DOOM engine to **PureBasic 6.41**.
> License: **GPL-2.0-only**. Primary reference: **id Software Linux Doom 1.10**.
> These instructions describe expected behavior; they do not imply that the project, scripts, or tests already exist.

## 1. Mission and non-negotiable constraints

Build an independently compiled, playable port of **The Ultimate Doom** in PureBasic. Preserve the original engine's algorithms, software renderer, fixed-point semantics, game logic, and WAD compatibility. Prioritize correctness and reproducibility over modernization.

- Implement the engine in **native PureBasic** (`.pb` / `.pbi`). Do **not** substitute a C/C++ engine, DLL wrapper, embedded interpreter, SDL-based reimplementation, or another game engine.
- PureBasic's standard libraries and necessary operating-system APIs are allowed for input, windowing, sound, file I/O, and final framebuffer presentation; they must not replace Doom's game or renderer algorithms.
- First development target: **Windows x64**. Required for 1.0: **Linux x64**.
- Classic software framebuffer: **320 × 200**, **8-bit palette indices**. Platform presentation/scaling is separate from world rendering.
- Original gameplay tick rate: **35 tics/second**, independent from drawing frequency. Maintain deterministic game-state updates.
- First supported commercial game: **The Ultimate Doom 1.9ud**, with a legal, user-provided IWAD. Doom II, Boom, advanced rendering, and multiplayer are *post-1.0* scope unless the owner changes the plan.
- Keep the repository buildable and runnable after each accepted increment. Never represent a stub as a complete port.

**Roadmap and acceptance criteria:** `docs/DEVELOPMENT_PLAN.md`. Read its relevant milestone before starting implementation. If that file is missing, report it rather than inventing its contents. The roadmap is planning guidance, not evidence that milestones are completed.

## 2. Reference code and documentation

Primary upstream:

- https://github.com/id-Software/DOOM (`linuxdoom-1.10/`)
- Suggested local sibling directory: `../doom-original/` (not part of this repository).
- Record the exact upstream commit SHA in `docs/PORTING_NOTES.md` or another appropriate document when the clone is available. Never invent a SHA.

Secondary reference, for portability and behavior clarification only:

- https://github.com/chocolate-doom/chocolate-doom

Language documentation:

- https://www.purebasic.com/documentation/
- https://www.purebasic.com/documentation/reference/cli_compiler.html

For each ported function or coherent subsystem:

1. Inspect its original C implementation and directly related structures/constants/callers.
2. Identify pointer lifetime, signedness, integer width, overflow and rounding, order of side effects, and global state.
3. Implement equivalent PureBasic behavior; preserve computations and update ordering where compatibility depends on them.
4. Document any intentional difference from original Doom in `docs/PORTING_NOTES.md`; do not silently replace an algorithm with an approximate version.
5. Validate against compiler and tests before moving to an unrelated subsystem.

Do not bulk-translate the entire C tree in one pass. Never paste unreviewed translated code and call it complete.

## 3. Repository layout and ownership

Planned layout (create directories and files **only when needed**):

```text
DoomPB/
  AGENTS.md                     # This file; repository-wide agent rules
  LICENSE                       # Full GNU GPL v2 text
  README.md
  docs/
    DEVELOPMENT_PLAN.md         # Authoritative milestone plan
    ARCHITECTURE.md
    PORTING_NOTES.md
    TESTING.md
    COMPATIBILITY.md
  src/
    DoomPB.pb                   # Entry point
    Core/                       # Types, endian helpers, fixed math, RNG, memory
    WAD/                        # Directory, lookup, cache, IWAD identification
    Graphics/                   # PLAYPAL, patches, textures, framebuffer, video
    Map/                        # Level formats, loader, validation
    Renderer/                   # Geometry, BSP, walls, planes, sprites, draw
    Game/                       # Tics, player, physics, thinkers, AI, weapons
    UI/                         # HUD, menu, automap, intermission
    Audio/                      # SFX, music, MUS handling
    Platform/                   # Input, display, timing, configuration
  tests/
    unit/                       # Tests independent of commercial data
    fixtures/                   # Entirely original/synthetic data
    integration/                # Local tests with user's own IWAD
    golden/                     # Non-reconstructable checksums/statistics only
  scripts/                      # build.ps1, build.sh, test.ps1, test.sh
  local-data/                   # User-owned IWADs; never commit
  build/                        # Generated output; never commit
```

Module boundaries may evolve if documented and consistent with `docs/DEVELOPMENT_PLAN.md`. Avoid cyclical `XIncludeFile` chains, unclear inclusion order, gratuitous globals, and duplicate definitions. Keep platform-specific calls confined to `src/Platform/` and the presentation/audio adapters.

For original-to-port correspondence, use the table in **section 3.1** of the development plan. Do not invent original C file/function names: check the source.

## 4. PureBasic 6.41 coding requirements

- Begin new entry points and standalone test sources with `EnableExplicit`; prefer explicit declarations and descriptive identifiers.
- Use `.l` for **32-bit** game-format integers when appropriate, `.q` for **64-bit** intermediates and bounds calculations, and `.i` / properly typed pointers for native addresses. Do not treat pointer-sized `.i` as a replacement for fixed-width WAD fields.
- Check signed versus unsigned interpretations explicitly. Do not assume C integer promotion, overflow, shift, structure layout, or pointer arithmetic behaves identically in PureBasic.
- Preserve Doom fixed-point **16.16** arithmetic (`FRACBITS = 16`, `FRACUNIT = 65536`), including truncation, saturation, and edge behavior required by the original algorithm. Use targeted reference tests. Avoid switching gameplay calculations to floating point.
- Read binary formats field by field with explicit little-endian helpers. **Never** overlay an in-memory PureBasic structure onto untrusted WAD bytes and rely on native alignment/packing.
- Parse 8-byte lump names as byte fields; do not assume null termination. Preserve original ordering and last-match lookup semantics for duplicate names.
- Validate file offsets and lengths **before** seeking, allocating, adding, multiplying, or slicing. Use safe 64-bit boundary calculations. Treat WAD/PWAD content as untrusted.
- Support zero-length marker lumps and reject malformed/truncated inputs with diagnostics, never memory corruption.
- Define buffer ownership, allocation/free rules, cache lifetime, and error paths. Avoid unsafe pointer retention when buffers may be reallocated.
- Keep the underlying 8-bit framebuffer independent of screen scaling and graphics backends. Prefer nearest-neighbor presentation for the classic look.
- Preserve Doom's PRNG, thinker order, event processing, and 35 Hz simulation. Rendering must not mutate simulation state.
- Verify PureBasic API names, syntax, library initialization, and return values against **the installed 6.41 compiler and official documentation**. Do not invent functions by analogy with C, C#, or other BASIC dialects.
- Favor small, comprehensible units. Comments should explain compatibility constraints and non-obvious algorithms, not restate code.

If a supposed PureBasic feature is uncertain, make a **small disposable compile-only reproduction** outside production modules and check it with the real compiler.

## 5. Build commands and environment discovery

Do not hard-code the developer's local installation path into tracked source files. Prefer repository scripts once implemented, otherwise discover the compiler via `PB_COMPILER`, `PATH`, or the user's known installation. Do not assume scripts or tools exist before inspecting the repository.

**Windows / PowerShell** (examples, from repository root):

```powershell
# Set this to the actual location when not available on PATH.
$compiler = if ($env:PB_COMPILER) { $env:PB_COMPILER } else { "pbcompiler.exe" }
& $compiler --version
& $compiler "src/DoomPB.pb" --check
New-Item -ItemType Directory -Force "build" | Out-Null
& $compiler "src/DoomPB.pb" --output "build/DoomPB.exe"
```

**Linux / Bash** (examples, from repository root):

```bash
PB_COMPILER="${PB_COMPILER:-pbcompiler}"
"$PB_COMPILER" --version
"$PB_COMPILER" src/DoomPB.pb --check
mkdir -p build
"$PB_COMPILER" src/DoomPB.pb --output build/DoomPB
```

`--check` is a **syntax check**, not an executable or functional test. A successful syntax check does not prove a working build. Compiler flags are documented at the PureBasic CLI reference above. Preserve non-zero exit status; never mask compiler failures with `|| true` or equivalent.

When `scripts/build.ps1`, `scripts/build.sh`, `scripts/test.ps1`, and `scripts/test.sh` exist and are verified, prefer them over ad hoc commands. Do not claim Windows and Linux have both passed unless both were actually tested on suitable hosts.

When compiler/runtime is unavailable: record the exact command attempted and limitation, perform safe static review, and report the work as **unverified**, not complete.

## 6. Verification and acceptance gates

For each implementation task, use this sequence:

1. **Inspect**: `git status`, relevant code, current milestone and upstream reference.
2. **Plan**: state intended files, C symbols/dependencies, invariants, and measurable acceptance criteria.
3. **Implement**: make the smallest cohesive patch; avoid unrelated refactors.
4. **Syntax check**: run PureBasic `--check` for the entry point that includes the touched modules.
5. **Build**: compile the applicable executable/test harness; capture compiler errors and fix them.
6. **Test**: run unit/fixture tests and the smallest relevant smoke/integration test.
7. **Inspect diff**: `git diff --check`, `git diff --stat`, `git diff`, `git status --short`.
8. **Report**: summarize changes, checks performed, unresolved risks, and next task.

**Do not mark a task/milestone complete solely because code was generated.** A milestone is accepted only when the Definition of Done in `docs/DEVELOPMENT_PLAN.md` is satisfied. Do not claim tests were run if they were only planned or simulated.

Test at least these categories as relevant:

- **WAD**: empty/malformed header; unexpected `IWAD`/`PWAD` signature; truncated/overflowing directory; invalid lump ranges; duplicated names; zero-size markers.
- **Graphics**: palette indexing; Doom patch column/post decoding, transparency, terminators, clipped drawing, malformed offsets.
- **Math**: fixed multiplication/division, integer limits, angle/table lookups, C reference values.
- **Map/renderer**: bad indices and nodes, BSP traversal, deterministic frame checks, masked textures, visplanes.
- **Game**: deterministic `ticcmd` sequences, RNG state, thinker ordering, collision, episode transitions, eventually demos/saves.
- **Cross-platform**: Windows and Linux compilation and targeted runtime checks before 1.0.

Maintain unit fixtures with independently created/synthetic resources. Integration tests may read the owner's local `DOOM.WAD` but must not copy its content into source, logs, test snapshots, commits, or published reports. Golden tests may store checksums and concise numerical measurements rather than copyrighted pixels, samples, or WAD sections.

## 7. Legal and data-handling guardrails

- Code license: **GPL-2.0-only**. Keep the full GPL v2 license and preserve appropriate upstream authorship/copyright notices when porting original code.
- Do not add a dependency, snippet, or another project's implementation with incompatible or unknown license without review.
- **Never commit, upload, embed, publish, or paste commercial IWAD/PWAD files or extracted copyrighted game graphics, sounds, music, and other assets.** These assets are not covered by the open-source engine license.
- Known local *identification fixture* (not distributable):
  - Game: The Ultimate Doom 1.9ud
  - Filename: typically `DOOM.WAD`
  - MD5: `c4fe9fd920207691a9f493668e0a2083`
  - Expected size: `12408292` bytes
  - Expected directory count: `2306` lumps
- The hash identifies one known IWAD revision; **do not reject all other legitimate IWADs simply because their hash differs**.
- Keep actual IWADs in ignored local directories such as `local-data/` (or pass an explicit path at runtime). Confirm `.gitignore` protects `*.wad`, `*.WAD`, `local-data/`, and generated output. Before staging any binary file, establish its origin and license.
- Do not add original C source trees, third-party source ports, or any external assets wholesale to this repository without an explicit, license-aware decision.
- Do not send local game data, private paths, credentials, or environment files to external APIs or logs unnecessarily.

## 8. Git and file-change safety

- Inspect the current branch and working tree before editing; **preserve pre-existing user changes** and resolve overlap rather than overwriting them.
- Only edit task-relevant files. Do not generate dozens of empty placeholders for future milestones.
- No sweeping formatting passes, dependency upgrades, renaming, history rewriting, mass deletes, or unrelated "cleanup".
- No `git reset --hard`, `git clean -fd`, force push, bulk deletes, or destructive commands without explicit owner approval.
- Never create/publish a GitHub repository, push changes, publish releases, change access rights, or change license terms without explicit owner authorization.
- Make a local commit **only if the current task authorizes commits**, and only after verified changes. Favor small, descriptive commits such as `feat(wad): parse directory entries` or `test(wad): reject truncated directories`.
- Don't auto-stage everything (`git add .`) when local data or unexplained generated files exist. Inspect the staged diff before committing.
- If repository state is unexpected or another agent changed files concurrently, stop conflicting edits and report what is different.

## 9. Milestones and scope discipline

| Milestone | Version | Acceptance headline |
|---|---|---|
| M0 | `v0.0.x` | Repository, license, toolchain, reproducible minimal build |
| M1 | `v0.1.0` | WAD directory/lookup, `PLAYPAL`, decode and display `TITLEPIC` |
| M2 | `v0.2.0` | Decode resources, textures, and load validated maps |
| M3 | `v0.3.0` | Fixed-point geometry, BSP, visible textured walls |
| M4 | `v0.4.0` | Full classic software rendering with flats, sky and sprites |
| M5 | `v0.5.0` | 35 Hz gameplay loop, input, player movement and collision |
| M6 | `v0.6.0` | Enemies, items, weapons, sector mechanics and exits |
| M7 | `v0.7.0` | HUD, UI, SFX and music |
| M8 | `v0.8.0` | Saves, demos, configuration, compatibility work |
| M9 | `v0.9.0` | Regression testing and Windows/Linux stability |
| M10 | `v1.0.0` | Playable, documented Ultimate Doom release |

This table is only a quick index. The **full criteria are in the development plan**. Do not skip acceptance gates or pull post-1.0 features into early milestones without approval.

### Immediate first milestone (M0 → M1)

If the repository has not been initialized, start with M0 rather than assuming a working engine:

1. Verify repo state, original source availability, and installed compiler version.
2. Establish `LICENSE`, `README.md`, `.gitignore`, `src/DoomPB.pb`, and reproducible build scripts (only what is missing).
3. Build a minimal executable successfully and record evidence.
4. Implement endian-safe WAD header and directory parsing, then name lookup and data access.
5. Test with synthetic malformed WADs first, then the owner's local IWAD.
6. Decode `PLAYPAL` and Doom patch imagery, display `TITLEPIC` using PureBasic.
7. Accept `v0.1.0` only after it displays the correct title screen and invalid files fail safely.

Do not skip straight to the 3D renderer.

## 10. Working with OpenCode / Kilo Code

- Treat OpenCode Desktop as the primary implementation agent. Kilo Code is an alternative editor/reviewer, not a concurrent writer to the same files.
- Use a **Plan → Implement → Compile → Test → Review** cycle for one narrow task at a time.
- Load related documentation *on demand*; don't flood model context with every reference source.
- Be explicit about uncertainties, missing compiler/toolchain, partially finished modules, and differences from Linux Doom.
- Prefer a small reproducible compiler/test case to lengthy speculation when PureBasic syntax is unclear.
- Avoid claiming that broad model context or high API quotas replace verification.

### Final report template after each coding task

Use concise, verifiable headings:

```text
Task / milestone:
Original C symbols consulted:
Files changed:
Behavior implemented:
Syntax check: PASS / FAIL / NOT RUN (command and reason)
Build: PASS / FAIL / NOT RUN (command and reason)
Tests: PASS / FAIL / NOT RUN (name + observed results)
Git status / diff reviewed:
Differences from original Doom / known risks:
Suggested next task:
```

**Success means observed results from real tools, not an agent's confidence.**
