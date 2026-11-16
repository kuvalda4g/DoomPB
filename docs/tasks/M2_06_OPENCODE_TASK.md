# DoomPB — M2-06: Map Loader, cross-reference validation and BSP integrity

> - **Task ID:** `M2-06`
> - **Milestone:** M2 — Resources, textures and validated maps (`v0.2.0` **not yet accepted**)
> - **Status:** Implementation assignment, not a completed-work report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017; reasoning **High**
> - **Compiler:** PureBasic 6.41 full edition; Windows x64 primary target
> - **Linux x64:** report `NOT RUN` unless actually compiled *and* executed on Linux
> - **License/data:** GPL-2.0-only engine; commercial IWAD is local, read-only and never committed
> - **Pinned original source:** `../doom-original`, commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M2-05 tested and committed; verify the current branch/HEAD rather than assuming a SHA
> - **Read:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, current source/tests, this task

## 1. Goal and acceptance boundary

Implement a **validated, caller-owned level object** assembled from the ten vanilla Doom map lumps, including cross-record references and BSP integrity checks. Integrate with M2-05 binary decoders rather than reimplementing their byte parsing. A successful call must yield enough safe, stable indices and metadata for M3 geometry/BSP rendering to consume later.

Required outcomes:

1. Find an explicitly requested Ultimate Doom map marker (initially `E1M1`, `E1M2`, `E4M1`) and validate the **ten consecutive lumps in canonical order**.
2. Decode all ten payloads through the real M2-05 decoder APIs, taking ownership of the resulting record sets. Fail safely on absent/misordered/truncated/malformed inputs.
3. Validate references **across** records, derive sidedef/sector/seg/subsector links, check the BSP tree and `REJECT` / `BLOCKMAP` against actual map dimensions.
4. Expose a metadata-only inspection path, ideally `--iwad <path> --map-info <ExMy>`, and robust synthetic/integration tests.
5. Verify `E1M1`, `E1M2`, `E4M1` from the owner's `data/DOOM.WAD` **read-only**. Preserve M0/M1/M2-01..05 behavior and version `0.1.0`.

**M2-07** is release integration and `v0.2.0` readiness. **M3** is fixed-point geometry and BSP drawing; this task must not claim playable maps or render an E1M1 view.

### Explicit non-goals

- No player spawning, `P_InitThinkers`, linedef action execution, collision simulation, visplane/column/wall rendering, live BSP traversal, sound, demos or gameplay loop.
- No multi-WAD overlay manager, ZDoom/UDMF/Hexen extended formats, map mutation, map editing or cache overhaul.
- No eager composition of every texture, sprite decoding for every map thing, or duplicated flat/texture decoder.
- No hardcoded geometry values, hardcoded per-map indices, undocumented repair of corrupt WAD data or license-incompatible assets.
- No `git add`, `commit`, `push`, `tag`, rebase, destructive Git commands or change of application version.

## 2. Inspect before editing (mandatory)

1. Run `git status --short --branch`, `git log -1 --oneline`, `git diff --stat`, `git diff --cached --stat`, `git tag --list`. Verify that M2-05 is **committed**; if not, preserve existing work and report the discrepancy. Do not assume a clean worktree.
2. Read exact existing signatures, `Magic` conventions and lifetimes for:
   - `src/WAD/WAD.pbi` (directory indexing, `WADFindLump`, `WADReadLump`, `WADLumpSize`, close/reopen);
   - `src/Map/MapTypes.pbi`, `MapDecode.pbi`, `Blockmap.pbi` (every record decoder/accessor/reset, `NF_SUBSECTOR`, ownership);
   - `src/Graphics/Flat.pbi`, `TextureDefs.pbi` (catalog name lookups, `-` sentinel, current WAD lifetime rules);
   - `src/DoomPB.pb`, all relevant unit tests and `scripts/{build,test}.{ps1,sh}`.
