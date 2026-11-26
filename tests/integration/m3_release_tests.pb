; -----------------------------------------------------------------------------
; DoomPB - M3-07 synthetic release acceptance tests MR01-MR36 + RI01-RI03
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Integration/release harness over existing M1/M2/M3 module APIs only. Reuses
; wall_texture_support.pbi synthetic PWAD builders and the independent Python
; goldens (m3_projection_golden, m3_wall_projection_golden,
; m3_wall_texture_golden). No commercial IWAD bytes, Doom graphics or
; production-renderer output are used as fixtures. Every resource byte is
; self-authored synthetic little-endian data.
;
; Scope: audit M3-01..M3-06 module topology, immutable tables, fixed/BAM
; arithmetic, projection fingerprints, BSP order/zero-node root, cull-free
; trace, solid/pass inclusive clipping, online far-box after near work,
; backface/FOV edge columns, WallSpanPlan 12-bit interpolation, one-sided and
; two-sided tier/pegging/mask policy, texture first-match/width mask, vertical
; iscale/stepping, <128-height bounded fallback, mask0/opaque-0/opaque-255
; semantics, 16x48 scalelight + COLORMAP, masked two-sided deferral, cache
; reuse/ownership, failure rollback, A-B-A invalidation, debug-mode
; preservation, textured fixture/full-plane FNV, nearest-neighbour 3x,
; allocation budget and unchanged CLI codes. RI01-RI03 cover full synthetic
; pipelines and malformed/recovery lifecycles.
;
; Exit code: 0 when all assertions pass; otherwise the failure count.
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
XIncludeFile "../../src/Graphics/Palette.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../fixtures/m3_projection_golden.pbi"
XIncludeFile "../fixtures/m3_wall_projection_golden.pbi"
XIncludeFile "../fixtures/m3_wall_texture_golden.pbi"
XIncludeFile "../../tests/integration/wall_texture_support.pbi"

#M3REL_FNV_Offset = -3750763034362895579
#M3REL_FNV_Prime = 1099511628211
#M3REL_ViewWidth = 320
#M3REL_ViewHeight = 200
#M3REL_FramePixelCount = 64000
; After the mandatory release gates pass, the production default is 0.3.0
; (prepared release scope; owner commit/tag remain pending). This single constant
; and MR36's expected CLI version are updated together and must stay in sync.
#M3REL_ExpectedVersion = "0.3.0"

#M3REL_FrameSeparator = "\"
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #M3REL_FrameSeparator = "\"
CompilerElse
  #M3REL_FrameSeparator = "/"
CompilerEndIf

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

Global *gProjForwardHash = ?ProjectionGoldForwardHash
Global *gProjPreHash = ?ProjectionGoldPreHash
Global *gProjInverseHash = ?ProjectionGoldInverseHash
Global *gProjFocalLength = ?ProjectionGoldFocalLength
Global *gProjClipAngle = ?ProjectionGoldClipAngle
; Span field count is a fixture constant #WALLGOLD_SpanFieldCount (not a label).

Global *gTI01Spans = ?TEXGOLD_TI01_Spans
Global *gTI01PlanL = ?TEXGOLD_TI01_PlanL
Global *gTI01PlanQ = ?TEXGOLD_TI01_PlanQ
Global *gTI01SampleX = ?TEXGOLD_TI01_SampleX
Global *gTI01Frame = ?TEXGOLD_TI01_Frame
Global *gTI01Hash = ?TEXGOLD_TI01_Hash
Global *gTI01SpanHash = ?TEXGOLD_TI01_SpanHash
Global *gTI02Spans = ?TEXGOLD_TI02_Spans
Global *gTI02PlanL = ?TEXGOLD_TI02_PlanL
Global *gTI02PlanQ = ?TEXGOLD_TI02_PlanQ
Global *gTI02SampleX = ?TEXGOLD_TI02_SampleX
Global *gTI02SampleRows = ?TEXGOLD_TI02_SampleRows
Global *gTI02Frame = ?TEXGOLD_TI02_Frame
Global *gTI02Hash = ?TEXGOLD_TI02_Hash
Global *gTI02SpanHash = ?TEXGOLD_TI02_SpanHash
Global *gTI01SampleRows = ?TEXGOLD_TI01_SampleRows
Global *gIscales = ?TEXGOLD_Iscales
Global *gScalelightBins = ?TEXGOLD_ScalelightBins

; ---------------------------------------------------------------------------
; Harness, FNV and canonical text helpers (independent of production hashes)
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
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #M3REL_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvByte(Hash, Value)
  Hash = FnvByte(Hash, Value >> 8)
  Hash = FnvByte(Hash, Value >> 16)
  Hash = FnvByte(Hash, Value >> 24)
  ProcedureReturn Hash
EndProcedure

Procedure.s Hex64Canonical(Value.q)
  Protected result.s = ""
  Protected shift.i
  Protected nibble.i
  Protected digit.i

  For shift = 15 To 0 Step -1
    nibble = (Value >> (shift * 4)) & $F
    If nibble < 10
      digit = nibble + 48
    Else
      digit = nibble + 55
    EndIf
    result = result + Chr(digit)
  Next
  ProcedureReturn result
EndProcedure

Procedure.i HashTextEquals(Value.q, Expected.s)
  Protected actual.s = Hex64Canonical(Value)
  ProcedureReturn Bool(Len(Expected) = 16 And Len(actual) = 16 And actual = Expected)
EndProcedure

; Independent full-plane FNV over exactly 64,000 row-major palette bytes.
Procedure.q TestFrameHash(*Frame.FrameBuffer)
  Protected hash.q = #M3REL_FNV_Offset
  Protected i.i

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #M3REL_ViewWidth Or *Frame\Height <> #M3REL_ViewHeight Or
     *Frame\PixelCount <> #M3REL_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For i = 0 To #M3REL_FramePixelCount - 1
    hash = FnvByte(hash, PeekA(*Frame\Pixels + i))
  Next
  ProcedureReturn hash
EndProcedure

; Independent M3-04 aggregate span fingerprint over nine numeric fields.
Procedure.q TestWallSpanHash(*Result.WallVisibilityResult)
  Protected hash.q = #M3REL_FNV_Offset
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
    hash = FnvAddLong(hash, sub)
    hash = FnvAddLong(hash, seg)
    hash = FnvAddLong(hash, line)
    hash = FnvAddLong(hash, side)
    hash = FnvAddLong(hash, front)
    hash = FnvAddLong(hash, back)
    hash = FnvAddLong(hash, first)
    hash = FnvAddLong(hash, last)
    hash = FnvAddLong(hash, kind)
  Next
  ProcedureReturn hash
EndProcedure

; Independent M3-03 trace fingerprint over published event fields.
Procedure.q TestTraceHash(*Trace.BspTrace, *EventCount.Long)
  Protected hash.q = #M3REL_FNV_Offset
  Protected count.i
  Protected i.i
  Protected kind.l = 0
  Protected subsector.l = 0
  Protected seg.l = 0
  Protected sector.l = 0
  Protected linedef.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0

  count = BspTraceCount(*Trace)
  If count < 0
    *EventCount\l = -1
    ProcedureReturn -1
  EndIf
  *EventCount\l = count
  For i = 0 To count - 1
    If BspTraceGet(*Trace, i, @kind, @subsector, @seg, @sector, @linedef,
                   @side, @front, @back) = #False
      *EventCount\l = -1
      ProcedureReturn -1
    EndIf
    hash = FnvAddLong(hash, kind)
    hash = FnvAddLong(hash, subsector)
    hash = FnvAddLong(hash, seg)
    hash = FnvAddLong(hash, sector)
    hash = FnvAddLong(hash, linedef)
    hash = FnvAddLong(hash, side)
    hash = FnvAddLong(hash, front)
    hash = FnvAddLong(hash, back)
  Next
  ProcedureReturn hash
EndProcedure

; Independent projection table hashes (little-endian 32-bit entries).
Procedure.q TestProjectionForwardHash(*Projection.Projection)
  Protected hash.q = #M3REL_FNV_Offset
  Protected index.i
  Protected value.l = 0

  If ProjectionIsValid(*Projection) = #False
    ProcedureReturn -1
  EndIf
  For index = 0 To #PROJ_VIEWANGLE_TOX_COUNT - 1
    If ProjectionGetViewAngleToX(*Projection, index, @value) = #False
      ProcedureReturn -1
    EndIf
    hash = FnvAddLong(hash, value)
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q TestProjectionPreHash(*Projection.Projection)
  Protected hash.q = #M3REL_FNV_Offset
  Protected index.i
  Protected value.l = 0

  If ProjectionIsValid(*Projection) = #False
    ProcedureReturn -1
  EndIf
  For index = 0 To #PROJ_VIEWANGLE_TOX_COUNT - 1
    If ProjectionGetPreViewAngleToX(*Projection, index, @value) = #False
      ProcedureReturn -1
    EndIf
    hash = FnvAddLong(hash, value)
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q TestProjectionInverseHash(*Projection.Projection)
  Protected hash.q = #M3REL_FNV_Offset
  Protected index.i
  Protected raw.q = 0
  Protected value.l = 0

  If ProjectionIsValid(*Projection) = #False
    ProcedureReturn -1
  EndIf
  For index = 0 To #PROJ_XTOVIEWANGLE_COUNT - 1
    If ProjectionGetXToViewAngle(*Projection, index, @raw) = #False
      ProcedureReturn -1
    EndIf
    value = FixedWrap32Low(raw)
    hash = FnvAddLong(hash, value)
  Next
  ProcedureReturn hash
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic build/prepare/cleanup helpers (existing production APIs only)
; ---------------------------------------------------------------------------

Procedure.i BuildSceneWad(FileName.s, SceneMode.i)
  Protected marker.s = "E1M1"
  Protected ok.i = #False

  If WallTexWadBegin(FileName.s) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9)
    If SceneMode = 1
      ok = WallTexBuildT01MapLumps()
      marker = "E1M1"
    ElseIf SceneMode = 2
      ok = WallTexBuildT02MapLumps()
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

