# DoomPB — M3-02: BAM angles, original trigonometric tables and geometry primitives

> - **Task ID:** `M3-02`
> - **Milestone:** M3 — Geometry & First Walls; `v0.3.0` is **not** complete
> - **Status:** Implementation assignment, not a completion report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017; reasoning **High**
> - **Language/compiler:** Native PureBasic **6.41**, full edition
> - **Primary target:** Windows x64; Linux x64 is `NOT RUN` unless genuinely built and tested there
> - **License:** GPL-2.0-only project; preserve applicable attribution when porting upstream tables/code
> - **Pinned Doom reference:** `../doom-original`, commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M3-01 fixed-point implementation accepted and committed; verify current Git state, do not assume a specific HEAD
> - **Required reading:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md` (M3), `docs/PORTING_NOTES.md`, actual M3-01 source/tests, this assignment

## 1. Objective and precise scope

Extend DoomPB's validated M3-01 16.16 arithmetic with the **binary angle measurement (BAM)** model, exact **vanilla Doom trigonometric lookup tables**, and the small geometric computations on which the renderer will depend. Implement equivalents of `SlopeDiv`, `R_PointToAngle` / `R_PointToAngle2`, `R_PointToDist`, `R_PointOnSide` and (if consistent with the small subsystem) `R_PointOnSegSide` using **actual pinned C code** as the reference.

Deliver independent, unit-testable math/geometry APIs with no windowing, no texture or BSP traversal and no dependency on commercial IWAD assets. Do not approximate the tables with runtime `Sin()`, `Cos()`, `ATan()` or a new floating-point algorithm. Preserve Doom's counterintuitive branch boundaries, octant rounding, sign tests and 32-bit angle wraparound.

**M3-03** will traverse BSP nodes; **M3-04–06** will address wall clipping/projection/columns. This task **must not** render or claim a visible map view.

### Explicit non-goals

- No visible walls, screen-space projection, camera/game loop, render frame, `R_RenderBSPNode`, `R_CheckBBox`, wall clipping or texture columns.
- No `R_InitTextureMapping`, `viewangletox`, `xtoviewangle`, FOV projection tables, `R_ScaleFromGlobalAngle` or lighting tables; those depend on later rendering decisions.
- No replacing the existing M3-01 `FixedMul`, `FixedDiv`, conversion semantics or rewriting map loader APIs merely for convenience.
- No multi-WAD/PWAD, level editor, non-vanilla Doom extensions, gameplay/AI, `P_PathTraverse`, collision rules or physics side tests.
- No generated raster imagery, extracted game resources, new commercial assets, binary snapshots or publishing of proprietary IWAD data.
- No version bump (keep `DoomPB 0.2.0`), release/tag `v0.3.0`, or unauthorized Git operations.

## 2. Repository, documentation and reference inspection — first, before edits

1. Run `git status --short --branch`, `git log -1 --oneline`, `git tag --list`, `git diff --stat`, `git diff --cached --stat`. Confirm that M3-01 exists in the Git history; inspect current staged/unstaged/untracked changes and **preserve all owner work**. If M3-01 is not committed, stop conflicting implementation and report the discrepancy; do not assume the preceding conversation equals repository state.
2. Read exact code/contracts in `src/Core/Fixed.pbi`, `tests/unit/fixed_math_tests.pb`, `tests/integration/m3_fixed_iwad_tests.pb`, `src/Map/MapLevel.pbi`, `src/Map/MapTypes.pbi`, `src/Map/MapLoader.pbi`, the current `src/DoomPB.pb` and all four scripts. Check module naming, `Magic`, reset behavior, `XIncludeFile` order, diagnostic conventions and test harness switches. **Never invent interfaces from this document's examples.**
3. Verify `git -C ../doom-original rev-parse HEAD` equals `a77dfb96cb91780ca334d0d4cfd86957558007e0` (or report the mismatch before relying on it). Read at least:
   - `linuxdoom-1.10/tables.h` and `tables.c`: BAM constants, `SlopeDiv`, literal `finetangent`, `finesine`, `tantoangle` data;
   - `linuxdoom-1.10/r_main.c`: `R_PointOnSide`, `R_PointOnSegSide`, `R_PointToAngle`, `R_PointToAngle2`, `R_PointToDist`, consumers and view state;
   - `linuxdoom-1.10/r_defs.h` and `r_local.h`: fixed-point node/seg/vertex representations and declared callers;
   - `linuxdoom-1.10/r_bsp.c`: uses of side and angle functions; `p_maputl.c` only to distinguish gameplay point-side functions (not to port them).
4. **Context7 documentation lookup:** follow the installed root `AGENTS.md`. If Context7 is configured and exposed, attempt it for uncertain external/PureBasic APIs and version-sensitive behavior; do not assume a PureBasic 6.41 entry exists. If no appropriate entry is available, use local PureBasic 6.41 CHM/help, official reference and short compile probes. The original local C remains authoritative for Doom's math. Report `Context7 USED / NO MATCH / UNAVAILABLE / NOT NEEDED` truthfully, with actual source/tool details. Do not reveal keys or upload user data.
5. Verify installed PureBasic syntax with the **actual** 6.41 compiler where uncertain: `.l/.q` values, signed/unsigned masks, logical vs arithmetic shift, low-32 narrowing, array bounds, `DataSection`/`Data.l` or static table initialization, pointer ownership, large constant notation and return types. Use disposable probes outside tracked production modules.
6. Before editing, present a short implementation plan: intended files, exact operations, angle representation, table storage and provenance, error/overflow policy, 48 test IDs, independent validation and integration evidence.

M3-01's **reported** baseline: Windows x64 PB 6.41, 43 fixed-point cases / 318 assertions including synthetic integrations; 73 script checks; `DoomPB 0.2.0`. Historical results are **not** proof of a fresh regression run. Linux runtime remained untested.

## 3. Recommended file layout and API boundaries

Prefer a small set of cohesive modules:

```text
src/Core/Angle.pbi                  # BAM constants, angle wrap and conversion/index helpers
src/Core/TrigTables.pbi             # exact pinned sine/tangent/atan tables and bounds-checked access
src/Renderer/Geometry.pbi           # slope, point-angle/distance, node/seg point-side
 tests/unit/angle_geometry_tests.pb
 tests/integration/m3_geometry_iwad_tests.pb    # only if it avoids duplicating test setup
