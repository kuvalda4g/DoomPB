# DoomPB — M2-07: M2 integration, acceptance and v0.2.0 preparation

> - **Task ID:** `M2-07`
> - **Milestone:** M2 — Resource loading, texture composition and validated vanilla maps
> - **Status:** Implementation/release-preparation assignment; **not** a report of completed work
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Reasoning:** High; increase only for a specific blocking defect or source-compatibility question
> - **Language / compiler:** PureBasic 6.41 full edition
> - **Primary test platform:** Windows x64
> - **Linux x64:** `NOT RUN` unless a native Linux PureBasic compiler and executable were actually used
> - **Engine license:** GPL-2.0-only; all commercial IWAD resources remain local
> - **Original engine reference:** `../doom-original`, pinned commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M2-06 committed by the owner; verify actual Git state, do not assume a commit hash
> - **Read first:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, current code/tests, then this task

## 1. Objective and Definition of Done

Close milestone **M2** on the existing Windows x64 development platform. Prove that the components implemented during M1 and M2-01…M2-06 form a consistent, safe, deterministic, read-only resource-and-map pipeline. Resolve any small release-blocking integration defects, extend focused regression tests, update version and release documentation **only after the integration gates pass**, and prepare a reviewable `v0.2.0` change set for owner-controlled commit and annotated tag.

The accepted behavior is:

1. Open the owner's legal Ultimate Doom 1.9ud IWAD through the existing WAD reader.
2. Decode `PLAYPAL`, `COLORMAP`, `PNAMES`, `TEXTURE1`, optional `TEXTURE2`, flat and sprite namespaces, and assemble representative/all vanilla wall textures using the already implemented APIs.
3. Load and cross-validate maps `E1M1`, `E1M2`, and `E4M1`, including the ten canonical map lumps, BSP, `REJECT`, and `BLOCKMAP`.
4. **Actually call** `MapLevelValidateResources` (or its current equivalent) to verify that each applicable map's referenced flats and wall textures are present in the loaded resource catalogs; report errors or explicit skip rules, not just record counts.
5. Verify ownership/lifetime, error recovery, repeated map loads, data determinism, resource invalidation on WAD reopen, and old CLI behavior.
6. Run the full Windows syntax/build/test suite and update `DoomPB --version` from `0.1.0` to **`0.2.0`**, once the M2 Windows acceptance gates are met. Update corresponding test expectations and documentation.
7. Leave release commit/tag creation, staging, push and publication **to the owner**.

**M2 does not mean the game is playable or that map geometry is rendered.** The title window remains the only GUI rendering proof. M3 will introduce fixed-point geometry, runtime BSP traversal and visible walls; M4 will expand to flats, sky and sprites.

### Explicit non-goals

- No wall/plane/sprite renderer, raycaster, BSP drawing, 35 Hz gameplay loop, thinker/AI/physics, sound, savegames or playable E1M1.
- No multi-WAD/PWAD overlay system, unsupported UDMF/Hexen/GL formats, full resource cache redesign, texture animation or shader backend.
- No destructive refactor of working M1/M2 modules, compiler upgrades, packaging commercial game data or rewriting the pinned C engine.
- No obligatory new CLI verbs if equivalent test-only metadata diagnostics are sufficient. Avoid unrelated UI changes.
- Do **not** implement deferred `LumpCache.pbi`, original Doom column cache or sector bounding boxes merely to tick a roadmap box; assess and document whether they are essential to the accepted M2 behavior. Keep M3 work in M3.

## 2. Discover current state before writing code

1. From the repository root run `git status --short --branch`, `git log -1 --oneline`, `git diff --stat`, `git diff --cached --stat` and `git tag --list`. Verify M2-06 is committed; earlier report's HEAD `2fb2481` was *before* M2-06 and must not be assumed current. Preserve any user edits or staged work. Do not stage files.
2. Read milestone M2's **actual** checklist and acceptance wording in `docs/DEVELOPMENT_PLAN.md`; identify implemented/deferred/partial entries. Read `AGENTS.md` including legal, ownership, compiler verification and Git requirements.
3. Inspect **actual** signatures and state contracts, not approximations from earlier reports, for:

   - `src/WAD/WAD.pbi`, `src/Core/Endian.pbi`;
   - `src/Graphics/Palette.pbi`, `Colormap.pbi`, `PNames.pbi`, `Patch.pbi`, `TextureDefs.pbi`, `Texture.pbi`, `Flat.pbi`, `Sprite.pbi`, `FrameBuffer.pbi`, `Video.pbi`;
   - `src/Map/MapTypes.pbi`, `MapDecode.pbi`, `Blockmap.pbi`, `MapLevel.pbi`, `MapLoader.pbi`, `MapValidate.pbi`;
   - `src/DoomPB.pb`, `README.md`, `CHANGELOG.md`, `docs/PORTING_NOTES.md` and any existing `docs/TESTING.md`;
   - every test source and `scripts/build.ps1`, `build.sh`, `test.ps1`, `test.sh`.

