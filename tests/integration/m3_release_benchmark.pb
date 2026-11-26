; -----------------------------------------------------------------------------
; DoomPB - M3-07 Windows wall-only frame benchmark (BEN01)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Test/integration benchmark over wholly synthetic TI02 resources/maps only.
; Measures (a) cold end-to-end wall preview: synthetic WADOpen, PNAMES/TEXTURE/
; flat/COLORMAP decode, map load, player-one view, M3-04 visibility, projection,
; cache/lighting/plan build and textured frame; (b) warm frame-only textured
; rendering on a prepared session with no resource reopen/redecode, including
; the per-frame pre-column unique-texture compose/cache and lighting/plan build;
; (c) warm legacy M3-05 debug-color frame rendering for comparison.
;
; Windows uses a verified kernel32.lib QueryPerformanceFrequency/Counter
; monotonic clock; Linux fallback (not run here) uses ElapsedMilliseconds and
; reports coarse resolution honestly instead of inventing sub-millisecond time.
; Individual frames are timed without batching because the QPC resolution is
; well below frame cost; observed counts/minimum/median/p95 are printed.
;
; Each frame verifies fixture hash/counters and the fixed outer allocation
; formula (cache allocations + five frame resources). The draw path has no
; per-column allocation/compose/WADRead call (static source audit mirrors MR35).
; This is a wall-only preview metric, not a complete Doom FPS claim; no hard
; performance threshold can fail due host variance. Exit code is 0 when all
; functional/determinism counters and timings are valid, otherwise failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Map/MapTypes.pbi"
XIncludeFile "../../src/Map/MapDecode.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/BSP.pbi"
XIncludeFile "../../src/Renderer/Projection.pbi"
XIncludeFile "../../src/Renderer/ClipSegs.pbi"
XIncludeFile "../../src/Renderer/WallVisibility.pbi"
XIncludeFile "../../src/Renderer/WallView.pbi"
XIncludeFile "../../src/Renderer/WallProject.pbi"
XIncludeFile "../../src/Renderer/WallDraw.pbi"
XIncludeFile "../../src/Renderer/RenderMain.pbi"
XIncludeFile "../../src/Renderer/WallTextureMapping.pbi"
XIncludeFile "../../src/Renderer/WallTextureCache.pbi"
XIncludeFile "../../src/Renderer/WallLighting.pbi"
XIncludeFile "../../src/Renderer/TexturedWallDraw.pbi"
XIncludeFile "../../src/Renderer/TexturedRenderMain.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/FrameBuffer.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Patch.pbi"
XIncludeFile "../../src/Graphics/Texture.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../fixtures/m3_wall_texture_golden.pbi"
XIncludeFile "../../tests/integration/wall_texture_support.pbi"

#BEN_FNV_Offset = -3750763034362895579
#BEN_FNV_Prime = 1099511628211
#BEN_ViewWidth = 320
#BEN_ViewHeight = 200
#BEN_PixelCount = 64000
#BEN_SceneWadName = "m3benchmark-ti02.wad"
#BEN_MapMarker = "E2M1"
#BEN_ColdWarmups = 2
#BEN_ColdMeasured = 11
#BEN_WarmWarmups = 20
#BEN_WarmMeasured = 100
#BEN_DebugWarmups = 10
#BEN_DebugMeasured = 100

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #BEN_ClockKind = 1
Import "kernel32.lib"
  QueryPerformanceFrequency(*Frequency)
  QueryPerformanceCounter(*Count)
EndImport
CompilerElse
  #BEN_ClockKind = 2
CompilerEndIf

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #BEN_Separator = "\"
CompilerElse
  #BEN_Separator = "/"
CompilerEndIf

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0
Global gClockFrequency.q = 0
Global gClockResolutionUS.q = 0

; ---------------------------------------------------------------------------
; Harness and deterministic helpers
; ---------------------------------------------------------------------------

Procedure BeginCase(Id.s, Title.s)
  gCaseCount + 1
  PrintN("")
  PrintN("[" + Id + "] " + Title)
EndProcedure

Procedure Check(Ok.i, Description.s)
  gAssertionCount + 1
  If Ok
    PrintN("  PASS: " + Description)
  Else
    PrintN("  FAIL: " + Description)
    gFailureCount + 1
  EndIf