```

Alternate paths are acceptable if consistent with existing project layout. Do not add unused placeholders for later renderer features. Keep original fixed-point arithmetic in `Core/Fixed.pbi`; avoid circular includes. Avoid storing pointers to WAD buffers, `MapLevel` temporary records or external tables with uncertain lifetime.

Suggested **conceptual** operations (adapt to existing PureBasic naming and compile-valid signatures):

```text
BamWrap32(Value.q) -> raw unsigned angle bits 0..4294967295
BamFineIndex(RawAngle) -> 0..8191 (angle >> 19 & 8191)
BamSin(RawAngle) / BamCos(RawAngle) -> fixed_t .l from exact tables
TrigTangentGet(FineIndex) / TrigTanToAngle(SlopeIndex) -> validated lookup
DoomSlopeDiv(Num, Den) -> 0..2048, with original early guard
GeometryPointToAngle(ViewX, ViewY, X, Y) -> 32-bit BAM raw angle
GeometryPointToAngle2(X1, Y1, X2, Y2) -> same semantics with explicit origin
GeometryPointToDist(ViewX, ViewY, X, Y) -> signed fixed_t distance
GeometryPointOnNodeSide(X, Y, NodeOriginX, NodeOriginY, DX, DY) -> 0/1
GeometryPointOnSegSide(X, Y, V1X, V1Y, V2X, V2Y) -> 0/1
GeometryLastError() -> deterministic diagnostic for invalid/out-of-domain inputs
```

A single public `GeometryPointToAngle2` plus an explicit origin/view overload is fine. **Do not** copy the original `R_PointToAngle2`'s mutation of `viewx/viewy` into an unrelated global state without a concrete reason. If choosing pure explicit-argument APIs, document this deliberate side-effect difference and test numerical equivalence. Use `MapLevel` validated accessors only for **optional integration**; the pure calculations must work without a WAD.

Define clearly whether functions use return-code-plus-output-pointer or value-plus-error. **Do not** use an ordinary zero angle, zero distance, or side `0` as an ambiguous error sentinel. Keep diagnostics consistent with M3-01's `FixedLastError` style. If exposing raw BAM through `.l`, document the signed bit-pattern interpretation; if `.q`, always constrain to the low unsigned 32 bits.

## 4. Exact BAM angle model and invariants

The Doom `angle_t` is an **unsigned 32-bit** binary angle, representing a full 360-degree revolution modulo `2^32`. The following are *bit patterns*, **not signed positive 32-bit values**:

| Symbol | Unsigned BAM value | Hex |
|---|---:|---|
| `ANG45` | 536870912 | `0x20000000` |
| `ANG90` | 1073741824 | `0x40000000` |
| `ANG180` | 2147483648 | `0x80000000` |
| `ANG270` | 3221225472 | `0xC0000000` |
| Full turn | 4294967296 | `0x100000000` (wraps to 0) |

Constants from `tables.h`:

```text
FINEANGLES = 8192
FINEMASK = 8191
ANGLETOFINESHIFT = 19
SLOPERANGE = 2048
SLOPEBITS = 11
DBITS = FRACBITS - SLOPEBITS = 5
```

- Keep exact low 32 bits for **all** adds/subtracts/negations and comparisons requiring unsigned BAM semantics. No accidental signed `.l` ordering for `ANG180` or `ANG270`.
- Convert a wrapped BAM angle to a sine/cosine index using `(angle >> 19) & 8191` on the nonnegative/raw bit representation. Do **not** use an arithmetic right shift on a signed angle for table indexing.
- Validate `ANGLETOFINESHIFT=19` and `2^32 / FINEANGLES = 2^19`. Test wrap from `0xFFFFFFFF` to 0; `ANG180` must map to fine index 4096.
- `R_PointToAngle` contains offsets such as `ANG90 - 1`, `ANG180 - 1`, `ANG270 - 1`. They reflect **original octant boundary behavior**, not noise. Do not round to perfect cardinal angles or replace with `ATan2()`.
- For point deltas, distinguish full `.l` fixed-point inputs from map `s16` coordinates. Convert map coordinates using existing M3-01 checked conversion. Never shift a potentially overflowing 32-bit world value without an explicit policy.

## 5. Trigonometric tables — exact upstream contents

Copy or reproducibly generate **the exact numerical table values from the pinned local `tables.c`** (within the GPL-compatible project and with required attribution). The reference arrays are:

| Original symbol | Number of entries | Interpretation |
|---|---:|---|
| `finetangent` | **4096** | Signed `.l` fine-angle tangent LUT; full original sequence |
| `finesine` | **10240** | Signed `.l` 16.16 sine LUT, with extra quarter-turn for cosine |
| `tantoangle` | **2049** | Raw BAM `angle_t` lookup for slope `0..2048` |

`finecosine` in `r_main.c` is an alias to `&finesine[FINEANGLES/4]`. It is **not a fourth separately calculated table**. Access cosine via sine table offset `+2048`, with checked bounds.

**Independent verification fixtures derived from pinned `tables.c`:** the following FNV-1a64 hashes feed every element as exactly **four bytes in little-endian order**, using the two's-complement low 32 bits for signed values. Hash is over raw values, not PB structure memory, pointers, textual representation or UTF-8 decimal strings.

| Array | Count | First value | Last value | Full table FNV-1a64 |
|---|---:|---:|---:|---|
| `finetangent` | 4096 | -170910304 | 170910304 | `6E300CFD277525E1` |
| `finesine` | 10240 | 25 | 65535 | `ADD266F0CB7B06B6` |
| `tantoangle` | 2049 | 0 | 536870912 | `56213612F87A0F4A` |

These figures were computed from the original pinned repository version. The agent **must independently confirm** them against its own pinned local checkout before treating them as golden. If hashes do not match, investigate extraction/ordering/packing/source revision instead of changing expectations to match the new code.

Storage strategy:

1. Choose an architecture-consistent **source-level** immutable table representation (e.g. a generated checked `.pbi` with literal `Data.l` or other compile-valid PB initialization). Do not depend on a local C compiler, internet access, JSON file, DLL or dynamic downloads at runtime.
2. A **one-time** developer generator is optional if it makes the transcription reproducible; it must read the user's separately licensed original source locally, emit only the numerical tables and preserve source provenance/license information. The generated table source must be tracked so an ordinary checkout builds without the original C tree.
3. Prevent off-by-one values, swapped table order, sign extension, endian mismatches, bogus aliasing and out-of-bounds cosine accesses. Test first, last, 0/90/180/270-degree samples and entire-table hashes.
4. Check PureBasic 6.41 practical constraints of huge arrays / data sections / compilation time. Favor a single validated initialization that does not allocate or regenerate tables on every call; avoid mutable public global tables or unnecessary heap ownership.
5. Do not turn this into a runtime trigonometry generator using floating-point library functions. Existing data contain historical rounding decisions; mathematically plausible approximations do not suffice.

## 6. `SlopeDiv` — vanilla formula and edge behavior

Read **the actual implementation in `tables.c`** before coding:

```text
if den < 512: return 2048
ans = (num << 3) / (den >> 8)  // unsigned integer division
return min(ans, 2048)
```

The formula and its early guard are compatibility-sensitive. Do not replace by `(num * 2048) / den`, which differs from truncating `den >> 8` before division. Preserve unsigned semantics and the `SLOPERANGE` cap. Use `.q` (or explicitly checked low-word behavior if demonstrated relevant) to avoid host-language undefined or accidental arithmetic overflow.

**Minimum tests:** `den=0`, `511`, `512`, `513`, numerator `0`, equal components, `num>den`, values near cap, large unsigned input checked according to the documented domain. Compare directly against a tiny independent C/Python reference for the valid Doom call domain.

## 7. Point-to-angle — `R_PointToAngle` and `R_PointToAngle2`

Reference behavior in `r_main.c`:

1. Form fixed-point deltas relative to explicit view position. Equal points return BAM **0**.
2. Use exact original eight-octant branches on signs and `x > y` (strict comparison); preserve all `-1` constants in quadrant formulas.
3. Use `tantoangle[SlopeDiv(smaller, larger)]` with validated slope index; return full unsigned 32-bit BAM ring value.
4. Preserve angular wrap in negative-Y octants and right/left boundary behavior, particularly `ANG90-1`, `ANG180-1`, and `ANG270-1` cases. Test axis-aligned points and exact diagonals, not just approximate degrees.
5. Original `R_PointToAngle2(x1,y1,x2,y2)` assigns `viewx/viewy` and calls `R_PointToAngle(x2,y2)`. A pure wrapper with four explicit coordinates is preferable as long as **output values** are equivalent. Record the intentional difference in global side effects.

**Numeric safety policy:** the original C can overflow while subtracting extreme fixed-point coordinates, and can negate `INT32_MIN`. State an explicit, deterministic policy: checked `.q` deltas with a clear failure for values outside the supported signed32 domain, OR an accurately justified modulo-32 C-compatibility strategy. Do not silently clamp, normalize into degrees, invoke `ATan2`, or turn UB into a fabricated promise of vanilla equivalence. The full non-overflowing map-coordinate domain must be supported.

Tests must cover all eight octants, origin, 0/90/180/270, all four diagonals, boundary `x=y`, 1-LSB neighbor changes, negative fixed inputs, signed32 extremes, unsigned angle ordering and deterministic repeated calls. Use a separate oracle that reads the **original table values** and reproduces C branches; trigonometric floats are **not** sufficient as an exact oracle.

## 8. Point-to-distance — `R_PointToDist`

The original `r_main.c` algorithm computes:

```text
dx = abs(x - viewx)
dy = abs(y - viewy)
if dy > dx: swap(dx,dy)
angle = (tantoangle[FixedDiv(dy,dx) >> DBITS] + ANG90) >> ANGLETOFINESHIFT
dist = FixedDiv(dx, finesine[angle])
```

Retain `FixedDiv`'s **conservative saturation** from M3-01; don't substitute mathematically exact or floating-point Euclidean distance. Preserve argument order, swap, index conversion, sine-table values, truncation and sign semantics.

The original code does not safely handle every degenerate/out-of-domain input. Explicitly handle identical points (`dx=dy=0`) without reading beyond the table; choose a documented deterministic **distance 0** result or a checked error (prefer distance 0 for a stable pure helper, but clearly document the difference). For extreme coordinates where `abs(INT32_MIN)`/subtraction may overflow, apply the declared numeric policy and never access invalid tables.

Test axis-aligned and diagonal distances, small fractional distances, odd/non-square deltas, conservative-guard boundaries, swapped x/y symmetry, identical points, deterministic repeatability, valid map-coordinate extrema and dangerous synthetic 32-bit extremes. Record **exact fixed-point outputs** from a pinned-reference oracle for a manageable set of golden vectors.

## 9. Point-on-side — node and seg line orientation

Reference `r_main.c` functions:

- `R_PointOnSide(x, y, node)`: node partition `(node.x,node.y,node.dx,node.dy)`, **0 front / 1 back**.
- `R_PointOnSegSide(x, y, seg)`: segment vertices and derived `ldx/ldy`, same fast-path structure.

Both include:

1. Vertical and horizontal fast paths with `<=` on the boundary; the sign of direction changes the chosen side.
2. An XOR sign-bit fast decision for certain quadrants.
3. `left = FixedMul(lineDY >> FRACBITS, pointDX)`; `right = FixedMul(pointDY, lineDX >> FRACBITS)`; **front if `right < left`, else back**. Exact equality therefore returns side **1** in that branch. Do not substitute a generic floating-point cross product with different tie behavior.
4. Signed-fixed 32-bit arithmetic and arithmetic right shifts, using the established M3-01 `FixedMul`/wrap conventions for the supported range.

Convert the loaded `mapnode_t` and `mapvertex_t` s16 coordinates to fixed values at the adapter boundary, retaining original directions and indices. The pure side-test function should not mutate map objects. Tests must cover vertical/horizontal partitions in both directions, points on the line, sign-bit shortcut, near-boundary 1-LSB cases, negative coordinates, opposite endpoints, and node-versus-seg expected side behavior.

If implementing `R_PointOnSegSide` would broaden the diff excessively, it can be a small follow-up **inside M3-02** after core table/angle tests; do not silently claim it is done if omitted. Gameplay `P_PointOnLineSide` is a distinct reference function; do not replace rendering-side rules with it.

## 10. Object ownership, errors and performance

- Tables are stable immutable process-lifetime data; their storage is independent of WAD lifetime. No per-query allocation or repeated table initialization.
- Scalar geometry helpers should operate without heap allocation, graphics/video initialization or WAD access.
- Avoid global `viewx/viewy` mutation for pure calculation; avoid reliance on uninitialized renderer state. If a minimal compatibility wrapper is necessary, make its side effects explicit.
- Ensure `GeometryLastError` cannot report a stale error after a successful operation; when an API returns both a value and a success flag, on failure leave the caller output unchanged (following M3-01 checked APIs).
- Do not use pointer-sized `.i` as a substitute for 32-bit BAM angles; document `.l`/`.q` or raw-bit transport.
- Verify memory/CPU cost of table initialization is acceptable, but do not optimize at expense of exactness. Avoid fatal exceptions for malformed caller inputs.
- Keep GPL-2.0-only project licensing intact and preserve original attribution for ported tables/source as appropriate. Do not embed commercial IWAD-derived data.

## 11. Testing: 48 mandatory synthetic cases `AG01–AG48`

Create `tests/unit/angle_geometry_tests.pb` as an independent PureBasic 6.41 harness, integrated with the existing script style. The following categories each map to **specific named scenarios**; no cases may be skipped while still claiming 48/48.

### AG01–AG08: BAM representation and indexing

- **AG01:** `ANG45/90/180/270` raw unsigned values and hex patterns.
- **AG02:** BAM add/subtract modulo `2^32`, including `0xFFFFFFFF + 1`.
- **AG03:** Fine index from 0, ANG90, ANG180, ANG270 and near `0xFFFFFFFF`.
- **AG04:** Signed `.l` representation of `0x80000000` / `0xC0000000` does not change unsigned table index.
- **AG05:** Fine index mask, wrap and `ANGLETOFINESHIFT=19`.
- **AG06:** Safe rejection or documented handling of out-of-range raw-angle inputs.
- **AG07:** Repeated angle normalization/indexing is deterministic.
- **AG08:** Angle helpers compile/include independently without WAD or video.

### AG09–AG16: exact tables and cosine alias

- **AG09:** `finetangent` length 4096, selected first/last/interior samples.
- **AG10:** `finesine` length 10240, selected first/last/interior samples.
- **AG11:** `tantoangle` length 2049 including exact endpoint index 2048.
- **AG12:** Full 4096-entry little-endian FNV-1a64 tangent hash.
- **AG13:** Full 10240-entry little-endian FNV-1a64 sine hash.
- **AG14:** Full 2049-entry little-endian FNV-1a64 slope-to-angle hash.
- **AG15:** Cosine is the original sine offset by 2048; quarter-turn/negative values.
- **AG16:** All out-of-range table accesses fail safely; valid boundary accesses pass.

### AG17–AG24: `SlopeDiv` and original division semantics

- **AG17:** Denominator 0 and 511 produce original early result 2048.
- **AG18:** Denominator 512/513 and shift-before-division semantics.
- **AG19:** Numerator 0 and equal small components.
- **AG20:** Saturation at 2048 when quotient exceeds range.
- **AG21:** Values immediately below/above the cap boundary.
- **AG22:** Shift/truncation compared with an independent C/Python integer oracle.
- **AG23:** Deterministic spread of nonnegative valid numerator/denominator pairs.
- **AG24:** Invalid signed/oversized caller-domain values are handled according to documented API contract.

### AG25–AG32: `R_PointToAngle*` equivalence

- **AG25:** Coincident point returns 0.
- **AG26:** Positive X/Y cardinal directions: exact BAM results from the C branches.
- **AG27:** Negative X/Y cardinal directions and unsigned wrap.
- **AG28:** Four diagonals, octant edges and strict `x>y` ties.
- **AG29:** All eight octants with independent golden vectors.
- **AG30:** One-LSB near-axis/near-diagonal perturbations and `ANGxx-1` behavior.
- **AG31:** Nonzero view origin; two-point wrapper matches explicit view-origin function.
- **AG32:** Signed32 extreme input policy and zero/unchanged checked output on errors.

### AG33–AG40: `R_PointToDist` exactness

- **AG33:** Horizontal and vertical axis-aligned distances.
- **AG34:** 45-degree/diagonal exact fixed-point distances.
- **AG35:** Unequal positive dx/dy and swapped-axis symmetry.
- **AG36:** Negative quadrants and nonzero viewpoint.
- **AG37:** Sub-unit fractional fixed coordinates and deterministic division.
- **AG38:** Identical point: explicit safe policy, no invalid table read.
- **AG39:** Deterministic repeated values and exact reference vectors (not `sqrt` approximation).
- **AG40:** Signed32 overflow/`abs(INT32_MIN)` domain policy and diagnostics.

### AG41–AG48: BSP side computations and stability

- **AG41:** Vertical partition, both orientations and boundary cases.
- **AG42:** Horizontal partition, both orientations and boundary cases.
- **AG43:** General sloped line, cross-product branch and equality tie.
- **AG44:** XOR sign-bit short-circuit with negative coordinates.
- **AG45:** One-LSB near-boundary point changes and exact arithmetic shifts.
- **AG46:** `R_PointOnSegSide` opposite endpoint direction and mirrored geometry.
- **AG47:** Node/seg side helper integration with synthetic `MapLevel` records, without borrowing pointers or modifying map data.
- **AG48:** Repeated computations, error clearance, input immutability and no state bleeding across calls.

For each case, report case count, assertion count and observed exit code. **Never** count the optional IWAD integration as a replacement for mandatory synthetic coverage. Prefer independent oracle results over hardcoded guesses; the C source's signs and corner cases are not intuitive.

## 12. Integration: three mandatory synthetic scenarios and optional IWAD

### I01 — Independent module composition

Compile and run an entry point using only `Fixed.pbi`, `Angle.pbi`, `TrigTables.pbi` and `Geometry.pbi`. Verify that no WAD, screen, window, renderer backend or imported C library is needed. Check table initialization is performed at most once and every value accessor is stable.

### I02 — Synthetic map geometry bridge

Build a small, synthetic map with signed vertices and node partitions, convert through `FixedFromIntChecked()` and check point-to-angle, distance, partition-side and derived seg orientation against a separately calculated reference. Include one node with `dx=0`, another with `dy=0` and a non-axis-aligned node.

### I03 — Error recovery and deterministic snapshot

Call several operations with invalid/out-of-domain inputs; assert diagnostics and unchanged checked outputs. Then run 12 or more valid mixed operations twice and compare a canonical little-endian numeric hash of their results. Verify prior errors do not leak into subsequent success. Test reset/lifetime only if any module owns allocated storage.

### I04 (optional, local owner IWAD; strictly read-only)

Use `data/DOOM.WAD` **only when present**, without writing to it. Through the existing M2 `MapLevelLoad()` and typed accessors, load `E1M1`, `E1M2`, `E4M1` and sample a bounded, deterministic subset of:

- converted vertex and BSP-node coordinates;
- node partition side tests for synthetic viewer positions;
- angles/distances between selected existing map vertices;
- read-only derived links already validated by M2.

Compute only **non-reconstructable** checksums, counts and selected numeric facts; do not print or store full map geometry, raw arrays, textures, screenshots or game payloads. Repeated execution on the same IWAD must yield the same results. If the IWAD is absent, report **NOT RUN**, not a synthetic-test failure. Confirm local file remains unchanged if checksumming is available.

Use an **independent** deterministic oracle (e.g. a tiny reference C/Python implementation of the original algorithms and tables) for key vectors. If extracting tables via an external script, compare the complete pinned-original table hashes independently of the PureBasic runtime values.

## 13. Build, script and CLI integration

Adapt existing scripts only as needed; preserve their actual naming conventions. Suggested switches if consistent with current scripts:

```text
scripts/build.ps1 -Check
scripts/build.ps1 -Check -GeometryTest
scripts/build.ps1 -GeometryTest
scripts/build.ps1 -GeometryIwadTest
scripts/test.ps1