3. Verify upstream commit with `git -C ../doom-original rev-parse HEAD`. Inspect `linuxdoom-1.10/p_setup.c`: `P_SetupLevel`, `P_LoadVertexes`, `P_LoadSideDefs`, `P_LoadLineDefs`, `P_LoadSegs`, `P_LoadSubsectors`, `P_LoadNodes`, `P_LoadSectors`, `P_GroupLines`, `P_LoadBlockMap`; and `doomdata.h`, `r_defs.h`. Inspect `p_maputl.c`, `p_sight.c` where relevant.
4. Confirm with compiler / PureBasic 6.41 documentation how to handle pointer fields in nested structures, arrays, allocation sizes, 32/64-bit calculations, errors, `XIncludeFile` order and CLI argument handling. For uncertain syntax, compile a **small disposable probe**.
5. Before implementation, state a concise plan: intended file changes, public API and ownership, validation order, BSP graph algorithm, synthetic tests, CLI behavior and non-goals.

**Historical baseline (must rerun, not merely quote):** M1 96 tests / 694 assertions; M2-01 31 / 191; M2-02 33 / 165; M2-03 30 / 141; M2-04 39 / 300; M2-05 48 unit / 169 plus 3 synthetic integration / 21. Last reported script checks: 56/56. The existing `--show-title` and `--version` must still work.

## 3. Module architecture and ownership

Prefer these modules; adapt names to project conventions without unnecessary refactoring:

```text
src/Map/MapLevel.pbi                 # composed level object; owner, reset, typed access
src/Map/MapLoader.pbi                # marker/lump discovery, I/O and decode transaction
src/Map/MapValidate.pbi              # cross-reference, BSP, REJECT and BLOCKMAP validation
 tests/unit/wad_map_loader_tests.pb # synthetic/integration test harness
```

Suggested conceptual APIs (NOT guaranteed valid PureBasic declarations):

```text
MapLevelLoad(Name.s, *Level, [*OptionalResourceCatalogs]) -> boolean
MapLevelReset(*Level)
MapLevelIsReady(*Level) -> boolean
MapLevelGetCounts(*Level, *Output) -> boolean
MapLevelGetLinedefLinks(*Level, LineIndex, *FrontSector, *BackSector, ...) -> boolean
MapLevelGetSegLinks(*Level, SegIndex, *LineIndex, *SideIndex, *FrontSector, *BackSector, ...) -> boolean
MapLevelGetSubsectorSector(*Level, SubsectorsIndex) -> integer/error
MapLevelGetBspRoot(*Level, *RootIsSubsector, *RootIndex) -> boolean
MapLevelGetSectorLineIndices(*Level, SectorIndex, ...) -> validated, borrowed view or copies
MapLevelLastError() -> useful diagnostic
```

No mandated exact names. Minimize unnecessary accessor duplication: reuse `MapThingSet`, `MapLinedefSet`, `MapVertexSet`, etc., and add compact *derived indices* as needed. Prefer **integer indices**, not pointers into mutable arrays. A handle-like type is acceptable if it protects ownership.

Ownership/lifetime rules:

- Caller zero-initializes the `MapLevel` once; `MapLevelReset` is idempotent and releases all owned decoded sets and derived arrays.
- `Load()` is a **transaction**: a failure (including late failure in BSP validation) clears the previous target level and leaves a safe empty object; no partially linked records, double frees or leaked temporary WAD payloads.
- Level data remains valid after the source lump byte buffers are freed and after closing the WAD. Do **not** keep raw pointers into WAD buffers, FlatCatalog, TextureCatalog, another temporary object or unpinned storage.
- Avoid shallow-copying any result object that owns pointers. If temporary objects are moved into `MapLevel`, explicitly transfer ownership and clear the source owner; verify behavior with the actual PureBasic compiler.
- Loaded structure access is read-only for this phase. Underlying WAD generation invalidates *resource* directory indices (if retained) on close/reopen, but owned map records and resolved **within-map indices** remain valid. Document both categories distinctly.
- Define caps based on M2-05 limits, with checked 64-bit arithmetic for counts, arrays and sum-of-sizes. No unbounded recursion, stack depth or per-entry allocation.
- Diagnostics include the requested map name, lump name/index, record index and invalid value when possible. Clear stale errors on success.

