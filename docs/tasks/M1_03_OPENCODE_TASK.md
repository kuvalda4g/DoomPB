# DoomPB — M1-03: PLAYPAL and Doom Patch decoder

> - **Task ID:** `M1-03`
> - **Milestone:** M1 — WAD Loader + TITLEPIC (`v0.1.0` remains incomplete)
> - **Status:** implementation assignment, not an implementation report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Recommended reasoning:** High; increase only for a specific unresolved issue
> - **Language / compiler:** PureBasic 6.41, full edition
> - **Primary platform:** Windows x64; Linux x64 remains a separate unverified target
> - **License:** GPL-2.0-only
> - **Pinned Doom reference:** `../doom-original`, commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Required reading:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, this task and the **actual** M1-01/M1-02 source and tests

## 1. Goal

Continue from the **committed M1-02 implementation**, using its existing WAD lookup/read APIs. Implement and test two independent decoders:

1. `PLAYPAL`: turn raw RGB triples into a validated palette representation, with indexed access to all palettes and colors.
2. **Doom picture/patch**: turn the column/post compressed picture format into an **8-bit row-major palette-index image plus a separate transparency mask**, preserving its signed origin offsets.

Use the existing single-WAD parser to load `PLAYPAL` and `TITLEPIC` from the user's legally owned Ultimate Doom installation **only in an optional read-only integration test**. The observable end result is validated metadata and deterministic checksums of the decoded `TITLEPIC` image, not a visible game window.

**M1-04**, not this task, presents the image in a PureBasic window. Do **not** claim `v0.1.0` or change the application's reported version just because M1-03 passes.

### Explicit non-goals

- No image window, video backend, screen scaling, framebuffer presentation or screenshots.
- No whole-Doom renderer, flats, COLORMAP, composite wall textures, PNAMES, map loader or gameplay.
- No PNG/BMP writer, extracting copyrighted resources into the repository, or asset generation from the commercial IWAD.
- No WAD cache/zone allocator, PWAD overlays, multi-WAD merging, or rewriting working WAD APIs.
- No speculative support for Boom/DeePsea **tall patch** relative topdelta semantics unless a later task authorizes it. Implement and document **vanilla Doom** behavior first.

## 2. Inspect the project and C reference **before editing**

1. Run `git status --short --branch`, `git log -1 --oneline`, `git diff --stat`, `git diff --cached --stat`. Do not assume a clean index or infer the committed M1-02 SHA from an earlier report. Preserve unrelated work.
2. Read the exact declarations and callers of `src/WAD/WAD.pbi`, `src/Core/Endian.pbi`, `src/DoomPB.pb`, `tests/unit/wad_header_tests.pb`, `tests/unit/wad_lump_tests.pb`, and `scripts/{build,test}.{ps1,sh}`. Reuse `WADFindLump(Name.s)`, `WADLumpSize(Index)`, `WADReadLump(Index, *Destination, Capacity.q)` **as actually declared**, not from memory.
3. Check `git -C ../doom-original rev-parse HEAD` against the pinned SHA. Inspect `linuxdoom-1.10/doomdata.h` or the actual definition of `patch_t`/`column_t`; inspect `v_video.c` (`V_DrawPatch`, `V_DrawPatchFlipped`), `d_main.c` (`D_PageDrawer`), and `r_data.c` where helpful.
4. Verify correct PureBasic 6.41 syntax for pointer arithmetic, binary reads, memory allocation, structures, and arrays using the installed compiler and official documentation. Do not invent PB functions based on C names.
5. **Before implementation**, present a brief plan: exact files, palette representation, decoded image representation, ownership/freeing rules, malformed input behavior, and proposed tests.

## 3. Existing M1-02 baseline: preserve it

The accepted M1-02 report describes these interfaces and behaviors (check source for exact signatures):