4. Verify the pinned upstream reference `git -C ../doom-original rev-parse HEAD`. Inspect original `p_setup.c` (`P_SetupLevel`, `P_GroupLines`), `r_data.c` (`R_InitTextures`, `R_InitFlats`, `R_InitColormaps`, `R_GenerateComposite`) and `r_things.c` as needed. Use source references for *actual compatibility questions*, not speculative rewriting.
5. Establish the compiler version using the actual toolchain, including how scripts locate `pbcompiler`. Inspect existing tests/fixtures before deciding whether any new harness or flags are necessary.
6. Before making edits, report a short implementation plan: audited acceptance gaps, files to touch, integration harness strategy, hard failure versus documented limitation, test cases, version bump conditions and rollback/cleanup handling.

### Historical baseline for regression (rerun, do not claim automatically)

| Existing subsystem | Previously observed cases | Previously observed assertions |
|---|---:|---:|
| M1-01…M1-04 | 96 | 694 |
| M2-01 COLORMAP/PNAMES | 31 | 191 |
| M2-02 TEXTURE definitions | 33 | 165 |
| M2-03 composite textures | 30 | 141 |
| M2-04 flats/sprites | 39 | 300 |
| M2-05 map binary decoders | 51 | 190 |
| M2-06 map loader | 55 | 167 |
| **Total before M2-07** | **335** | **1848** |

Last reported Windows script checks: **60/60**. M2-06 `--map-info E1M1/E1M2/E4M1`, the `--show-title` window and `--version` all passed on Windows. These are **reported prior results**, not the result of this task.

## 3. Architecture: prefer integration, not duplicated parsing

Use existing public APIs as the only path for loading and validating resources. A small test-only integration helper may orchestrate them; do not create a second WAD parser, map parser, texture decoder or independent copy of business logic.

Recommended test placement (adapt to existing repository patterns):

```text
tests/integration/m2_release_tests.pb         # preferred if build harness supports it
# or tests/unit/wad_m2_integration_tests.pb   # acceptable for current harness
scripts/build.ps1 / build.sh                  # add a narrow test target only if needed
scripts/test.ps1 / test.sh                    # discover/compile/run that target
src/DoomPB.pb                                 # 0.2.0 version; only necessary CLI fixes
README.md
CHANGELOG.md
docs/PORTING_NOTES.md
docs/DEVELOPMENT_PLAN.md                     # status/checklist truthfully updated
```

**Minimal production edits only when a test reproduces a real bug** (e.g. stale indices, lifetime error, bad resource skip behavior). Avoid adding a broad new `ResourceManager` module solely for release testing. The M2 architecture may use explicit WAD generation invalidation until a later, scoped change is approved.

### State/ownership contract to verify

- Opening WAD creates the current directory. Catalogs and resolved texture references may contain **WAD indices** tied to that directory; they must be invalidated/rebuilt if WAD is closed/reopened.
- Decoded palettes, patches, flats, composed textures and map-record arrays own their own memory and remain valid after temporary raw-lump buffers are freed.
- `MapLevel` owns its decoded records and **within-map derived indices**; these must remain valid after WADClose, independent of resource-directory indices.
- `MapLevelLoad` is transactional: on failure it must not leave a partially valid level or stale derived links. Repeated load/reset must release all old ownership.
- `TextureCatalog` must not silently reuse resolved WAD indices after a reopen. A documented explicit `InvalidateResolved` + `Resolve` sequence is acceptable; test it as an invariant.
- Do not shallow-copy pointer-owning PureBasic structures, retain pointers into temporary buffers, or assume WAD indices stay stable across opens.

## 4. End-to-end integration sequence

Provide a reusable **test-only** orchestration that executes approximately the following sequence, adapted to *actual* PureBasic APIs and required include order:

```text
WADOpen(owner-provided path)
  -> WAD directory sanity; lookup required lumps
  -> PLAYPAL and COLORMAP (raw indexed data)
  -> PNAMES
  -> TEXTURE1 and optional TEXTURE2 -> TextureCatalog -> Resolve referenced patches
  -> FlatCatalog + SpriteCatalog from marker namespaces
  -> representative/all TextureCompose checks, FlatLoad and Sprite frame checks
  -> MapLevelLoad("E1M1") -> validate references, BSP, REJECT, BLOCKMAP
  -> MapLevelValidateResources(level, flat catalog, texture catalog) [actual API]
  -> repeat for "E1M2", "E4M1"; check deterministic counts/hashes
  -> release temporary images, level, catalogs; close WAD
```

The loading order may differ where APIs require it. Do **not** retain pointers to raw payloads or leave a short-circuit on error without freeing all initialized resources. The integration must be **read-only** with respect to the IWAD.

### Texture and flat binding rules

1. Resolve sector `floorpic` and `ceilingpic` names through the existing flat catalog, using bounded 8-byte names. Treat `F_SKY1` as a normal valid flat name for **resource binding**; sky rendering semantics are for M4.
2. Resolve `SIDEDEFS` upper, lower and middle wall texture names through the combined texture definitions (`TEXTURE1` then `TEXTURE2`); use their **first matching definition**, while WAD lump lookup retains last-match semantics.
3. Skip canonical no-texture sentinel `"-"` according to the existing validator's documented 8-byte handling. All-NUL names may be a documented empty/unused slot; **do not** interpret an embedded NUL followed by printable characters as an ordinary valid name.
4. Do not require every side slot to be used by a particular geometry configuration merely to accept a vanilla map; verify the policy against `P_LoadSideDefs` and existing M2-06 behavior. But do **not** silently skip a genuinely referenced unknown texture or flat.
5. Differentiate: `missing name`, `invalid name`, `name found but resource corrupt`, and `resource not applicable`. Include map name, record index and field in diagnostics; avoid printing long copyrighted name lists.
6. Do not eagerly decode all sprite patches or pretend that sprite ID metadata automatically implies a complete set of actor runtime definitions. Check a small valid sample through `PatchDecode` where appropriate.
7. Preserve flat/sprite namespace limits and the explicit marker entries described in M2-04. An interior zero-length marker is metadata, **not** a 4096-byte flat.
8. Ensure the whole pipeline behaves correctly after a WAD reopen even if directory indices change. Fresh resolution is required; existing owned map geometry may remain valid.

### Optional map report

Keep the existing `--map-info` behavior and exit codes `0` success, `1` runtime/bad data and `2` bad usage. If an **optional**, backwards-compatible resource-summary flag is useful, make it metadata-only and separately tested; do not turn release integration into a large CLI rewrite.

For M2 acceptance, an E1M1 technical report must include counts for geometry, BSP, REJECT, BLOCKMAP and **summary of resolved referenced flats/wall textures**. Report distinct counts, missing counts and perhaps a very small non-reconstructable diagnostic sample. If `docs/DEVELOPMENT_PLAN.md` requests a named texture list, it may be a **local opt-in CLI view**; do not commit a full exported content listing or commercial data to the repository.

## 5. Fixed known-IWAD integration fixture (read-only)

Known owner-supplied GOG Ultimate Doom 1.9ud fixture (do not distribute):

```text
Filename (locally): data/DOOM.WAD
Size:               12,408,292 bytes
MD5:                c4fe9fd920207691a9f493668e0a2083
WAD directory:      2,306 entries
PLAYPAL:            14 palettes; 10,752 bytes
COLORMAP:           34 maps; 8,704 bytes
PNAMES:             351 names; 2,812 bytes
TEXTURE1:           9,234 bytes
TEXTURE2:           8,036 bytes
Texture catalog:    287 definitions; 980 patch placements
Wall compositions:  287/287 previously passed
F_START/F_END:      2193/2305; 107 valid flat payloads
S_START/S_END:      1068/1833; 764 interior sprite entries
```

Only apply **exact fixture expectations** after checking the actual file's MD5. Other legitimate IWAD versions must not be rejected simply because hashes differ. If the local file is absent, optional commercial-IWAD integration is `NOT RUN`, **not a substitute for synthetic CI tests**.

Known prior level metadata:

| Field | E1M1 | E1M2 | E4M1 |
|---|---:|---:|---:|
| Map marker index | 7 | 18 | 304 |
| Things | 143 | 262 | 141 |
| Linedefs | 486 | 1033 | 471 |
| Sidedefs | 666 | 1323 | 642 |
| Vertexes | 470 | 942 | 439 |
| Segs | 747 | 1463 | 695 |
| Subsectors | 239 | 448 | 196 |
| Nodes | 238 | 447 | 195 |
| Sectors | 88 | 200 | 81 |
| REJECT bytes | 968 | 5000 | 821 |
| BLOCKMAP cells | 828 | 1302 | 162 |
| BSP root node | 237 | 446 | 194 |

The recorded level counts and hashes are **regression evidence**, not substitutes for cross-resource binding or runtime tests. A single successful `--map-info` run without resource catalogs does **not** prove M2-07 integration.

For deterministic checksums:

- Build a canonical little-endian test-only sequence from selected **metadata** (record counts, stable map links, selected indices and bounds); hash it using an established FNV-1a64 helper if one exists. Document exact order and types in the test. Do not hash pointers, allocation addresses, randomized timestamps, platform-dependent native PB structure bytes or padding.
- Compare two independent loads of the **same IWAD version**; report the resulting checksum. If recording new fixed expectations, first verify computation independently; do not invent a golden value.
- Previously observed composed texture hashes may be reused only if their original byte ordering and mask inclusion are verified. Otherwise report new hashes as diagnostics without declaring a false regression.
- **Never** save or commit full game textures, decoded map records, raw WAD bytes, screenshots or other reconstructable proprietary data.

## 6. Synthetic regression matrix — 32 required scenarios

Implement **E01–E32** as focused, independently reportable scenarios. Reuse existing synthetic-WAD builders and test harness conventions; avoid duplicating a huge fixture generator if an existing helper suffices. Test names/counts may be adapted slightly if actual project design requires it, but maintain the checked behaviors. Each scenario must have assertions and a clear PASS/FAIL result.

| ID | Required behavior |
|---|---|
| E01 | Synthetic valid WAD: basic WAD directory → PNAMES + TEXTURE1 → catalog resolution → compose small wall texture. |
| E02 | Synthetic valid WAD: flat namespace with one exact 4096-byte flat, `FlatLoad` and owned pixels. |
| E03 | Synthetic valid WAD: sprite namespace and strict frame/rotation selection; paired flip handling. |
| E04 | Integrated valid one-map fixture: all ten adjacent map lumps decode/load and BSP validates. |
| E05 | Full minimal resource binding of sector floor/ceiling flat and sidedef wall textures. |
| E06 | Correct `-` no-texture sentinel and optional all-NUL empty wall slot behavior; no false lookup. |
| E07 | Invalid referenced flat name fails resource binding with field/record diagnostic. |
| E08 | Invalid referenced wall texture fails resource binding with field/record diagnostic. |
| E09 | Embedded-NUL/nonprintable resource name is rejected without unsafe truncation. |
| E10 | Texture first-definition precedence preserved for same name in TEXTURE1 and TEXTURE2. |
| E11 | Patch WAD lump last-match precedence preserved in resolved compositing. |
| E12 | Flat namespace lookup does not select a same-name lump outside its namespace. |
| E13 | WAD A opened; catalogs resolved; load/compose a resource and map successfully. |
| E14 | After WADClose, owned decoded map records and already composed images remain readable. |
| E15 | After opening WAD B, old resolved WAD indices are explicitly invalidated and cannot be used as valid references. |
| E16 | Rebuild/re-resolve on WAD B produces B's data rather than stale A resource data. |
| E17 | Reopen WAD A + fresh resolution restores the prior deterministic results. |
| E18 | Repeated MapLevelLoad/MapLevelReset cycles do not leak or double-free and always leave a consistent state. |
| E19 | Late MapLevelLoad validation failure after prior success clears the target and derived links. |
| E20 | MapLevelValidateResources failure does not mutate source data; cleanup remains correct. |
| E21 | Missing, misordered or nonzero-sized map marker fails cleanly, no partial level. |
| E22 | Invalid linedef/sidedef/seg/subsector references fail before unsafe use. |
| E23 | Cyclic BSP fails deterministically; a valid BSP still reloads successfully afterwards. |
| E24 | REJECT too short or BLOCKMAP line index out of range fails cleanly. |
| E25 | Missing/corrupt required PNAMES or TEXTURE1 yields explicit failure and no stale catalogs. |
| E26 | Present-but-malformed TEXTURE2 is rejected; absent TEXTURE2 remains valid. |
| E27 | Malformed referenced patch fails compositing; temporary payloads and output released. |
| E28 | Interior zero-length flat marker can be catalogued but not decoded as a valid flat. |
| E29 | Two identical valid synthetic loads yield the same canonical metadata checksum. |
| E30 | Test does not rely on pointer size, native structure packing or traversal order of hash maps. |
| E31 | Legacy `--show-title`, `--dump-info` and `--lump-info` remain behaviorally unchanged. |
| E32 | CLI missing IWAD/map or conflicting options returns documented `1/2`, without crash or resource leak. |