## 4. Exact map marker and lump selection

The **vanilla Doom format** stores a map as a marker followed by ten *adjacent directory entries*:

| Relative index | Required lump name |
|---:|---|
| +1 | `THINGS` |
| +2 | `LINEDEFS` |
| +3 | `SIDEDEFS` |
| +4 | `VERTEXES` |
| +5 | `SEGS` |
| +6 | `SSECTORS` |
| +7 | `NODES` |
| +8 | `SECTORS` |
| +9 | `REJECT` |
| +10 | `BLOCKMAP` |

- `E#M#` is supported for Ultimate Doom; initially accept canonical uppercase/lowercase ASCII external queries using the same bounded lookup rules as WAD. Validate name length/characters (for `E1M1`/`E4M1`, no Unicode normalization). Never construct arbitrary paths from map names.
- Use existing WAD directory lookup to find the marker. Verify its size is zero for the vanilla marker policy. If duplicate map markers exist, use existing last-match semantics consistently and test that the complete map block is selected; do not mix `THINGS` from one map with `LINEDEFS` from another.
- Read the *next ten entries by absolute index* after the selected marker. **Do not** independently `WADFindLump("THINGS")`, etc. for each resource: many maps share these names.
- Verify that all entries exist, their 8-byte bounded names match exactly the canonical names, and each payload range passes the existing WAD reader checks. Reject out-of-order data, missing blocks, maps truncated by end-of-directory and misleading names.
- Local decoders handle malformed/empty blobs by their existing contract. The combined map layer must reject missing *essential geometry* (e.g. no valid vertices/lines/sides/sectors/segs/subsectors for a nonempty level) before indexing. Zero things are allowed; other zero-length cases depend on whether a complete, meaningful synthetic map can be formed.
- Optional `MAPxx` recognition may be documented but **must not** falsely promise Doom II or Hexen support. Keep scope to vanilla Doom/Ultimate Doom.
- Do not silently skip or reorder extra lumps inside a classic ten-lump group. Detection of unsupported extended node formats should yield an actionable error, not an attempt to reinterpret them as vanilla.

## 5. Ordered cross-reference validation

All checks happen **after** the ten independent structures have decoded, but **before** publishing a ready level. Use bounds-checked getters to avoid assuming internal array layouts.

### 5.1 Vertices, sides, sectors and linedefs

1. Every linedef `v1` and `v2` must be `< NumVertices`; reject references outside range before geometry computations. A zero-length geometric segment (`v1==v2` or equal coordinates) may be retained as a *diagnostic/warning* unless it demonstrably prevents safe use; do not casually reject a vanilla-compatible map.
2. For each sidedef, `sector` must be `< NumSectors`. Preserve the raw upper/lower/middle eight-byte names; optional resource binding is separate (section 8).
3. For each linedef, `sidenum[0]` (front) must identify an existing sidedef in a renderable vanilla map; an absent front side is invalid. `sidenum[1] == -1` means no back side. Other negative values and positive out-of-range values are invalid.
4. Check the original `ML_TWOSIDED` bit and its dependency on a usable back side **without blindly indexing**. A two-sided flag with no back sidedef is a hard error because `P_LoadSegs` may dereference it. Record the distinction between flag and actual side presence for later rendering; do not invent a back side.
5. Derive linedef `frontSector` / `backSector` from the associated sidedefs. When the back side exists, verify its sector index; a one-sided line gets a documented sentinel (e.g. `-1`), not an address-zero pointer.
6. Preserve original `flags`, `tag`, `special`, orientation and order; do not normalize two-sided geometry, reorder endpoints or mutate raw map data.

### 5.2 SEGS and SSECTORS

