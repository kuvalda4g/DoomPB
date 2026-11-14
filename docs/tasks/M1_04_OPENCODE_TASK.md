# DoomPB — M1-04: TITLEPIC presentation in a PureBasic window

> - **Task ID:** `M1-04`
> - **Milestone:** M1 — WAD Loader + TITLEPIC (`v0.1.0` is **not yet released**)
> - **Task status:** implementation assignment; not evidence that M1-04 has passed
> - **Agent:** OpenCode Desktop + DeepSeek V4.1 Flash 1017
> - **Recommended reasoning:** High; escalate only for an unresolved, reproducible problem
> - **Language / toolchain:** PureBasic 6.41, full edition
> - **First verification target:** Windows x64; Linux runtime must be reported `NOT RUN` unless actually tested
> - **License:** GPL-2.0-only
> - **Pinned reference:** `../doom-original` at commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`
> - **Required reading:** `AGENTS.md`, `docs/DEVELOPMENT_PLAN.md` (M1), `docs/PORTING_NOTES.md`, this task, actual implementation and tests for M1-01/M1-02/M1-03

## 1. Objective and scope

Continue from the **committed M1-03 implementation** without regenerating the existing project. Connect the current WAD loader, `PLAYPAL` palette decoder and Doom Patch decoder to a **real PureBasic window**, and display `TITLEPIC` from the owner's legally obtained Ultimate Doom `DOOM.WAD`.

The first observable goal: launch `DoomPB.exe --iwad data/DOOM.WAD --show-title`, see a correctly colored title image and close the window normally without a hang, crash, memory leak or error. Exact CLI spelling may be adapted to existing code, but should be documented and remain unambiguous.

Keep the architecture suitable for the future software renderer: **indexed framebuffer in RAM → palette conversion → PureBasic presentation**. Do not decode WAD directly into GUI objects or couple the framebuffer to Win32-specific APIs.

### Explicit non-goals

- No BSP, level renderer, game loop, controls, monsters, sound, textures, COLORMAP, PWAD overlays or cache/zone allocator.
- No OpenGL/Vulkan game renderer, SDL, C DLL wrapper or third-party image library.
- No gameplay version bump, tag, GitHub Release, binary distribution or changes to the GPL license.
- No automatic resource extraction, PNG/BMP export, WAD payload dump or inclusion of copyrighted screenshots/assets in Git.
- Do not rewrite tested M1-01/02/03 modules unless a focused bug is demonstrated with a reproducer.

## 2. Mandatory inspection before editing

1. Run `git status --short --branch`, `git log -1 --oneline`, `git diff --stat`, `git diff --cached --stat`. Confirm M1-03 is committed. Preserve all pre-existing staged, untracked and edited files; do not assume the tree is clean.
2. Read actual declarations and ownership rules in `src/Graphics/Palette.pbi`, `src/Graphics/Patch.pbi`, `src/WAD/WAD.pbi`, `src/DoomPB.pb`, all three current unit suites and `scripts/{build,test}.{ps1,sh}`. Do not invent API signatures from the previous task report.
3. Verify `../doom-original` pinned commit. Inspect `linuxdoom-1.10/v_video.c`, `i_video.c`, `d_main.c` (`D_PageDrawer`) and related code. Identify which behavior is original Doom behavior and which is a modern presentation adapter.
4. Verify actual PureBasic 6.41 APIs **using installed compiler + official documentation**, especially `CreateImage`, `StartDrawing(ImageOutput())`, `DrawingBuffer`/pitch/format if used, `ResizeImage`, `ImageGadget` or `WindowOutput`, `OpenWindow`, `WaitWindowEvent`, `StopDrawing`, `FreeImage` and `CloseWindow`.
5. Before writing code, present a short design: exact files changed, module interfaces, ownership and cleanup graph, pixel byte order, chosen presentation method, CLI behavior, planned synthetic and manual tests.

## 3. Established baseline — preserve it

From the accepted M1-03 report; confirm against the **current source**:

```text
PaletteSet { Magic, Count, *RGB }
PaletteDecode(*Bytes, Length, *Result) -> boolean
PaletteReset(*Result)
PaletteGetRGB(*Result, PaletteIndex, ColorIndex, *R, *G, *B)

