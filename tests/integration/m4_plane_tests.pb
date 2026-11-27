; -----------------------------------------------------------------------------
; DoomPB - M4-01 synthetic integration tests PI01-PI03
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Standalone no-IWAD suite. PI01/PI02 build wholly original synthetic PWADs from
; the shared support module (T01/P02 exact oracle geometry/resources), decode all
; resources through production APIs, render the transactional combined wall+flat
; frame into a fresh 320x200 target with an optional bounded span trace, and
; compare every 64,000 frame byte, sample column rows, plane span record, light/
; row arithmetic counter and FNV hash to the independent generated M4-01 fixture.
; PI03 exercises resource lifecycle A->B->A, repeated draw/reset determinism,
; late truncated used-floor FlatLoad rollback with byte-for-byte target state,
; short-COLORMAP entry rejection, trace-cap late limit rollback, zero emitted
; WallSpans with valid subsector/plane context, and frozen legacy M3-04/M3-06
; span/textured hashes. Synthetic WADs are written only under build output in the
; harness fixture directory; no owner IWAD bytes, extracted graphics or display.
;
; Exit code: 0 when all assertions passed, else the failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../integration/wall_texture_support.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"
XIncludeFile "../../src/Renderer/RenderMain.pbi"
XIncludeFile "../../src/Renderer/TexturedRenderMain.pbi"
XIncludeFile "../../src/Renderer/PlaneRenderMain.pbi"
XIncludeFile "../../src/Graphics/Video.pbi"
XIncludeFile "../fixtures/m4_plane_golden.pbi"
XIncludeFile "../fixtures/m3_wall_texture_golden.pbi"

Global gPICaseCount.i = 0
Global gPIAssertionCount.i = 0
Global gPIFailureCount.i = 0

Global *gPI01Frame.Byte = ?PLGOLD_PI01_Frame
Global *gPI01Samples.Byte = ?PLGOLD_PI01_Samples
Global *gPI01PlaneSpans.Long = ?PLGOLD_PI01_PlaneSpans
Global *gPI01HashValue.Quad = ?PLGOLD_PI01_HashValue
Global *gPI02Frame.Byte = ?PLGOLD_PI02_Frame
Global *gPI02Samples.Byte = ?PLGOLD_PI02_Samples
Global *gPI02PlaneSpans.Long = ?PLGOLD_PI02_PlaneSpans
Global *gPI02HashValue.Quad = ?PLGOLD_PI02_HashValue
Global *gLegacyPlanSpans.Long = ?TEXGOLD_TI01_Spans
Global *gLegacySpanHash.Quad = ?TEXGOLD_TI01_SpanHash
Global *gLegacyFrameHash.Quad = ?TEXGOLD_TI01_Hash

Procedure BeginCase(Id.s, Title.s)
  gPICaseCount + 1
  PrintN("CASE " + Id + ": " + Title)
EndProcedure

Procedure Check(Ok.i, Description.s)
  gPIAssertionCount + 1
  If Ok = 0
    gPIFailureCount + 1
    PrintN("  FAIL: " + Description)
  Else
    PrintN("  ok: " + Description)
  EndIf
EndProcedure

; ---------------------------------------------------------------------------
; Numeric snapshot of the published combined-frame result
; ---------------------------------------------------------------------------

Structure PlaneStatsSnapshot
  SpanCount.l
  SegmentCount.l
  TexturePlanCount.l
  Visplanes.l
  RegularVisplanes.l
  SkyVisplanes.l
  EmptyVisplanes.l
  PopulatedVisplanes.l
  SkyDeferredBands.l
  SkyDeferredPixels.l
  PlaneSpans.l
  PlanePixels.l
  PlaneOpenedRows.l
  PlaneClosedRows.l
  PlaneRowCacheHits.l
  PlaneRowCacheMisses.l
  PlaneColormapTexels.l
  FloorVisplanes.l
  CeilingVisplanes.l
  FloorPixels.l
  CeilingPixels.l
  FindCalls.l
  FindReuse.l
  FindCreate.l
  CheckCalls.l
  CheckMerges.l
  CheckSplits.l
  MarkCeilingCalls.l
  MarkFloorCalls.l
  MarkCeilingBands.l
  MarkFloorBands.l
  TimelineVisits.l
  TimelineEvents.l
  ZeroSpanVisits.l
  SkyFindVisits.l
  RegularFindVisits.l
  WallProcessedColumns.l
  WallTextureColumnsComputed.l
  WallMiddlePixels.l
  WallUpperPixels.l
  WallLowerPixels.l
  WallDrawnPixels.l
  WallDrawRanges.l
  WallEmptyColumns.l
  WallClippedColumns.l
  WallOutOfFrameColumns.l
  WallTextureSamples.l
  WallCoveredPixels.l
  NonZeroBytes.l
  ZeroBytes.l
  ComposedTextures.l
  RequestedReferences.l
  ReusedReferences.l
  MaskedMidSpans.l
  ShortTextures.l
  TextureCacheAllocations.l
  FlatCacheCount.l
  FlatCacheCapacity.l
  FlatCacheRequestedReferences.l
  FlatCacheUniqueFlats.l
  FlatCacheLoadedFlats.l
  FlatCacheAllocations.l
  PlaneFrameAllocations.l
  TimelineAllocations.l
  ZLightAllocations.l
  WallTableAllocations.l
  VisibilityAllocations.l
  ClipAllocations.l
  FrameAllocations.l
  CoverageAllocations.l
  MetadataAllocations.l
  Allocations.l
  EmittedFragments.l
  Hash.q
EndStructure

; Reads the public getter once, copying every numeric counter atomically on a
; valid result. Uses the exact published parameter list; no production hash or
; fixture value is guessed here.
Procedure.i PISnapshotStats(*Result.PlaneRenderResult, *Snap.PlaneStatsSnapshot)
  Protected span.l = 0
  Protected seg.l = 0
  Protected texp.l = 0
  Protected visplanes.l = 0
  Protected reg.l = 0
  Protected sky.l = 0
  Protected empty.l = 0
  Protected populated.l = 0
  Protected skyb.l = 0
  Protected skyp.l = 0
  Protected psp.l = 0
  Protected ppx.l = 0
  Protected oor.l = 0
  Protected cor.l = 0
  Protected hit.l = 0
  Protected miss.l = 0
  Protected tex.l = 0
  Protected fv.l = 0
  Protected cv.l = 0
  Protected fp.l = 0
  Protected cp.l = 0
  Protected fc.l = 0
  Protected fr.l = 0
  Protected fcr.l = 0
  Protected cc.l = 0
  Protected cm.l = 0
  Protected cs.l = 0
  Protected mc.l = 0
  Protected mf.l = 0
  Protected mcb.l = 0
  Protected mfb.l = 0
  Protected tv.l = 0
  Protected te.l = 0
  Protected zv.l = 0
  Protected sf.l = 0
  Protected rf.l = 0
  Protected wproc.l = 0
  Protected wtex.l = 0
  Protected wmid.l = 0
  Protected wup.l = 0
  Protected wlo.l = 0
  Protected wd.l = 0
  Protected woof.l = 0
  Protected wsamp.l = 0
  Protected cov.l = 0
  Protected nz.l = 0
  Protected z.l = 0
  Protected fcnt.l = 0
  Protected funiq.l = 0
  Protected fload.l = 0
  Protected falloc.l = 0
  Protected hash.q = 0
  Protected ok.i = #False

  If *Snap = 0 Or PlaneRenderResultIsValid(*Result) = #False
    ProcedureReturn #False
  EndIf
  FillMemory(*Snap, Int(SizeOf(PlaneStatsSnapshot)), 0)
  ok = PlaneRenderGetStats(*Result, @span.l, @seg.l, 0,
                           @texp.l, 0,
                           @visplanes, @reg, @sky, @empty, @populated,
                           @skyb, @skyp, @psp, @ppx, @oor, @cor, @hit, @miss,
                           @tex, @fv, @cv, @fp, @cp, @fc, @fr, @fcr,
                           @cc, @cm, @cs, @mc, @mf, @mcb, @mfb,
                           @tv, @te, @zv, @sf, @rf, 0, 0, 0, 0,
                           @wproc, @wtex, @wmid, @wup, @wlo, @wd,
                           0, 0, 0, 0, 0, 0, @woof, @wsamp, 0, 0,
                           @cov, @nz, @z, 0, 0, 0, 0, 0, 0,
                           @fcnt, 0, 0, @funiq, @fload, @falloc,
                           0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, @hash)
  If ok = #False
    ProcedureReturn #False
  EndIf
  *Snap\SpanCount = span
  *Snap\SegmentCount = seg
  *Snap\TexturePlanCount = texp
  *Snap\Visplanes = visplanes
  *Snap\RegularVisplanes = reg
  *Snap\SkyVisplanes = sky
  *Snap\EmptyVisplanes = empty
  *Snap\PopulatedVisplanes = populated
  *Snap\SkyDeferredBands = skyb
  *Snap\SkyDeferredPixels = skyp
  *Snap\PlaneSpans = psp
  *Snap\PlanePixels = ppx
  *Snap\PlaneOpenedRows = oor
  *Snap\PlaneClosedRows = cor
  *Snap\PlaneRowCacheHits = hit
  *Snap\PlaneRowCacheMisses = miss
  *Snap\PlaneColormapTexels = tex
  *Snap\FloorVisplanes = fv
  *Snap\CeilingVisplanes = cv
  *Snap\FloorPixels = fp
  *Snap\CeilingPixels = cp
  *Snap\FindCalls = fc
  *Snap\FindReuse = fr
  *Snap\FindCreate = fcr
  *Snap\CheckCalls = cc
  *Snap\CheckMerges = cm
  *Snap\CheckSplits = cs
  *Snap\MarkCeilingCalls = mc
  *Snap\MarkFloorCalls = mf
  *Snap\MarkCeilingBands = mcb
  *Snap\MarkFloorBands = mfb
  *Snap\TimelineVisits = tv
  *Snap\TimelineEvents = te
  *Snap\ZeroSpanVisits = zv
  *Snap\SkyFindVisits = sf
  *Snap\RegularFindVisits = rf
  *Snap\WallProcessedColumns = wproc
  *Snap\WallTextureColumnsComputed = wtex
  *Snap\WallMiddlePixels = wmid
  *Snap\WallUpperPixels = wup
  *Snap\WallLowerPixels = wlo
  *Snap\WallDrawnPixels = wd
  *Snap\WallEmptyColumns = 0
  *Snap\WallClippedColumns = 0
  *Snap\WallOutOfFrameColumns = woof
  *Snap\WallTextureSamples = wsamp
  *Snap\WallCoveredPixels = cov
  *Snap\NonZeroBytes = nz
  *Snap\ZeroBytes = z
  *Snap\FlatCacheCount = fcnt
  *Snap\FlatCacheUniqueFlats = funiq
  *Snap\FlatCacheLoadedFlats = fload
  *Snap\FlatCacheAllocations = falloc
  *Snap\Hash = hash
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent integer/FNV helpers
; ---------------------------------------------------------------------------

