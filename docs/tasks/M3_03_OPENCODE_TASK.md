# DoomPB — M3-03: Deterministic BSP traversal and camera state

> - **Task ID:** `M3-03`
> - **Milestone:** M3 — Geometry & First Walls; `v0.3.0` is **not complete**
> - **Status:** Implementation assignment, not a completion report
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017; reasoning **High**
> - **Compiler:** Native PureBasic **6.41**, full edition; Windows x64 primary target
> - **Linux x64:** `NOT RUN` until genuinely compiled and executed on Linux
> - **License:** GPL-2.0-only; no commercial IWAD assets in repository
> - **Primary C reference:** `../doom-original/linuxdoom-1.10`, pinned commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Prerequisite:** M3-02 accepted and committed; inspect actual HEAD and worktree, never assume its SHA
> - **Read first:** `AGENTS.md`, M3 in `docs/DEVELOPMENT_PLAN.md`, `docs/PORTING_NOTES.md`, M3-02 geometry source/tests, M2 map source/tests, this document

## 1. Objective and release boundary

Implement a **safe, deterministic near-to-far traversal** of the validated vanilla Doom BSP from a **fixed camera**. Connect the M2 `MapLevel` representation to M3-02's fixed-point geometry, generating a chronological list of visited subsectors and their segs for later wall clipping/projection. Keep the original Doom ordering and branch/tie behavior where applicable, without assuming any screen-space occlusion state exists yet.

Successful M3-03 should:

1. Accept a **ready** `MapLevel` (including a zero-node/single-subsector level) and a validated camera with **16.16 coordinates** and a raw **unsigned 32-bit BAM** heading.
2. Select the near child at each BSP node using the existing exact `GeometryPointOnNodeSideChecked` semantics; traverse near subtree, then far subtree.
3. Emit an owned, read-only ordered event trace: subsector entry followed by its segs in original increasing `firstseg..firstseg+numsegs-1` order. Include stable indices/derived links for M3-04 consumers.
4. Use an **explicit bounded stack**; avoid recursive traversal, borrowed WAD memory, and unbounded allocation. Handle errors transactionally.
5. Test with self-created synthetic data and read-only optional E1M1/E1M2/E4M1 integration; preserve all earlier tests and CLI behavior.

The trace is **not a visible-surface list**. Without projection and `solidsegs`, visiting all geometrically reachable subsectors is expected. M3-03 does **not** produce rendered pixels or claim correct screen occlusion.

### Non-goals

- **No `R_CheckBBox` occlusion pruning yet.** Original `r_bsp.c:R_CheckBBox` needs `viewangletox`, `clipangle`, and the evolving `solidsegs` ranges maintained by `R_ClipSolidWallSegment`; neither screen projection nor wall clipping is implemented. Do not substitute speculative bounding-box/FOV culling that may hide visible geometry. You may expose a non-pruning, diagnostic-only bbox accessor if genuinely useful.
- No `R_AddLine`, `R_ClipSolidWallSegment`, `R_ClipPassWallSegment`, `R_StoreWallRange`, drawsegs, wall projection, textured or untextured columns, visplanes, sprites, sky, lighting, frame hashes, UI, player controls, collision, movement or gameplay tick loop.
- No renderer-visible WAD extraction, PWAD overlays, map editing, new mandatory CLI command, or wholesale refactor of M2's validated level loader.
- Do not change DoomPB version `0.2.0`, create `v0.3.0`, or mark M3 complete.

## 2. Mandatory inspection and planning before edits

1. Run `git status --short --branch`, `git log -3 --oneline`, `git tag --list`, `git diff --stat`, `git diff --cached --stat`. Confirm M3-02 commit actually exists. Preserve unrelated changes; do not stage, commit or tag.
2. Inspect exact current public interfaces and type widths; do **not** invent PureBasic signatures:
   - `src/Map/MapLevel.pbi`, `MapLoader.pbi`, `MapValidate.pbi`, `MapTypes.pbi`, `MapDecode.pbi`.
   - `src/Core/Fixed.pbi`, `Angle.pbi`, `TrigTables.pbi`; `src/Renderer/Geometry.pbi`.
   - Current test harnesses and `scripts/{build,test}.{ps1,sh}`, `src/DoomPB.pb`.
