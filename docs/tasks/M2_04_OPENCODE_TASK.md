# DoomPB — M2-04: Flats, sprite namespaces and sprite frame metadata

> - **Task ID:** `M2-04`
> - **Milestone:** M2 — resources and level loading; `v0.2.0` is **not** complete
> - **Status:** implementation assignment, not an implementation report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Reasoning:** High; escalate only for a concrete difficult defect
> - **Language/compiler:** native PureBasic 6.41, full edition; GPL-2.0-only
> - **Primary platform:** Windows x64; report Linux x64 `NOT RUN` unless executed there
> - **Reference:** `../doom-original`, pinned commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M2-03 accepted and committed; verify rather than assume
> - **Read:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, current source/tests, this assignment

## 1. Objective

Extend the working DoomPB WAD/graphics pipeline with two reusable, strictly validated resource facilities:

1. **Flats:** discover the namespace bracketed by `F_START` / `F_END`; expose stable catalog metadata; decode a vanilla flat as **exactly 64 × 64 = 4096 bytes** of row-major 8-bit palette indices with explicit, independently owned storage.
2. **Sprites:** discover the namespace bracketed by `S_START` / `S_END`; retain raw names, WAD indices and patch metadata; parse the vanilla **4-character sprite ID + frame + rotation** naming convention, including optional second mirrored frame/rotation pair; provide optional validated frame/rotation lookup for a *requested* sprite ID.

Make all access bounds-checked and lifetime-safe. Reuse existing WAD accessors and `PatchDecode()`; do not implement an alternative WAD manager, image decoder, renderer or sprite/game state.

The expected deliverable is **reliable resource metadata and decoded sample resources**, verified by synthetic WAD fixtures and optional read-only tests against the owner's Ultimate Doom 1.9ud IWAD. Do **not** export commercial pixels or names en masse into tracked files.

### Non-goals

- No map (`E1M1`) loading, things/thinkers, movement, 35 Hz game loop or sprite projection.
- No 3D floor/ceiling drawing, visplanes, sky rendering, masked draw columns, translation tables, lighting application, rendering animation or texture caching.
- No PNG/BMP extraction, resource viewer, new permanent screen/UI mode or screenshot publication.
- No PWAD layering, multiple concurrent WAD handles, Boom/MBF namespace generalization or special-port sprite naming extensions.
- No replacement of `TextureCompose`, the existing patch decoder or WAD lookup internals absent a demonstrable regression.
- No change to reported `DoomPB 0.1.0` and no tag/release for M2 yet.

## 2. Inspect real code and upstream before editing

1. Run `git status --short --branch`, `git log -1 --oneline`, `git tag --list`, `git diff --stat`, `git diff --cached --stat`; verify whether M2-03 is actually committed. Preserve any pre-existing staged/unstaged/untracked work. **Do not commit**.
2. Inspect *actual declarations and tests* in `src/WAD/WAD.pbi`, `src/Core/Endian.pbi`, `src/Graphics/Patch.pbi`, `src/Graphics/TextureDefs.pbi`, `src/Graphics/Texture.pbi`, `src/Graphics/Palette.pbi`, `src/DoomPB.pb`, and all current test/build scripts. Do not assume API signatures from prior summaries.
3. Verify pinned upstream SHA using `git -C ../doom-original rev-parse HEAD`. Study `linuxdoom-1.10/r_data.c`: `R_InitFlats`, `R_InitSpriteLumps`, `R_FlatNumForName`, `R_PrecacheLevel`; study `r_things.c`: `R_InstallSpriteLump`, `R_InitSpriteDefs`, `R_ProjectSprite`, and `r_defs.h` (`spriteframe_t`, `spritedef_t`). Consult `w_wad.c` for how names, indices and duplicate entries are handled.
4. Confirm PureBasic 6.41 data types, pointer arithmetic, memory copying, string handling and module include order with the **installed compiler**. A speculative API must first be tried in a small disposable compile check.
5. **Before writing code**, present a short plan covering files, public API, namespace lookup policy, raw name handling, ownership and reset/failure behavior, frame/rotation policy, tests, and limits.

Reference source (inspect at the pinned local checkout first):
- https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_data.c
- https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_things.c

## 3. Flat format and catalog

### 3.1. Vanilla namespace and payload

