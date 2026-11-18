; -----------------------------------------------------------------------------
; DoomPB - M3-03 deterministic BSP traversal unit tests (B01-B48)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Standalone synthetic suite. It includes the M3-01/M3-02 fixed/BAM/geometry core,
; the M2 validated MapLevel type composition plus MapValidate authority, and the
; M3-03 Camera/BSP modules. No WAD, loader, palette, graphics, window, video
; backend or commercial asset is used or needed.
;
; Test fixtures are original tiny vanilla map records assembled field-by-field
; through the existing M2 decoders and then validated by MapValidateLevel. Test-
; only fixtures emulate zero-node roots, nested trees, raw cycle/shared graphs and
; externally corrupted ready levels WITHOUT weakening production validation.
;
; Expected near/far orders are hand-computed from original R_PointOnSide ties and
; the recursive R_RenderBSPNode child order. B32 uses a separate test-only
; recursive reference interpreter (not the production stack machine) to prove the
; LIFO push order. Trace fingerprints are canonical little-endian FNV-1a64 over
; published numeric event fields; no pointer or structure padding bytes enter.
; No level coordinates, WAD bytes, graphics or screenshots are printed.
;
; Exit code: 0 when every assertion passed, otherwise the number of failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/BSP.pbi"

#TEST_FNV_Offset = -3750763034362895579
#TEST_FNV_Prime = 1099511628211

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

; Synthetic map lump buffers indexed 1..10 in vanilla canonical order.
Global Dim gMapLump(10)
Global Dim gMapLumpSize.q(10)

; B32 is the only case using the recursive test-only reference interpreter; it is
; bounded to tiny curated trees and never drives production traversal.
Global Dim gRefKind.l(255)
Global Dim gRefSubsector.l(255)
Global Dim gRefSeg.l(255)
Global gRefCount.l = 0

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

; Canonical little-endian 32-bit serialization of one published event's eight
; numeric fields, independently implemented in this harness.
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
; Synthetic map binary builders (original test-only records)
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

Procedure.i NewZero(Size.i)
  Protected memory.i = AllocateMemory(Size)

  If memory <> 0
    FillMemory(memory, Size, 0)
  EndIf
  ProcedureReturn memory
EndProcedure

Procedure.i TestNewMapLump(Kind.i, Size.i)
  If gMapLump(Kind) <> 0
    FreeMemory(gMapLump(Kind))
  EndIf
  gMapLump(Kind) = NewZero(Size)
  gMapLumpSize(Kind) = Size
  ProcedureReturn gMapLump(Kind)
EndProcedure

; Default valid base: one sector, four vertices/lines/sides/segs, one minimal
; BLOCKMAP cell and one zero REJECT byte. Caller supplies subsector/node specs.
Procedure.i TestBuildLevel(*Level.MapLevel, *Subs.TestSubSpec, SubCount.i,
                          *Nodes.TestNodeSpec, NodeCount.i, SegCount.i)
  Protected i.i
  Protected ok.i
  Protected v1.i
  Protected v2.i
  Protected child0.i
  Protected child1.i

  If *Level = 0
    ProcedureReturn #False
  EndIf
  MapLevelReset(*Level)
  TestMapFree()

  If SubCount <= 0 Or NodeCount < 0 Or SegCount < 1 Or SegCount > 4
    MapLevelSetError("Test fixture declaration is invalid.")
    ProcedureReturn #False
  EndIf

  ; THINGS: zero-length synthetic set.
  ok = MapThingsDecode(0, 0, @*Level\Things)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; LINEDEFS: four clockwise one-sided boundary walls, side1=-1.
  If TestNewMapLump(2, 4 * 14) = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To 3
    Put16(gMapLump(2), i * 14, i)
    Put16(gMapLump(2), i * 14 + 2, (i + 1) % 4)
    Put16(gMapLump(2), i * 14 + 4, 0)
    Put16(gMapLump(2), i * 14 + 10, i)
    Put16(gMapLump(2), i * 14 + 12, -1)
  Next
  ok = MapLinedefsDecode(gMapLump(2), gMapLumpSize(2), @*Level\Linedefs)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; SIDEDEFS: four one-sided slots all facing sector 0. Names are synthetic and
  ; are not resource-validated in this non-WAD harness.
  If TestNewMapLump(3, 4 * 30) = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To 3
    PutName8(gMapLump(3), i * 30 + 4, "WALL1")
    PutName8(gMapLump(3), i * 30 + 12, "WALL1")
    PutName8(gMapLump(3), i * 30 + 20, "WALL1")
    Put16(gMapLump(3), i * 30 + 28, 0)
  Next
  ok = MapSidedefsDecode(gMapLump(3), gMapLumpSize(3), @*Level\Sidedefs)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; VERTEXES: unit square in signed map units.
  If TestNewMapLump(4, 4 * 4) = 0
    ProcedureReturn #False
  EndIf
  Put16(gMapLump(4), 0, 0)
  Put16(gMapLump(4), 2, 0)
  Put16(gMapLump(4), 4, 64)
  Put16(gMapLump(4), 6, 0)
  Put16(gMapLump(4), 8, 64)
  Put16(gMapLump(4), 10, 64)
  Put16(gMapLump(4), 12, 0)
  Put16(gMapLump(4), 14, 64)
  ok = MapVertexesDecode(gMapLump(4), gMapLumpSize(4), @*Level\Vertexes)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; SEGS: caller-bounded 1..4 clockwise one-sided segment records, line i%4.
  If TestNewMapLump(5, SegCount * 12) = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To SegCount - 1
    v1 = i % 4
    v2 = (i + 1) % 4
    Put16(gMapLump(5), i * 12, v1)
    Put16(gMapLump(5), i * 12 + 2, v2)
    Put16(gMapLump(5), i * 12 + 4, 0)
    Put16(gMapLump(5), i * 12 + 6, v1)
    Put16(gMapLump(5), i * 12 + 8, 0)
    Put16(gMapLump(5), i * 12 + 10, 0)
  Next
  ok = MapSegsDecode(gMapLump(5), gMapLumpSize(5), @*Level\Segs)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; SSECTORS: caller-supplied seg ranges (may share, as validated vanilla does).
  If TestNewMapLump(6, SubCount * 4) = 0
    ProcedureReturn #False
  EndIf
  For i = 0 To SubCount - 1
    Put16(gMapLump(6), i * 4, *Subs\NumSegs)
    Put16(gMapLump(6), i * 4 + 2, *Subs\FirstSeg)
    *Subs = *Subs + SizeOf(TestSubSpec)
  Next
  ; Restore the caller pointer for deterministic record-field inspection.
  *Subs = *Subs - SubCount * SizeOf(TestSubSpec)
  ok = MapSubsectorsDecode(gMapLump(6), gMapLumpSize(6), @*Level\Subsectors)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; NODES: caller-supplied original/synthetic partition and raw 16-bit children.
  ; A null caller node pointer is only possible for a zero-node level, and no field
  ; is dereferenced in that case. A zero-length NODES lump is valid and null data
  ; is accepted by the M2 decoder.
  TestNewMapLump(7, NodeCount * 28)
  If NodeCount > 0
    If gMapLump(7) = 0
      ProcedureReturn #False
    EndIf
    If *Nodes = 0
      MapLevelSetError("Test fixture node specs are required for a nonempty node set.")
      ProcedureReturn #False
    EndIf
    For i = 0 To NodeCount - 1
      Put16(gMapLump(7), i * 28, *Nodes\OriginX)
      Put16(gMapLump(7), i * 28 + 2, *Nodes\OriginY)
      Put16(gMapLump(7), i * 28 + 4, *Nodes\DX)
      Put16(gMapLump(7), i * 28 + 6, *Nodes\DY)
      child0 = *Nodes\Child0
      child1 = *Nodes\Child1
      Put16(gMapLump(7), i * 28 + 24, child0)
      Put16(gMapLump(7), i * 28 + 26, child1)
      *Nodes = *Nodes + SizeOf(TestNodeSpec)
    Next
    *Nodes = *Nodes - NodeCount * SizeOf(TestNodeSpec)
  EndIf
  ok = MapNodesDecode(gMapLump(7), gMapLumpSize(7), @*Level\Nodes)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; SECTORS: one synthetic sector with unit names and a plausible light level.
  If TestNewMapLump(8, 26) = 0
    ProcedureReturn #False
  EndIf
  PutName8(gMapLump(8), 4, "FLOOR1")
  PutName8(gMapLump(8), 12, "CEIL1")
  Put16(gMapLump(8), 20, 160)
  ok = MapSectorsDecode(gMapLump(8), gMapLumpSize(8), @*Level\Sectors)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; REJECT: one sector needs one zero byte.
  If TestNewMapLump(9, 1) = 0
    ProcedureReturn #False
  EndIf
  ok = MapRejectDecode(gMapLump(9), gMapLumpSize(9), @*Level\Reject)
  If ok = #False
    ProcedureReturn #False
  EndIf

  ; BLOCKMAP: 8-byte header + offset word + dummy + valid line 0 + terminator.
  If TestNewMapLump(10, 16) = 0
    ProcedureReturn #False
  EndIf
  Put16(gMapLump(10), 4, 1)
  Put16(gMapLump(10), 6, 1)
  Put16(gMapLump(10), 8, 5)
  Put16(gMapLump(10), 10, 0)
  Put16(gMapLump(10), 12, 0)
  Put16(gMapLump(10), 14, $FFFF)
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
; B32 test-only recursive reference interpreter (tiny bounded trees only)
; ---------------------------------------------------------------------------