```text
WADFindLump(Name.s) -> index.i or -1
WADReadLump(Index.i, *Destination, Capacity.q) -> boolean
WADLumpSize(Index) -> size
WADLastError() -> diagnostic string
```

- The WAD directory is owned by the parser, and a WAD is closed after directory parsing. Payload reads reopen the file temporarily and verify file length and ranges.
- A resource buffer belongs to the **caller**, must have an adequate capacity, and must be explicitly released.
- Zero-sized lumps (e.g., `E1M1`) are markers, **not** valid patch data.
- Preserve the `--version`, `--help`, `--dump-info`, `--lump-info` CLI behavior and their exit codes.
- Previous reported checks: M0/CLI script checks **25/25**, M1-01 **17/17 cases with 146/146 assertions**, and M1-02 **21/21 cases with 152/152 assertions**. These are **historical baselines**, not a substitute for actual reruns.
- All actual source changes must retain the project rule: **no trailing whitespace**, including Markdown hard-break spaces.

## 4. Part A — palette decoding

### 4.1. File format

`PLAYPAL` contains consecutive palettes. Each palette consists of **256 RGB triples**, with one byte each for red, green and blue: **768 bytes/palette**. The known Ultimate Doom 1.9ud resource has **14 palettes**, occupying **10,752 bytes**. Palette `0` is the normal display palette.

Implement explicit byte reads, keeping channel values **0–255**; do not apply a VGA `0–63` scaling, gamma correction, byte swapping, BGR conversion, or lighting changes during decoding.

### 4.2. Suggested module and contract

Create `src/Graphics/Palette.pbi` (or the nearest architecture-consistent path already used). Prefer a small cohesive API similar to:

```text
PaletteDecode(*Bytes, Length.q, *Result) -> boolean
PaletteCount(*Result) -> integer
PaletteGetRGB(*Result, PaletteIndex, ColorIndex, *R, *G, *B) -> boolean
PaletteReset(*Result)
PaletteLastError(...) -> informative diagnostic
```

These signatures are **design guidance**, not required exact PureBasic code: inspect existing conventions and use valid PB 6.41 syntax. Explicitly document ownership and free/reset behavior.

- Decode every complete palette; for generic payloads accept a **nonzero multiple of 768** with a documented reasonable count bound. Verify **exactly 14** in the known Ultimate Doom integration.
- Refuse null input when length is nonzero, invalid lengths (including 0, negative, truncated RGB triple), unreasonable palette count or output allocation failure.
- Validate requested palette and color indices; do not read outside allocated storage.
- Return a deterministic error state after failure; clear stale errors after success.
- Make failures and repeated decoding/reset safe, without dangling pointers or leaks.
- Keep palette conversion to display-format RGB/RGBA **separate**. At this stage output raw RGB channels.

## 5. Part B — classic Doom patch decoding

### 5.1. Binary picture layout

The lump is **not** a 320×200 raw RGB bitmap. It is a Doom `patch_t` picture:

| Offset | Field | On-disk type |
|---|---|---|
| 0 | width | little-endian `int16` (must be positive) |
| 2 | height | little-endian `int16` (must be positive) |
| 4 | leftoffset | little-endian **signed** `int16` |
| 6 | topoffset | little-endian **signed** `int16` |
| 8 | `columnofs[width]` | array of little-endian 32-bit offsets, relative to **start of patch lump** |

A column is a sequence of posts, followed by a **one-byte `0xFF` topdelta terminator**. Each nonterminator post is:

```text
+0: topdelta      u8  (absolute starting row, vanilla semantics)
+1: length        u8  (number of pixel indices)
+2: unused/pad    u8
+3: pixels        length bytes (palette indices)
+3+length: pad     u8
next post starts at: current post position + 4 + length
```

Thus `post.totalBytes = length + 4`. Empty/sparse columns are legal. The column may contain several posts; pixels not covered by a post remain transparent. **The byte value `0xFF` is a column terminator only when read as `topdelta`, NOT when read inside pixel data.** Original C rendering uses the post topdelta as an absolute row. Do not silently add tall-patch relative-offset behavior in this task.

