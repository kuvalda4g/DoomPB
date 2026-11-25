; -----------------------------------------------------------------------------
; DoomPB - M3-05 synthetic wall render integration tests WI01-WI03
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; No commercial data, WAD bytes or window: every map is an owned synthetic
; ten-lump validated MapLevel built by ../unit/wall_test_support.pbi (with the
; explicit SEGS raw-angle field) and every expected frame/hash/sample row comes
; from the independently generated numeric fixture
; tests/fixtures/m3_wall_projection_golden.pbi. Independent prefix hashes use the
; documented FNV-1a64 constants and exact 64,000 row-major palette bytes.
;
; WI01: minimal one-sector A/B/E scenes; one-column and wide visible one-sided
;       walls; bounding controls, nonzero wall pixels, independent golden frame
;       hashes and repeated build/render identity.
; WI02: two-sided C portal room with near SOLID wall and farther upper/lower
;       tiers clipped around it; ordered WallSpan IDs/X intervals against the
;       C golden record; full sample-column row agreement, occlusion crossing,
;       opening background and y=0/199 boundary checks for tiny/full spans.
; WI03: malformed seg references, coincident/near-zero division, invalid viewz,
;       renderer span budget cap, invalid pixel coords, transactional frame
;       recovery, synthetic A->B->A load/render cycles, noncommutative heading
;       hashes and deterministic diagnostics. CLI modes are exercised by the
;       project script/owner, not by this headless compile-only harness.
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
XIncludeFile "../../src/Map/MapValidate.pbi"
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
XIncludeFile "../unit/wall_test_support.pbi"

#INT_FNV_Offset = -3750763034362895579
#INT_FNV_Prime  = 1099511628211
#INT_HeadingAlt = $20000000

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

Global *gIntA_Spans = ?WallGold_A_Spans
Global *gIntB_Spans = ?WallGold_B_Spans
Global *gIntE_Spans = ?WallGold_E_Spans
Global *gIntC_Spans = ?WallGold_C_Spans
Global *gIntA_Samples = ?WallGold_A_SampleX
Global *gIntB_Samples = ?WallGold_B_SampleX
Global *gIntE_Samples = ?WallGold_E_SampleX
Global *gIntC_Samples = ?WallGold_C_SampleX
Global *gIntA_Rows = ?WallGold_A_SampleRows
Global *gIntB_Rows = ?WallGold_B_SampleRows
Global *gIntE_Rows = ?WallGold_E_SampleRows
Global *gIntC_Rows = ?WallGold_C_SampleRows
Global *gIntA_Hash = ?WallGold_A_Hash
Global *gIntB_Hash = ?WallGold_B_Hash
Global *gIntE_Hash = ?WallGold_E_Hash
Global *gIntC_Hash = ?WallGold_C_Hash

; ---------------------------------------------------------------------------
; Harness and independent fingerprint helpers
; ---------------------------------------------------------------------------

Procedure BeginIntCase(Id.s, Title.s)
  gCaseCount + 1
  PrintN("")
  PrintN("[" + Id + "] " + Title)
EndProcedure

Procedure IntCheck(Ok.i, Description.s)
  gAssertionCount + 1
  If Ok
    PrintN("  PASS: " + Description)
  Else
    PrintN("  FAIL: " + Description)
    gFailureCount + 1
  EndIf
EndProcedure

Procedure.q IntFnvByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #INT_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q IntFnvFrame(*Buffer.FrameBuffer)
  Protected hash.q = #INT_FNV_Offset
  Protected byteIndex.i

  For byteIndex = 0 To #WALLDRAW_PixelCount - 1
    hash = IntFnvByte(hash, PeekA(*Buffer\Pixels + byteIndex))
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q IntFnvUniform(PaletteIndex.i)
  Protected hash.q = #INT_FNV_Offset
  Protected byteIndex.i

  For byteIndex = 0 To #WALLDRAW_PixelCount - 1
    hash = IntFnvByte(hash, PaletteIndex)
  Next
  ProcedureReturn hash
EndProcedure

Procedure.i IntHexCanonical(Text.s)
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
; Generated fixture accessors (numeric synthetic only)
; ---------------------------------------------------------------------------

Procedure.i IntSceneSpanCount(SceneId.s)
  If SceneId = "A"
    ProcedureReturn #WALLGOLD_A_SpanCount
  ElseIf SceneId = "B"
    ProcedureReturn #WALLGOLD_B_SpanCount
  ElseIf SceneId = "E"
    ProcedureReturn #WALLGOLD_E_SpanCount
  ElseIf SceneId = "C"
    ProcedureReturn #WALLGOLD_C_SpanCount
  EndIf
  ProcedureReturn -1
EndProcedure