PatchImage { Magic, Width, Height, LeftOffset, TopOffset,
             PixelCount, *Pixels, *Mask }
PatchDecode(*Bytes, Length, *Result) -> boolean
PatchReset(*Result)
PatchPixelAt(...), PatchOpaqueAt(...)

WADOpen(Path), WADFindLump(Name), WADLumpSize(Index),
WADReadLump(Index, *Destination, Capacity.q), WADClose()
```

- `PLAYPAL` is RGB triples: `14 × 256 × 3 = 10,752` bytes for known Ultimate Doom; use palette **0** for `TITLEPIC`.
- Decoded `TITLEPIC`: **320 × 200**, **64,000 pixels**, every pixel opaque, offsets `(0, 0)` in the known user IWAD.
- Existing patch pixels are row-major **8-bit palette indices** plus an independent opacity mask. The input buffer may be freed after a successful decode.
- `255` is a legitimate **opaque palette index** and must never mean transparency by itself.
- Existing test baselines (historic, must actually rerun): M0/CLI 29/29 script checks; M1-01 17/17 cases, 146/146 assertions; M1-02 21/21 cases, 152/152 assertions; M1-03 palette 10/10, 76/76 and patch 24/24, 121/121.
- Application version stays **`0.0.1`** during implementation. Deciding whether to set `0.1.0` and tag `v0.1.0` is a later owner-controlled acceptance/release action.

### Known Ultimate Doom checksums (optional read-only integration)

| Item | Expected |
|---|---|
| IWAD MD5 | `c4fe9fd920207691a9f493668e0a2083` |
| Total bytes | `12408292` |
| Lump count | `2306` |
| `PLAYPAL` size / decoded palettes | `10752` / `14` |
| `TITLEPIC` size | `68168` |
| Decoded width × height | `320 × 200` |
| Decoded pixel FNV-1a64 | `19C7668B2DF19A1A` |
| Decoded mask FNV-1a64 | `C68BF664EFA3E525` |
| Pixel indices in corners | `187`, `179`, `0`, `2` |

These values identify **one** legitimate IWAD revision. Do **not** reject other legal IWADs just for different hashes or different `TITLEPIC` dimensions. The task's viewing code should accept valid patch dimensions subject to reasonable limits; 320 × 200 is the initial known integration case.

## 4. Part A — software framebuffer (new `src/Graphics/FrameBuffer.pbi`)

Implement a small **platform-independent**, ownership-safe indexed framebuffer module. The Doom world renderer will eventually write to this buffer instead of directly to a window.

### Preferred model

- Own a contiguous row-major plane of `Width * Height` **8-bit palette indices**; classic target `320 × 200`.
- Use caller-visible lifecycle APIs such as `FrameBufferCreate/Reset/Clear/BlitPatch`, or names consistent with existing modules. Do not assume those API names already exist. Document `Create/Reset` ownership and whether reusable output structures must be zero-initialized once.
- Validate `Width`, `Height`, multiplication/size caps, null pointers, image bounds and all allocations before writing. Avoid unchecked `.i` / `.l` conversion and row indexing.
- Clear to a specified palette index, not directly to RGB.
- Copy/blit an already decoded `PatchImage` using **its opacity mask**; masked-out source pixels leave destination pixels unchanged. A valid index `255` must be copied when mask=1.
- Define intentional placement semantics: raw `x,y` blit positioning for TITLEPIC. Preserve `LeftOffset/TopOffset` and do **not** silently apply origin offsets unless a separate documented anchor-aware operation is required.
- Clip safely at all four edges; reject malformed dimensions and invalid structures. Allow clean, harmless behavior for fully offscreen blits.
- Keep the framebuffer usable with **no window** (for headless unit tests and future renderer).
- Prefer one reusable allocation over allocation per pixel or frame.
- Explicitly document whether failed creation/decode leaves a reusable empty framebuffer and ensure `Reset` is idempotent after successful initialization.

### Palette conversion

Keep palette-index data as the authoritative framebuffer. Add a separately testable conversion routine, either in `FrameBuffer.pbi` or a very small `Graphics` companion function:

```text
(indexed framebuffer, PaletteSet, palette index 0, destination RGB/RGBA buffer)
    -> boolean success + deterministic color data