`R_InitFlats()` obtains `firstflat = W_GetNumForName("F_START") + 1`, `lastflat = W_GetNumForName("F_END") - 1`, and stores the inclusive range. The boundary markers are **not flats** and ordinarily have zero-length payloads.

A vanilla flat's image payload has **no header**: `64 × 64` bytes, one palette index per pixel in row-major order. There is no alpha or patch-style mask. Values **0 through 255 are all valid opaque colors**. The sky marker `F_SKY1` is special to the *renderer*, not a signal to render a wall texture at this stage.

Choose a single explicit policy for standard `F_START/F_END` markers consistent with the current single-WAD API: preferably use existing `WADFindLump()` (last matching marker if duplicated), validate `start < end`, and retain the resulting inclusive indices. Document precise behavior for duplicate, absent, reversed and empty ranges. Preserve physical directory order. Do not silently support alternate Boom namespace variants or conflate arbitrary global lump-name matches with flat names in the discovered range.

For flat lookup by name, clearly distinguish:
- Raw **catalog** lookup among the enumerated flat entries, with a documented duplicate rule (e.g. last matching within the range).
- Vanilla `R_FlatNumForName()` which first resolves a **global** WAD name and subtracts `firstflat`. If your catalog API implements namespace-constrained lookup rather than exact vanilla global semantics, explicitly document the difference; do not claim exact compatibility in cross-namespace name collisions.

For malformed entries, keep **discovery** separate from **image decoding**: catalog enumeration should expose names/sizes without dereferencing arbitrary lumps; decoding a selected flat requires exactly 4096 bytes. Whether a zero-length/non-4096 entry causes catalog failure or only decode failure must be unambiguous and tested. Prefer allowing metadata inspection but rejecting malformed flat payload when decoding.

### 3.2. Suggested design and ownership

Prefer cohesive modules:

```text
src/Graphics/Flat.pbi               # 64x64 pixel decode and owned result
src/Graphics/ResourceNamespace.pbi  # generic bounded marker range ONLY if it reduces duplication
src/Graphics/Sprite.pbi             # sprite catalog and frame/rotation metadata
 tests/unit/wad_flat_sprite_tests.pb # independent synthetic fixtures
```

The shared namespace helper is optional; avoid creating framework abstractions ahead of need.

Suggested conceptual API (**adapt to actual project conventions and valid PB code**):

```text
FlatCatalogBuild(*Catalog) -> boolean     ; discovers F_START ... F_END in open WAD
FlatCatalogReset(*Catalog)
FlatCatalogCount(*Catalog) -> integer
FlatCatalogGetEntry(*Catalog, RelativeIndex, ... rawName, WADIndex, LumpSize) -> boolean
FlatCatalogFindName(*Catalog, Query) -> relativeIndex or -1
FlatDecode(*Bytes, Length.q, *FlatImage) -> boolean
FlatLoad(*Catalog, RelativeIndex, *FlatImage) -> boolean
FlatImageGetPixel(*FlatImage, X, Y) -> 0..255 or explicit error
FlatImageReset(*FlatImage)
FlatLastError() -> string
```

- Caller initializes results to zero once. Catalog and `FlatImage` privately own buffers and do not retain pointers into transient WAD payloads.
- A failed decode/rebuild clears the relevant previous result, releases allocations, and provides a deterministic diagnostic. Reset is safe to call twice.
- Flat pixel indices are **bytes**, not converted RGB; never apply COLORMAP, palette, transparency or resampling.
- Require exactly `4096` bytes to decode. Reject negative lengths, null input, inadequate output or buffer corruption.
- `FlatImageGetPixel(0,0)` refers to byte 0 and `(63,63)` to byte 4095. Row stride is exactly 64, no pitch.
- Read source resource using existing `WADReadLump` into a temporary owned buffer; free it on success and every failure path.
- Use `WADLumpSize` or actual equivalent to validate payload size before allocating/reading; check integer overflow and indices.
- Do not bake an unconditional `DOOM.WAD` path into production source.

## 4. Sprite namespace and individual resource metadata

### 4.1. Discovering the range

Original `R_InitSpriteLumps()` uses `S_START + 1` through `S_END - 1` inclusive. Exclude markers themselves. Use the same **explicit and documented** duplicate/missing/reversed marker policy as flats; never allow an out-of-range `WADLumpInfo` call or negative count allocation.

