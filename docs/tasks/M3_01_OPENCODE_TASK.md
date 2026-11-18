# DoomPB — M3-01: Fixed-point 16.16 arithmetic and numeric compatibility

> - **Task ID:** `M3-01`
> - **Milestone:** M3 — Geometry and first rendered walls; `v0.3.0` is **not** complete
> - **Status:** Implementation assignment, not an implementation report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017; Reasoning **High**
> - **Language/compiler:** PureBasic 6.41 full edition; Windows x64 first
> - **Linux x64:** `NOT RUN` unless actually compiled and executed there
> - **Code license:** GPL-2.0-only; do not include commercial game data
> - **Upstream:** `../doom-original`, commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M2-07 finalized and committed; verify branch/HEAD and `v0.2.0` tag independently
> - **Read first:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, current code and tests, then this task

## 1. Objective and acceptance boundary

Implement a reusable and rigorously verified **signed 32-bit 16.16 fixed-point math foundation** for future Doom geometry, BSP drawing and player movement. Match the *observable* behavior of `FixedMul`, `FixedDiv` and the successful/numeric portion of `FixedDiv2` in the pinned original Linux Doom 1.10 source, including negative rounding, early saturation and overflow boundaries. Define safe PureBasic behavior for C undefined/implementation-defined cases and explicitly document those choices.

The principal deliverable is `src/Core/Fixed.pbi`, a small standalone `tests/unit/fixed_math_tests.pb` suite, and integration into the existing build/test scripts. It must be usable independently of WAD, windows, renderer and game state.

**This is M3-01, not M3 as a whole.** No geometry renderer or wall drawing yet. Do not claim a playable Doom or `v0.3.0`. The application continues to report `DoomPB 0.2.0`.

### Non-goals

- No `R_PointToAngle`, `R_PointOnSide`, `R_ScaleFromGlobalAngle`, BAM-angle tables, `finesine`, `finetangent`, `tantoangle` or trigonometry; those belong to M3-02.
- No BSP traversal for rendering, perspective projection, wall clipping, column drawing, camera, viewport, visplanes, sprites, gameplay, 35 Hz loop, or sound.
- No replacing vanilla mathematics with floating-point gameplay calculations, vectorization, alternative game engine, SDL or C DLL.
- No rewriting existing WAD, resource, texture, map or framebuffer modules unless a concrete regression demonstrates the need for a tiny fix.
- No persistent use of a reference C program at runtime. A disposable or test-only reference comparator is allowed but must not be a production dependency.
- No release/version update, Git commit, tag, push or unrelated refactor.

## 2. Mandatory initial inspection

Before editing:

1. Run `git status --short --branch`, `git log -1 --oneline`, `git tag --list`, `git diff --stat`, `git diff --cached --stat`. Verify M2-07 was committed. Check for `v0.2.0`, but **do not create it** if absent; report the actual state. Preserve preexisting user changes, staged content and task documents.
2. Read `src/Core/Endian.pbi`, `src/DoomPB.pb`, `src/Map/MapTypes.pbi`, `src/Map/MapDecode.pbi`, the `MapLevel` accessors, existing PureBasic type conventions, all relevant `scripts/{build,test}.{ps1,sh}`, and established unit-test harness patterns. Inspect only what is necessary to understand module inclusion and runner configuration.
3. Verify `git -C ../doom-original rev-parse HEAD` equals the pinned SHA. Inspect **actual** `linuxdoom-1.10/m_fixed.h` and `m_fixed.c`, including the **active**, not `#if 0`, implementation of `FixedDiv2`. For consumers, inspect selected calls in `p_maputl.c`, `r_main.c` and `r_segs.c` as context only.
4. Check actual PureBasic **6.41** language rules for signed `.l`, signed `.q`, integer division, casts/narrowing, arithmetic shifts, signed `Mod` or remainder, and pointers/results. Use small disposable compiler probes outside production modules. Do not import assumptions from C, C# or other BASIC dialects.
5. **Before implementation**, explain in a short plan: exact files, API and return types, 32-bit wrap policy, negative rounding algorithm, overflow/saturation rules, checked `FixedDiv2` error semantics, standalone tests and test-runner integration.

**Known historical regression baseline from M2-07 report:** 371/371 test cases and 2088/2088 assertions when the optional owner IWAD is present; 370/370 and 2069/2069 without it; 64/64 script checks on Windows. These are historical reported results, **not** permission to skip rerunning the actual suites. Linux compilation/runtime was not verified.

