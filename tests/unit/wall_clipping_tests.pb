; -----------------------------------------------------------------------------
; DoomPB - M3-04 screen projection, wall clipping and online BSP occlusion tests
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Standalone synthetic suite WC01-WC52. Includes M3-01 fixed/BAM/trig core,
; M3-02 geometry primitives, the M2 validated MapLevel/MapValidate composition,
; M3-03 Camera API, M3-04 Projection/ClipSegs/WallVisibility, and a generated
; independent projection fixture derived from pinned tables.c by
; scripts/gen_projection_golden.py. No WAD, graphics, window, commercial data or
; copyrighted payload is used. Test fixtures are original synthetic map records.
;
; Oracles:
;   - projection: every forward/pre/inverse table entry compared to the generated
;     Python C-order fixture plus canonical little-endian FNV-1a64 hashes;
;   - clipping: independent bitmap coverage oracle for tiny widths 8/16/32,
;     including exhaustive and deterministic seeded sequences;
;   - R_AddLine: a separate test-only translation of the original C branch order
;     (angle/backface/FOV/projection/classification) using the same verified
;     geometry primitive and fixture table, never production Clip/Wall helpers;
;   - R_CheckBBox: a separate test-only branch translation for exact reachable
;     boxpos cases; production online traversal is compared against a recursive
;     test-only walker that schedules near clip before far bbox.
; Fingerprints cover published numeric span fields only; no images/coords lists.
;
; Exit code: 0 when every assertion passed, otherwise the failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/Projection.pbi"
XIncludeFile "../../src/Renderer/ClipSegs.pbi"
XIncludeFile "../../src/Renderer/WallVisibility.pbi"
XIncludeFile "../fixtures/m3_projection_golden.pbi"

#TEST_FNV_Offset = -3750763034362895579
#TEST_FNV_Prime = 1099511628211

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

Global gTestCaseFailed.i = 0

; Synthetic ten-lump buffers indexed 1..10 in vanilla canonical order.
Global Dim gMapLump(10)
Global Dim gMapLumpSize.q(10)

; Generated projection fixture addresses and scalar expectations.
Global *gGoldFocalLength = ?ProjectionGoldFocalLength
Global *gGoldClipAngle = ?ProjectionGoldClipAngle
Global *gGoldForwardHash = ?ProjectionGoldForwardHash
Global *gGoldPreHash = ?ProjectionGoldPreHash
Global *gGoldInverseHash = ?ProjectionGoldInverseHash
Global *gGoldThresholdKind = ?ProjectionGoldThresholdKind
Global *gGoldForward = ?ProjectionGoldForward
Global *gGoldPre = ?ProjectionGoldPre
Global *gGoldInverse = ?ProjectionGoldInverse

