; -----------------------------------------------------------------------------
; DoomPB - M4-01 visplane/flat/zlight unit tests PL01-PL60
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Standalone synthetic/no-IWAD suite. Includes the accepted M2/M3 resource, map,
; geometry, visibility, projection, textured wall and the new M4-01 plane
; modules; the independent generated M4-01 fixture from
; scripts/gen_plane_golden.py, the old M3-06 wall-fixture for legacy hash
; preservation, the shared synthetic WAD/map support module and the production
; framebuffer/video presentation constants. Expected plane/span/row/lighting,
; counters, full 64,000 palette bytes, full-frame hashes and scalar values come
; from the independent Python oracle fixture or an explicit integer formula here,
; never from first production output. No commercial WAD bytes, Doom graphics or
; real display usage occur. Synthetic WAD files are written only in the harness
; temp fixture directory under build output and released on each teardown.
;
; Exit code: 0 when every assertion passed, otherwise the failure count.
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

#UNIT_FNV_Prime64 = 1099511628211
#UNIT_FNV_Basis64 = -3750763034362895579

Global gUCaseCount.i = 0
Global gUAssertionCount.i = 0
Global gUFailureCount.i = 0
Global gUFixedDirPrepared.i = #False

Global *gPI01Spans = ?PLGOLD_PI01_SpanVectors
Global *gPI01PlaneSpans = ?PLGOLD_PI01_PlaneSpans
Global *gPI01Frame = ?PLGOLD_PI01_Frame
Global *gPI01Samples = ?PLGOLD_PI01_Samples
Global *gPI01HashValue = ?PLGOLD_PI01_HashValue
Global *gPI02Spans = ?PLGOLD_PI02_SpanVectors
Global *gPI02PlaneSpans = ?PLGOLD_PI02_PlaneSpans
Global *gPI02Frame = ?PLGOLD_PI02_Frame
Global *gPI02Samples = ?PLGOLD_PI02_Samples
Global *gPI02HashValue = ?PLGOLD_PI02_HashValue
Global *gYSlopes = ?PLGOLD_YSlopeValues
Global *gDistScales = ?PLGOLD_DistScaleValues
Global *gZLightLevels = ?PLGOLD_ZLightLevels
Global *gMapPlaneSample = ?PLGOLD_MapPlaneSample
Global *gSpotValues = ?PLGOLD_SpotValues
Global *gLegacyTI01Hash = ?TEXGOLD_TI01_Hash
Global *gLegacyTI01SpanHash = ?TEXGOLD_TI01_SpanHash

Procedure BeginCase(Id.s, Title.s)
  gUCaseCount + 1
  PrintN("CASE " + Id + ": " + Title)
EndProcedure

Procedure Check(Ok.i, Description.s)
  gUAssertionCount + 1
  If Ok = 0
    gUFailureCount + 1
    PrintN("  FAIL: " + Description)
  Else
    PrintN("  ok: " + Description)
  EndIf
EndProcedure

; ---------------------------------------------------------------------------
; Shared synthetic scene/resource setup
; ---------------------------------------------------------------------------

Procedure.i UFixtureDirectoryReady()
  If gUFixedDirPrepared
    ProcedureReturn #True
  EndIf
  If WallTexPrepareFixtureDirectory() = #False
    ProcedureReturn #False
  EndIf
  gUFixedDirPrepared = #True
  ProcedureReturn #True
EndProcedure

Procedure.i UBuildSceneWad(FileName.s, SceneMode.i)
  Protected marker.s = ""
  Protected ok.i = #False

  If UFixtureDirectoryReady() = #False
    ProcedureReturn #False
  EndIf
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
      ok = WallTexAddMapLumpsToWad(marker)
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

; Opens a built synthetic scene PWAD and decodes all production resources, map
; through MapLevelLoad, resource binding, player-one view, classic projection.
; Leaves the WAD open and every object caller-owned for a frame call.
Procedure.i UPrepareScene(FileName.s, Marker.s,
                         *Pnames.PNamesTable,
                         *Textures.TextureCatalog,
                         *Flats.FlatCatalog,
                         *Colormap.ColormapSet,
                         *Level.MapLevel, *View.WallView,
                         *Projection.Projection)
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

  If WADOpen(WallTexFixturePath(FileName)) = #False
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
  If MapLevelLoad(Marker, *Level) = #False
    ProcedureReturn #False
  EndIf
  If MapLevelValidateResources(*Level, *Flats, *Textures) = #False
    ProcedureReturn #False
  EndIf
  If WallRenderPlayerStartView(*Level, *View, @thingIndex, @subsectorIndex,
                               @sectorIndex) = #False
    ProcedureReturn #False
  EndIf
  If ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure UCloseScene(*Pnames.PNamesTable, *Textures.TextureCatalog,
                      *Flats.FlatCatalog, *Colormap.ColormapSet,
                      *Level.MapLevel, *View.WallView, *Projection.Projection)
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
EndProcedure

