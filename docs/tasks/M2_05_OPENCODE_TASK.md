# DoomPB — M2-05: Vanilla Doom map binary structures and safe decoders

> - **Task ID:** `M2-05`
> - **Milestone:** M2 — Resources, textures and level data; `v0.2.0` is **not** complete
> - **Status:** implementation assignment, not an implementation report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Reasoning:** High; use Extra High only for a demonstrated blocking ambiguity
> - **Language/compiler:** PureBasic 6.41 (full edition)
> - **Primary target:** Windows x64; Linux x64 status must be `NOT RUN` unless genuinely compiled and executed
> - **License:** GPL-2.0-only; do not distribute commercial IWAD data
> - **Reference:** `../doom-original`, pinned commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M2-04 verified; check its actual Git commit status before editing
> - **Read first:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, relevant code/tests and this assignment

## 1. Objective

Implement **format-accurate, independently testable, bounds-checked decoders** for the ten vanilla Doom map lumps:

```text
map marker (E1M1, E1M2, E4M1 or MAPxx in the generic format)
  +1 THINGS       +2 LINEDEFS    +3 SIDEDEFS    +4 VERTEXES
  +5 SEGS         +6 SSECTORS    +7 NODES       +8 SECTORS
  +9 REJECT      +10 BLOCKMAP
```

Produce a clear native PureBasic representation for each record type, without depending on PureBasic's in-memory structure layout matching the on-disk packed format. Preserve original raw fixed-width values where later Doom behavior depends on them. Validate payloads before all allocations, indexing or arithmetic. Include synthetic tests and optional read-only metadata integration with the user's legal Ultimate Doom 1.9ud IWAD.

**M2-06**, not this task, will discover and load a complete named map, cross-validate all inter-lump references, resolve sector textures/flats, establish BSP relationships and expose usable level objects. M2-05 may use a **test-only** helper to read the ten known contiguous lumps; do not introduce a production `MapLoader` prematurely.

### Explicit non-goals

- No geometry linking, runtime `line_t`/`sector_t`/`seg_t` graph, fixed-point conversion, BSP traversal, renderer, spatial/collision simulation, thing spawning or gameplay.
- No `TEXTMAP`, UDMF, Hexen-format linedefs/things, ZDoom/GL/extended nodes, compressed nodes or Doom 64 formats. Detect unsupported variants rather than silently decoding them as vanilla.
- No multi-WAD overlays, PWAD mounting, lump cache overhaul or WAD API redesign.
- No `REJECT` visibility optimization, `BLOCKMAP` collision queries or regenerated blockmap. Provide safe structure and optional read-only accessors only.
- No dumping of proprietary map geometry, named asset lists, full record tables, images or other reconstructable content into repository fixtures/logs.
- No CLI refactoring or new version: retain `DoomPB 0.1.0`, no release/tag `v0.2.0`.

## 2. Initial inspection and short implementation plan

Before changing files:

1. Run `git status --short --branch`, `git log -1 --oneline`, `git tag --list`, `git diff --stat` and `git diff --cached --stat`. Verify **M2-04 is committed**; if it is not, preserve everything and report the mismatch instead of claiming a clean baseline. Do not stage or commit anything.
2. Read actual APIs and ownership contracts of `src/Core/Endian.pbi`, `src/WAD/WAD.pbi`, `src/Graphics/Flat.pbi`, `src/Graphics/Sprite.pbi`, `src/DoomPB.pb`; inspect test harnesses for M2-01 through M2-04 and `scripts/{build,test}.{ps1,sh}`. Never invent function signatures.
3. Verify pinned upstream SHA with `git -C ../doom-original rev-parse HEAD`. Inspect `linuxdoom-1.10/doomdata.h`: `ML_*`, `mapvertex_t`, `mapthing_t`, `maplinedef_t`, `mapsidedef_t`, `mapseg_t`, `mapsubsector_t`, `mapnode_t`, `mapsector_t`, `NF_SUBSECTOR`; and `p_setup.c`: `P_Load*`, `P_LoadBlockMap`, `P_SetupLevel`. Inspect `p_maputl.c` and `p_sight.c` if needed for `BLOCKMAP`/`REJECT` interpretation.
4. Look at the installed PureBasic 6.41 documentation/real compiler to confirm `AllocateMemory`, `CopyMemory`, signed/unsigned numeric fields, `PeekW` alternatives, arrays, and zero-initialization. Make tiny isolated compile probes where syntax is uncertain.
5. Present a **brief plan** with exact files, chosen API/data layout, memory caps, raw-versus-semantic validation boundary, test identifiers and cleanup strategy before implementing.