3. Inspect original C at the pinned SHA:
   - `r_bsp.c`: `R_RenderBSPNode`, `R_Subsector`, `R_CheckBBox`, `R_AddLine`, `R_ClearClipSegs`; identify **dependencies**, not merely names.
   - `r_main.c`: `R_PointOnSide`, `R_PointInSubsector`, `R_RenderPlayerView`, `viewx/viewy/viewangle`, `numnodes - 1` root.
   - `r_defs.h`: `node_t`, `subsector_t`, `seg_t`, `vertex_t`; `doomdata.h`: `mapnode_t`, `NF_SUBSECTOR`; `tables.h`: BAM.
4. Follow the updated `AGENTS.md` **Context7 documentation policy**. Check Context7 for version-relevant PureBasic APIs if available; explicitly record a no-match/unavailable result if appropriate. The pinned C source controls Doom semantics, and the actual PureBasic 6.41 compiler is the authority on PB behavior. Run small disposable compiler probes for uncertain stack structures, pointer-to-array access or typed callback signatures.
5. Present a short implementation plan: files, data ownership, event schema, stack phases, camera validation, error policy, test matrix, and why occlusion is intentionally deferred.

**Historical regression baseline (re-run it, do not just quote it):** previous reported tests after M3-02 were **464 cases / 2,704 assertions** in the synthetic/non-IWAD suite, **467 / 2,784** including owner-IWAD optional checks, and **86/86** script checks; these figures are not current-run evidence.

## 3. Source-level algorithm: faithful near/far ordering

Original `linuxdoom-1.10/r_bsp.c:R_RenderBSPNode(int bspnum)`:

- If `bspnum & NF_SUBSECTOR`, visit the leaf. Special original root `bspnum == -1` maps to subsector zero.
- Otherwise, read `nodes[bspnum]` and use `R_PointOnSide(viewx, viewy, node)` (0/1) to pick the **near** child.
- Recursively visit `children[side]` first.
- Then visit `children[side ^ 1]` **if** `R_CheckBBox(bsp->bbox[side ^ 1])` permits it.

**M3-03 translation:** replace C recursion with a bounded iterative frame machine. With occlusion disabled, the far child must **always** be visited after the near subtree completes. Keep the original side mapping (0 is front, 1 is back), with equality/tie handled by `GeometryPointOnNodeSideChecked` rather than new cross-product logic. Avoid sorting leaves or segs numerically.

Pseudo-algorithm (language-neutral; do not copy as unverified PB syntax):

```text
Traverse(root, camera, level):
  stack.push(root)
  while stack not empty:
    item = stack.pop()
    if item is a subsector:
      emit SUBSECTOR(item.index, derived_sector)
      for segIndex in [firstseg, firstseg + numsegs):
        emit SEG(segIndex, item.index, derived line/side/sectors)
      continue
    node = checked_level_node(item.index)
    side = original_point_on_side(camera.xy, node partition)
    // LIFO: push far first, then near so near is processed first.
    stack.push(node.children[side XOR 1])
    stack.push(node.children[side])
```

A frame-based `(node, phase, near_child, far_child)` implementation is equally acceptable; explicit work-stack push order must give the same leaf/seg sequence as recursive C. In particular, preserve child0/child1 meaning and the BSP root index, not disk-directory order.

### Exact root and child conventions

- Use `MapLevelIsReady` and `MapLevelGetBspRoot`, which currently expose `BspRootIsSubsector` and `BspRootIndex`. **Do not** assume the root is node 0.
- For vanilla maps with nodes, M2 derives root `nodeCount - 1`; with **zero nodes and exactly one subsector**, the validated root is subsector 0. This is the safe equivalent of original `R_RenderBSPNode(-1)` behavior.
- On-disk `child[0..1]` is a **16-bit unsigned** value; high bit `#MAP_NF_SUBSECTOR = $8000` marks a leaf, lower 15 bits are its index. Otherwise it is an index into the nodes table.
- `MapNodesGet` returns decoded records; `MapNodesChildIsSubsector` and `MapNodesChildIndex` may help, but inspect their actual return/error conventions. Never treat an invalid index or unchecked `-1` as a valid pointer.
- Existing `MapValidateLevel` already validates child indices and detects **reachable** BSP cycles; do not reimplement decoder, graph validator or loader as part of renderer traversal. A defensive per-trace budget is still necessary.