1. Every seg `v1`, `v2` index must be `< NumVertices`; `linedef` `< NumLinedefs`; `side` must be exactly `0` or `1`.
2. Resolve a seg's sidedef **using its referenced linedef and selected side**; reject missing/out-of-range side. Compute `frontSector` from that side and `backSector` from `side XOR 1` only when allowed by the original two-sided semantics. Check both references before use.
3. Preserve raw seg angle and offset; do not attempt fixed-point conversion or overwrite user data. The original C does 16.16 conversions, but those belong to M3 or a clearly separate checked adapter.
4. For every subsector: `numsegs > 0` for a level usable by `P_GroupLines`; check `firstseg < NumSegs` and `firstseg + numsegs <= NumSegs` in a checked 64-bit intermediate. Avoid off-by-one and `u16` wraparound.
5. Derive each subsector's sector index from the **first seg's sidedef sector**, matching `P_GroupLines`. Any optional check that every seg shares the same sector must be documented as a compatibility check; do not reject legitimate original maps without confirming the invariant against the known IWAD.
6. Check intersecting/overlapping subsector seg ranges and unreferenced segs as diagnostics or appropriately justified strict rules. In particular, do not claim a bijection without verifying vanilla data.

### 5.3 Sector line membership

- Build a deterministic, owned per-sector index view/list of associated linedefs (optional but recommended). A line appears in the front sector; it appears in the back sector only if the back sector **differs** from the front sector. Preserve original linedef iteration order.
- Use a bounded two-pass count/prefix-sum/fill strategy (or an equivalently safe simple algorithm): checked count sums, validated indices, no pointer invalidation or quadratic memory explosions.
- Derive per-sector line count and optional bounding box metadata (min/max vertices) without introducing runtime sound origin, collision clipping or `blockbox` simulation. If a sector has no associated lines, define a stable empty result and avoid uninitialized box values.
- For optional `line_t`-style helpers, keep integer world-map coordinates as decoded; do not accidentally treat them as 16.16 fixed-point.

## 6. BSP validation (the main safety gate)

`NODES` is a binary directed graph represented as a tree. Its historical root is the **last node** (`NumNodes - 1`); `NODES.children[]` is a 16-bit field with bit `0x8000` (`NF_SUBSECTOR`) indicating a subsector leaf and lower 15 bits containing the index.

Mandatory:

1. For every node child, if bit `0x8000` is clear, the value is a node index `< NumNodes`. Otherwise the lower 15 bits must be `< NumSubsectors`. `0xFFFF` is **not** a safe unconditional `-1` sentinel: interpret its bits and validate the resulting subsector index.
2. Reject references to nonexistent nodes/subsectors before traversing or exposing them.
3. Starting at root `NumNodes-1`, perform **iterative** DFS (explicit stack with bounded memory), with three-state coloring (`unseen`, `visiting`, `visited`) or equivalent to detect **self-cycles and multi-node cycles** without recursive stack overflow.
4. For a zero-node map, support the special case of **exactly one valid subsector** as a direct subsector root if the project deliberately supports it; otherwise reject with a clear diagnostic. Do not try `nodes[-1]`.
5. Count reachable nodes and subsectors. Report unreachable items and repeated references. Treat unused records as a warning unless the original map format or a demonstrably required invariant justifies rejecting them. A shared child in an otherwise acyclic graph may be unusual but not automatically a memory-safety failure.
6. If validating `bbox[2][4]` internal min/max relationships, distinguish malformed safety-critical fields from merely unusual geometry. No collision or visibility algorithm is executed yet; do not reject valid IWADs using speculative geometry heuristics.
7. Store a safe root identifier and optional aggregate diagnostics for M3; do not perform camera-based BSP traversal or recursive rendering.

Test at least: single node with two leaf children, deeper tree, child `0x8000`, high leaf bits, last-node root, invalid node child, invalid subsector leaf, direct self-reference, multi-node cycle, zero-node/one-subsector special case, unreachable node, and very deep acyclic tree that must not overflow the process stack.

