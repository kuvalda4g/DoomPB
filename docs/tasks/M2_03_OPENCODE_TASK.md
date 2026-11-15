# DoomPB — M2-03: Composite Wall Textures

> - **Task ID:** `M2-03`
> - **Milestone:** M2 — Resource and Map Loading; `v0.2.0` is **not** complete
> - **Status:** Implementation assignment, **not** a completion report
> - **Primary agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Recommended reasoning:** High; use XHigh only for a specific unresolved compatibility issue
> - **Language:** Native PureBasic **6.41**, full edition
> - **Primary verification:** Windows x64; Linux x64 = `NOT RUN` unless truly tested
> - **License:** GPL-2.0-only; the commercial IWAD is local test data only
> - **Primary C reference:** `../doom-original/linuxdoom-1.10/r_data.c`
> - **Pinned upstream commit:** `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Read first:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, actual M1 and M2-01/M2-02 source, tests and scripts

## 1. Objective

Continue **from the existing committed M2-02 implementation**, without creating a parallel WAD, patch or texture-definition subsystem. Implement a deterministic, bounds-checked **wall texture compositor** that:

1. Selects an existing definition from the resolved `TextureCatalog` (`TEXTURE1` followed by optional `TEXTURE2`).
2. Loads the actual referenced patch lumps from the currently open WAD with the existing `WADReadLump` API.
3. Decodes each patch using the existing M1-03 `PatchDecode` implementation.
4. Draws the patches in definition order, at their signed `originx`/`originy` positions, into a **row-major 8-bit index plane plus a separate opacity mask**.
5. Reports metadata and deterministic checksums for synthetic test fixtures and, optionally, the owner's read-only Ultimate Doom IWAD.

**Milestone output:** a correctly composed texture in owned memory, **not** a rendered wall or preview file. M2-04 will handle flats/sprites and M3/M4 will implement the classic wall renderer and its column-oriented access.

### Explicit non-goals

- No BSP, `R_DrawColumn`, `R_GetColumn`, `R_RenderPlayerView`, game window, map loader, or 3D renderer.
- No new texture definitions decoder, PNAMES parser, WAD lookup system, Doom patch decoder, palette decoder or framebuffer rewrite.
- No `COLORMAP` lighting, RGB colorization, gamma processing, alpha blending, filtering, scaling or color-key transparency.
- No generalized PWAD overlay manager, disk image cache, long-lived patch cache, texture animation, mipmaps, GPU/SDL/OpenGL/Vulkan.
- No PNG/BMP export or publishing extracted/composited commercial graphics; **do not** write previews into tracked folders.
- No release/version bump: application must continue reporting `DoomPB 0.1.0`; do not tag `v0.2.0`.

## 2. Mandatory inspection and plan before editing

1. Run `git status --short --branch`, `git log -1 --oneline`, `git tag --list`, `git diff --stat`, `git diff --cached --stat`. The owner reported that M2-02 was committed; **verify actual HEAD and working tree**. Preserve existing staged/untracked/user files.
2. Read the actual APIs, types, lifetimes, includes and tests in:
   - `src/Graphics/TextureDefs.pbi`, especially `TextureCatalog`, `TextureCatalogResolve`, `TextureCatalogGetPatch`, `TextureCatalogGetResolvedPatchLump`, and any invalidation function;
   - `src/Graphics/Patch.pbi`, especially `PatchImage`, `PatchDecode`, `PatchReset` and the row-major planes;
   - `src/WAD/WAD.pbi` (`WADOpen`, `WADClose`, `WADLumpSize`, `WADReadLump`, error handling);
   - `src/Graphics/FrameBuffer.pbi` for prior blit and clipping semantics, **without coupling texture composition to the window**;
   - `tests/unit/wad_texture_defs_tests.pb`, `wad_graphics_tests.pb`, `wad_display_tests.pb`, and `scripts/{build,test}.{ps1,sh}`;
   - `docs/PORTING_NOTES.md` for all prior compatibility decisions.
3. Verify `git -C ../doom-original rev-parse HEAD` matches the pinned SHA; inspect `r_data.c`: `texpatch_t`, `texture_t`, `R_InitTextures`, `R_GenerateLookup`, `R_DrawColumnInCache`, `R_GenerateComposite`, `R_GetColumn`. Inspect `v_video.c`/`r_defs.h` only if needed to clarify patch coordinates and mask behavior.
4. Check PureBasic 6.41 compiler/docs for allocation sizes, pointers, byte reads/writes, structures and loops. For uncertain APIs, compile a minimal disposable experiment; **do not invent PureBasic functions**.
5. **Present a short implementation plan before changing code**: exact files, API/ownership, how WAD payloads and patch images are freed, clipping arithmetic, uncovered-pixel policy, tests and error/cleanup strategy.

## 3. Existing baseline — do not regress

The accepted M2-02 report describes the following **observed**, not guaranteed exact, APIs. Read declarations before selecting signatures:

```text
TextureCatalogDecode / Reset / Count / FindName / Resolve
TextureCatalogGetProperties / GetPatch / GetResolvedPatchLump
TextureCatalogInvalidateResolved
PatchDecode(*Bytes, Length, *Result), PatchReset(*Result)
PatchImage: Width, Height, LeftOffset, TopOffset, *Pixels, *Mask
WADReadLump(Index, *Destination, Capacity), WADLumpSize(Index)
```

- M2-02 preserves `TEXTURE1` then `TEXTURE2`, source definition order, and ordered patch placements.
- Texture-name lookup returns the **first** matching texture definition; WAD lookup by lump name returns the **last** matching directory entry. Reuse resolved indices; **do not change either rule**.
- All referenced PNAMES entries were resolved in the known Ultimate Doom integration; resolving to an index is not the same as validating its **patch payload format**.
- Resolved WAD indices currently require **explicit invalidation/re-resolution** after `WADClose()`/`WADOpen()`. Do not assume they remain valid across a WAD change. Do not silently use stale results.
- The M1-03 decoder exposes a **separate mask**: opaque color index `255` is valid, not transparency.
- M1-04's framebuffer is index-based; keep composition headless and independent from `Video.pbi`.

Previous reported Windows results (rerun, do not merely quote): M1 `96` scenarios / `694` assertions; M2-01 `31` / `191`; M2-02 `33` / `165`; build/test-script checks `44/44`. Counts may change if the harness evolves; report observed values.

## 4. Vanilla Doom semantics and deliberate scope boundary

The original `r_data.c` stores each texture as an ordered list of patch placements. `R_GenerateLookup()` counts coverage per **column** and can point directly into a source patch for a single-patch column. `R_GenerateComposite()` creates cached columns for columns covered by multiple patches, using `R_DrawColumnInCache()` to clip posts vertically. The eventual renderer consumes this representation via `R_GetColumn()`.

For **M2-03**, implement the **logical per-pixel equivalent** in a simpler 2D indexed surface; do **not** prematurely port the exact column cache or `texturewidthmask` optimization. Preserve original placement order, opaque post pixels and signed placement coordinates; record that the storage layout and treatment of unfilled cached bytes differ from original's internal column cache. This distinction will matter when M3/M4 implement exact column sampling.

### Placement and clipping semantics

For each texture definition, in stored order:

```text
For each placement p (definition order, first to last):
  patch = decode(WAD[p.resolvedLumpIndex])
  for each patch pixel (px, py) with mask(px,py) != 0:
    tx = p.originx + px
    ty = p.originy + py
    if 0 <= tx < texture.width and 0 <= ty < texture.height:
      output.indices[ty * texture.width + tx] = patch.indices[py * patch.width + px]
      output.mask[ty * texture.width + tx] = 1