**Test-design notes:**

- Keep commercial-data tests separate from the synthetic fixtures. The CI test suite must be runnable without `DOOM.WAD`.
- Do not treat E31/E32's console smoke invocations as a substitute for actual unit assertions. Match current scripts' exit-code conventions.
- Where a strict existing M2-06 validation policy rejects a synthetic fixture, fix the **fixture** if it is invalid; fix production only when a demonstrated valid vanilla case fails.
- If E15 cannot be directly observed because the API intentionally requires caller invalidation, prove the contract by explicit invalidation + failure/refresh, and report that stale-index protection is **caller responsibility**. Do not silently claim automatic detection.
- Keep memory usage bounded and prevent arbitrary untrusted WAD lengths from reaching unchecked allocation.
- Empty sets, zero-length markers and sentinel handling must match actual documented APIs and recorded intentional deviations from vanilla.

### Additional integration cases

Run and report separately:

- **I01:** Synthetic full resource-and-map pipeline; all ten map lumps plus referenced textures/flats pass together.
- **I02:** Synthetic failure/recovery with missing or damaged referenced texture/flat; no partial state or old WAD-index reuse.
- **I03:** Repeated A→B→A synthetic WAD lifecycle; deterministic metadata and independent owned data.
- **I04 (optional real IWAD):** Load the owner-provided Ultimate Doom file, verify `E1M1`, `E1M2`, `E4M1`, run full `MapLevelValidateResources` and record resource-resolution summary plus stable checksums.

If the existing test runner has equivalent checks already, reuse and extend it rather than duplicating the entire old suite. Count **actual** cases and assertions in the final report, not planned numbers.

## 7. Release acceptance checklist and version bump

### Gate A — integration correctness

- [ ] All 32 required synthetic cases and I01–I03 pass.
- [ ] Optional I04 passes against the known user's IWAD if available; report `NOT RUN` if absent.
- [ ] `MapLevelValidateResources` is genuinely executed with both flat and texture catalogs for all three known maps (not only parsing). Record resolved/ignored/failed counts by resource class.
- [ ] WAD → graphics catalog → texture composition → map validation can be completed in one process with correct cleanup.
- [ ] Identical inputs give deterministic metadata hashes; old-index invalidation and ownership are verified.
- [ ] All pre-existing regression suites remain green, including the TITLEPIC visual path's existing automated checks.

### Gate B — Windows build and CLI compatibility

- [ ] `scripts/build.ps1 -Check`: PASS, real PureBasic 6.41 compiler.
- [ ] `scripts/build.ps1`: PASS and creates a working `DoomPB.exe`.
- [ ] `scripts/test.ps1`: PASS with exact observed cases, assertions, script-check totals and exit codes.
- [ ] Run `--help`, `--version`, `--dump-info`, `--lump-info`, `--show-title`, `--map-info E1M1` and selected invalid-input checks.
- [ ] Ensure `--show-title` window still closes normally and does not require M3 rendering components.
- [ ] For `--map-info`, report the level and geometry/BSP/REJECT/BLOCKMAP data without dumping content blobs.

### Gate C — release metadata/documentation

After **A and B pass**, and only then:

1. Bump the application's reported version to `0.2.0` in the correct single source of truth (previously `#DoomPB_Version` in `src/DoomPB.pb`). Update *all actual* build/test script expectations and `--help` behavior.
2. Run build/tests again after the version change. Verify literal console output `DoomPB 0.2.0` with exit `0`.
3. Update `README.md`: project status `v0.2.0` **prepared**, supported OS, CLI examples, M2 capabilities, known limitations, local IWAD usage, no gameplay/rendering and optional resource diagnostics.
4. Add/update the **Unreleased or 0.2.0** section in `CHANGELOG.md`: M2-01…07 capabilities and documented limitations. Do not imply Git tag exists until the owner creates it.
5. Update `docs/PORTING_NOTES.md` with verified C correspondences and differences: raw resource models, row-major composition vs vanilla columns, namespace lookup, safety caps, single-WAD restriction, explicit invalidation after reopen, missing cache and lack of Linux runtime validation.
6. Update M2 status in `docs/DEVELOPMENT_PLAN.md` **truthfully**. Distinguish features complete for the present single-IWAD Windows goal from delayed items (e.g. generic LumpCache, original renderer-column cache, support for overlays). Do not mark an unimplemented feature complete merely because the release passes.
7. If `docs/TESTING.md` or `docs/COMPATIBILITY.md` exists, update observed statuses without creating unnecessary new documentation files.
8. **Windows x64 tested; Linux x64 NOT RUN** unless Linux compiler and runtime checks actually occurred. Do not label `bash -n` PASS when no working shell was available; do not equate Bash syntax checking with Linux build success.
9. Preserve GPL-2.0-only license and local-only IWAD policy. The `data/`, `local-data/` and `build/` directories must remain ignored.

**If A/B fail:** fix a verified release blocker narrowly and rerun; otherwise leave version at `0.1.0` and mark `v0.2.0` as **BLOCKED**, explaining the exact issue. Never pretend a planned check was run.

### Gate D — Git safety and owner handoff

- [ ] `git diff --check` and `git diff --cached --check` return 0.
- [ ] Verify **untracked** `.pb`, `.pbi`, `.ps1`, `.sh`, `.md` for trailing spaces/tabs; these are not covered by `git diff --check` until tracked.
- [ ] Inspect `git status --short`, `git diff --stat`, `git diff`, and existing staged changes without overwriting them.
- [ ] Do not include `DOOM.WAD`, proprietary assets, full decoded texture/map images, PNGs, EXEs/DLLs, logs with commercial payloads, or absolute private filesystem paths.
- [ ] Do not perform `git add`, `git commit`, `git push`, `git tag`, `git reset --hard`, `git clean` or destructive Git operations.
- [ ] Recommend a **Conventional Commit** subject/body and a **proposed** annotated tag `v0.2.0`, but leave both unexecuted.

Suggested **commit only after owner acceptance**:

```text
chore(release): prepare DoomPB v0.2.0

- Complete M2 resource and map integration validation
- Verify wall textures, flats and validated maps on Ultimate Doom 1.9ud
- Add synthetic end-to-end and lifecycle regression coverage
- Update CLI version, documentation and release notes
- Record Windows validation and outstanding Linux/caching limits
```

Suggested **owner-controlled** annotated tag, after the release commit:

```bash
git tag -a v0.2.0 -m "DoomPB 0.2.0 - resources and validated maps"
```

If the owner chooses to keep a separate test/integration commit before a small release-metadata commit, that is also fine; recommend clean separation based on the observed diff, **without performing Git actions**.

## 8. Reporting requirements

Submit an exact technical report with these headings:

```text
Task / milestone: M2-07 — integration and v0.2.0 preparation
Baseline Git branch, HEAD, index/worktree status:
Windows OS and exact PureBasic compiler version:
Original C symbols and pinned commit inspected:
Files created/modified:
Acceptance-gap audit (complete/partial/deferred):
End-to-end WAD/resources/maps integration results:
MapLevelValidateResources results for E1M1, E1M2, E4M1:
Ownership, reopen/invalidation and deterministic-hash evidence:
New synthetic E01–E32 and integration I01–I04 test results:
Previous regression tests and exact totals:
Syntax check/build/CLI checks with commands and exit codes:
Version and release documentation status:
Linux build/runtime status (PASS/FAIL/NOT RUN, actual evidence):
Git diff/whitespace/resource audit:
Known limitations, deviations and remaining M3 work:
Release decision: READY FOR OWNER ACCEPTANCE / BLOCKED
Suggested Conventional Commit and annotated tag (not executed):
```

When optional tests cannot run, use `NOT RUN`, not `PASS`. If an external GUI cannot be visually inspected, report the actual evidence (for example last-known screenshot check and a new process/window smoke test); do not claim a new visual PASS without seeing an image.

## 9. Final scope reminder

The accepted deliverable is a **working tree** with a tested `0.2.0` version candidate and accurate docs. This assignment does not authorize staging, commits, tags, pushes, releases or starting M3. The owner decides when to accept M2 and when `v0.2.0` officially exists in Git.