scripts/build.sh --check
scripts/build.sh --geometry-test
scripts/test.sh
```

Do not claim the listed options exist before implementing them. If adding optional test switches, apply matching behavior to `.ps1` and `.sh`, even if Linux runtime cannot be tested, and check `bash -n` in Git Bash **when available**. `bash -n` on Windows is only a shell syntax check, **not Linux validation**.

Verify with the installed real PureBasic compiler:

1. Syntax check the main app and all touched/new test targets. A syntax check alone is not a build.
2. Build application + unit/integration executables. Execute tests and record exact results and exit codes.
3. Run the complete previous M0/M1/M2/M3-01 regression suite; report observed totals separately from historical totals. The previous report indicated **413 synthetic cases / 2387 assertions** before optional owner-IWAD runs; rerun to confirm rather than copying numbers.
4. Smoke `--version` (`DoomPB 0.2.0`), `--help`, `--dump-info`, `--lump-info`, `--show-title` (window close and exit code), `--map-info E1M1` with the owner's local IWAD. Do not introduce a new user-visible CLI command just for geometry unless demonstrably needed; use test executables.
5. On Windows, record the exact compiler version and explicitly distinguish Linux compiler/run status from Git Bash syntax checks. Do not infer Linux PASS.

## 14. Definition of Done (M3-02 only)

Accept M3-02 only if **all** are true:

- `AG01–AG48` and `I01–I03` pass with recorded assertion counts; optional I04 is either PASS or explicit NOT RUN.
- The three full pinned-source table hashes match and all sample/index/alias tests pass.
- `SlopeDiv`, eight-octant angle computations, distance calculations and node-side decisions have exact golden vectors checked against an independent oracle.
- Point/coordinate edge behavior is explicitly defined and cannot access past a table, silently overflow or corrupt memory.
- Modules are independently usable in native PureBasic, with no WAD/runtime graphics dependency and with proper ownership/error handling.
- All previously passing M0/M1/M2/M3-01 regression tests are rerun and pass; application `0.2.0`, existing CLI and TITLEPIC stay unchanged.
- Windows x64 PB 6.41 syntax, build and functional tests actually ran. Linux is `NOT RUN` unless separately verified.
- Documentation and test scripts are updated only as necessary, with no unrelated sweeping refactors.
- `git diff --check`, staged diff review, untracked file whitespace audit and commercial-resource safety audit are PASS.
- No staging, commit, push, tag, repo publication or unauthorized changes occurred.

## 15. Documentation and code review

Update only relevant files such as `README.md`, `docs/PORTING_NOTES.md`, `CHANGELOG.md` under an **Unreleased / M3-02** entry, plus build/test scripts. Do not bump version or mark M3 complete. Explain:

- raw 32-bit BAM representation and why `ANG180` is not a positive `.l` value;
- exact table provenance/checksums and cosine sine-offset alias;
- differences between the original global `viewx/viewy` usage and any pure API;
- chosen out-of-domain input/overflow and coincident-point policies;
- intentionally deferred screen/FOV mapping and BSP traversal;
- Context7 lookup results and actual PureBasic documentation used.

Keep the diff scoped. Never edit the upstream `../doom-original` tree. Never commit local IWAD, decoded graphical resources, generated screenshots, `.exe`, `build/`, raw C source tree, downloaded help or key/config secrets.

Review with:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --stat
git diff --cached --stat
git diff
git diff --cached
```