## 7. REJECT and BLOCKMAP validation against actual geometry

### REJECT

- Compute `requiredBytes = ceil(NumSectors * NumSectors / 8)` with `.q` arithmetic, checking caps/overflow. An occupied map should have a sector count greater than zero.
- Require at least this many bytes. Match the M2-05 `MapReject` rules; valid padding bytes beyond the required logical bitset may be allowed and must not be mistaken for sector data.
- Verify safe lookup of first, last and cross-byte sector pairs via the existing LSB-first accessor. Preserve the actual bytes; **do not** synthesize missing matrix bits, apply visibility filtering or assume bit=1 means visible (it means *rejected/not visible*).
- A nonzero valid bit does not imply that the engine must skip gameplay visibility unconditionally; actual sight tracing belongs later.

### BLOCKMAP

- Reuse `MapBlockmapDecode` from M2-05, including unsigned **word offsets**, dimension/size validation, `0x0000` list prefix and `0xFFFF` terminator handling.
- Once `NumLinedefs` is known, validate every referenced line index in every *reachable cell list* is `< NumLinedefs`. The initial `0` list word is an ordinary referenced linedef index under classic Doom conventions; ensure `NumLinedefs > 0` when checking it.
- Preserve shared lists and unsorted offsets; do not reject them purely because multiple cells point to the same list. Avoid repeated massive scans by using a bounded visited-offset set or enforce a documented total scan budget.
- Do not interpret `0xFFFF` as a line index. Check integer multiplication for grid dimensions and index arithmetic.
- Do not regenerate the blockmap or validate that every linedef appears in all mathematically expected spatial cells: that is an algorithmic correctness check for a later collision subsystem.

## 8. Resource binding and diagnostic interfaces

- **Required:** produce a coherent map level even if the caller only provides WAD + M2-05 decoders. Synthetic WAD tests may contain map lumps but no PNAMES/TEXTURE1/flats.
- **Optional/conditional:** when valid `FlatCatalog` / `TextureCatalog` instances are supplied from the *same current WAD*, resolve floor/ceiling flat names and *non-`-`* wall texture names to catalog indices. Always treat the eight-byte names as bounded fields, never raw C-style unbounded strings.
- `-` wall texture means “no texture”, not a request to find a texture named `-`. `F_SKY1` is a sky marker with special rendering semantics later; don't treat it as a wall texture or reject it based on missing ordinary texture use without examining vanilla reference behavior.
- Do not require a texture to be rendered or all unused sprite/flat resources loaded. If resource validation finds missing names, use clear diagnostics and a documented optional strictness mode; do not couple synthetic geometry tests to commercial graphics assets.
- Do not cache raw pointers to a resource catalog with a shorter lifetime than `MapLevel`.

### CLI: metadata-only `--map-info`

Implement a narrow CLI entrypoint if the existing argument parser can be extended without large refactoring. Preferred invocation:

```powershell
.\build\DoomPB.exe --iwad data\DOOM.WAD --map-info E1M1
```

- Return `0` for successful load/validation with concise numeric counts and statuses, `1` for missing/malformed WAD/map data or invalid cross-references, and `2` for incorrect or conflicting CLI options (retain existing conventions).
- Print: map label, marker index, counts for the eight fixed-record sets, REJECT byte count/required byte count, BLOCKMAP dimensions/cell count, number of BSP nodes/subsectors, root kind/index, and validation result. No full geometry dumps, game texture lists, screenshots or copyrighted asset data.
- With `--map-info`, **do not** open a graphical window and do not launch gameplay. Existing `--help`, `--version`, `--dump-info`, `--lump-info`, `--show-title` must keep their outputs/exit codes.
- If a CLI extension would require a risky redesign, document the concern and use an explicit integration-test executable instead; the *level-loader API and all validations* remain mandatory.

## 9. Test plan: 52 mandatory synthetic cases + integration

