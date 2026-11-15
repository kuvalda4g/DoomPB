# DoomPB — M2-02: TEXTURE1/TEXTURE2 definitions and PNAMES resolution

> - **Task ID:** `M2-02`
> - **Milestone:** M2 — Resources, textures and level data; `v0.2.0` is **not** complete
> - **Status:** Implementation assignment, not an implementation report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Reasoning:** High; increase only for a concrete problem
> - **Language / compiler:** PureBasic 6.41, full edition
> - **Primary platform:** Windows x64; Linux x64 must be reported `NOT RUN` unless actually tested
> - **License:** GPL-2.0-only; commercial IWAD content must remain local
> - **Pinned reference:** `../doom-original`, commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M2-01 committed and all M0/M1/M2-01 tests passing
> - **Read first:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, actual code and tests, then this assignment

## 1. Objective and scope

Extend the existing DoomPB resource pipeline with **validated wall-texture definitions** from `TEXTURE1` and optional `TEXTURE2`. Decode each definition's name, dimensions, flags, and ordered patch placements; validate PNAMES indices; resolve **referenced** PNAMES entries to WAD lump indices using the existing single-WAD APIs.

The deliverable is a reusable, independently testable, **data-only texture definition model**, not a rendered picture. Record exact, observable metadata and reference counts from the owner's legally obtained Ultimate Doom IWAD without extracting or committing game graphics.

**M2-03**, not this task, will assemble/decode patch pixels and composite textures.

### Explicit non-goals

- No composite texture pixel allocation, column lookup generation, post clipping, wall drawing, or 3D rendering.
- No `COLORMAP` lighting implementation, animation, PNAMES rewriting, texture-cache replacement, or generic patch decoding rewrite.
- No multi-WAD/PWAD overlay manager; keep one currently open WAD and document future extension points.
- No map parser, `E1M1` geometry, sprites/flats, audio, Doom II support, or release/tag `v0.2.0`.
- No broad CLI refactoring, generated texture previews, screenshot publication, or saving copyrighted lump payloads.
- Do not silently 'fix' missing texture definitions or missing patch names by inventing replacements.

## 2. Inspect project and C reference before editing

1. Run `git status --short --branch`, `git log -1 --oneline`, `git tag --list`, `git diff --stat`, and `git diff --cached --stat`; preserve user edits, staged files and unrelated work. Verify that M2-01 is committed; do not guess HEAD SHA.
2. Read real declarations, ownership contracts, error behavior and tests for:
   - `src/WAD/WAD.pbi`, `src/Core/Endian.pbi`;
   - `src/Graphics/PNames.pbi`, `src/Graphics/Colormap.pbi`;
   - `src/Graphics/Patch.pbi` and `src/DoomPB.pb` only as needed;
   - `tests/unit/wad_resource_tests.pb`, earlier WAD/graphics/display tests;
   - `scripts/build.ps1`, `scripts/build.sh`, `scripts/test.ps1`, `scripts/test.sh`.
3. Verify `git -C ../doom-original rev-parse HEAD` against the pinned upstream SHA. Inspect `linuxdoom-1.10/r_data.c`, especially `mappatch_t`, `maptexture_t`, `texpatch_t`, `texture_t`, `R_InitTextures`, `R_CheckTextureNumForName`, `R_GenerateLookup`. Inspect `w_wad.c` lookup semantics.
4. Verify *actual* PureBasic syntax for dynamic memory, structures, pointer arithmetic, signed 16-bit reads, array/list operations and capacity handling with the installed PureBasic 6.41 compiler. Do not invent APIs.
5. **Before making changes**, provide a short plan listing files, proposed functions/types, lifecycle/ownership, handling of `TEXTURE2`, duplicate-name rules, limits, and tests.

The prior M2-01 report found `COLORMAP` = 8,704 bytes / 34 tables and `PNAMES` = 2,812 bytes / 351 names in the owner's `DOOM.WAD`. These are known **integration fixtures**, not constraints for every valid WAD. The application version is `0.1.0` and must remain unchanged.

## 3. Exact on-disk layout — do not rely on C structure packing

The canonical Doom `TEXTURE1` / `TEXTURE2` lump format is little-endian:

```text
texture lump:
  +0          int32  numtextures
  +4          int32  offsets[numtextures]  (from start of this lump)

maptexture_t at offsets[i]:
  +0          char[8] name (raw bytes; no guaranteed NUL terminator)
  +8          int32  masked (preserve raw value; no rendering effect here)
  +12         int16  width
  +14         int16  height
  +16         int32  columndirectory (obsolete; preserve raw value; NEVER dereference)
  +20         int16  patchcount
  +22         mappatch_t patches[patchcount]

mappatch_t (10 bytes each):
  +0          int16  originx
  +2          int16  originy
  +4          int16  patch (index into PNAMES)
  +6          int16  stepdir (historical field; preserve)
  +8          int16  colormap (historical field; preserve)
```

Thus a definition occupies **22 + 10 × patchcount** bytes starting at its directory offset. The offsets directory occupies **4 + 4 × numtextures** bytes. On-disk `columndirectory` is *obsolete*, not a pointer into a file or a location to seek.

**Signedness:** parse signed int16 fields accurately. In particular `originx`/`originy` may be negative; patch indices and patch counts must be checked before use. `masked` and obsolete fields should be preserved exactly, without inferred semantics. Use endian-safe reads rather than overlaying PureBasic structures onto file bytes.

**Ordering:** Texture definitions are read in directory order: all entries from `TEXTURE1`, followed by those from `TEXTURE2` if present. Patch placements within each texture preserve their original order for later back-to-front composition.

**Important duplicate distinction:**

- `WADFindLump()` finds the **last** matching lump in the WAD directory (existing M1-02 contract).
- Vanilla `R_CheckTextureNumForName()` scans the **texture definition array from the beginning**, returning the **first** matching texture name. Do not import lump duplicate precedence into texture-name lookup. Inspect the original implementation and document the rule.

## 4. Decoder representation and lifetime

Use architecture-appropriate modules, preferably:

```text
src/Graphics/TextureDefs.pbi            # binary decoding, accessors and ownership
src/Graphics/TextureResolver.pbi        # PNAMES -> WAD index mapping (only if needed)
tests/unit/wad_texture_defs_tests.pb    # standalone synthetic tests
```

A single cohesive module is acceptable if it keeps responsibilities clear. Avoid naming collisions with PureBasic built-ins. Save the name `Texture.pbi` for M2-03 composition if appropriate.

Provide documented public operations equivalent to these **conceptual signatures** (adapt to actual PureBasic declarations and existing naming conventions):

```text
TextureDefsDecode(*Bytes, Length.q, *Result) -> boolean
TextureDefsReset(*Result)
TextureDefsCount(*Result) -> integer
TextureDefsGetNameByte(*Result, TextureIndex, ByteIndex) -> 0..255 / error
TextureDefsGetProperties(*Result, TextureIndex, *Fields...) -> boolean
TextureDefsGetPatch(*Result, TextureIndex, PatchIndex, *Fields...) -> boolean
TextureDefsLastError() -> string

TextureDefsResolve(*Result, *PNames) -> boolean or structured status
TextureDefsGetResolvedPatchLump(*Result, TextureIndex, PatchIndex) -> index / error
TextureDefsFindName(*Combined, Name) -> definition index / -1
```

This is **API guidance**, not an instruction to generate the exact text above. A dedicated `TextureDefSet` can represent one lump. A separate `TextureCatalog` or a lightweight combined index can concatenate two sets without copying all entries. Pick the simplest design matching the project.

### Ownership requirements

- The caller zero-initializes each result structure **once** and owns its lifetime. The decoder owns **private copies** of all definition and patch metadata; it must not retain borrowed pointers into the input WAD payload.
- Reset/free operations must be safe and idempotent. Repeated decode, failed decode and reset should neither leak nor double-free memory. If replacing an existing result fails, define and test whether the result is emptied (preferred given prior decoders) or retains its old value; be consistent.
- For an optional `TEXTURE2`, reset/close must release both texture sets and any resolved-index arrays. Failure halfway through loading the second lump must leave a well-defined state, not half-valid references.
- Do not store raw pointers to `PNamesTable` or WAD parser-global arrays whose lifetime may end; store stable **indices and owned metadata**, and document that a subsequent `WADOpen/WADClose` invalidates resolved WAD indices until re-resolution.
- No unbounded per-texture allocations or allocation by unvalidated counts. Prefer a predictable memory budget; check each multiplication and sum using `.q` before allocating.
- Keep raw eight-byte texture names and source identity (`TEXTURE1` or `TEXTURE2`). Provide a printable diagnostic name separately; never assume embedded NUL is safe to turn directly into a string.