Check each new/untracked `.pb`, `.pbi`, `.ps1`, `.sh` and `.md` file for trailing whitespace; `git diff --check` alone does **not** inspect untracked files. Preserve existing owner changes. No hardcoded absolute paths. Do not weaken `.gitattributes` whitespace rules.

## 16. Exact final implementation report template

```text
Task / milestone: M3-02 — BAM Angles & Geometry
Windows OS / PureBasic exact version:
Linux compiler/runtime: PASS / FAIL / NOT RUN (reason)
Git branch / baseline HEAD / worktree / M3-01 commit status:
Original C commit and symbols inspected:
Documentation lookup: Context7 USED / NO MATCH / UNAVAILABLE / NOT NEEDED; sources checked
Files created and modified:
Angle model / signedness / overflow policy:
Upstream trig table counts and full FNV-1a64 LE32 hashes:
SlopeDiv result and independent oracle comparison:
Point-to-angle / distance / side exactness and degenerate cases:
Source/API deviations and error/ownership contracts:
Syntax check: PASS / FAIL / NOT RUN (actual commands, exit codes)
Build: PASS / FAIL / NOT RUN (actual commands, exit codes)
Unit AG01–AG48: passed/cases/assertions/failures:
Synthetic integration I01–I03: passed/cases/assertions/failures:
Owner IWAD I04: PASS / FAIL / NOT RUN (maps, hashes, reason)
Prior M0/M1/M2/M3-01 regression totals:
CLI regression (--version, --map-info, --show-title):
Git status / git diff / whitespace / commercial resource audit:
Known limitations / remaining M3-03 scope:
Suggested Conventional Commit message (do not commit):
Suggested next task: M3-03 — BSP Traversal (DO NOT START)
```

**Success requires real compiler output, independent numeric evidence, accurate reporting and an owner review.** Do not claim M3, Doom world rendering or `v0.3.0` are complete.