Enumerate every interior lump and retain:

- exact **raw eight-byte name** (a byte array, never an implicitly NUL-terminated PB string);
- absolute WAD directory index, relative sprite-lump index and source length;
- metadata derived from the name (sprite identifier, frame, rotation, optional mirrored second pair) when valid;
- optional patch header metadata (width, height, signed left/top offsets) read safely for selected resources, without decoding every sprite into permanent memory.

The original `R_InitSpriteLumps()` uses sprite patch header width and offsets to prepare geometry; at M2-04 expose equivalent **integer metadata**. Fixed-point `<<16` conversion and rendering projection belong to M3/M4. Optionally decode a chosen sprite through the existing `PatchDecode()` for an integration test, but do not duplicate that decoder.

Validate source payload size **before** accessing patch header fields; for fully decoded selected sprite, let `PatchDecode()` enforce column/post boundaries. If metadata-only header checks do not validate the full post stream, explicitly say so.

### 4.2. Vanilla sprite lump names

Every standard sprite name occupies up to **8 raw bytes**:

```text
AAAAF0       four-byte sprite ID + frame F + rotation 0 (all angles)
TROOA1       sprite TROO, frame A, rotation 1
TROOA2A8     same payload for A2 and mirrored A8
```

The first **four** bytes select the sprite. Byte 4 encodes the frame; byte 5 encodes the rotation. A second pair in bytes 6 and 7 represents an additional frame/rotation which uses the *same patch with horizontal flip* (for the second pair only). For a six-character name, bytes 6 and 7 should be NUL padding in a canonical IWAD. Do not treat a single nonzero byte 6 with byte 7 absent as a complete pair.

**Match vanilla `r_things.c`, rather than a generic filename parser:** `R_InstallSpriteLump()` accepts frame indices 0..28 (`'A'` through `'A'+28` in the original byte arithmetic), rotations `0..8`; rotations 1..8 correspond to different viewing directions. Standard resources commonly use A..Z; decide and document whether the 26..28 extension is supported, and test the chosen policy. Do not coerce lower-case, non-ASCII, unexpected NULs or arbitrary punctuation into valid names.

A rotation **0** supplies all eight views and conflicts with explicit rotations for that frame. Rotations **1..8** require all eight slots in a *fully validated requested sprite definition*. A paired `A2A8` uses the same WAD lump for both slots, with `flip=false` on A2 and `flip=true` on A8. A paired name may refer to two distinct frames as well as two rotations of the same frame.

Use the source directory index for a sprite resource; **do not accidentally resolve all sprite names via `WADFindLump()`**, which may choose a different duplicate entry. The pinned C has a `modifiedgame`/patching branch; multi-WAD overriding and that branch are out of scope. Record any deliberate difference.

### 4.3. Separate namespace catalog from strict frame assembly

**Do not reject an entire WAD** because a sprite group is incomplete or an unreferenced extra lump has a noncanonical name. Vanilla `R_InitSpriteDefs()` builds frames for *requested* actor sprite IDs, not for arbitrary unreferenced names. Separate:

1. **Catalog scan:** enumerate the range safely. A malformed sprite name or suspect payload is marked invalid/unusable with diagnostics, but does not cause unsafe access or erase unrelated valid entries.
2. **Frame assembly** for a caller-provided 4-byte sprite ID: find matching entries in original directory order; decode each primary/optional secondary name into `(frame, rotation, lump index, flip)`; detect duplicate/conflicting slots; check contiguous frames and complete rotations for the requested sprite. Return a usable independently owned frame table or a clear validation error.

Suggested conceptual API:

```text
SpriteCatalogBuild(*Catalog) -> boolean
SpriteCatalogReset(*Catalog)
SpriteCatalogCount(*Catalog) -> integer
SpriteCatalogGetEntry(*Catalog, SpriteIndex, ... rawName, WADIndex, LumpSize) -> boolean
SpriteCatalogGetPatchInfo(*Catalog, SpriteIndex, *Width, *Height, *Left, *Top) -> boolean
SpriteBuildFrames(*Catalog, SpriteID, *FrameSet) -> boolean
SpriteFrameGet(*FrameSet, FrameIndex, Rotation1To8, *WADIndex, *Flip) -> boolean
SpriteFrameSetReset(*FrameSet)
SpriteLastError() -> string
```