```

- Use the decoded **RGB 0..255** channels without VGA scaling, BGR swaps, gamma, lighting or interpolation.
- Avoid relying on a guessed `RGB()` packed integer layout when writing native memory. Specify and test a **canonical output byte order** for CPU-side conversion (for example explicit RGBA bytes `R,G,B,255`), then adapt it when uploading to the PureBasic image surface.
- If `DrawingBuffer()` is used, respect **`DrawingBufferPitch()`**, actual **`DrawingBufferPixelFormat()`** and possible **`#PB_PixelFormat_ReversedY`**; never assume `width * 4` stride or universal BGRA ordering.
- A portable per-pixel `Plot(x,y,RGB(r,g,b))` upload path is acceptable for this static 320×200 milestone if direct buffer formats are unreliable; first correctness, then performance. Keep the expensive upload outside the event loop when the picture has not changed.
- For transparent source patches, compositing uses the mask **before** conversion. Final displayed TITLEPIC is opaque; a transparent patch should reveal the framebuffer's previously existing index.
- No WAD I/O or GUI calls inside pixel conversion functions.

## 5. Part B — window/presentation adapter (new `src/Graphics/Video.pbi`)

Use PureBasic standard graphics/window libraries to present a finished framebuffer. Keep image resource handles local to the presentation layer and ensure every failure path releases them.

### Initial display mode

- Open a centered native window titled clearly, e.g. `DoomPB — TITLEPIC (M1-04)`.
- First supported mode: **native 320 × 200 source**, enlarged by an exact **3× nearest-neighbor** mapping to **960 × 600 client pixels** for deterministic pixel-perfect output. Do not add blur/bilinear smoothing.
- **Important aspect-ratio distinction:** 320 × 200 has **8:5** pixel dimensions. Original CRT-era Doom was generally displayed at **4:3** by stretching the image vertically. `960 × 600` is pixel-perfect square-pixel scaling, **not** historical 4:3 correction. Clearly document this. Historical 4:3 mode (`960 × 720` for a 960-pixel-wide display) may be investigated as a separate optional enhancement, but must not obscure or break the mandatory 3× test.
- Keep the renderer-side framebuffer at 320 × 200 regardless of display size. Never resize/rewrite the original index plane to obtain window dimensions.
- A straightforward `CreateImage()` → `StartDrawing(ImageOutput())` → pixel upload → `ImageGadget()` or `WindowOutput()` design is acceptable; `ResizeImage(...,#PB_Image_Raw)` on a **copy** of the source can implement nearest-neighbor. Verify output with real PB 6.41; `ResizeImage` changes the image object and can invalidate image IDs.
- If using direct `WindowOutput()`, repaint the window when needed (`#PB_Event_Repaint`, restore/expose) because its content can be lost. If using `ImageGadget`, confirm the content survives uncover/minimize/restore and the resource's image handle remains valid.
- Keep the window alive until the user closes it; process window events via `WaitWindowEvent()` or another CPU-friendly event loop. No busy spin and no accidental exit immediately after showing the picture.
- Handle window creation/drawing/image allocation failures with a useful message and a nonzero exit code. Close normally with exit code 0, including repeated open/close runs.
- Do not assume graphics/display is present on a headless CI environment. Automated tests must not launch a blocking GUI without an explicit interactive option.

### Modularity and performance guardrails

- The presentation adapter may depend on framebuffer/palette; the framebuffer **must not** depend on windowing.
- Do not introduce Win32-only window handles or renderer DLLs. Use portable PureBasic APIs where possible; document any platform caveats.
- Recreate/upload scaled images only when underlying frame or output size actually changes. Avoid 64,000 `Plot` calls on every idle event.
- Avoid unnecessary image copies if a simpler working PureBasic method is demonstrated, but not at the expense of byte-order or lifetime correctness.
- The eventual Doom game loop will repaint frequently; do not present a static title-screen-only implementation as a proven high-performance gameplay renderer.

## 6. Part C — CLI integration and lifecycle

Preserve all previously verified console behavior and exit codes:

```text
DoomPB --version                                -> 0, 'DoomPB 0.0.1'
DoomPB --help                                   -> 0
DoomPB                                         -> 0, existing bootstrap behavior
DoomPB --iwad <path> --dump-info                -> 0 or 1 on WAD failure
DoomPB --iwad <path> --lump-info <name>         -> 0 or 1 on WAD/lookup failure
unknown/malformed CLI options                  -> 2
```