## 3. Fixed-point representation and exact constants

`fixed_t` in original `m_fixed.h` is a **signed 32-bit** integer interpreted as **16 integer bits and 16 fractional bits**:

```text
FRACBITS = 16
FRACUNIT = 1 << 16 = 65536
FIXED_MIN = -2147483648  = 0x80000000
FIXED_MAX =  2147483647  = 0x7FFFFFFF
  1.0 =>   65536
 -1.0 =>  -65536
  0.5 =>   32768
 -0.5 =>  -32768
```

- Prefer an explicit `Fixed32.l` convention (or well-commented `.l` signatures) and `.q` for intermediate arithmetic. `Long` in PureBasic is 32-bit; native `.i` is pointer-sized and **must not** substitute for fixed-point values.
- `FRACUNIT` is not a floating-point unit. Operations must remain integer based in production unless a demonstrable reference-compatibility problem requires a documented and tested exception.
- A map vertex/sector height is a signed 16-bit integer number of map units. Converting it to 16.16 must multiply by 65536 in a 64-bit temporary and then confirm the 32-bit range. `-32768` is representable; `+32768` is not.
- Do not treat the entire unsigned 32-bit bit pattern as a nonnegative fixed value. Verify sign extension and two's-complement interpretation when converting or masking.
- Do not replace Doom's signed right shifts by truncation toward zero. That changes negative subpixel behavior.

### Proposed narrow public API

Adapt these **conceptual names** to existing project conventions and valid PureBasic 6.41 syntax:

```text
DoomFixedMul(A.l, B.l) -> .l
DoomFixedDiv(A.l, B.l) -> .l
DoomFixedDiv2Checked(A.l, B.l, *Result.l) -> boolean
DoomFixedFromIntChecked(Value.i or Value.q, *Result.l) -> boolean
DoomFixedToIntFloor(Value.l) -> integer
DoomFixedLastError() -> string    [only if error-returning helpers need it]
```

The names are suggestions; preserving recognizable `FixedMul` / `FixedDiv` names may be preferable if they do not collide with existing declarations. Do not invent APIs by analogy without checking source. If `ToIntTrunc` is added, clearly distinguish its behavior from a signed arithmetic shift; **do not** let it silently replace the original renderer's `>> FRACBITS`.

Keep the module dependency-free and free of heap allocations. Ordinary value-returning multiply/divide operations should not require a `Magic` state object. For checked helpers, return `False` on invalid input without modifying `*Result`, or use another explicitly documented deterministic failure contract. Do not hide errors in an ambiguous numeric sentinel.

## 4. Original C behavior: `FixedMul`

Pinned upstream `m_fixed.c` computes the following in C:

```c
return ((long long) a * (long long) b) >> FRACBITS;
```

The 64-bit signed multiplication is safe for any pair of signed 32-bit operands. On the original arithmetic-shift targets, the right shift of a negative product is equivalent to **flooring** the real quotient by 65536 (toward negative infinity), **not** truncating toward zero:

```text
FixedMul(     1,     -1) = -1
FixedMul(    -1,     -1) =  0
FixedMul( 32768, -32768) = -16384
FixedMul( 65536,  65536) = 65536
```

**Overflow semantics:** the final C result has type `fixed_t` (`int32`). Narrowing an out-of-range signed 64-bit intermediate to a C `int` is implementation-defined. Adopt an explicit **low 32-bit two's-complement wrap** convention matching the target behavior; this function must **not saturate**, because the original `FixedMul` does not. Do not rely on unspecified PureBasic narrowing behavior: implement or prove it with compiler tests. Example target values for this convention:

```text
FixedMul( 2147483647, 2147483647) = -65536
FixedMul(-2147483648,-2147483648) = 0
FixedMul(-2147483648,      65536) = -2147483648
```

Do not obtain the correct answer only accidentally through a cast. Test the boundary explicitly. A helper that implements the signed arithmetic shift using checked 64-bit division and remainder is acceptable if PureBasic's shift behavior is unclear. The returned result must exactly match the defined 32-bit signed bit pattern.

## 5. Original C behavior: `FixedDiv`

Pinned upstream `m_fixed.c` uses an **early guard**:

```c
if ((abs(a) >> 14) >= abs(b))
    return (a ^ b) < 0 ? MININT : MAXINT;
return FixedDiv2(a, b);
```