## 5. Decoder validation policy

Implement both structural validation and clear, actionable errors.

1. Require non-null input, `Length >= 4`, and a valid output object.
2. Parse `numtextures` as signed LE32. Reject negative and unreasonably large counts (choose and **document** a justified safety cap; e.g. 65,536 definitions/lump). A zero count may be allowed as an empty definition table, if consistently documented and tested.
3. Verify `4 + 4 × numtextures <= Length` with checked 64-bit arithmetic before reading any offsets.
4. Decode each signed LE32 definition offset. Reject negative offsets and truncated definition headers. For a strict parser, reject offsets **inside the directory table**, and document that this is stricter than original C.
5. Validate `22 + 10 × patchcount` and `offset + requiredBytes <= Length` before reading any patch; reject negative patchcount and cap unreasonable counts/total allocations.
6. Validate width and height as positive signed 16-bit values within a documented reasonable cap (suggest 1..4096 for the first implementation). Do not substitute unsigned interpretation, clamp corrupted values, or silently accept zero dimensions.
7. Preserve signed origins and all historical fields as raw parsed integers. The `masked`/`columndirectory` fields are not addresses; **do not follow them**.
8. Preserve directory order; do **not** assume offsets are sorted or contiguous. Duplicate or overlapping valid ranges can be tolerated when within bounds; never use such overlap to read beyond the blob. Record any intentionally stricter policy.
9. A patchcount of **zero** may be parsed as a structurally empty definition with an explicit **not renderable** status; do not accidentally allocate a negative-sized array or loop with a signed underflow. Referenced negative PNAMES indices must never be dereferenced.
10. Avoid partial writes on failed argument checks; on partial decode failures, free transient allocations and leave the result in a documented safe state. Error messages should identify the texture index, source lump and failing field when possible.
11. Do not require a texture to have power-of-two width or height: data decoding and future legacy renderer width masking are separate concerns.
12. Never treat counts, byte lengths or names from a WAD as trusted simply because the user's first IWAD passes tests.

Do not rewrite `Core/Endian.pbi` or the WAD reader unless a concrete failing test demonstrates a defect; keep the diff narrow.

## 6. PNAMES resolution and texture catalog semantics

### 6.1. Resolve referenced patch indices

For each **actually referenced** `mappatch_t.patch`:

1. Verify it is a nonnegative index smaller than `PNamesCount()`; reject invalid indices before accessing PNAMES.
2. Obtain its **raw 8-byte** name via the existing `PNamesRawNameByte()` API (verify its real signature). Preserve the original bytes; do not overwrite or uppercase the PNAMES table.
3. For canonical printable ASCII Doom names with optional trailing NUL padding, convert safely to a query and use **existing** `WADFindLump()` to obtain the winning lump index.
4. Validate that a resolved lump exists and has nonzero data if it will be consumed as a picture. Report missing/zero-length referenced patch as an explicit resolution problem; do not silently substitute another image. A deeper patch-format check belongs to M2-03.
5. Store an **index**, not a borrowed file buffer or pointer. Preserve source PNAMES index and placement origin separately.

Do **not** eagerly require every PNAMES entry to exist in the WAD. Some entries may be unused, and vanilla Doom resolves names but raises a fatal error only when a missing patch is actually referenced by a texture.

The M2-01 PNAMES decoder intentionally allows malformed raw names, including embedded NUL, lowercase, and bytes >= 128. The resolver must handle these safely: explicitly report **unresolvable/noncanonical referenced names**, rather than silently normalizing or truncating them into another valid resource. For canonical names, use the same ASCII query behavior as existing `WADFindLump()`.