The symbols are **suggestions**, not mandatory exact signatures. Frame results own their numeric slots/flags, not WAD payload pointers. Document frame count and how frame index/rotation arguments are represented (e.g. index `0` for A, requests for rotations `1..8`). Invalid/out-of-range access must fail deterministically.

Potential compatibility nuance: the original `R_InitSpriteDefs()` has `modifiedgame` handling for the first pair only. Do not generalize that behavior to unsupported multi-WAD overlays or claim complete patched-WAD equivalence; basic single-IWAD directory mapping is the acceptance target.

## 5. Lifetime, budgets and failure policy

- Limit catalog entries to actual bounded WAD directory ranges and cap additional allocations conservatively (e.g. 65,536 entries per category), documenting the chosen limit. Never allocate from untrusted counts before checking arithmetic in `.q`.
- Names are stored as **eight bytes**. Byte comparisons are explicit; printable display names are diagnostics only and may escape invalid bytes.
- Respect signed offset fields in sprite patch header. No postprocessing of left/top origin in a metadata-only query.
- All WAD directory indices and range metadata become **stale after WAD close/reopen**; follow the established explicit invalidation/rebuild convention, or introduce a safe generation check if it is narrowly scoped and does not break other modules. Tests must exercise reuse after reopening a different WAD.
- Borrowed WAD input bytes may be released immediately after successful decode; decoded results must remain usable.
- Every failing decode, build, lookup or allocation must return a helpful error without stale or partially initialized output.
- Flat pixel index 255 is valid. Sprite patch pixel index 255 is opaque if the existing `PatchDecode` mask says it is.
- No crash, out-of-bounds access, double free, memory leak or partial write even on malformed synthetic input.
- Avoid unnecessary copies of all sprite pixel payloads: metadata catalog may remain lightweight; decode on demand.
- Do not introduce network access or new third-party dependencies.

## 6. Required tests — synthetic fixtures, no commercial data

Create `tests/unit/wad_flat_sprite_tests.pb` (or architecture-consistent name), with **at least 36 uniquely reported cases**, distributed as F01–F16 and S01–S20. Implement each case as a real assertion-driven test, not an empty label. All fixtures must be generated from synthetic bytes in temporary ignored/build locations.

### Flat tests F01–F16

| ID | Required case |
|---|---|
| F01 | Discover exact `F_START`/`F_END` boundaries; exclude both markers |
| F02 | Flat count and returned WAD indices preserve physical directory order |
| F03 | Decode exactly 4096 bytes; verify dimensions and row-major corners |
| F04 | Palette index 255 is a legal opaque flat color |
| F05 | Reject short input (including 0 and 4095) without reading beyond buffer |
| F06 | Reject long input (4097+) according to exact-size contract |
| F07 | Reject null input, invalid output or negative length safely |
| F08 | Reject invalid pixel coordinates and catalog indices |
| F09 | Owned image remains valid after temporary source buffer release |
| F10 | Reset twice and repeated decoding are safe; failure clears prior image |
| F11 | Missing `F_START`, missing `F_END` and reversed markers fail clearly |
| F12 | Empty marker range behavior is explicit and safe |
| F13 | Duplicate marker selection follows documented WAD lookup policy |
| F14 | Raw 8-byte names preserved; flat name lookup handles duplicates deterministically |
| F15 | Zero-length or wrong-size interior entry is rejected at decode, without crash |
| F16 | WAD close/reopen forces explicit catalog rebuild; no stale resource use |

### Sprite tests S01–S20

| ID | Required case |
|---|---|
| S01 | Discover `S_START`/`S_END` range, exclude markers, preserve order |
| S02 | Missing/reversed/duplicate markers and empty range behave as specified |
| S03 | Raw eight-byte names retained exactly, including NULs and odd bytes |
| S04 | Canonical six-byte `TROOA0` maps frame A to all 8 rotations |
| S05 | Canonical `TROOA1` maps only rotation 1 before completeness validation |
| S06 | Paired `TROOA2A8`: same lump, primary unflipped, secondary flipped |
| S07 | Paired name referencing two different frames maps both correctly |
| S08 | Eight explicit rotations form one valid complete frame |
| S09 | Incomplete 1..8 rotations fail **requested frame assembly**, not catalog scan |
| S10 | Conflict between rotation 0 and explicit rotations fails deterministically |
| S11 | Duplicate rotation or duplicate rotation-0 registration fails clearly |
| S12 | Missing intermediate frame fails requested assembly; unrelated sprites survive |
| S13 | Bad primary frame bytes or bad rotation bytes marked invalid safely |
| S14 | Malformed secondary pair (half present, invalid frame/rot) rejected safely |
| S15 | Header read returns correct positive width/height and signed left/top offsets |
| S16 | Too-short/zero-length patch cannot be inspected as valid header |
| S17 | Selected synthetic sprite successfully decodes through existing PatchDecode |
| S18 | Invalid sprite catalog indices and frame/rotation getters fail safely |
| S19 | FrameSet reset/rebuild and output lifetime are deterministic; no aliasing |
| S20 | Duplicate lump names elsewhere in WAD do not redirect original catalog index; reopen invalidates catalog |

