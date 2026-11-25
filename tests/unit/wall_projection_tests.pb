; -----------------------------------------------------------------------------
; DoomPB - M3-05 wall projection/solid-color draw unit tests WP01-WP56
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Standalone synthetic/no-WAD suite. Includes M3-01/M3-02/M3-03/M3-04 accepted
; modules, the new M3-05 WallView/WallProject/WallDraw/RenderMain, the existing
; independent M3-04 projection fixture, and the generated numeric-only M3-05
; wall golden fixture from scripts/gen_wall_projection_golden.py. The synthetic
; map support writes real SEGS raw 16-bit angles and original ten-lump records;
; no commercial data, WAD bytes, textures/flats pixels, window or screenshots.
;
; Oracles:
;   - projection/scale/sines/angles use pinned-table and generated values, plus
;     explicit integer formulas in the test;
;   - numeric map scenes A/B/E/T/C mirror the Python oracle source scenes exactly;
;     expected spans, plans, sample palette rows and frame FNV hashes come from
;     the generated fixture, not from this port's renderer;
;   - direct clip/draw cases use explicit inclusive row arithmetic and independent
;     color masks; production helpers are called, expectations are hand/derived
;     numbers tied to the documented source rules.
;
; Exit code: 0 when every assertion passed, otherwise the failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Map/MapTypes.pbi"
XIncludeFile "../../src/Map/MapDecode.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/Projection.pbi"
XIncludeFile "../../src/Renderer/ClipSegs.pbi"
XIncludeFile "../../src/Renderer/WallVisibility.pbi"
XIncludeFile "../../src/Renderer/WallView.pbi"
XIncludeFile "../../src/Renderer/WallProject.pbi"
XIncludeFile "../../src/Renderer/WallDraw.pbi"
XIncludeFile "../../src/Renderer/RenderMain.pbi"
XIncludeFile "../../src/Graphics/FrameBuffer.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../fixtures/m3_projection_golden.pbi"
XIncludeFile "../fixtures/m3_wall_projection_golden.pbi"
XIncludeFile "wall_test_support.pbi"

#TEST_FNV_Offset = -3750763034362895579
#TEST_FNV_Prime = 1099511628211
#TEST_WALL_TiltedHeading = $18000000

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

Global *gGoldA_Spans = ?WallGold_A_Spans
Global *gGoldB_Spans = ?WallGold_B_Spans
Global *gGoldE_Spans = ?WallGold_E_Spans
Global *gGoldT_Spans = ?WallGold_T_Spans
Global *gGoldC_Spans = ?WallGold_C_Spans
Global *gGoldA_PlanL = ?WallGold_A_PlanL
Global *gGoldB_PlanL = ?WallGold_B_PlanL
Global *gGoldE_PlanL = ?WallGold_E_PlanL
Global *gGoldT_PlanL = ?WallGold_T_PlanL
Global *gGoldC_PlanL = ?WallGold_C_PlanL
Global *gGoldA_PlanQ = ?WallGold_A_PlanQ
Global *gGoldB_PlanQ = ?WallGold_B_PlanQ
Global *gGoldE_PlanQ = ?WallGold_E_PlanQ
Global *gGoldT_PlanQ = ?WallGold_T_PlanQ
Global *gGoldC_PlanQ = ?WallGold_C_PlanQ
Global *gGoldA_Samples = ?WallGold_A_SampleX
Global *gGoldB_Samples = ?WallGold_B_SampleX
Global *gGoldE_Samples = ?WallGold_E_SampleX
Global *gGoldT_Samples = ?WallGold_T_SampleX
Global *gGoldC_Samples = ?WallGold_C_SampleX
Global *gGoldA_Rows = ?WallGold_A_SampleRows
Global *gGoldB_Rows = ?WallGold_B_SampleRows
Global *gGoldE_Rows = ?WallGold_E_SampleRows
Global *gGoldT_Rows = ?WallGold_T_SampleRows
Global *gGoldC_Rows = ?WallGold_C_SampleRows
Global *gGoldA_Hash = ?WallGold_A_Hash
Global *gGoldB_Hash = ?WallGold_B_Hash
Global *gGoldE_Hash = ?WallGold_E_Hash
Global *gGoldT_Hash = ?WallGold_T_Hash
Global *gGoldC_Hash = ?WallGold_C_Hash
Global *gGoldSineIndex0 = ?WallGold_SineIndex0_Value
Global *gGoldSineIndex1028 = ?WallGold_SineIndex1028_Value
Global *gGoldSineIndex2048 = ?WallGold_SineIndex2048_Value
Global *gGoldSineIndex3073 = ?WallGold_SineIndex3073_Value
Global *gGoldTangentIndex0 = ?WallGold_TangentIndex0_Value
Global *gGoldTangentIndex3072 = ?WallGold_TangentIndex3072_Value
Global *gGoldClipAngle = ?ProjectionGoldClipAngle

; ---------------------------------------------------------------------------
; Harness
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

Procedure.q FnvAddByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #TEST_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvAddByte(Hash, Value & $FF)
  Hash = FnvAddByte(Hash, (Value >> 8) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 16) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

Procedure.q TestFnvFrameReference(*FrameBuffer.FrameBuffer)
  Protected hash.q = #TEST_FNV_Offset
  Protected byteIndex.i

  For byteIndex = 0 To #WALLDRAW_PixelCount - 1
    hash = FnvAddByte(hash, PeekA(*FrameBuffer\Pixels + byteIndex))
  Next
  ProcedureReturn hash
EndProcedure

; ---------------------------------------------------------------------------
; Generated fixture numeric accessors (numeric/synthetic only)
; ---------------------------------------------------------------------------

Procedure.i GoldSceneSpanCount(SceneId.s)
  If SceneId = "A"
    ProcedureReturn #WALLGOLD_A_SpanCount
  ElseIf SceneId = "B"
    ProcedureReturn #WALLGOLD_B_SpanCount
  ElseIf SceneId = "E"
    ProcedureReturn #WALLGOLD_E_SpanCount
  ElseIf SceneId = "T"
    ProcedureReturn #WALLGOLD_T_SpanCount
  ElseIf SceneId = "C"
    ProcedureReturn #WALLGOLD_C_SpanCount
  EndIf
  ProcedureReturn -1
EndProcedure