### 6.2. Missing resources and failure strategy

Choose a simple documented outcome: e.g. parsing the texture definitions can succeed before WAD/PNAMES resolution, while a **strict resolution** call fails with a detailed error on a referenced missing patch. If there are multiple errors, report the first with source texture/patch indexes; do not leave stale resolved indices from earlier successful calls.

For a user WAD that lacks `TEXTURE1`, loading a full wall-texture catalog must fail cleanly. `TEXTURE2` is **optional**: absent is success, present but malformed is failure. Parse a deliberately empty `TEXTURE2` only according to the documented zero-count rule. Use WAD lookup for resource names, which already implements last-lump precedence within the single WAD.

### 6.3. Texture-name lookup

If a combined catalog supports `TextureDefsFindName()`:

- Use 8-byte Doom-style ASCII case-insensitive query comparison for **canonical** stored texture names, with deterministic ASCII handling and bounded reads.
- Search definitions **from first to last** (`TEXTURE1` first, then `TEXTURE2`), matching the original `R_CheckTextureNumForName` lookup order.
- Reject invalid/noncanonical external queries rather than interpreting them as Unicode identifiers; keep raw stored names available for diagnostics.
- The special wall-side `"-"` no-texture marker and vanilla's index-0 sentinel behavior belong to a later texture consumer; do **not** accidentally equate that marker with a real texture definition in this API. Document any deliberate compatibility shortcut.

## 7. CLI and integration behavior

**Do not change** existing `--version`, `--help`, `--dump-info`, `--lump-info`, and `--show-title` behavior. Keep the reported version `DoomPB 0.1.0` until milestone M2 is accepted.

For observability, use the test harness. An optional metadata-only diagnostic `--texture-info` may be added **only if it fits cleanly** into the current CLI without a broad refactor; document exact invocation and codes if implemented.

An M2-02 smoke/integration test should:

1. Use the WAD API to load `PNAMES`, `TEXTURE1` and optional `TEXTURE2` into temporary caller-owned byte buffers.
2. Decode definitions into independent owned metadata, then immediately release the raw lump buffers to prove independence.
3. Combine source-order definitions and resolve only referenced patches through the existing PNAMES and WAD interfaces.
4. Report **counts, dimensions, patch counts, zero-based indices and non-reconstructable hashes only**. Do not dump names en masse, raw patch payloads, texture previews, or derived copyrighted graphics.
5. Verify that first-match texture-name precedence is respected without modifying the original user IWAD.

For the known Ultimate Doom IWAD, check **observed** values rather than hard-coding an unverified texture count. You may record stable counts/hashes as future integration fixtures after measuring them. Confirm the input MD5 if available: `c4fe9fd920207691a9f493668e0a2083`.

The integration must not modify `data/DOOM.WAD`; missing local IWAD is `NOT RUN`, not test failure for synthetic-only CI.

## 8. Tests — minimum synthetic coverage

Create `tests/unit/wad_texture_defs_tests.pb` (or architecture-consistent equivalent). Generate **entirely synthetic** WAD/lump fixtures under ignored temporary/build directories; never commit game assets. Follow existing assertion/result conventions. All categories below should run through compiled PureBasic 6.41 code, not be simulated in Python/PowerShell.

### Binary definitions: D01–D20 (20 categories)

