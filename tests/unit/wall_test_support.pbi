; -----------------------------------------------------------------------------
; DoomPB - shared original-synthetic map builder for M3-05 wall tests
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Test-support module only: owned synthetic ten-lump records/decoding from the
; existing M3-04 unit harness, plus an explicit SEGS raw 16-bit angle field for
; realistic wall-projection fixtures. Never WAD bytes, commercial data,
; graphics, production output or copyrighted payload: every map record is
; caller-defined original numbers/names and written little-endian at vanilla
; strides. THINGS is zero-length unless a future test explicitly needs it.
;
; Include after an EnableExplicit harness. This guard prevents duplicate
; definitions across unit/integration test programs.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLTESTSUPPORT_PBI, #PB_Constant) = 0

#DOOMPB_WALLTESTSUPPORT_PBI = 1

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Map/MapTypes.pbi"
XIncludeFile "../../src/Map/MapDecode.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
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
  RawAngle.l
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
; Synthetic ten-lump buffers indexed 1..10 in vanilla canonical order.
Global Dim gMapLump(10)
Global Dim gMapLumpSize.q(10)

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
    Put16(gMapLump(5), i * #MAP_SegSize + 4, *seg\RawAngle)
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
CompilerEndIf