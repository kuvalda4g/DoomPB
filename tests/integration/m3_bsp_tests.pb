; -----------------------------------------------------------------------------
; DoomPB - M3-03 deterministic BSP traversal synthetic integration (I01-I03)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; I01: full synthetic WAD pipeline: streamed original map records -> WADOpen ->
;      MapLevelLoad -> fixed Camera -> full BSP trace with original order/links.
; I02: lifetime contract: owned level + owned trace across WADClose, MapLevelReset,
;      distinct map load, reload, repeated trace reset and failed-build cleanup.
; I03: edge/error integration: malformed node reference rejected by the real
;      loader, late geometry overflow and exponential-DAG budget failure leave
;      transactional empty traces with diagnostics and unchanged camera/level,
;      then valid recovery builds. No production validation is weakened.
;
; All fixtures are entirely original synthetic ten-lump PWAD maps. No commercial
; IWAD bytes, graphics, textures, coordinates or screenshots are stored, printed
; or committed. Optional owner-IWAD I04 lives in a separate harness. The
; application CLI and version remain untouched.
;
; Expected traces use hand-computed original R_PointOnSide ties and recursive
; near-then-far order. Canonical FNV-1a64 fingerprints cover published numeric
; event fields only. Exit code: 0 when every assertion passed, else failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
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

; Streamed synthetic WAD writer.
Global gWadFile.i = 0
Global gWadEntryCount.i = 0
Global Dim gWadName.s(255)
Global Dim gWadPosition.q(255)
Global Dim gWadSize.q(255)

Structure TestSubSpec
  FirstSeg.l
  NumSegs.l
EndStructure

Structure TestNodeSpec
  OriginX.l
  OriginY.l
  DX.l
  DY.l
  Child0.l
  Child1.l
EndStructure

Structure TestLumpRef
  Name.s
  Size.i
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