| ID | Scenario | Expected result |
|---|---|---|
| D01 | One valid texture with one patch | Exact name, width/height, placement and count |
| D02 | Multiple textures; offsets out of order | Directory order preserved regardless of physical order |
| D03 | Valid definitions with negative `originx/originy` | Signed 16-bit values preserved |
| D04 | Exactly eight name bytes with no NUL | Correct raw-name access; no overread |
| D05 | Short name with NUL padding | Raw bytes and diagnostic rendering distinguish padding |
| D06 | `masked`, obsolete `columndirectory`, `stepdir`, `colormap` nonzero | Values preserved; obsolete field never dereferenced |
| D07 | Missing header / 0..3 bytes | Controlled error, no invalid read |
| D08 | Negative definition count | Rejected before allocation |
| D09 | Count exceeds cap or directory arithmetic overflow | Safe rejection |
| D10 | Truncated offsets directory | Rejected before reading missing entries |
| D11 | Negative definition offset / offset past EOF | Safe rejection |
| D12 | Definition offset inside directory table | Rejected by documented strict policy |
| D13 | Truncated 22-byte definition header | Safe rejection |
| D14 | Width/height 0, negative, or above cap | Rejected with useful diagnostic |
| D15 | Negative patchcount or excessive patchcount | Rejected before allocation |
| D16 | Truncated 10-byte patch placement | Rejected; partial allocations freed |
| D17 | Exactly-at-EOF final patch placement | Correct acceptance, no off-by-one |
| D18 | Empty texture directory (count 0) | Documented safe empty result |
| D19 | Struct reused: successful decode, failure, decode again, double reset | No stale data, leaks or double-free |
| D20 | Distinct definitions at overlapping or duplicate legal offsets | Safe deterministic behavior; no invented sorting |

### PNAMES / WAD resolution: R01–R10 (10 categories)

| ID | Scenario | Expected result |
|---|---|---|
| R01 | One valid PNAMES index, matching WAD patch lump | Correct resolved lump index |
| R02 | Multiple placements referencing same PNAMES entry | Consistent indices, no payload duplication |
| R03 | Negative PNAMES index or index == `PNamesCount()` | Safe failure with precise diagnostic |
| R04 | Referenced PNAMES entry absent from WAD | Explicit resolution error, never fallback |
| R05 | Unused PNAMES entry missing from WAD | Does not fail resolution of valid referenced entries |
| R06 | Duplicate patch-lump names in WAD directory | **Last** lump index wins |
| R07 | Duplicate texture names across TEXTURE1 and TEXTURE2 | Texture-name lookup returns **first** texture index |
| R08 | TEXTURE2 missing vs present and malformed | Missing optional is OK; malformed present fails |
| R09 | Zero-length referenced patch, noncanonical/embedded-NUL PNAMES name | Controlled error, no buffer overread or silent substitution |
| R10 | WAD close/reopen or failed re-resolution after earlier success | Resolved state invalidated, no stale indices/pointers |

### Integration: I01–I04 (4 categories)

- **I01:** Synthetic WAD with `PNAMES` + `TEXTURE1`, all raw buffers released after decode; ownership is correct.
- **I02:** Synthetic WAD with both `TEXTURE1` and `TEXTURE2`, source-order concatenation and first-match texture name behavior.
- **I03:** Synthetic WAD with absent `TEXTURE1`, malformed `TEXTURE2`, or invalid referenced patch; readable errors and no leaked handles.
- **I04 (optional):** Read-only local Ultimate Doom IWAD: actual texture counts, sample dimensions/placements, patch resolution, and stable metadata hashes. `NOT RUN` if legal IWAD is unavailable.

Add byte-pattern guards/canaries where raw buffers or index arrays are accessed. Verify both success and failure paths, including no writes beyond validated structures. Where helpful, use intentionally unsorted data and negative signed values to catch accidental unsigned or pointer-based parsing.

## 9. Regression, build scripts and review