Procedure TestRefClear()
  Protected i.i

  gRefCount = 0
  For i = 0 To 255
    gRefKind(i) = -1
    gRefSubsector(i) = -1
    gRefSeg(i) = -1
  Next
EndProcedure

Procedure.i TestRefAppend(Kind.l, Subsector.l, Seg.l)
  If gRefCount >= 256
    ProcedureReturn #False
  EndIf
  gRefKind(gRefCount) = Kind
  gRefSubsector(gRefCount) = Subsector
  gRefSeg(gRefCount) = Seg
  gRefCount + 1
  ProcedureReturn #True
EndProcedure

; Deliberately recursive, matching original R_RenderBSPNode recursion; no culling.
; It reads the same validated MapLevel records but uses no production stack frames.
Procedure.i TestRefWalk(*Level.MapLevel, RawItem.l, CameraX.l, CameraY.l, Depth.i)
  Protected leafIndex.l
  Protected nodeIndex.l
  Protected numSegs.l
  Protected firstSeg.l
  Protected lastSeg.l
  Protected segIndex.l
  Protected originX.l
  Protected originY.l
  Protected dx.l
  Protected dy.l
  Protected child0.l
  Protected child1.l
  Protected side.l = 0
  Protected target.l

  If Depth > 64
    ProcedureReturn #False
  EndIf

  If (RawItem & #MAP_NF_SUBSECTOR) <> 0
    leafIndex = RawItem & $7FFF
    If MapSubsectorsGet(@*Level\Subsectors, leafIndex, @numSegs, @firstSeg) = #False
      ProcedureReturn #False
    EndIf
    If TestRefAppend(#BSP_EventSubsector, leafIndex, #BSP_NoIndex) = #False
      ProcedureReturn #False
    EndIf
    lastSeg = firstSeg + numSegs - 1
    For segIndex = firstSeg To lastSeg
      If TestRefAppend(#BSP_EventSeg, leafIndex, segIndex) = #False
        ProcedureReturn #False
      EndIf
    Next
    ProcedureReturn #True
  EndIf

  nodeIndex = RawItem
  If MapNodesGet(@*Level\Nodes, nodeIndex, @originX, @originY, @dx, @dy,
                 0, 0, 0, 0, 0, 0, 0, 0, @child0, @child1) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(originX, @originX) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(originY, @originY) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(dx, @dx) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(dy, @dy) = #False
    ProcedureReturn #False
  EndIf
  If GeometryPointOnNodeSideChecked(CameraX, CameraY, originX, originY, dx, dy, @side) = #False
    ProcedureReturn #False
  EndIf

  If side = 0
    target = child0
  Else
    target = child1
  EndIf
  If TestRefWalk(*Level, target, CameraX, CameraY, Depth + 1) = #False
    ProcedureReturn #False
  EndIf
  If side = 0
    target = child1
  Else
    target = child0
  EndIf
  ProcedureReturn TestRefWalk(*Level, target, CameraX, CameraY, Depth + 1)
EndProcedure

; ---------------------------------------------------------------------------
; B01-B05: null/unready/corrupt root inputs
; ---------------------------------------------------------------------------

Procedure TestB01()
  BeginCase("B01", "Null level rejected with empty valid trace")
  Protected trace.BspTrace
  Protected camera.BspCamera

  Check(Bool(BspCameraSetMapUnits(@camera, 1, 1, #BAM_ANG90) <> 0), "synthetic camera created")
  Check(Bool(BspTraceReset(@trace) <> 0 And BspTraceCount(@trace) = 0), "target trace starts empty")
  Check(Bool(BspTraceBuild(0, @camera, @trace) = 0), "null MapLevel pointer is rejected")
  Check(Bool(BspTraceCount(@trace) = 0), "failed null-level build left the trace empty")
  Check(Bool(Len(BspTraceLastError()) > 0), "null MapLevel produces a diagnostic")
EndProcedure

Procedure TestB02()
  BeginCase("B02", "Null camera rejected")
  Protected level.MapLevel
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 1) <> 0), "zero-node one-subsector level built")
  Check(Bool(BspTraceReset(@trace) <> 0), "target trace initialized")
  Check(Bool(BspTraceBuild(@level, 0, @trace) = 0), "null camera pointer is rejected")
  Check(Bool(BspTraceCount(@trace) = 0), "failed null-camera build left the trace empty")
  Check(Bool(Len(BspTraceLastError()) > 0), "null camera produces a diagnostic")
  MapLevelReset(@level)
EndProcedure

Procedure TestB03()
  BeginCase("B03", "Null trace pointer rejected without access violation")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected Dim subs.TestSubSpec(0)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 1) <> 0), "zero-node level built")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, 0) = 0), "null trace pointer is rejected")
  Check(Bool(Len(BspTraceLastError()) > 0), "null trace produces a diagnostic")
  Check(Bool(BspTraceReset(0) = 0), "null trace reset is rejected safely")
  MapLevelReset(@level)
EndProcedure

Procedure TestB04()
  BeginCase("B04", "Uninitialized/not-ready level rejected")
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected emptyLevel.MapLevel

  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceReset(@trace) <> 0), "target trace initialized")
  Check(Bool(MapLevelIsReady(@emptyLevel) = 0), "fresh zero-initialized level is not ready")
  Check(Bool(BspTraceBuild(@emptyLevel, @camera, @trace) = 0), "not-ready MapLevel is rejected")
  Check(Bool(BspTraceCount(@trace) = 0), "failed unready-level build left the trace empty")
  Check(Bool(Len(BspTraceLastError()) > 0), "not-ready MapLevel produces a diagnostic")
EndProcedure

Procedure TestB05()
  BeginCase("B05", "Invalid/corrupt root index rejected before dereference")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)
  Protected Dim nodes.TestNodeSpec(0)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Child0 = $8000 ! 0
  nodes(0)\Child1 = $8000 ! 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @nodes(0), 1, 2) <> 0), "one-node/two-leaf level built")
  Check(Bool(level\BspRootIsSubsector = 0 And level\BspRootIndex = 0), "M2 root is last node zero")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera created")
  level\BspRootIndex = 9
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "out-of-range root node index rejected")
  Check(Bool(BspTraceCount(@trace) = 0), "corrupt root leaves no events")
  Check(Bool(Len(BspTraceLastError()) > 0), "corrupt root produces a diagnostic")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; B06-B07: zero-node root conventions
; ---------------------------------------------------------------------------