The preceding M2-04 report recorded: Windows x64 PureBasic 6.41; M1 96/96 cases (694 assertions), M2-01 31/31 (191), M2-02 33/33 (165), M2-03 30/30 (141), M2-04 39/39 (300); script checks 52/52. These are **historical numbers**, not substitutes for rerunning tests. Its baseline was `117708d`; do not assume that is the current HEAD.

## 3. Proposed module boundaries and API

Prefer a small, cohesive arrangement; exact names may follow existing conventions:

```text
src/Map/MapTypes.pbi           # typed decoded records, constants, ownership
src/Map/MapDecode.pbi          # eight fixed-record lump decoders + REJECT
src/Map/Blockmap.pbi           # BLOCKMAP layout and checked access
 tests/unit/wad_map_types_tests.pb
```

One `MapDecode.pbi` plus `MapTypes.pbi` is acceptable if `BLOCKMAP` can remain clearly isolated. Do not create empty future `MapLoader.pbi` or `MapValidate.pbi` placeholders.

Suggested conceptual (not guaranteed PB syntax) API:

```text
MapRecordsDecode(Kind, *Bytes, Length.q, *Result) -> boolean
MapRecordsCount(*Result) -> integer
MapRecordsGetThing / GetLinedef / GetSidedef / GetVertex / GetSeg /
  GetSubsector / GetNode / GetSector(*Result, Index, *Fields...) -> boolean
MapRecordsNameByte(*Result, Index, Field, ByteIndex) -> 0..255 or error
MapRecordsReset(*Result)

MapRejectDecode(*Bytes, Length.q, *Result) -> boolean
MapRejectGetBit(*Result, SectorCount, FromSector, ToSector) -> 0/1/error
MapRejectReset(*Result)

MapBlockmapDecode(*Bytes, Length.q, *Result) -> boolean
MapBlockmapGetHeader / GetBlockList / GetLineIndex(*Result, ...) -> checked result
MapBlockmapReset(*Result)
MapDecodeLastError() / MapBlockmapLastError() -> diagnostic
```

Alternative names and structures are fine. Minimize public API duplication and avoid enormous unions or per-record heap allocations. A `MapRecordSet {Magic, Kind, Count, *Records}` may hold **owned native records**, or dedicated type arrays may be simpler. The public API must expose **all** needed fields, including raw eight-byte names, raw angles/flags and child bits.

**Ownership:** caller zero-initializes result objects once; decoder takes its own copies of data; reset frees owned allocations and is idempotent. A failed decode clears previous output (consistent with prior DoomPB modules) and returns a deterministic diagnostic. Results remain usable when the input lump byte buffer is freed and WAD closed. Don't store borrowed WAD pointers or assume a packed 10/14/30-byte native PB structure. Define safe behavior for zero-length fixed-record lumps (an empty table may succeed where meaningful; see section 6).

## 4. Vanilla Doom map format: precise disk layout

All multibyte fields are **little-endian**. A `s16` is signed -32768..32767; a `u16` is unsigned 0..65535. These labels specify the intended **decoded semantics**; the upstream C types are mostly `short` and need interpretation at point of use. Keep the raw bits retrievable, particularly for flags and node children.