Add a new explicit **interactive** mode, preferably:

```text
DoomPB --iwad data/DOOM.WAD --show-title
```

- Treat `--show-title` as an intentional GUI action; plain `--iwad` or `--dump-info` must never unexpectedly open a window.
- Validate required arguments; failure to open IWAD / missing `PLAYPAL` / missing `TITLEPIC` / invalid payload / graphics initialization error returns **nonzero** with an actionable diagnostic. Malformed CLI syntax returns exit **2**; valid arguments with a runtime/resource error return **1**, consistent with existing policy.
- Use only `WADFindLump()` and `WADReadLump()` for resource access; do not make a second WAD parser or use embedded Doom assets.
- Read both lump payloads into temporary caller-owned buffers, decode to `PaletteSet` / `PatchImage`, then release raw buffers once no longer required. Construct framebuffer, composite patch, convert to display image and keep resources alive only as long as needed.
- **Centralize cleanup** after every path: WAD close, `PaletteReset`, `PatchReset`, framebuffer reset, temporary FreeMemory, `FreeImage`, window close. Respect actual existing `Magic`/initialization contracts; do not apply reset to uninitialized garbage structures.
- Never print or save copyrighted pixel bytes or dump the TITLEPIC graphic to a tracked asset. Reporting dimensions and checksums is fine.
- If malformed resource data is encountered, fail cleanly **before** showing a partly initialized image/window.

## 7. Automated test requirements

Add a new synthetic test suite (e.g. `tests/unit/wad_display_tests.pb`) integrated into existing build/test scripts without removing earlier suites. Prefer reusable tiny tests for framebuffer/palette math; no commercial WAD required. Write minimal fully synthetic `PaletteSet`/`PatchImage`-like inputs using public constructors or decoders rather than corrupting private ownership fields.

At minimum test the following **24 categories**. Several assertions per case are expected; list real counts in report.

| ID | Scenario | Expected result |
|---|---|---|
| F01 | Framebuffer create 320×200 | Correct dimensions and 64,000-byte index plane |
| F02 | Clear with index 0 | All indices become 0 |
| F03 | Clear with index 255 | All pixels become 255, not transparent |
| F04 | Valid 2×2 patch blit at origin | Correct row-major placement |
| F05 | Patch with transparent gaps | Destination preserved where mask=0 |
| F06 | Opaque source pixel index 255 | Destination index 255 retained |
| F07 | Repeated/overlapping patch blits | Later opaque pixels win; masked pixels do not overwrite |
| F08 | Left/top clipping | Correct surviving destination pixels; no out-of-bounds |
| F09 | Right/bottom clipping | Correct surviving destination pixels; no out-of-bounds |
| F10 | Entirely offscreen blit | Defined no-op or clearly documented result; no corruption |
| F11 | Invalid/null patch or framebuffer | Controlled failure, no access violations |
| F12 | Invalid dimensions / overflow / budget | Reject without dangerous allocation |
| F13 | Repeated create/reset | Safe lifetime, no double-free or stale state |
| F14 | Valid `PaletteSet` palette 0 conversion | Known RGB triples map to exact expected channels |
| F15 | RGB channel order with asymmetric test color | Detect R/B swaps (e.g. R=17, G=93, B=201) |
| F16 | Palette index 255 conversion | Color 255 is valid and opaque |
| F17 | Multiple palette indices | Only requested palette used (test palette 0 vs 1) |
| F18 | Invalid palette index / null pointers | Controlled failure; canary buffers not overwritten |
| F19 | Exact destination size / undersized output | Exact size succeeds; insufficient capacity fails before writing |
| F20 | Pixel conversion at edge indices | Correct first/last pixels and row boundaries |
| F21 | 3× nearest-neighbor mapping on tiny synthetic image | Each source pixel maps to a 3×3 block; no interpolation |
| F22 | Unsupported/invalid output size | Safe error; no divide by zero/overflow |
| F23 | Failure then successful reuse | No stale buffers, status or error |
| F24 | End-to-end synthetic palette+patch+framebuffer | Deterministic pixel/checksum output without GUI |