Compare this representation to the reference `V_DrawPatch()` before coding. Original C code assumes trusted resources and does not perform all bounds checks; this PureBasic decoder **must** check untrusted input.

### 5.2. Suggested data model and APIs

Create `src/Graphics/Patch.pbi` and any very small shared types module strictly necessary for it.

Suggested decoded image fields:

```text
Width, Height: positive integers
LeftOffset, TopOffset: signed integers (decoded from int16)
*PixelIndices: Width * Height bytes (row-major)
*OpaqueMask: Width * Height bytes (0=transparent, 1=opaque)
```

A palette index is valid even when its value equals **255**. Do not use 0 or 255 as a transparency sentinel in the pixel plane. Keep the mask distinct, and do not bake an arbitrary background into the picture. Output pixel values in transparent locations should be initialized deterministically (e.g., zero), but their mask remains **0**.

Suggested API:

```text
PatchDecode(*Bytes, Length.q, *Decoded) -> boolean
PatchReset(*Decoded)  ; releases owned buffers and zeros metadata
PatchLastError(...) -> string
```

Exact signatures can differ to match the existing project, but the public contract **must** specify ownership, lifetime, error handling, and whether the same result structure can be reused. Do not store pointers to the caller's temporary WAD payload in the decoded image; the output must survive after the input bytes have been freed.

### 5.3. Validation and memory safety

1. Validate `Length >= 8` and all buffer accesses as **offset plus required-byte-count <= Length**, using checked 64-bit arithmetic. Never trust a nominally valid header alone.
2. Validate `Width > 0`, `Height > 0`, and `8 + 4 * Width <= Length` before reading column offsets.
3. Apply documented defensive dimension and pixel-budget limits, e.g. maximum **4096** per dimension and maximum **16,777,216** decoded pixels. Do not assume a generic patch is always 320×200; these are safety caps, not engine-level target dimensions.
4. Before allocating the two output planes, check `Width * Height` using 64-bit arithmetic and verify allocation success. A 16-million-pixel budget implies approximately 32 MiB for two byte planes. Avoid unnecessary intermediate copies.
5. Decode each column offset explicitly as an unsigned little-endian 32-bit number, validated against the **lump length**; reject offsets that do not point to a readable post/terminator. An offset into the header/table should normally be considered malformed unless the C reference or a known valid lump demonstrates otherwise.
6. For every post, first ensure there are enough bytes to read the header. When `topdelta == 255`, finish the column immediately (do **not** require pad bytes for the sentinel).
7. Otherwise ensure all `length + 4` bytes exist before reading pixels. Verify `topdelta + length <= Height` before any output write. Zero-length posts may be accepted if they advance correctly.
8. Compute output index as `row * Width + column` with checked range arithmetic. Check both destination planes and keep writes within allocated bounds.
9. Advance the input cursor by exactly `length + 4` after each post; the cursor must strictly increase, ensuring no infinite loop. Reject truncated columns and columns without a terminator. Do not require column offsets to be sorted; shared offsets may be valid.
10. Process posts in input order. If posts overlap, later covered pixels overwrite previous ones, matching sequential source rendering; the mask remains opaque there. Document/verify this behavior with a synthetic case.
11. Never interpret signed offsets as image dimensions or extend the allocation based on `leftoffset`/`topoffset`. Offsets describe positioning in a later rendering layer.
12. Fail safely on invalid source, incorrect dimensions, overflow or allocation failure; release partial allocations and expose an actionable error string. A failed call should leave the output cleared or in another **documented safe state**.
13. Avoid assumptions about alignment, native structure packing, pointer-sized `Integer` vs 16/32-bit on-disk fields, or implicit Unicode string conversions.
14. Optional compiler debugger/Purifier runs are useful, but ordinary compiled-run assertions and canary checks remain mandatory.