; Independent bitmap clipping oracle state (tiny widths only).
Global Dim gOracleCovered.l(#CLIP_MaxWidth)
Global Dim gOracleSpanFirst.l(#CLIP_MaxRanges)
Global Dim gOracleSpanLast.l(#CLIP_MaxRanges)
Global Dim gOracleSpanKind.l(#CLIP_MaxRanges)
Global gOracleSpanCount.i = 0

; Test-only recursive online walker output/counters.
Global Dim gRefSpanSubsector.l(4096)
Global Dim gRefSpanSeg.l(4096)
Global Dim gRefSpanFirst.l(4096)
Global Dim gRefSpanLast.l(4096)
Global Dim gRefSpanKind.l(4096)
Global Dim gRefSpanLine.l(4096)
Global Dim gRefSpanSide.l(4096)
Global Dim gRefSpanFront.l(4096)
Global Dim gRefSpanBack.l(4096)
Global gRefSpanCount.i = 0
Global gRefProcessed.l = 0
Global gRefBackface.l = 0
Global gRefFovLeft.l = 0
Global gRefFovRight.l = 0
Global gRefEmpty.l = 0
Global gRefSolid.l = 0
Global gRefPass.l = 0
Global gRefVisitedNodes.l = 0
Global gRefVisitedSubsectors.l = 0
Global gRefBboxTests.l = 0
Global gRefBboxVisible.l = 0
Global gRefBboxOccluded.l = 0
Global gRefBboxUnknown.l = 0
Global gRefOcclusionSkips.l = 0
Global gRefWorkItems.l = 0

; Test-only independent clip posts plus per-column coverage used by the recursive
; online oracle. No production ClipSegs state/calls feed this reference.
Global Dim gRefClipFirst.l(#CLIP_MaxRanges)
Global Dim gRefClipLast.l(#CLIP_MaxRanges)
Global gRefClipCount.i = 0
Global Dim gRefCovered.l(#CLIP_MaxWidth)

; Test-only R_CheckBBox table copy (bytes, 12 rows x 4 columns). Independent of
; the production DataSection; row values are the exact pinned C table.
DataSection
  TestRefCheckCoordData:
  Data.b 3,0,2,1, 3,0,2,0, 3,1,2,0, 0,0,0,0
  Data.b 2,0,2,1, 0,0,0,0, 3,1,3,0, 0,0,0,0
  Data.b 2,0,3,1, 2,1,3,1, 2,1,3,0, 0,0,0,0
EndDataSection
Global *gRefCheckCoordData = ?TestRefCheckCoordData

; Test-only bbox verdict codes, separate from production tri-state constants.
#REFBBOX_Occluded = 0
#REFBBOX_Visible = 1
#REFBBOX_Unknown = 2

Structure TestSectorSpec
  FloorHeight.l
  CeilingHeight.l
  LightLevel.l
  FloorName.s
  CeilingName.s
EndStructure

Structure TestLineSpec
  V1.l
  V2.l
  Flags.l
  Special.l
  Tag.l
  Side0.l
  Side1.l
EndStructure

Structure TestSideSpec
  Sector.l
  TopName.s
  BottomName.s
  MidName.s
EndStructure

Structure TestVertexSpec
  X.l
  Y.l
EndStructure

Structure TestSegSpec
  V1.l
  V2.l
  Line.l
  Side.l
EndStructure

Structure TestSubSpec
  FirstSeg.l
  NumSegs.l
EndStructure

Structure TestNodeSpec
  OriginX.l
  OriginY.l
  DX.l
  DY.l
  Box0Top.l
  Box0Bottom.l
  Box0Left.l
  Box0Right.l
  Box1Top.l
  Box1Bottom.l
  Box1Left.l
  Box1Right.l
  Child0.l
  Child1.l
EndStructure

; ---------------------------------------------------------------------------
; Harness
; ---------------------------------------------------------------------------

Procedure BeginCase(Id.s, Title.s)
  gCaseCount + 1
  gTestCaseFailed = 0
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
    gTestCaseFailed + 1
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

Procedure.q FnvAddU32(Hash.q, Value.q)
  Protected wrapped.q = BamWrap32(Value)
  Hash = FnvAddByte(Hash, wrapped & $FF)
  Hash = FnvAddByte(Hash, (wrapped >> 8) & $FF)
  Hash = FnvAddByte(Hash, (wrapped >> 16) & $FF)
  Hash = FnvAddByte(Hash, (wrapped >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic flexible map builders
; ---------------------------------------------------------------------------

Procedure Put16(*Data.Byte, Offset.i, Value.i)
  PokeA(*Data + Offset, Value & $FF)
  PokeA(*Data + Offset + 1, (Value >> 8) & $FF)
EndProcedure

Procedure PutName8(*Data.Byte, Offset.i, Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      PokeA(*Data + Offset + i, Asc(Mid(Name, i + 1, 1)))
    Else
      PokeA(*Data + Offset + i, 0)
    EndIf
  Next
EndProcedure

Procedure TestMapFree()
  Protected i.i

  For i = 1 To 10
    If gMapLump(i) <> 0
      FreeMemory(gMapLump(i))
    EndIf
    gMapLump(i) = 0
    gMapLumpSize(i) = 0
  Next
EndProcedure

Procedure.i NewZero(Size.q)
  Protected memory.i

  If Size <= 0
    ProcedureReturn 0
  EndIf
  memory = AllocateMemory(Size)
  If memory <> 0
    FillMemory(memory, Int(Size), 0)
  EndIf
  ProcedureReturn memory
EndProcedure

Procedure.i TestNewMapLump(Kind.i, Size.q)
  If gMapLump(Kind) <> 0
    FreeMemory(gMapLump(Kind))
    gMapLump(Kind) = 0
  EndIf
  gMapLump(Kind) = NewZero(Size)
  gMapLumpSize(Kind) = Size
  ProcedureReturn gMapLump(Kind)
EndProcedure

; Builds an owned validated synthetic MapLevel from caller-defined sector, line,
; side, vertex, seg, subsector and node specs. All disk fields are written
; explicitly little-endian at vanilla strides. THINGS is zero-length; REJECT has
; the minimum (N*N+7)/8 bytes; BLOCKMAP is one synthetic cell listing every line.
Procedure.i TestBuildFlexibleMap(*Level.MapLevel,
                                 *Sectors.TestSectorSpec, SectorCount.l,
                                 *Lines.TestLineSpec, LineCount.l,
                                 *Sides.TestSideSpec, SideCount.l,
                                 *Vertices.TestVertexSpec, VertexCount.l,
                                 *Segs.TestSegSpec, SegCount.l,
                                 *Subs.TestSubSpec, SubCount.l,
                                 *Nodes.TestNodeSpec, NodeCount.l)
  Protected ok.i
  Protected i.i
  Protected *sector.TestSectorSpec
  Protected *line.TestLineSpec
  Protected *side.TestSideSpec
  Protected *vertex.TestVertexSpec
  Protected *seg.TestSegSpec
  Protected *sub.TestSubSpec
  Protected *node.TestNodeSpec
  Protected *bytes.Byte
  Protected rejectBytes.q
  Protected blockmapBytes.q
  Protected blockmapPosition.q

  If *Level = 0
    ProcedureReturn #False
  EndIf
  If SectorCount < 1 Or SectorCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If LineCount < 1 Or LineCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If SideCount < 1 Or SideCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If VertexCount < 1 Or VertexCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If SegCount < 1 Or SegCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If SubCount < 1 Or SubCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If NodeCount < 0 Or NodeCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If *Sectors = 0 Or *Lines = 0 Or *Sides = 0 Or *Vertices = 0 Or *Segs = 0 Or *Subs = 0
    ProcedureReturn #False
  EndIf
  If NodeCount > 0 And *Nodes = 0
    ProcedureReturn #False
  EndIf

  MapLevelReset(*Level)
  TestMapFree()

  ok = MapThingsDecode(0, 0, @*Level\Things)
  If ok = #False
    ProcedureReturn #False
  EndIf

  If TestNewMapLump(2, Int(LineCount) * #MAP_LinedefSize) = 0
    ProcedureReturn #False
  EndIf
  *line = *Lines
  For i = 0 To LineCount - 1
    Put16(gMapLump(2), i * #MAP_LinedefSize, *line\V1)
    Put16(gMapLump(2), i * #MAP_LinedefSize + 2, *line\V2)
    Put16(gMapLump(2), i * #MAP_LinedefSize + 4, *line\Flags)
    Put16(gMapLump(2), i * #MAP_LinedefSize + 6, *line\Special)
    Put16(gMapLump(2), i * #MAP_LinedefSize + 8, *line\Tag)
    Put16(gMapLump(2), i * #MAP_LinedefSize + 10, *line\Side0)
    Put16(gMapLump(2), i * #MAP_LinedefSize + 12, *line\Side1)
    *line = *line + SizeOf(TestLineSpec)
  Next
  ok = MapLinedefsDecode(gMapLump(2), gMapLumpSize(2), @*Level\Linedefs)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  If TestNewMapLump(3, Int(SideCount) * #MAP_SidedefSize) = 0
    ProcedureReturn #False
  EndIf
  *side = *Sides
  For i = 0 To SideCount - 1
    Put16(gMapLump(3), i * #MAP_SidedefSize, 0)
    Put16(gMapLump(3), i * #MAP_SidedefSize + 2, 0)
    PutName8(gMapLump(3), i * #MAP_SidedefSize + 4, *side\TopName)
    PutName8(gMapLump(3), i * #MAP_SidedefSize + 12, *side\BottomName)
    PutName8(gMapLump(3), i * #MAP_SidedefSize + 20, *side\MidName)
    Put16(gMapLump(3), i * #MAP_SidedefSize + 28, *side\Sector)
    *side = *side + SizeOf(TestSideSpec)
  Next
  ok = MapSidedefsDecode(gMapLump(3), gMapLumpSize(3), @*Level\Sidedefs)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  If TestNewMapLump(4, Int(VertexCount) * #MAP_VertexSize) = 0
    ProcedureReturn #False
  EndIf
  *vertex = *Vertices
  For i = 0 To VertexCount - 1
    Put16(gMapLump(4), i * #MAP_VertexSize, *vertex\X)
    Put16(gMapLump(4), i * #MAP_VertexSize + 2, *vertex\Y)
    *vertex = *vertex + SizeOf(TestVertexSpec)
  Next
  ok = MapVertexesDecode(gMapLump(4), gMapLumpSize(4), @*Level\Vertexes)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  If TestNewMapLump(5, Int(SegCount) * #MAP_SegSize) = 0
    ProcedureReturn #False
  EndIf
  *seg = *Segs
  For i = 0 To SegCount - 1
    Put16(gMapLump(5), i * #MAP_SegSize, *seg\V1)
    Put16(gMapLump(5), i * #MAP_SegSize + 2, *seg\V2)
    Put16(gMapLump(5), i * #MAP_SegSize + 4, 0)
    Put16(gMapLump(5), i * #MAP_SegSize + 6, *seg\Line)
    Put16(gMapLump(5), i * #MAP_SegSize + 8, *seg\Side)
    Put16(gMapLump(5), i * #MAP_SegSize + 10, 0)
    *seg = *seg + SizeOf(TestSegSpec)
  Next
  ok = MapSegsDecode(gMapLump(5), gMapLumpSize(5), @*Level\Segs)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  If TestNewMapLump(6, Int(SubCount) * #MAP_SubsectorSize) = 0
    ProcedureReturn #False
  EndIf
  *sub = *Subs
  For i = 0 To SubCount - 1
    Put16(gMapLump(6), i * #MAP_SubsectorSize, *sub\NumSegs)
    Put16(gMapLump(6), i * #MAP_SubsectorSize + 2, *sub\FirstSeg)
    *sub = *sub + SizeOf(TestSubSpec)
  Next
  ok = MapSubsectorsDecode(gMapLump(6), gMapLumpSize(6), @*Level\Subsectors)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  TestNewMapLump(7, Int(NodeCount) * #MAP_NodeSize)
  If NodeCount > 0
    If gMapLump(7) = 0
      TestMapFree()
      ProcedureReturn #False
    EndIf
    *node = *Nodes
    For i = 0 To NodeCount - 1
      Put16(gMapLump(7), i * #MAP_NodeSize, *node\OriginX)
      Put16(gMapLump(7), i * #MAP_NodeSize + 2, *node\OriginY)
      Put16(gMapLump(7), i * #MAP_NodeSize + 4, *node\DX)
      Put16(gMapLump(7), i * #MAP_NodeSize + 6, *node\DY)
      Put16(gMapLump(7), i * #MAP_NodeSize + 8, *node\Box0Top)
      Put16(gMapLump(7), i * #MAP_NodeSize + 10, *node\Box0Bottom)
      Put16(gMapLump(7), i * #MAP_NodeSize + 12, *node\Box0Left)
      Put16(gMapLump(7), i * #MAP_NodeSize + 14, *node\Box0Right)
      Put16(gMapLump(7), i * #MAP_NodeSize + 16, *node\Box1Top)
      Put16(gMapLump(7), i * #MAP_NodeSize + 18, *node\Box1Bottom)
      Put16(gMapLump(7), i * #MAP_NodeSize + 20, *node\Box1Left)
      Put16(gMapLump(7), i * #MAP_NodeSize + 22, *node\Box1Right)
      Put16(gMapLump(7), i * #MAP_NodeSize + 24, *node\Child0)
      Put16(gMapLump(7), i * #MAP_NodeSize + 26, *node\Child1)
      *node = *node + SizeOf(TestNodeSpec)
    Next
    ; caller spec pointer deliberately untouched
  EndIf
  ok = MapNodesDecode(gMapLump(7), gMapLumpSize(7), @*Level\Nodes)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  If TestNewMapLump(8, Int(SectorCount) * #MAP_SectorSize) = 0
    ProcedureReturn #False
  EndIf
  *sector = *Sectors
  For i = 0 To SectorCount - 1
    Put16(gMapLump(8), i * #MAP_SectorSize, *sector\FloorHeight)
    Put16(gMapLump(8), i * #MAP_SectorSize + 2, *sector\CeilingHeight)
    PutName8(gMapLump(8), i * #MAP_SectorSize + 4, *sector\FloorName)
    PutName8(gMapLump(8), i * #MAP_SectorSize + 12, *sector\CeilingName)
    Put16(gMapLump(8), i * #MAP_SectorSize + 20, *sector\LightLevel)
    Put16(gMapLump(8), i * #MAP_SectorSize + 22, 0)
    Put16(gMapLump(8), i * #MAP_SectorSize + 24, 0)
    *sector = *sector + SizeOf(TestSectorSpec)
  Next
  ok = MapSectorsDecode(gMapLump(8), gMapLumpSize(8), @*Level\Sectors)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  ; REJECT minimum bytes for sectorCount sectors, all-zero synthetic bits.
  rejectBytes = Int(SectorCount) * Int(SectorCount) + 7
  rejectBytes = rejectBytes >> 3
  If rejectBytes <= 0
    rejectBytes = 1
  EndIf
  If TestNewMapLump(9, rejectBytes) = 0
    TestMapFree()
    ProcedureReturn #False
  EndIf
  ok = MapRejectDecode(gMapLump(9), gMapLumpSize(9), @*Level\Reject)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  ; one-cell BLOCKMAP: header origin 0/0, width=height=1, offset word 5 (word
  ; index -> byte 10), zero dummy, every line index, 0xFFFF terminator.
  blockmapBytes = Int(LineCount) * 2 + 14
  If TestNewMapLump(10, blockmapBytes) = 0
    TestMapFree()
    ProcedureReturn #False
  EndIf
  *bytes = gMapLump(10)
  Put16(*bytes, 0, 0)
  Put16(*bytes, 2, 0)
  Put16(*bytes, 4, 1)
  Put16(*bytes, 6, 1)
  Put16(*bytes, 8, 5)
  Put16(*bytes, 10, 0)
  blockmapPosition = 12
  For i = 0 To LineCount - 1
    Put16(*bytes, Int(blockmapPosition), i)
    blockmapPosition + 2
  Next
  Put16(*bytes, Int(blockmapPosition), $FFFF)
  ok = MapBlockmapDecode(gMapLump(10), gMapLumpSize(10), @*Level\Blockmap)
  If ok = #False
    TestMapFree()
    ProcedureReturn #False
  EndIf

  TestMapFree()
  ok = MapValidateLevel(*Level)
  ProcedureReturn ok
EndProcedure

; ---------------------------------------------------------------------------
; Common one-sector synthetic wall fixture
; ---------------------------------------------------------------------------

Procedure.i TestBuildOneSidedWall(*Level.MapLevel, V0X.l, V0Y.l, V1X.l, V1Y.l, MidName.s)
  Protected Dim sectors.TestSectorSpec(0)
  Protected Dim lines.TestLineSpec(0)
  Protected Dim sides.TestSideSpec(0)
  Protected Dim vertices.TestVertexSpec(1)
  Protected Dim segs.TestSegSpec(0)
  Protected Dim subs.TestSubSpec(0)
  Protected ok.i

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
  sides(0)\MidName = MidName

  vertices(0)\X = V0X
  vertices(0)\Y = V0Y
  vertices(1)\X = V1X
  vertices(1)\Y = V1Y

  segs(0)\V1 = 0
  segs(0)\V2 = 1
  segs(0)\Line = 0
  segs(0)\Side = 0

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1

  ok = TestBuildFlexibleMap(*Level, @sectors(0), 1, @lines(0), 1, @sides(0), 1,
                            @vertices(0), 2, @segs(0), 1, @subs(0), 1, 0, 0)
  ProcedureReturn ok
EndProcedure

; ---------------------------------------------------------------------------
; Projection fixture verification helpers
; ---------------------------------------------------------------------------

Procedure.q TestForwardHash(*Projection.Projection)
  Protected hash.q = #TEST_FNV_Offset
  Protected i.i
  Protected x.l = 0

  For i = 0 To #PROJ_VIEWANGLE_TOX_COUNT - 1
    If ProjectionGetViewAngleToX(*Projection, i, @x) = #False
      ProcedureReturn -1
    EndIf
    hash = FnvAddLong(hash, x)
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q TestPreHash(*Projection.Projection)
  Protected hash.q = #TEST_FNV_Offset
  Protected i.i
  Protected x.l = 0

  For i = 0 To #PROJ_VIEWANGLE_TOX_COUNT - 1
    If ProjectionGetPreViewAngleToX(*Projection, i, @x) = #False
      ProcedureReturn -1
    EndIf
    hash = FnvAddLong(hash, x)
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q TestInverseHash(*Projection.Projection)
  Protected hash.q = #TEST_FNV_Offset
  Protected i.i
  Protected raw.q = 0

  For i = 0 To #PROJ_XTOVIEWANGLE_COUNT - 1
    If ProjectionGetXToViewAngle(*Projection, i, @raw) = #False
      ProcedureReturn -1
    EndIf
    hash = FnvAddU32(hash, raw)
  Next
  ProcedureReturn hash
EndProcedure

; ---------------------------------------------------------------------------
; Independent bitmap clipping oracle (test-only tiny widths)
; ---------------------------------------------------------------------------

Procedure TestClippingOracleBegin(Width.l)
  Protected column.i

  gOracleSpanCount = 0
  For column = 0 To Width - 1
    gOracleCovered(column) = 1
  Next
  For column = Width To #CLIP_MaxWidth - 1
    gOracleCovered(column) = 0
  Next
EndProcedure

Procedure TestClippingOracleEmit(First.l, Last.l, Kind.l)
  Protected column.i
  Protected runStart.l = -1

  For column = First To Last
    If gOracleCovered(column) <> 0
      If runStart < 0
        runStart = column
      EndIf
    ElseIf runStart >= 0
      If gOracleSpanCount >= #CLIP_MaxRanges
        ProcedureReturn #False
      EndIf
      gOracleSpanFirst(gOracleSpanCount) = runStart
      gOracleSpanLast(gOracleSpanCount) = column - 1
      gOracleSpanKind(gOracleSpanCount) = Kind
      gOracleSpanCount + 1
      runStart = -1
    EndIf
  Next
  If runStart >= 0
    If gOracleSpanCount >= #CLIP_MaxRanges
      ProcedureReturn #False
    EndIf
    gOracleSpanFirst(gOracleSpanCount) = runStart
    gOracleSpanLast(gOracleSpanCount) = Last
    gOracleSpanKind(gOracleSpanCount) = Kind
    gOracleSpanCount + 1
  EndIf
  If Kind = #WALL_KIND_SOLID
    For column = First To Last
      gOracleCovered(column) = 0
    Next
  EndIf
  ProcedureReturn #True
EndProcedure

; Compares all newly emitted production spans and production final screen
; coverage against the independent bitmap oracle. Tested widths are tiny; the
; production sentinel fields are not part of drawable coverage.
Procedure.i TestClippingCompareStep(*State.ClipState, Width.l, SpanStart.l, OracleStart.l)
  Protected i.i
  Protected column.i
  Protected covered.i
  Protected *range.ClipRange
  Protected productionFirst.l = 0
  Protected productionLast.l = 0
  Protected productionKind.l = 0
  Protected afterSpans.l

  afterSpans = 0
  *range = 0
  ClipStateGetStats(*State, 0, 0, @afterSpans, 0, 0, 0)
  If afterSpans < 0 Or SpanStart < 0 Or OracleStart < 0
    ProcedureReturn #False
  EndIf
  If afterSpans - SpanStart <> gOracleSpanCount - OracleStart
    ProcedureReturn #False
  EndIf
  For i = SpanStart To afterSpans - 1
    productionFirst = 0
    productionLast = 0
    productionKind = 0
    If ClipStateGetSpan(*State, i, 0, 0, 0, 0, 0, 0,
                        @productionFirst, @productionLast, @productionKind) = #False
      ProcedureReturn #False
    EndIf
    If productionFirst <> gOracleSpanFirst(OracleStart + i - SpanStart) Or
       productionLast <> gOracleSpanLast(OracleStart + i - SpanStart) Or
       productionKind <> gOracleSpanKind(OracleStart + i - SpanStart)
      ProcedureReturn #False
    EndIf
  Next

  ; Coverage of [0..width-1] from real posts only, compared to the oracle map.
  ; The bitmap oracle stores 1 for still-visible/uncovered columns and 0 for
  ; solid-hidden columns; production post containment stores the hidden truth.
  For column = 0 To Width - 1
    covered = 0
    For i = *State\RangeCount - 2 To 1 Step -1
      *range = *State\Ranges + i * SizeOf(ClipRange)
      If column >= *range\First And column <= *range\Last
        covered = 1
        Break
      EndIf
    Next
    If Bool(covered <> 0) <> Bool(gOracleCovered(column) = 0)
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

; One deterministic synthetic operation step: performs production clipping then
; the independent oracle and compares. Returns false if production op fails or
; any spans/coverage differ.
Procedure.i TestClippingOneStep(*State.ClipState, Width.l, First.l, Last.l, Kind.l, Seed.l)
  Protected spanStart.l
  Protected oracleStart.l
  Protected Seg.l = Seed
  Protected passRowWanted.i

  If Kind = #WALL_KIND_SOLID
    passRowWanted = 0
  Else
    passRowWanted = 1
  EndIf
  spanStart = 0
  ClipStateGetStats(*State, 0, 0, @spanStart, 0, 0, 0)
  If spanStart < 0
    ProcedureReturn #False
  EndIf
  oracleStart = gOracleSpanCount
  If Kind = #WALL_KIND_SOLID
    If ClipSolidSegment(*State, First, Last, 7, Seg, Seed, 0, 7, -1) = #False
      ProcedureReturn #False
    EndIf
  Else
    If ClipPassSegment(*State, First, Last, 7, Seg, Seed, 0, 7, -1) = #False
      ProcedureReturn #False
    EndIf
  EndIf
  If TestClippingOracleEmit(First, Last, Kind) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn TestClippingCompareStep(*State, Width, spanStart, oracleStart)
EndProcedure

; ---------------------------------------------------------------------------
; Deterministic LCG for seeded clipping tests
; ---------------------------------------------------------------------------

Procedure.l TestLcgNext(*Seed.Long)
  Protected value.q

  value = Int(PeekL(*Seed)) * 1103515245 + 12345
  value = BamWrap32(value) & $7FFFFFFF
  PokeL(*Seed, Int(value))
  ProcedureReturn Int(value)
EndProcedure

; ---------------------------------------------------------------------------
; WC01-WC12 projection cases
; ---------------------------------------------------------------------------

Procedure TestWC01()
  Protected projection.Projection
  Protected hashFirst.q
  Protected hashSecond.q
  Protected ok.i

  BeginCase("WC01", "Projection reset, default 320 width and repeated init reproducibility")

  ok = ProjectionReset(@projection)
  Check(Bool(ok <> 0), "first empty reset succeeds")
  Check(Bool(ProjectionIsValid(@projection) = 0), "empty reusable projection is not ready")
  Check(Bool(ProjectionReset(@projection) <> 0), "repeated reset is idempotent")
  ok = ProjectionInitClassic(@projection)
  Check(Bool(ok <> 0), "classic 320-column init succeeds")
  Check(Bool(ProjectionIsValid(@projection) <> 0), "initialized classic projection is ready")
  hashFirst = TestForwardHash(@projection)
  ok = ProjectionInitClassic(@projection)
  Check(Bool(ok <> 0), "second init on the same object succeeds")
  hashSecond = TestForwardHash(@projection)
  Check(Bool(hashFirst = hashSecond), "repeated init produces an identical forward table")
  Check(Bool(ProjectionReset(@projection) <> 0 And ProjectionIsValid(@projection) = 0),
        "reset releases owned tables and leaves a reusable empty object")
EndProcedure

Procedure TestWC02()
  Protected projection.Projection
  Protected width.l = 0
  Protected viewHeight.l = 0
  Protected centerX.l = 0
  Protected centerY.l = 0
  Protected centerXFixed.l = 0
  Protected centerYFixed.l = 0
  Protected projectionFixed.l = 0
  Protected focal.l = 0
  Protected fieldOfView.l = 0

  BeginCase("WC02", "FIELDOFVIEW, focal index and center/projection constants")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for constants")
  Check(Bool(ProjectionGetConstants(@projection, @width, @viewHeight, @centerX, @centerY,
                               @centerXFixed, @centerYFixed, @projectionFixed,
                               @focal, @fieldOfView) <> 0), "constants accessor succeeds")
  Check(Bool(width = 320 And viewHeight = 200), "classic logical viewport is 320x200")
  Check(Bool(centerX = 160 And centerY = 100), "center x/y are original 160/100")
  Check(Bool(centerXFixed = 160 * #FRACUNIT And centerYFixed = 100 * #FRACUNIT),
        "center fixed values are 160/100 times FRACUNIT")
  Check(Bool(projectionFixed = centerXFixed), "projection equals centerxfrac")
  Check(Bool(fieldOfView = 2048), "FIELDOFVIEW is exactly 2048")
  Check(Bool(#PROJ_FOCAL_TANGENT_INDEX = 3072), "focal tangent index is FINEANGLES/4+FIELDOFVIEW/2 = 3072")
  Check(Bool(ProjectionReset(@projection) <> 0), "constants projection cleanup")
EndProcedure

Procedure TestWC03()
  Protected projection.Projection
  Protected forward.l = 0
  Protected inverse.l = 0
  Protected pre.l = 0
  Protected x.l = 0
  Protected raw.q = 0

  BeginCase("WC03", "Table lengths 4096/321 and checked first/last indexed access")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for table access")
  Check(Bool(ProjectionGetTableCounts(@projection, @forward, @inverse, @pre) <> 0), "table counts accessor")
  Check(Bool(forward = 4096 And pre = 4096), "forward and pre tables have 4096 entries")
  Check(Bool(inverse = 321), "xtoviewangle has viewwidth+1=321 entries")
  Check(Bool(ProjectionGetViewAngleToX(@projection, 0, @x) <> 0), "forward index 0 is readable")
  Check(Bool(ProjectionGetViewAngleToX(@projection, 4095, @x) <> 0), "forward index 4095 is readable")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 0, @raw) <> 0), "inverse index 0 is readable")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 320, @raw) <> 0), "inverse index 320 is readable")
  Check(Bool(ProjectionGetViewAngleToX(@projection, 4096, @x) = 0), "forward index 4096 is rejected")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 321, @raw) = 0), "inverse index 321 is rejected")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC04()
  Protected projection.Projection
  Protected focal.l = 0
  Protected fixtureFocal.l

  BeginCase("WC04", "focallength against the independent original-divide oracle")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for focal check")
  Check(Bool(ProjectionGetConstants(@projection, 0, 0, 0, 0, 0, 0, 0, @focal, 0) <> 0),
        "focal accessor succeeds")
  fixtureFocal = PeekL(*gGoldFocalLength)
  Check(Bool(focal = fixtureFocal), "focallength equals independent fixture " + Str(fixtureFocal))
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC05()
  Protected projection.Projection
  Protected Dim selected.l(5)
  Protected i.i
  Protected tangent.l = 0
  Protected expected.l = 0
  Protected actual.l = 0
  Protected mismatch.i = 0
  Protected fence.l = 0

  BeginCase("WC05", "Selected negative/zero/positive tangent projection values")

  selected(0) = 0
  selected(1) = 604
  selected(2) = 2047
  selected(3) = 2048
  selected(4) = 3491
  selected(5) = 4095

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for selected tangent values")
  For i = 0 To 5
    expected = PeekL(*gGoldPre + selected(i) * 4)
    If ProjectionGetPreViewAngleToX(@projection, selected(i), @actual) = 0 Or actual <> expected
      mismatch + 1
    EndIf
    expected = PeekL(*gGoldForward + selected(i) * 4)
    If ProjectionGetViewAngleToX(@projection, selected(i), @actual) = 0 Or actual <> expected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "selected pre/post projection values match the fixture")

  Check(Bool(TrigTangentChecked(2047, @tangent) <> 0 And tangent < 0),
        "fine index 2047 is a negative tangent projection vector")
  Check(Bool(TrigTangentChecked(2048, @tangent) <> 0 And tangent > 0),
        "fine index 2048 is a positive tangent projection vector")
  Check(Bool(ProjectionTangentFence(0, @fence) <> 0 And fence = 0),
        "exact zero tangent remains an ordinary projection vector")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC06()
  Protected projection.Projection
  Protected Dim boundary.l(5)
  Protected i.i
  Protected fence.l = 0
  Protected expected.l = 0
  Protected actual.l = 0
  Protected mismatch.i = 0

  BeginCase("WC06", "Strict >+2*FRACUNIT and <-2*FRACUNIT boundaries")

  boundary(0) = #FRACUNIT * 2
  boundary(1) = #FRACUNIT * 2 + 1
  boundary(2) = #FRACUNIT * 2 - 1
  boundary(3) = -(#FRACUNIT * 2)
  boundary(4) = -(#FRACUNIT * 2) - 1

  Check(Bool(ProjectionTangentFence(boundary(0), @fence) <> 0 And fence = 0),
        "tangent exactly +2*FRACUNIT is ordinary by strict >")
  Check(Bool(ProjectionTangentFence(boundary(1), @fence) <> 0 And fence = -1),
        "tangent +2*FRACUNIT+1 is the plus fencepost -1")
  Check(Bool(ProjectionTangentFence(boundary(2), @fence) <> 0 And fence = 0),
        "tangent +2*FRACUNIT-1 is ordinary")
  Check(Bool(ProjectionTangentFence(boundary(3), @fence) <> 0 And fence = 0),
        "tangent exactly -2*FRACUNIT is ordinary by strict <")
  Check(Bool(ProjectionTangentFence(boundary(4), @fence) <> 0 And fence = 320 + 1),
        "-2*FRACUNIT-1 is the minus fencepost viewwidth+1")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for boundary entries")
  boundary(0) = 603
  boundary(1) = 604
  boundary(2) = 605
  boundary(3) = 3490
  boundary(4) = 3491
  boundary(5) = 3492
  For i = 0 To 5
    expected = PeekL(*gGoldPre + boundary(i) * 4)
    If ProjectionGetPreViewAngleToX(@projection, boundary(i), @actual) = 0 Or actual <> expected
      mismatch + 1
    EndIf
    expected = PeekL(*gGoldForward + boundary(i) * 4)
    If ProjectionGetViewAngleToX(@projection, boundary(i), @actual) = 0 Or actual <> expected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "exact threshold neighbour entries match the fixture")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC07()
  Protected projection.Projection
  Protected preCount.l = 0
  Protected i.i
  Protected actual.l = 0
  Protected expected.l = 0
  Protected mismatch.i = 0
  Protected hash.q

  BeginCase("WC07", "Pre-fencepost table retained for inverse lookup computation")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for pre table")
  Check(Bool(ProjectionGetTableCounts(@projection, 0, 0, @preCount) <> 0 And preCount = 4096),
        "owned pre-fencepost table retains all 4096 entries")
  For i = 0 To 4095
    expected = PeekL(*gGoldPre + i * 4)
    If ProjectionGetPreViewAngleToX(@projection, i, @actual) = 0 Or actual <> expected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "every pre-fencepost entry matches the independent fixture")
  hash = TestPreHash(@projection)
  Check(Bool(hash = PeekQ(*gGoldPreHash)), "pre-fencepost canonical FNV-1a64 matches the fixture")
  Check(Bool(ProjectionGetPreViewAngleToX(@projection, 4096, @actual) = 0),
        "pre table index 4096 is rejected")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC08()
  Protected projection.Projection
  Protected i.i
  Protected preValue.l = 0
  Protected postValue.l = 0
  Protected mismatch.i = 0

  BeginCase("WC08", "Post-fencepost -1 to 0 and viewwidth+1 to viewwidth order")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for fencepost normalization")
  For i = 0 To 4095
    If ProjectionGetPreViewAngleToX(@projection, i, @preValue) = 0 Or
       ProjectionGetViewAngleToX(@projection, i, @postValue) = 0
      mismatch + 1
      Continue
    EndIf
    If preValue = -1
      If postValue <> 0
        mismatch + 1
      EndIf
    ElseIf preValue = 321
      If postValue <> 320
        mismatch + 1
      EndIf
    ElseIf postValue <> preValue
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "all 4096 fencepost substitutions follow -1->0 and 321->320 order")
  Check(Bool(PeekB(*gGoldThresholdKind + 604) = 0 And PeekB(*gGoldThresholdKind + 3491) = 0),
        "independent fixture records exact +-2*FRACUNIT indexes as ordinary")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC09()
  Protected projection.Projection
  Protected i.i
  Protected actual.l = 0
  Protected expected.l = 0
  Protected mismatch.i = 0
  Protected hash.q

  BeginCase("WC09", "All 4096 forward entries compared to test-only reference/hash")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for full forward table")
  For i = 0 To 4095
    expected = PeekL(*gGoldForward + i * 4)
    If ProjectionGetViewAngleToX(@projection, i, @actual) = 0 Or actual <> expected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "every one of 4096 viewangletox entries equals the fixture")
  hash = TestForwardHash(@projection)
  Check(Bool(hash = PeekQ(*gGoldForwardHash)), "whole forward table FNV-1a64 equals fixture hash")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC10()
  Protected projection.Projection
  Protected i.i
  Protected actual.q = 0
  Protected expected.q
  Protected mismatch.i = 0
  Protected hash.q

  BeginCase("WC10", "All 321 inverse entries compared to test-only reference/hash")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for full inverse table")
  For i = 0 To 320
    expected = PeekQ(*gGoldInverse + i * 8)
    If ProjectionGetXToViewAngle(@projection, i, @actual) = 0 Or actual <> expected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "every one of 321 xtoviewangle raw BAM entries equals the fixture")
  hash = TestInverseHash(@projection)
  Check(Bool(hash = PeekQ(*gGoldInverseHash)), "whole inverse table FNV-1a64 equals fixture hash")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC11()
  Protected projection.Projection
  Protected clip.q = 0
  Protected inverseZero.q = 0
  Protected fixtureClip.q

  BeginCase("WC11", "clipangle matches inverse x=0 and unsigned BAM representation")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "projection init for clipangle")
  Check(Bool(ProjectionGetClipAngle(@projection, @clip) <> 0), "clipangle accessor succeeds")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 0, @inverseZero) <> 0),
        "xtoviewangle[0] accessor succeeds")
  fixtureClip = PeekQ(*gGoldClipAngle)
  Check(Bool(clip = inverseZero), "clipangle equals xtoviewangle[0]")
  Check(Bool(clip = fixtureClip), "clipangle matches the independent fixture raw value")
  Check(Bool(BamRawInUnsignedDomain(clip) <> 0), "clipangle is a canonical unsigned raw BAM value")
  Check(Bool(ProjectionReset(@projection) <> 0), "projection cleanup")
EndProcedure

Procedure TestWC12()
  Protected projection.Projection
  Protected badProjection.Projection
  Protected x.l = 0
  Protected errorFirst.s
  Protected ok.i

  BeginCase("WC12", "Invalid table access, null pointer, repeated reset/reinit and stale errors")

  badProjection\Magic = $12345678
  Check(Bool(ProjectionReset(@badProjection) = 0), "unrecognized Magic object is rejected")
  Check(Bool(ProjectionLastError() <> ""), "rejection sets an actionable diagnostic")
  Check(Bool(ProjectionReset(0) = 0), "null projection pointer is rejected")
  Check(Bool(ProjectionInitClassic(0) = 0), "null projection init is rejected")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "valid projection initialized")
  Check(Bool(ProjectionGetViewAngleToX(@projection, 4096, @x) = 0), "invalid forward index rejected")
  errorFirst = ProjectionLastError()
  Check(Bool(errorFirst <> ""), "invalid index leaves a nonempty diagnostic")
  Check(Bool(ProjectionGetViewAngleToX(@projection, 0, 0) = 0), "null forward output rejected")
  Check(Bool(ProjectionGetXToViewAngle(@projection, 0, 0) = 0), "null inverse output rejected")
  Check(Bool(ProjectionGetViewAngleToX(@projection, 0, @x) <> 0 And ProjectionLastError() = ""),
        "successful access clears stale error")
  ok = ProjectionReset(@projection)
  Check(Bool(ok <> 0 And ProjectionIsValid(@projection) = 0), "reset invalidates ready state")
  ok = ProjectionInitClassic(@projection)
  Check(Bool(ok <> 0 And ProjectionIsValid(@projection) <> 0), "reinit after reset succeeds")
  Check(Bool(ProjectionReset(@projection) <> 0), "final cleanup")
EndProcedure

; ---------------------------------------------------------------------------
; WC13-WC26 clipping cases
; ---------------------------------------------------------------------------

Procedure TestWC13()
  Protected state.ClipState
  Protected width.l = 0
  Protected ranges.l = 0
  Protected spans.l = 0
  Protected first.l = 0
  Protected last.l = 0

  BeginCase("WC13", "Initial sentinels and empty visible coverage")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins at canonical width 320")
  Check(Bool(ClipStateGetStats(@state, @width, @ranges, @spans, 0, 0, 0) <> 0),
        "clip statistics accessor succeeds")
  Check(Bool(width = 320 And ranges = 2 And spans = 0),
        "empty frame has width 320, two sentinel posts and zero visible spans")
  Check(Bool(ClipStateGetRange(@state, 0, @first, @last) <> 0 And first = -2147483647 And last = -1),
        "left sentinel is exactly [-0x7FFFFFFF,-1]")
  Check(Bool(ClipStateGetRange(@state, 1, @first, @last) <> 0 And first = 320 And last = 2147483647),
        "right sentinel is exactly [viewwidth,+0x7FFFFFFF]")
  Check(Bool(ClipStateGetSpan(@state, 0, 0, 0, 0, 0, 0, 0, @first, @last, 0) = 0),
        "empty visible-span index is rejected")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC14()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0

  BeginCase("WC14", "First and last drawable columns; one-column SOLID")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 0, 0, 0, 0, 0, 0, 0, -1) <> 0), "column 0 solid clip succeeds")
  Check(Bool(ClipStateGetSpan(@state, 0, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 0 And last = 0 And kind = #WALL_KIND_SOLID),
        "single-column span [0,0] is published as SOLID")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And spans = 1),
        "first-column occlusion emits exactly one span")
  Check(Bool(ClipSolidSegment(@state, 319, 319, 0, 1, 0, 0, 0, -1) <> 0), "last column 319 solid clip succeeds")
  Check(Bool(ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 319 And last = 319 And kind = #WALL_KIND_SOLID),
        "last-column span [319,319] is published separately")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, 0, 0, 0, 0) <> 0 And ranges = 4),
        "two single-column real posts plus two sentinels are tracked")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC15()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC15", "Disjoint SOLID intervals: sorted insertion and visible output order")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 100, 150, 4, 9, 1, 0, 4, -1) <> 0), "first disjoint interval succeeds")
  Check(Bool(ClipSolidSegment(@state, 10, 20, 5, 10, 1, 0, 5, -1) <> 0), "second lower interval succeeds")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And spans = 2),
        "both disjoint intervals emit one span each")
  Check(Bool(ClipStateGetSpan(@state, 0, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 100 And last = 150 And kind = #WALL_KIND_SOLID),
        "chronological first span remains [100,150]")
  Check(Bool(ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 10 And last = 20 And kind = #WALL_KIND_SOLID),
        "chronological second span is [10,20]")
  Check(Bool(ranges = 4), "two real posts plus two sentinels")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And realFirst = 10 And realLast = 20),
        "insertion sorts the lower real post first")
  Check(Bool(ClipStateGetRange(@state, 2, @realFirst, @realLast) <> 0 And realFirst = 100 And realLast = 150),
        "stored real posts remain sorted left-to-right")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC16()
  Protected state.ClipState
  Protected prefixState.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC16", "Adjacent SOLID intervals coalesce at inclusive endpoints")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins for suffix adjacency")
  Check(Bool(ClipSolidSegment(@state, 100, 150, 0, 0, 0, 0, 0, -1) <> 0), "base post [100,150] succeeds")
  Check(Bool(ClipSolidSegment(@state, 151, 200, 1, 1, 0, 0, 0, -1) <> 0), "adjacent suffix [151,200] succeeds")
  Check(Bool(ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 151 And last = 200 And kind = #WALL_KIND_SOLID),
        "inclusive adjacency emits the uncovered suffix [151,200]")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, 0, 0, 0, 0) <> 0 And ranges = 3),
        "adjacent suffix coalesces into one real post plus sentinels")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And realFirst = 100 And realLast = 200),
        "coalesced inclusive occlusion post is [100,200]")

  Check(Bool(ClipStateBeginFrame(@prefixState, 320) <> 0), "clip frame begins for prefix adjacency")
  Check(Bool(ClipSolidSegment(@prefixState, 100, 150, 0, 0, 0, 0, 0, -1) <> 0), "prefix base post succeeds")
  Check(Bool(ClipSolidSegment(@prefixState, 99, 99, 0, 1, 0, 0, 0, -1) <> 0), "adjacent prefix [99,99] succeeds")
  Check(Bool(ClipStateGetSpan(@prefixState, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 99 And last = 99 And kind = #WALL_KIND_SOLID),
        "inclusive prefix adjacency emits [99,99]")
  Check(Bool(ClipStateGetStats(@prefixState, 0, @ranges, 0, 0, 0, 0) <> 0 And ranges = 3),
        "prefix adjacency coalesces into one real post")
  Check(Bool(ClipStateGetRange(@prefixState, 1, @realFirst, @realLast) <> 0 And realFirst = 99 And realLast = 150),
        "prefix coalescing extends inclusive occlusion to [99,150]")
  Check(Bool(ClipStateReset(@state) <> 0 And ClipStateReset(@prefixState) <> 0), "clip cleanups")
EndProcedure

Procedure TestWC17()
  Protected state.ClipState
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC17", "Nested SOLID fully covered: no fragment emission")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 0, 319, 0, 0, 0, 0, 0, -1) <> 0), "full-screen solid occlusion succeeds")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And spans = 1 And ranges = 3),
        "full-screen post is one real [0,319] plus sentinels")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And
        realFirst = 0 And realLast = 319), "full real post covers inclusive 0..319")
  Check(Bool(ClipSolidSegment(@state, 100, 200, 1, 1, 0, 0, 0, -1) <> 0),
        "nested solid span is accepted as already hidden")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And spans = 1 And ranges = 3),
        "nested fully covered span emits nothing and leaves occlusion unchanged")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC18()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC18", "Overlapping SOLID: visible prefix only")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 100, 200, 0, 0, 0, 0, 0, -1) <> 0), "base occlusion [100,200] succeeds")
  Check(Bool(ClipSolidSegment(@state, 50, 150, 1, 1, 0, 0, 0, -1) <> 0), "overlapping prefix clip succeeds")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And spans = 2),
        "only the uncovered prefix adds a second span")
  Check(Bool(ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 50 And last = 99 And kind = #WALL_KIND_SOLID),
        "visible prefix is [50,99] inclusive")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And
        realFirst = 50 And realLast = 200), "coverage extends to [50,200]")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC19()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC19", "Overlapping SOLID: visible suffix only")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 100, 200, 0, 0, 0, 0, 0, -1) <> 0), "base occlusion [100,200] succeeds")
  Check(Bool(ClipSolidSegment(@state, 150, 250, 1, 1, 0, 0, 0, -1) <> 0), "overlapping suffix clip succeeds")
  Check(Bool(ClipStateGetStats(@state, 0, 0, @spans, 0, 0, 0) <> 0 And spans = 2),
        "only the uncovered suffix adds a second span")
  Check(Bool(ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 201 And last = 250 And kind = #WALL_KIND_SOLID),
        "visible suffix is [201,250] inclusive")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And
        realFirst = 100 And realLast = 250), "coverage extends to [100,250]")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC20()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC20", "SOLID fills gap between two intervals and merges both")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 50, 100, 0, 0, 0, 0, 0, -1) <> 0), "left interval [50,100] succeeds")
  Check(Bool(ClipSolidSegment(@state, 200, 250, 0, 1, 0, 0, 0, -1) <> 0), "right interval [200,250] succeeds")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, 0, 0, 0, 0) <> 0 And ranges = 4),
        "two real posts and two sentinels before gap fill")
  Check(Bool(ClipSolidSegment(@state, 101, 199, 1, 2, 0, 0, 0, -1) <> 0), "gap filling solid succeeds")
  Check(Bool(ClipStateGetSpan(@state, 2, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 101 And last = 199 And kind = #WALL_KIND_SOLID),
        "gap fill emits [101,199] only")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, 0, 0, 0, 0) <> 0 And ranges = 3),
        "both intervals coalesce into one real post")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And
        realFirst = 50 And realLast = 250), "merged occlusion is [50,250]")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC21()
  Protected state.ClipState
  Protected SpanCountBefore.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC21", "SOLID spanning multiple occluders emits each uncovered gap")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 10, 20, 0, 0, 0, 0, 0, -1) <> 0), "post [10,20] succeeds")
  Check(Bool(ClipSolidSegment(@state, 100, 110, 0, 1, 0, 0, 0, -1) <> 0), "post [100,110] succeeds")
  Check(Bool(ClipSolidSegment(@state, 200, 210, 0, 2, 0, 0, 0, -1) <> 0), "post [200,210] succeeds")
  ClipStateGetStats(@state, 0, @ranges, @SpanCountBefore, 0, 0, 0)
  Check(Bool(SpanCountBefore = 3), "three pre-existing posts published three spans")
  Check(Bool(ClipSolidSegment(@state, 5, 250, 1, 3, 0, 0, 0, -1) <> 0),
        "wide solid spanning all three occluders succeeds")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And spans = 7),
        "wide solid emits four uncovered fragments")
  Check(Bool(ClipStateGetSpan(@state, 3, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 5 And last = 9), "first uncovered prefix is [5,9]")
  Check(Bool(ClipStateGetSpan(@state, 4, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 21 And last = 99), "gap between posts 1/2 is [21,99]")
  Check(Bool(ClipStateGetSpan(@state, 5, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 111 And last = 199), "gap between posts 2/3 is [111,199]")
  Check(Bool(ClipStateGetSpan(@state, 6, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 211 And last = 250), "final uncovered suffix is [211,250]")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, 0, 0, 0, 0) <> 0 And ranges = 3),
        "all three occluders are consolidated into one [5,250] post")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And
        realFirst = 5 And realLast = 250), "merged coverage covers the wide solid exactly")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC22()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0

  BeginCase("WC22", "PASS on empty state emits span but adds no occluder")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipPassSegment(@state, 100, 200, 0, 0, 0, 0, 0, -1) <> 0), "pass span on empty state succeeds")
  Check(Bool(ClipStateGetSpan(@state, 0, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 100 And last = 200 And kind = #WALL_KIND_PASS),
        "pass publishes its whole visible span as PASS")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And
        spans = 1 And ranges = 2), "pass adds one span but occlusion remains only two sentinels")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC23()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC23", "PASS overlapping SOLID emits only visible gap and does not mutate clips")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipSolidSegment(@state, 100, 150, 0, 0, 0, 0, 0, -1) <> 0), "occluding solid [100,150] succeeds")
  Check(Bool(ClipPassSegment(@state, 50, 200, 1, 1, 0, 0, 0, -1) <> 0), "overlapping pass succeeds")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And
        spans = 3 And ranges = 3), "pass emits two gaps while occlusion count stays three")
  Check(Bool(ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 50 And last = 99 And kind = #WALL_KIND_PASS), "left uncovered gap is [50,99] PASS")
  Check(Bool(ClipStateGetSpan(@state, 2, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 151 And last = 200 And kind = #WALL_KIND_PASS), "right uncovered gap is [151,200] PASS")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And
        realFirst = 100 And realLast = 150), "pass never mutates the [100,150] solid post")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC24()
  Protected state.ClipState
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected spans.l = 0
  Protected ranges.l = 0
  Protected realFirst.l = 0
  Protected realLast.l = 0

  BeginCase("WC24", "PASS then PASS, PASS then SOLID, SOLID then PASS chronology")

  Check(Bool(ClipStateBeginFrame(@state, 320) <> 0), "clip frame begins")
  Check(Bool(ClipPassSegment(@state, 100, 200, 0, 0, 0, 0, 0, -1) <> 0), "first PASS succeeds")
  Check(Bool(ClipPassSegment(@state, 50, 250, 0, 1, 0, 0, 0, -1) <> 0), "second PASS over empty state succeeds")
  Check(Bool(ClipStateGetSpan(@state, 1, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 50 And last = 250 And kind = #WALL_KIND_PASS),
        "PASS->PASS does not treat the earlier pass span as an occluder")
  Check(Bool(ClipSolidSegment(@state, 100, 150, 1, 2, 0, 0, 0, -1) <> 0), "following SOLID succeeds")
  Check(Bool(ClipStateGetSpan(@state, 2, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 100 And last = 150 And kind = #WALL_KIND_SOLID),
        "PASS->SOLID publishes the solid span and inserts its occlusion")
  Check(Bool(ClipPassSegment(@state, 50, 200, 2, 3, 0, 0, 0, -1) <> 0), "SOLID->PASS succeeds")
  Check(Bool(ClipStateGetSpan(@state, 3, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 50 And last = 99 And kind = #WALL_KIND_PASS), "SOLID->PASS left gap is [50,99]")
  Check(Bool(ClipStateGetSpan(@state, 4, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 151 And last = 200 And kind = #WALL_KIND_PASS), "SOLID->PASS right gap is [151,200]")
  Check(Bool(ClipSolidSegment(@state, 50, 250, 2, 4, 0, 0, 0, -1) <> 0), "final wider SOLID succeeds")
  Check(Bool(ClipStateGetSpan(@state, 5, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 50 And last = 99 And kind = #WALL_KIND_SOLID),
        "final solid prefix emitted after the earlier pass gaps")
  Check(Bool(ClipStateGetSpan(@state, 6, 0, 0, 0, 0, 0, 0, @first, @last, @kind) <> 0 And
        first = 151 And last = 250 And kind = #WALL_KIND_SOLID),
        "final solid suffix emitted last")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And
        spans = 7 And ranges = 3), "chronology emits seven spans and one merged real post")
  Check(Bool(ClipStateGetRange(@state, 1, @realFirst, @realLast) <> 0 And
        realFirst = 50 And realLast = 250), "final coverage is [50,250]")
  Check(Bool(ClipStateReset(@state) <> 0), "clip cleanup")
EndProcedure

Procedure TestWC25()
  Protected state.ClipState
  Protected Width.l
  Protected First.l
  Protected Last.l
  Protected Kind.l
  Protected firstKind.l
  Protected firstFirst.l
  Protected firstLast.l
  Protected secondKind.l
  Protected secondFirst.l
  Protected secondLast.l
  Protected seed.l
  Protected value.l
  Protected stepNo.i
  Protected mismatch.i = 0
  Protected beginOk.i = 0

  BeginCase("WC25", "Tiny-width exhaustive/seeded bitmap-oracle comparison")

  ; Width 8: every valid SOLID/PASS single operation.
  mismatch = 0
  For Kind = 0 To 1
    For First = 0 To 7
      For Last = First To 7
        beginOk = ClipStateBeginFrame(@state, 8)
        TestClippingOracleBegin(8)
        If beginOk = 0 Or TestClippingOneStep(@state, 8, First, Last, Kind, First) = 0
          mismatch + 1
        EndIf
        ClipStateReset(@state)
      Next
    Next
  Next
  Check(Bool(mismatch = 0), "all width-8 single SOLID/PASS operations match bitmap coverage and spans")

  ; Width 8: every ordered pair of operations, both kinds.
  mismatch = 0
  For firstKind = 0 To 1
    For firstFirst = 0 To 7
      For firstLast = firstFirst To 7
        For secondKind = 0 To 1
          For secondFirst = 0 To 7
            For secondLast = secondFirst To 7
              beginOk = ClipStateBeginFrame(@state, 8)
              TestClippingOracleBegin(8)
              If beginOk = 0 Or
                 TestClippingOneStep(@state, 8, firstFirst, firstLast, firstKind, firstFirst) = 0 Or
                 TestClippingOneStep(@state, 8, secondFirst, secondLast, secondKind, firstFirst) = 0
                mismatch + 1
              EndIf
              ClipStateReset(@state)
            Next
          Next
        Next
      Next
    Next
  Next
  Check(Bool(mismatch = 0), "all width-8 two-operation combinations match bitmap coverage and span order")

  ; Width 16 seeded deterministic sequence.
  mismatch = 0
  Width = 16
  seed = 12345
  beginOk = ClipStateBeginFrame(@state, Width)
  TestClippingOracleBegin(Width)
  If beginOk = 0
    mismatch + 1
  Else
    For stepNo = 0 To 199
      value = TestLcgNext(@seed)
      First = value % Width
      value = TestLcgNext(@seed)
      Last = First + value % (Width - First)
      value = TestLcgNext(@seed)
      Kind = value % 2
      If TestClippingOneStep(@state, Width, First, Last, Kind, seed) = 0
        mismatch + 1
        Break
      EndIf
    Next
  EndIf
  Check(Bool(mismatch = 0), "200 deterministic width-16 seeded operations match the bitmap oracle")
  ClipStateReset(@state)

  ; Width 32 seeded deterministic sequence.
  mismatch = 0
  Width = 32
  seed = 54321
  beginOk = ClipStateBeginFrame(@state, Width)
  TestClippingOracleBegin(Width)
  If beginOk = 0
    mismatch + 1
  Else
    For stepNo = 0 To 299
      value = TestLcgNext(@seed)
      First = value % Width
      value = TestLcgNext(@seed)
      Last = First + value % (Width - First)
      value = TestLcgNext(@seed)
      Kind = value % 2
      If TestClippingOneStep(@state, Width, First, Last, Kind, seed) = 0
        mismatch + 1
        Break
      EndIf
    Next
  EndIf
  Check(Bool(mismatch = 0), "300 deterministic width-32 seeded operations match the bitmap oracle")
  ClipStateReset(@state)
EndProcedure

Procedure TestWC26()
  Protected state.ClipState
  Protected width.l = 0
  Protected ranges.l = 0
  Protected spans.l = 0
  Protected rangeGrowths.l = 0
  Protected spanGrowths.l = 0
  Protected allocations.l = 0
  Protected firstSentinel.l = 0
  Protected lastSentinel.l = 0
  Protected seed.l = 45678
  Protected value.l = 0
  Protected First.l
  Protected Last.l
  Protected stepNo.i
  Protected mismatch.i = 0
  Protected growthFail.i = 0
  Protected outFirst.l = -99
  Protected outLast.l = -99

  BeginCase("WC26", "Bad ranges, growth budget, reset and output invariant contract")

  Check(Bool(ClipStateBeginFrame(0, 320) = 0), "null clip state pointer is rejected")
  Check(Bool(ClipStateBeginFrame(@state, 0) = 0), "width 0 is rejected before state mutation")
  Check(Bool(ClipStateBeginFrame(@state, 321) = 0), "width 321 exceeds the 320 safety cap")
  Check(Bool(ClipStateReset(0) = 0), "null clip reset is rejected")
  Check(Bool(ClipStateGetRange(0, 0, 0, 0) = 0), "null clip range accessor is rejected")
  Check(Bool(ClipSolidSegment(0, 0, 0, 0, 0, 0, 0, 0, -1) = 0), "null solid clip is rejected")
  Check(Bool(ClipPassSegment(0, 0, 0, 0, 0, 0, 0, 0, -1) = 0), "null pass clip is rejected")

  Check(Bool(ClipStateBeginFrame(@state, 8) <> 0), "valid tiny width 8 begins")
  ClipStateGetStats(@state, @width, @ranges, @spans, 0, 0, 0)
  Check(Bool(ClipStateBeginFrame(@state, 321) = 0 And
        ClipStateGetStats(@state, @width, @ranges, @spans, 0, 0, 0) <> 0 And
        width = 8 And ranges = 2 And spans = 0),
        "a rejected rebuild leaves the existing valid frame unchanged")

  Check(Bool(ClipSolidSegment(@state, -1, 0, 0, 0, 0, 0, 0, -1) = 0), "negative first column is rejected")
  Check(Bool(ClipSolidSegment(@state, 5, 4, 0, 0, 0, 0, 0, -1) = 0), "inverted range First>Last is rejected")
  Check(Bool(ClipSolidSegment(@state, 0, 8, 0, 0, 0, 0, 0, -1) = 0), "Last>=width is rejected")
  ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0)
  Check(Bool(ranges = 2 And spans = 0), "every rejected clip leaves ranges and spans unchanged")
  Check(Bool(ClipStateGetRange(@state, 0, @firstSentinel, @lastSentinel) <> 0 And
        firstSentinel = -2147483647 And lastSentinel = -1),
        "rejected clips preserve both sentinel invariants")
  outFirst = -99
  outLast = -99
  Check(Bool(ClipStateGetRange(@state, 9, @outFirst, @outLast) = 0 And outFirst = -99 And outLast = -99),
        "invalid range access rejects without touching outputs")

  Check(Bool(ClipStateBeginFrame(@state, 32) <> 0), "width 32 growth-budget frame begins")
  seed = 45678
  For stepNo = 0 To 149
    value = TestLcgNext(@seed)
    First = value % 32
    value = TestLcgNext(@seed)
    Last = First + value % (32 - First)
    value = TestLcgNext(@seed)
    If value % 2 = 0
      If ClipSolidSegment(@state, First, Last, stepNo, stepNo, 0, 0, 0, -1) = 0
        mismatch + 1
        Break
      EndIf
    Else
      If ClipPassSegment(@state, First, Last, stepNo, stepNo, 0, 0, 0, -1) = 0
        mismatch + 1
        Break
      EndIf
    EndIf
  Next
  Check(Bool(mismatch = 0), "150 bounded width-32 operations stay inside all clipping caps")
  Check(Bool(mismatch = 0), "150 bounded width-32 operations stay inside all clipping caps")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, @rangeGrowths, @spanGrowths, @allocations) <> 0 And
        ranges >= 2 And ranges <= 18 And spans >= 0 And spans <= #CLIP_MaxSpans And
        allocations >= 2),
        "150-operation frame remains inside the range/span/cap budget")
  Check(Bool(ClipStateReset(@state) <> 0), "setup reset before the range-growth burst")

  ; Range growth burst: sixteen disjoint one-column posts plus sentinels.
  Check(Bool(ClipStateBeginFrame(@state, 32) <> 0), "width-32 range-growth burst begins")
  growthFail = 0
  For First = 0 To 30 Step 2
    If ClipSolidSegment(@state, First, First, stepNo, stepNo, 0, 0, 0, -1) = 0
      growthFail + 1
      Break
    EndIf
  Next
  Check(Bool(growthFail = 0), "sixteen disjoint one-column SOLID operations succeed")
  ClipStateGetStats(@state, 0, @ranges, @spans, @rangeGrowths, @spanGrowths, @allocations)
  Check(Bool(ranges = 18 And spanGrowths = 0 And rangeGrowths > 0 And allocations > 2),
        "range storage grows transactionally to 18 sentinel-inclusive posts")
  Check(Bool(ClipStateReset(@state) <> 0), "reset after range growth")

  ; Span growth burst: PASS never adds occlusion posts, so repeated columns each
  ; publish a fragment until the initial 64-span capacity is exceeded.
  Check(Bool(ClipStateBeginFrame(@state, 32) <> 0), "width-32 span-growth burst begins")
  growthFail = 0
  For stepNo = 0 To 69
    If ClipPassSegment(@state, stepNo % 32, stepNo % 32, stepNo, stepNo, 0, 0, 0, -1) = 0
      growthFail + 1
      Break
    EndIf
  Next
  Check(Bool(growthFail = 0), "seventy PASS operations remain bounded")
  ClipStateGetStats(@state, 0, @ranges, @spans, @rangeGrowths, @spanGrowths, @allocations)
  Check(Bool(spans = 70 And rangeGrowths = 0 And spanGrowths > 0 And allocations > 2),
        "span storage grows transactionally past the initial 64-span capacity")
  Check(Bool(ClipStateReset(@state) <> 0 And ClipStateReset(@state) <> 0),
        "repeated reset is idempotent and frees owned storage")
  Check(Bool(ClipStateGetRange(@state, 0, 0, 0) = 0), "post-reset range access is rejected")
EndProcedure

; ---------------------------------------------------------------------------
; Test-only R_AddLine reference translation and measurement bridge
; ---------------------------------------------------------------------------

; Canonical flat-slot rule of the documented fallback: printable bytes before
; the first NUL, then only NUL/space padding, and a nonempty result.
Procedure.i TestRefFlatCanonical(*Level.MapLevel, Sector.l, Field.l)
  Protected byteIndex.i
  Protected value.i
  Protected sawNul.i = 0

  sawNul = #False
  For byteIndex = 0 To 7
    value = MapSectorsNameByte(@*Level\Sectors, Sector, Field, byteIndex)
    If value < 0
      ProcedureReturn #False
    EndIf
    If sawNul
      If value <> 0 And value <> 32
        ProcedureReturn #False
      EndIf
    ElseIf value = 0
      sawNul = #True
    ElseIf value < 32 Or value > 126
      ProcedureReturn #False
    EndIf
  Next
  ; A slot that starts with NUL and only padding is noncanonical (empty).
  If MapSectorsNameByte(@*Level\Sectors, Sector, Field, 0) = 0
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

; Canonical raw eight-byte identity fallback used for reference classification.
Procedure.i TestRefFlatSame(*Level.MapLevel, SectorA.l, SectorB.l, Field.l)
  Protected byteIndex.i
  Protected byteA.i
  Protected byteB.i

  If TestRefFlatCanonical(*Level, SectorA, Field) = #False Or
     TestRefFlatCanonical(*Level, SectorB, Field) = #False
    ProcedureReturn 0
  EndIf
  For byteIndex = 0 To 7
    byteA = MapSectorsNameByte(@*Level\Sectors, SectorA, Field, byteIndex)
    byteB = MapSectorsNameByte(@*Level\Sectors, SectorB, Field, byteIndex)
    If byteA <> byteB
      ProcedureReturn 0
    EndIf
  Next
  ProcedureReturn 1
EndProcedure

; Fallback middle absence: canonical "-"/all-NUL only. Malformed slots are
; conservatively present, exactly the documented DoomPB policy.
Procedure.i TestRefMiddleAbsent(*Level.MapLevel, Side.l)
  Protected byteIndex.i
  Protected value.i

  value = MapSidedefsNameByte(@*Level\Sidedefs, Side, 2, 0)
  If value < 0
    ProcedureReturn 0
  EndIf
  If value = 0 Or value = Asc("-")
    For byteIndex = 1 To 7
      value = MapSidedefsNameByte(@*Level\Sidedefs, Side, 2, byteIndex)
      If value < 0 Or (value <> 0 And value <> 32)
        ProcedureReturn 0
      EndIf
    Next
    ProcedureReturn 1
  EndIf
  ProcedureReturn 0
EndProcedure

; Independent test-only translation of original R_AddLine branch order using the
; same verified geometry primitive and generated fixture tables, but no
; production Projection/Clip/Wall helpers. Reads validated map records through
; public M2 accessors. Outputs outcome status and, for SOLID/PASS, inclusive
; candidate [x1,x2-1]. No clipping state is consulted; classification fallback
; mirrors the documented raw canonical policy.
Procedure.i TestRefAddLine(*Level.MapLevel, CameraX.l, CameraY.l, Heading.q,
                           Subsector.l, Seg.l,
                           *Status.Long, *FirstX.Long, *LastX.Long)
  Protected v1.l
  Protected v2.l
  Protected segAngle.l
  Protected segLine.l
  Protected segSide.l
  Protected segOffset.l
  Protected vertexX1.l
  Protected vertexY1.l
  Protected vertexX2.l
  Protected vertexY2.l
  Protected fixedX1.l = 0
  Protected fixedY1.l = 0
  Protected fixedX2.l = 0
  Protected fixedY2.l = 0
  Protected frontSector.l
  Protected backSector.l
  Protected side0.l
  Protected side1.l
  Protected selectedSide.l
  Protected frontFloor.l
  Protected frontCeiling.l
  Protected frontLight.l
  Protected backFloor.l
  Protected backCeiling.l
  Protected backLight.l
  Protected angle1.BamAngleValue
  Protected angle2.BamAngleValue
  Protected span.q
  Protected relative1.q
  Protected relative2.q
  Protected tspan.q
  Protected twoClip.q
  Protected clipAngle.q
  Protected fixtureClip.q
  Protected fine1.q
  Protected fine2.q
  Protected x1.l
  Protected x2.l
  Protected sameFloor.l
  Protected sameCeiling.l
  Protected sameLight.i
  Protected middleAbsent.l
  Protected kind.l
  Protected evaluatedValue.l = 0

  *Status\l = -1
  *FirstX\l = -1
  *LastX\l = -1

  If MapSegsGet(@*Level\Segs, Seg, @v1, @v2, @segAngle, @segLine, @segSide, @segOffset) = #False
    ProcedureReturn #False
  EndIf
  If MapVertexesGet(@*Level\Vertexes, v1, @vertexX1, @vertexY1) = #False
    ProcedureReturn #False
  EndIf
  If MapVertexesGet(@*Level\Vertexes, v2, @vertexX2, @vertexY2) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexX1, @fixedX1) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexY1, @fixedY1) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexX2, @fixedX2) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexY2, @fixedY2) = #False
    ProcedureReturn #False
  EndIf
  If MapLevelGetSegLinks(*Level, Seg, @segLine, @segSide, @frontSector, @backSector) = #False
    ProcedureReturn #False
  EndIf
  If MapLinedefsGet(@*Level\Linedefs, segLine, 0, 0, 0, 0, 0, @side0, @side1) = #False
    ProcedureReturn #False
  EndIf
  If segSide = 0
    selectedSide = side0
  Else
    selectedSide = side1
  EndIf

  If GeometryPointToAngleChecked(CameraX, CameraY, fixedX1, fixedY1, @angle1) = #False
    ProcedureReturn #False
  EndIf
  If GeometryPointToAngleChecked(CameraX, CameraY, fixedX2, fixedY2, @angle2) = #False
    ProcedureReturn #False
  EndIf
  span = BamSubtract(angle1\Raw, angle2\Raw)
  If span >= #BAM_ANG180
    *Status\l = #WALLLINE_Backface
    ProcedureReturn #True
  EndIf

  relative1 = BamSubtract(angle1\Raw, Heading)
  relative2 = BamSubtract(angle2\Raw, Heading)
  fixtureClip = PeekQ(*gGoldClipAngle)
  clipAngle = fixtureClip
  twoClip = BamAdd(clipAngle, clipAngle)

  tspan = BamAdd(relative1, clipAngle)
  If tspan > twoClip
    tspan = BamSubtract(tspan, twoClip)
    If tspan >= span
      *Status\l = #WALLLINE_FovLeft
      ProcedureReturn #True
    EndIf
    relative1 = clipAngle
  EndIf
  tspan = BamSubtract(clipAngle, relative2)
  If tspan > twoClip
    tspan = BamSubtract(tspan, twoClip)
    If tspan >= span
      *Status\l = #WALLLINE_FovRight
      ProcedureReturn #True
    EndIf
    relative2 = BamNegate(clipAngle)
  EndIf

  fine1 = BamFineIndex(BamAdd(relative1, #BAM_ANG90))
  fine2 = BamFineIndex(BamAdd(relative2, #BAM_ANG90))
  If fine1 >= 4096 Or fine2 >= 4096
    ProcedureReturn #False
  EndIf
  x1 = PeekL(*gGoldForward + Int(fine1) * 4)
  x2 = PeekL(*gGoldForward + Int(fine2) * 4)
  If x1 = x2
    *Status\l = #WALLLINE_ZeroWidth
    *FirstX\l = x1
    *LastX\l = x2
    ProcedureReturn #True
  EndIf
  If x2 <= x1
    ProcedureReturn #False
  EndIf

  If backSector = #WALLVIS_NoIndex
    kind = #WALL_KIND_SOLID
  Else
    If MapSectorsGet(@*Level\Sectors, frontSector, @frontFloor, @frontCeiling, @frontLight, 0, 0) = #False
      ProcedureReturn #False
    EndIf
    If MapSectorsGet(@*Level\Sectors, backSector, @backFloor, @backCeiling, @backLight, 0, 0) = #False
      ProcedureReturn #False
    EndIf
    If backCeiling <= frontFloor Or backFloor >= frontCeiling
      kind = #WALL_KIND_SOLID
    ElseIf backCeiling <> frontCeiling Or backFloor <> frontFloor
      kind = #WALL_KIND_PASS
    Else
      sameFloor = TestRefFlatSame(*Level, frontSector, backSector, 0)
      sameCeiling = TestRefFlatSame(*Level, frontSector, backSector, 1)
      sameLight = Bool(backLight = frontLight)
      middleAbsent = TestRefMiddleAbsent(*Level, selectedSide)
      If sameFloor <> 0 And sameCeiling <> 0 And sameLight <> 0 And middleAbsent <> 0
        *Status\l = #WALLLINE_EmptySkip
        ProcedureReturn #True
      EndIf
      kind = #WALL_KIND_PASS
    EndIf
  EndIf

  If kind = #WALL_KIND_SOLID
    *Status\l = #WALLLINE_Solid
    *FirstX\l = x1
    *LastX\l = x2 - 1
  Else
    *Status\l = #WALLLINE_Pass
    *FirstX\l = x1
    *LastX\l = x2 - 1
  EndIf
  ProcedureReturn #True
EndProcedure

; Runs production WallVisibilityAddLine on one seg in an empty 320-column clip
; frame, runs the independent reference, and returns Bool(all measured status/
; span fields agree). Production/test objects are local and always cleaned up.
Procedure.i TestMeasureOneAddLine(*Level.MapLevel, MapX.q, MapY.q, Heading.q,
                                  Subsector.l, Seg.l,
                                  *ProdStatus.Long, *ProdEmitted.Long,
                                  *ProdFirst.Long, *ProdLast.Long,
                                  *ProdSpanCount.Long, *ProdRangeCount.Long,
                                  *RefStatus.Long, *RefFirst.Long, *RefLast.Long)
  Protected camera.BspCamera
  Protected projection.Projection
  Protected state.ClipState
  Protected clipCreated.i = 0
  Protected projectionCreated.i = 0
  Protected setupOk.i = 1
  Protected callOk.i = 1
  Protected refOk.i = 1
  Protected agree.i = 2
  Protected spanKind.l = 0
  Protected statsOk.i = 1
  Protected prodStatusVar.l = -1
  Protected prodEmissionVar.l = -1
  Protected prodCountVar.l = -1
  Protected prodRangeCountVar.l = -1
  Protected prodSpanFirstVar.l = -1
  Protected prodSpanLastVar.l = -1
  Protected refStatusVar.l = -1
  Protected refFirstVar.l = -1
  Protected refLastVar.l = -1
  Protected refCameraX.l = 0
  Protected refCameraY.l = 0
  Protected refHeading.q = 0

  *ProdStatus\l = -1
  *ProdEmitted\l = -1
  *ProdFirst\l = -1
  *ProdLast\l = -1
  *ProdSpanCount\l = -1
  *ProdRangeCount\l = -1
  *RefStatus\l = -1
  *RefFirst\l = -1
  *RefLast\l = -1

  If BspCameraSetMapUnits(@camera, MapX, MapY, Heading) = #False
    setupOk = 0
  EndIf
  If ProjectionInitClassic(@projection) = #False
    setupOk = 0
  Else
    projectionCreated = 1
  EndIf
  If setupOk <> 0
    If ClipStateBeginFrame(@state, 320) = #False
      setupOk = 0
    Else
      clipCreated = 1
    EndIf
  EndIf
  If setupOk <> 0
    If BspCameraGet(@camera, @refCameraX, @refCameraY, @refHeading) = #False
      setupOk = 0
    EndIf
  EndIf
  If setupOk <> 0
    If WallVisibilityAddLine(*Level, @camera, @projection, 0, 0, @state,
                             Subsector, Seg, @prodStatusVar, @prodEmissionVar) = #False
      callOk = 0
    EndIf
  EndIf

  If callOk <> 0
    *ProdStatus\l = prodStatusVar
    *ProdEmitted\l = prodEmissionVar
    If ClipStateGetStats(@state, 0, @prodRangeCountVar, @prodCountVar, 0, 0, 0) = #False
      statsOk = 0
    Else
      *ProdSpanCount\l = prodCountVar
      *ProdRangeCount\l = prodRangeCountVar
    EndIf
    If *ProdSpanCount\l > 0
      If ClipStateGetSpan(@state, 0, 0, 0, 0, 0, 0, 0,
                          @prodSpanFirstVar, @prodSpanLastVar, @spanKind) = #False
        statsOk = 0
      Else
        *ProdFirst\l = prodSpanFirstVar
        *ProdLast\l = prodSpanLastVar
      EndIf
    EndIf
    If statsOk = 0
      callOk = 0
    EndIf
  EndIf

  If TestRefAddLine(*Level, refCameraX, refCameraY, refHeading,
                    Subsector, Seg, @refStatusVar, @refFirstVar, @refLastVar) = #False
    refOk = 0
  EndIf
  If callOk <> 0 And refOk <> 0
    *RefStatus\l = refStatusVar
    *RefFirst\l = refFirstVar
    *RefLast\l = refLastVar
    agree = 0
    If *ProdStatus\l = *RefStatus\l
      If *RefStatus\l = #WALLLINE_Solid
        If *ProdEmitted\l = 1 And *ProdSpanCount\l = 1 And
           *ProdFirst\l = *RefFirst\l And *ProdLast\l = *RefLast\l And
           spanKind = #WALL_KIND_SOLID
          agree = 1
        EndIf
      ElseIf *RefStatus\l = #WALLLINE_Pass
        If *ProdEmitted\l = 1 And *ProdSpanCount\l = 1 And
           *ProdFirst\l = *RefFirst\l And *ProdLast\l = *RefLast\l And
           spanKind = #WALL_KIND_PASS
          agree = 1
        EndIf
      Else
        If *ProdEmitted\l = 0 And *ProdSpanCount\l = 0
          agree = 1
        EndIf
      EndIf
    EndIf
  EndIf

  If clipCreated <> 0
    ClipStateReset(@state)
  EndIf
  If projectionCreated <> 0
    ProjectionReset(@projection)
  EndIf
  ProcedureReturn Bool(setupOk <> 0 And callOk <> 0 And refOk <> 0 And agree <> 0)
EndProcedure

; ---------------------------------------------------------------------------
; Generic two-sector two-sided wall fixture (WC34-WC39)
; ---------------------------------------------------------------------------
; Front parameters belong to the seg-selected sidedef's sector. For SegSide=0
; that is sector0/side0; for SegSide=1 it is sector1/side1 and the geometry is
; reversed (seg V1=vertex1, V2=vertex0) to preserve the original right-side
; orientation. The back parameters belong to the opposite linedef side. The
; caller chooses the linedef flags; two-sided tests include #MAP_ML_TWOSIDED.
Procedure.i TestBuildTwoSectorWall(*Level.MapLevel,
                                  V0X.l, V0Y.l, V1X.l, V1Y.l,
                                  FrontFloor.l, FrontCeil.l, FrontLight.l,
                                  FrontFloorName.s, FrontCeilName.s,
                                  BackFloor.l, BackCeil.l, BackLight.l,
                                  BackFloorName.s, BackCeilName.s,
                                  SegSide.l, Mid0.s, Mid1.s, Flags.l)
  Protected Dim sectors.TestSectorSpec(1)
  Protected Dim lines.TestLineSpec(0)
  Protected Dim sides.TestSideSpec(1)
  Protected Dim vertices.TestVertexSpec(1)
  Protected Dim segs.TestSegSpec(0)
  Protected Dim subs.TestSubSpec(0)

  If SegSide <> 0 And SegSide <> 1
    ProcedureReturn #False
  EndIf

  If SegSide = 0
    sectors(0)\FloorHeight = FrontFloor
    sectors(0)\CeilingHeight = FrontCeil
    sectors(0)\LightLevel = FrontLight
    sectors(0)\FloorName = FrontFloorName
    sectors(0)\CeilingName = FrontCeilName
    sectors(1)\FloorHeight = BackFloor
    sectors(1)\CeilingHeight = BackCeil
    sectors(1)\LightLevel = BackLight
    sectors(1)\FloorName = BackFloorName
    sectors(1)\CeilingName = BackCeilName
  Else
    sectors(1)\FloorHeight = FrontFloor
    sectors(1)\CeilingHeight = FrontCeil
    sectors(1)\LightLevel = FrontLight
    sectors(1)\FloorName = FrontFloorName
    sectors(1)\CeilingName = FrontCeilName
    sectors(0)\FloorHeight = BackFloor
    sectors(0)\CeilingHeight = BackCeil
    sectors(0)\LightLevel = BackLight
    sectors(0)\FloorName = BackFloorName
    sectors(0)\CeilingName = BackCeilName
  EndIf

  lines(0)\V1 = 0
  lines(0)\V2 = 1
  lines(0)\Flags = Flags
  lines(0)\Special = 0
  lines(0)\Tag = 0
  lines(0)\Side0 = 0
  lines(0)\Side1 = 1

  sides(0)\Sector = 0
  sides(0)\TopName = "WALL1"
  sides(0)\BottomName = "WALL1"
  sides(0)\MidName = Mid0
  sides(1)\Sector = 1
  sides(1)\TopName = "WALL1"
  sides(1)\BottomName = "WALL1"
  sides(1)\MidName = Mid1

  vertices(0)\X = V0X
  vertices(0)\Y = V0Y
  vertices(1)\X = V1X
  vertices(1)\Y = V1Y

  If SegSide = 0
    segs(0)\V1 = 0
    segs(0)\V2 = 1
  Else
    segs(0)\V1 = 1
    segs(0)\V2 = 0
  EndIf
  segs(0)\Line = 0
  segs(0)\Side = SegSide

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1

  ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), 2, @lines(0), 1, @sides(0), 2,
                                       @vertices(0), 2, @segs(0), 1, @subs(0), 1, 0, 0)
EndProcedure

; ---------------------------------------------------------------------------
; Independent test-only clipping oracle for the recursive online walk
; ---------------------------------------------------------------------------
; Original solidsegs semantics without production ClipSegs: two fixed sentinels,
; a per-column coverage bitmap for uncovered fragment emission (left-to-right),
; and a sorted real-post list used only by the bbox containment scan. Solid
; updates merge touching/overlapping posts into one; PASS never changes posts.

Procedure.i TestRefClipBeginFrame(Width.l)
  Protected column.i

  If Width < 1 Or Width > #CLIP_MaxWidth
    ProcedureReturn #False
  EndIf
  gRefSpanCount = 0
  gRefClipCount = 2
  gRefClipFirst(0) = #CLIP_SentinelMinFirst
  gRefClipLast(0) = #CLIP_SentinelMinLast
  gRefClipFirst(1) = Width
  gRefClipLast(1) = #CLIP_SentinelMaxLast
  For column = 0 To Width - 1
    gRefCovered(column) = 1
  Next
  For column = Width To #CLIP_MaxWidth - 1
    gRefCovered(column) = 0
  Next
  ProcedureReturn #True
EndProcedure

Procedure.i TestRefClipAppend(First.l, Last.l, Kind.l,
                             Subsector.l, Seg.l, Linedef.l, Side.l,
                             FrontSector.l, BackSector.l)
  If gRefSpanCount >= 4096
    ProcedureReturn #False
  EndIf
  gRefSpanSubsector(gRefSpanCount) = Subsector
  gRefSpanSeg(gRefSpanCount) = Seg
  gRefSpanFirst(gRefSpanCount) = First
  gRefSpanLast(gRefSpanCount) = Last
  gRefSpanKind(gRefSpanCount) = Kind
  gRefSpanLine(gRefSpanCount) = Linedef
  gRefSpanSide(gRefSpanCount) = Side
  gRefSpanFront(gRefSpanCount) = FrontSector
  gRefSpanBack(gRefSpanCount) = BackSector
  gRefSpanCount + 1
  ProcedureReturn #True
EndProcedure

Procedure.i TestRefClipEmit(First.l, Last.l, Kind.l,
                           Subsector.l, Seg.l, Linedef.l, Side.l,
                           FrontSector.l, BackSector.l)
  Protected column.i
  Protected runStart.l = -1

  For column = First To Last
    If gRefCovered(column) <> 0
      If runStart < 0
        runStart = column
      EndIf
    ElseIf runStart >= 0
      If TestRefClipAppend(runStart, column - 1, Kind,
                           Subsector, Seg, Linedef, Side,
                           FrontSector, BackSector) = #False
        ProcedureReturn #False
      EndIf
      runStart = -1
    EndIf
  Next
  If runStart >= 0
    If TestRefClipAppend(runStart, Last, Kind,
                         Subsector, Seg, Linedef, Side,
                         FrontSector, BackSector) = #False
      ProcedureReturn #False
    EndIf
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure.i TestRefClipMergePost(First.l, Last.l)
  Protected i.i
  Protected startIndex.i = -1
  Protected endIndex.i = -1
  Protected newFirst.l
  Protected newLast.l
  Protected removed.l
  Protected target.i

  For i = 1 To gRefClipCount - 2
    If First <= gRefClipLast(i) + 1 And Last >= gRefClipFirst(i) - 1
      If startIndex < 0
        startIndex = i
      EndIf
      endIndex = i
    EndIf
  Next
  If startIndex < 0
    ; No touching real post: insert at the sorted position before the fixed
    ; right sentinel. Caller width makes the real-post cap incidentally small.
    i = 1
    While i <= gRefClipCount - 2 And gRefClipFirst(i) < First
      i + 1
    Wend
    If gRefClipCount >= #CLIP_MaxRanges
      ProcedureReturn #False
    EndIf
    For target = gRefClipCount - 1 To i Step - 1
      gRefClipFirst(target + 1) = gRefClipFirst(target)
      gRefClipLast(target + 1) = gRefClipLast(target)
    Next
    gRefClipFirst(i) = First
    gRefClipLast(i) = Last
    gRefClipCount + 1
    ProcedureReturn #True
  EndIf

  newFirst = gRefClipFirst(startIndex)
  If First < newFirst
    newFirst = First
  EndIf
  newLast = gRefClipLast(endIndex)
  If Last > newLast
    newLast = Last
  EndIf
  gRefClipFirst(startIndex) = newFirst
  gRefClipLast(startIndex) = newLast
  removed = endIndex - startIndex
  If removed > 0
    For i = endIndex + 1 To gRefClipCount - 1
      gRefClipFirst(i - removed) = gRefClipFirst(i)
      gRefClipLast(i - removed) = gRefClipLast(i)
    Next
    gRefClipCount - removed
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure.i TestRefClipApply(First.l, Last.l, Kind.l,
                            Subsector.l, Seg.l, Linedef.l, Side.l,
                            FrontSector.l, BackSector.l)
  Protected width.l
  Protected column.i

  width = gRefClipFirst(gRefClipCount - 1)
  If First < 0 Or Last < First Or Last > width - 1
    ProcedureReturn #False
  EndIf
  If TestRefClipEmit(First, Last, Kind, Subsector, Seg, Linedef, Side,
                     FrontSector, BackSector) = #False
    ProcedureReturn #False
  EndIf
  If Kind = #WALL_KIND_SOLID
    For column = First To Last
      gRefCovered(column) = 0
    Next
    If TestRefClipMergePost(First, Last) = #False
      ProcedureReturn #False
    EndIf
  EndIf
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent test-only FOV clip branch translations (WC29/WC30, bbox)
; ---------------------------------------------------------------------------

Procedure.i TestRefFovLeftAdjust(Relative.q, Span.q, Clip.q,
                               *Adjusted.Quad, *Rejected.Long)
  Protected twoClip.q
  Protected tspan.q

  If *Adjusted = 0 Or *Rejected = 0
    ProcedureReturn #False
  EndIf
  twoClip = BamAdd(Clip, Clip)
  tspan = BamAdd(Relative, Clip)
  If tspan > twoClip
    tspan = BamSubtract(tspan, twoClip)
    If tspan >= Span
      PokeQ(*Adjusted, 0)
      *Rejected\l = 1
      ProcedureReturn #True
    EndIf
    PokeQ(*Adjusted, BamWrap32(Clip))
    *Rejected\l = 0
    ProcedureReturn #True
  EndIf
  PokeQ(*Adjusted, BamWrap32(Relative))
  *Rejected\l = 0
  ProcedureReturn #True
EndProcedure

Procedure.i TestRefFovRightAdjust(Relative.q, Span.q, Clip.q,
                                *Adjusted.Quad, *Rejected.Long)
  Protected twoClip.q
  Protected tspan.q

  If *Adjusted = 0 Or *Rejected = 0
    ProcedureReturn #False
  EndIf
  twoClip = BamAdd(Clip, Clip)
  tspan = BamSubtract(Clip, Relative)
  If tspan > twoClip
    tspan = BamSubtract(tspan, twoClip)
    If tspan >= Span
      PokeQ(*Adjusted, 0)
      *Rejected\l = 1
      ProcedureReturn #True
    EndIf
    PokeQ(*Adjusted, BamNegate(Clip))
    *Rejected\l = 0
    ProcedureReturn #True
  EndIf
  PokeQ(*Adjusted, BamWrap32(Relative))
  *Rejected\l = 0
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent test-only R_CheckBBox translation
; ---------------------------------------------------------------------------

Procedure.i TestRefCheckCoordGet(Row.l, Col.l, *Value.Long)
  If *Value = 0
    ProcedureReturn #False
  EndIf
  If Row < 0 Or Row > #WALL_CHECKCOORD_ROWS - 1 Or
     Col < 0 Or Col > #WALL_CHECKCOORD_COLS - 1
    ProcedureReturn #False
  EndIf
  *Value\l = PeekB(*gRefCheckCoordData + Row * #WALL_CHECKCOORD_COLS + Col)
  ProcedureReturn #True
EndProcedure

Procedure.i TestRefCheckBBox(*Level.MapLevel, NodeIndex.l, BoxIndex.l,
                            CameraX.l, CameraY.l, Heading.q,
                            *Verdict.Long)
  Protected box0Top.l
  Protected box0Bottom.l
  Protected box0Left.l
  Protected box0Right.l
  Protected box1Top.l
  Protected box1Bottom.l
  Protected box1Left.l
  Protected box1Right.l
  Protected topValue.l = 0
  Protected bottomValue.l = 0
  Protected leftValue.l = 0
  Protected rightValue.l = 0
  Protected Dim bboxCoord.l(3)
  Protected boxXIndex.l
  Protected boxYIndex.l
  Protected boxPosition.l
  Protected row.l
  Protected coordIndex.l = 0
  Protected cornerValue.l = 0
  Protected x1.l = 0
  Protected y1.l = 0
  Protected x2.l = 0
  Protected y2.l = 0
  Protected angle1.BamAngleValue
  Protected angle2.BamAngleValue
  Protected relative1.q
  Protected relative2.q
  Protected span.q
  Protected clipAngle.q
  Protected adjustedLeft.q = 0
  Protected adjustedRight.q = 0
  Protected rejectedLeft.l = 0
  Protected rejectedRight.l = 0
  Protected fine1.q
  Protected fine2.q
  Protected sx1.l = 0
  Protected sx2.l = 0
  Protected startIndex.i

  *Verdict\l = -1
  If *Verdict = 0 Or *Level = 0
    ProcedureReturn #False
  EndIf
  If MapLevelIsReady(*Level) = #False
    ProcedureReturn #False
  EndIf
  If NodeIndex < 0 Or NodeIndex >= *Level\Nodes\Count Or
     BoxIndex <> 0 And BoxIndex <> 1
    ProcedureReturn #False
  EndIf
  If MapNodesGet(@*Level\Nodes, NodeIndex, 0, 0, 0, 0,
                 @box0Top, @box0Bottom, @box0Left, @box0Right,
                 @box1Top, @box1Bottom, @box1Left, @box1Right,
                 0, 0) = #False
    ProcedureReturn #False
  EndIf
  If BoxIndex = 0
    topValue = box0Top
    bottomValue = box0Bottom
    leftValue = box0Left
    rightValue = box0Right
  Else
    topValue = box1Top
    bottomValue = box1Bottom
    leftValue = box1Left
    rightValue = box1Right
  EndIf
  If FixedFromIntChecked(topValue, @bboxCoord(0)) = #False Or
     FixedFromIntChecked(bottomValue, @bboxCoord(1)) = #False Or
     FixedFromIntChecked(leftValue, @bboxCoord(2)) = #False Or
     FixedFromIntChecked(rightValue, @bboxCoord(3)) = #False
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf

  If CameraX <= bboxCoord(2)
    boxXIndex = 0
  ElseIf CameraX < bboxCoord(3)
    boxXIndex = 1
  Else
    boxXIndex = 2
  EndIf
  If CameraY >= bboxCoord(0)
    boxYIndex = 0
  ElseIf CameraY > bboxCoord(1)
    boxYIndex = 1
  Else
    boxYIndex = 2
  EndIf
  boxPosition = (boxYIndex << 2) + boxXIndex
  If boxPosition = 5
    *Verdict\l = #REFBBOX_Visible
    ProcedureReturn #True
  EndIf
  If boxPosition < 0 Or boxPosition > #WALL_CHECKCOORD_ROWS - 1
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If boxPosition = 3 Or boxPosition = 7 Or boxPosition = 11
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf

  clipAngle = PeekQ(*gGoldClipAngle)
  row = boxPosition
  If TestRefCheckCoordGet(row, 0, @coordIndex) = #False Or coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  cornerValue = bboxCoord(coordIndex)
  x1 = cornerValue
  If TestRefCheckCoordGet(row, 1, @coordIndex) = #False Or coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  y1 = bboxCoord(coordIndex)
  If TestRefCheckCoordGet(row, 2, @coordIndex) = #False Or coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  x2 = bboxCoord(coordIndex)
  If TestRefCheckCoordGet(row, 3, @coordIndex) = #False Or coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  y2 = bboxCoord(coordIndex)

  If GeometryPointToAngleChecked(CameraX, CameraY, x1, y1, @angle1) = #False Or
     GeometryPointToAngleChecked(CameraX, CameraY, x2, y2, @angle2) = #False
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  relative1 = BamSubtract(angle1\Raw, Heading)
  relative2 = BamSubtract(angle2\Raw, Heading)
  span = BamSubtract(relative1, relative2)
  If span >= #BAM_ANG180
    *Verdict\l = #REFBBOX_Visible
    ProcedureReturn #True
  EndIf

  If TestRefFovLeftAdjust(relative1, span, clipAngle, @adjustedLeft, @rejectedLeft) = #False
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If rejectedLeft <> 0
    *Verdict\l = #REFBBOX_Occluded
    ProcedureReturn #True
  EndIf
  relative1 = adjustedLeft

  If TestRefFovRightAdjust(relative2, span, clipAngle, @adjustedRight, @rejectedRight) = #False
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If rejectedRight <> 0
    *Verdict\l = #REFBBOX_Occluded
    ProcedureReturn #True
  EndIf
  relative2 = adjustedRight

  fine1 = BamFineIndex(BamAdd(relative1, #BAM_ANG90))
  fine2 = BamFineIndex(BamAdd(relative2, #BAM_ANG90))
  If fine1 >= #PROJ_VIEWANGLE_TOX_COUNT Or fine2 >= #PROJ_VIEWANGLE_TOX_COUNT
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  sx1 = PeekL(*gGoldForward + Int(fine1) * 4)
  sx2 = PeekL(*gGoldForward + Int(fine2) * 4)
  If sx1 = sx2
    *Verdict\l = #REFBBOX_Occluded
    ProcedureReturn #True
  EndIf
  sx2 - 1
  If sx1 < 0 Or sx2 < 0 Or sx1 > #PROJ_VIEWWIDTH - 1 Or sx2 > #PROJ_VIEWWIDTH - 1
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf

  startIndex = 0
  While startIndex < gRefClipCount And gRefClipLast(startIndex) < sx2
    startIndex + 1
  Wend
  If startIndex >= gRefClipCount
    *Verdict\l = #REFBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If sx1 >= gRefClipFirst(startIndex) And sx2 <= gRefClipLast(startIndex)
    *Verdict\l = #REFBBOX_Occluded
    ProcedureReturn #True
  EndIf
  *Verdict\l = #REFBBOX_Visible
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Recursive test-only near-to-far online walk oracle
; ---------------------------------------------------------------------------

Procedure.i TestRefSubsector(*Level.MapLevel, LeafIndex.l,
                             CameraX.l, CameraY.l, Heading.q)
  Protected numSegs.l
  Protected firstSeg.l
  Protected lastSeg.l
  Protected segIndex.l
  Protected segLine.l
  Protected segSide.l
  Protected frontSector.l
  Protected backSector.l
  Protected outcome.l
  Protected firstX.l
  Protected lastX.l
  Protected spanStart.l
  Protected emitted.l

  If MapSubsectorsGet(@*Level\Subsectors, LeafIndex, @numSegs, @firstSeg) = #False
    ProcedureReturn #False
  EndIf
  If numSegs <= 0 Or firstSeg < 0
    ProcedureReturn #False
  EndIf
  lastSeg = firstSeg + numSegs - 1
  If lastSeg < firstSeg Or lastSeg >= *Level\Segs\Count
    ProcedureReturn #False
  EndIf
  gRefVisitedSubsectors + 1

  segIndex = firstSeg
  While segIndex <= lastSeg
    If TestRefAddLine(*Level, CameraX, CameraY, Heading, LeafIndex, segIndex,
                      @outcome, @firstX, @lastX) = #False
      ProcedureReturn #False
    EndIf
    gRefProcessed.l + 1
    Select outcome
      Case #WALLLINE_EmptySkip
        gRefEmpty + 1
      Case #WALLLINE_Backface
        gRefBackface + 1
      Case #WALLLINE_FovLeft
        gRefFovLeft + 1
      Case #WALLLINE_FovRight
        gRefFovRight + 1
      Case #WALLLINE_ZeroWidth
        ; pixel-width reject; no dedicated ref counter required by comparison.
      Case #WALLLINE_Solid
        gRefSolid + 1
      Case #WALLLINE_Pass
        gRefPass + 1
      Default
        ProcedureReturn #False
    EndSelect

    If outcome = #WALLLINE_Solid Or outcome = #WALLLINE_Pass
      If MapLevelGetSegLinks(*Level, segIndex, @segLine, @segSide,
                             @frontSector, @backSector) = #False
        ProcedureReturn #False
      EndIf
      spanStart = gRefSpanCount
      If outcome = #WALLLINE_Solid
        If TestRefClipApply(firstX, lastX, #WALL_KIND_SOLID,
                            LeafIndex, segIndex, segLine, segSide,
                            frontSector, backSector) = #False
          ProcedureReturn #False
        EndIf
      Else
        If TestRefClipApply(firstX, lastX, #WALL_KIND_PASS,
                            LeafIndex, segIndex, segLine, segSide,
                            frontSector, backSector) = #False
          ProcedureReturn #False
        EndIf
      EndIf
      emitted = gRefSpanCount - spanStart
      If emitted < 0
        ProcedureReturn #False
      EndIf
    EndIf
    segIndex + 1
  Wend
  ProcedureReturn #True
EndProcedure

Procedure.i TestRefVisitRaw(*Level.MapLevel, CameraX.l, CameraY.l, Heading.q,
                            RawChild.l)
  Protected leafIndex.l
  Protected nodeIndex.l
  Protected nodeOriginX.l
  Protected nodeOriginY.l
  Protected nodeDX.l
  Protected nodeDY.l
  Protected child0.l
  Protected child1.l
  Protected side.l
  Protected nearRaw.l
  Protected farRaw.l
  Protected verdict.l

  If (RawChild & #MAP_NF_SUBSECTOR) <> 0
    leafIndex = RawChild & $7FFF
    If leafIndex < 0 Or leafIndex >= *Level\Subsectors\Count
      ProcedureReturn #False
    EndIf
    ProcedureReturn TestRefSubsector(*Level, leafIndex, CameraX, CameraY, Heading)
  EndIf

  nodeIndex = RawChild
  If nodeIndex < 0 Or nodeIndex >= *Level\Nodes\Count Or nodeIndex >= #MAP_NF_SUBSECTOR
    ProcedureReturn #False
  EndIf
  If MapNodesGet(@*Level\Nodes, nodeIndex, @nodeOriginX, @nodeOriginY,
                 @nodeDX, @nodeDY, 0, 0, 0, 0, 0, 0, 0, 0,
                 @child0, @child1) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(nodeOriginX, @nodeOriginX) = #False Or
     FixedFromIntChecked(nodeOriginY, @nodeOriginY) = #False Or
     FixedFromIntChecked(nodeDX, @nodeDX) = #False Or
     FixedFromIntChecked(nodeDY, @nodeDY) = #False
    ProcedureReturn #False
  EndIf
  If GeometryPointOnNodeSideChecked(CameraX, CameraY, nodeOriginX, nodeOriginY,
                                    nodeDX, nodeDY, @side) = #False
    ProcedureReturn #False
  EndIf
  If side <> 0 And side <> 1
    ProcedureReturn #False
  EndIf
  gRefVisitedNodes + 1

  If side = 0
    nearRaw = child0
    farRaw = child1
  Else
    nearRaw = child1
    farRaw = child0
  EndIf
  If (nearRaw & #MAP_NF_SUBSECTOR) <> 0
    If (nearRaw & $7FFF) >= *Level\Subsectors\Count
      ProcedureReturn #False
    EndIf
  ElseIf nearRaw < 0 Or nearRaw >= *Level\Nodes\Count Or nearRaw >= #MAP_NF_SUBSECTOR
    ProcedureReturn #False
  EndIf
  If (farRaw & #MAP_NF_SUBSECTOR) <> 0
    If (farRaw & $7FFF) >= *Level\Subsectors\Count
      ProcedureReturn #False
    EndIf
  ElseIf farRaw < 0 Or farRaw >= *Level\Nodes\Count Or farRaw >= #MAP_NF_SUBSECTOR
    ProcedureReturn #False
  EndIf

  If TestRefVisitRaw(*Level, CameraX, CameraY, Heading, nearRaw) = #False
    ProcedureReturn #False
  EndIf
  If TestRefCheckBBox(*Level, nodeIndex, side ! 1, CameraX, CameraY, Heading,
                      @verdict) = #False
    ProcedureReturn #False
  EndIf
  gRefBboxTests + 1
  Select verdict
    Case #REFBBOX_Occluded
      gRefBboxOccluded + 1
      gRefOcclusionSkips + 1
      ProcedureReturn #True
    Case #REFBBOX_Visible
      gRefBboxVisible + 1
    Case #REFBBOX_Unknown
      gRefBboxUnknown + 1
    Default
      ProcedureReturn #False
  EndSelect
  If TestRefVisitRaw(*Level, CameraX, CameraY, Heading, farRaw) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

; Runs the entire recursive online oracle from the validated BSP root, returning
; false on any structural/API failure. Results are in the gRefSpan/gRef counter
; globals and remain independent of production Projection/Clip/WallVisibility.
Procedure.i TestRefWalkOnline(*Level.MapLevel, CameraX.l, CameraY.l, Heading.q)
  Protected rootIsSubsector.l = 0
  Protected rootIndex.l = 0
  Protected rootRaw.l

  gRefSpanCount = 0
  gRefProcessed.l = 0
  gRefBackface.l = 0
  gRefFovLeft.l = 0
  gRefFovRight.l = 0
  gRefEmpty.l = 0
  gRefSolid.l = 0
  gRefPass.l = 0
  gRefVisitedNodes.l = 0
  gRefVisitedSubsectors.l = 0
  gRefBboxTests.l = 0
  gRefBboxVisible.l = 0
  gRefBboxOccluded.l = 0
  gRefBboxUnknown.l = 0
  gRefOcclusionSkips.l = 0
  gRefWorkItems.l = 0

  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    ProcedureReturn #False
  EndIf
  If TestRefClipBeginFrame(#PROJ_VIEWWIDTH) = #False
    ProcedureReturn #False
  EndIf
  If MapLevelGetBspRoot(*Level, @rootIsSubsector, @rootIndex) = #False
    ProcedureReturn #False
  EndIf
  If rootIsSubsector <> 0
    If *Level\Nodes\Count <> 0 Or *Level\Subsectors\Count <> 1
      ProcedureReturn #False
    EndIf
    If rootIndex < 0 Or rootIndex >= *Level\Subsectors\Count Or
       rootIndex > #MAP_NF_SUBSECTOR - 1
      ProcedureReturn #False
    EndIf
    rootRaw = rootIndex ! #MAP_NF_SUBSECTOR
  Else
    If *Level\Nodes\Count <= 0 Or rootIndex < 0 Or
       rootIndex >= *Level\Nodes\Count Or rootIndex >= #MAP_NF_SUBSECTOR
      ProcedureReturn #False
    EndIf
    rootRaw = rootIndex
  EndIf
  ProcedureReturn TestRefVisitRaw(*Level, CameraX, CameraY, Heading, rootRaw)
EndProcedure

; ---------------------------------------------------------------------------
; Published wall-result / reference span fingerprints and comparison bridge
; ---------------------------------------------------------------------------

Procedure.q TestRefSpanHash()
  Protected hash.q = #TEST_FNV_Offset
  Protected i.i

  For i = 0 To gRefSpanCount - 1
    hash = FnvAddLong(hash, gRefSpanSubsector(i))
    hash = FnvAddLong(hash, gRefSpanSeg(i))
    hash = FnvAddLong(hash, gRefSpanLine(i))
    hash = FnvAddLong(hash, gRefSpanSide(i))
    hash = FnvAddLong(hash, gRefSpanFront(i))
    hash = FnvAddLong(hash, gRefSpanBack(i))
    hash = FnvAddLong(hash, gRefSpanFirst(i))
    hash = FnvAddLong(hash, gRefSpanLast(i))
    hash = FnvAddLong(hash, gRefSpanKind(i))
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q TestWallResultHash(*Result.WallVisibilityResult)
  Protected hash.q = #TEST_FNV_Offset
  Protected i.i
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
  For i = 0 To *Result\Count - 1
    If WallVisibilityGetSpan(*Result, i, @sub, @seg, @line, @side,
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

; Compares a production WallVisibilityResult against a freshly-run recursive
; online oracle for the same map/camera/heading. Span order and all nine source/
; interval fields must agree; every published column must be 0..319 inclusive.
; Counter comparison excludes WorkItems (the production stack-detail count) but
; includes every event, visited-node/leaf, bbox and occlusion-skip total.
Procedure.i TestCompareWallResult(*Level.MapLevel, MapX.q, MapY.q, Heading.q,
                                  *Prod.WallVisibilityResult,
                                  *RefHash.Quad)
  Protected count.l = 0
  Protected i.i
  Protected agree.i = 1
  Protected sub.l = 0
  Protected seg.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected refCameraX.l = 0
  Protected refCameraY.l = 0
  Protected refHeading.q = 0
  Protected prodValue.l = 0
  Protected refValue.l = 0
  Protected prodVisitedNodes.l = 0
  Protected prodVisitedSubsectors.l = 0
  Protected prodProcessedSegs.l = 0
  Protected prodEmittedFragments.l = 0
  Protected prodBackfaceRejects.l = 0
  Protected prodFovLeftRejects.l = 0
  Protected prodFovRightRejects.l = 0
  Protected prodFovRejects.l = 0
  Protected prodPixelWidthRejects.l = 0
  Protected prodEmptyLineRejects.l = 0
  Protected prodSolidCandidates.l = 0
  Protected prodPassCandidates.l = 0
  Protected prodBboxTests.l = 0
  Protected prodBboxVisible.l = 0
  Protected prodBboxOccluded.l = 0
  Protected prodBboxUnknown.l = 0
  Protected prodOcclusionSkips.l = 0
  Protected prodWorkItems.l = 0
  Protected prodClipRangeGrowths.l = 0
  Protected prodClipSpanGrowths.l = 0
  Protected prodAllocations.l = 0

  *RefHash\q = -1
  If TestRefWalkOnline(*Level, MapX, MapY, Heading) = #False
    ProcedureReturn #False
  EndIf
  *RefHash\q = TestRefSpanHash()

  If WallVisibilityIsValid(*Prod.WallVisibilityResult) = #False
    ProcedureReturn #False
  EndIf
  count = WallVisibilityCount(*Prod.WallVisibilityResult)
  If count < 0 Or count <> gRefSpanCount
    ProcedureReturn #False
  EndIf
  For i = 0 To count - 1
    If WallVisibilityGetSpan(*Prod.WallVisibilityResult, i,
                             @sub, @seg, @line, @side, @front, @back,
                             @first, @last, @kind) = #False
      ProcedureReturn #False
    EndIf
    If first < 0 Or last < first Or last > #PROJ_VIEWWIDTH - 1
      ProcedureReturn #False
    EndIf
    If sub <> gRefSpanSubsector(i) Or seg <> gRefSpanSeg(i) Or
       line <> gRefSpanLine(i) Or side <> gRefSpanSide(i) Or
       front <> gRefSpanFront(i) Or back <> gRefSpanBack(i) Or
       first <> gRefSpanFirst(i) Or last <> gRefSpanLast(i) Or
       kind <> gRefSpanKind(i)
      ProcedureReturn #False
    EndIf
  Next

  If WallVisibilityGetStats(*Prod.WallVisibilityResult,
      @prodVisitedNodes, @prodVisitedSubsectors, @prodProcessedSegs,
      @prodEmittedFragments, @prodBackfaceRejects, @prodFovLeftRejects,
      @prodFovRightRejects, @prodFovRejects, @prodPixelWidthRejects,
      @prodEmptyLineRejects, @prodSolidCandidates, @prodPassCandidates,
      @prodBboxTests, @prodBboxVisible, @prodBboxOccluded,
      @prodBboxUnknown, @prodOcclusionSkips, @prodWorkItems,
      @prodClipRangeGrowths, @prodClipSpanGrowths, @prodAllocations) = #False
    agree = 0
  Else
    If prodVisitedNodes <> gRefVisitedNodes.l
      agree = 0
    EndIf
    If prodVisitedSubsectors <> gRefVisitedSubsectors.l
      agree = 0
    EndIf
    If prodProcessedSegs <> gRefProcessed.l
      agree = 0
    EndIf
    If prodEmittedFragments <> gRefSpanCount
      agree = 0
    EndIf
    If prodBackfaceRejects <> gRefBackface.l
      agree = 0
    EndIf
    If prodFovLeftRejects <> gRefFovLeft.l
      agree = 0
    EndIf
    If prodFovRightRejects <> gRefFovRight.l
      agree = 0
    EndIf
    If prodFovRejects <> gRefFovLeft.l + gRefFovRight.l
      agree = 0
    EndIf
    If prodPixelWidthRejects <> 0
      agree = 0
    EndIf
    If prodEmptyLineRejects <> gRefEmpty.l
      agree = 0
    EndIf
    If prodSolidCandidates <> gRefSolid.l
      agree = 0
    EndIf
    If prodPassCandidates <> gRefPass.l
      agree = 0
    EndIf
    If prodBboxTests <> gRefBboxTests.l
      agree = 0
    EndIf
    If prodBboxVisible <> gRefBboxVisible.l
      agree = 0
    EndIf
    If prodBboxOccluded <> gRefBboxOccluded.l
      agree = 0
    EndIf
    If prodBboxUnknown <> gRefBboxUnknown.l
      agree = 0
    EndIf
    If prodOcclusionSkips <> gRefOcclusionSkips.l
      agree = 0
    EndIf
  EndIf

  ; Span/order/counter agreement is complete above; no extra camera re-read is
  ; needed because the caller already supplies the same map-unit inputs.
  ProcedureReturn Bool(count = gRefSpanCount And agree <> 0)
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic BSP/bbox visibility fixtures
; ---------------------------------------------------------------------------
; A single-node root with two reachable leaves. The broad synthetic horizontal
; line/seg records are structurally valid but irrelevant to direct R_CheckBBox
; cases; the caller chooses the node bounding rectangle and camera placement.
Procedure.i TestBuildSingleNodeBBox(*Level.MapLevel,
                                    BoxTop.l, BoxBottom.l, BoxLeft.l, BoxRight.l)
  Protected Dim sectors.TestSectorSpec(0)
  Protected Dim lines.TestLineSpec(0)
  Protected Dim sides.TestSideSpec(0)
  Protected Dim vertices.TestVertexSpec(1)
  Protected Dim segs.TestSegSpec(1)
  Protected Dim subs.TestSubSpec(1)
  Protected Dim nodes.TestNodeSpec(0)
  Protected i.i

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
  sides(0)\MidName = "-"

  vertices(0)\X = -1000
  vertices(0)\Y = 100
  vertices(1)\X = 1000
  vertices(1)\Y = 100

  For i = 0 To 1
    segs(i)\V1 = 0
    segs(i)\V2 = 1
    segs(i)\Line = 0
    segs(i)\Side = 0
  Next
  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1

  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Box0Top = BoxTop
  nodes(0)\Box0Bottom = BoxBottom
  nodes(0)\Box0Left = BoxLeft
  nodes(0)\Box0Right = BoxRight
  nodes(0)\Box1Top = BoxTop
  nodes(0)\Box1Bottom = BoxBottom
  nodes(0)\Box1Left = BoxLeft
  nodes(0)\Box1Right = BoxRight
  nodes(0)\Child0 = #MAP_NF_SUBSECTOR ! 0
  nodes(0)\Child1 = #MAP_NF_SUBSECTOR ! 1

  ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), 1, @lines(0), 1,
                                       @sides(0), 1, @vertices(0), 2,
                                       @segs(0), 2, @subs(0), 2, @nodes(0), 1)
EndProcedure

; Zero-node synthetic level: one broad one-sided subsector wall, root encoded as
; the NF_SUBSECTOR leaf index 0. Camera (-1,0), heading ANG90 (north) sees the
; horizontal wall y=100 spanning x -1000..1000.
Procedure.i TestBuildZeroNodeWall(*Level.MapLevel)
  Protected Dim sectors.TestSectorSpec(0)
  Protected Dim lines.TestLineSpec(0)
  Protected Dim sides.TestSideSpec(0)
  Protected Dim vertices.TestVertexSpec(1)
  Protected Dim segs.TestSegSpec(0)
  Protected Dim subs.TestSubSpec(0)

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

  vertices(0)\X = -1000
  vertices(0)\Y = 100
  vertices(1)\X = 1000
  vertices(1)\Y = 100

  segs(0)\V1 = 0
  segs(0)\V2 = 1
  segs(0)\Line = 0
  segs(0)\Side = 0

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1

  ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), 1, @lines(0), 1,
                                       @sides(0), 1, @vertices(0), 2,
                                       @segs(0), 1, @subs(0), 1, 0, 0)
EndProcedure

; Two-leaf root. PassNear=0: both lines one-sided SOLID broad walls. PassNear=1:
; both lines two-sided with a genuinely open floor-height window (PASS) and the
; common synthetic node bbox {Top=200,Bottom=50,Left=-100,Right=100}, camera
; (-1,0) heading ANG90 => reachable boxpos 9 horizontal bottom-edge selection.
; Node children leaf0 (far on side 1) and leaf1 (near on side 1).
Procedure.i TestBuildTwoLeafTree(*Level.MapLevel, PassNear.i)
  Protected Dim sectors.TestSectorSpec(1)
  Protected Dim lines.TestLineSpec(1)
  Protected Dim sides.TestSideSpec(3)
  Protected Dim vertices.TestVertexSpec(1)
  Protected Dim segs.TestSegSpec(1)
  Protected Dim subs.TestSubSpec(1)
  Protected Dim nodes.TestNodeSpec(0)
  Protected i.i

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\LightLevel = 160
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"
  If PassNear <> 0
    sectors(1)\FloorHeight = 64
    sectors(1)\CeilingHeight = 128
    sectors(1)\LightLevel = 160
    sectors(1)\FloorName = "FLOOR1"
    sectors(1)\CeilingName = "CEIL1"
  EndIf

  vertices(0)\X = -1000
  vertices(0)\Y = 100
  vertices(1)\X = 1000
  vertices(1)\Y = 100

  If PassNear <> 0
    For i = 0 To 1
      lines(i)\V1 = 0
      lines(i)\V2 = 1
      lines(i)\Flags = #MAP_ML_TWOSIDED
      lines(i)\Special = 0
      lines(i)\Tag = 0
      lines(i)\Side0 = i * 2
      lines(i)\Side1 = i * 2 + 1
      sides(i * 2)\Sector = 0
      sides(i * 2 + 1)\Sector = 1
      sides(i * 2)\TopName = "WALL1"
      sides(i * 2)\BottomName = "WALL1"
      sides(i * 2)\MidName = "WALL1"
      sides(i * 2 + 1)\TopName = "WALL1"
      sides(i * 2 + 1)\BottomName = "WALL1"
      sides(i * 2 + 1)\MidName = "WALL1"
    Next
  Else
    For i = 0 To 1
      lines(i)\V1 = 0
      lines(i)\V2 = 1
      lines(i)\Flags = 0
      lines(i)\Special = 0
      lines(i)\Tag = 0
      lines(i)\Side0 = i
      lines(i)\Side1 = -1
      sides(i)\Sector = 0
      sides(i)\TopName = "WALL1"
      sides(i)\BottomName = "WALL1"
      sides(i)\MidName = "WALL1"
    Next
  EndIf

  For i = 0 To 1
    segs(i)\V1 = 0
    segs(i)\V2 = 1
    segs(i)\Line = i
    segs(i)\Side = 0
  Next
  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1

  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Box0Top = 200
  nodes(0)\Box0Bottom = 50
  nodes(0)\Box0Left = -100
  nodes(0)\Box0Right = 100
  nodes(0)\Box1Top = 200
  nodes(0)\Box1Bottom = 50
  nodes(0)\Box1Left = -100
  nodes(0)\Box1Right = 100
  nodes(0)\Child0 = #MAP_NF_SUBSECTOR ! 0
  nodes(0)\Child1 = #MAP_NF_SUBSECTOR ! 1

  If PassNear <> 0
    ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), 2, @lines(0), 2,
                                         @sides(0), 4, @vertices(0), 2,
                                         @segs(0), 2, @subs(0), 2, @nodes(0), 1)
  EndIf
  ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), 1, @lines(0), 2,
                                       @sides(0), 2, @vertices(0), 2,
                                       @segs(0), 2, @subs(0), 2, @nodes(0), 1)
EndProcedure

; Deeper four-leaf/three-node synthetic tree. AllPass=0: four one-sided SOLID
; broad walls. AllPass=1: four two-sided open-floor-height PASS broad walls. Node
; 2 (root) children node0/node1; node0 children leaf0/leaf1; node1 children
; leaf2/leaf3. Every node has the same reachable broad bottom-edge bbox. Camera
; (-1,0) heading ANG90 walks near leaf3 then far leaf2, then node0's near leaf1
; then far leaf0 in both production and recursive oracle.
Procedure.i TestBuildQuadTree(*Level.MapLevel, AllPass.i)
  Protected Dim sectors.TestSectorSpec(1)
  Protected Dim lines.TestLineSpec(3)
  Protected Dim sides.TestSideSpec(7)
  Protected Dim vertices.TestVertexSpec(1)
  Protected Dim segs.TestSegSpec(3)
  Protected Dim subs.TestSubSpec(3)
  Protected Dim nodes.TestNodeSpec(2)
  Protected i.i

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\LightLevel = 160
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"
  If AllPass <> 0
    sectors(1)\FloorHeight = 64
    sectors(1)\CeilingHeight = 128
    sectors(1)\LightLevel = 160
    sectors(1)\FloorName = "FLOOR1"
    sectors(1)\CeilingName = "CEIL1"
  EndIf

  vertices(0)\X = -1000
  vertices(0)\Y = 100
  vertices(1)\X = 1000
  vertices(1)\Y = 100

  If AllPass <> 0
    For i = 0 To 3
      lines(i)\V1 = 0
      lines(i)\V2 = 1
      lines(i)\Flags = #MAP_ML_TWOSIDED
      lines(i)\Special = 0
      lines(i)\Tag = 0
      lines(i)\Side0 = i * 2
      lines(i)\Side1 = i * 2 + 1
      sides(i * 2)\Sector = 0
      sides(i * 2 + 1)\Sector = 1
      sides(i * 2)\TopName = "WALL1"
      sides(i * 2)\BottomName = "WALL1"
      sides(i * 2)\MidName = "WALL1"
      sides(i * 2 + 1)\TopName = "WALL1"
      sides(i * 2 + 1)\BottomName = "WALL1"
      sides(i * 2 + 1)\MidName = "WALL1"
    Next
  Else
    For i = 0 To 3
      lines(i)\V1 = 0
      lines(i)\V2 = 1
      lines(i)\Flags = 0
      lines(i)\Special = 0
      lines(i)\Tag = 0
      lines(i)\Side0 = i
      lines(i)\Side1 = -1
      sides(i)\Sector = 0
      sides(i)\TopName = "WALL1"
      sides(i)\BottomName = "WALL1"
      sides(i)\MidName = "WALL1"
    Next
  EndIf

  For i = 0 To 3
    segs(i)\V1 = 0
    segs(i)\V2 = 1
    segs(i)\Line = i
    segs(i)\Side = 0
    subs(i)\FirstSeg = i
    subs(i)\NumSegs = 1
  Next

  For i = 0 To 2
    nodes(i)\OriginX = 0
    nodes(i)\OriginY = 0
    nodes(i)\DX = 0
    nodes(i)\DY = 1
    nodes(i)\Box0Top = 200
    nodes(i)\Box0Bottom = 50
    nodes(i)\Box0Left = -100
    nodes(i)\Box0Right = 100
    nodes(i)\Box1Top = 200
    nodes(i)\Box1Bottom = 50
    nodes(i)\Box1Left = -100
    nodes(i)\Box1Right = 100
  Next
  nodes(0)\Child0 = #MAP_NF_SUBSECTOR ! 0
  nodes(0)\Child1 = #MAP_NF_SUBSECTOR ! 1
  nodes(1)\Child0 = #MAP_NF_SUBSECTOR ! 2
  nodes(1)\Child1 = #MAP_NF_SUBSECTOR ! 3
  nodes(2)\Child0 = 0
  nodes(2)\Child1 = 1

  If AllPass <> 0
    ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), 2, @lines(0), 4,
                                         @sides(0), 8, @vertices(0), 2,
                                         @segs(0), 4, @subs(0), 4, @nodes(0), 3)
  EndIf
  ProcedureReturn TestBuildFlexibleMap(*Level, @sectors(0), 1, @lines(0), 4,
                                       @sides(0), 4, @vertices(0), 2,
                                       @segs(0), 4, @subs(0), 4, @nodes(0), 3)
EndProcedure

; Full production online Build measurement plus independent recursive-oracle
; comparison. Camera/projection are created locally and cleaned up; the result
; remains caller-owned and readable afterward.
Procedure.i TestMeasureWallBuild(*Level.MapLevel, MapX.q, MapY.q, Heading.q,
                                 *Result.WallVisibilityResult,
                                 *BuildOk.Long, *CompareOk.Long, *RefHash.Quad)
  Protected camera.BspCamera
  Protected projection.Projection
  Protected projectionCreated.i = 0
  Protected buildOk.i = 0
  Protected compareOk.i = 0

  *BuildOk\l = 0
  *CompareOk\l = 0
  *RefHash\q = -1

  If BspCameraSetMapUnits(@camera, MapX, MapY, Heading) = #False
    ProcedureReturn #False
  EndIf
  If ProjectionInitClassic(@projection) = #False
    ProcedureReturn #False
  EndIf
  projectionCreated = 1
  If WallVisibilityBuild(*Level, @camera, @projection, 0, 0, *Result) = #False
    buildOk = 0
  Else
    buildOk = 1
  EndIf
  If buildOk <> 0
    If TestCompareWallResult(*Level, MapX, MapY, Heading, *Result, *RefHash) = #False
      compareOk = 0
    Else
      compareOk = 1
    EndIf
  EndIf
  *BuildOk\l = buildOk
  *CompareOk\l = compareOk
  If projectionCreated <> 0
    ProjectionReset(@projection)
  EndIf
  ProcedureReturn Bool(buildOk <> 0 And compareOk <> 0)
EndProcedure

; ---------------------------------------------------------------------------
; WC27-WC39 R_AddLine / classification cases
; ---------------------------------------------------------------------------
; All measured cases run production WallVisibilityAddLine and the independent
; TestRefAddLine translation in a fresh empty 320-column clip frame. The bridge
; already verifies identical outcome, emitted count and candidate interval; cases
; add source-semantic assertions on the observed production fields.

Procedure TestWC27()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1

  BeginCase("WC27", "Camera +X, -X, +Y, -Y facing with exact BAM wrap and symmetric projection")

  Check(Bool(BamRawInUnsignedDomain(0) <> 0 And #BAM_ANG90 = $40000000),
        "cardinal BAM constants are exact, with ANG0 raw value zero")
  Check(Bool(BamRawInUnsignedDomain(#BAM_ANG180) <> 0 And BamRawInUnsignedDomain(#BAM_ANG270) <> 0),
        "ANG180/ANG270 fit only the canonical unsigned raw domain")

  ; (1) +X facing: vertical x=100 wall from north to south, camera 0 heading 0.
  buildOk = TestBuildOneSidedWall(@map, 100, 64, 100, -64, "WALL1")
  Check(Bool(buildOk <> 0), "plus-X synthetic wall level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "plus-X production AddLine agrees with the independent oracle")
  Check(Bool(prodStatus = #WALLLINE_Solid And prodEmitted = 1 And prodSpanCount = 1 And
             prodFirst = 58 And prodLast = 262 And prodRangeCount = 3),
        "plus-X one-sided wall emits SOLID candidate [58,262] and one real occluder")
  Check(Bool(refStatus = prodStatus And refFirst = prodFirst And refLast = prodLast),
        "plus-X reference outcome/candidate match measured production fields")
  MapLevelReset(@map)

  ; (2) -X facing: mirrored vertical -100 wall from south to north, heading ANG180.
  buildOk = TestBuildOneSidedWall(@map, -100, -64, -100, 64, "WALL1")
  Check(Bool(buildOk <> 0), "minus-X mirrored synthetic wall level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, #BAM_ANG180, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "minus-X production AddLine agrees with the independent oracle")
  Check(Bool(prodStatus = #WALLLINE_Solid And prodEmitted = 1 And prodSpanCount = 1 And
             prodFirst = 58 And prodLast = 262),
        "minus-X one-sided wall emits SOLID candidate [58,262]")
  MapLevelReset(@map)

  ; (3) +Y facing: horizontal y=100 wall from west to east, heading ANG90.
  buildOk = TestBuildOneSidedWall(@map, -64, 100, 64, 100, "WALL1")
  Check(Bool(buildOk <> 0), "plus-Y synthetic wall level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, #BAM_ANG90, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "plus-Y production AddLine agrees with the independent oracle")
  Check(Bool(prodStatus = #WALLLINE_Solid And prodEmitted = 1 And prodSpanCount = 1 And
             prodFirst = 58 And prodLast = 262),
        "plus-Y one-sided wall emits SOLID candidate [58,262]")
  MapLevelReset(@map)

  ; (4) -Y facing: horizontal y=-100 reversed wall west, heading ANG270.
  buildOk = TestBuildOneSidedWall(@map, 64, -100, -64, -100, "WALL1")
  Check(Bool(buildOk <> 0), "minus-Y reversed synthetic wall level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, #BAM_ANG270, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "minus-Y production AddLine agrees with the independent oracle")
  Check(Bool(prodStatus = #WALLLINE_Solid And prodEmitted = 1 And prodSpanCount = 1 And
             prodFirst = 58 And prodLast = 262),
        "minus-Y one-sided wall emits SOLID candidate [58,262]")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC28()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1

  BeginCase("WC28", "Backface rejection span==ANG180 and both sides of threshold")

  Check(Bool(WallSpanIsBackface(#BAM_ANG180) <> 0),
        "unsigned span exactly ANG180 (=2147483648) is rejected as a backface")
  Check(Bool(WallSpanIsBackface(BamSubtract(#BAM_ANG180, 1)) = 0),
        "span ANG180-1 (2147483647) remains front-facing")
  Check(Bool(WallSpanIsBackface(BamAdd(#BAM_ANG180, 1)) <> 0),
        "span ANG180+1 (2147483649) remains rejected")
  Check(Bool(WallSpanIsBackface(BamSubtract(#BAM_ANG180, 1) + 2) <> 0),
        "exact threshold equality is not a strict boundary")

  ; Opposite endpoints around the camera make angle1-angle2 exactly ANG180.
  buildOk = TestBuildOneSidedWall(@map, 100, 64, -100, -64, "WALL1")
  Check(Bool(buildOk <> 0), "exact-180 synthetic one-sided wall validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "exact-180 production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Backface And prodEmitted = 0 And prodSpanCount = 0),
        "backface test precedes solidity and emits no span")
  Check(Bool(prodRangeCount = 2 And refStatus = #WALLLINE_Backface),
        "backface rejection leaves only the two sentinels and matches the oracle")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC29()
  Protected Dim relative.q(7)
  Protected Dim spanValue.q(7)
  Protected clip.q = 0
  Protected twoClip.q = 0
  Protected prodAdjusted.Quad
  Protected prodRejected.l = 0
  Protected refAdjusted.Quad
  Protected refRejected.l = 0
  Protected i.i
  Protected mismatch.i = 0
  Protected tieAdjusted.Quad
  Protected tieRejected.l = 0
  Protected boundaryAdjusted.Quad
  Protected boundaryRejected.l = 0

  BeginCase("WC29", "Left FOV edge clipping and strict inequality tie")

  clip = PeekQ(*gGoldClipAngle)
  twoClip = BamAdd(clip, clip)
  relative(0) = clip
  spanValue(0) = 1
  relative(1) = clip + 1
  spanValue(1) = 1
  relative(2) = clip + 1
  spanValue(2) = 2
  relative(3) = twoClip
  spanValue(3) = clip
  relative(4) = twoClip
  spanValue(4) = clip + 1
  relative(5) = twoClip + 1
  spanValue(5) = clip
  relative(6) = 0
  spanValue(6) = 6000000
  relative(7) = 123456789
  spanValue(7) = 98765

  For i = 0 To 7
    prodRejected = 0
    refRejected = 0
    prodAdjusted\q = 0
    refAdjusted\q = 0
    If WallApplyLeftClip(relative(i), spanValue(i), clip,
                         @prodAdjusted, @prodRejected) = 0 Or
       TestRefFovLeftAdjust(relative(i), spanValue(i), clip,
                            @refAdjusted, @refRejected) = 0
      mismatch + 1
      Continue
    EndIf
    If prodAdjusted\q <> refAdjusted\q Or prodRejected <> refRejected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "all 8 left-branch vectors match the independent translation")

  ; Vector 0: relative==clip -> tspan==2*clip exactly; the source's strict > does
  ; not adjust the angle, so the exact boundary remains visible.
  tieRejected = 0
  tieAdjusted\q = 0
  Check(Bool(WallApplyLeftClip(clip, 1, clip, @tieAdjusted, @tieRejected) <> 0 And
             tieAdjusted\q = clip And tieRejected = 0),
        "tspan exactly 2*clip is not adjusted and not rejected")
  ; One past the boundary subtracts to 1; span 1 rejects by exact >= equality.
  boundaryRejected = 0
  boundaryAdjusted\q = 0
  Check(Bool(WallApplyLeftClip(clip + 1, 1, clip, @boundaryAdjusted, @boundaryRejected) <> 0 And
             boundaryRejected <> 0),
        "tspan 2*clip+1 vs span 1 rejects at the equality boundary")
  Check(Bool(WallApplyLeftClip(clip + 1, 2, clip, @boundaryAdjusted, @boundaryRejected) <> 0 And
             boundaryAdjusted\q = clip And boundaryRejected = 0),
        "tspan 2*clip+1 vs span 2 instead clips to exactly clipangle")
  Check(Bool(WallApplyLeftClip(0, 0, clip, 0, 0) = 0 And WallVisibilityLastError() <> ""),
        "null left-clip outputs are rejected with a diagnostic")
EndProcedure

Procedure TestWC30()
  Protected Dim relative.q(7)
  Protected Dim spanValue.q(7)
  Protected clip.q = 0
  Protected twoClip.q = 0
  Protected negClip.q = 0
  Protected prodAdjusted.Quad
  Protected prodRejected.l = 0
  Protected refAdjusted.Quad
  Protected refRejected.l = 0
  Protected i.i
  Protected mismatch.i = 0
  Protected tieAdjusted.Quad
  Protected tieRejected.l = 0
  Protected boundaryAdjusted.Quad
  Protected boundaryRejected.l = 0

  BeginCase("WC30", "Right FOV edge clipping and strict inequality tie")

  clip = PeekQ(*gGoldClipAngle)
  twoClip = BamAdd(clip, clip)
  negClip = BamNegate(clip)
  relative(0) = 0
  spanValue(0) = 5000
  relative(1) = clip
  spanValue(1) = 5000
  relative(2) = negClip
  spanValue(2) = 1
  relative(3) = BamSubtract(negClip, 1)
  spanValue(3) = 1
  relative(4) = BamSubtract(negClip, 1)
  spanValue(4) = 2
  relative(5) = twoClip
  spanValue(5) = 90000
  relative(6) = BamAdd(negClip, 1)
  spanValue(6) = 90000
  relative(7) = 10000
  spanValue(7) = 40000

  For i = 0 To 7
    prodRejected = 0
    refRejected = 0
    prodAdjusted\q = 0
    refAdjusted\q = 0
    If WallApplyRightClip(relative(i), spanValue(i), clip,
                          @prodAdjusted, @prodRejected) = 0 Or
       TestRefFovRightAdjust(relative(i), spanValue(i), clip,
                             @refAdjusted, @refRejected) = 0
      mismatch + 1
      Continue
    EndIf
    If prodAdjusted\q <> refAdjusted\q Or prodRejected <> refRejected
      mismatch + 1
    EndIf
  Next
  Check(Bool(mismatch = 0), "all 8 right-branch vectors match the independent translation")

  ; relative==-clip -> tspan==clip-(-clip)==2*clip exactly; not adjusted.
  tieRejected = 0
  tieAdjusted\q = 0
  Check(Bool(WallApplyRightClip(negClip, 1, clip, @tieAdjusted, @tieRejected) <> 0 And
             tieAdjusted\q = negClip And tieRejected = 0),
        "right tspan exactly 2*clip is not adjusted and retains -clipangle")
  boundaryRejected = 0
  boundaryAdjusted\q = 0
  Check(Bool(WallApplyRightClip(BamSubtract(negClip, 1), 1, clip,
                                @boundaryAdjusted, @boundaryRejected) <> 0 And
             boundaryRejected <> 0),
        "right tspan 2*clip+1 vs span 1 rejects at the equality boundary")
  Check(Bool(WallApplyRightClip(BamSubtract(negClip, 1), 2, clip,
                                @boundaryAdjusted, @boundaryRejected) <> 0 And
             boundaryAdjusted\q = negClip And boundaryRejected = 0),
        "right tspan 2*clip+1 vs span 2 clips to exactly -clipangle")
  Check(Bool(WallApplyRightClip(0, 0, clip, 0, 0) = 0 And WallVisibilityLastError() <> ""),
        "null right-clip outputs are rejected with a diagnostic")
EndProcedure

Procedure TestWC31()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1
  Protected rightStatus.l = -1
  Protected rightEmitted.l = -1
  Protected rightSpanCount.l = -1
  Protected rightRangeCount.l = -1

  BeginCase("WC31", "Outside FOV rejected before any clip-state mutation")

  buildOk = TestBuildOneSidedWall(@map, 100, 64, 100, -64, "WALL1")
  Check(Bool(buildOk <> 0), "vertical x=100 synthetic wall validates")
  ; Heading ANG180 faces away: the left FOV branch rejects before projection/clip.
  measureOk = TestMeasureOneAddLine(@map, 0, 0, #BAM_ANG180, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "left-FOV production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_FovLeft And prodEmitted = 0 And prodSpanCount = 0 And
             prodRangeCount = 2 And refStatus = #WALLLINE_FovLeft),
        "left-FOV rejection adds no span and leaves exactly the two sentinels")
  ; A second cardinal heading (ANG90 north) also hits the left FOV branch after
  ; unsigned wrap and rejects before any clip-state mutation. AddLine's right
  ; branch remains a pure-helper concern (WC30); front-facing AddLines normally
  ; encounter the left strict tie first, so this case does not invent an additive
  ; right verdict.
  measureOk = TestMeasureOneAddLine(@map, 0, 0, #BAM_ANG90, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "north-heading FOV production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_FovLeft And prodEmitted = 0 And prodSpanCount = 0 And
             prodRangeCount = 2 And refStatus = #WALLLINE_FovLeft),
        "unsigned-wrapped north heading still rejects through the left FOV branch only")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC32()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1

  BeginCase("WC32", "x1==x2 pixel-width rejection; [x1,x2-1] inclusive endpoint")

  ; Two near-collinear endpoints 45 degrees away: equal projected column.
  buildOk = TestBuildOneSidedWall(@map, 100, 100, 101, 101, "WALL1")
  Check(Bool(buildOk <> 0), "zero-width synthetic diagonal wall validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "zero-width production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_ZeroWidth And prodEmitted = 0 And prodSpanCount = 0 And
             prodRangeCount = 2 And refStatus = #WALLLINE_ZeroWidth),
        "x1==x2 is rejected rather than converted into a one-column wall")
  MapLevelReset(@map)

  ; One map-unit horizontal endpoint produces exactly one inclusive pixel.
  buildOk = TestBuildOneSidedWall(@map, 100, 100, 101, 100, "WALL1")
  Check(Bool(buildOk <> 0), "one-pixel synthetic wall validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "one-pixel production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Solid And prodEmitted = 1 And prodSpanCount = 1 And
             prodRangeCount = 3 And prodFirst = 1 And prodLast = 1),
        "x2=x1+1 publishes the inclusive endpoint [1,1] = [1,x2-1]")
  Check(Bool(refFirst = 1 And refLast = 1 And refStatus = #WALLLINE_Solid),
        "independent oracle matches the inclusive candidate and SOLID classification")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC33()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1
  Protected lineOut.l = -1
  Protected sideOut.l = -1
  Protected frontOut.l = -1
  Protected backOut.l = -1

  BeginCase("WC33", "One-sided linedef with valid middle texture -> SOLID")

  buildOk = TestBuildOneSidedWall(@map, 100, 64, 100, -64, "WALL1")
  Check(Bool(buildOk <> 0), "one-sided wall with canonical middle texture validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "one-sided middle-texture production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Solid And prodEmitted = 1 And prodSpanCount = 1 And
             prodRangeCount = 3 And prodFirst = 58 And prodLast = 262),
        "valid middle texture does not alter a one-sided SOLID result")
  Check(Bool(refStatus = #WALLLINE_Solid And refFirst = prodFirst And refLast = prodLast),
        "independent oracle confirms SOLID candidate [58,262]")
  Check(Bool(MapLevelGetSegLinks(@map, 0, @lineOut, @sideOut, @frontOut, @backOut) <> 0 And
             lineOut = 0 And sideOut = 0 And frontOut = 0 And backOut = -1),
        "derived seg links expose the canonical one-sided back-sector sentinel -1")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC34()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1
  Protected frontOut.l = -1
  Protected backOut.l = -1

  BeginCase("WC34", "Closed two-sided door via ceiling/floor overlap -> SOLID")

  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   128, 128, 160, "FLOOR1", "CEIL1",
                                   0, "WALL1", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "closed two-sector door level validates")
  Check(Bool(MapLevelGetLinedefLinks(@map, 0, @frontOut, @backOut) <> 0 And
             frontOut = 0 And backOut = 1),
        "derived linedef front/back sectors are 0 and 1")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "closed-door production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Solid And prodEmitted = 1 And prodSpanCount = 1 And
             prodRangeCount = 3 And prodFirst = 58 And prodLast = 262),
        "back floor >= front ceiling equality makes a two-sided door SOLID")
  Check(Bool(refStatus = #WALLLINE_Solid And refFirst = prodFirst And refLast = prodLast),
        "independent oracle confirms closed-door SOLID [58,262]")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC35()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1

  BeginCase("WC35", "Two-sided window with different floor height -> PASS")

  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   64, 128, 160, "FLOOR1", "CEIL1",
                                   0, "WALL1", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "different-floor window level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "different-floor production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1 And
             prodRangeCount = 2 And prodFirst = 58 And prodLast = 262),
        "equal ceilings but back floor != front floor yields PASS with no occluder")
  Check(Bool(refStatus = #WALLLINE_Pass And refFirst = prodFirst And refLast = prodLast),
        "independent oracle confirms PASS candidate [58,262]")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC36()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1

  BeginCase("WC36", "Two-sided window with different ceiling height -> PASS")

  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, 96, 160, "FLOOR1", "CEIL1",
                                   0, "WALL1", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "different-ceiling window level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "different-ceiling production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1 And
             prodRangeCount = 2 And prodFirst = 58 And prodLast = 262),
        "equal floors but back ceiling != front ceiling yields PASS with no occluder")
  Check(Bool(refStatus = #WALLLINE_Pass And refFirst = prodFirst And refLast = prodLast),
        "independent oracle confirms PASS candidate [58,262]")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC37()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1
  Protected sameFloor.l = 0
  Protected sameCeiling.l = 0
  Protected middleAbsent.l = 0
  Protected ok.i

  BeginCase("WC37", "Identical planes/light and absent middle texture -> SKIP")

  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, "-", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "equal-plane absent-middle trigger wall level validates")
  ok = WallSectorFlatIdentity(@map, 0, 0, 1, 0, @sameFloor)
  Check(Bool(ok <> 0 And sameFloor = 1), "canonical floor flat identity is true")
  ok = WallSectorFlatIdentity(@map, 0, 0, 1, 1, @sameCeiling)
  Check(Bool(ok <> 0 And sameCeiling = 1), "canonical ceiling flat identity is true")
  ok = WallMiddleTextureAbsent(@map, 0, 0, @middleAbsent)
  Check(Bool(ok <> 0 And middleAbsent = 1), "canonical '-' middle slot is absent")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "empty-trigger production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_EmptySkip And prodEmitted = 0 And prodSpanCount = 0 And
             prodRangeCount = 2 And refStatus = #WALLLINE_EmptySkip),
        "identical planes/light plus absent middle skips the trigger line")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC38()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1

  BeginCase("WC38", "Same planes/light but present midtexture -> PASS; lighting/texture differences -> PASS")

  ; (a) identical planes/flats/lights, canonical present middle texture.
  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, "WALL1", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "present-middle equal-plane level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "present-middle production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1 And
             prodFirst = 58 And prodLast = 262),
        "same planes and light with present midtexture remains a PASS wall")
  MapLevelReset(@map)

  ; (b) identical geometry/flats but differing light levels.
  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, 128, 128, "FLOOR1", "CEIL1",
                                   0, "WALL1", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "lighting-difference level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "lighting-difference production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1),
        "different light levels cannot produce an empty trigger SKIP")
  MapLevelReset(@map)

  ; (c) identical heights/light but different canonical floor flat names.
  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, 128, 160, "FLOOR2", "CEIL1",
                                   0, "WALL1", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "texture-identity-difference level validates")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "texture-difference production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1),
        "different canonical floor names pass the fallback identity test -> PASS")
  MapLevelReset(@map)
EndProcedure

Procedure TestWC39()
  Protected map.MapLevel
  Protected buildOk.i
  Protected measureOk.i
  Protected prodStatus.l = -1
  Protected prodEmitted.l = -1
  Protected prodFirst.l = -1
  Protected prodLast.l = -1
  Protected prodSpanCount.l = -1
  Protected prodRangeCount.l = -1
  Protected refStatus.l = -1
  Protected refFirst.l = -1
  Protected refLast.l = -1
  Protected lineOut.l = -1
  Protected sideOut.l = -1
  Protected frontOut.l = -1
  Protected backOut.l = -1
  Protected malformedMid.s = ""
  Protected middleAbsent.l = 0
  Protected sameFloor.l = 0
  Protected sameCeiling.l = 0
  Protected ok.i

  BeginCase("WC39", "Seg side 1 orientation, derived front/back links, bad/missing name handling")

  ; (a) SegSide=1: line side0 is the back/east? sector, side1 the seg-selected front
  ; sector. Reversed geometry (v1->v0) and east camera heading ANG180 reproduces
  ; the same symmetric [58,262] candidate with a genuinely open floor height.
  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   64, 128, 160, "FLOOR1", "CEIL1",
                                   1, "WALL1", "WALL1", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "side-1 oriented two-sector wall level validates")
  ok = MapLevelGetSegLinks(@map, 0, @lineOut, @sideOut, @frontOut, @backOut)
  Check(Bool(ok <> 0 And lineOut = 0 And sideOut = 1 And frontOut = 1 And backOut = 0),
        "seg side 1 derives front sector 1 from side1 and back sector 0 from side0")
  measureOk = TestMeasureOneAddLine(@map, 200, 0, #BAM_ANG180, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "side-1 oriented production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1 And
             prodFirst = 58 And prodLast = 262),
        "reversed seg direction with east camera retains PASS and its symmetric span")
  MapLevelReset(@map)

  ; (b) selected side1 middle slot with an embedded NUL is malformed, so the
  ; documented fallback conservatively treats it as present (PASS, never a SKIP).
  malformedMid = "A" + Chr(0) + "B"
  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   0, 128, 160, "FLOOR1", "CEIL1",
                                   1, "WALL1", malformedMid, #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "malformed side-1 middle-name level validates structurally")
  ok = WallMiddleTextureAbsent(@map, 0, 1, @middleAbsent)
  Check(Bool(ok <> 0 And middleAbsent = 0),
        "embedded-NUL middle slot is conservatively present, never an empty slot")
  measureOk = TestMeasureOneAddLine(@map, 200, 0, #BAM_ANG180, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "malformed-name production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1),
        "malformed/no-name middle handling yields conservative PASS, not SKIP")
  MapLevelReset(@map)

  ; (c) identical planes/light with matching all-NUL (empty) floor/ceiling slots:
  ; raw fallback cannot prove identity, so this must be conservative PASS.
  buildOk = TestBuildTwoSectorWall(@map, 100, 64, 100, -64,
                                   0, 128, 160, "", "",
                                   0, 128, 160, "", "",
                                   0, "-", "-", #MAP_ML_TWOSIDED)
  Check(Bool(buildOk <> 0), "all-NUL flat-name trigger level validates structurally")
  ok = WallSectorFlatIdentity(@map, 0, 0, 1, 0, @sameFloor)
  Check(Bool(ok <> 0 And sameFloor = 0),
        "empty/missing floor slots cannot be proven identical by the raw fallback")
  ok = WallSectorFlatIdentity(@map, 0, 0, 1, 1, @sameCeiling)
  Check(Bool(ok <> 0 And sameCeiling = 0),
        "empty/missing ceiling slots cannot be proven identical by the raw fallback")
  measureOk = TestMeasureOneAddLine(@map, 0, 0, 0, 0, 0,
                                    @prodStatus, @prodEmitted, @prodFirst, @prodLast,
                                    @prodSpanCount, @prodRangeCount,
                                    @refStatus, @refFirst, @refLast)
  Check(Bool(measureOk <> 0), "missing-name production/reference agreement")
  Check(Bool(prodStatus = #WALLLINE_Pass And prodEmitted = 1 And prodSpanCount = 1),
        "unprovable/empty flat names yield conservative PASS rather than SKIP")
  MapLevelReset(@map)
EndProcedure

; ---------------------------------------------------------------------------
; WC40-WC52 bbox / online BSP / lifecycle cases
; ---------------------------------------------------------------------------

Procedure TestWC40()
  Protected row.i
  Protected col.i
  Protected prodValue.l = 0
  Protected refValue.l = 0
  Protected mismatch.i = 0
  Protected Dim cameraMapX.q(8)
  Protected Dim cameraMapY.q(8)
  Protected Dim expectedBoxX.l(8)
  Protected Dim expectedBoxY.l(8)
  Protected Dim expectedBoxPos.l(8)
  Protected topFixed.l = 0
  Protected bottomFixed.l = 0
  Protected leftFixed.l = 0
  Protected rightFixed.l = 0
  Protected cameraFixedX.l = 0
  Protected cameraFixedY.l = 0
  Protected boxXOut.l = 0
  Protected boxYOut.l = 0
  Protected boxPosOut.l = 0
  Protected i.i
  Protected positionMismatch.i = 0

  BeginCase("WC40", "checkcoord mapping for each reachable camera-box region")

  For row = 0 To #WALL_CHECKCOORD_ROWS - 1
    For col = 0 To #WALL_CHECKCOORD_COLS - 1
      prodValue = 0
      refValue = 0
      If WallCheckCoordGet(row, col, @prodValue) = 0 Or
         TestRefCheckCoordGet(row, col, @refValue) = 0
        mismatch + 1
        Continue
      EndIf
      If prodValue <> refValue
        mismatch + 1
      EndIf
    Next
  Next
  Check(Bool(mismatch = 0), "all 48 checkcoord bytes match the independent exact C-table copy")
  Check(Bool(WallCheckCoordGet(0, 0, @prodValue) <> 0 And prodValue = 3),
        "row0 sample is the original 3 corner index")
  Check(Bool(WallCheckCoordGet(9, 1, @prodValue) <> 0 And prodValue = 1),
        "reachable row9 horizontal selection starts at bottom corner 1")
  For col = 0 To #WALL_CHECKCOORD_COLS - 1
    Check(Bool(WallCheckCoordGet(3, col, @prodValue) <> 0 And prodValue = 0),
          "unreachable placeholder row3 cell " + Str(col) + " is zero")
  Next
  For col = 0 To #WALL_CHECKCOORD_COLS - 1
    Check(Bool(WallCheckCoordGet(7, col, @prodValue) <> 0 And prodValue = 0),
          "unreachable placeholder row7 cell " + Str(col) + " is zero")
  Next
  For col = 0 To #WALL_CHECKCOORD_COLS - 1
    Check(Bool(WallCheckCoordGet(11, col, @prodValue) <> 0 And prodValue = 0),
          "trailing unreachable row11 cell " + Str(col) + " is zero")
  Next

  Check(Bool(FixedFromIntChecked(200, @topFixed) <> 0 And
             FixedFromIntChecked(50, @bottomFixed) <> 0 And
             FixedFromIntChecked(-100, @leftFixed) <> 0 And
             FixedFromIntChecked(100, @rightFixed) <> 0),
        "boundary box map-unit coordinates convert exactly to fixed16.16")

  cameraMapX(0) = -200 : cameraMapY(0) = 200 : expectedBoxX(0) = 0 : expectedBoxY(0) = 0 : expectedBoxPos(0) = 0
  cameraMapX(1) = -1   : cameraMapY(1) = 200 : expectedBoxX(1) = 1 : expectedBoxY(1) = 0 : expectedBoxPos(1) = 1
  cameraMapX(2) = 200  : cameraMapY(2) = 200 : expectedBoxX(2) = 2 : expectedBoxY(2) = 0 : expectedBoxPos(2) = 2
  cameraMapX(3) = -200 : cameraMapY(3) = 100 : expectedBoxX(3) = 0 : expectedBoxY(3) = 1 : expectedBoxPos(3) = 4
  cameraMapX(4) = -1   : cameraMapY(4) = 100 : expectedBoxX(4) = 1 : expectedBoxY(4) = 1 : expectedBoxPos(4) = 5
  cameraMapX(5) = 200  : cameraMapY(5) = 100 : expectedBoxX(5) = 2 : expectedBoxY(5) = 1 : expectedBoxPos(5) = 6
  cameraMapX(6) = -200 : cameraMapY(6) = 0   : expectedBoxX(6) = 0 : expectedBoxY(6) = 2 : expectedBoxPos(6) = 8
  cameraMapX(7) = -1   : cameraMapY(7) = 0   : expectedBoxX(7) = 1 : expectedBoxY(7) = 2 : expectedBoxPos(7) = 9
  cameraMapX(8) = 200  : cameraMapY(8) = 0   : expectedBoxX(8) = 2 : expectedBoxY(8) = 2 : expectedBoxPos(8) = 10

  For i = 0 To 8
    If FixedFromIntChecked(cameraMapX(i), @cameraFixedX) = 0 Or
       FixedFromIntChecked(cameraMapY(i), @cameraFixedY) = 0
      positionMismatch + 1
      Continue
    EndIf
    boxXOut = 0 : boxYOut = 0 : boxPosOut = 0
    If WallBoxPosition(cameraFixedX, cameraFixedY, topFixed, bottomFixed,
                       leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) = 0
      positionMismatch + 1
      Continue
    EndIf
    If boxXOut <> expectedBoxX(i) Or boxYOut <> expectedBoxY(i) Or
       boxPosOut <> expectedBoxPos(i)
      positionMismatch + 1
    EndIf
  Next
  Check(Bool(positionMismatch = 0),
        "nine reachable camera/box regions map exactly to boxpos 0,1,2,4,5,6,8,9,10")
  Check(Bool(expectedBoxPos(4) = 5), "middle-middle boxpos is the original 5 inside-box code")
  Check(Bool(WallBoxPosition(cameraFixedX, cameraFixedY, topFixed, bottomFixed,
                             leftFixed, rightFixed, 0, 0, 0) = 0 And
             WallVisibilityLastError() <> ""),
        "null WallBoxPosition outputs are rejected with a diagnostic")
EndProcedure

Procedure TestWC41()
  Protected topFixed.l = 0
  Protected bottomFixed.l = 0
  Protected leftFixed.l = 0
  Protected rightFixed.l = 0
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected boxXOut.l = 0
  Protected boxYOut.l = 0
  Protected boxPosOut.l = 0

  BeginCase("WC41", "Camera exactly on left/right/top/bottom bbox boundary")

  Check(Bool(FixedFromIntChecked(200, @topFixed) <> 0 And
             FixedFromIntChecked(50, @bottomFixed) <> 0 And
             FixedFromIntChecked(-100, @leftFixed) <> 0 And
             FixedFromIntChecked(100, @rightFixed) <> 0),
        "boundary box coordinates convert exactly")

  Check(Bool(FixedFromIntChecked(-100, @cameraX) <> 0 And
             FixedFromIntChecked(100, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxXOut = 0 And boxYOut = 1 And boxPosOut = 4),
        "cameraX exactly on Left uses <= and selects boxx0")
  Check(Bool(FixedFromIntChecked(-99, @cameraX) <> 0 And
             FixedFromIntChecked(100, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxXOut = 1 And boxPosOut = 5),
        "one map unit above Left selects the middle boxx1")
  Check(Bool(FixedFromIntChecked(100, @cameraX) <> 0 And
             FixedFromIntChecked(100, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxXOut = 2 And boxPosOut = 6),
        "cameraX exactly on Right does not satisfy strict < and selects boxx2")
  Check(Bool(FixedFromIntChecked(99, @cameraX) <> 0 And
             FixedFromIntChecked(100, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxXOut = 1 And boxPosOut = 5),
        "one map unit below Right selects the middle boxx1")

  Check(Bool(FixedFromIntChecked(-1, @cameraX) <> 0 And
             FixedFromIntChecked(200, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxYOut = 0 And boxPosOut = 1),
        "cameraY exactly on Top uses >= and selects boxy0")
  Check(Bool(FixedFromIntChecked(-1, @cameraX) <> 0 And
             FixedFromIntChecked(199, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxYOut = 1 And boxPosOut = 5),
        "one map unit below Top selects the middle boxy1")
  Check(Bool(FixedFromIntChecked(-1, @cameraX) <> 0 And
             FixedFromIntChecked(50, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxYOut = 2 And boxPosOut = 9),
        "cameraY exactly on Bottom does not satisfy strict > and selects boxy2")
  Check(Bool(FixedFromIntChecked(-1, @cameraX) <> 0 And
             FixedFromIntChecked(51, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxYOut = 1 And boxPosOut = 5),
        "one map unit above Bottom selects the middle boxy1")

  Check(Bool(FixedFromIntChecked(-100, @cameraX) <> 0 And
             FixedFromIntChecked(200, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxXOut = 0 And boxYOut = 0 And boxPosOut = 0),
        "simultaneous Left/Top equality selects corner boxpos 0")
  Check(Bool(FixedFromIntChecked(100, @cameraX) <> 0 And
             FixedFromIntChecked(50, @cameraY) <> 0 And
             WallBoxPosition(cameraX, cameraY, topFixed, bottomFixed,
                             leftFixed, rightFixed, @boxXOut, @boxYOut, @boxPosOut) <> 0 And
             boxXOut = 2 And boxYOut = 2 And boxPosOut = 10),
        "simultaneous Right/Bottom equality selects corner boxpos 10")
EndProcedure

Procedure TestWC42()
  Protected map.MapLevel
  Protected buildOk.i
  Protected camera.BspCamera
  Protected projection.Projection
  Protected state.ClipState
  Protected clipOk.i
  Protected projectionOk.i
  Protected clipCreated.i = 0
  Protected projectionCreated.i = 0
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected prodVerdict.l = -1
  Protected refVerdict.l = -1
  Protected prodOk.i
  Protected refOk.i
  Protected width.l = 0
  Protected ranges.l = 0
  Protected spans.l = 0

  BeginCase("WC42", "Camera inside bbox (boxpos=5) always conservatively visible")

  buildOk = TestBuildSingleNodeBBox(@map, 200, 50, -100, 100)
  Check(Bool(buildOk <> 0), "inside-box synthetic node map validates")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 100, 0) <> 0),
        "camera -1,100 map units is strictly inside the bbox")
  projectionOk = ProjectionInitClassic(@projection)
  Check(Bool(projectionOk <> 0), "bbox projection tables initialize")
  If projectionOk <> 0
    projectionCreated = 1
  EndIf
  clipOk = ClipStateBeginFrame(@state, 320)
  Check(Bool(clipOk <> 0), "bbox clip frame begins at 320")
  If clipOk <> 0
    clipCreated = 1
  EndIf
  Check(Bool(ClipSolidSegment(@state, 0, 319, 0, 0, 0, 0, 0, -1) <> 0),
        "full-screen solid post installed before the inside-box check")
  Check(Bool(BspCameraGet(@camera, @cameraX, @cameraY, @heading) <> 0),
        "bbox camera fixed values are readable")

  prodVerdict = -1
  prodOk = WallCheckBBox(@map, @camera, @projection, @state, 0, 0, @prodVerdict)
  Check(Bool(prodOk <> 0 And prodVerdict = #WALLBBOX_Visible),
        "production inside-box short path ignores current occlusion and is visible")
  TestRefClipBeginFrame(320)
  TestRefClipApply(0, 319, #WALL_KIND_SOLID, 0, 0, 0, 0, 0, -1)
  refVerdict = -1
  refOk = TestRefCheckBBox(@map, 0, 0, cameraX, cameraY, heading, @refVerdict)
  Check(Bool(refOk <> 0 And refVerdict = #REFBBOX_Visible),
        "independent bbox oracle confirms boxpos5 is conservatively visible")
  Check(Bool(WallVisibilityLastError() = ""), "inside-box bbox success clears diagnostics")
  Check(Bool(ClipStateGetStats(@state, @width, @ranges, @spans, 0, 0, 0) <> 0 And
             width = 320 And ranges = 3 And spans = 1),
        "footprint check leaves the full-screen real post untouched")
  If clipCreated <> 0
    ClipStateReset(@state)
  EndIf
  If projectionCreated <> 0
    ProjectionReset(@projection)
  EndIf
  MapLevelReset(@map)
EndProcedure

Procedure TestWC43()
  Protected map.MapLevel
  Protected buildOk.i
  Protected camera.BspCamera
  Protected projection.Projection
  Protected state.ClipState
  Protected projectionOk.i
  Protected clipOk.i
  Protected projectionCreated.i = 0
  Protected clipCreated.i = 0
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected prodVerdict.l = -1
  Protected refVerdict.l = -1
  Protected prodOk.i
  Protected refOk.i
  Protected width.l = 0
  Protected ranges.l = 0
  Protected spans.l = 0

  BeginCase("WC43", "No occlusion posts: far bbox preserved unless genuinely outside FOV")

  buildOk = TestBuildSingleNodeBBox(@map, 200, 50, -100, 100)
  Check(Bool(buildOk <> 0), "broad bottom-edge synthetic bbox map validates")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0),
        "camera -1,0 heading ANG90 selects reachable boxpos 9")
  projectionOk = ProjectionInitClassic(@projection)
  Check(Bool(projectionOk <> 0), "empty-clip bbox projection initializes")
  If projectionOk <> 0
    projectionCreated = 1
  EndIf
  clipOk = ClipStateBeginFrame(@state, 320)
  Check(Bool(clipOk <> 0), "empty-clip bbox frame begins")
  If clipOk <> 0
    clipCreated = 1
  EndIf
  Check(Bool(BspCameraGet(@camera, @cameraX, @cameraY, @heading) <> 0),
        "bbox camera fixed values are readable")

  prodVerdict = -1
  prodOk = WallCheckBBox(@map, @camera, @projection, @state, 0, 0, @prodVerdict)
  Check(Bool(prodOk <> 0 And prodVerdict = #WALLBBOX_Visible),
        "empty solidsegs preserve the broad projected bbox as VISIBLE")
  TestRefClipBeginFrame(320)
  refVerdict = -1
  refOk = TestRefCheckBBox(@map, 0, 0, cameraX, cameraY, heading, @refVerdict)
  Check(Bool(refOk <> 0 And refVerdict = #REFBBOX_Visible),
        "independent empty-post oracle confirms VISIBLE")
  Check(Bool(ClipStateGetStats(@state, @width, @ranges, @spans, 0, 0, 0) <> 0 And
             width = 320 And ranges = 2 And spans = 0),
        "the no-occlusion check never mutated the empty clip state")
  If clipCreated <> 0
    ClipStateReset(@state)
  EndIf
  If projectionCreated <> 0
    ProjectionReset(@projection)
  EndIf
  MapLevelReset(@map)
EndProcedure

Procedure TestWC44()
  Protected map.MapLevel
  Protected buildOk.i
  Protected camera.BspCamera
  Protected projection.Projection
  Protected state.ClipState
  Protected projectionOk.i
  Protected clipOk.i
  Protected projectionCreated.i = 0
  Protected clipCreated.i = 0
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected prodVerdict.l = -1
  Protected refVerdict.l = -1
  Protected prodOk.i
  Protected refOk.i
  Protected width.l = 0
  Protected ranges.l = 0
  Protected spans.l = 0

  BeginCase("WC44", "Bbox completely behind FOV: safe rejection with independent oracle")

  buildOk = TestBuildSingleNodeBBox(@map, 200, 50, -100, 100)
  Check(Bool(buildOk <> 0), "behind-FOV synthetic bbox map validates")
  Check(Bool(BspCameraSetMapUnits(@camera, 200, 0, 0) <> 0),
        "camera east of the box heading ANG0 selects reachable boxpos 10")
  projectionOk = ProjectionInitClassic(@projection)
  Check(Bool(projectionOk <> 0), "behind-FOV bbox projection initializes")
  If projectionOk <> 0
    projectionCreated = 1
  EndIf
  clipOk = ClipStateBeginFrame(@state, 320)
  Check(Bool(clipOk <> 0), "behind-FOV bbox frame begins empty")
  If clipOk <> 0
    clipCreated = 1
  EndIf
  Check(Bool(BspCameraGet(@camera, @cameraX, @cameraY, @heading) <> 0),
        "bbox camera fixed values are readable")

  prodVerdict = -1
  prodOk = WallCheckBBox(@map, @camera, @projection, @state, 0, 0, @prodVerdict)
  Check(Bool(prodOk <> 0 And prodVerdict = #WALLBBOX_Occluded),
        "both corner angles lie outside the left/right FOV branches -> OCCLUDED")
  TestRefClipBeginFrame(320)
  refVerdict = -1
  refOk = TestRefCheckBBox(@map, 0, 0, cameraX, cameraY, heading, @refVerdict)
  Check(Bool(refOk <> 0 And refVerdict = #REFBBOX_Occluded),
        "independent oracle agrees on the behind-FOV Occluded verdict")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And
             ranges = 2 And spans = 0),
        "the rejected far box left the empty occlusion state unchanged")
  If clipCreated <> 0
    ClipStateReset(@state)
  EndIf
  If projectionCreated <> 0
    ProjectionReset(@projection)
  EndIf
  MapLevelReset(@map)
EndProcedure

Procedure TestWC45()
  Protected map.MapLevel
  Protected buildOk.i
  Protected camera.BspCamera
  Protected projection.Projection
  Protected state.ClipState
  Protected projectionOk.i
  Protected clipOk.i
  Protected projectionCreated.i = 0
  Protected clipCreated.i = 0
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected prodVerdict.l = -1
  Protected refVerdict.l = -1
  Protected prodOk.i
  Protected refOk.i
  Protected width.l = 0
  Protected ranges.l = 0
  Protected spans.l = 0
  Protected postFirst.l = 0
  Protected postLast.l = 0

  BeginCase("WC45", "Bbox projected range fully covered by one solidseg -> OCCLUDED")

  buildOk = TestBuildSingleNodeBBox(@map, 200, 50, -100, 100)
  Check(Bool(buildOk <> 0), "half-screen-occluded synthetic bbox map validates")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0),
        "camera -1,0 heading ANG90 selects the broad row9 horizontal span")
  projectionOk = ProjectionInitClassic(@projection)
  Check(Bool(projectionOk <> 0), "full-occlusion bbox projection initializes")
  If projectionOk <> 0
    projectionCreated = 1
  EndIf
  clipOk = ClipStateBeginFrame(@state, 320)
  Check(Bool(clipOk <> 0), "full-occlusion bbox frame begins")
  If clipOk <> 0
    clipCreated = 1
  EndIf
  Check(Bool(ClipSolidSegment(@state, 0, 319, 0, 0, 0, 0, 0, -1) <> 0),
        "one full-screen real post is installed")
  Check(Bool(ClipStateGetRange(@state, 1, @postFirst, @postLast) <> 0 And
             postFirst = 0 And postLast = 319),
        "single solid post covers inclusive columns 0..319")
  Check(Bool(BspCameraGet(@camera, @cameraX, @cameraY, @heading) <> 0),
        "bbox camera fixed values are readable")

  prodVerdict = -1
  prodOk = WallCheckBBox(@map, @camera, @projection, @state, 0, 0, @prodVerdict)
  Check(Bool(prodOk <> 0 And prodVerdict = #WALLBBOX_Occluded),
        "one post fully contains the projected span -> production OCCLUDED")
  TestRefClipBeginFrame(320)
  TestRefClipApply(0, 319, #WALL_KIND_SOLID, 0, 0, 0, 0, 0, -1)
  refVerdict = -1
  refOk = TestRefCheckBBox(@map, 0, 0, cameraX, cameraY, heading, @refVerdict)
  Check(Bool(refOk <> 0 And refVerdict = #REFBBOX_Occluded),
        "independent post-containment oracle agrees on Occluded")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And
             ranges = 3 And spans = 1),
        "the query only read the full-screen post; its state stayed at one span")
  If clipCreated <> 0
    ClipStateReset(@state)
  EndIf
  If projectionCreated <> 0
    ProjectionReset(@projection)
  EndIf
  MapLevelReset(@map)
EndProcedure

Procedure TestWC46()
  Protected map.MapLevel
  Protected buildOk.i
  Protected camera.BspCamera
  Protected projection.Projection
  Protected state.ClipState
  Protected projectionOk.i
  Protected clipOk.i
  Protected projectionCreated.i = 0
  Protected clipCreated.i = 0
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected prodVerdict.l = -1
  Protected refVerdict.l = -1
  Protected prodOk.i
  Protected refOk.i
  Protected width.l = 0
  Protected ranges.l = 0
  Protected spans.l = 0
  Protected firstPostFirst.l = 0
  Protected firstPostLast.l = 0
  Protected secondPostFirst.l = 0
  Protected secondPostLast.l = 0

  BeginCase("WC46", "Bbox partially covered, multiple clips, fencepost single pixel -> VISIBLE")

  buildOk = TestBuildSingleNodeBBox(@map, 200, 50, -100, 100)
  Check(Bool(buildOk <> 0), "gap-column synthetic bbox map validates")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0),
        "camera -1,0 heading ANG90 selects the broad row9 horizontal span")
  projectionOk = ProjectionInitClassic(@projection)
  Check(Bool(projectionOk <> 0), "partial-occlusion bbox projection initializes")
  If projectionOk <> 0
    projectionCreated = 1
  EndIf
  clipOk = ClipStateBeginFrame(@state, 320)
  Check(Bool(clipOk <> 0), "partial-occlusion bbox frame begins")
  If clipOk <> 0
    clipCreated = 1
  EndIf
  Check(Bool(ClipSolidSegment(@state, 0, 199, 0, 0, 0, 0, 0, -1) <> 0 And
             ClipSolidSegment(@state, 201, 319, 1, 1, 0, 0, 0, -1) <> 0),
        "two solid posts leaving exactly the single uncovered column 200")
  Check(Bool(ClipStateGetRange(@state, 1, @firstPostFirst, @firstPostLast) <> 0 And
             firstPostFirst = 0 And firstPostLast = 199),
        "left solid post ends at inclusive 199")
  Check(Bool(ClipStateGetRange(@state, 2, @secondPostFirst, @secondPostLast) <> 0 And
             secondPostFirst = 201 And secondPostLast = 319),
        "right solid post starts at inclusive 201, leaving fencepost column 200")
  Check(Bool(BspCameraGet(@camera, @cameraX, @cameraY, @heading) <> 0),
        "bbox camera fixed values are readable")

  prodVerdict = -1
  prodOk = WallCheckBBox(@map, @camera, @projection, @state, 0, 0, @prodVerdict)
  Check(Bool(prodOk <> 0 And prodVerdict = #WALLBBOX_Visible),
        "no single post fully contains the span -> production conservatively VISIBLE")
  TestRefClipBeginFrame(320)
  TestRefClipApply(0, 199, #WALL_KIND_SOLID, 0, 0, 0, 0, 0, -1)
  TestRefClipApply(201, 319, #WALL_KIND_SOLID, 1, 1, 0, 0, 0, -1)
  refVerdict = -1
  refOk = TestRefCheckBBox(@map, 0, 0, cameraX, cameraY, heading, @refVerdict)
  Check(Bool(refOk <> 0 And refVerdict = #REFBBOX_Visible),
        "independent multiple-post oracle agrees on VISIBLE")
  Check(Bool(gRefCovered(200) <> 0), "reference bitmap leaves column 200 as the one uncovered fencepost pixel")
  Check(Bool(ClipStateGetStats(@state, 0, @ranges, @spans, 0, 0, 0) <> 0 And
             ranges = 4 And spans = 2),
        "two real occluder posts plus the two sentinels stay tracked")
  If clipCreated <> 0
    ClipStateReset(@state)
  EndIf
  If projectionCreated <> 0
    ProjectionReset(@projection)
  EndIf
  MapLevelReset(@map)
EndProcedure

Procedure TestWC47()
  Protected map.MapLevel
  Protected result.WallVisibilityResult
  Protected buildOk.i
  Protected measureOk.i
  Protected compareOk.i
  Protected refHash.q = -1
  Protected resultHash.q = -1
  Protected spanKind.l = 0
  Protected spanSub.l = 0
  Protected spanSeg.l = 0
  Protected spanLine.l = 0
  Protected spanSide.l = 0
  Protected spanFront.l = 0
  Protected spanBack.l = 0
  Protected spanFirst.l = 0
  Protected spanLast.l = 0

  BeginCase("WC47", "Concrete two-leaf BSP: near SOLID occludes far child only after near visits")

  TestBuildTwoLeafTree(@map, 0)
  Check(Bool(MapLevelIsReady(@map) <> 0), "two-leaf all-SOLID tree validates")
  measureOk = TestMeasureWallBuild(@map, -1, 0, #BAM_ANG90,
                                   @result, @buildOk, @compareOk, @refHash)
  Check(Bool(measureOk <> 0 And buildOk = 1 And compareOk = 1),
        "production online Build agrees with the recursive near-to-far oracle")
  Check(Bool(result\Count = 1), "only the near leaf contributes a published span")
  Check(Bool(result\VisitedNodes = 1 And result\VisitedSubsectors = 1 And
             result\ProcessedSegs = 1 And result\EmittedFragments = 1),
        "near leaf processed; far leaf is never visited after occlusion")
  Check(Bool(result\SolidCandidates = 1 And result\PassCandidates = 0),
        "near broad one-sided wall classifies as SOLID")
  Check(Bool(result\BboxTests = 1 And result\BboxOccluded = 1 And
             result\BboxVisible = 0 And result\OcclusionSkips = 1),
        "far bbox tested only once, after near spans, and prunes the far branch")
  Check(Bool(result\Count = 1 And WallVisibilityGetSpan(@result, 0,
             @spanSub, @spanSeg, @spanLine, @spanSide, @spanFront, @spanBack,
             @spanFirst, @spanLast, @spanKind) <> 0 And
             spanSub = 1 And spanSeg = 1 And spanKind = #WALL_KIND_SOLID And
             spanFirst >= 0 And spanLast >= spanFirst And spanLast < #PROJ_VIEWWIDTH),
        "published span is source-identifiable, SOLID and inside 0..319")
  resultHash = TestWallResultHash(@result)
  Check(Bool(resultHash <> -1 And resultHash = refHash),
        "production span-order fingerprint equals the independent oracle hash")
  Check(Bool(result\WorkItems > 0), "iterative stack work-item accounting is bounded/nonzero")
  WallVisibilityReset(@result)
  MapLevelReset(@map)
EndProcedure

Procedure TestWC48()
  Protected map.MapLevel
  Protected result.WallVisibilityResult
  Protected buildOk.i
  Protected measureOk.i
  Protected compareOk.i
  Protected refHash.q = -1
  Protected resultHash.q = -1
  Protected spanSubA.l = 0
  Protected spanSubB.l = 0
  Protected spanKindA.l = 0
  Protected spanKindB.l = 0
  Protected spanFirstA.l = 0
  Protected spanLastA.l = 0
  Protected spanFirstB.l = 0
  Protected spanLastB.l = 0

  BeginCase("WC48", "Near PASS wall does not occlude far branch")

  TestBuildTwoLeafTree(@map, 1)
  Check(Bool(MapLevelIsReady(@map) <> 0), "two-leaf all-PASS tree validates")
  measureOk = TestMeasureWallBuild(@map, -1, 0, #BAM_ANG90,
                                   @result, @buildOk, @compareOk, @refHash)
  Check(Bool(measureOk <> 0 And buildOk = 1 And compareOk = 1),
        "PASS near-wall traversal agrees with the recursive oracle")
  Check(Bool(result\Count = 2), "near PASS and far closed-floor window both publish spans")
  Check(Bool(result\VisitedNodes = 1 And result\VisitedSubsectors = 2),
        "the near PASS wall leaves no occluder, so the far leaf is visited")
  Check(Bool(result\PassCandidates = 2 And result\SolidCandidates = 0),
        "both open-floor-height broad walls classify as PASS")
  Check(Bool(result\BboxTests = 1 And result\BboxVisible = 1 And
             result\BboxOccluded = 0 And result\OcclusionSkips = 0),
        "far bbox remains VISIBLE and the pruned-branch counter stays zero")
  Check(Bool(WallVisibilityGetSpan(@result, 0, @spanSubA, 0, 0, 0, 0, 0,
                                    @spanFirstA, @spanLastA, @spanKindA) <> 0 And
             WallVisibilityGetSpan(@result, 1, @spanSubB, 0, 0, 0, 0, 0,
                                    @spanFirstB, @spanLastB, @spanKindB) <> 0 And
             spanSubA = 1 And spanSubB = 0 And spanKindA = #WALL_KIND_PASS And
             spanKindB = #WALL_KIND_PASS And spanFirstA >= 0 And spanLastA < 320 And
             spanFirstB >= 0 And spanLastB < 320),
        "chronology is near leaf1 PASS [0..319] then far leaf0 PASS [0..319]")
  resultHash = TestWallResultHash(@result)
  Check(Bool(resultHash = refHash), "PASS traversal fingerprint equals the independent oracle")
  WallVisibilityReset(@result)
  MapLevelReset(@map)
EndProcedure

Procedure TestWC49()
  Protected mapA.MapLevel
  Protected mapB.MapLevel
  Protected resultA.WallVisibilityResult
  Protected resultB.WallVisibilityResult
  Protected buildA.i
  Protected compareA.i
  Protected buildB.i
  Protected compareB.i
  Protected measureA.i
  Protected measureB.i
  Protected refHashA.q = -1
  Protected refHashB.q = -1
  Protected hashA.q = -1
  Protected hashB.q = -1
  Protected orderSub0.l = 0
  Protected orderSub1.l = 0
  Protected orderSub2.l = 0
  Protected orderSub3.l = 0
  Protected orderKindA.l = 0
  Protected orderFirstA.l = 0
  Protected orderLastA.l = 0

  BeginCase("WC49", "Deeper near/far order; test-only recursive-online oracle equivalence")

  ; (A) all-SOLID four-leaf tree: the near leaf3 full wall occludes both far bboxes.
  TestBuildQuadTree(@mapA, 0)
  Check(Bool(MapLevelIsReady(@mapA) <> 0), "four-leaf all-SOLID tree validates")
  measureA = TestMeasureWallBuild(@mapA, -1, 0, #BAM_ANG90,
                                  @resultA, @buildA, @compareA, @refHashA)
  Check(Bool(measureA <> 0 And buildA = 1 And compareA = 1),
        "SOLID nested traversal agrees with the recursive near-first oracle")
  Check(Bool(resultA\VisitedNodes = 2 And resultA\VisitedSubsectors = 1 And
             resultA\ProcessedSegs = 1 And resultA\SolidCandidates = 1),
        "root node2 and node1 are entered; node0 plus leaves 2/1/0 are pruned")
  Check(Bool(resultA\BboxTests = 2 And resultA\BboxOccluded = 2 And
             resultA\BboxVisible = 0 And resultA\OcclusionSkips = 2),
        "both far bbox evaluations occur after the near leaf3 coverage and prune")
  Check(Bool(resultA\Count = 1 And
             WallVisibilityGetSpan(@resultA, 0, @orderSub0, 0, 0, 0, 0, 0,
                                   @orderFirstA, @orderLastA, @orderKindA) <> 0 And
             orderSub0 = 3 And orderKindA = #WALL_KIND_SOLID And orderLastA < 320),
        "only near leaf3 publishes its SOLID span")
  hashA = TestWallResultHash(@resultA)
  Check(Bool(hashA = refHashA), "SOLID nested fingerprint equals the recursive oracle hash")
  WallVisibilityReset(@resultA)
  MapLevelReset(@mapA)

  ; (B) all-PASS four-leaf tree: no solidsegs update, every far branch is visited.
  TestBuildQuadTree(@mapB, 1)
  Check(Bool(MapLevelIsReady(@mapB) <> 0), "four-leaf all-PASS tree validates")
  measureB = TestMeasureWallBuild(@mapB, -1, 0, #BAM_ANG90,
                                  @resultB, @buildB, @compareB, @refHashB)
  Check(Bool(measureB <> 0 And buildB = 1 And compareB = 1),
        "PASS nested traversal agrees with the recursive near-first oracle")
  Check(Bool(resultB\VisitedNodes = 3 And resultB\VisitedSubsectors = 4 And
             resultB\ProcessedSegs = 4 And resultB\PassCandidates = 4),
        "three nodes and all four leaves are visited exactly once")
  Check(Bool(resultB\BboxTests = 3 And resultB\BboxVisible = 3 And
             resultB\BboxOccluded = 0 And resultB\OcclusionSkips = 0),
        "every far bbox is VISIBLE because PASS walls never mutate occlusion")
  Check(Bool(resultB\Count = 4), "four ordered PASS fragments in the deeper tree")
  Check(Bool(WallVisibilityGetSpan(@resultB, 0, @orderSub0, 0, 0, 0, 0, 0,
                                    @orderFirstA, @orderLastA, @orderKindA) <> 0 And
             WallVisibilityGetSpan(@resultB, 1, @orderSub1, 0, 0, 0, 0, 0,
                                    @orderFirstA, @orderLastA, @orderKindA) <> 0 And
             WallVisibilityGetSpan(@resultB, 2, @orderSub2, 0, 0, 0, 0, 0,
                                    @orderFirstA, @orderLastA, @orderKindA) <> 0 And
             WallVisibilityGetSpan(@resultB, 3, @orderSub3, 0, 0, 0, 0, 0,
                                    @orderFirstA, @orderLastA, @orderKindA) <> 0 And
             orderSub0 = 3 And orderSub1 = 2 And orderSub2 = 1 And orderSub3 = 0 And
             orderKindA = #WALL_KIND_PASS),
        "publication order is near/far node1 leaves 3,2 then node0 leaves 1,0")
  hashB = TestWallResultHash(@resultB)
  Check(Bool(hashB = refHashB), "PASS nested fingerprint equals the recursive oracle hash")
  WallVisibilityReset(@resultB)
  MapLevelReset(@mapB)
EndProcedure

Procedure TestWC50()
  Protected map.MapLevel
  Protected result.WallVisibilityResult
  Protected buildOk.i
  Protected measurementOk.i
  Protected compareOk.i
  Protected refHash.q = -1
  Protected resultHash.q = -1
  Protected rootIsSubsector.l = 0
  Protected rootIndex.l = 0
  Protected rootOk.i
  Protected spanSub.l = 0
  Protected spanSeg.l = 0
  Protected spanKind.l = 0
  Protected spanFirst.l = 0
  Protected spanLast.l = 0

  BeginCase("WC50", "Zero-node one-subsector map and empty/subsector root edge handling")

  TestBuildZeroNodeWall(@map)
  Check(Bool(MapLevelIsReady(@map) <> 0), "zero-node one-subsector synthetic map validates")
  rootOk = MapLevelGetBspRoot(@map, @rootIsSubsector, @rootIndex)
  Check(Bool(rootOk <> 0 And rootIsSubsector = 1 And rootIndex = 0),
        "validated root is exactly a subsector leaf: NF_SUBSECTOR|0")
  Check(Bool(map\Nodes\Count = 0 And map\Subsectors\Count = 1),
        "source has zero BSP nodes and exactly one subsector")
  measurementOk = TestMeasureWallBuild(@map, -1, 0, #BAM_ANG90,
                                       @result, @buildOk, @compareOk, @refHash)
  Check(Bool(measurementOk <> 0 And buildOk = 1 And compareOk = 1),
        "zero-node online Build agrees with the recursive root-leaf oracle")
  Check(Bool(result\VisitedNodes = 0 And result\VisitedSubsectors = 1 And
             result\ProcessedSegs = 1 And result\BboxTests = 0 And
             result\OcclusionSkips = 0),
        "subsector root processes one leaf with no node or bbox evaluation")
  Check(Bool(result\Count = 1 And WallVisibilityGetSpan(@result, 0,
             @spanSub, @spanSeg, 0, 0, 0, 0, @spanFirst, @spanLast, @spanKind) <> 0 And
             spanSub = 0 And spanSeg = 0 And spanKind = #WALL_KIND_SOLID And
             spanFirst >= 0 And spanLast < 320),
        "root leaf publishes its one valid SOLID interval")
  resultHash = TestWallResultHash(@result)
  Check(Bool(resultHash <> -1 And resultHash = refHash),
        "zero-node fingerprint equals the independent recursive oracle hash")
  Check(Bool(result\WorkItems > 0), "subsector-root stack still records bounded work items")
  WallVisibilityReset(@result)
  MapLevelReset(@map)
EndProcedure

Procedure TestWC51()
  Protected map.MapLevel
  Protected result.WallVisibilityResult
  Protected *node.MapNode
  Protected buildOk.i = 0
  Protected compareOk.i = 0
  Protected measureOk.i
  Protected refHash.q = -1
  Protected childMissing.l = 0
  Protected childNodeSelf.l = 0

  BeginCase("WC51", "Corrupt child/bbox/delta, DAG/work/event caps: deterministic safe failure or conservative fallback")

  Check(Bool(#WALLVIS_MaxSpans = 1000000 And #WALLVIS_MaxWorkItems = 4000000),
        "explicit span/work hard caps are declared")

  TestBuildTwoLeafTree(@map, 0)
  Check(Bool(MapLevelIsReady(@map) <> 0), "corruption-target two-leaf tree validates before mutation")
  *node = map\Nodes\Items
  Check(Bool(*node <> 0 And map\Nodes\Count = 1),
        "decoded node storage exposes exactly one mutable root node")

  ; (1) corrupt far child to a missing subsector leaf index.
  childMissing = #MAP_NF_SUBSECTOR ! 99
  *node\Child0 = childMissing
  measureOk = TestMeasureWallBuild(@map, -1, 0, #BAM_ANG90,
                                   @result, @buildOk, @compareOk, @refHash)
  Check(Bool(measureOk = 0 And buildOk = 0), "missing leaf child makes the online Build fail")
  Check(Bool(WallVisibilityLastError() <> "" And
             FindString(WallVisibilityLastError(), "missing subsector") <> 0),
        "missing-leaf failure carries an actionable diagnostic")
  Check(Bool(WallVisibilityIsValid(@result) <> 0 And result\Count = 0 And result\Spans = 0),
        "failed Build leaves a valid empty result, never partial spans")
  Check(Bool(MapLevelIsReady(@map) <> 0), "the corrupted traversal failure leaves level ownership intact")
  ; restore the far leaf before the next probe.
  *node\Child0 = #MAP_NF_SUBSECTOR ! 0

  ; (2) corrupt node origin map-unit value beyond the 16-bit source domain.
  *node\X = 32768
  measureOk = TestMeasureWallBuild(@map, -1, 0, #BAM_ANG90,
                                   @result, @buildOk, @compareOk, @refHash)
  Check(Bool(measureOk = 0 And buildOk = 0), "unconvertible node origin delta fails Build")
  Check(Bool(WallVisibilityLastError() <> "" And
             FindString(WallVisibilityLastError(), "origin X conversion failed") <> 0),
        "origin conversion failure is diagnosed, not silently skipped")
  Check(Bool(WallVisibilityIsValid(@result) <> 0 And result\Count = 0),
        "origin failure leaves the reusable result valid-empty")
  *node\X = 0

  ; (3) corrupt bbox top beyond the signed SHORT domain: conservative UNKNOWN
  ; verdict visits the far branch instead of silently culling it.
  *node\Box0Top = 32768
  measureOk = TestMeasureWallBuild(@map, -1, 0, #BAM_ANG90,
                                   @result, @buildOk, @compareOk, @refHash)
  Check(Bool(measureOk <> 0 And buildOk = 1 And compareOk = 1),
        "bbox arithmetic uncertainty falls back conservatively and matches the oracle")
  Check(Bool(result\BboxUnknown = 1 And result\BboxOccluded = 0 And
             result\BboxVisible = 0 And result\OcclusionSkips = 0),
        "UNKNOWN bbox verdict is counted and never treated as an occlusion cull")
  Check(Bool(result\VisitedSubsectors = 2 And result\ProcessedSegs = 2 And
             result\Count = 1),
        "uncertain far bbox is still visited; the nested far wall emits no extra span")
  *node\Box0Top = 200

  ; (4) cycle mutation: both root children point to the root node itself. The
  ; explicit stack must hit its 2*nodes+4 capacity and fail deterministically
  ; rather than recurse or grow without bound.
  TestBuildTwoLeafTree(@map, 1)
  Check(Bool(MapLevelIsReady(@map) <> 0), "PASS tree validates before the cycle mutation")
  *node = map\Nodes\Items
  childNodeSelf = 0
  *node\Child0 = childNodeSelf
  *node\Child1 = childNodeSelf
  measureOk = TestMeasureWallBuild(@map, -1, 0, #BAM_ANG90,
                                   @result, @buildOk, @compareOk, @refHash)
  Check(Bool(measureOk = 0 And buildOk = 0), "self-child cyclic DAG fails instead of looping")
  Check(Bool(WallVisibilityLastError() <> "" And
             FindString(WallVisibilityLastError(), "stack overflow") <> 0),
        "cyclic child overflow is diagnosed against the bounded stack capacity")
  Check(Bool(WallVisibilityIsValid(@result) <> 0 And result\Count = 0),
        "cycle failure is transactional and leaves no published geometry")
  Check(Bool(MapLevelIsReady(@map) <> 0), "cycle failure did not reset/alter the validated level")
  *node\Child0 = #MAP_NF_SUBSECTOR ! 0
  *node\Child1 = #MAP_NF_SUBSECTOR ! 1
  WallVisibilityReset(@result)
  MapLevelReset(@map)
EndProcedure

Procedure TestWC52()
  Protected map.MapLevel
  Protected camera.BspCamera
  Protected projection.Projection
  Protected resultA.WallVisibilityResult
  Protected resultB.WallVisibilityResult
  Protected *node.MapNode
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected buildAOk.i
  Protected buildBOk.i
  Protected buildRecoveredOk.i
  Protected buildFailedOk.i
  Protected compareRecoveredOk.i
  Protected refHash.q = -1
  Protected hashA.q = -1
  Protected hashB.q = -1
  Protected hashRecovered.q = -1
  Protected countA.l = -1
  Protected countB.l = -1
  Protected countRecovered.l = -1
  Protected firstA.l = 0
  Protected lastA.l = 0
  Protected countAfterReset.l = -1
  Protected hashAfterReset.q = -1
  Protected sub.l = 0
  Protected seg.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0

  BeginCase("WC52", "Transactional failure, old result lifetime after MapLevel/WAD reset, repeated build determinism")

  TestBuildTwoLeafTree(@map, 0)
  Check(Bool(MapLevelIsReady(@map) <> 0), "deterministic two-leaf tree validates")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0),
        "deterministic camera -1,0 heading ANG90 is created")
  Check(Bool(ProjectionInitClassic(@projection) <> 0),
        "reusable immutable classic projection is created")

  buildAOk = WallVisibilityBuild(@map, @camera, @projection, 0, 0, @resultA)
  Check(Bool(buildAOk <> 0 And WallVisibilityIsValid(@resultA) <> 0 And
             WallVisibilityCount(@resultA) > 0),
        "first Build publishes a valid nonempty result A")
  countA = WallVisibilityCount(@resultA)
  hashA = TestWallResultHash(@resultA)
  Check(Bool(countA > 0 And hashA <> -1 And
             WallVisibilityGetSpan(@resultA, 0, @sub, @seg, @line, @side,
                                   @front, @back, @firstA, @lastA, @kind) <> 0 And
             resultA\VisitedSubsectors = 1 And resultA\OcclusionSkips = 1),
        "result A carries one ordered SOLID span and the positive occlusion counters")
  buildBOk = WallVisibilityBuild(@map, @camera, @projection, 0, 0, @resultB)
  Check(Bool(buildBOk <> 0 And WallVisibilityIsValid(@resultB) <> 0),
        "second Build into a separate result object succeeds")
  countB = WallVisibilityCount(@resultB)
  hashB = TestWallResultHash(@resultB)
  Check(Bool(countB = countA And hashB = hashA),
        "repeated same map/camera build is bit-for-bit deterministic in spans/order")

  ; The published result owns numeric copies only: MapLevel reset destroys all
  ; source decoded sets but A must remain fully readable with an identical hash.
  Check(Bool(MapLevelReset(@map) <> 0), "source MapLevel reset succeeds after publication")
  countAfterReset = WallVisibilityCount(@resultA)
  hashAfterReset = TestWallResultHash(@resultA)
  Check(Bool(WallVisibilityIsValid(@resultA) <> 0 And
             countAfterReset = countA And hashAfterReset = hashA),
        "result A survives MapLevelReset with unchanged count and span fingerprint")
  Check(Bool(WallVisibilityGetSpan(@resultA, 0, @sub, @seg, @line, @side,
                                   @front, @back, @first, @last, @kind) <> 0 And
             first = firstA And last = lastA And kind = #WALL_KIND_SOLID),
        "every owned numeric span field remains independently readable after reset")

  ; Rebuild the same synthetic source; intentionally corrupt one child edge and
  ; verify transactional failure against the pre-existing result object.
  TestBuildTwoLeafTree(@map, 0)
  Check(Bool(MapLevelIsReady(@map) <> 0), "source B rebuild validates for failure probe")
  *node = map\Nodes\Items
  Check(Bool(*node <> 0), "root node remains mutable for the failure probe")
  *node\Child0 = #MAP_NF_SUBSECTOR ! 99
  buildFailedOk = WallVisibilityBuild(@map, @camera, @projection, 0, 0, @resultA)
  Check(Bool(buildFailedOk = 0), "corrupted far child rejects the rebuild transactionally")
  Check(Bool(WallVisibilityIsValid(@resultA) <> 0 And WallVisibilityCount(@resultA) = 0 And
             resultA\Spans = 0 And WallVisibilityLastError() <> ""),
        "failed rebuild replaces result A with a valid empty diagnostic-only object")
  Check(Bool(BspCameraGet(@camera, @cameraX, @cameraY, @heading) <> 0 And
             cameraX = -65536 And cameraY = 0 And heading = #BAM_ANG90),
        "failure leaves the input camera owned/ready and unchanged")
  Check(Bool(ProjectionIsValid(@projection) <> 0),
        "failure leaves the immutable projection tables valid")
  Check(Bool(MapLevelIsReady(@map) <> 0),
        "failure leaves the (locally corrupted) map level ready and owned")

  ; Restore the edge and rebuild into the same result; deterministic recovery
  ; must reproduce the original hash/count rather than stale partial data.
  *node\Child0 = #MAP_NF_SUBSECTOR ! 0
  buildRecoveredOk = WallVisibilityBuild(@map, @camera, @projection, 0, 0, @resultA)
  Check(Bool(buildRecoveredOk <> 0 And WallVisibilityIsValid(@resultA) <> 0),
        "restored edge allows the same result object to recover")
  countRecovered = WallVisibilityCount(@resultA)
  hashRecovered = TestWallResultHash(@resultA)
  Check(Bool(countRecovered = countA And hashRecovered = hashA),
        "failure/recovery cycle reproduces the original deterministic span hash")
  compareRecoveredOk = TestCompareWallResult(@map, -1, 0, #BAM_ANG90, @resultA, @refHash)

  Check(Bool(compareRecoveredOk <> 0 And hashRecovered = refHash),
        "recovered result still matches the fresh recursive-online oracle")

  ; Keep a deterministic reference snapshot from the pre-recycle result B.
  Check(Bool(WallVisibilityIsValid(@resultB) <> 0 And WallVisibilityCount(@resultB) = countA),
        "unrelated result B retained its own valid lifetime and count throughout")

  WallVisibilityReset(@resultA)
  WallVisibilityReset(@resultB)
  Check(Bool(WallVisibilityReset(@resultA) <> 0 And WallVisibilityReset(@resultA) <> 0 And
             WallVisibilityIsValid(@resultA) <> 0 And WallVisibilityCount(@resultA) = 0),
        "repeated result Reset is idempotent and leaves a reusable valid-empty owner")
  ProjectionReset(@projection)
  MapLevelReset(@map)
EndProcedure

; ---------------------------------------------------------------------------
; Suite driver and measured summary
; ---------------------------------------------------------------------------

Procedure Main()
  TestWC01()
  TestWC02()
  TestWC03()
  TestWC04()
  TestWC05()
  TestWC06()
  TestWC07()
  TestWC08()
  TestWC09()
  TestWC10()
  TestWC11()
  TestWC12()
  TestWC13()
  TestWC14()
  TestWC15()
  TestWC16()
  TestWC17()
  TestWC18()
  TestWC19()
  TestWC20()
  TestWC21()
  TestWC22()
  TestWC23()
  TestWC24()
  TestWC25()
  TestWC26()
  TestWC27()
  TestWC28()
  TestWC29()
  TestWC30()
  TestWC31()
  TestWC32()
  TestWC33()
  TestWC34()
  TestWC35()
  TestWC36()
  TestWC37()
  TestWC38()
  TestWC39()
  TestWC40()
  TestWC41()
  TestWC42()
  TestWC43()
  TestWC44()
  TestWC45()
  TestWC46()
  TestWC47()
  TestWC48()
  TestWC49()
  TestWC50()
  TestWC51()
  TestWC52()
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