### Camera and fixed-point coordinates

- Camera location uses signed `.l` fixed-point **16.16** values, not raw WAD map units. Angles use canonical raw BAM `0..$FFFFFFFF` via `.q` or `BamAngleValue`, not degrees or signed `.l`.
- A small `Renderer/Camera.pbi` with caller-owned `BspCamera` is recommended; if an existing camera abstraction already exists, integrate rather than duplicate.
- Provide explicit checked creation from map units using `FixedFromIntChecked` and/or checked setter for fixed coordinates. **Heading is stored even though traversal order currently depends only on X/Y**, so M3-04 can reuse the same camera type.
- A fixed camera is not an actor/player: no P_Start, no input updates, no `viewz` or 35-Hz simulation needed for this step.
- M3-02's `GeometryPointOnNodeSideChecked(X, Y, NodeOriginX, NodeOriginY, DX, DY, *Side.Long)` is the existing side classifier. Convert node origin/direction from signed map units with checked `FixedFromIntChecked`, preserving sign and branch ties.
- M3-02 explicitly **rejects** deltas outside signed 32-bit fixed range instead of silently wrapping C signed overflow. Propagate that deterministic failure (camera, node index, coordinates) and leave no partially published output; do not invent a different renderer-only wrap policy.
- There may be valid negative fixed-point values. Test axes, signed extremes, and exact partition equality. Use 64-bit intermediates for any calculations that can overflow `.l` during conversion/arithmetic.

## 4. Proposed files and responsibilities

Expected new files, subject to existing architecture:

```text
src/Renderer/Camera.pbi              # fixed camera X/Y + raw BAM heading, checked setup
src/Renderer/BSP.pbi                 # bounded BSP traversal, trace ownership & accessors
 tests/unit/bsp_traversal_tests.pb   # B01–B48: independent synthetic trees
 tests/integration/m3_bsp_tests.pb  # I01–I03: synthetic full MapLevel pipeline
 tests/integration/m3_bsp_iwad_tests.pb  # I04 optional, legal owner IWAD only
```

`Camera.pbi` may be merged into `BSP.pbi` if it would otherwise be a trivial wrapper; avoid dummy future `Segs.pbi`/`Draw.pbi`/`RenderMain.pbi`. You may add a compact synthetic reference-data generator under `scripts/` or `tests/fixtures/` **only if** that demonstrably improves independent validation; it must be deterministic and contain no commercial resource data.

Likely touched existing files: `src/DoomPB.pb` (compile inclusion only if necessary), `scripts/build.ps1`, `scripts/build.sh`, `scripts/test.ps1`, `scripts/test.sh`, `README.md`, `CHANGELOG.md`, `docs/PORTING_NOTES.md`, and `docs/DEVELOPMENT_PLAN.md` (M3-03 status only). Avoid unrelated CLI or module redesign.

### Recommended public API (conceptual, not verified PureBasic syntax)

```text
BspCameraSetMapUnits(*Camera, X.q, Y.q, HeadingRaw.q) -> bool
BspCameraSetFixed(*Camera, X.l, Y.l, HeadingRaw.q) -> bool
BspCameraGet(*Camera, *X.Long, *Y.Long, *Heading.Quad) -> bool
BspCameraLastError() -> string

BspTraceBuild(*Level.MapLevel, *Camera.BspCamera, *Trace.BspTrace) -> bool
BspTraceReset(*Trace.BspTrace) -> bool / void (idempotent)
BspTraceCount(*Trace) -> integer
BspTraceGet(*Trace, EventIndex, *Kind, *Subsector, *Seg,
            *Sector, *Linedef, *Side, ...) -> bool
BspTraceLastError() -> string
```

Alternative names are fine if consistent with the project. Document exact field types, whether `Kind` is `SUBSECTOR` or `SEG`, which irrelevant fields are `-1`, and the testable ownership/lifetime contract. Accessors may return validated copies of event records or bounded read-only access; do not return borrowed addresses of temporary stack elements.

### Event schema and ordering contract

