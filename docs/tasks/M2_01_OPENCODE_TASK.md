# DoomPB — M2-01: COLORMAP and PNAMES resource tables

> - **Task ID:** `M2-01`
> - **Milestone:** M2 — Resource & Map Loading (planned `v0.2.0`, **not yet complete**)
> - **Status:** implementation assignment, not a completion report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Reasoning:** High; increase only to resolve a concrete problem
> - **Language/compiler:** PureBasic 6.41, full edition
> - **Primary verification:** Windows x64; Linux x64 must be reported `NOT RUN` if unavailable
> - **License:** GPL-2.0-only
> - **Reference:** `../doom-original` at commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Read first:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md` (M2 and compatibility rules), `docs/PORTING_NOTES.md`, the current source/tests/build scripts, and this task

## 1. Goal and milestone boundary

Continue from the **committed M1 implementation**, which already parses WADs, looks up and reads lumps, decodes `PLAYPAL` and Doom patches, and displays `TITLEPIC` in a PureBasic window. Implement two foundational resource parsers required by the upcoming wall texture renderer:

1. **`COLORMAP`**: safely read and represent tables that map an 8-bit palette index to a different 8-bit palette index for lighting/effects.
2. **`PNAMES`**: safely read and represent the ordered list of eight-byte wall-patch names referenced later by `TEXTURE1` / `TEXTURE2`.

The new decoders must be reusable, independent of the window backend, and callable with **synthetic input bytes** without opening a commercial WAD. Validate with the user's local Ultimate Doom IWAD as an **optional read-only integration check**.

**This is M2-01 only.** Do not parse texture definitions, assemble composite textures, implement flats/sprite tables, load maps, write a renderer, add GPU graphics, or begin M2-02. Do not release `v0.2.0` or change the application's `0.1.0` version for this task.

### Scope exclusions

- No `TEXTURE1`, `TEXTURE2`, `PNAMES` patch placement, composite image generation, or image export.
- No lighting formula, selection of a light map from sector intensity, distance attenuation, or `COLORMAP` application to the live Doom title window.
- No zone allocator, WAD overlays, multi-file API redesign or persistent lump caching.
- No code copied from incompatible libraries and no platform-specific video code.
- No checked-in game assets or output images reconstructed from the commercial IWAD.

## 2. Inspect actual repository and upstream first

Before editing:

1. Run `git status --short --branch`, `git log -1 --oneline`, `git diff --stat`, `git diff --cached --stat`, and inspect staged/untracked items. Preserve the owner's work. Do **not** assume M1-04's new commit SHA or that a `v0.1.0` tag was created; verify and **report** the tag status without creating/changing it.
2. Examine the **actual** declarations, conventions and ownership in `src/WAD/WAD.pbi`, `src/Graphics/Palette.pbi`, `src/Graphics/Patch.pbi`, `src/Graphics/FrameBuffer.pbi`, `src/DoomPB.pb` and the current PureBasic test files. Inspect `scripts/build.ps1`, `build.sh`, `test.ps1`, `test.sh`; do not replace working scripts with templates.
3. Verify `git -C ../doom-original rev-parse HEAD` equals the pinned SHA. Inspect `linuxdoom-1.10/r_data.c`, especially `R_InitColormaps`, `R_InitTextures` and how it reads `PNAMES` / resolves patch references through `W_CheckNumForName`; consult `w_wad.c` only where needed.
4. Check PureBasic 6.41 compiler/documentation for unfamiliar pointer operations, memory management and endian access. Confirm any new API syntax through actual compilation.
5. **Present a short implementation plan before editing**: exact files, proposed type/API names, byte layout, ownership/reset rules, size/count safety limits and tests.

**Known earlier baseline (from user reports, not a substitute for inspecting code):** `WADFindLump(Name.s)` returns last matching index; `WADLumpSize(Index)` returns payload length; `WADReadLump(Index, *Destination, Capacity.q)` reads to caller-owned memory; M1 had 17+21+34+24 = **96 unit scenarios**, **694 assertions**, and **36 script checks**. Report actual observed results after changes rather than blindly repeating these numbers.

## 3. Binary format: COLORMAP

The resource contains consecutive **256-byte tables**. Each entry is a **palette index** (`0..255`), not RGB data. Applying colormap `m` to index `p` gives:

```text
mapped_index = table[m * 256 + p]
color = PLAYPAL[0][mapped_index].RGB  ; concept only, not display work here
```

Standard Ultimate Doom uses **34 tables × 256 bytes = 8,704 bytes**:

- Maps `0..31`: normal lighting lookup levels.
- Map `32`: invulnerability-style grayscale mapping.
- Map `33`: extra dark/black table.

These indices are **semantic notes**; store the actual bytes without altering or synthesizing any entries. Do not assume every map is the identity or that all table entries can be calculated from `PLAYPAL`.

### Implementation contract

Suggested module: `src/Graphics/Colormap.pbi` (or existing architecture-consistent equivalent).

Suggested API, adaptable to verified PureBasic conventions:

```text
ColormapDecode(*Bytes, Length.q, *Result) -> boolean
ColormapCount(*Result) -> integer
ColormapLookup(*Result, MapIndex, PaletteIndex) -> 0..255 on success, -1 on failure
ColormapReset(*Result)
ColormapLastError(...) -> text
```

Use a caller-owned zero-initialized result structure with a clearly owned, copied memory region or fixed-size internal representation. If following the `PaletteSet`/`PatchImage` pattern, document its `Magic` state, reset behavior, and limitations of copying the structure by value. The result **must not borrow pointers** to a temporary WAD read buffer.

Requirements:

- Input length must be positive, exactly divisible by 256 and within a documented, reasonable safety cap (for example 256 tables); **do not hardcode exactly 34 in the generic decoder**.
- The known Ultimate Doom integration **must** decode 34 maps; check actual size and count.
- Validate null input, negative/zero length, partial table and excessive count before copying or allocation.
- Bounds-check both table and color indices; preserve bytes `0`, `128`, `255` exactly.
- Repeated decode, reset, decode-after-failure and malformed input must not leak or leave stale usable state. Specify whether a failed replacement clears or preserves prior state, and test that exact policy.
- No float math, gamma correction, RGB/BGR conversion, `PLAYPAL` modification or screen output in this module.

## 4. Binary format: PNAMES

`PNAMES` starts with a **little-endian signed 32-bit count** followed by exactly `count` consecutive eight-byte names; these names index **wall patches**, not actual decoded images.

```text
Offset       Bytes     Meaning
0            4         int32 little-endian patch count N
4            8         name[0] (raw 8 bytes)
12           8         name[1] (raw 8 bytes)
...
4+8*(N-1)    8         name[N-1]
```

A shorter name is usually NUL-padded; an eight-byte name **need not terminate with NUL**. Names are opaque **8-byte identifiers**, not Unicode/UTF-8 strings. Preserve original bytes and original order; duplicate names are legal and **must not be deduplicated or sorted**.

### Implementation contract

Suggested module: `src/Graphics/PNames.pbi` (or a similarly named resource-table module consistent with the codebase).

Suggested API, adaptable after inspecting existing declarations:

```text
PNamesDecode(*Bytes, Length.q, *Result) -> boolean
PNamesCount(*Result) -> integer
PNamesRawNameByte(*Result, NameIndex, ByteOffset) -> 0..255 or -1
PNamesDisplayName(*Result, NameIndex) -> safe diagnostic string
PNamesReset(*Result)
PNamesLastError(...) -> text
```

An optional `PNamesResolve...` operation may be added **only if small and justified**. It must use the existing `WADFindLump` behavior, preserve PNAMES table positions and report unresolved names without inventing patch content. Prefer **deferring bulk resolution to M2-02** if it would introduce cross-module coupling. No need to eagerly `PatchDecode()` every name.

Requirements:

- Validate input length `>= 4` and read N explicitly via the existing endian helpers; reject **negative** counts.
- For safety, enforce a documented sane maximum count (e.g. 65,536) and test the boundary. Calculate `4 + 8 * N` using 64-bit arithmetic **before** allocation/indexing.
- Require that the declared name array **fits** the supplied byte length. If trailing bytes exist, follow a documented permissive policy for compatibility (accept and ignore trailing bytes without treating them as names), and test it. Do not silently accept truncated entries.
- Allow `N = 0` as a safe, valid empty table; test empty count + exactly four bytes.
- Preserve raw 8 bytes including embedded NUL, lowercase bytes, `0x80` and `0xFF`; **do not mutate to uppercase**. Display formatting must escape or sanitize nonprintable data; never read beyond byte 7.
- For lookup integration, reuse existing vanilla-compatible `WADFindLump` name semantics; do not add Unicode locale folding or conflate the PNAMES index with a WAD directory index.
- Caller's decoded object owns its own memory. Reset frees it, prevents stale reads and remains safe when repeated. Decoder must not depend on input remaining allocated.

### Why PNAMES order matters

In Doom's `R_InitTextures`, each texture patch descriptor references a **numeric PNAMES index**. The later `TEXTURE1/TEXTURE2` decoder will use that number to select a raw name and then find the corresponding WAD lump. Reordering, trimming, normalizing, or deduplicating PNAMES would corrupt those references even if the directory lookup still works.

## 5. Resource loading / integration (narrow)

The two decoders accept caller-provided memory and **must not** internally reopen WADs. For integration tests, add a small helper/test harness that:

1. Opens the user's local WAD using existing `WADOpen` and finds `COLORMAP` and `PNAMES` with `WADFindLump`.
2. Checks `WADLumpSize`, allocates exactly sufficient buffers using verified PureBasic APIs, reads with `WADReadLump`, decodes and frees the raw payload buffer.
3. Exercises public getters, then resets/free decoded objects and closes the WAD. Inspect both success and failure cleanup paths.
4. Prints **metadata, selected numerical results and optionally non-reconstructable hashes only**. Do not dump raw colormap tables, lists of patch names, screenshots or assets into tracked files.

If the project already has a safe reusable read-to-buffer helper, use it; otherwise keep this temporary loader local to tests rather than creating a cache/manager. **One WAD at a time** is still the current contract; do not rework it here.

### Optional user IWAD smoke test

Use `data/DOOM.WAD` only if it already exists and is legally owned. Expected known file identity:

```text
Type:              IWAD
Size:              12408292 bytes
Lumps:             2306
Directory offset:  12371396
MD5:               c4fe9fd920207691a9f493668e0a2083
```

Required checks if available:

- `COLORMAP` lookup/read succeeds; length **8704 bytes**, 34 maps, and sample indices can be read without range errors.
- `PNAMES` lookup/read succeeds; derive the **actual** count and byte length from the file, validate `4 + count*8 <= size`, verify names are individually retrievable by index. **Do not invent a fixed count** in the report.
- `PLAYPAL` and `TITLEPIC` functionality remains intact; `--show-title` must still show the already verified correct window. Do not change the title palette or graphics path.
- Record measured metadata and optional FNV hashes; do not modify `DOOM.WAD`.

If the local WAD is missing, report this integration **NOT RUN** and still pass deterministic synthetic tests. Avoid network downloads of copyrighted assets.

## 6. Automated tests — at least 28 cases

Add a focused self-contained PureBasic test source, for example `tests/unit/wad_resource_tests.pb`, compiled by the existing scripts with a discoverable test mode (e.g. `-ResourceTest` / `--resource-test`), without breaking M0/M1 test selection. Reuse existing test harness conventions, synthetic input utilities, and exit-code behavior. These cases are minimum categories; add assertions per case as useful.

### COLORMAP tests (C01–C13)

| ID | Input/scenario | Expected behavior |
|---|---|---|
| C01 | Valid synthetic 1-table map | Count 1, byte-exact mapping |
| C02 | Multiple tables with deliberately different values | Correct table selection and row stride 256 |
| C03 | Table boundary colors 0, 255 and a high-bit value 128 | Exact unsigned 0..255 indices |
| C04 | Null data pointer with positive length | Controlled failure |
| C05 | Zero and negative length | Controlled failure, no allocation |
| C06 | Length 255, 257, 511 | Reject incomplete tables |
| C07 | Valid 34-table synthetic input | 34 tables decoded, correct last table/entry |
| C08 | Safety cap and oversize length | Safe rejection, no overflow/huge allocation |
| C09 | Invalid map index: negative, count, large | Error/sentinel, no access outside array |
| C10 | Invalid color index: negative, 256, large | Error/sentinel, no access outside array |
| C11 | Input changed/freed after decode | Decoded data remains independent |
| C12 | Decode twice + repeated Reset | No stale state, no double-free or leak |
| C13 | Valid decode then malformed replacement then valid decode | Deterministic documented failure-state policy |

### PNAMES tests (N01–N15)

| ID | Input/scenario | Expected behavior |
|---|---|---|
| N01 | N=0 with 4-byte payload | Valid empty table |
| N02 | N=1, NUL-padded short name | All 8 raw bytes preserved |
| N03 | Exactly 8 non-NUL name bytes | No overread, correct byte getter |
| N04 | Two or more ordered names | Index -> exact original entry |
| N05 | Duplicate names | Duplicate positions preserved, no deduplication |
| N06 | Embedded NUL bytes in name | Raw representation preserved; safe display |
| N07 | Lowercase bytes in stored name | Raw bytes not uppercased |
| N08 | High bytes 0x80 / 0xFF | Byte-safe getters; diagnostic escaping |
| N09 | Buffer smaller than 4-byte count | Safe rejection |
| N10 | Negative count (-1) | Safe rejection |
| N11 | Count > safety cap / huge signed count | Reject before allocation/multiplication |
| N12 | Count requires more bytes than present | Reject truncated table |
| N13 | Trailing bytes beyond declared entries | Documented policy: accept and ignore |
| N14 | Invalid name index and byte-offset (0..7 bounds) | Safe sentinel/error, no memory corruption |
| N15 | Reuse/Reset, bad-after-good and good-after-bad | Deterministic ownership/lifetime |

### Additional integration checks (I01–I04)

These are **separate integration checks**, not counted toward the 28 required synthetic tests:

| ID | Scenario | Expected behavior |
|---|---|---|
| I01 | Synthetic WAD containing COLORMAP + PNAMES | Existing lookup/read + decoders cooperate |
| I02 | Duplicate COLORMAP or PNAMES lumps in synthetic WAD | Last directory entry wins, no decoder reordering |
| I03 | Missing or zero-length required lump | Clean failure; no crash, no side effects |
| I04 | Optional genuine Ultimate Doom (read-only) | 34 maps, valid PNAMES count, no payload output |

All fixtures must be invented for tests, not copied/extracted from Ultimate Doom. Use ignored temporary directories for generated `.wad` files, clean them after tests and check canary bytes around small buffers where pointer operations are used. Test with debug mode when available; never equate a compiler syntax check with an executed test.

## 7. Regression and verification requirements

### Build/tests

- Run full `scripts/build.ps1 -Check` and the existing per-test `-Check` modes for prior M1 unit sources.
- Add and syntax-check/compile the new resource test target; run it and verify a **nonzero exit on assertion failure**.
- Build the real application; execute the complete `scripts/test.ps1` suite, including the new tests.
- Revalidate CLI options `--version` (`DoomPB 0.1.0`), `--help`, `--dump-info`, `--lump-info`, `--show-title` (as feasible), and error codes.
- Preserve all **96 earlier M1 unit scenarios / 694 assertions** as reported; report actual measured totals if changed.
- Run `bash -n scripts/build.sh scripts/test.sh` when Git Bash is available. Do not claim Linux runtime pass without Linux x64 PureBasic and real test execution.

### Git and file hygiene

- Review `git status --short --branch`, `git diff --check`, `git diff --stat`, relevant diffs, and any staged diff if present.
- New/untracked files do not appear in an ordinary `git diff --check`: **explicitly scan their line endings and trailing whitespace**.
- No trailing spaces/tabs in modified `.md`, `.pb`, `.pbi`, `.ps1`, `.sh`; keep Markdown tables/lists clean, no double-space hard breaks.
- Ensure `data/`, `local-data/`, `build/`, original game assets, temporary captures, secrets and binaries never enter Git.
- Do not add absolute private filesystem paths to tracked files; obtain compiler and WAD paths from existing scripts/configuration.
- **No** `git add`, `git commit`, `git push`, tags, releases or starting M2-02 unless the owner explicitly authorizes them. Do not modify pre-existing staged content.

### Documentation

Update `README.md` and `docs/PORTING_NOTES.md` only where necessary to explain new decoder APIs, ownership, formats, original C correspondence and intentional deviations. Keep the version `0.1.0`; M2 is *in progress*. Do not falsely claim Windows and Linux both passed. Avoid editing `AGENTS.md` or the development roadmap unless an actual contradiction requires owner approval.

## 8. Definition of Done

- [ ] Actual M1 code, full Git state, and pinned original `r_data.c` inspected before editing.
- [ ] `COLORMAP` tables decoded and indexed safely, with a clear ownership/reset policy and no byte transformations.
- [ ] `PNAMES` count and 8-byte entries decoded safely, in original order, preserving raw names including NUL/high bytes.
- [ ] Bounds, negative values, malformed inputs, repeated decode/reset and ownership are covered by tests.
- [ ] All **28 synthetic cases (C01–C13, N01–N15)** pass using PureBasic 6.41; integration checks are reported separately.
- [ ] Previous M1 tests and executable build pass with actual observed results.
- [ ] User's `DOOM.WAD` integration is PASS or explicitly NOT RUN; no commercial asset content is committed.
- [ ] `--show-title` is not broken, and the application remains version `0.1.0`.
- [ ] Full diff review completed; new files have no trailing whitespace and no unrelated changes.
- [ ] All changes remain uncommitted/unstaged; next task M2-02 is **not** started.

**M2-01 is complete only after actual compilation and executed tests. M2 / `v0.2.0` remains incomplete until the later resource and map-loading tasks are accepted.**

## 9. Mandatory completion report

```text
Task / milestone: M2-01 — COLORMAP and PNAMES resource tables
OS / compiler: <actual>; Linux: PASS / FAIL / NOT RUN
Baseline HEAD / worktree and v0.1.0 tag status: <actual>
Original Doom source consulted: <file/symbols, pinned SHA>
Files created/modified: <paths>
COLORMAP API / byte representation / ownership: <actual>
PNAMES API / raw names / count / ownership: <actual>
Validation and deviations from original C: <details>
Syntax check: PASS / FAIL / NOT RUN — <command, exit code>
Build: PASS / FAIL / NOT RUN — <command, exit code>
Previous M0/M1 regression: <actual counts>
New C01–C13 synthetic tests: <cases, assertions>
New N01–N15 synthetic tests: <cases, assertions>
Synthetic integration I01–I03: <actual results>
Optional Ultimate Doom I04: PASS / FAIL / NOT RUN — <numeric metadata only>
TITLEPIC regression: <actual status>
Bash syntax / Linux runtime: <actual>
Git diff / whitespace / commercial data audit: <results>
Known limitations and deferred work: <list>
Suggested next task: M2-02 — TEXTURE1/TEXTURE2 definitions (DO NOT START)
```

## 10. Reference links

- Original Linux Doom 1.10 — `r_data.c`: https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_data.c
- Original Doom WAD access — `w_wad.c`: https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/w_wad.c
- COLORMAP format and meaning: https://doom.fandom.com/wiki/COLORMAP
- PNAMES format: https://doom.fandom.com/wiki/PNAMES
- WAD technical reference: https://reverseengineering.wiki/index.php/Format%3AWAD_%28Doom_engine%29
- PureBasic memory APIs: https://www.purebasic.com/documentation/memory/index.html

> This document is a task specification, not evidence that M2-01 code or tests already exist.