Create `tests/unit/wad_map_loader_tests.pb`, using synthetic, independently created WAD bytes. Existing M2-05 unit fixtures may be reused where license-safe. Prefer deterministic tiny maps, not extracted commercial records. **Every test must compile and actually execute**.

### Marker and load transaction: L01–L12 (12)

| ID | Scenario |
|---|---|
| L01 | Valid ten-lump map loads with expected counts |
| L02 | Missing map marker: clean error |
| L03 | Last matching map marker selected when duplicated |
| L04 | Missing one of ten required lumps |
| L05 | Correct lump names but wrong order rejected |
| L06 | End-of-directory truncation rejected |
| L07 | Nonzero or otherwise invalid marker rejected under documented vanilla policy |
| L08 | Map name invalid/overlong/Unicode input rejected safely |
| L09 | Bad binary record length fails, no partial level |
| L10 | Loading a second valid level replaces the first safely |
| L11 | Failure after prior success leaves empty target |
| L12 | Reset repeated, borrowed lump buffers freed and resulting data ownership proven |

### Geometry references and linked sectors: L13–L25 (13)

| ID | Scenario |
|---|---|
| L13 | Valid linedef→vertex references |
| L14 | Linedef vertex index at NumVertices rejected |
| L15 | Valid sidedef→sector and front/back sector derivation |
| L16 | Sidedef sector index at NumSectors rejected |
| L17 | Invalid front sidedef index rejected |
| L18 | Back side `-1` is sentinel, not array access |
| L19 | Negative back side other than `-1` rejected |
| L20 | Two-sided flag with absent back side rejected without crash |
| L21 | Valid seg→linedef→sidedef and sector links |
| L22 | Seg `side=2` or negative side rejected |
| L23 | Seg vertex/line index out of bounds rejected |
| L24 | SSECTOR `firstseg+numsegs` overflow/out-of-range rejected |
| L25 | Subsector sector derives from first seg; sector line membership deduplicates same-sector back side |

### BSP topology and reachability: L26–L37 (12)

| ID | Scenario |
|---|---|
| L26 | Single node, two subsector leaves, last-node root |
| L27 | Multi-node acyclic tree valid |
| L28 | Child flag `NF_SUBSECTOR` and leaf 0 accepted |
| L29 | Invalid node index rejected |
| L30 | Invalid subsector index rejected |
| L31 | Node self-cycle rejected |
| L32 | Two-node cycle rejected |
| L33 | Nontrivial deeper cycle rejected |
| L34 | Zero-node single-subsector special case handled deliberately |
| L35 | Zero-node multi-subsector case diagnosed |
| L36 | Unreachable node reported with documented severity |
| L37 | Deep acyclic chain handled iteratively without stack overflow |

### REJECT, BLOCKMAP, resources and lifecycle: L38–L52 (15)

| ID | Scenario |
|---|---|
| L38 | Exact `ceil(N²/8)` REJECT length succeeds |
| L39 | REJECT one-byte-short rejected |
| L40 | REJECT padding allowed and accessor uses correct bits |
| L41 | BLOCKMAP valid one-cell linedef list |
| L42 | BLOCKMAP out-of-range referenced linedef rejected |
| L43 | BLOCKMAP `0xFFFF` terminator not mistaken for linedef |
| L44 | Shared blocklist offsets remain valid |
| L45 | Bad BLOCKMAP offset/list structure propagates error |
| L46 | Large dimensions/count arithmetic bounded safely |
| L47 | Optional flat/texture catalog absent: structural map still validates |
| L48 | Optional resource binding honors `-` texture sentinel |
| L49 | Optional resource binding rejects malformed noncanonical names safely |
| L50 | WAD A→WAD B reload has no stale cross-level indices or borrowed pointers |
| L51 | Repeated load/reset and late-stage error cleanup deterministic |
| L52 | Read-only map-info diagnostics and CLI error codes, if CLI implemented |