Procedure.i TestSubOrder(*Trace.BspTrace, EventIndex.i, *Subsector.Long)
  Protected kind.l = -1
  Protected temp.l = -1
  Protected ok.i

  ok = BspTraceGet(*Trace, EventIndex, @kind, *Subsector, @temp, @temp,
                   @temp, @temp, @temp, @temp)
  ProcedureReturn Bool(ok <> 0 And kind = #BSP_EventSubsector)
EndProcedure

; ---------------------------------------------------------------------------
; Fixture directory and streamed WAD writer
; ---------------------------------------------------------------------------

Procedure.s FixturePath(FileName.s)
  ProcedureReturn gFixtureDirectory + FileName
EndProcedure

Procedure.i PrepareFixtureDirectory()
  Protected directorySize.i

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "m3-bsp-test-tmp" + #FixtureSeparator
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
; Synthetic map record helpers (original ten-lump PWAD groups)
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

Procedure.i NewZero(Size.i)
  Protected memory.i = AllocateMemory(Size)

  If memory <> 0
    FillMemory(memory, Size, 0)
  EndIf
  ProcedureReturn memory
EndProcedure

; Adds one marker plus the canonical ten map lumps to the streamed WAD. All
; record buffers are synthetic, written once and freed immediately.
Procedure.i WaddMapGroup(Marker.s, *Subs.TestSubSpec, SubCount.i,
                        *Nodes.TestNodeSpec, NodeCount.i, SegCount.i)
  Protected i.i
  Protected v1.i
  Protected v2.i
  Protected *bytes.Byte

  If Marker = "" Or SubCount <= 0 Or NodeCount < 0 Or SegCount < 1 Or SegCount > 4
    ProcedureReturn #False
  EndIf
  WadAdd(Marker, 0, 0)

  WadAdd("THINGS", 0, 0)

  *bytes = NewZero(4 * 14)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To 3
    Put16(*bytes, i * 14, i)
    Put16(*bytes, i * 14 + 2, (i + 1) % 4)
    Put16(*bytes, i * 14 + 10, i)
    Put16(*bytes, i * 14 + 12, -1)
  Next
  WadAdd("LINEDEFS", *bytes, 4 * 14)
  FreeMemory(*bytes)

  *bytes = NewZero(4 * 30)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To 3
    PutName8(*bytes, i * 30 + 4, "WALL1")
    PutName8(*bytes, i * 30 + 12, "WALL1")
    PutName8(*bytes, i * 30 + 20, "WALL1")
    Put16(*bytes, i * 30 + 28, 0)
  Next
  WadAdd("SIDEDEFS", *bytes, 4 * 30)
  FreeMemory(*bytes)

  *bytes = NewZero(4 * 4)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  Put16(*bytes, 0, 0)
  Put16(*bytes, 2, 0)
  Put16(*bytes, 4, 64)
  Put16(*bytes, 6, 0)
  Put16(*bytes, 8, 64)
  Put16(*bytes, 10, 64)
  Put16(*bytes, 12, 0)
  Put16(*bytes, 14, 64)
  WadAdd("VERTEXES", *bytes, 4 * 4)
  FreeMemory(*bytes)

  *bytes = NewZero(SegCount * 12)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To SegCount - 1
    v1 = i % 4
    v2 = (i + 1) % 4
    Put16(*bytes, i * 12, v1)
    Put16(*bytes, i * 12 + 2, v2)
    Put16(*bytes, i * 12 + 4, 0)
    Put16(*bytes, i * 12 + 6, v1)
    Put16(*bytes, i * 12 + 8, 0)
    Put16(*bytes, i * 12 + 10, 0)
  Next
  WadAdd("SEGS", *bytes, SegCount * 12)
  FreeMemory(*bytes)

  *bytes = NewZero(SubCount * 4)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To SubCount - 1
    Put16(*bytes, i * 4, *Subs\NumSegs)
    Put16(*bytes, i * 4 + 2, *Subs\FirstSeg)
    *Subs = *Subs + SizeOf(TestSubSpec)
  Next
  *Subs = *Subs - SubCount * SizeOf(TestSubSpec)
  WadAdd("SSECTORS", *bytes, SubCount * 4)
  FreeMemory(*bytes)

  If NodeCount > 0
    *bytes = NewZero(NodeCount * 28)
    If *bytes = 0
      ProcedureReturn #False
    EndIf
    For i = 0 To NodeCount - 1
      Put16(*bytes, i * 28, *Nodes\OriginX)
      Put16(*bytes, i * 28 + 2, *Nodes\OriginY)
      Put16(*bytes, i * 28 + 4, *Nodes\DX)
      Put16(*bytes, i * 28 + 6, *Nodes\DY)
      Put16(*bytes, i * 28 + 24, *Nodes\Child0)
      Put16(*bytes, i * 28 + 26, *Nodes\Child1)
      *Nodes = *Nodes + SizeOf(TestNodeSpec)
    Next
    *Nodes = *Nodes - NodeCount * SizeOf(TestNodeSpec)
    WadAdd("NODES", *bytes, NodeCount * 28)
    FreeMemory(*bytes)
  Else
    WadAdd("NODES", 0, 0)
  EndIf

  *bytes = NewZero(26)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  PutName8(*bytes, 4, "FLOOR1")
  PutName8(*bytes, 12, "CEIL1")
  Put16(*bytes, 20, 160)
  WadAdd("SECTORS", *bytes, 26)
  FreeMemory(*bytes)

  *bytes = NewZero(1)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  WadAdd("REJECT", *bytes, 1)
  FreeMemory(*bytes)

  *bytes = NewZero(16)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  Put16(*bytes, 4, 1)
  Put16(*bytes, 6, 1)
  Put16(*bytes, 8, 5)
  Put16(*bytes, 10, 0)
  Put16(*bytes, 12, 0)
  Put16(*bytes, 14, $FFFF)
  WadAdd("BLOCKMAP", *bytes, 16)
  FreeMemory(*bytes)

  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Fixture setups shared by I01-I03
; ---------------------------------------------------------------------------

; Original nested three-node/four-leaf tree from the unit suite.
Procedure TestSetupNestedA(*Subs.TestSubSpec, *Nodes.TestNodeSpec)
  Protected i.i
  Protected *item.TestSubSpec
  Protected *nodeItem.TestNodeSpec

  For i = 0 To 3
    *item = *Subs + i * SizeOf(TestSubSpec)
    *item\FirstSeg = i
    *item\NumSegs = 1
  Next
  *nodeItem = *Nodes + 0 * SizeOf(TestNodeSpec)
  *nodeItem\OriginX = 0
  *nodeItem\OriginY = 0
  *nodeItem\DX = 0
  *nodeItem\DY = 1
  *nodeItem\Child0 = $8000 ! 0
  *nodeItem\Child1 = $8000 ! 1
  *nodeItem = *Nodes + 1 * SizeOf(TestNodeSpec)
  *nodeItem\OriginX = 0
  *nodeItem\OriginY = 0
  *nodeItem\DX = 0
  *nodeItem\DY = 1
  *nodeItem\Child0 = $8000 ! 2
  *nodeItem\Child1 = $8000 ! 3
  *nodeItem = *Nodes + 2 * SizeOf(TestNodeSpec)
  *nodeItem\OriginX = 0
  *nodeItem\OriginY = 0
  *nodeItem\DX = 0
  *nodeItem\DY = 1
  *nodeItem\Child0 = 0
  *nodeItem\Child1 = 1
EndProcedure

; Distinct two-leaf one-node tree for the same WAD used by lifetime I02.
Procedure TestSetupTwoLeafB(*Subs.TestSubSpec, *Nodes.TestNodeSpec)
  Protected i.i
  Protected *item.TestSubSpec
  Protected *nodeItem.TestNodeSpec

  For i = 0 To 1
    *item = *Subs + i * SizeOf(TestSubSpec)
    *item\FirstSeg = i
    *item\NumSegs = 1
  Next
  *nodeItem = *Nodes
  *nodeItem\OriginX = 0
  *nodeItem\OriginY = 0
  *nodeItem\DX = 0
  *nodeItem\DY = 1
  *nodeItem\Child0 = $8000 ! 0
  *nodeItem\Child1 = $8000 ! 1
EndProcedure

; 20-node cycle-free doubling DAG accepted by M2, then bounded by M3 budgets.
Procedure TestSetupDoublingDag(*Subs.TestSubSpec, *Nodes.TestNodeSpec)
  Protected i.i
  Protected *item.TestSubSpec
  Protected *nodeItem.TestNodeSpec

  *item = *Subs
  *item\FirstSeg = 0
  *item\NumSegs = 1
  For i = 0 To 19
    *nodeItem = *Nodes + i * SizeOf(TestNodeSpec)
    *nodeItem\OriginX = 0
    *nodeItem\OriginY = 0
    *nodeItem\DX = 0
    *nodeItem\DY = 1
    If i = 0
      *nodeItem\Child0 = $8000 ! 0
      *nodeItem\Child1 = $8000 ! 0
    Else
      *nodeItem\Child0 = i - 1
      *nodeItem\Child1 = i - 1
    EndIf
  Next
EndProcedure

; Extreme signed node origin used only for a late geometry-overflow test.
Procedure TestSetupExtremeOrigin(*Subs.TestSubSpec, *Nodes.TestNodeSpec)
  Protected *item.TestSubSpec
  Protected *nodeItem.TestNodeSpec

  *item = *Subs
  *item\FirstSeg = 0
  *item\NumSegs = 1
  *item = *Subs + 1 * SizeOf(TestSubSpec)
  *item\FirstSeg = 1
  *item\NumSegs = 1
  *nodeItem = *Nodes
  *nodeItem\OriginX = -32768
  *nodeItem\OriginY = 0
  *nodeItem\DX = 1
  *nodeItem\DY = 1
  *nodeItem\Child0 = $8000 ! 0
  *nodeItem\Child1 = $8000 ! 1
EndProcedure

; Malformed node reference: nonleaf child 5000 exceeds the one-node table.
Procedure TestSetupMalformedNode(*Subs.TestSubSpec, *Nodes.TestNodeSpec)
  Protected *item.TestSubSpec
  Protected *nodeItem.TestNodeSpec

  *item = *Subs
  *item\FirstSeg = 0
  *item\NumSegs = 1
  *nodeItem = *Nodes
  *nodeItem\OriginX = 0
  *nodeItem\OriginY = 0
  *nodeItem\DX = 0
  *nodeItem\DY = 1
  *nodeItem\Child0 = 5000
  *nodeItem\Child1 = $8000 ! 0
EndProcedure

Procedure.i BuildNestedWad(FileName.s)
  Protected Dim subs.TestSubSpec(3)
  Protected Dim nodes.TestNodeSpec(2)
  Protected ok.i

  TestSetupNestedA(@subs(0), @nodes(0))
  If WadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  ok = WaddMapGroup("E1M1", @subs(0), 4, @nodes(0), 3, 4)
  If ok = #False
    CloseFile(gWadFile)
    gWadFile = 0
    ProcedureReturn #False
  EndIf
  ProcedureReturn WadFinish()
EndProcedure

Procedure.i BuildLifetimeWad(FileName.s)
  Protected Dim subsA.TestSubSpec(3)
  Protected Dim nodesA.TestNodeSpec(2)
  Protected Dim subsB.TestSubSpec(1)
  Protected Dim nodesB.TestNodeSpec(0)
  Protected ok.i

  TestSetupNestedA(@subsA(0), @nodesA(0))
  TestSetupTwoLeafB(@subsB(0), @nodesB(0))
  If WadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  ok = WaddMapGroup("E1M1", @subsA(0), 4, @nodesA(0), 3, 4)
  If ok
    ok = WaddMapGroup("E1M2", @subsB(0), 2, @nodesB(0), 1, 2)
  EndIf
  If ok = #False
    CloseFile(gWadFile)
    gWadFile = 0
    ProcedureReturn #False
  EndIf
  ProcedureReturn WadFinish()
EndProcedure

Procedure.i BuildEdgeWad(FileName.s)
  Protected Dim subsMal.TestSubSpec(0)
  Protected Dim nodesMal.TestNodeSpec(0)
  Protected Dim subsA.TestSubSpec(3)
  Protected Dim nodesA.TestNodeSpec(2)
  Protected Dim subsB.TestSubSpec(0)
  Protected Dim nodesB.TestNodeSpec(19)
  Protected Dim subsX.TestSubSpec(1)
  Protected Dim nodesX.TestNodeSpec(0)
  Protected ok.i

  TestSetupMalformedNode(@subsMal(0), @nodesMal(0))
  TestSetupNestedA(@subsA(0), @nodesA(0))
  TestSetupDoublingDag(@subsB(0), @nodesB(0))
  TestSetupExtremeOrigin(@subsX(0), @nodesX(0))
  If WadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  ok = WaddMapGroup("E1M1", @subsMal(0), 1, @nodesMal(0), 1, 1)
  If ok
    ok = WaddMapGroup("E1M2", @subsA(0), 4, @nodesA(0), 3, 4)
  EndIf
  If ok
    ok = WaddMapGroup("E1M3", @subsB(0), 1, @nodesB(0), 20, 1)
  EndIf
  If ok
    ok = WaddMapGroup("E1M4", @subsX(0), 2, @nodesX(0), 1, 2)
  EndIf
  If ok = #False
    CloseFile(gWadFile)
    gWadFile = 0
    ProcedureReturn #False
  EndIf
  ProcedureReturn WadFinish()
EndProcedure

; ---------------------------------------------------------------------------
; I01 - full synthetic WAD -> validated level -> fixed camera -> trace
; ---------------------------------------------------------------------------

Procedure TestI01()
  BeginCase("I01", "Full synthetic WAD pipeline produces original near-to-far order")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected count.i
  Protected first.l = -1
  Protected second.l = -1
  Protected third.l = -1
  Protected fourth.l = -1
  Protected segment.l = -1
  Protected linedef.l = -1
  Protected side.l = -1
  Protected front.l = -1
  Protected back.l = -1
  Protected kind.l = -1
  Protected owner.l = -1

  Check(Bool(PrepareFixtureDirectory() <> 0), "irrelevant fixture directory prepared under ignored build tmp")
  Check(Bool(BuildNestedWad("m3-bsp-i01.wad") <> 0), "synthetic ten-lump PWAD streamed")
  Check(Bool(WADOpen(FixturePath("m3-bsp-i01.wad")) <> 0), "synthetic WAD opens through the real WAD API")
  Check(Bool(MapLevelLoad("E1M1", @level) <> 0), "validated MapLevel loads through the real M2 loader")
  Check(Bool(level\Name = "E1M1" And level\BspRootIndex = 2 And MapLevelIsReady(@level) <> 0),
        "loaded level is named E1M1 and root is last node 2")

  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "fixed camera created through checked map-unit API")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "deterministic BSP trace build succeeds")
  count = BspTraceCount(@trace)
  Check(Bool(count = 8), "four leaves and four segs produce eight chronological events")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 3), "camera A first subsector is leaf3")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 2), "second subsector leaf2")
  Check(Bool(TestSubOrder(@trace, 4, @third) <> 0 And third = 1), "third subsector leaf1")
  Check(Bool(TestSubOrder(@trace, 6, @fourth) <> 0 And fourth = 0), "fourth subsector leaf0")

  segment = -1
  linedef = -1
  side = -1
  front = -1
  back = -999
  kind = -1
  owner = -1
  Check(Bool(BspTraceGet(@trace, 1, @kind, @owner, @segment, 0, @linedef, @side, @front, @back) <> 0),
        "first seg event fields readable")
  Check(Bool(kind = #BSP_EventSeg And owner = 3 And segment = 3 And linedef = 3 And
        side = 0 And front = 0 And back = -1),
        "leaf3 follows with absolute seg3 links line3/side0/front0/back -1")
  Check(Bool(trace\VisitedNodes = 3 And trace\VisitedSubsectors = 4 And
        trace\EmittedSegs = 4 And trace\OcclusionSkips = 0),
        "trace counters record complete walk with zero occlusion skip")

  WADClose()
  MapLevelReset(@level)
  BspTraceReset(@trace)
  Check(Bool(WADIsOpen() = #False And MapLevelIsReady(@level) = 0), "WAD and level released cleanly")
  DeleteFile(FixturePath("m3-bsp-i01.wad"))
EndProcedure

; ---------------------------------------------------------------------------
; I02 - lifetime across WADClose/reset/reload and deterministic reload
; ---------------------------------------------------------------------------

Procedure TestI02()
  BeginCase("I02", "Owned trace/lifetime across WAD close, level reset, reload and cleanup")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected elemHash.q
  Protected replayHash.q
  Protected elemCount.l = -1
  Protected replayCount.l = -1
  Protected first.l = -1
  Protected second.l = -1
  Protected savedRoot.l
  Protected resetFirst.i
  Protected resetSecond.i

  Check(Bool(PrepareFixtureDirectory() <> 0), "fixture directory ready")
  Check(Bool(BuildLifetimeWad("m3-bsp-i02.wad") <> 0), "two-map synthetic PWAD streamed")
  Check(Bool(WADOpen(FixturePath("m3-bsp-i02.wad")) <> 0), "lifetime WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) <> 0), "map A loads")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "map A camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "map A trace succeeds")
  elemHash = TestTraceHash(@trace, @elemCount)
  Check(Bool(elemCount = 8), "map A owned trace has eight events")

  WADClose()
  Check(Bool(MapLevelIsReady(@level) <> 0), "loaded level stays valid after WADClose")
  Check(Bool(BspTraceCount(@trace) = elemCount), "owned trace count stays valid after WADClose")
  Check(Bool(TestTraceHash(@trace, @replayCount) = elemHash And replayCount = elemCount),
        "owned trace checksum survives WADClose unchanged")
  Check(Bool(MapLevelReset(@level) <> 0 And MapLevelIsReady(@level) = 0), "map A level reset succeeds")
  Check(Bool(BspTraceCount(@trace) = elemCount), "trace remains readable after source level reset")
  Check(Bool(TestTraceHash(@trace, @replayCount) = elemHash), "trace data remains unchanged after level reset")

  Check(Bool(WADOpen(FixturePath("m3-bsp-i02.wad")) <> 0), "lifetime WAD reopens")
  Check(Bool(MapLevelLoad("E1M2", @level) <> 0), "distinct map B loads")
  Check(Bool(level\Name = "E1M2" And level\BspRootIndex = 0), "map B identity/root distinct from A")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "map B camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "map B distinct trace succeeds")
  replayHash = TestTraceHash(@trace, @replayCount)
  Check(Bool(replayCount = 4), "map B two leaves/two segs give four events")
  Check(Bool(replayHash <> elemHash), "map B snapshot differs from map A")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 0), "map B front order starts leaf0")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 1), "map B second leaf1")
  MapLevelReset(@level)

  Check(Bool(MapLevelLoad("E1M1", @level) <> 0), "map A reloads in the same WAD session")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "map A camera restored")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "reloaded map A trace succeeds")
  Check(Bool(TestTraceHash(@trace, @replayCount) = elemHash And replayCount = elemCount),
        "reloaded map A reproduces identical checksum and order")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 3), "reloaded map A order starts leaf3")

  savedRoot = level\BspRootIndex
  level\BspRootIndex = 99
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "externally corrupt root rejects a build")
  Check(Bool(BspTraceCount(@trace) = 0), "failure cleanup clears stale reload trace")
  Check(Bool(Len(BspTraceLastError()) > 0), "failure cleanup reports a diagnostic")
  level\BspRootIndex = savedRoot
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "corrected root recovers with a normal build")
  Check(Bool(TestTraceHash(@trace, @elemCount) = elemHash), "recovered normal trace reproduces map A checksum")

  resetFirst = BspTraceReset(@trace)
  resetSecond = BspTraceReset(@trace)
  Check(Bool(resetFirst <> 0 And resetSecond <> 0), "trace reset is idempotent twice")
  Check(Bool(BspTraceCount(@trace) = 0), "repeated reset leaves valid empty trace")
  MapLevelReset(@level)
  WADClose()
  DeleteFile(FixturePath("m3-bsp-i02.wad"))