Procedure TestB06()
  BeginCase("B06", "Zero-node one-subsector root emits leaf and its segs")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)
  Protected count.i
  Protected kind.l = 0
  Protected subsector.l = 0
  Protected seg.l = 0
  Protected sector.l = 0
  Protected linedef.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 2
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 2) <> 0), "zero-node one-subsector two-seg level built")
  Check(Bool(level\BspRootIsSubsector = 1 And level\BspRootIndex = 0), "M2 root is subsector zero")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  count = BspTraceCount(@trace)
  Check(Bool(count = 3), "one subsector event plus two seg events are emitted")
  Check(Bool(BspTraceGet(@trace, 0, @kind, @subsector, @seg, @sector,
                         @linedef, @side, @front, @back) <> 0), "first event readable")
  Check(Bool(kind = #BSP_EventSubsector And subsector = 0), "first event is subsector 0")
  Check(Bool(seg = -1 And linedef = -1 And side = -1 And front = -1 And back = -1),
        "SUBSECTOR irrelevant fields are -1 sentinels")
  Check(Bool(sector = 0), "SUBSECTOR derived sector is zero")
  seg = 0
  subsector = 0
  Check(Bool(BspTraceGet(@trace, 1, @kind, @subsector, 0, 0, 0, 0, 0, 0) <> 0),
        "first seg event readable")
  Check(Bool(kind = #BSP_EventSeg And subsector = 0 And seg = 0), "first SEG event is seg 0")
  seg = 0
  Check(Bool(BspTraceGet(@trace, 2, @kind, @subsector, @seg, 0, 0, 0, 0, 0) <> 0),
        "second seg event readable")
  Check(Bool(kind = #BSP_EventSeg And subsector = 0 And seg = 1), "second SEG event is seg 1")
  Check(Bool(trace\VisitedNodes = 0 And trace\VisitedSubsectors = 1 And
        trace\EmittedSegs = 2 And trace\OcclusionSkips = 0),
        "zero-node counters record one leaf, two segs and no occlusion skip")
  MapLevelReset(@level)
EndProcedure

Procedure TestB07()
  BeginCase("B07", "Zero-node but invalid multi-leaf raw object fails safely")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 2, 0, 0, 2) = 0), "validator rejects zero nodes with two subsectors")
  Check(Bool(Len(MapLevelLastError()) > 0), "validator rejection is a diagnostic")
  MapLevelReset(@level)

  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 1) <> 0), "valid one-subsector root rebuilt")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceReset(@trace) <> 0), "target trace initialized empty")
  level\Subsectors\Count = 2
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "externally corrupted multi-leaf zero-node object rejected")
  Check(Bool(BspTraceCount(@trace) = 0), "corrupted zero-node root leaves no events")
  Check(Bool(Len(BspTraceLastError()) > 0), "corrupted zero-node root produces a diagnostic")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; B08-B15: side classification, ties, signed partitions, near child order
; ---------------------------------------------------------------------------

; Shared one-node/two-leaf fixture. Caller fills node spec and cameras.
Procedure TestBuildOneNode(*Level.MapLevel, *Node.TestNodeSpec)
  Protected Dim subs.TestSubSpec(1)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  ProcedureReturn TestBuildLevel(*Level, @subs(0), 2, *Node, 1, 2)
EndProcedure

; Reads only subsector Kind/Subsector of a chronological trace.
Procedure.i TestSubOrder(*Trace.BspTrace, Index.i, *Subsector.Long)
  Protected kind.l = -1
  Protected subOther.l = -1
  Protected ok.i

  ok = BspTraceGet(*Trace, Index, @kind, *Subsector, @subOther, @subOther,
                   @subOther, @subOther, @subOther, @subOther)
  ProcedureReturn Bool(ok <> 0 And kind = #BSP_EventSubsector)
EndProcedure

Procedure TestB08()
  BeginCase("B08", "One-node tree camera on side 0: leaf0 then leaf1")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected first.l = -1
  Protected second.l = -1

  node\OriginX = 0
  node\OriginY = 0
  node\DX = 0
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildOneNode(@level, @node) <> 0), "one-node/two-leaf level built")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera on positive X side created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 0), "near child0 leaf0 is visited first")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 1), "far child1 leaf1 follows its own seg event")
  MapLevelReset(@level)
EndProcedure

Procedure TestB09()
  BeginCase("B09", "One-node tree camera on side 1: leaf1 then leaf0")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected first.l = -1
  Protected second.l = -1

  node\OriginX = 0
  node\OriginY = 0
  node\DX = 0
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildOneNode(@level, @node) <> 0), "one-node/two-leaf level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera on negated side created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 1), "near child1 leaf1 is visited first")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 0), "far child0 leaf0 follows its own seg event")
  MapLevelReset(@level)
EndProcedure

