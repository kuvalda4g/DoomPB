# DoomPB — M1-02: Lump name lookup and safe payload reading

> - **Task ID:** `M1-02`
> - **Milestone:** M1 — WAD Loader + TITLEPIC (`v0.1.0` remains incomplete)
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Recommended reasoning:** High
> - **Language / compiler:** PureBasic 6.41, full edition
> - **Primary verification:** Windows x64; Linux x64 later, report `NOT RUN` if unavailable
> - **License:** GPL-2.0-only
> - **Required reading:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md` (M1, compatibility, testing), `docs/PORTING_NOTES.md`, actual M1-01 source and tests
> - **Pinned upstream:** `../doom-original` at `a77dfb96cb91780ca334d0d4cfd86957558007e0`

## 1. Goal and boundaries

Continue from the **existing, committed M1-01 implementation**, not a newly generated project. Implement two reusable operations for the already-open, already-validated **single WAD**:

1. Locate a lump by its classic Doom eight-byte name, including correct duplicate precedence.
2. Read its **binary payload** by index into a caller-owned buffer, with strict size, bounds, and I/O checks.

Preserve M1-01 behavior, the M0 CLI, and all earlier tests. The local user's Ultimate Doom `DOOM.WAD` is optional integration input only. Do not add or commit copyrighted game resources.

**Out of scope:** `PLAYPAL` parsing, Doom picture/patch decoding, `TITLEPIC` display, rendering, map interpretation, sound, `W_CacheLumpNum` / zone allocator, multi-WAD overlays, PWAD merging, compression, or bulk loading an entire WAD into RAM. These belong to later tasks.

## 2. Inspect first — mandatory

1. Run `git status --short --branch`, `git log -1 --oneline`, inspect staged/untracked changes, and preserve all unrelated work. Confirm the M1-01 commit exists; do not invent its SHA or assume the worktree is clean.
2. Read the **actual** `src/WAD/WAD.pbi`, `src/Core/Endian.pbi`, `src/DoomPB.pb`, `tests/unit/wad_header_tests.pb`, and all existing `scripts/build.*` / `scripts/test.*`. Reuse the M1-01 API instead of replacing it.
3. Verify the local upstream commit and inspect `linuxdoom-1.10/w_wad.c` / `w_wad.h`: especially `W_CheckNumForName`, `W_GetNumForName`, `W_LumpLength`, `W_ReadLump`, the directory structure, and how a file is associated with each lump.
4. Explain the implementation plan **before editing**: exact files, new API signatures, name comparison semantics, memory ownership, file re-open strategy, error handling, and test cases.
5. Use the installed PureBasic 6.41 compiler and the repository scripts. Do not hard-code a local absolute path into tracked files.

## 3. Existing M1-01 API: do not break it

The reported M1-01 API includes:

```text
WADOpen(Path) / WADClose() / WADReset()
WADIsOpen, WADGetKind(KindName), WADGetFileSize, WADGetLumpCount
WADGetDirectoryOffset, WADGetPath, WADLastError
WADLumpPosition, WADLumpSize, WADLumpIsMarker
WADLumpRawNameByte, WADLumpRawNameHex, WADLumpDisplayName
```

**Important:** This list comes from the accepted M1-01 report. Inspect real declarations, return types, and call sites before choosing names or parameters. M1-01 owns a module-global directory and **closes the file after parsing**; M1-02 must accommodate this design without introducing stale file handles or pointers.

M1-01 validates nonempty payload bounds using 64-bit intermediates, accepts zero-length markers with arbitrary raw positions, limits directory count to 1,000,000 entries, and preserves raw 8-byte names. Do not weaken these guarantees.

## 4. Part A — lookup by name

### 4.1. Required public operation

Introduce one documented lookup operation, preferably:

```text
WADFindLump(Name.s) -> index.i
```

- Returns **zero-based directory index** for the winning entry; returns `-1` if no match or WAD is not open.
- A match uses **exactly eight name bytes**, including NUL padding when shorter than eight characters. Never assume the directory's 8 bytes are NUL terminated.
- Normalize the **query** to ASCII uppercase (`a`–`z` only), as the original `W_CheckNumForName` does. Compare against **unchanged, raw bytes** from the WAD directory. Canonical Doom lumps are uppercase; do not silently rewrite stored bytes. This preserves vanilla behavior for malformed lowercase directory names.
- Search **from last directory entry to first**: the last matching entry wins. This applies equally to zero-size markers. For two entries named `TEST`, return the later index, even if the earlier one points to different payload bytes.
- Reject empty names, unsupported/non-ASCII query characters, or explicitly document and test a safer, deterministic convention. For names longer than eight ASCII bytes, **match original Doom truncation to the first eight bytes** unless the actual C reference proves otherwise; document edge behavior and tests. Never index outside the query or directory buffer.
- Use a straightforward reverse linear scan for the first implementation; do **not** add a hash table, a second ownership system, or persistent cache prematurely. Search correctness is more important than micro-optimization.
- Lookup **does not read or allocate payload data**. It also must not mutate the directory or invalidate cached entry metadata.
- Distinguish ordinary 'not found' from a parser state or malformed API input in the documented error contract. Avoid stale error messages after successful calls.

### 4.2. Vanilla reference nuance

Original `W_CheckNumForName` uppercases the requested name, compares two 32-bit words covering all eight bytes, and scans backward. Names in the WAD directory are **not** uppercased in place. Do not replace this with Unicode string equality or locale-sensitive case folding. An ASCII byte-wise implementation is preferable in PureBasic.

Do **not** add PWAD overlay loading in this task; backward search within one directory establishes the lookup behavior that later overlays will reuse.

## 5. Part B — binary-safe payload read

### 5.1. Required public operation

Prefer a caller-owned-buffer API equivalent to:

```text
WADReadLump(Index.i, *Destination, Capacity.q) -> success boolean
```

Adapt the exact declaration to PureBasic 6.41 and existing naming conventions. The contract must be documented and unit-tested:

- Check `WADIsOpen` and `0 <= Index < WADGetLumpCount` before accessing an entry.
- Obtain `Position` and `Size` from the validated entry (do not recompute via name lookup).
- **Capacity must be >= Size**, nonnegative and representable; fail cleanly before writing to an undersized buffer. Avoid off-by-one errors.
- For `Size > 0`, require a valid non-null destination buffer with caller-proven capacity. Do not silently allocate a replacement or call `ReadData` on a null pointer.
- For **zero-length entries**, return success with **zero bytes read** and permit a null destination with capacity 0. Never seek to their arbitrary recorded positions.
- Support arbitrary bytes, including `0x00`, `0x80` and `0xFF`; **do not** convert to a PureBasic string or append a terminator.
- Reopen the WAD **read-only** using its saved path when data is requested (since M1-01 closed the handle). Close that temporary file handle on **every** success/error path. Do not retain an unowned borrowed pointer after the call.
- Recheck actual file length after reopening. Check the `position + size` range against this **current** length using 64-bit intermediates; also detect a changed file size relative to the parsed snapshot. Failure must be controlled, not a crash.
- Seek only after validating bounds. Where possible verify the resulting `Loc()`; `FileSeek()` itself is not a success/failure API. Verify every `ReadData()` return count and treat short reads as errors.
- PureBasic `ReadData()` documents a **2 GB limit per call**. If needed, read in bounded chunks and use checked pointer arithmetic; never truncate a 64-bit size to a smaller type silently. Do not impose a global large buffer allocation in the parser.
- Failure must leave no open file descriptor; return an actionable `WADLastError` message without printing payload data. Document that if a short read happens mid-transfer the destination **may be partially modified**; basic validation failures must be detected before the first write.
- Successful calls must clear/refresh transient error status. Repeated reads of the same index must be safe.

Caller owns the destination and is responsible for its allocation and freeing. **Do not implement the original zone-based lump cache yet.** A future `LumpCache.pbi` will build on this low-level primitive. If a small convenience wrapper is genuinely useful, keep it subordinate to the tested buffer API and explicitly define free/ownership rules.

### 5.2. Intervening file modifications

The parsed WAD directory is a snapshot. A later read reopens the file: it might have been deleted, replaced, or truncated. This task **must** detect missing files, unexpected length, insufficient current bounds, and short reads. Equal-size replacement cannot necessarily be detected with simple checks; document that limitation instead of claiming perfect file identity guarantees. Re-validating an entire file on every read is **not** required for M1-02.

## 6. CLI integration — narrow and metadata-only

Preserve these observed M0/M1-01 behaviors and exit codes:

```text
DoomPB --version                      -> 0
DoomPB --help                         -> 0
DoomPB                              -> 0
DoomPB <unknown argument>             -> 2
DoomPB --iwad <path> --dump-info      -> 0 on valid WAD, 1 on WAD failure
```

To make lookup observable without exposing copyrighted bytes, optionally add one diagnostic form:

```text
DoomPB --iwad <path> --lump-info PLAYPAL
```

Output **only** name/index/offset/size, and a reasonable not-found message/exit code. If adding an option would entangle the existing CLI parser, use a unit/integration harness instead and explain why. **Do not add a `--dump-lump`, hex dump, binary file extraction or automatic graphical output.**

Keep reported application version `0.0.1`; `v0.1.0` requires all M1 tasks, including `TITLEPIC` on screen.

## 7. Automated tests — required

Build on the existing synthetic test harness, or add a second small PureBasic test source that the existing Windows scripts compile and execute. **All tests must be deterministic and independent of commercial IWADs.** Generate disposable `.wad` fixtures in an ignored temporary location, not the tracked source tree; clean them up after the tests.

Minimum new categories (multiple assertions each where useful):

| ID | Scenario | Expected outcome |
|---|---|---|
| L01 | Lookup canonical uppercase name | Finds exact index |
| L02 | Lowercase/mixed-case **query** | Finds same uppercase stored lump |
| L03 | Missing name | Returns `-1`, controlled not-found result |
| L04 | Duplicate name with different payloads | Returns **last** directory entry |
| L05 | Exactly 8-byte, non-NUL-terminated name | Found; all 8 bytes compared |
| L06 | Short name with NUL padding | Found; no accidental prefix match |
| L07 | Distinct names with same first 7 bytes | No false positive |
| L08 | Name more than 8 ASCII bytes | Document/test first-8 truncation matching vanilla |
| L09 | Zero-length marker, including invalid recorded offset | Can be found by name; not read at its offset |
| L10 | Valid nonempty payload with `00 80 FF` binary bytes | Exact byte-for-byte equality; no string conversion |
| L11 | Read by index where duplicate names point to different content | Reads correct selected **index**, not implicit latest-name content |
| L12 | Buffer exactly required size | Success; adjacent guard bytes unchanged |
| L13 | Buffer too small, negative capacity, null destination for nonempty lump | Safe failure; no guard-byte modification |
| L14 | Invalid indices (`-1`, `count`, larger) / reader before open | Safe failures; no memory access outside arrays |
| L15 | Empty payload with null pointer and zero capacity | Successful no-op, no seek |
| L16 | Source file removed/renamed after successful `WADOpen()` | Controlled read failure, no leaked descriptor |
| L17 | Source file truncated or changed in size after `WADOpen()` | Controlled read failure before out-of-range I/O |
| L18 | Open→read→close→reopen and failed-open→successful-open | No stale name index, path, error, handle or buffer state |
| L19 | Two entries with overlapping/shared data ranges | Both read their declared data correctly |
| L20 | Oversize/requested capacity boundary | No overflow, huge allocation, or truncated byte count |

**Extra compatibility test:** An intentionally lowercase name stored in a malformed directory should preserve its raw bytes. If using vanilla raw comparison, a query uppercased to `TEST` should **not** silently match stored `test`; document that this behavior follows the reference implementation. This edge case should not change lookup of normal uppercase Doom resources.

Test binary reads and memory ownership using canary bytes around small destination buffers. Avoid depending on debug-only traps as your sole safety validation. No test may modify the user's real `DOOM.WAD`.

**Baseline:** maintain all previous M1-01 synthetic cases (**17/17 cases, 146/146 assertions** as reported) and the existing **14/14 M0 smoke tests**. These are historic baseline counts, not a license to skip tests if the test harness changes. Report actual observed totals and failures, not only expected numbers.

### Optional Ultimate Doom integration

If the file already exists locally at `data/DOOM.WAD` or `local-data/DOOM.WAD`, verify it **read-only**. Known test IWAD:

```text
Type:             IWAD
File size:        12408292 bytes
Directory count:  2306
Directory offset: 12371396
MD5:              c4fe9fd920207691a9f493668e0a2083
```

- Confirm lookup succeeds for `PLAYPAL`, `TITLEPIC`, `E1M1`, and case-insensitive **queries** such as `playpal`.
- `E1M1` is a **zero-length map marker**: lookup success does not imply a nonempty payload. Validate marker handling accordingly.
- Read `PLAYPAL` and `TITLEPIC` into private, caller-owned temporary buffers, check that returned length and bounds agree with directory metadata, and release the buffers.
- Print **metadata and optional short checksums only**. Do not print/store raw lump contents, sprites, pictures, or extracted resources; do not commit generated copyrighted assets.
- Do not require that the user file exists; report `NOT RUN` if absent. Do not download or reconstruct it.

## 8. Verification and Git hygiene

1. Run existing `scripts/build.ps1 -Check`, relevant unit test syntax checks, actual build, and the complete `scripts/test.ps1` suite on Windows.
2. Verify compiler and test process **exit codes**. Record exact commands, actual pass/fail counts and actual `DoomPB.exe` CLI results.
3. Exercise safe repeated reads, known-size and zero-length buffers, missing file and changed file cases. Confirm buffers are released by their owners and file handles are closed.
4. If Bash/Linux cannot be executed, record `Linux/Bash: NOT RUN`; review edits to shell scripts statically, and **do not** claim Linux runtime validation.
5. Review `git status --short --branch`, `git diff --check`, `git diff --stat`, and file diffs. If staged content exists, review `git diff --cached --check` and staged files as well.
6. Verify no `*.wad`, executable, payload dump, `data/`, `local-data/`, secrets, local absolute paths, or confidential resources were added to Git.
7. Source and Markdown files must have **no trailing whitespace** (including two-space Markdown hard breaks). Use lists/blank lines instead; `git diff --check` should be clean.
8. **Do not** run `git add`, `git commit`, `git push`, force-push, alter tags/releases, or start M1-03 unless the owner explicitly authorizes it. Stage/commit decisions remain with the owner.
9. Update `README.md` and `docs/PORTING_NOTES.md` only where needed to describe the new public API, C mapping, ownership and known deviations. Keep the diff focused.

## 9. Acceptance criteria (Definition of Done)

- [ ] Actual M1-01 implementation and pinned upstream reference inspected before edits.
- [ ] Lookup returns exact matching index; last duplicate wins; exact eight-byte semantics and query normalization are tested.
- [ ] Missing, invalid and zero-length lump cases behave as documented without crashes.
- [ ] Binary payload read uses a **caller-owned buffer** with validated index/capacity and byte-exact content.
- [ ] Source WAD is reopened safely for reads, revalidated after reopen and always closed afterwards.
- [ ] Existing metadata functions, `--dump-info` and M0 CLI behavior remain intact.
- [ ] All **20** new test categories and existing M1-01/M0 tests pass with actual PureBasic 6.41 compilation.
- [ ] Optional local IWAD integration is PASS, or explicitly NOT RUN with reason.
- [ ] Git diff reviewed; no trailing whitespace and no commercial or private data in changes.
- [ ] Changes remain **uncommitted and unstaged** unless explicitly approved; M1-03 is not started.

**This task is complete only when the new lookup/read API is compiled and exercised by real tests. M1 and `v0.1.0` remain incomplete until the patch/palette decoder and visible `TITLEPIC` are implemented.**

## 10. Mandatory completion report

```text
Task / milestone: M1-02 — lump lookup and payload read
OS / compiler: <observed>; Linux/Bash: PASS / FAIL / NOT RUN
Baseline HEAD / worktree: <actual git state>
Upstream C symbols inspected: <files/functions and pinned revision>
Files created / modified: <paths>
Lookup API and name matching: <names, precedence, >8 behavior, errors>
Read API and ownership: <signature, buffer lifecycle, reopen/close rules>
Behavior implemented: <actual functionality>
Syntax check: PASS / FAIL / NOT RUN — <command, exit>
Build: PASS / FAIL / NOT RUN — <command, exit>
M0 smoke tests: <actual N/N>
Existing M1-01 tests: <actual N/N and assertion count>
New M1-02 tests: <actual N/N and assertions; note L01–L20>
Optional Ultimate Doom integration: PASS / FAIL / NOT RUN — <metadata only>
File-change / buffer-edge tests: <results>
Git status / diff / whitespace / resource audit: <results>
Compatibility deviations and limitations: <list>
Next suggested task: M1-03 — PLAYPAL + Doom patch decoder (DO NOT START)
```

## 11. Source links

- Original Doom `w_wad.c`: https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/w_wad.c
- Original Doom `w_wad.h`: https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/w_wad.h
- PureBasic `ReadFile()`: https://www.purebasic.com/documentation/file/readfile.html
- PureBasic `FileSeek()`: https://www.purebasic.com/documentation/file/fileseek.html
- PureBasic `ReadData()`: https://www.purebasic.com/documentation/file/readdata.html
- PureBasic `AllocateMemory()`: https://www.purebasic.com/documentation/memory/allocatememory.html
- WAD format and lookup context: https://doomwiki.org/wiki/WAD

**Scope guard:** This task makes named lumps addressable and their raw bytes readable. It does **not** interpret their payload formats, implement caching or complete milestone M1.