Procedure.q PIFnvByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #TEXGOLD_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q PIFnvLong(Hash.q, Value.l)
  Hash = PIFnvByte(Hash, Value)
  Hash = PIFnvByte(Hash, Value >> 8)
  Hash = PIFnvByte(Hash, Value >> 16)
  Hash = PIFnvByte(Hash, Value >> 24)
  ProcedureReturn Hash
EndProcedure

Procedure.q PIFnvFrame(*Frame.FrameBuffer)
  Protected index.i
  Protected hash.q = #TEXGOLD_FNV_Offset

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #PLANERENDER_FrameWidth Or
     *Frame\Height <> #PLANERENDER_FrameHeight Or
     *Frame\PixelCount <> #PLANERENDER_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For index = 0 To #PLANERENDER_FramePixelCount - 1
    hash = PIFnvByte(hash, PeekA(*Frame\Pixels + index))
  Next
  ProcedureReturn hash
EndProcedure

; Independent M3-04 aggregate span fingerprint exactly over the nine published
; numeric fields; used only to compare the frozen legacy M3-06 oracle hash.
Procedure.q PISpanHash(*Result.WallVisibilityResult)
  Protected hash.q = #TEXGOLD_FNV_Offset
  Protected index.i
  Protected sub.l = 0
  Protected seg.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0

  If WallVisibilityIsValid(*Result) = #False
    ProcedureReturn -1
  EndIf
  For index = 0 To *Result\Count - 1
    If WallVisibilityGetSpan(*Result, index, @sub, @seg, @line, @side,
                             @front, @back, @first, @last, @kind) = #False
      ProcedureReturn -1
    EndIf
    hash = PIFnvLong(hash, sub)
    hash = PIFnvLong(hash, seg)
    hash = PIFnvLong(hash, line)
    hash = PIFnvLong(hash, side)
    hash = PIFnvLong(hash, front)
    hash = PIFnvLong(hash, back)
    hash = PIFnvLong(hash, first)
    hash = PIFnvLong(hash, last)
    hash = PIFnvLong(hash, kind)
  Next
  ProcedureReturn hash
EndProcedure

; ---------------------------------------------------------------------------
; Whole-frame and sample comparisons against the independent fixture
; ---------------------------------------------------------------------------