Procedure TestB10()
  BeginCase("B10", "Vertical partition, camera on exact boundary: original tie")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected side.l = -123
  Protected first.l = -1
  Protected second.l = -1
  Protected originX.l = 0
  Protected dx.l = 0
  Protected dy.l = 0

  node\OriginX = 0
  node\OriginY = 0
  node\DX = 0
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildOneNode(@level, @node) <> 0), "one-node/two-leaf level built")
  Check(Bool(FixedFromIntChecked(node\OriginX, @originX) <> 0 And
        FixedFromIntChecked(node\DX, @dx) <> 0 And
        FixedFromIntChecked(node\DY, @dy) <> 0), "partition fields convert exactly")
  Check(Bool(GeometryPointOnNodeSideChecked(0, 0, originX, 0, dx, dy, @side) <> 0 And side = 1),
        "x <= origin with dy>0 returns original back side")
  Check(Bool(BspCameraSetFixed(@camera, 0, 0, #BAM_ANG90) <> 0), "camera placed at exact boundary")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 1), "boundary tie visits near child1 leaf1")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 0), "then far child0 leaf0")
  MapLevelReset(@level)
EndProcedure

Procedure TestB11()
  BeginCase("B11", "Horizontal partition, camera on exact boundary")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected side.l = -123
  Protected first.l = -1
  Protected second.l = -1
  Protected originY.l = 0
  Protected dx.l = 0
  Protected dy.l = 0

  node\OriginX = 0
  node\OriginY = 0
  node\DX = 1
  node\DY = 0
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildOneNode(@level, @node) <> 0), "one-node/two-leaf level built")
  Check(Bool(FixedFromIntChecked(node\OriginY, @originY) <> 0 And
        FixedFromIntChecked(node\DX, @dx) <> 0 And
        FixedFromIntChecked(node\DY, @dy) <> 0), "partition fields convert exactly")
  Check(Bool(GeometryPointOnNodeSideChecked(0, 0, 0, originY, dx, dy, @side) <> 0 And side = 0),
        "y <= origin with dx>0 returns original front side")
  Check(Bool(BspCameraSetFixed(@camera, 0, 0, #BAM_ANG90) <> 0), "camera placed at exact boundary")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 0), "boundary front tie visits near child0 leaf0")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 1), "then far child1 leaf1")
  MapLevelReset(@level)
EndProcedure

Procedure TestB12()
  BeginCase("B12", "General diagonal partition: exact left/right classification")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected sideA.l = -123
  Protected sideB.l = -123
  Protected originX.l = 0
  Protected originY.l = 0
  Protected dx.l = 0
  Protected dy.l = 0
  Protected first.l = -1
  Protected second.l = -1

  node\OriginX = 0
  node\OriginY = 0
  node\DX = 1
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildOneNode(@level, @node) <> 0), "one-node/two-leaf level built")
  Check(Bool(FixedFromIntChecked(node\OriginX, @originX) <> 0 And
        FixedFromIntChecked(node\OriginY, @originY) <> 0 And
        FixedFromIntChecked(node\DX, @dx) <> 0 And
        FixedFromIntChecked(node\DY, @dy) <> 0), "diagonal partition fields convert exactly")
  Check(Bool(GeometryPointOnNodeSideChecked(65536, -65536, originX, originY, dx, dy, @sideA) <> 0 And sideA = 0),
        "diagonal point 1,-1 classified front side 0")
  Check(Bool(GeometryPointOnNodeSideChecked(-65536, 65536, originX, originY, dx, dy, @sideB) <> 0 And sideB = 1),
        "diagonal point -1,1 classified back side 1")

  Check(Bool(BspCameraSetMapUnits(@camera, 1, -1, #BAM_ANG90) <> 0), "front-side camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "front-side trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 0), "front side visits leaf0 first")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 1), "then leaf1")

  trace\Count = 0
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 1, #BAM_ANG90) <> 0), "back-side camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "back-side trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 1), "back side visits leaf1 first")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 0), "then leaf0")
  MapLevelReset(@level)
EndProcedure

Procedure TestB13()
  BeginCase("B13", "General partition multiplication equality tie yields back side")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected side.l = -123
  Protected first.l = -1
  Protected second.l = -1
  Protected originX.l = 0
  Protected originY.l = 0
  Protected dx.l = 0
  Protected dy.l = 0

  node\OriginX = 0
  node\OriginY = 0
  node\DX = 1
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildOneNode(@level, @node) <> 0), "one-node/two-leaf level built")
  Check(Bool(FixedFromIntChecked(node\OriginX, @originX) <> 0 And
        FixedFromIntChecked(node\OriginY, @originY) <> 0 And
        FixedFromIntChecked(node\DX, @dx) <> 0 And
        FixedFromIntChecked(node\DY, @dy) <> 0), "partition fields convert exactly")
  Check(Bool(GeometryPointOnNodeSideChecked(65536, 65536, originX, originY, dx, dy, @side) <> 0 And side = 1),
        "exact partition equality uses right<left false -> back side")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 1, #BAM_ANG90) <> 0), "on-line camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 1), "equality tie visits back near child1 leaf1")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 0), "then front far child0 leaf0")
  MapLevelReset(@level)
EndProcedure

Procedure TestB14()
  BeginCase("B14", "Negative node origin and direction produce expected near child")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected side.l = -123
  Protected originX.l = 0
  Protected originY.l = 0
  Protected dx.l = 0
  Protected dy.l = 0
  Protected first.l = -1
  Protected second.l = -1

  node\OriginX = -1
  node\OriginY = 0
  node\DX = -1
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildOneNode(@level, @node) <> 0), "negative partition level built")
  Check(Bool(FixedFromIntChecked(node\OriginX, @originX) <> 0 And originX = -65536), "negative origin X maps to fixed -65536")
  Check(Bool(FixedFromIntChecked(node\DX, @dx) <> 0 And dx = -65536), "negative direction raw -1 -> fixed -65536")
  Check(Bool(FixedFromIntChecked(node\DY, @dy) <> 0 And dy = 65536), "positive direction raw 1 -> fixed 65536")
  Check(Bool(GeometryPointOnNodeSideChecked(-131072, 0, originX, originY, dx, dy, @side) <> 0 And side = 1),
        "negative origin/direction still classify camera on back side")
  Check(Bool(BspCameraSetMapUnits(@camera, -2, 0, #BAM_ANG90) <> 0), "negated camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 1), "expected near child1 leaf1")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 0), "far leaf0 follows")
  MapLevelReset(@level)
EndProcedure

Procedure TestB15()
  BeginCase("B15", "Reverse partition direction reverses side classification")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected nodeA.TestNodeSpec
  Protected nodeB.TestNodeSpec
  Protected sideA.l = -123
  Protected sideB.l = -123
  Protected originX.l = 0
  Protected originY.l = 0
  Protected dxA.l = 0
  Protected dyA.l = 0
  Protected dxB.l = 0
  Protected dyB.l = 0
  Protected first.l = -1
  Protected second.l = -1

  nodeA\OriginX = 0
  nodeA\OriginY = 0
  nodeA\DX = 1
  nodeA\DY = 1
  nodeA\Child0 = $8000 ! 0
  nodeA\Child1 = $8000 ! 1
  nodeB\OriginX = 0
  nodeB\OriginY = 0
  nodeB\DX = -1
  nodeB\DY = -1
  nodeB\Child0 = $8000 ! 0
  nodeB\Child1 = $8000 ! 1

  Check(Bool(TestBuildOneNode(@level, @nodeA) <> 0), "forward-direction tree built")
  Check(Bool(FixedFromIntChecked(nodeA\DX, @dxA) <> 0 And
        FixedFromIntChecked(nodeA\DY, @dyA) <> 0), "forward direction converts")
  Check(Bool(GeometryPointOnNodeSideChecked(65536, -65536, 0, 0, dxA, dyA, @sideA) <> 0 And sideA = 0),
        "forward direction gives front side")
  Check(Bool(BspCameraSetFixed(@camera, 65536, -65536, #BAM_ANG90) <> 0), "fixed camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "forward trace succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 0), "forward near child0 leaf0")
  MapLevelReset(@level)

  Check(Bool(TestBuildOneNode(@level, @nodeB) <> 0), "reverse-direction tree rebuilt")
  Check(Bool(FixedFromIntChecked(nodeB\DX, @dxB) <> 0 And dxB = -65536), "reverse dx -1 -> fixed -65536")
  Check(Bool(FixedFromIntChecked(nodeB\DY, @dyB) <> 0 And dyB = -65536), "reverse dy -1 -> fixed -65536")
  Check(Bool(GeometryPointOnNodeSideChecked(65536, -65536, 0, 0, dxB, dyB, @sideB) <> 0 And sideB = 1),
        "reverse direction flips same point to back side")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "reverse trace succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @second) <> 0 And second = 1), "reverse side visits leaf1 first")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; B16-B19: nested/full order, root conventions, child encoding
; ---------------------------------------------------------------------------

Procedure TestBuildNestedTree(*Level.MapLevel)
  Protected Dim subs.TestSubSpec(3)
  Protected Dim nodes.TestNodeSpec(2)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  subs(2)\FirstSeg = 2
  subs(2)\NumSegs = 1
  subs(3)\FirstSeg = 3
  subs(3)\NumSegs = 1

  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Child0 = $8000 ! 0
  nodes(0)\Child1 = $8000 ! 1
  nodes(1)\OriginX = 0
  nodes(1)\OriginY = 0
  nodes(1)\DX = 0
  nodes(1)\DY = 1
  nodes(1)\Child0 = $8000 ! 2
  nodes(1)\Child1 = $8000 ! 3
  nodes(2)\OriginX = 0
  nodes(2)\OriginY = 0
  nodes(2)\DX = 0
  nodes(2)\DY = 1
  nodes(2)\Child0 = 0
  nodes(2)\Child1 = 1

  ProcedureReturn TestBuildLevel(*Level, @subs(0), 4, @nodes(0), 3, 4)
EndProcedure

Procedure TestB16()
  BeginCase("B16", "Nested three-node/four-leaf tree: expected full order camera A")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected count.i
  Protected i.i
  Protected subsector.l = -1
  Protected Dim expected.l(3)

  expected(0) = 3
  expected(1) = 2
  expected(2) = 1
  expected(3) = 0

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(level\BspRootIndex = 2), "root is last node 2, not node 0")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera A created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  count = BspTraceCount(@trace)
  Check(Bool(count = 4 + 4), "four leaves and four segs produce eight events")
  For i = 0 To 3
    subsector = -1
    Check(Bool(TestSubOrder(@trace, i * 2, @subsector) <> 0 And subsector = expected(i)),
          "camera A subsector order slot " + Str(i) + " = " + Str(expected(i)))
  Next
  MapLevelReset(@level)
EndProcedure

Procedure TestB17()
  BeginCase("B17", "Same nested tree: distinct full order for camera B")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected count.i
  Protected i.i
  Protected subsector.l = -1
  Protected Dim expected.l(3)

  expected(0) = 0
  expected(1) = 1
  expected(2) = 2
  expected(3) = 3

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera B created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  count = BspTraceCount(@trace)
  Check(Bool(count = 8), "complete camera B trace has eight events")
  For i = 0 To 3
    subsector = -1
    Check(Bool(TestSubOrder(@trace, i * 2, @subsector) <> 0 And subsector = expected(i)),
          "camera B subsector order slot " + Str(i) + " = " + Str(expected(i)))
  Next
  Check(Bool(trace\VisitedNodes = 3 And trace\VisitedSubsectors = 4 And trace\EmittedSegs = 4),
        "camera B visits all three nodes, four leaves and four segs once")
  MapLevelReset(@level)
EndProcedure

Procedure TestB18()
  BeginCase("B18", "Root is last node; no assumption of node 0")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)
  Protected Dim nodes.TestNodeSpec(1)
  Protected first.l = -1
  Protected second.l = -1

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1

  ; Node 0 is unreachable from the root node 1 (diagnostic-only in M2).
  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 1
  nodes(0)\DY = 0
  nodes(0)\Child0 = $8000 ! 0
  nodes(0)\Child1 = $8000 ! 1
  nodes(1)\OriginX = 0
  nodes(1)\OriginY = 0
  nodes(1)\DX = 0
  nodes(1)\DY = 1
  nodes(1)\Child0 = $8000 ! 0
  nodes(1)\Child1 = $8000 ! 1

  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @nodes(0), 2, 2) <> 0), "two-node level with unreachable node0 built")
  Check(Bool(level\BspRootIsSubsector = 0 And level\BspRootIndex = 1), "root uses last node index, never node 0")
  Check(Bool(level\ReachableNodes = 1 And level\UnreachableNodes = 1), "validator reports root-node reachability")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(trace\VisitedNodes = 1), "walk visits only the root node, not unreachable node 0")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 1), "root side1 near leaf1 first")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 0), "then leaf0")
  MapLevelReset(@level)
EndProcedure

Procedure TestB19()
  BeginCase("B19", "Child encoding high bit 0x8000 and index mask 0x7FFF")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(3)
  Protected Dim nodes.TestNodeSpec(0)
  Protected first.l = -1
  Protected second.l = -1

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  subs(2)\FirstSeg = 2
  subs(2)\NumSegs = 1
  subs(3)\FirstSeg = 3
  subs(3)\NumSegs = 1
  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Child0 = $8000 ! 3
  nodes(0)\Child1 = $8000 ! 1

  Check(Bool(TestBuildLevel(@level, @subs(0), 4, @nodes(0), 1, 4) <> 0), "encoded-child tree built")
  Check(Bool(MapNodesChildIsSubsector(@level\Nodes, 0, 0) = 1 And
        MapNodesChildIsSubsector(@level\Nodes, 0, 1) = 1), "both raw children report leaf high bit")
  Check(Bool(MapNodesChildIndex(@level\Nodes, 0, 0) = 3 And
        MapNodesChildIndex(@level\Nodes, 0, 1) = 1), "0x7FFF mask extracts leaf indices 3 and 1")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "front-side camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 3), "side0 near leaf index 3, not numeric 0x7FFF")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 1), "then far leaf index 1")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; B20-B25: absolute seg ranges, event schema, links and sentinels