| Lump | Packed record size | Fields in disk order |
|---|---:|---|
| `THINGS` | 10 | `x:s16`, `y:s16`, `angle:s16`, `type:s16`, `options:s16` |
| `LINEDEFS` | 14 | `v1:u16`, `v2:u16`, `flags:u16`, `special:s16`, `tag:s16`, `sidenum[0]:s16`, `sidenum[1]:s16` |
| `SIDEDEFS` | 30 | `textureoffset:s16`, `rowoffset:s16`, `toptexture:byte[8]`, `bottomtexture:byte[8]`, `midtexture:byte[8]`, `sector:u16` |
| `VERTEXES` | 4 | `x:s16`, `y:s16` |
| `SEGS` | 12 | `v1:u16`, `v2:u16`, `angle:u16`, `linedef:u16`, `side:s16`, `offset:s16` |
| `SSECTORS` | 4 | `numsegs:u16`, `firstseg:u16` |
| `NODES` | 28 | `x:s16`, `y:s16`, `dx:s16`, `dy:s16`, `bbox[2][4]:s16`, `children[2]:u16` |
| `SECTORS` | 26 | `floorheight:s16`, `ceilingheight:s16`, `floorpic:byte[8]`, `ceilingpic:byte[8]`, `lightlevel:s16`, `special:s16`, `tag:s16` |
| `REJECT` | variable | Opaque bytes, bitset interpreted using sector count |
| `BLOCKMAP` | variable | Four 16-bit header words; unsigned word offsets; variable terminated blocklists |

In `doomdata.h` some index-bearing fields are declared `short`. Reading them as `u16` preserves all 16 bits and defers whether a value is valid to M2-06. For `LINEDEFS.sidenum[]`, preserve signed `-1` sentinel (one-sided wall); do **not** coerce to index 65535. `LINEDEFS.flags` is a bitfield; do not sign-extend it or discard high bits. Preserve signed heights and offsets, even when unexpected.

### 4.1 THINGS (10 bytes)

- `x/y` are **map units**, not 16.16 fixed-point yet.
- Keep `angle`, `type`, `options` exact, including unusual values; gameplay interpretation is later.
- Do not spawn entities or special-case deathmatch/player starts at parse time.

### 4.2 LINEDEFS (14 bytes)

- The ordered vertex indices must be retained exactly. Do **not** resolve them or reject out-of-range indices until combined-map validation in M2-06.
- `sidenum[0]` is front and `sidenum[1]` is back. `-1` means no back side; retain both values and signedness. An invalid negative value other than `-1` can be reported later as a semantic error, not an unsafe memory access here.
- Keep `flags`, `special`, `tag` raw. The `ML_TWOSIDED` bit is not permission to index `sidenum[1]` without checking it.

### 4.3 SIDEDEFS (30 bytes)

- Preserve the three **independent eight-byte names** with no assumption of NUL termination. A name may contain a `-` no-texture marker, but resource resolution is M2-06 work.
- Keep signed texture/row offsets. Store sector field as a nonnegative 16-bit word; validate against sector count later.
- Accessors should allow retrieving each raw name byte and a bounded printable representation for diagnostics, with no Unicode normalization of raw bytes.

### 4.4 VERTEXES (4 bytes)

- Keep negative and extreme `s16` positions without converting to floating-point/fixed-point.
- Test the full `-32768`, `32767` boundary.

### 4.5 SEGS (12 bytes) and SSECTORS (4 bytes)

- `SEGS.angle` is a raw unsigned 16-bit binary angle representation; avoid converting it to degrees or `angle_t` in the decoder.
- Keep `SEGS.offset` signed map units. The `side` field is a signed 16-bit value; validate `0/1` in M2-06, not by indexing a sides array here.
- `SSECTORS.firstseg` and `numsegs` are independent unsigned 16-bit counts/offsets. Do not assume the range fits before other lumps have been loaded.

### 4.6 NODES (28 bytes)

The precise byte positions for each node are:

```text
+00  x:s16         +02  y:s16
+04  dx:s16        +06  dy:s16
+08  bbox[0][0]:s16  +10 bbox[0][1]:s16
+12  bbox[0][2]:s16  +14 bbox[0][3]:s16
+16  bbox[1][0]:s16  +18 bbox[1][1]:s16
+20  bbox[1][2]:s16  +22 bbox[1][3]:s16
+24  children[0]:u16 +26 children[1]:u16
```

- Preserve original bbox order `[top, bottom, left, right]` (as used by Doom bounding boxes); do not reorder as x/y/width/height.
- `NF_SUBSECTOR = $8000`. A child with `(rawChild & $8000) != 0` refers to a **subsector**; index is `rawChild & $7FFF`. Otherwise it refers to a **node**. Preserve the raw 16 bits and expose derived kind/index through safe helpers, but **do not traverse the graph** in this task.
- `0x8000` legitimately identifies subsector index `0`. `0xFFFF` means a flagged subsector index `32767`, **not** a generic null child. Out-of-range children are rejected by M2-06 after counts are known.

### 4.7 SECTORS (26 bytes)

- Heights are signed map units; lightlevel/special/tag remain raw signed 16-bit values.
- Floor and ceiling pic names are separate 8-byte fields. Keep raw bytes; no flat resolution, `F_SKY1` renderer interpretation or light calculations here.

## 5. REJECT format and safe optional access

`REJECT` is a byte-oriented matrix of potential inter-sector visibility. For a map with `N` sectors it contains at least `ceil(N*N/8)` usable bytes. Bit `from * N + to`, stored **LSB-first within each byte**, means rejection when set. Use checked 64-bit products for all calculations.

**Separation of concerns:** M2-05 cannot know `N` while decoding `REJECT` alone. `MapRejectDecode` should retain an **owned copy of the raw bytes**, including a possible empty lump; it must not guess sector count. A separate accessor may take `SectorCount` and validate that sufficient bytes exist, both sector indexes are in range, and the multiplication cannot overflow. When short/empty for a requested pair, return a clear error; never read beyond memory or silently reinterpret a missing byte as valid data. Full `REJECT`-versus-`SECTORS` size policy belongs to M2-06.

Test LSB order, cross-byte boundaries, non-square bit indexes, zero sector count, excessively large counts, negative indices and truncated buffer. Do not conflate a 0 bit with a failed lookup.

## 6. BLOCKMAP format: word offsets, not byte offsets

Header is **8 bytes**, containing four LE16 words:

```text
byte 0: originX:s16
byte 2: originY:s16
byte 4: width:u16  (positive number of blocks)
byte 6: height:u16 (positive number of blocks)
byte 8: offsets[width * height]:u16
then: one or more variable-length blocklists in 16-bit words
```

Each offset entry is an **unsigned count of 16-bit words from the beginning of the BLOCKMAP lump**. Convert with `bytePosition = offsetWords * 2`, checked in `.q`; `0x8000..0xFFFF` are valid numeric offset values if the data is long enough. Do not sign-extend offsets, treat `0xFFFF` as a missing-offset sentinel, or multiply them by four.

A standard blocklist is a sequence of LE16 words, with an initial dummy `0x0000`, zero or more linedef indexes, and a final terminator `0xFFFF`. It is legal for **multiple cells to reference the same list offset**. A linedef entry of zero is valid and may repeat the dummy; do not deduplicate or skip arbitrary line references. The terminator is only a list terminator, not a header/table sentinel. Preserve the order of line references.

Validation required:

1. Reject null pointer, odd byte length, buffer shorter than eight bytes, zero dimensions and unreasonable grid dimensions/budgets.
2. Compute `width * height` and `8 + 2 * width * height` in checked `.q` **before allocation or reading offsets**. Use a justified configurable cap (e.g. 1,048,576 cells) and document it.
3. Require that all offset words target a position **at or after** the end of the grid offset table and inside the lump, with enough room for at least a dummy and terminator.
4. Walk referenced blocklists only within the lump. Reject a missing `0xFFFF` terminator, truncated entries, or malformed list start according to a documented vanilla-strict policy. Allow shared and out-of-order offsets; do not require contiguous or sorted lists.
5. Avoid excessive repeated rescanning for shared offsets: cache validated list boundaries by starting offset or otherwise enforce an explicit work budget.
6. Do not index actual `LINEDEFS` or validate individual linedef numbers against another lump here; M2-06 handles that semantic check.
7. Do not build runtime blocklinks or allocate based on unchecked `width * height * pointerSize`.
8. Permit trailing whole-word padding that is not referenced, if documented. A rejected malformed file must leave no leaked partial output.