EndProcedure

Procedure.q FnvByte(Hash.q, Value.i)
  Protected byteValue.q = Value & $FF

  Hash = Hash ! byteValue
  ProcedureReturn (Hash * #BEN_FNV_Prime) & $FFFFFFFFFFFFFFFF
EndProcedure

Procedure.q TestFrameHash(*Frame.FrameBuffer)
  Protected hash.q = #BEN_FNV_Offset
  Protected i.i

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #BEN_ViewWidth Or *Frame\Height <> #BEN_ViewHeight Or
     *Frame\PixelCount <> #BEN_PixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For i = 0 To #BEN_PixelCount - 1
    hash = FnvByte(hash, PeekA(*Frame\Pixels + i))
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q FixtureHashAt(*Label.Byte)
  ProcedureReturn PeekQ(*Label)
EndProcedure

; ---------------------------------------------------------------------------
; Monotonic clock (real QueryPerformanceFrequency/Counter on Windows)
; ---------------------------------------------------------------------------

Procedure.i BenchInitializeClock(*Frequency.Quad, *ResolutionUS.Quad)
  Protected measuredFrequency.q = 0

  PokeQ(*Frequency, 0)
  PokeQ(*ResolutionUS, 0)
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    If QueryPerformanceFrequency(*Frequency) = 0
      ProcedureReturn #False
    EndIf
    measuredFrequency = PeekQ(*Frequency)
    If measuredFrequency <= 0
      ProcedureReturn #False
    EndIf
    PokeQ(*ResolutionUS, (1000000 + measuredFrequency - 1) / measuredFrequency)
  CompilerElse
    ; Coarse fallback only; represent ElapsedMilliseconds units as 1000 Hz.
    PokeQ(*Frequency, 1000)
    PokeQ(*ResolutionUS, 1000)
  CompilerEndIf
  ProcedureReturn #True
EndProcedure

Procedure.q BenchTicksNow()
  Protected ticks.q = 0
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    If QueryPerformanceCounter(@ticks) = 0
      ProcedureReturn 0
    EndIf
  CompilerElse
    ticks = ElapsedMilliseconds()
  CompilerEndIf
  ProcedureReturn ticks
EndProcedure

Procedure.q BenchElapsedMicroseconds(StartTicks.q, StopTicks.q, Frequency.q)
  Protected difference.q

  difference = StopTicks - StartTicks
  If difference < 0 Or Frequency <= 0
    ProcedureReturn -1
  EndIf
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    ProcedureReturn (difference * 1000000) / Frequency
  CompilerElse
    ProcedureReturn difference * 1000
  CompilerEndIf
EndProcedure

; In-place insertion sort of measured Quad microseconds; observed min, median,
; p95 rank and mean are returned. No floating point or fabricated sub-ms claim.
Procedure.i TimingStats(*Values.Quad, Count.l, *Min.Quad, *Median.Quad,
                        *P95.Quad, *Mean.Quad)
  Protected i.l
  Protected j.l
  Protected key.q = 0
  Protected left.q = 0
  Protected total.q = 0
  Protected p95Index.l = 0

  PokeQ(*Min, -1)
  PokeQ(*Median, -1)
  PokeQ(*P95, -1)
  PokeQ(*Mean, -1)
  If *Values = 0 Or Count <= 0
    ProcedureReturn #False
  EndIf
  For i = 1 To Count - 1
    key = PeekQ(*Values + Int(i) * SizeOf(Quad))
    j = i - 1
    While j >= 0
      left = PeekQ(*Values + Int(j) * SizeOf(Quad))
      If left > key
        PokeQ(*Values + Int(j + 1) * SizeOf(Quad), left)
        j = j - 1
      Else
        Break
      EndIf
    Wend
    PokeQ(*Values + Int(j + 1) * SizeOf(Quad), key)
  Next
  total = 0
  For i = 0 To Count - 1
    total = total + PeekQ(*Values + Int(i) * SizeOf(Quad))
  Next
  PokeQ(*Min, PeekQ(*Values + 0))
  PokeQ(*Median, PeekQ(*Values + Int(Count / 2) * SizeOf(Quad)))
  p95Index = Int((Int(Count) * 95) / 100)
  If p95Index >= Count
    p95Index = Count - 1
  EndIf
  PokeQ(*P95, PeekQ(*Values + Int(p95Index) * SizeOf(Quad)))
  PokeQ(*Mean, total / Int(Count))
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic TI02 builder/session/release helpers (existing modules only)
; ---------------------------------------------------------------------------

Procedure.s BenchFixturePath(FileName.s)
  ProcedureReturn WallTexFixturePath(FileName.s)
EndProcedure

Procedure.i BuildBenchmarkScene()
  Protected ok.i = #False

  If WallTexWadBegin(#BEN_SceneWadName) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9)
    ok = WallTexBuildT02MapLumps()
    If ok
      ok = WallTexAddMapLumpsToWad(#BEN_MapMarker)
    EndIf
  EndIf
  If ok
    ok = WallTexWadFinish()
  EndIf
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  WallTexFreeMap()
  ProcedureReturn ok
EndProcedure

Procedure.i PrepareBenchSession(*Pnames.PNamesTable,
                                *Textures.TextureCatalog,
                                *Flats.FlatCatalog,
                                *Colormap.ColormapSet,
                                *Level.MapLevel, *View.WallView,
                                *Projection.Projection,
                                *Visibility.WallVisibilityResult)
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0

  PNamesReset(*Pnames)
  TextureCatalogReset(*Textures)
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  MapLevelReset(*Level)
  WallViewReset(*View)
  ProjectionReset(*Projection)
  WallVisibilityReset(*Visibility)

  If WADOpen(BenchFixturePath(#BEN_SceneWadName)) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallCatalog(*Pnames, *Textures) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallFlats(*Flats) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallColormap(*Colormap) = #False
    ProcedureReturn #False
  EndIf
  If MapLevelLoad(#BEN_MapMarker, *Level) = #False
    ProcedureReturn #False
  EndIf
  If WallRenderPlayerStartView(*Level, *View, @thingIndex, @subsectorIndex,
                               @sectorIndex) = #False
    ProcedureReturn #False
  EndIf
  If ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallVisibilityBuild(*Level, @*View\Camera, *Projection,
                                      *Flats, *Textures, *Visibility)
EndProcedure

Procedure CleanupBenchSession(*Pnames.PNamesTable,
                              *Textures.TextureCatalog,
                              *Flats.FlatCatalog,
                              *Colormap.ColormapSet,
                              *Level.MapLevel, *View.WallView,
                              *Projection.Projection,
                              *Visibility.WallVisibilityResult)
  If WADIsOpen()
    WADClose()
  EndIf
  PNamesReset(*Pnames)
  TextureCatalogReset(*Textures)
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  MapLevelReset(*Level)
  WallViewReset(*View)
  ProjectionReset(*Projection)
  WallVisibilityReset(*Visibility)
EndProcedure

; ---------------------------------------------------------------------------
; BEN01 - cold, warm textured and warm debug measurements
; ---------------------------------------------------------------------------

Procedure TestBEN01()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected texturedTarget.FrameBuffer
  Protected texturedResult.TexturedWallRenderResult
  Protected debugTarget.FrameBuffer
  Protected debugResult.WallRenderResult
  Protected Dim coldTimes.q(#BEN_ColdMeasured - 1)
  Protected Dim warmTimes.q(#BEN_WarmMeasured - 1)
  Protected Dim debugTimes.q(#BEN_DebugMeasured - 1)
  Protected cycle.l
  Protected measuredIndex.l
  Protected startTicks.q = 0
  Protected stopTicks.q = 0
  Protected elapsed.q = 0
  Protected coldFailed.l = 0
  Protected warmFailed.l = 0
  Protected debugFailed.l = 0
  Protected hashMismatch.l = 0
  Protected allocMismatch.l = 0
  Protected prepareFailed.l = 0
  Protected finalTexHash.q = 0
  Protected finalDebugHash.q = 0
  Protected minCold.q = 0
  Protected medianCold.q = 0
  Protected p95Cold.q = 0
  Protected meanCold.q = 0
  Protected minWarm.q = 0
  Protected medianWarm.q = 0
  Protected p95Warm.q = 0
  Protected meanWarm.q = 0
  Protected minDebug.q = 0
  Protected medianDebug.q = 0
  Protected p95Debug.q = 0
  Protected meanDebug.q = 0
  Protected fixtureTexHash.q = 0
  Protected finalAllocations.l = 0
  Protected finalComposed.l = 0
  Protected tempExpected.q = 0
  Protected entryExpected.q = 0
  Protected planeExpected.q = 0
  Protected peakExpected.q = 0
  Protected clockOk.i = #False
  Protected sceneOk.i = #False

  BeginCase("BEN01", "Windows cold end-to-end and warm textured/debug frame timing")
  PrintN("  wall-only 320x200 synthetic TI02 preview; not a complete game frame")
  PrintN("  clock: QueryPerformanceFrequency/Counter monotonic batch-free (Windows)")
  Check(Bool(BenchInitializeClock(@gClockFrequency, @gClockResolutionUS)),
        "monotonic clock initialized with nonzero frequency")
  PrintN("  clock frequency " + Str(gClockFrequency) + " ticks/s, resolution " +
         Str(gClockResolutionUS) + " us")
  clockOk = #True
  Check(Bool(gClockResolutionUS <= 1000),
        "high-resolution clock is adequate for individual wall frames")
  Check(Bool(WallTexPrepareFixtureDirectory()), "synthetic benchmark fixture directory ready")
  sceneOk = BuildBenchmarkScene()
  Check(Bool(sceneOk), "synthetic TI02 benchmark scene WAD built")
  If sceneOk = #False
    WallTexCleanupFixtureDirectory()
    ProcedureReturn
  EndIf
  fixtureTexHash = FixtureHashAt(?TEXGOLD_TI02_Hash)

  ; Cold end-to-end: each run opens/redecodes the same synthetic WAD, derives
  ; map/camera/visibility, then renders the textured frame; timed from WADOpen
  ; through frame commit/hash publication. Warmups are not recorded.
  coldFailed = 0
  prepareFailed = 0
  hashMismatch = 0
  allocMismatch = 0
  measuredIndex = 0
  For cycle = 0 To #BEN_ColdWarmups + #BEN_ColdMeasured - 1
    Check(Bool(FrameBufferCreate(@texturedTarget, #BEN_ViewWidth, #BEN_ViewHeight)),
          "cold cycle " + Str(cycle) + " target created")
    TexturedWallRenderResultReset(@texturedResult)
    startTicks = BenchTicksNow()
    If PrepareBenchSession(@pnames, @textures, @flats, @colormap, @level, @view,
                           @projection, @visibility) = #False
      prepareFailed + 1
    EndIf
    If TexturedWallRenderFrame(@level, @view, @projection, @flats,
                               @textures, @colormap, @visibility, @texturedTarget,
                               @texturedResult, 1) = #False
      coldFailed + 1
    Else
      If texturedResult\Hash <> fixtureTexHash
        hashMismatch + 1
      EndIf
      If texturedResult\Allocations <> #TEXGOLD_TI02_Allocations Or
         texturedResult\CacheAllocations <> #TEXGOLD_TI02_CacheAllocations
        allocMismatch + 1
      EndIf
    EndIf
    stopTicks = BenchTicksNow()
    If cycle >= #BEN_ColdWarmups
      elapsed = BenchElapsedMicroseconds(startTicks, stopTicks, gClockFrequency)
      coldTimes(measuredIndex) = elapsed
      measuredIndex = measuredIndex + 1
    EndIf
    TexturedWallRenderResultReset(@texturedResult)
    FrameBufferReset(@texturedTarget)
    CleanupBenchSession(@pnames, @textures, @flats, @colormap, @level, @view,
                        @projection, @visibility)
  Next
  Check(Bool(prepareFailed = 0), "every cold end-to-end session prepare succeeded")
  Check(Bool(coldFailed = 0), "every cold end-to-end textured frame succeeded")
  Check(Bool(hashMismatch = 0), "every cold frame hash equals locked TI02 fixture")
  Check(Bool(allocMismatch = 0), "every cold frame allocation/cache counts equal fixture budget")
  Check(Bool(measuredIndex = #BEN_ColdMeasured), "recorded cold frame count exactly 11")
  Check(Bool(TimingStats(@coldTimes(0), #BEN_ColdMeasured, @minCold, @medianCold,
                         @p95Cold, @meanCold)),
        "cold timing minimum/median/p95 ranks computed from actual samples")

  ; Warm textured: one fully prepared session, no WAD reopen/redecode; warmups
  ; then 100 frame-only renders including per-frame cache composition and light
  ; table/plan/clip/frame allocations that all occur before column loops.
  Check(Bool(PrepareBenchSession(@pnames, @textures, @flats, @colormap, @level,
                                @view, @projection, @visibility)),
        "warm prepared session/renderer resources initialized once")
  Check(Bool(FrameBufferCreate(@texturedTarget, #BEN_ViewWidth, #BEN_ViewHeight)),
        "warm textured target created once")
  TexturedWallRenderResultReset(@texturedResult)
  For cycle = 0 To #BEN_WarmWarmups - 1
    Check(Bool(TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                       @textures, @colormap, @visibility,
                                       @texturedTarget, @texturedResult, 1)),
          "textured warmup frame " + Str(cycle) + " succeeds")
  Next
  warmFailed = 0
  hashMismatch = 0
  allocMismatch = 0
  For cycle = 0 To #BEN_WarmMeasured - 1
    TexturedWallRenderResultReset(@texturedResult)
    startTicks = BenchTicksNow()
    If TexturedWallRenderFrame(@level, @view, @projection, @flats,
                               @textures, @colormap, @visibility, @texturedTarget,
                               @texturedResult, 1) = #False
      warmFailed + 1
    Else
      If texturedResult\Hash <> fixtureTexHash
        hashMismatch + 1
      EndIf
      If texturedResult\Allocations <> #TEXGOLD_TI02_Allocations Or
         texturedResult\CacheAllocations <> #TEXGOLD_TI02_CacheAllocations Or
         texturedResult\ComposedTextures <> #TEXGOLD_TI02_Composed
        allocMismatch + 1
      EndIf
    EndIf
    stopTicks = BenchTicksNow()
    elapsed = BenchElapsedMicroseconds(startTicks, stopTicks, gClockFrequency)
    warmTimes(cycle) = elapsed
  Next
  finalTexHash = TestFrameHash(@texturedTarget)
  Check(Bool(warmFailed = 0), "all 100 measured warm textured frames succeeded")
  Check(Bool(hashMismatch = 0), "all measured warm textured result hashes equal fixture")
  Check(Bool(allocMismatch = 0), "all measured warm allocation/composition counters fixed")
  Check(Bool(finalTexHash = fixtureTexHash And texturedResult\Hash = finalTexHash),
        "final warm independent full-plane FNV equals production/fixture hash")
  Check(Bool(texturedResult\CacheAllocations = 1 + 1 + 2 * texturedResult\ComposedTextures And
             texturedResult\Allocations = texturedResult\CacheAllocations + 5),
        "warm outer allocations remain pre-column formula: cache + five resources")
  tempExpected = 5 * SizeOf(Long)
  entryExpected = Int(texturedResult\ComposedTextures) * SizeOf(WallTextureEntry)
  planeExpected = 38400
  peakExpected = texturedResult\CacheTempBytes + entryExpected + planeExpected
  Check(Bool(texturedResult\CacheTempBytes = tempExpected And
             texturedResult\CachePlaneBytes = planeExpected And
             texturedResult\CachePeakBytes = peakExpected),
        "warm cache temp/entry/plane/peak bytes equal measured pre-loop budget")
  Check(Bool(texturedResult\ProcessedColumns = #TEXGOLD_TI02_ProcessedColumns And
             texturedResult\TextureSamples = #TEXGOLD_TI02_TextureSamples And
             texturedResult\DrawnPixels = #TEXGOLD_TI02_DrawnPixels),
        "warm 353 columns/38173 texels render inside zero-per-column-compose path")
  Check(Bool(TimingStats(@warmTimes(0), #BEN_WarmMeasured, @minWarm, @medianWarm,
                         @p95Warm, @meanWarm)),
        "warm textured timing minimum/median/p95 ranks computed from 100 samples")
  finalAllocations = texturedResult\Allocations
  finalComposed = texturedResult\ComposedTextures
  TexturedWallRenderResultReset(@texturedResult)

  ; Warm legacy debug-colour frame: no texture compose/lighting, same session.
  Check(Bool(FrameBufferCreate(@debugTarget, #BEN_ViewWidth, #BEN_ViewHeight)),
        "warm debug target created once")
  WallRenderResultReset(@debugResult)
  For cycle = 0 To #BEN_DebugWarmups - 1
    Check(Bool(WallRenderFrame(@level, @view, @projection, @flats, @textures,
                               @visibility, @debugTarget, @debugResult, 1)),
          "debug warmup frame " + Str(cycle) + " succeeds")
  Next
  debugFailed = 0
  For cycle = 0 To #BEN_DebugMeasured - 1
    WallRenderResultReset(@debugResult)
    startTicks = BenchTicksNow()
    If WallRenderFrame(@level, @view, @projection, @flats, @textures,
                       @visibility, @debugTarget, @debugResult, 1) = #False
      debugFailed + 1
    EndIf
    stopTicks = BenchTicksNow()
    elapsed = BenchElapsedMicroseconds(startTicks, stopTicks, gClockFrequency)
    debugTimes(cycle) = elapsed
  Next
  finalDebugHash = TestFrameHash(@debugTarget)
  Check(Bool(debugFailed = 0), "all 100 measured warm debug-color frames succeeded")
  Check(Bool(debugResult\Hash <> -1 And
             finalDebugHash = debugResult\Hash And debugResult\DrawnPixels > 0),
        "final warm debug frame independent FNV/counters equal production")
  Check(Bool(TimingStats(@debugTimes(0), #BEN_DebugMeasured, @minDebug,
                         @medianDebug, @p95Debug, @meanDebug)),
        "debug timing minimum/median/p95 ranks computed from 100 samples")

  PrintN("  cold end-to-end wall preview: cycles " + Str(#BEN_ColdWarmups) +
         " warmup + " + Str(#BEN_ColdMeasured) + " measured; per-frame us min/median/p95/mean " +
         Str(minCold) + "/" + Str(medianCold) + "/" + Str(p95Cold) + "/" + Str(meanCold))
  PrintN("  warm textured frame-only: cycles " + Str(#BEN_WarmWarmups) +
         " warmup + " + Str(#BEN_WarmMeasured) + " measured; per-frame us min/median/p95/mean " +
         Str(minWarm) + "/" + Str(medianWarm) + "/" + Str(p95Warm) + "/" + Str(meanWarm))
  PrintN("  warm debug-colour frame-only: cycles " + Str(#BEN_DebugWarmups) +
         " warmup + " + Str(#BEN_DebugMeasured) + " measured; per-frame us min/median/p95/mean " +
         Str(minDebug) + "/" + Str(medianDebug) + "/" + Str(p95Debug) + "/" + Str(meanDebug))
  PrintN("  allocations: warm total " + Str(finalAllocations) +
         " observed fixture budget 13; compose " + Str(finalComposed) +
         " unique (not per column/pixel)")
  PrintN("  No WADReadLump/AllocateMemory/TextureCompose appears in the per-column " +
         "TexturedWallDraw source (MR35 audit); frame-only cost excludes display/window I/O.")
  PrintN("  No FPS claim: this excludes floors/ceilings/sprites/gameplay and uses a synthetic wall preview.")

  WallRenderResultReset(@debugResult)
  FrameBufferReset(@debugTarget)
  TexturedWallRenderResultReset(@texturedResult)
  FrameBufferReset(@texturedTarget)
  CleanupBenchSession(@pnames, @textures, @flats, @colormap, @level, @view,
                      @projection, @visibility)
  WallTexCleanupFixtureDirectory()
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

Procedure.i BenchmarkOutput()
  PrintN("")
  PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) +
         ", failures: " + Str(gFailureCount))
  If gFailureCount = 0
    PrintN("RESULT: PASS")
    ProcedureReturn 0
  EndIf
  PrintN("RESULT: FAIL")
  ProcedureReturn gFailureCount
EndProcedure

OpenConsole()
TestBEN01()
End BenchmarkOutput()