Procedure.i GoldSpanGet(SceneId.s, SpanIndex.l, FieldIndex.l, *Value.Long)
  Protected *base.Long

  If SpanIndex < 0 Or SpanIndex >= GoldSceneSpanCount(SceneId)
    ProcedureReturn #False
  EndIf
  If FieldIndex < 0 Or FieldIndex >= #WALLGOLD_SpanFieldCount
    ProcedureReturn #False
  EndIf
  If SceneId = "A"
    *base = *gGoldA_Spans
  ElseIf SceneId = "B"
    *base = *gGoldB_Spans
  ElseIf SceneId = "E"
    *base = *gGoldE_Spans
  ElseIf SceneId = "T"
    *base = *gGoldT_Spans
  ElseIf SceneId = "C"
    *base = *gGoldC_Spans
  Else
    ProcedureReturn #False
  EndIf
  If *base = 0
    ProcedureReturn #False
  EndIf
  *Value\l = PeekL(*base + (SpanIndex * #WALLGOLD_SpanFieldCount + FieldIndex) * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

; Plan field ordinals are the explicit generator L_PLAN_FIELDS order mirrored in
; the fixture header constants; tests name the fields below.
Procedure.i GoldPlanLGet(SceneId.s, PlanIndex.l, FieldIndex.l, *Value.Long)
  Protected *base.Long
  Protected count.l = GoldSceneSpanCount(SceneId)

  If PlanIndex < 0 Or PlanIndex >= count
    ProcedureReturn #False
  EndIf
  If FieldIndex < 0 Or FieldIndex >= #WALLGOLD_PlanLFieldCount
    ProcedureReturn #False
  EndIf
  If SceneId = "A"
    *base = *gGoldA_PlanL
  ElseIf SceneId = "B"
    *base = *gGoldB_PlanL
  ElseIf SceneId = "E"
    *base = *gGoldE_PlanL
  ElseIf SceneId = "T"
    *base = *gGoldT_PlanL
  ElseIf SceneId = "C"
    *base = *gGoldC_PlanL
  EndIf
  If *base = 0
    ProcedureReturn #False
  EndIf
  *Value\l = PeekL(*base + (PlanIndex * #WALLGOLD_PlanLFieldCount + FieldIndex) * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

Procedure.i GoldPlanQGet(SceneId.s, PlanIndex.l, FieldIndex.l, *Value.Quad)
  Protected *base.Quad
  Protected count.l = GoldSceneSpanCount(SceneId)

  If PlanIndex < 0 Or PlanIndex >= count
    ProcedureReturn #False
  EndIf
  If FieldIndex < 0 Or FieldIndex >= #WALLGOLD_PlanQFieldCount
    ProcedureReturn #False
  EndIf
  If SceneId = "A"
    *base = *gGoldA_PlanQ
  ElseIf SceneId = "B"
    *base = *gGoldB_PlanQ
  ElseIf SceneId = "E"
    *base = *gGoldE_PlanQ
  ElseIf SceneId = "T"
    *base = *gGoldT_PlanQ
  ElseIf SceneId = "C"
    *base = *gGoldC_PlanQ
  EndIf
  If *base = 0
    ProcedureReturn #False
  EndIf
  *Value\q = PeekQ(*base + (PlanIndex * #WALLGOLD_PlanQFieldCount + FieldIndex) * SizeOf(Quad))
  ProcedureReturn #True
EndProcedure

Procedure.i GoldSampleXGet(SceneId.s, SampleIndex.l, *X.Long)
  Protected *base.Long
  Protected count.l

  If SceneId = "A"
    *base = *gGoldA_Samples
    count = #WALLGOLD_A_SampleCount
  ElseIf SceneId = "B"
    *base = *gGoldB_Samples
    count = #WALLGOLD_B_SampleCount
  ElseIf SceneId = "E"
    *base = *gGoldE_Samples
    count = #WALLGOLD_E_SampleCount
  ElseIf SceneId = "T"
    *base = *gGoldT_Samples
    count = #WALLGOLD_T_SampleCount
  ElseIf SceneId = "C"
    *base = *gGoldC_Samples
    count = #WALLGOLD_C_SampleCount
  EndIf
  If *base = 0 Or SampleIndex < 0 Or SampleIndex >= count
    ProcedureReturn #False
  EndIf
  *X\l = PeekL(*base + SampleIndex * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

Procedure.i GoldSampleIndexForColumn(SceneId.s, Column.l, *SampleIndex.Long)
  Protected count.l
  Protected i.i
  Protected sampleX.l = 0

  If SceneId = "A"
    count = #WALLGOLD_A_SampleCount
  ElseIf SceneId = "B"
    count = #WALLGOLD_B_SampleCount
  ElseIf SceneId = "E"
    count = #WALLGOLD_E_SampleCount
  ElseIf SceneId = "T"
    count = #WALLGOLD_T_SampleCount
  ElseIf SceneId = "C"
    count = #WALLGOLD_C_SampleCount
  Else
    ProcedureReturn #False
  EndIf
  For i = 0 To count - 1
    If GoldSampleXGet(SceneId, i, @sampleX) = #False
      ProcedureReturn #False
    EndIf
    If sampleX = Column
      *SampleIndex\l = i
      ProcedureReturn #True
    EndIf
  Next
  ProcedureReturn #False
EndProcedure

Procedure.i GoldSampleRowGet(SceneId.s, SampleIndex.l, Row.l, *Value.Long)
  Protected *base.Byte
  Protected count.l

  If SceneId = "A"
    *base = *gGoldA_Rows
    count = #WALLGOLD_A_SampleCount
  ElseIf SceneId = "B"
    *base = *gGoldB_Rows
    count = #WALLGOLD_B_SampleCount
  ElseIf SceneId = "E"
    *base = *gGoldE_Rows
    count = #WALLGOLD_E_SampleCount
  ElseIf SceneId = "T"
    *base = *gGoldT_Rows
    count = #WALLGOLD_T_SampleCount
  ElseIf SceneId = "C"
    *base = *gGoldC_Rows
    count = #WALLGOLD_C_SampleCount
  EndIf
  If *base = 0 Or SampleIndex < 0 Or SampleIndex >= count
    ProcedureReturn #False
  EndIf
  If Row < 0 Or Row >= #WALLGOLD_SampleRowBytes
    ProcedureReturn #False
  EndIf
  *Value\l = PeekA(*base + (SampleIndex * #WALLGOLD_SampleRowBytes + Row))
  ProcedureReturn #True
EndProcedure

Procedure.q GoldSceneHash(SceneId.s)
  If SceneId = "A"
    ProcedureReturn PeekQ(*gGoldA_Hash)
  ElseIf SceneId = "B"
    ProcedureReturn PeekQ(*gGoldB_Hash)
  ElseIf SceneId = "E"
    ProcedureReturn PeekQ(*gGoldE_Hash)
  ElseIf SceneId = "T"
    ProcedureReturn PeekQ(*gGoldT_Hash)
  ElseIf SceneId = "C"
    ProcedureReturn PeekQ(*gGoldC_Hash)
  EndIf
  ProcedureReturn -1
EndProcedure

; ---------------------------------------------------------------------------
; Original synthetic scenes A/B/E/T/C mirrored by the Python generator
; ---------------------------------------------------------------------------

Procedure.i TestBuildSceneMap(SceneId.s, *Level.MapLevel)
  Protected Dim sectors.TestSectorSpec(1)
  Protected Dim lines.TestLineSpec(1)
  Protected Dim sides.TestSideSpec(2)
  Protected Dim vertices.TestVertexSpec(3)
  Protected Dim segs.TestSegSpec(1)
  Protected Dim subs.TestSubSpec(0)
  Protected Dim nodes.TestNodeSpec(0)
  Protected i.i
  Protected sectorCount.l = 1
  Protected lineCount.l = 1
  Protected sideCount.l = 1
  Protected vertexCount.l = 2
  Protected segCount.l = 1
  Protected subCount.l = 1
  Protected nodeCount.l = 0

  If *Level = 0
    ProcedureReturn #False
  EndIf

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\LightLevel = 160
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"

  lines(0)\V1 = 0
  lines(0)\V2 = 1
  lines(0)\Flags = 0
  lines(0)\Special = 0
  lines(0)\Tag = 0
  lines(0)\Side0 = 0
  lines(0)\Side1 = -1

  sides(0)\Sector = 0
  sides(0)\TopName = "WALL1"
  sides(0)\BottomName = "WALL1"
  sides(0)\MidName = "WALL1"

  segs(0)\V1 = 0
  segs(0)\V2 = 1
  segs(0)\Line = 0
  segs(0)\Side = 0
  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1

  Select SceneId
    Case "A"
      vertices(0)\X = 100
      vertices(0)\Y = 100
      vertices(1)\X = 101
      vertices(1)\Y = 100
      segs(0)\RawAngle = 0
    Case "B"
      vertices(0)\X = 100
      vertices(0)\Y = 64
      vertices(1)\X = 100
      vertices(1)\Y = -64
      segs(0)\RawAngle = 49152
    Case "E"
      vertices(0)\X = 64
      vertices(0)\Y = 32767
      vertices(1)\X = 64
      vertices(1)\Y = -32767
      segs(0)\RawAngle = 49152
    Case "T"
      vertices(0)\X = 64
      vertices(0)\Y = 32767
      vertices(1)\X = 64
      vertices(1)\Y = -32767
      segs(0)\RawAngle = 49152
    Case "C"
      sectors(1)\FloorHeight = 32
      sectors(1)\CeilingHeight = 96
      sectors(1)\LightLevel = 160
      sectors(1)\FloorName = "FLOOR2"
      sectors(1)\CeilingName = "CEIL2"
      sectorCount = 2

      lines(1)\V1 = 2
      lines(1)\V2 = 3
      lines(1)\Flags = #MAP_ML_TWOSIDED
      lines(1)\Special = 0
      lines(1)\Tag = 0
      lines(1)\Side0 = 1
      lines(1)\Side1 = 2
      lineCount = 2

      sides(1)\Sector = 0
      sides(1)\TopName = "WALL1"
      sides(1)\BottomName = "WALL1"
      sides(1)\MidName = "-"
      sides(2)\Sector = 1
      sides(2)\TopName = "WALL1"
      sides(2)\BottomName = "WALL1"
      sides(2)\MidName = "WALL1"
      sideCount = 3
      segs(0)\RawAngle = 49152
      vertices(0)\X = 100
      vertices(0)\Y = 64
      vertices(1)\X = 100
      vertices(1)\Y = -64

      vertices(2)\X = 300
      vertices(2)\Y = 32767
      vertices(3)\X = 300
      vertices(3)\Y = -32767
      vertexCount = 4

      segs(1)\V1 = 2
      segs(1)\V2 = 3
      segs(1)\RawAngle = 49152
      segs(1)\Line = 1
      segs(1)\Side = 0
      segCount = 2
      subs(0)\FirstSeg = 0
      subs(0)\NumSegs = 2
    Default
      ProcedureReturn #False
  EndSelect

  ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), sectorCount,
                                       @lines(0), lineCount,
                                       @sides(0), sideCount,
                                       @vertices(0), vertexCount,
                                       @segs(0), segCount,
                                       @subs(0), subCount,
                                       @nodes(0), nodeCount)
EndProcedure

Procedure.i TestBuildSceneView(SceneId.s, *View.WallView,
                               *Projection.Projection)
  Protected heading.q = 0
  Protected headingDomain.i

  If SceneId = "T"
    heading = #TEST_WALL_TiltedHeading
  Else
    heading = 0
  EndIf
  If BamRawInUnsignedDomain(heading) = 0
    ProcedureReturn #False
  EndIf
  If WallViewSetMapUnits(*View, 0, 0, heading, 0) = #False
    ProcedureReturn #False
  EndIf
  headingDomain = Bool(WallViewIsValid(*View) <> 0)
  If headingDomain = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn ProjectionInitClassic(*Projection)
EndProcedure

; Builds the map, explicit camera/viewz and classic projection, then runs the
; unchanged M3-04 online visibility walk with fallback texture/flat identity
; (no catalogs) exactly as the Python synthetic scenes.
Procedure.i TestPrepareScene(SceneId.s, *Level.MapLevel, *View.WallView,
                             *Projection.Projection,
                             *Visibility.WallVisibilityResult)
  If TestBuildSceneMap(SceneId, *Level) = #False
    ProcedureReturn #False
  EndIf
  If TestBuildSceneView(SceneId, *View, *Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallVisibilityBuild(*Level, @*View\Camera, *Projection,
                                      0, 0, *Visibility)
EndProcedure

; ---------------------------------------------------------------------------
; Parametric single-line synthetic vertical wall scenes for tier/clip cases
; ---------------------------------------------------------------------------

; Caller-controlled two-sector/one-sided or two-sided vertical wall geometry.
; Vertices are always the original synthetic pair (100,64)/(100,-64) with raw
; SEGS angle 49152; camera origin/heading/viewz remain explicit map-unit inputs.
Structure TestSceneParams
  FrontFloor.l
  FrontCeiling.l
  FrontFloorName.s
  FrontCeilingName.s
  FrontLight.l
  BackFloor.l
  BackCeiling.l
  BackFloorName.s
  BackCeilingName.s
  BackLight.l
  TopWallName.s
  BottomWallName.s
  MiddleWallName.s
  TwoSided.l
  Heading.q
  ViewFloor.q
EndStructure

; Zero-safe caller defaults: common front/back heights and unused "-" slots.
Procedure TestSceneParamsBase(*Params.TestSceneParams)
  FillMemory(*Params, Int(SizeOf(TestSceneParams)), 0)
  *Params\FrontFloor = 0
  *Params\FrontCeiling = 128
  *Params\FrontFloorName = "FLOOR1"
  *Params\FrontCeilingName = "CEIL1"
  *Params\FrontLight = 160
  *Params\BackFloor = 0
  *Params\BackCeiling = 128
  *Params\BackFloorName = "FLOOR2"
  *Params\BackCeilingName = "CEIL2"
  *Params\BackLight = 160
  *Params\TopWallName = "-"
  *Params\BottomWallName = "-"
  *Params\MiddleWallName = "-"
  *Params\TwoSided = 0
  *Params\Heading = 0
  *Params\ViewFloor = 0
EndProcedure

Procedure.i TestPrepareParamsScene(*Params.TestSceneParams,
                                   *Level.MapLevel, *View.WallView,
                                   *Projection.Projection,
                                   *Visibility.WallVisibilityResult)
  Protected Dim sectors.TestSectorSpec(1)
  Protected Dim lines.TestLineSpec(0)
  Protected Dim sides.TestSideSpec(1)
  Protected Dim vertices.TestVertexSpec(1)
  Protected Dim segs.TestSegSpec(0)
  Protected Dim subs.TestSubSpec(0)
  Protected Dim nodes.TestNodeSpec(0)
  Protected sectorCount.l
  Protected lineCount.l = 1
  Protected sideCount.l
  Protected vertexCount.l = 2
  Protected segCount.l = 1
  Protected subCount.l = 1
  Protected nodeCount.l = 0
  Protected twoSided.i

  If *Params = 0 Or *Level = 0 Or *View = 0 Or *Projection = 0 Or *Visibility = 0
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(*Params\Heading) = 0
    ProcedureReturn #False
  EndIf
  twoSided = Bool(*Params\TwoSided <> 0)

  sectors(0)\FloorHeight = *Params\FrontFloor
  sectors(0)\CeilingHeight = *Params\FrontCeiling
  sectors(0)\LightLevel = *Params\FrontLight
  sectors(0)\FloorName = *Params\FrontFloorName
  sectors(0)\CeilingName = *Params\FrontCeilingName

  If twoSided
    sectorCount = 2
    sectors(1)\FloorHeight = *Params\BackFloor
    sectors(1)\CeilingHeight = *Params\BackCeiling
    sectors(1)\LightLevel = *Params\BackLight
    sectors(1)\FloorName = *Params\BackFloorName
    sectors(1)\CeilingName = *Params\BackCeilingName
    sideCount = 2
  Else
    sectorCount = 1
    sideCount = 1
  EndIf

  lines(0)\V1 = 0
  lines(0)\V2 = 1
  lines(0)\Flags = Bool(twoSided) * #MAP_ML_TWOSIDED
  lines(0)\Special = 0
  lines(0)\Tag = 0
  lines(0)\Side0 = 0
  If twoSided
    lines(0)\Side1 = 1
  Else
    lines(0)\Side1 = -1
  EndIf

  sides(0)\Sector = 0
  sides(0)\TopName = *Params\TopWallName
  sides(0)\BottomName = *Params\BottomWallName
  sides(0)\MidName = *Params\MiddleWallName
  If twoSided
    sides(1)\Sector = 1
    sides(1)\TopName = "-"
    sides(1)\BottomName = "-"
    sides(1)\MidName = "-"
  EndIf

  vertices(0)\X = 100
  vertices(0)\Y = 64
  vertices(1)\X = 100
  vertices(1)\Y = -64

  segs(0)\V1 = 0
  segs(0)\V2 = 1
  segs(0)\RawAngle = 49152
  segs(0)\Line = 0
  segs(0)\Side = 0
  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1

  If TestBuildFlexibleMap(*Level, @sectors(0), sectorCount,
                          @lines(0), lineCount,
                          @sides(0), sideCount,
                          @vertices(0), vertexCount,
                          @segs(0), segCount,
                          @subs(0), subCount,
                          @nodes(0), nodeCount) = #False
    ProcedureReturn #False
  EndIf
  If WallViewSetMapUnits(*View, 0, 0, *Params\Heading, *Params\ViewFloor) = #False
    ProcedureReturn #False
  EndIf
  If WallViewIsValid(*View) = 0 Or ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallVisibilityBuild(*Level, @*View\Camera, *Projection,
                                      0, 0, *Visibility)
EndProcedure

; ---------------------------------------------------------------------------
; Span/plan/frame helpers
; ---------------------------------------------------------------------------

Procedure.i TestReadVisibilitySpan(*Visibility.WallVisibilityResult, SpanIndex.l,
                                   *Span.WallSpan)
  Protected sub.l = 0
  Protected seg.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = -1

  If WallVisibilityGetSpan(*Visibility, SpanIndex, @sub, @seg, @line, @side,
                           @front, @back, @first, @last, @kind) = #False
    ProcedureReturn #False
  EndIf
  *Span\Subsector = sub
  *Span\Seg = seg
  *Span\Linedef = line
  *Span\Side = side
  *Span\FrontSector = front
  *Span\BackSector = back
  *Span\FirstX = first
  *Span\LastX = last
  *Span\Kind = kind
  ProcedureReturn #True
EndProcedure

Procedure.i TestProjectSpan(*Level.MapLevel, *View.WallView,
                            *Projection.Projection, *Span.WallSpan,
                            *Flats.FlatCatalog, *Textures.TextureCatalog,
                            *Plan.WallSpanPlan)
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected viewZ.l = 0

  If WallViewGet(*View, @cameraX, @cameraY, @heading, @viewZ) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallProjectSpanChecked(*Level, *Flats, *Textures, *Projection,
                                         cameraX, cameraY, heading, viewZ,
                                         *Span\Subsector, *Span, *Plan)
EndProcedure

Procedure.i TestFrameAndClipBegin(*FrameBuffer.FrameBuffer,
                                  *Clip.WallVerticalClip)
  If FrameBufferCreate(*FrameBuffer, 320, 200) = #False
    ProcedureReturn #False
  EndIf
  If FrameBufferClear(*FrameBuffer, #WALLDRAW_BackgroundIndex) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallVerticalClipBegin(*Clip)
EndProcedure

; Draws one already prepared plan into a frame/clip/tally state.
Procedure.i TestDrawPlan(*FrameBuffer.FrameBuffer, *Plan.WallSpanPlan,
                         *Clip.WallVerticalClip, *Tally.WallDrawTally)
  ProcedureReturn WallDrawSpan(*FrameBuffer, *Plan, *Clip, *Tally)
EndProcedure

; Independent FNV-1a64 of a hypothetical uniform 64,000-byte palette plane.
Procedure.q TestFnvUniformReference(PaletteIndex.i)
  Protected hash.q = #TEST_FNV_Offset
  Protected byteIndex.i

  For byteIndex = 0 To #WALLDRAW_PixelCount - 1
    hash = FnvAddByte(hash, PaletteIndex)
  Next
  ProcedureReturn hash
EndProcedure

; Raw map slot mutation for malformed/noncanonical name edge tests. Only the
; owned synthetic decoded MapLevel copy is touched; no WAD bytes are modified.
Procedure.i TestFillSideNameRaw(*Level.MapLevel, SideIndex.l, Field.l, Bytes.s)
  Protected *side.MapSidedef
  Protected i.i
  Protected value.i
  Protected *fieldBase.Byte

  If *Level = 0 Or MapLevelIsReady(*Level) = 0
    ProcedureReturn #False
  EndIf
  If SideIndex < 0 Or SideIndex >= *Level\Sidedefs\Count
    ProcedureReturn #False
  EndIf
  If Field < 0 Or Field > 2
    ProcedureReturn #False
  EndIf
  If Len(Bytes) > 8
    ProcedureReturn #False
  EndIf
  *side = *Level\Sidedefs\Items + SideIndex * SizeOf(MapSidedef)
  If Field = 0
    *fieldBase = @*side\TopTexture
  ElseIf Field = 1
    *fieldBase = @*side\BottomTexture
  Else
    *fieldBase = @*side\MidTexture
  EndIf
  For i = 0 To 7
    If i < Len(Bytes)
      value = Asc(Mid(Bytes, i + 1, 1))
    Else
      value = 0
    EndIf
    PokeA(*fieldBase + i, value & $FF)
  Next
  ProcedureReturn #True
EndProcedure

; One raw byte mutation at an exact slot index for malformed byte-pattern edges.
Procedure.i TestPokeSideNameRawByte(*Level.MapLevel, SideIndex.l, Field.l,
                                   ByteIndex.l, ByteValue.i)
  Protected *side.MapSidedef
  Protected *fieldBase.Byte

  If *Level = 0 Or MapLevelIsReady(*Level) = 0
    ProcedureReturn #False
  EndIf
  If SideIndex < 0 Or SideIndex >= *Level\Sidedefs\Count Or
     Field < 0 Or Field > 2 Or ByteIndex < 0 Or ByteIndex > 7
    ProcedureReturn #False
  EndIf
  *side = *Level\Sidedefs\Items + SideIndex * SizeOf(MapSidedef)
  If Field = 0
    *fieldBase = @*side\TopTexture
  ElseIf Field = 1
    *fieldBase = @*side\BottomTexture
  Else
    *fieldBase = @*side\MidTexture
  EndIf
  PokeA(*fieldBase + Int(ByteIndex), ByteValue & $FF)
  ProcedureReturn #True
EndProcedure

; Raw map SEG V1 mutation for corrupt-index transactional tests.
Procedure.i TestPokeMapSegV1(*Level.MapLevel, SegIndex.l, V1.l)
  Protected *seg.MapSeg

  If *Level = 0 Or MapLevelIsReady(*Level) = 0
    ProcedureReturn #False
  EndIf
  If SegIndex < 0 Or SegIndex >= *Level\Segs\Count
    ProcedureReturn #False
  EndIf
  *seg = *Level\Segs\Items + SegIndex * SizeOf(MapSeg)
  *seg\V1 = V1
  ProcedureReturn #True
EndProcedure

; Canonical 16-character uppercase hexadecimal text predicate, exactly the
; documented WallFrameHashHex64 policy.
Procedure.i TestHexTextCanonical(Text.s)
  Protected i.i
  Protected value.i

  If Len(Text) <> 16
    ProcedureReturn #False
  EndIf
  For i = 1 To 16
    value = Asc(Mid(Text, i, 1))
    If value < Asc("0") Or value > Asc("F") Or
       (value > Asc("9") And value < Asc("A"))
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent golden comparisons
; ---------------------------------------------------------------------------

Procedure.i TestCompareSpansGold(SceneId.s, *Visibility.WallVisibilityResult)
  Protected expectedCount.l
  Protected actualCount.l
  Protected spanIndex.i
  Protected fieldIndex.i
  Protected actual.l = 0
  Protected expected.l = 0
  Protected span.WallSpan
  Protected mismatch.i = 0
  Protected compared.i = 0

  expectedCount = GoldSceneSpanCount(SceneId)
  actualCount = WallVisibilityCount(*Visibility)
  If expectedCount < 0 Or actualCount <> expectedCount
    ProcedureReturn #False
  EndIf
  For spanIndex = 0 To expectedCount - 1
    If TestReadVisibilitySpan(*Visibility, spanIndex, @span) = #False
      ProcedureReturn #False
    EndIf
    For fieldIndex = 0 To #WALLGOLD_SpanFieldCount - 1
      If GoldSpanGet(SceneId, spanIndex, fieldIndex, @expected) = #False
        ProcedureReturn #False
      EndIf
      If fieldIndex = 0
        actual = span\Subsector
      ElseIf fieldIndex = 1
        actual = span\Seg
      ElseIf fieldIndex = 2
        actual = span\Linedef
      ElseIf fieldIndex = 3
        actual = span\Side
      ElseIf fieldIndex = 4
        actual = span\FrontSector
      ElseIf fieldIndex = 5
        actual = span\BackSector
      ElseIf fieldIndex = 6
        actual = span\FirstX
      ElseIf fieldIndex = 7
        actual = span\LastX
      ElseIf fieldIndex = 8
        actual = span\Kind
      EndIf
      If actual <> expected
        mismatch + 1
      EndIf
      compared + 1
    Next
  Next
  ProcedureReturn Bool(mismatch = 0 And compared = expectedCount * #WALLGOLD_SpanFieldCount)
EndProcedure

; Compares every generator plan L/Q field for one span against the prepared plan.
Procedure.i TestComparePlanGold(SceneId.s, PlanIndex.l, *Plan.WallSpanPlan)
  Protected fieldIndex.i
  Protected expected.l = 0
  Protected actual.l = 0
  Protected expectedQ.q = 0
  Protected actualQ.q = 0
  Protected mismatch.i = 0
  Protected compared.i = 0
  Protected Dim lFields.l(#WALLGOLD_PlanLFieldCount - 1)
  Protected Dim qFields.q(#WALLGOLD_PlanQFieldCount - 1)

  If *Plan = 0 Or WallSpanPlanIsReady(*Plan) = #False
    ProcedureReturn #False
  EndIf
  If PlanIndex < 0 Or PlanIndex >= GoldSceneSpanCount(SceneId)
    ProcedureReturn #False
  EndIf

  lFields(0) = *Plan\Subsector
  lFields(1) = *Plan\Seg
  lFields(2) = *Plan\Linedef
  lFields(3) = *Plan\Side
  lFields(4) = *Plan\FrontSector
  lFields(5) = *Plan\BackSector
  lFields(6) = *Plan\FirstX
  lFields(7) = *Plan\LastX
  lFields(8) = *Plan\Kind
  lFields(9) = *Plan\Hyp
  lFields(10) = *Plan\Distance
  lFields(11) = *Plan\Scale1
  lFields(12) = *Plan\Scale2
  lFields(13) = *Plan\ScaleStep
  lFields(14) = *Plan\WorldTopRaw
  lFields(15) = *Plan\WorldBottomRaw
  lFields(16) = *Plan\WorldHighRaw
  lFields(17) = *Plan\WorldLowRaw
  lFields(18) = *Plan\WorldTop
  lFields(19) = *Plan\WorldBottom
  lFields(20) = *Plan\WorldHigh
  lFields(21) = *Plan\WorldLow
  lFields(22) = *Plan\TopFrac
  lFields(23) = *Plan\BottomFrac
  lFields(24) = *Plan\TopStep
  lFields(25) = *Plan\BottomStep
  lFields(26) = *Plan\PixHigh
  lFields(27) = *Plan\PixLow
  lFields(28) = *Plan\PixHighStep
  lFields(29) = *Plan\PixLowStep
  lFields(30) = *Plan\MarkFloor
  lFields(31) = *Plan\MarkCeiling
  lFields(32) = *Plan\TopRegion
  lFields(33) = *Plan\BottomRegion
  lFields(34) = *Plan\TopTier
  lFields(35) = *Plan\BottomTier
  lFields(36) = *Plan\MiddleTier
  lFields(37) = *Plan\FrontSky
  lFields(38) = *Plan\BackSky
  lFields(39) = *Plan\SkyHack
  lFields(40) = *Plan\ClosedDoor
  lFields(41) = *Plan\TopTexturePresent
  lFields(42) = *Plan\BottomTexturePresent
  lFields(43) = *Plan\MiddleTexturePresent

  qFields(0) = *Plan\ViewAngle
  qFields(1) = *Plan\NormalAngle
  qFields(2) = *Plan\ReferenceAngle
  qFields(3) = *Plan\RawAngularSeparation
  qFields(4) = *Plan\OffsetAngle
  qFields(5) = *Plan\DistAngle

  For fieldIndex = 0 To #WALLGOLD_PlanLFieldCount - 1
    If GoldPlanLGet(SceneId, PlanIndex, fieldIndex, @expected) = #False
      ProcedureReturn #False
    EndIf
    If lFields(fieldIndex) <> expected
      mismatch + 1
    EndIf
    compared + 1
  Next
  For fieldIndex = 0 To #WALLGOLD_PlanQFieldCount - 1
    If GoldPlanQGet(SceneId, PlanIndex, fieldIndex, @expectedQ) = #False
      ProcedureReturn #False
    EndIf
    If qFields(fieldIndex) <> expectedQ
      mismatch + 1
    EndIf
    compared + 1
  Next
  ProcedureReturn Bool(mismatch = 0 And
                       compared = #WALLGOLD_PlanLFieldCount + #WALLGOLD_PlanQFieldCount)
EndProcedure

Procedure.i TestCompareGoldSampleColumn(SceneId.s, Column.l,
                                        *FrameBuffer.FrameBuffer)
  Protected sampleIndex.l = 0
  Protected row.i
  Protected expected.l = 0
  Protected actual.i
  Protected mismatch.i = 0

  If GoldSampleIndexForColumn(SceneId, Column, @sampleIndex) = #False
    ProcedureReturn #False
  EndIf
  For row = 0 To #WALLGOLD_SampleRowBytes - 1
    If GoldSampleRowGet(SceneId, sampleIndex, row, @expected) = #False
      ProcedureReturn #False
    EndIf
    actual = FrameBufferGetPixel(*FrameBuffer, Column, row)
    If actual < 0
      ProcedureReturn #False
    EndIf
    If actual <> expected
      mismatch + 1
    EndIf
  Next
  ProcedureReturn Bool(mismatch = 0)
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic wall texture catalog for catalog-aware slot tests
; ---------------------------------------------------------------------------

Structure TestTexSpec
  Name.s
  Width.l
  Height.l
  PNameIndex.l
EndStructure

Procedure Put32(*Data.Byte, Offset.i, Value.q)
  PokeA(*Data + Offset, Value & $FF)
  PokeA(*Data + Offset + 1, (Value >> 8) & $FF)
  PokeA(*Data + Offset + 2, (Value >> 16) & $FF)
  PokeA(*Data + Offset + 3, (Value >> 24) & $FF)
EndProcedure

Procedure.i MakeTexture1Lump(*Specs.TestTexSpec, Count.i, *OutSize.Quad)
  Protected size.q = 4 + Int(Count) * 4 + Int(Count) * 32
  Protected *data.Byte = NewZero(size)
  Protected i.i
  Protected definitionOffset.q = 4 + Int(Count) * 4
  Protected *spec.TestTexSpec

  If *data = 0
    *OutSize\q = 0
    ProcedureReturn 0
  EndIf
  Put32(*data, 0, Count)
  For i = 0 To Count - 1
    *spec = *Specs + i * SizeOf(TestTexSpec)
    Put32(*data, 4 + i * 4, definitionOffset)
    PutName8(*data, Int(definitionOffset), *spec\Name)
    Put32(*data, Int(definitionOffset) + 8, 0)
    Put16(*data, Int(definitionOffset) + 12, *spec\Width)
    Put16(*data, Int(definitionOffset) + 14, *spec\Height)
    Put32(*data, Int(definitionOffset) + 16, 0)
    Put16(*data, Int(definitionOffset) + 20, 1)
    Put16(*data, Int(definitionOffset) + 22, 0)
    Put16(*data, Int(definitionOffset) + 24, 0)
    Put16(*data, Int(definitionOffset) + 26, *spec\PNameIndex)
    Put16(*data, Int(definitionOffset) + 28, 0)
    Put16(*data, Int(definitionOffset) + 30, 0)
    definitionOffset + 32
  Next
  *OutSize\q = size
  ProcedureReturn *data
EndProcedure

; ---------------------------------------------------------------------------
; WP01 - WP29: constants, view height, angle/distance/scale/height primitives
; ---------------------------------------------------------------------------

Procedure TestWP01()
  BeginCase("WP01", "Constants: canonical 320x200, 16.16 fixed, HEIGHTBITS=12")
  Check(Bool(#WALLDRAW_ViewWidth = 320 And #WALLDRAW_ViewHeight = 200),
        "classic framebuffer width/height are exactly 320x200")
  Check(Bool(#WALLDRAW_PixelCount = 64000),
        "row-major index plane is exactly 64000 pixels")
  Check(Bool(#FRACBITS = 16 And #FRACUNIT = 65536),
        "16 integer/16 fractional fixed format from m_fixed.h")
  Check(Bool(#WALLPROJ_HeightBits = 12 And #WALLPROJ_HeightUnit = 4096),
        "r_segs.c HEIGHTBITS=12 / HEIGHTUNIT=4096 interpolation constants")
  Check(Bool(#PROJ_VIEWWIDTH = 320 And #PROJ_VIEWHEIGHT = 200 And
             #PROJ_CENTERX = 160 And #PROJ_CENTERY = 100),
        "reused canonical projection constants are not drifting")
  Check(Bool(#WALLDRAW_FNV_Offset = -3750763034362895579 And
             #WALLDRAW_FNV_Prime = 1099511628211),
        "frame hash constants are the documented FNV-1a64 offset/prime")
EndProcedure

Procedure TestWP02()
  BeginCase("WP02", "Checked WallView setter/getter/reset without WAD")
  Protected view.WallView
  Protected x.l = 0
  Protected y.l = 0
  Protected heading.q = 0
  Protected viewZ.l = 0
  Protected getOk.i
  Protected resetOk.i

  Check(Bool(WallViewReset(@view) <> 0), "fresh zero WallView resets to empty reusable state")
  Check(Bool(WallViewIsValid(@view) = 0), "reset view is not ready")
  Check(Bool(WallViewSetFixed(@view, 0, 0, #BAM_ANG45,
                              #WALLVIEW_ViewHeightFixed) <> 0),
        "explicit fixed camera and signed viewz setter succeeds")
  getOk = WallViewGet(@view, @x, @y, @heading, @viewZ)
  Check(Bool(getOk <> 0), "ready view copies camera and viewz")
  Check(Bool(x = 0 And y = 0 And heading = #BAM_ANG45 And
             viewZ = #WALLVIEW_ViewHeightFixed),
        "getter returns exactly the published fixed/BAM values")
  resetOk = WallViewReset(@view)
  Check(Bool(resetOk <> 0), "ready view reset is idempotent and leaves no heap state")
  Check(Bool(WallViewGet(@view, @x, @y, @heading, @viewZ) = 0),
        "reset view getter rejects a not-ready wrapper")
EndProcedure

Procedure TestWP03()
  BeginCase("WP03", "viewz conversion floor map units + 41, 64-bit overflow checks")
  Protected viewZ.l = 0
  Protected floorSum.q

  Check(Bool(WallViewHeightFromFloorChecked(0, @viewZ) <> 0), "floor 0 viewz succeeds")
  Check(Bool(viewZ = #WALLVIEW_ViewHeightFixed), "floor 0 gives exactly 41*FRACUNIT")
  Check(Bool(viewZ = 2686976), "41*65536 measured signed fixed value")
  Check(Bool(WallViewHeightFromFloorChecked(-32, @viewZ) <> 0), "negative floor -32 succeeds")
  Check(Bool(viewZ = 589824), "floor -32: -2097152 + 2686976 = 589824")
  Check(Bool(WallViewHeightFromFloorChecked(32726, @viewZ) <> 0),
        "largest map-unit floor that still fits viewz succeeds")
  floorSum = Int(32726) * #FRACUNIT + Int(#WALLVIEW_ViewHeightFixed)
  Check(Bool(viewZ = floorSum And floorSum <= #FIXED_MAX),
        "32726 floor maps to checked exact widened signed sum 2147418112")
  Check(Bool(WallViewHeightFromFloorChecked(32732, @viewZ) = 0),
        "32732 floor + VIEWHEIGHT exceeds signed32 and is diagnosed")
  Check(Bool(WallViewHeightFromFloorChecked(32767, @viewZ) = 0),
        "maximum map-unit 32767 cannot fit viewz after +41 and is rejected")
  Check(Bool(WallViewHeightFromFloorChecked(32768, @viewZ) = 0),
        "32768 map units cannot be represented as signed fixed_t")
  Check(Bool(WallViewHeightFromFloorChecked(-32768, @viewZ) <> 0),
        "floor -32768 produces INT_MIN + VIEWHEIGHT inside signed32 and succeeds")
  Check(Bool(viewZ = -2144796672),
        "floor -32768 checked viewz equals -2147483648+2686976=-2144796672")
  Check(Bool(WallViewHeightFromFloorChecked(-32769, @viewZ) = 0),
        "floor -32769 is outside the signed map-unit domain")
EndProcedure

Procedure TestWP04()
  BeginCase("WP04", "Negative floor/ceiling/viewz differences and arithmetic shift")
  Protected viewZ.q = #WALLVIEW_ViewHeightFixed
  Protected ceilingPositive.q = 128 * #FRACUNIT
  Protected floorNegative.q = -32 * #FRACUNIT
  Protected ceilNegative.q = -16 * #FRACUNIT
  Protected floorPositive.q = 64 * #FRACUNIT
  Protected worldTop.l = 0
  Protected worldBottom.l = 0
  Protected shiftedTop.l = 0
  Protected shiftedBottom.l = 0

  worldTop = WallFixedSubLow(Int(ceilingPositive), Int(viewZ))
  worldBottom = WallFixedSubLow(Int(floorNegative), Int(viewZ))
  Check(Bool(worldTop = 5701632), "positive ceiling-viewz fixed offset is exact")
  Check(Bool(worldBottom = -4784128), "negative floor-viewz fixed offset is exact negative")
  shiftedTop = worldTop >> 4
  shiftedBottom = worldBottom >> 4
  Check(Bool(shiftedTop = 356352), "positive worldtop >>4 arithmetic result")
  Check(Bool(shiftedBottom = -299008), "negative worldbottom >>4 floors toward negative infinity")
  worldTop = WallFixedSubLow(Int(ceilNegative), Int(viewZ))
  Check(Bool(worldTop = -3735552), "negative ceiling offset keeps its sign")
  Check(Bool((worldTop >> 4) = -233472), "negative ceiling >>4 exact floor quotient")
  worldTop = WallFixedSubLow(Int(floorPositive), Int(viewZ))
  worldBottom = WallFixedSubLow(Int(ceilNegative), Int(viewZ))
  Check(Bool(worldTop = 1507328), "positive floor-viewz offset is positive")
  Check(Bool((worldTop >> 4) = 94208), "positive >>4 non-negative")
EndProcedure

Procedure TestWP05()
  BeginCase("WP05", "BAM rw_normalangle=segangle+ANG90 raw transport")
  Protected normal.q = 0
  Protected rawAngle.q = 0

  Check(Bool(WallSegNormalAngleChecked(0, @normal) <> 0), "seg raw 0 normal succeeds")
  Check(Bool(normal = #BAM_ANG90), "seg raw 0 -> ANG90 unsigned wrap")
  Check(Bool(WallSegNormalAngleChecked(49152, @normal) <> 0), "seg raw ANG270 succeeds")
  Check(Bool(normal = 0), "seg raw 49152/ANG270 + ANG90 wraps to raw 0")
  Check(Bool(WallSegNormalAngleChecked(-16384, @normal) <> 0),
        "C SHORT -16384 carries the same bits as unsigned 49152")
  Check(Bool(normal = 0), "signed raw16 transport gives the same normal raw bits")
  Check(Bool(WallSegNormalAngleChecked(32768, @normal) <> 0),
        "unsigned/A raw16 32768 = ANG180>>16 converts")
  Check(Bool(WallSegRawAngleToBamChecked(32768, @rawAngle) <> 0 And rawAngle = $80000000),
        "raw conversion stores 2147483648 in a Quad field, not a signed Long")
  Check(Bool(normal = $C0000000), "ANG180+ANG90 unsigned addition = ANG270 raw")
  Check(Bool(BamRawInUnsignedDomain(normal) <> 0), "raw transport is canonical even above INT32_MAX")
EndProcedure

Procedure TestWP06()
  BeginCase("WP06", "SEGS raw 16-bit angle -> BAM: 0/90/180/270 and wrap edges")
  Protected raw.q = 0
  Protected expected.q

  Check(Bool(WallSegRawAngleToBamChecked(0, @raw) <> 0 And raw = 0),
        "raw16 0 -> BAM raw 0")
  Check(Bool(WallSegRawAngleToBamChecked(16384, @raw) <> 0 And raw = #BAM_ANG90),
        "raw16 ANG90>>16=16384 -> ANG90 raw")
  Check(Bool(WallSegRawAngleToBamChecked(32768, @raw) <> 0 And raw = #BAM_ANG180),
        "raw16 ANG180>>16=32768 (signed SHORT -32768) -> ANG180 raw")
  Check(Bool(WallSegRawAngleToBamChecked(49152, @raw) <> 0 And raw = #BAM_ANG270),
        "raw16 ANG270>>16=49152 -> ANG270 raw")
  Check(Bool(WallSegRawAngleToBamChecked(-16384, @raw) <> 0 And raw = #BAM_ANG270),
        "signed raw16 -16384 maps to the same ANG270 low32 bits")
  Check(Bool(WallSegRawAngleToBamChecked(65535, @raw) <> 0 And raw = $FFFF0000),
        "unsigned max raw16 65535 leaves $FFFF0000")
  Check(Bool(WallSegRawAngleToBamChecked(-1, @raw) <> 0 And raw = $FFFF0000),
        "signed -1 bits match unsigned 65535 low32")
  Check(Bool(WallSegRawAngleToBamChecked(1, @raw) <> 0 And raw = $00010000),
        "raw16 one maps to the smallest nonzero BAM unit")
  Check(Bool(WallSegRawAngleToBamChecked(65536, @raw) = 0),
        "raw16 above unsigned 16-bit max is rejected")
  Check(Bool(WallSegRawAngleToBamChecked(-32769, @raw) = 0),
        "raw16 below signed 16-bit minimum is rejected")
EndProcedure

Procedure TestWP07()
  BeginCase("WP07", "Original unclipped v1 angle drives distance, not span endpoints")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected viewZ.l = 0
  Protected v1X.l = 0
  Protected v1Y.l = 0
  Protected segAngleRaw.l = 0
  Protected segV1.l = 0
  Protected v1FixedX.l = 0
  Protected v1FixedY.l = 0
  Protected referenceOracle.BamAngleValue
  Protected inverseFirst.q = 0
  Protected visFirst.q = 0
  Protected planOk.i

  If TestPrepareScene("B", @map, @view, @projection, @visibility) = #False
    Check(#False, "scene B synthetic map/view/projection/visibility prepares")
    MapLevelReset(@map)
    WallVisibilityReset(@visibility)
    ProcedureReturn
  EndIf
  Check(Bool(TestCompareSpansGold("B", @visibility) <> 0),
        "scene B visibility spans equal the independent golden record")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "span 0 is readable")
  If MapSegsGet(@map\Segs, span\Seg, @segV1, 0, @segAngleRaw, 0, 0, 0) = #False
    Check(#False, "seg v1 record reads for independent reference oracle")
  Else
    Check(Bool(MapVertexesGet(@map\Vertexes, segV1, @v1X, @v1Y) <> 0), "v1 vertex reads")
    Check(Bool(FixedFromIntChecked(v1X, @v1FixedX) <> 0 And
               FixedFromIntChecked(v1Y, @v1FixedY) <> 0), "v1 coordinates convert checked")
    Check(Bool(WallViewGet(@view, @cameraX, @cameraY, @heading, @viewZ) <> 0),
          "view camera/viewz reads")
    Check(Bool(GeometryPointToAngleChecked(cameraX, cameraY, v1FixedX, v1FixedY,
                                           @referenceOracle) <> 0),
          "test-only original v1 point angle computes")
    Check(Bool(WallSegRawAngleToBamChecked(segAngleRaw, @segAngleRaw) <> 0),
          "seg stored raw16 converts for independent normal")
    planOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
    Check(Bool(planOk <> 0), "production span projection builds the plan")
    Check(Bool(plan\ReferenceAngle = referenceOracle\Raw),
          "plan reference angle equals the original v1 point angle")
    Check(Bool(ProjectionGetXToViewAngle(@projection, span\FirstX, @inverseFirst) <> 0),
          "first-column inverse angle reads")
    visFirst = BamAdd(heading, inverseFirst)
    Check(Bool(plan\ReferenceAngle <> visFirst),
          "plan reference angle is not the FOV-truncated span-endpoint view angle")
    Check(Bool(TestComparePlanGold("B", 0, @plan) <> 0),
          "all plan L/Q fields equal the Python plan oracle")
  EndIf
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  WallViewReset(@view)
  ProjectionReset(@projection)
EndProcedure

Procedure TestWP08()
  BeginCase("WP08", "Angular separation wrap near 0/180/360 and clamp")
  Protected magnitude.q = 0
  Protected offset.q = 0
  Protected delta.q
  Protected reject.i

  Check(Bool(WallAngleOffsetChecked(#BAM_ANG90, #BAM_ANG90, @magnitude, @offset) <> 0),
        "equal normal/reference angles succeed")
  Check(Bool(magnitude = 0 And offset = 0), "identical angles have zero separation/offset")
  delta = BamSubtract(0, 0)
  Check(Bool(delta = 0), "near-zero wrap delta tests the exact unsigned subtract")
  Check(Bool(WallAngleOffsetChecked(1, 2, @magnitude, @offset) <> 0),
        "one-unit wrap near a full turn succeeds")
  Check(Bool(magnitude = 1 And offset = 1), "normal 1 vs reference 2 wraps delta to 1 raw")
  Check(Bool(WallAngleOffsetChecked(#BAM_ANG270, #BAM_ANG90, @magnitude, @offset) = 0),
        "exact 180-degree opposite separation is the abs(INT32_MIN) rejected edge")
  Check(Bool(WallAngleOffsetChecked(#BAM_ANG270, #BAM_ANG90 + 1, @magnitude, @offset) <> 0),
        "near-180 delta just above INT32_MIN succeeds")
  Check(Bool(magnitude = 2147483647), "near-180 separation magnitude is the signed-max magnitude")
  Check(Bool(offset = #BAM_ANG90), "magnitude beyond ANG90 clamps exactly to ANG90")
  Check(Bool(WallAngleOffsetChecked(#BAM_ANG180 + 1, 0,
                                    @magnitude, @offset) <> 0),
        "normal just above ANG180 vs zero reference succeeds")
  Check(Bool(magnitude = 2147483647),
        "unsigned delta $80000001 maps via 2^32-delta to signed abs magnitude 2147483647")
  Check(Bool(offset = #BAM_ANG90), "any magnitude > ANG90 is the source clamp")
  Check(Bool(WallAngleOffsetChecked(-1, 0, @magnitude, @offset) = 0),
        "noncanonical negative input angle rejected")
EndProcedure

Procedure TestWP09()
  BeginCase("WP09", "distangle clamp at ANG90 and exact boundary equality")
  Protected clamped.q = 0
  Protected dist.q = 0
  Protected fine.l = 0
  Protected sine.l = 0

  Check(Bool(WallDistanceAngleChecked(#BAM_ANG90, @clamped, @dist, @fine, @sine) <> 0),
        "offset exactly ANG90 succeeds")
  Check(Bool(clamped = #BAM_ANG90 And dist = 0), "ANG90 boundary equality gives distangle 0, unchanged")
  Check(Bool(fine = 0 And sine = 25), "distangle 0 maps to fine index0 and pinned sine value25")
  Check(Bool(WallDistanceAngleChecked(#BAM_ANG90 - 1, @clamped, @dist, @fine, @sine) <> 0),
        "offset ANG90-1 below boundary succeeds")
  Check(Bool(clamped = #BAM_ANG90 - 1 And dist = 1), "below boundary keeps offset and distangle 1")
  Check(Bool(WallDistanceAngleChecked(#BAM_ANG90 + 1, @clamped, @dist, @fine, @sine) <> 0),
        "offset just above ANG90 clamps")
  Check(Bool(clamped = #BAM_ANG90 And dist = 0), "offset > ANG90 becomes exactly ANG90/distangle0")
  Check(Bool(WallDistanceAngleChecked(0, @clamped, @dist, @fine, @sine) <> 0),
        "zero offset succeeds")
  Check(Bool(dist = #BAM_ANG90 And fine = 2048 And sine = 65535),
        "offset 0 yields distangle ANG90, fine 2048 and pinned sine 65535")
  Check(Bool(WallDistanceAngleChecked(-1, @clamped, @dist, @fine, @sine) = 0),
        "negative angle_t offset is rejected")
  Check(Bool(WallDistanceAngleChecked(#BAM_RAW_MAX + 1, @clamped, @dist, @fine, @sine) = 0),
        "out-of-ring offset is rejected")
EndProcedure

Procedure TestWP10()
  BeginCase("WP10", "R_PointToDist hyp and FixedMul distance golden vectors")
  Protected hip.l = 0
  Protected hip2.l = 0
  Protected distance.l = 0
  Protected sineval.l = 0

  Check(Bool(GeometryPointToDistChecked(0, 0, 100 * #FRACUNIT, 64 * #FRACUNIT,
                                        @hip) <> 0),
        "production R_PointToDist computes positive hyp for (100,64)")
  Check(Bool(hip = 7778060), "hyp equals the independent Python scene B 7778060")
  Check(Bool(WallSegPointDistanceChecked(0, 0, 100 * #FRACUNIT, 64 * #FRACUNIT,
                                         @hip2) <> 0),
        "production checked wall v1 distance accepts the same hyp")
  Check(Bool(hip2 = hip), "checked wall hyp equals raw geometry hyp")
  sineval = 55219
  distance = FixedMul(hip2, sineval)
  Check(Bool(WallWallDistanceChecked(hip2, sineval, @distance) <> 0),
        "checked WallWallDistance produces the source FixedMul result")
  Check(Bool(distance = 6553599 And distance = FixedMul(7778060, 55219)),
        "golden distance equals explicit test FixedMul(hyp,sineval)=6553599")
  Check(Bool(WallWallDistanceChecked(hip2, 65536, @distance) <> 0),
        "sine exactly FRACUNIT succeeds")
  Check(Bool(distance = hip2), "FixedMul(hyp,FRACUNIT) returns exact hyp")
EndProcedure

Procedure TestWP11()
  BeginCase("WP11", "Coincident/near-zero vertex distance deterministic policy")
  Protected geomDist.l = -1
  Protected wallHyp.l = -1
  Protected nearDistance.l = -1
  Protected scale.l = -1
  Protected errorText.s

  Check(Bool(GeometryPointToDistChecked(0, 0, 0, 0, @geomDist) <> 0),
        "coincident primitive is deterministic valid")
  Check(Bool(geomDist = 0), "GeometryPointToDistChecked returns exact zero at coincidence")
  Check(Bool(WallSegPointDistanceChecked(0, 0, 0, 0, @wallHyp) = 0),
        "coincident seg-v1/camera wall distance is explicitly rejected")
  errorText = WallProjectLastError()
  Check(Bool(FindString(errorText, "coincides") > 0),
        "diagnostic names the coincident viewpoint edge")
  Check(Bool(WallSegPointDistanceChecked(0, 0, 1, 0, @wallHyp) <> 0),
        "nonzero near-zero fixed v1 offset remains accepted")
  Check(Bool(wallHyp > 0), "near-zero vertex hyp stays positive")
  Check(Bool(WallWallDistanceChecked(wallHyp, 25, @nearDistance) <> 0),
        "tiny hyp plus pinned sine25 is accepted without division")
  Check(Bool(nearDistance = FixedMul(wallHyp, 25)), "tiny distance is the explicit FixedMul truncation")
  Check(Bool(WallScaleFromSinesChecked(10485760, nearDistance, 25, 1, @scale) <> 0),
        "scale denominator-zero branch executes deterministically")
  Check(Bool(nearDistance = 0), "tiny hyp 1 with sine25 truncates distance to zero")
  Check(Bool(scale = #WALLPROJ_ScaleMax),
        "distance zero / den==num>>16==0 selects exact source 64F default, no divide")
EndProcedure

Procedure TestWP12()
  BeginCase("WP12", "Positive/negative coordinate pairs, all four cardinal facings")
  Protected pX.l = 0
  Protected nX.l = 0
  Protected pY.l = 0
  Protected nY.l = 0
  Protected expected.q
  Protected fine.l = 0
  Protected sine.l = 0

  Check(Bool(GeometryPointToDistChecked(0, 0, 100 * #FRACUNIT, 0, @pX) <> 0),
        "positive-X cardinal point distance computes")
  Check(Bool(GeometryPointToDistChecked(0, 0, -100 * #FRACUNIT, 0, @nX) <> 0),
        "negative-X mirrored point distance computes")
  Check(Bool(GeometryPointToDistChecked(0, 0, 0, 100 * #FRACUNIT, @pY) <> 0),
        "positive-Y cardinal point distance computes")
  Check(Bool(GeometryPointToDistChecked(0, 0, 0, -100 * #FRACUNIT, @nY) <> 0),
        "negative-Y mirrored point distance computes")
  Check(Bool(pX > 0 And pX = nX And pX = pY And pX = nY),
        "all four cardinal facings produce the same positive fixed distance")
  Check(Bool(WallDistanceAngleChecked(0, @expected, @expected, @fine, @sine) <> 0),
        "ANG90 distangle sine lookup succeeds for cardinal formula")
  expected = 6553600 * #FRACUNIT / 65535
  Check(Bool(pX = expected), "cardinal distance equals explicit fixed-division formula")
EndProcedure

Procedure TestWP13()
  BeginCase("WP13", "R_ScaleFromGlobalAngle ordinary scene-B reference vectors")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected goldScale1.l = 0
  Protected goldScale2.l = 0
  Protected goldStep.l = 0
  Protected planOk.i

  If TestPrepareScene("B", @map, @view, @projection, @visibility) = #False
    Check(#False, "scene B prepares for scale golden")
    ProcedureReturn
  EndIf
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "scene B span readable")
  planOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(planOk <> 0), "scene B plan projection succeeds")
  Check(Bool(GoldPlanLGet("B", 0, 11, @goldScale1) <> 0 And
             GoldPlanLGet("B", 0, 12, @goldScale2) <> 0 And
             GoldPlanLGet("B", 0, 13, @goldStep) <> 0), "golden scale fields readable")
  Check(Bool(plan\Scale1 = goldScale1 And plan\Scale2 = goldScale2 And
             plan\ScaleStep = goldStep),
        "production start/end scale and step equal independent fixed-point oracle")
  Check(Bool(plan\Scale1 = 104857 And plan\Scale2 = 104857 And plan\ScaleStep = 0),
        "measured perpendicular scene scales are deterministic 104857")
  Check(Bool(plan\Scale1 >= #WALLPROJ_ScaleMin And plan\Scale1 <= #WALLPROJ_ScaleMax),
        "ordinary scale stays inside original 256..64F clamp band")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP14()
  BeginCase("WP14", "Scale lower clamp at 256")
  Protected scale.l = 0
  Protected expected.q

  Check(Bool(WallScaleFromSinesChecked(10485760, 41000, 65536, 1, @scale) <> 0),
        "true branch with small quotient succeeds")
  expected = (FixedMul(10485760, 1)) * #FRACUNIT / FixedMul(41000, 65536)
  Check(Bool(expected >= 0 And expected < 256), "independent quotient is below 256")
  Check(Bool(scale = 256), "scale just below original minimum clamps to exactly 256")
EndProcedure

Procedure TestWP15()
  BeginCase("WP15", "Scale upper clamp at 64*65536")
  Protected scale.l = 0
  Protected expected.l

  Check(Bool(WallScaleFromSinesChecked(10485760, 2, 65536, 1, @scale) <> 0),
        "true branch with large quotient succeeds")
  expected = FixedDiv(FixedMul(10485760, 1), FixedMul(2, 65536))
  Check(Bool(expected > #WALLPROJ_ScaleMax), "independent quotient exceeds 64*FRACUNIT")
  Check(Bool(scale = #WALLPROJ_ScaleMax), "scale above maximum clamps to exactly 64*FRACUNIT")
  Check(Bool(#WALLPROJ_ScaleMax = 4194304), "64*65536 measured value")
EndProcedure

Procedure TestWP16()
  BeginCase("WP16", "den > num>>16 strict branch including equality")
  Protected scale.l = 0
  Protected num.l
  Protected numHigh.l
  Protected den.l

  num = FixedMul(10485760, 1)
  numHigh = num >> 16
  den = FixedMul(0, 25)
  Check(Bool(numHigh = 0 And den = 0), "equality setup num>>16 == den == 0")
  Check(Bool(WallScaleFromSinesChecked(10485760, 0, 25, 1, @scale) <> 0),
        "equality scale call succeeds")
  Check(Bool(scale = #WALLPROJ_ScaleMax), "strict `den > num>>16` equality takes 64F default branch")
  den = FixedMul(1, 65536)
  Check(Bool(den = 1 And numHigh = 0), "strict-above setup den=1 > num>>16=0")
  Check(Bool(WallScaleFromSinesChecked(10485760, 1, 65536, 1, @scale) <> 0),
        "strict-above scale call succeeds")
  Check(Bool(scale = #WALLPROJ_ScaleMax), "strict-above quotient is clamped at upper bound")
  Check(Bool(FixedDiv(num, den) = 10485760), "explicit FixedDiv intermediate confirms branch arithmetic")
EndProcedure

Procedure TestWP17()
  BeginCase("WP17", "Valid sine/tangent indexes with exact pinned table values and bounds")
  Protected sine.l = 0
  Protected tangent.l = 0
  Protected signedIndex.l = 0
  Protected signedSine.l = 0
  Protected expected.l = 0

  Check(Bool(TrigSineChecked(0, @sine) <> 0), "finesine index0 readable")
  expected = PeekL(*gGoldSineIndex0)
  Check(Bool(sine = expected And sine = 25), "finesine[0] equals independent pinned value 25")
  Check(Bool(TrigSineChecked(1028, @sine) <> 0), "finesine index1028 readable")
  expected = PeekL(*gGoldSineIndex1028)
  Check(Bool(sine = expected), "finesine[1028] equals generator value")
  Check(Bool(TrigSineChecked(2048, @sine) <> 0), "finesine index2048 readable")
  expected = PeekL(*gGoldSineIndex2048)
  Check(Bool(sine = expected And sine = 65535), "finesine[2048] equals pinned 65535")
  Check(Bool(TrigSineChecked(3073, @sine) <> 0), "finesine index3073 readable")
  expected = PeekL(*gGoldSineIndex3073)
  Check(Bool(sine = expected), "finesine[3073] equals generator value 46287")
  Check(Bool(TrigTangentChecked(0, @tangent) <> 0), "finetangent index0 readable")
  Check(Bool(tangent = PeekL(*gGoldTangentIndex0) And tangent = -170910304),
        "finetangent[0] equals pinned -170910304")
  Check(Bool(TrigTangentChecked(3072, @tangent) <> 0), "focal tangent index3072 readable")
  Check(Bool(tangent = PeekL(*gGoldTangentIndex3072)), "finetangent[3072] equals generator value")
  Check(Bool(WallSignedSineIndexChecked($60080000, @signedIndex, @signedSine) <> 0),
        "signed fine index for raw $60080000 succeeds")
  Check(Bool(signedIndex = 3073 And signedSine = 46287),
        "$60080000 signed index/low value match generator")
  Check(Bool(WallSignedSineIndexChecked($20200000, @signedIndex, @signedSine) <> 0),
        "signed fine index for right-edge raw $20200000 succeeds")
  Check(Bool(signedIndex = 1028 And signedSine = 46500),
        "$20200000 signed index/low value match generator")
  Check(Bool(WallSignedSineIndexChecked($80000000, @signedIndex, @signedSine) = 0),
        "raw $80000000 negative C-int domain is rejected, never masked")
  Check(Bool(TrigSineChecked(-1, @sine) = 0 And TrigTangentChecked(4096, @tangent) = 0),
        "table bounds reject negative and excess indexes")
EndProcedure

Procedure TestWP18()
  BeginCase("WP18", "viewangle+xtoviewangle[0] leftmost BAM wrapping")
  Protected projection.Projection
  Protected inverse.q = 0
  Protected clip.q = 0
  Protected visNoHeading.q = 0
  Protected visAng45.q = 0
  Protected expectedQ.q

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "classic projection initializes")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 0, @inverse) <> 0), "leftmost inverse angle reads")
  Check(Bool(inverse = $20080000), "xtoviewangle[0] raw is the pinned clipangle $20080000")
  Check(Bool(inverse = PeekQ(*gGoldClipAngle)), "leftmost inverse equals projection fixture clipangle")
  Check(Bool(ProjectionGetClipAngle(@projection, @clip) <> 0), "clipangle accessor reads")
  Check(Bool(clip = inverse), "clipangle equals xtoviewangle[0] without off-by-one")
  visNoHeading = BamAdd(0, inverse)
  Check(Bool(visNoHeading = $20080000), "viewangle raw0 + left inverse has no shift")
  visAng45 = BamAdd(#BAM_ANG45, inverse)
  expectedQ = BamAdd(#BAM_ANG45, $20080000)
  Check(Bool(visAng45 = expectedQ), "ANG45 heading + left inverse uses unsigned BamAdd exactly")
  Check(Bool(visAng45 = $40080000), "measured ANG45+$20080000 raw = $40080000")
  ProjectionReset(@projection)
EndProcedure

Procedure TestWP19()
  BeginCase("WP19", "Rightmost x=319 inverse lookup and unsigned add")
  Protected projection.Projection
  Protected inverse.q = 0
  Protected vis.q = 0
  Protected expectedQ.q

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection initializes for right edge")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 319, @inverse) <> 0),
        "inverse x=319 succeeds, no off-by-one")
  Check(Bool(inverse = $E0200000), "xtoviewangle[319] raw = pinned right-edge $E0200000")
  vis = BamAdd(0, inverse)
  Check(Bool(vis = $E0200000), "heading0 + right inverse keeps right-edge raw")
  vis = BamAdd(#BAM_ANG45, inverse)
  expectedQ = BamAdd(#BAM_ANG45, $E0200000)
  Check(Bool(vis = expectedQ), "ANG45 + right inverse unsigned wrap equals explicit BamAdd")
  Check(Bool(vis = $00200000), "measured wrapped right edge $00200000")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 320, @inverse) <> 0),
        "inverse fencepost 320 remains legally readable")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 321, @inverse) = 0),
        "inverse index321 is rejected outside 0..320")
  ProjectionReset(@projection)
EndProcedure

Procedure TestWP20()
  BeginCase("WP20", "Tilted full-span [0,319] start/end scale and step golden record")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected goldScale1.l = 0
  Protected goldScale2.l = 0
  Protected goldStep.l = 0
  Protected planOk.i

  If TestPrepareScene("T", @map, @view, @projection, @visibility) = #False
    Check(#False, "tilted scene T prepares")
    ProcedureReturn
  EndIf
  Check(Bool(TestCompareSpansGold("T", @visibility) <> 0),
        "scene T span is the golden inclusive [0,319]")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "scene T span readable")
  Check(Bool(span\FirstX = 0 And span\LastX = 319), "measured full-span endpoints are exactly 0/319")
  planOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(planOk <> 0), "scene T full-span plan projection succeeds")
  Check(Bool(GoldPlanLGet("T", 0, 11, @goldScale1) <> 0 And
             GoldPlanLGet("T", 0, 12, @goldScale2) <> 0 And
             GoldPlanLGet("T", 0, 13, @goldStep) <> 0), "golden T scale fields read")
  Check(Bool(goldScale1 = 46072 And goldScale2 = 232066 And goldStep = 583),
        "independent golden T values are 46072/232066/583")
  Check(Bool(plan\Scale1 = goldScale1 And plan\Scale2 = goldScale2 And
             plan\ScaleStep = goldStep), "production full-span scale record equals oracle")
  Check(Bool(plan\ScaleStep <> 0), "tilted long span exercises non-zero scale stepping")
  Check(Bool(TestComparePlanGold("T", 0, @plan) <> 0), "all scene T plan fields match oracle")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP21()
  BeginCase("WP21", "Single-column [x,x]: scale1==scale2 and step=0")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected goldScale1.l = 0
  Protected goldScale2.l = 0
  Protected goldStep.l = 0
  Protected planOk.i

  If TestPrepareScene("A", @map, @view, @projection, @visibility) = #False
    Check(#False, "one-column scene A prepares")
    ProcedureReturn
  EndIf
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "scene A span readable")
  Check(Bool(span\FirstX = 1 And span\LastX = 1), "measured one-column inclusive endpoint is [1,1]")
  planOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(planOk <> 0), "single-column plan projection succeeds")
  Check(Bool(GoldPlanLGet("A", 0, 11, @goldScale1) <> 0 And
             GoldPlanLGet("A", 0, 12, @goldScale2) <> 0 And
             GoldPlanLGet("A", 0, 13, @goldStep) <> 0), "golden A scale fields read")
  Check(Bool(goldScale1 = 104295 And goldScale2 = 104295 And goldStep = 0),
        "independent single-column golden scale equals and step zero")
  Check(Bool(plan\Scale1 = goldScale1 And plan\Scale2 = plan\Scale1 And
             plan\ScaleStep = 0), "production single-column policy scale2=scale1/step0")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP22()
  BeginCase("WP22", "Two-column span C division truncation in signed scaleStep")
  Protected finalScale2.l = -1
  Protected stepValue.l = -1
  Protected finalScale2b.l = -1
  Protected stepb.l = -1

  Check(Bool(WallScaleStepChecked(0, 2, 1000, 1003, @finalScale2, @stepValue) <> 0),
        "positive difference/span succeeds")
  Check(Bool(stepValue = 1), "3/2 truncates toward zero to 1")
  Check(Bool(finalScale2 = 1003), "long span publishes input scale2 unchanged")
  Check(Bool(WallScaleStepChecked(0, 2, 1003, 1000, @finalScale2b, @stepb) <> 0),
        "negative difference/span succeeds")
  Check(Bool(stepb = -1), "-3/2 truncates toward zero to -1 (not floor -2)")
  Check(Bool(WallScaleStepChecked(0, 2, 1000, 1001, @finalScale2, @stepValue) <> 0),
        "one-unit positive difference succeeds")
  Check(Bool(stepValue = 0), "1/2 truncates toward zero to zero")
  Check(Bool(WallScaleStepChecked(0, 2, 1001, 1000, @finalScale2b, @stepb) <> 0),
        "one-unit negative difference succeeds")
  Check(Bool(stepb = 0), "-1/2 truncates toward zero to zero")
  Check(Bool(WallScaleStepChecked(5, 5, 1000, 2000, @finalScale2, @stepValue) <> 0),
        "single-column scale-step succeeds")
  Check(Bool(finalScale2 = 1000 And stepValue = 0), "equal endpoints force scale2=scale1 and step0")
  Check(Bool(WallScaleStepChecked(6, 5, 1000, 1001, @finalScale2, @stepValue) = 0),
        "inverted span columns rejected")
EndProcedure

Procedure TestWP23()
  BeginCase("WP23", "Long-span fixed-step accumulation equals independent column oracle")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected hash.q = 0
  Protected expectedHash.q
  Protected sampleX.l = 0
  Protected sampleIndex.l = 0
  Protected i.i
  Protected renderOk.i
  Protected columns.l = 0
  Protected drawn.l = 0
  Protected goldResultOk.i = #False

  If TestPrepareScene("T", @map, @view, @projection, @visibility) = #False
    Check(#False, "scene T prepares for accumulation oracle")
    ProcedureReturn
  EndIf
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "scene T full frame renders transactionally")
  Check(Bool(WallRenderGetStats(@result, 0, 0, 0, @columns, @drawn,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, @hash, 0) <> 0),
        "result counters/hash readable")
  expectedHash = GoldSceneHash("T")
  Check(Bool(hash = expectedHash), "frame hash equals independent Python full-column oracle")
  Check(Bool(hash <> 0), "frame hash is not a default/unmeasured value")
  Check(Bool(columns = 320), "all 320 columns processed across the full span")
  Check(Bool(drawn > 0), "fixed-step accumulation produced nonzero wall pixels")
  For i = 0 To #WALLGOLD_T_SampleCount - 1
    If GoldSampleXGet("T", i, @sampleX) = #False
      Check(#False, "golden sample column X is readable")
      continue
    EndIf
    If GoldSampleIndexForColumn("T", sampleX, @sampleIndex) = #False
      Check(#False, "golden sample index resolves")
      continue
    EndIf
    goldResultOk = TestCompareGoldSampleColumn("T", sampleX, @target)
    Check(Bool(goldResultOk <> 0),
          "long-span column " + Str(sampleX) + " all 200 palette rows equal independent oracle")
  Next
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP24()
  BeginCase("WP24", "Ceiling edge formula: topfrac 12-bit ceil rounding positive")
  Protected y.l = 0

  Check(Bool(WallTopEdgeFromFrac(0) = 0), "topfrac0 +4095 >>12 yields row0")
  Check(Bool(WallTopEdgeFromFrac(1) = 1), "topfrac1 +4095 =4096 >>12 yields row1")
  Check(Bool(WallTopEdgeFromFrac(4095) = 1), "topfrac4095 +4095=8190 >>12 yields row1")
  Check(Bool(WallTopEdgeFromFrac(4096) = 1), "exact unit boundary topfrac4096 yields row1")
  Check(Bool(WallTopEdgeFromFrac(8191) = 2), "8191+4095=12286 arithmetic >>12 = row2")
  y = WallTopEdgeFromFrac(65536)
  Check(Bool(y = 16), "topfrac65536 +4095 =69631 >>12 floors to exact row16")
EndProcedure

Procedure TestWP25()
  BeginCase("WP25", "Ceiling edge negative values and arithmetic right shift")
  Protected negativeTop.l = -1

  Check(Bool(WallTopEdgeFromFrac(-1) = 0), "-1+4095=4094 >>12 =0 (ceil toward row)")
  Check(Bool(WallTopEdgeFromFrac(-4096) = -1), "-4096+4095=-1 arithmetic >>12 = -1")
  Check(Bool(WallTopEdgeFromFrac(-4097) = -1), "-4097+4095=-2 >>12 floors to -1")
  Check(Bool(WallTopEdgeFromFrac(-65537) = -16), "-65537+4095=-61442 >>12 arithmetic floor -16")
  Check(Bool(WallBottomEdgeFromFrac(-1) = -1), "bottomfrac -1 arithmetic >>12 = -1")
  Check(Bool(WallBottomEdgeFromFrac(-4096) = -1), "bottomfrac exact -1 unit >>12 = -1")
  Check(Bool(WallBottomEdgeFromFrac(-4097) = -2), "bottomfrac -4097 >>12 floors to -2")
  negativeTop = WallBottomEdgeFromFrac(-65537)
  Check(Bool(negativeTop = -17), "bottomfrac -65537 >>12 arithmetic floor = -17")
EndProcedure

Procedure TestWP26()
  BeginCase("WP26", "Floor edge: bottomfrac 12-bit floor rounding")
  Protected positiveEdge.l
  Protected zeroEdge.l
  Protected f.l

  Check(Bool(WallBottomEdgeFromFrac(0) = 0), "bottomfrac0 >>12 yields row0 exactly")
  Check(Bool(WallBottomEdgeFromFrac(1) = 0), "bottomfrac1 >>12 floors to row0")
  Check(Bool(WallBottomEdgeFromFrac(4095) = 0), "unit-minus-one floors to row0")
  Check(Bool(WallBottomEdgeFromFrac(4096) = 1), "bottomfrac4096 yields row1 exactly")
  Check(Bool(WallBottomEdgeFromFrac(8191) = 1), "8191 arithmetic >>12 = row1")
  positiveEdge = WallBottomEdgeFromFrac(65536)
  Check(Bool(positiveEdge = 16), "bottomfrac65536 >>12 =16")
  zeroEdge = WallTopEdgeFromFrac(8191)
  f = WallBottomEdgeFromFrac(8191)
  Check(Bool(zeroEdge = 2 And f = 1 And zeroEdge <> f),
        "top ceil 8191+4095=12286>>12=row2; bottom floor 8191>>12=row1 differs across unit boundary")
EndProcedure

Procedure TestWP27()
  BeginCase("WP27", "Exactly equal edge/tie and zero-height face handling")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected plan.WallSpanPlan
  Protected pixelCount.l = -1
  Protected outcome.i
  Protected drawOk.i
  Protected middlePixelCount.l = 0
  Protected rowValue.i = 0

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip begin for tie test")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "manual ready-plan reset succeeds")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "draw tally resets")
  ; Zero-height one-sided middle: equal topfrac/bottomfrac 4096 produce yl=yh=1.
  plan\FirstX = 160
  plan\LastX = 160
  plan\Kind = #WALL_KIND_SOLID
  plan\Scale1 = #FRACUNIT
  plan\Scale2 = #FRACUNIT
  plan\ScaleStep = 0
  plan\TopFrac = 4096
  plan\BottomFrac = 4096
  plan\TopStep = 0
  plan\BottomStep = 0
  plan\MiddleTier = 1
  plan\MarkFloor = 1
  plan\MarkCeiling = 1
  plan\Ready = 1
  outcome = WallDrawSolidColumn(@frame, 160, 1, 1, #WALLDRAW_MiddleIndex, @pixelCount)
  Check(Bool(outcome = #WALLDRAW_RangeDrawn), "equal edges direct inclusive range draws")
  Check(Bool(pixelCount = 1), "exactly equal yl/yh draws count+1 = one pixel")
  drawOk = WallDrawSpan(@frame, @plan, @clip, @tally)
  Check(Bool(drawOk <> 0), "zero-height one-sided middle plan draws")
  middlePixelCount = tally\MiddlePixels
  Check(Bool(middlePixelCount = 1), "zero-height wall draws exactly one inclusive middle pixel")
  rowValue = FrameBufferGetPixel(@frame, 160, 1)
  Check(Bool(rowValue = #WALLDRAW_MiddleIndex), "drawn zero-height pixel row y=1 has middle color")
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
EndProcedure

Procedure TestWP28()
  BeginCase("WP28", "Height near INT32 limits, explicit signed-overflow wrap policy")
  Protected max.l = #FIXED_MAX
  Protected min.l = #FIXED_MIN

  Check(Bool(WallFixedAddLow(max, 1) = min),
        "MAX+1 widened then low32 wrap is documented MIN value")
  Check(Bool(WallFixedSubLow(min, 1) = max),
        "MIN-1 widened then low32 wrap is documented MAX value")
  Check(Bool(WallFixedNegateLow(min) = min),
        "C unary-minus INT32_MIN edge is explicit low32 wrap, not UB")
  Check(Bool(WallFixedAddLow(-2, 2) = 0), "ordinary near-limit addition remains exact")
  Check(Bool(WallFixedSubLow(max, max) = 0), "ordinary max-max subtraction remains exact")
  Check(Bool(WallFixedNegateLow(-2147483647) = 2147483647), "ordinary negation remains exact")
  Check(Bool(WallFixedAddLow(max, max) = -2), "wide 4294967294 low32 signed = -2")
  Check(Bool(WallFixedSubLow(min, max) = 1), "wide -4294967295 low32 signed = 1")
EndProcedure

Procedure TestWP29()
  BeginCase("WP29", "ceilingclip=-1 floorclip=200 initialization on each frame")
  Protected clip.WallVerticalClip
  Protected ceilValue.l = 0
  Protected floorValue.l = 0
  Protected column.i
  Protected mismatch.i = 0

  Check(Bool(WallVerticalClipReset(@clip) <> 0), "zero-init clip arrays reset")
  Check(Bool(WallVerticalClipBegin(@clip) <> 0), "first per-frame clip begin succeeds")
  For column = 0 To 319
    If WallVerticalClipGet(@clip, column, @ceilValue, @floorValue) = #False Or
       ceilValue <> -1 Or floorValue <> #WALLDRAW_ViewHeight
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0),
        "all 320 columns initialized to exact ceilingclip=-1 and floorclip=200")
  Check(Bool(PeekL(clip\Ceiling) = -1 And PeekL(clip\Floor) = 200),
        "column0 raw array bytes confirm -1/200")
  Check(Bool(PeekL(clip\Ceiling + 319 * 4) = -1 And PeekL(clip\Floor + 319 * 4) = 200),
        "column319 raw array bytes confirm -1/200")
  PokeL(clip\Ceiling + 160 * 4, 5)
  PokeL(clip\Floor + 160 * 4, 170)
  WallVerticalClipBegin(@clip)
  mismatch = 0
  For column = 0 To 319
    If WallVerticalClipGet(@clip, column, @ceilValue, @floorValue) = #False Or
       ceilValue <> -1 Or floorValue <> 200
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0),
        "repeated frame Begin deterministically reinitializes every column sentinel")
  WallVerticalClipReset(@clip)
EndProcedure

; ---------------------------------------------------------------------------
; WP30 - WP41: solid-tier drawing, portals/closed doors, sky and texture slots
; ---------------------------------------------------------------------------

Procedure TestWP30()
  BeginCase("WP30", "One-sided middle wall writes inclusive vertical pixels")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected plan.WallSpanPlan
  Protected drawOk.i
  Protected row.i
  Protected value.i

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip initialized for inclusive wall")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "draw tally reset")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "one-sided middle plan reset")
  plan\FirstX = 120
  plan\LastX = 120
  plan\Kind = #WALL_KIND_SOLID
  plan\Scale1 = #FRACUNIT
  plan\Scale2 = #FRACUNIT
  plan\ScaleStep = 0
  plan\TopFrac = 4096
  plan\BottomFrac = 65536
  plan\TopStep = 0
  plan\BottomStep = 0
  plan\MiddleTier = 1
  plan\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan, @clip, @tally)
  Check(Bool(drawOk <> 0), "wall draw succeeds for valid one-sided middle")
  Check(Bool(tally\MiddlePixels = 16), "inclusive yl=1, yh=16 writes exactly 16+1-1 pixels")
  Check(Bool(tally\MiddleRanges = 1), "one inclusive middle range was written")
  Check(Bool(tally\DrawnPixels = 16), "drawn total equals middle pixels only")
  value = FrameBufferGetPixel(@frame, 120, 1)
  Check(Bool(value = #WALLDRAW_MiddleIndex), "upper-inclusive first row y=1 is middle color")
  value = FrameBufferGetPixel(@frame, 120, 16)
  Check(Bool(value = #WALLDRAW_MiddleIndex), "lower-inclusive last row y=16 is middle color")
  value = FrameBufferGetPixel(@frame, 120, 0)
  Check(Bool(value = #WALLDRAW_BackgroundIndex), "row y=0 just above yl stays background")
  value = FrameBufferGetPixel(@frame, 120, 17)
  Check(Bool(value = #WALLDRAW_BackgroundIndex), "row y=17 just below inclusive yh stays background")
  For row = 1 To 16
    value = FrameBufferGetPixel(@frame, 120, row)
    If value <> #WALLDRAW_MiddleIndex
      Check(#False, "middle row " + Str(row) + " not the expected middle color")
    EndIf
  Next
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  WallDrawTallyReset(@tally)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP31()
  BeginCase("WP31", "One-sided wall closes column clip after drawing")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected plan1.WallSpanPlan
  Protected plan2.WallSpanPlan
  Protected drawOk.i
  Protected hashBefore.q
  Protected hashAfter.q
  Protected clipCeil.l
  Protected clipFloor.l

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip initialized for close semantics")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "tally reset before near wall")
  Check(Bool(WallSpanPlanReset(@plan1) <> 0), "near wall plan reset")
  plan1\FirstX = 140
  plan1\LastX = 140
  plan1\Kind = #WALL_KIND_SOLID
  plan1\Scale1 = #FRACUNIT
  plan1\Scale2 = #FRACUNIT
  plan1\ScaleStep = 0
  plan1\TopFrac = 4096
  plan1\BottomFrac = 40960
  plan1\TopStep = 0
  plan1\BottomStep = 0
  plan1\MiddleTier = 1
  plan1\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan1, @clip, @tally)
  Check(Bool(drawOk <> 0), "near one-sided wall draws successfully")
  Check(Bool(tally\MiddlePixels = 10), "near wall inclusive rows 1..10 writes ten pixels")
  Check(Bool(WallVerticalClipGet(@clip, 140, @clipCeil, @clipFloor) <> 0),
        "near column clip values readable")
  Check(Bool(clipCeil = #WALLDRAW_ViewHeight And clipFloor = -1),
        "one-sided middle closes column to ceilingclip=200/floorclip=-1")
  Check(Bool(WallFrameHash64(@frame, @hashBefore) <> 0), "frame hash captured before behind-wall attempt")
  Check(Bool(WallSpanPlanReset(@plan2) <> 0), "behind wall plan reset")
  plan2\FirstX = 140
  plan2\LastX = 140
  plan2\Kind = #WALL_KIND_SOLID
  plan2\Scale1 = #FRACUNIT
  plan2\Scale2 = #FRACUNIT
  plan2\ScaleStep = 0
  plan2\TopFrac = 4096
  plan2\BottomFrac = 40960
  plan2\TopStep = 0
  plan2\BottomStep = 0
  plan2\MiddleTier = 1
  plan2\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan2, @clip, @tally)
  Check(Bool(drawOk <> 0), "second draw after closed clip safely succeeds as an empty range")
  Check(Bool(tally\MiddlePixels = 10), "closed clip prevents any second middle pixel")
  Check(Bool(tally\DrawnPixels = 10), "drawn total remains ten after closed-clip attempt")
  Check(Bool(tally\EmptyColumns = 1), "closed-clip second column is counted as empty")
  Check(Bool(tally\ProcessedColumns = 2), "both requested columns were processed, none silently skipped")
  Check(Bool(WallFrameHash64(@frame, @hashAfter) <> 0), "frame hash after closed-clip attempt")
  Check(Bool(hashAfter = hashBefore), "closed clip left the frame byte-for-byte unchanged")
  Check(Bool(PeekL(clip\Ceiling + 140 * SizeOf(Long)) = 200 And
             PeekL(clip\Floor + 140 * SizeOf(Long)) = -1),
        "raw clip bytes still exactly ceilingclip=200/floorclip=-1")
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  WallDrawTallyReset(@tally)
  WallSpanPlanReset(@plan1)
  WallSpanPlanReset(@plan2)
EndProcedure

Procedure TestWP32()
  BeginCase("WP32", "Two-sided portal with equal heights leaves center empty")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected row.i
  Protected mismatch.i = 0
  Protected pixel.i
  Protected hash.q

  TestSceneParamsBase(@params)
  params\BackFloor = 0
  params\BackCeiling = 96
  params\FrontCeiling = 96
  params\BackFloorName = "FLOOR1"
  params\BackCeilingName = "CEIL1"
  params\BackLight = 160
  params\TopWallName = "-"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "equal-height two-sided portal prepares")
  Check(Bool(WallVisibilityCount(@visibility) = 0),
        "equal heights/flats/light with absent selected middle classify SKIP and emit no span")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) = 0),
        "no portal span slot exists for the source SKIP classification")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #False)
  Check(Bool(renderOk <> 0), "zero-span SKIP portal frame renders legally empty without failure")
  Check(Bool(WallRenderResultIsValid(@result) <> 0), "SKIP portal render result is valid")
  Check(Bool(result\SpanCount = 0 And result\DrawnPixels = 0 And
             result\MiddlePixels = 0 And result\UpperPixels = 0 And
             result\LowerPixels = 0),
        "SKIP portal frame publishes zero spans/tiers, never a full-screen occlusion")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel <> #WALLDRAW_BackgroundIndex
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "all 200 rows at portal column 160 remain background")
  Check(Bool(WallFrameHash64(@target, @hash) <> 0 And hash = TestFnvUniformReference(0)),
        "portal frame hash equals independently reconstructed background plane")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP33()
  BeginCase("WP33", "Two-sided upper wall when back ceiling is lower")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected row.i
  Protected upperCount.l = 0
  Protected middleCount.l = 0
  Protected lowerCount.l = 0
  Protected backgroundCount.l = 0
  Protected pixel.i

  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\BackFloor = 0
  params\BackCeiling = 64
  params\TopWallName = "WALL1"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "lower-back-ceiling portal prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "upper-tier span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "upper-tier span projection succeeds")
  Check(Bool(plan\TopRegion = 1), "back ceiling below front ceiling selects top region")
  Check(Bool(plan\BottomRegion = 0), "equal floors suppress bottom region")
  Check(Bool(plan\TopTexturePresent = 1), "canonical nonempty WALL1 top slot is present in fallback")
  Check(Bool(plan\TopTier = 1 And plan\BottomTier = 0 And plan\MiddleTier = 0),
        "only upper debug tier is selected for this portal")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "upper-tier portal frame draws nonzero wall pixels")
  Check(Bool(result\UpperPixels > 0), "upper tier painted concrete pixels")
  Check(Bool(result\MiddlePixels = 0 And result\LowerPixels = 0),
        "no invented middle/lower pixels for a top-only portal")
  Check(Bool(result\DrawnPixels = result\UpperPixels), "drawn total equals upper tier count")
  Check(Bool(span\FirstX <= 160 And span\LastX >= 160), "sample column 160 lies inside the visible span")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel = #WALLDRAW_UpperIndex
      upperCount + 1
    ElseIf pixel = #WALLDRAW_MiddleIndex
      middleCount + 1
    ElseIf pixel = #WALLDRAW_LowerIndex
      lowerCount + 1
    Else
      backgroundCount + 1
    EndIf
  Next
  Check(Bool(upperCount > 0), "sample column paints actual upper palette pixels")
  Check(Bool(middleCount = 0 And lowerCount = 0), "sample column has no forbidden middle/lower colors")
  Check(Bool(backgroundCount > 0), "sample column retains non-wall background above/below the top tier")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP34()
  BeginCase("WP34", "Two-sided lower wall when back floor is higher")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected row.i
  Protected upperCount.l = 0
  Protected middleCount.l = 0
  Protected lowerCount.l = 0
  Protected backgroundCount.l = 0
  Protected pixel.i

  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\BackFloor = 32
  params\BackCeiling = 96
  params\TopWallName = "-"
  params\BottomWallName = "WALL1"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "higher-back-floor portal prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "lower-tier span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "lower-tier span projection succeeds")
  Check(Bool(plan\BottomRegion = 1), "back floor above front floor selects bottom region")
  Check(Bool(plan\TopRegion = 0), "equal ceilings suppress top region")
  Check(Bool(plan\BottomTexturePresent = 1), "canonical nonempty WALL1 bottom slot present")
  Check(Bool(plan\BottomTier = 1 And plan\TopTier = 0 And plan\MiddleTier = 0),
        "only lower debug tier is selected for this portal")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "lower-tier portal frame draws nonzero wall pixels")
  Check(Bool(result\LowerPixels > 0), "lower tier painted concrete pixels")
  Check(Bool(result\MiddlePixels = 0 And result\UpperPixels = 0),
        "no invented middle/upper pixels for a bottom-only portal")
  Check(Bool(result\DrawnPixels = result\LowerPixels), "drawn total equals lower tier count")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel = #WALLDRAW_UpperIndex
      upperCount + 1
    ElseIf pixel = #WALLDRAW_MiddleIndex
      middleCount + 1
    ElseIf pixel = #WALLDRAW_LowerIndex
      lowerCount + 1
    Else
      backgroundCount + 1
    EndIf
  Next
  Check(Bool(lowerCount > 0), "sample column paints actual lower palette pixels")
  Check(Bool(upperCount = 0 And middleCount = 0), "sample column has no forbidden upper/middle colors")
  Check(Bool(backgroundCount > 0), "sample column retains background above the lower tier")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP35()
  BeginCase("WP35", "Both upper and lower tiers in one column; opening stays background")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected column.l = 160
  Protected delta.l
  Protected scaleCurrent.l
  Protected topFracCurrent.l
  Protected bottomFracCurrent.l
  Protected pixHighCurrent.l
  Protected pixLowCurrent.l
  Protected yl.l
  Protected yh.l
  Protected midUp.l
  Protected midLow.l
  Protected ceilingAfter.l
  Protected upperStart.l
  Protected upperEnd.l
  Protected lowerStart.l
  Protected lowerEnd.l
  Protected gapCount.l = 0
  Protected mismatch.i = 0
  Protected row.i
  Protected pixel.i

  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\BackFloor = 32
  params\BackCeiling = 64
  params\TopWallName = "WALL1"
  params\BottomWallName = "WALL1"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "upper+lower portal prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "both-tier span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "both-tier span projection succeeds")
  Check(Bool(plan\TopRegion = 1 And plan\BottomRegion = 1),
        "back ceiling lower and back floor higher select both regions")
  Check(Bool(plan\TopTier = 1 And plan\BottomTier = 1 And plan\MiddleTier = 0),
        "both upper and lower wall tiers are selected, middle omitted")
  Check(Bool(span\FirstX <= column And span\LastX >= column), "sample column lies inside span")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "both-tier frame renders nonzero wall pixels")
  Check(Bool(result\UpperPixels > 0 And result\LowerPixels > 0),
        "both upper and lower tiers painted concrete pixels")
  Check(Bool(result\MiddlePixels = 0), "no middle pixels for absent two-sided middle slot")

  ; Independent per-column fixed accumulation and inclusive edge classification.
  delta = column - plan\FirstX
  scaleCurrent = WallFixedAddLow(plan\Scale1, FixedWrap32Low(Int(plan\ScaleStep) * Int(delta)))
  topFracCurrent = WallFixedAddLow(plan\TopFrac, FixedWrap32Low(Int(plan\TopStep) * Int(delta)))
  bottomFracCurrent = WallFixedAddLow(plan\BottomFrac,
                                      FixedWrap32Low(Int(plan\BottomStep) * Int(delta)))
  pixHighCurrent = WallFixedAddLow(plan\PixHigh,
                                   FixedWrap32Low(Int(plan\PixHighStep) * Int(delta)))
  pixLowCurrent = WallFixedAddLow(plan\PixLow,
                                  FixedWrap32Low(Int(plan\PixLowStep) * Int(delta)))
  yl = WallTopEdgeFromFrac(topFracCurrent)
  yh = WallBottomEdgeFromFrac(bottomFracCurrent)
  midUp = WallPixHighToY(pixHighCurrent)
  midLow = WallPixLowToY(pixLowCurrent)
  If yl < 0
    yl = 0
  EndIf
  If yh >= #WALLDRAW_ViewHeight
    yh = #WALLDRAW_ViewHeight - 1
  EndIf
  If midUp >= #WALLDRAW_ViewHeight
    midUp = #WALLDRAW_ViewHeight - 1
  EndIf
  If midUp >= yl And midUp < yh + 1
    upperStart = yl
    upperEnd = midUp
    ceilingAfter = midUp
  Else
    upperStart = 0
    upperEnd = -1
    ceilingAfter = yl - 1
  EndIf
  lowerStart = midLow
  If lowerStart <= ceilingAfter
    lowerStart = ceilingAfter + 1
  EndIf
  lowerEnd = yh
  If lowerEnd > #WALLDRAW_ViewHeight - 1
    lowerEnd = #WALLDRAW_ViewHeight - 1
  EndIf
  If midUp < yh + 1 And midLow > midUp
    gapCount = midLow - midUp - 1
  EndIf

  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, column, row)
    If row >= upperStart And row <= upperEnd
      If pixel <> #WALLDRAW_UpperIndex
        mismatch + 1
      EndIf
    ElseIf row >= lowerStart And row <= lowerEnd
      If pixel <> #WALLDRAW_LowerIndex
        mismatch + 1
      EndIf
    ElseIf pixel <> #WALLDRAW_BackgroundIndex
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "per-column upper/lower/background rows follow explicit edge formula")
  Check(Bool(gapCount > 0), "explicit upper/lower row gap leaves visible background opening")
  Check(Bool(upperEnd >= upperStart), "upper interval nonempty in chosen synthetic portal")
  Check(Bool(lowerEnd >= lowerStart), "lower interval nonempty in chosen synthetic portal")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP36()
  BeginCase("WP36", "Closed door / backceiling<=frontfloor geometry")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected row.i
  Protected upperCount.l = 0
  Protected backgroundCount.l = 0
  Protected pixel.i

  TestSceneParamsBase(@params)
  params\FrontFloor = 32
  params\FrontCeiling = 96
  params\BackFloor = -16
  params\BackCeiling = 0
  params\TopWallName = "WALL1"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "raised-floor closed-door portal prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "closed-door span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "closed-door span projection succeeds")
  Check(Bool(plan\FrontFloorMap = 32 And plan\FrontCeilingMap = 96 And
             plan\BackFloorMap = -16 And plan\BackCeilingMap = 0),
        "plan records the explicit synthetic closed-door map heights")
  Check(Bool(plan\ClosedDoor = 1), "backceiling 0 <= frontfloor 32 triggers source closed-door flag")
  Check(Bool(plan\MarkFloor = 1 And plan\MarkCeiling = 1),
        "closed-door condition forces both plane marks despite equalities")
  Check(Bool(plan\TopRegion = 1 And plan\TopTier = 1 And plan\BottomTier = 0),
        "closed portal upper text region selected, lower absent")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "closed-door frame draws upper wall pixels")
  Check(Bool(result\UpperPixels > 0), "closed-door upper tier painted concrete pixels")
  Check(Bool(result\LowerPixels = 0 And result\MiddlePixels = 0),
        "closed-door frame draws no invented lower/middle pixels")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel = #WALLDRAW_UpperIndex
      upperCount + 1
    Else
      backgroundCount + 1
    EndIf
  Next
  Check(Bool(upperCount > 0 And backgroundCount > 0),
        "closed-door column paints upper wall and retains background outside it")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP37()
  BeginCase("WP37", "Opposite closed door / backfloor>=frontceiling geometry")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected row.i
  Protected lowerCount.l = 0
  Protected backgroundCount.l = 0
  Protected pixel.i

  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 64
  params\BackFloor = 64
  params\BackCeiling = 128
  params\TopWallName = "WALL1"
  params\BottomWallName = "WALL1"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "lowered-ceiling opposite closed-door portal prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "opposite closed-door span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "opposite closed-door span projection succeeds")
  Check(Bool(plan\BackFloorMap = 64 And plan\FrontCeilingMap = 64),
        "back floor equals front ceiling in the opposite closed-door arrangement")
  Check(Bool(plan\ClosedDoor = 1), "backfloor 64 >= frontceiling 64 triggers source closed-door flag")
  Check(Bool(plan\MarkFloor = 1 And plan\MarkCeiling = 1),
        "opposite closed-door condition forces both plane marks")
  Check(Bool(plan\TopRegion = 0 And plan\BottomRegion = 1 And plan\BottomTier = 1),
        "opposite geometry selects lower text region only")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "opposite closed-door frame draws lower wall pixels")
  Check(Bool(result\LowerPixels > 0), "opposite closed-door lower tier painted concrete pixels")
  Check(Bool(result\UpperPixels = 0 And result\MiddlePixels = 0),
        "opposite closed-door draws no invented upper/middle pixels")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel = #WALLDRAW_LowerIndex
      lowerCount + 1
    Else
      backgroundCount + 1
    EndIf
  Next
  Check(Bool(lowerCount > 0 And backgroundCount > 0),
        "opposite closed-door column paints lower wall and retains background")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP38()
  BeginCase("WP38", "Sky-to-sky worldtop=worldhigh boundary special case")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected hash.q
  Protected mismatch.i = 0
  Protected row.i
  Protected pixel.i

  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\FrontFloorName = "FLOOR1"
  params\FrontCeilingName = "F_SKY1"
  params\BackFloor = 32
  params\BackCeiling = 96
  params\BackFloorName = "FLOOR2"
  params\BackCeilingName = "F_SKY1"
  params\BackLight = 160
  params\TopWallName = "-"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "sky-to-sky portal with differing floors prepares")
  Check(Bool(WallVisibilityCount(@visibility) = 1),
        "differing back floor breaks SKIP and publishes one sky portal span")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "sky portal span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "sky-to-sky span projection succeeds")
  Check(Bool(plan\FrontSky = 1 And plan\BackSky = 1),
        "both canonical F_SKY1 ceiling slots resolve as sky in fallback")
  Check(Bool(plan\SkyHack = 1), "both-sky boundary hack is enabled only for back-sector geometry")
  Check(Bool(plan\WorldTopRaw = plan\WorldHighRaw),
        "source outdoor hack copies worldtop=worldhigh for equal sky ceilings")
  Check(Bool(plan\WorldTopRaw = 3604480),
        "both 96-unit F_SKY1 ceilings minus 41-unit viewz equal 3604480")
  Check(Bool(plan\TopRegion = 0 And plan\BottomRegion = 1),
        "equal sky ceilings collapse top region; differing back floor opens bottom region")
  Check(Bool(plan\TopTier = 0 And plan\BottomTier = 0 And plan\MiddleTier = 0),
        "absent '-' top/bottom slots still select no debug wall tier")
  Check(Bool(plan\MarkFloor = 1 And plan\MarkCeiling = 0),
        "differing floor height demands floor mark; equal sky ceiling suppresses ceiling mark")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #False)
  Check(Bool(renderOk <> 0), "sky boundary frame succeeds with no invented sky pixels")
  Check(Bool(result\DrawnPixels = 0), "M3-05 sky boundary path paints zero wall pixels")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel <> #WALLDRAW_BackgroundIndex
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "sky hack column remains background, no fabricated sky/flats")
  Check(Bool(WallFrameHash64(@target, @hash) <> 0 And hash = TestFnvUniformReference(0)),
        "sky boundary frame hash matches independent background fingerprint")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP39()
  BeginCase("WP39", "F_SKY1 one-sided/two-sided mismatch must not trigger sky hack")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected prepareOk.i
  Protected projectOk.i

  ; A. One-sided front sky has no back-sector and therefore no outdoor hack.
  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\FrontCeilingName = "F_SKY1"
  params\TopWallName = "-"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 0
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "one-sided F_SKY1 wall prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "one-sided sky span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "one-sided sky span projection succeeds")
  Check(Bool(plan\FrontSky = 1 And plan\BackSky = 0 And plan\SkyHack = 0),
        "one-sided F_SKY1 identifies front sky but cannot enable hack")
  Check(Bool(plan\WorldTopRaw = 3604480),
        "one-sided sky leaves worldtop as the original front-ceiling offset")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
  WallSpanPlanReset(@plan)

  ; B. Front sky + back non-sky two-sided portal must not copy worldtop=worldhigh.
  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\FrontCeilingName = "F_SKY1"
  params\BackFloor = 0
  params\BackCeiling = 96
  params\BackCeilingName = "CEIL2"
  params\TopWallName = "-"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "front-sky/back-nonsky portal prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "mismatched sky span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "front-sky mismatch span projection succeeds")
  Check(Bool(plan\FrontSky = 1 And plan\BackSky = 0 And plan\SkyHack = 0),
        "front-only F_SKY1 mismatch leaves SkyHack disabled")
  Check(Bool(plan\WorldTopRaw = 3604480 And plan\WorldHighRaw = 3604480),
        "mismatch does not perform the copy; equal heights justify equal offsets only")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
  WallSpanPlanReset(@plan)

  ; C. Front non-sky + lower back sky: front retains original worldtop.
  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 128
  params\FrontCeilingName = "CEIL1"
  params\BackFloor = 0
  params\BackCeiling = 96
  params\BackCeilingName = "F_SKY1"
  params\TopWallName = "WALL1"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 1
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "back-only sky portal prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "back-only sky span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "back-only sky span projection succeeds")
  Check(Bool(plan\FrontSky = 0 And plan\BackSky = 1 And plan\SkyHack = 0),
        "back-only F_SKY1 leaves hack disabled and front sky false")
  Check(Bool(plan\WorldTopRaw = 5701632 And plan\WorldHighRaw = 3604480),
        "back-only sky retains distinct front ceiling 5701632 and back ceiling 3604480")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP40()
  BeginCase("WP40", "Absent '-' wall texture slot yields no invented source pixels")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected secondProjectOk.i
  Protected secondRenderOk.i
  Protected hash.q
  Protected secondHash.q
  Protected mismatch.i = 0
  Protected row.i
  Protected pixel.i
  Protected nameMutated.i

  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\TopWallName = "-"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 0
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "one-sided absent-middle wall prepares")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "absent-middle span readable")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk <> 0), "absent-middle span projection succeeds")
  Check(Bool(plan\MiddleTexturePresent = 0 And plan\MiddleTier = 0),
        "canonical '-' middle slot resolves to NoTexture with no tier")
  Check(Bool(plan\TopTier = 0 And plan\BottomTier = 0),
        "one-sided source still forces absent top/bottom, no invented tiers")
  Check(Bool(WallProjectLastError() = ""), "successful absent slot leaves no stale diagnostic")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #False)
  Check(Bool(renderOk <> 0), "absent-middle wall frame succeeds as a legal empty frame")
  Check(Bool(result\DrawnPixels = 0 And result\MiddlePixels = 0),
        "absent middle slot paints zero pixels, never fabricated fill")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel <> #WALLDRAW_BackgroundIndex
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "all 200 rows at absent-middle column remain exact background")
  Check(Bool(WallFrameHash64(@target, @hash) <> 0 And hash = TestFnvUniformReference(0)),
        "absent-middle frame hash equals independent background fingerprint")

  nameMutated = TestFillSideNameRaw(@map, 0, 2, "")
  Check(Bool(nameMutated <> 0), "synthetic middle slot mutated to canonical all-NUL bytes")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "all-NUL absence plan reset")
  secondProjectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(secondProjectOk <> 0), "all-NUL middle slot projection succeeds")
  Check(Bool(plan\MiddleTexturePresent = 0 And plan\MiddleTier = 0),
        "all-NUL middle slot is equally canonical absent NoTexture")
  secondRenderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                                   @target, @result, #False)
  Check(Bool(secondRenderOk <> 0), "all-NUL absence frame succeeds")
  Check(Bool(result\DrawnPixels = 0), "all-NUL middle slot paints zero pixels")
  Check(Bool(WallFrameHash64(@target, @secondHash) <> 0 And
             secondHash = TestFnvUniformReference(0)),
        "repeated all-NUL build leaves the identical background fingerprint")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP41()
  BeginCase("WP41", "Catalog-resolved slots and NoTexture index0 sentinel handling")
  Protected params.TestSceneParams
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected catalog.TextureCatalog
  Protected Dim specs.TestTexSpec(1)
  Protected textureBytes.q
  Protected *textureLump.Byte
  Protected catalogOk.i
  Protected prepareOk.i
  Protected topPresent.l = -1
  Protected bottomPresent.l = -1
  Protected middlePresent.l = -1
  Protected bottomOk.i
  Protected middleOk.i
  Protected find1.i
  Protected find0.i
  Protected findMissing.i
  Protected mutateOk.i
  Protected failureOk.i
  Protected errorText.s
  Protected fallbackPresent.l = -1
  Protected fallbackOk.i

  specs(0)\Name = "SENT0"
  specs(0)\Width = 64
  specs(0)\Height = 128
  specs(0)\PNameIndex = 1
  specs(1)\Name = "WALL1"
  specs(1)\Width = 64
  specs(1)\Height = 128
  specs(1)\PNameIndex = 1
  *textureLump = MakeTexture1Lump(@specs(0), 2, @textureBytes)
  Check(Bool(*textureLump <> 0 And textureBytes > 0), "synthetic two-definition TEXTURE1 bytes built")
  catalogOk = TextureCatalogDecode(*textureLump, textureBytes, 0, 0, #False, @catalog)
  Check(Bool(catalogOk <> 0), "catalog decoder accepts the owned synthetic TEXTURE1")
  Check(Bool(TextureCatalogCount(@catalog) = 2), "catalog carries exactly two texture definitions")
  find1 = TextureCatalogFindName(@catalog, "WALL1")
  find0 = TextureCatalogFindName(@catalog, "SENT0")
  findMissing = TextureCatalogFindName(@catalog, "NOPE")
  Check(Bool(find1 = 1), "ordinary WALL1 resolves to numeric texture index 1")
  Check(Bool(find0 = 0), "SENT0 resolves to the original NoTexture index-0 sentinel slot")
  Check(Bool(findMissing = -1), "missing NOPE texture name reports -1 with explicit catalog error")
  FreeMemory(*textureLump)

  TestSceneParamsBase(@params)
  params\FrontFloor = 0
  params\FrontCeiling = 96
  params\TopWallName = "WALL1"
  params\BottomWallName = "-"
  params\MiddleWallName = "-"
  params\TwoSided = 0
  prepareOk = TestPrepareParamsScene(@params, @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "catalog-slot synthetic one-sided map prepares")

  Check(Bool(WallSideTexturePresentChecked(@map, @catalog, 0, 0, @topPresent) <> 0),
        "catalog-aware top slot check succeeds for WALL1")
  Check(Bool(topPresent = 1), "resolved index1 top slot is debug-present")
  Check(Bool(WallSideTexturePresentChecked(@map, @catalog, 0, 1, @bottomPresent) <> 0),
        "catalog-aware canonical '-' bottom slot check succeeds")
  Check(Bool(bottomPresent = 0), "canonical '-' slot is absent even in catalog-aware path")
  Check(Bool(WallSideTexturePresentChecked(@map, @catalog, 0, 2, @middlePresent) <> 0),
        "catalog-aware canonical '-' middle slot check succeeds")
  Check(Bool(middlePresent = 0), "canonical '-' middle slot is absent NoTexture")

  mutateOk = TestFillSideNameRaw(@map, 0, 2, "SENT0")
  Check(Bool(mutateOk <> 0), "middle slot mutated to resolving SENT0 name")
  middleOk = WallSideTexturePresentChecked(@map, @catalog, 0, 2, @middlePresent)
  Check(Bool(middleOk <> 0), "resolved numeric index0 middle slot check succeeds")
  Check(Bool(middlePresent = 0), "resolved texture index0 sentinel is treated as absent NoTexture")

  mutateOk = TestFillSideNameRaw(@map, 0, 0, "-")
  Check(Bool(mutateOk <> 0), "top slot mutated to canonical '-'")
  topPresent = -1
  Check(Bool(WallSideTexturePresentChecked(@map, @catalog, 0, 0, @topPresent) <> 0 And
             topPresent = 0), "canonical '-' top slot absent independent of catalog entries")

  mutateOk = TestFillSideNameRaw(@map, 0, 0, "NOPE")
  Check(Bool(mutateOk <> 0), "top slot mutated to catalog-missing NOPE")
  failureOk = Bool(WallSideTexturePresentChecked(@map, @catalog, 0, 0, @topPresent) = 0)
  errorText = WallProjectLastError()
  Check(Bool(failureOk <> 0), "catalog-aware missing noncanonical-safe name is an explicit failure")
  Check(Bool(FindString(errorText, "not found") > 0),
        "missing slot diagnostic names the unresolved catalog texture")

  mutateOk = Bool(TestPokeSideNameRawByte(@map, 0, 2, 0, Asc("W")) <> 0 And
                  TestPokeSideNameRawByte(@map, 0, 2, 1, Asc("A")) <> 0 And
                  TestPokeSideNameRawByte(@map, 0, 2, 2, 0) <> 0 And
                  TestPokeSideNameRawByte(@map, 0, 2, 3, Asc("X")) <> 0)
  Check(Bool(mutateOk <> 0), "middle slot bytes mutated to embedded-NUL malformed pattern")
  Check(Bool(WallSideTexturePresentChecked(@map, @catalog, 0, 2, @middlePresent) = 0),
        "catalog-aware embedded-NUL/trailing-byte slot rejects explicitly")
  errorText = WallProjectLastError()
  Check(Bool(FindString(errorText, "noncanonical") > 0),
        "malformed slot diagnostic names the noncanonical eight-byte pattern")
  fallbackOk = WallSideTexturePresentChecked(@map, 0, 0, 2, @fallbackPresent)
  Check(Bool(fallbackOk <> 0 And fallbackPresent = 1),
        "catalogless fallback treats noncanonical slot conservatively present")
  Check(Bool(WallProjectLastError() = ""), "fallback noncanonical conservative present leaves no stale error")

  TextureCatalogReset(@catalog)
  Check(Bool(TextureCatalogCount(@catalog) = 0),
        "synthetic catalog reset releases definitions and reuses zero-count state")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

; ---------------------------------------------------------------------------
; WP42 - WP56: byte clipping, bounded drawing, hashes, lifetimes, hot path,
;              and the full independent sample-column oracle
; ---------------------------------------------------------------------------

Procedure TestWP42()
  BeginCase("WP42", "Per-column clip prevents overwriting nearer upper pixels")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected nearPlan.WallSpanPlan
  Protected behindPlan.WallSpanPlan
  Protected drawOk.i
  Protected ceilValue.l = 0
  Protected floorValue.l = 0
  Protected row.i
  Protected pixel.i
  Protected mismatch.i = 0

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip initialized for overlap protection")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "tally reset")
  Check(Bool(WallSpanPlanReset(@nearPlan) <> 0), "near upper-tier plan reset")
  nearPlan\FirstX = 145
  nearPlan\LastX = 145
  nearPlan\Kind = #WALL_KIND_SOLID
  nearPlan\Scale1 = #FRACUNIT
  nearPlan\Scale2 = #FRACUNIT
  nearPlan\ScaleStep = 0
  nearPlan\TopFrac = 4096
  nearPlan\BottomFrac = 126976
  nearPlan\TopStep = 0
  nearPlan\BottomStep = 0
  nearPlan\PixHigh = 81920
  nearPlan\PixHighStep = 0
  nearPlan\TopTier = 1
  nearPlan\BottomTier = 0
  nearPlan\MiddleTier = 0
  nearPlan\MarkFloor = 1
  nearPlan\Ready = 1
  drawOk = TestDrawPlan(@frame, @nearPlan, @clip, @tally)
  Check(Bool(drawOk <> 0), "near upper tier draws rows 1..20 into fresh clip")
  Check(Bool(tally\UpperPixels = 20), "near upper wall writes exactly twenty inclusive pixels")
  Check(Bool(WallVerticalClipGet(@clip, 145, @ceilValue, @floorValue) <> 0),
        "column 145 clip readable after upper draw")
  Check(Bool(ceilValue = 20 And floorValue = 32),
        "upper draw stores ceilingclip=mid row20 and markfloor yh+1=32")
  pixel = FrameBufferGetPixel(@frame, 145, 20)
  Check(Bool(pixel = #WALLDRAW_UpperIndex), "near wall row 20 is genuine upper color before overlap")
  Check(Bool(WallSpanPlanReset(@behindPlan) <> 0), "behind middle wall plan reset")
  behindPlan\FirstX = 145
  behindPlan\LastX = 145
  behindPlan\Kind = #WALL_KIND_SOLID
  behindPlan\Scale1 = #FRACUNIT
  behindPlan\Scale2 = #FRACUNIT
  behindPlan\ScaleStep = 0
  behindPlan\TopFrac = 4096
  behindPlan\BottomFrac = 122880
  behindPlan\TopStep = 0
  behindPlan\BottomStep = 0
  behindPlan\MiddleTier = 1
  behindPlan\Ready = 1
  drawOk = TestDrawPlan(@frame, @behindPlan, @clip, @tally)
  Check(Bool(drawOk <> 0), "behind middle wall draws only the unoccluded lower interval")
  Check(Bool(tally\MiddlePixels = 10 And tally\UpperPixels = 20),
        "behind draw adds ten middle rows without re-counting near upper pixels")
  Check(Bool(tally\DrawnPixels = 30), "combined drawn total is exactly thirty but one pixel plane")
  pixel = FrameBufferGetPixel(@frame, 145, 20)
  Check(Bool(pixel = #WALLDRAW_UpperIndex), "row20 nearest upper pixel was not overwritten by behind wall")
  For row = 1 To 20
    pixel = FrameBufferGetPixel(@frame, 145, row)
    If pixel <> #WALLDRAW_UpperIndex
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "nearest rows 1..20 remain exclusively upper palette")
  mismatch = 0
  For row = 21 To 30
    pixel = FrameBufferGetPixel(@frame, 145, row)
    If pixel <> #WALLDRAW_MiddleIndex
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "only behind rows21..30 receive middle color below ceilingclip=20")
  pixel = FrameBufferGetPixel(@frame, 145, 31)
  Check(Bool(pixel = #WALLDRAW_BackgroundIndex), "row31 below behind yh remains background")
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  WallDrawTallyReset(@tally)
  WallSpanPlanReset(@nearPlan)
  WallSpanPlanReset(@behindPlan)
EndProcedure

Procedure TestWP43()
  BeginCase("WP43", "PASS type does not fill opening or solid-occlude full screen")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected plan.WallSpanPlan
  Protected drawOk.i
  Protected hash.q
  Protected row.i
  Protected pixel.i

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip initialized for full PASS")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "tally reset before full PASS")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "full-screen PASS plan reset")
  plan\FirstX = 0
  plan\LastX = 319
  plan\Kind = #WALL_KIND_PASS
  plan\Scale1 = #FRACUNIT
  plan\Scale2 = #FRACUNIT
  plan\ScaleStep = 0
  plan\TopFrac = 0
  plan\BottomFrac = 0
  plan\TopStep = 0
  plan\BottomStep = 0
  plan\MarkFloor = 1
  plan\MarkCeiling = 1
  plan\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan, @clip, @tally)
  Check(Bool(drawOk <> 0), "full-width PASS draws successfully without unsupported failure")
  Check(Bool(tally\ProcessedColumns = 320), "every PASS column was explicitly processed")
  Check(Bool(tally\DrawnPixels = 0 And tally\MiddlePixels = 0 And
             tally\UpperPixels = 0 And tally\LowerPixels = 0),
        "PASS type fills no portal pixels or tiers")
  Check(Bool(tally\DrawRanges = 0), "no solid byte ranges were recorded")
  Check(Bool(tally\EmptyColumns = 320), "all 320 PASS columns are counted empty")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@frame, 160, row)
    If pixel <> #WALLDRAW_BackgroundIndex
      Check(#False, "full PASS row " + Str(row) + " unexpectedly non-background")
    EndIf
  Next
  Check(Bool(WallFrameHash64(@frame, @hash) <> 0 And hash = TestFnvUniformReference(0)),
        "full PASS leaves exact independent background fingerprint, no full-screen occlusion")
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  WallDrawTallyReset(@tally)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP44()
  BeginCase("WP44", "firstX=0,lastX=319 and bottom row y=199 safely writable")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected plan.WallSpanPlan
  Protected drawOk.i
  Protected hash.q
  Protected expectedHash.q
  Protected bottomLeft.i
  Protected bottomCenter.i
  Protected bottomRight.i
  Protected topLeft.i

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip initialized for full solid width")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "tally reset")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "full-width middle plan reset")
  plan\FirstX = 0
  plan\LastX = 319
  plan\Kind = #WALL_KIND_SOLID
  plan\Scale1 = #FRACUNIT
  plan\Scale2 = #FRACUNIT
  plan\ScaleStep = 0
  plan\TopFrac = 0
  plan\BottomFrac = 815104
  plan\TopStep = 0
  plan\BottomStep = 0
  plan\MiddleTier = 1
  plan\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan, @clip, @tally)
  Check(Bool(drawOk <> 0), "full solid span x=0..319 draws without boundary failure")
  Check(Bool(tally\MiddlePixels = 64000), "full span inclusive rows0..199 writes all 64,000 pixels")
  Check(Bool(tally\MiddleRanges = 320), "each of the 320 columns records one inclusive middle range")
  Check(Bool(tally\DrawnPixels = 64000 And tally\EmptyColumns = 0 And
             tally\OutOfFrameColumns = 0),
        "complete plane painted with no empty or out-of-frame accounting")
  bottomLeft = FrameBufferGetPixel(@frame, 0, 199)
  bottomCenter = FrameBufferGetPixel(@frame, 160, 199)
  bottomRight = FrameBufferGetPixel(@frame, 319, 199)
  topLeft = FrameBufferGetPixel(@frame, 0, 0)
  Check(Bool(bottomLeft = #WALLDRAW_MiddleIndex), "bottom row y=199 at column0 writable")
  Check(Bool(bottomCenter = #WALLDRAW_MiddleIndex), "bottom row y=199 at center column writable")
  Check(Bool(bottomRight = #WALLDRAW_MiddleIndex), "bottom row y=199 at column319 writable")
  Check(Bool(topLeft = #WALLDRAW_MiddleIndex), "top row y=0 at boundary column0 writable")
  Check(Bool(WallFrameHash64(@frame, @hash) <> 0), "full-frame hash computed over exact 64,000 bytes")
  expectedHash = TestFnvUniformReference(#WALLDRAW_MiddleIndex)
  Check(Bool(hash = expectedHash), "frame hash equals independent uniform middle-plane FNV-1a64")
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  WallDrawTallyReset(@tally)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP45()
  BeginCase("WP45", "Invalid negative/out-of-range X rejected without buffer mutation")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected plan.WallSpanPlan
  Protected drawOk.i
  Protected directOk.i
  Protected pixelCount.l = -1
  Protected hashBefore.q
  Protected hashAfter.q
  Protected changedBytes.i = 0
  Protected errorText.s

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip initialized for invalid X")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "tally zeroed before invalid X attempts")
  Check(Bool(WallFrameHash64(@frame, @hashBefore) <> 0), "background fingerprint captured before mutation probes")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "negative-column plan reset")
  plan\FirstX = -1
  plan\LastX = 4
  plan\Kind = #WALL_KIND_SOLID
  plan\Scale1 = #FRACUNIT
  plan\Scale2 = #FRACUNIT
  plan\ScaleStep = 0
  plan\TopFrac = 4096
  plan\BottomFrac = 65536
  plan\TopStep = 0
  plan\BottomStep = 0
  plan\MiddleTier = 1
  plan\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan, @clip, @tally)
  Check(Bool(drawOk = 0), "negative firstX is rejected by plan-level bounds")
  errorText = WallDrawLastError()
  Check(Bool(FindString(errorText, "invalid") > 0),
        "diagnostic names invalid wall plan columns including observed -1..4")
  Check(Bool(tally\ProcessedSpans = 0 And tally\ProcessedColumns = 0 And tally\DrawnPixels = 0),
        "failed negative plan leaves tally completely untouched")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "out-of-range right-column plan reset")
  plan\FirstX = 319
  plan\LastX = 320
  plan\Kind = #WALL_KIND_SOLID
  plan\Scale1 = #FRACUNIT
  plan\Scale2 = #FRACUNIT
  plan\ScaleStep = 0
  plan\TopFrac = 4096
  plan\BottomFrac = 65536
  plan\TopStep = 0
  plan\BottomStep = 0
  plan\MiddleTier = 1
  plan\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan, @clip, @tally)
  Check(Bool(drawOk = 0), "lastX=320 is rejected by plan-level bounds")
  Check(Bool(FindString(WallDrawLastError(), "invalid") > 0),
        "second diagnostic names invalid observed columns 319..320")
  directOk = WallDrawSolidColumn(@frame, -1, 2, 3, #WALLDRAW_MiddleIndex, @pixelCount)
  Check(Bool(directOk = #WALLDRAW_RangeOutOfFrame), "direct negative column returns RangeOutOfFrame")
  Check(Bool(pixelCount = 0), "direct negative column publishes zero pixels")
  Check(Bool(FindString(WallDrawLastError(), "escaped") > 0),
        "direct helper diagnostic names escaped x=-1 x/y plane")
  Check(Bool(WallFrameHash64(@frame, @hashAfter) <> 0), "frame hash re-read after all invalid probes")
  Check(Bool(hashAfter = hashBefore), "negative/out-of-range X attempts changed no framebuffer byte")
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  WallDrawTallyReset(@tally)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP46()
  BeginCase("WP46", "Invalid/empty Y ranges clipped or skipped without mutation")
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected plan.WallSpanPlan
  Protected directOk.i
  Protected drawOk.i
  Protected pixelCount.l = -1
  Protected hashBefore.q
  Protected hashAfter.q
  Protected row.i
  Protected pixel.i

  Check(Bool(TestFrameAndClipBegin(@frame, @clip) <> 0), "frame/clip initialized for invalid Y tests")
  Check(Bool(WallDrawTallyReset(@tally) <> 0), "tally reset")
  Check(Bool(WallFrameHash64(@frame, @hashBefore) <> 0), "background fingerprint captured")
  directOk = WallDrawSolidColumn(@frame, 160, 5, 4, #WALLDRAW_MiddleIndex, @pixelCount)
  Check(Bool(directOk = #WALLDRAW_RangeEmpty And pixelCount = 0),
        "yl=5 > yh=4 returns empty with zero pixels")
  directOk = WallDrawSolidColumn(@frame, 160, -1, 3, #WALLDRAW_MiddleIndex, @pixelCount)
  Check(Bool(directOk = #WALLDRAW_RangeOutOfFrame And pixelCount = 0),
        "negative yl=-1 safely rejected with zero pixels")
  Check(Bool(FindString(WallDrawLastError(), "escaped") > 0),
        "negative-Y diagnostic names the escaped plane coordinates")
  directOk = WallDrawSolidColumn(@frame, 160, 0, 200, #WALLDRAW_MiddleIndex, @pixelCount)
  Check(Bool(directOk = #WALLDRAW_RangeOutOfFrame And pixelCount = 0),
        "yh=200 bottom boundary beyond plane safely rejected")
  Check(Bool(WallFrameHash64(@frame, @hashAfter) <> 0 And hashAfter = hashBefore),
        "all direct invalid-Y attempts leave every frame byte unchanged")

  Check(Bool(WallSpanPlanReset(@plan) <> 0), "inverted fixed-edge plan reset")
  plan\FirstX = 160
  plan\LastX = 160
  plan\Kind = #WALL_KIND_SOLID
  plan\Scale1 = #FRACUNIT
  plan\Scale2 = #FRACUNIT
  plan\ScaleStep = 0
  plan\TopFrac = 0
  plan\BottomFrac = -4096
  plan\TopStep = 0
  plan\BottomStep = 0
  plan\MiddleTier = 1
  plan\Ready = 1
  drawOk = TestDrawPlan(@frame, @plan, @clip, @tally)
  Check(Bool(drawOk <> 0), "topfrac0/bottomfrac-4096 yields yl=0/yh=-1 and safely draws nothing")
  Check(Bool(tally\MiddlePixels = 0 And tally\DrawnPixels = 0),
        "inverted inclusive wall interval skips all pixel writes")
  Check(Bool(tally\EmptyColumns = 1 And tally\OutOfFrameColumns = 0),
        "inverted range is counted empty rather than an out-of-frame failure")
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@frame, 160, row)
    If pixel <> #WALLDRAW_BackgroundIndex
      Check(#False, "empty interval row " + Str(row) + " was mutated with a wall color")
    EndIf
  Next
  Check(Bool(WallFrameHash64(@frame, @hashAfter) <> 0 And hashAfter = hashBefore),
        "empty interval plan also leaves the background fingerprint untouched")
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  WallDrawTallyReset(@tally)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP47()
  BeginCase("WP47", "Distinct stable debug palette indices for four tiers")
  Protected frame.FrameBuffer
  Protected pixelCountBg.l = 0
  Protected pixelCountMid.l = 0
  Protected pixelCountUp.l = 0
  Protected pixelCountLo.l = 0
  Protected directOk.i
  Protected pixelValue.i

  Check(Bool(#WALLDRAW_BackgroundIndex = 0 And #WALLDRAW_MiddleIndex = 176 And
             #WALLDRAW_UpperIndex = 252 And #WALLDRAW_LowerIndex = 96),
        "measured stable policy indices are background0/middle176/upper252/lower96")
  Check(Bool(#WALLDRAW_BackgroundIndex <> #WALLDRAW_MiddleIndex And
             #WALLDRAW_BackgroundIndex <> #WALLDRAW_UpperIndex And
             #WALLDRAW_BackgroundIndex <> #WALLDRAW_LowerIndex And
             #WALLDRAW_MiddleIndex <> #WALLDRAW_UpperIndex And
             #WALLDRAW_MiddleIndex <> #WALLDRAW_LowerIndex And
             #WALLDRAW_UpperIndex <> #WALLDRAW_LowerIndex),
        "four tier indices are pairwise distinct")
  Check(Bool(#WALLDRAW_BackgroundIndex >= 0 And #WALLDRAW_BackgroundIndex <= 255 And
             #WALLDRAW_MiddleIndex >= 0 And #WALLDRAW_MiddleIndex <= 255 And
             #WALLDRAW_UpperIndex >= 0 And #WALLDRAW_UpperIndex <= 255 And
             #WALLDRAW_LowerIndex >= 0 And #WALLDRAW_LowerIndex <= 255),
        "every debug index is inside the canonical 0..255 palette domain")
  Check(Bool(FrameBufferCreate(@frame, 320, 200) <> 0), "framebuffer created for index probes")
  Check(Bool(FrameBufferClear(@frame, #WALLDRAW_BackgroundIndex) <> 0), "plane cleared to background")
  directOk = WallDrawSolidColumn(@frame, 10, 20, 20, #WALLDRAW_BackgroundIndex, @pixelCountBg)
  Check(Bool(directOk = #WALLDRAW_RangeDrawn And pixelCountBg = 1), "background index direct byte write")
  directOk = WallDrawSolidColumn(@frame, 11, 21, 21, #WALLDRAW_MiddleIndex, @pixelCountMid)
  Check(Bool(directOk = #WALLDRAW_RangeDrawn And pixelCountMid = 1), "middle index direct byte write")
  directOk = WallDrawSolidColumn(@frame, 12, 22, 22, #WALLDRAW_UpperIndex, @pixelCountUp)
  Check(Bool(directOk = #WALLDRAW_RangeDrawn And pixelCountUp = 1), "upper index direct byte write")
  directOk = WallDrawSolidColumn(@frame, 13, 23, 23, #WALLDRAW_LowerIndex, @pixelCountLo)
  Check(Bool(directOk = #WALLDRAW_RangeDrawn And pixelCountLo = 1), "lower index direct byte write")
  pixelValue = FrameBufferGetPixel(@frame, 10, 20)
  Check(Bool(pixelValue = #WALLDRAW_BackgroundIndex), "written background pixel reproduces index0")
  pixelValue = FrameBufferGetPixel(@frame, 11, 21)
  Check(Bool(pixelValue = #WALLDRAW_MiddleIndex), "written middle pixel reproduces exact index176")
  pixelValue = FrameBufferGetPixel(@frame, 12, 22)
  Check(Bool(pixelValue = #WALLDRAW_UpperIndex), "written upper pixel reproduces exact index252")
  pixelValue = FrameBufferGetPixel(@frame, 13, 23)
  Check(Bool(pixelValue = #WALLDRAW_LowerIndex), "written lower pixel reproduces exact index96")
  FrameBufferReset(@frame)
EndProcedure

Procedure TestWP48()
  BeginCase("WP48", "FrameBuffer row-major direct bytes and GetPixel agreement")
  Protected frame.FrameBuffer
  Protected pixelValue.i
  Protected byteValue.i
  Protected adjacentValue.i
  Protected aboveValue.i
  Protected belowValue.i
  Protected invalidValue.i
  Protected rowOneValue.i
  Protected neighborValue.i

  Check(Bool(FrameBufferCreate(@frame, 320, 200) <> 0), "canonical framebuffer created")
  Check(Bool(FrameBufferClear(@frame, #WALLDRAW_BackgroundIndex) <> 0), "row-major plane cleared")
  Check(Bool(frame\Magic = #FRAMEBUFFER_Magic And frame\Width = 320 And
             frame\Height = 200 And frame\PixelCount = 64000),
        "owned plane publishes canonical Magic/width/height/pixel count")
  ; Exact row-major byte at (x=160,y=42): offset = y*320 + x.
  PokeA(frame\Pixels + (42 * 320 + 160), 91)
  byteValue = PeekA(frame\Pixels + (42 * 320 + 160))
  Check(Bool(byteValue = 91), "direct row-major byte at x=160 y=42 reads exactly 91")
  pixelValue = FrameBufferGetPixel(@frame, 160, 42)
  Check(Bool(pixelValue = 91), "GetPixel agrees with direct byte at x=160 y=42")
  adjacentValue = PeekA(frame\Pixels + (42 * 320 + 159))
  neighborValue = FrameBufferGetPixel(@frame, 161, 42)
  Check(Bool(adjacentValue = #WALLDRAW_BackgroundIndex And
             neighborValue = #WALLDRAW_BackgroundIndex),
        "neighbor bytes x=159/x=161 row42 remain untouched background")
  aboveValue = PeekA(frame\Pixels + (41 * 320 + 160))
  belowValue = PeekA(frame\Pixels + (43 * 320 + 160))
  Check(Bool(aboveValue = 0 And belowValue = 0), "row above and below touch no same-column byte")
  ; Row-major second-row offset: (x=0,y=1) = 1*320 + 0 = 320; (x=1,y=1)=321.
  PokeA(frame\Pixels + 320, 77)
  PokeA(frame\Pixels + 321, 88)
  rowOneValue = FrameBufferGetPixel(@frame, 0, 1)
  neighborValue = FrameBufferGetPixel(@frame, 1, 1)
  Check(Bool(rowOneValue = 77 And neighborValue = 88),
        "row1 x=0 at offset320 and x=1 at offset321 resolve independently")
  invalidValue = FrameBufferGetPixel(@frame, -1, 0)
  Check(Bool(invalidValue = -1), "GetPixel rejects negative X=-1 with -1 sentinel")
  invalidValue = FrameBufferGetPixel(@frame, 0, 200)
  Check(Bool(invalidValue = -1), "GetPixel rejects bottom row Y=200 with -1 sentinel")
  invalidValue = FrameBufferGetPixel(@frame, 320, 0)
  Check(Bool(invalidValue = -1), "GetPixel rejects X=320 fencepost with -1 sentinel")
  invalidValue = FrameBufferGetPixel(@frame, 160, -1)
  Check(Bool(invalidValue = -1), "GetPixel rejects negative Y=-1 with -1 sentinel")
  Check(Bool(frame\PixelCount = 64000 And frame\Width * frame\Height = 64000),
        "row-major geometry remains exactly 320*200=64,000 bytes")
  FrameBufferReset(@frame)
EndProcedure

Procedure TestWP49()
  BeginCase("WP49", "Exact 64,000-byte FNV-1a64 hash repeated twice")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected renderOk.i
  Protected hashResult.q
  Protected hashRepeatA.q
  Protected hashRepeatB.q
  Protected expectedHash.q
  Protected hashText.s

  prepareOk = TestPrepareScene("A", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "single-column scene A prepares for hash repeat")
  Check(Bool(WallVisibilityCount(@visibility) = 1), "scene A publishes one visible span")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "scene A frame renders with expected nonzero drawn pixel")
  Check(Bool(WallRenderResultIsValid(@result) <> 0), "hash result is valid after render")
  Check(Bool(target\PixelCount = #WALLDRAW_PixelCount), "target plane still exactly 64,000 bytes")
  hashResult = result\Hash
  expectedHash = GoldSceneHash("A")
  Check(Bool(hashResult = expectedHash), "frame hash equals independent scene-A golden FNV")
  hashText = WallRenderGetHashText(@result)
  Check(Bool(TestHexTextCanonical(hashText) <> 0), "hash text is canonical 16 uppercase hex characters")
  Check(Bool(hashText = "2090BE09430C7B25"),
        "scene-A hash text is exact independently generated 2090BE09430C7B25")
  Check(Bool(WallFrameHash64(@target, @hashRepeatA) <> 0), "first direct 64,000-byte hash recompute succeeds")
  Check(Bool(hashRepeatA = hashResult), "first repeated hash equals renderer-published hash")
  Check(Bool(WallFrameHash64(@target, @hashRepeatB) <> 0), "second identical direct hash recompute succeeds")
  Check(Bool(hashRepeatB = hashResult), "second repeated hash remains byte-stable")
  Check(Bool(hashRepeatA = hashRepeatB), "two repeated FNV passes agree exactly")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP50()
  BeginCase("WP50", "Different headings or viewz produce justified differing hashes")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected resultBase.WallRenderResult
  Protected resultHeading.WallRenderResult
  Protected resultViewZ.WallRenderResult
  Protected prepareOk.i
  Protected viewSetOk.i
  Protected visibilityOk.i
  Protected renderOk.i
  Protected hashBase.q
  Protected hashHeading.q
  Protected hashViewZ.q
  Protected expectedBase.q
  Protected textBase.s
  Protected textHeading.s
  Protected textViewZ.s

  prepareOk = TestPrepareScene("B", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "wide scene B prepares for camera-justification hashes")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultBase, #True)
  Check(Bool(renderOk <> 0), "heading0/viewfloor0 baseline frame renders")
  hashBase = resultBase\Hash
  expectedBase = GoldSceneHash("B")
  Check(Bool(hashBase = expectedBase), "baseline hash equals independent scene-B golden FNV")
  Check(Bool(hashBase <> 0), "baseline integer hash is not a default zero")
  textBase = WallRenderGetHashText(@resultBase)
  Check(Bool(TestHexTextCanonical(textBase) <> 0), "baseline hash text has canonical 16 uppercase digits")
  Check(Bool(textBase = "72685823901A3A25"),
        "baseline hash text is exact generated scene-B 72685823901A3A25")

  viewSetOk = WallViewSetMapUnits(@view, 0, 0, #BAM_ANG45, 0)
  Check(Bool(viewSetOk <> 0), "scene B view changed to explicit heading ANG45")
  WallVisibilityReset(@visibility)
  visibilityOk = WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0, @visibility)
  Check(Bool(visibilityOk <> 0), "visibility rebuilt under ANG45 heading")
  Check(Bool(WallVisibilityCount(@visibility) = 1), "ANG45 still publishes exactly one clipped span")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultHeading, #True)
  Check(Bool(renderOk <> 0), "ANG45 heading frame renders nonzero wall pixels")
  hashHeading = resultHeading\Hash
  Check(Bool(hashHeading <> 0), "heading-altered hash is measured nonzero")
  textHeading = WallRenderGetHashText(@resultHeading)
  Check(Bool(TestHexTextCanonical(textHeading) <> 0), "heading-altered hash text stays canonical hex")
  Check(Bool(hashHeading <> hashBase), "ANG45 clipping/scale alteration produces a differing frame hash")
  Check(Bool(textHeading <> textBase), "heading hashes differ in canonical textual form too")

  viewSetOk = WallViewSetFixed(@view, 0, 0, 0, #WALLVIEW_ViewHeightFixed + #FRACUNIT)
  Check(Bool(viewSetOk <> 0), "scene B view changed to explicit extra-one-unit viewz 42*FRACUNIT")
  WallVisibilityReset(@visibility)
  visibilityOk = WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0, @visibility)
  Check(Bool(visibilityOk <> 0), "visibility rebuilt under altered checked viewz")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultViewZ, #True)
  Check(Bool(renderOk <> 0), "viewz-altered frame renders nonzero wall pixels")
  hashViewZ = resultViewZ\Hash
  Check(Bool(hashViewZ <> 0), "viewz-altered hash is measured nonzero")
  textViewZ = WallRenderGetHashText(@resultViewZ)
  Check(Bool(TestHexTextCanonical(textViewZ) <> 0), "viewz-altered hash text remains canonical hex")
  Check(Bool(hashViewZ <> hashBase), "viewz 42*FRACUNIT changes upper/lower fracs and therefore hash")
  Check(Bool(hashViewZ <> hashHeading), "heading and viewz alternations are distinct justified hashes")
  FrameBufferReset(@target)
  WallRenderResultReset(@resultBase)
  WallRenderResultReset(@resultHeading)
  WallRenderResultReset(@resultViewZ)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP51()
  BeginCase("WP51", "Span ordering preserved without sorting or deduplication")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected visibilityAgain.WallVisibilityResult
  Protected span.WallSpan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected againOk.i
  Protected renderOk.i
  Protected hash.q
  Protected expectedHash.q
  Protected count.l
  Protected span0Seg.l = -1
  Protected span1Seg.l = -1
  Protected span2Seg.l = -1
  Protected span0First.l = -1
  Protected span2Last.l = -1

  prepareOk = TestPrepareScene("C", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "occluded near+far scene C prepares")
  count = WallVisibilityCount(@visibility)
  Check(Bool(count = 3), "scene C publishes three ordered spans, no dedup collapse")
  Check(Bool(TestCompareSpansGold("C", @visibility) <> 0),
        "all ordered span IDs and X intervals equal independent generated C record")
  Check(Bool(TestReadVisibilitySpan(@visibility, 0, @span) <> 0), "ordered span slot0 readable")
  span0Seg = span\Seg
  span0First = span\FirstX
  Check(Bool(span\Kind = #WALL_KIND_SOLID And span\FirstX = 58 And span\LastX = 262),
        "slot0 is near SOLID seg0 interval [58,262] in original append order")
  Check(Bool(TestReadVisibilitySpan(@visibility, 1, @span) <> 0), "ordered span slot1 readable")
  span1Seg = span\Seg
  Check(Bool(span\Kind = #WALL_KIND_PASS And span\FirstX = 0 And span\LastX = 57),
        "slot1 is first far PASS fragment [0,57] immediately after near span")
  Check(Bool(TestReadVisibilitySpan(@visibility, 2, @span) <> 0), "ordered span slot2 readable")
  span2Seg = span\Seg
  span2Last = span\LastX
  Check(Bool(span\Kind = #WALL_KIND_PASS And span\FirstX = 263 And span\LastX = 319),
        "slot2 is second far PASS fragment [263,319], no sort or merge")
  Check(Bool(span0Seg = 0 And span1Seg = 1 And span2Seg = 1 And
             span0First = 58 And span2Last = 319),
        "segment identities and interval chronology stay exactly as published")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), "scene C ordered spans render a nonzero occluded wall frame")
  Check(Bool(WallRenderResultIsValid(@result) <> 0), "scene C render result valid")
  Check(Bool(result\SpanCount = 3 And result\SegmentCount = 3),
        "result consumes all three source spans in order with no filtering")
  Check(Bool(result\ProcessedColumns = 320), "near 205 + far left58 + far right57 cover every column")
  Check(Bool(result\DrawnPixels > 0 And result\MiddlePixels > 0 And
             result\UpperPixels > 0 And result\LowerPixels > 0),
        "frame paints near solid and far upper/lower tiers in their clipped fragments")
  hash = result\Hash
  expectedHash = GoldSceneHash("C")
  Check(Bool(hash = expectedHash), "ordered render hash equals independent generated C FNV")
  Check(Bool(WallRenderGetHashText(@result) = "4D32B97402CD3925"),
        "scene-C hash text is exact generated 4D32B97402CD3925")

  WallVisibilityReset(@visibilityAgain)
  againOk = WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0, @visibilityAgain)
  Check(Bool(againOk <> 0), "identical repeated visibility Build succeeds")
  Check(Bool(WallVisibilityCount(@visibilityAgain) = 3), "repeated Build keeps exactly three spans")
  Check(Bool(TestCompareSpansGold("C", @visibilityAgain) <> 0),
        "repeated Build reproduces identical ordered ID/X chronology, no sort drift")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  WallVisibilityReset(@visibilityAgain)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP52()
  BeginCase("WP52", "Corrupt indices, unready owners and null outputs rejected")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected blankVisibility.WallVisibilityResult
  Protected span.WallSpan
  Protected corruptSpan.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected spanOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected errorText.s
  Protected planReadyCheck.i

  prepareOk = TestPrepareScene("B", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "scene B prepares for rejection paths")
  spanOk = TestReadVisibilitySpan(@visibility, 0, @span)
  Check(Bool(spanOk <> 0), "scene B span readable for corruption copy")
  corruptSpan\Subsector = span\Subsector
  corruptSpan\Seg = 99
  corruptSpan\Linedef = span\Linedef
  corruptSpan\Side = span\Side
  corruptSpan\FrontSector = span\FrontSector
  corruptSpan\BackSector = span\BackSector
  corruptSpan\FirstX = span\FirstX
  corruptSpan\LastX = span\LastX
  corruptSpan\Kind = span\Kind
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "plan reset before corrupt seg index")
  projectOk = WallProjectSpanChecked(@map, 0, 0, @projection,
                                     0, 0, 0, #WALLVIEW_ViewHeightFixed,
                                     0, @corruptSpan, @plan)
  Check(Bool(projectOk = 0), "corrupt seg index 99 in synthetic span is rejected")
  errorText = WallProjectLastError()
  Check(Bool(FindString(errorText, "seg index") > 0 Or FindString(errorText, "out of range") > 0),
        "corrupt-index diagnostic names invalid seg 99 / decoder bounds")
  planReadyCheck = WallSpanPlanIsReady(@plan)
  Check(Bool(planReadyCheck = 0), "failed corrupt projection leaves plan unready")
  Check(Bool(plan\Distance = 0 And plan\Hyp = 0), "failed corrupt projection publishes no stale numeric fields")

  Check(Bool(WallViewReset(@view) <> 0), "view reset to unready state")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "plan reset before unready view check")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk = 0), "unready camera view rejects span projection")
  errorText = WallViewLastError()
  Check(Bool(FindString(errorText, "not ready") > 0),
        "unready view diagnostic names the camera readiness precondition")
  Check(Bool(WallSpanPlanIsReady(@plan) = 0), "unready-view failure leaves plan unready")

  Check(Bool(WallViewSetMapUnits(@view, 0, 0, 0, 0) <> 0),
        "view re-readied before projection-only precondition probe")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection reset to unready state")
  Check(Bool(WallSpanPlanReset(@plan) <> 0), "plan reset before unready projection check")
  projectOk = TestProjectSpan(@map, @view, @projection, @span, 0, 0, @plan)
  Check(Bool(projectOk = 0), "unready projection rejects span projection")
  errorText = WallProjectLastError()
  Check(Bool(FindString(errorText, "projection") > 0), "unready projection diagnostic names the projection")
  Check(Bool(WallSpanPlanIsReady(@plan) = 0), "unready-projection failure never marks plan ready")

  prepareOk = TestPrepareScene("B", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "scene B rebuilt after owner-reset rejection probes")
  projectOk = WallProjectSpanChecked(@map, 0, 0, @projection,
                                     0, 0, 0, #WALLVIEW_ViewHeightFixed,
                                     0, @span, 0)
  Check(Bool(projectOk = 0), "null plan output pointer rejected before any field write")
  Check(Bool(FindString(WallProjectLastError(), "plan pointer is null") > 0),
        "null plan diagnostic names the missing plan output pointer")

  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, 0, #False)
  Check(Bool(renderOk = 0), "null render result pointer rejected")
  Check(Bool(FindString(WallRenderLastError(), "result pointer is null") > 0),
        "null render-result diagnostic names the missing metadata pointer")
  Check(Bool(target\Magic = 0 And target\Pixels = 0),
        "null-result rejection leaves a zero caller frame untouched")

  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             0, @result, #False)
  Check(Bool(renderOk = 0), "null target framebuffer pointer rejected")
  Check(Bool(FindString(WallRenderLastError(), "target framebuffer pointer is null") > 0),
        "null-target diagnostic names the missing framebuffer pointer")
  Check(Bool(result\Magic = #RENDER_Magic And result\Ready = 0 And result\Allocations = 0),
        "null-target failure resets reusable metadata with Ready=0 and zero counters")

  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @blankVisibility,
                             @target, @result, #False)
  Check(Bool(renderOk = 0), "zero-initialized unready visibility authority rejects frame build")
  Check(Bool(FindString(WallRenderLastError(), "visibility result is not initialized") > 0),
        "uninitialized visibility diagnostic names the M3-04 authority precondition")
  Check(Bool(target\Magic = 0 And target\Pixels = 0),
        "null-visibility failure leaves caller frame byte-free/untouched")
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
  WallSpanPlanReset(@plan)
EndProcedure

Procedure TestWP53()
  BeginCase("WP53", "Transactional failure leaves previous frame unchanged")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected resultValid.WallRenderResult
  Protected resultFailed.WallRenderResult
  Protected prepareOk.i
  Protected firstRenderOk.i
  Protected failureOk.i
  Protected recoveryOk.i
  Protected mutateOk.i
  Protected oldHash.q
  Protected oldResultHash.q
  Protected afterFailureHash.q
  Protected afterRecoveryHash.q
  Protected expectedHash.q
  Protected oldColumns.l
  Protected oldDrawn.l
  Protected errorText.s

  prepareOk = TestPrepareScene("A", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "scene A prepares for transactional corruption")
  firstRenderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                                  @target, @resultValid, #True)
  Check(Bool(firstRenderOk <> 0), "valid scene A frame builds into initially empty target")
  Check(Bool(WallRenderResultIsValid(@resultValid) <> 0), "successful transactional result is valid")
  Check(Bool(target\Magic = #FRAMEBUFFER_Magic And target\PixelCount = 64000 And
             target\Pixels <> 0),
        "success transfers ownership of a valid canonical target plane")
  oldHash = resultValid\Hash
  oldResultHash = TestFnvFrameReference(@target)
  expectedHash = GoldSceneHash("A")
  Check(Bool(oldHash = expectedHash And oldResultHash = expectedHash),
        "first target/result hashes both equal independent scene-A FNV")
  oldColumns = resultValid\ProcessedColumns
  oldDrawn = resultValid\DrawnPixels
  Check(Bool(oldColumns = 1 And oldDrawn > 0), "first frame processed one column with nonzero pixels")

  mutateOk = TestPokeMapSegV1(@map, 0, 99)
  Check(Bool(mutateOk <> 0), "owned synthetic seg v1 mutated to corrupt index 99")
  failureOk = Bool(WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                                   @target, @resultFailed, #True) = 0)
  Check(Bool(failureOk <> 0), "corrupt seg v1 makes whole transaction fail")
  Check(Bool(resultFailed\Magic = #RENDER_Magic And resultFailed\Ready = 0 And
             resultFailed\SpanCount = 0 And resultFailed\Hash = 0),
        "failed transaction resets reusable metadata with Ready=0, no stale span/hash")
  errorText = WallRenderLastError()
  Check(Bool(FindString(errorText, "projection failed") > 0 And
             FindString(errorText, "vertex") > 0),
        "failure diagnostic identifies span0 projection vertex-corruption bounds")
  Check(Bool(WallFrameHash64(@target, @afterFailureHash) <> 0), "previous target hash read after failure")
  Check(Bool(afterFailureHash = oldHash And
             TestFnvFrameReference(@target) = oldResultHash),
        "failed private build leaves prior target byte-for-byte identical")
  Check(Bool(target\Magic = #FRAMEBUFFER_Magic And target\Pixels <> 0),
        "failed transaction still retains valid caller-owned prior plane")
  Check(Bool(resultFailed\Allocations = 0 And resultFailed\SpanCount = 0 And
             resultFailed\DrawnPixels = 0),
        "failed result publishes no stale allocation/span/pixel counters")

  mutateOk = TestPokeMapSegV1(@map, 0, 0)
  Check(Bool(mutateOk <> 0), "synthetic seg v1 restored to original valid index0")
  recoveryOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                               @target, @resultFailed, #True)
  Check(Bool(recoveryOk <> 0), "restored map geometry allows recovery transaction")
  Check(Bool(WallRenderResultIsValid(@resultFailed) <> 0), "recovery result is valid and reusable")
  afterRecoveryHash = resultFailed\Hash
  Check(Bool(afterRecoveryHash = oldHash), "recovery rebuild reproduces original golden frame hash")
  Check(Bool(WallFrameHash64(@target, @afterRecoveryHash) <> 0 And
             afterRecoveryHash = oldHash),
        "recovery target repaint is byte-identical to prior successful frame")
  Check(Bool(resultFailed\ProcessedColumns = oldColumns And
             resultFailed\DrawnPixels = oldDrawn),
        "recovered counts equal original processed/drawn counters without stale state")
  FrameBufferReset(@target)
  WallRenderResultReset(@resultValid)
  WallRenderResultReset(@resultFailed)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP54()
  BeginCase("WP54", "Repeated render/reset/load A-B-A cycles and buffer ownership")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected resultA.WallRenderResult
  Protected resultB.WallRenderResult
  Protected resultAgainA.WallRenderResult
  Protected prepareOk.i
  Protected renderOk.i
  Protected resetOk.i
  Protected recreateOk.i
  Protected hashA.q
  Protected hashB.q
  Protected hashAAgain.q
  Protected expectedA.q
  Protected expectedB.q
  Protected columnsA.l
  Protected columnsB.l
  Protected columnsAAgain.l
  Protected drawnA.l
  Protected drawnAAgain.l
  Protected invalidPixel.i
  Protected validPixel.i
  Protected uniformBefore.q
  Protected uniformAfter.q

  prepareOk = TestPrepareScene("A", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "first A load prepares")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultA, #True)
  Check(Bool(renderOk <> 0), "first A frame renders into zero target")
  hashA = resultA\Hash
  expectedA = GoldSceneHash("A")
  columnsA = resultA\ProcessedColumns
  drawnA = resultA\DrawnPixels
  Check(Bool(hashA = expectedA), "first A frame equals independent scene-A FNV")
  Check(Bool(columnsA = 1 And drawnA > 0), "first A counters are one column/nonzero drawn pixels")
  Check(Bool(target\Magic = #FRAMEBUFFER_Magic And target\Pixels <> 0),
        "first A success leaves caller buffer owning valid pixels")

  resetOk = FrameBufferReset(@target)
  Check(Bool(resetOk <> 0), "first caller-frame release succeeds")
  invalidPixel = FrameBufferGetPixel(@target, 0, 0)
  Check(Bool(invalidPixel = -1 And target\Magic = 0 And target\PixelCount = 0 And
             target\Pixels = 0),
        "after Reset old plane is freed and pixel access is safely rejected")
  resetOk = FrameBufferReset(@target)
  Check(Bool(resetOk <> 0), "idempotent second Reset of already-empty caller frame succeeds")
  recreateOk = FrameBufferCreate(@target, 320, 200)
  Check(Bool(recreateOk <> 0), "caller can re-Create canonical frame after Reset")
  Check(Bool(FrameBufferClear(@target, #WALLDRAW_BackgroundIndex) <> 0), "re-Created plane clears")
  uniformBefore = TestFnvFrameReference(@target)
  Check(Bool(uniformBefore = TestFnvUniformReference(0)),
        "re-Created empty plane equals independent background fingerprint")

  prepareOk = TestPrepareScene("B", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "B load after A prepare/reset succeeds")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultB, #True)
  Check(Bool(renderOk <> 0), "B frame renders into caller-recreated buffer")
  hashB = resultB\Hash
  expectedB = GoldSceneHash("B")
  columnsB = resultB\ProcessedColumns
  Check(Bool(hashB = expectedB), "B frame equals independent scene-B FNV")
  Check(Bool(columnsB = 205), "B render processes exactly the generated 58..262 span width")
  Check(Bool(target\Magic = #FRAMEBUFFER_Magic And target\Pixels <> 0),
        "B success replaced re-created target by valid owned B plane")
  uniformAfter = TestFnvFrameReference(@target)
  Check(Bool(uniformAfter = hashB), "target bytes after B render agree with published B hash")

  resetOk = FrameBufferReset(@target)
  Check(Bool(resetOk <> 0), "B caller frame released before returning to A")
  invalidPixel = FrameBufferGetPixel(@target, 160, 100)
  Check(Bool(invalidPixel = -1), "released B plane pixel access is safely rejected")
  prepareOk = TestPrepareScene("A", @map, @view, @projection, @visibility)
  Check(Bool(prepareOk <> 0), "A reload after B reset/load cycle succeeds")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultAgainA, #True)
  Check(Bool(renderOk <> 0), "second A frame renders into freed/reused caller buffer")
  hashAAgain = resultAgainA\Hash
  columnsAAgain = resultAgainA\ProcessedColumns
  drawnAAgain = resultAgainA\DrawnPixels
  Check(Bool(hashAAgain = expectedA), "repeated A frame reproduces original independent A FNV")
  Check(Bool(hashAAgain = hashA), "A->B->A cycle ends with identical A integer hash")
  Check(Bool(columnsAAgain = columnsA And drawnAAgain = drawnA),
        "repeated A counters exactly equal first A run")
  validPixel = FrameBufferGetPixel(@target, 1, 100)
  Check(Bool(validPixel >= 0), "A->B->A final target pixel access is valid row-major byte")
  resetOk = FrameBufferReset(@target)
  Check(Bool(resetOk <> 0), "final A caller frame release succeeds")
  FrameBufferReset(@target)
  WallRenderResultReset(@resultA)
  WallRenderResultReset(@resultB)
  WallRenderResultReset(@resultAgainA)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

Procedure TestWP55()
  BeginCase("WP55", "No per-column allocation; fixed allocations and limits checked")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected resultA.WallRenderResult
  Protected resultT.WallRenderResult
  Protected prepareAOk.i
  Protected prepareTOk.i
  Protected renderAOk.i
  Protected renderTOk.i
  Protected allocationsA.l
  Protected allocationsT.l
  Protected columnsPH.l
  Protected drawnPH.l
  Protected *pixelsBefore.Byte
  Protected *pixelsAfter.Byte
  Protected *clipCeilBefore.Long
  Protected *clipCeilAfter.Long
  Protected *clipFloorBefore.Long
  Protected *clipFloorAfter.Long
  Protected hotPlan.WallSpanPlan
  Protected hotClip.WallVerticalClip
  Protected hotTally.WallDrawTally
  Protected hotFrame.FrameBuffer
  Protected hotDrawOk.i
  Protected hotHash.q
  Protected hotExpected.q

  prepareAOk = TestPrepareScene("A", @map, @view, @projection, @visibility)
  Check(Bool(prepareAOk <> 0), "single-column scene A prepares for allocation accounting")
  renderAOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                              @target, @resultA, #True)
  Check(Bool(renderAOk <> 0), "one-column frame succeeds")
  Check(Bool(WallRenderResultIsValid(@resultA) <> 0), "one-column allocations result valid")
  allocationsA = resultA\Allocations
  Check(Bool(allocationsA = 3), "A publishes exactly one clip + one metadata + one frame allocation =3")
  columnsPH = resultA\ProcessedColumns
  Check(Bool(columnsPH = 1), "A processed a single column for allocation comparison")

  prepareTOk = TestPrepareScene("T", @map, @view, @projection, @visibility)
  Check(Bool(prepareTOk <> 0), "full-width tilted scene T prepares")
  renderTOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                              @target, @resultT, #True)
  Check(Bool(renderTOk <> 0), "full-width frame succeeds")
  allocationsT = resultT\Allocations
  drawnPH = resultT\ProcessedColumns
  Check(Bool(allocationsT = 3), "320-column frame still publishes exactly three fixed allocations")
  Check(Bool(allocationsT = allocationsA), "allocation count is independent of processed column volume")
  Check(Bool(drawnPH = 320), "T explicitly processed all 320 columns through the same hot loop")
  Check(Bool(resultT\SpanCount = resultA\SpanCount And resultT\SpanCount = 1),
        "both one-span scenes consume a single metadata slot, confirming budgets")
  Check(Bool(#RENDER_MaxSpans = 200000 And #RENDER_MaxMetadataBytes = 67108864),
        "documented wide64 render span/metadata budgets are checked constants")
  Check(Bool(#WALLDRAW_MaxClipBytes = 2560 And #WALLDRAW_PixelCount = 64000),
        "clip budget 2,560 bytes and plane budget 64,000 are exact checked constants")
  Check(Bool(#PROJ_VIEWWIDTH = 320 And #PROJ_VIEWHEIGHT = 200),
        "column/row limits derive from canonical viewport, not loose values")

  Check(Bool(FrameBufferCreate(@hotFrame, 320, 200) <> 0), "hot-path frame created")
  Check(Bool(FrameBufferClear(@hotFrame, #WALLDRAW_BackgroundIndex) <> 0), "hot-path frame cleared")
  Check(Bool(WallVerticalClipReset(@hotClip) <> 0), "hot-path clip reset")
  Check(Bool(WallVerticalClipBegin(@hotClip) <> 0), "hot-path clip arrays allocated once at frame begin")
  Check(Bool(WallDrawTallyReset(@hotTally) <> 0), "hot-path tally reset")
  Check(Bool(WallSpanPlanReset(@hotPlan) <> 0), "hot-path one-span plan reset")
  hotPlan\FirstX = 0
  hotPlan\LastX = 319
  hotPlan\Kind = #WALL_KIND_SOLID
  hotPlan\Scale1 = #FRACUNIT
  hotPlan\Scale2 = #FRACUNIT
  hotPlan\ScaleStep = 0
  hotPlan\TopFrac = 0
  hotPlan\BottomFrac = 815104
  hotPlan\TopStep = 0
  hotPlan\BottomStep = 0
  hotPlan\MiddleTier = 1
  hotPlan\Ready = 1
  Check(Bool(@hotPlan <> 0 And WallSpanPlanIsReady(@hotPlan) <> 0), "manual hot plan ready")
  *pixelsBefore = hotFrame\Pixels
  *clipCeilBefore = hotClip\Ceiling
  *clipFloorBefore = hotClip\Floor
  Check(Bool(*pixelsBefore <> 0 And *clipCeilBefore <> 0 And *clipFloorBefore <> 0),
        "all per-frame buffers own nonnull bases before hot draw")
  hotDrawOk = WallDrawSpan(@hotFrame, @hotPlan, @hotClip, @hotTally)
  Check(Bool(hotDrawOk <> 0), "320-column one-span hot draw succeeds")
  *pixelsAfter = hotFrame\Pixels
  *clipCeilAfter = hotClip\Ceiling
  *clipFloorAfter = hotClip\Floor
  Check(Bool(*pixelsAfter = *pixelsBefore And *clipCeilAfter = *clipCeilBefore And
             *clipFloorAfter = *clipFloorBefore),
        "320 per-column iterations retain identical owned frame/clip pointers, no hot allocation")
  Check(Bool(hotTally\ProcessedColumns = 320 And hotTally\MiddlePixels = 64000 And
             hotTally\DrawnPixels = 64000 And hotTally\ProcessedSpans = 1),
        "hot-path counters are checked exact: 320 columns, 64,000 pixels, 1 span")
  Check(Bool(WallFrameHash64(@hotFrame, @hotHash) <> 0), "hot-path full plane hash computed")
  hotExpected = TestFnvUniformReference(#WALLDRAW_MiddleIndex)
  Check(Bool(hotHash = hotExpected), "hot-path full plane equals independent middle uniform FNV")
  FrameBufferReset(@hotFrame)
  WallVerticalClipReset(@hotClip)
  WallDrawTallyReset(@hotTally)
  WallSpanPlanReset(@hotPlan)
  FrameBufferReset(@target)
  WallRenderResultReset(@resultA)
  WallRenderResultReset(@resultT)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

; ---------------------------------------------------------------------------
; WP56 - five-scene broad independent sample-column oracle (helper + case)
; ---------------------------------------------------------------------------

Procedure.i TestVerifySceneGoldFrame(SceneId.s)
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected renderOk.i
  Protected hash.q
  Protected expected.q
  Protected fixtureSpanCount.l
  Protected fixtureSampleCount.l
  Protected sampleX.l
  Protected i.i
  Protected text.s
  Protected beforeFailure.i = gFailureCount

  prepareOk = TestPrepareScene(SceneId, @map, @view, @projection, @visibility)
  If prepareOk = 0
    Check(#False, SceneId + ": synthetic map/view/projection/visibility prepares")
    MapLevelReset(@map)
    WallVisibilityReset(@visibility)
    ProjectionReset(@projection)
    WallViewReset(@view)
    ProcedureReturn #False
  EndIf
  Check(Bool(TestCompareSpansGold(SceneId, @visibility) <> 0),
        SceneId + ": published spans/IDs/intervals equal generated oracle record")
  fixtureSpanCount = GoldSceneSpanCount(SceneId)
  If SceneId = "A"
    fixtureSampleCount = #WALLGOLD_A_SampleCount
  ElseIf SceneId = "B"
    fixtureSampleCount = #WALLGOLD_B_SampleCount
  ElseIf SceneId = "E"
    fixtureSampleCount = #WALLGOLD_E_SampleCount
  ElseIf SceneId = "T"
    fixtureSampleCount = #WALLGOLD_T_SampleCount
  ElseIf SceneId = "C"
    fixtureSampleCount = #WALLGOLD_C_SampleCount
  Else
    fixtureSampleCount = 0
  EndIf
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  Check(Bool(renderOk <> 0), SceneId + ": frame renders nonzero expected-visible pixels")
  Check(Bool(WallRenderResultIsValid(@result) <> 0), SceneId + ": render result valid")
  Check(Bool(result\SpanCount = fixtureSpanCount),
        SceneId + ": result span count equals generated record count")
  hash = result\Hash
  expected = GoldSceneHash(SceneId)
  Check(Bool(hash = expected), SceneId + ": full-plane FNV equals independent generated hash")
  text = WallRenderGetHashText(@result)
  Check(Bool(TestHexTextCanonical(text) <> 0),
        SceneId + ": published hash text is canonical 16 uppercase hex")
  Check(Bool(result\DrawnPixels > 0),
        SceneId + ": expected-visible oracle scene paints concrete nonzero pixels")
  For i = 0 To fixtureSampleCount - 1
    If GoldSampleXGet(SceneId, i, @sampleX) = #False
      Check(#False, SceneId + ": oracle sample X index readable")
      continue
    EndIf
    Check(Bool(TestCompareGoldSampleColumn(SceneId, sampleX, @target) <> 0),
          SceneId + ": column x=" + Str(sampleX) +
          " all 200 row-major palette bytes agree with independent Python oracle")
  Next
  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
  ProcedureReturn Bool(gFailureCount = beforeFailure)
EndProcedure

Procedure TestWP56()
  BeginCase("WP56", "Independent C/Python oracle agreement at sample columns")
  Check(Bool(TestVerifySceneGoldFrame("A") <> 0),
        "scene A tiny [1,1] frame oracle agrees fully")
  Check(Bool(TestVerifySceneGoldFrame("B") <> 0),
        "scene B wide [58,262] frame oracle agrees fully")
  Check(Bool(TestVerifySceneGoldFrame("E") <> 0),
        "scene E screen-filling [0,319] frame oracle agrees fully")
  Check(Bool(TestVerifySceneGoldFrame("T") <> 0),
        "scene T tilted full-width accumulating frame oracle agrees fully")
  Check(Bool(TestVerifySceneGoldFrame("C") <> 0),
        "scene C occluded near+far ordered tier frame oracle agrees fully")
EndProcedure

; ---------------------------------------------------------------------------
; Suite driver and measured summary
; ---------------------------------------------------------------------------

Procedure Main()
  TestWP01()
  TestWP02()
  TestWP03()
  TestWP04()
  TestWP05()
  TestWP06()
  TestWP07()
  TestWP08()
  TestWP09()
  TestWP10()
  TestWP11()
  TestWP12()
  TestWP13()
  TestWP14()
  TestWP15()
  TestWP16()
  TestWP17()
  TestWP18()
  TestWP19()
  TestWP20()
  TestWP21()
  TestWP22()
  TestWP23()
  TestWP24()
  TestWP25()
  TestWP26()
  TestWP27()
  TestWP28()
  TestWP29()
  TestWP30()
  TestWP31()
  TestWP32()
  TestWP33()
  TestWP34()
  TestWP35()
  TestWP36()
  TestWP37()
  TestWP38()
  TestWP39()
  TestWP40()
  TestWP41()
  TestWP42()
  TestWP43()
  TestWP44()
  TestWP45()
  TestWP46()
  TestWP47()
  TestWP48()
  TestWP49()
  TestWP50()
  TestWP51()
  TestWP52()
  TestWP53()
  TestWP54()
  TestWP55()
  TestWP56()
EndProcedure

OpenConsole()
Main()

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