**Compatibility boundary:** the original `P_LoadBlockMap` trusts resources and converts words in place. A safer parser may be stricter about malformed offsets/lists; document departures. Treat cell dimensions as unsigned on disk, but do not presume vanilla engine can support every large positive value. If the known IWAD unexpectedly fails a strict rule, investigate the actual bytes before changing policy.

## 7. Generic decoder rules and resource budgets

- Every fixed-size lump length must be **nonnegative and divisible by the exact record size**. A one-byte truncation is a failure, never silently ignored as upstream `length / sizeof(record)` may do.
- A zero-length **fixed-record** lump can produce a valid empty decoded table where this is meaningful, but all record getters must reject indexes safely. If a particular type needs a nonempty table for a playable level, defer that requirement to M2-06.
- Use a documented cap (e.g. **65,536 records per type**, or smaller for implementation limits) and an overall decoded-memory budget. Check `Count * InMemoryRecordSize` before any allocation; do not assume PB native struct widths match disk sizes.
- Keep untrusted little-endian byte parsing distinct from native-record storage. Use explicit readers and unsigned masking, and never cast a raw lump pointer to a PB `Structure` to parse it.
- Preserve all bytes of 8-byte texture/flat names even if they contain `NUL`, lowercase, `0x80` or `0xFF`. A printable/display-name helper is optional and must not corrupt stored bytes.
- Getter calls check pointer, object validity, record kind, index and destination capacity. No underflow when `Count=0`; no read after Reset. Avoid ambiguous return values by using a success boolean plus out-parameters where useful.
- Previous decoded output must be released when a replacement fails; double reset, repeated decode and failure-after-success must be covered.
- Do not accidentally apply `<< 16` to negative 16-bit coordinates in the file decoder. Conversion to Doom's 16.16 runtime values is M2-06 work and requires its own overflow-compatible strategy.
- Check error-state lifecycle: failure returns diagnostic naming lump/entry/byte where possible; success clears stale errors.
- No data- or memory-dependent nondeterministic checksums or address values in tests.

## 8. Test plan: 48 required synthetic scenarios

Create one self-contained suite `tests/unit/wad_map_types_tests.pb`, using **generated** byte arrays (not commercial map lumps), with 48 named scenarios. Labels and group boundaries below are mandatory, but implementation may group helper assertions sensibly.

### Common decoding and lifetime (M01–M06)

- **M01:** each fixed-record type accepts exactly one fully formed record and returns correct count.
- **M02:** each fixed-record type rejects partial trailing bytes (including size-minus-one and size-plus-one).
- **M03:** zero-length fixed-record types are handled according to the documented empty-table policy; getters fail safely.
- **M04:** null input with nonzero length and null output pointers fail without dereference; negative lengths fail.
- **M05:** decode twice, reset twice, decode after reset; no leak or stale values.
- **M06:** failure after successful decode releases old data; decoded records remain valid after the input buffer is freed.

### THINGS (M07–M10)

- **M07:** signed negative/positive coordinates and odd angle values are preserved.
- **M08:** all five 16-bit values are read from correct byte positions.
- **M09:** options/type bits including high bit survive exact round-trip through getters.
- **M10:** multiple THINGS preserve on-disk order; invalid index does not access memory.

### LINEDEFS (M11–M15)