If needed, add more cases for 29-frame bound, byte-255 sprite transparency mask, frame 0/8 conflicts, or namespace marker prefix collisions. Report exact case/assertion counts **as observed**, not as predicted.

### Synthetic integration I01–I03

1. **I01:** Construct an in-memory synthetic IWAD with both marker ranges, two 4096-byte flat payloads, and several synthetic sprite patches. Discover both catalogs using the existing WAD API; verify counts, names, read paths and one frame mapping.
2. **I02:** Construct missing/malformed namespace boundaries, a wrong-size flat and short sprite; verify clean failure/diagnostics and no crash or stale resources.
3. **I03:** Open WAD A, create catalogs/frames and decode an image; close A, open different WAD B, explicitly rebuild/re-resolve, and verify fresh indices plus the independently owned old decoded image.

Use synthetic fixtures only; no IWAD redistribution, no copyrighted pixel dumps.

## 7. Optional read-only Ultimate Doom integration I04

Use the owner's local `data/DOOM.WAD` **only if present**. Known identification fixture: 12,408,292 bytes, 2306 lumps, MD5 `c4fe9fd920207691a9f493668e0a2083`. Report `NOT RUN` if absent, not a failure for synthetic CI.

1. Open the IWAD through existing API; locate vanilla `F_START/F_END` and `S_START/S_END` markers; record actual start/end indices, counts and sizes **as observed**, not guessed. Do not assert fabricated flat/sprite counts.
2. Verify the resource ranges are ordered, exclude markers, and cannot read out of bounds. Validate selected flats of length 4096 and decode them; compute non-reconstructable checksums and a few numeric pixel values if useful.
3. Inspect several selected canonical sprite names/headers, optionally build frames for an **observed, actually present** sprite ID and decode one selected patch via `PatchDecode()`. Do not require every arbitrary sprite ID in the namespace to be a fully valid game actor.
4. If possible, compare counts/header offsets against an **independent reader** or pinned vanilla source interpretation; document any discrepancies.
5. Release everything, verify `data/DOOM.WAD` remains unmodified, and do not save or publish any full commercial images, sprites, flat byte dumps, screenshots or extracted WAD payloads.

**Important:** `R_InitSpriteDefs` is driven by an explicit game sprite-name list. A catalog of all raw entries and a strict requested-name frame constructor are two different tasks; a strict check of every discovered prefix is *not* a valid acceptance criterion here.

## 8. Build/test integration and CLI regressions

- Extend the existing `scripts/build.ps1`, `scripts/build.sh`, `scripts/test.ps1`, and `scripts/test.sh` **according to their actual options** to include this test executable in the established sequence. Keep every prior target functioning; do not duplicate test runners or change unrelated script interfaces.
- Run application and new-test `pbcompiler --check` using installed PureBasic 6.41, then build and **execute** the tests. `--check` alone does not satisfy the acceptance gate.
- Rerun **all** M0/M1, M2-01, M2-02 and M2-03 tests; compare actual cases/assertions with the previously reported baselines: M1 96/694, M2-01 31/191, M2-02 33/165, M2-03 30/141. Script checks M2-03 baseline 48/48. If counts legitimately change, explain why; never mechanically edit expected totals to hide failures.
- Verify application `--version` still emits `DoomPB 0.1.0` with exit 0; `--dump-info`, `--lump-info` and `--show-title` still work. If window visual review is needed, use the previously proven read-only client-area screenshot method; do not commit a screenshot.
- Run `bash -n scripts/build.sh scripts/test.sh`; this **does not** mean the Linux runtime passed. If Linux compiler/execution is unavailable, report `NOT RUN`.
- No new public CLI mode is required. Favor a test-only integration mode; do not turn application startup into an expensive scan of every sprite/flat.
- Maintain existing deterministic exit code behavior for malformed WADs and syntax errors.