Implement the guard faithfully, **before** evaluating a quotient. This is an intentionally conservative check. Do not replace it with a mathematically ideal 32-bit range check: the results would differ from vanilla Doom.

- Compute absolute magnitudes using **signed 64-bit widening**, so `abs(-2147483648)` becomes the valid magnitude `2147483648`. The original C expression `abs(INT_MIN)` has undefined behavior; explicit widening is a deliberate safety improvement.
- Compare `(magnitudeA >> 14) >= magnitudeB` exactly. Keep it distinct from the `FRACBITS = 16` division shift.
- Saturate to `FIXED_MIN` if the operand sign bits differ, otherwise `FIXED_MAX`. Sign handling must work with a **zero denominator**, too.
- Within the non-saturating branch, return a fixed-point quotient truncated **toward zero**, matching valid original `FixedDiv2` output. A widened integer expression for the quotient is preferred, as long as parity with the original active `double` implementation is checked on all golden and differential cases.
- For `b = 0`, the guard is always true, so `FixedDiv` returns a saturated value rather than attempting division. Specifically `FixedDiv(0,0) = FIXED_MAX`, `FixedDiv(positive,0) = FIXED_MAX`, `FixedDiv(negative,0) = FIXED_MIN` under the original guard.

Critical golden vectors:

```text
FixedDiv( 65536,  65536) =      65536
FixedDiv( 65536,  32768) =     131072
FixedDiv(     1,      3) =      21845
FixedDiv(     1,     -3) =     -21845
FixedDiv( 16383,      1) = 1073676288
FixedDiv( 16384,      1) = 2147483647  [EARLY SATURATION]
FixedDiv(-16384,      1) = -2147483648 [EARLY SATURATION]
FixedDiv(     0,      0) = 2147483647
FixedDiv(   123,      0) = 2147483647
FixedDiv(  -123,      0) = -2147483648
FixedDiv(-2147483648, 1) = -2147483648
FixedDiv(-2147483648,-2147483648) = 65536
```

Do not claim that `FixedDiv` saturates **only** when the mathematical quotient exceeds signed 32-bit range; the 16384/1 case disproves that claim.

## 6. `FixedDiv2` and floating-point reference parity

The pinned C source includes a `#if 0` integer implementation, but the **active** implementation is:

```c
c = ((double)a) / ((double)b) * FRACUNIT;
if (c >= 2147483648.0 || c < -2147483648.0)
    I_Error(...);
return (fixed_t)c;
```

It performs a floating-point calculation and truncates toward zero when converting a representable finite `double` to `int32`. `FixedDiv2` is not automatically a saturating variant of `FixedDiv`. Distinguish the APIs.

Preferred safe PureBasic design:

1. Expose **`FixedDiv`** as the normal non-failing, vanilla-compatible function with the early guard above.
2. Expose a **checked** direct `FixedDiv2` equivalent, if it is part of the module interface: on `b = 0` or out-of-range result, return an explicit error/`False` instead of calling a fatal engine function or allowing a runtime crash. The original would call `I_Error` on an out-of-range floating result; DoomPB must report the condition safely.
3. Use an independent comparison with the original active `double` formula over a deterministic sample of representable inputs, plus boundary vectors. If a valid in-range pair differs by one ULP or one integer unit, investigate FPU rounding and document it; do not silently change the defined result or round to nearest.
4. If direct `FixedDiv2` is unnecessary for current consumers, a checked helper is sufficient. Do not introduce a knowingly crash-prone public divide-by-zero API merely for C name symmetry.
5. Never evaluate an unchecked `a << 16` on a **signed negative 32-bit** value; this is undefined in C and may produce incorrect PureBasic results. Widen and multiply instead.

### Why these details matter

A single off-by-one error in signed fixed-point arithmetic can later change BSP side selection, projection, wall columns and even demo determinism. This milestone is the right place to lock down semantics with tests, while no renderer depends on them yet.

## 7. Checked conversions and strict type boundaries

Implement only small helpers that genuinely help the future renderer:

- Convert integer/map-unit coordinates to 16.16 via `Value * 65536` in `.q`, then range-check against `FIXED_MIN/MAX` before narrowing.
- Test `-32768` success and `+32767` success; `+32768` and `-32769` must be rejected if a wide integer input API accepts them.
- A floor-style extraction of the integer part must match arithmetic `>> 16`: e.g. `-1` fixed unit has integer floor `-1`; `-65537` has floor `-2`.
- An optional separate `ToIntTrunc()` may return `0` and `-1` respectively. If provided, name it unambiguously and test it.
- Preserve negative fractional bits; avoid `Abs()` on signed32 minimum and avoid intermediate `.l` products.
- Keep helper API independent from `MapLevel` so the math module can be unit tested without WAD or commercial resources.

Document any fixed-point helpers intentionally postponed to M3-02; do not add trigonometry or lookup arrays now.

## 8. Planned implementation files and build integration

Prefer the smallest cohesive change:

```text
+ src/Core/Fixed.pbi
+ tests/unit/fixed_math_tests.pb
  scripts/build.ps1
  scripts/build.sh
  scripts/test.ps1
  scripts/test.sh
  docs/PORTING_NOTES.md
  README.md                         [brief M3-in-progress status, only if needed]
  CHANGELOG.md                      [unreleased M3 entry, if project convention uses it]
  docs/tasks/M3_01_OPENCODE_TASK.md [owner-provided assignment, do not overwrite]
```

Use the established Windows PowerShell and Linux Bash test-target convention. Suggested names `-FixedTest` (PowerShell) and `--fixed-test` (Bash), adjusted to the actual script style. Test harness must be **standalone** and never attempt to open Doom's application window or require an IWAD.

- All new entry-point test `.pb` sources start with `EnableExplicit`.
- Include order is explicit and acyclic. Avoid adding production code to `src/DoomPB.pb` unless a compile smoke check requires it; if included, change no gameplay/CLI logic.
- Preserve existing targets, error exit codes and `--version` output `DoomPB 0.2.0`.
- Add test compilation and execution to both `test.ps1` and `test.sh`, honoring unavailable compilers as `NOT RUN` rather than PASS.
- No hardcoded local PureBasic path in tracked scripts. Use existing `PB_COMPILER` discovery mechanisms.
- Do not change `AGENTS.md` or the roadmap without a specific compatibility issue that requires it.

## 9. Mandatory tests — FM01–FM40

Implement **40 named, independently reportable synthetic scenarios**. The following table describes required coverage, not exact PureBasic syntax. Each case should contain sufficient assertions to make a meaningful failure.

| ID | Case | Required property |
|---|---|---|
| FM01 | Constants/type | FRACBITS=16, FRACUNIT=65536, signed 32-bit limits |
| FM02 | Map-unit conversion | -32768, -1, 0, +1, +32767 scale exactly |
| FM03 | Conversion failures | +32768 and -32769 cannot fit 16.16; output intact on failure |
| FM04 | Integer floor | -1 and -65537 fixed values floor to -1 and -2 |
| FM05 | Optional truncation | If `ToIntTrunc` exists, negative fractions truncate to zero |
| FM06 | Zero multiply | `FixedMul(x,0)=0` for small/extreme x |
| FM07 | Unit multiply | `FixedMul(x,FRACUNIT)=x` across signed range |
| FM08 | Positive half multiply | `0.5*0.5` equals 0.25 in 16.16 |
| FM09 | Negative half multiply | `-0.5*0.5` equals -0.25 |
| FM10 | Positive fractional product | Non-integer quotient rounds down correctly |
| FM11 | Negative fractional product | `FixedMul(1,-1)=-1`, not zero |
| FM12 | Tiny double negative | `FixedMul(-1,-1)=0` |
| FM13 | High positive product | `FixedMul(INT32_MAX,INT32_MAX)=-65536` under specified wrap |
| FM14 | Extreme negative product | `FixedMul(INT32_MIN,INT32_MIN)=0` under specified wrap |
| FM15 | Mixed extreme product | `FixedMul(INT32_MIN,FRACUNIT)=INT32_MIN` |
| FM16 | Commutativity | `FixedMul(a,b)=FixedMul(b,a)` for representative pairs |
| FM17 | Exhaustive tiny domain | Test each pair `a,b` in [-32,32] using independent floor oracle |
| FM18 | Bit-pattern spread | Deterministic set of positive/negative and near-limit operands |
| FM19 | Divide by unit | `FixedDiv(x,FRACUNIT)` for representative valid x |
| FM20 | Divide halves/doubles | `FixedDiv(FRACUNIT,32768)=131072` etc. |
| FM21 | Divide sign combinations | ++, +-, -+, -- produce expected signs |
| FM22 | Positive quotient truncation | `FixedDiv(1,3)=21845` |
| FM23 | Negative quotient truncation | `FixedDiv(1,-3)=-21845` |
| FM24 | Positive overflow guard | Return INT32_MAX for numerator magnitude above guard threshold |
| FM25 | Negative overflow guard | Return INT32_MIN with sign mismatch |
| FM26 | Conservative guard | `FixedDiv(16384,1)=INT32_MAX`, even though true quotient fits |
| FM27 | Threshold below guard | `FixedDiv(16383,1)=1073676288` |
| FM28 | Positive / zero | `FixedDiv(123,0)=INT32_MAX` |
| FM29 | Negative / zero | `FixedDiv(-123,0)=INT32_MIN` |
| FM30 | Zero / zero | `FixedDiv(0,0)=INT32_MAX` |
| FM31 | Zero / nonzero | `FixedDiv(0,b)=0` for signed nonzero b |
| FM32 | INT32_MIN numerator | Safe magnitude; no `Abs()` overflow |
| FM33 | INT32_MIN divisor | Defined quotient; no intermediate overflow |
| FM34 | Checked Div2 zero | Return error safely, no crash or stale output |
| FM35 | Checked Div2 overflow | Return error for mathematically out-of-range result |
| FM36 | Checked Div2 exact minimum | -2147483648 result is valid, not overflow |
| FM37 | Differential division | >=10,000 deterministic inputs against independent guarded oracle |
| FM38 | Negative arithmetic shift | Verify PB shift behavior or portable floor implementation |
| FM39 | Signed narrowing | Verify explicit 32-bit wrap across both signs |
| FM40 | Repeatability/error clearing | Repeated calls same results; checked failures do not contaminate success |

