; -----------------------------------------------------------------------------
; DoomPB - M3-04 screen projection / wall clipping / occlusion synthetic integration
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; I01: fresh standalone entry point streams a legal synthetic ten-lump PWAD ->
;      WADOpen -> MapLevelLoad -> fixed camera -> full online visible walk; the
;      published ordered spans and counters are compared to an independent,
;      explicitly constructed expected fingerprint/field list.
; I02: the same nested three-node/four-leaf tree is streamed twice (all-SOLID and
;      all-PASS variants). The pre-existing cull-free BspTraceBuild must keep its
;      complete four-leaf/three-node chronology and its expected event hash while
;      the M3-04 online walker actually demonstrates BboxTests>0,
;      OcclusionSkips>0 for the SOLID map and OcclusionSkips=0/full traversal for
;      the PASS control. No old M3-03 trace API or assertions are modified.
; I03: A -> B -> A lifetime: two synthetic maps, camera heading changes,
;      WADClose/MapLevelReset survival, deterministic first/repeat/reload and
;      directional fingerprints, then a deliberately corrupted decoded BSP child
;      fails transactionally and the restored edge reproduces the original hash.
;      Only measured numeric hashes and explicit expected field tuples are used.
;
; Optional owner-IWAD I04 is a separate harness; no WAD asset bytes, graphics,
; coordinates or screenshots are committed or printed. Fixtures live under an
; ignored build tmp directory and are removed. The application version remains
; 0.2.0; the CLI is untouched.
;
; Exit code: 0 when every assertion passed, otherwise the failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/Projection.pbi"
XIncludeFile "../../src/Renderer/ClipSegs.pbi"
XIncludeFile "../../src/Renderer/WallVisibility.pbi"
XIncludeFile "../../src/Renderer/BSP.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

#TEST_FNV_Offset = -3750763034362895579
#TEST_FNV_Prime = 1099511628211

Global gFixtureDirectory.s = ""
Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

Global gWadFile.i = 0
Global gWadEntryCount.i = 0
Global Dim gWadName.s(255)
Global Dim gWadPosition.q(255)
Global Dim gWadSize.q(255)

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