## 9. Documentation, git hygiene and licensing

- Update `README.md`, `docs/PORTING_NOTES.md` and `CHANGELOG.md` with **observed** M2-04 functionality, limits, differences from vanilla, test numbers and Linux status. Preserve previous historical milestone entries; M2 remains in progress.
- Explicitly document: exact-size flat decode, namespace marker selection, name lookup policy, raw sprite names, rotation-0 versus rotations-1..8, paired-name horizontal flip, optional strict requested-sprite validation, and stale-WAD-index lifecycle.
- Document that `F_SKY1` remains a semantic sky sentinel for later renderer work, not a reason to generate sky pixels here.
- Inspect `git diff --stat`, `git diff`, `git diff --check`, `git diff --cached --check`, `git status --short`; include **new/untracked source files** in the whitespace audit since ordinary diff does not show them. No trailing blanks/tabs in `.pb`, `.pbi`, `.ps1`, `.sh`, `.md`, including Markdown.
- Preserve `.gitignore` protection for `*.wad`, `*.WAD`, `build/`, `data/`, `local-data/`. Commercial IWADs, derived images, binaries, captured screenshots, local absolute paths and unrelated artifacts must **never** be staged.
- No destructive git operations, sweeping formatting changes, additional dependencies, release tag, commit, push or Git staging by the agent.

## 10. Acceptance criteria / Definition of Done

M2-04 is accepted for Windows x64 only when all conditions hold:

1. Flat and sprite namespace boundaries are found reliably without including marker lumps; missing/duplicated/reversed marker policy is documented and tested.
2. Selected 4096-byte flats decode into owned 64×64 indexed pixels without scaling, masking or RGB conversion; malformed sizes fail safely.
3. Sprite entries preserve raw 8-byte names, original WAD indices and bounded patch header metadata.
4. Six-byte and paired eight-byte sprite names map correctly into frame/rotation/flip metadata. Requested actor frame validation catches duplicate, inconsistent and missing rotations without rejecting an unrelated valid entry.
5. Owned outputs survive release of input byte buffers. Catalog index invalidation after WAD reopen is respected and tested.
6. Synthetic F01–F16, S01–S20 and I01–I03 run and pass; optional I04 gives real counts/hashes if the user's IWAD is available.
7. The complete previous test suite compiles, runs and passes on Windows x64 using the actual PureBasic 6.41 compiler. CLI and TITLEPIC regressions pass.
8. Documentation updated; project still reports version **0.1.0** and **M2 remains incomplete**. No proprietary game data in Git.
9. No build/lint/whitespace regressions; current worktree safely preserved; no git commit/tag/push performed.

**Do not start M2-05 or M2-06.** Loading map objects is a separate bounded implementation task.

## 11. Final agent report — required structure

```text
Task / milestone:
OS / compiler and exact version:
Baseline HEAD / branch / staged-unstaged-untracked:
Pinned Doom reference and C functions actually inspected:
Files created / modified:
Flat namespace and decoder API / ownership:
Sprite catalog, frame mapping and flip semantics:
Error handling / limits / lifecycle / vanilla differences:
Syntax checks: PASS / FAIL / NOT RUN (commands, codes)
Build: PASS / FAIL / NOT RUN (commands, codes)
Previous M0/M1/M2 regression: cases, assertions, script checks
New F01–F16, S01–S20: exact cases, assertions, failures
Synthetic integrations I01–I03:
Ultimate Doom read-only integration I04: observed counts/indices/hashes, or NOT RUN
TITLEPIC / CLI regressions:
Linux runtime: PASS / FAIL / NOT RUN (not bash -n)
Git diff / whitespace / commercial-data audit:
Known limitations, compatibility risks and owner verification needs:
Suggested Conventional Commit message (do not commit):
Next task: M2-05 (DO NOT START)
```

**Verification rule:** never report a successful visual/run/test result that the agent did not actually observe. If the toolchain cannot run the necessary binary or access the WAD, state exactly what was not run. Scope ends with this report.