### Oracle construction guidelines

- **Use two independently expressed implementations.** Avoid deriving expectations by calling the same production helper twice under different names. For example, a `.q` division/remainder-based floor oracle can check a shift-based production multiply, or vice versa; account for negative products explicitly.
- For division, the oracle should express the literal C guard with safe widened magnitudes, then compute the quotient separately. Compare the non-guard path against the **active** original `double` formula on a selected reference dataset. Do not use C `abs(INT_MIN)` or signed-left-shift UB in a reference harness.
- Use a documented, fixed seed for randomized/property cases and include it in failure reports. Inputs in the `INT32_MIN` boundary, zero denominators, sign crossings and threshold region are mandatory even if random sampling misses them.
- Where fixed-point decimal literals might be rounded before conversion, prefer **raw signed integer values** in tests. Never use production conversion helpers to generate every golden test input.
- Only store numerical pairs, integer results and concise hashes in fixtures. There is no need to include WAD assets or images.
- A test compiler `--check` success is not execution. Compile, run, and capture zero exit status.

## 10. Synthetic integration and optional map fixture

Add at least **three** lightweight integration scenarios alongside or after FM01–FM40:

**FI01 — Standalone module inclusion:** Include `Fixed.pbi` in a new `EnableExplicit` entry point without linking or initializing WAD, graphics or MapLevel. Compile and execute value tests.

**FI02 — Map-coordinate bridge:** Create synthetic signed map vertex/sector height values (including -32768 and +32767), convert them to 16.16 with checked helpers, verify exact numerical bits, and confirm no float rounding. Never mutate the M2 map decoder's owned data.

**FI03 — Error/boundary and deterministic repeat:** Execute a fixed sequence of multiply/divide/conversion operations twice after an intentional checked-division error; compare explicit results or a canonical numeric checksum. No dependency on random system seed, process address or struct padding.

**Optional FI04 — Original Ultimate Doom read-only:** If `data/DOOM.WAD` exists and existing map APIs are easily reusable, load E1M1/E1M2/E4M1, convert selected signed integer vertex coordinates and sector heights into fixed values, check bounds and reproducibility, then close the WAD. Do **not** invent fixed geometry expected hashes without measuring independently. No proprietary coordinates/entire level tables should be printed. If data or compiler is unavailable, mark FI04 `NOT RUN` (not FAIL for standard synthetic CI).

The math suite must run **without commercial assets** on a clean checkout. Avoid unnecessary import of large map modules into `Fixed.pbi` just to implement FI02/FI04.

## 11. Acceptance gates and commands

Follow the established agent workflow: **inspect → short plan → implement → syntax check → compile → execute tests → review diff → report**.