- **M11:** all seven 16-bit fields map to correct offsets.
- **M12:** back-side `-1` survives, not transformed into an array index.
- **M13:** high flag bits and two-sided flag survive without reinterpretation.
- **M14:** vertex/sidedef references are stored raw without attempting cross-lump resolution.
- **M15:** getters reject negative and out-of-range record indexes.

### SIDEDEFS (M16–M19)

- **M16:** signed `textureoffset/rowoffset` and sector number are correctly decoded.
- **M17:** 3 separate 8-byte names preserve embedded NUL and trailing padding.
- **M18:** lowercase/non-ASCII bytes survive and do not leak across name fields.
- **M19:** invalid name-field/byte/index getters fail with no out-of-bounds read.

### VERTEXES (M20–M22)

- **M20:** ±16-bit extremes are preserved for x and y.
- **M21:** multiple records preserve order and the expected 4-byte stride.
- **M22:** odd/truncated vertex input is rejected.

### SEGS (M23–M26)

- **M23:** six fields, including raw high-bit `angle`, are decoded correctly.
- **M24:** signed `offset` negative; side `0/1` preserved without cross-validation.
- **M25:** large raw vertex/line indexes are retained without dereferencing.
- **M26:** truncated seg rejected and output cleared.

### SSECTORS (M27–M29)

- **M27:** unsigned firstseg/count edge values are retained.
- **M28:** valid zero count and adjacent subsector records preserve order.
- **M29:** partial record and invalid getters fail safely.

### NODES (M30–M34)

- **M30:** partition coordinates and all eight bbox values match exact byte offsets/order.
- **M31:** child `0x8000` produces subsector index zero.
- **M32:** child `0xFFFF` stays subsector index 32767, not a null pointer.
- **M33:** unflagged child is a node index; child accessors preserve raw bits.
- **M34:** truncated 27-byte node rejected; negative bbox values preserved.

### SECTORS (M35–M38)

- **M35:** signed heights/lightlevel/special/tag round-trip correctly.
- **M36:** floorpic and ceilingpic each preserve exactly eight raw bytes.
- **M37:** `F_SKY1` or `-` names are stored as data, not interpreted at parse time.
- **M38:** malformed record length and bad getters fail safely.

### REJECT (M39–M42)

- **M39:** LSB-first bit indexing for 3×3 matrix (cross-byte included) matches independently calculated values.
- **M40:** empty raw REJECT decodes safely; requesting an inaccessible bit reports failure.
- **M41:** negative/overflow-sized sector counts or invalid from/to indices fail safely.
- **M42:** owned copy survives freeing original input; repeated reset/redecode works.

### BLOCKMAP (M43–M48)

- **M43:** valid 1×1 grid with `[0, lineIndex, 0xFFFF]`, header/sign and line-order getters.
- **M44:** two cells share an offset; empty `[0, 0xFFFF]` list accepted.
- **M45:** unsigned offset >= `0x8000` to a valid padded position is decoded correctly **if within documented memory budget**; do not sign-extend.
- **M46:** reject zero dimensions, too-short offset table, huge product and odd lump byte length.
- **M47:** reject offsets into header/table, beyond length or with no room for list terminator.
- **M48:** reject unterminated or truncated list; reset clears partial result and restores deterministic error state.

**All 48 named scenarios must be reported with observed pass/fail counts and assertions.** Add subcases/extra tests for exact-size edges and allocation failure if practical. No fabricated success counts.

## 9. Synthetic WAD and Ultimate Doom integration

Add optional integration exercises to the same test executable (or a small dedicated fixture runner) using the **existing** `WADOpen/WADReadLump` API. Preserve current test-script idioms.