## 6. Reusable architecture and integration

The recommended dependency direction is:

```text
WADReadLump(...)  --> caller-owned raw byte buffer
                              |
                     +--------+--------+
                     |                 |
              PaletteDecode       PatchDecode
                     |                 |
               RGB palettes      pixel indices + mask
                     \                 /
                      \-- later M1-04 --/
                           video output
```

The decoders should accept **in-memory bytes**, not depend directly on WAD globals. This lets the same decoder test synthetic payloads without constructing an entire WAD file, and later be used with cached resources.

Suggested usage in the integration harness:

1. Find `PLAYPAL`, allocate `WADLumpSize()` bytes, read with `WADReadLump()`, call `PaletteDecode()`, verify count/channels and release input allocation.
2. Find `TITLEPIC`, allocate/read payload, decode with `PatchDecode()`, release input allocation, and verify the decoded structure still works (no borrowed pointer).
3. Verify `TITLEPIC` is **320×200** for the known test IWAD; do **not** blindly assume this for generic patches. Check pixel and mask lengths, palette index ranges, and representative corner/bounds accesses.
4. Produce reproducible checksum(s) of decoded pixels and mask (e.g., FNV-1a64), computed from actual local data. **Do not invent expected checksum values**. If possible, compare with a simple independent reference decoder or a second test path, rather than treating a self-generated hash as proof of correctness.
5. Free both decoded output planes and verify reset/reuse. The commercial data and derived image bytes must never enter version control, console dumps, or fixtures.

### Previously observed Ultimate Doom integration facts

```text
IWAD MD5:            c4fe9fd920207691a9f493668e0a2083
WAD size:            12408292 bytes
Lump count:          2306
Directory offset:    12371396
PLAYPAL:             index 0, size 10752, offset 12
TITLEPIC:            index 700, size 68168, offset 6005628
PLAYPAL raw FNV1a64: 0872FFC746616E5A
TITLEPIC raw FNV1a64:5F1254C1156A681E
```

These facts come from the accepted M1-02 report and must be **rechecked if the file is available**; they are not generic constants to hardcode into the decoder. Use the local `data/DOOM.WAD` only read-only; if absent, mark the integration `NOT RUN` and do not download the IWAD.

## 7. Synthetic tests (mandatory)

Add `tests/unit/wad_graphics_tests.pb` or an equivalent clearly named source. Connect it to existing `scripts/build.ps1`, `scripts/build.sh`, `scripts/test.ps1`, and `scripts/test.sh` without breaking existing CLI or test targets. Adapt exact script switches to the established pattern; avoid gratuitous refactors. Test byte buffers should be synthesized in code or generated in an ignored temp directory, **never extracted from Ultimate Doom**.

### PLAYPAL test matrix

| ID | Scenario | Required outcome |
|---|---|---|
| P01 | One complete 768-byte synthetic palette | Exactly 256 RGB entries, correct channel order |
| P02 | Two distinctly colored palettes | Correct palette selection, no cross-palette mixing |
| P03 | 14 palettes / 10752 bytes | Correct count and boundary indexing |
| P04 | RGB values including `00`, `80`, `FF` | Exact unsigned bytes, no scaling or clipping |
| P05 | 0, 1, 767, 769 and non-multiple-of-768 lengths | Controlled rejection, no out-of-range access |
| P06 | Null pointer with nonzero length, negative length | Controlled failure and clear error |
| P07 | Negative/out-of-range palette and color indices | Controlled failure, no invalid read |
| P08 | Decode → reset → decode; failure → success | No stale state, leaks or invalid pointer reuse |
| P09 | Guard bytes / output allocation boundaries | No modification outside owned storage |
| P10 | Reasonable palette count cap or allocation failure | Defined error behavior, no huge allocation |

### Patch decoder test matrix