```

- **Later opaque pixels overwrite earlier opaque pixels.** Later **transparent** pixels leave the previous texture pixel and mask intact.
- **Negative `originx` and/or `originy` are legal**; clip to texture bounds without out-of-bounds pointer operations.
- `PatchImage.LeftOffset` and `.TopOffset` are **not** added to `originx`/`originy` again. The placement in a wall texture is already defined by `mappatch_t`/`texpatch_t`. Document this with a targeted test.
- Preserve texture `width`/`height` and every 8-bit palette index exactly. Neither decode nor composition applies `COLORMAP`, PLAYPAL RGB, VGA scaling or palette index remapping.
- Uncovered texture pixels have `mask=0` and deterministic `indices=0`. **Do not invent missing colors, transparency fallbacks or opaque black.** Some columns/pixels may have no contributing opaque posts; never read uninitialized memory.
- Zero placements, completely off-screen placements, disconnected patches, sparse columns, and shared/overlapping patch rectangles must not cause unsafe memory access. If no patch placements are considered unsupported for composition, fail cleanly with a documented reason; do not corrupt memory.
- A **source patch's width/height** and its origin inside the texture are independent of its signed internal alignment offsets (`PatchImage.LeftOffset/TopOffset`).
- Use **64-bit intermediates** for `origin + coordinate`, `width * height`, `row * width + column`, buffer sizes and all bounds calculations. Validate before converting to pointer-sized allocation counts.
- Do not require that every column or pixel is opaque; coverage can be reported as a statistic instead. If a future strict vanilla renderer disallows uncovered columns, that belongs to renderer-specific validation.

### Explicit vanilla compatibility note

The original's single-source-column fast path and its multi-source composite cached-column layout are not identical to a row-major plane+mask representation. **Matching synthetic per-pixel composition does not establish bitwise equivalence with `R_GetColumn` or pixel-perfect game rendering.** Do not claim that in README or the report. A renderer-friendly column accessor/lookup may be designed later, once M3/M4 consumers are known.

## 5. Module, API and ownership requirements

Prefer `src/Graphics/Texture.pbi` (or a clearly named equivalent if `Texture.pbi` already exists) and a standalone test file `tests/unit/wad_composite_tests.pb`.

Suggested *conceptual* interface — adapt to real PureBasic 6.41 conventions:

```text
TextureImage { Magic, Width, Height, PixelCount, *Pixels, *Mask }
TextureCompose(*Catalog, TextureIndex.i, *Output) -> boolean
TextureImageReset(*Output)
TextureImageGetPixel(*Output, X, Y) -> 0..255 / error
TextureImageIsOpaque(*Output, X, Y) -> boolean / error
TextureImageOpaqueCount(*Output) -> count / error
TextureLastError() -> diagnostic string
```

**Choose the smallest API needed**, without duplicating existing frame-buffer utilities. Compositing may use a private helper that clips and blits `PatchImage` into the output; if reusing `FrameBufferBlitPatch()`, do so only if its semantics fully match and do not hide mask tracking or ownership. The final texture object must carry a reliable mask.

Ownership/lifetime contract:

- Caller initializes `TextureImage` to zero once, owns it and calls `TextureImageReset`. Reset is idempotent and safe after success/failure.
- Compositor owns **private copies** of the final indices/mask. They remain valid after temporary WAD payload buffers and decoded `PatchImage` objects are freed.
- Each input WAD payload buffer belongs to the immediate caller of `WADReadLump`; every early return and failure releases it.
- Every decoded temporary patch must be reset/freed even when a subsequent patch fails.
- A failed compose must leave output in a documented state (prefer cleared/empty, consistent with existing decoders) and must not retain partially composed valid-looking data or dangling pointers.
- A repeated compose into the same output must not leak, double-free or retain pixels from the previous texture.
- Do not modify the `TextureCatalog`, `PNamesTable`, source WAD directory, input patches or saved raw names. Distinguish `TextureCatalog` owner lifetime from output texture image lifetime.
- It is acceptable to decode each patch placement independently for this milestone; **avoid introducing an unbounded cache**. If a bounded private cache is warranted by a measured performance problem, document ownership, invalidation, limits and tests first.

### WAD/index lifetime risk

Before any WAD payload access, verify that a WAD is open and the selected catalog is currently resolved for that WAD **to the extent supported by the existing APIs**. Explicitly test and document stale-index hazards on WAD reopen. If no generation token exists, do **not** claim automatic detection of same-sized/reordered WAD replacement. Prefer a narrowly scoped guard or a documented precondition over a broad refactor of M2-02.

## 6. Input validation and resource budgets

- Reject null/invalid output structure, invalid texture index, unresolved/invalid patch index, absent WAD, zero-sized patch lump, corrupt/truncated patch data and allocation failures with actionable error messages.
- Respect the existing M2-02 definition bounds (dimensions 1..4096, patch counts), but verify `width * height <= 16,777,216` with `.q` **before** allocating **two** pixel planes. The 16M-pixel cap is a project policy, not a Doom format limit.
- Check patch payload size and source buffer allocation bounds; do not trust an index simply because resolution succeeded earlier.
- Do not alter the M1-03 `PatchDecode` safety caps or reinterpret tall-patch relative topdelta semantics; corrupted/later-format input should produce a controlled failure, not a best-effort guess.
- If intermediate decoding fails, release all temporary buffers; preserve the underlying WAD parser's own error details when relevant.
- Never use `PeekS`, string operations, unmanaged C `memcpy`, or struct overlay reads on raw WAD payload bytes to move indexed color data.
- Allocate only validated sizes; avoid per-pixel heap allocation, recursion or large temporary full-WAD copies.
- Ensure error paths do not call an external graphical backend or create windows.

## 7. Test suite — mandatory synthetic cases

Use **original synthetic patches and synthetic WADs** generated by test code; do not copy or reconstruct commercial IWAD assets into the repository. Prefer to extend the existing fixture helpers without changing historical tests merely to fit new APIs. Implement at least the following **30 test categories**; use multiple assertions per case.

| ID | Scenario | Expected behavior |
|---|---|---|
| X01 | One opaque 2×2 patch at (0,0) | Correct row-major indices and full mask |
| X02 | One patch with transparent gaps | Opaque mask only where post pixels exist |
| X03 | Opaque palette index `255` | Index 255 stays opaque |
| X04 | Two patches, same origin, different values | Later opaque pixels win |
| X05 | Later transparent pixels over older opaque | Earlier pixels remain unchanged |
| X06 | Two patches with partially overlapping rectangles | Per-pixel order and mask correct |
| X07 | Negative `originx` | Left clipping works without wraparound |
| X08 | Negative `originy` | Top clipping works without wraparound |
| X09 | Positive origin overflowing right | Right clipping and canary bytes safe |
| X10 | Positive origin overflowing bottom | Bottom clipping and canaries safe |
| X11 | Patch completely outside on every side | Successful no-op, no invalid memory access |
| X12 | Offset with no overlapping rows or columns | Correct no-op; unchanged mask |
| X13 | Signed `PatchImage.LeftOffset/TopOffset` | Never double-applied to texture placement |
| X14 | Non-square texture and patch | Row stride/coordinate mapping correct |
| X15 | Zero and highest valid palette indices | No color remapping or RGB conversion |
| X16 | Width/height of 1 and boundary coordinates | Exact edge behavior |
| X17 | All-transparent patch / empty post columns | No opaque output; deterministic indices |
| X18 | Multiple overlapping patches (3+) | Last opaque placement wins |
| X19 | Same patch lump referenced by several placements | Correct independent coordinates, no leaks |
| X20 | Invalid texture catalog index | Controlled failure before allocation |
| X21 | Unresolved or invalid resolved WAD index | Controlled failure, no stale output |
| X22 | Missing/zero-length referenced lump | Controlled failure and cleanup |
| X23 | Malformed/truncated patch payload in valid WAD | Propagate decoder error, no partial output |
| X24 | Repeated compose / reset / compose | No stale pixels, leak or double-free |
| X25 | Failed compose after earlier success | Output reset/retention matches documented contract |
| X26 | Texture dimensions over pixel budget | Reject without huge allocation |
| X27 | Many patch placements within safe test budget | No integer overflow or wrong ordering |
| X28 | Input patch payload freed immediately after decode | Output still valid and independent |
| X29 | Synthetic WAD with duplicate lump names | Uses last matching lump index resolved in catalog |
| X30 | WAD close/reopen and catalog re-resolution | Explicit invalidation contract; no silent claims of safety |

### Additional verification (recommended)

- Guard/canary bytes around destination planes in a small dedicated test to detect out-of-bounds writes.
- Fully transparent texture with a syntactically valid placement is not silently converted into an opaque background.
- Invalid dimensions or pointer/capacity errors do not cause a crash, even on build without the debugger.
- A fixture with patch internals `LeftOffset=-3, TopOffset=+5` must still place the patch by the TEXTURE definition's `originx/originy` alone.
- Tests must use the **actual existing TextureCatalog/PNAMES/WAD pipeline** for integration, rather than bypassing it with hand-injected fabricated internal pointers.

### Baseline regression acceptance

Rebuild/re-execute every existing test executable and the CLI smoke suite. Historical checks before M2-03 were:

| Subsystem | Previous reported result |
|---|---:|
| M1-01 | 17 cases / 146 assertions |
| M1-02 | 21 / 152 |
| M1-03 | 34 / 197 |
| M1-04 | 24 / 199 |
| M2-01 | 31 / 191 (including synthetic integrations) |
| M2-02 | 33 / 165 (including synthetic integrations) |
| Build/test script checks | 44/44 |

These counts are historical baselines. **Report actual rerun outcomes**, not merely expectations. Add the new `-CompositeTest` or equivalent to Windows and Linux build/test scripts without breaking the existing target flags.

## 8. Ultimate Doom integration — read-only and optional

If the owner-provided `data/DOOM.WAD` exists locally, test **without modifying or exporting** it. Known identification fixture:

```text
DOOM.WAD MD5: c4fe9fd920207691a9f493668e0a2083
Size:         12,408,292 bytes
Lumps:        2,306
TEXTURE1:     9,234 bytes
TEXTURE2:     8,036 bytes
PNAMES:       351 names
Definitions:  287 textures / 980 patch placements (M2-02 report)
```

Integration checks:

1. Open WAD, decode `PNAMES`/`TEXTURE1`/optional `TEXTURE2` and resolve patch indices via existing, tested APIs.
2. Choose **at least three** valid textures to compose: a simple single-patch texture, a multi-patch/overlapping texture and one texture with clipping/sparse coverage **if present**. Determine selections from actual metadata, not guessed resource names. If a category cannot be found in the IWAD, report `NOT APPLICABLE` rather than inventing a case.
3. For each, record texture catalog index, dimensions, placement count, opaque pixel count, and **FNV-1a64 of row-major indices and mask**. Keep checksum byte order and initial seed identical to earlier suites; do not hardcode unmeasured expected hashes.
4. Ensure the known 287 definitions/980 placements continue to decode/resolve successfully. Full *pixel composition of all 287* can be a separate bounded stress test if runtime permits; it should not become a mandatory unbounded memory/cache operation.
5. Verify compositing the same texture twice gives identical checksums and no retained WAD file handles. Compare at least one small synthetic fixture with an **independent** reference compositor (e.g. PowerShell/Python) for an algorithmic cross-check. Do not mistake identical self-derived hashes for independent verification.
6. Re-run `--version` (`0.1.0`), `--dump-info`, `--lump-info` and `--show-title` (including closing the window) to verify no graphics regression.
7. Output **metadata, counts and non-reconstructable hashes only**. Do not log, commit, upload or generate files containing commercial pixels, palette data, patch payloads or full names lists. If debugging needs a local preview, it must be explicitly owner-authorized and remain in an ignored private directory; previews are **not** required for acceptance.

If the IWAD is absent, report **Ultimate Doom integration: NOT RUN** and retain successful synthetic tests as the task's core acceptance gate.

## 9. Build, integration, Git and safety gates

1. Syntax-check the application and every applicable test target with installed PureBasic 6.41; run actual builds of application and test executables.
2. Execute the complete `scripts/test.ps1` on Windows and report actual exit statuses and observed test/ assertion totals.
3. For `.sh` scripts, run `bash -n` if possible; **do not** claim Linux runtime `PASS` unless an actual Linux PureBasic build and tests succeeded.
4. Keep public CLI behavior unchanged. Do not add `--export-texture` or any raw-resource dump option; use tests for introspection.
5. Before reporting success inspect `git status --short --branch`, `git diff --stat`, `git diff --check`, `git diff`, staged changes via `git diff --cached` where appropriate, and check **untracked files** separately because `git diff --check` does not inspect them.
6. No trailing whitespace in changed/new `.md`, `.pb`, `.pbi`, `.ps1`, `.sh`. Preserve LF conventions and existing `.gitattributes`.
7. Ensure `DOOM.WAD`, `data/`, `local-data/`, `build/`, screenshots and derived commercial images, `.exe`, `.dll`, secrets and private absolute paths are not staged or published.
8. Update `README.md`, `docs/PORTING_NOTES.md`, and `CHANGELOG.md` only for actual new behavior and tested limitations; keep documentation in sync with the **0.1.0** version.
9. Do **not** use `git add`, `git commit`, `git push`, create tags/releases, alter Git history or start M2-04 without owner permission.

## 10. Definition of Done

- [ ] Actual M2-02 code and pinned reference inspected; safe implementation plan presented before edits.
- [ ] A texture is composed from existing catalog-resolved WAD lumps and existing patch decoder.
- [ ] Correct origin placement, signed clipping and ordered opaque overwrite are verified with synthetic tests.
- [ ] Palette index 255 stays opaque when mask=1; gaps stay transparent in mask.
- [ ] Internal patch alignment offsets are **not** applied again to texture placements.
- [ ] Output ownership, idempotent reset, failure cleanup and absence of input buffer aliasing are demonstrated.
- [ ] Missing/malformed/stale resources fail safely with useful diagnostics and no unsafe pointer access.
- [ ] All **30** mandatory new synthetic categories pass; historical regressions and CLI pass after real PureBasic 6.41 compilation.
- [ ] Optional real `DOOM.WAD` integration is PASS or explicitly NOT RUN; samples report metadata/checksums only.
- [ ] Git/whitespace/commercial-resource audit completed; changes remain uncommitted/unstaged.
- [ ] Version stays `0.1.0`; no M2-04 work or `v0.2.0` tag.

## 11. Required agent completion report

```text
Task / milestone: M2-03 — composite wall textures
OS / compiler: <observed>; Linux runtime: PASS / FAIL / NOT RUN
Baseline HEAD / Git state: <actual SHA, branch, staged/unstaged/untracked>
Original Doom C symbols inspected: <functions/types, pinned SHA>
Files created / modified: <exact paths>
Public composition API / ownership: <signatures, storage, Reset>
Placement semantics: <order, clipping, mask, palette 255, patch offsets>
Vanilla differences: <row-major output vs column lookup/cache>
Validation and error handling: <behavior and limits>
Syntax / build: PASS / FAIL / NOT RUN — <commands and exit codes>
Previous regression: <observed test counts and assertions>
M2-03 synthetic tests: <X01-X30 cases/assertions, failures>
Optional Ultimate Doom integration: PASS / FAIL / NOT RUN — <metadata and hashes>
Repeated compose / lifetime tests: <results>
TITLEPIC and CLI regression: <observed results>
Git diff / whitespace / resource audit: <results>
Known limitations / technical risks: <list>
Suggested next task: M2-04 — Flats & Sprites (DO NOT START)
```

## 12. References

- [Original Linux Doom 1.10 `r_data.c`](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_data.c): `R_GenerateLookup`, `R_GenerateComposite`, `R_DrawColumnInCache`, `R_GetColumn`.
- [Original Doom source repository](https://github.com/id-Software/DOOM).
- [PureBasic 6.41 official documentation](https://www.purebasic.com/documentation/).
- `docs/DEVELOPMENT_PLAN.md` — M2 criteria; `docs/PORTING_NOTES.md` — actual porting deviations.

---

**This assignment does not declare M2-03 or v0.2.0 complete.** Only real compilation, tests and review can establish completion.