; ---------------------------------------------------------------------------

Procedure TestB20()
  BeginCase("B20", "Subsector firstseg not zero: emitted absolute seg indices")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)
  Protected subsector.l = 0
  Protected seg.l = 0
  Protected linedef.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected kind.l = 0

  subs(0)\FirstSeg = 2
  subs(0)\NumSegs = 2
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 4) <> 0), "firstseg=2 level built")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(BspTraceCount(@trace) = 3), "three events emitted")
  seg = -1
  Check(Bool(BspTraceGet(@trace, 1, @kind, @subsector, @seg, 0, 0, 0, 0, 0) <> 0),
        "first SEG event readable")
  Check(Bool(kind = #BSP_EventSeg And subsector = 0 And seg = 2), "absolute seg index 2, not relative 0")
  seg = -1
  Check(Bool(BspTraceGet(@trace, 2, @kind, @subsector, @seg, 0, 0, 0, 0, 0) <> 0),
        "second SEG event readable")
  Check(Bool(kind = #BSP_EventSeg And seg = 3), "absolute seg index 3 follows")
  linedef = -1
  side = -1
  front = -1
  back = -999
  Check(Bool(BspTraceGet(@trace, 1, 0, 0, 0, 0, @linedef, @side, @front, @back) <> 0), "seg links readable")
  Check(Bool(linedef = 2 And side = 0 And front = 0 And back = -1), "seg2 links linedef2/side0/front sector0/back -1")
  MapLevelReset(@level)
EndProcedure

Procedure TestB21()
  BeginCase("B21", "Multiple segs emitted sequentially within one subsector")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)
  Protected i.i
  Protected kind.l = 0
  Protected seg.l = 0
  Protected subsector.l = 0

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 3
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 3) <> 0), "three-seg subsector built")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(BspTraceCount(@trace) = 4), "subsector plus three segs give four events")
  For i = 0 To 2
    seg = -1
    subsector = -1
    Check(Bool(BspTraceGet(@trace, 1 + i, @kind, @subsector, @seg, 0, 0, 0, 0, 0) <> 0),
          "seg event slot " + Str(i) + " readable")
    Check(Bool(kind = #BSP_EventSeg And subsector = 0 And seg = i),
          "seg event slot " + Str(i) + " has sequential index " + Str(i))
  Next
  Check(Bool(trace\EmittedSegs = 3), "emitted-seg counter is three")
  MapLevelReset(@level)
EndProcedure

Procedure TestB22()
  BeginCase("B22", "Events interleave SUBSECTOR then SEG, not all leaves first")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected node.TestNodeSpec
  Protected Dim subs.TestSubSpec(1)
  Protected i.i
  Protected kind.l = 0
  Protected subsector.l = 0
  Protected seg.l = 0
  Protected Dim expectedKind.l(3)
  Protected Dim expectedSub.l(3)
  Protected Dim expectedSeg.l(3)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  node\OriginX = 0
  node\OriginY = 0
  node\DX = 0
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  expectedKind(0) = #BSP_EventSubsector
  expectedSub(0) = 0
  expectedSeg(0) = -1
  expectedKind(1) = #BSP_EventSeg
  expectedSub(1) = 0
  expectedSeg(1) = 0
  expectedKind(2) = #BSP_EventSubsector
  expectedSub(2) = 1
  expectedSeg(2) = -1
  expectedKind(3) = #BSP_EventSeg
  expectedSub(3) = 1
  expectedSeg(3) = 1

  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @node, 1, 2) <> 0), "two-leaf tree built")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "front-side camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(BspTraceCount(@trace) = 4), "two subsectors plus two segs give four events")
  For i = 0 To 3
    kind = -1
    subsector = -1
    seg = -1
    Check(Bool(BspTraceGet(@trace, i, @kind, @subsector, @seg, 0, 0, 0, 0, 0) <> 0),
          "interleaved slot " + Str(i) + " readable")
    Check(Bool(kind = expectedKind(i) And subsector = expectedSub(i) And seg = expectedSeg(i)),
          "event slot " + Str(i) + " interleaves subsector entry then its seg")
  Next
  MapLevelReset(@level)
EndProcedure

Procedure TestB23()
  BeginCase("B23", "Derived sector index preserved in SUBSECTOR event")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)
  Protected derived.l
  Protected eventSector.l = -7

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 1) <> 0), "one-leaf level built")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  derived = MapLevelGetSubsectorSector(@level, 0)
  Check(Bool(derived = 0), "independent level accessor reports derived sector 0")
  Check(Bool(BspTraceGet(@trace, 0, 0, 0, 0, @eventSector, 0, 0, 0, 0) <> 0),
        "subsector event sector readable")
  Check(Bool(eventSector = derived), "SUBSECTOR event preserves the derived sector index")
  Check(Bool(BspTraceGet(@trace, 1, 0, 0, 0, @eventSector, 0, 0, 0, 0) <> 0),
        "seg event sector readable")
  Check(Bool(eventSector = derived), "SEG event carries the owning leaf's derived sector")
  MapLevelReset(@level)
EndProcedure

Procedure TestB24()
  BeginCase("B24", "SEG event includes correct linedef, side, front/back sectors")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)
  Protected lineRef.l = -7
  Protected sideRef.l = -7
  Protected frontRef.l = -7
  Protected backRef.l = -7
  Protected segLine.l = -7
  Protected segSide.l = -7
  Protected segFront.l = -7
  Protected segBack.l = -7

  subs(0)\FirstSeg = 1
  subs(0)\NumSegs = 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 2) <> 0), "seg1 level built")
  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  lineRef = -1
  sideRef = -1
  frontRef = -1
  backRef = -999
  Check(Bool(MapLevelGetSegLinks(@level, 1, @lineRef, @sideRef, @frontRef, @backRef) <> 0),
        "independent level seg link accessor works")
  segLine = -1
  segSide = -1
  segFront = -1
  segBack = -999
  Check(Bool(BspTraceGet(@trace, 1, 0, 0, 0, 0, @segLine, @segSide, @segFront, @segBack) <> 0),
        "seg event fields readable")
  Check(Bool(segLine = lineRef And segSide = sideRef And segFront = frontRef And segBack = backRef),
        "SEG event exactly matches validated linedef/side/front/back links")
  Check(Bool(segLine = 1 And segSide = 0 And segFront = 0 And segBack = -1),
        "one-sided seg has linedef1, side0, front sector0 and back -1")
  MapLevelReset(@level)
EndProcedure

Procedure TestB25()
  BeginCase("B25", "SEG one-sided back-sector -1 sentinel preserved")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)
  Protected node.TestNodeSpec
  Protected i.i
  Protected back.l = -999
  Protected kind.l = 0
  Protected seg.l = 0

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  node\OriginX = 0
  node\OriginY = 0
  node\DX = 1
  node\DY = 0
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @node, 1, 2) <> 0), "valid two-leaf one-sided level built")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  Check(Bool(BspTraceCount(@trace) = 4), "two subsectors and two segs emitted")
  For i = 1 To 3 Step 2
    back = -999
    seg = -1
    kind = 0
    Check(Bool(BspTraceGet(@trace, i, @kind, 0, @seg, 0, 0, 0, 0, @back) <> 0),
          "SEG slot " + Str(i) + " back field readable")
    Check(Bool(kind = #BSP_EventSeg And back = -1),
          "SEG slot " + Str(i) + " preserves the documented one-sided -1 sentinel")
  Next
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; B26-B30: invalid record ranges and graph cycle rejection
; ---------------------------------------------------------------------------

Procedure TestB26()
  BeginCase("B26", "Empty/invalid seg range fails or is rejected as specified")
  Protected level.MapLevel
  Protected Dim subs.TestSubSpec(0)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 0
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 1) = 0), "zero-seg subsector rejected by M2 validator")
  Check(Bool(Len(MapLevelLastError()) > 0), "zero-seg rejection reports a diagnostic")
  MapLevelReset(@level)

  subs(0)\FirstSeg = 3
  subs(0)\NumSegs = 2
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, 0, 0, 3) = 0), "seg range past SEGS rejected by M2 validator")
  Check(Bool(Len(MapLevelLastError()) > 0), "out-of-range seg rejection reports a diagnostic")
  MapLevelReset(@level)
EndProcedure