Tests should use **independent expected values**, not just compare an API output to itself. Add explicit assertions for exact numerical values, original record order, invalid status and deterministic error reset. In the final report enumerate any test ID that was renamed, merged or not run; do not silently report a requested test as passed if it was omitted.

### Synthetic integration (mandatory)

- **I01:** Minimal complete synthetic `E1M1` through WAD directory lookup, all ten lumps, `MapLevelLoad` + validation, counts, links, root and error-free reset.
- **I02:** Deliberately corrupt synthetic WAD: duplicate named marker, misplaced `SECTORS`, invalid seg side, invalid node child, undersized REJECT, out-of-range BLOCKMAP linedef. Each distinct case must fail without crash, leaking buffers or affecting unrelated WAD lookups.
- **I03:** WAD A→B (two different valid synthetic maps), close/reopen, load second map and verify first level's **owned** data stays valid until explicitly reset; never dereference stale resource lookup indices.

### Optional owner-supplied Ultimate Doom integration (read-only)

Use `data/DOOM.WAD` if actually present. For the known Ultimate Doom 1.9ud file, MD5 `c4fe9fd920207691a9f493668e0a2083`, 12,408,292 bytes, 2306 directory entries. **Do not require this hash for every legitimate IWAD**. Load and validate each map separately:

| Map | Marker index | THINGS | LINEDEFS | SIDEDEFS | VERTEXES | SEGS | SSECTORS | NODES | SECTORS | BLOCKMAP cells |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| E1M1 | 7 | 143 | 486 | 666 | 470 | 747 | 239 | 238 | 88 | 828 |
| E1M2 | 18 | 262 | 1033 | 1323 | 942 | 1463 | 448 | 447 | 200 | 1302 |
| E4M1 | 304 | 141 | 471 | 642 | 439 | 695 | 196 | 195 | 81 | 162 |

These numbers are **previously observed fixtures**, not guesses or a generic-WAD contract. Reject sizes below `ceil(N²/8)` for REJECT; previously observed: E1M1 = 968 bytes, E1M2 = 5000 bytes, E4M1 = 821 bytes. Record actual BSP reachable counts, sector linkage counts, BLOCKMAP index validation results and a deterministic **non-reconstructable metadata checksum** as measured, without copying raw map resources into the repo.

If a new stricter validation fails on the real IWAD, investigate the **exact** relationship with upstream `P_SetupLevel` and M2-05 decoder before relaxing/changing it. Do not simply disable failing assertions or claim PASS. If local IWAD is absent: report `NOT RUN` for that optional integration.

## 10. Build and regression matrix

After changes:

1. Compile/syntax-check the main entry and **every existing test target** with actual PureBasic 6.41. Use existing build/test scripts instead of guessing switches; introduce `-MapLoaderTest` only if it matches the scripts' established convention.
2. Build the main program and new standalone test executable. A `--check` result is not a functional runtime test.
3. Run full `scripts/test.ps1` and all M0, M1, M2-01 through M2-05 tests; ensure no history regressions. Verify all script checks with actual commands and exit codes.
4. Run L01–L52, I01–I03 and read-only E1M1/E1M2/E4M1 integration if available. Show explicit PASS/FAIL/NOT RUN, case/assertion totals and any diagnostics.
5. Test CLI (as implemented):

```powershell
.\build\DoomPB.exe --version
.\build\DoomPB.exe --iwad data\DOOM.WAD --dump-info
.\build\DoomPB.exe --iwad data\DOOM.WAD --lump-info E1M1
.\build\DoomPB.exe --iwad data\DOOM.WAD --map-info E1M1
.\build\DoomPB.exe --iwad data\DOOM.WAD --map-info E1M2
.\build\DoomPB.exe --iwad data\DOOM.WAD --map-info E4M1
.\build\DoomPB.exe --iwad data\DOOM.WAD --show-title
```

For `--show-title`, window must render 960×600 and close with exit 0. Don't claim visual inspection unless screenshot/frame was actually reviewed; previous M1 visual acceptance still stands, and a new screenshot is not mandatory if video code is untouched.