Procedure.i PrepareSyntheticSession(FileName.s, Marker.s,
                                    *Pnames.PNamesTable,
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

  If WADOpen(WallTexFixturePath(FileName.s)) = #False
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
  If MapLevelLoad(Marker.s, *Level) = #False
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

Procedure CleanupSyntheticSession(*Pnames.PNamesTable,
                                 *Textures.TextureCatalog,
                                 *Flats.FlatCatalog,
                                 *Colormap.ColormapSet,
                                 *Level.MapLevel, *View.WallView,
                                 *Projection.Projection,
                                 *Visibility.WallVisibilityResult)
  Protected pnamesPtr.PNamesTable
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

; Direct zero-node one-sector one-sided middle level (T01 geometry, no WAD).
Procedure.i BuildZeroNodeMiddleLevel(*Level.MapLevel)
  Protected Dim sectors.WallTexSectorSpec(0)
  Protected Dim lines.WallTexLineSpec(0)
  Protected Dim sides.WallTexSideSpec(0)
  Protected Dim verts.WallTexVertexSpec(1)
  Protected Dim segs.WallTexSegSpec(0)
  Protected Dim subs.WallTexSubSpec(0)
  Protected Dim nodes.WallTexNodeSpec(0)
  Protected Dim things.WallTexThingSpec(1)

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"
  sectors(0)\LightLevel = 160
  lines(0)\V1 = 0 : lines(0)\V2 = 1 : lines(0)\Flags = 0
  lines(0)\Side0 = 0 : lines(0)\Side1 = -1
  sides(0)\TextureOffset = 5 : sides(0)\RowOffset = -3 : sides(0)\Sector = 0
  sides(0)\TopName = "-" : sides(0)\BottomName = "-" : sides(0)\MidName = "TEXMID"
  verts(0)\X = 100 : verts(0)\Y = 64
  verts(1)\X = 100 : verts(1)\Y = -64
  segs(0)\V1 = 0 : segs(0)\V2 = 1 : segs(0)\RawAngle = 49152
  segs(0)\Line = 0 : segs(0)\Side = 0 : segs(0)\Offset = -7
  subs(0)\NumSegs = 1 : subs(0)\FirstSeg = 0
  things(0)\X = 0 : things(0)\Y = 0 : things(0)\Angle = 0
  things(0)\Type = 1 : things(0)\Options = 0
  ProcedureReturn WallTexBuildMapLevel(*Level,
     @sectors(0), 1, @lines(0), 1, @sides(0), 1, @verts(0), 2,
     @segs(0), 1, @subs(0), 1, @nodes(0), 0, @things(0), 1)
EndProcedure

; Direct one-node two-leaf broad horizontal wall repeated in both leaves.
; Camera (-1,0) ANG90 selects side 1 => near leaf1 then far leaf0; near SOLID
; span covers the screen and the far bbox is occluded after the near work.
Procedure.i BuildTwoLeafBroadLevel(*Level.MapLevel)
  Protected Dim sectors.WallTexSectorSpec(0)
  Protected Dim lines.WallTexLineSpec(1)
  Protected Dim sides.WallTexSideSpec(1)
  Protected Dim verts.WallTexVertexSpec(1)
  Protected Dim segs.WallTexSegSpec(1)
  Protected Dim subs.WallTexSubSpec(1)
  Protected Dim nodes.WallTexNodeSpec(0)
  Protected i.i

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"
  sectors(0)\LightLevel = 160
  verts(0)\X = -1000 : verts(0)\Y = 100
  verts(1)\X = 1000 : verts(1)\Y = 100
  For i = 0 To 1
    lines(i)\V1 = 0 : lines(i)\V2 = 1 : lines(i)\Flags = 0
    lines(i)\Side0 = i : lines(i)\Side1 = -1
    sides(i)\Sector = 0
    sides(i)\TopName = "WALL1" : sides(i)\BottomName = "WALL1"
    sides(i)\MidName = "WALL1"
    segs(i)\V1 = 0 : segs(i)\V2 = 1
    segs(i)\RawAngle = 0 : segs(i)\Line = i : segs(i)\Side = 0
    subs(i)\FirstSeg = i : subs(i)\NumSegs = 1
  Next
  nodes(0)\OriginX = 0 : nodes(0)\OriginY = 0
  nodes(0)\DX = 0 : nodes(0)\DY = 1
  nodes(0)\Box0Top = 200 : nodes(0)\Box0Bottom = 50
  nodes(0)\Box0Left = -100 : nodes(0)\Box0Right = 100
  nodes(0)\Box1Top = 200 : nodes(0)\Box1Bottom = 50
  nodes(0)\Box1Left = -100 : nodes(0)\Box1Right = 100
  nodes(0)\Child0 = #MAP_NF_SUBSECTOR ! 0
  nodes(0)\Child1 = #MAP_NF_SUBSECTOR ! 1
  ProcedureReturn WallTexBuildMapLevel(*Level,
     @sectors(0), 1, @lines(0), 2, @sides(0), 2, @verts(0), 2,
     @segs(0), 2, @subs(0), 2, @nodes(0), 1, 0, 0)
EndProcedure

; Direct one-sector map with caller-defined flat/ceiling/side names for
; presence/sky/pegging audit. Zero-node one subsector.
Procedure.i BuildSingleSurfaceLevel(*Level.MapLevel,
                                    FloorName.s, CeilingName.s,
                                    FloorHeight.l, CeilingHeight.l, Light.l,
                                    MidName.s, LineFlags.l, RowOffset.l,
                                    TextureOffset.l)
  Protected Dim sectors.WallTexSectorSpec(0)
  Protected Dim lines.WallTexLineSpec(0)
  Protected Dim sides.WallTexSideSpec(0)
  Protected Dim verts.WallTexVertexSpec(1)
  Protected Dim segs.WallTexSegSpec(0)
  Protected Dim subs.WallTexSubSpec(0)
  Protected Dim nodes.WallTexNodeSpec(0)

  sectors(0)\FloorHeight = FloorHeight
  sectors(0)\CeilingHeight = CeilingHeight
  sectors(0)\FloorName = FloorName
  sectors(0)\CeilingName = CeilingName
  sectors(0)\LightLevel = Light
  lines(0)\V1 = 0 : lines(0)\V2 = 1 : lines(0)\Flags = LineFlags
  lines(0)\Side0 = 0 : lines(0)\Side1 = -1
  sides(0)\TextureOffset = TextureOffset : sides(0)\RowOffset = RowOffset
  sides(0)\Sector = 0
  sides(0)\TopName = "-" : sides(0)\BottomName = "-" : sides(0)\MidName = MidName
  verts(0)\X = 100 : verts(0)\Y = 64
  verts(1)\X = 100 : verts(1)\Y = -64
  segs(0)\V1 = 0 : segs(0)\V2 = 1 : segs(0)\RawAngle = 49152
  segs(0)\Line = 0 : segs(0)\Side = 0 : segs(0)\Offset = 0
  subs(0)\NumSegs = 1 : subs(0)\FirstSeg = 0
  ProcedureReturn WallTexBuildMapLevel(*Level,
     @sectors(0), 1, @lines(0), 1, @sides(0), 1, @verts(0), 2,
     @segs(0), 1, @subs(0), 1, @nodes(0), 0, 0, 0)
EndProcedure

; Production plan field accessor using the published fixture field layout.
Procedure.l PlanField(*Legacy.WallSpanPlan, *Tex.WallTextureSpanPlan, FieldIndex.l)
  Select FieldIndex
    Case 0 : ProcedureReturn *Legacy\Subsector
    Case 1 : ProcedureReturn *Legacy\Seg
    Case 2 : ProcedureReturn *Legacy\Linedef
    Case 3 : ProcedureReturn *Legacy\Side
    Case 4 : ProcedureReturn *Legacy\FrontSector
    Case 5 : ProcedureReturn *Legacy\BackSector
    Case 6 : ProcedureReturn *Legacy\FirstX
    Case 7 : ProcedureReturn *Legacy\LastX
    Case 8 : ProcedureReturn *Legacy\Kind
    Case 9 : ProcedureReturn *Legacy\Scale1
    Case 10 : ProcedureReturn *Legacy\Scale2
    Case 11 : ProcedureReturn *Legacy\ScaleStep
    Case 12 : ProcedureReturn *Legacy\Hyp
    Case 13 : ProcedureReturn *Legacy\Distance
    Case 14 : ProcedureReturn *Legacy\WorldTopRaw
    Case 15 : ProcedureReturn *Legacy\WorldBottomRaw
    Case 16 : ProcedureReturn *Legacy\WorldHighRaw
    Case 17 : ProcedureReturn *Legacy\WorldLowRaw
    Case 18 : ProcedureReturn *Legacy\WorldTop
    Case 19 : ProcedureReturn *Legacy\WorldBottom
    Case 20 : ProcedureReturn *Legacy\WorldHigh
    Case 21 : ProcedureReturn *Legacy\WorldLow
    Case 22 : ProcedureReturn *Legacy\TopFrac
    Case 23 : ProcedureReturn *Legacy\BottomFrac
    Case 24 : ProcedureReturn *Legacy\TopStep
    Case 25 : ProcedureReturn *Legacy\BottomStep
    Case 26 : ProcedureReturn *Legacy\PixHigh
    Case 27 : ProcedureReturn *Legacy\PixLow
    Case 28 : ProcedureReturn *Legacy\PixHighStep
    Case 29 : ProcedureReturn *Legacy\PixLowStep
    Case 30 : ProcedureReturn *Legacy\MarkFloor
    Case 31 : ProcedureReturn *Legacy\MarkCeiling
    Case 32 : ProcedureReturn *Legacy\TopRegion
    Case 33 : ProcedureReturn *Legacy\BottomRegion
    Case 34 : ProcedureReturn *Legacy\TopTier
    Case 35 : ProcedureReturn *Legacy\BottomTier
    Case 36 : ProcedureReturn *Legacy\MiddleTier
    Case 37 : ProcedureReturn *Legacy\TwoSided
    Case 38 : ProcedureReturn *Legacy\FrontLight
    Case 39 : ProcedureReturn *Legacy\ClosedDoor
    Case 40 : ProcedureReturn *Legacy\SkyHack
    Case 41 : ProcedureReturn *Tex\MidTextureIndex
    Case 42 : ProcedureReturn *Tex\TopTextureIndex
    Case 43 : ProcedureReturn *Tex\BottomTextureIndex
    Case 44 : ProcedureReturn *Tex\MaskedMidIndex
    Case 45 : ProcedureReturn *Tex\MidTextureMid
    Case 46 : ProcedureReturn *Tex\TopTextureMid
    Case 47 : ProcedureReturn *Tex\BottomTextureMid
    Case 48 : ProcedureReturn *Tex\MidWidth
    Case 49 : ProcedureReturn *Tex\MidHeight
    Case 50 : ProcedureReturn *Tex\MidWidthMask
    Case 51 : ProcedureReturn *Tex\TopWidth
    Case 52 : ProcedureReturn *Tex\TopHeight
    Case 53 : ProcedureReturn *Tex\TopWidthMask
    Case 54 : ProcedureReturn *Tex\BottomWidth
    Case 55 : ProcedureReturn *Tex\BottomHeight
    Case 56 : ProcedureReturn *Tex\BottomWidthMask
    Case 57 : ProcedureReturn *Tex\RawOffset
    Case 58 : ProcedureReturn *Tex\LightNum
    Case 59 : ProcedureReturn *Tex\MaskedMid
    Case 60 : ProcedureReturn *Tex\HasPaintedTier
    Case 61 : ProcedureReturn *Tex\SegmentTextured
    Default : ProcedureReturn -999999
  EndSelect
EndProcedure

Procedure.q PlanQ(*Legacy.WallSpanPlan, *Tex.WallTextureSpanPlan, FieldIndex.l)
  Select FieldIndex
    Case 0 : ProcedureReturn *Legacy\ViewAngle
    Case 1 : ProcedureReturn *Legacy\NormalAngle
    Case 2 : ProcedureReturn *Legacy\ReferenceAngle
    Case 3 : ProcedureReturn *Legacy\OffsetAngle
    Case 4 : ProcedureReturn *Legacy\DistAngle
    Case 5 : ProcedureReturn *Tex\CenterAngle
    Default : ProcedureReturn -999999
  EndSelect
EndProcedure

; Flattened fixture plan lookup: each published plan contributes 62 Long fields.
Procedure.l FixturePlanLValue(*Base.Byte, PlanIndex.l, FieldIndex.l)
  Protected offset.l

  offset = (PlanIndex * #TEXGOLD_PlanLFieldCount + FieldIndex) * SizeOf(Long)
  ProcedureReturn PeekL(*Base + offset)
EndProcedure

Procedure.q FixturePlanQValue(*Base.Byte, PlanIndex.l, FieldIndex.l)
  Protected offset.l

  offset = (PlanIndex * #TEXGOLD_PlanQFieldCount + FieldIndex) * SizeOf(Quad)
  ProcedureReturn PeekQ(*Base + offset)
EndProcedure

; Fixture hash labels hold Data.q canonical FNV-1a64 constants, read at runtime
; so the harness does not duplicate frozen fixture values as extra constants.
Procedure.q FixtureHashAt(*Label.Byte)
  ProcedureReturn PeekQ(*Label)
EndProcedure

; Release-only synthetic scene builder. Every payload byte is self-authored:
; gradient or zero PLAYPAL, standard flats, PNAMES/TEXTURE1/PATCHES and a
; caller-defined COLORMAP table count (1..256, written directly so a deliberately
; incomplete <32 lighting lump can be built), optional absent texture/cooked
; resource variants and T01/T02 style map lumps. No commercial bytes.
Procedure.i BuildReleaseSceneWad(FileName.s, SceneMode.i,
                                PatchAPixel.l, PatchBPixel.l,
                                PatchUpPixel.l, PatchLoPixel.l,
                                ColormapBase.l, ColormapStep.l,
                                ColormapTableCount.l,
                                IncludeTextures.i = #True,
                                IncludeColormap.i = #True,
                                CustomPalette.i = #False)
  Protected marker.s = "E1M1"
  Protected ok.i = #False
  Protected *data.Byte
  Protected size.q = 0
  Protected tableBytes.q
  Protected mapIndex.l
  Protected texel.l
  Protected value.l
  Protected colorIndex.l
  Protected patchSize.l

  If WallTexWadBegin(FileName.s) = #False
    ProcedureReturn #False
  EndIf

  If CustomPalette
    ; 768-byte single palette with distinct deterministic RGB gradients.
    *data = WallTexNewZero(768)
    If *data = 0
      CloseFile(gWallTexWadFile)
      gWallTexWadFile = 0
      ProcedureReturn #False
    EndIf
    For colorIndex = 0 To 255
      PokeA(*data + colorIndex * 3, colorIndex)
      PokeA(*data + colorIndex * 3 + 1, 255 - colorIndex)
      PokeA(*data + colorIndex * 3 + 2, (colorIndex * 3) & $FF)
    Next
    WallTexWadAdd("PLAYPAL", *data, 768)
    FreeMemory(*data)
  Else
    WallTexAddPalette()
  EndIf

  WallTexAddStandardFlatNamespace()

  ; Textures and patches only: COLORMAP is appended separately below.
  If WallTexAddStandardWallResources(PatchAPixel, PatchBPixel, PatchUpPixel,
                                     PatchLoPixel, ColormapBase, ColormapStep,
                                     IncludeTextures, #False) = #False
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
    ProcedureReturn #False
  EndIf

  If IncludeColormap And ColormapTableCount > 0
    tableBytes = Int(ColormapTableCount) * 256
    If tableBytes <= 0 Or tableBytes > 1048576 Or ColormapBase < 0 Or
       ColormapStep < 0
      CloseFile(gWallTexWadFile)
      gWallTexWadFile = 0
      ProcedureReturn #False
    EndIf
    *data = WallTexNewZero(tableBytes)
    If *data = 0
      CloseFile(gWallTexWadFile)
      gWallTexWadFile = 0
      ProcedureReturn #False
    EndIf
    For mapIndex = 0 To ColormapTableCount - 1
      For texel = 0 To 255
        value = (texel + ColormapBase + mapIndex * ColormapStep) & 255
        PokeA(*data + mapIndex * 256 + texel, value)
      Next
    Next
    WallTexWadAdd("COLORMAP", *data, tableBytes)
    FreeMemory(*data)
  EndIf

  If SceneMode = 1
    ok = WallTexBuildT01MapLumps()
    marker = "E1M1"
  ElseIf SceneMode = 2
    ok = WallTexBuildT02MapLumps()
    marker = "E2M1"
  Else
    ok = #True
  EndIf
  If ok And SceneMode <> 0
    ok = WallTexAddMapLumpsToWad(marker)
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

; Synthetic malformed resource WAD: valid palette/flats/PNAMES/patch/COLORMAP and
; T01 map, but TEXTURE1 is a four-byte truncated count/offset header with no
; definitions. Existing decoder must reject it before map/player startup.
Procedure.i BuildTruncatedTextureSceneWad(FileName.s)
  Protected marker.s = "E1M1"
  Protected ok.i = #False
  Protected *data.Byte
  Protected size.q = 0
  Protected patchSize.l = 0

  If WallTexWadBegin(FileName.s) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()

  *data = WallTexMakePNames("PATCHA", @size)
  If *data = 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
    ProcedureReturn #False
  EndIf
  WallTexWadAdd("PNAMES", *data, size)
  FreeMemory(*data)

  *data = WallTexNewZero(4)
  If *data = 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
    ProcedureReturn #False
  EndIf
  WallTexPut32(*data, 0, 1)
  WallTexWadAdd("TEXTURE1", *data, 4)
  FreeMemory(*data)

  *data = WallTexMakeSolidPatch(32, 128, 37, @patchSize)
  If *data = 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
    ProcedureReturn #False
  EndIf
  WallTexWadAdd("PATCHA", *data, patchSize)
  FreeMemory(*data)

  *data = WallTexMakeColormap(32, #TEXGOLD_ColormapBase,
                             #TEXGOLD_ColormapStep, @size)
  If *data = 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
    ProcedureReturn #False
  EndIf
  WallTexWadAdd("COLORMAP", *data, size)
  FreeMemory(*data)

  ok = WallTexBuildT01MapLumps()
  If ok
    ok = WallTexAddMapLumpsToWad(marker)
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

; Decodes the synthetic PLAYPAL while the fixture WAD remains open; caller owns
; *Palette and must reset it. Bytes are released on both success/failure.
Procedure.i DecodeSyntheticPalette(*Palette.PaletteSet)
  Protected *bytes.Byte = 0
  Protected size.q = 0
  Protected ok.i = #False

  *bytes = WallTexReadLumpBuffer("PLAYPAL", @size)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  ok = PaletteDecode(*bytes, size, *Palette)
  FreeMemory(*bytes)
  ProcedureReturn ok
EndProcedure

; Test-only executable source audit: counts exact API token occurrences in a
; tracked renderer source file. Used to confirm no allocation/composition/WAD
; read call exists in the per-column draw path. Not a performance profiler.
Procedure.i SourceTokenCount(FileName.s, Token.s, *Count.Long)
  Protected root.s
  Protected path.s
  Protected file.i
  Protected lineText.s
  Protected tokenCount.l = 0

  *Count\l = -1
  root = GetPathPart(ProgramFilename()) + ".." + #M3REL_FrameSeparator +
         "src" + #M3REL_FrameSeparator + "Renderer" + #M3REL_FrameSeparator
  path = root + FileName
  If FileSize(path) <= 0
    ProcedureReturn #False
  EndIf
  file = ReadFile(#PB_Any, path)
  If file = 0
    ProcedureReturn #False
  EndIf
  While Not Eof(file)
    lineText = ReadString(file, #PB_UTF8)
    If FindString(lineText, Token) > 0
      tokenCount + 1
    EndIf
  Wend
  CloseFile(file)
  *Count\l = tokenCount
  ProcedureReturn #True
EndProcedure

; Real CLI execution: build/DoomPB.exe is the tracked release executable compiled
; by the scripts. Returns captured stdout and the actual OS exit code.
Procedure.s RunCli(ArgumentLine.s, *ExitCode.Long)
  Protected executablePath.s = GetPathPart(ProgramFilename()) + "DoomPB.exe"
  Protected program.i
  Protected output.s = ""

  *ExitCode\l = -1
  If FileSize(executablePath) < 0
    ProcedureReturn ""
  EndIf
  program = RunProgram(executablePath, ArgumentLine,
                       GetPathPart(executablePath),
                       #PB_Program_Open | #PB_Program_Read)
  If program = 0
    ProcedureReturn ""
  EndIf
  While ProgramRunning(program)
    If AvailableProgramOutput(program)
      output + ReadProgramString(program) + Chr(10)
    Else
      Delay(5)
    EndIf
  Wend
  While AvailableProgramOutput(program)
    output + ReadProgramString(program) + Chr(10)
  Wend
  *ExitCode\l = ProgramExitCode(program)
  CloseProgram(program)
  ProcedureReturn output
EndProcedure

Procedure.s Quote(Text.s)
  ProcedureReturn Chr(34) + Text + Chr(34)
EndProcedure

; Read the current default version constant from the tracked entry source.
Procedure.s ReadDefaultsVersion(*Found.Long)
  Protected directoryRoot.s
  Protected path.s
  Protected file.i
  Protected line.s
  Protected marker.s = "#DoomPB_Version = "
  Protected version.s = ""
  Protected lineText.s

  *Found\l = 0
  directoryRoot = GetPathPart(ProgramFilename()) + ".." + #M3REL_FrameSeparator +
                  "src" + #M3REL_FrameSeparator
  path = directoryRoot + "DoomPB.pb"
  If FileSize(path) <= 0
    ProcedureReturn ""
  EndIf
  file = ReadFile(#PB_Any, path)
  If file = 0
    ProcedureReturn ""
  EndIf
  While Not Eof(file)
    lineText = ReadString(file, #PB_UTF8)
    If FindString(lineText, marker) > 0
      line = Mid(lineText, FindString(lineText, marker) + Len(marker))
      line = Trim(line)
      version = Mid(line, 2, Len(line) - 2)
      *Found\l = 1
      Break
    EndIf
  Wend
  CloseFile(file)
  ProcedureReturn version
EndProcedure

; ---------------------------------------------------------------------------
; MR01 - module topology / API signature smoke
; ---------------------------------------------------------------------------

Procedure TestMR01()
  BeginCase("MR01", "Module include dependency and API signature smoke")
  Check(Bool(#DOOMPB_WALLTEXTURESUPPORT_PBI = 1 And #DOOMPB_PROJGOLD_PBI = 1 And
             #DOOMPB_WALLGOLD_PBI = 1 And #DOOMPB_WALLTEXGOLD_PBI = 1),
        "all support/fixture include guards resolved once")
  Check(Bool(#PROJ_VIEWWIDTH = 320 And #PROJ_VIEWHEIGHT = 200 And
             #PROJ_CENTERX = 160 And #PROJ_CENTERY = 100),
        "canonical projection constants are exposed with expected values")
  Check(Bool(SizeOf(WallSpan) = #WALLGOLD_SpanFieldCount * SizeOf(Long) And
             SizeOf(BspEvent) = 8 * SizeOf(Long) And
             SizeOf(ClipRange) = 2 * SizeOf(Long)),
        "published WallSpan/BspEvent/ClipRange record field counts are exact")
  Check(Bool(#WALLVIS_Magic <> #BSPTRACE_Magic And #BSPTRACE_Magic <> #RENDER_Magic And
             #RENDER_Magic <> #TEXTRENDER_Magic And #TEXTRENDER_Magic <> #CLIP_Magic And
             #WALLPROJ_PlanMagic <> #WALLTEXSPAN_Magic),
        "owning structure Magic values are distinct and compile-visible")
  Check(Bool(#MAP_NF_SUBSECTOR = $8000 And #MAP_ML_TWOSIDED = 4 And
             #MAP_ML_DONTPEGTOP = 8 And #MAP_ML_DONTPEGBOTTOM = 16),
        "vanilla node-child/texture-pegging constants preserved")
  Check(Bool(#FIXED_MIN = -2147483648 And #FIXED_MAX = 2147483647 And
             #BAM_ANG180 = 2147483648 And #BAM_ANG270 = 3221225472),
        "signed fixed/BAM extremes remain canonical unsigned/ signed carriers")
EndProcedure

; ---------------------------------------------------------------------------
; MR02 - default version equals the active prepared-release expectation
; ---------------------------------------------------------------------------

Procedure TestMR02()
  Protected found.l = 0
  Protected defaultVersion.s = ""

  BeginCase("MR02", "Default --version expectation equals active release version")
  defaultVersion = ReadDefaultsVersion(@found)
  Check(Bool(found = 1), "tracked entry point version declaration is readable")
  Check(Bool(Len(defaultVersion) > 0), "default version value was extracted")
  Check(Bool(defaultVersion = #M3REL_ExpectedVersion),
        "default version equals the active release expectation " + #M3REL_ExpectedVersion)
EndProcedure

; ---------------------------------------------------------------------------
; MR03 - original fine-angle/geometry/table constants unaffected
; ---------------------------------------------------------------------------

Procedure TestMR03()
  Protected tangent.l = 0
  Protected sine.l = 0
  Protected atan.l = 0
  Protected angle.BamAngleValue

  BeginCase("MR03", "Original fine-angle/geometry/table constants unaffected")
  Check(Bool(#BAM_FINEANGLES = 8192 And #BAM_FINEMASK = 8191 And
             #BAM_ANGLETOFINESHIFT = 19 And #BAM_COSINE_OFFSET = 2048 And
             #TRIG_FINETANGENT_COUNT = 4096 And #TRIG_SINE_COUNT = 10240 And
             #TRIG_TANTOANGLE_COUNT = 2049),
        "FINEANGLES/mask/shift/cosine offset/table sizes unchanged")
  Check(Bool(TrigTangentChecked(#PROJ_FOCAL_TANGENT_INDEX, @tangent) And tangent = 65586),
        "canonical focal tan index 3072 yields source value 65586")
  Check(Bool(TrigSineChecked(2048, @sine) And sine = 65535),
        "finesine[FINEANGLES/4] cosine alias remains 65535")
  Check(Bool(TrigTanToAngleChecked(#BAM_SLOPERANGE, @atan) And atan = #BAM_ANG45),
        "tantoangle endpoint equals ANG45/BAM_SLOPERANGE")
  Check(Bool(GeometryPointToAngleChecked(0, 0, 0, -65536, @angle) And
             angle\Raw = #BAM_ANG270),
        "negative Y cardinal direction still returns ANG270")
EndProcedure

; ---------------------------------------------------------------------------
; MR04 - fixed multiplication/division sign and overflow spot checks
; ---------------------------------------------------------------------------

Procedure TestMR04()
  Protected result.l = 0
  Protected checked.i = #False

  BeginCase("MR04", "FixedMul/FixedDiv sign/overflow integration spot checks")
  Check(Bool(FixedMul(1, -1) = -1 And FixedMul(-1, -1) = 0 And
             FixedMul(32768, -32768) = -16384 And
             FixedMul(#FRACUNIT, #FRACUNIT) = #FRACUNIT),
        "FixedMul small signed pairs follow C flooring semantics")
  Check(Bool(FixedMul(#FIXED_MAX, #FIXED_MAX) = -65536 And
             FixedMul(#FIXED_MIN, #FRACUNIT) = #FIXED_MIN And
             FixedMul(#FIXED_MAX, 65537) = -2147450882),
        "FixedMul 32-bit overflow uses explicit low-32 two's-complement wrap")
  Check(Bool(FixedDiv(#FRACUNIT, 32768) = 131072 And
             FixedDiv(1, 3) = 21845 And FixedDiv(1, -3) = -21845),
        "FixedDiv exact quotient truncation and sign preserved")
  Check(Bool(FixedDiv(16384, 1) = #FIXED_MAX And FixedDiv(0, 0) = #FIXED_MAX And
             FixedDiv(-123, 0) = #FIXED_MIN),
        "FixedDiv early saturation guard reproduces source MIN/MAX choices")
  result = 0
  checked = FixedDiv2Checked(-32768, 1, @result)
  Check(Bool(checked And result = #FIXED_MIN),
        "FixedDiv2Checked admits exact signed32 minimum quotient")
EndProcedure

; ---------------------------------------------------------------------------
; MR05 - canonical 320x200 projection/table fingerprints unchanged
; ---------------------------------------------------------------------------

Procedure TestMR05()
  Protected projection.Projection
  Protected width.l = 0
  Protected height.l = 0
  Protected centerX.l = 0
  Protected centerY.l = 0
  Protected centerXFixed.l = 0
  Protected centerYFixed.l = 0
  Protected projectionFixed.l = 0
  Protected focal.l = 0
  Protected fov.l = 0
  Protected clip.q = 0
  Protected forwardCount.l = 0
  Protected inverseCount.l = 0
  Protected preCount.l = 0
  Protected forwardHash.q = 0
  Protected preHash.q = 0
  Protected inverseHash.q = 0

  BeginCase("MR05", "Canonical 320x200 projection/table fingerprints unchanged")
  ProjectionReset(@projection)
  Check(Bool(ProjectionInitClassic(@projection)), "R_InitTextureMapping equivalent initialized")
  Check(Bool(ProjectionGetConstants(@projection, @width, @height, @centerX, @centerY,
                                   @centerXFixed, @centerYFixed, @projectionFixed,
                                   @focal, @fov) And width = 320 And height = 200 And
             centerX = 160 And centerY = 100 And centerXFixed = 10485760 And
             centerYFixed = 6553600 And projectionFixed = 10485760 And
             focal = 10477766 And fov = 2048),
        "canonical width/height/center/focal/fov constants preserved")
  Check(Bool(ProjectionGetClipAngle(@projection, @clip) And clip = $20080000),
        "clipangle retains raw unsigned 0x20080000")
  Check(Bool(ProjectionGetTableCounts(@projection, @forwardCount, @inverseCount,
                                      @preCount) And forwardCount = 4096 And
             inverseCount = 321 And preCount = 4096),
        "normalized/pre window tables 4096 and inverse 321 unchanged")
  forwardHash = TestProjectionForwardHash(@projection)
  preHash = TestProjectionPreHash(@projection)
  inverseHash = TestProjectionInverseHash(@projection)
  Check(Bool(forwardHash = PeekQ(*gProjForwardHash)),
        "whole normalized viewangletox FNV equals independent fixture")
  Check(Bool(preHash = PeekQ(*gProjPreHash)),
        "whole retained pre-fencepost FNV equals independent fixture")
  Check(Bool(inverseHash = PeekQ(*gProjInverseHash)),
        "whole xtoviewangle unsigned LE32 FNV equals independent fixture")
  Check(Bool(PeekL(*gProjFocalLength) = focal And PeekQ(*gProjClipAngle) = clip),
        "fixture focal/clip scalar values match production")
  ProjectionReset(@projection)
EndProcedure

; ---------------------------------------------------------------------------
; MR06 - BSP leaf/near-first ordering and zero-node root convention
; ---------------------------------------------------------------------------

Procedure TestMR06()
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected rootIsSub.l = 0
  Protected rootIndex.l = 0
  Protected count.l = 0
  Protected kind.l = 0
  Protected sub.l = 0
  Protected seg.l = 0
  Protected sector.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected okZero.i = #False
  Protected okNode.i = #False

  BeginCase("MR06", "BSP leaf/near-first ordering and zero-node root convention")
  BspCameraReset(@camera)
  MapLevelReset(@level)
  BspTraceReset(@trace)
  Check(Bool(BuildZeroNodeMiddleLevel(@level)), "zero-node one-subsector synthetic level validated")
  Check(Bool(MapLevelGetBspRoot(@level, @rootIsSub, @rootIndex) And
             rootIsSub = 1 And rootIndex = 0),
        "zero-node root convention is subsector 0, never node 0")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, 0)), "camera set at (0,0) heading 0")
  okZero = BspTraceBuild(@level, @camera, @trace)
  count = BspTraceCount(@trace)
  Check(Bool(okZero And count = 2 And #BSPTRACE_Magic = trace\Magic),
        "zero-node cull-free trace publishes one subsector + one seg event")
  Check(Bool(BspTraceGet(@trace, 0, @kind, @sub, @seg, @sector, @line, @side,
                         @front, @back) And kind = #BSP_EventSubsector And sub = 0 And
             seg = -1 And sector = 0 And line = -1 And side = -1 And
             front = -1 And back = -1),
        "first event is SUBSECTOR 0 with derived sector and documented -1 fields")
  Check(Bool(BspTraceGet(@trace, 1, @kind, @sub, @seg, @sector, @line, @side,
                         @front, @back) And kind = #BSP_EventSeg And sub = 0 And
             seg = 0 And sector = 0 And line = 0 And side = 0 And front = 0 And
             back = -1),
        "second event is SEG 0 linked to leaf 0/linedef 0/side 0 one-sided")
  BspTraceReset(@trace)
  MapLevelReset(@level)

  Check(Bool(BuildTwoLeafBroadLevel(@level)), "one-node two-leaf synthetic level validated")
  Check(Bool(MapLevelGetBspRoot(@level, @rootIsSub, @rootIndex) And
             rootIsSub = 0 And rootIndex = 0),
        "node map root is final node 0 with subsector flag false")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, 0)), "camera at node origin side 1")
  okNode = BspTraceBuild(@level, @camera, @trace)
  count = BspTraceCount(@trace)
  Check(Bool(okNode And count = 4), "node trace publishes both leaves and two segs")
  Check(Bool(BspTraceGet(@trace, 0, @kind, @sub, @seg, @sector, @line, @side,
                         @front, @back) And kind = #BSP_EventSubsector And sub = 1),
        "near child 1 completes first (exact R_PointOnSide tie side 1)")
  Check(Bool(BspTraceGet(@trace, 2, @kind, @sub, @seg, @sector, @line, @side,
                         @front, @back) And kind = #BSP_EventSubsector And sub = 0),
        "far child 0 follows after the near subtree")
  BspTraceReset(@trace)
  MapLevelReset(@level)
  BspCameraReset(@camera)
EndProcedure

; ---------------------------------------------------------------------------
; MR07 - M3-03 trace cull-free ownership/reset
; ---------------------------------------------------------------------------

Procedure TestMR07()
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected traceA.BspTrace
  Protected traceB.BspTrace
  Protected hashA.q = 0
  Protected hashB.q = 0
  Protected countA.l = 0
  Protected countB.l = 0
  Protected builtA.i = #False
  Protected builtB.i = #False

  BeginCase("MR07", "M3-03 trace ownership, cull-free semantics and reset")
  MapLevelReset(@level)
  Check(Bool(BuildTwoLeafBroadLevel(@level)), "two-leaf node level built")
  Check(Bool(BspCameraSetFixed(@camera, 0, 0, 0)), "fixed camera heading 0")
  BspTraceReset(@traceA)
  BspTraceReset(@traceB)
  builtA = BspTraceBuild(@level, @camera, @traceA)
  hashA = TestTraceHash(@traceA, @countA)
  Check(Bool(builtA And countA = 4 And traceA\OcclusionSkips = 0 And
             traceA\VisitedSubsectors = 2),
        "cull-free trace visits both leaves with zero occlusion skips")
  MapLevelReset(@level)
  hashB = TestTraceHash(@traceA, @countB)
  Check(Bool(countB = countA And hashB = hashA),
        "trace owns copied numeric events and survives MapLevelReset")
  Check(Bool(BuildTwoLeafBroadLevel(@level)), "same synthetic level reloaded after reset")
  builtB = BspTraceBuild(@level, @camera, @traceB)
  Check(Bool(builtB And TestTraceHash(@traceB, @countB) = hashA),
        "fresh rebuild reproduces identical cull-free event fingerprint")
  Check(Bool(BspTraceReset(@traceA) And BspTraceCount(@traceA) = 0),
        "idempotent reset frees events and yields a valid empty trace")
  Check(Bool(BspTraceReset(@traceA) And BspTraceCount(@traceA) = 0),
        "second reset is idempotent with no stale pointer")
  BspTraceReset(@traceB)
  BspCameraReset(@camera)
EndProcedure

; ---------------------------------------------------------------------------
; MR08 - M3-04 solidsegs sentinels and inclusive interval boundaries
; ---------------------------------------------------------------------------

Procedure TestMR08()
  Protected state.ClipState
  Protected width.l = 0
  Protected rangeCount.l = 0
  Protected spanCount.l = 0
  Protected growth.l = 0
  Protected allocations.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected sub.l = 0
  Protected seg.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected fFirst.l = 0
  Protected fLast.l = 0
  Protected kind.l = 0

  BeginCase("MR08", "M3-04 solidsegs sentinel and inclusive interval boundaries")
  ClipStateReset(@state)
  Check(Bool(ClipStateBeginFrame(@state, 320)), "clip frame begin allocates sentinels")
  Check(Bool(ClipStateGetStats(@state, @width, @rangeCount, @spanCount, @growth,
                               @growth, @allocations) And width = 320 And
             rangeCount = 2 And spanCount = 0 And allocations = 2),
        "frame width/range/span/initial allocation metadata exact")
  Check(Bool(ClipStateGetRange(@state, 0, @first, @last) And
             first = #CLIP_SentinelMinFirst And last = #CLIP_SentinelMinLast),
        "left post sentinel [-2147483647,-1] fixed")
  Check(Bool(ClipStateGetRange(@state, 1, @first, @last) And
             first = 320 And last = #CLIP_SentinelMaxLast),
        "right post sentinel [320,2147483647] fixed")
  Check(Bool(ClipSolidSegment(@state, 10, 20, 0, 0, 0, 0, 0, -1) And
             ClipStateGetSpan(@state, 0, @sub, @seg, @line, @side, @front, @back,
                              @fFirst, @fLast, @kind) And fFirst = 10 And
             fLast = 20 And kind = #WALL_KIND_SOLID),
        "solid interval 10..20 published inclusive, never 10..19")
  Check(Bool(ClipSolidSegment(@state, 15, 25, 0, 1, 1, 0, 0, -1) And
             ClipStateGetSpan(@state, 1, @sub, @seg, @line, @side, @front, @back,
                              @fFirst, @fLast, @kind) And fFirst = 21 And
             fLast = 25),
        "overlapping solid emits only uncovered inclusive 21..25")
  Check(Bool(ClipPassSegment(@state, 0, 319, 0, 2, 2, 0, 0, 1) And
             ClipStateGetSpan(@state, 2, @sub, @seg, @line, @side, @front, @back,
                              @fFirst, @fLast, @kind) And fFirst = 0 And fLast = 9 And
             ClipStateGetSpan(@state, 3, @sub, @seg, @line, @side, @front, @back,
                              @fFirst, @fLast, @kind) And fFirst = 26 And fLast = 319),
        "pass domain edges emit inclusive 0..9 and 26..319 fragments")
  Check(Bool(ClipPassSegment(@state, 319, 319, 0, 3, 3, 0, 0, 1) And
             ClipStateGetSpan(@state, 4, @sub, @seg, @line, @side, @front, @back,
                              @fFirst, @fLast, @kind) And fFirst = 319 And
             fLast = 319 And kind = #WALL_KIND_PASS),
        "single-pixel span at x=319 is published inclusive")
  Check(Bool(ClipStateReset(@state) And state\Magic = #CLIP_Magic And
             state\Ready = 0 And state\Width = 0 And state\RangeCount = 0 And
             state\SpanCount = 0 And state\AllocationCount = 0 And
             state\Ranges = 0 And state\Spans = 0),
        "reset frees ranges/spans and returns valid empty reusable state")
  ClipStateReset(@state)
EndProcedure

; ---------------------------------------------------------------------------
; MR09 - online far-BBox visibility checked only after near work
; ---------------------------------------------------------------------------

Procedure TestMR09()
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected projection.Projection
  Protected result.WallVisibilityResult
  Protected spanCount.l = 0
  Protected visitedNodes.l = 0
  Protected visitedSubs.l = 0
  Protected processed.l = 0
  Protected emitted.l = 0
  Protected solidC.l = 0
  Protected bboxTests.l = 0
  Protected bboxVisible.l = 0
  Protected bboxOccluded.l = 0
  Protected bboxUnknown.l = 0
  Protected skips.l = 0
  Protected work.l = 0
  Protected allocations.l = 0
  Protected sub.l = 0
  Protected seg.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected built.i = #False

  BeginCase("MR09", "Online far-BBox visibility checked only after near work")
  MapLevelReset(@level)
  ProjectionReset(@projection)
  WallVisibilityReset(@result)
  Check(Bool(BuildTwoLeafBroadLevel(@level)), "two-leaf broad synthetic level built")
  Check(Bool(ProjectionInitClassic(@projection)), "canonical projection initialized")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90)),
        "camera at (-1,0) heading ANG90 selects node side 1/near leaf 1")
  built = WallVisibilityBuild(@level, @camera, @projection, 0, 0, @result)
  spanCount = WallVisibilityCount(@result)
  Check(Bool(built And spanCount = 1), "online walk emits one near SOLID fragment")
  Check(Bool(WallVisibilityGetStats(@result, @visitedNodes, @visitedSubs,
             @processed, @emitted, 0, 0, 0, 0, 0, 0, @solidC, 0,
             @bboxTests, @bboxVisible, @bboxOccluded, @bboxUnknown,
             @skips, @work, 0, 0, @allocations) And
             visitedNodes = 1 And visitedSubs = 1 And bboxTests = 1 And
             bboxVisible = 0 And bboxOccluded = 1 And bboxUnknown = 0 And
             skips = 1 And allocations >= 1),
        "far box tested once only after near coverage and pruned as occluded")
  Check(Bool(WallVisibilityGetSpan(@result, 0, @sub, @seg, @line, @side,
                                   @front, @back, @first, @last, @kind) And
             sub = 1 And seg = 1 And line = 1 And side = 0 And front = 0 And
             back = -1 And first = 0 And last = 319 And kind = #WALL_KIND_SOLID),
        "published SOLID span is near leaf 1 inclusive [0,319], far leaf pruned")
  Check(Bool(WallVisibilityReset(@result) And WallVisibilityCount(@result) = 0),
        "reset leaves empty owned result after online walk")
  WallVisibilityReset(@result)
  ProjectionReset(@projection)
  MapLevelReset(@level)
  BspCameraReset(@camera)
EndProcedure

; ---------------------------------------------------------------------------
; MR10 - backface/FOV one-pixel and x=0/319 edge behavior
; ---------------------------------------------------------------------------

Procedure TestMR10()
  Protected state.ClipState
  Protected spanCount.l = 0
  Protected fFirst.l = 0
  Protected fLast.l = 0
  Protected kind.l = 0
  Protected i.i

  BeginCase("MR10", "Backface/FOV one-pixel and x=0/319 edge behavior")
  Check(Bool(WallSpanIsBackface(#BAM_ANG180) = 1 And
             WallSpanIsBackface(#BAM_ANG180 - 1) = 0),
        "strong backface predicate is inclusive at ANG180 boundary")
  ClipStateReset(@state)
  Check(Bool(ClipStateBeginFrame(@state, 320)), "clip edge frame begins")
  Check(Bool(ClipPassSegment(@state, 0, 0, 0, 0, 0, 0, 0, -1) And
             ClipStateGetSpan(@state, 0, 0, 0, 0, 0, 0, 0, @fFirst, @fLast, @kind) And
             fFirst = 0 And fLast = 0), "left-screen one-pixel span 0 inclusive")
  Check(Bool(ClipPassSegment(@state, 319, 319, 0, 1, 1, 0, 0, -1) And
             ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @fFirst, @fLast, @kind) And
             fFirst = 319 And fLast = 319), "right-screen one-pixel span 319 inclusive")
  spanCount = 0
  For i = 0 To 1
    If ClipStateGetSpan(@state, i, 0, 0, 0, 0, 0, 0, @fFirst, @fLast, @kind)
      spanCount + 1
    EndIf
  Next
  Check(Bool(spanCount = 2), "both screen edge columns are usable, no off-frame cut")
  ClipStateReset(@state)
EndProcedure

; ---------------------------------------------------------------------------
; MR11 - M3-04 span/counter fingerprints preserved
; ---------------------------------------------------------------------------

Procedure TestMR11()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibilityA.WallVisibilityResult
  Protected visibilityB.WallVisibilityResult
  Protected spanHashA.q = 0
  Protected spanHashB.q = 0
  Protected spanCountA.l = 0
  Protected spanCountB.l = 0
  Protected repeatHash.q = 0
  Protected repeatCount.l = 0
  Protected okA.i = #False
  Protected okB.i = #False
  Protected okRepeat.i = #False

  BeginCase("MR11", "M3-04 span/counter fingerprints preserved, not silently changed")
  Check(Bool(BuildSceneWad("m3rel-ti01.wad", 1)), "synthetic TI01 PWAD built")
  Check(Bool(BuildSceneWad("m3rel-ti02.wad", 2)), "synthetic TI02 PWAD built")
  okA = PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames, @textures,
                                @flats, @colormap, @level, @view, @projection,
                                @visibilityA)
  Check(Bool(okA), "TI01 production session prepared")
  spanCountA = WallVisibilityCount(@visibilityA)
  spanHashA = TestWallSpanHash(@visibilityA)
  Check(Bool(spanCountA = #TEXGOLD_TI01_SpanCount And
             HashTextEquals(spanHashA, Hex64Canonical(PeekQ(*gTI01SpanHash)))),
        "TI01 unchanged M3-04 span fingerprint matches independent fixture")
  Check(Bool(spanHashA <> -1 And TestWallSpanHash(@visibilityA) = spanHashA),
        "TI01 repeated fingerprint read is deterministic")
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibilityA)
  Check(Bool(WADIsOpen() = #False And WallVisibilityReset(@visibilityA)),
        "TI01 session closed and owned visibility reset")

  okB = PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames, @textures,
                                @flats, @colormap, @level, @view, @projection,
                                @visibilityB)
  Check(Bool(okB), "TI02 production session prepared")
  spanCountB = WallVisibilityCount(@visibilityB)
  spanHashB = TestWallSpanHash(@visibilityB)
  Check(Bool(spanCountB = #TEXGOLD_TI02_SpanCount And
             HashTextEquals(spanHashB, Hex64Canonical(PeekQ(*gTI02SpanHash)))),
        "TI02 unchanged M3-04 span fingerprint matches independent fixture")
  ; Repeat Build on a fresh result without re-walking or re-sorting externally.
  WallVisibilityReset(@visibilityA)
  okRepeat = WallVisibilityBuild(@level, @view\Camera, @projection, @flats,
                                @textures, @visibilityA)
  repeatHash = TestWallSpanHash(@visibilityA)
  repeatCount = WallVisibilityCount(@visibilityA)
  Check(Bool(okRepeat And repeatCount = spanCountB And repeatHash = spanHashB),
        "fresh duplicate Build reproduces identical order/counter fingerprint")
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibilityB)
  WallVisibilityReset(@visibilityA)
  Check(Bool(WADIsOpen() = #False And WallVisibilityCount(@visibilityB) = 0),
        "TI02 session closed with no retained WAD pointer in owned result")
EndProcedure

; ---------------------------------------------------------------------------
; MR12 - WallSpanPlan scale and HEIGHTBITS=12 deterministic interpolation
; ---------------------------------------------------------------------------

Procedure TestMR12()
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
  Protected legacy.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected fixtureL.l = 0
  Protected fixtureQ.q = 0
  Protected actualL.l = 0
  Protected actualQ.q = 0
  Protected fieldIndex.l
  Protected qIndex.l
  Protected mismatch.l = 0
  Protected planCount.l = 0
  Protected planIndex.l
  Protected rendered.i = #False

  BeginCase("MR12", "WallSpanPlan scale/HEIGHTBITS=12 deterministic interpolation")
  Check(Bool(#WALLGOLD_HeightBits = 12 And #WALLGOLD_HeightUnit = 4096 And
             #WALLPROJ_HeightBits = 12 And #WALLPROJ_HeightUnit = 4096),
        "HeightBits/HeightUnit constants remain 12/4096")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 session prepared for plan audit")
  Check(Bool(FrameBufferCreate(@target, #M3REL_ViewWidth, #M3REL_ViewHeight)),
        "textured target frame created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  planCount = result\TexturePlanCount
  Check(Bool(rendered And planCount = #TEXGOLD_TI01_SpanCount),
        "one textured plan published per M3-04 span")
  If rendered And planCount = 1
    TexturedWallRenderGetPlan(@result, 0, @legacy)
    TexturedWallRenderGetTexturePlan(@result, 0, @texPlan)
    Check(Bool(WallSpanPlanIsReady(@legacy) And
               WallTextureSpanPlanIsReady(@texPlan)),
          "legacy and textured plan records are ready/owned")
    mismatch = 0
    For fieldIndex = 0 To #TEXGOLD_PlanLFieldCount - 1
      fixtureL = PeekL(*gTI01PlanL + fieldIndex * SizeOf(Long))
      actualL = PlanField(@legacy, @texPlan, fieldIndex)
      If actualL <> fixtureL
        mismatch + (1)
      EndIf
    Next
    Check(Bool(mismatch = 0), "all 62 published plan scalar fields equal fixture")
    mismatch = 0
    For qIndex = 0 To #TEXGOLD_PlanQFieldCount - 1
      fixtureQ = PeekQ(*gTI01PlanQ + qIndex * SizeOf(Quad))
      actualQ = PlanQ(@legacy, @texPlan, qIndex)
      If actualQ <> fixtureQ
        mismatch + (1)
      EndIf
    Next
    Check(Bool(mismatch = 0), "all six raw angle/q fields equal fixture")
    Check(Bool(PlanField(@legacy, @texPlan, 9) = 104857 And
               PlanField(@legacy, @texPlan, 10) = 104857 And
               PlanField(@legacy, @texPlan, 11) = 0 And
               PlanField(@legacy, @texPlan, 24) = 0 And
               PlanField(@legacy, @texPlan, 25) = 0 And
               PlanField(@legacy, @texPlan, 22) = -160559 And
               PlanField(@legacy, @texPlan, 23) = 678297),
          "scale1/scale2/step and 12-bit topfrac/bottomfrac interpolation exact")
    Check(Bool(PlanField(@legacy, @texPlan, 0) = 0 And
               PlanField(@legacy, @texPlan, 6) = 58 And
               PlanField(@legacy, @texPlan, 7) = 262),
          "plan identity/span endpoints reproduce fixture order")
  Else
    Check(#False, "TI01 textured frame rendered for plan audit")
  EndIf
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR13 - one-sided middle tier and clip-close semantics
; ---------------------------------------------------------------------------

Procedure TestMR13()
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
  Protected legacy.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected actual.l = 0
  Protected expected.l = 0
  Protected pixel.l = 0
  Protected middlePixels.l = 0
  Protected rendered.i = #False

  BeginCase("MR13", "One-sided middle tier and clip-close semantics")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 session prepared")
  Check(Bool(FrameBufferCreate(@target, #M3REL_ViewWidth, #M3REL_ViewHeight)),
        "target frame created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rendered), "one-sided middle textured frame succeeds")
  If rendered
    TexturedWallRenderGetPlan(@result, 0, @legacy)
    TexturedWallRenderGetTexturePlan(@result, 0, @texPlan)
    Check(Bool(PlanField(@legacy, @texPlan, 36) = 1 And
               PlanField(@legacy, @texPlan, 34) = 0 And
               PlanField(@legacy, @texPlan, 35) = 0 And
               PlanField(@legacy, @texPlan, 37) = 0),
          "one-sided plan marks middle tier only, no upper/lower/two-sided")
    Check(Bool(PlanField(@legacy, @texPlan, 41) = 1 And
               PlanField(@legacy, @texPlan, 45) = 5505024 And
               PlanField(@legacy, @texPlan, 57) = 4057753),
          "resolved middle slot/texturemid/raw offset equal fixture values")
    middlePixels = result\MiddlePixels
    Check(Bool(middlePixels = #TEXGOLD_TI01_MiddlePixels And middlePixels > 0),
          "middle pixels equal the independent fixture count")
    ; Shared clip close leaves background above/below; rows y=0/y=199 untouched.
    expected = PeekA(*gTI01Frame + 0 * 320 + 160)
    actual = FrameBufferGetPixel(@target, 160, 0)
    Check(Bool(actual = expected),
          "screen row y=0 at middle column matches the clipped fixture")
    expected = PeekA(*gTI01Frame + 199 * 320 + 160)
    actual = FrameBufferGetPixel(@target, 160, 199)
    Check(Bool(actual = expected And expected = 0),
          "screen row y=199 remains background after one-sided clip close")
    expected = PeekA(*gTI01Frame + 90 * 320 + 160)
    actual = FrameBufferGetPixel(@target, 160, 90)
    Check(Bool(actual = expected), "middle-column painted texel matches fixture row")
    ; Column inside [first,last] observable on the sample grid.
    Check(Bool(FrameBufferGetPixel(@target, 0, 90) = PeekA(*gTI01Frame + 90 * 320)), "left of span stays background")
  Else
    Check(#False, "one-sided middle frame rendered")
  EndIf
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR14 - two-sided upper/lower/hole clipping chronology
; ---------------------------------------------------------------------------

Procedure TestMR14()
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
  Protected legacy.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected planIndex.l
  Protected spanCount.l = 0
  Protected texturePlans.l = 0
  Protected maskedMid.l = 0
  Protected maskedDetected.l = 0
  Protected maskedSlotGood.l = 0
  Protected upperPixels.l = 0
  Protected lowerPixels.l = 0
  Protected upperRanges.l = 0
  Protected lowerRanges.l = 0
  Protected zeroBytes.l = 0
  Protected rendered.i = #False

  BeginCase("MR14", "Two-sided upper/lower/hole clipping chronology")
  If BuildSceneWad("m3rel-ti02.wad", 2) = #False
    Check(#False, "synthetic TI02 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI02 portal session prepared")
  Check(Bool(FrameBufferCreate(@target, #M3REL_ViewWidth, #M3REL_ViewHeight)),
        "portal target frame created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rendered), "two-sided portal textured frame succeeds")
  If rendered
    spanCount = result\SpanCount
    texturePlans = result\TexturePlanCount
    Check(Bool(spanCount = #TEXGOLD_TI02_SpanCount And texturePlans = spanCount),
          "four M3-04 spans and one textured plan per span preserved")
    maskedMid = result\MaskedMidSpans
    Check(Bool(maskedMid = #TEXGOLD_TI02_MaskedMidSpans), "masked two-sided middles detected/counted")
    maskedDetected = 0
    maskedSlotGood = 0
    For planIndex = 0 To texturePlans - 1
      TexturedWallRenderGetTexturePlan(@result, planIndex, @texPlan)
      TexturedWallRenderGetPlan(@result, planIndex, @legacy)
      If PlanField(@legacy, @texPlan, 59) = 1
        maskedDetected + (1)
        If PlanField(@legacy, @texPlan, 41) = #WALLTEXSPAN_NoTexture And
           PlanField(@legacy, @texPlan, 44) = 1 And
           texPlan\MidCacheSlot = #WALLTEXSPAN_NoCacheSlot And
           PlanField(@legacy, @texPlan, 37) = 1
          maskedSlotGood + (1)
        EndIf
      EndIf
    Next
    Check(Bool(maskedDetected = 2 And maskedSlotGood = 2),
          "masked middle slot recorded with no composed/painted cache slot")
    upperPixels = result\UpperPixels
    lowerPixels = result\LowerPixels
    upperRanges = result\UpperRanges
    lowerRanges = result\LowerRanges
    Check(Bool(upperPixels = #TEXGOLD_TI02_UpperPixels And
               lowerPixels = #TEXGOLD_TI02_LowerPixels),
          "upper/lower painted pixel totals equal fixture")
    Check(Bool(upperRanges = #TEXGOLD_TI02_UpperRanges And
               lowerRanges = #TEXGOLD_TI02_LowerRanges And
               result\MiddleRanges = #TEXGOLD_TI02_MiddleRanges),
          "upper/lower/middle range chronology equals fixture")
    zeroBytes = result\ZeroBytes
    Check(Bool(zeroBytes = #TEXGOLD_TI02_ZeroBytes),
          "deferred masked middles leave portal background bytes untouched")
    Check(Bool(result\MiddlePixels = #TEXGOLD_TI02_MiddlePixels),
          "masked middles never add opaque middle pixels beyond fixture")
  Else
    Check(#False, "two-sided portal frame rendered")
  EndIf
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR15 - middle pegging default vs ML_DONTPEGBOTTOM with rowoffset
; ---------------------------------------------------------------------------

Procedure TestMR15()
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
  Protected texPlan.WallTextureSpanPlan
  Protected mid.l = 0
  Protected defaultMid.l = 0
  Protected bottomMid.l = 0
  Protected expectedDefault.l = 0
  Protected expectedBottom.l = 0
  Protected rowFixed.l = 0
  Protected viewZ.l = 0
  Protected rendered.i = #False

  BeginCase("MR15", "Middle pegging default vs ML_DONTPEGBOTTOM with rowoffset")
  Check(Bool(FixedFromIntChecked(-3, @rowFixed) And rowFixed = -196608),
        "signed SIDEDEFS rowoffset map unit converts to fixed -196608")
  viewZ = 2686976
  expectedDefault = WallFixedAddLow(5701632, rowFixed)
  expectedBottom = WallFixedAddLow(WallFixedSubLow(WallFixedAddLow(0, 8388608), viewZ), rowFixed)
  Check(Bool(expectedDefault = 5505024), "default mid = front ceiling-viewz+rowoffset")
  Check(Bool(expectedBottom = 5505024), "bottom-peg mid = floor+textureheight-viewz+rowoffset")
  Check(Bool(WallTextureMidOneSidedChecked(5701632, 0, viewZ, 8388608, -3, 0,
                                           @defaultMid) And defaultMid = expectedDefault),
        "default one-sided helper matches source formula")
  Check(Bool(WallTextureMidOneSidedChecked(5701632, 0, viewZ, 8388608, -3,
                                           #MAP_ML_DONTPEGBOTTOM, @bottomMid) And
             bottomMid = expectedBottom), "DONTPEGBOTTOM helper matches source formula")
  expectedDefault = WallFixedAddLow(#FRACUNIT * 128, #FRACUNIT * 7)
  viewZ = 4784128
  rowFixed = #FRACUNIT * 7
  expectedDefault = WallFixedSubLow(8388608, viewZ)
  expectedDefault = WallFixedAddLow(expectedDefault, rowFixed)
  Check(Bool(expectedDefault = 4063232), "distinct default expectation recomputed")
  expectedBottom = WallFixedSubLow(WallFixedAddLow(2097152, 8388608), viewZ)
  expectedBottom = WallFixedAddLow(expectedBottom, rowFixed)
  Check(Bool(WallTextureMidOneSidedChecked(3604480, 2097152, viewZ, 8388608, 7, 0,
                                           @defaultMid) And defaultMid = expectedDefault),
        "distinct floor/ceiling default branch recomputed independently")
  Check(Bool(WallTextureMidOneSidedChecked(3604480, 2097152, viewZ, 8388608, 7,
                                           #MAP_ML_DONTPEGBOTTOM, @bottomMid) And
             bottomMid = expectedBottom And bottomMid <> defaultMid),
        "distinct DONTPEGBOTTOM branch differs and matches rowoffset addition")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 session prepared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI01 target frame created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  If rendered
    TexturedWallRenderGetTexturePlan(@result, 0, @texPlan)
    Check(Bool(texPlan\MidTextureMid = PeekL(*gTI01PlanL + 45 * SizeOf(Long))),
          "production one-sided default texturemid equals fixture value")
  Else
    Check(#False, "TI01 frame rendered for texturemid audit")
  EndIf
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR16 - upper pegging default vs ML_DONTPEGTOP with sky-hack cases
; ---------------------------------------------------------------------------

Procedure TestMR16()
  Protected level.MapLevel
  Protected isSky.l = 0
  Protected skyIndex.l = 0
  Protected defaultMid.l = 0
  Protected topPegMid.l = 0
  Protected expectedDefault.l = 0
  Protected expectedTopPeg.l = 0
  Protected rowFixed.l = 0

  BeginCase("MR16", "Upper default vs ML_DONTPEGTOP with sky-hack cases")
  Check(Bool(FixedFromIntChecked(-8, @rowFixed) And rowFixed = -524288),
        "signed rowoffset -8 converts to fixed -524288")
  expectedTopPeg = WallFixedAddLow(6553599, rowFixed)
  expectedDefault = WallFixedSubLow(WallFixedAddLow(8388608, 9216 * 65536), 2686976)
  expectedDefault = WallFixedAddLow(expectedDefault, rowFixed)
  Check(Bool(WallTextureMidUpperChecked(6553599, 8388608, 2686976,
                                        9216 * 65536, -8, #MAP_ML_DONTPEGTOP,
                                        @topPegMid) And topPegMid = expectedTopPeg),
        "ML_DONTPEGTOP upper mid is worldtop + rowoffset")
  Check(Bool(WallTextureMidUpperChecked(6553599, 8388608, 2686976,
                                        9216 * 65536, -8, 0, @defaultMid) And
             defaultMid = expectedDefault And defaultMid <> topPegMid),
        "default upper mid is least back ceiling+height-viewz+rowoffset")
  Check(Bool(BuildSingleSurfaceLevel(@level, "FLOOR1", "F_SKY1", 0, 128, 160,
                                     "-", 0, 0, 0)), "sky-ceiling zero-node level built")
  Check(Bool(WallSectorSkyChecked(@level, 0, 0, @isSky, @skyIndex) And isSky = 1),
        "canonical F_SKY1 ceiling is detected without catalogs")
  MapLevelReset(@level)
  Check(Bool(BuildSingleSurfaceLevel(@level, "FLOOR1", "CEIL1", 0, 128, 160,
                                     "-", 0, 0, 0)), "non-sky ceiling level rebuilt")
  Check(Bool(WallSectorSkyChecked(@level, 0, 0, @isSky, @skyIndex) And isSky = 0),
        "non-sky ceiling is not misclassified as sky")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; MR17 - lower pegging default vs ML_DONTPEGBOTTOM with rowoffset
; ---------------------------------------------------------------------------

Procedure TestMR17()
  Protected defaultMid.l = 0
  Protected bottomMid.l = 0
  Protected expectedDefault.l = 0
  Protected expectedBottom.l = 0
  Protected rowFixed.l = 0

  BeginCase("MR17", "Lower default vs ML_DONTPEGBOTTOM with rowoffset")
  Check(Bool(FixedFromIntChecked(5, @rowFixed) And rowFixed = 327680),
        "signed rowoffset 5 converts to fixed 327680")
  expectedBottom = WallFixedAddLow(7778060, rowFixed)
  expectedDefault = WallFixedAddLow(-2686976, rowFixed)
  Check(Bool(WallTextureMidLowerChecked(7778060, -2686976, 5, 0, @defaultMid) And
             defaultMid = expectedDefault And defaultMid = -2359296),
        "default lower mid is back floor-viewz + rowoffset")
  Check(Bool(WallTextureMidLowerChecked(7778060, -2686976, 5,
                                        #MAP_ML_DONTPEGBOTTOM, @bottomMid) And
             bottomMid = expectedBottom And bottomMid = 8105740 And
             bottomMid <> defaultMid),
        "DONTPEGBOTTOM lower mid is front worldtop + rowoffset")
EndProcedure

; ---------------------------------------------------------------------------
; MR18 - texture catalog first-match/index-zero/canonical absence
; ---------------------------------------------------------------------------

Procedure TestMR18()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected present.l = 0
  Protected catalogIndex.l = 0
  Protected decoded.i = #False

  BeginCase("MR18", "TextureCatalog first-match, index-zero absence, canonical -/NUL")
  ; Independent in-memory duplicate-definition catalog (no WAD resolution).
  Protected Dim specs.WallTexTextureSpec(1)
  Protected Dim dummyPlac.WallTexPatchPlacement(0)
  Protected *dupBytes.Byte = 0
  Protected dupSize.l = 0
  Protected dupCat.TextureCatalog
  specs(0)\Name = "TEXDUP" : specs(0)\Width = 64 : specs(0)\Height = 128
  specs(0)\Masked = 0 : specs(0)\PatchCount = 0 : specs(0)\Placements = @dummyPlac(0)
  specs(1)\Name = "TEXDUP" : specs(1)\Width = 32 : specs(1)\Height = 64
  specs(1)\Masked = 1 : specs(1)\PatchCount = 0 : specs(1)\Placements = @dummyPlac(0)
  *dupBytes = WallTexMakeTextureLump(@specs(0), 2, @dupSize)
  Check(Bool(*dupBytes <> 0), "synthetic duplicate TEXTURE1 bytes built")
  TextureCatalogReset(@dupCat)
  decoded = TextureCatalogDecode(*dupBytes, dupSize, 0, 0, 0, @dupCat)
  Check(Bool(decoded), "duplicate definitions decode with absent TEXTURE2")
  catalogIndex = TextureCatalogFindName(@dupCat, "TEXDUP")
  Check(Bool(TextureCatalogCount(@dupCat) = 2 And catalogIndex = 0),
        "texture-name lookup is first-match index 0, not last-match")
  If *dupBytes <> 0
    FreeMemory(*dupBytes)
  EndIf
  TextureCatalogReset(@dupCat)

  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 categorical session prepared")
  Check(Bool(TextureCatalogFindName(@textures, "TEXMID") = 1 And
             TextureCatalogFindName(@textures, "TEXUP") = 2 And
             TextureCatalogFindName(@textures, "TEXLO") = 3 And
             TextureCatalogFindName(@textures, "NODEF") = 0),
        "declared definitions resolved to their canonical first indexes")
  MapLevelReset(@level)
  Check(Bool(BuildSingleSurfaceLevel(@level, "FLOOR1", "CEIL1", 0, 128, 160,
                                     "NODEF", 0, 0, 0)),
        "index-zero NODEF middle sidedef map built")
  Check(Bool(WallSideTexturePresentChecked(@level, @textures, 0, 2, @present) And
             present = 0), "resolved catalog index 0 keeps NoTexture absence")
  MapLevelReset(@level)
  Check(Bool(BuildSingleSurfaceLevel(@level, "FLOOR1", "CEIL1", 0, 128, 160,
                                     "", 0, 0, 0)),
        "all-NUL middle name sidedef map built")
  Check(Bool(WallSideTexturePresentChecked(@level, @textures, 0, 2, @present) And
             present = 0), "canonical all-NUL padded name stays absent")
  MapLevelReset(@level)
  Check(Bool(BuildSingleSurfaceLevel(@level, "FLOOR1", "CEIL1", 0, 128, 160,
                                     "-", 0, 0, 0)),
        "canonical '-' sidedef map built")
  Check(Bool(WallSideTexturePresentChecked(@level, @textures, 0, 2, @present) And
             present = 0), "canonical '-' sentinel is skipped without lookup")
  MapLevelReset(@level)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR19 - negative/edge texture columns and vanilla width masks
; ---------------------------------------------------------------------------

Procedure TestMR19()
  Protected mask.l = 0
  Protected wrapped.l = 0
  Protected column.l = 0
  Protected columnFixed.l = 0

  BeginCase("MR19", "Negative/edge texture columns and vanilla width mask 64/96/128/256")
  Check(Bool(WallTextureWidthMaskChecked(64, @mask) And mask = 63), "64-width mask is 63")
  Check(Bool(WallTextureWidthMaskChecked(96, @mask) And mask = 63),
        "96-width mask is highest power <= width-1 = 63, not 95")
  Check(Bool(WallTextureWidthMaskChecked(128, @mask) And mask = 127), "128-width mask is 127")
  Check(Bool(WallTextureWidthMaskChecked(256, @mask) And mask = 255), "256-width mask is 255")
  Check(Bool(WallTextureColumnWrapChecked(-1, 63, 64, @wrapped) And wrapped = 63),
        "negative raw column -1 wraps by vanilla two's-complement & to 63")
  Check(Bool(WallTextureColumnWrapChecked(-65, 63, 64, @wrapped) And wrapped = 63),
        "column -65 & 63 lands 63 without generic modulo")
  Check(Bool(WallTextureColumnWrapChecked(67, 127, 128, @wrapped) And wrapped = 67),
        "in-domain column 67 remains 67 under 128 mask")
  Check(Bool(WallTextureColumnChecked(0, 0, 0, 0, @columnFixed, @column) And
             columnFixed = 0 And column = 0),
        "zero offset/tangent/distance texturecolumn yields exact fixed 0")
EndProcedure

; ---------------------------------------------------------------------------
; MR20 - vertical dc_iscale and exact inclusive texel stepping y=0/y=199
; ---------------------------------------------------------------------------

Procedure TestMR20()
  Protected iscale256.l = 0
  Protected iscale512.l = 0
  Protected iscale2.l = 0
  Protected iscaleProbe.l = 0
  Protected mid.l = 0
  Protected centerY.l = 0
  Protected fracY0.l = 0
  Protected fracY199.l = 0
  Protected expectedY0.l = 0
  Protected expectedY199.l = 0
  Protected wrappedY0.l = 0
  Protected wrappedY199.l = 0
  Protected diffY0.q = 0
  Protected prodY0.q = 0
  Protected diffY199.q = 0
  Protected prodY199.q = 0
  Protected advanced.l = 0
  Protected row0.l = 0
  Protected row199.l = 0
  Protected expectedRow0.l = 0
  Protected expectedRow199.l = 0
  Protected y.l
  Protected i.l

  BeginCase("MR20", "Vertical dc_iscale/texel stepping exact at y=0 and y=199")
  centerY = #PROJ_CENTERY
  mid = PeekL(*gTI01PlanL + 45 * SizeOf(Long))
  Check(Bool(centerY = 100 And mid = 5505024),
        "canonical centerY 100 and fixture one-sided texturemid read")
  iscale256 = PeekL(*gIscales + Int(0) * SizeOf(Long))
  iscale512 = PeekL(*gIscales + Int(1) * SizeOf(Long))
  iscale2 = PeekL(*gIscales + Int(2) * SizeOf(Long))
  Check(Bool(WallTextureIscaleChecked(256, @iscaleProbe) And
             iscaleProbe = iscale256 And iscaleProbe = 16777215),
        "unsigned 0xFFFFFFFF/256 equals fixture dc_iscale 16777215")
  Check(Bool(WallTextureIscaleChecked(512, @iscaleProbe) And
             iscaleProbe = iscale512 And iscaleProbe = 8388607),
        "unsigned 0xFFFFFFFF/512 equals fixture dc_iscale 8388607")
  Check(Bool(WallTextureIscaleChecked(2, @iscaleProbe) And
             iscaleProbe = iscale2 And iscaleProbe = 2147483647),
        "admitted minimum scale 2 yields signed fixed boundary 2147483647")
  Check(Bool(WallTextureIscaleChecked(1, @iscaleProbe) = #False And
             WallTextureIscaleChecked(0, @iscaleProbe) = #False And
             WallTextureIscaleChecked(-3, @iscaleProbe) = #False),
        "scale 1 zero-wrap and nonpositive scale rejected instead of invented")

  ; Independent test-only recomputation of frac=(texturemid + (yl-centery)*iscale)
  ; in documented low-32 C overflow policy, then the source (frac>>16)&127.
  diffY0.q = Int(0) - Int(centerY)
  prodY0.q = diffY0 * Int(iscale256)
  wrappedY0 = FixedWrap32Low(prodY0)
  expectedY0 = WallFixedAddLow(mid, wrappedY0)
  Check(Bool(WallTextureFracChecked(mid, 0, centerY, iscale256, @fracY0) And
             fracY0 = expectedY0),
        "y=0 frac(texturemid-100*iscale) matches independent low32 arithmetic")
  diffY199.q = Int(199) - Int(centerY)
  prodY199.q = diffY199 * Int(iscale256)
  wrappedY199 = FixedWrap32Low(prodY199)
  expectedY199 = WallFixedAddLow(mid, wrappedY199)
  Check(Bool(WallTextureFracChecked(mid, 199, centerY, iscale256, @fracY199) And
             fracY199 = expectedY199),
        "y=199 frac(texturemid+99*iscale) matches independent low32 arithmetic")
  row0 = WallTextureSourceRow128(fracY0)
  expectedRow0 = (fracY0 >> #FRACBITS) & 127
  Check(Bool(row0 = expectedRow0), "y=0 source row equals exact (frac>>16)&127")
  row199 = WallTextureSourceRow128(fracY199)
  expectedRow199 = (fracY199 >> #FRACBITS) & 127
  Check(Bool(row199 = expectedRow199), "y=199 source row equals exact (frac>>16)&127")
  Check(Bool(row0 <> row199), "edge rows 0 and 199 address distinct exact texels")
  advanced = fracY0
  For i = 0 To 198
    advanced = WallTextureFracAdvance(advanced, iscale256)
  Next
  Check(Bool(advanced = fracY199),
        "199 inclusive fracstep advances from y=0 reach y=199 start exactly")
  Check(Bool(fracY199 <> fracY0),
        "full 200-row inclusive stepping changed frac without saturating")
  Check(Bool(WallTextureIscaleChecked(512, @iscaleProbe) And
             iscaleProbe = iscale512),
        "512-scale dc_iscale rechecked before boundary recomputation")
  prodY199.q = diffY199 * Int(iscaleProbe)
  wrappedY199 = FixedWrap32Low(prodY199)
  expectedY199 = WallFixedAddLow(mid, wrappedY199)
  Check(Bool(WallTextureFracChecked(mid, 199, centerY, iscaleProbe, @fracY199) And
             fracY199 = expectedY199),
        "512-scale y=199 frac matches independent low32 arithmetic")
  prodY0.q = diffY0 * Int(iscaleProbe)
  wrappedY0 = FixedWrap32Low(prodY0)
  expectedY0 = WallFixedAddLow(mid, wrappedY0)
  Check(Bool(WallTextureFracChecked(mid, 0, centerY, iscaleProbe, @fracY0) And
             fracY0 = expectedY0),
        "512-scale y=0 frac matches independent low32 arithmetic")
EndProcedure

; ---------------------------------------------------------------------------
; MR21 - non-128 height bounded policy and short-height fallback counts
; ---------------------------------------------------------------------------

Procedure TestMR21()
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
  Protected imageUp.TextureImage
  Protected imageLo.TextureImage
  Protected imageMid.TextureImage
  Protected sourceRow.l = 0
  Protected fallback.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected rendered.i = #False

  BeginCase("MR21", "Bounded <128 height policy and short-height fallback counts")
  Check(Bool(WallTextureSourceRowBounded(127, 128, @sourceRow, @fallback) And
             sourceRow = 127 And fallback = 0),
        "height 128 preserves exact row127 with no fallback")
  Check(Bool(WallTextureSourceRowBounded(127, 256, @sourceRow, @fallback) And
             sourceRow = 127 And fallback = 0),
        "height >128 keeps original first-128 row127, not modulo height")
  Check(Bool(WallTextureSourceRowBounded(127, 72, @sourceRow, @fallback) And
             sourceRow = 55 And fallback = 1),
        "72-height row127 wraps modulo height to bounded row55 with flag")
  Check(Bool(WallTextureSourceRowBounded(127, 64, @sourceRow, @fallback) And
             sourceRow = 63 And fallback = 1),
        "64-height row127 wraps to row63 with explicit fallback flag")
  Check(Bool(WallTextureSourceRowBounded(127, 1, @sourceRow, @fallback) And
             sourceRow = 0 And fallback = 1),
        "1-height fallback stays row0 inside composed plane")
  Check(Bool(WallTextureSourceRowBounded(127, 4096, @sourceRow, @fallback) And
             sourceRow = 127 And fallback = 0),
        "4096 maximum height keeps source row a valid direct row")
  Check(Bool(WallTextureSourceRowBounded(128, 128, @sourceRow, @fallback) = #False And
             WallTextureSourceRowBounded(127, 0, @sourceRow, @fallback) = #False),
        "row128 outside original domain and zero height rejected safely")

  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  If PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames, @textures,
                             @flats, @colormap, @level, @view, @projection,
                             @visibility) = #False
    Check(#False, "TI01 session prepared")
    ProcedureReturn
  EndIf
  TextureImageReset(@imageMid)
  TextureImageReset(@imageUp)
  TextureImageReset(@imageLo)
  Check(Bool(TextureCompose(@textures, 1, @imageMid) And
             WallTextureSampleChecked(@imageMid, 0, 127, @sourceRow,
                                      @opaque, @pixel, @fallback) And
             sourceRow = 127 And fallback = 0 And opaque = 1 And pixel = 37),
        "128-height TEXMID row127 samples exact patchA texel")
  Check(Bool(TextureCompose(@textures, 2, @imageUp) And
             WallTextureSampleChecked(@imageUp, 0, 127, @sourceRow,
                                      @opaque, @pixel, @fallback) And
             sourceRow = 55 And fallback = 1 And opaque = 1 And pixel = 73),
        "short TEXUP 72-height bounded row55 fallback samples patchU texel")
  Check(Bool(TextureCompose(@textures, 3, @imageLo) And
             WallTextureSampleChecked(@imageLo, 0, 127, @sourceRow,
                                      @opaque, @pixel, @fallback) And
             sourceRow = 63 And fallback = 1 And opaque = 1 And pixel = 19),
        "short TEXLO 64-height bounded row63 fallback samples patchLo texel")
  TextureImageReset(@imageMid)
  TextureImageReset(@imageUp)
  TextureImageReset(@imageLo)
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI01 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rendered And result\ShortTextures = #TEXGOLD_TI01_ShortTextures),
        "TI01 frame composes no short textures and reports fixture count 0")
  Check(Bool(result\ShortHeightFallbacks = #TEXGOLD_TI01_ShortHeightFallbacks),
        "TI01 128-height columns report fixture zero short-height fallbacks")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  If BuildSceneWad("m3rel-ti02.wad", 2) = #False
    Check(#False, "synthetic TI02 PWAD built")
    ProcedureReturn
  EndIf
  If PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames, @textures,
                             @flats, @colormap, @level, @view, @projection,
                             @visibility) = #False
    Check(#False, "TI02 session prepared")
    ProcedureReturn
  EndIf
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI02 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rendered And result\ShortTextures = #TEXGOLD_TI02_ShortTextures And
             result\ShortTextures = 2),
        "TI02 frame composes two <128 textures (TEXUP/TEXLO)")
  Check(Bool(result\ShortHeightFallbacks = #TEXGOLD_TI02_ShortHeightFallbacks And
             result\ShortHeightFallbacks = 4143),
        "TI02 bounded fallback counter equals fixture 4143")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR22 - mask0/uncovered index0 vs opaque index0/index255 source semantics
; ---------------------------------------------------------------------------

Procedure TestMR22()
  Protected image.TextureImage
  Protected *pixels.Byte = 0
  Protected *masks.Byte = 0
  Protected pixelCount.q = 8192
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected unitCount.l = 0
  Protected i.i

  BeginCase("MR22", "Mask0 vs opaque index0/255 remain distinct source semantics")
  TextureImageReset(@image)
  *pixels = AllocateMemory(pixelCount)
  *masks = AllocateMemory(pixelCount)
  If *pixels = 0 Or *masks = 0
    Check(#False, "synthetic 64x128 pixel/mask planes allocated")
    If *pixels <> 0
      FreeMemory(*pixels)
    EndIf
    If *masks <> 0
      FreeMemory(*masks)
    EndIf
    ProcedureReturn
  EndIf
  FillMemory(*pixels, Int(pixelCount), 0)
  FillMemory(*masks, Int(pixelCount), 0)
  ; texel (row0,col0): mask0/pixel0 uncovered hole; (row1,col1): mask1/pixel255
  ; opaque; (row2,col2): mask1/pixel0 opaque palette colour; (row3,col3): mask2
  PokeA(*pixels + 0 * 64 + 0, 0)
  PokeA(*masks + 0 * 64 + 0, 0)
  PokeA(*pixels + 1 * 64 + 1, 255)
  PokeA(*masks + 1 * 64 + 1, 1)
  PokeA(*pixels + 2 * 64 + 2, 0)
  PokeA(*masks + 2 * 64 + 2, 1)
  PokeA(*pixels + 3 * 64 + 3, 0)
  PokeA(*masks + 3 * 64 + 3, 2)
  image\Magic = #TEXTURE_ImageMagic
  image\Width = 64
  image\Height = 128
  image\PixelCount = pixelCount
  image\Pixels = *pixels
  image\Mask = *masks
  image\OpaqueCount = 2

  Check(Bool(WallTextureSampleChecked(@image, 0, 0, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             sourceRow = 0 And opaque = 0 And pixel = 0 And fallback = 0),
        "mask0 uncovered texel reports Opaque=0 and composed index0 unchanged")
  Check(Bool(WallTextureSampleChecked(@image, 1, 1, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             sourceRow = 1 And opaque = 1 And pixel = 255 And fallback = 0),
        "mask1 source index255 is ordinary opaque texel, not transparency sentinel")
  Check(Bool(WallTextureSampleChecked(@image, 2, 2, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             sourceRow = 2 And opaque = 1 And pixel = 0 And fallback = 0),
        "mask1 source index0 is opaque palette colour distinct from uncovered hole")
  Check(Bool(WallTextureSampleChecked(@image, 3, 3, @sourceRow, @opaque,
                                      @pixel, @fallback) = #False),
        "mask byte other than 0/1 rejected as malformed source input")
  Check(Bool(FindString(WallTextureMappingLastError(), "non-0/1 byte") > 0),
        "malformed mask diagnostic identifies non-0/1 opacity byte")
  unitCount = 0
  For i = 0 To Int(pixelCount) - 1
    If PeekA(*masks + i) = 1
      unitCount + 1
    EndIf
  Next
  Check(Bool(unitCount = 2 And image\OpaqueCount = 2),
        "owned test image opaque count reflects exactly two mask=1 texels")
  TextureImageReset(@image)
  Check(Bool(image\Magic = 0 And image\Pixels = 0 And image\Mask = 0),
        "manual image reset released both owned planes exactly once")
EndProcedure

; ---------------------------------------------------------------------------
; MR23 - vanilla 16x48 scalelight source formula, light row/scale clamp
; ---------------------------------------------------------------------------

Procedure TestMR23()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected table.WallScalelightTable
  Protected lightNum.l = -1
  Protected scaleIndex.l = -1
  Protected mapIndex.l = -1
  Protected mismatch.l = 0
  Protected expected.l = 0
  Protected levelIndex.l
  Protected scale.l

  BeginCase("MR23", "16x48 scalelight formula, light row correction and scale clamp")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  If PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames, @textures,
                             @flats, @colormap, @level, @view, @projection,
                             @visibility) = #False
    Check(#False, "TI01 session prepared")
    ProcedureReturn
  EndIf
  Check(Bool(ColormapCount(@colormap) = #TEXGOLD_ScalelightMapLevelCount),
        "synthetic COLORMAP exposes 32 classic lighting tables")
  WallScalelightTableReset(@table)
  Check(Bool(WallScalelightTableBuild(@table, @colormap)), "scalelight table built")
  Check(Bool(WallScalelightTableIsValid(@table) And table\Count = 768 And
             table\Capacity = 768 And table\MapIndex <> 0 And table\Allocations = 1),
        "768 Long bins owned with one pre-loop allocation and valid metadata")
  mismatch = 0
  For levelIndex = 0 To 15
    For scale = 0 To 47
      mapIndex = -1
      If WallLightingTableMapIndexChecked(@table, levelIndex, scale,
                                          @mapIndex) = #False
        mismatch + 1
      Else
        expected = PeekL(*gScalelightBins +
                         (levelIndex * 48 + scale) * SizeOf(Long))
        If mapIndex <> expected
          mismatch + 1
        EndIf
      EndIf
    Next
  Next
  Check(Bool(mismatch = 0),
        "all 768 table bins equal independent Python scalelight fixture")
  Check(Bool(WallLightingLightNumChecked(160, 10, 10, 0, 5, 0,
                                         @lightNum) And lightNum = 9),
        "front light160 same-Y vertical correction yields row9")
  Check(Bool(WallLightingLightNumChecked(160, 10, 20, 5, 5, 0,
                                         @lightNum) And lightNum = 11),
        "same-X horizontal correction adds one row to light160 => row11")
  Check(Bool(WallLightingLightNumChecked(160, 10, 20, 0, 5, 0,
                                         @lightNum) And lightNum = 10),
        "neither same Y nor same X diagonal keeps light160 row10")
  Check(Bool(WallLightingLightNumChecked(0, 10, 10, 0, 5, 0,
                                         @lightNum) And lightNum = 0),
        "front light0 vertical decrement clamps to source row0")
  Check(Bool(WallLightingLightNumChecked(270, 10, 20, 5, 5, 0,
                                         @lightNum) And lightNum = 15),
        "front light270 horizontal increment clamps to top row15")
  Check(Bool(WallLightingLightNumChecked(160, 10, 20, 0, 5, 1,
                                         @lightNum) = #False),
        "nonzero dynamic extralight rejected under static zero contract")
  Check(Bool(WallLightingScaleIndexChecked(256, @scaleIndex) And scaleIndex = 0),
        "rw_scale 256 yields column scale index0")
  Check(Bool(WallLightingScaleIndexChecked(4096, @scaleIndex) And scaleIndex = 1),
        "rw_scale 4096 yields column scale index1")
  Check(Bool(WallLightingScaleIndexChecked(196608, @scaleIndex) And scaleIndex = 47),
        "rw_scale 196608 arithmetic index48 clamps to 47")
  Check(Bool(WallLightingScaleIndexChecked(200704, @scaleIndex) And scaleIndex = 47),
        "rw_scale 200704 arithmetic index49 clamps to 47")
  Check(Bool(WallLightingScaleIndexChecked(0, @scaleIndex) = #False And
             WallLightingScaleIndexChecked(-4096, @scaleIndex) = #False),
        "nonpositive column scale rejected instead of signed index invention")
  Check(Bool(WallLightingTableMapIndexChecked(@table, 16, 0, @mapIndex) = #False And
             WallLightingTableMapIndexChecked(@table, 0, 48, @mapIndex) = #False),
        "scalelight row16 and scale index48 rejected outside 16x48 domain")
  Check(Bool(WallScalelightTableReset(@table) And table\MapIndex = 0 And
             table\Count = 0 And table\Allocations = 0),
        "scalelight reset releases owned 768-bin allocation idempotently")
  Check(Bool(WallScalelightTableReset(@table)), "second scalelight reset safe")
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR24 - COLORMAP index mapping with synthetic, known palette bytes
; ---------------------------------------------------------------------------

Procedure TestMR24()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected table.WallScalelightTable
  Protected mapIndex.l = -1
  Protected mapped.l = -1
  Protected expected.l = 0
  Protected mismatch.l = 0
  Protected texel.l

  BeginCase("MR24", "COLORMAP index mapping on known synthetic palette bytes")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  If PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames, @textures,
                             @flats, @colormap, @level, @view, @projection,
                             @visibility) = #False
    Check(#False, "TI01 session prepared")
    ProcedureReturn
  EndIf
  WallScalelightTableReset(@table)
  Check(Bool(WallScalelightTableBuild(@table, @colormap)), "scalelight table built")
  Check(Bool(WallLightingTableMapIndexChecked(@table, 0, 0, @mapIndex) And
             mapIndex = 31),
        "row0 scale0 selects clamped COLORMAP map index31")
  Check(Bool(mapIndex = PeekL(*gScalelightBins + 0)),
        "selected map index equals independent scalelight fixture row0")
  mismatch = 0
  For texel = 0 To 255
    mapped = -1
    If WallLightingWallTexelChecked(@colormap, @table, 0, 0, texel,
                                    @mapped) = #False
      mismatch + 1
    Else
      expected = (texel + #TEXGOLD_ColormapBase +
                  mapIndex * #TEXGOLD_ColormapStep) & 255
      If mapped <> expected
        mismatch + 1
      EndIf
    EndIf
  Next
  Check(Bool(mismatch = 0),
        "all 256 synthetic texels map through known base17/step9 formula")
  expected = ((0 + #TEXGOLD_ColormapBase +
               mapIndex * #TEXGOLD_ColormapStep) & 255)
  Check(Bool(WallLightingWallTexelChecked(@colormap, @table, 0, 0, 0,
                                         @mapped) And mapped = expected And
             expected <> 0),
        "palette index0 maps to a genuine nonzero COLORMAP colour")
  Check(Bool(WallLightingWallTexelChecked(@colormap, @table, 0, 0, 255,
                                         @mapped) And mapped = 39),
        "palette index255 maps ordinarily through COLORMAP to fixture formula")
  Check(Bool(WallLightingWallTexelChecked(@colormap, @table, 0, 0, 256,
                                         @mapped) = #False And
             WallLightingWallTexelChecked(@colormap, @table, 16, 0, 37,
                                         @mapped) = #False),
        "texel256 and lighting row16 rejected outside source domains")
  Check(Bool(WallScalelightTableReset(@table) And table\MapIndex = 0),
        "MR24 scalelight reset released table before session cleanup")
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR25 - masked two-sided middle detected/deferred, portal never opaque-filled
; ---------------------------------------------------------------------------

Procedure TestMR25()
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
  Protected legacy.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected planIndex.l
  Protected maskedPlanCount.l = 0
  Protected maskedSlotGood.l = 0
  Protected maskedTierBad.l = 0
  Protected rendered.i = #False

  BeginCase("MR25", "Masked two-sided middle detected and deferred without opaque fill")
  If BuildSceneWad("m3rel-ti02.wad", 2) = #False
    Check(#False, "synthetic TI02 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI02 portal session prepared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI02 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rendered), "TI02 textured frame succeeds")
  Check(Bool(result\MaskedMidSpans = #TEXGOLD_TI02_MaskedMidSpans And
             result\MaskedMidSpans = 2),
        "cache/frame counters detect exactly two masked two-sided middles")
  Check(Bool(result\ComposedTextures = #TEXGOLD_TI02_Composed And
             result\RequestedReferences = #TEXGOLD_TI02_Requested And
             result\ReusedReferences = #TEXGOLD_TI02_Reused),
        "masked middle slots never add obsolete composition/reference counts")
  maskedPlanCount = 0
  maskedSlotGood = 0
  maskedTierBad = 0
  For planIndex = 0 To result\TexturePlanCount - 1
    If TexturedWallRenderGetPlan(@result, planIndex, @legacy) = #False Or
       TexturedWallRenderGetTexturePlan(@result, planIndex, @texPlan) = #False
      maskedTierBad + 1
      maskedPlanCount + 1
      Continue
    EndIf
    If PlanField(@legacy, @texPlan, 59) = 1
      maskedPlanCount + 1
      If PlanField(@legacy, @texPlan, 41) = #WALLTEXSPAN_NoTexture And
         PlanField(@legacy, @texPlan, 44) <> #WALLTEXSPAN_NoTexture And
         texPlan\MidCacheSlot = #WALLTEXSPAN_NoCacheSlot And
         PlanField(@legacy, @texPlan, 36) = 0 And
         PlanField(@legacy, @texPlan, 37) = 1
        maskedSlotGood + 1
      Else
        maskedTierBad + 1
      EndIf
    EndIf
  Next
  Check(Bool(maskedPlanCount = 2 And maskedSlotGood = 2 And maskedTierBad = 0),
        "two masked plans record no painted middle tier or composed cache slot")
  Check(Bool(result\MiddlePixels = #TEXGOLD_TI02_MiddlePixels And
             result\MiddlePixels = 34030),
        "masked deferred middles never increase opaque middle pixel total")
  Check(Bool(result\ZeroBytes = #TEXGOLD_TI02_ZeroBytes And
             result\ZeroBytes = 25827),
        "portal/floors/sky hole bytes stay index0 background, not opaque fill")
  Check(Bool(result\DrawnPixels = #TEXGOLD_TI02_DrawnPixels And
             result\NonZeroBytes = #TEXGOLD_TI02_NonZeroBytes),
        "drawn/nonzero portal bytes equal fixture after deferred masked middles")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR26 - composed texture reuse without duplicate ownership/free
; ---------------------------------------------------------------------------

Procedure TestMR26()
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
  Protected cache.WallTextureCache
  Protected statCount.l = 0
  Protected statCapacity.l = 0
  Protected statRequested.l = 0
  Protected statReused.l = 0
  Protected statMasked.l = 0
  Protected statShort.l = 0
  Protected statAllocations.l = 0
  Protected statTemp.q = 0
  Protected statPlane.q = 0
  Protected statPeak.q = 0
  Protected entryBytes.q = 0
  Protected expectedPlane.q = 0
  Protected expectedPeak.q = 0
  Protected entryIndex.l = 0
  Protected foundIndex.l = -1
  Protected catalogIndex.l = 0
  Protected priorCatalog.l = 0
  Protected width.l = 0
  Protected height.l = 0
  Protected widthMask.l = 0
  Protected shortHeight.l = 0
  Protected opaqueCount.q = 0
  Protected imagePixels.q = 0
  Protected duplicateCount.l = 0
  Protected ptrA.i = 0
  Protected ptrB.i = 0
  Protected ptrC.i = 0
  Protected i.l
  Protected j.l

  BeginCase("MR26", "Composed texture reuse and unique cache ownership")
  If BuildSceneWad("m3rel-ti02.wad", 2) = #False
    Check(#False, "synthetic TI02 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI02 session prepared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI02 target created")
  TexturedWallRenderResultReset(@result)
  Check(Bool(TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)),
        "TI02 frame publishes plans for cache reuse")
  WallTextureCacheReset(@cache)
  Check(Bool(WallTextureCacheBuild(@level, @textures, result\Plans,
                                   result\SegmentCount, @cache)),
        "cache rebuild while resolved WAD open composes unique textures")
  Check(Bool(WallTextureCacheGetStats(@cache, @statCount, @statCapacity,
                                      @statRequested, @statReused, @statMasked,
                                      @statShort, @statAllocations,
                                      @statTemp, @statPlane, @statPeak)),
        "cache statistics read after reuse build")
  Check(Bool(statCount = #TEXGOLD_TI02_Composed And
             statCapacity = #TEXGOLD_TI02_Composed And
             statRequested = #TEXGOLD_TI02_Requested And
             statReused = #TEXGOLD_TI02_Reused),
        "three unique composed textures absorb seven requested tier references")
  Check(Bool(statMasked = #TEXGOLD_TI02_MaskedMidSpans And
             statShort = #TEXGOLD_TI02_ShortTextures And statShort = 2),
        "cache mask/short counts remain fixture-identical after reuse")
  Check(Bool(statAllocations = #TEXGOLD_TI02_CacheAllocations And
             statAllocations = 8),
        "cache owns temp + entries + exactly two planes per composed texture")
  Check(Bool(statTemp = 5 * SizeOf(Long)),
        "uniqueness temp array bytes equal catalog count five Long slots")
  entryBytes = 3 * SizeOf(WallTextureEntry)
  expectedPlane = Int(64) * Int(128) * 2 + Int(96) * Int(72) * 2 +
                  Int(64) * Int(64) * 2
  Check(Bool(statPlane = expectedPlane And statPlane = 38400),
        "retained composed plane bytes equal MID+UP+LO dimension budget")
  expectedPeak = statTemp + entryBytes + expectedPlane
  Check(Bool(statPeak = expectedPeak),
        "cache peak bytes equal temp + entry array + retained planes")

  foundIndex = WallTextureCacheFindIndex(@cache, 1)
  Check(Bool(foundIndex >= 0 And
             WallTextureCacheEntryGet(@cache, foundIndex, @catalogIndex,
                                      @width, @height, @widthMask,
                                      @shortHeight, @opaqueCount,
                                      @imagePixels) And
             catalogIndex = 1 And width = 64 And height = 128 And
             widthMask = 63 And shortHeight = 0 And opaqueCount = 8192 And
             imagePixels = 8192),
        "TEXMID unique entry keeps exact 64x128 metadata and opaque plane count")
  foundIndex = WallTextureCacheFindIndex(@cache, 2)
  Check(Bool(foundIndex >= 0 And
             WallTextureCacheEntryGet(@cache, foundIndex, @catalogIndex,
                                      @width, @height, @widthMask,
                                      @shortHeight, @opaqueCount,
                                      @imagePixels) And
             catalogIndex = 2 And width = 96 And height = 72 And
             widthMask = 63 And shortHeight = 1 And opaqueCount = 6912 And
             imagePixels = 6912),
        "TEXUP short entry keeps exact 96x72 metadata and width mask63")
  foundIndex = WallTextureCacheFindIndex(@cache, 3)
  Check(Bool(foundIndex >= 0 And
             WallTextureCacheEntryGet(@cache, foundIndex, @catalogIndex,
                                      @width, @height, @widthMask,
                                      @shortHeight, @opaqueCount,
                                      @imagePixels) And
             catalogIndex = 3 And width = 64 And height = 64 And
             widthMask = 63 And shortHeight = 1 And opaqueCount = 4096 And
             imagePixels = 4096),
        "TEXLO short entry keeps exact 64x64 metadata and width mask63")
  duplicateCount = 0
  For i = 0 To statCount - 1
    If WallTextureCacheEntryGet(@cache, i, @catalogIndex, 0, 0, 0, 0, 0, 0)
      priorCatalog = catalogIndex
      For j = 0 To i - 1
        If WallTextureCacheEntryGet(@cache, j, @catalogIndex, 0, 0, 0, 0, 0, 0)
          If catalogIndex = priorCatalog
            duplicateCount + 1
          EndIf
        EndIf
      Next
    Else
      duplicateCount + 1
    EndIf
  Next
  Check(Bool(duplicateCount = 0),
        "cache entry array contains no duplicate catalog texture ownership")
  ptrA = WallTextureCacheImagePtr(@cache, 0)
  ptrB = WallTextureCacheImagePtr(@cache, 1)
  ptrC = WallTextureCacheImagePtr(@cache, 2)
  Check(Bool(ptrA <> 0 And ptrB <> 0 And ptrC <> 0 And
             ptrA <> ptrB And ptrB <> ptrC And ptrA <> ptrC),
        "composed images are distinct embedded entry planes without shared aliasing")
  Check(Bool(WallTextureCacheReset(@cache)), "cache reset releases three entry images")
  Check(Bool(WallTextureCacheGetStats(@cache, @statCount, @statCapacity,
                                      @statRequested, @statReused, @statMasked,
                                      @statShort, @statAllocations,
                                      @statTemp, @statPlane, @statPeak) And
             statCount = 0 And statCapacity = 0 And statAllocations = 0 And
             statTemp = 0 And statPlane = 0 And statPeak = 0),
        "reset leaves empty reusable zero-allocation cache statistics")
  Check(Bool(WallTextureCacheReset(@cache)), "second cache reset idempotent")
  Check(Bool(WallTextureCacheBuild(@level, @textures, result\Plans,
                                   result\SegmentCount, @cache)),
        "cache re-build after double reset while WAD open succeeds")
  Check(Bool(WallTextureCacheGetStats(@cache, @statCount, @statCapacity,
                                      @statRequested, @statReused, @statMasked,
                                      @statShort, @statAllocations,
                                      @statTemp, @statPlane, @statPeak) And
             statCount = 3 And statRequested = 7 And statReused = 4 And
             statAllocations = 8 And statPlane = 38400),
        "rebuilt cache reproduces reuse/ownership counters without duplication")
  Check(Bool(WallTextureCacheReset(@cache)), "rebuilt cache released before cleanup")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR27 - absent/unresolved/corrupt resources rejected without publication
; ---------------------------------------------------------------------------

Procedure TestMR27()
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
  Protected cache.WallTextureCache
  Protected Dim badPlans.WallSpanPlan(0)
  Protected absentPrepared.i = #False
  Protected targetHashBefore.q = 0
  Protected targetHashAfter.q = 0
  Protected rejected.i = #False
  Protected statCount.l = 0
  Protected statCapacity.l = 0
  Protected statRequested.l = 0
  Protected statReused.l = 0
  Protected statMasked.l = 0
  Protected statShort.l = 0
  Protected statAllocations.l = 0
  Protected statTemp.q = 0
  Protected statPlane.q = 0
  Protected statPeak.q = 0

  BeginCase("MR27", "Absent/unresolved/corrupt resources rejected safely")
  Check(Bool(BuildReleaseSceneWad("m3rel-mr27-absent.wad", 0, 37, 201, 73,
                                  19, 17, 9, 0, #False, #False)),
        "synthetic PWAD without TEXTURE/PNAMES/COLORMAP built")
  absentPrepared = PrepareSyntheticSession("m3rel-mr27-absent.wad", "", @pnames,
                                           @textures, @flats, @colormap, @level,
                                           @view, @projection, @visibility)
  Check(Bool(absentPrepared = #False And TextureCatalogCount(@textures) = 0),
        "missing texture catalog rejected before map startup")
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "target frame created")
  TexturedWallRenderResultReset(@result)
  rejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rejected = #False), "renderer rejects absent catalog/map/view safely")
  Check(Bool(TexturedWallRenderResultIsValid(@result) And result\Ready = 0 And
             result\Plans = 0 And result\TexturePlans = 0 And
             result\Allocations = 0),
        "failure leaves reusable empty result with no metadata allocation")
  targetHashBefore = TestFrameHash(@target)
  rejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  targetHashAfter = TestFrameHash(@target)
  Check(Bool(rejected = #False And targetHashAfter = targetHashBefore),
        "repeated absent-resource rejection never publishes to target")
  Check(Bool(TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility,
                                     0, @result, 1) = #False),
        "null target framebuffer rejected transactionally")
  Check(Bool(TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     0, 1) = #False),
        "null result pointer rejected before target release")
  Check(Bool(TexturedWallRenderResultReset(@result) And
             TexturedWallRenderResultReset(@result)),
        "double result reset idempotent after null-pointer rejections")
  FrameBufferReset(@target)

  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 categorical session prepared for corruption probes")
  WallTextureCacheReset(@cache)
  Check(Bool(WallTextureCacheBuild(@level, @textures, @badPlans(0), 1,
                                   @cache) = #False),
        "unready zero-Magic WallSpanPlan rejected by cache build")
  Check(Bool(WallTextureCacheGetStats(@cache, @statCount, @statCapacity,
                                      @statRequested, @statReused, @statMasked,
                                      @statShort, @statAllocations,
                                      @statTemp, @statPlane, @statPeak) And
             statCount = 0 And statCapacity = 0 And statAllocations = 0),
        "failed cache build rolls back to empty reusable zero-allocation cache")
  Check(Bool(ColormapReset(@colormap)), "valid COLORMAP deliberately cleared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "MR27 probe target created")
  TexturedWallRenderResultReset(@result)
  targetHashBefore = TestFrameHash(@target)
  rejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  targetHashAfter = TestFrameHash(@target)
  Check(Bool(rejected = #False), "renderer rejects cleared/absent COLORMAP")
  Check(Bool(FindString(TexturedWallRenderLastError(), "COLORMAP") > 0),
        "COLORMAP rejection diagnostic names the missing resource")
  Check(Bool(targetHashAfter = targetHashBefore And
             TexturedWallRenderResultIsValid(@result) And result\Ready = 0),
        "COLORMAP rejection preserves target bytes and empty reusable result")
  Check(Bool(WallTextureCacheReset(@cache) And WallTextureCacheReset(@cache)),
        "cache reset remains idempotent after failure probes")
  Check(Bool(ColormapReset(@colormap)), "second COLORMAP reset safe")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR28 - late and early failures never modify an existing target frame
; ---------------------------------------------------------------------------

Procedure TestMR28()
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
  Protected targetHashBefore.q = 0
  Protected targetHashAfter.q = 0
  Protected rendered.i = #False
  Protected lateRejected.i = #False
  Protected earlyRejected.i = #False

  BeginCase("MR28", "Failed resource/late render preserves existing target byte-for-byte")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 session prepared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  targetHashBefore = TestFrameHash(@target)
  Check(Bool(rendered And targetHashBefore = FixtureHashAt(*gTI01Hash) And
             result\Hash = FixtureHashAt(*gTI01Hash)),
        "success frame publishes exact fixture target before failure probes")

  ; Failure A: WAD invalidated after resource/catalog decode, cache composition
  ; requiring the open current WAD detects it before any pixel draw.
  WADClose()
  Check(Bool(WADIsOpen() = #False), "resource WAD deliberately invalidated without stale access")
  lateRejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                         @textures, @colormap, @visibility,
                                         @target, @result, 1)
  targetHashAfter = TestFrameHash(@target)
  Check(Bool(lateRejected = #False And targetHashAfter = targetHashBefore),
        "closed-WAD cache failure leaves target exact previously published bytes")
  Check(Bool(TexturedWallRenderResultIsValid(@result) And result\Ready = 0 And
             result\Plans = 0 And result\TexturePlans = 0),
        "closed-WAD failure finalizer released plan metadata and emptied result")
  Check(Bool(FindString(TexturedWallRenderLastError(), "WAD") > 0),
        "closed-WAD failure diagnostic names stale resource lifetime")

  Check(Bool(WADOpen(WallTexFixturePath("m3rel-ti01.wad"))), "same synthetic WAD reopened")
  Check(Bool(WADIsOpen()), "reopened WAD session is active for probe two")
  Check(Bool(WallVisibilityReset(@visibility) And visibility\Count = 0),
        "published visibility deliberately reset to zero spans")

  ; Failure B: no spans plus RequireDrawnPixels=1 fails only after plans, cache,
  ; lighting, private frame construction/hash prep; target release not reached.
  lateRejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                         @textures, @colormap, @visibility,
                                         @target, @result, 1)
  targetHashAfter = TestFrameHash(@target)
  Check(Bool(lateRejected = #False), "zero-span expected-visible frame rejected")
  Check(Bool(FindString(TexturedWallRenderLastError(), "zero textured wall pixels") > 0),
        "late zero-pixel diagnostic names the transaction failure phase")
  Check(Bool(targetHashAfter = targetHashBefore And
             result\Ready = 0 And result\Plans = 0),
        "deep-stage failure preserves target bytes and releases all metadata")
  Check(Bool(TexturedWallRenderResultReset(@result) And
             TexturedWallRenderResultReset(@result)),
        "failed-result Reset is idempotent twice")
  Check(Bool(WallVisibilityReset(@visibility)), "visibility reset remains idempotent")
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR29 - repeated build/reset/WADClose releases every owned allocation
; ---------------------------------------------------------------------------

Procedure TestMR29()
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
  Protected cache.WallTextureCache
  Protected statCount.l = 0
  Protected statCapacity.l = 0
  Protected statRequested.l = 0
  Protected statReused.l = 0
  Protected statMasked.l = 0
  Protected statShort.l = 0
  Protected statAllocations.l = 0
  Protected statTemp.q = 0
  Protected statPlane.q = 0
  Protected statPeak.q = 0
  Protected firstBuildCount.l = 0
  Protected firstBuildAlloc.l = 0
  Protected firstTemp.q = 0
  Protected firstPlane.q = 0
  Protected firstPeak.q = 0
  Protected frameAlloc.l = 0
  Protected frameHash.q = 0
  Protected repeatAlloc.l = 0
  Protected repeatHash.q = 0
  Protected targetHash.q = 0
  Protected closedRejected.i = #False
  Protected rep.l

  BeginCase("MR29", "Repeated Build/Reset/WADClose ownership and idempotence")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 session prepared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "target created")
  TexturedWallRenderResultReset(@result)
  Check(Bool(TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)), "initial textured frame succeeds")
  frameAlloc = result\Allocations
  frameHash = TestFrameHash(@target)
  Check(Bool(frameHash = FixtureHashAt(*gTI01Hash) And result\Hash = frameHash And
             frameAlloc = #TEXGOLD_TI01_Allocations),
        "initial frame reports fixture hash and exact 9 allocation events")

  WallTextureCacheReset(@cache)
  Check(Bool(WallTextureCacheBuild(@level, @textures, result\Plans,
                                   result\SegmentCount, @cache)),
        "cache first build while WAD open")
  Check(Bool(WallTextureCacheGetStats(@cache, @statCount, @statCapacity,
                                      @statRequested, @statReused, @statMasked,
                                      @statShort, @statAllocations,
                                      @statTemp, @statPlane, @statPeak)),
        "first cache statistics")
  firstBuildCount = statCount
  firstBuildAlloc = statAllocations
  firstTemp = statTemp
  firstPlane = statPlane
  firstPeak = statPeak
  Check(Bool(firstBuildCount = 1 And firstBuildAlloc = 4 And firstTemp = 20 And
             firstPlane = 16384),
        "one MID plane build costs four caller allocations and 16384 plane bytes")
  Check(Bool(WallTextureCacheReset(@cache)), "first cache reset")
  Check(Bool(WallTextureCacheGetStats(@cache, @statCount, @statCapacity,
                                      @statRequested, @statReused, @statMasked,
                                      @statShort, @statAllocations,
                                      @statTemp, @statPlane, @statPeak) And
             statCount = 0 And statAllocations = 0 And statTemp = 0 And
             statPlane = 0 And statPeak = 0),
        "first reset clears counters and retains empty Magic object")
  Check(Bool(WallTextureCacheBuild(@level, @textures, result\Plans,
                                   result\SegmentCount, @cache)),
        "cache rebuild after reset")
  Check(Bool(WallTextureCacheGetStats(@cache, @statCount, @statCapacity,
                                      @statRequested, @statReused, @statMasked,
                                      @statShort, @statAllocations,
                                      @statTemp, @statPlane, @statPeak) And
             statCount = firstBuildCount And
             statAllocations = firstBuildAlloc And statTemp = firstTemp And
             statPlane = firstPlane And statPeak = firstPeak),
        "rebuild reproduces exact counters without accumulation")
  Check(Bool(WallTextureCacheReset(@cache) And WallTextureCacheReset(@cache)),
        "cache double reset idempotent after rebuild")
  Check(Bool(cache\Entries = 0 And cache\Count = 0 And cache\Capacity = 0),
        "cache reset clears owning entry pointer for eventual WADClose")

  ; Two fresh result/target cycles of the same frame must not drift counters/hash.
  repeatAlloc = 0
  repeatHash = 0
  For rep = 1 To 2
    TexturedWallRenderResultReset(@result)
    FrameBufferReset(@target)
    Check(Bool(FrameBufferCreate(@target, 320, 200)),
          "repeat target recreated for frame cycle " + Str(rep))
    Check(Bool(TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                       @textures, @colormap, @visibility,
                                       @target, @result, 1)),
          "repeat textured frame cycle " + Str(rep) + " succeeds")
    repeatHash = TestFrameHash(@target)
    repeatAlloc = result\Allocations
    Check(Bool(repeatHash = frameHash And repeatAlloc = frameAlloc),
          "repeat cycle " + Str(rep) + " is deterministic in hash and allocations")
  Next
  TexturedWallRenderResultReset(@result)
  Check(Bool(result\Plans = 0 And result\TexturePlans = 0 And
             result\SpanCount = 0 And result\Allocations = 0),
        "repeated result reset unloads plan metadata and counters")
  targetHash = TestFrameHash(@target)
  FrameBufferReset(@target)

  WADClose()
  Check(Bool(WADIsOpen() = #False And WADGetFileSize() = 0),
        "WADClose after all resets clears session/file-size state without stale access")
  TexturedWallRenderResultReset(@result)
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "closed-WAD probe target")
  closedRejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                           @textures, @colormap, @visibility,
                                           @target, @result, 1)
  Check(Bool(closedRejected = #False And TestFrameHash(@target) <> -1),
        "frame after WADClose rejected before target publication")
  Check(Bool(TexturedWallRenderResultReset(@result) And
             TexturedWallRenderResultReset(@result)),
        "failed closed-WAD result reset idempotent")
  Check(Bool(WallTextureCacheReset(@cache)), "cache reset safe while WAD closed")
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR30 - synthetic WAD A->B->A invalidates and re-resolves patch indices
; ---------------------------------------------------------------------------

Procedure TestMR30()
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
  Protected imageMid.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected midIndex.l = -1
  Protected targetHashA1.q = 0
  Protected targetHashA2.q = 0
  Protected targetHashB.q = 0
  Protected renderedA1.i = #False
  Protected renderedB.i = #False
  Protected renderedA2.i = #False

  BeginCase("MR30", "Synthetic WAD A->B->A re-resolves patch/composition indexes")
  Check(Bool(BuildReleaseSceneWad("m3rel-aba-a.wad", 1, 37, 201, 73, 19,
                                  17, 9, 32, #True, #True, #False)),
        "variant A fixture-color T01 PWAD built")
  Check(Bool(PrepareSyntheticSession("m3rel-aba-a.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "variant A resources/map/camera/visibility prepared")
  midIndex = TextureCatalogFindName(@textures, "TEXMID")
  Check(Bool(midIndex = 1), "variant A TEXMID resolves canonical index1")
  TextureImageReset(@imageMid)
  Check(Bool(TextureCompose(@textures, Int(midIndex), @imageMid) And
             WallTextureSampleChecked(@imageMid, 0, 0, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             pixel = 37 And opaque = 1),
        "variant A composed pixel column0 row0 is patchA color37")
  Check(Bool(WallTextureSampleChecked(@imageMid, 32, 0, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             pixel = 201 And opaque = 1),
        "variant A composed pixel column32 row0 is patchB color201")
  TextureImageReset(@imageMid)
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "variant A target created")
  TexturedWallRenderResultReset(@result)
  renderedA1 = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                       @textures, @colormap, @visibility, @target,
                                       @result, 1)
  targetHashA1 = TestFrameHash(@target)
  Check(Bool(renderedA1 And targetHashA1 = FixtureHashAt(*gTI01Hash) And
             result\Hash = targetHashA1),
        "variant A full frame equals locked TI01 fixture hash")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  Check(Bool(BuildReleaseSceneWad("m3rel-aba-a.wad", 1, 99, 211, 73, 19,
                                  20, 11, 32, #True, #True, #False)),
        "variant B rewrote the same synthetic WAD path with new payload colors")
  Check(Bool(PrepareSyntheticSession("m3rel-aba-a.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "variant B re-opened/re-resolved catalog/map across WAD session change")
  midIndex = TextureCatalogFindName(@textures, "TEXMID")
  TextureImageReset(@imageMid)
  Check(Bool(midIndex = 1 And
             TextureCompose(@textures, Int(midIndex), @imageMid) And
             WallTextureSampleChecked(@imageMid, 0, 0, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             pixel = 99 And opaque = 1),
        "variant B fresh composition column0 row0 re-resolves patchA color99")
  Check(Bool(WallTextureSampleChecked(@imageMid, 32, 0, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             pixel = 211 And opaque = 1),
        "variant B fresh composition column32 row0 re-resolves patchB color211")
  TextureImageReset(@imageMid)
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "variant B target created")
  TexturedWallRenderResultReset(@result)
  renderedB = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                      @textures, @colormap, @visibility, @target,
                                      @result, 1)
  targetHashB = TestFrameHash(@target)
  Check(Bool(renderedB And targetHashB <> targetHashA1),
        "variant B frame differs instead of silently reusing stale variant A pixels")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  Check(Bool(BuildReleaseSceneWad("m3rel-aba-a.wad", 1, 37, 201, 73, 19,
                                  17, 9, 32, #True, #True, #False)),
        "variant A payload restored to the original synthetic WAD bytes")
  Check(Bool(PrepareSyntheticSession("m3rel-aba-a.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "variant A second session re-resolved after B")
  midIndex = TextureCatalogFindName(@textures, "TEXMID")
  TextureImageReset(@imageMid)
  Check(Bool(midIndex = 1 And
             TextureCompose(@textures, Int(midIndex), @imageMid) And
             WallTextureSampleChecked(@imageMid, 0, 0, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             pixel = 37 And opaque = 1),
        "A->B->A second composition re-resolves patchA color37, not cache B")
  Check(Bool(WallTextureSampleChecked(@imageMid, 32, 0, @sourceRow, @opaque,
                                      @pixel, @fallback) And
             pixel = 201 And opaque = 1),
        "A->B->A second composition re-resolves patchB color201, not static index")
  TextureImageReset(@imageMid)
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "returned variant A target created")
  TexturedWallRenderResultReset(@result)
  renderedA2 = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                       @textures, @colormap, @visibility,
                                       @target, @result, 1)
  targetHashA2 = TestFrameHash(@target)
  Check(Bool(renderedA2 And targetHashA2 = targetHashA1 And
             targetHashA2 = FixtureHashAt(*gTI01Hash) And result\Hash = targetHashA2),
        "A->B->A full frame returns exact first-A TI01 fixture hash")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR31 - debug-colour raw frame unchanged by independent textured-mode runs
; ---------------------------------------------------------------------------

Procedure TestMR31()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected debugTarget.FrameBuffer
  Protected debugResult.WallRenderResult
  Protected texturedTarget.FrameBuffer
  Protected texturedResult.TexturedWallRenderResult
  Protected debugHash.q = 0
  Protected debugHashRepeat.q = 0
  Protected texturedHash.q = 0
  Protected debugDrawn.l = 0
  Protected debugRendered.i = #False
  Protected texturedRendered.i = #False

  BeginCase("MR31", "Debug-colour raw frame unchanged by independent textured mode")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 session prepared")
  Check(Bool(FrameBufferCreate(@debugTarget, 320, 200)), "debug target created")
  WallRenderResultReset(@debugResult)
  debugRendered = WallRenderFrame(@level, @view, @projection, @flats,
                                  @textures, @visibility, @debugTarget,
                                  @debugResult, 1)
  debugHash = TestFrameHash(@debugTarget)
  debugDrawn = debugResult\DrawnPixels
  Check(Bool(debugRendered And debugHash <> -1 And
             debugResult\Hash = debugHash And debugDrawn > 0),
        "M3-05 debug-colour frame publishes deterministic raw hash and pixels")
  Check(Bool(FrameBufferCreate(@texturedTarget, 320, 200)),
        "independent textured target created")
  TexturedWallRenderResultReset(@texturedResult)
  texturedRendered = TexturedWallRenderFrame(@level, @view, @projection,
                                             @flats, @textures, @colormap,
                                             @visibility, @texturedTarget,
                                             @texturedResult, 1)
  texturedHash = TestFrameHash(@texturedTarget)
  Check(Bool(texturedRendered And texturedHash = FixtureHashAt(*gTI01Hash)),
        "M3-06 textured run writes a separate fixture target")
  Check(Bool(TestFrameHash(@debugTarget) = debugHash And
             debugResult\Hash = debugHash And
             debugDrawn = debugResult\DrawnPixels),
        "debug raw frame bytes/hash/counters unchanged by textured-mode run")
  Check(Bool(texturedHash <> debugHash),
        "debug-colour and textured modes remain distinct target outputs")
  WallRenderResultReset(@debugResult)
  debugRendered = WallRenderFrame(@level, @view, @projection, @flats,
                                  @textures, @visibility, @debugTarget,
                                  @debugResult, 1)
  debugHashRepeat = TestFrameHash(@debugTarget)
  Check(Bool(debugRendered And debugHashRepeat = debugHash And
             debugResult\Hash = debugHash),
        "debug rerender on same target reproduces identical raw bytes/hash")
  WallRenderResultReset(@debugResult)
  FrameBufferReset(@debugTarget)
  TexturedWallRenderResultReset(@texturedResult)
  FrameBufferReset(@texturedTarget)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR32 - synthetic textured fixture/full-plane independent oracle equality
; ---------------------------------------------------------------------------

Procedure TestMR32()
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
  Protected rendered.i = #False
  Protected frameHash.q = 0
  Protected spanHash.q = 0
  Protected spanCount.l = 0

  BeginCase("MR32", "Synthetic textured full-plane fixture hashes independent oracle")
  If BuildSceneWad("m3rel-ti01.wad", 1) = #False
    Check(#False, "synthetic TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI01 session prepared")
  spanHash = TestWallSpanHash(@visibility)
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanHash = #TEXGOLD_TI01_SpanHash And
             spanCount = #TEXGOLD_TI01_SpanCount),
        "M3-04 TI01 span count/fingerprint equal independent fixture")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI01 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  frameHash = TestFrameHash(@target)
  Check(Bool(rendered And frameHash = FixtureHashAt(*gTI01Hash) And
             result\Hash = FixtureHashAt(*gTI01Hash)),
        "TI01 target full-plane FNV equals Python generated fixture hash")
  Check(Bool(result\NonZeroBytes = #TEXGOLD_TI01_NonZeroBytes And
             result\ZeroBytes = #TEXGOLD_TI01_ZeroBytes And
             result\NonZeroBytes + result\ZeroBytes = 64000),
        "TI01 byte audit equal fixture non/zero totals over exactly 64000 bytes")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  If BuildSceneWad("m3rel-ti02.wad", 2) = #False
    Check(#False, "synthetic TI02 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI02 session prepared")
  spanHash = TestWallSpanHash(@visibility)
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanHash = #TEXGOLD_TI02_SpanHash And
             spanCount = #TEXGOLD_TI02_SpanCount),
        "M3-04 TI02 four-span fingerprint equals independent fixture")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI02 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  frameHash = TestFrameHash(@target)
  Check(Bool(rendered And frameHash = FixtureHashAt(*gTI02Hash) And
             result\Hash = FixtureHashAt(*gTI02Hash)),
        "TI02 target full-plane FNV equals Python generated fixture hash")
  Check(Bool(result\UpperPixels = #TEXGOLD_TI02_UpperPixels And
             result\LowerPixels = #TEXGOLD_TI02_LowerPixels And
             result\MiddlePixels = #TEXGOLD_TI02_MiddlePixels),
        "TI02 upper/lower/middle pixel tiers equal independent fixture counts")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR33 - raw 320x200 FNV-1a64 over exact 64000 palette-index bytes
; ---------------------------------------------------------------------------

Procedure TestMR33()
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
  Protected rendered.i = #False
  Protected frameHash.q = 0
  Protected auditNonZero.l = 0
  Protected auditZero.l = 0

  BeginCase("MR33", "Raw 320x200 FNV over exactly 64000 palette bytes")
  If BuildSceneWad("m3rel-ti02.wad", 2) = #False
    Check(#False, "synthetic TI02 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI02 session prepared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI02 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  frameHash = TestFrameHash(@target)
  Check(Bool(rendered), "TI02 frame rendered for exact-plane hash audit")
  Check(Bool(target\Width = 320 And target\Height = 200 And
             target\PixelCount = 64000 And target\Pixels <> 0),
        "committed target is canonical 320x200 row-major 64000-byte plane")
  Check(Bool(#M3REL_FramePixelCount = 64000 And #TEXGOLD_PixelCount = 64000),
        "harness and fixture pixel-count constants both exactly 64000")
  Check(Bool(frameHash <> -1 And frameHash = result\Hash And
             frameHash = FixtureHashAt(*gTI02Hash)),
        "independent FNV over target bytes equals production and fixture hash")
  Check(Bool(TexturedWallFrameByteAudit(@target, @auditNonZero, @auditZero) And
             auditNonZero = result\NonZeroBytes And
             auditZero = result\ZeroBytes And
             auditNonZero + auditZero = 64000),
        "independent byte audit covers all 64000 bytes and agrees with result")
  Check(Bool(TestFrameHash(@target) = frameHash),
        "second independent full-plane recompute is deterministic")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR34 - nearest-neighbour 3x conversion: every source pixel becomes 3x3xRGB
; ---------------------------------------------------------------------------

Procedure TestMR34()
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
  Protected palette.PaletteSet
  Protected *baseRGBA.Byte = 0
  Protected *scaledRGBA.Byte = 0
  Protected baseBytes.q = 0
  Protected scaledBytes.q = 0
  Protected baseOffset.i = 0
  Protected scaledOffset.i = 0
  Protected scaledWord.l = 0
  Protected baseWord.l = 0
  Protected mismatch.l = 0
  Protected found90X.i = -1
  Protected found90Y.i = -1
  Protected found254X.i = -1
  Protected found254Y.i = -1
  Protected rawPixel.l = 0
  Protected r90.i = 0
  Protected g90.i = 0
  Protected b90.i = 0
  Protected r254.i = 0
  Protected g254.i = 0
  Protected b254.i = 0
  Protected rendered.i = #False
  Protected converted.i = #False
  Protected scaled.i = #False
  Protected x.i
  Protected y.i
  Protected blockX.i
  Protected blockY.i

  BeginCase("MR34", "Nearest-neighbour 3x: every source pixel exact 3x3 RGBA")
  Check(Bool(BuildReleaseSceneWad("m3rel-mr34.wad", 1, 37, 201, 73, 19,
                                  17, 9, 32, #True, #True, #True)),
        "fixture T01 scene with synthetic gradient palette built")
  Check(Bool(PrepareSyntheticSession("m3rel-mr34.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "gradient-palette TI01 session prepared")
  Check(Bool(DecodeSyntheticPalette(@palette) And PaletteCount(@palette) = 1),
        "synthetic 768-byte PLAYPAL decoded while WAD open")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "raw 320x200 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rendered And TestFrameHash(@target) = FixtureHashAt(*gTI01Hash)),
        "raw indexed frame remains fixture-exact independent of RGB palette")
  baseBytes = Int(320) * Int(200) * 4
  scaledBytes = Int(960) * Int(600) * 4
  *baseRGBA = AllocateMemory(baseBytes)
  *scaledRGBA = AllocateMemory(scaledBytes)
  Check(Bool(baseBytes = 256000 And scaledBytes = 2304000 And
             *baseRGBA <> 0 And *scaledRGBA <> 0),
        "canonical 1x 256000-byte RGBA and 3x 2304000-byte RGBA buffers allocated")
  converted = FrameBufferConvertRGBA(@target, @palette, 0, *baseRGBA, baseBytes)
  scaled = FrameBufferScaleNearestRGBA(@target, @palette, 0, 3,
                                       *scaledRGBA, scaledBytes)
  Check(Bool(converted And scaled), "1x RGBA conversion and 3x nearest-neighbour scale succeed")
  mismatch = 0
  For y = 0 To 199
    For x = 0 To 319
      baseOffset = (Int(y) * Int(320) + Int(x)) * 4
      baseWord = PeekL(*baseRGBA + baseOffset)
      For blockY = 0 To 2
        For blockX = 0 To 2
          scaledOffset = ((Int(y) * 3 + blockY) * 960 +
                          (Int(x) * 3 + blockX)) * 4
          scaledWord = PeekL(*scaledRGBA + scaledOffset)
          If scaledWord <> baseWord
            mismatch + 1
          EndIf
        Next
      Next
    Next
  Next
  Check(Bool(mismatch = 0),
        "all 64000 source pixels replicate exact 3x3 RGBA blocks with zero mismatch")
  Check(Bool(mismatch = 0 And scaledBytes = (Int(960) * Int(600)) * 4),
        "scaled RGBA capacity/output pixel count exactly bounded 960x600")
  mismatch = 0
  For y = 0 To 199
    For x = 0 To 319
      rawPixel = FrameBufferGetPixel(@target, Int(x), Int(y))
      If rawPixel = 90 And found90X < 0
        found90X = Int(x)
        found90Y = Int(y)
      ElseIf rawPixel = 254 And found254X < 0
        found254X = Int(x)
        found254Y = Int(y)
      EndIf
    Next
  Next
  Check(Bool(found90X >= 0 And found90Y >= 0 And
             found254X >= 0 And found254Y >= 0),
        "raw frame contains distinct mapped palette indexes 90 and 254")
  baseOffset = (Int(found90Y) * 320 + Int(found90X)) * 4
  Check(Bool(PaletteGetRGB(@palette, 0, 90, @r90, @g90, @b90) And
             r90 = 90 And g90 = 165 And b90 = 14 And
             PeekA(*baseRGBA + baseOffset) = r90 And
             PeekA(*baseRGBA + baseOffset + 1) = g90 And
             PeekA(*baseRGBA + baseOffset + 2) = b90 And
             PeekA(*baseRGBA + baseOffset + 3) = $FF),
        "index90 maps to exact gradient RGB(90,165,14) with alpha255")
  baseOffset = (Int(found254Y) * 320 + Int(found254X)) * 4
  Check(Bool(PaletteGetRGB(@palette, 0, 254, @r254, @g254, @b254) And
             r254 = 254 And g254 = 1 And b254 = 250 And
             PeekA(*baseRGBA + baseOffset) = r254 And
             PeekA(*baseRGBA + baseOffset + 1) = g254 And
             PeekA(*baseRGBA + baseOffset + 2) = b254 And
             PeekA(*baseRGBA + baseOffset + 3) = $FF),
        "index254 maps to a distinct exact gradient RGB(254,1,250)")
  Check(Bool(r90 <> r254 Or g90 <> g254 Or b90 <> b254),
        "indexed palette colours remain distinct, not a flat black conversion")
  If *baseRGBA <> 0
    FreeMemory(*baseRGBA)
  EndIf
  If *scaledRGBA <> 0
    FreeMemory(*scaledRGBA)
  EndIf
  PaletteReset(@palette)
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR35 - allocation/composition counters outside the per-column draw path
; ---------------------------------------------------------------------------

Procedure TestMR35()
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
  Protected drawAllocCount.l = -1
  Protected drawComposeCount.l = -1
  Protected drawReadCount.l = -1
  Protected mainReadCount.l = -1
  Protected sourceOk.i = #False
  Protected wadSizeBefore.q = 0
  Protected wadSizeAfter.q = 0
  Protected wadLumpsBefore.l = 0
  Protected wadLumpsAfter.l = 0
  Protected entryBytes.q = 0
  Protected expectedPeak.q = 0
  Protected frameHash.q = 0
  Protected repeatHash.q = 0
  Protected firstAlloc.l = 0
  Protected repeatAlloc.l = 0
  Protected rendered.i = #False
  Protected repeated.i = #False

  BeginCase("MR35", "Pre-loop allocation/composition and no draw-path resource I/O")
  Check(Bool(SourceTokenCount("TexturedWallDraw.pbi", "AllocateMemory(",
                              @drawAllocCount)),
        "per-column textured draw source audit reads")
  Check(Bool(SourceTokenCount("TexturedWallDraw.pbi", "TextureCompose(",
                              @drawComposeCount)),
        "per-column draw source composition token audit read")
  Check(Bool(SourceTokenCount("TexturedWallDraw.pbi", "WADReadLump(",
                              @drawReadCount)),
        "per-column draw source WAD read token audit read")
  Check(Bool(drawAllocCount = 0 And drawComposeCount = 0 And drawReadCount = 0),
        "draw column/span path contains no heap allocation, compose or WAD read")
  sourceOk = SourceTokenCount("TexturedRenderMain.pbi", "WADReadLump(",
                              @mainReadCount)
  Check(Bool(sourceOk And mainReadCount = 0),
        "frame orchestrator contains no direct WADReadLump call")
  If BuildSceneWad("m3rel-ti02.wad", 2) = #False
    Check(#False, "synthetic TI02 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ti02.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "TI02 session prepared")
  wadSizeBefore = WADGetFileSize()
  wadLumpsBefore = WADGetLumpCount()
  Check(Bool(wadSizeBefore > 0 And wadLumpsBefore > 0),
        "synthetic WAD directory metadata measured before frame")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "TI02 target created")
  TexturedWallRenderResultReset(@result)
  rendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  frameHash = TestFrameHash(@target)
  wadSizeAfter = WADGetFileSize()
  wadLumpsAfter = WADGetLumpCount()
  Check(Bool(rendered And frameHash = FixtureHashAt(*gTI02Hash)),
        "instrumented TI02 frame succeeds with fixture hash")
  Check(Bool(wadSizeAfter = wadSizeBefore And wadLumpsAfter = wadLumpsBefore),
        "frame performs no file mutation and WAD directory counters unchanged")
  Check(Bool(result\ComposedTextures = 3 And result\RequestedReferences = 7 And
             result\ReusedReferences = 4),
        "composition count equals only three unique textures, not 353 columns")
  Check(Bool(result\CacheAllocations = 8 And result\Allocations = 13 And
             result\Allocations = result\CacheAllocations + 5),
        "outer allocation total equals cache8 + five frame-owned resources")
  Check(Bool(result\CacheAllocations = 1 + 1 + 2 * result\ComposedTextures),
        "cache allocation formula is temp+entries+two planes per unique texture")
  Check(Bool(result\CacheTempBytes = 5 * SizeOf(Long)),
        "uniqueness temp allocation bytes exact 20 pre-loop")
  Check(Bool(result\CachePlaneBytes = 38400),
        "retained unique composed planes total 38400 bytes before columns")
  entryBytes = 3 * SizeOf(WallTextureEntry)
  expectedPeak = result\CacheTempBytes + entryBytes + result\CachePlaneBytes
  Check(Bool(result\CachePeakBytes = expectedPeak),
        "peak allocation accounting equals temp + entries + retained planes")
  Check(Bool(result\ProcessedColumns = 353 And
             result\TextureColumnsComputed = 353 And
             result\TextureSamples = 38173 And result\DrawnPixels = 38173),
        "353 columns and 38173 texels processed inside zero-compose draw path")
  firstAlloc = result\Allocations
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "repeat benchmark target")
  repeated = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  repeatHash = TestFrameHash(@target)
  repeatAlloc = result\Allocations
  Check(Bool(repeated And repeatHash = frameHash And repeatAlloc = firstAlloc And
             result\CacheAllocations = 8),
        "same frame repeats identical allocations/hash with no column accumulation")
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; MR36 - CLI parser success/usage/runtime codes and exclusive modes
; ---------------------------------------------------------------------------

Procedure TestMR36()
  Protected output.s
  Protected exitCode.l = -1
  Protected versionSource.s = ""
  Protected versionFound.l = 0
  Protected wadPath.s
  Protected missing.s

  BeginCase("MR36", "CLI parser success/usage/runtime codes and exclusive modes")
  versionSource = ReadDefaultsVersion(@versionFound)
  Check(Bool(versionFound = 1 And versionSource = #M3REL_ExpectedVersion),
        "tracked entry default version equals prepared release expectation")
  output = RunCli("--version", @exitCode)
  Check(Bool(exitCode = 0), "--version exits actual code 0")
  Check(Bool(FindString(output, "DoomPB " + #M3REL_ExpectedVersion) > 0),
        "--version prints the exact tracked version")
  output = RunCli("", @exitCode)
  Check(Bool(exitCode = 0 And FindString(output, "Status: bootstrap") > 0),
        "no-argument invocation prints bootstrap status and exits 0")
  output = RunCli("--help", @exitCode)
  Check(Bool(exitCode = 0 And FindString(output, "Usage:") > 0),
        "--help exits 0 and prints usage")
  output = RunCli("--unknown-flag", @exitCode)
  Check(Bool(exitCode = 2 And FindString(output, "unknown option") > 0),
        "unknown flag exits usage code 2 with diagnostic")
  output = RunCli("--iwad", @exitCode)
  Check(Bool(exitCode = 2 And FindString(output, "requires a file path") > 0),
        "lone --iwad exits usage code 2 with path diagnostic")
  missing = WallTexFixturePath("definitely-missing-m3-rel.wad")
  output = RunCli("--iwad " + Quote(missing) + " --map-info E1M1", @exitCode)
  Check(Bool(exitCode = 1 And FindString(output, "Cannot open WAD") > 0),
        "missing WAD runtime failure exits code 1 with WAD diagnostic")

  If BuildReleaseSceneWad("m3rel-mr36.wad", 1, 37, 201, 73, 19, 17, 9,
                          32, #True, #True, #False) = #False
    Check(#False, "synthetic MR36 PWAD built")
    ProcedureReturn
  EndIf
  wadPath = WallTexFixturePath("m3rel-mr36.wad")
  output = RunCli("--iwad " + Quote(wadPath) + " --iwad " + Quote(wadPath) +
                  " --dump-info", @exitCode)
  Check(Bool(exitCode = 2 And FindString(output, "duplicate '--iwad'") > 0),
        "duplicate --iwad exits usage code 2")
  output = RunCli("--iwad " + Quote(wadPath) + " --dump-info --show-title",
                  @exitCode)
  Check(Bool(exitCode = 2 And FindString(output, "only one of") > 0),
        "conflicting dump-info/show-title modes exit usage code 2")
  output = RunCli("--iwad " + Quote(wadPath) + " --show-walls E1M1 " +
                  "--show-textured-walls E1M1", @exitCode)
  Check(Bool(exitCode = 2 And FindString(output, "only one of") > 0),
        "exclusive debug/textured GUI modes rejected before opening windows")
  output = RunCli("--iwad " + Quote(wadPath) + " --dump-info", @exitCode)
  Check(Bool(exitCode = 0 And FindString(output, "Lumps:") > 0),
        "synthetic --dump-info exits 0 and prints directory metadata")
  output = RunCli("--iwad " + Quote(wadPath) + " --lump-info PLAYPAL",
                  @exitCode)
  Check(Bool(exitCode = 0 And FindString(output, "Size:") > 0),
        "synthetic --lump-info PLAYPAL exits 0 and prints metadata")
  output = RunCli("--iwad " + Quote(wadPath) + " --map-info E1M1", @exitCode)
  Check(Bool(exitCode = 0 And FindString(output, "Map: E1M1") > 0 And
             FindString(output, "Validation: OK") > 0),
        "synthetic --map-info E1M1 exits 0 and validates the map")
  DeleteFile(wadPath)
EndProcedure

; ---------------------------------------------------------------------------
; RI01 - full synthetic pipeline, old fingerprint, both modes
; ---------------------------------------------------------------------------

Procedure TestRI01()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected debugTarget.FrameBuffer
  Protected debugResult.WallRenderResult
  Protected texturedTarget.FrameBuffer
  Protected texturedResult.TexturedWallRenderResult
  Protected legacy.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected spanHash.q = 0
  Protected debugHash.q = 0
  Protected debugRepeatHash.q = 0
  Protected texturedHash.q = 0
  Protected mismatch.l = 0
  Protected actualField.l = 0
  Protected expectedField.l = 0
  Protected actualQuad.q = 0
  Protected expectedQuad.q = 0
  Protected fieldIndex.l
  Protected queryIndex.l
  Protected debugRendered.i = #False
  Protected debugRepeated.i = #False
  Protected texturedRendered.i = #False

  BeginCase("RI01", "Synthetic WAD->visibility->debug->textured full pipeline")
  If BuildSceneWad("m3rel-ri01.wad", 1) = #False
    Check(#False, "synthetic RI01 TI01 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ri01.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "complete resource/map/camera/visibility pipeline prepared")
  spanHash = TestWallSpanHash(@visibility)
  Check(Bool(WallVisibilityCount(@visibility) = 1 And
             spanHash = #TEXGOLD_TI01_SpanHash),
        "old M3-04 span fingerprint preserved through full pipeline")
  Check(Bool(FrameBufferCreate(@debugTarget, 320, 200)), "debug target created")
  WallRenderResultReset(@debugResult)
  debugRendered = WallRenderFrame(@level, @view, @projection, @flats,
                                  @textures, @visibility, @debugTarget,
                                  @debugResult, 1)
  debugHash = TestFrameHash(@debugTarget)
  Check(Bool(debugRendered And debugHash <> -1 And debugResult\Hash = debugHash),
        "legacy M3-05 debug mode remains usable on the same pipeline")
  WallRenderResultReset(@debugResult)
  debugRepeated = WallRenderFrame(@level, @view, @projection, @flats,
                                  @textures, @visibility, @debugTarget,
                                  @debugResult, 1)
  debugRepeatHash = TestFrameHash(@debugTarget)
  Check(Bool(debugRepeated And debugRepeatHash = debugHash),
        "debug A-A rerun keeps deterministic raw fingerprint")
  Check(Bool(FrameBufferCreate(@texturedTarget, 320, 200)), "textured target created")
  TexturedWallRenderResultReset(@texturedResult)
  texturedRendered = TexturedWallRenderFrame(@level, @view, @projection,
                                             @flats, @textures, @colormap,
                                             @visibility, @texturedTarget,
                                             @texturedResult, 1)
  texturedHash = TestFrameHash(@texturedTarget)
  Check(Bool(texturedRendered And texturedHash = FixtureHashAt(*gTI01Hash) And
             texturedResult\Hash = texturedHash),
        "new M3-06 textured fixture hash preserved in both independent paths")
  Check(Bool(texturedTarget\Width = 320 And texturedTarget\Height = 200 And
             texturedTarget\PixelCount = 64000 And
             texturedResult\NonZeroBytes + texturedResult\ZeroBytes = 64000),
        "textured frame exposes exact 64000-byte row-major plane length")
  mismatch = 0
  For fieldIndex = 0 To #TEXGOLD_PlanLFieldCount - 1
    If TexturedWallRenderGetPlan(@texturedResult, 0, @legacy) = #False Or
       TexturedWallRenderGetTexturePlan(@texturedResult, 0, @texPlan) = #False
      mismatch + 1
    Else
      actualField = PlanField(@legacy, @texPlan, Int(fieldIndex))
      expectedField = FixturePlanLValue(*gTI01PlanL, 0, Int(fieldIndex))
      If actualField <> expectedField
        mismatch + 1
      EndIf
    EndIf
  Next
  For queryIndex = 0 To #TEXGOLD_PlanQFieldCount - 1
    If TexturedWallRenderGetPlan(@texturedResult, 0, @legacy) = #False Or
       TexturedWallRenderGetTexturePlan(@texturedResult, 0, @texPlan) = #False
      mismatch + 1
    Else
      actualQuad = PlanQ(@legacy, @texPlan, Int(queryIndex))
      expectedQuad = FixturePlanQValue(*gTI01PlanQ, 0, Int(queryIndex))
      If actualQuad <> expectedQuad
        mismatch + 1
      EndIf
    EndIf
  Next
  Check(Bool(mismatch = 0),
        "TI01 62 numeric fields and 6 BAM quad fields equal fixture plan exactly")
  Check(Bool(texturedResult\MaskedMidSpans = 0 And
             texturedResult\SpanCount = 1 And texturedResult\TexturePlanCount = 1),
        "one-sided TI01 scene has no masked deferral and one plan per span")
  WallRenderResultReset(@debugResult)
  FrameBufferReset(@debugTarget)
  TexturedWallRenderResultReset(@texturedResult)
  FrameBufferReset(@texturedTarget)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; RI02 - two-sided upper/lower/masked scene, pegging, COLORMAP, 3x
; ---------------------------------------------------------------------------

Procedure TestRI02()
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
  Protected debugTarget.FrameBuffer
  Protected debugResult.WallRenderResult
  Protected palette.PaletteSet
  Protected *scaledRGBA.Byte = 0
  Protected scaledBytes.q = 0
  Protected *baseRGBA.Byte = 0
  Protected baseBytes.q = 0
  Protected legacy.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected planIndex.l
  Protected fieldIndex.l
  Protected queryIndex.l
  Protected sampleIndex.l
  Protected sampleX.l = 0
  Protected rowY.l
  Protected expectedByte.i = 0
  Protected actualByte.i = 0
  Protected mismatch.l = 0
  Protected actualField.l = 0
  Protected expectedField.l = 0
  Protected actualQuad.q = 0
  Protected expectedQuad.q = 0
  Protected maskedMismatch.l = 0
  Protected maskedGood.l = 0
  Protected spanHash.q = 0
  Protected texturedHash.q = 0
  Protected debugHash.q = 0
  Protected blockOffset.i = 0
  Protected baseOffset.i = 0
  Protected blockMismatch.l = 0
  Protected scaled.i = #False
  Protected debugRendered.i = #False
  Protected texturedRendered.i = #False

  BeginCase("RI02", "Two-sided masked portal pipeline with pegging/light/3x")
  If BuildSceneWad("m3rel-ri02.wad", 2) = #False
    Check(#False, "synthetic RI02 TI02 PWAD built")
    ProcedureReturn
  EndIf
  Check(Bool(PrepareSyntheticSession("m3rel-ri02.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "multi-surface two-sided pipeline prepared")
  spanHash = TestWallSpanHash(@visibility)
  Check(Bool(WallVisibilityCount(@visibility) = #TEXGOLD_TI02_SpanCount And
             spanHash = #TEXGOLD_TI02_SpanHash),
        "four-span old fingerprint preserved on two-sided scene")
  Check(Bool(FrameBufferCreate(@debugTarget, 320, 200)), "debug target created")
  WallRenderResultReset(@debugResult)
  debugRendered = WallRenderFrame(@level, @view, @projection, @flats,
                                  @textures, @visibility, @debugTarget,
                                  @debugResult, 1)
  debugHash = TestFrameHash(@debugTarget)
  Check(Bool(debugRendered And debugHash <> -1 And debugResult\Hash = debugHash),
        "legacy debug mode remains distinct and usable on two-sided scene")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "textured target created")
  TexturedWallRenderResultReset(@result)
  texturedRendered = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                             @textures, @colormap, @visibility,
                                             @target, @result, 1)
  texturedHash = TestFrameHash(@target)
  Check(Bool(texturedRendered And texturedHash = FixtureHashAt(*gTI02Hash) And
             result\Hash = texturedHash),
        "two-sided textured upper/lower/hole fixture hash preserved")
  Check(Bool(result\SpanCount = 4 And result\TexturePlanCount = 4 And
             result\UpperPixels = #TEXGOLD_TI02_UpperPixels And
             result\LowerPixels = #TEXGOLD_TI02_LowerPixels And
             result\MiddlePixels = #TEXGOLD_TI02_MiddlePixels),
        "upper/lower/middle tiers and four plans equal independent fixture")
  mismatch = 0
  For planIndex = 0 To result\TexturePlanCount - 1
    For fieldIndex = 0 To #TEXGOLD_PlanLFieldCount - 1
      If TexturedWallRenderGetPlan(@result, Int(planIndex), @legacy) = #False Or
         TexturedWallRenderGetTexturePlan(@result, Int(planIndex), @texPlan) = #False
        mismatch + 1
      Else
        actualField = PlanField(@legacy, @texPlan, Int(fieldIndex))
        expectedField = FixturePlanLValue(*gTI02PlanL, Int(planIndex),
                                          Int(fieldIndex))
        If actualField <> expectedField
          mismatch + 1
        EndIf
      EndIf
    Next
    For queryIndex = 0 To #TEXGOLD_PlanQFieldCount - 1
      If TexturedWallRenderGetPlan(@result, Int(planIndex), @legacy) = #False Or
         TexturedWallRenderGetTexturePlan(@result, Int(planIndex), @texPlan) = #False
        mismatch + 1
      Else
        actualQuad = PlanQ(@legacy, @texPlan, Int(queryIndex))
        expectedQuad = FixturePlanQValue(*gTI02PlanQ, Int(planIndex),
                                         Int(queryIndex))
        If actualQuad <> expectedQuad
          mismatch + 1
        EndIf
      EndIf
    Next
  Next
  Check(Bool(mismatch = 0),
        "all four plans' 62 numeric fields and 6 BAM fields equal fixture")
  maskedGood = 0
  maskedMismatch = 0
  For planIndex = 0 To result\TexturePlanCount - 1
    If TexturedWallRenderGetPlan(@result, Int(planIndex), @legacy) = #False Or
       TexturedWallRenderGetTexturePlan(@result, Int(planIndex), @texPlan) = #False
      maskedMismatch + 1
    ElseIf PlanField(@legacy, @texPlan, 59) = 1
      If PlanField(@legacy, @texPlan, 41) = #WALLTEXSPAN_NoTexture And
         texPlan\MidCacheSlot = #WALLTEXSPAN_NoCacheSlot And
         PlanField(@legacy, @texPlan, 36) = 0 And
         PlanField(@legacy, @texPlan, 37) = 1
        maskedGood + 1
      Else
        maskedMismatch + 1
      EndIf
    EndIf
  Next
  Check(Bool(result\MaskedMidSpans = 2 And maskedGood = 2 And
             maskedMismatch = 0),
        "masked two-sided middle deferred: no opaque tier/cache slot")
  Check(Bool(result\MaskedMidSpans = #TEXGOLD_TI02_MaskedMidSpans And
             result\MiddlePixels = #TEXGOLD_TI02_MiddlePixels And
             result\ZeroBytes = #TEXGOLD_TI02_ZeroBytes),
        "deferred masked middles leave fixture middle/background counts unchanged")
  mismatch = 0
  For sampleIndex = 0 To #TEXGOLD_TI02_SampleCount - 1
    sampleX = PeekL(*gTI02SampleX + Int(sampleIndex) * SizeOf(Long))
    For rowY = 0 To 199
      expectedByte = PeekA(*gTI02SampleRows +
                            Int(sampleIndex) * #TEXGOLD_SampleRowBytes +
                            Int(rowY))
      actualByte = FrameBufferGetPixel(@target, Int(sampleX), Int(rowY))
      If actualByte <> expectedByte
        mismatch + 1
      EndIf
    Next
  Next
  Check(Bool(mismatch = 0),
        "eight sample columns x200 rows equal independent COLORMAP fixture bytes")
  Check(Bool(DecodeSyntheticPalette(@palette)),
        "COLORMAP-lit frame palette decoded for presentation layer")
  baseBytes = Int(320) * Int(200) * 4
  scaledBytes = Int(960) * Int(600) * 4
  *scaledRGBA = AllocateMemory(scaledBytes)
  *baseRGBA = AllocateMemory(baseBytes)
  scaled = Bool(*scaledRGBA <> 0 And *baseRGBA <> 0 And
                FrameBufferScaleNearestRGBA(@target, @palette, 0, 3,
                                            *scaledRGBA, scaledBytes) And
                FrameBufferConvertRGBA(@target, @palette, 0, *baseRGBA,
                                       baseBytes))
  Check(Bool(scaled And scaledBytes = 2304000),
        "indexed frame converts to canonical 960x600 3x RGBA presentation")
  blockMismatch = 0
  baseOffset = 0
  blockOffset = 0
  For rowY = 0 To 2
    For sampleIndex = 0 To 2
      baseOffset = Int(rowY / 3) * 320 * 4 + Int(sampleIndex / 3) * 4
      blockOffset = Int(rowY) * 960 * 4 + Int(sampleIndex) * 4
      If PeekL(*scaledRGBA + blockOffset) <> PeekL(*baseRGBA + baseOffset)
        blockMismatch + 1
      EndIf
    Next
  Next
  Check(Bool(blockMismatch = 0),
        "a deterministic 3x3 source block replicates nearest-neighbour RGBA")
  If *scaledRGBA <> 0
    FreeMemory(*scaledRGBA)
  EndIf
  If *baseRGBA <> 0
    FreeMemory(*baseRGBA)
  EndIf
  PaletteReset(@palette)
  WallRenderResultReset(@debugResult)
  FrameBufferReset(@debugTarget)
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; RI03 - malformed resources, rollback/recovery and A->B->A
; ---------------------------------------------------------------------------

Procedure TestRI03()
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
  Protected targetHashHA.q = 0
  Protected targetHashHA2.q = 0
  Protected targetHashB.q = 0
  Protected targetHashProbe.q = 0
  Protected absentPrepared.i = #False
  Protected truncatedPrepared.i = #False
  Protected shortColormapPrepared.i = #False
  Protected recoveredA1.i = #False
  Protected recoveredB.i = #False
  Protected recoveredA2.i = #False
  Protected rejected.i = #False

  BeginCase("RI03", "Malformed texture/COLORMAP rollback, recovery and A->B->A")
  Check(Bool(BuildSceneWad("m3rel-ri03-a.wad", 1) = #True),
        "valid A TI01 synthetic WAD built")
  Check(Bool(PrepareSyntheticSession("m3rel-ri03-a.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "valid A session prepared")
  Check(Bool(FrameBufferCreate(@target, 320, 200)), "previous target created")
  TexturedWallRenderResultReset(@result)
  recoveredA1 = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                        @textures, @colormap, @visibility,
                                        @target, @result, 1)
  targetHashHA = TestFrameHash(@target)
  Check(Bool(recoveredA1 And targetHashHA = FixtureHashAt(*gTI01Hash)),
        "valid A publishes fixture TI01 full-plane as previous target")
  TexturedWallRenderResultReset(@result)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  ; Malformed 1: absent texture catalog (valid palette/flats/COLORMAP/map).
  Check(Bool(BuildReleaseSceneWad("m3rel-ri03-mtext.wad", 1, 37, 201, 73,
                                  19, 17, 9, 32, #False, #True)),
        "PWAD with absent PNAMES/TEXTURE resources built")
  absentPrepared = PrepareSyntheticSession("m3rel-ri03-mtext.wad", "E1M1",
                                           @pnames, @textures, @flats,
                                           @colormap, @level, @view,
                                           @projection, @visibility)
  Check(Bool(absentPrepared = #False And TextureCatalogCount(@textures) = 0),
        "absent texture resource rejected before map startup")
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
  TexturedWallRenderResultReset(@result)
  targetHashProbe = TestFrameHash(@target)
  rejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rejected = #False And TestFrameHash(@target) = targetHashHA),
        "absent-texture attempt keeps previous target bytes and no publication")
  Check(Bool(TexturedWallRenderResultReset(@result) And
             TexturedWallRenderResultReset(@result) And result\Ready = 0),
        "fail-result reset twice idempotent and leaves empty reusable result")

  ; Malformed 2: truncated four-byte TEXTURE1 header; decoder rejects.
  Check(Bool(BuildTruncatedTextureSceneWad("m3rel-ri03-trunc.wad")),
        "truncated TEXTURE1 synthetic resource/map WAD built")
  truncatedPrepared = PrepareSyntheticSession("m3rel-ri03-trunc.wad", "E1M1",
                                              @pnames, @textures, @flats,
                                              @colormap, @level, @view,
                                              @projection, @visibility)
  Check(Bool(truncatedPrepared = #False And TextureCatalogCount(@textures) = 0),
        "truncated TEXTURE1 definitions rejected before partial startup")
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
  TexturedWallRenderResultReset(@result)
  rejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rejected = #False And TestFrameHash(@target) = targetHashHA),
        "truncated-texture failure preserves previous target byte-for-byte")
  Check(Bool(FindString(TexturedWallRenderLastError(), "not ready") > 0 Or
             FindString(TexturedWallRenderLastError(), "catalog") > 0),
        "truncated-texture recovery frame reports explicit resource diagnostic")
  TexturedWallRenderResultReset(@result)

  ; Malformed 3: 31-table lighting lump decodes but lacks classic >=32 tables.
  Check(Bool(BuildReleaseSceneWad("m3rel-ri03-light.wad", 1, 37, 201, 73,
                                  19, 17, 9, 31, #True, #True)),
        "31-table COLORMAP but otherwise valid synthetic WAD built")
  shortColormapPrepared = PrepareSyntheticSession("m3rel-ri03-light.wad",
                                                  "E1M1", @pnames, @textures,
                                                  @flats, @colormap, @level,
                                                  @view, @projection,
                                                  @visibility)
  Check(Bool(shortColormapPrepared And ColormapCount(@colormap) = 31),
        "31 tables decode/load but are below classic wall-lighting minimum")
  TexturedWallRenderResultReset(@result)
  rejected = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(rejected = #False And TestFrameHash(@target) = targetHashHA),
        "below-32 lighting gate rejects render and preserves published target")
  Check(Bool(FindString(TexturedWallRenderLastError(), "at least 32") > 0),
        "lighting failure diagnostic states the >=32 COLORMAP gate")
  Check(Bool(result\Ready = 0 And result\Plans = 0 And result\Allocations = 0),
        "lighting failure rollback releases plan metadata/counters")
  TexturedWallRenderResultReset(@result)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  ; Recovery A->B->A after all malformed attempts, with same target object.
  Check(Bool(BuildSceneWad("m3rel-ri03-a.wad", 1)), "valid A rebuilt after failures")
  Check(Bool(PrepareSyntheticSession("m3rel-ri03-a.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "recovery A re-resolves all owned catalog/map resources")
  TexturedWallRenderResultReset(@result)
  recoveredA1 = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                        @textures, @colormap, @visibility,
                                        @target, @result, 1)
  targetHashHA2 = TestFrameHash(@target)
  Check(Bool(recoveredA1 And targetHashHA2 = targetHashHA And
             result\Hash = targetHashHA2),
        "recovery A reproduces exact previous fixture target hash")
  TexturedWallRenderResultReset(@result)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  Check(Bool(BuildSceneWad("m3rel-ri03-b.wad", 2)), "valid B TI02 WAD built")
  Check(Bool(PrepareSyntheticSession("m3rel-ri03-b.wad", "E2M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "valid B re-resolves two-sided scene without stale A references")
  TexturedWallRenderResultReset(@result)
  recoveredB = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                       @textures, @colormap, @visibility,
                                       @target, @result, 1)
  targetHashB = TestFrameHash(@target)
  Check(Bool(recoveredB And targetHashB = FixtureHashAt(*gTI02Hash) And
             targetHashB <> targetHashHA),
        "A->B frame replaces target with exact independent TI02 fixture hash")
  TexturedWallRenderResultReset(@result)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  Check(Bool(BuildSceneWad("m3rel-ri03-a.wad", 1)), "valid A third session rebuilt")
  Check(Bool(PrepareSyntheticSession("m3rel-ri03-a.wad", "E1M1", @pnames,
                                     @textures, @flats, @colormap, @level, @view,
                                     @projection, @visibility)),
        "B->A third session re-resolves TI01 resources/map/camera")
  TexturedWallRenderResultReset(@result)
  recoveredA2 = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                        @textures, @colormap, @visibility,
                                        @target, @result, 1)
  targetHashHA2 = TestFrameHash(@target)
  Check(Bool(recoveredA2 And targetHashHA2 = targetHashHA And
             targetHashHA2 = FixtureHashAt(*gTI01Hash)),
        "A->B->A returns exact first-A target hash with no stale index")
  Check(Bool(WADGetFileSize() > 0 And WADGetLumpCount() > 0 And WADIsOpen()),
        "final A WAD remains open with readable read-only directory state")
  Check(Bool(TexturedWallRenderResultReset(@result) And
             TexturedWallRenderResultReset(@result)),
        "successful full-pipeline result double reset idempotent")
  FrameBufferReset(@target)
  CleanupSyntheticSession(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

Procedure ReleaseOutput()
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

Procedure Main()
  If WallTexPrepareFixtureDirectory() = #False
    PrintN("FAIL: cannot create synthetic fixture directory")
    ProcedureReturn 1
  EndIf
  TestMR01()
  TestMR02()
  TestMR03()
  TestMR04()
  TestMR05()
  TestMR06()
  TestMR07()
  TestMR08()
  TestMR09()
  TestMR10()
  TestMR11()
  TestMR12()
  TestMR13()
  TestMR14()
  TestMR15()
  TestMR16()
  TestMR17()
  TestMR18()
  TestMR19()
  TestMR20()
  TestMR21()
  TestMR22()
  TestMR23()
  TestMR24()
  TestMR25()
  TestMR26()
  TestMR27()
  TestMR28()
  TestMR29()
  TestMR30()
  TestMR31()
  TestMR32()
  TestMR33()
  TestMR34()
  TestMR35()
  TestMR36()
  TestRI01()
  TestRI02()
  TestRI03()
  WallTexCleanupFixtureDirectory()
  ProcedureReturn ReleaseOutput()
EndProcedure

OpenConsole()
End Main()