Procedure.i TestSubOrder(*Trace.BspTrace, EventIndex.i, *Subsector.Long)
  Protected kind.l = -1
  Protected temp.l = -1
  Protected ok.i

  ok = BspTraceGet(*Trace, EventIndex, @kind, *Subsector, @temp, @temp,
                   @temp, @temp, @temp, @temp)
  ProcedureReturn Bool(ok <> 0 And kind = #BSP_EventSubsector)
EndProcedure

; ---------------------------------------------------------------------------
; Fixture directory and streamed WAD writer (original synthetic records only)
; ---------------------------------------------------------------------------

Procedure.s FixturePath(FileName.s)
  ProcedureReturn gFixtureDirectory + FileName
EndProcedure

Procedure.i PrepareFixtureDirectory()
  Protected directorySize.i

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "m3-wall-clip-test-tmp" + #FixtureSeparator
  directorySize = FileSize(gFixtureDirectory)
  If directorySize = -1
    ProcedureReturn CreateDirectory(gFixtureDirectory)
  EndIf
  If directorySize = -2
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure.i CleanupFixtureDirectory()
  Protected directory.i
  Protected entryName.s
  Protected deleted.i

  directory = ExamineDirectory(#PB_Any, gFixtureDirectory, "*")
  If directory
    While NextDirectoryEntry(directory)
      If DirectoryEntryType(directory) = #PB_DirectoryEntry_File
        entryName = DirectoryEntryName(directory)
        DeleteFile(gFixtureDirectory + entryName)
      EndIf
    Wend
    FinishDirectory(directory)
  EndIf
  deleted = DeleteDirectory(gFixtureDirectory, "*.*")
  ProcedureReturn deleted
EndProcedure

Procedure.i WadBegin(FileName.s)
  gWadEntryCount = 0
  gWadFile = CreateFile(#PB_Any, FixturePath(FileName))
  If gWadFile = 0
    ProcedureReturn #False
  EndIf
  WriteString(gWadFile, "PWAD", #PB_UTF8)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  ProcedureReturn #True
EndProcedure

Procedure WadAdd(Name.s, *Data.Byte, Size.q)
  gWadName(gWadEntryCount) = Name
  gWadPosition(gWadEntryCount) = Loc(gWadFile)
  gWadSize(gWadEntryCount) = Size
  If Size > 0
    WriteData(gWadFile, *Data, Size)
  EndIf
  gWadEntryCount + 1
EndProcedure

Declare Put32File(Value.q)
Declare PutNameFile(Name.s)

Procedure.i WadFinish()
  Protected directoryOffset.q
  Protected i.i
  Protected entryPosition.q
  Protected entrySize.q
  Protected entryName.s

  directoryOffset = Loc(gWadFile)
  FileSeek(gWadFile, 4)
  Put32File(gWadEntryCount)
  Put32File(directoryOffset)
  FileSeek(gWadFile, directoryOffset)
  For i = 0 To gWadEntryCount - 1
    entryPosition = gWadPosition(i)
    entrySize = gWadSize(i)
    entryName = gWadName(i)
    Put32File(entryPosition)
    Put32File(entrySize)
    PutNameFile(entryName)
  Next
  CloseFile(gWadFile)
  gWadFile = 0
  ProcedureReturn #True
EndProcedure

Procedure Put32File(Value.q)
  WriteByte(gWadFile, Value & $FF)
  WriteByte(gWadFile, (Value >> 8) & $FF)
  WriteByte(gWadFile, (Value >> 16) & $FF)
  WriteByte(gWadFile, (Value >> 24) & $FF)
EndProcedure

Procedure PutNameFile(Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      WriteByte(gWadFile, Asc(Mid(Name, i + 1, 1)))
    Else
      WriteByte(gWadFile, 0)
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic map record packing helpers
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

; Streams one marker plus the canonical ten vanilla map lumps from caller-defined
; specs, all written once and freed immediately. THINGS is zero-length; NODES may
; be zero-length; REJECT is the minimum ceil(sectors^2/8); BLOCKMAP is one cell
; listing every line. On disk records are explicit little-endian at vanilla
; strides, never native structure overlays.
Procedure.i WadAddMapGroup(Marker.s,
                          *Sectors.TestSectorSpec, SectorCount.l,
                          *Lines.TestLineSpec, LineCount.l,
                          *Sides.TestSideSpec, SideCount.l,
                          *Vertices.TestVertexSpec, VertexCount.l,
                          *Segs.TestSegSpec, SegCount.l,
                          *Subs.TestSubSpec, SubCount.l,
                          *Nodes.TestNodeSpec, NodeCount.l)
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

  If Marker = "" Or SectorCount < 1 Or LineCount < 1 Or SideCount < 1 Or
     VertexCount < 1 Or SegCount < 1 Or SubCount < 1 Or
     NodeCount < 0 Or NodeCount > #MAP_MaxRecords
    ProcedureReturn #False
  EndIf
  If *Sectors = 0 Or *Lines = 0 Or *Sides = 0 Or *Vertices = 0 Or
     *Segs = 0 Or *Subs = 0 Or NodeCount > 0 And *Nodes = 0
    ProcedureReturn #False
  EndIf

  WadAdd(Marker, 0, 0)
  WadAdd("THINGS", 0, 0)

  *bytes = NewZero(Int(LineCount) * #MAP_LinedefSize)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  *line = *Lines
  For i = 0 To LineCount - 1
    Put16(*bytes, i * #MAP_LinedefSize, *line\V1)
    Put16(*bytes, i * #MAP_LinedefSize + 2, *line\V2)
    Put16(*bytes, i * #MAP_LinedefSize + 4, *line\Flags)
    Put16(*bytes, i * #MAP_LinedefSize + 6, *line\Special)
    Put16(*bytes, i * #MAP_LinedefSize + 8, *line\Tag)
    Put16(*bytes, i * #MAP_LinedefSize + 10, *line\Side0)
    Put16(*bytes, i * #MAP_LinedefSize + 12, *line\Side1)
    *line = *line + SizeOf(TestLineSpec)
  Next
  WadAdd("LINEDEFS", *bytes, Int(LineCount) * #MAP_LinedefSize)
  FreeMemory(*bytes)

  *bytes = NewZero(Int(SideCount) * #MAP_SidedefSize)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  *side = *Sides
  For i = 0 To SideCount - 1
    Put16(*bytes, i * #MAP_SidedefSize, 0)
    Put16(*bytes, i * #MAP_SidedefSize + 2, 0)
    PutName8(*bytes, i * #MAP_SidedefSize + 4, *side\TopName)
    PutName8(*bytes, i * #MAP_SidedefSize + 12, *side\BottomName)
    PutName8(*bytes, i * #MAP_SidedefSize + 20, *side\MidName)
    Put16(*bytes, i * #MAP_SidedefSize + 28, *side\Sector)
    *side = *side + SizeOf(TestSideSpec)
  Next
  WadAdd("SIDEDEFS", *bytes, Int(SideCount) * #MAP_SidedefSize)
  FreeMemory(*bytes)

  *bytes = NewZero(Int(VertexCount) * #MAP_VertexSize)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  *vertex = *Vertices
  For i = 0 To VertexCount - 1
    Put16(*bytes, i * #MAP_VertexSize, *vertex\X)
    Put16(*bytes, i * #MAP_VertexSize + 2, *vertex\Y)
    *vertex = *vertex + SizeOf(TestVertexSpec)
  Next
  WadAdd("VERTEXES", *bytes, Int(VertexCount) * #MAP_VertexSize)
  FreeMemory(*bytes)

  *bytes = NewZero(Int(SegCount) * #MAP_SegSize)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  *seg = *Segs
  For i = 0 To SegCount - 1
    Put16(*bytes, i * #MAP_SegSize, *seg\V1)
    Put16(*bytes, i * #MAP_SegSize + 2, *seg\V2)
    Put16(*bytes, i * #MAP_SegSize + 4, 0)
    Put16(*bytes, i * #MAP_SegSize + 6, *seg\Line)
    Put16(*bytes, i * #MAP_SegSize + 8, *seg\Side)
    Put16(*bytes, i * #MAP_SegSize + 10, 0)
    *seg = *seg + SizeOf(TestSegSpec)
  Next
  WadAdd("SEGS", *bytes, Int(SegCount) * #MAP_SegSize)
  FreeMemory(*bytes)

  *bytes = NewZero(Int(SubCount) * #MAP_SubsectorSize)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  *sub = *Subs
  For i = 0 To SubCount - 1
    Put16(*bytes, i * #MAP_SubsectorSize, *sub\NumSegs)
    Put16(*bytes, i * #MAP_SubsectorSize + 2, *sub\FirstSeg)
    *sub = *sub + SizeOf(TestSubSpec)
  Next
  WadAdd("SSECTORS", *bytes, Int(SubCount) * #MAP_SubsectorSize)
  FreeMemory(*bytes)

  If NodeCount > 0
    *bytes = NewZero(Int(NodeCount) * #MAP_NodeSize)
    If *bytes = 0
      ProcedureReturn #False
    EndIf
    *node = *Nodes
    For i = 0 To NodeCount - 1
      Put16(*bytes, i * #MAP_NodeSize, *node\OriginX)
      Put16(*bytes, i * #MAP_NodeSize + 2, *node\OriginY)
      Put16(*bytes, i * #MAP_NodeSize + 4, *node\DX)
      Put16(*bytes, i * #MAP_NodeSize + 6, *node\DY)
      Put16(*bytes, i * #MAP_NodeSize + 8, *node\Box0Top)
      Put16(*bytes, i * #MAP_NodeSize + 10, *node\Box0Bottom)
      Put16(*bytes, i * #MAP_NodeSize + 12, *node\Box0Left)
      Put16(*bytes, i * #MAP_NodeSize + 14, *node\Box0Right)
      Put16(*bytes, i * #MAP_NodeSize + 16, *node\Box1Top)
      Put16(*bytes, i * #MAP_NodeSize + 18, *node\Box1Bottom)
      Put16(*bytes, i * #MAP_NodeSize + 20, *node\Box1Left)
      Put16(*bytes, i * #MAP_NodeSize + 22, *node\Box1Right)
      Put16(*bytes, i * #MAP_NodeSize + 24, *node\Child0)
      Put16(*bytes, i * #MAP_NodeSize + 26, *node\Child1)
      *node = *node + SizeOf(TestNodeSpec)
    Next
    WadAdd("NODES", *bytes, Int(NodeCount) * #MAP_NodeSize)
    FreeMemory(*bytes)
  Else
    WadAdd("NODES", 0, 0)
  EndIf

  *bytes = NewZero(Int(SectorCount) * #MAP_SectorSize)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  *sector = *Sectors
  For i = 0 To SectorCount - 1
    Put16(*bytes, i * #MAP_SectorSize, *sector\FloorHeight)
    Put16(*bytes, i * #MAP_SectorSize + 2, *sector\CeilingHeight)
    PutName8(*bytes, i * #MAP_SectorSize + 4, *sector\FloorName)
    PutName8(*bytes, i * #MAP_SectorSize + 12, *sector\CeilingName)
    Put16(*bytes, i * #MAP_SectorSize + 20, *sector\LightLevel)
    Put16(*bytes, i * #MAP_SectorSize + 22, 0)
    Put16(*bytes, i * #MAP_SectorSize + 24, 0)
    *sector = *sector + SizeOf(TestSectorSpec)
  Next
  WadAdd("SECTORS", *bytes, Int(SectorCount) * #MAP_SectorSize)
  FreeMemory(*bytes)

  rejectBytes = Int(SectorCount) * Int(SectorCount) + 7
  rejectBytes = rejectBytes >> 3
  If rejectBytes <= 0
    rejectBytes = 1
  EndIf
  *bytes = NewZero(rejectBytes)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  WadAdd("REJECT", *bytes, rejectBytes)
  FreeMemory(*bytes)

  blockmapBytes = Int(LineCount) * 2 + 14
  *bytes = NewZero(blockmapBytes)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
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
  WadAdd("BLOCKMAP", *bytes, blockmapBytes)
  FreeMemory(*bytes)

  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Streamed synthetic visibility map variants
; ---------------------------------------------------------------------------

; Two-leaf one-node tree with a broad horizontal wall repeated for both leaves.
; PassMode=0: both lines are one-sided SOLID walls. PassMode=1: both are
; two-sided open-floor-height PASS walls. Camera (-1,0) heading ANG90 and the
; common bbox {Top=200,Bottom=50,Left=-100,Right=100} => boxpos 9.
Procedure.i StreamTwoLeafBroadMap(Marker.s, PassMode.i)
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
  If PassMode <> 0
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

  If PassMode <> 0
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
    subs(i)\FirstSeg = i
    subs(i)\NumSegs = 1
  Next
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

  If PassMode <> 0
    ProcedureReturn WadAddMapGroup(Marker, @sectors(0), 2, @lines(0), 2,
                                   @sides(0), 4, @vertices(0), 2,
                                   @segs(0), 2, @subs(0), 2, @nodes(0), 1)
  EndIf
  ProcedureReturn WadAddMapGroup(Marker, @sectors(0), 1, @lines(0), 2,
                                 @sides(0), 2, @vertices(0), 2,
                                 @segs(0), 2, @subs(0), 2, @nodes(0), 1)
EndProcedure

; Two-leaf one-node tree with a vertical mid-height wall at x=100 repeated for
; both leaves, all one-sided. Camera 0,0 heading ANG0 sees the south-to-north
; front-face candidate [58,262]. Used by I03's distinct map B.
Procedure.i StreamTwoLeafVerticalMap(Marker.s)
  Protected Dim sectors.TestSectorSpec(0)
  Protected Dim lines.TestLineSpec(1)
  Protected Dim sides.TestSideSpec(1)
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
  vertices(0)\X = 100
  vertices(0)\Y = 64
  vertices(1)\X = 100
  vertices(1)\Y = -64

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
    segs(i)\V1 = 0
    segs(i)\V2 = 1
    segs(i)\Line = i
    segs(i)\Side = 0
    subs(i)\FirstSeg = i
    subs(i)\NumSegs = 1
  Next
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

  ProcedureReturn WadAddMapGroup(Marker, @sectors(0), 1, @lines(0), 2,
                                 @sides(0), 2, @vertices(0), 2,
                                 @segs(0), 2, @subs(0), 2, @nodes(0), 1)
EndProcedure

; Four-leaf/three-node nested tree with the broad horizontal wall repeated for
; every leaf. PassMode=0: four one-sided SOLID walls. PassMode=1: four two-sided
; open-floor-height PASS walls. Node2 root children node0/node1; node0 leaves
; 0/1; node1 leaves 2/3. Camera (-1,0) heading ANG90 yields public leaf order
; 3,2,1,0 in both cull-free and online walks.
Procedure.i StreamQuadMap(Marker.s, PassMode.i)
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
  If PassMode <> 0
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

  If PassMode <> 0
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

  If PassMode <> 0
    ProcedureReturn WadAddMapGroup(Marker, @sectors(0), 2, @lines(0), 4,
                                   @sides(0), 8, @vertices(0), 2,
                                   @segs(0), 4, @subs(0), 4, @nodes(0), 3)
  EndIf
  ProcedureReturn WadAddMapGroup(Marker, @sectors(0), 1, @lines(0), 4,
                                 @sides(0), 4, @vertices(0), 2,
                                 @segs(0), 4, @subs(0), 4, @nodes(0), 3)
EndProcedure

; ---------------------------------------------------------------------------
; Explicit independent expected fingerprints
; ---------------------------------------------------------------------------

; FNV over the published M3-04 WallSpan numeric fields in chronological order.
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

; Exact expected cull-free BspTrace hash for a four-leaf quad tree. Independent
; field tuples from the original R_Subsector event order and synthetic links:
; subsector event kind 0 (sub, -1, sector0, -1,-1,-1,-1); seg event kind 1
; (sub, leaf=seg, sector0, line=leaf, side0, front0, back -1 or 1).
Procedure.q TestExpectedQuadTraceHash(PassMode.i)
  Protected hash.q = #TEST_FNV_Offset
  Protected Dim leafOrder.l(3)
  Protected i.i
  Protected leaf.l
  Protected back.l
  Protected kind.l

  leafOrder(0) = 3
  leafOrder(1) = 2
  leafOrder(2) = 1
  leafOrder(3) = 0
  If PassMode <> 0
    back = 1
  Else
    back = -1
  EndIf
  For i = 0 To 3
    leaf = leafOrder(i)
    ; subsector event
    hash = FnvAddLong(hash, #BSP_EventSubsector)
    hash = FnvAddLong(hash, leaf)
    hash = FnvAddLong(hash, -1)
    hash = FnvAddLong(hash, 0)
    hash = FnvAddLong(hash, -1)
    hash = FnvAddLong(hash, -1)
    hash = FnvAddLong(hash, -1)
    hash = FnvAddLong(hash, -1)
    ; seg event
    hash = FnvAddLong(hash, #BSP_EventSeg)
    hash = FnvAddLong(hash, leaf)
    hash = FnvAddLong(hash, leaf)
    hash = FnvAddLong(hash, 0)
    hash = FnvAddLong(hash, leaf)
    hash = FnvAddLong(hash, 0)
    hash = FnvAddLong(hash, 0)
    hash = FnvAddLong(hash, back)
  Next
  ProcedureReturn hash
EndProcedure

; Exact expected cull-free BspTrace hash for the two-leaf one-node broad-level
; tree. Public order on camera side 1 is leaf1 then far leaf0; both synthetic
; segs are line N/side0/front0 and share back=-1. FNV fields include each
; subsector event then its seg event.
Procedure.q TestExpectedTwoLeafTraceHash()
  Protected hash.q = #TEST_FNV_Offset
  Protected leaf.l

  leaf = 1
  hash = FnvAddLong(hash, #BSP_EventSubsector)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, #BSP_EventSeg)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, -1)
  leaf = 0
  hash = FnvAddLong(hash, #BSP_EventSubsector)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, #BSP_EventSeg)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, leaf)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, -1)
  ProcedureReturn hash
EndProcedure

; Exact expected online-visibility fingerprint for the four-leaf SOLID variant:
; near leaf3's one-sided broad wall publishes one [0,319] SOLID fragment tied to
; sub3/seg3/line3/side0/front0/back-1. A clipped left fencepost yields inclusive
; column1 and the right clipped angle yields inclusive 319.
Procedure.q TestExpectedQuadSolidVisibilityHash()
  Protected hash.q = #TEST_FNV_Offset

  hash = FnvAddLong(hash, 3)
  hash = FnvAddLong(hash, 3)
  hash = FnvAddLong(hash, 3)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, 319)
  hash = FnvAddLong(hash, #WALL_KIND_SOLID)
  ProcedureReturn hash
EndProcedure

; Exact expected online-visibility fingerprint for the four-leaf SOLID variant
; under heading ANG180. The broad horizontal wall's unsigned 32-bit left
; addition wraps (tspan becomes small), so the left branch does not adjust while
; the right branch still clamps; the source-faithful candidate is inclusive
; [177,319], one SOLID fragment tied to leaf3/line3. This expected tuple is
; independent of the implementation and documents the wrapped left-tie quirk.
Procedure.q TestExpectedQuadHeading180VisibilityHash()
  Protected hash.q = #TEST_FNV_Offset

  hash = FnvAddLong(hash, 3)
  hash = FnvAddLong(hash, 3)
  hash = FnvAddLong(hash, 3)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, 177)
  hash = FnvAddLong(hash, 319)
  hash = FnvAddLong(hash, #WALL_KIND_SOLID)
  ProcedureReturn hash
EndProcedure

; Exact expected online-visibility fingerprint for the four-leaf PASS variant:
; every broad open floor-height wall emits one PASS fragment, in order 3,2,1,0,
; each inclusive [0,319] with sub=N/seg=N/line=N/side0/front0/back1.
Procedure.q TestExpectedQuadPassVisibilityHash()
  Protected hash.q = #TEST_FNV_Offset
  Protected Dim leafOrder.l(3)
  Protected i.i
  Protected leaf.l

  leafOrder(0) = 3
  leafOrder(1) = 2
  leafOrder(2) = 1
  leafOrder(3) = 0
  For i = 0 To 3
    leaf = leafOrder(i)
    hash = FnvAddLong(hash, leaf)
    hash = FnvAddLong(hash, leaf)
    hash = FnvAddLong(hash, leaf)
    hash = FnvAddLong(hash, 0)
    hash = FnvAddLong(hash, 0)
    hash = FnvAddLong(hash, 1)
    hash = FnvAddLong(hash, 0)
    hash = FnvAddLong(hash, 319)
    hash = FnvAddLong(hash, #WALL_KIND_PASS)
  Next
  ProcedureReturn hash
EndProcedure

; Exact expected online-visibility fingerprint for I01's two-leaf SOLID broad
; tree: near leaf1 occludes far leaf0, one SOLID [1,319] sub1/seg1/line1.
Procedure.q TestExpectedTwoLeafSolidVisibilityHash()
  Protected hash.q = #TEST_FNV_Offset

  hash = FnvAddLong(hash, 1)
  hash = FnvAddLong(hash, 1)
  hash = FnvAddLong(hash, 1)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, -1)
  hash = FnvAddLong(hash, 0)
  hash = FnvAddLong(hash, 319)
  hash = FnvAddLong(hash, #WALL_KIND_SOLID)
  ProcedureReturn hash
EndProcedure

; FNV over the cull-free BspTrace numeric event fields in published order.
Procedure.q TestTraceHash(*Trace.BspTrace, *EventCount.Long)
  Protected hash.q = #TEST_FNV_Offset
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
    ProcedureReturn hash
  EndIf
  *EventCount\l = count
  For i = 0 To count - 1
    kind = 0
    subsector = 0
    seg = 0
    sector = 0
    linedef = 0
    side = 0
    front = 0
    back = 0
    If BspTraceGet(*Trace, i, @kind, @subsector, @seg, @sector,
                   @linedef, @side, @front, @back) = #False
      *EventCount\l = -1
      ProcedureReturn hash
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

; ---------------------------------------------------------------------------
; I01 - full synthetic WAD -> validated level -> cull-free trace + visible walk
; ---------------------------------------------------------------------------

Procedure TestI01()
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected projection.Projection
  Protected trace.BspTrace
  Protected result.WallVisibilityResult
  Protected hash.q = -1
  Protected expectedHash.q = -1
  Protected traceHash.q = -1
  Protected expectedTraceHash.q = -1
  Protected traceCount.l = -1
  Protected expectedCount.l = -1
  Protected firstSub.l = -1
  Protected secondSub.l = -1
  Protected kind.l = -1
  Protected owner.l = -1
  Protected segment.l = -1
  Protected sector.l = -1
  Protected linedef.l = -1
  Protected side.l = -1
  Protected front.l = -1
  Protected back.l = -999
  Protected spanSub.l = 0
  Protected spanSeg.l = 0
  Protected spanLine.l = 0
  Protected spanSide.l = 0
  Protected spanFront.l = 0
  Protected spanBack.l = -999
  Protected spanFirst.l = 0
  Protected spanLast.l = 0
  Protected spanKind.l = -1

  BeginCase("I01", "Fresh synthetic WAD -> map/camera/projection -> full online visible walk")

  Check(Bool(PrepareFixtureDirectory() <> 0), "ignored synthetic fixture directory ready")
  Check(Bool(WadBegin("m3-wall-i01.wad") <> 0), "streamed PWAD header begins")
  Check(Bool(StreamTwoLeafBroadMap("E1M1", 0) <> 0), "one synthetic ten-lump two-leaf SOLID map group streamed")
  Check(Bool(WadFinish() <> 0), "directory/header finalized for the synthetic WAD")
  Check(Bool(WADOpen(FixturePath("m3-wall-i01.wad")) <> 0), "synthetic PWAD opens through the real WAD API")
  Check(Bool(MapLevelLoad("E1M1", @level) <> 0), "validated MapLevel loads through M2 MapLoader")
  Check(Bool(level\Name = "E1M1" And level\BspRootIndex = 0 And MapLevelIsReady(@level) <> 0),
        "loaded level identity/root and readiness are canonical")
  Check(Bool(level\Nodes\Count = 1 And level\Subsectors\Count = 2 And level\Segs\Count = 2),
        "the loaded map owns one node, two subsectors and two synthetic segs")

  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0),
        "fixed camera -1,0 heading ANG90 is created through checked map units")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0),
        "pre-existing cull-free BspTraceBuild remains available and succeeds")
  traceCount = BspTraceCount(@trace)
  Check(Bool(traceCount = 4), "two leaves/two segs produce four chronological trace events")
  Check(Bool(TestSubOrder(@trace, 0, @firstSub) <> 0 And firstSub = 1),
        "full trace starts with the camera-near leaf1")
  Check(Bool(TestSubOrder(@trace, 2, @secondSub) <> 0 And secondSub = 0),
        "full trace later processes far leaf0 without visibility culling")
  Check(Bool(trace\VisitedNodes = 1 And trace\VisitedSubsectors = 2 And
             trace\EmittedSegs = 2 And trace\OcclusionSkips = 0),
        "old trace counters cover both leaves and retain zero occlusion skips")
  traceHash = TestTraceHash(@trace, @expectedCount)
  expectedTraceHash = TestExpectedTwoLeafTraceHash()
  Check(Bool(expectedCount = 4 And traceHash = expectedTraceHash),
        "cull-free trace fingerprint equals the explicit independent event tuple")

  kind = -1
  owner = -1
  segment = -1
  sector = -1
  linedef = -1
  side = -1
  front = -1
  back = -999
  Check(Bool(BspTraceGet(@trace, 1, @kind, @owner, @segment, @sector,
                         @linedef, @side, @front, @back) <> 0),
        "first seg trace event fields are readable")
  Check(Bool(kind = #BSP_EventSeg And owner = 1 And segment = 1 And sector = 0 And
             linedef = 1 And side = 0 And front = 0 And back = -1),
        "leaf1 seg1 trace event links line1/side0/front0/one-sided back -1")

  Check(Bool(ProjectionInitClassic(@projection) <> 0), "immutable classic 320-column projection initialized")
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @result) <> 0),
        "M3-04 online near-to-far visible walk succeeds")
  Check(Bool(WallVisibilityCount(@result) = 1), "near SOLID leaf1 occludes far leaf0 -> exactly one span")
  Check(Bool(result\VisitedNodes = 1 And result\VisitedSubsectors = 1 And
             result\ProcessedSegs = 1 And result\EmittedFragments = 1),
        "online visibility processes only the covering near leaf, never far leaf0")
  Check(Bool(result\SolidCandidates = 1 And result\PassCandidates = 0 And
             result\BackfaceRejects = 0 And result\FovLeftRejects = 0 And
             result\FovRightRejects = 0),
        "one-sided broad front-face wall classifies SOLID without angular rejects")
  Check(Bool(result\BboxTests = 1 And result\BboxOccluded = 1 And
             result\BboxVisible = 0 And result\BboxUnknown = 0 And
             result\OcclusionSkips = 1),
        "the far bbox is evaluated once, after near coverage, and pruned")

  Check(Bool(WallVisibilityGetSpan(@result, 0, @spanSub, @spanSeg, @spanLine,
                                   @spanSide, @spanFront, @spanBack,
                                   @spanFirst, @spanLast, @spanKind) <> 0),
        "owned published span fields are readable")
  Check(Bool(spanSub = 1 And spanSeg = 1 And spanLine = 1 And spanSide = 0 And
             spanFront = 0 And spanBack = -1 And spanFirst = 0 And spanLast = 319 And
             spanKind = #WALL_KIND_SOLID),
        "span is SOLID, source-identifiable and inclusive [0,319] = clipped fenceposts")
  hash = TestWallResultHash(@result)
  expectedHash = TestExpectedTwoLeafSolidVisibilityHash()
  Check(Bool(hash <> -1 And hash = expectedHash),
        "visible-walk fingerprint equals the explicit independent span tuple")

  WADClose()
  Check(Bool(WADIsOpen() = #False), "synthetic WAD closes through the real API")
  Check(Bool(WallVisibilityCount(@result) = 1 And TestWallResultHash(@result) = expectedHash),
        "owned result A remains identical/readable after WADClose")
  Check(Bool(MapLevelReset(@level) <> 0 And MapLevelIsReady(@level) = 0),
        "source MapLevel reset succeeds independently of the result")
  Check(Bool(WallVisibilityCount(@result) = 1 And TestWallResultHash(@result) = expectedHash),
        "owned numeric result survives source-level reset unchanged")

  BspTraceReset(@trace)
  ProjectionReset(@projection)
  WallVisibilityReset(@result)
  DeleteFile(FixturePath("m3-wall-i01.wad"))
  Check(Bool(CleanupFixtureDirectory() <> 0), "temporary synthetic fixture directory removed")
EndProcedure

; ---------------------------------------------------------------------------
; I02 - occlusion chronology against unchanged cull-free BspTrace
; ---------------------------------------------------------------------------

Procedure TestI02()
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected projection.Projection
  Protected traceA.BspTrace
  Protected traceB.BspTrace
  Protected resultA.WallVisibilityResult
  Protected resultB.WallVisibilityResult
  Protected traceHashA.q = -1
  Protected traceHashB.q = -1
  Protected expectedTraceA.q = -1
  Protected expectedTraceB.q = -1
  Protected visHashA.q = -1
  Protected visHashB.q = -1
  Protected expectedVisA.q = -1
  Protected expectedVisB.q = -1
  Protected traceCountA.l = -1
  Protected traceCountB.l = -1
  Protected expectedCount.l = -1
  Protected order0.l = -1
  Protected order1.l = -1
  Protected order2.l = -1
  Protected order3.l = -1
  Protected spanSub0.l = 0
  Protected spanSub1.l = 0
  Protected spanSub2.l = 0
  Protected spanSub3.l = 0
  Protected spanFirst0.l = 0
  Protected spanFirst1.l = 0
  Protected spanFirst2.l = 0
  Protected spanFirst3.l = 0
  Protected spanLast0.l = 0
  Protected spanLast1.l = 0
  Protected spanLast2.l = 0
  Protected spanLast3.l = 0
  Protected spanKind0.l = -1
  Protected spanKind1.l = -1
  Protected spanKind2.l = -1
  Protected spanKind3.l = -1

  BeginCase("I02", "Online occlusion chronology with unchanged cull-free BspTrace and PASS control")

  Check(Bool(PrepareFixtureDirectory() <> 0), "fixture directory ready")
  Check(Bool(WadBegin("m3-wall-i02.wad") <> 0), "streamed PWAD header begins")
  Check(Bool(StreamQuadMap("E1M1", 0) <> 0), "nested four-leaf SOLID map A streamed")
  Check(Bool(StreamQuadMap("E1M2", 1) <> 0), "nested four-leaf PASS control map B streamed")
  Check(Bool(WadFinish() <> 0), "directory finalized after both synthetic map groups")
  Check(Bool(WADOpen(FixturePath("m3-wall-i02.wad")) <> 0), "two-map synthetic PWAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) <> 0), "nested SOLID map A loads/validates")
  Check(Bool(level\Nodes\Count = 3 And level\Subsectors\Count = 4 And level\Segs\Count = 4),
        "map A owns exactly three nodes/four leaves/four segs")

  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0),
        "map A deterministic camera -1,0 heading ANG90")
  Check(Bool(ProjectionInitClassic(@projection) <> 0), "map A immutable classic projection initialized")

  ; (a) unchanged M3-03 cull-free trace: both far branches retain full geometry.
  Check(Bool(BspTraceBuild(@level, @camera, @traceA) <> 0), "map A cull-free trace succeeds")
  traceCountA = BspTraceCount(@traceA)
  Check(Bool(traceCountA = 8), "map A cull-free trace retains all eight leaf/seg events")
  Check(Bool(TestSubOrder(@traceA, 0, @order0) <> 0 And order0 = 3 And
             TestSubOrder(@traceA, 2, @order1) <> 0 And order1 = 2 And
             TestSubOrder(@traceA, 4, @order2) <> 0 And order2 = 1 And
             TestSubOrder(@traceA, 6, @order3) <> 0 And order3 = 0),
        "cull-free public leaf order remains near-to-far 3,2,1,0")
  Check(Bool(traceA\VisitedNodes = 3 And traceA\VisitedSubsectors = 4 And
             traceA\EmittedSegs = 4 And traceA\OcclusionSkips = 0),
        "map A trace counters visit every node/leaf with no visibility pruning")
  traceHashA = TestTraceHash(@traceA, @expectedCount)
  expectedTraceA = TestExpectedQuadTraceHash(0)
  Check(Bool(expectedCount = 8 And traceHashA = expectedTraceA),
        "map A trace fingerprint equals the explicit prior-style cull-free tuple")

  ; (b) online visibility uses live solidsegs and really prunes far boxes.
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultA) <> 0),
        "map A online visibility walk succeeds")
  Check(Bool(WallVisibilityCount(@resultA) = 1 And
             resultA\VisitedNodes = 2 And resultA\VisitedSubsectors = 1 And
             resultA\ProcessedSegs = 1 And resultA\SolidCandidates = 1),
        "near leaf3 coverage limits the online walk to root/node1/leaf3")
  Check(Bool(resultA\BboxTests = 2 And resultA\BboxOccluded = 2 And
             resultA\BboxVisible = 0 And resultA\OcclusionSkips = 2),
        "two far bbox tests run after leaf3 coverage and prune both branches")
  Check(Bool(resultA\VisitedSubsectors < traceA\VisitedSubsectors And
             resultA\OcclusionSkips > traceA\OcclusionSkips),
        "positive OcclusionSkips distinguishes live culling from the cull-free trace")
  visHashA = TestWallResultHash(@resultA)
  expectedVisA = TestExpectedQuadSolidVisibilityHash()
  Check(Bool(visHashA <> -1 And visHashA = expectedVisA),
        "map A occlusion span fingerprint equals the explicit independent tuple")

  ; (c) no-occlusion PASS control on the same nested tree / camera direction.
  Check(Bool(MapLevelReset(@level) <> 0), "map A reset before loading the control")
  Check(Bool(MapLevelLoad("E1M2", @level) <> 0), "nested PASS map B loads/validates")
  Check(Bool(level\Name = "E1M2" And level\BspRootIndex = 2),
        "control map B identity/root are distinct from A")
  Check(Bool(BspTraceBuild(@level, @camera, @traceB) <> 0), "control map B cull-free trace succeeds")
  traceCountB = BspTraceCount(@traceB)
  Check(Bool(traceCountB = 8), "control trace still has eight events")
  Check(Bool(TestSubOrder(@traceB, 0, @order0) <> 0 And order0 = 3 And
             TestSubOrder(@traceB, 6, @order3) <> 0 And order3 = 0),
        "control trace retains the identical near-to-far 3..0 order")
  traceHashB = TestTraceHash(@traceB, @expectedCount)
  expectedTraceB = TestExpectedQuadTraceHash(1)
  Check(Bool(traceHashB = expectedTraceB And traceHashB <> traceHashA),
        "control cull-free fingerprint equals its explicit PASS tuple and differs from A")
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultB) <> 0),
        "control online PASS walk succeeds")
  Check(Bool(WallVisibilityCount(@resultB) = 4 And
             resultB\VisitedNodes = 3 And resultB\VisitedSubsectors = 4 And
             resultB\ProcessedSegs = 4 And resultB\PassCandidates = 4),
        "PASS walls update no occlusion; all nodes/four leaves emit four fragments")
  Check(Bool(resultB\BboxTests = 3 And resultB\BboxVisible = 3 And
             resultB\BboxOccluded = 0 And resultB\BboxUnknown = 0 And
             resultB\OcclusionSkips = 0),
        "each far bbox remains VISIBLE and no far branch is pruned")
  Check(Bool(WallVisibilityGetSpan(@resultB, 0, @spanSub0, 0, 0, 0, 0, 0,
                                   @spanFirst0, @spanLast0, @spanKind0) <> 0 And
             WallVisibilityGetSpan(@resultB, 1, @spanSub1, 0, 0, 0, 0, 0,
                                   @spanFirst1, @spanLast1, @spanKind1) <> 0 And
             WallVisibilityGetSpan(@resultB, 2, @spanSub2, 0, 0, 0, 0, 0,
                                   @spanFirst2, @spanLast2, @spanKind2) <> 0 And
             WallVisibilityGetSpan(@resultB, 3, @spanSub3, 0, 0, 0, 0, 0,
                                   @spanFirst3, @spanLast3, @spanKind3) <> 0 And
             spanSub0 = 3 And spanSub1 = 2 And spanSub2 = 1 And spanSub3 = 0 And
             spanKind0 = #WALL_KIND_PASS And spanKind1 = #WALL_KIND_PASS And
             spanKind2 = #WALL_KIND_PASS And spanKind3 = #WALL_KIND_PASS And
             spanFirst0 = 0 And spanLast0 = 319 And
             spanFirst1 = 0 And spanLast1 = 319 And
             spanFirst2 = 0 And spanLast2 = 319 And
             spanFirst3 = 0 And spanLast3 = 319),
        "control publishes four ordered PASS fragments [0,319] in 3,2,1,0 order")
  visHashB = TestWallResultHash(@resultB)
  expectedVisB = TestExpectedQuadPassVisibilityHash()
  Check(Bool(visHashB <> -1 And visHashB = expectedVisB And visHashB <> visHashA),
        "control PASS visible-walk fingerprint equals its explicit independent tuple")

  WADClose()
  Check(Bool(WADIsOpen() = #False), "synthetic WAD closes")
  Check(Bool(WallVisibilityCount(@resultA) = 1 And TestWallResultHash(@resultA) = expectedVisA),
        "owned SOLID result survives WADClose unchanged")
  Check(Bool(TestTraceHash(@traceA, @expectedCount) = expectedTraceA And expectedCount = 8),
        "old cull-free trace A remains valid/identical across WADClose")
  Check(Bool(TestTraceHash(@traceB, @expectedCount) = expectedTraceB And expectedCount = 8),
        "old cull-free trace B remains valid/identical across WADClose")

  MapLevelReset(@level)
  BspTraceReset(@traceA)
  BspTraceReset(@traceB)
  ProjectionReset(@projection)
  WallVisibilityReset(@resultA)
  WallVisibilityReset(@resultB)
  DeleteFile(FixturePath("m3-wall-i02.wad"))
  Check(Bool(CleanupFixtureDirectory() <> 0), "fixture directory cleaned")
EndProcedure

; ---------------------------------------------------------------------------
; I03 - A -> B -> A lifetime, direction change, failure and recovery
; ---------------------------------------------------------------------------

Procedure TestI03()
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected projection.Projection
  Protected resultA.WallVisibilityResult
  Protected resultDir.WallVisibilityResult
  Protected resultRepeat.WallVisibilityResult
  Protected resultB.WallVisibilityResult
  Protected resultReloadA.WallVisibilityResult
  Protected resultRecover.WallVisibilityResult
  Protected *node.MapNode
  Protected hashA.q = -1
  Protected hashDir.q = -1
  Protected hashRepeat.q = -1
  Protected hashB.q = -1
  Protected hashReloadA.q = -1
  Protected hashRecovered.q = -1
  Protected expectedA.q = -1
  Protected expectedDir.q = -1
  Protected dirCamX.l = 0
  Protected dirCamY.l = 0
  Protected dirHeading.q = 0
  Protected countA.l = -1
  Protected countDir.l = -1
  Protected countRepeat.l = -1
  Protected countB.l = -1
  Protected countReloadA.l = -1
  Protected countRecovered.l = -1
  Protected spanSub.l = 0
  Protected spanSeg.l = 0
  Protected spanLine.l = 0
  Protected spanSide.l = 0
  Protected spanFront.l = 0
  Protected spanBack.l = -999
  Protected spanFirst.l = 0
  Protected spanLast.l = 0
  Protected spanKind.l = -1
  Protected errorBefore.s = ""

  BeginCase("I03", "A -> B -> A WAD lifecycle, direction change, repeated rebuild and corrupt-edge recovery")

  Check(Bool(PrepareFixtureDirectory() <> 0), "fixture directory ready")
  Check(Bool(WadBegin("m3-wall-i03.wad") <> 0), "lifetime PWAD header begins")
  Check(Bool(StreamQuadMap("E1M1", 0) <> 0), "map A nested SOLID quad group streamed")
  Check(Bool(StreamTwoLeafVerticalMap("E1M2") <> 0), "distinct map B vertical two-leaf group streamed")
  Check(Bool(WadFinish() <> 0), "lifetime PWAD directory finalized")
  Check(Bool(WADOpen(FixturePath("m3-wall-i03.wad")) <> 0), "lifetime PWAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) <> 0), "map A loads/validates")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "map A camera heading north created")
  Check(Bool(ProjectionInitClassic(@projection) <> 0), "immutable projection initialized once/reused")

  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultA) <> 0),
        "map A first visible walk succeeds")
  countA = WallVisibilityCount(@resultA)
  hashA = TestWallResultHash(@resultA)
  expectedA = TestExpectedQuadSolidVisibilityHash()
  Check(Bool(countA = 1 And hashA = expectedA And resultA\OcclusionSkips = 2),
        "map A first build reproduces the explicit SOLID occlusion fingerprint")

  ; Direction change: heading ANG180 makes every broad front-face wall hit the
  ; left FOV branch; the walk stays valid/empty and therefore has a distinct hash.
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG180) <> 0),
        "same camera position switches to heading ANG180")
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultDir) <> 0),
        "reversed-heading walk still completes transactionally")
  countDir = WallVisibilityCount(@resultDir)
  hashDir = TestWallResultHash(@resultDir)
  expectedDir = TestExpectedQuadHeading180VisibilityHash()
  dirCamX = 0 : dirCamY = 0 : dirHeading = 0
  BspCameraGet(@camera, @dirCamX, @dirCamY, @dirHeading)
  if countDir > 0
    WallVisibilityGetSpan(@resultDir, 0, @spanSub,0,0,0,0,0,@spanFirst,@spanLast,@spanKind)
  endif
  Check(Bool(countDir = 1 And hashDir = expectedDir And
             resultDir\FovLeftRejects = 0 And resultDir\SolidCandidates = 1 And
             resultDir\VisitedSubsectors = 1 And dirHeading = #BAM_ANG180),
        "heading direction changes the visible source-wrapped [177,319] SOLID fingerprint")
  Check(Bool(spanSub = 3 And spanFirst = 177 And spanLast = 319 And
             spanKind = #WALL_KIND_SOLID),
        "ANG180 unsigned left-addition wrap retains the exact [177,319] interval")
  Check(Bool(hashDir <> hashA), "directional visible fingerprint differs from map A forward hash")
  Check(Bool(WallVisibilityReset(@resultDir) <> 0 And WallVisibilityIsValid(@resultDir) <> 0 And
             WallVisibilityCount(@resultDir) = 0),
        "resultDir Reset is idempotent and leaves a reusable empty result")

  ; Restore direction; explicit Reset then rebuild proves duplicate determinism.
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0),
        "heading restored to north for deterministic rebuild")
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultRepeat) <> 0),
        "map A duplicate build succeeds")
  countRepeat = WallVisibilityCount(@resultRepeat)
  hashRepeat = TestWallResultHash(@resultRepeat)
  Check(Bool(countRepeat = countA And hashRepeat = hashA),
        "repeated map A build is bit-for-bit deterministic in span identity/order")
  Check(Bool(WallVisibilityReset(@resultRepeat) <> 0 And
             WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultRepeat) <> 0 And
             TestWallResultHash(@resultRepeat) = hashA And WallVisibilityCount(@resultRepeat) = countA),
        "explicit Reset/Build again reproduces the same fingerprint")

  ; A -> B within one WAD session.
  Check(Bool(MapLevelReset(@level) <> 0), "map A reset before the distinct B load")
  Check(Bool(MapLevelLoad("E1M2", @level) <> 0), "map B loads/validates from the same WAD")
  Check(Bool(level\Name = "E1M2" And level\BspRootIndex = 0 And
             level\Segs\Count = 2 And level\Subsectors\Count = 2),
        "map B identity/root/records differ from map A")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, 0) <> 0), "map B camera 0,0 heading ANG0 created")
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultB) <> 0),
        "map B distinct visible walk succeeds")
  countB = WallVisibilityCount(@resultB)
  hashB = TestWallResultHash(@resultB)
  Check(Bool(countB >= 1 And hashB <> -1 And hashB <> hashA),
        "map B has a nonempty, distinct deterministic visible fingerprint")
  Check(Bool(WallVisibilityGetSpan(@resultB, 0, @spanSub, @spanSeg, @spanLine,
                                   @spanSide, @spanFront, @spanBack,
                                   @spanFirst, @spanLast, @spanKind) <> 0 And
             spanSub = 1 And spanSeg = 1 And spanLine = 1 And spanSide = 0 And
             spanFront = 0 And spanBack = -1 And spanFirst = 58 And spanLast = 262 And
             spanKind = #WALL_KIND_SOLID),
        "map B first span keeps source identity and the vertical [58,262] SOLID columns")

  ; B -> A reload.
  Check(Bool(MapLevelReset(@level) <> 0), "map B reset before A reload")
  Check(Bool(MapLevelLoad("E1M1", @level) <> 0), "map A reloads from the still-open lifetime WAD")
  Check(Bool(level\Name = "E1M1"), "reloaded level identity returns to map A")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "map A original camera restored")
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultReloadA) <> 0),
        "reloaded map A visible walk succeeds")
  countReloadA = WallVisibilityCount(@resultReloadA)
  hashReloadA = TestWallResultHash(@resultReloadA)
  Check(Bool(countReloadA = countA And hashReloadA = hashA),
        "A -> B -> A reload reproduces the original map A fingerprint exactly")

  ; Failure: corrupt the decoded root child edge after validation; Build must fail
  ; transactionally into a valid-empty result, then restoring the edge recovers.
  *node = level\Nodes\Items + 2 * SizeOf(MapNode)
  Check(Bool(*node <> 0), "decoded root node2 storage is mutable for the failure probe")
  *node\Child0 = #MAP_NF_SUBSECTOR ! 99
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultRecover) = 0),
        "corrupt root child makes the reloaded map A Build fail")
  errorBefore = WallVisibilityLastError()
  Check(Bool(errorBefore <> "" And FindString(errorBefore, "missing subsector") <> 0),
        "corrupt-edge failure carries an actionable missing-leaf diagnostic")
  countRecovered = WallVisibilityCount(@resultRecover)
  Check(Bool(WallVisibilityIsValid(@resultRecover) <> 0 And countRecovered = 0 And
             resultRecover\Spans = 0),
        "failed build leaves a valid empty owned result, never stale partial spans")
  Check(Bool(MapLevelIsReady(@level) <> 0 And ProjectionIsValid(@projection) <> 0),
        "failure leaves the map/projection owners intact for recovery")
  *node\Child0 = 0
  Check(Bool(WallVisibilityBuild(@level, @camera, @projection, 0, 0, @resultRecover) <> 0),
        "restored root edge allows recovery Build")
  hashRecovered = TestWallResultHash(@resultRecover)
  countRecovered = WallVisibilityCount(@resultRecover)
  Check(Bool(hashRecovered = hashA And countRecovered = countA),
        "failure/recovery rebuild reproduces the original A hash without stale pointers")

  ; Close the source; owned numeric results must survive both WADClose and reset.
  WADClose()
  Check(Bool(WADIsOpen() = #False), "lifetime WAD closes")
  Check(Bool(WallVisibilityCount(@resultA) = countA And TestWallResultHash(@resultA) = hashA),
        "result A released-source lifetime retains count/hash")
  Check(Bool(WallVisibilityCount(@resultRecover) = countRecovered And
             TestWallResultHash(@resultRecover) = hashA),
        "recovered result retains count/hash after WADClose")
  Check(Bool(MapLevelReset(@level) <> 0 And MapLevelIsReady(@level) = 0),
        "source level reset after WADClose succeeds")
  Check(Bool(WallVisibilityCount(@resultA) = countA And TestWallResultHash(@resultA) = hashA),
        "result A remains readable with identical numeric hash after level reset")

  WallVisibilityReset(@resultA)
  WallVisibilityReset(@resultDir)
  WallVisibilityReset(@resultRepeat)
  WallVisibilityReset(@resultB)
  WallVisibilityReset(@resultReloadA)
  WallVisibilityReset(@resultRecover)
  ProjectionReset(@projection)
  DeleteFile(FixturePath("m3-wall-i03.wad"))
  Check(Bool(CleanupFixtureDirectory() <> 0), "fixture directory cleaned")
EndProcedure

; ---------------------------------------------------------------------------
; Suite driver and measured summary
; ---------------------------------------------------------------------------

Procedure Main()
  TestI01()
  TestI02()
  TestI03()
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