For F21, test nearest-neighbor **mapping math** independently of GUI rendering, or provide a testable CPU software scaler used by the adapter. If delegating nearest-neighbor scaling to PureBasic `ResizeImage(...,#PB_Image_Raw)`, verify with a tiny in-memory image and `Point()` checks in a **headless-safe** image test; report whether that image test can run without a desktop. Do not assert successful graphics tests by merely comparing declared dimensions.

### Regression and CLI tests

1. Preserve previous compiled suites: M1-01 **17 cases, 146 assertions**, M1-02 **21, 152**, M1-03 **34 total, 197 assertions**, and M0/CLI checks. These are historic observed counts; report actual values from this run.
2. Add nonblocking CLI checks for bad `--show-title` syntax and missing/nonexistent WAD. **Do not** open an interactive window from ordinary `scripts/test.ps1` or CI.
3. Ensure all three previous build targets and new display test target are syntax-checked and really compiled, not only statically reviewed.
4. Test native library failure behavior with a small standalone repro if memory layout or scaling behavior is uncertain.
5. Run `bash -n scripts/build.sh scripts/test.sh` when Bash is available. **Linux runtime `NOT RUN`** without real Linux PureBasic and a display; do not claim otherwise.

## 8. Optional read-only Ultimate Doom integration + required manual GUI acceptance

If local `data/DOOM.WAD` or `local-data/DOOM.WAD` exists, execute read-only integration. Check the expected known size/lump count (or report a different legitimate file), `PLAYPAL` first palette, `TITLEPIC` dimensions, opaque pixel count and previously reported checksums.

Then, **on an interactive Windows desktop**, launch:

```powershell
./scripts/build.ps1
./build/DoomPB.exe --iwad data/DOOM.WAD --show-title
```

Manually confirm all items below; distinguish the agent's own observed checks from checks requiring the **human owner**. If OpenCode cannot inspect the visible window, explicitly mark visual checks **OWNER VERIFICATION REQUIRED** rather than claiming that it looked correct.

- [ ] An actual window opens and remains visible until closed.
- [ ] The displayed image visually matches **the Ultimate Doom TITLEPIC** with correct colors, no obvious red/blue inversion, missing lines, unwanted transparency or black bars.
- [ ] The source content is 320×200; initial window client area is 960×600, nearest-neighbor pixel-perfect 3×, with no blurred filtering.
- [ ] Minimize/restore, cover/uncover and repaint work; no lost/blank image.
- [ ] Closing via window X terminates the process normally, exit 0; repeated launch/close also succeeds.
- [ ] Missing WAD, missing TITLEPIC, invalid patch or palette yield useful errors and no stuck processes; malformed synthetic data must be used rather than modifying user's IWAD.
- [ ] The user's commercial WAD remains unchanged. No screenshots or image resources are staged/published. Owner may keep a local screenshot for private review.

**Historical display aspect note:** This acceptance test proves pixel-perfect 3× presentation, **not** CRT 4:3 correction. If optional 4:3 is implemented, test and document it separately and never imply its pixels remain exact 3× squares.

## 9. Build, diff, licensing and resource audit

1. Run full Windows check/build/test using existing scripts, extended with one focused display test target only if needed. Capture commands and process exit codes.
2. Run the optional real-IWAD integration without exporting any commercial data. Keep any screenshots private/local; do not make images part of source or artifacts for this task.
3. Inspect `git diff --check`, `git diff --stat`, full diffs, `git diff --cached --check`, `git status --short --branch` and list any untracked files.
4. Verify **no trailing whitespace** in touched `.pb`, `.pbi`, `.ps1`, `.sh` or `.md`. No Markdown two-space hard breaks. Preserve project LF/CRLF rules.
5. Ensure no `*.wad`, binary executable, image dump, screenshots, credentials, absolute user paths, `build/`, `data/` or `local-data/` are staged or included in patch.
6. Do **not** run `git add`, `git commit`, `git push`, `git tag`, publish releases or start M2 unless the owner expressly authorizes it. Keep modifications unstaged.
7. Update only necessary documentation: `README.md` for new CLI/UI feature and current stage; `docs/PORTING_NOTES.md` for pixel format, display mode, source C mapping, lifetime, limitations. Do not do a wholesale reformat.
8. Never silently claim GUI success from passing headless unit tests or Windows success as Linux validation.