| ID | Scenario | Required outcome |
|---|---|---|
| G01 | Minimal 1×1 opaque synthetic patch | One expected pixel and mask=1 |
| G02 | 2×3 patch, distinct pixels in each column | Correct **row-major** output orientation |
| G03 | Column containing several posts with transparent gap | Correct gap mask=0 and preserved pixels |
| G04 | Empty transparent column (only `FF` terminator) | Success; all mask values zero in that column |
| G05 | Pixel **value 255** within a post | Opaque pixel (mask=1), not a terminator |
| G06 | Signed negative `leftoffset`/`topoffset` | Correct signed decoding, unchanged image dimensions |
| G07 | Nonzero positive offsets | Correct metadata, no coordinate shift during decode |
| G08 | Column-table entries unsorted or two columns sharing an offset | No spurious sort assumption; deterministic result |
| G09 | Two overlapping posts | Later values win, no memory overflow |
| G10 | Zero-length post followed by valid post | Cursor advances; deterministic behavior |
| G11 | Empty / 1–7 byte input | Reject malformed header without memory access |
| G12 | Zero/negative dimensions and dimension > safety cap | Reject before allocating output |
| G13 | `8 + 4*width` beyond input length | Reject truncated offset table |
| G14 | Column offset beyond EOF or exactly EOF | Reject, no source out-of-bounds read |
| G15 | Truncated post header / missing length byte | Reject safely |
| G16 | Truncated `length + 4` post, missing trailing pad | Reject safely |
| G17 | Missing `FF` column terminator | Reject safely; bounded traversal |
| G18 | `topdelta + length > height` | Reject before output write |
| G19 | Giant declared dimensions / product overflow | Reject with controlled error, no huge allocation |
| G20 | Corrupt second column after valid first | Failure releases partial output cleanly |
| G21 | Decode failure followed by valid decode using same result | Reset/reuse works, no stale ownership |
| G22 | Free raw input after successful decode | Decoded image independent of original input |
| G23 | Canary-guarded input/output buffers | All guard bytes intact after valid and invalid cases |
| G24 | Multiple successive decode/free cycles | No crashes, output metadata and pixels stable |

If any matrix item is not meaningful for the chosen API, document an equally strong alternate assertion instead of silently skipping it. Test IDs are **categories**, not guaranteed single assertions. All new tests must run in a normal compiled PureBasic executable; report actual test counts and assertions.

### Optional integration test

- Read original `PLAYPAL` and `TITLEPIC` from `data/DOOM.WAD` **without modifying the file**.
- Confirm known metadata and raw FNV-1a64 checksums before decoding (if the existing harness supports this).
- Verify decoded palette count=14 and `TITLEPIC` dimensions=320×200; report decoded pixel/mask checksum and opaque pixel count.
- If exact independent expected decoded checksums are unavailable, report that the checks are **structural**, and leave pixel-perfect verification pending; do not falsely claim exact rendering equivalence.
- Never write `TITLEPIC`/palette raw data, screenshot files, encoded pictures, or commercial lump excerpts into the repository or the test logs.

## 8. Compile, run, and validate

1. Validate `src/Graphics/Palette.pbi` and `src/Graphics/Patch.pbi` through actual PureBasic 6.41 builds and real test execution (do not rely solely on syntax highlighting or model intuition).
2. Run the existing M0 smoke suite and **all** M1-01/M1-02 tests, reporting their actual counts and exit codes. Run the new graphics tests with both success and deliberately invalid inputs.
3. Run `scripts/build.ps1 -Check`, the normal build, all relevant unit build targets, and `scripts/test.ps1` on Windows. Preserve established conventions for program exit codes.
4. If Bash is installed, run `bash -n scripts/build.sh` and `bash -n scripts/test.sh`. If the Linux PureBasic compiler or Linux runtime is unavailable, mark **Linux runtime: NOT RUN**, even if Bash syntax checks pass.
5. Review `git status --short --branch`, `git diff --check`, `git diff --stat`, and the complete changed file diffs; inspect staged files separately if necessary. Do not stage changes on behalf of the owner.
6. Scan changed source/scripts/docs for trailing spaces/tabs. Avoid `whitespace=-blank-at-eol` workarounds in `.gitattributes`.
7. Confirm no WADs, game resources, image files, binary builds, absolute personal paths, secrets or temporary artifacts have appeared in Git status/index. Existing `data/` and `build/` must remain ignored.
8. Update `README.md` and `docs/PORTING_NOTES.md` with the exact APIs, buffer ownership, C source mapping, format assumptions, and known compatibility limitations. Do not edit `AGENTS.md` or the roadmap unless truly necessary and explained.
9. **Do not run** `git add`, `git commit`, `git push`, `git tag`, create a GitHub Release, or start M1-04. The owner will review and commit M1-03 separately.