Windows PowerShell commands (adapt paths/flags after inspecting existing scripts):

```powershell
./scripts/build.ps1 -Check
./scripts/build.ps1 -Check -FixedTest
./scripts/build.ps1 -FixedTest
./scripts/test.ps1
./scripts/build.ps1
./build/DoomPB.exe --version
```

Do not use an imaginary script flag simply because it appears above: add and test it first, following current convention. Verify all existing test targets still run. If there is already a better unit-test selector, integrate into that without duplicate targets.

Linux: syntax-check scripts if a real Bash is available and run the PureBasic Linux compiler and tests **only when installed**. Do not treat WSL stubs or shell syntax checks as proof of Linux runtime. Maintain `NOT RUN` otherwise.

Mandatory acceptance:

1. Every FM01–FM40 case passes, plus FI01–FI03; optional FI04 properly reports PASS or NOT RUN.
2. Independently checked golden results cover all negative shifts, saturating guard and safe minimum-value boundaries.
3. `FixedDiv` returns deterministic values for every signed32 input pair, including b=0; checked `FixedDiv2` rejects invalid cases without crashing.
4. Standalone compilation proves no WAD/display dependencies and stable `.l` results.
5. Full M0/M1/M2 regression suite passes **after** modifications; if an unrelated pre-existing regression fails, report and investigate without making unrequested sweeping changes.
6. `--version` prints **DoomPB 0.2.0**; `--show-title`, `--map-info E1M1` (with local IWAD) and other CLI modes remain unaffected.
7. Windows PureBasic 6.41 syntax check, real build and full test execution PASS. No fabricated Linux PASS.
8. `git diff --check`, `git diff --cached --check`, untracked-file trailing whitespace inspection and commercial asset audit PASS.
9. No `git add`, `commit`, `tag`, `push` or unrelated file changes. No M3-02 or renderer implementation.

## 12. Legal, provenance and safety checks

- GPL-2.0-only project. Cite the original C function/file and pinned SHA in `docs/PORTING_NOTES.md` without copying the entire C source or replacing the PureBasic implementation with an external engine/library.
- Keep user's local `DOOM.WAD` read-only and ignored. No copies of game pixels, sounds, models, map dumps or assets in tracked files or test logs.
- No absolute developer paths, build binaries, screenshots, DLLs, PNG/BMP or WAD assets in the Git diff.
- No trailing spaces or tabs at end of lines, including Markdown. Use LF line endings for new task documentation and any new test fixture text.
- Do not weaken Git's whitespace checks through `.gitattributes` or other configuration.
- Do not create release notes for `v0.3.0` at this stage. If using CHANGELOG, label work as **Unreleased**.

## 13. Required final agent report

Use these headings and actual observed results:

```text
Task / milestone: M3-01 — Fixed-point Math
OS / PureBasic exact compiler version; Linux runtime status:
Git baseline HEAD / branch / staged / unstaged / untracked / v0.2.0 tag:
Original C reference: commit, files, exact FixedMul/FixedDiv/FixedDiv2 behavior:
Files created and changed:
Public API and numeric representation:
FixedMul: negative shift and 32-bit narrowing policy, observed golden vectors:
FixedDiv: original overflow guard and b=0 semantics, observed golden vectors:
FixedDiv2Checked: valid domain, error handling, float/reference comparison:
Checked conversion behavior and signed-coordinate boundaries:
Syntax check: command, PASS/FAIL/NOT RUN:
Build: command, PASS/FAIL/NOT RUN:
FM01–FM40: cases/assertions and failures:
FI01–FI03: cases/assertions and failures:
FI04 optional IWAD integration: PASS/FAIL/NOT RUN and reason:
Previous M0/M1/M2 regression: actual totals:
CLI regression: --version, --show-title, --map-info:
Linux compiler/test runtime: PASS/FAIL/NOT RUN with reason:
Git diff/status and whitespace/resource audit:
Differences from original C; unresolved portability/overflow risks:
Suggested Conventional Commit message (DO NOT COMMIT):
Suggested next task: M3-02 — Angles and Geometry (DO NOT START)
```

### Final Definition of Done

The result is an independently compiled and tested, dependency-free PureBasic 6.41 **signed 16.16 math module** whose multiplication, early-saturating division, checked direct division and conversions behave deterministically across the important original Doom boundaries. The full existing project remains buildable; version stays `0.2.0`. No geometry or rendering yet.