EndProcedure

; ---------------------------------------------------------------------------
; I03 - malformed references, late geometry, budget failure and recovery
; ---------------------------------------------------------------------------

Procedure TestI03()
  BeginCase("I03", "Edge/error integration: malformed node, geometry/budget failures, recovery")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected malformedOk.i
  Protected hashA.q
  Protected hashRecovered.q
  Protected countA.l = -1
  Protected countRecovered.l = -1
  Protected beforeX.l = 0
  Protected beforeY.l = 0
  Protected beforeHeading.q = 0

  Check(Bool(PrepareFixtureDirectory() <> 0), "fixture directory ready")
  Check(Bool(BuildEdgeWad("m3-bsp-i03.wad") <> 0), "four-map edge synthetic PWAD streamed")
  Check(Bool(WADOpen(FixturePath("m3-bsp-i03.wad")) <> 0), "edge WAD opens")

  ; Malformed node reference through the real loader/validator.
  malformedOk = MapLevelLoad("E1M1", @level)
  Check(Bool(malformedOk = 0), "malformed nonleaf child node reference rejected by real MapLevelLoad")
  Check(Bool(Len(MapLevelLastError()) > 0), "malformed map rejection reports a diagnostic")
  Check(Bool(MapLevelIsReady(@level) = 0), "malformed load leaves no partially ready level")
  Check(Bool(level\Nodes\Count = 0), "failed malformed load reset every decoded set")

  ; Valid map A recovery after the loader failure.
  Check(Bool(MapLevelLoad("E1M2", @level) <> 0), "valid map A recovers after malformed rejection")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "recovering map A camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "recovering map A trace succeeds")
  hashA = TestTraceHash(@trace, @countA)
  Check(Bool(countA = 8), "recovering map A trace has eight events")
  MapLevelReset(@level)

  ; Exponential DAG accepted by M2, bounded to a controlled trace-budget failure.
  Check(Bool(MapLevelLoad("E1M3", @level) <> 0), "cycle-free doubling DAG accepted by real validated loader")
  Check(Bool(level\ReachableNodes = 20 And level\ReachableSubsectors = 1), "loader permits shared DAG without cycle")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "DAG camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "exponential DAG terminates with a controlled budget failure")
  Check(Bool(BspTraceCount(@trace) = 0), "budget failure leaves transactional empty trace")
  Check(Bool(Len(BspTraceLastError()) > 0), "budget failure reports a diagnostic including the map")
  Check(Bool(MapLevelIsReady(@level) <> 0), "budget failure leaves the validated level unchanged")
  Check(Bool(BspCameraGet(@camera, @beforeX, @beforeY, @beforeHeading) <> 0 And beforeX = 65536),
        "budget failure leaves the camera unchanged and ready")
  MapLevelReset(@level)

  ; Late geometry overflow on a valid extreme-origin map, then recovery.
  Check(Bool(MapLevelLoad("E1M4", @level) <> 0), "extreme-origin map loads and validates")
  Check(Bool(BspCameraSetFixed(@camera, 2147483647, 0, #BAM_ANG90) <> 0), "out-of-domain geometry camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "late node-side delta overflow rejects the build")
  Check(Bool(BspTraceCount(@trace) = 0), "geometry failure clears partial trace transactionally")
  Check(Bool(Len(BspTraceLastError()) > 0), "geometry failure reports Geometry diagnostics")
  Check(Bool(MapLevelIsReady(@level) <> 0 And level\Name = "E1M4"), "geometry failure leaves validated map unchanged")
  Check(Bool(BspCameraSetMapUnits(@camera, -32768, 0, #BAM_ANG90) <> 0), "coincident-origin camera recovers")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "same extreme-origin map builds normally after recovery")
  Check(Bool(BspTraceCount(@trace) = 4), "recovered extreme-origin map publishes two leaves and two segs")
  MapLevelReset(@level)

  ; Final valid recovery from map A after all failure types.
  Check(Bool(MapLevelLoad("E1M2", @level) <> 0), "map A reloads after the error chain")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "final map A camera restored")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "final recovery build succeeds")
  hashRecovered = TestTraceHash(@trace, @countRecovered)
  Check(Bool(hashRecovered = hashA And countRecovered = countA),
        "final recovery reproduces the original map A checksum/order")
  Check(Bool(Len(BspTraceLastError()) = 0), "successful final build clears the entire prior error chain")

  MapLevelReset(@level)
  WADClose()
  Check(Bool(WADIsOpen() = #False), "edge WAD closes cleanly")
  DeleteFile(FixturePath("m3-bsp-i03.wad"))
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-03 deterministic BSP traversal synthetic integration (I01-I03)")
PrintN("No commercial game data is read by this harness; fixtures are self-created.")

Check(Bool(PrepareFixtureDirectory() <> 0), "shared fixture root directory prepared")
TestI01()
TestI02()
TestI03()
Check(Bool(CleanupFixtureDirectory() <> 0), "synthetic fixture directory deletion reports success")
Check(Bool(FileSize(gFixtureDirectory) < 0), "removed fixture directory no longer reports a directory/file size")

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