Procedure TestB27()
  BeginCase("B27", "Invalid child-node index test object fails safely")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)
  Protected Dim nodes.TestNodeSpec(1)
  Protected *item.MapNode

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Child0 = $8000 ! 0
  nodes(0)\Child1 = $8000 ! 1
  nodes(1)\OriginX = 0
  nodes(1)\OriginY = 0
  nodes(1)\DX = 0
  nodes(1)\DY = 1
  nodes(1)\Child0 = 0
  nodes(1)\Child1 = $8000 ! 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @nodes(0), 2, 2) <> 0), "two-node tree built")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera created")
  *item = level\Nodes\Items + 1 * SizeOf(MapNode)
  *item\Child0 = 5000
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "externally corrupted child-node index rejected")
  Check(Bool(BspTraceCount(@trace) = 0), "corrupt node child leaves no events")
  Check(Bool(Len(BspTraceLastError()) > 0), "corrupt node child produces a diagnostic")
  MapLevelReset(@level)
EndProcedure

Procedure TestB28()
  BeginCase("B28", "Invalid child-subsector index test object fails safely")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)
  Protected Dim nodes.TestNodeSpec(1)
  Protected *item.MapNode

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Child0 = $8000 ! 0
  nodes(0)\Child1 = $8000 ! 1
  nodes(1)\OriginX = 0
  nodes(1)\OriginY = 0
  nodes(1)\DX = 0
  nodes(1)\DY = 1
  nodes(1)\Child0 = $8000 ! 0
  nodes(1)\Child1 = $8000 ! 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @nodes(0), 2, 2) <> 0), "two-node tree built")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera created")
  *item = level\Nodes\Items + 1 * SizeOf(MapNode)
  *item\Child0 = $8000 ! 5
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "externally corrupted child-subsector index rejected")
  Check(Bool(BspTraceCount(@trace) = 0), "corrupt leaf child leaves no events")
  Check(Bool(Len(BspTraceLastError()) > 0), "corrupt leaf child produces a diagnostic")
  MapLevelReset(@level)
EndProcedure

Procedure TestB29()
  BeginCase("B29", "Self-cycle test object rejected by M2 as documented")
  Protected level.MapLevel
  Protected Dim subs.TestSubSpec(0)
  Protected node.TestNodeSpec

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  node\OriginX = 0
  node\OriginY = 0
  node\DX = 0
  node\DY = 1
  node\Child0 = 0
  node\Child1 = $8000 ! 0
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, @node, 1, 1) = 0), "self-cycle node graph rejected")
  Check(Bool(Len(MapLevelLastError()) > 0), "self-cycle rejection reports a diagnostic")
  Check(Bool(MapLevelIsReady(@level) = 0), "cycle rejection never publishes a ready level")
  MapLevelReset(@level)
EndProcedure

Procedure TestB30()
  BeginCase("B30", "Two-node cycle test object rejected by M2 as documented")
  Protected level.MapLevel
  Protected Dim subs.TestSubSpec(0)
  Protected Dim nodes.TestNodeSpec(1)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  nodes(0)\OriginX = 0
  nodes(0)\OriginY = 0
  nodes(0)\DX = 0
  nodes(0)\DY = 1
  nodes(0)\Child0 = 1
  nodes(0)\Child1 = $8000 ! 0
  nodes(1)\OriginX = 0
  nodes(1)\OriginY = 0
  nodes(1)\DX = 0
  nodes(1)\DY = 1
  nodes(1)\Child0 = 0
  nodes(1)\Child1 = $8000 ! 0
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, @nodes(0), 2, 1) = 0), "two-node cycle graph rejected")
  Check(Bool(Len(MapLevelLastError()) > 0), "two-node cycle rejection reports a diagnostic")
  Check(Bool(MapLevelIsReady(@level) = 0), "two-node cycle never publishes a ready level")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; B31-B33: deep iterative traversal, independent LIFO oracle, heading neutrality
; ---------------------------------------------------------------------------

Procedure TestB31()
  BeginCase("B31", "Deep skewed tree traversed iteratively without recursion")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(300)
  Protected Dim nodes.TestNodeSpec(299)
  Protected i.i
  Protected count.i
  Protected subsector.l = -1
  Protected first.l = -1
  Protected second.l = -1
  Protected last.l = -1

  For i = 0 To 300
    subs(i)\FirstSeg = 0
    subs(i)\NumSegs = 1
  Next
  For i = 0 To 299
    nodes(i)\OriginX = 0
    nodes(i)\OriginY = 0
    nodes(i)\DX = 0
    nodes(i)\DY = 1
    nodes(i)\Child0 = $8000 ! i
    If i = 0
      nodes(i)\Child1 = $8000 ! 300
    Else
      nodes(i)\Child1 = i - 1
    EndIf
  Next

  Check(Bool(TestBuildLevel(@level, @subs(0), 301, @nodes(0), 300, 1) <> 0), "300-node/301-leaf skewed tree built")
  Check(Bool(level\BspRootIndex = 299), "deep fixture root is last node 299")
  Check(Bool(level\ReachableNodes = 300 And level\ReachableSubsectors = 301),
        "validator proves the complete deep chain reachable")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera fixed to consistent back side")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "iterative build succeeds at depth 300 without recursion failure")
  count = BspTraceCount(@trace)
  Check(Bool(count = 301 * 2), "301 leaf visits and one seg each produce 602 events")
  Check(Bool(trace\VisitedNodes = 300 And trace\VisitedSubsectors = 301 And
        trace\EmittedSegs = 301 And trace\WorkItems > 0),
        "deep counters record all nodes, leaves, segs and explicit work items")
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 300), "deepest near leaf 300 is first")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 0), "deepest far leaf 0 is second")
  Check(Bool(TestSubOrder(@trace, count - 2, @last) <> 0 And last = 299), "shallow root far leaf 299 is last")
  For i = 2 To 300
    subsector = -1
    Check(Bool(TestSubOrder(@trace, i * 2, @subsector) <> 0 And subsector = i - 1),
          "pending far leaves 1..299 pop in deterministic ancestor order at slot " + Str(i))
  Next
  MapLevelReset(@level)
EndProcedure

Procedure TestB32()
  BeginCase("B32", "Near/far LIFO push order proven against independent recursive oracle")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected i.i
  Protected productionCount.i
  Protected productionKind.l
  Protected productionSub.l
  Protected productionSeg.l
  Protected ok.i

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera A created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "production iterative trace succeeds")
  productionCount = BspTraceCount(@trace)

  TestRefClear()
  Check(Bool(TestRefWalk(@level, level\BspRootIndex, -65536, 0, 0) <> 0),
        "test-only recursive reference interpreter completes")
  Check(Bool(gRefCount = 8), "reference oracle emits eight chronological events")
  Check(Bool(productionCount = gRefCount), "production event count equals independent oracle")
  For i = 0 To gRefCount - 1
    productionKind = -1
    productionSub = -1
    productionSeg = -1
    ok = BspTraceGet(@trace, i, @productionKind, @productionSub, @productionSeg,
                    0, 0, 0, 0, 0)
    Check(Bool(ok <> 0 And productionKind = gRefKind(i) And
          productionSub = gRefSubsector(i) And productionSeg = gRefSeg(i)),
          "production LIFO event slot " + Str(i) + " matches recursive oracle")
  Next
  MapLevelReset(@level)
EndProcedure

Procedure TestB33()
  BeginCase("B33", "Camera BAM heading change alone does not change unculled walk")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected hashA.q
  Protected hashB.q
  Protected countA.l = -1
  Protected countB.l = -1
  Protected heading.q = 0

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG45) <> 0), "camera with ANG45 heading created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "ANG45 trace build succeeds")
  hashA = TestTraceHash(@trace, @countA)
  Check(Bool(countA = 8), "ANG45 trace has eight published events")

  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG180) <> 0), "same X/Y with ANG180 heading created")
  Check(Bool(BspCameraGet(@camera, 0, 0, @heading) <> 0 And heading = #BAM_ANG180),
        "ANG180 heading stored as exact unsigned raw value")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "ANG180 heading trace build succeeds")
  hashB = TestTraceHash(@trace, @countB)
  Check(Bool(countB = countA), "heading change keeps identical event count")
  Check(Bool(hashB = hashA), "heading change alone leaves cull-free BSP walk unchanged")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; B34-B38: camera map-unit/fixed/BAM representation and overflow rules
; ---------------------------------------------------------------------------