Emit two types of events in **one** chronological stream:

- `SUBSECTOR`: index of the reached subsector and derived sector index; occurs **once per actual leaf visit**.
- `SEG`: absolute seg index, owning subsector, resolved linedef index, side (0/1), front sector and back sector (use documented `-1` sentinel). Occurs immediately after its subsector entry, in **original seg order**.

The sequence represents BSP walk order, **not** physical draw order within wall-clipping output (that is a later contract). Do not globally sort, deduplicate, or classify visibility based on `REJECT` or `BLOCKMAP`; those structures have different roles. Do not emit every linedef in the sector: the subsector's `SEGS` range is authoritative.

Use `MapSubsectorsGet`, `MapSegsGet`, `MapLevelGetSubsectorSector`, `MapLevelGetSegLinks` and/or already validated typed arrays. Avoid allocating a duplicate map graph with `node_t`/`seg_t` pointers. Validation ensures ordinary vanilla indices are legal; render-side APIs must nevertheless fail safely when called with null, not-ready or corrupted objects.

## 5. Determinism, safety and resource limits

1. **Transactional output:** clear/reset target trace before a new build. A failed build leaves the trace empty, not a partial list. Preserve camera and source MapLevel; do not modify `viewx/viewy` globals or mutate the level.
2. **No WAD dependency:** the traversal reads only the loaded `MapLevel`; it must work after `WADClose()`. The trace owns all published numeric event data so it can be inspected after `MapLevelReset()` (unless the API expressly forbids that and tests prove the contract). Do not retain borrowed level or WAD pointers.
3. **Bounded stack:** explicit work frames; every push/pop/index checked; no recursion, no infinite loop. A full traversal of an ordinary BSP tree is `O(nodes + subsectors + seg events)`.
4. **Bounded events:** choose a documented, reasonable cap (for example at most 1,000,000 emitted events and an independently bounded work budget). Allocate/grow with checked `.q` arithmetic, capacity checks and clean OOM recovery. Don't preallocate enormous arrays for an empty level.
5. **Shared-child DAG nuance:** M2 detects cycles but does **not necessarily** reject DAG-style sharing. Do not silently skip a repeated child/leaf or call the result equivalent to Doom. Original recursion visits each occurrence. Either reproduce repeated occurrences **under a hard visit budget** or explicitly reject unsupported shared graph references **at traversal time**, without changing M2 map validity. Document and test whichever policy is selected. Never let a compact malicious DAG expand exponentially without a bound.
6. **Integrity:** check bounds on node indices, leaf indices, subsector `firstseg + numsegs`, event sizes and dereferences. If a pre-validated MapLevel has been externally corrupted in memory, a clean error is preferable to undefined behavior; there is no need to add a redundant full cross-lump validator.
7. **Failure diagnostics:** identify map name (if present), camera inputs when relevant, node/child index, subsector/seg/event limit, and original `GeometryLastError()` where available. Success clears stale error state. Null output pointers leave caller state safe.
8. **No hot-path heap churn:** allocate bounded scratch buffers once per trace build, not per node or seg. No per-frame log spam, screen interaction or external service calls.
9. **No hidden culling:** maintain a counter of visited nodes/subsectors/segs and possible skip count; report zero 'occlusion skips' in this phase. A bounding box may be computed for diagnostics but must not drive pruning.
10. Preserve deterministic order across repeated builds and map reopen cycles. Don't derive output from hash-table enumeration or pointer addresses.

## 6. BBox and projection boundary — important compatibility rule

The original `R_CheckBBox` is **not** a standalone 'rectangle outside camera FOV' predicate:

```text
R_CheckBBox(bspcoord):
    choose bbox silhouette corners relative to viewx/viewy
    compute BAM relative angles and clip to clipangle
    convert to screen columns with viewangletox[]
    compare screen span against current solidsegs[]
    return whether some portion might still be visible
```

In original rendering, `R_RenderBSPNode` invokes `R_CheckBBox` on the **far** child after processing the near subtree; `R_AddLine` updates `solidsegs` during near traversal. Because M3-03 does not implement `R_AddLine`, screen projection and clipping, a naive port of `R_CheckBBox` would be incomplete and might cull valid geometry.