Procedure.i IntSpanGet(SceneId.s, SpanIndex.l, FieldIndex.l, *Value.Long)
  Protected *base.Long

  If SpanIndex < 0 Or SpanIndex >= IntSceneSpanCount(SceneId)
    ProcedureReturn #False
  EndIf
  If FieldIndex < 0 Or FieldIndex >= #WALLGOLD_SpanFieldCount
    ProcedureReturn #False
  EndIf
  If SceneId = "A"
    *base = *gIntA_Spans
  ElseIf SceneId = "B"
    *base = *gIntB_Spans
  ElseIf SceneId = "E"
    *base = *gIntE_Spans
  ElseIf SceneId = "C"
    *base = *gIntC_Spans
  Else
    ProcedureReturn #False
  EndIf
  If *base = 0
    ProcedureReturn #False
  EndIf
  *Value\l = PeekL(*base + (SpanIndex * #WALLGOLD_SpanFieldCount + FieldIndex) * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

Procedure.i IntSceneSampleCount(SceneId.s)
  If SceneId = "A"
    ProcedureReturn #WALLGOLD_A_SampleCount
  ElseIf SceneId = "B"
    ProcedureReturn #WALLGOLD_B_SampleCount
  ElseIf SceneId = "E"
    ProcedureReturn #WALLGOLD_E_SampleCount
  ElseIf SceneId = "C"
    ProcedureReturn #WALLGOLD_C_SampleCount
  EndIf
  ProcedureReturn -1
EndProcedure

Procedure.i IntSampleXGet(SceneId.s, SampleIndex.l, *X.Long)
  Protected *base.Long
  Protected count.l = IntSceneSampleCount(SceneId)

  If SceneId = "A"
    *base = *gIntA_Samples
  ElseIf SceneId = "B"
    *base = *gIntB_Samples
  ElseIf SceneId = "E"
    *base = *gIntE_Samples
  ElseIf SceneId = "C"
    *base = *gIntC_Samples
  Else
    ProcedureReturn #False
  EndIf
  If *base = 0 Or SampleIndex < 0 Or SampleIndex >= count
    ProcedureReturn #False
  EndIf
  *X\l = PeekL(*base + SampleIndex * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

Procedure.i IntSampleIndexForColumn(SceneId.s, Column.l, *SampleIndex.Long)
  Protected count.l = IntSceneSampleCount(SceneId)
  Protected i.i
  Protected sampleX.l = 0

  If count < 0
    ProcedureReturn #False
  EndIf
  For i = 0 To count - 1
    If IntSampleXGet(SceneId, i, @sampleX) = #False
      ProcedureReturn #False
    EndIf
    If sampleX = Column
      *SampleIndex\l = i
      ProcedureReturn #True
    EndIf
  Next
  ProcedureReturn #False
EndProcedure

Procedure.i IntSampleRowGet(SceneId.s, SampleIndex.l, Row.l, *Value.Long)
  Protected *base.Byte
  Protected count.l = IntSceneSampleCount(SceneId)

  If SceneId = "A"
    *base = *gIntA_Rows
  ElseIf SceneId = "B"
    *base = *gIntB_Rows
  ElseIf SceneId = "E"
    *base = *gIntE_Rows
  ElseIf SceneId = "C"
    *base = *gIntC_Rows
  Else
    ProcedureReturn #False
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

Procedure.q IntSceneHash(SceneId.s)
  If SceneId = "A"
    ProcedureReturn PeekQ(*gIntA_Hash)
  ElseIf SceneId = "B"
    ProcedureReturn PeekQ(*gIntB_Hash)
  ElseIf SceneId = "E"
    ProcedureReturn PeekQ(*gIntE_Hash)
  ElseIf SceneId = "C"
    ProcedureReturn PeekQ(*gIntC_Hash)
  EndIf
  ProcedureReturn -1
EndProcedure

; ---------------------------------------------------------------------------
; Independent synthetic maps A/B/E one-sector and C occluded portal
; ---------------------------------------------------------------------------

Procedure.i IntBuildSceneMap(SceneId.s, *Level.MapLevel)
  Protected Dim sectors.TestSectorSpec(1)
  Protected Dim lines.TestLineSpec(1)
  Protected Dim sides.TestSideSpec(2)
  Protected Dim vertices.TestVertexSpec(3)
  Protected Dim segs.TestSegSpec(1)
  Protected Dim subs.TestSubSpec(0)
  Protected Dim nodes.TestNodeSpec(0)
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

      vertices(0)\X = 100
      vertices(0)\Y = 64
      vertices(1)\X = 100
      vertices(1)\Y = -64
      vertices(2)\X = 300
      vertices(2)\Y = 32767
      vertices(3)\X = 300
      vertices(3)\Y = -32767
      vertexCount = 4

      segs(0)\RawAngle = 49152
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

; Builds map + explicit camera/viewz + classic projection + M3-04 visibility.
Procedure.i IntPrepareScene(SceneId.s, *Level.MapLevel, *View.WallView,
                            *Projection.Projection,
                            *Visibility.WallVisibilityResult)
  If IntBuildSceneMap(SceneId, *Level) = #False
    ProcedureReturn #False
  EndIf
  If WallViewSetMapUnits(*View, 0, 0, 0, 0) = #False
    ProcedureReturn #False
  EndIf
  If WallViewIsValid(*View) = 0 Or ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallVisibilityBuild(*Level, @*View\Camera, *Projection,
                                      0, 0, *Visibility)
EndProcedure

; ---------------------------------------------------------------------------
; Span/plan/row helpers
; ---------------------------------------------------------------------------

Procedure.i IntReadSpan(*Visibility.WallVisibilityResult, SpanIndex.l,
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

Procedure.i IntProjectSpan(*Level.MapLevel, *View.WallView,
                           *Projection.Projection, *Span.WallSpan,
                           *Plan.WallSpanPlan)
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected viewZ.l = 0

  If WallViewGet(*View, @cameraX, @cameraY, @heading, @viewZ) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallProjectSpanChecked(*Level, 0, 0, *Projection,
                                         cameraX, cameraY, heading, viewZ,
                                         *Span\Subsector, *Span, *Plan)
EndProcedure

Procedure.i IntCompareSpansGold(SceneId.s, *Visibility.WallVisibilityResult)
  Protected expected.l = 0
  Protected actual.l = 0
  Protected count.l = IntSceneSpanCount(SceneId)
  Protected span.WallSpan
  Protected spanIndex.i
  Protected fieldIndex.i
  Protected mismatch.i = 0
  Protected compared.i = 0

  If count < 0 Or WallVisibilityCount(*Visibility) <> count
    ProcedureReturn #False
  EndIf
  For spanIndex = 0 To count - 1
    If IntReadSpan(*Visibility, spanIndex, @span) = #False
      ProcedureReturn #False
    EndIf
    For fieldIndex = 0 To #WALLGOLD_SpanFieldCount - 1
      If IntSpanGet(SceneId, spanIndex, fieldIndex, @expected) = #False
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
  ProcedureReturn Bool(mismatch = 0 And
                       compared = count * #WALLGOLD_SpanFieldCount)
EndProcedure

Procedure.i IntCompareGoldSampleColumn(SceneId.s, Column.l,
                                       *Buffer.FrameBuffer)
  Protected sampleIndex.l = 0
  Protected expected.l = 0
  Protected actual.i
  Protected row.i
  Protected mismatch.i = 0

  If IntSampleIndexForColumn(SceneId, Column, @sampleIndex) = #False
    ProcedureReturn #False
  EndIf
  For row = 0 To #WALLGOLD_SampleRowBytes - 1
    If IntSampleRowGet(SceneId, sampleIndex, row, @expected) = #False
      ProcedureReturn #False
    EndIf
    actual = FrameBufferGetPixel(*Buffer, Column, row)
    If actual < 0
      ProcedureReturn #False
    EndIf
    If actual <> expected
      mismatch + 1
    EndIf
  Next
  ProcedureReturn Bool(mismatch = 0)
EndProcedure

Procedure.i IntVerifyAllGoldColumns(SceneId.s, *Buffer.FrameBuffer)
  Protected count.l = IntSceneSampleCount(SceneId)
  Protected sampleX.l = 0
  Protected i.i
  Protected mismatch.i = 0

  If count < 0
    ProcedureReturn #False
  EndIf
  For i = 0 To count - 1
    If IntSampleXGet(SceneId, i, @sampleX) = #False
      ProcedureReturn #False
    EndIf
    If IntCompareGoldSampleColumn(SceneId, sampleX, *Buffer) = #False
      mismatch + 1
    EndIf
  Next
  ProcedureReturn Bool(mismatch = 0)
EndProcedure

; Raw map seg field mutation for corrupt-reference/lifetime probes.
Procedure.i IntPokeSegField(*Level.MapLevel, SegIndex.l, Field.l, Value.l)
  Protected *seg.MapSeg

  If *Level = 0 Or MapLevelIsReady(*Level) = 0
    ProcedureReturn #False
  EndIf
  If SegIndex < 0 Or SegIndex >= *Level\Segs\Count Or Field < 0 Or Field > 2
    ProcedureReturn #False
  EndIf
  *seg = *Level\Segs\Items + SegIndex * SizeOf(MapSeg)
  If Field = 0
    *seg\V1 = Value
  ElseIf Field = 1
    *seg\V2 = Value
  Else
    *seg\Angle = Value
  EndIf
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; WI01 - minimal single-sector synthetic walls, one-column and wide segments
; ---------------------------------------------------------------------------

Procedure TestWI01()
  BeginIntCase("WI01", "Minimal one-sector A/B/E synthetic wall frames")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected visibilityAgain.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected resultRepeat.WallRenderResult
  Protected prepareOk.i
  Protected againOk.i
  Protected projectOk.i
  Protected renderOk.i
  Protected repeatOk.i
  Protected hashA.q
  Protected hashB.q
  Protected hashRepeat.q
  Protected hashE.q
  Protected backgroundHash.q
  Protected expectedA.q
  Protected expectedB.q
  Protected expectedE.q
  Protected spanCount.l
  Protected columns.l
  Protected middle.l
  Protected pixel.i

  ; A. One-column scene: exact synthetic ten-lump MapLevel through one-sided wall.
  prepareOk = IntPrepareScene("A", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "A one-column synthetic MapLevel builds/validates/prepares")
  spanCount = WallVisibilityCount(@visibility)
  IntCheck(Bool(spanCount = 1), "A one-column visibility emits exactly one span")
  IntCheck(Bool(IntCompareSpansGold("A", @visibility) <> 0),
        "A ordered span IDs/interval equal independent generated record [1,1]")
  IntCheck(Bool(IntReadSpan(@visibility, 0, @span) <> 0), "A span readable")
  IntCheck(Bool(span\FirstX = 1 And span\LastX = 1 And span\Kind = #WALL_KIND_SOLID),
        "A measured span is inclusive one-column SOLID [1,1]")
  projectOk = IntProjectSpan(@map, @view, @projection, @span, @plan)
  IntCheck(Bool(projectOk <> 0), "A one-column plan projection succeeds")
  IntCheck(Bool(plan\FirstX = 1 And plan\LastX = 1 And plan\Ready = 1),
        "A plan publishes the same one-column interval and ready state")
  IntCheck(Bool(plan\MiddleTier = 1), "A one-sided middle slot selects the debug middle tier")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  IntCheck(Bool(renderOk <> 0), "A expected-visible frame draws nonzero wall pixels")
  IntCheck(Bool(WallRenderResultIsValid(@result) <> 0), "A render result valid")
  IntCheck(Bool(result\SpanCount = 1 And result\ProcessedColumns = 1 And
             result\DrawnPixels > 0),
        "A bounding controls: one span, one processed column, concrete nonzero pixels")
  IntCheck(Bool(result\MiddlePixels = result\DrawnPixels And result\MiddlePixels > 0),
        "A painted pixels are genuine middle wall bytes, not background-only false PASS")
  hashA = result\Hash
  expectedA = IntSceneHash("A")
  IntCheck(Bool(hashA = expectedA), "A full-plane FNV equals independent generated golden hash")
  IntCheck(Bool(WallRenderGetHashText(@result) = "2090BE09430C7B25"),
        "A hash text is exact generated 2090BE09430C7B25")
  backgroundHash = IntFnvUniform(#WALLDRAW_BackgroundIndex)
  IntCheck(Bool(hashA <> backgroundHash), "A frame hash differs from uniform background plane")
  pixel = FrameBufferGetPixel(@target, 0, 100)
  IntCheck(Bool(pixel = #WALLDRAW_BackgroundIndex), "A column0 outside tiny span remains background")
  pixel = FrameBufferGetPixel(@target, 2, 100)
  IntCheck(Bool(pixel = #WALLDRAW_BackgroundIndex), "A column2 just right of span remains background")
  IntCheck(Bool(IntVerifyAllGoldColumns("A", @target) <> 0),
        "A all five generated sample columns/200 rows agree independently (bounds x=1/y=0..199)")
  WallVisibilityReset(@visibilityAgain)
  againOk = WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0, @visibilityAgain)
  IntCheck(Bool(againOk <> 0), "A repeated visibility Build succeeds")
  IntCheck(Bool(IntCompareSpansGold("A", @visibilityAgain) <> 0),
        "A repeated Build reproduces identical span order/interval")
  repeatOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibilityAgain,
                             @target, @resultRepeat, #True)
  IntCheck(Bool(repeatOk <> 0), "A repeated frame render succeeds")
  hashRepeat = resultRepeat\Hash
  IntCheck(Bool(hashRepeat = hashA And hashRepeat = expectedA),
        "A repeated-build frame identity equals first and independent golden hash")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  WallVisibilityReset(@visibilityAgain)
  WallRenderResultReset(@result)
  WallRenderResultReset(@resultRepeat)

  ; B. Wide vertical one-sided segment x=58..262; explicit two-segment bounds.
  prepareOk = IntPrepareScene("B", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "B wide synthetic one-sector map prepares")
  spanCount = WallVisibilityCount(@visibility)
  IntCheck(Bool(spanCount = 1), "B wide visibility emits exactly one clipped span")
  IntCheck(Bool(IntCompareSpansGold("B", @visibility) <> 0),
        "B ordered span IDs/interval equal independent generated record")
  IntCheck(Bool(IntReadSpan(@visibility, 0, @span) <> 0), "B span readable")
  IntCheck(Bool(span\FirstX = 58 And span\LastX = 262),
        "B measured compiled span interval is exactly inclusive [58,262]")
  projectOk = IntProjectSpan(@map, @view, @projection, @span, @plan)
  IntCheck(Bool(projectOk <> 0), "B wide spanned plan projection succeeds")
  IntCheck(Bool(plan\MiddleTier = 1 And plan\Scale1 = 104857 And plan\Scale2 = 104857 And
             plan\ScaleStep = 0),
        "B plan reproduces independent fixed scale 104857/104857/0")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  IntCheck(Bool(renderOk <> 0), "B wide expected-visible frame draws nonzero wall pixels")
  IntCheck(Bool(result\SpanCount = 1 And result\ProcessedColumns = 205),
        "B bounding controls: generated 58..262 span width is exactly 205 columns")
  IntCheck(Bool(result\MiddlePixels = result\DrawnPixels And result\MiddlePixels > 0),
        "B painted bytes are genuine one-sided middle wall, not background-only")
  hashB = result\Hash
  expectedB = IntSceneHash("B")
  IntCheck(Bool(hashB = expectedB), "B full-plane FNV equals independent generated golden hash")
  IntCheck(Bool(WallRenderGetHashText(@result) = "72685823901A3A25"),
        "B hash text is exact generated 72685823901A3A25")
  pixel = FrameBufferGetPixel(@target, 57, 100)
  IntCheck(Bool(pixel = #WALLDRAW_BackgroundIndex), "B column57 just outside left bound is background")
  pixel = FrameBufferGetPixel(@target, 263, 100)
  IntCheck(Bool(pixel = #WALLDRAW_BackgroundIndex), "B column263 just outside right bound is background")
  IntCheck(Bool(IntVerifyAllGoldColumns("B", @target) <> 0),
        "B all five generated sample columns/200 rows agree independently")
  WallVisibilityReset(@visibilityAgain)
  againOk = WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0, @visibilityAgain)
  IntCheck(Bool(againOk <> 0), "B repeated visibility Build succeeds")
  IntCheck(Bool(IntCompareSpansGold("B", @visibilityAgain) <> 0),
        "B repeated Build reproduces identical clipped span chronology")
  repeatOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibilityAgain,
                             @target, @resultRepeat, #True)
  IntCheck(Bool(repeatOk <> 0), "B repeated frame render succeeds")
  hashRepeat = resultRepeat\Hash
  IntCheck(Bool(hashRepeat = hashB And hashRepeat = expectedB),
        "B repeated-build frame identity equals first and independent golden hash")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  WallVisibilityReset(@visibilityAgain)

  ; E. Full-width screen-filling one-sided segment; 320 processed columns.
  prepareOk = IntPrepareScene("E", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "E full-width synthetic one-sector map prepares")
  IntCheck(Bool(IntCompareSpansGold("E", @visibility) <> 0),
        "E ordered span interval equal independent generated screen-filling record")
  IntCheck(Bool(IntReadSpan(@visibility, 0, @span) <> 0), "E span readable")
  IntCheck(Bool(span\FirstX = 0 And span\LastX = 319), "E span is inclusive full width 0..319")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  IntCheck(Bool(renderOk <> 0), "E full-width expected-visible frame renders")
  IntCheck(Bool(result\ProcessedColumns = 320 And result\DrawnPixels > 0),
        "E bounding controls process all 320 columns with nonzero pixels")
  hashE = result\Hash
  expectedE = IntSceneHash("E")
  IntCheck(Bool(hashE = expectedE), "E full-plane FNV equals independent generated golden hash")
  IntCheck(Bool(WallRenderGetHashText(@result) = "B226A1443E08AB25"),
        "E hash text is exact generated B226A1443E08AB25")
  IntCheck(Bool(IntVerifyAllGoldColumns("E", @target) <> 0),
        "E all three generated sample columns/200 rows agree independently")

  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  WallVisibilityReset(@visibilityAgain)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

; ---------------------------------------------------------------------------
; WI02 - two-sided occluded C room plus tiny/full-span y-boundary checks
; ---------------------------------------------------------------------------

Procedure TestWI02()
  BeginIntCase("WI02", "Two-sided occluded portal room, ordering, boundaries")
  Protected map.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected span.WallSpan
  Protected target.FrameBuffer
  Protected result.WallRenderResult
  Protected prepareOk.i
  Protected renderOk.i
  Protected count.l
  Protected hash.q
  Protected expected.q
  Protected span0Seg.l = -1
  Protected span1Seg.l = -1
  Protected span2Seg.l = -1
  Protected span0First.l = -1
  Protected span2Last.l = -1
  Protected lowerAtNear.l = 0
  Protected middleAtNear.l = 0
  Protected backgroundAtFar.l = 0
  Protected upperAtFar.l = 0
  Protected lowerAtFar.l = 0
  Protected row.i
  Protected pixel.i

  ; C. Near front SOLID wall and farther two-sided upper/lower portal fragments.
  prepareOk = IntPrepareScene("C", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "C fully synthetic occluded portal room prepares")
  count = WallVisibilityCount(@visibility)
  IntCheck(Bool(count = 3), "C publishes exactly three ordered spans, no hidden merge")
  IntCheck(Bool(IntCompareSpansGold("C", @visibility) <> 0),
        "C all ordered WallSpan IDs/X intervals equal independent M3-04 generated record")
  IntCheck(Bool(IntReadSpan(@visibility, 0, @span) <> 0), "C ordered slot0 readable")
  span0Seg = span\Seg
  span0First = span\FirstX
  IntCheck(Bool(span\Kind = #WALL_KIND_SOLID And span\FirstX = 58 And span\LastX = 262),
        "C slot0 is near SOLID seg0 inclusive [58,262] in source append order")
  IntCheck(Bool(IntReadSpan(@visibility, 1, @span) <> 0), "C ordered slot1 readable")
  span1Seg = span\Seg
  IntCheck(Bool(span\Kind = #WALL_KIND_PASS And span\FirstX = 0 And span\LastX = 57),
        "C slot1 is first far PASS clipped fragment [0,57] immediately after near span")
  IntCheck(Bool(IntReadSpan(@visibility, 2, @span) <> 0), "C ordered slot2 readable")
  span2Seg = span\Seg
  span2Last = span\LastX
  IntCheck(Bool(span\Kind = #WALL_KIND_PASS And span\FirstX = 263 And span\LastX = 319),
        "C slot2 is second far PASS clipped fragment [263,319], no sort/deduplication")
  IntCheck(Bool(span0Seg = 0 And span1Seg = 1 And span2Seg = 1 And
             span0First = 58 And span2Last = 319),
        "C segment identities/interval chronology equal generated order")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  IntCheck(Bool(renderOk <> 0), "C occluded near+far frame renders concrete pixels")
  IntCheck(Bool(WallRenderResultIsValid(@result) <> 0), "C render result valid")
  IntCheck(Bool(result\SpanCount = 3 And result\SegmentCount = 3),
        "C result consumes all three generated spans without filtering/dedup")
  IntCheck(Bool(result\ProcessedColumns = 320),
        "C near205+far58+far57 partitioned ranges cover all 320 columns once")
  IntCheck(Bool(result\MiddlePixels > 0 And result\UpperPixels > 0 And
             result\LowerPixels > 0),
        "C paints near middle plus farther upper/lower concrete tier pixels")
  hash = result\Hash
  expected = IntSceneHash("C")
  IntCheck(Bool(hash = expected), "C occluded frame FNV equals independent generated golden hash")
  IntCheck(Bool(WallRenderGetHashText(@result) = "4D32B97402CD3925"),
        "C hash text is exact generated 4D32B97402CD3925")

  ; Occlusion crossing at column160: near middle must dominate there, no lower paint-through.
  lowerAtNear = 0
  middleAtNear = 0
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 160, row)
    If pixel = #WALLDRAW_LowerIndex
      lowerAtNear + 1
    ElseIf pixel = #WALLDRAW_MiddleIndex
      middleAtNear + 1
    EndIf
  Next
  IntCheck(Bool(middleAtNear > 0), "C column160 inside near wall paints genuine middle bytes")
  IntCheck(Bool(lowerAtNear = 0),
        "C column160 has no farther lower paint-through; far wall does not paint over near wall")
  IntCheck(Bool(IntCompareGoldSampleColumn("C", 160, @target) <> 0),
        "C column160 all 200 rows equal independent oracle under occlusion crossing")

  ; Far portal opening stays background until its valid upper/lower tiers fill.
  backgroundAtFar = 0
  upperAtFar = 0
  lowerAtFar = 0
  For row = 0 To 199
    pixel = FrameBufferGetPixel(@target, 300, row)
    If pixel = #WALLDRAW_UpperIndex
      upperAtFar + 1
    ElseIf pixel = #WALLDRAW_LowerIndex
      lowerAtFar + 1
    ElseIf pixel = #WALLDRAW_BackgroundIndex
      backgroundAtFar + 1
    EndIf
  Next
  IntCheck(Bool(upperAtFar > 0 And lowerAtFar > 0),
        "C farther clipped column300 fills only valid upper/lower tier pixels")
  IntCheck(Bool(backgroundAtFar > 0),
        "C portal opening between upper/lower tiers remains background")
  IntCheck(Bool(IntVerifyAllGoldColumns("C", @target) <> 0),
        "C all nine generated columns/200 rows agree independently across near/far tiers")

  ; A tiny one-column boundary y=0/y=199 independently compare.
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  prepareOk = IntPrepareScene("A", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "A tiny wall prepares inside WI02 boundary block")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  IntCheck(Bool(renderOk <> 0), "A tiny wall frame renders y-boundary plane")
  IntCheck(Bool(IntCompareGoldSampleColumn("A", 1, @target) <> 0),
        "A tiny span column1 rows y=0..199 agree independently at both boundaries")
  IntCheck(Bool(FrameBufferGetPixel(@target, 1, 0) >= 0 And
             FrameBufferGetPixel(@target, 1, 199) >= 0),
        "A boundary rows row0 and row199 are safely readable on canonical plane")

  ; E full-width segment boundary rows at both top and bottom.
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  prepareOk = IntPrepareScene("E", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "E full width prepares inside y-boundary block")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @result, #True)
  IntCheck(Bool(renderOk <> 0), "E full-width frame renders without out-of-frame failure")
  IntCheck(Bool(result\ProcessedColumns = 320 And result\OutOfFrameColumns = 0),
        "E full-width y-boundaries stay inside 0..199 with zero out-of-frame columns")
  IntCheck(Bool(IntCompareGoldSampleColumn("E", 160, @target) <> 0),
        "E center full-span column160 rows0..199 agree independently")
  IntCheck(Bool(FrameBufferGetPixel(@target, 160, 0) >= 0 And
             FrameBufferGetPixel(@target, 160, 199) >= 0),
        "E boundary row0/199 center pixels remain safely readable, no masked overflow")

  FrameBufferReset(@target)
  WallRenderResultReset(@result)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  ProjectionReset(@projection)
  WallViewReset(@view)
EndProcedure

; ---------------------------------------------------------------------------
; WI03 - errors, caps, recovery, A->B->A cycles and noncommutative hashes
; ---------------------------------------------------------------------------

Procedure TestWI03()
  BeginIntCase("WI03", "Errors, work caps, lifetime cycles and justified hashes")
  Protected map.MapLevel
  Protected view.WallView
  Protected invalidView.WallView
  Protected projection.Projection
  Protected invalidProjection.Projection
  Protected visibility.WallVisibilityResult
  Protected visibilityAgain.WallVisibilityResult
  Protected blankVisibility.WallVisibilityResult
  Protected span.WallSpan
  Protected plan.WallSpanPlan
  Protected target.FrameBuffer
  Protected resultA.WallRenderResult
  Protected resultB.WallRenderResult
  Protected resultHeading.WallRenderResult
  Protected resultRecover.WallRenderResult
  Protected resultAgainA.WallRenderResult
  Protected resultBad.WallRenderResult
  Protected prepareOk.i
  Protected buildOk.i
  Protected buildBadOk.i
  Protected buildGoodOk.i
  Protected mutateOk.i
  Protected renderOk.i
  Protected failRenderOk.i
  Protected budgetResultOk.i
  Protected headerFailOk.i
  Protected invalidViewFailOk.i
  Protected invalidProjFailOk.i
  Protected pixelCount.l = -1
  Protected directRange.i
  Protected invalidPixel.i
  Protected oldTargetHash.q
  Protected oldResultHash.q
  Protected hashA.q
  Protected hashB.q
  Protected hashAlt.q
  Protected hashAAgain.q
  Protected expectedA.q
  Protected expectedB.q
  Protected uniformBackground.q
  Protected hashBaseline.q
  Protected textAlt.s
  Protected errorText.s

  ; Malformed map reference: corrupt C seg v2, Build rejects without stale owners.
  prepareOk = IntPrepareScene("C", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "C synthetic occluded map prepares for malformed probe")
  mutateOk = IntPokeSegField(@map, 1, 1, 99)
  IntCheck(Bool(mutateOk <> 0), "owned synthetic C seg1 v2 mutated to corrupt vertex 99")
  buildBadOk = Bool(WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0,
                                        @visibilityAgain) = 0)
  IntCheck(Bool(buildBadOk <> 0), "corrupt seg reference makes M3-04 visibility Build fail")
  errorText = WallVisibilityLastError()
  IntCheck(Bool(FindString(errorText, "out of range") > 0 Or
             FindString(errorText, "vertex") > 0),
        "malformed map reference diagnostic names vertex bounds")
  IntCheck(Bool(MapLevelIsReady(@map) <> 0 And WallViewIsValid(@view) <> 0 And
             ProjectionIsValid(@projection) <> 0),
        "failed Build leaves map/camera/projection owners intact for recovery")
  IntCheck(Bool(WallVisibilityCount(@visibilityAgain) = 0),
        "failed transactional Build leaves reusable zero-count result, no stale spans")
  mutateOk = IntPokeSegField(@map, 1, 1, 3)
  IntCheck(Bool(mutateOk <> 0), "synthetic seg v2 restored to valid vertex index3")
  buildGoodOk = WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0,
                                    @visibilityAgain)
  IntCheck(Bool(buildGoodOk <> 0), "restored map geometry allows successful Build recovery")
  IntCheck(Bool(IntCompareSpansGold("C", @visibilityAgain) <> 0),
        "recovered visibility reproduces identical generated ordered spans")
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  WallVisibilityReset(@visibilityAgain)
  ProjectionReset(@projection)
  WallViewReset(@view)

  ; Synthetic A->B->A cycles with caller-owned target reuse/reset/reload.
  prepareOk = IntPrepareScene("A", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "A first synthetic load prepares")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultA, #True)
  IntCheck(Bool(renderOk <> 0), "A first frame renders into zero target")
  hashA = resultA\Hash
  expectedA = IntSceneHash("A")
  IntCheck(Bool(hashA = expectedA), "A first frame equals independent generated A FNV")
  IntCheck(Bool(FrameBufferReset(@target) <> 0), "A caller target released before B")
  IntCheck(Bool(FrameBufferGetPixel(@target, 0, 0) = -1),
        "released A plane pixel access is safely rejected, lifetime honored")
  prepareOk = IntPrepareScene("B", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "B synthetic load after A reset prepares")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultB, #True)
  IntCheck(Bool(renderOk <> 0), "B frame renders into released/reused target")
  hashB = resultB\Hash
  expectedB = IntSceneHash("B")
  IntCheck(Bool(hashB = expectedB), "B cycle frame equals independent generated B FNV")
  IntCheck(Bool(FrameBufferReset(@target) <> 0), "B caller target released before returning A")
  prepareOk = IntPrepareScene("A", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "A reload after B reset/load cycle prepares")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultAgainA, #True)
  IntCheck(Bool(renderOk <> 0), "second A frame renders into freed/reused caller buffer")
  hashAAgain = resultAgainA\Hash
  IntCheck(Bool(hashAAgain = hashA And hashAAgain = expectedA),
        "A->B->A cycle closes with identical A frame hash and counters ownership")
  uniformBackground = IntFnvUniform(#WALLDRAW_BackgroundIndex)
  IntCheck(Bool(hashAAgain <> uniformBackground),
        "A repeated content hash is not the uniform background false PASS fingerprint")

  ; Noncommutative heading hash on B under explicit ANG45 camera.
  prepareOk = IntPrepareScene("B", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "B synthetic load prepares for justified heading hash")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultB, #True)
  IntCheck(Bool(renderOk <> 0), "B baseline renders for noncommutative hash comparison")
  hashBaseline = resultB\Hash
  IntCheck(Bool(hashBaseline = expectedB), "B baseline hash equals independent generated B FNV")
  IntCheck(Bool(WallViewSetMapUnits(@view, 0, 0, #INT_HeadingAlt, 0) <> 0),
        "B camera heading changed to explicit ANG45")
  WallVisibilityReset(@visibility)
  buildOk = WallVisibilityBuild(@map, @view\Camera, @projection, 0, 0, @visibility)
  IntCheck(Bool(buildOk <> 0), "B visibility rebuild succeeds under ANG45 clipping")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultHeading, #True)
  IntCheck(Bool(renderOk <> 0), "ANG45 heading frame renders concrete altered wall pixels")
  hashAlt = resultHeading\Hash
  textAlt = WallRenderGetHashText(@resultHeading)
  IntCheck(Bool(hashAlt <> hashBaseline And hashAlt <> 0),
        "ANG45 heading produces a differing justified frame hash, not baseline")
  IntCheck(Bool(IntHexCanonical(textAlt) <> 0),
        "ANG45 altered hash text remains canonical 16 uppercase hex")

  ; Invalid/coincident arithmetic frame recovery: camera on B seg v1.
  prepareOk = IntPrepareScene("B", @map, @view, @projection, @visibility)
  IntCheck(Bool(prepareOk <> 0), "B synthetic load prepares for coincident division probe")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultRecover, #True)
  IntCheck(Bool(renderOk <> 0), "B valid baseline builds before coincident corruption")
  oldTargetHash = resultRecover\Hash
  oldResultHash = IntFnvFrame(@target)
  IntCheck(Bool(oldTargetHash = expectedB And oldResultHash = expectedB),
        "B baseline target/result fingerprints equal independent generated B")
  IntCheck(Bool(WallViewSetFixed(@view, 100 * #FRACUNIT, 64 * #FRACUNIT, 0,
                                #WALLVIEW_ViewHeightFixed) <> 0),
        "camera moved exactly onto synthetic seg v1 (100,64) for coincident probe")
  failRenderOk = Bool(WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                                     @target, @resultB, #True) = 0)
  IntCheck(Bool(failRenderOk <> 0), "coincident seg-v1/camera hyp transaction is rejected")
  errorText = WallRenderLastError()
  IntCheck(Bool(FindString(errorText, "coincides") > 0),
        "near-zero division diagnostic names the coincident viewpoint/seg-v1 edge")
  IntCheck(Bool(IntFnvFrame(@target) = oldResultHash),
        "coincident failure leaves previous caller frame byte-for-byte unchanged")
  IntCheck(Bool(WallViewSetFixed(@view, 0, 0, 0, #WALLVIEW_ViewHeightFixed) <> 0),
        "camera origin restored after coincident negative probe")
  renderOk = WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                             @target, @resultRecover, #True)
  IntCheck(Bool(renderOk <> 0), "restored checked camera allows transaction recovery")
  IntCheck(Bool(resultRecover\Hash = expectedB And IntFnvFrame(@target) = expectedB),
        "recovery repaint reproduces the prior independent B frame hash")

  ; Invalid viewz conversion on a separate unready view instance.
  IntCheck(Bool(WallViewReset(@invalidView) <> 0), "separate view reset for invalid viewz")
  invalidViewFailOk = Bool(WallViewSetMapUnits(@invalidView, 0, 0, 0, 32732) = 0)
  IntCheck(Bool(invalidViewFailOk <> 0), "floor map unit 32732 + VIEWHEIGHT overflows and is rejected")
  errorText = WallViewLastError()
  IntCheck(Bool(FindString(errorText, "overflow") > 0),
        "invalid viewz diagnostic names signed fixed overflow")

  ; Unready projection owner on a separate projection and already valid camera.
  IntCheck(Bool(WallVisibilityCount(@visibility) = 1), "B recovery visibility retains one span")
  IntCheck(Bool(IntReadSpan(@visibility, 0, @span) <> 0), "B visible span readable for projection fault")
  IntCheck(Bool(ProjectionReset(@invalidProjection) <> 0), "separate projection reset")
  IntCheck(Bool(WallViewSetMapUnits(@view, 0, 0, 0, 0) <> 0), "main camera re-readied for projection fault")
  IntCheck(Bool(WallSpanPlanReset(@plan) <> 0), "plan slot reset before unready projection")
  invalidProjFailOk = Bool(IntProjectSpan(@map, @view, @invalidProjection, @span, @plan) = 0)
  IntCheck(Bool(invalidProjFailOk <> 0), "unready projection rejects span projection")
  errorText = WallProjectLastError()
  IntCheck(Bool(FindString(errorText, "projection") > 0),
        "unready projection diagnostic names the projection precondition")
  IntCheck(Bool(WallSpanPlanIsReady(@plan) = 0),
        "unready projection failure leaves plan unready")

  ; Renderer span budget cap: valid reusable result with corrupt count > MaxSpans.
  IntCheck(Bool(WallVisibilityReset(@visibility) <> 0), "visibility reset before budget probe")
  visibility\Count = #RENDER_MaxSpans + 1
  IntCheck(Bool(WallVisibilityCount(@visibility) = #RENDER_MaxSpans + 1),
        "test-only corrupt reusable visibility count exceeds checked 200,000 span budget")
  budgetResultOk = Bool(WallRenderFrame(@map, @view, @projection, 0, 0, @visibility,
                                       @target, @resultB, #False) = 0)
  IntCheck(Bool(budgetResultOk <> 0), "span count above #RENDER_MaxSpans rejects whole frame")
  errorText = WallRenderLastError()
  IntCheck(Bool(FindString(errorText, "exceeds the renderer budget") > 0),
        "work-cap diagnostic names 200,000 span budget before allocation")
  IntCheck(Bool(IntFnvFrame(@target) = expectedB),
        "span-budget failure leaves prior generated B frame bytes unchanged")
  WallVisibilityReset(@visibility)

  ; Null/unready visibility authority rejects clearly.
  IntCheck(Bool(WallRenderFrame(@map, @view, @projection, 0, 0, @blankVisibility,
                                @target, @resultB, #False) = 0),
        "zero-initialized unready visibility authority rejects frame build")
  errorText = WallRenderLastError()
  IntCheck(Bool(FindString(errorText, "visibility result is not initialized") > 0),
        "null visibility diagnostic names the M3-04 authority precondition")

  ; Invalid pixel coordinates and out-of-frame range do not mutate plane.
  IntCheck(Bool(FrameBufferCreate(@target, 320, 200) <> 0), "caller framebuffer re-created for pixel bounds")
  IntCheck(Bool(FrameBufferClear(@target, #WALLDRAW_BackgroundIndex) <> 0), "pixel-bound plane cleared")
  hashBaseline = IntFnvFrame(@target)
  invalidPixel = FrameBufferGetPixel(@target, -1, 0)
  IntCheck(Bool(invalidPixel = -1), "negative X=-1 pixel access rejects with -1 sentinel")
  invalidPixel = FrameBufferGetPixel(@target, 0, 200)
  IntCheck(Bool(invalidPixel = -1), "Y=200 pixel access rejects with -1 sentinel")
  directRange = WallDrawSolidColumn(@target, 320, 0, 3, #WALLDRAW_MiddleIndex,
                                    @pixelCount)
  IntCheck(Bool(directRange = #WALLDRAW_RangeOutOfFrame And pixelCount = 0),
        "solid column x=320 out-of-range returns empty no-mutation outcome")
  errorText = WallDrawLastError()
  IntCheck(Bool(FindString(errorText, "escaped") > 0),
        "invalid-coordinate drawing diagnostic names escaped 320x200 plane")
  IntCheck(Bool(IntFnvFrame(@target) = hashBaseline),
        "invalid pixel/column probes leave exact background plane bytes unchanged")

  FrameBufferReset(@target)
  WallRenderResultReset(@resultA)
  WallRenderResultReset(@resultB)
  WallRenderResultReset(@resultHeading)
  WallRenderResultReset(@resultRecover)
  WallRenderResultReset(@resultAgainA)
  WallRenderResultReset(@resultBad)
  MapLevelReset(@map)
  WallVisibilityReset(@visibility)
  WallVisibilityReset(@visibilityAgain)
  WallViewReset(@view)
  WallViewReset(@invalidView)
  ProjectionReset(@projection)
  ProjectionReset(@invalidProjection)
EndProcedure

; ---------------------------------------------------------------------------
; Suite driver and measured summary
; ---------------------------------------------------------------------------

Procedure Main()
  TestWI01()
  TestWI02()
  TestWI03()
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