; Resource-only synthetic PWAD with the standard flats/COLORMAP layout. Used by
; direct plane-map tests that need the production FlatCatalog/ColormapSet while
; the WAD is open but no map textures/view.
Procedure.i UBuildResourceOnlyWad(FileName.s)
  If UFixtureDirectoryReady() = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallTexBuildStandardResourceWad(FileName, 37, 201, 73, 19,
                                                  17, 9, #True)
EndProcedure

Procedure.i UOpenResourceOnlyWad(FileName.s,
                                 *Flats.FlatCatalog,
                                 *Colormap.ColormapSet,
                                 *Textures.TextureCatalog,
                                 *Pnames.PNamesTable)
  PNamesReset(*Pnames)
  TextureCatalogReset(*Textures)
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  If WADOpen(WallTexFixturePath(FileName)) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallFlats(*Flats) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallColormap(*Colormap) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

; Direct caller-built valid room MapLevel (T01 geometry with custom floor/ceiling)
; through the production M2 decoders. No WAD bytes; specs wholly synthetic.
Procedure.i UBuildDirectRoomMap(*Level.MapLevel, FloorHeight.l, CeilingHeight.l,
                               FloorName.s, CeilingName.s, LightLevel.l,
                               AllowFloor.i, AllowCeiling.i)
  Protected Dim sectors.WallTexSectorSpec(1)
  Protected Dim lines.WallTexLineSpec(1)
  Protected Dim sides.WallTexSideSpec(1)
  Protected Dim verts.WallTexVertexSpec(2)
  Protected Dim segs.WallTexSegSpec(1)
  Protected Dim subs.WallTexSubSpec(1)
  Protected Dim things.WallTexThingSpec(1)
  Protected ok.i

  sectors(0)\FloorHeight = FloorHeight
  sectors(0)\CeilingHeight = CeilingHeight
  sectors(0)\FloorName = FloorName
  sectors(0)\CeilingName = CeilingName
  sectors(0)\LightLevel = LightLevel
  lines(0)\V1 = 0 : lines(0)\V2 = 1
  lines(0)\Flags = #MAP_ML_TWOSIDED
  lines(0)\Side0 = 0 : lines(0)\Side1 = 0
  sides(0)\Sector = 0
  sides(0)\TopName = "-" : sides(0)\BottomName = "-" : sides(0)\MidName = "-"
  sides(0)\TextureOffset = 0 : sides(0)\RowOffset = 0
  verts(0)\X = 100 : verts(0)\Y = 64
  verts(1)\X = 100 : verts(1)\Y = -64
  segs(0)\V1 = 0 : segs(0)\V2 = 1 : segs(0)\RawAngle = 49152
  segs(0)\Line = 0 : segs(0)\Side = 0 : segs(0)\Offset = 0
  subs(0)\NumSegs = 1 : subs(0)\FirstSeg = 0
  things(0)\X = 0 : things(0)\Y = 0 : things(0)\Angle = 0
  things(0)\Type = 1 : things(0)\Options = 0
  ok = WallTexBuildMapLevel(*Level, @sectors(0), 1, @lines(0), 1, @sides(0), 1,
                            @verts(0), 2, @segs(0), 1, @subs(0), 1,
                            0, 0, @things(0), 1)
  If AllowFloor = 0 Or AllowCeiling = 0
    ; Geometry contents remain; eligibility comes from heights only.
  EndIf
  ProcedureReturn ok
EndProcedure

; Wrong-size FLAT resource for strict 4096-byte load failure. Marker namespace
; holds one deliberately 4095-byte synthesized flat plus no commercial bytes.
Procedure.i UBuildBrokenFlatWad(FileName.s)
  Protected *bad.Byte = 0
  Protected ok.i = #False

  If UFixtureDirectoryReady() = #False
    ProcedureReturn #False
  EndIf
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
  WallTexWadAdd("BADFLAT", *bad, 4095)
  WallTexWadAdd("F_END", 0, 0)
  WallTexWadAdd("COLORMAP", 0, 0)
  ok = WallTexWadFinish()
  FreeMemory(*bad)
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  ProcedureReturn ok
EndProcedure

; Complete one-sector T01 scene whose FLOOR1 flat is deliberately 4095 bytes:
; palette/flats, standard wall resources and COLORMAP, T01 map. The WAD opens
; and validates resources, but the used-floor FlatLoad fails late only after the
; wall pass, exercising transactional private-frame rollback.
Procedure.i UBuildLateBrokenSceneWad(FileName.s)
  Protected *bad.Byte = 0
  Protected ok.i = #False

  If UFixtureDirectoryReady() = #False
    ProcedureReturn #False
  EndIf
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

; COLORMAP with only 16 complete tables: decoder resource exists but the classic
; zlight >=32-table gate rejects it. Wholly synthetic bytes.
Procedure.i UBuildShortColormapWad(FileName.s)
  Protected tableCount.l = 16
  Protected *data.Byte = 0
  Protected mapIndex.l
  Protected texel.l
  Protected ok.i = #False

  If UFixtureDirectoryReady() = #False
    ProcedureReturn #False
  EndIf
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
  WallTexWadAdd("F_START", 0, 0)
  WallTexAddFlat("FLOOR1", 45)
  WallTexWadAdd("F_END", 0, 0)
  WallTexWadAdd("COLORMAP", *data, Int(tableCount) * 256)
  ok = WallTexWadFinish()
  FreeMemory(*data)
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  ProcedureReturn ok
EndProcedure

; Exact independent spot reference formula from source r_draw.c R_DrawSpan.
Procedure.l UReferenceSpot(XFrac.l, YFrac.l)
  ProcedureReturn ((YFrac >> 10) & (63 * 64)) + ((XFrac >> 16) & 63)
EndProcedure

; Custom synthetic flat-variant resources: palette, F_START/FLATZERO/FLATMAX/
; FLOOR1/CEIL1/F_SKY1/F_END and the standard 32-table COLORMAP. No wall textures
; needed. Sources 0 and 255 are ordinary palette indexes, never skipped.
; F_SKY1/F_END and the standard 32-table COLORMAP. No wall textures needed.
Procedure.i UBuildFlatVariantWad(FileName.s, FloorPixel.l)
  Protected ok.i = #False

  If UFixtureDirectoryReady() = #False
    ProcedureReturn #False
  EndIf
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

; ---------------------------------------------------------------------------
; Full-frame runner: independent single-pass combined scene summary
; ---------------------------------------------------------------------------

Structure URunSummary
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
  OpenedRows.l
  ClosedRows.l
  RowCacheHits.l
  RowCacheMisses.l
  ColormapTexels.l
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
  WallDrawnPixels.l
  WallCoveredPixels.l
  NonZeroBytes.l
  ZeroBytes.l
  ComposedTextures.l
  RequestedReferences.l
  ReusedTextures.l
  MaskedMidSpans.l
  ShortTextures.l
  TextureCacheAllocations.l
  FlatCacheCount.l
  FlatCacheUnique.l
  FlatCacheLoaded.l
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
  Hash.q
  ManualHash.q
EndStructure

Procedure.q UFnvFrame(*Frame.FrameBuffer)
  Protected index.i
  Protected value.q = #UNIT_FNV_Basis64

  If *Frame = 0 Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For index = 0 To Int(*Frame\PixelCount) - 1
    value = value ! PeekA(*Frame\Pixels + index)
    value = value * #UNIT_FNV_Prime64
  Next
  ProcedureReturn value
EndProcedure

; Builds one completely synthetic scene PWAD, decodes all resources, loads the
; marker map, derives player-one view/projection, renders the transactional
; combined wall+plane frame into a fresh target/result, copies the numeric
; summary, computes the manual FNV over target pixels, and releases every local
; owner. An optional caller-owned trace is passed through and kept (not reset);
; the caller must reset it after reading.
Procedure.i URunScene(FileName.s, SceneMode.i, *Summary.URunSummary,
                     *Trace.PlaneSpanTrace = 0)
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected target.FrameBuffer
  Protected result.PlaneRenderResult
  Protected spanCount.l = 0
  Protected segmentCount.l = 0
  Protected texturePlanCount.l = 0
  Protected visplanes.l = 0
  Protected regularVisplanes.l = 0
  Protected skyVisplanes.l = 0
  Protected emptyVisplanes.l = 0
  Protected populatedVisplanes.l = 0
  Protected skyDeferredBands.l = 0
  Protected skyDeferredPixels.l = 0
  Protected planeSpans.l = 0
  Protected planePixels.l = 0
  Protected planeOpenedRows.l = 0
  Protected planeClosedRows.l = 0
  Protected planeRowCacheHits.l = 0
  Protected planeRowCacheMisses.l = 0
  Protected planeColormapTexels.l = 0
  Protected floorVisplanes.l = 0
  Protected ceilingVisplanes.l = 0
  Protected floorPixels.l = 0
  Protected ceilingPixels.l = 0
  Protected findCalls.l = 0
  Protected findReuse.l = 0
  Protected findCreate.l = 0
  Protected checkCalls.l = 0
  Protected checkMerges.l = 0
  Protected checkSplits.l = 0
  Protected markCeilingCalls.l = 0
  Protected markFloorCalls.l = 0
  Protected markCeilingBands.l = 0
  Protected markFloorBands.l = 0
  Protected timelineVisits.l = 0
  Protected timelineEvents.l = 0
  Protected zeroSpanVisits.l = 0
  Protected skyFindVisits.l = 0
  Protected regularFindVisits.l = 0
  Protected wallProcessedColumns.l = 0
  Protected wallTextureColumns.l = 0
  Protected wallMiddlePixels.l = 0
  Protected wallUpperPixels.l = 0
  Protected wallLowerPixels.l = 0
  Protected wallDrawnPixels.l = 0
  Protected wallDrawRanges.l = 0
  Protected wallEmptyColumns.l = 0
  Protected wallClippedColumns.l = 0
  Protected wallOutOfFrameColumns.l = 0
  Protected wallTextureSamples.l = 0
  Protected wallCoveredPixels.l = 0
  Protected nonzeroBytes.l = 0
  Protected zeroBytes.l = 0
  Protected composedTextures.l = 0
  Protected requestedReferences.l = 0
  Protected reusedReferences.l = 0
  Protected maskedMidSpans.l = 0
  Protected shortTextures.l = 0
  Protected textureCacheAlloc.l = 0
  Protected flatCacheCount.l = 0
  Protected flatCacheUnique.l = 0
  Protected flatCacheLoaded.l = 0
  Protected flatCacheAlloc.l = 0
  Protected planeFrameAlloc.l = 0
  Protected timelineAlloc.l = 0
  Protected zlightAlloc.l = 0
  Protected wallTableAlloc.l = 0
  Protected visibilityAlloc.l = 0
  Protected clipAlloc.l = 0
  Protected frameAlloc.l = 0
  Protected coverageAlloc.l = 0
  Protected metadataAlloc.l = 0
  Protected allocations.l = 0
  Protected visitedNodes.l = 0
  Protected visitedSubsectors.l = 0
  Protected processedSegs.l = 0
  Protected emittedFragments.l = 0
  Protected hash.q = 0
  Protected manual.q = 0
  Protected ok.i = #False
  Protected marker.s = ""
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0

  If *Summary = 0
    ProcedureReturn #False
  EndIf
  FillMemory(*Summary, Int(SizeOf(URunSummary)), 0)
  If UBuildSceneWad(FileName, SceneMode) = #False
    ProcedureReturn #False
  EndIf
  marker = "E1M1"
  If SceneMode = 2
    marker = "E2M1"
  EndIf

  PNamesReset(@pnames)
  TextureCatalogReset(@textures)
  FlatCatalogReset(@flats)
  ColormapReset(@colormap)
  MapLevelReset(@level)
  WallViewReset(@view)
  ProjectionReset(@projection)
  FrameBufferReset(@target)
  PlaneRenderResultReset(@result)

  If WADOpen(WallTexFixturePath(FileName)) = #False
    Goto URunDone
  EndIf
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False
    Goto URunDone
  EndIf
  If WallTexDecodeWallFlats(@flats) = #False
    Goto URunDone
  EndIf
  If WallTexDecodeWallColormap(@colormap) = #False
    Goto URunDone
  EndIf
  If MapLevelLoad(marker, @level) = #False
    Goto URunDone
  EndIf
  If MapLevelValidateResources(@level, @flats, @textures) = #False
    Goto URunDone
  EndIf
  If WallRenderPlayerStartView(@level, @view, @thingIndex, @subsectorIndex,
                               @sectorIndex) = #False
    Goto URunDone
  EndIf
  If ProjectionInitClassic(@projection) = #False
    Goto URunDone
  EndIf
  If FrameBufferCreate(@target, 320, 200) = #False
    Goto URunDone
  EndIf
  If PlaneRenderResultReset(@result) = #False
    Goto URunDone
  EndIf
  If PlaneRenderFrame(@level, @view, @projection, @flats, @textures,
                      @colormap, @target, @result, #True, *Trace) = #False
    Goto URunDone
  EndIf

  If PlaneRenderGetStats(@result, @spanCount, @segmentCount, 0,
                          @texturePlanCount, 0,
                          @visplanes, @regularVisplanes, @skyVisplanes,
                          @emptyVisplanes, @populatedVisplanes,
                          @skyDeferredBands, @skyDeferredPixels,
                          @planeSpans, @planePixels,
                          @planeOpenedRows, @planeClosedRows,
                          @planeRowCacheHits, @planeRowCacheMisses,
                          @planeColormapTexels,
                          @floorVisplanes, @ceilingVisplanes,
                          @floorPixels, @ceilingPixels,
                          @findCalls, @findReuse, @findCreate,
                          @checkCalls, @checkMerges, @checkSplits,
                          @markCeilingCalls, @markFloorCalls,
                          @markCeilingBands, @markFloorBands,
                          @timelineVisits, @timelineEvents,
                          @zeroSpanVisits, @skyFindVisits, @regularFindVisits,
                          0, 0, 0, 0,
                          @wallProcessedColumns, @wallTextureColumns,
                          @wallMiddlePixels, @wallUpperPixels, @wallLowerPixels,
                          @wallDrawnPixels, 0, 0, 0, @wallDrawRanges,
                          @wallEmptyColumns, @wallClippedColumns,
                          @wallOutOfFrameColumns, @wallTextureSamples, 0, 0,
                          @wallCoveredPixels, @nonzeroBytes, @zeroBytes,
                          @composedTextures, @requestedReferences,
                          @reusedReferences, @maskedMidSpans, @shortTextures,
                          @textureCacheAlloc, @flatCacheCount, 0,
                          0, @flatCacheUnique, @flatCacheLoaded,
                          @flatCacheAlloc,
                          @planeFrameAlloc, @timelineAlloc, @zlightAlloc,
                          @wallTableAlloc, @visibilityAlloc, @clipAlloc,
                          @frameAlloc, @coverageAlloc, @metadataAlloc,
                          @allocations,
                          @visitedNodes, @visitedSubsectors, @processedSegs,
                          @emittedFragments, 0, 0, 0, 0, 0, @hash) = #False
    Goto URunDone
  EndIf
  manual = UFnvFrame(@target)
  If manual = -1
    Goto URunDone
  EndIf

  *Summary\SpanCount = spanCount
  *Summary\SegmentCount = segmentCount
  *Summary\TexturePlanCount = spanCount
  *Summary\Visplanes = visplanes
  *Summary\RegularVisplanes = regularVisplanes
  *Summary\SkyVisplanes = skyVisplanes
  *Summary\EmptyVisplanes = emptyVisplanes
  *Summary\PopulatedVisplanes = populatedVisplanes
  *Summary\SkyDeferredBands = skyDeferredBands
  *Summary\SkyDeferredPixels = skyDeferredPixels
  *Summary\PlaneSpans = planeSpans
  *Summary\PlanePixels = planePixels
  *Summary\OpenedRows = planeOpenedRows
  *Summary\ClosedRows = planeClosedRows
  *Summary\RowCacheHits = planeRowCacheHits
  *Summary\RowCacheMisses = planeRowCacheMisses
  *Summary\ColormapTexels = planeColormapTexels
  *Summary\FloorVisplanes = floorVisplanes
  *Summary\CeilingVisplanes = ceilingVisplanes
  *Summary\FloorPixels = floorPixels
  *Summary\CeilingPixels = ceilingPixels
  *Summary\FindCalls = findCalls
  *Summary\FindReuse = findReuse
  *Summary\FindCreate = findCreate
  *Summary\CheckCalls = checkCalls
  *Summary\CheckMerges = checkMerges
  *Summary\CheckSplits = checkSplits
  *Summary\MarkCeilingCalls = markCeilingCalls
  *Summary\MarkFloorCalls = markFloorCalls
  *Summary\MarkCeilingBands = markCeilingBands
  *Summary\MarkFloorBands = markFloorBands
  *Summary\TimelineVisits = timelineVisits
  *Summary\TimelineEvents = timelineEvents
  *Summary\ZeroSpanVisits = zeroSpanVisits
  *Summary\SkyFindVisits = skyFindVisits
  *Summary\RegularFindVisits = regularFindVisits
  *Summary\WallDrawnPixels = wallDrawnPixels
  *Summary\WallCoveredPixels = wallCoveredPixels
  *Summary\NonZeroBytes = nonzeroBytes
  *Summary\ZeroBytes = zeroBytes
  *Summary\ComposedTextures = composedTextures
  *Summary\RequestedReferences = requestedReferences
  *Summary\ReusedTextures = reusedReferences
  *Summary\MaskedMidSpans = maskedMidSpans
  *Summary\ShortTextures = shortTextures
  *Summary\TextureCacheAllocations = textureCacheAlloc
  *Summary\FlatCacheCount = flatCacheCount
  *Summary\FlatCacheUnique = flatCacheUnique
  *Summary\FlatCacheLoaded = flatCacheLoaded
  *Summary\FlatCacheAllocations = flatCacheAlloc
  *Summary\PlaneFrameAllocations = planeFrameAlloc
  *Summary\TimelineAllocations = timelineAlloc
  *Summary\ZLightAllocations = zlightAlloc
  *Summary\WallTableAllocations = wallTableAlloc
  *Summary\VisibilityAllocations = visibilityAlloc
  *Summary\ClipAllocations = clipAlloc
  *Summary\FrameAllocations = frameAlloc
  *Summary\CoverageAllocations = coverageAlloc
  *Summary\MetadataAllocations = metadataAlloc
  *Summary\Allocations = allocations
  *Summary\Hash = hash
  *Summary\ManualHash = manual
  ok = #True

  URunDone:
  ; summary fields remain zero when failure occurred above this label
  PlaneRenderResultReset(@result)
  FrameBufferReset(@target)
  WallViewReset(@view)
  ProjectionReset(@projection)
  MapLevelReset(@level)
  FlatCatalogReset(@flats)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
  ColormapReset(@colormap)
  If WADIsOpen()
    WADClose()
  EndIf
  ProcedureReturn ok
EndProcedure

; Minimal valid plane frame for direct plane mapping/mark/MakeSpans cases.
Procedure.i UPlaneFrameBegin(*Frame.PlaneFrame, *Projection.Projection,
                             ViewZ.l, SkyFlatIndex.l, MaxVisplanes.l)
  If ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn PlaneFrameBegin(*Frame, *Projection, 0, 0, 0, ViewZ,
                                  SkyFlatIndex, MaxVisplanes)
EndProcedure

; ---------------------------------------------------------------------------
; PL01-PL05: initialize/reset/ownership, limits, invalid pointers, sentinels
; ---------------------------------------------------------------------------

Procedure TestPL01()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected ok.i

  BeginCase("PL01", "Zero frame/exported Reset ownership and Begin allocation contract")
  FillMemory(@frame, Int(SizeOf(PlaneFrame)), 0)
  Check(Bool(PlaneFrameReset(@frame)), "PL01 zeroed caller frame Reset accepted")
  ok = UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024)
  Check(Bool(ok), "PL01 canonical projection/frame Begin succeeds")
  Check(Bool(ok And frame\Allocations = 3 And frame\Records <> 0 And frame\Boards <> 0 And frame\Tables <> 0 And frame\Ready = 1), "PL01 private record/board/table arrays owned exactly three allocations")
  Check(Bool(PlaneFrameReset(@frame)), "PL01 idempotent Reset releases frame")
  Check(Bool(frame\LastPlane = 0 And frame\Records = 0 And frame\Boards = 0 And frame\Tables = 0 And frame\Ready = 0), "PL01 empty reusable state after Reset")
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL02()
  Protected frame.PlaneFrame
  Protected projection.Projection

  BeginCase("PL02", "Invalid/fake Magic frame and missing canonical projection fail safely")
  FillMemory(@frame, Int(SizeOf(PlaneFrame)), 0)
  frame\Magic = $12345678
  Check(Bool(PlaneFrameReset(@frame) = #False And FindString(PlanesLastError(), "unrecognized Magic") > 0), "PL02 fake frame Magic Reset rejected with diagnostic")
  FillMemory(@frame, Int(SizeOf(PlaneFrame)), 0)
  Check(Bool(PlaneFrameReset(@frame)), "PL02 zero frame Reset accepted again")
  Check(Bool(PlaneFrameBegin(@frame, 0, 0, 0, 0, 0, 0) = #False And FindString(PlanesLastError(), "projection") > 0), "PL02 null projection Begin fails with projection diagnostic")
  Check(Bool(frame\Records = 0 And frame\Boards = 0 And frame\Tables = 0 And frame\LastPlane = 0 And frame\Ready = 0), "PL02 failed Begin publishes no partial arrays")
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL03()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected value.l = 0
  Protected sentinelLoop.l = 0
  Protected padMismatch.l = 0
  Protected logicalX.l

  BeginCase("PL03", "320x200 logical limits and top 0xFF/padded bottom sentinels")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL03 frame Begin succeeds")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 128 << #FRACBITS, 41, 192, @planeIndex) = #False
    Check(#False, "PL03 Find creates sentinel plane")
    Goto PL03Done
  EndIf
  padMismatch = 0
  For logicalX = -1 To 320
    If PlaneColumnValue(@frame, planeIndex, logicalX, #True, @value) = #False
      padMismatch + 1
    ElseIf value <> 255
      padMismatch + 1
    EndIf
    If PlaneColumnValue(@frame, planeIndex, logicalX, #False, @value) = #False
      padMismatch + 1
    ElseIf value <> 0
      padMismatch + 1
    EndIf
  Next
  Check(Bool(padMismatch = 0), "PL03 every logical -1..320 top is 0xFF and padded bottom is 0")
  Check(Bool(PlaneColumnValue(@frame, planeIndex, 321, #True, @value) = #False And FindString(PlanesLastError(), "outside the padded") > 0), "PL03 x=321 column access rejected with domain diagnostic")
  Check(Bool(PlaneTopSentinelSet(@frame, planeIndex, -1) And PlaneTopSentinelSet(@frame, planeIndex, 320)), "PL03 minx-1/maxx+1 sentinel setter accepts edges")
  Check(Bool(PlaneColumnValue(@frame, planeIndex, -1, #True, @value) = #True And value = 255 And PlaneColumnValue(@frame, planeIndex, 320, #True, @value) = #True And value = 255), "PL03 edge sentinel cells read 0xFF")
  PL03Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL04()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected height.l = 0
  Protected flatPic.l = 0
  Protected light.l = 0
  Protected sky.l = 0
  Protected minX.l = 0
  Protected maxX.l = 0
  Protected top.l = 0
  Protected bottom.l = 0

  BeginCase("PL04", "R_FindPlane initial 320/-1 empty record plus owned sentinel row pads")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL04 frame Begin succeeds")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, -8 << #FRACBITS, 41, 192, @planeIndex) = #False
    Check(#False, "PL04 floor Find succeeds")
    Goto PL04Done
  EndIf
  Check(Bool(PlaneRecordGet(@frame, planeIndex, @height, @flatPic, @light,
                             @sky, @minX, @maxX)), "PL04 record accessor succeeds")
  Check(Bool(planeIndex = 0 And minX = 320 And maxX = -1 And height = -524288 And flatPic = 41 And light = 192 And sky = 0), "PL04 new record key and minx=320/maxx=-1 empty bounds")
  Check(Bool(PlaneRecordGet(@frame, planeIndex + 1, 0, 0, 0, 0, 0, 0) = #False And FindString(PlanesLastError(), "outside the created range") > 0), "PL04 created range excludes not-yet-created index")
  Check(Bool(PlaneColumnValue(@frame, planeIndex, 320, #True, @top) And PlaneColumnValue(@frame, planeIndex, 320, #False, @bottom) And top = 255 And bottom = 0), "PL04 x=320 pad top/bottom are 0xFF/0")
  PL04Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL05()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected merged.l = 0
  Protected stored.l = 0
  Protected value.l = 0

  BeginCase("PL05", "Invalid output pointers, null frame and visplane cap 1..1024")
  Check(Bool(PlaneFrameBegin(0, 0, 0, 0, 0, 0, 0, 1024) = #False And FindString(PlanesLastError(), "frame pointer is null") > 0), "PL05 null frame Begin rejected")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL05 frame Begin succeeds")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, -8 << #FRACBITS, 41, 192, @planeIndex) = #False
    Check(#False, "PL05 Find creates plane")
    Goto PL05Done
  EndIf
  Check(Bool(PlaneFindPlane(@frame, -8 << #FRACBITS, 41, 192, 0) = #False And FindString(PlanesLastError(), "output pointer is null") > 0), "PL05 null Find output rejected")
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 0, 0, 0, @merged) = #False And FindString(PlanesLastError(), "output pointer is null") > 0), "PL05 null Check outputs rejected")
  Check(Bool(PlaneColumnValue(@frame, planeIndex, 0, #True, 0) = #False And FindString(PlanesLastError(), "output pointer is null") > 0), "PL05 null column output rejected")
  Check(Bool(PlaneMarkCeilingBand(@frame, planeIndex, 0, -1, 200, 4, 0) = #False And FindString(PlanesLastError(), "stored output pointer is null") > 0), "PL05 null mark-stored output rejected")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
  ; Cap contract: 1024 accepted fresh, 0 and 1025 rejected without arrays.
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL05 cap=1024 Begin")
    ProcedureReturn
  EndIf
  Check(Bool(frame\Capacity = 1024 And frame\Allocations = 3), "PL05 cap=1024 exact and arrays owned")
  PlaneFrameReset(@frame)
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 0) = #False And FindString(PlanesLastError(), "visplane cap") > 0
    Check(#True, "PL05 cap=0 rejected with diagnostic")
  Else
    Check(#False, "PL05 cap=0 rejected with diagnostic")
  EndIf
  ProjectionReset(@projection)
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1025) = #False And FindString(PlanesLastError(), "visplane cap") > 0
    Check(#True, "PL05 cap=1025 rejected with diagnostic")
  Else
    Check(#False, "PL05 cap=1025 rejected with diagnostic")
  EndIf
  Check(Bool(frame\Records = 0 And frame\Boards = 0 And frame\Tables = 0), "PL05 rejected cap leaves no partial arrays")
  PL05Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

; ---------------------------------------------------------------------------
; PL06-PL10: FindPlane key/normalization/reuse/flat-0 identity
; ---------------------------------------------------------------------------

Procedure TestPL06()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected first.l = 0
  Protected second.l = 0
  Protected calls.l = 0
  Protected reuse.l = 0
  Protected create.l = 0

  BeginCase("PL06", "FindPlane exact key scan order and reuse counters")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL06 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 128 << #FRACBITS, 41, 192, @first) = #False Or
     PlaneFindPlane(@frame, 128 << #FRACBITS, 41, 192, @second) = #False
    Check(#False, "PL06 two Find calls succeed")
    Goto PL06Done
  EndIf
  Check(Bool(first = 0 And second = 0), "PL06 identical height/flat/light returns same index")
  Check(Bool(PlaneFrameGetStats(@frame, 0, @calls, @reuse, @create, 0, 0, 0, 0,
                                0, 0, 0, 0, 0) = #False Or
              (calls = 2 And reuse = 1 And create = 1)), "PL06 calls=2 reuse=1 create=1")
  PL06Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL07()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected height.l = 0
  Protected flatPic.l = 0
  Protected light.l = 0
  Protected sky.l = 0
  Protected index.l = 0

  BeginCase("PL07", "Sky height/light normalization and all-skys map together")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL07 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 128 << #FRACBITS, 4, 160, @index) = #False Or
     PlaneFindPlane(@frame, 0, 4, 0, @index) = #False
    Check(#False, "PL07 sky finds succeed")
    Goto PL07Done
  EndIf
  If PlaneRecordGet(@frame, index, @height, @flatPic, @light, @sky, 0, 0) = #False
    Check(#False, "PL07 sky record read")
    Goto PL07Done
  EndIf
  Check(Bool(height = 0 And flatPic = 4 And light = 0 And sky = 1), "PL07 sky normalized height0/light0 and sky flag")
  Check(Bool(index = 0 And frame\LastPlane = 1 And frame\SkyVisplanes = 1), "PL07 second sky find reuses the normalized key")
  PL07Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL08()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected first.l = 0
  Protected second.l = 0

  BeginCase("PL08", "Non-sky exact key differences create distinct visplanes")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL08 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @first) = #False Or
     PlaneFindPlane(@frame, 0, 41, 96, @second) = #False
    Check(#False, "PL08 non-sky finds")
    Goto PL08Done
  EndIf
  Check(Bool(first = 0 And second = 1 And second <> first), "PL08 lightlevel change creates a distinct index")
  Check(Bool(frame\FindCalls = 2 And frame\FindReuse = 0 And frame\FindCreate = 2 And frame\LastPlane = 2), "PL08 Find counters distinct creation order")
  PL08Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL09()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected height.l = 0
  Protected flatPic.l = 0
  Protected light.l = 0
  Protected sky.l = 0
  Protected index.l = 0

  BeginCase("PL09", "Legitimate resolved flat index 0 is ordinary, not sky")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL09 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 128 << #FRACBITS, 0, 160, @index) = #False Or
     PlaneRecordGet(@frame, index, @height, @flatPic, @light, @sky, 0, 0) = #False
    Check(#False, "PL09 flat-0 Find/record")
    Goto PL09Done
  EndIf
  Check(Bool(height = 128 << #FRACBITS And light = 160 And flatPic = 0 And sky = 0), "PL09 flat 0 keeps ordinary height/light key")
  Check(Bool(frame\SkyVisplanes = 0), "PL09 flat-0 did not increment sky count")
  PL09Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL10()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected floorPlane.l = 0
  Protected ceilingPlane.l = 0
  Protected floor2.l = 0
  Protected ceiling2.l = 0

  BeginCase("PL10", "R_Subsector reuse across repeated sector entry calls")
  If UBuildSceneWad("u1001.wad", 1) = #False Or
     UPrepareScene("u1001.wad", "E1M1", @pnames, @textures, @flats, @colormap,
                   @level, @view, @projection) = #False
    Check(#False, "PL10 synthetic scene prepared")
    ProcedureReturn
  EndIf
  If PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL10 plane frame Begin")
    Goto PL10Done
  EndIf
  Check(Bool(PlaneSubsectorPrepare(@frame, @level, @flats, 0, 4,
                                   41 << #FRACBITS, @floorPlane, @ceilingPlane) And
              floorPlane = 0 And ceilingPlane = 1), "PL10 sector0 floor/ceiling planes created")
  Check(Bool(PlaneSubsectorPrepare(@frame, @level, @flats, 0, 4,
                                   41 << #FRACBITS, @floor2, @ceiling2) And
              floor2 = 0 And ceiling2 = 1), "PL10 repeated entry reuses identical sector planes")
  Check(Bool(frame\FindCalls = 4 And frame\FindReuse = 2 And frame\FindCreate = 2), "PL10 reuse counters across repeated sector entries")
  PL10Done:
  PlaneFrameReset(@frame)
  UCloseScene(@pnames, @textures, @flats, @colormap, @level, @view, @projection)
EndProcedure

; ---------------------------------------------------------------------------
; PL11-PL15: CheckPlane merge/split boundaries/cap/order
; ---------------------------------------------------------------------------

Procedure TestPL11()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected merged.l = 0
  Protected minX.l = 0
  Protected maxX.l = 0

  BeginCase("PL11", "Disjoint union extends one plane and merge counter")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL11 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False
    Check(#False, "PL11 plane created")
    Goto PL11Done
  EndIf
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 10, 20, @planeIndex, @merged) And
              merged = 1), "PL11 empty minx=320/maxx=-1 start 10..20 merges same plane")
  Check(Bool(PlaneRecordGet(@frame, planeIndex, 0, 0, 0, 0, @minX, @maxX) And
              minX = 10 And maxX = 20), "PL11 merged bounds union exactly 10..20")
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 30, 40, @planeIndex, @merged) And
              merged = 1 And PlaneRecordGet(@frame, planeIndex, 0, 0, 0, 0,
                                            @minX, @maxX) And minX = 10 And maxX = 40),
        "PL11 second disjoint union keeps 10 and extends max to 40")
  PL11Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL12()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected newIndex.l = 0
  Protected merged.l = 0
  Protected height.l = 0
  Protected flatPic.l = 0
  Protected light.l = 0
  Protected sky.l = 0
  Protected minX.l = 0
  Protected maxX.l = 0

  BeginCase("PL12", "Used overlap column splits independent same-key plane")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL12 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False Or
     PlaneCheckPlane(@frame, planeIndex, 10, 20, @planeIndex, @merged) = #False
    Check(#False, "PL12 disjoint initial bounds established")
    Goto PL12Done
  EndIf
  Check(Bool(merged = 1 And PlaneRecordGet(@frame, planeIndex, 0, 0, 0, 0,
                                           @minX, @maxX) And minX = 10 And maxX = 20),
        "PL12 first disjoint union sets old bounds 10..20")
  If PlaneColumnSetBand(@frame, planeIndex, 15, 10, 20) = #False
    Check(#False, "PL12 used band setup")
    Goto PL12Done
  EndIf
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 10, 20, @newIndex, @merged) And
              merged = 0 And newIndex > planeIndex And newIndex = 1),
        "PL12 overlap creates new index 1 rather than extending old")
  If PlaneRecordGet(@frame, newIndex, @height, @flatPic, @light, @sky, @minX, @maxX) = #False
    Check(#False, "PL12 split record read")
    Goto PL12Done
  EndIf
  Check(Bool(height = 0 And flatPic = 41 And light = 192 And sky = 0 And
              minX = 10 And maxX = 20), "PL12 split copy same key and start..stop bounds")
  Check(Bool(PlaneColumnValue(@frame, newIndex, 15, #True, @height) And
              PlaneColumnValue(@frame, planeIndex, 15, #True, @height) And height = 10),
        "PL12 split owns untouched rows while old retains used column")
  PL12Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL13()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected newIndex.l = 0
  Protected merged.l = 0
  Protected minX.l = 0
  Protected maxX.l = 0

  BeginCase("PL13", "Disjoint merge boundaries x=0 and x=319")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL13 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False
    Check(#False, "PL13 plane created")
    Goto PL13Done
  EndIf
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 0, 0, @planeIndex, @merged) And
              merged = 1 And PlaneRecordGet(@frame, planeIndex, 0, 0, 0, 0,
                                            @minX, @maxX) And minX = 0 And maxX = 0),
        "PL13 left boundary 0..0 merges union")
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 319, 319, @planeIndex, @merged) And
              merged = 1 And PlaneRecordGet(@frame, planeIndex, 0, 0, 0, 0,
                                            @minX, @maxX) And minX = 0 And maxX = 319),
        "PL13 right boundary 319..319 extends to full columns")
  PlaneColumnSetBand(@frame, planeIndex, 0, 5, 9)
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 0, 5, @newIndex, @merged) And
              merged = 0 And PlaneRecordGet(@frame, newIndex, 0, 0, 0, 0,
                                            @minX, @maxX) And minX = 0 And maxX = 5),
        "PL13 used x=0 overlap split keeps exact lower boundary")
  PL13Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL14()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected newIndex.l = 0
  Protected merged.l = 0

  BeginCase("PL14", "Required split under cap-1 fails with no partial plane/state")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1) = #False
    Check(#False, "PL14 cap-1 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False Or
     PlaneCheckPlane(@frame, planeIndex, 0, 5, @planeIndex, @merged) = #False
    Check(#False, "PL14 one plane/initial bounds")
    Goto PL14Done
  EndIf
  Check(Bool(merged = 1), "PL14 initial disjoint union sets cap-1 plane bounds")
  If PlaneColumnSetBand(@frame, planeIndex, 3, 10, 20) = #False
    Check(#False, "PL14 used band setup")
    Goto PL14Done
  EndIf
  newIndex = 0
  merged = 0
  Check(Bool(PlaneCheckPlane(@frame, planeIndex, 0, 5, @newIndex, @merged) = #False And
              FindString(PlanesLastError(), "no more visplanes") > 0), "PL14 overlapping split rejects at cap with diagnostic")
  Check(Bool(frame\LastPlane = 1 And frame\CheckSplits = 0 And newIndex = 0 And merged = 0), "PL14 failed split publishes no new plane/split counter")
  PL14Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL15()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected floorPlane.l = 0
  Protected ceilingPlane.l = 0
  Protected otherPlane.l = 0
  Protected splitPlane.l = 0
  Protected merged.l = 0
  Protected creationOrder.l = 0

  BeginCase("PL15", "Creation order is LastPlane chronology; reuse/split interleave")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL15 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @floorPlane) = #False Or
     PlaneFindPlane(@frame, 128 << #FRACBITS, 41, 192, @ceilingPlane) = #False Or
     PlaneFindPlane(@frame, 0, 41, 96, @otherPlane) = #False
    Check(#False, "PL15 three distinct finds")
    Goto PL15Done
  EndIf
  Check(Bool(floorPlane = 0 And ceilingPlane = 1 And otherPlane = 2 And
              frame\LastPlane = 3), "PL15 first three creation indexes monotonic")
  If PlaneColumnSetBand(@frame, floorPlane, 4, 10, 20) = #False
    Check(#False, "PL15 used floor band")
    Goto PL15Done
  EndIf
  If PlaneCheckPlane(@frame, floorPlane, 0, 6, @floorPlane, @merged) = #False Or
     merged <> 1
    Check(#False, "PL15 initial disjoint union sets floor bounds")
    Goto PL15Done
  EndIf
  If PlaneCheckPlane(@frame, floorPlane, 0, 6, @splitPlane, @merged) = #False
    Check(#False, "PL15 split after creation")
    Goto PL15Done
  EndIf
  Check(Bool(splitPlane = 3 And merged = 0 And frame\LastPlane = 4 And
              frame\CheckCalls = 2 And frame\CheckMerges = 1 And frame\CheckSplits = 1), "PL15 split appends creation index 3")
  Check(Bool(PlaneFindPlane(@frame, 128 << #FRACBITS, 41, 192, @ceilingPlane) And
              ceilingPlane = 1 And frame\FindReuse = 1), "PL15 later key scan reuses earlier index")
  PL15Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

; ---------------------------------------------------------------------------
; PL16-PL20: subsector eligibility, chronology context, near/far order
; ---------------------------------------------------------------------------

Procedure TestPL16()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected floorPlane.l = 0
  Protected ceilingPlane.l = 0

  BeginCase("PL16", "Subsector legal floor/ceiling with viewz between both heights")
  If UBuildSceneWad("u1601.wad", 1) = #False Or
     UPrepareScene("u1601.wad", "E1M1", @pnames, @textures, @flats, @colormap,
                   @level, @view, @projection) = #False
    Check(#False, "PL16 synthetic scene prepared")
    ProcedureReturn
  EndIf
  If PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL16 frame Begin")
    Goto PL16Done
  EndIf
  If PlaneSubsectorPrepare(@frame, @level, @flats, 0, 4, 41 << #FRACBITS,
                           @floorPlane, @ceilingPlane) = #False
    Check(#False, "PL16 R_Subsector entry succeeds")
    Goto PL16Done
  EndIf
  Check(Bool(floorPlane = 0), "PL16 floorheight 0 < viewz creates floor plane")
  Check(Bool(ceilingPlane = 1 And ceilingPlane <> floorPlane), "PL16 ceilingheight 128 > viewz creates separate ceiling plane")
  Check(Bool(frame\FindCalls = 2 And frame\FindCreate = 2), "PL16 two eligibility Find calls")
  PL16Done:
  PlaneFrameReset(@frame)
  UCloseScene(@pnames, @textures, @flats, @colormap, @level, @view, @projection)
EndProcedure

Procedure TestPL17()
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected level.MapLevel
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected floorPlane.l = 0
  Protected ceilingPlane.l = 0

  BeginCase("PL17", "Floor above viewz is ineligible while ceiling remains eligible")
  If UBuildResourceOnlyWad("u1701.wad") = #False Or
     UOpenResourceOnlyWad("u1701.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL17 synthetic resource WAD opened")
    ProcedureReturn
  EndIf
  If UBuildDirectRoomMap(@level, 64, 128, "FLOOR1", "CEIL1", 192, 1, 1) = #False
    Check(#False, "PL17 direct valid room map")
    Goto PL17Done
  EndIf
  If ProjectionInitClassic(@projection) = #False
    Check(#False, "PL17 classic projection")
    Goto PL17Done
  EndIf
  If PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL17 frame Begin")
    Goto PL17Done
  EndIf
  If PlaneSubsectorPrepare(@frame, @level, @flats, 0, 4, 41 << #FRACBITS,
                           @floorPlane, @ceilingPlane) = #False
    Check(#False, "PL17 subsector entry succeeds despite floor ineligible")
    Goto PL17Done
  EndIf
  Check(Bool(floorPlane = -1), "PL17 floor 64 >= viewz yields no floor plane")
  Check(Bool(ceilingPlane >= 0), "PL17 ceiling 128 > viewz still creates plane")
  Check(Bool(frame\FindCalls = 1 And frame\FindCreate = 1 And frame\LastPlane = 1), "PL17 only ceiling Find call occurred")
  PL17Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
  MapLevelReset(@level)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@flats)
  ColormapReset(@colormap)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure TestPL18()
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected level.MapLevel
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected floorPlane.l = 0
  Protected ceilingPlane.l = 0

  BeginCase("PL18", "Non-sky ceiling below viewz is ineligible with floor eligible")
  If UBuildResourceOnlyWad("u1801.wad") = #False Or
     UOpenResourceOnlyWad("u1801.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL18 synthetic resource WAD opened")
    ProcedureReturn
  EndIf
  If UBuildDirectRoomMap(@level, 0, 30, "FLOOR1", "CEIL1", 192, 1, 0) = #False
    Check(#False, "PL18 direct valid room map")
    Goto PL18Done
  EndIf
  If ProjectionInitClassic(@projection) = #False
    Check(#False, "PL18 classic projection")
    Goto PL18Done
  EndIf
  If PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL18 frame Begin")
    Goto PL18Done
  EndIf
  If PlaneSubsectorPrepare(@frame, @level, @flats, 0, 4, 41 << #FRACBITS,
                           @floorPlane, @ceilingPlane) = #False
    Check(#False, "PL18 subsector entry succeeds")
    Goto PL18Done
  EndIf
  Check(Bool(floorPlane >= 0), "PL18 floor 0 < viewz creates plane")
  Check(Bool(ceilingPlane = -1), "PL18 non-sky ceiling 30 < viewz yields no plane")
  Check(Bool(frame\FindCalls = 1 And frame\FindCreate = 1), "PL18 only floor Find call occurred")
  PL18Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
  MapLevelReset(@level)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@flats)
  ColormapReset(@colormap)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure TestPL19()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected timeline.WallPlaneTimeline
  Protected floorPlane.l = 0
  Protected ceilingPlane.l = 0
  Protected visits.l = 0
  Protected zeroVisits.l = 0
  Protected events.l = 0
  Protected allocations.l = 0

  BeginCase("PL19", "Zero emitted WallSpans yet valid subsector/plane chronology context")
  If UBuildSceneWad("u1901.wad", 1) = #False Or
     UPrepareScene("u1901.wad", "E1M1", @pnames, @textures, @flats, @colormap,
                   @level, @view, @projection) = #False
    Check(#False, "PL19 synthetic scene prepared")
    ProcedureReturn
  EndIf
  If PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL19 frame Begin")
    Goto PL19Done
  EndIf
  If PlaneSubsectorPrepare(@frame, @level, @flats, 0, 4, 41 << #FRACBITS,
                           @floorPlane, @ceilingPlane) = #False
    Check(#False, "PL19 subsector plane context")
    Goto PL19Done
  EndIf
  If PlaneTimelineBegin(@timeline, 4, 4) = #False
    Check(#False, "PL19 timeline Begin")
    Goto PL19Done
  EndIf
  Check(Bool(PlaneTimelineAddVisit(@timeline, 0, 0, 1, 1, floorPlane, ceilingPlane,
                                   0, 0, 0, 0)), "PL19 wall-free visit had zero segs/spans")
  If PlaneTimelineGetStats(@timeline, @visits, @events, @zeroVisits, 0, 0,
                           0, 0, 0, 0, @allocations) = #False
    Check(#False, "PL19 timeline stats")
    Goto PL19Done
  EndIf
  Check(Bool(visits = 1 And events = 0 And zeroVisits = 1 And allocations = 2), "PL19 zero-span visit counted with no span events")
  Check(Bool(PlaneTimelineIsValid(@timeline)), "PL19 timeline remains valid reusable")
  PL19Done:
  PlaneTimelineReset(@timeline)
  PlaneFrameReset(@frame)
  UCloseScene(@pnames, @textures, @flats, @colormap, @level, @view, @projection)
EndProcedure

Procedure TestPL20()
  Protected summary.URunSummary
  Protected trace.PlaneSpanTrace
  Protected spanCount.l = 0
  Protected index.l
  Protected mismatch.l = 0
  Protected spanField.l
  Protected expected.l
  Protected actual.l
  Protected planeIndex.l = 0
  Protected row.l = 0
  Protected firstX.l = 0
  Protected lastX.l = 0

  BeginCase("PL20", "Near/far online chronology on PI02 sky/portal scene")
  If URunScene("u2002.wad", 2, @summary) = #False
    Check(#False, "PL20 PI02 synthetic combined frame succeeds")
    ProcedureReturn
  EndIf
  Check(Bool(summary\SpanCount = #PLGOLD_PI02_SpanCount And
              summary\TimelineVisits = 1 And
              summary\TimelineEvents = #PLGOLD_PI02_SpanCount),
        "PL20 one wall/plane visitor and event per published ClipSpan")
  Check(Bool(summary\Visplanes = #PLGOLD_PI02_Visplanes And
              summary\FindCalls = #PLGOLD_PI02_FindCalls And
              summary\FindCreate = #PLGOLD_PI02_FindCreate),
        "PL20 subsector Find chronology exact oracle")
  Check(Bool(summary\CheckCalls = #PLGOLD_PI02_CheckCalls And
              summary\CheckMerges = #PLGOLD_PI02_CheckMerges And
              summary\CheckSplits = #PLGOLD_PI02_CheckSplits),
        "PL20 span CheckPlane merge/split chronology exact oracle")
  Check(Bool(summary\SkyVisplanes = #PLGOLD_PI02_SkyVisplanes And
              summary\SkyDeferredBands = #PLGOLD_PI02_SkyBands And
              summary\SkyDeferredPixels = #PLGOLD_PI02_SkyPixels),
        "PL20 sky plane normalized/collected but deferred")
  Check(Bool(summary\PlaneSpans = #PLGOLD_PI02_PlaneSpans And
              summary\PlanePixels = #PLGOLD_PI02_PlanePixels And
              summary\FloorPixels = #PLGOLD_PI02_FloorPixels),
        "PL20 post-wall plane spans/pixels exact oracle")
  Check(Bool(summary\Hash = #PLGOLD_PI02_Hash And summary\ManualHash = #PLGOLD_PI02_Hash), "PL20 combined PI02 FNV exact independent oracle")
EndProcedure

; ---------------------------------------------------------------------------
; PL21-PL25: mark rows before clip mutation, closures, tiers, mark-only, doors
; ---------------------------------------------------------------------------

Procedure TestPL21()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected storedCeil.l = 0
  Protected storedFloor.l = 0
  Protected ceilBands.l = 0
  Protected floorBands.l = 0
  Protected top.l = 0
  Protected bottom.l = 0

  BeginCase("PL21", "MarkCeiling/MarkFloor read pre-column clips and store exact bands")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL21 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False
    Check(#False, "PL21 plane created")
    ProcedureReturn
  EndIf
  Check(Bool(PlaneMarkCeilingBand(@frame, planeIndex, 100, -1, 200, 4, @storedCeil) And
              storedCeil = 1), "PL21 ceiling mark stores a drawable band")
  Check(Bool(PlaneColumnValue(@frame, planeIndex, 100, #True, @top) And
              PlaneColumnValue(@frame, planeIndex, 100, #False, @bottom) And
              top = 0 And bottom = 3), "PL21 ceiling top=clip+1/bottom=yl-1 exact")
  Check(Bool(PlaneMarkFloorBand(@frame, planeIndex, 100, -1, 200, 150, @storedFloor) And
              storedFloor = 1), "PL21 floor mark stores a drawable band")
  Check(Bool(PlaneColumnValue(@frame, planeIndex, 100, #True, @top) And
              PlaneColumnValue(@frame, planeIndex, 100, #False, @bottom) And
              top = 151 And bottom = 199), "PL21 floor top=yh+1/bottom=floorclip-1 exact")
  Check(Bool(PlaneFrameGetStats(@frame, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                @ceilBands, @floorBands, 0, 0) = #False Or
              (ceilBands = 1 And floorBands = 1)), "PL21 stored-band counters grow once")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL22()
  Protected summary.URunSummary

  BeginCase("PL22", "One-sided middle closure in PI01 keeps marks/counters exact")
  If URunScene("u2201.wad", 1, @summary) = #False
    Check(#False, "PL22 PI01 combined frame succeeds")
    ProcedureReturn
  EndIf
  Check(Bool(summary\MarkCeilingCalls = #PLGOLD_PI01_MarkCeilingColumns And
              summary\MarkCeilingBands = #PLGOLD_PI01_MarkCeilingBands),
        "PL22 PI01 one-sided ceiling marks stored exactly oracle")
  Check(Bool(summary\MarkFloorCalls = #PLGOLD_PI01_MarkFloorColumns And
              summary\MarkFloorBands = #PLGOLD_PI01_MarkFloorBands),
        "PL22 PI01 one-sided floor marks stored exactly oracle")
  Check(Bool(summary\PopulatedVisplanes = #PLGOLD_PI01_PopulatedVisplanes And
              summary\EmptyVisplanes = #PLGOLD_PI01_EmptyVisplanes),
        "PL22 PI01 one-sided closure leaves empty/populated split exact oracle")
EndProcedure

Procedure TestPL23()
  Protected summary.URunSummary

  BeginCase("PL23", "Two-sided upper/lower tiers and sky-plane mark bands")
  If URunScene("u2302.wad", 2, @summary) = #False
    Check(#False, "PL23 PI02 combined frame succeeds")
    ProcedureReturn
  EndIf
  Check(Bool(summary\MarkCeilingCalls = #PLGOLD_PI02_MarkCeilingColumns And
              summary\MarkCeilingBands = #PLGOLD_PI02_MarkCeilingBands),
        "PL23 two-sided upper-tier ceiling bands/marks exact oracle")
  Check(Bool(summary\MarkFloorCalls = #PLGOLD_PI02_MarkFloorColumns And
              summary\MarkFloorBands = #PLGOLD_PI02_MarkFloorBands),
        "PL23 two-sided lower-tier floor bands/marks exact oracle")
  Check(Bool(summary\WallDrawnPixels = #PLGOLD_PI02_WallDrawnPixels And
              summary\WallCoveredPixels = #PLGOLD_PI02_WallDrawnPixels),
        "PL23 upper/lower painted wall coverage remains disjoint/exact")
EndProcedure

Procedure TestPL24()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected stored.l = 0

  BeginCase("PL24", "Mark-only non-drawable branches store nothing but count calls")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL24 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False
    Check(#False, "PL24 plane created")
    ProcedureReturn
  EndIf
  Check(Bool(PlaneMarkCeilingBand(@frame, planeIndex, 50, -1, 0, 1, @stored) And
              stored = 0), "PL24 ceiling bottom clamped below top stores no band")
  Check(Bool(PlaneMarkFloorBand(@frame, planeIndex, 50, 10, 10, 5, @stored) And
              stored = 0), "PL24 floor clamped top > bottom stores no band")
  Check(Bool(PlaneMarkCeilingBand(@frame, planeIndex, 50, 201, 200, 4, @stored) = #False And
              FindString(PlanesLastError(), "outside -1..200") > 0),
        "PL24 out-of-domain clip value explicitly rejected")
  Check(Bool(frame\MarkCeilingCalls = 1 And frame\MarkFloorCalls = 1 And
              frame\MarkCeilingBands = 0 And frame\MarkFloorBands = 0),
        "PL24 valid mark calls counted, zero stored bands")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL25()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected storedCeil.l = 0
  Protected storedFloor.l = 0

  BeginCase("PL25", "Closed-door full middle closure marks both faces but stores no bands")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False
    Check(#False, "PL25 frame Begin")
    ProcedureReturn
  EndIf
  If PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False
    Check(#False, "PL25 closed-face plane created")
    ProcedureReturn
  EndIf
  Check(Bool(PlaneMarkCeilingBand(@frame, planeIndex, 100, -1, 200, 0, @storedCeil) And
              storedCeil = 0), "PL25 closed ceiling yl=0 clamped to no band")
  Check(Bool(PlaneMarkFloorBand(@frame, planeIndex, 100, -1, 200, 199, @storedFloor) And
              storedFloor = 0), "PL25 closed floor top=200 exceeds floorclip-1, no band")
  Check(Bool(frame\MarkCeilingCalls = 1 And frame\MarkFloorCalls = 1 And
              frame\MarkCeilingBands = 0 And frame\MarkFloorBands = 0),
        "PL25 closed-door marks executed with no stored rows")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

; ---------------------------------------------------------------------------
; PL26-PL30: R_MakeSpans adjacent open/close/merge/edges/sentinel guards
; ---------------------------------------------------------------------------

Procedure TestPL26()
  Protected summary.URunSummary
  Protected trace.PlaneSpanTrace
  Protected spanCount.l = 0
  Protected spanIndex.l
  Protected fieldIndex.l
  Protected expected.l = 0
  Protected actual.l = 0
  Protected mismatch.l = 0
  Protected planeIndex.l = 0
  Protected row.l = 0
  Protected firstX.l = 0
  Protected lastX.l = 0
  Protected pixels.l = 0

  BeginCase("PL26", "Actual R_MakeSpans closing/opening sequence via bounded trace")
  PlaneSpanTraceReset(@trace)
  If PlaneSpanTraceBegin(@trace, 1024) = #False
    Check(#False, "PL26 trace Begin")
    ProcedureReturn
  EndIf
  If URunScene("u2601.wad", 1, @summary, @trace) = #False
    Check(#False, "PL26 PI01 trace/combined frame succeeds")
    Goto PL26Done
  EndIf
  spanCount = trace\SpanCount
  Check(Bool(spanCount = #PLGOLD_PI01_PlaneSpans And
              summary\PlaneSpans = #PLGOLD_PI01_PlaneSpans), "PL26 trace captures every drawn plane span")
  Check(Bool(summary\OpenedRows = #PLGOLD_PI01_OpenedRows And
              summary\ClosedRows = #PLGOLD_PI01_ClosedRows), "PL26 open/close row counters exact oracle")
  mismatch = 0
  For spanIndex = 0 To spanCount - 1
    actual = 0
    If PlaneSpanTraceGetSpan(@trace, spanIndex, @planeIndex, @row,
                             @firstX, @lastX, 0, 0, 0, 0, 0, 0, 0, 0,
                             @pixels, 0) = #False
      mismatch + 1
    Else
      For fieldIndex = 0 To 3
        expected = PeekL(*gPI01PlaneSpans + Int(spanIndex) * #PLGOLD_PlaneSpanFieldCount * 4 +
                         Int(fieldIndex) * 4)
        Select fieldIndex
          Case 0 : actual = planeIndex
          Case 1 : actual = row
          Case 2 : actual = firstX
          Case 3 : actual = lastX
        EndSelect
        If actual <> expected
          mismatch + 1
        EndIf
      Next
      expected = PeekL(*gPI01PlaneSpans + Int(spanIndex) * #PLGOLD_PlaneSpanFieldCount * 4 +
                       Int(12) * 4)
      If pixels <> expected
        mismatch + 1
      EndIf
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL26 trace plane/row/column/pixel chronology exact oracle")
  PL26Done:
  PlaneSpanTraceReset(@trace)
EndProcedure

Procedure TestPL27()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected tally.PlaneDrawTally
  Protected context.PlaneDrawContext

  BeginCase("PL27", "Adjacent open/close and same-row merge from R_MakeSpans")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1) = #False Or
     PlaneDrawTallyReset(@tally) = #False
    Check(#False, "PL27 frame/tally setup")
    ProcedureReturn
  EndIf
  FillMemory(@context, Int(SizeOf(PlaneDrawContext)), 0)
  context\Magic = #PLANE_DRAW_ContextMagic
  context\Frame = @frame
  context\Tally = @tally
  If PlaneMakeSpans(@context, 5, 255, 0, 0, 0) = #False
    Check(#False, "PL27 top opening finds a new row span start")
    Goto PL27Done
  EndIf
  Check(Bool(tally\OpenedRows = 1 And tally\PlaneSpans = 0 And tally\PlanePixels = 0),
        "PL27 opening stores start x but draws no closed span")
  Check(Bool(PeekL(frame\SpanStart + 0 * SizeOf(Long)) = 5), "PL27 spanstart[0]=opening column")
  If PlaneMakeSpans(@context, 6, 0, 0, 0, 0) = #False
    Check(#False, "PL27 same top/bottom values no-op succeeds")
    Goto PL27Done
  EndIf
  Check(Bool(tally\OpenedRows = 1 And tally\ClosedRows = 0 And tally\PlaneSpans = 0),
        "PL27 same-row merge emits no duplicate open/close")
  PL27Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL28()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected tally.PlaneDrawTally
  Protected context.PlaneDrawContext

  BeginCase("PL28", "Top/bottom edge rows open at x=0 with minx-1 sentinel values")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1) = #False Or
     PlaneDrawTallyReset(@tally) = #False
    Check(#False, "PL28 frame/tally setup")
    ProcedureReturn
  EndIf
  FillMemory(@context, Int(SizeOf(PlaneDrawContext)), 0)
  context\Magic = #PLANE_DRAW_ContextMagic
  context\Frame = @frame
  context\Tally = @tally
  If PlaneMakeSpans(@context, 0, 255, 0, 0, 1) = #False
    Check(#False, "PL28 edge opening spans succeed")
    Goto PL28Done
  EndIf
  Check(Bool(tally\OpenedRows = 2 And tally\ClosedRows = 0), "PL28 top and bottom edge rows both open")
  Check(Bool(PeekL(frame\SpanStart + 0 * SizeOf(Long)) = 0 And
              PeekL(frame\SpanStart + 1 * SizeOf(Long)) = 0),
        "PL28 spanstart rows 0 and 1 at opening column 0")
  PL28Done:
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL29()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected tally.PlaneDrawTally
  Protected context.PlaneDrawContext
  Protected planeIndex.l = 0
  Protected value.l = 0

  BeginCase("PL29", "maxx+1/minx-1 sentinel writes and x=320 opening guard")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1024) = #False Or
     PlaneDrawTallyReset(@tally) = #False Or
     PlaneFindPlane(@frame, 0, 41, 192, @planeIndex) = #False
    Check(#False, "PL29 frame/tally/plane setup")
    ProcedureReturn
  EndIf
  Check(Bool(PlaneTopSentinelSet(@frame, planeIndex, 319 + 1) And
              PlaneTopSentinelSet(@frame, planeIndex, 0 - 1)), "PL29 maxx+1 and minx-1 sentinels set")
  Check(Bool(PlaneColumnValue(@frame, planeIndex, 320, #True, @value) And value = 255 And
              PlaneColumnValue(@frame, planeIndex, 0 - 1, #True, @value) And value = 255),
        "PL29 sentinel cells at logical 320 and -1 read 0xFF")
  FillMemory(@context, Int(SizeOf(PlaneDrawContext)), 0)
  context\Magic = #PLANE_DRAW_ContextMagic
  context\Frame = @frame
  context\Tally = @tally
  Check(Bool(PlaneMakeSpans(@context, 320, 255, 0, 0, 0) = #False And
              FindString(PlaneDrawLastError(), "opening span start") > 0),
        "PL29 opening at x=320 fails outside drawable 0..319")
  Check(Bool(tally\OpenedRows = 0 And tally\PlaneSpans = 0 And tally\ClosedRows = 0),
        "PL29 guard failure leaves counters untouched")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL30()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected tally.PlaneDrawTally
  Protected context.PlaneDrawContext
  Protected opened.l = 0
  Protected spans.l = 0

  BeginCase("PL30", "Empty/duplicate adjacent bands and invalid rows explicit failure")
  If UPlaneFrameBegin(@frame, @projection, 41 << #FRACBITS, 4, 1) = #False Or
     PlaneDrawTallyReset(@tally) = #False
    Check(#False, "PL30 frame/tally setup")
    ProcedureReturn
  EndIf
  FillMemory(@context, Int(SizeOf(PlaneDrawContext)), 0)
  context\Magic = #PLANE_DRAW_ContextMagic
  context\Frame = @frame
  context\Tally = @tally
  Check(Bool(PlaneMakeSpans(@context, 5, 10, 12, 10, 12) And
              tally\OpenedRows = 0 And tally\ClosedRows = 0 And tally\PlaneSpans = 0),
        "PL30 identical open bands merge with zero rows/spans")
  Check(Bool(PlaneMakeSpans(@context, 6, 200, 220, 220, 220) = #False And
              FindString(PlaneDrawLastError(), "adjacent top/bottom values are outside the guarded bands") > 0),
        "PL30 out-of-band adjacent rows explicit guard diagnostic")
  Check(Bool(PlaneMakeSpans(@context, 321, 255, 0, 0, 0) = #False And
              FindString(PlaneDrawLastError(), "outside the padded logical domain") > 0),
        "PL30 x=321 beyond 0..320 explicit failure")
  Check(Bool(tally\OpenedRows = 0 And tally\ClosedRows = 0 And tally\PlaneSpans = 0),
        "PL30 failures never publish partial span counters")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

; ---------------------------------------------------------------------------
; PL31-PL35: yslope/distscale/base scales/heading/BAM boundaries
; ---------------------------------------------------------------------------

Procedure TestPL31()
  Protected rowsY.l
  Protected row.l
  Protected expected.l = 0
  Protected actual.l = 0
  Protected mismatch.l = 0
  Protected halfPixel.l = 0

  BeginCase("PL31", "yslope half-pixel horizon and all row values from oracle")
  For row = 0 To 199
    expected = PeekL(*gYSlopes + Int(row) * SizeOf(Long))
    If PlaneYSlopeValue(row, #PROJ_CENTERXFIXED, #PROJ_VIEWWIDTH, @actual) = #False
      mismatch + 1
    ElseIf actual <> expected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL31 all 200 yslope rows exact independent oracle")
  If PlaneYSlopeValue(100, #PROJ_CENTERXFIXED, #PROJ_VIEWWIDTH, @halfPixel) = #False
    Check(#False, "PL31 row-100 half-pixel horizon")
  Else
    Check(Bool(halfPixel = 320 << #FRACBITS And halfPixel = PeekL(*gYSlopes + 100 * SizeOf(Long))),
          "PL31 row 100 dy=(0<<16)+FRACUNIT/2 yslope=320<<16")
  EndIf
  Check(Bool(PlaneYSlopeValue(200, #PROJ_CENTERXFIXED, 320, @actual) = #False And
              FindString(PlaneMappingLastError(), "outside 0..199") > 0),
        "PL31 row=200 outside canonical yslope domain")
EndProcedure

Procedure TestPL32()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected screenX.l
  Protected expected.l = 0
  Protected actual.l = 0
  Protected mismatch.l = 0
  Protected cosAdj.l = 0
  Protected scale.l = 0
  Protected rawAngle.q = 0

  BeginCase("PL32", "distscale cosadj/FixedDiv table exact oracle and direct angle")
  If ProjectionInitClassic(@projection) = #False Or
     PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4,
                     1024) = #False
    Check(#False, "PL32 projection/frame preparation")
    ProjectionReset(@projection)
    ProcedureReturn
  EndIf
  mismatch = 0
  For screenX = 0 To 319
    expected = PeekL(*gDistScales + Int(screenX) * SizeOf(Long))
    actual = PeekL(frame\DistScale + Int(screenX) * SizeOf(Long))
    If actual <> expected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL32 full 320-column frame distscale table exact oracle")
  rawAngle = PeekQ(frame\XToViewAngle)
  Check(Bool(PlaneDistScaleFromAngle(rawAngle, @cosAdj, @scale)), "PL32 direct distscale from x=0 raw xtoviewangle")
  Check(Bool(scale = PeekL(frame\DistScale)), "PL32 direct angle scale equals frame x=0 entry")
  Check(Bool(PlaneDistScaleTableFromRaw(frame\XToViewAngle, 320, frame\DistScale)),
        "PL32 checked 320-column table rebuild accepted")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL33()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected headings.l = 0
  Protected heading.q = 0
  Protected xScale.l = 0
  Protected yScale.l = 0
  Protected expectedX.l = 0
  Protected expectedY.l = 0
  Protected cosine.l = 0
  Protected sine.l = 0
  Protected fine.l
  Protected mismatch.l = 0

  BeginCase("PL33", "basex/baseyscale heading quadrants and zero-heading oracle")
  If ProjectionInitClassic(@projection) = #False Or
     PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4,
                     1024) = #False
    Check(#False, "PL33 heading0 frame")
    ProjectionReset(@projection)
    ProcedureReturn
  EndIf
  Check(Bool(frame\BaseXScale = #PLGOLD_BaseXScale And frame\BaseYScale = #PLGOLD_BaseYScale),
        "PL33 heading 0 base scales exact independent oracle")
  mismatch = 0
  For headings = 0 To 3
    heading = Int(headings) * #BAM_ANG90
    If PlaneBaseScaleFromHeading(heading, #PROJ_CENTERXFIXED, @xScale, @yScale) = #False
      mismatch + 1
    Else
      fine = Int(BamFineIndex(BamSubtract(heading, #BAM_ANG90)))
      If TrigCosineChecked(fine, @cosine) = #False Or TrigSineChecked(fine, @sine) = #False
        mismatch + 1
      Else
        expectedX = FixedDiv(cosine, #PROJ_CENTERXFIXED)
        expectedY = -FixedDiv(sine, #PROJ_CENTERXFIXED)
        If xScale <> expectedX Or yScale <> expectedY
          mismatch + 1
        EndIf
      EndIf
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL33 quadrants 0/90/180/270 exact source formula")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL34()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected xScale.l = 0
  Protected yScale.l = 0

  BeginCase("PL34", "signed/unsigned raw BAM boundaries reject only outside domain")
  Check(Bool(PlaneBaseScaleFromHeading(4294967296, #PROJ_CENTERXFIXED,
                                       @xScale, @yScale) = #False And
              FindString(PlaneMappingLastError(), "outside the raw unsigned BAM") > 0),
        "PL34 heading 2^32 rejects explicit unsigned-domain diagnostic")
  Check(Bool(PlaneBaseScaleFromHeading(4294967295, #PROJ_CENTERXFIXED,
                                       @xScale, @yScale)), "PL34 heading 2^32-1 accepted raw BAM edge")
  If ProjectionInitClassic(@projection) = #False
    Check(#False, "PL34 projection preparation")
    ProcedureReturn
  EndIf
  Check(Bool(PlaneFrameBegin(@frame, @projection, 0, 0, 4294967296, 0, 4, 1) = #False And
              FindString(PlanesLastError(), "outside the raw unsigned BAM") > 0),
        "PL34 frame Begin rejects wrapping heading 2^32")
  Check(Bool(frame\Ready = 0 And frame\Records = 0), "PL34 rejected heading leaves no partial frame")
  Check(Bool(PlaneFrameBegin(@frame, @projection, 0, 0, 4294967295, 0, 4, 1)), "PL34 frame Begin accepts raw BAM max edge")
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
EndProcedure

Procedure TestPL35()
  Protected xScale.l = 0
  Protected yScale.l = 0
  Protected x.l = 0
  Protected y.l = 0
  Protected expectedCos.l = 0
  Protected expectedScale.l = 0
  Protected fine.l
  Protected cosine.l = 0
  Protected magnitude.q
  Protected actualCos.l = 0
  Protected actualScale.l = 0

  BeginCase("PL35", "distscale zero-magnitude/saturation edge and unsigned raw entry")
  If PlaneDistScaleFromAngle(#BAM_ANG90, @actualCos, @actualScale) = #False
    Check(#False, "PL35 ANG90 distscale edge succeeds")
    ProcedureReturn
  EndIf
  fine = Int(BamFineIndex(#BAM_ANG90))
  If TrigCosineChecked(fine, @cosine) = #False
    Check(#False, "PL35 cosine reference")
    ProcedureReturn
  EndIf
  magnitude = Int(cosine)
  If magnitude < 0
    magnitude = -magnitude
  EndIf
  expectedCos = FixedWrap32Low(magnitude)
  If magnitude = 0
    expectedScale = #FIXED_MAX
  Else
    expectedScale = FixedDiv(#FRACUNIT, FixedWrap32Low(magnitude))
  EndIf
  Check(Bool(actualCos = expectedCos And actualScale = expectedScale),
        "PL35 ANG90 cosadj/scale exact FixedDiv saturation formula")
  Check(Bool(PlaneDistScaleFromAngle(4294967296, @actualCos, @actualScale) = #False And
              FindString(PlaneMappingLastError(), "raw unsigned BAM") > 0),
        "PL35 raw angle 2^32 explicitly rejected")
EndProcedure

; ---------------------------------------------------------------------------
; PL36-PL40: R_MapPlane planeheight/row cache/x-y/step/row bounds
; ---------------------------------------------------------------------------

Procedure.i UPrepareMapRowFixture(*Frame.PlaneFrame, *Projection.Projection,
                                 *Flats.FlatCatalog, *Colormap.ColormapSet,
                                 *ZTable.PlaneZLightTable,
                                 *Textures.TextureCatalog,
                                 *Pnames.PNamesTable, FileName.s)
  If UBuildResourceOnlyWad(FileName) = #False Or
     UOpenResourceOnlyWad(FileName, *Flats, *Colormap, *Textures,
                          *Pnames) = #False
    ProcedureReturn #False
  EndIf
  If ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  If PlaneFrameBegin(*Frame, *Projection, 0, 0, 0, 41 << #FRACBITS, -1,
                     1024) = #False
    ProcedureReturn #False
  EndIf
  If PlaneZLightTableBuild(*ZTable, *Colormap) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure UReleaseMapRowFixture(*Frame.PlaneFrame, *Projection.Projection,
                                *Flats.FlatCatalog, *Colormap.ColormapSet,
                                *ZTable.PlaneZLightTable,
                                *Textures.TextureCatalog,
                                *Pnames.PNamesTable)
  PlaneZLightTableReset(*ZTable)
  PlaneFrameReset(*Frame)
  ProjectionReset(*Projection)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  TextureCatalogReset(*Textures)
  PNamesReset(*Pnames)
EndProcedure

Procedure TestPL36()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected params.PlaneMapParams
  Protected sampleIndex.l
  Protected planeHeight.l = 0
  Protected row.l = 0
  Protected firstX.l = 0
  Protected lightNum.l = 0
  Protected distance.l = 0
  Protected expectedDistance.l = 0
  Protected xStep.l = 0
  Protected yStep.l = 0
  Protected mismatch.l = 0
  Protected sampleCount.l = #PLGOLD_MapPlaneSampleCount

  BeginCase("PL36", "R_MapPlane planeheight/distance/xstep/ystep and row cache")
  If UPrepareMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                           @textures, @pnames, "u3601.wad") = #False
    Check(#False, "PL36 resource plane mapping fixture prepared")
    Goto PL36Done
  EndIf
  mismatch = 0
  For sampleIndex = 0 To sampleCount - 1
    planeHeight = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 0 * 4)
    row = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 1 * 4)
    firstX = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 2 * 4)
    distance = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 3 * 4)
    xStep = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 4 * 4)
    yStep = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 5 * 4)
    lightNum = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 8 * 4)
    If PlaneMapRowParameters(@frame, @zlight, planeHeight, row, firstX,
                             lightNum, @params) = #False
      mismatch + 1
    ElseIf params\PlaneHeight <> planeHeight Or params\Distance <> distance Or
           params\XStep <> xStep Or params\YStep <> yStep
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL36 all 10 sample planeheight/distance/steps exact oracle")
  firstX = PeekL(*gMapPlaneSample + 2 * 4)
  row = PeekL(*gMapPlaneSample + 1 * 4)
  planeHeight = PeekL(*gMapPlaneSample + 0 * 4)
  If PlaneMapRowParameters(@frame, @zlight, 87 << #FRACBITS, row,
                           PeekL(*gMapPlaneSample + 9 * 10 * 4 + 2 * 4), 10,
                           @params) = #False
    Check(#False, "PL36 repeated row cache lookup")
  Else
    expectedDistance = PeekL(*gMapPlaneSample + 9 * 10 * 4 + 3 * 4)
    Check(Bool(params\CacheHit = 1 And params\Distance = expectedDistance),
          "PL36 same planeheight/row second lookup is cache hit with same distance")
  EndIf
  If PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, row,
                           PeekL(*gMapPlaneSample + 9 * 10 * 4 + 2 * 4), 10,
                           @params) = #False
    Check(#False, "PL36 changed-height row cache probe")
  Else
    Check(Bool(params\CacheHit = 0 And params\PlaneHeight = 41 << #FRACBITS),
          "PL36 changed planeheight recomputes row cache miss")
  EndIf
  PL36Done:
  UReleaseMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                        @textures, @pnames)
EndProcedure

Procedure TestPL37()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected params.PlaneMapParams
  Protected sampleIndex.l
  Protected planeHeight.l = 0
  Protected row.l = 0
  Protected firstX.l = 0
  Protected lightNum.l = 0
  Protected xFrac.l = 0
  Protected yFrac.l = 0
  Protected mapIndex.l = 0
  Protected expectedX.l = 0
  Protected expectedY.l = 0
  Protected expectedLight.l = 0
  Protected expectedMap.l = 0
  Protected mismatch.l = 0
  Protected sampleCount.l = #PLGOLD_MapPlaneSampleCount

  BeginCase("PL37", "R_MapPlane x/y coordinates/light/map index exact oracle")
  If UPrepareMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                           @textures, @pnames, "u3701.wad") = #False
    Check(#False, "PL37 resource plane mapping fixture prepared")
    Goto PL37Done
  EndIf
  mismatch = 0
  For sampleIndex = 0 To sampleCount - 1
    planeHeight = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 0 * 4)
    row = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 1 * 4)
    firstX = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 2 * 4)
    lightNum = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 8 * 4)
    expectedX = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 6 * 4)
    expectedY = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 7 * 4)
    expectedMap = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 9 * 4)
    If PlaneMapRowParameters(@frame, @zlight, planeHeight, row, firstX,
                             lightNum, @params) = #False
      mismatch + 1
    ElseIf params\XFrac <> expectedX Or params\YFrac <> expectedY Or
           params\LightNum <> lightNum Or params\MapIndex <> expectedMap
      mismatch + 1
    EndIf
    If params\XFrac <> expectedX Or params\YFrac <> expectedY
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL37 XFrac/YFrac/cos-sine/viewx-viewy exact oracle")
  If PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 199, 319, 10,
                           @params) = #False
    Check(#False, "PL37 row199/column319 coordinate sample")
  Else
    expectedX = PeekL(*gMapPlaneSample + 3 * 10 * 4 + 6 * 4)
    Check(Bool(params\XFrac = expectedX), "PL37 row199/column319 coordinate sample exact oracle")
  EndIf
  PL37Done:
  UReleaseMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                        @textures, @pnames)
EndProcedure

Procedure TestPL38()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected params.PlaneMapParams
  Protected magnitude.l = 0

  BeginCase("PL38", "16.16 overflow/rejected planeheight/rows/columns/light rows")
  Check(Bool(PlaneHeightChecked(-2147483648, 0, @magnitude) = #False And
              FindString(PlaneMappingLastError(), "abs(INT32_MIN)") > 0),
        "PL38 INT_MIN abs undefined edge explicitly rejected")
  Check(Bool(PlaneHeightChecked(-2147483647, 1, @magnitude) = #False And
              FindString(PlaneMappingLastError(), "undefined edge") > 0),
        "PL38 widening difference equal INT32_MIN abs edge rejected")
  Check(Bool(PlaneHeightChecked(0, 41 << #FRACBITS, @magnitude) And
              magnitude = 41 << #FRACBITS), "PL38 exact abs(height-viewz)=41<<16")
  If UPrepareMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                           @textures, @pnames, "u3801.wad") = #False
    Check(#False, "PL38 mapping fixture prepared")
    Goto PL38Done
  EndIf
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, -1, 0, 0, 10, @params) = #False And
              FindString(PlaneDrawLastError(), "planeheight is negative") > 0),
        "PL38 negative planeheight row mapping rejected")
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 200, 0, 10,
                                   @params) = #False And
              FindString(PlaneDrawLastError(), "outside 0..199") > 0),
        "PL38 row=200 destination domain rejected")
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 0, 320, 10,
                                   @params) = #False And
              FindString(PlaneDrawLastError(), "outside 0..319") > 0),
        "PL38 first column=320 rejected")
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 0, 0, 16,
                                   @params) = #False And
              FindString(PlaneDrawLastError(), "outside 0..15") > 0),
        "PL38 light row=16 zlight domain rejected")
  PL38Done:
  UReleaseMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                        @textures, @pnames)
EndProcedure

Procedure TestPL39()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected params.PlaneMapParams
  Protected sampleIndex.l
  Protected expectedDistance.l = 0
  Protected expectedXStep.l = 0
  Protected expectedYStep.l = 0
  Protected mismatch.l = 0
  Protected sampleCount.l = #PLGOLD_MapPlaneSampleCount

  BeginCase("PL39", "step arithmetic FixedMul(distance,base) and row-cache step order")
  If UPrepareMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                           @textures, @pnames, "u3901.wad") = #False
    Check(#False, "PL39 mapping fixture prepared")
    Goto PL39Done
  EndIf
  mismatch = 0
  For sampleIndex = 0 To sampleCount - 1
    expectedDistance = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 3 * 4)
    expectedXStep = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 4 * 4)
    expectedYStep = PeekL(*gMapPlaneSample + Int(sampleIndex) * 10 * 4 + 5 * 4)
    If expectedXStep <> FixedMul(expectedDistance, frame\BaseXScale)
      mismatch + 1
    EndIf
    If expectedYStep <> FixedMul(expectedDistance, frame\BaseYScale)
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL39 every oracle xstep/ystep equals FixedMul(distance,base)")
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 0, 0, 10,
                                   @params) And
              params\XStep = PeekL(*gMapPlaneSample + 0 + 4 * 4) And
              params\YStep = PeekL(*gMapPlaneSample + 5 * 4)),
        "PL39 first row step order computed distance then xstep/ystep")
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 0, 5, 10,
                                   @params) And
                                   PeekL(*gMapPlaneSample + 3 * 4) = params\Distance), "PL39 row cache carries stored distance")
  PL39Done:
  UReleaseMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                        @textures, @pnames)
EndProcedure

Procedure TestPL40()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected params.PlaneMapParams
  Protected row.l
  Protected mismatch.l = 0
  Protected planeSpanIndex.l
  Protected planeSpanRow.l = 0
  Protected pixelOffset.q = 0

  BeginCase("PL40", "row=199/319 coordinate edge and row wrap/destination bounds")
  If UPrepareMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                           @textures, @pnames, "u4001.wad") = #False
    Check(#False, "PL40 mapping fixture prepared")
    Goto PL40Done
  EndIf
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 199, 319,
                                   10, @params)), "PL40 row199/column319 accepted")
  pixelOffset = Int(199) * Int(#PLANE_DRAW_ViewWidth) + Int(319)
  Check(Bool(pixelOffset >= 0 And pixelOffset = Int(#PLANE_DRAW_PixelCount) - 1),
        "PL40 row199+319 destination offset is final 64,000th cell")
  mismatch = 0
  For planeSpanIndex = 0 To #PLGOLD_PI01_PlaneSpans - 1
    planeSpanRow = PeekL(*gPI01PlaneSpans + Int(planeSpanIndex) * #PLGOLD_PlaneSpanFieldCount * 4 + 1 * 4)
    If planeSpanRow < 0 Or planeSpanRow > 199
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL40 every oracle plane span row remains 0..199")
  Check(Bool(PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 200, 0, 10,
                                   @params) = #False), "PL40 row=200 destination bound rejected")
  PL40Done:
  UReleaseMapRowFixture(@frame, @projection, @flats, @colormap, @zlight,
                        @textures, @pnames)
EndProcedure

; ---------------------------------------------------------------------------
; PL41-PL45: spot formula, negative wrap, palette 0/255, span/row bounds
; ---------------------------------------------------------------------------

Procedure TestPL41()
  Protected expectedSpot.l
  Protected actualSpot.l
  Protected inputCount.l = 6
  Protected spotCase.l
  Protected mismatch.l = 0
  Protected reference.l = 0

  BeginCase("PL41", "64x64 flat spot bit formula exact independent oracle")
  For spotCase = 0 To inputCount - 1
    expectedSpot = PeekL(*gSpotValues + Int(spotCase) * SizeOf(Long))
    Select spotCase
      Case 0 : actualSpot = UReferenceSpot(0, 0)
      Case 1 : actualSpot = UReferenceSpot(#FRACUNIT, 0)
      Case 2 : actualSpot = UReferenceSpot(0, #FRACUNIT)
      Case 3 : actualSpot = UReferenceSpot(54 << #FRACBITS, 29 << #FRACBITS)
      Case 4 : actualSpot = UReferenceSpot(-#FRACUNIT, -#FRACUNIT)
      Case 5 : actualSpot = UReferenceSpot((64 << #FRACBITS) - 1, (63 << 10) - 1)
    EndSelect
    If actualSpot <> expectedSpot
      mismatch + 1
    EndIf
    If actualSpot < 0 Or actualSpot > #FLAT_ByteSize - 1
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL41 all six spot cases exact oracle and inside 0..4095")
  Check(Bool(#PLANE_DRAW_SpotMaskY = 63 * 64 And #PLANE_DRAW_SpotMaskX = 63),
        "PL41 spot masks 4032/63 mirror r_draw.c constants")
EndProcedure

Procedure TestPL42()
  Protected xfrac.l
  Protected yfrac.l
  Protected actual.l = 0
  Protected expected.l = 0
  Protected mismatch.l = 0

  BeginCase("PL42", "Negative/edge fixed x/y wrap maps to ordinary flat spot bits")
  xfrac = -#FRACUNIT
  yfrac = -#FRACUNIT
  expected = PeekL(*gSpotValues + 4 * SizeOf(Long))
  actual = UReferenceSpot(xfrac, yfrac)
  Check(Bool(actual = expected And actual >= 0 And actual <= 4095),
        "PL42 negative ffrac x/y wrap spot inside flat and exact oracle")
  mismatch = 0
  For xfrac = -3 To 3
    yfrac = xfrac << #FRACBITS
    actual = UReferenceSpot(xfrac << #FRACBITS, yfrac)
    If actual < 0 Or actual > 4095
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL42 signed small fixed values never escape flat source spot")
EndProcedure

Procedure TestPL43()
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected zlight.PlaneZLightTable
  Protected target.FrameBuffer
  Protected coverageMemory.i = 0
  Protected tally.PlaneDrawTally
  Protected imageZero.FlatImage
  Protected imageMax.FlatImage
  Protected paramsZero.PlaneMapParams
  Protected paramsMax.PlaneMapParams
  Protected zeroIndex.i
  Protected maxIndex.i
  Protected pixels.l = 0
  Protected expectedZero.l = 0
  Protected expectedMax.l = 0
  Protected actual.l = 0

  BeginCase("PL43", "Palette source 0 and 255 are ordinary COLORMAP-mapped values")
  If UBuildFlatVariantWad("u4301.wad", 45) = #False Or
     UOpenResourceOnlyWad("u4301.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL43 variant flat resources opened")
    ProcedureReturn
  EndIf
  If ProjectionInitClassic(@projection) = #False Or
     PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, -1,
                     1024) = #False Or
     PlaneZLightTableBuild(@zlight, @colormap) = #False Or
     FrameBufferCreate(@target, 320, 200) = #False Or
     PlaneDrawTallyReset(@tally) = #False
    Check(#False, "PL43 frame/zlight/target/tally")
    Goto PL43Done
  EndIf
  coverageMemory = AllocateMemory(#PLANE_DRAW_PixelCount)
  If coverageMemory = 0
    Check(#False, "PL43 coverage allocation")
    Goto PL43Done
  EndIf
  FillMemory(coverageMemory, Int(#PLANE_DRAW_PixelCount), 0)
  zeroIndex = FlatCatalogFindName(@flats, "FLATZERO")
  maxIndex = FlatCatalogFindName(@flats, "FLATMAX")
  Check(Bool(zeroIndex >= 0 And maxIndex >= 0), "PL43 synthetic FLATZERO/FLATMAX resolved")
  If FlatLoad(@flats, zeroIndex, @imageZero) = #False Or
     FlatLoad(@flats, maxIndex, @imageMax) = #False
    Check(#False, "PL43 source-0 and source-255 64x64 FlatLoad")
    Goto PL43Done
  EndIf
  Check(Bool(PeekA(imageZero\Pixels) = 0 And PeekA(imageMax\Pixels) = 255 And
              imageZero\PixelCount = #FLAT_ByteSize And imageMax\PixelCount = #FLAT_ByteSize),
        "PL43 palette indexes 0 and 255 decode as ordinary 4096-byte flats")
  If PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 0, 0, 10,
                           @paramsZero) = #False Or
     PlaneMapRowParameters(@frame, @zlight, 41 << #FRACBITS, 1, 0, 10,
                           @paramsMax) = #False
    Check(#False, "PL43 row parameters")
    Goto PL43Done
  EndIf
  If PlaneDrawOneSpan(@target, coverageMemory, @imageZero, @colormap,
                      @paramsZero, 0, 0, 1, @tally, @pixels) = #False
    Check(#False, "PL43 source-0 row span")
    Goto PL43Done
  EndIf
  expectedZero = (0 + #PLGOLD_ColormapBase + paramsZero\MapIndex * #PLGOLD_ColormapStep) & 255
  actual = PeekA(target\Pixels + 0)
  Check(Bool(pixels = 2 And actual = expectedZero), "PL43 source 0 paints mapped value, not skipped")
  If PlaneDrawOneSpan(@target, coverageMemory, @imageMax, @colormap,
                      @paramsMax, 1, 0, 1, @tally, @pixels) = #False
    Check(#False, "PL43 source-255 row span")
    Goto PL43Done
  EndIf
  expectedMax = (255 + #PLGOLD_ColormapBase + paramsMax\MapIndex * #PLGOLD_ColormapStep) & 255
  actual = PeekA(target\Pixels + Int(1) * Int(#PLANE_DRAW_ViewWidth))
  Check(Bool(pixels = 2 And actual = expectedMax), "PL43 source 255 paints ordinary mapped value")
  PL43Done:
  If coverageMemory <> 0
    FreeMemory(coverageMemory)
  EndIf
  FlatImageReset(@imageZero)
  FlatImageReset(@imageMax)
  PlaneZLightTableReset(@zlight)
  PlaneFrameReset(@frame)
  FrameBufferReset(@target)
  ProjectionReset(@projection)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@flats)
  ColormapReset(@colormap)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure.i UDrawSpanSetup(*Frame.PlaneFrame, *Projection.Projection,
                          *Flats.FlatCatalog, *Colormap.ColormapSet,
                          *ZTable.PlaneZLightTable,
                          *Textures.TextureCatalog, *Pnames.PNamesTable,
                          *Target.FrameBuffer, *Tally.PlaneDrawTally,
                          *Params.PlaneMapParams, *Image.FlatImage,
                          FileName.s, FlatName.s, PlaneHeight.l, Row.l,
                          FirstX.l, LightNum.l, *Coverage.Byte)
  Protected flatIndex.i

  If *Coverage = 0
    ProcedureReturn #False
  EndIf
  If UBuildResourceOnlyWad(FileName) = #False Or
     UOpenResourceOnlyWad(FileName, *Flats, *Colormap, *Textures,
                          *Pnames) = #False
    ProcedureReturn #False
  EndIf
  If ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  If PlaneFrameBegin(*Frame, *Projection, 0, 0, 0, 41 << #FRACBITS, -1,
                     1024) = #False
    ProcedureReturn #False
  EndIf
  If PlaneZLightTableBuild(*ZTable, *Colormap) = #False
    ProcedureReturn #False
  EndIf
  If FrameBufferCreate(*Target, 320, 200) = #False
    ProcedureReturn #False
  EndIf
  If PlaneDrawTallyReset(*Tally) = #False
    ProcedureReturn #False
  EndIf
  flatIndex = FlatCatalogFindName(*Flats, FlatName)
  If flatIndex < 0
    ProcedureReturn #False
  EndIf
  If FlatLoad(*Flats, flatIndex, *Image) = #False
    ProcedureReturn #False
  EndIf
  If PlaneMapRowParameters(*Frame, *ZTable, PlaneHeight, Row, FirstX,
                           LightNum, *Params) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure UDrawSpanRelease(*Frame.PlaneFrame, *Projection.Projection,
                           *Flats.FlatCatalog, *Colormap.ColormapSet,
                           *ZTable.PlaneZLightTable,
                           *Textures.TextureCatalog, *Pnames.PNamesTable,
                           *Target.FrameBuffer, *Image.FlatImage,
                           coverageMemory.i)
  PlaneZLightTableReset(*ZTable)
  PlaneFrameReset(*Frame)
  FrameBufferReset(*Target)
  FlatImageReset(*Image)
  ProjectionReset(*Projection)
  If coverageMemory <> 0
    FreeMemory(coverageMemory)
  EndIf
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  TextureCatalogReset(*Textures)
  PNamesReset(*Pnames)
EndProcedure

Procedure TestPL44()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected target.FrameBuffer
  Protected tally.PlaneDrawTally
  Protected image.FlatImage
  Protected params.PlaneMapParams
  Protected coverageMemory.i = 0
  Protected pixels.l = 0
  Protected expected.l = 0
  Protected actual.l = 0

  BeginCase("PL44", "Inclusive [x1,x2] horizontal span painting and bounds")
  coverageMemory = AllocateMemory(#PLANE_DRAW_PixelCount)
  If coverageMemory = 0
    Check(#False, "PL44 coverage allocation")
    ProcedureReturn
  EndIf
  FillMemory(coverageMemory, Int(#PLANE_DRAW_PixelCount), 0)
  If UDrawSpanSetup(@frame, @projection, @flats, @colormap, @zlight,
                    @textures, @pnames, @target, @tally, @params, @image,
                    "u4401.wad", "FLOOR1", 41 << #FRACBITS, 42, 160, 10,
                    coverageMemory) = #False
    Check(#False, "PL44 draw span setup")
    Goto PL44Done
  EndIf
  If PlaneDrawOneSpan(@target, coverageMemory, @image, @colormap, @params,
                      42, 160, 160, @tally, @pixels) = #False
    Check(#False, "PL44 single-column inclusive span")
    Goto PL44Done
  EndIf
  expected = (PeekA(image\Pixels + UReferenceSpot(params\XFrac, params\YFrac)) +
              #PLGOLD_ColormapBase + params\MapIndex * #PLGOLD_ColormapStep) & 255
  actual = PeekA(target\Pixels + Int(42) * Int(#PLANE_DRAW_ViewWidth) + 160)
  Check(Bool(pixels = 1 And actual = expected), "PL44 FirstX=LastX paints exactly one inclusive pixel")
  UDrawSpanRelease(@frame, @projection, @flats, @colormap, @zlight,
                   @textures, @pnames, @target, @image, coverageMemory)
  coverageMemory = 0
  coverageMemory = AllocateMemory(#PLANE_DRAW_PixelCount)
  If coverageMemory = 0
    Check(#False, "PL44 two-column coverage allocation")
    ProcedureReturn
  EndIf
  If UDrawSpanSetup(@frame, @projection, @flats, @colormap, @zlight,
                    @textures, @pnames, @target, @tally, @params, @image,
                    "u4402.wad", "FLOOR1", 41 << #FRACBITS, 43, 159, 10,
                    coverageMemory) = #False
    Check(#False, "PL44 two-column draw span setup")
    Goto PL44Done
  EndIf
  FillMemory(coverageMemory, Int(#PLANE_DRAW_PixelCount), 0)
  If PlaneDrawOneSpan(@target, coverageMemory, @image, @colormap, @params,
                      43, 159, 160, @tally, @pixels) = #False
    Check(#False, "PL44 159..160 inclusive span")
    Goto PL44Done
  EndIf
  Check(Bool(pixels = 2), "PL44 count=ds_x2-ds_x1 paints count+1 inclusive pixels")
  Check(Bool(PeekA(target\Pixels + Int(43) * Int(#PLANE_DRAW_ViewWidth) + 159) <> 0 And
              PeekA(target\Pixels + Int(43) * Int(#PLANE_DRAW_ViewWidth) + 160) <> 0),
        "PL44 both inclusive destination columns written")
  If PlaneDrawOneSpan(@target, coverageMemory, @image, @colormap, @params,
                      43, 160, 159, @tally, @pixels) = #False And
     FindString(PlaneDrawLastError(), "horizontal columns are invalid") > 0
    Check(#True, "PL44 FirstX>LastX rejected with diagnostic")
  Else
    Check(#False, "PL44 FirstX>LastX rejected with diagnostic")
  EndIf
  PL44Done:
  UDrawSpanRelease(@frame, @projection, @flats, @colormap, @zlight,
                   @textures, @pnames, @target, @image, coverageMemory)
EndProcedure

Procedure TestPL45()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected target.FrameBuffer
  Protected tally.PlaneDrawTally
  Protected image.FlatImage
  Protected params.PlaneMapParams
  Protected coverageMemory.i = 0
  Protected pixels.l = 0
  Protected destination.q = 0

  BeginCase("PL45", "Flat source/row/destination bounds and 320x200 last cell")
  coverageMemory = AllocateMemory(#PLANE_DRAW_PixelCount)
  If coverageMemory = 0 Or
     UDrawSpanSetup(@frame, @projection, @flats, @colormap, @zlight,
                    @textures, @pnames, @target, @tally, @params, @image,
                    "u4501.wad", "FLOOR1", 41 << #FRACBITS, 199, 319, 10,
                    coverageMemory) = #False
    Check(#False, "PL45 final-cell draw setup")
    Goto PL45Done
  EndIf
  FillMemory(coverageMemory, Int(#PLANE_DRAW_PixelCount), 0)
  If PlaneDrawOneSpan(@target, coverageMemory, @image, @colormap, @params,
                      199, 319, 319, @tally, @pixels) = #False
    Check(#False, "PL45 row199/column319 span")
    Goto PL45Done
  EndIf
  destination = Int(199) * Int(#PLANE_DRAW_ViewWidth) + Int(319)
  Check(Bool(pixels = 1 And destination = Int(#PLANE_DRAW_PixelCount) - 1 And
              PeekA(target\Pixels + destination) <> 0),
        "PL45 last row/column writes final canonical pixel and stays in plane")
  Check(Bool(PlaneDrawOneSpan(@target, coverageMemory, @image, @colormap,
                              @params, 200, 0, 0, @tally, @pixels) = #False And
              FindString(PlaneDrawLastError(), "screen row is outside 0..199") > 0),
        "PL45 row=200 explicit destination failure")
  Check(Bool(PlaneDrawOneSpan(@target, coverageMemory, @image, @colormap,
                              @params, 199, 320, 320, @tally, @pixels) = #False And
              FindString(PlaneDrawLastError(), "horizontal columns are invalid") > 0),
        "PL45 column=320 explicit horizontal failure")
  Check(Bool(#PLANE_DRAW_FlatWidth = 64 And #PLANE_DRAW_FlatHeight = 64 And
              #PLANE_DRAW_FlatByteSize = 4096), "PL45 source flat exact 64x64/4096 contract")
  PL45Done:
  UDrawSpanRelease(@frame, @projection, @flats, @colormap, @zlight,
                   @textures, @pnames, @target, @image, coverageMemory)
EndProcedure

; ---------------------------------------------------------------------------
; PL46-PL50: zlight 16x128/clamps/map index/COLORMAP remap/sky skip
; ---------------------------------------------------------------------------

Procedure.i UZLightSetup(*ZTable.PlaneZLightTable, *Colormap.ColormapSet,
                        *Flats.FlatCatalog, *Textures.TextureCatalog,
                        *Pnames.PNamesTable, FileName.s)
  If UBuildResourceOnlyWad(FileName) = #False Or
     UOpenResourceOnlyWad(FileName, *Flats, *Colormap, *Textures,
                          *Pnames) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn PlaneZLightTableBuild(*ZTable, *Colormap)
EndProcedure

Procedure UZLightRelease(*ZTable.PlaneZLightTable, *Colormap.ColormapSet,
                        *Flats.FlatCatalog, *Textures.TextureCatalog,
                        *Pnames.PNamesTable)
  PlaneZLightTableReset(*ZTable)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  TextureCatalogReset(*Textures)
  PNamesReset(*Pnames)
EndProcedure

Procedure TestPL46()
  Protected zlight.PlaneZLightTable
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected lightRow.l
  Protected distanceBin.l
  Protected mapIndex.l = 0
  Protected expected.l = 0
  Protected mismatch.l = 0
  Protected binIndex.l

  BeginCase("PL46", "zlight 16x128 levels exact independent oracle")
  If UZLightSetup(@zlight, @colormap, @flats, @textures, @pnames,
                  "u4601.wad") = #False
    Check(#False, "PL46 zlight fixture setup")
    ProcedureReturn
  EndIf
  Check(Bool(zlight\Allocations = 1 And zlight\LightRows = #PLANE_LIGHTLEVELS And
              zlight\DistanceBins = #PLANE_MAXLIGHTZ), "PL46 zlight owns 1 allocation, 16 rows/128 bins")
  mismatch = 0
  For lightRow = 0 To #PLANE_LIGHTLEVELS - 1
    For distanceBin = 0 To #PLANE_MAXLIGHTZ - 1
      If PlaneZLightMapIndex(@zlight, lightRow, distanceBin << #PLANE_LIGHTZSHIFT,
                             @mapIndex) = #False
        mismatch + 1
      Else
        binIndex = lightRow * #PLANE_MAXLIGHTZ + distanceBin
        expected = PeekL(*gZLightLevels + Int(binIndex) * SizeOf(Long))
        If mapIndex <> expected
          mismatch + 1
        EndIf
      EndIf
    Next
  Next
  Check(Bool(mismatch = 0), "PL46 all 2,048 table levels exact oracle")
  UZLightRelease(@zlight, @colormap, @flats, @textures, @pnames)
EndProcedure

Procedure TestPL47()
  Protected lightNum.l = 0

  BeginCase("PL47", "Sector lighting shift clamp 0..15")
  Check(Bool(PlaneLightRowChecked(160, 0, @lightNum) And lightNum = 10),
        "PL47 sector light 160 rule shift>>4 yields row10")
  Check(Bool(PlaneLightRowChecked(256, 0, @lightNum) And lightNum = 15),
        "PL47 light 256 clamps row to MAXLIGHTLEVELS-1")
  Check(Bool(PlaneLightRowChecked(-1, 0, @lightNum) And lightNum = 0),
        "PL47 signed negative light shifts to row0 clamp")
  Check(Bool(PlaneLightRowChecked(32768, 0, @lightNum) = #False And
              FindString(PlaneMappingLastError(), "signed 16-bit") > 0),
        "PL47 light>32767 outside signed SHORT domain rejected")
  Check(Bool(PlaneLightRowChecked(160, 1, @lightNum) = #False And
              FindString(PlaneMappingLastError(), "extralight") > 0),
        "PL47 extralight deferred/unsupported explicitly rejected")
EndProcedure

Procedure TestPL48()
  Protected zlight.PlaneZLightTable
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected mapIndex.l = 0
  Protected expected.l = 0

  BeginCase("PL48", "distance >>20 index clamp 127 including negative/huge")
  If UZLightSetup(@zlight, @colormap, @flats, @textures, @pnames,
                  "u4801.wad") = #False
    Check(#False, "PL48 zlight fixture setup")
    ProcedureReturn
  EndIf
  If PlaneZLightMapIndex(@zlight, 10, 0, @mapIndex) = #False
    Check(#False, "PL48 distance index 0")
  Else
    expected = PeekL(*gZLightLevels + Int(10) * #PLANE_MAXLIGHTZ * 4)
    Check(Bool(mapIndex = expected), "PL48 distance 0 selects bin 0 exact oracle")
  EndIf
  If PlaneZLightMapIndex(@zlight, 10, -1, @mapIndex) = #False
    Check(#False, "PL48 negative fixed distance")
  Else
    expected = PeekL(*gZLightLevels + Int(10) * #PLANE_MAXLIGHTZ * 4 + 127 * 4)
    Check(Bool(mapIndex = expected), "PL48 negative signed distance maps unsigned clamp bin127")
  EndIf
  If PlaneZLightMapIndex(@zlight, 10, 200 << #PLANE_LIGHTZSHIFT, @mapIndex) = #False
    Check(#False, "PL48 huge distance")
  Else
    Check(Bool(mapIndex = expected), "PL48 distance index >=128 clamps to 127")
  EndIf
  UZLightRelease(@zlight, @colormap, @flats, @textures, @pnames)
EndProcedure

Procedure TestPL49()
  Protected frame.PlaneFrame
  Protected projection.Projection
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected zlight.PlaneZLightTable
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected target.FrameBuffer
  Protected tally.PlaneDrawTally
  Protected image.FlatImage
  Protected params.PlaneMapParams
  Protected coverageMemory.i = 0
  Protected pixels.l = 0
  Protected expected.l = 0
  Protected actual.l = 0
  Protected columnX.l

  BeginCase("PL49", "COLORMAP table/distance remap differs per light/distance")
  coverageMemory = AllocateMemory(#PLANE_DRAW_PixelCount)
  If coverageMemory = 0 Or
     UDrawSpanSetup(@frame, @projection, @flats, @colormap, @zlight,
                    @textures, @pnames, @target, @tally, @params, @image,
                    "u4901.wad", "FLOOR1", 41 << #FRACBITS, 42, 100, 10,
                    coverageMemory) = #False
    Check(#False, "PL49 draw span setup")
    Goto PL49Done
  EndIf
  FillMemory(coverageMemory, Int(#PLANE_DRAW_PixelCount), 0)
  If PlaneDrawOneSpan(@target, coverageMemory, @image, @colormap, @params,
                      42, 100, 103, @tally, @pixels) = #False
    Check(#False, "PL49 100..103 remapped span")
    Goto PL49Done
  EndIf
  If pixels = 4
    Check(#True, "PL49 four COLORMAP texels for inclusive 100..103")
  Else
    Check(#False, "PL49 four COLORMAP texels for inclusive 100..103")
  EndIf
  For columnX = 100 To 103
    expected = (45 + #PLGOLD_ColormapBase + params\MapIndex * #PLGOLD_ColormapStep) & 255
    actual = PeekA(target\Pixels + Int(42) * Int(#PLANE_DRAW_ViewWidth) + Int(columnX))
    If actual <> expected
      Check(#False, "PL49 every span byte remapped through COLORMAP formula")
      Goto PL49Done
    EndIf
  Next
  Check(#True, "PL49 every span byte remapped through COLORMAP formula")
  PL49Done:
  UDrawSpanRelease(@frame, @projection, @flats, @colormap, @zlight,
                   @textures, @pnames, @target, @image, coverageMemory)
EndProcedure

Procedure TestPL50()
  Protected summary.URunSummary

  BeginCase("PL50", "Sky F_SKY1 never loaded/drawn; deferred bands/pixels counted")
  If URunScene("u5002.wad", 2, @summary) = #False
    Check(#False, "PL50 PI02 combined frame succeeds")
    ProcedureReturn
  EndIf
  Check(Bool(summary\SkyVisplanes = #PLGOLD_PI02_SkyVisplanes And
              summary\SkyDeferredBands = #PLGOLD_PI02_SkyBands And
              summary\SkyDeferredPixels = #PLGOLD_PI02_SkyPixels),
        "PL50 sky visplane bands/pixels deferred exact oracle")
  Check(Bool(summary\PlanePixels = #PLGOLD_PI02_PlanePixels And
              summary\FloorPixels = #PLGOLD_PI02_FloorPixels And
              summary\CeilingPixels = #PLGOLD_PI02_CeilingPixels),
        "PL50 only regular floor pixels painted; zero sky pixels substituted")
  Check(Bool(summary\FlatCacheUnique = 1 And summary\FlatCacheLoaded = 1 And
              summary\FlatCacheCount = 1 And summary\FlatCacheAllocations >= 1),
        "PL50 used-flat cache loads only FLOOR1; F_SKY1 absent")
EndProcedure

; ---------------------------------------------------------------------------
; PL51-PL55: cache lifecycle uniqueness, A->B->A, malformed/caps/rollback
; ---------------------------------------------------------------------------

Procedure TestPL51()
  Protected summary.URunSummary
  Protected first.URunSummary

  BeginCase("PL51", "Used-flat cache uniqueness/only-used loading")
  If URunScene("u5101.wad", 1, @first) = #False Or
     URunScene("u5102.wad", 2, @summary) = #False
    Check(#False, "PL51 PI01/PI02 combined frames succeed")
    ProcedureReturn
  EndIf
  Check(Bool(first\FlatCacheUnique = 1 And first\FlatCacheLoaded = 1 And
              first\FlatCacheCount = 1), "PL51 PI01 loads FLOOR1 once; CEIL1 lacks visible bands")
  Check(Bool(summary\FlatCacheUnique = 1 And summary\FlatCacheLoaded = 1 And
              summary\FlatCacheCount = 1), "PL51 PI02 loads only floor, never sky/deferred flat")
  Check(Bool(first\FlatCacheAllocations >= 1 And summary\FlatCacheAllocations >= 1),
        "PL51 cache owns bounded entries/image allocations")
EndProcedure

Procedure TestPL52()
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected planeIndex.l = 0
  Protected flatIndex.i
  Protected cache.PlaneFlatCache
  Protected *image.FlatImage = 0

  BeginCase("PL52", "Flat cache A->B->A invalidation/reload and WAD-close lifetime")
  If UBuildFlatVariantWad("u52A.wad", 45) = #False Or
     UBuildFlatVariantWad("u52B.wad", 90) = #False
    Check(#False, "PL52 variant A/B WADs built")
    ProcedureReturn
  EndIf
  If UOpenResourceOnlyWad("u52A.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL52 A session opened")
    ProcedureReturn
  EndIf
  flatIndex = FlatCatalogFindName(@flats, "FLOOR1")
  If ProjectionInitClassic(@projection) = #False Or
     PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, -1,
                     1024) = #False Or flatIndex < 0 Or
     PlaneFindPlane(@frame, 0, flatIndex, 192, @planeIndex) = #False Or
     PlaneColumnSetBand(@frame, planeIndex, 100, 10, 12) = #False
    Check(#False, "PL52 frame/band setup")
    Goto PL52Done
  EndIf
  FillMemory(@cache, Int(SizeOf(PlaneFlatCache)), 0)
  If PlaneFlatCacheBuild(@cache, @flats, @frame) = #False
    Check(#False, "PL52 A cache build")
    Goto PL52Done
  EndIf
  *image = PlaneFlatCacheImagePtr(@cache, flatIndex)
  Check(Bool(*image <> 0 And PeekA(*image\Pixels) = 45 And cache\Count = 1 And
              cache\Ready = 1), "PL52 A loaded FLOOR1 source pixel 45 once")
  WADClose()
  Check(Bool(PlaneFlatCacheReset(@cache)), "PL52 cache Reset releases session-A image")
  Check(Bool(PlaneFlatCacheImagePtr(@cache, flatIndex) = 0 And
              PlaneFlatCacheIsValid(@cache) = #False And
              FindString(PlaneFlatCacheLastError(), "not initialized") > 0),
        "PL52 old A image pointer invalidated after Reset")

  If UOpenResourceOnlyWad("u52B.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL52 B session opened")
    Goto PL52Done
  EndIf
  flatIndex = FlatCatalogFindName(@flats, "FLOOR1")
  If flatIndex < 0 Or PlaneFlatCacheBuild(@cache, @flats, @frame) = #False
    Check(#False, "PL52 B cache rebuild from same frame bands")
    Goto PL52Done
  EndIf
  *image = PlaneFlatCacheImagePtr(@cache, flatIndex)
  Check(Bool(*image <> 0 And PeekA(*image\Pixels) = 90), "PL52 B reload picks new source pixel 90")
  PlaneFlatCacheReset(@cache)
  WADClose()

  If UOpenResourceOnlyWad("u52A.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL52 A re-open")
    Goto PL52Done
  EndIf
  flatIndex = FlatCatalogFindName(@flats, "FLOOR1")
  If flatIndex < 0 Or PlaneFlatCacheBuild(@cache, @flats, @frame) = #False
    Check(#False, "PL52 A second cache build")
    Goto PL52Done
  EndIf
  *image = PlaneFlatCacheImagePtr(@cache, flatIndex)
  Check(Bool(*image <> 0 And PeekA(*image\Pixels) = 45 And cache\Count = 1),
        "PL52 A->B->A reload returns original source pixel 45 once")
  PL52Done:
  *image = 0
  PlaneFlatCacheReset(@cache)
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@flats)
  ColormapReset(@colormap)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure TestPL53()
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected image.FlatImage
  Protected colormapCount.l = 0
  Protected brokenIndex.i
  Protected mapCount.l = 0

  BeginCase("PL53", "Missing/truncated flat and short COLORMAP fail explicitly")
  If UBuildBrokenFlatWad("u5301.wad") = #False Or
     WADOpen(WallTexFixturePath("u5301.wad")) = #False
    Check(#False, "PL53 wrong-size flat WAD built/opened")
    ProcedureReturn
  EndIf
  FillMemory(@flats, Int(SizeOf(FlatCatalog)), 0)
  If FlatCatalogBuild(@flats) = #False
    Check(#False, "PL53 marker catalog builds with truncated interior flat")
    Goto PL53A
  EndIf
  brokenIndex = FlatCatalogFindName(@flats, "BADFLAT")
  Check(Bool(brokenIndex >= 0), "PL53 BADFLAT is catalog-addressable")
  If brokenIndex >= 0
    Check(Bool(FlatLoad(@flats, brokenIndex, @image) = #False And
                FindString(FlatLastError(), "wrong size") > 0 And
                FindString(FlatLastError(), "4096") > 0),
          "PL53 FlatLoad rejects 4095-byte flat with size diagnostic")
  Else
    Check(#False, "PL53 truncation failure observable")
  EndIf
  PL53A:
  FlatImageReset(@image)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@flats)

  If UBuildShortColormapWad("u5302.wad") = #False Or
     UOpenResourceOnlyWad("u5302.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL53 16-table COLORMAP WAD opened/decoded")
    ProcedureReturn
  EndIf
  Check(Bool(ColormapCount(@colormap) = 16), "PL53 decoder accepts 16 complete COLORMAP tables")
  Check(Bool(PlaneColormapValidate(@colormap, @mapCount) = #False And
              FindString(PlaneMappingLastError(), "requires at least") > 0 And
              FindString(PlaneMappingLastError(), "32") > 0),
        "PL53 classic zlight >=32-table gate rejects short COLORMAP")
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@flats)
  ColormapReset(@colormap)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure TestPL54()
  Protected projection.Projection
  Protected frame.PlaneFrame
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected planeIndex.l = 0
  Protected flatIndex.i
  Protected cache.PlaneFlatCache

  BeginCase("PL54", "Visplane/board/cache/spans/metadata memory caps")
  Check(Bool(#PLANE_MaxVisplanes = 1024 And
              #PLANE_MaxBoardBytes = #PLANE_MaxVisplanes * #PLANE_PaddedColumns * 2 * 4 And
              #PLANE_MaxRecordBytes = 65536),
        "PL54 1024 visplane/record/board caps exact")
  Check(Bool(#PLANE_FLAT_CACHE_MaxEntries = 1024 And
              #PLANERENDER_MaxSpans = 200000 And
              #PLANERENDER_MaxMetadataBytes = 67108864 And
              #PLANE_Timeline_MaxVisits = 65536 And
              #PLANE_Timeline_MaxEvents = 65536),
        "PL54 flat cache/timeline/span/metadata caps declared")
  If ProjectionInitClassic(@projection) = #False Or
     PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4,
                     1024) = #False
    Check(#False, "PL54 cap=1024 frame Begin")
    ProjectionReset(@projection)
    ProcedureReturn
  EndIf
  Check(Bool(frame\Capacity = 1024 And
              frame\BoardBytes = #PLANE_MaxVisplanes * #PLANE_PaddedColumns * 2 * 4 And
              frame\Allocations = 3), "PL54 maximum visplane frame owned under exact board cap")
  PlaneFrameReset(@frame)
  Check(Bool(PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, 4,
                             1025) = #False And
              FindString(PlanesLastError(), "visplane cap") > 0),
        "PL54 cap=1025 explicit rejection")
  ProjectionReset(@projection)

  If UBuildResourceOnlyWad("u5401.wad") = #False Or
     UOpenResourceOnlyWad("u5401.wad", @flats, @colormap, @textures,
                          @pnames) = #False
    Check(#False, "PL54 closed-WAD cache probe resources")
    ProcedureReturn
  EndIf
  flatIndex = FlatCatalogFindName(@flats, "FLOOR1")
  If ProjectionInitClassic(@projection) = #False Or
     PlaneFrameBegin(@frame, @projection, 0, 0, 0, 41 << #FRACBITS, -1,
                     1024) = #False Or flatIndex < 0 Or
     PlaneFindPlane(@frame, 0, flatIndex, 192, @planeIndex) = #False Or
     PlaneColumnSetBand(@frame, planeIndex, 50, 9, 12) = #False
    Check(#False, "PL54 cache frame preparation")
    Goto PL54Done
  EndIf
  WADClose()
  FillMemory(@cache, Int(SizeOf(PlaneFlatCache)), 0)
  Check(Bool(PlaneFlatCacheBuild(@cache, @flats, @frame) = #False And
              FindString(PlaneFlatCacheLastError(), "no WAD is open") > 0),
        "PL54 used-flat load requires WAD open; closed session fails explicitly")
  PL54Done:
  PlaneFlatCacheReset(@cache)
  PlaneFrameReset(@frame)
  ProjectionReset(@projection)
  If WADIsOpen()
    WADClose()
  EndIf
  FlatCatalogReset(@flats)
  ColormapReset(@colormap)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure TestPL55()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected target.FrameBuffer
  Protected result.PlaneRenderResult
  Protected byteIndex.q
  Protected mismatch.l = 0
  Protected errorText.s = ""

  BeginCase("PL55", "Late truncated flat failure preserves target byte-for-byte")
  If UBuildLateBrokenSceneWad("u5501.wad") = #False Or
     UPrepareScene("u5501.wad", "E1M1", @pnames, @textures, @flats, @colormap,
                   @level, @view, @projection) = #False
    Check(#False, "PL55 late-broken scene resources prepared")
    ProcedureReturn
  EndIf
  If FrameBufferCreate(@target, 320, 200) = #False Or
     PlaneRenderResultReset(@result) = #False
    Check(#False, "PL55 target/result setup")
    Goto PL55Done
  EndIf
  FillMemory(target\Pixels, Int(target\PixelCount), 7)
  FillMemory(@result, Int(SizeOf(PlaneRenderResult)), 0)
  result\Magic = #PLANERENDER_Magic
  If PlaneRenderFrame(@level, @view, @projection, @flats, @textures,
                      @colormap, @target, @result, #True) = #True
    Check(#False, "PL55 truncated used-floor flat must fail")
    Goto PL55Done
  EndIf
  errorText = PlaneRenderLastError()
  Check(Bool(FindString(errorText, "flat cache") > 0 And
              (FindString(errorText, "wrong size") > 0 Or
               FindString(PlaneFlatCacheLastError(), "wrong size") > 0)),
        "PL55 late wall-pass/private-frame phase fails at flat cache load")
  mismatch = 0
  For byteIndex = 0 To Int(target\PixelCount) - 1
    If PeekA(target\Pixels + byteIndex) <> 7
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "PL55 all 64,000 prior target bytes preserved on late failure")
  Check(Bool(result\Ready = 0 And result\Plans = 0 And result\TexturePlans = 0),
        "PL55 failed result owns no metadata and remains reusable empty")
  PL55Done:
  PlaneRenderResultReset(@result)
  FrameBufferReset(@target)
  WallViewReset(@view)
  ProjectionReset(@projection)
  MapLevelReset(@level)
  FlatCatalogReset(@flats)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
  ColormapReset(@colormap)
  If WADIsOpen()
    WADClose()
  EndIf
EndProcedure

; ---------------------------------------------------------------------------
; PL56-PL60: legacy wall preservation/chronology/FNV/allocation/presentation
; ---------------------------------------------------------------------------

Procedure TestPL56()
  Protected summary.URunSummary
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected legacyHash.q = 0

  BeginCase("PL56", "Legacy M3-06 wall-only hash/pixels unchanged; combined disjoint")
  If URunScene("u5601.wad", 1, @summary) = #False
    Check(#False, "PL56 PI01 combined frame succeeds")
    ProcedureReturn
  EndIf
  Check(Bool(summary\SpanCount = #TEXGOLD_TI01_SpanCount And
              summary\WallDrawnPixels = #TEXGOLD_TI01_DrawnPixels And
              summary\WallCoveredPixels = summary\WallDrawnPixels),
        "PL56 combined wall writes/coverage equal frozen M3-06 oracle count")
  Check(Bool(summary\Hash = #PLGOLD_PI01_Hash And
              summary\ManualHash = #PLGOLD_PI01_Hash),
        "PL56 combined PI01 hash exact oracle; planes never overwrite covered walls")
  If UBuildSceneWad("u5602.wad", 1) = #False Or
     UPrepareScene("u5602.wad", "E1M1", @pnames, @textures, @flats, @colormap,
                   @level, @view, @projection) = #False
    Check(#False, "PL56 legacy textured session prepared")
    ProcedureReturn
  EndIf
  If WallVisibilityBuild(@level, @view\Camera, @projection, @flats, @textures,
                         @visibility) = #False
    Check(#False, "PL56 legacy 6-argument M3-04 visibility")
    Goto PL56Done
  EndIf
  If WallVisibilityCount(@visibility) <> #TEXGOLD_TI01_SpanCount
    Check(#False, "PL56 legacy visibility span count unchanged")
    Goto PL56Done
  EndIf
  If FrameBufferCreate(@target, 320, 200) = #False Or
     TexturedWallRenderResultReset(@result) = #False Or
     TexturedWallRenderFrame(@level, @view, @projection, @flats, @textures,
                             @colormap, @visibility, @target, @result,
                             #True) = #False
    Check(#False, "PL56 legacy textured wall-only frame succeeds")
    Goto PL56Done
  EndIf
  legacyHash = result\Hash
  Check(Bool(legacyHash = PeekQ(*gLegacyTI01Hash)), "PL56 old M3-06 textured hash preserved exactly")
  Check(Bool(result\DrawnPixels = #TEXGOLD_TI01_DrawnPixels), "PL56 old M3-06 painted wall pixel count preserved")
  PL56Done:
  TexturedWallRenderResultReset(@result)
  WallVisibilityReset(@visibility)
  FrameBufferReset(@target)
  UCloseScene(@pnames, @textures, @flats, @colormap, @level, @view, @projection)
EndProcedure

Procedure TestPL57()
  Protected summary.URunSummary
  Protected spanCount.l = 0

  BeginCase("PL57", "Numeric online plane event chronology exact oracle")
  If URunScene("u5702.wad", 2, @summary) = #False
    Check(#False, "PL57 PI02 combined frame succeeds")
    ProcedureReturn
  EndIf
  spanCount = summary\SpanCount
  Check(Bool(spanCount = #PLGOLD_PI02_SpanCount And
              summary\TimelineVisits = 1 And
              summary\TimelineEvents = spanCount And
              summary\ZeroSpanVisits = 0),
        "PL57 visitor/event counts equal published ClipSpans; no zero-span visit")
  Check(Bool(summary\FindCalls = #PLGOLD_PI02_FindCalls And
              summary\FindReuse = #PLGOLD_PI02_FindReuse And
              summary\FindCreate = #PLGOLD_PI02_FindCreate),
        "PL57 subsector Find call order exact oracle")
  Check(Bool(summary\CheckCalls = #PLGOLD_PI02_CheckCalls And
              summary\CheckMerges = #PLGOLD_PI02_CheckMerges And
              summary\CheckSplits = #PLGOLD_PI02_CheckSplits),
        "PL57 per-span CheckPlane union/split event order exact oracle")
  Check(Bool(summary\MarkCeilingCalls = #PLGOLD_PI02_MarkCeilingColumns And
              summary\MarkCeilingBands = #PLGOLD_PI02_MarkCeilingBands And
              summary\MarkFloorCalls = #PLGOLD_PI02_MarkFloorColumns And
              summary\MarkFloorBands = #PLGOLD_PI02_MarkFloorBands),
        "PL57 mark-before-clip column/band counters exact oracle")
  Check(Bool(summary\SkyFindVisits >= 1 And summary\Visplanes = #PLGOLD_PI02_Visplanes),
        "PL57 sky Find visit accounted within created visplane chronology")
EndProcedure

Procedure TestPL58()
  Protected first.URunSummary
  Protected second.URunSummary

  BeginCase("PL58", "Independent full-plane FNV and deterministic repeatability")
  If URunScene("u5801.wad", 1, @first) = #False Or
     URunScene("u5802.wad", 1, @second) = #False
    Check(#False, "PL58 two PI01 combined runs succeed")
    ProcedureReturn
  EndIf
  Check(Bool(first\Hash = #PLGOLD_PI01_Hash And first\ManualHash = first\Hash),
        "PL58 first run result FNV equals independent manual 64,000-byte FNV")
  Check(Bool(second\Hash = #PLGOLD_PI01_Hash And second\ManualHash = second\Hash),
        "PL58 second run result/manual FNV matches same oracle")
  Check(Bool(first\Hash = second\Hash And first\ManualHash = second\ManualHash),
        "PL58 repeated independent loads/resets produce identical full-plane hash")
  Check(Bool(first\NonZeroBytes + first\ZeroBytes = #PLANERENDER_FramePixelCount And
              second\NonZeroBytes + second\ZeroBytes = #PLANERENDER_FramePixelCount),
        "PL58 zero/nonzero audit accounts all 64,000 bytes each run")
EndProcedure

Procedure TestPL59()
  Protected summary.URunSummary
  Protected expectedTotal.l = 0
  Protected allocationSum.l = 0

  BeginCase("PL59", "One bounded allocation/owner per frame phase; no hot-loop malloc")
  If URunScene("u5902.wad", 2, @summary) = #False
    Check(#False, "PL59 PI02 combined frame succeeds")
    ProcedureReturn
  EndIf
  Check(Bool(summary\PlaneFrameAllocations = 3 And
              summary\TimelineAllocations = 2 And
              summary\ZLightAllocations = 1 And
              summary\ClipAllocations = 1 And
              summary\FrameAllocations = 1 And
              summary\CoverageAllocations = 1 And
              summary\MetadataAllocations = 2),
        "PL59 frame/timeline/zlight/clip/frame/coverage/metadata allocation counts")
  allocationSum = summary\MetadataAllocations + summary\WallTableAllocations +
                  summary\ZLightAllocations + summary\ClipAllocations +
                  summary\FrameAllocations + summary\CoverageAllocations +
                  summary\PlaneFrameAllocations + summary\TimelineAllocations +
                  summary\VisibilityAllocations + summary\TextureCacheAllocations +
                  summary\FlatCacheAllocations
  Check(Bool(allocationSum = summary\Allocations),
        "PL59 published total equals all phase-owned allocation counters")
  Check(Bool(summary\Allocations > 0 And summary\TextureCacheAllocations > 0 And
              summary\FlatCacheAllocations > 0 And summary\VisibilityAllocations > 0),
        "PL59 all allocation counters positive and bounded per prebuilt phase")
  Check(Bool(summary\WallTableAllocations = 1 And summary\Allocations < 1000),
        "PL59 wall scalelight one table allocation; total bounded small frame")
EndProcedure

Procedure TestPL60()
  Protected summary.URunSummary

  BeginCase("PL60", "3x nearest-neighbour presentation contract and canonical frame")
  Check(Bool(#VIDEO_DefaultScale = 3 And #PROJ_VIEWWIDTH = 320 And
              #PROJ_VIEWHEIGHT = 200 And #PROJ_CENTERX = 160 And
              #PROJ_CENTERY = 100),
        "PL60 GUI logical 320x200/client 960x600 3x nearest-neighbour constants")
  Check(Bool(#PLANERENDER_FrameWidth = 320 And #PLANERENDER_FrameHeight = 200 And
              #PLANE_DRAW_PixelCount = 64000), "PL60 canonical 64,000-byte row-major frame contract")
  If URunScene("u6001.wad", 1, @summary) = #False
    Check(#False, "PL60 PI01 combined CLI-style frame succeeds")
    ProcedureReturn
  EndIf
  Check(Bool(summary\Hash = #PLGOLD_PI01_Hash And
              summary\NonZeroBytes + summary\ZeroBytes = 64000),
        "PL60 full-plane presentation frame hash/byte audit exact; human GUI smoke reported separately")
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

Procedure Main()
  TestPL01() : TestPL02() : TestPL03() : TestPL04() : TestPL05()
  TestPL06() : TestPL07() : TestPL08() : TestPL09() : TestPL10()
  TestPL11() : TestPL12() : TestPL13() : TestPL14() : TestPL15()
  TestPL16() : TestPL17() : TestPL18() : TestPL19() : TestPL20()
  TestPL21() : TestPL22() : TestPL23() : TestPL24() : TestPL25()
  TestPL26() : TestPL27() : TestPL28() : TestPL29() : TestPL30()
  TestPL31() : TestPL32() : TestPL33() : TestPL34() : TestPL35()
  TestPL36() : TestPL37() : TestPL38() : TestPL39() : TestPL40()
  TestPL41() : TestPL42() : TestPL43() : TestPL44() : TestPL45()
  TestPL46() : TestPL47() : TestPL48() : TestPL49() : TestPL50()
  TestPL51() : TestPL52() : TestPL53() : TestPL54() : TestPL55()
  TestPL56() : TestPL57() : TestPL58() : TestPL59() : TestPL60()
EndProcedure

OpenConsole()
Main()

PrintN("")
PrintN("Cases: " + Str(gUCaseCount) + ", assertions: " + Str(gUAssertionCount) +
       ", failures: " + Str(gUFailureCount))
If gUFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gUFailureCount