**Acceptance condition:** the far subtree is always traversed in M3-03, regardless of a bbox. Document that M3-04 (clipping/projection integration, or a later clearly assigned step) will introduce the real `R_CheckBBox` with exact `clipangle`, `viewangletox`, and `solidsegs`. Never call the no-cull trace a final visibility solution.

## 7. Test plan — 48 synthetic unit cases (B01–B48)

Create small hand-authored BSP graphs with original/synthetic map records. Use independent expected sequences, not a test oracle that directly calls the production traversal. Group tests as follows; retain unique stable IDs:

| ID | Required assertion focus |
|---|---|
| B01 | Null level is rejected with diagnostic and empty trace |
| B02 | Null camera is rejected |
| B03 | Null trace pointer rejected; no access violation |
| B04 | Uninitialized/not-ready level rejected |
| B05 | Invalid/corrupt root index is rejected before dereference |
| B06 | Zero-node, one-subsector level emits leaf and its segs |
| B07 | Zero-node but invalid multi-leaf raw test object fails safely |
| B08 | One-node tree, camera on side 0: leaf0 then leaf1 |
| B09 | One-node tree, camera on side 1: leaf1 then leaf0 |
| B10 | Vertical partition with camera on exact boundary (original tie) |
| B11 | Horizontal partition with camera on exact boundary |
| B12 | General diagonal partition with exact left/right classification |
| B13 | General partition multiplication equality tie yields back side |
| B14 | Negative node origin and direction produce expected near child |
| B15 | Reverse partition direction reverses side classification |
| B16 | Nested three-node/four-leaf tree: expected full order for camera A |
| B17 | Same nested tree: distinct full order for camera B |
| B18 | Root is last node; no assumption of node 0 |
| B19 | Child encoding high bit `0x8000` and index mask `0x7FFF` |
| B20 | Subsector `firstseg` not zero: emitted absolute seg indices |
| B21 | Multiple segs emitted sequentially within one subsector |
| B22 | Events interleave SUBSECTOR then SEG, not all leaves first |
| B23 | Derived sector index is preserved in SUBSECTOR event |
| B24 | SEG event includes correct linedef, side, front/back sectors |
| B25 | SEG one-sided back-sector `-1` sentinel preserved |
| B26 | Empty/invalid seg range fails or is rejected by loader as specified |
| B27 | Invalid child-node index test object fails safely |
| B28 | Invalid child-subsector index test object fails safely |
| B29 | Self-cycle test object fails or loader rejects as documented |
| B30 | Two-node cycle test object fails or loader rejects |
| B31 | Deep skewed tree traversed iteratively without recursion |
| B32 | Near/far LIFO push order proven against independent oracle |
| B33 | Camera BAM heading change alone does not change unculled walk |
| B34 | Camera map-unit-to-fixed positive conversion exact |
| B35 | Camera map-unit-to-fixed negative conversion exact |
| B36 | Camera conversion rejects out-of-range map units transactionally |
| B37 | Camera preserves raw BAM `ANG180`/`ANG270` as unsigned values |
| B38 | Signed map-coordinate endpoints `-32768`/`32767` convert exactly to 16.16 |
| B39 | M3-02 geometry overflow returns error and clears partial trace |
| B40 | Repeated same camera + level yields identical events/checksum |
| B41 | Distinct camera positions yield expected reordering |
| B42 | Trace reset is idempotent; count becomes zero |
| B43 | Failed build after successful build clears stale events |
| B44 | Success after failure clears prior error and works normally |
| B45 | Trace remains inspectable after source MapLevel reset |
| B46 | Accessor rejects negative index and count-boundary index |
| B47 | Shared-child DAG repeats deterministically or fails by policy |
| B48 | Artificial event/work budget exhausted safely (no hang/OOM) |

**Test construction note:** use the real synthetic 10-lump WAD builder/loader from M2 where possible. Some raw-cycle/corrupt-object tests cannot pass `MapValidateLevel`; test these through a narrowly scoped test-only setup or assert that the real loader rejects them, without weakening production validation. Never make a test pass by skipping its meaningful assertion.

### Independent golden oracle