6. On any host without Linux PureBasic, run `bash -n scripts/build.sh scripts/test.sh`, and report **Linux runtime NOT RUN**. Do not represent `bash -n` as an actual Linux compilation/test.
7. Review `git diff --check`, `git diff --cached --check`, `git diff --stat`, `git status --short`; include untracked file whitespace scan. Check no executable/WAD/PNG/BMP/asset, `build/`, `data/`, `local-data/`, private path or accidental generated file is staged or tracked.

## 11. Documentation expectations

Update only relevant sections of:

- `README.md`: map loader availability and explicit non-features (no rendering/gameplay), optional `--map-info` usage, Windows verified/Linux unverified.
- `docs/PORTING_NOTES.md`: exact C functions, ownership, original-vs-strict validation, group-lines rules, BSP algorithm, REJECT/BLOCKMAP semantics, exceptions/warnings.
- `CHANGELOG.md`: M2-06 work **under Unreleased**, not under a published `v0.2.0` entry.
- `scripts/build.ps1`, `build.sh`, `test.ps1`, `test.sh` only to add the new test target with consistent exit handling.
- `docs/DEVELOPMENT_PLAN.md`: do not mark the whole M2 complete until M2-07 and owner acceptance. If tracking subtasks there, use clearly bounded completion marks.

Preserve no trailing whitespace (including `.md`) and avoid irrelevant refactors. Keep `DoomPB 0.1.0` and both existing release tags unchanged.

## 12. Definition of Done

- [ ] Real PureBasic 6.41 build/check passes on Windows x64.
- [ ] Complete map search uses marker + **adjacent ten named lumps**; duplicate markers and corruption are safe.
- [ ] Decoded sets owned by `MapLevel`; fail/reset/reload have no leaks or dangling references.
- [ ] Linedef, sidedef, vertex, seg, subsector, sector references validated and safe link access available.
- [ ] BSP child flags/indices validated; cycle detection iterative; root determined; reachable counts recorded.
- [ ] REJECT bitset size and BLOCKMAP linedef indices checked against actual level counts.
- [ ] 52 synthetic cases, three synthetic integrations run with explicit case/assertion totals.
- [ ] E1M1, E1M2, E4M1 load successfully from local known IWAD, or optional check clearly `NOT RUN` if unavailable.
- [ ] All earlier regression tests and existing CLI commands still pass.
- [ ] `--map-info` works or a documented safe test-only equivalent exists without broad CLI refactor.
- [ ] No commercial game data leaked to Git or reports; diff/whitespace audited.
- [ ] No version change, tag, commit, push or M2-07/M3 work.

## 13. Final report required from OpenCode

Return a **factual** report containing:

```text
Task/milestone: M2-06 — Map Loader & Validation
OS/compiler, actual version; Linux status:
Baseline HEAD, branch, staged/unstaged/untracked status; M2-05 commit verified:
Original C symbols inspected and upstream pinned commit:
Files created/modified:
MapLevel API, ownership, load/reset contract:
How marker selection and ten-lump indexing work:
Cross-reference and derived sector/line links:
BSP root, cycle detection, leaf/reachability semantics:
REJECT/BLOCKMAP validation against live record counts:
Resource binding and compatibility differences:
PureBasic syntax checks/builds (exact commands/exit codes):
Previous regression totals:
L01–L52 case/assertion totals:
I01–I03 results:
E1M1/E1M2/E4M1 observed counts/checksums and validation results (or NOT RUN):
--map-info/--show-title/--version and exit codes:
Linux bash syntax and actual runtime status:
Git diff/status, staged/untracked files, whitespace and commercial-data audit:
Limitations, deferred issues and any strictness differing from vanilla:
Suggested Conventional Commit message (do not execute):
Next task: M2-07 (do not start):
```

Success is based on real compiler/tests and a safely loaded level, not a generated-code description. Preserve owner control over Git operations and release decisions.