Procedure TestB34()
  BeginCase("B34", "Camera map-unit-to-fixed positive conversion exact")
  Protected camera.BspCamera
  Protected x.l = -1
  Protected y.l = -1
  Protected heading.q = 0

  Check(Bool(BspCameraSetMapUnits(@camera, 1, 2, #BAM_ANG90) <> 0), "positive map-unit camera created")
  Check(Bool(BspCameraGet(@camera, @x, @y, @heading) <> 0), "camera accessor succeeds")
  Check(Bool(x = 65536), "X map 1 -> exact fixed 65536")
  Check(Bool(y = 131072), "Y map 2 -> exact fixed 131072")
  Check(Bool(heading = #BAM_ANG90), "ANG90 heading preserved as raw 0x40000000")
EndProcedure

Procedure TestB35()
  BeginCase("B35", "Camera map-unit-to-fixed negative conversion exact")
  Protected camera.BspCamera
  Protected x.l = 0
  Protected y.l = 0
  Protected heading.q = 0

  Check(Bool(BspCameraSetMapUnits(@camera, -1, -2, #BAM_ANG270) <> 0), "negative map-unit camera created")
  Check(Bool(BspCameraGet(@camera, @x, @y, @heading) <> 0), "camera accessor succeeds")
  Check(Bool(x = -65536), "X map -1 -> exact fixed -65536")
  Check(Bool(y = -131072), "Y map -2 -> exact fixed -131072")
  Check(Bool(heading = #BAM_ANG270), "ANG270 heading preserved as unsigned 0xC0000000")
EndProcedure

Procedure TestB36()
  BeginCase("B36", "Camera conversion rejects out-of-range map units transactionally")
  Protected camera.BspCamera
  Protected x.l = 0
  Protected y.l = 0
  Protected heading.q = 0
  Protected beforeX.l
  Protected beforeY.l
  Protected beforeHeading.q

  Check(Bool(BspCameraSetMapUnits(@camera, 1, 2, #BAM_ANG90) <> 0), "baseline camera created")
  beforeX = 0
  beforeY = 0
  beforeHeading = 0
  Check(Bool(BspCameraGet(@camera, @beforeX, @beforeY, @beforeHeading) <> 0), "baseline snapshot succeeds")
  Check(Bool(BspCameraSetMapUnits(@camera, 32768, 0, #BAM_ANG90) = 0), "map-unit 32768 is rejected")
  Check(Bool(Len(BspCameraLastError()) > 0), "out-of-range map unit reports a diagnostic")
  x = 0
  y = 0
  heading = 0
  Check(Bool(BspCameraGet(@camera, @x, @y, @heading) <> 0), "camera still readable after rejected setter")
  Check(Bool(x = beforeX And y = beforeY And heading = beforeHeading),
        "rejected conversion left the previous camera unchanged")
EndProcedure

Procedure TestB37()
  BeginCase("B37", "Camera preserves raw BAM ANG180/ANG270 as unsigned values")
  Protected camera.BspCamera
  Protected heading.q = 0
  Protected x.l = 0
  Protected y.l = 0

  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG180) <> 0), "ANG180 camera created")
  heading = 0
  Check(Bool(BspCameraGet(@camera, @x, @y, @heading) <> 0), "ANG180 camera accessor succeeds")
  Check(Bool(heading = 2147483648), "ANG180 raw bit pattern is 2147483648, not a negative .l")

  Check(Bool(BspCameraSetMapUnits(@camera, 0, 0, #BAM_ANG270) <> 0), "ANG270 camera created")
  heading = 0
  Check(Bool(BspCameraGet(@camera, @x, @y, @heading) <> 0), "ANG270 camera accessor succeeds")
  Check(Bool(heading = 3221225472), "ANG270 raw bit pattern is 3221225472")
EndProcedure

Procedure TestB38()
  BeginCase("B38", "Signed map-coordinate endpoints -32768/32767 convert exactly to 16.16")
  Protected camera.BspCamera
  Protected x.l = 0
  Protected y.l = 0
  Protected heading.q = 0

  Check(Bool(BspCameraSetMapUnits(@camera, -32768, 32767, #BAM_ANG45) <> 0),
        "absolute signed map endpoints accepted")
  Check(Bool(BspCameraGet(@camera, @x, @y, @heading) <> 0), "endpoint camera accessor succeeds")
  Check(Bool(x = -2147483648), "map -32768 -> exact fixed INT32_MIN")
  Check(Bool(y = 2147418112), "map 32767 -> exact fixed 32767*65536")
  Check(Bool(heading = #BAM_ANG45), "endpoint heading remains canonical raw BAM")
EndProcedure

; ---------------------------------------------------------------------------
; B39-B48: geometry overflow, determinism, lifetime, reset, accessor and budgets
; ---------------------------------------------------------------------------

Procedure TestB39()
  BeginCase("B39", "M3-02 geometry overflow returns error and clears partial trace")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)
  Protected node.TestNodeSpec

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  node\OriginX = -32768
  node\OriginY = 0
  node\DX = 1
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @node, 1, 2) <> 0), "extreme-origin one-node tree built")
  Check(Bool(BspCameraSetFixed(@camera, 2147483647, 0, #BAM_ANG90) <> 0),
        "camera at signed fixed maximum created directly")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "delta overflow in node side classification rejects the build")
  Check(Bool(BspTraceCount(@trace) = 0), "geometry overflow leaves a transactional empty trace")
  Check(Bool(Len(BspTraceLastError()) > 0), "geometry overflow reports actionable diagnostics")
  Check(Bool(BspCameraGet(@camera, 0, 0, 0) <> 0), "camera remains usable/unchanged after failure")
  Check(Bool(MapLevelIsReady(@level) <> 0), "level remains ready and unmutated after failure")
  MapLevelReset(@level)
EndProcedure

Procedure TestB40()
  BeginCase("B40", "Repeated same camera + level yields identical events/checksum")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected firstHash.q
  Protected secondHash.q
  Protected firstCount.l = -1
  Protected secondCount.l = -1

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "deterministic camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "first trace build succeeds")
  firstHash = TestTraceHash(@trace, @firstCount)
  Check(Bool(firstCount = 8), "first trace publishes eight events")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "second trace build succeeds")
  secondHash = TestTraceHash(@trace, @secondCount)
  Check(Bool(secondCount = firstCount), "second trace publishes the same event count")
  Check(Bool(secondHash = firstHash), "canonical event checksum repeats exactly")
  MapLevelReset(@level)
EndProcedure

Procedure TestB41()
  BeginCase("B41", "Distinct camera positions yield expected reordering")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected hashA.q
  Protected hashB.q
  Protected countA.l = -1
  Protected countB.l = -1
  Protected first.l = -1
  Protected second.l = -1

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera A created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "camera A trace succeeds")
  hashA = TestTraceHash(@trace, @countA)
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 3), "camera A order starts leaf3")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 2), "camera A second leaf2")

  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera B created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "camera B trace succeeds")
  hashB = TestTraceHash(@trace, @countB)
  Check(Bool(TestSubOrder(@trace, 0, @first) <> 0 And first = 0), "camera B order starts leaf0")
  Check(Bool(TestSubOrder(@trace, 2, @second) <> 0 And second = 1), "camera B second leaf1")
  Check(Bool(countB = countA), "both camera positions publish same count")
  Check(Bool(hashB <> hashA), "distinct BSP orders produce distinct checksums")
  MapLevelReset(@level)
EndProcedure

Procedure TestB42()
  BeginCase("B42", "Trace reset is idempotent; count becomes zero")
  Protected trace.BspTrace

  Check(Bool(BspTraceReset(@trace) <> 0), "fresh trace reset succeeds")
  Check(Bool(BspTraceCount(@trace) = 0), "fresh reset trace is a valid empty object")
  Check(Bool(BspTraceReset(@trace) <> 0), "second reset of empty trace succeeds")
  Check(Bool(BspTraceCount(@trace) = 0), "second reset keeps count zero")
  Check(Bool(trace\Events = 0 And trace\Capacity = 0), "reset releases and zeroes owned storage")
  Check(Bool(Len(BspTraceLastError()) = 0), "successful reset clears error state")
EndProcedure

Procedure TestB43()
  BeginCase("B43", "Failed build after successful build clears stale events")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected count.i

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "first successful build publishes events")
  count = BspTraceCount(@trace)
  Check(Bool(count = 8), "successful trace had eight events")
  level\BspRootIndex = 99
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "camera/root failure rejects the second build")
  Check(Bool(BspTraceCount(@trace) = 0), "failed rebuild cleared every stale event")
  Check(Bool(Len(BspTraceLastError()) > 0), "failed rebuild reports a diagnostic rather than stale success state")
  MapLevelReset(@level)
EndProcedure

Procedure TestB44()
  BeginCase("B44", "Success after failure clears prior error and works normally")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(1)
  Protected node.TestNodeSpec

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  subs(1)\FirstSeg = 1
  subs(1)\NumSegs = 1
  node\OriginX = -32768
  node\OriginY = 0
  node\DX = 1
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 1
  Check(Bool(TestBuildLevel(@level, @subs(0), 2, @node, 1, 2) <> 0), "overlap fixture level built")
  Check(Bool(BspCameraSetFixed(@camera, 2147483647, 0, #BAM_ANG90) <> 0), "failing extreme camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) = 0), "first build fails on geometry overflow")
  Check(Bool(Len(BspTraceLastError()) > 0), "failure error state is populated")
  Check(Bool(BspCameraSetMapUnits(@camera, -32768, 0, #BAM_ANG90) <> 0), "recoverable coincident-origin camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "second build succeeds normally")
  Check(Bool(Len(BspTraceLastError()) = 0), "successful build clears the prior error")
  Check(Bool(BspTraceCount(@trace) = 4), "recovered trace publishes two leaves and two segs")
  MapLevelReset(@level)
EndProcedure

Procedure TestB45()
  BeginCase("B45", "Trace remains inspectable after source MapLevel reset")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected countBefore.i
  Protected hashBefore.q
  Protected countAfter.i
  Protected hashAfter.q
  Protected hashCount.l = -1
  Protected subsector.l = -1
  Protected kind.l = -1

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  countBefore = BspTraceCount(@trace)
  hashBefore = TestTraceHash(@trace, @hashCount)
  Check(Bool(countBefore = 8 And hashCount = 8), "owned trace has eight events")
  Check(Bool(MapLevelReset(@level) <> 0), "source MapLevel reset succeeds")
  Check(Bool(MapLevelIsReady(@level) = 0), "source level is no longer ready")
  countAfter = BspTraceCount(@trace)
  hashAfter = TestTraceHash(@trace, @hashCount)
  Check(Bool(countAfter = countBefore), "trace count survives level reset")
  Check(Bool(hashAfter = hashBefore), "trace numeric data survives level reset unchanged")
  Check(Bool(BspTraceGet(@trace, 7, @kind, @subsector, 0, 0, 0, 0, 0, 0) <> 0 And kind = #BSP_EventSeg),
        "last owned seg event stays readable after level reset")
EndProcedure

Procedure TestB46()
  BeginCase("B46", "Accessor rejects negative index and count-boundary index")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected count.i
  Protected kind.l = 0
  Protected subsector.l = 0

  Check(Bool(TestBuildNestedTree(@level) <> 0), "nested tree level built")
  Check(Bool(BspCameraSetMapUnits(@camera, -1, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "trace build succeeds")
  count = BspTraceCount(@trace)
  Check(Bool(count = 8), "trace has eight events")
  Check(Bool(BspTraceGet(@trace, -1, @kind, @subsector, 0, 0, 0, 0, 0, 0) = 0),
        "negative event index rejected")
  Check(Bool(Len(BspTraceLastError()) > 0), "negative index produces a diagnostic")
  kind = -1
  subsector = -1
  Check(Bool(BspTraceGet(@trace, count, @kind, @subsector, 0, 0, 0, 0, 0, 0) = 0),
        "count-boundary event index rejected")
  Check(Bool(kind = -1 And subsector = -1), "rejected accessor wrote no partial output")
  kind = -1
  subsector = -1
  Check(Bool(BspTraceGet(@trace, count - 1, @kind, @subsector, 0, 0, 0, 0, 0, 0) <> 0),
        "last valid event index remains readable")
  Check(Bool(kind = #BSP_EventSeg), "last valid event is a SEG record")
  MapLevelReset(@level)
EndProcedure

Procedure TestB47()
  BeginCase("B47", "Shared-child DAG repeats deterministically under budget")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)
  Protected node.TestNodeSpec
  Protected i.i
  Protected count.i
  Protected kind.l = 0
  Protected subsector.l = 0
  Protected seg.l = 0
  Protected hashFirst.q
  Protected hashSecond.q
  Protected countFirst.l = -1
  Protected countSecond.l = -1
  Protected Dim expectedKind.l(3)
  Protected Dim expectedSub.l(3)
  Protected Dim expectedSeg.l(3)

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  node\OriginX = 0
  node\OriginY = 0
  node\DX = 0
  node\DY = 1
  node\Child0 = $8000 ! 0
  node\Child1 = $8000 ! 0
  expectedKind(0) = #BSP_EventSubsector
  expectedSub(0) = 0
  expectedSeg(0) = -1
  expectedKind(1) = #BSP_EventSeg
  expectedSub(1) = 0
  expectedSeg(1) = 0
  expectedKind(2) = #BSP_EventSubsector
  expectedSub(2) = 0
  expectedSeg(2) = -1
  expectedKind(3) = #BSP_EventSeg
  expectedSub(3) = 0
  expectedSeg(3) = 0

  Check(Bool(TestBuildLevel(@level, @subs(0), 1, @node, 1, 1) <> 0), "shared-child DAG accepted by M2 validator")
  Check(Bool(MapLevelIsReady(@level) <> 0 And level\ReachableSubsectors = 1),
        "validator counts the shared leaf once as reachable")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera created")
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "DAG traversal succeeds under budgets")
  count = BspTraceCount(@trace)
  Check(Bool(count = 4), "both child occurrences repeat the same leaf and seg")
  For i = 0 To 3
    kind = -1
    subsector = -1
    seg = -1
    Check(Bool(BspTraceGet(@trace, i, @kind, @subsector, @seg, 0, 0, 0, 0, 0) <> 0),
          "DAG event slot " + Str(i) + " readable")
    Check(Bool(kind = expectedKind(i) And subsector = expectedSub(i) And seg = expectedSeg(i)),
          "DAG event slot " + Str(i) + " deterministically repeats original occurrence")
  Next
  Check(Bool(trace\VisitedNodes = 1 And trace\VisitedSubsectors = 2),
        "one node occurrence visits the shared leaf twice, not silently skipped")
  hashFirst = TestTraceHash(@trace, @countFirst)
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0), "second DAG build succeeds")
  hashSecond = TestTraceHash(@trace, @countSecond)
  Check(Bool(countFirst = countSecond And hashFirst = hashSecond),
        "repeated DAG builds produce identical counts and checksums")
  MapLevelReset(@level)
EndProcedure

Procedure TestB48()
  BeginCase("B48", "Artificial event/work budget exhausted safely (no hang/OOM)")
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected Dim subs.TestSubSpec(0)
  Protected Dim nodes.TestNodeSpec(19)
  Protected i.i
  Protected buildOk.i

  subs(0)\FirstSeg = 0
  subs(0)\NumSegs = 1
  For i = 0 To 19
    nodes(i)\OriginX = 0
    nodes(i)\OriginY = 0
    nodes(i)\DX = 0
    nodes(i)\DY = 1
    If i = 0
      nodes(i)\Child0 = $8000 ! 0
      nodes(i)\Child1 = $8000 ! 0
    Else
      nodes(i)\Child0 = i - 1
      nodes(i)\Child1 = i - 1
    EndIf
  Next
  Check(Bool(TestBuildLevel(@level, @subs(0), 1, @nodes(0), 20, 1) <> 0),
        "20-node cycle-free doubling DAG accepted by M2 validator")
  Check(Bool(MapLevelIsReady(@level) <> 0 And level\ReachableNodes = 20 And
        level\ReachableSubsectors = 1),
        "validator records unique reachable nodes without rejecting sharing")
  Check(Bool(BspCameraSetMapUnits(@camera, 1, 0, #BAM_ANG90) <> 0), "camera created")
  buildOk = BspTraceBuild(@level, @camera, @trace)
  Check(Bool(buildOk = 0), "exponential repeated paths terminate with a controlled failure")
  Check(Bool(BspTraceCount(@trace) = 0), "budget failure publishes zero partial events")
  Check(Bool(Len(BspTraceLastError()) > 0), "budget failure reports a diagnostic")
  Check(Bool(trace\OcclusionSkips = 0 And trace\WorkItems = 0),
        "failed reset has no occlusion skips and publishes no lingering work state")
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-03 deterministic BSP traversal unit tests (B01-B48)")

TestB01()
TestB02()
TestB03()
TestB04()
TestB05()
TestB06()
TestB07()
TestB08()
TestB09()
TestB10()
TestB11()
TestB12()
TestB13()
TestB14()
TestB15()
TestB16()
TestB17()
TestB18()
TestB19()
TestB20()
TestB21()
TestB22()
TestB23()
TestB24()
TestB25()
TestB26()
TestB27()
TestB28()
TestB29()
TestB30()
TestB31()
TestB32()
TestB33()
TestB34()
TestB35()
TestB36()
TestB37()
TestB38()
TestB39()
TestB40()
TestB41()
TestB42()
TestB43()
TestB44()
TestB45()
TestB46()
TestB47()
TestB48()

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