Use a tiny independently specified graph (`node index`, `child0/child1`, expected side at camera A/B, leaf seg ranges) and hand-computed expected order. For larger synthetic graphs, a **test-only** straightforward recursive/reference interpreter in Python or C may generate expected traces, with explicit depth limit and fixed deterministic seed; it must not simply copy production stack logic. If retaining a generated fixture, store only synthetic tree data and numeric results.

A canonical **FNV-1a64** trace fingerprint is useful but optional. If introduced, define exact **little-endian** serialization of event type and numeric fields; prohibit pointers/structure-padding bytes and ensure independent golden generation. Report the value only after actually running tests—do **not** invent hash constants in advance.

## 8. Integration I01–I03 and owner-IWAD I04

- **I01 — Full synthetic pipeline:** build an original synthetic WAD containing a valid tiny map, open it, `MapLevelLoad`, set camera, trace front-to-back, verify full event order and links using ordinary public APIs. No proprietary data, no renderer/video.
- **I02 — Lifetime / ownership:** load A, trace and checksum; `WADClose`; verify both the owned level and trace remain usable; reset level; verify trace still readable; load distinct synthetic B, trace; reload A; verify identical A checksum/order. Test repeated `BspTraceReset` and failure cleanup.
- **I03 — Edge/error integration:** synthetic malformed node/reference and at least one late geometry/trace-budget failure; verify error diagnostics, unchanged camera and level, transactional empty trace and ability to recover with another valid build.
- **I04 — Optional read-only owner IWAD:** use `data/DOOM.WAD` only when explicitly present/passed, load E1M1/E1M2/E4M1, choose documented fixed camera(s) (e.g. validated player-one THING start converted to fixed), walk tree fully with culling disabled. In each map, expect every **reachable** subsector to be visited and every seg from those leaves to be emitted once for the normal tree; do not assert screen visibility. Compare repeat trace checksums; no full geometry dumps. Historic M2 counts to cross-check, not hardcode as a generic loader rule:

| Map | Expected reachable subsectors | Expected seg records | Nodes in real map |
|---|---:|---:|---:|
| E1M1 | 239 | 747 | 238 |
| E1M2 | 448 | 1463 | 447 |
| E4M1 | 196 | 695 | 195 |

If IWAD is absent, mark **I04 NOT RUN** and exit successfully for optional tests; never label it PASS. Verify owner IWAD unchanged/read-only. Do not print/commit raw map geometry, sprites, textures, screenshots or a reconstructable record list. Prefer coarse statistics and non-reconstructable hashes.

## 9. Tooling, build, scripts and CLI regression

Extend the existing scripts consistently, naming flags to fit actual conventions:

```text
scripts/build.ps1     -BspTest / -BspIntegrationTest / -BspIwadTest
scripts/build.sh      --bsp-test / --bsp-integration-test / --bsp-iwad-test
scripts/test.ps1      syntax, build, run B01–B48, I01–I03; optional I04 only by explicit path
scripts/test.sh       same intended behavior; do not claim Linux runtime without testing
```

Exact spelling may be adapted to the existing script patterns after inspection. Main `src/DoomPB.pb` may include `BSP.pbi` to catch compile-time errors, but must not start graphics, load a map or create a camera on ordinary startup. **No mandatory new `--bsp-info`/`--bsp-trace` CLI feature**; an optional read-only debug mode should only be added if it is trivial and covered by tests. Keep the public CLI stable:

- `--version` prints `DoomPB 0.2.0` with exit 0.
- `--help`, `--dump-info`, `--lump-info PLAYPAL`, and `--map-info E1M1/E1M2/E4M1` still work with their documented paths/error codes.
- `--show-title` opens and closes successfully with local legal IWAD (classic 320x200 -> existing 960x600 presentation); do not call a process smoke a pixel-accurate screenshot test.
- PureBasic 6.41 Windows x64 syntax check, build, all old unit/integration tests. Run `bash -n` only if a suitable shell is available and clearly label it as syntax, **not** Linux runtime validation.

Historical baseline M3-02 script checks **86/86** may increase; record the **observed** new number, test case/assertion count and exact commands. Do not fake newly added assertions or counts.

## 10. Documentation, ownership and repository hygiene

Update relevant docs only with observed data:

- `README.md`: describe M3-03 deterministic BSP trace as a **non-rendering** developer capability; no claim of visible E1M1 walls.
- `CHANGELOG.md`: Unreleased M3-03 entry under `0.2.0` current release.
- `docs/PORTING_NOTES.md`: exact reference functions, deliberate non-pruning difference from `R_CheckBBox`, zero-node handling, camera coordinate/BAM representation, trace ownership, bounds and DAG policy, tests/known limits.
- `docs/DEVELOPMENT_PLAN.md`: check M3 BSP near-to-far item when the tested traversal exists; do not mark screen projection/occlusion, textured walls or M3 release complete.
- `AGENTS.md`: follow existing Context7 policy; avoid modifying unrelated agent rules.

Formatting and safety:

- LF text, zero trailing spaces/tabs, no unintended encoding conversion, no bulk formatting.
- `git diff --check`; `git diff --cached --check`; inspect `git status --short`, `git diff --stat`, all new untracked files and scripts.
- Ensure `data/DOOM.WAD` and `build/` remain ignored, never stage proprietary files/binaries/keys.
- Respect GPL-2.0-only and original id Software copyright attribution where original algorithm code is ported.
- No `git add`, `commit`, `push`, `tag`, `reset`, `clean`, version bump or publishing without explicit owner's approval.

## 11. Acceptance criteria and blocking conditions

M3-03 is **READY FOR OWNER ACCEPTANCE** only when all of these hold:

- [ ] Correct ready `MapLevel` and fixed camera contract, including zero-node root and unsigned BAM heading.
- [ ] Original near-child classification and full near-before-far processing match independent reference order.
- [ ] Subsector events and their seg events preserve canonical in-subsector ordering and derived links.
- [ ] Iterative stack and deterministic event/work limits prevent unbounded recursion/loops/explosive DAGs.
- [ ] All result buffers are owned and transactional; reset/reopen/retry are safe.
- [ ] No premature `R_CheckBBox`/FOV culling, no renderer drawing or gameplay.
- [ ] B01–B48 and I01–I03 pass on a real compiler/runtime.
- [ ] I04 E1M1/E1M2/E4M1 passes with a legal IWAD **or** is explicitly `NOT RUN` if unavailable.
- [ ] All previous M0/M1/M2/M3-01/M3-02 suites rerun and pass; CLI regression passes.
- [ ] Windows build and syntax checks pass with PureBasic 6.41; Linux status is truthful.
- [ ] Documentation and Git/whitespace/license audit pass; application remains `0.2.0`.

If an important correctness issue remains unresolved, report `BLOCKED` with exact reproducible evidence. Do not weaken validation or silently omit tests simply to report success.

## 12. Final report format (required)

Return a concise but complete report with these headings:

```text
Task / milestone: M3-03 BSP Traversal (not M3 overall)
Git branch and initial HEAD; M3-02 committed?:
Windows OS / PureBasic exact version; Linux runtime status:
Original C pinned SHA / exact symbols consulted:
Documentation lookup: Context7 USED / NO MATCH / UNAVAILABLE / NOT NEEDED; fallbacks
Files created and modified:
Camera structure, fixed coordinate/BAM API and overflow rules:
BSP iterative traversal algorithm, near/far ordering, node/leaf root:
R_CheckBBox / occlusion status (must state deferred):
Event schema, counts, ownership, memory/work limits and DAG policy:
B01–B48: cases, assertions, failures:
I01–I03: cases, assertions, failures:
I04 owner IWAD E1M1/E1M2/E4M1: PASS / NOT RUN, counts and repeat hashes:
Previous regression totals and script checks (observed, not predicted):
Syntax checks and builds (exact commands, exit codes):
CLI regressions including --show-title and --map-info:
Git diff, whitespace, ignored assets and license checks:
Differences from original Doom and unresolved risks:
Release decision: READY FOR OWNER ACCEPTANCE / BLOCKED:
Suggested next task: M3-04 wall clipping preparation; later projection / occlusion integration:
```

**Finish at M3-03.** Do not proceed into M3-04 or promise visible walls yet. Later M3 steps will connect this traversal to screen-angle tables, solid-wall clipping and, once its dependencies exist, a faithful `R_CheckBBox` visibility predicate.