1. **I01 (synthetic ten-lump sequence):** create a tiny self-contained IWAD/PWAD in a temporary ignored path with `E1M1` marker and ten named entries in the correct order, including `REJECT` and `BLOCKMAP`; verify that each lump is read and independently decoded with exact byte sizes and counts. A test-only sequence locator is permitted.
2. **I02 (bad WAD/order):** absent/misnamed/truncated map lump and malformed `BLOCKMAP` fail cleanly with diagnostics, without impacting unrelated WAD functions. The production *map-loader* semantics are deferred to M2-06.
3. **I03 (lifetime):** parse synthetic map lumps, free raw data and close WAD, then exercise owned decoded accessors and resets. Repeat with a different synthetic WAD; no borrowed pointers or stale outputs.
4. **I04 (optional local original IWAD, read-only):** with `data/DOOM.WAD` or the repository's existing explicitly provided IWAD path, verify file MD5 `c4fe9fd920207691a9f493668e0a2083` when possible and `2306` lumps. Inspect `E1M1` and, where present, `E1M2` and `E4M1`. Locate map marker by bounded lookup, verify **the next ten entries by index and exact names/order**, use each actual lump size/reader to decode it, and report **only** counts, sizes, short numerical summaries, and non-reconstructable hashes. Do not hard-code unverified counts. Repeat selected reads and check deterministic results.

For `REJECT`, report raw byte count and derived minimum length using observed sector count, but do not silently reject a legacy map due to a compatibility policy not yet decided. For `BLOCKMAP`, report width, height and valid list count; investigate unexpected offsets rather than inventing values. Accept that some vanilla maps can contain edge cases not represented by synthetic fixtures; document strict-policy differences.

When the IWAD is missing, mark I04 `NOT RUN`, while synthetic tests must still pass. Never commit `DOOM.WAD`, extracted map data, tables, generated sprites/flats, screenshots, binaries, or full human-readable geometry dumps. Do not modify the IWAD. Don't print all names/coordinates or publish the map in JSON/CSV.

## 10. Build, regression and integration into project scripts

- Add a new opt-in test selector to both build scripts, e.g. `-MapTypesTest` for PowerShell and the existing consistent Bash spelling. Inspect actual option parsing and preserve old options; avoid overriding a used switch.
- Add this test target to `scripts/test.ps1` and `scripts/test.sh` with correct exit-code handling. No `|| true` or silent failure fallback.
- Syntax-check/build/run the main app and the new test target with the **actual installed** compiler. Make sure standalone suite has valid `EnableExplicit` and include-order convention.
- Rerun all existing unit/integration suites and command-line regressions. Historical M1/M2 counts must be repeated and reported, not merely inferred.
- Confirm `--version` outputs `DoomPB 0.1.0`, `--dump-info` and `--lump-info` still work, and `--show-title` displays 960×600 / closes with exit code 0. If a visual window check cannot run, report the exact limit; no automatic full-screen capture is necessary.
- Run `bash -n scripts/build.sh scripts/test.sh`; this is **not** proof of Linux compilation or runtime.
- Keep the executable version at **0.1.0**. No changes to title screen or unrelated graphics unless a proven regression requires a targeted fix.

Suggested check commands, adapt to actual repository scripts:

```powershell
./scripts/build.ps1 -Check
./scripts/build.ps1 -Check -MapTypesTest
./scripts/build.ps1 -MapTypesTest
./scripts/build.ps1
./scripts/test.ps1
```

```bash
bash -n scripts/build.sh scripts/test.sh
# Only if Linux PureBasic 6.41 and runtime are actually installed:
# ./scripts/build.sh --map-types-test && ./scripts/test.sh
```

If compiler unavailable, report exact attempted commands and `NOT RUN` rather than claiming a passing build.

## 11. Documentation and review

Update **only relevant portions** of `README.md`, `docs/PORTING_NOTES.md`, `CHANGELOG.md` and scripts, reflecting M2-05 capability and its limitations. In `docs/PORTING_NOTES.md` record:

- M2-05 vanilla binary fields, sizes, signedness and origin upstream functions.
- Parser-vs-validator boundary (M2-05 raw records, M2-06 cross-references).
- `REJECT` interpretation and any short-matrix compatibility caveat.
- `BLOCKMAP` unsigned **word-offset** semantics and your validation policy.
- Ownership/reset rules and chosen memory safety caps.
- Known deviations from original C (nonpacked native representation, stricter malformed-data rejection).
- Windows-only verification until Linux actually runs; no `v0.2.0` claim.