## 10. Definition of Done

- [ ] M1-03 commit and actual existing source inspected; upstream SHA verified.
- [ ] Indexed software framebuffer is memory-safe, independently testable, owns its allocation and supports opaque/transparent patch blit.
- [ ] Palette index → RGB/RGBA conversion is deterministic and color-order tested.
- [ ] `Video.pbi` presents the framebuffer using PureBasic native window/image APIs; no C engine/SDL dependency.
- [ ] `--iwad ... --show-title` opens a real window and displays the decoded TITLEPIC using palette 0, with a 960×600 pixel-perfect 3× mode.
- [ ] GUI event loop supports normal close/repaint, no busy loop, no resource leak on repeated launches.
- [ ] All 24 new synthetic categories pass using the actual PureBasic 6.41 compiler, alongside all previous tests.
- [ ] Interactive window/image visually accepted by the human owner, or clearly marked as outstanding rather than PASS.
- [ ] Windows actual syntax/build/test evidence recorded; Linux runtime not claimed without execution.
- [ ] Diff/whitespace/privacy audit clean, no staging, commits or tags by agent.
- [ ] M1-04 is reported complete only if the interactive acceptance and Definition of Done pass. **Do not release/tag `v0.1.0` until the owner explicitly approves milestone M1.**

## 11. Mandatory completion report

```text
Task / milestone: M1-04 — TITLEPIC presentation
OS / PureBasic compiler: <actual>; Linux runtime: PASS / FAIL / NOT RUN
Baseline HEAD / worktree: <actual git status and branch>
Original Doom C symbols consulted: <files/functions and pinned SHA>
Files created / modified: <paths>
Framebuffer API / ownership: <exact signatures, memory lifecycle>
Pixel conversion: <RGB/RGBA ordering, pitch/format handling, tests>
Video backend: <PureBasic library and redraw/resize approach>
CLI: <exact invocation, exit codes, error behavior>
Syntax check: PASS / FAIL / NOT RUN — <commands and exit codes>
Build: PASS / FAIL / NOT RUN — <commands and exit codes>
M0 / M1-01 / M1-02 / M1-03 regression: <actual test cases and assertions>
New M1-04 tests: <actual F01–F24 counts and assertions>
Ultimate Doom integration: PASS / FAIL / NOT RUN — <metadata/checksums only>
Visible window review: PASS / FAIL / OWNER VERIFICATION REQUIRED
Window close/repaint/restart: PASS / FAIL / OWNER VERIFICATION REQUIRED
Git status, diff, whitespace and commercial-data audit: <results>
Known deviations: <square-pixel 8:5 vs historical 4:3; others>
Next action: M1-04 owner acceptance, then owner-controlled commit/v0.1.0 decision
```

## 12. Reference links

- [Doom GPL source code / `linuxdoom-1.10`](https://github.com/id-Software/DOOM/tree/master/linuxdoom-1.10)
- [PureBasic official documentation](https://www.purebasic.com/documentation/)
- [PureBasic `CreateImage()`](https://www.purebasic.com/documentation/image/createimage.html)
- [PureBasic `DrawingBufferPixelFormat()`](https://www.purebasic.com/documentation/2ddrawing/drawingbufferpixelformat.html)
- [PureBasic `DrawingBufferPitch()`](https://www.purebasic.com/documentation/2ddrawing/drawingbufferpitch.html)
- [PureBasic `StartDrawing()`](https://www.purebasic.com/documentation/2ddrawing/startdrawing.html)
- [PureBasic `ResizeImage()`; raw/no interpolation](https://www.purebasic.com/documentation/image/resizeimage.html)
- [PureBasic `ImageGadget()`](https://www.purebasic.com/documentation/gadget/imagegadget.html)
- [PureBasic `WindowOutput()` and repaint behavior](https://www.purebasic.com/documentation/window/windowoutput.html)
- [PureBasic `WaitWindowEvent()`](https://www.purebasic.com/documentation/window/waitwindowevent.html)
- [Chocolate Doom: correct 4:3 aspect ratio](https://www.chocolate-doom.org/wiki/index.php/Setup/Display_configuration)

**Reminder:** This task document specifies desired behavior, not an already-running GUI. Do not claim Windows visual success, Linux runtime success or release completion until verified.