## 9. Definition of Done

- [ ] Actual committed M1-02 API and pinned C reference examined, without replacing working code.
- [ ] `PLAYPAL` decoded as a sequence of unsigned RGB triplets; known IWAD has 14 palettes.
- [ ] Generic vanilla picture patches decoded into a row-major indexed image and a separate opaque mask; signed picture origins retained.
- [ ] Valid, empty, overlapping, multi-post and sparse columns handled according to documented rules.
- [ ] All malformed data cases rejected without memory overreads/writes, loops, leaks or stale output state.
- [ ] New synthetic matrix P01–P10 and G01–G24 executed with real PureBasic 6.41 and actual assertions reported.
- [ ] Existing M0/M1-01/M1-02 regression suites pass, or any failure is documented explicitly.
- [ ] Optional local `DOOM.WAD` integration PASS, FAIL, or NOT RUN, with reason and **metadata/checksums only**.
- [ ] `git diff --check` clean; no trailing whitespace, private resources or unintended changes.
- [ ] All changes left uncommitted and unstaged (except owner-preexisting staging), and **M1-04 has not begun**.

## 10. Completion report (required)

```text
Task / milestone: M1-03 — PLAYPAL and Doom Patch decoder
OS / PureBasic compiler: <actual>; Linux runtime: PASS / FAIL / NOT RUN
Baseline HEAD / worktree: <actual>
Upstream functions/types inspected: <exact paths and pinned SHA>
Files created / modified: <paths>
Palette API / representation / ownership: <actual implementation>
Patch API / representation / ownership: <actual implementation>
Vanilla post/topdelta handling: <rules; tall patches out of scope>
Validation strategy and safety caps: <rules and limits>
Syntax/build checks: PASS / FAIL / NOT RUN — <commands and exit codes>
M0 smoke tests: <actual counts>
M1-01 tests: <actual counts and assertions>
M1-02 tests: <actual counts and assertions>
M1-03 palette tests: <P01–P10; counts/assertions>
M1-03 patch tests: <G01–G24; counts/assertions>
Ultimate Doom integration: PASS / FAIL / NOT RUN — <metadata only>
Decoded TITLEPIC: <width, height, opaque count, pixel and mask checksum>
Git/diff/whitespace/commercial-resource audit: <actual results>
Known limitations / compatibility deviations: <list>
Next suggested task: M1-04 — TITLEPIC presentation (DO NOT START)
```

## 11. Sources and technical reference

- [Original Doom, pinned upstream repository](https://github.com/id-Software/DOOM/tree/master/linuxdoom-1.10)
- [Original Doom `v_video.c` — V_DrawPatch reference](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/v_video.c)
- [Original Doom `d_main.c` — title page draw path](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/d_main.c)
- [Original Doom `doomdata.h` — picture and column structures](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/doomdata.h)
- [Doom WAD format, including patch and PLAYPAL layout](https://reverseengineering.wiki/index.php/Format%3AWAD_%28Doom_engine%29)
- [PureBasic 6.41 Memory library](https://www.purebasic.com/documentation/memory/index.html)

**This document is an assignment. No M1-03 code has been written or tested by its creation.**