Procedure.l PIFrameMismatchCount(*Frame.FrameBuffer, *Fixture.Byte)
  Protected index.q
  Protected mismatch.l = 0

  If *Frame = 0 Or *Frame\Pixels = 0 Or *Fixture = 0
    ProcedureReturn -1
  EndIf
  For index = 0 To Int(#PLANERENDER_FramePixelCount) - 1
    If PeekA(*Frame\Pixels + index) <> PeekA(*Fixture + index)
      mismatch + 1
    EndIf
  Next
  ProcedureReturn mismatch
EndProcedure

Procedure.i PISampleColumn(SceneId.s, SampleIndex.l, *X.Long)
  If *X = 0
    ProcedureReturn #False
  EndIf
  If SceneId = "PI01"
    If SampleIndex < 0 Or SampleIndex > #PLGOLD_PI01_SampleCount - 1
      ProcedureReturn #False
    EndIf
    Select SampleIndex
      Case 0 : PokeL(*X, 0)
      Case 1 : PokeL(*X, 100)
      Case 2 : PokeL(*X, 159)
      Case 3 : PokeL(*X, 160)
      Case 4 : PokeL(*X, 161)
      Case 5 : PokeL(*X, 319)
    EndSelect
    ProcedureReturn #True
  EndIf
  If SceneId = "PI02"
    If SampleIndex < 0 Or SampleIndex > #PLGOLD_PI02_SampleCount - 1
      ProcedureReturn #False
    EndIf
    Select SampleIndex
      Case 0 : PokeL(*X, 0)
      Case 1 : PokeL(*X, 58)
      Case 2 : PokeL(*X, 120)
      Case 3 : PokeL(*X, 160)
      Case 4 : PokeL(*X, 200)
      Case 5 : PokeL(*X, 240)
      Case 6 : PokeL(*X, 300)
      Case 7 : PokeL(*X, 319)
    EndSelect
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure.l PISceneSampleMismatch(*Frame.FrameBuffer, *Fixture.Byte, SceneId.s,
                                 SampleCount.l)
  Protected sample.l
  Protected row.l
  Protected columnX.l = 0
  Protected fixtureOffs.q
  Protected targetOffs.q
  Protected mismatch.l = 0

  If *Frame = 0 Or *Frame\Pixels = 0 Or *Fixture = 0 Or SampleCount < 0
    ProcedureReturn -1
  EndIf
  For sample = 0 To Int(SampleCount) - 1
    If PISampleColumn(SceneId, sample, @columnX) = #False
      mismatch + 1
    Else
      For row = 0 To Int(#PLANERENDER_FrameHeight) - 1
        fixtureOffs = Int(sample) * Int(#PLANERENDER_FrameHeight) + Int(row)
        targetOffs = Int(row) * Int(#PLANERENDER_FrameWidth) + Int(columnX)
        If PeekA(*Fixture + fixtureOffs) <> PeekA(*Frame\Pixels + targetOffs)
          mismatch + 1
        EndIf
      Next
    EndIf
  Next
  ProcedureReturn mismatch
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic PWAD builders (original bytes only)
; ---------------------------------------------------------------------------

Procedure.i PIBuildSceneWad(FileName.s, SceneMode.i)
  Protected marker.s = ""
  Protected ok.i = #False

  If WallTexWadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9)
    If SceneMode = 1
      ok = WallTexBuildT01MapLumps()
      marker = "E1M1"
    ElseIf SceneMode = 2
      ok = WallTexBuildP02MapLumps()
      marker = "E2M1"
    EndIf
    If ok
      If WallTexAddMapLumpsToWad(marker)
        ok = WallTexWadFinish()
      EndIf
    EndIf
  EndIf
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  WallTexFreeMap()
  ProcedureReturn ok
EndProcedure

; Flat-layout resource-only WAD: palette, F_START/FLATZERO/FLATMAX/FLOOR1/
; CEIL1/F_SKY1/F_END, no wall textures, standard 32-table COLORMAP. No map.
Procedure.i PIBuildFlatVariantWad(FileName.s, FloorPixel.l)
  Protected ok.i = #False

  If WallTexWadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexWadAdd("F_START", 0, 0)
  WallTexAddFlat("FLATZERO", 0)
  WallTexAddFlat("FLATMAX", 255)
  WallTexAddFlat("FLOOR1", FloorPixel)
  WallTexAddFlat("CEIL1", 47)
  WallTexAddF_SKY1()
  WallTexWadAdd("F_END", 0, 0)
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9, #False, #True)
    ok = WallTexWadFinish()
  EndIf
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  ProcedureReturn ok
EndProcedure

; One-sector T01 scene with a deliberately 4095-byte used FLOOR1 flat. The WAD
; opens and validates resources; FlatLoad fails only after the wall pass.
Procedure.i PIBuildLateBrokenSceneWad(FileName.s)
  Protected *bad.Byte = 0
  Protected ok.i = #False

  *bad = WallTexNewZero(4095)
  If *bad = 0
    ProcedureReturn #False
  EndIf
  If WallTexWadBegin(FileName) = #False
    FreeMemory(*bad)
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexWadAdd("F_START", 0, 0)
  WallTexWadAdd("FLOOR1", *bad, 4095)
  WallTexAddFlat("CEIL1", 47)
  WallTexAddF_SKY1()
  WallTexWadAdd("F_END", 0, 0)
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9)
    If WallTexBuildT01MapLumps()
      If WallTexAddMapLumpsToWad("E1M1")
        ok = WallTexWadFinish()
      EndIf
    EndIf
  EndIf
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  WallTexFreeMap()
  FreeMemory(*bad)
  ProcedureReturn ok
EndProcedure

; One-sector T01 scene with only sixteen complete COLORMAP tables. The decoder
; accepts them; the classic >=32-table lighting gate rejects at frame entry.
Procedure.i PIBuildShortColormapSceneWad(FileName.s)
  Protected tableCount.l = 16
  Protected *data.Byte = 0
  Protected mapIndex.l
  Protected texel.l
  Protected ok.i = #False

  *data = WallTexNewZero(Int(tableCount) * 256)
  If *data = 0
    ProcedureReturn #False
  EndIf
  For mapIndex = 0 To tableCount - 1
    For texel = 0 To 255
      PokeA(*data + Int(mapIndex) * 256 + Int(texel),
            (texel + 17 + mapIndex * 9) & 255)
    Next
  Next
  If WallTexWadBegin(FileName) = #False
    FreeMemory(*data)
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9, #True, #False)
    WallTexWadAdd("COLORMAP", *data, Int(tableCount) * 256)
    If WallTexBuildT01MapLumps()
      If WallTexAddMapLumpsToWad("E1M1")
        ok = WallTexWadFinish()
      EndIf
    EndIf
  EndIf
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  WallTexFreeMap()
  FreeMemory(*data)
  ProcedureReturn ok
EndProcedure

; ---------------------------------------------------------------------------
; Production session open/prepare/close
; ---------------------------------------------------------------------------

; Opens the built synthetic PWAD, decodes PNAMES/TEXTURE1/flats/COLORMAP, loads
; and validates the marker map, derives the exact player-one view and classic
; projection. Leaves the WAD open and all resources caller-owned for a frame.
Procedure.i PISessionPrepare(FileName.s, Marker.s,
                             *P.PNamesTable, *T.TextureCatalog,
                             *F.FlatCatalog, *C.ColormapSet,
                             *L.MapLevel, *V.WallView, *Proj.Projection)
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0

  PNamesReset(*P)
  TextureCatalogReset(*T)
  FlatCatalogReset(*F)
  ColormapReset(*C)
  MapLevelReset(*L)
  WallViewReset(*V)
  ProjectionReset(*Proj)
  If WADOpen(WallTexFixturePath(FileName)) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallCatalog(*P, *T) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallFlats(*F) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallColormap(*C) = #False
    ProcedureReturn #False
  EndIf
  If MapLevelLoad(Marker, *L) = #False
    ProcedureReturn #False
  EndIf
  If MapLevelValidateResources(*L, *F, *T) = #False
    ProcedureReturn #False
  EndIf
  If WallRenderPlayerStartView(*L, *V, @thingIndex, @subsectorIndex,
                               @sectorIndex) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn ProjectionInitClassic(*Proj)
EndProcedure

Procedure PISessionClose(*P.PNamesTable, *T.TextureCatalog,
                         *F.FlatCatalog, *C.ColormapSet,
                         *L.MapLevel, *V.WallView, *Proj.Projection)
  If WADIsOpen()
    WADClose()
  EndIf
  PNamesReset(*P)
  TextureCatalogReset(*T)
  FlatCatalogReset(*F)
  ColormapReset(*C)
  MapLevelReset(*L)
  WallViewReset(*V)
  ProjectionReset(*Proj)
EndProcedure

; Resource-only decode of flats + COLORMAP while the WAD is open; texture/PNAMES
; objects are reset but not decoded because the variant WADs omit wall textures.
Procedure.i PIResourceOpen(FileName.s, *F.FlatCatalog, *C.ColormapSet,
                           *T.TextureCatalog, *P.PNamesTable)
  FlatCatalogReset(*F)
  ColormapReset(*C)
  PNamesReset(*P)
  TextureCatalogReset(*T)
  If WADOpen(WallTexFixturePath(FileName)) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallFlats(*F) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallTexDecodeWallColormap(*C)
EndProcedure

; ---------------------------------------------------------------------------
; PI01: one-sided closed room, real floor/ceiling flats, no sky
; ---------------------------------------------------------------------------

Procedure TestPI01()
  Protected p.PNamesTable
  Protected t.TextureCatalog
  Protected f.FlatCatalog
  Protected c.ColormapSet
  Protected l.MapLevel
  Protected v.WallView
  Protected proj.Projection
  Protected target.FrameBuffer
  Protected result.PlaneRenderResult
  Protected trace.PlaneSpanTrace
  Protected snap.PlaneStatsSnapshot
  Protected renderOk.i = #False
  Protected snapshotOk.i = #False
  Protected frameMismatch.l = 0
  Protected sampleMismatch.l = 0
  Protected traceMismatch.l = 0
  Protected manualHash.q = 0
  Protected spanIndex.l
  Protected planeIndex.l = 0
  Protected row.l = 0
  Protected firstX.l = 0
  Protected lastX.l = 0
  Protected planeHeight.l = 0
  Protected distance.l = 0
  Protected xStep.l = 0
  Protected yStep.l = 0
  Protected xFrac.l = 0
  Protected yFrac.l = 0
  Protected lightNum.l = 0
  Protected mapIndex.l = 0
  Protected pixels.l = 0
  Protected cacheHit.l = 0
  Protected expected.l = 0
  Protected actual.l = 0
  Protected fieldIndex.l
  Protected traceSpanCount.l = 0

  BeginCase("PI01", "T01 closed-room synthetic combined frame vs full independent oracle")

  Check(Bool(PIBuildSceneWad("m4pi01.wad", 1)), "PI01 synthetic T01 scene PWAD built")
  If PISessionPrepare("m4pi01.wad", "E1M1", @p, @t, @f, @c, @l, @v, @proj)
    Check(#True, "PI01 production decode/map/player/projection prepared")
  Else
    Check(#False, "PI01 session prepared")
    Goto PI01Done
  EndIf
  If FrameBufferCreate(@target, 320, 200) = #False Or
     PlaneRenderResultReset(@result) = #False Or
     PlaneSpanTraceBegin(@trace, 1024) = #False
    Check(#False, "PI01 target/result/trace setup")
    Goto PI01Done
  EndIf
  renderOk = PlaneRenderFrame(@l, @v, @proj, @f, @t, @c, @target, @result,
                              #True, @trace)
  Check(Bool(renderOk), "PI01 combined wall+plane transactional frame succeeds")
  If renderOk = #False
    PrintN("  PI01 render error: " + PlaneRenderLastError())
    Goto PI01Done
  EndIf
  Check(Bool(PlaneRenderResultIsValid(@result)), "PI01 result publishes valid ready state")
  snapshotOk = PISnapshotStats(@result, @snap)
  Check(Bool(snapshotOk), "PI01 public stats snapshot read")
  If snapshotOk = #False
    Goto PI01Done
  EndIf

  Check(Bool(snap\SpanCount = #PLGOLD_PI01_SpanCount And
              snap\Visplanes = #PLGOLD_PI01_Visplanes And
              snap\RegularVisplanes = #PLGOLD_PI01_RegularVisplanes And
              snap\SkyVisplanes = #PLGOLD_PI01_SkyVisplanes And
              snap\EmptyVisplanes = #PLGOLD_PI01_EmptyVisplanes And
              snap\PopulatedVisplanes = #PLGOLD_PI01_PopulatedVisplanes),
        "PI01 wall span/visplane regular-sky-empty-populated counts exact oracle")
  Check(Bool(snap\FindCalls = #PLGOLD_PI01_FindCalls And
              snap\FindReuse = #PLGOLD_PI01_FindReuse And
              snap\FindCreate = #PLGOLD_PI01_FindCreate And
              snap\CheckCalls = #PLGOLD_PI01_CheckCalls And
              snap\CheckMerges = #PLGOLD_PI01_CheckMerges And
              snap\CheckSplits = #PLGOLD_PI01_CheckSplits),
        "PI01 subsector Find/span CheckPlane chronology exact oracle")
  Check(Bool(snap\MarkCeilingCalls = #PLGOLD_PI01_MarkCeilingColumns And
              snap\MarkCeilingBands = #PLGOLD_PI01_MarkCeilingBands And
              snap\MarkFloorCalls = #PLGOLD_PI01_MarkFloorColumns And
              snap\MarkFloorBands = #PLGOLD_PI01_MarkFloorBands),
        "PI01 mark-before-clip column/band counters exact oracle")
  Check(Bool(snap\PlaneSpans = #PLGOLD_PI01_PlaneSpans And
              snap\PlanePixels = #PLGOLD_PI01_PlanePixels And
              snap\PlaneOpenedRows = #PLGOLD_PI01_OpenedRows And
              snap\PlaneClosedRows = #PLGOLD_PI01_ClosedRows And
              snap\PlaneRowCacheHits = #PLGOLD_PI01_RowCacheHits And
              snap\PlaneRowCacheMisses = #PLGOLD_PI01_RowCacheMisses And
              snap\PlaneColormapTexels = #PLGOLD_PI01_ColormapTexels),
        "PI01 post-wall span rows/pixels/cache/COLORMAP texels exact oracle")
  Check(Bool(snap\FloorVisplanes = #PLGOLD_PI01_FloorVisplanes And
              snap\CeilingVisplanes = #PLGOLD_PI01_CeilingVisplanes And
              snap\FloorPixels = #PLGOLD_PI01_FloorPixels And
              snap\CeilingPixels = #PLGOLD_PI01_CeilingPixels),
        "PI01 floor/ceiling visplane/pixel split exact oracle")
  Check(Bool(snap\SkyVisplanes = #PLGOLD_PI01_SkyVisplanes And
              snap\SkyDeferredBands = #PLGOLD_PI01_SkyBands And
              snap\SkyDeferredPixels = #PLGOLD_PI01_SkyPixels),
        "PI01 no sky plane deferred in the closed room")
  Check(Bool(snap\WallDrawnPixels = #PLGOLD_PI01_WallDrawnPixels And
              snap\WallCoveredPixels = #PLGOLD_PI01_CoveredPixels),
        "PI01 wall writes and explicit coverage count exact; planes disjoint")
  Check(Bool(snap\FlatCacheCount = 1 And snap\FlatCacheUniqueFlats = 1 And
              snap\FlatCacheLoadedFlats = 1 And snap\FlatCacheAllocations >= 1 And
              snap\FlatCacheAllocations < 16),
        "PI01 cache loads only FLOOR1 once under bounded allocation")
  Check(Bool(snap\NonZeroBytes = #PLGOLD_PI01_NonZeroBytes And
              snap\ZeroBytes = #PLGOLD_PI01_ZeroBytes And
              snap\NonZeroBytes + snap\ZeroBytes = #PLANERENDER_FramePixelCount),
        "PI01 nonzero/zero byte audit equals independent oracle and 64,000 cells")

  frameMismatch = PIFrameMismatchCount(@target, *gPI01Frame)
  Check(Bool(frameMismatch = 0), "PI01 all 64,000 frame bytes exact independent oracle")
  sampleMismatch = PISceneSampleMismatch(@target, *gPI01Samples, "PI01",
                                         #PLGOLD_PI01_SampleCount)
  Check(Bool(sampleMismatch = 0), "PI01 six sample columns x 200 rows exact fixture")
  manualHash = PIFnvFrame(@target)
  Check(Bool(manualHash = PeekQ(*gPI01HashValue) And
              snap\Hash = PeekQ(*gPI01HashValue)), "PI01 result/manual FNV exact independent oracle")

  traceSpanCount = trace\SpanCount
  Check(Bool(traceSpanCount = #PLGOLD_PI01_PlaneSpans),
        "PI01 trace captures every 34 post-wall plane span")
  traceMismatch = 0
  For spanIndex = 0 To traceSpanCount - 1
    If PlaneSpanTraceGetSpan(@trace, spanIndex, @planeIndex, @row,
                             @firstX, @lastX, @planeHeight, @distance,
                             @xStep, @yStep, @xFrac, @yFrac,
                             @lightNum, @mapIndex, @pixels, @cacheHit) = #False
      traceMismatch + 1
    Else
      For fieldIndex = 0 To #PLGOLD_PlaneSpanFieldCount - 1
        expected = PeekL(*gPI01PlaneSpans +
                         Int(spanIndex) * Int(#PLGOLD_PlaneSpanFieldCount) * 4 +
                         Int(fieldIndex) * 4)
        Select fieldIndex
          Case 0 : actual = planeIndex
          Case 1 : actual = row
          Case 2 : actual = firstX
          Case 3 : actual = lastX
          Case 4 : actual = planeHeight
          Case 5 : actual = distance
          Case 6 : actual = xStep
          Case 7 : actual = yStep
          Case 8 : actual = xFrac
          Case 9 : actual = yFrac
          Case 10 : actual = lightNum
          Case 11 : actual = mapIndex
          Case 12 : actual = pixels
          Case 13 : actual = cacheHit
        EndSelect
        If actual <> expected
          traceMismatch + 1
        EndIf
      Next
    EndIf
  Next
  Check(Bool(traceMismatch = 0), "PI01 all 14 span fields chronology exact independent oracle")

  PI01Done:
  PlaneSpanTraceReset(@trace)
  PlaneRenderResultReset(@result)
  FrameBufferReset(@target)
  PISessionClose(@p, @t, @f, @c, @l, @v, @proj)
EndProcedure

; ---------------------------------------------------------------------------
; PI02: two sectors, portal tiers, deferred sky, repeated/split visplanes
; ---------------------------------------------------------------------------

Procedure TestPI02()
  Protected p.PNamesTable
  Protected t.TextureCatalog
  Protected f.FlatCatalog
  Protected c.ColormapSet
  Protected l.MapLevel
  Protected v.WallView
  Protected proj.Projection
  Protected target.FrameBuffer
  Protected result.PlaneRenderResult
  Protected trace.PlaneSpanTrace
  Protected snap.PlaneStatsSnapshot
  Protected renderOk.i = #False
  Protected snapshotOk.i = #False
  Protected frameMismatch.l = 0
  Protected sampleMismatch.l = 0
  Protected traceMismatch.l = 0
  Protected manualHash.q = 0
  Protected spanIndex.l
  Protected planeIndex.l = 0
  Protected row.l = 0
  Protected firstX.l = 0
  Protected lastX.l = 0
  Protected planeHeight.l = 0
  Protected distance.l = 0
  Protected xStep.l = 0
  Protected yStep.l = 0
  Protected xFrac.l = 0
  Protected yFrac.l = 0
  Protected lightNum.l = 0
  Protected mapIndex.l = 0
  Protected pixels.l = 0
  Protected cacheHit.l = 0
  Protected expected.l = 0
  Protected actual.l = 0
  Protected fieldIndex.l
  Protected traceSpanCount.l = 0

  BeginCase("PI02", "P02 portal + sky synthetic combined frame vs full independent oracle")

  Check(Bool(PIBuildSceneWad("m4pi02.wad", 2)), "PI02 synthetic P02 sky/portal scene PWAD built")
  If PISessionPrepare("m4pi02.wad", "E2M1", @p, @t, @f, @c, @l, @v, @proj)
    Check(#True, "PI02 production decode/map/player/projection prepared")
  Else
    Check(#False, "PI02 session prepared")
    Goto PI02Done
  EndIf
  If FrameBufferCreate(@target, 320, 200) = #False Or
     PlaneRenderResultReset(@result) = #False Or
     PlaneSpanTraceBegin(@trace, 1024) = #False
    Check(#False, "PI02 target/result/trace setup")
    Goto PI02Done
  EndIf
  renderOk = PlaneRenderFrame(@l, @v, @proj, @f, @t, @c, @target, @result,
                              #True, @trace)
  Check(Bool(renderOk), "PI02 combined wall+plane transactional frame succeeds")
  If renderOk = #False
    PrintN("  PI02 render error: " + PlaneRenderLastError())
    Goto PI02Done
  EndIf
  Check(Bool(PlaneRenderResultIsValid(@result)), "PI02 result publishes valid ready state")
  snapshotOk = PISnapshotStats(@result, @snap)
  Check(Bool(snapshotOk), "PI02 public stats snapshot read")
  If snapshotOk = #False
    Goto PI02Done
  EndIf

  Check(Bool(snap\SpanCount = #PLGOLD_PI02_SpanCount And
              snap\Visplanes = #PLGOLD_PI02_Visplanes And
              snap\RegularVisplanes = #PLGOLD_PI02_RegularVisplanes And
              snap\SkyVisplanes = #PLGOLD_PI02_SkyVisplanes And
              snap\EmptyVisplanes = #PLGOLD_PI02_EmptyVisplanes And
              snap\PopulatedVisplanes = #PLGOLD_PI02_PopulatedVisplanes),
        "PI02 wall span/visplane regular-sky-empty-populated counts exact oracle")
  Check(Bool(snap\FindCalls = #PLGOLD_PI02_FindCalls And
              snap\FindReuse = #PLGOLD_PI02_FindReuse And
              snap\FindCreate = #PLGOLD_PI02_FindCreate And
              snap\CheckCalls = #PLGOLD_PI02_CheckCalls And
              snap\CheckMerges = #PLGOLD_PI02_CheckMerges And
              snap\CheckSplits = #PLGOLD_PI02_CheckSplits),
        "PI02 subsector Find/span CheckPlane merge-split chronology exact oracle")
  Check(Bool(snap\MarkCeilingCalls = #PLGOLD_PI02_MarkCeilingColumns And
              snap\MarkCeilingBands = #PLGOLD_PI02_MarkCeilingBands And
              snap\MarkFloorCalls = #PLGOLD_PI02_MarkFloorColumns And
              snap\MarkFloorBands = #PLGOLD_PI02_MarkFloorBands),
        "PI02 upper/lower tier mark-before-clip counters exact oracle")
  Check(Bool(snap\PlaneSpans = #PLGOLD_PI02_PlaneSpans And
              snap\PlanePixels = #PLGOLD_PI02_PlanePixels And
              snap\PlaneOpenedRows = #PLGOLD_PI02_OpenedRows And
              snap\PlaneClosedRows = #PLGOLD_PI02_ClosedRows And
              snap\PlaneRowCacheHits = #PLGOLD_PI02_RowCacheHits And
              snap\PlaneRowCacheMisses = #PLGOLD_PI02_RowCacheMisses And
              snap\PlaneColormapTexels = #PLGOLD_PI02_ColormapTexels),
        "PI02 post-wall span rows/pixels/cache/COLORMAP texels exact oracle")
  Check(Bool(snap\SkyVisplanes = #PLGOLD_PI02_SkyVisplanes And
              snap\SkyDeferredBands = #PLGOLD_PI02_SkyBands And
              snap\SkyDeferredPixels = #PLGOLD_PI02_SkyPixels),
        "PI02 F_SKY1 deferred bands/pixels counted, never textured")
  Check(Bool(snap\FloorVisplanes = #PLGOLD_PI02_FloorVisplanes And
              snap\CeilingVisplanes = #PLGOLD_PI02_CeilingVisplanes And
              snap\FloorPixels = #PLGOLD_PI02_FloorPixels And
              snap\CeilingPixels = #PLGOLD_PI02_CeilingPixels),
        "PI02 floor/ceiling regular pixel split exact; zero sky substituted")
  Check(Bool(snap\WallDrawnPixels = #PLGOLD_PI02_WallDrawnPixels And
              snap\WallCoveredPixels = #PLGOLD_PI02_CoveredPixels),
        "PI02 upper/lower/middle wall writes and coverage exact; planes disjoint")
  Check(Bool(snap\FlatCacheCount = 1 And snap\FlatCacheUniqueFlats = 1 And
              snap\FlatCacheLoadedFlats = 1 And snap\FlatCacheAllocations >= 1 And
              snap\FlatCacheAllocations < 16),
        "PI02 cache loads only the used FLOOR1, never F_SKY1")
  Check(Bool(snap\NonZeroBytes = #PLGOLD_PI02_NonZeroBytes And
              snap\ZeroBytes = #PLGOLD_PI02_ZeroBytes And
              snap\NonZeroBytes + snap\ZeroBytes = #PLANERENDER_FramePixelCount),
        "PI02 nonzero/zero byte audit equals independent oracle and 64,000 cells")

  frameMismatch = PIFrameMismatchCount(@target, *gPI02Frame)
  Check(Bool(frameMismatch = 0), "PI02 all 64,000 frame bytes exact independent oracle")
  sampleMismatch = PISceneSampleMismatch(@target, *gPI02Samples, "PI02",
                                         #PLGOLD_PI02_SampleCount)
  Check(Bool(sampleMismatch = 0), "PI02 eight sample columns x 200 rows exact fixture")
  manualHash = PIFnvFrame(@target)
  Check(Bool(manualHash = PeekQ(*gPI02HashValue) And
              snap\Hash = PeekQ(*gPI02HashValue)), "PI02 result/manual FNV exact independent oracle")

  traceSpanCount = trace\SpanCount
  Check(Bool(traceSpanCount = #PLGOLD_PI02_PlaneSpans),
        "PI02 trace captures every 120 post-wall plane span")
  traceMismatch = 0
  For spanIndex = 0 To traceSpanCount - 1
    If PlaneSpanTraceGetSpan(@trace, spanIndex, @planeIndex, @row,
                             @firstX, @lastX, @planeHeight, @distance,
                             @xStep, @yStep, @xFrac, @yFrac,
                             @lightNum, @mapIndex, @pixels, @cacheHit) = #False
      traceMismatch + 1
    Else
      For fieldIndex = 0 To #PLGOLD_PlaneSpanFieldCount - 1
        expected = PeekL(*gPI02PlaneSpans +
                         Int(spanIndex) * Int(#PLGOLD_PlaneSpanFieldCount) * 4 +
                         Int(fieldIndex) * 4)
        Select fieldIndex
          Case 0 : actual = planeIndex
          Case 1 : actual = row
          Case 2 : actual = firstX
          Case 3 : actual = lastX
          Case 4 : actual = planeHeight
          Case 5 : actual = distance
          Case 6 : actual = xStep
          Case 7 : actual = yStep
          Case 8 : actual = xFrac
          Case 9 : actual = yFrac
          Case 10 : actual = lightNum
          Case 11 : actual = mapIndex
          Case 12 : actual = pixels
          Case 13 : actual = cacheHit
        EndSelect
        If actual <> expected
          traceMismatch + 1
        EndIf
      Next
    EndIf
  Next
  Check(Bool(traceMismatch = 0), "PI02 all 14 span fields chronology exact independent oracle")

  PI02Done:
  PlaneSpanTraceReset(@trace)
  PlaneRenderResultReset(@result)
  FrameBufferReset(@target)
  PISessionClose(@p, @t, @f, @c, @l, @v, @proj)
EndProcedure

; ---------------------------------------------------------------------------
; PI03: lifecycle, rollback, trace cap, zero-span context, legacy preservation
; ---------------------------------------------------------------------------

Procedure.i PIColumnBytePreserved(*Frame.FrameBuffer, FillValue.l)
  Protected index.q
  Protected mismatches.l = 0

  If *Frame = 0 Or *Frame\Pixels = 0
    ProcedureReturn 0
  EndIf
  For index = 0 To Int(#PLANERENDER_FramePixelCount) - 1
    If PeekA(*Frame\Pixels + index) <> (FillValue & 255)
      mismatches + 1
    EndIf
  Next
  ProcedureReturn Bool(mismatches = 0)
EndProcedure

Procedure TestPI03()
  Protected f.FlatCatalog
  Protected c.ColormapSet
  Protected t.TextureCatalog
  Protected p.PNamesTable
  Protected frame.PlaneFrame
  Protected proj.Projection
  Protected planeIndex.l = 0
  Protected flatIndex.i = 0
  Protected cache.PlaneFlatCache
  Protected *image.FlatImage = 0

  Protected rp.PNamesTable
  Protected rt.TextureCatalog
  Protected rf.FlatCatalog
  Protected rc.ColormapSet
  Protected rl.MapLevel
  Protected rv.WallView
  Protected rproj.Projection
  Protected target.FrameBuffer
  Protected result.PlaneRenderResult
  Protected snap.PlaneStatsSnapshot
  Protected *frameCopy.Byte = 0
  Protected firstHash.q = 0
  Protected secondHash.q = 0
  Protected firstManual.q = 0
  Protected secondManual.q = 0
  Protected repeatMismatch.l = 0
  Protected copyMismatch.l = 0
  Protected fixtureMismatch.l = 0

  Protected bp.PNamesTable
  Protected bt.TextureCatalog
  Protected bf.FlatCatalog
  Protected bc.ColormapSet
  Protected bl.MapLevel
  Protected bv.WallView
  Protected bproj.Projection
  Protected brokenTarget.FrameBuffer
  Protected brokenResult.PlaneRenderResult
  Protected brokenError.s = ""

  Protected sp.PNamesTable
  Protected st.TextureCatalog
  Protected sf.FlatCatalog
  Protected sc.ColormapSet
  Protected sl.MapLevel
  Protected sv.WallView
  Protected sproj.Projection
  Protected shortTarget.FrameBuffer
  Protected shortResult.PlaneRenderResult
  Protected shortError.s = ""

  Protected tp.PNamesTable
  Protected tt.TextureCatalog
  Protected tf.FlatCatalog
  Protected tc.ColormapSet
  Protected tl.MapLevel
  Protected tv.WallView
  Protected tproj.Projection
  Protected capTarget.FrameBuffer
  Protected capResult.PlaneRenderResult
  Protected capTrace.PlaneSpanTrace
  Protected capError.s = ""

  Protected lp.PNamesTable
  Protected lt.TextureCatalog
  Protected lf.FlatCatalog
  Protected lc.ColormapSet
  Protected ll.MapLevel
  Protected lv.WallView
  Protected lproj.Projection
  Protected visibility.WallVisibilityResult
  Protected legacyTarget.FrameBuffer
  Protected legacyResult.TexturedWallRenderResult
  Protected legacySpanHash.q = 0
  Protected legacyFrameHash.q = 0
  Protected legacySpanField.l
  Protected legacyExpected.l = 0
  Protected legacyActual.l = 0
  Protected legacyMismatch.l = 0
  Protected legacyOldFieldCount.l = #TEXGOLD_SpanFieldCount
  Protected plan.WallSpanPlan

  Protected zp.PNamesTable
  Protected zt.TextureCatalog
  Protected zf.FlatCatalog
  Protected zc.ColormapSet
  Protected zl.MapLevel
  Protected zv.WallView
  Protected zproj.Projection
  Protected zeroTarget.FrameBuffer
  Protected zeroResult.PlaneRenderResult
  Protected zeroSnap.PlaneStatsSnapshot
  Protected zeroManualHash.q = 0
  Protected zeroRenderOk.i = #False

  BeginCase("PI03", "Lifecycle/rollback/limit/zero-span/legacy synthetic preservation")

  ; (1) Resource lifecycle A -> B -> A with real 64x64 flat reloads.
  Check(Bool(PIBuildFlatVariantWad("m4piab_a.wad", 45)), "PI03 variant A WAD built (FLOOR1=45)")
  Check(Bool(PIBuildFlatVariantWad("m4piab_b.wad", 90)), "PI03 variant B WAD built (FLOOR1=90)")
  If PIResourceOpen("m4piab_a.wad", @f, @c, @t, @p) = #False
    Check(#False, "PI03 A flat/colormap session opened")
    ProcedureReturn
  EndIf
  flatIndex = FlatCatalogFindName(@f, "FLOOR1")
  If ProjectionInitClassic(@proj) = #False Or
     PlaneFrameBegin(@frame, @proj, 0, 0, 0, 41 << #FRACBITS, -1, 1024) = #False Or
     flatIndex < 0 Or
     PlaneFindPlane(@frame, 0, flatIndex, 192, @planeIndex) = #False Or
     PlaneColumnSetBand(@frame, planeIndex, 100, 10, 12) = #False
    Check(#False, "PI03 A frame/plane/band setup")
    Goto PI03ABADone
  EndIf
  FillMemory(@cache, Int(SizeOf(PlaneFlatCache)), 0)
  If PlaneFlatCacheBuild(@cache, @f, @frame) = #False
    Check(#False, "PI03 A flat cache build")
    Goto PI03ABADone
  EndIf
  *image = PlaneFlatCacheImagePtr(@cache, flatIndex)
  Check(Bool(*image <> 0 And PeekA(*image\Pixels) = 45 And cache\Count = 1 And
              cache\Ready <> 0), "PI03 A cache loads real FLOOR1 pixel 45 once")
  WADClose()
  Check(Bool(PlaneFlatCacheReset(@cache)), "PI03 A cache Reset releases image")
  Check(Bool(PlaneFlatCacheImagePtr(@cache, flatIndex) = 0 And
              PlaneFlatCacheIsValid(@cache) = #False And
              FindString(PlaneFlatCacheLastError(), "not initialized") > 0),
        "PI03 old A image pointer invalidated after Reset")

  If PIResourceOpen("m4piab_b.wad", @f, @c, @t, @p) = #False
    Check(#False, "PI03 B flat/colormap session opened")
    Goto PI03ABADone
  EndIf
  flatIndex = FlatCatalogFindName(@f, "FLOOR1")
  If flatIndex < 0 Or PlaneFlatCacheBuild(@cache, @f, @frame) = #False
    Check(#False, "PI03 B cache rebuild")
    Goto PI03ABADone
  EndIf
  *image = PlaneFlatCacheImagePtr(@cache, flatIndex)
  Check(Bool(*image <> 0 And PeekA(*image\Pixels) = 90), "PI03 B reload picks new FLOOR1 pixel 90")
  Check(Bool(PlaneFlatCacheReset(@cache)), "PI03 B cache Reset releases image")
  WADClose()

  If PIResourceOpen("m4piab_a.wad", @f, @c, @t, @p) = #False
    Check(#False, "PI03 A reopen flat/colormap session")
    Goto PI03ABADone
  EndIf
  flatIndex = FlatCatalogFindName(@f, "FLOOR1")
  If flatIndex < 0 Or PlaneFlatCacheBuild(@cache, @f, @frame) = #False
    Check(#False, "PI03 A second cache build")
    Goto PI03ABADone
  EndIf
  *image = PlaneFlatCacheImagePtr(@cache, flatIndex)
  Check(Bool(*image <> 0 And PeekA(*image\Pixels) = 45 And cache\Count = 1),
        "PI03 A->B->A reload returns original FLOOR1 pixel 45 once")
  PI03ABADone:
  *image = 0
  PlaneFlatCacheReset(@cache)
  PlaneFrameReset(@frame)
  ProjectionReset(@proj)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@f)
  ColormapReset(@c)
  TextureCatalogReset(@t)
  PNamesReset(@p)

  ; (2) Repeated draw/reset determinism on the PI02 sky/portal scene.
  If PIBuildSceneWad("m4pi03repeat.wad", 2) = #False Or
     PISessionPrepare("m4pi03repeat.wad", "E2M1", @rp, @rt, @rf, @rc, @rl, @rv,
                      @rproj) = #False
    Check(#False, "PI03 repeat synthetic scene prepared")
    Goto PI03RepeatDone
  EndIf
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "PI03 repeat target created")
  FillMemory(@result, Int(SizeOf(PlaneRenderResult)), 0)
  If PlaneRenderFrame(@rl, @rv, @rproj, @rf, @rt, @rc, @target, @result,
                      #True) = #False
    Check(#False, "PI03 first repeated draw succeeds")
    Goto PI03RepeatDone
  EndIf
  firstHash = result\Hash
  firstManual = PIFnvFrame(@target)
  Check(Bool(PlaneRenderResultIsValid(@result) And
              firstHash = #PLGOLD_PI02_Hash And
              firstManual = #PLGOLD_PI02_Hash),
        "PI03 first repeated draw exact oracle hash")
  *frameCopy = AllocateMemory(Int(#PLANERENDER_FramePixelCount))
  If *frameCopy = 0
    Check(#False, "PI03 first frame copy allocation")
    Goto PI03RepeatDone
  EndIf
  CopyMemory(target\Pixels, *frameCopy, Int(#PLANERENDER_FramePixelCount))
  PlaneRenderResultReset(@result)
  If PlaneRenderFrame(@rl, @rv, @rproj, @rf, @rt, @rc, @target, @result,
                      #True) = #False
    Check(#False, "PI03 second repeated draw after result Reset succeeds")
    Goto PI03RepeatDone
  EndIf
  secondHash = result\Hash
  secondManual = PIFnvFrame(@target)
  If PISnapshotStats(@result, @snap)
    Check(Bool(snap\PlaneSpans = #PLGOLD_PI02_PlaneSpans And
              snap\PlanePixels = #PLGOLD_PI02_PlanePixels),
          "PI03 repeated draw plane counters exact after second pass")
  Else
    Check(#False, "PI03 repeated draw stats snapshot")
  EndIf
  Check(Bool(PlaneRenderResultIsValid(@result) And
              PlaneRenderResultReset(@result)),
        "PI03 second result valid and reusable Reset accepted")
  copyMismatch = 0
  For repeatMismatch = 0 To Int(#PLANERENDER_FramePixelCount) - 1
    If PeekA(target\Pixels + repeatMismatch) <> PeekA(*frameCopy + repeatMismatch)
      copyMismatch + 1
    EndIf
  Next
  Check(Bool(copyMismatch = 0), "PI03 repeated draw produces identical 64,000 target bytes")
  fixtureMismatch = PIFrameMismatchCount(@target, *gPI02Frame)
  Check(Bool(fixtureMismatch = 0), "PI03 repeated draw still matches full oracle frame")
  Check(Bool(secondHash = firstHash And secondHash = #PLGOLD_PI02_Hash And
              secondManual = firstManual And secondManual = #PLGOLD_PI02_Hash),
        "PI03 repeated draw hash/manual FNV deterministic and oracle-exact")
  PI03RepeatDone:
  If *frameCopy <> 0
    FreeMemory(*frameCopy)
    *frameCopy = 0
  EndIf
  PlaneRenderResultReset(@result)
  FrameBufferReset(@target)
  PISessionClose(@rp, @rt, @rf, @rc, @rl, @rv, @rproj)

  ; (3) Late truncated used-floor flat: rollback target byte-for-byte.
  If PIBuildLateBrokenSceneWad("m4pi03badflat.wad") = #False Or
     PISessionPrepare("m4pi03badflat.wad", "E1M1", @bp, @bt, @bf, @bc, @bl, @bv,
                      @bproj) = #False
    Check(#False, "PI03 late-broken flat scene prepared")
    Goto PI03BrokenDone
  EndIf
  If FrameBufferCreate(@brokenTarget, 320, 200) = #False Or
     PlaneRenderResultReset(@brokenResult) = #False
    Check(#False, "PI03 broken target/result setup")
    Goto PI03BrokenDone
  EndIf
  FillMemory(brokenTarget\Pixels, Int(brokenTarget\PixelCount), 7)
  If PlaneRenderFrame(@bl, @bv, @bproj, @bf, @bt, @bc, @brokenTarget,
                      @brokenResult, #True) = #True
    Check(#False, "PI03 truncated used-floor flat must fail")
    Goto PI03BrokenDone
  EndIf
  brokenError = PlaneRenderLastError()
  Check(Bool(FindString(brokenError, "flat cache") > 0 And
              (FindString(brokenError, "wrong size") > 0 Or
               FindString(PlaneFlatCacheLastError(), "wrong size") > 0)),
        "PI03 late wall-pass/private-frame phase fails at flat cache load")
  Check(Bool(PIColumnBytePreserved(@brokenTarget, 7)),
        "PI03 all 64,000 prior target bytes preserved on late flat failure")
  Check(Bool(brokenResult\Ready = 0 And brokenResult\Plans = 0 And
              brokenResult\TexturePlans = 0 And brokenResult\Magic = #PLANERENDER_Magic),
        "PI03 failed result owns no metadata and is reusable empty")
  PI03BrokenDone:
  PlaneRenderResultReset(@brokenResult)
  FrameBufferReset(@brokenTarget)
  PISessionClose(@bp, @bt, @bf, @bc, @bl, @bv, @bproj)

  ; (4) Short COLORMAP entry rejection preserves target state.
  If PIBuildShortColormapSceneWad("m4pi03shortcm.wad") = #False Or
     PISessionPrepare("m4pi03shortcm.wad", "E1M1", @sp, @st, @sf, @sc, @sl, @sv,
                      @sproj) = #False
    Check(#False, "PI03 short-COLORMAP scene prepared")
    Goto PI03ShortDone
  EndIf
  If FrameBufferCreate(@shortTarget, 320, 200) = #False Or
     PlaneRenderResultReset(@shortResult) = #False
    Check(#False, "PI03 short target/result setup")
    Goto PI03ShortDone
  EndIf
  FillMemory(shortTarget\Pixels, Int(shortTarget\PixelCount), 4)
  If PlaneRenderFrame(@sl, @sv, @sproj, @sf, @st, @sc, @shortTarget,
                      @shortResult, #True) = #True
    Check(#False, "PI03 16-table COLORMAP must fail the classic lighting gate")
    Goto PI03ShortDone
  EndIf
  shortError = PlaneRenderLastError()
  Check(Bool(FindString(shortError, "COLORMAP") > 0 And
              FindString(shortError, "requires at least") > 0 And
              FindString(shortError, "32") > 0),
        "PI03 short COLORMAP rejected explicitly before private frame writes")
  Check(Bool(PIColumnBytePreserved(@shortTarget, 4)),
        "PI03 all 64,000 prior target bytes preserved on COLORMAP rejection")
  Check(Bool(shortResult\Ready = 0 And shortResult\Plans = 0 And
              shortResult\Magic = #PLANERENDER_Magic),
        "PI03 COLORMAP rejection leaves reusable empty result")
  PI03ShortDone:
  PlaneRenderResultReset(@shortResult)
  FrameBufferReset(@shortTarget)
  PISessionClose(@sp, @st, @sf, @sc, @sl, @sv, @sproj)

  ; (5) Late trace-cap limit failure during plane drawing rollback.
  If PIBuildSceneWad("m4pi03cap.wad", 2) = #False Or
     PISessionPrepare("m4pi03cap.wad", "E2M1", @tp, @tt, @tf, @tc, @tl, @tv,
                      @tproj) = #False
    Check(#False, "PI03 trace-cap scene prepared")
    Goto PI03CapDone
  EndIf
  If FrameBufferCreate(@capTarget, 320, 200) = #False Or
     PlaneRenderResultReset(@capResult) = #False Or
     PlaneSpanTraceBegin(@capTrace, 2) = #False
    Check(#False, "PI03 trace-cap target/result/trace setup")
    Goto PI03CapDone
  EndIf
  FillMemory(capTarget\Pixels, Int(capTarget\PixelCount), 9)
  If PlaneRenderFrame(@tl, @tv, @tproj, @tf, @tt, @tc, @capTarget,
                      @capResult, #True, @capTrace) = #True
    Check(#False, "PI03 trace cap must fail the late plane span audit")
    Goto PI03CapDone
  EndIf
  capError = PlaneRenderLastError()
  Check(Bool(FindString(capError, "span trace budget is exhausted") > 0),
        "PI03 trace cap rejection surfaces late span audit budget diagnostic")
  Check(Bool(capTrace\SpanCount <= capTrace\Capacity And capTrace\Capacity = 2),
        "PI03 failure retains only bounded caller-owned trace records")
  Check(Bool(PIColumnBytePreserved(@capTarget, 9)),
        "PI03 all 64,000 prior target bytes preserved on late trace-cap failure")
  Check(Bool(capResult\Ready = 0 And capResult\Plans = 0 And
              capResult\Magic = #PLANERENDER_Magic),
        "PI03 trace-cap failure leaves reusable empty result")
  PI03CapDone:
  PlaneSpanTraceReset(@capTrace)
  PlaneRenderResultReset(@capResult)
  FrameBufferReset(@capTarget)
  PISessionClose(@tp, @tt, @tf, @tc, @tl, @tv, @tproj)

  ; (6) Legacy M3-04/M3-06 frozen outputs unchanged on the synthetic room.
  If PIBuildSceneWad("m4pi03legacy.wad", 1) = #False Or
     PISessionPrepare("m4pi03legacy.wad", "E1M1", @lp, @lt, @lf, @lc, @ll, @lv,
                      @lproj) = #False
    Check(#False, "PI03 legacy synthetic scene prepared")
    Goto PI03LegacyDone
  EndIf
  If WallVisibilityBuild(@ll, @lv\Camera, @lproj, @lf, @lt, @visibility) = #False
    Check(#False, "PI03 unchanged 6-argument M3-04 visibility")
    Goto PI03LegacyDone
  EndIf
  Check(Bool(WallVisibilityIsValid(@visibility) And
              WallVisibilityCount(@visibility) = #TEXGOLD_TI01_SpanCount),
        "PI03 legacy M3-04 span count unchanged")
  legacySpanHash = PISpanHash(@visibility)
  Check(Bool(legacySpanHash <> -1 And legacySpanHash = PeekQ(*gLegacySpanHash)),
        "PI03 legacy M3-04 span fingerprint unchanged")
  legacyMismatch = 0
  For legacySpanField = 0 To Int(legacyOldFieldCount) - 1
    If WallVisibilityGetSpan(@visibility, 0, @plan\Subsector, @plan\Seg,
                             @plan\Linedef, @plan\Side, @plan\FrontSector,
                             @plan\BackSector, @plan\FirstX, @plan\LastX,
                             @plan\Kind) = #False
      legacyMismatch + 1
    Else
      legacyExpected = PeekL(*gLegacyPlanSpans + Int(legacySpanField) * 4)
      Select legacySpanField
        Case 0 : legacyActual = plan\Subsector
        Case 1 : legacyActual = plan\Seg
        Case 2 : legacyActual = plan\Linedef
        Case 3 : legacyActual = plan\Side
        Case 4 : legacyActual = plan\FrontSector
        Case 5 : legacyActual = plan\BackSector
        Case 6 : legacyActual = plan\FirstX
        Case 7 : legacyActual = plan\LastX
        Case 8 : legacyActual = plan\Kind
      EndSelect
      If legacyActual <> legacyExpected
        legacyMismatch + 1
      EndIf
    EndIf
  Next
  Check(Bool(legacyMismatch = 0), "PI03 legacy M3-04 span vector fields unchanged")
  If FrameBufferCreate(@legacyTarget, 320, 200) = #False Or
     TexturedWallRenderResultReset(@legacyResult) = #False Or
     TexturedWallRenderFrame(@ll, @lv, @lproj, @lf, @lt, @lc, @visibility,
                             @legacyTarget, @legacyResult, #True) = #False
    Check(#False, "PI03 legacy M3-06 textured frame succeeds")
    Goto PI03LegacyDone
  EndIf
  legacyFrameHash = legacyResult\Hash
  Check(Bool(legacyFrameHash = PeekQ(*gLegacyFrameHash) And
              legacyResult\DrawnPixels = #TEXGOLD_TI01_DrawnPixels),
        "PI03 legacy M3-06 textured hash/painted pixels unchanged")
  PI03LegacyDone:
  TexturedWallRenderResultReset(@legacyResult)
  WallVisibilityReset(@visibility)
  FrameBufferReset(@legacyTarget)
  PISessionClose(@lp, @lt, @lf, @lc, @ll, @lv, @lproj)

  ; (7) Zero emitted WallSpans yet valid subsector/plane context: camera moves
  ; behind the one-sided wall of the T01 room while the zero-node subsector root
  ; still yields two empty regular plane records and no span events.
  If PIBuildSceneWad("m4pi03zero.wad", 1) = #False Or
     PISessionPrepare("m4pi03zero.wad", "E1M1", @zp, @zt, @zf, @zc, @zl, @zv,
                      @zproj) = #False
    Check(#False, "PI03 zero-span synthetic scene prepared")
    Goto PI03ZeroDone
  EndIf
  Check(Bool(WallViewSetMapUnits(@zv, 200, 0, 0, 0)),
        "PI03 camera override behind the one-sided wall accepted")
  If FrameBufferCreate(@zeroTarget, 320, 200) = #False Or
     PlaneRenderResultReset(@zeroResult) = #False
    Check(#False, "PI03 zero-span target/result setup")
    Goto PI03ZeroDone
  EndIf
  zeroRenderOk = PlaneRenderFrame(@zl, @zv, @zproj, @zf, @zt, @zc, @zeroTarget,
                                  @zeroResult, #False)
  Check(Bool(zeroRenderOk), "PI03 zero-span combined frame succeeds without pixels")
  If zeroRenderOk = #False Or PISnapshotStats(@zeroResult, @zeroSnap) = #False
    Check(#False, "PI03 zero-span result/stats snapshot")
    Goto PI03ZeroDone
  EndIf
  Check(Bool(PlaneRenderResultIsValid(@zeroResult) And
              zeroSnap\SpanCount = 0 And zeroSnap\PlaneSpans = 0 And
              zeroSnap\PlanePixels = 0 And zeroSnap\WallDrawnPixels = 0 And
              zeroSnap\WallCoveredPixels = 0),
        "PI03 zero emitted WallSpans and zero plane/wall pixel writes")
  Check(Bool(zeroSnap\TimelineVisits = 1 And zeroSnap\TimelineEvents = 0 And
              zeroSnap\ZeroSpanVisits = 1),
        "PI03 valid subsector visit counted with zero span events")
  Check(Bool(zeroSnap\Visplanes = 2 And zeroSnap\RegularVisplanes = 2 And
              zeroSnap\SkyVisplanes = 0 And zeroSnap\EmptyVisplanes = 2 And
              zeroSnap\PopulatedVisplanes = 0),
        "PI03 zero-span context still creates two empty regular visplanes")
  Check(Bool(zeroSnap\FindCalls = 2 And zeroSnap\FindCreate = 2 And
              zeroSnap\CheckCalls = 0 And zeroSnap\MarkCeilingCalls = 0 And
              zeroSnap\MarkFloorCalls = 0),
        "PI03 subsector Find chronology valid while no span reaches Check/marks")
  Check(Bool(zeroSnap\NonZeroBytes = 0 And zeroSnap\ZeroBytes = 64000),
        "PI03 empty wall/plane pass leaves all 64,000 target bytes zero")
  zeroManualHash = PIFnvFrame(@zeroTarget)
  Check(Bool(zeroManualHash <> -1 And zeroSnap\Hash = zeroManualHash),
        "PI03 zero-pixel result hash equals independent manual 64,000-byte FNV")
  Check(Bool(PIColumnBytePreserved(@zeroTarget, 0) And
              zeroSnap\FlatCacheCount = 0 And zeroSnap\FlatCacheUniqueFlats = 0),
        "PI03 no wall/flat loads occur with zero used plane bands")
  PI03ZeroDone:
  PlaneRenderResultReset(@zeroResult)
  FrameBufferReset(@zeroTarget)
  PISessionClose(@zp, @zt, @zf, @zc, @zl, @zv, @zproj)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

Procedure Main()
  If WallTexPrepareFixtureDirectory() = #False
    PrintN("fixture directory preparation failed")
    gPIFailureCount + 1
    ProcedureReturn
  EndIf
  TestPI01()
  TestPI02()
  TestPI03()
EndProcedure

OpenConsole()
Main()
PrintN("")
PrintN("Cases: " + Str(gPICaseCount) + ", assertions: " + Str(gPIAssertionCount) +
       ", failures: " + Str(gPIFailureCount))
If gPIFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gPIFailureCount