1. Integrate new tests into existing `scripts/build.ps1`, `scripts/build.sh`, `scripts/test.ps1`, `scripts/test.sh` without changing existing flags. A distinct test target like `-TextureDefTest` / `--texture-def-test` is fine; adapt to actual script conventions.
2. Run PureBasic syntax checks for the production executable and **all** test entry points. Run the actual Windows x64 build, then complete `scripts/test.ps1`.
3. Preserve M0/M1 baseline: **96 synthetic scenarios / 694 assertions**, and M2-01 baseline **28 synthetic cases / 160 assertions plus 3 synthetic integration cases / 31 assertions** (reported counts; re-measure, don't hardcode). Confirm script checks and the `--show-title` regression.
4. Use synthetic fixtures for every required unit test. The real IWAD is optional, read-only and excluded from public automated tests.
5. On Windows, confirm application still reports `DoomPB 0.1.0`; run `--dump-info`/`--lump-info` and title-window launch/close as appropriate. Do not require GUI for headless unit tests.
6. If Linux PureBasic is not available, run `bash -n` on updated scripts if Bash exists, and report Linux runtime as **NOT RUN**; don't claim parity from shell syntax validation.
7. Inspect `git status --short --branch`, `git diff --check`, `git diff --stat`, `git diff`, plus staged state if any. No trailing whitespace in `.md`, `.pb`, `.pbi`, `.ps1` or `.sh`.
8. Audit **all changed and added files** before staging: no commercial WADs, raw lump data, `.exe`, DLL, images, screenshots, generated binaries, local absolute paths, credentials or secrets.
9. Update `docs/PORTING_NOTES.md`, `README.md` and (only if appropriate) `CHANGELOG.md` with the implemented API, source mapping, validation differences and deferred tasks. Do not rewrite earlier history or imply M2 is complete.
10. **Do not** run `git add`, `git commit`, `git push`, create tags/releases, change version, or begin M2-03. All Git publication decisions remain with the owner.

## 10. Definition of Done

- [ ] Actual committed M2-01 API/tests and pinned original Doom C sources inspected before editing.
- [ ] TEXTURE1 parsed securely; TEXTURE2 handled as an optional second definition lump.
- [ ] Every parsed definition preserves eight name bytes, dimensions, masked/obsolete fields and ordered signed patch placement metadata.
- [ ] Decode validates count, offset, bounds, dimensions, patchcount, indices and memory ownership.
- [ ] PNAMES references are checked and **only referenced names** are resolved to WAD indices.
- [ ] Duplicate **lump** names use last match; duplicate **texture** names use first match, documented and tested.
- [ ] Failed parse or resolve leaves valid resettable state and helpful errors, with no stale references.
- [ ] D01–D20, R01–R10, I01–I03 all pass; I04 passes with local IWAD or explicitly reports `NOT RUN`.
- [ ] Existing PureBasic tests, CLI and TITLEPIC presentation remain working.
- [ ] Windows compilation and tests genuinely executed; Linux is accurately marked PASS/FAIL/NOT RUN.
- [ ] Git diff/whitespace/licensing audits clean; files left unstaged and uncommitted.
- [ ] Application remains `0.1.0`; `v0.2.0` not claimed; M2-03 not started.

## 11. Mandatory final report

```text
Task / milestone: M2-02 — TEXTURE1/TEXTURE2 definitions
OS / compiler: <observed>; Linux runtime: PASS / FAIL / NOT RUN
Baseline HEAD / Git state: <observed commit and preexisting edits>
Upstream symbols inspected: <C files/functions/types; pinned SHA>
Files created / modified: <paths>
Definition API / memory ownership: <names, bounds, reset/error semantics>
Texture format semantics: <header fields, patch placements, TEXTURE2 handling>
Resolution semantics: <PNAMES checks, missing patches, invalidation policy>
Duplicate precedence: <WAD last-match; texture definitions first-match>
Syntax checks: PASS / FAIL / NOT RUN — <commands, exit codes>
Build: PASS / FAIL / NOT RUN — <commands, exit codes>
M0/M1/M2-01 regression: <actual test and assertion counts>
M2-02 new tests: <actual D01-D20, R01-R10, I01-I03 assertions/results>
Ultimate Doom I04: PASS / FAIL / NOT RUN — <observed metadata, no content>
TITLEPIC / CLI regression: <results>
Git diff / whitespace / resource audit: <results>
Known deviations / technical risks: <list>
Suggested next task: M2-03 — composite wall textures (DO NOT START)
```

## 12. Sources and technical references

- [Original Doom `r_data.c`](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_data.c): `mappatch_t`, `maptexture_t`, `R_InitTextures`, `R_CheckTextureNumForName`.
- [Original Doom `w_wad.c`](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/w_wad.c): WAD lookup and lump reads.
- [Doom texture lump specification](https://doomwiki.org/wiki/TEXTURE1_and_TEXTURE2): on-disk definitions and placements; verify exact fields against original C.
- [PureBasic documentation](https://www.purebasic.com/documentation/): syntax and memory safety for the installed compiler.
- Project docs: `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`.

---

**This assignment defines only M2-02.** The end result is a validated, resolved **description of textures**. Rendering and pixel composition are M2-03+ tasks.