Final repository checks:

```text
git diff --check
git diff --cached --check
git diff --stat
git status --short
```

Also audit **new untracked files** separately, since `git diff --check` does not see them. Ensure no trailing spaces/tabs in `.pb`, `.pbi`, `.ps1`, `.sh`, `.md`; normal LF files; no absolute local paths or user data; no `.wad`, `.exe`, `.dll`, `.png`, `.bmp` or generated `build/`/`data/` in changes. Do not work around trailing whitespace by adding `.gitattributes whitespace=-blank-at-eol`.

Do **not** run `git add`, `git commit`, `git push`, `git tag`, `git reset --hard`, `git clean`, or force operations. The owner controls commits and releases.

## 12. Definition of Done / acceptance

M2-05 is accepted when:

1. All ten vanilla map lumps have an explicit documented decoder/data representation; all eight fixed-record formats use the exact disk strides and byte offsets.
2. Signedness, 8-byte names, `-1` sidedef sentinel and `NF_SUBSECTOR` are demonstrably correct.
3. `REJECT` is copied safely with correct LSB-first matrix access; `BLOCKMAP` uses unsigned 16-bit **word** offsets and bounded terminated list reading.
4. Zero-length and malicious/truncated payloads cause deterministic errors or documented empty-result behavior; no dangling buffers or out-of-bounds reads.
5. All **48 synthetic cases** and I01–I03 pass. I04 on locally available owned Ultimate Doom passes or is accurately `NOT RUN` with reason.
6. All prior M0/M1/M2-01..04 tests and app CLI are preserved; Windows compile and execution are actually observed.
7. The diff is narrow, docs accurate, no commercial data stored or published, version unchanged, and **nothing staged/committed/tagged** by the agent.

Completing M2-05 **does not** mean map loading, BSP integrity validation or milestone M2 are complete.

## 13. Required final report

Use the project final-report convention with the additional details below. Report factual tool results, not simulated results:

```text
Task / milestone: M2-05 — vanilla map binary structures
OS / PureBasic version; Linux: PASS/FAIL/NOT RUN
Baseline HEAD / branch / staged-unstaged-untracked; M2-04 commit status
Pinned Doom commit and exact C types/functions inspected
Files created/modified
Public APIs and data ownership/reset/error contracts
Fixed-record sizes and field/signedness handling
REJECT bit semantics; BLOCKMAP offset/list semantics and safety caps
Deviations from vanilla and deferred cross-reference checks
Syntax checks: commands + exit codes
Build: commands + exit codes
M0/M1/M2-01..04 regressions: cases and assertions
M2-05 M01–M48: pass/fail cases and assertions
Synthetic integrations I01–I03: observed results
Optional Ultimate Doom I04 (E1M1/E1M2/E4M1): counts/sizes, hashes, result
--version/--show-title/--dump-info regression status
Linux bash -n and actual Linux runtime status
Git diff/status, untracked-file whitespace and commercial-data audit
Known limitations, compatibility risks, owner review needs
Suggested Conventional Commit message (DO NOT COMMIT)
Suggested next task: M2-06 — Map Loader and cross-reference validation (DO NOT START)
```

## 14. Reference material

- Original upstream (local pinned checkout): `linuxdoom-1.10/doomdata.h`, `p_setup.c`, `p_maputl.c`, `p_sight.c`, `w_wad.c`.
- Online upstream: https://github.com/id-Software/DOOM/tree/master/linuxdoom-1.10
- Packed map-lump background: https://reverseengineering.wiki/index.php/Format%3AWAD_%28Doom_engine%29
- BLOCKMAP offset/list details: https://www.gamers.org/dhs/helpdocs/dmsp1666.html
- Official PureBasic documentation: https://www.purebasic.com/documentation/

The local pinned source and actual installed compiler are authoritative. Secondary documentation may clarify the serialized format but must not override an observed upstream/source disagreement without investigation and tests.
