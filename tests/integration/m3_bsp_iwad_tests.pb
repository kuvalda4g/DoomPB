; -----------------------------------------------------------------------------
; DoomPB - M3-03 optional real-IWAD deterministic BSP integration (I04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Optional harness; the owner-provided legal IWAD path is its first argument
; (same convention as M2/M3-01/M3-02 I04). Reads strictly read-only, loads E1M1,
; E1M2 and E4M1 through the existing validated M2 MapLevel APIs, chooses a fixed
; camera from the first player-one THING start converted with
; FixedFromIntChecked (or vertex 0 as a documented fallback), stores heading as
; the original P_SpawnPlayer-style raw BAM value, then walks the complete BSP
; tree with culling disabled (R_CheckBBox deferred).
;
; For each normal vanilla tree the trace must visit every reachable subsector
; once, emit every segment of those leaves exactly once, visit every node once,
; emit no duplicate/missing event indices and report zero occlusion skips.
; Expected reachable subsector/seg totals are cross-checked against historic M2
; measurements (not imposed as a generic loader rule). Repeat traces must yield
; identical canonical FNV-1a64 fingerprints.
;
; The IWAD is opened only through WADOpen (no writes). Before/after MD5 and file
; size are compared to verify the file is unchanged; its MD5 may be printed for
; identification but a different legal IWAD hash is never rejected by this
; harness. Only coarse totals and non-reconstructable hashes are printed: no map
; geometry coordinates, entire record lists, WAD payload bytes, graphics,
; textures, sprites or screenshots are stored, copied or published.
;
; Without a path argument I04 is reported NOT RUN; that is not failure.
; Exit code: 0 when every assertion passed (or NOT RUN), else failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/BSP.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"

#IWAD_FNV_Offset = -3750763034362895579
#IWAD_FNV_Prime = 1099511628211

; Project policy only: a bound on the optional read-only fingerprint buffer.
#IWAD_Md5MaxBytes = 268435456

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

Structure BspMapStats
  Loaded.l
  PlayerThingStart.l
  SubsectorEvents.q
  SegEvents.q
  EventTotal.q
  DuplicateSubsector.q
  DuplicateSeg.q
  MissingSubsector.q
  MissingSeg.q
  VisitedNodes.l
  VisitedSubsectors.l
  EmittedSegs.l
  OcclusionSkips.l
  Hash.q
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
  Hash = Hash * #IWAD_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvAddByte(Hash, Value & $FF)
  Hash = FnvAddByte(Hash, (Value >> 8) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 16) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

; Widened integer sum helper for the checked 64-bit event-total reconciliation.
Procedure.q Int64Sum(A.l, B.l)
  Protected wideA.q = A
  Protected wideB.q = B

  ProcedureReturn wideA + wideB
EndProcedure

Procedure.q TestTraceHash(*Trace.BspTrace, *EventCount.Long)
  Protected hash.q = #IWAD_FNV_Offset
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
; Optional read-only file fingerprint (verification only)
; ---------------------------------------------------------------------------

Procedure.s TestFileMd5(Path.s)
  Protected fileSize.q
  Protected bytes.i
  Protected readCount.i
  Protected file.i
  Protected fingerprint.s

  fileSize = FileSize(Path)
  If fileSize < 0 Or fileSize > #IWAD_Md5MaxBytes
    ProcedureReturn ""
  EndIf
  bytes = AllocateMemory(fileSize)
  If bytes = 0
    ProcedureReturn ""
  EndIf
  file = ReadFile(#PB_Any, Path)
  If file = 0
    FreeMemory(bytes)
    ProcedureReturn ""
  EndIf
  readCount = ReadData(file, bytes, fileSize)
  CloseFile(file)
  If readCount <> fileSize
    FreeMemory(bytes)
    ProcedureReturn ""
  EndIf
  UseMD5Fingerprint()
  fingerprint = Fingerprint(bytes, fileSize, #PB_Cipher_MD5)
  FreeMemory(bytes)
  ProcedureReturn fingerprint
EndProcedure

; ---------------------------------------------------------------------------
; Fixed camera selection from validated map data
; ---------------------------------------------------------------------------

; Original P_SpawnPlayer (p_mobj.c) sets the THING start heading as
; `mobj->angle = ANG45 * (mthing->angle/45)` with integer division truncation.
; The same raw unsigned BAM value is stored here; traversal itself ignores the
; heading until future projection work. Player-one THING coordinates are signed
; map units converted through FixedFromIntChecked.
Procedure.i TestChooseCamera(*Level.MapLevel, *Camera.BspCamera, *PlayerThing.Long)
  Protected thingCount.i
  Protected i.i
  Protected x.l
  Protected y.l
  Protected angle.l
  Protected type.l
  Protected options.l
  Protected quotient.l
  Protected wideQuotient.q
  Protected rawHeading.q
  Protected vertexX.l = 0
  Protected vertexY.l = 0

  *PlayerThing\l = 0
  thingCount = MapThingsCount(@*Level\Things)
  For i = 0 To thingCount - 1
    If MapThingsGet(@*Level\Things, i, @x, @y, @angle, @type, @options) = #False
      Continue
    EndIf
    If type = 1
      quotient = angle / 45
      wideQuotient = quotient
      rawHeading = BamWrap32(#BAM_ANG45 * wideQuotient)
      If BspCameraSetMapUnits(*Camera, x, y, rawHeading) = #False
        BspSetError("player-start camera rejected: " + BspCameraLastError())
        ProcedureReturn #False
      EndIf
      *PlayerThing\l = 1
      ProcedureReturn #True
    EndIf
  Next

  ; Documented fallback: vertex 0 in signed map units, canonical ANG90 heading.
  If MapVertexesGet(@*Level\Vertexes, 0, @vertexX, @vertexY) = #False
    BspSetError("cannot read fallback vertex 0: " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If BspCameraSetMapUnits(*Camera, vertexX, vertexY, #BAM_ANG90) = #False
    BspSetError("fallback vertex camera rejected: " + BspCameraLastError())
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Per-map measurement
; ---------------------------------------------------------------------------

Procedure.i MeasureBspMap(Name.s, *Stats.BspMapStats)
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected playerThing.l = 0
  Protected cameraOk.i
  Protected traceOk.i
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
  Protected subCount.i
  Protected segCount.i
  Protected *subSeen.Byte = 0
  Protected *segSeen.Byte = 0
  Protected value.i
  Protected resetOk.i
  Protected hash.q
  Protected eventCount.l = -1
  Protected failure.i = 0

  *Stats\Loaded = 0
  *Stats\PlayerThingStart = 0
  *Stats\SubsectorEvents = 0
  *Stats\SegEvents = 0
  *Stats\EventTotal = 0
  *Stats\DuplicateSubsector = 0
  *Stats\DuplicateSeg = 0
  *Stats\MissingSubsector = 0
  *Stats\MissingSeg = 0
  *Stats\VisitedNodes = 0
  *Stats\VisitedSubsectors = 0
  *Stats\EmittedSegs = 0
  *Stats\OcclusionSkips = 0
  *Stats\Hash = 0

  If MapLevelLoad(Name, @level) = #False
    MapLevelReset(@level)
    ProcedureReturn #False
  EndIf
  *Stats\Loaded = 1

  cameraOk = TestChooseCamera(@level, @camera, @playerThing)
  If cameraOk = #False
    MapLevelReset(@level)
    ProcedureReturn #False
  EndIf
  *Stats\PlayerThingStart = playerThing

  traceOk = BspTraceBuild(@level, @camera, @trace)
  If traceOk = #False
    MapLevelReset(@level)
    ProcedureReturn #False
  EndIf

  count = BspTraceCount(@trace)
  If count < 0
    *Stats\Loaded = 0
    MapLevelReset(@level)
    BspTraceReset(@trace)
    ProcedureReturn #False
  EndIf
  subCount = level\Subsectors\Count
  segCount = level\Segs\Count
  If subCount <= 0 Or segCount <= 0 Or count > 3000000
    *Stats\Loaded = 0
    MapLevelReset(@level)
    BspTraceReset(@trace)
    ProcedureReturn #False
  EndIf

  *subSeen = AllocateMemory(subCount)
  *segSeen = AllocateMemory(segCount)
  If *subSeen = 0 Or *segSeen = 0
    If *subSeen <> 0
      FreeMemory(*subSeen)
    EndIf
    If *segSeen <> 0
      FreeMemory(*segSeen)
    EndIf
    *Stats\Loaded = 0
    MapLevelReset(@level)
    BspTraceReset(@trace)
    ProcedureReturn #False
  EndIf
  FillMemory(*subSeen, subCount, 0)
  FillMemory(*segSeen, segCount, 0)

  hash = #IWAD_FNV_Offset
  For i = 0 To count - 1
    kind = 0
    subsector = 0
    seg = 0
    sector = 0
    linedef = 0
    side = 0
    front = 0
    back = 0
    If BspTraceGet(@trace, i, @kind, @subsector, @seg, @sector,
                   @linedef, @side, @front, @back) = #False
      failure = 1
      Break
    EndIf
    hash = FnvAddLong(hash, kind)
    hash = FnvAddLong(hash, subsector)
    hash = FnvAddLong(hash, seg)
    hash = FnvAddLong(hash, sector)
    hash = FnvAddLong(hash, linedef)
    hash = FnvAddLong(hash, side)
    hash = FnvAddLong(hash, front)
    hash = FnvAddLong(hash, back)
    If kind = #BSP_EventSubsector
      *Stats\SubsectorEvents + 1
      If subsector < 0 Or subsector >= subCount
        failure = 1
        Break
      EndIf
      value = PeekA(*subSeen + subsector)
      If value = 0
        PokeA(*subSeen + subsector, 1)
      Else
        *Stats\DuplicateSubsector + 1
      EndIf
    ElseIf kind = #BSP_EventSeg
      *Stats\SegEvents + 1
      If seg < 0 Or seg >= segCount
        failure = 1
        Break
      EndIf
      value = PeekA(*segSeen + seg)
      If value = 0
        PokeA(*segSeen + seg, 1)
      Else
        *Stats\DuplicateSeg + 1
      EndIf
    Else
      failure = 1
      Break
    EndIf
  Next

  If failure = 0
    For i = 0 To subCount - 1
      If PeekA(*subSeen + i) = 0
        *Stats\MissingSubsector + 1
      EndIf
    Next
    For i = 0 To segCount - 1
      If PeekA(*segSeen + i) = 0
        *Stats\MissingSeg + 1
      EndIf
    Next
    *Stats\EventTotal = *Stats\SubsectorEvents + *Stats\SegEvents
    *Stats\VisitedNodes = trace\VisitedNodes
    *Stats\VisitedSubsectors = trace\VisitedSubsectors
    *Stats\EmittedSegs = trace\EmittedSegs
    *Stats\OcclusionSkips = trace\OcclusionSkips
    *Stats\Hash = hash
  Else
    *Stats\Loaded = 0
  EndIf

  FreeMemory(*subSeen)
  FreeMemory(*segSeen)
  resetOk = MapLevelReset(@level)
  If resetOk = #False
    *Stats\Loaded = 0
  EndIf
  BspTraceReset(@trace)
  ProcedureReturn Bool(*Stats\Loaded <> 0)
EndProcedure

; ---------------------------------------------------------------------------
; I04 optional owner IWAD pass
; ---------------------------------------------------------------------------

Procedure CheckBspMap(Name.s, ExpectedSubsectors.l, ExpectedSegs.l, ExpectedNodes.l)
  Protected first.BspMapStats
  Protected second.BspMapStats
  Protected loadedFirst.i
  Protected loadedSecond.i

  loadedFirst = MeasureBspMap(Name, @first)
  Check(Bool(loadedFirst <> 0 And first\Loaded <> 0), Name + " loads through validated MapLevel API")
  Check(Bool(first\PlayerThingStart <> 0), Name + " fixed camera derived from validated player-one THING start")
  Check(Bool(first\SubsectorEvents = ExpectedSubsectors),
        Name + " visits the expected reachable subsector count " + Str(ExpectedSubsectors))
  Check(Bool(first\SegEvents = ExpectedSegs),
        Name + " emits the expected segment records " + Str(ExpectedSegs))
  Check(Bool(first\EventTotal = Int64Sum(ExpectedSubsectors, ExpectedSegs)),
        Name + " chronological SUBSECTOR/SEG total reconciles")
  Check(Bool(first\DuplicateSubsector = 0 And first\DuplicateSeg = 0),
        Name + " normal tree emits no duplicate leaf or seg occurrence")
  Check(Bool(first\MissingSubsector = 0 And first\MissingSeg = 0),
        Name + " every reachable subsector and every leaf segment is emitted")
  Check(Bool(first\VisitedNodes = ExpectedNodes),
        Name + " every BSP node is traversed exactly once at expected node count " + Str(ExpectedNodes))
  Check(Bool(first\VisitedSubsectors = first\SubsectorEvents And
        first\EmittedSegs = first\SegEvents),
        Name + " traversal counters reconcile with published event totals")
  Check(Bool(first\OcclusionSkips = 0), Name + " M3-03 reports zero R_CheckBBox occlusion skips")

  loadedSecond = MeasureBspMap(Name, @second)
  Check(Bool(loadedSecond <> 0 And second\Loaded <> 0), Name + " reloads for reproducibility")
  Check(Bool(first\Hash = second\Hash), Name + " canonical FNV-1a64 trace checksum repeats identically")
  Check(Bool(first\SubsectorEvents = second\SubsectorEvents And
        first\SegEvents = second\SegEvents And
        first\EventTotal = second\EventTotal And
        first\VisitedNodes = second\VisitedNodes And
        first\VisitedSubsectors = second\VisitedSubsectors And
        first\EmittedSegs = second\EmittedSegs And
        first\OcclusionSkips = second\OcclusionSkips And
        first\DuplicateSubsector = second\DuplicateSubsector And
        first\DuplicateSeg = second\DuplicateSeg And
        first\MissingSubsector = second\MissingSubsector And
        first\MissingSeg = second\MissingSeg),
        Name + " coarse deterministic counts repeat identically")

  PrintN("  " + Name + ": player-start camera; subsector events " + Str(first\SubsectorEvents) +
         ", seg events " + Str(first\SegEvents) + ", event total " + Str(first\EventTotal))
  PrintN("    nodes visited " + Str(first\VisitedNodes) + ", leaf/seg counters " +
         Str(first\VisitedSubsectors) + "/" + Str(first\EmittedSegs) +
         ", duplicate/missing subs " + Str(first\DuplicateSubsector) + "/" + Str(first\MissingSubsector) +
         ", duplicate/missing segs " + Str(first\DuplicateSeg) + "/" + Str(first\MissingSeg) +
         ", occlusion skips " + Str(first\OcclusionSkips))
  PrintN("    FNV-1a64 trace " + Hex(first\Hash))
EndProcedure

Procedure TestI04(Path.s)
  Protected beforeSize.q
  Protected afterSize.q
  Protected beforeMd5.s
  Protected afterMd5.s

  If Path = ""
    PrintN("[I04] Optional real Ultimate Doom read-only deterministic BSP integration: NOT RUN (no WAD path argument)")
    ProcedureReturn
  EndIf

  BeginCase("I04", "Optional real Ultimate Doom read-only deterministic BSP integration")
  beforeSize = FileSize(Path)
  Check(Bool(beforeSize > 0), "owner IWAD path reports a positive size before reading")
  beforeMd5 = TestFileMd5(Path)
  Check(Bool(beforeMd5 <> ""), "owner IWAD read-only MD5 fingerprint computed before opening")
  PrintN("  owner IWAD size " + Str(beforeSize) + ", MD5 " + beforeMd5)

  If WADOpen(Path) = #False
    Check(#False, "real IWAD opens read-only: " + WADLastError())
    ProcedureReturn
  EndIf
  Check(#True, "real IWAD opens read-only")
  PrintN("  WAD: " + WADGetPath() + ", lumps " + Str(WADGetLumpCount()))

  CheckBspMap("E1M1", 239, 747, 238)
  CheckBspMap("E1M2", 448, 1463, 447)
  CheckBspMap("E4M1", 196, 695, 195)

  WADClose()
  Check(Bool(WADIsOpen() = #False), "WAD closes cleanly after the read-only pass")
  afterSize = FileSize(Path)
  afterMd5 = TestFileMd5(Path)
  Check(Bool(afterSize = beforeSize), "owner IWAD byte size unchanged after read-only pass")
  Check(Bool(afterMd5 <> "" And afterMd5 = beforeMd5), "owner IWAD MD5 fingerprint unchanged after read-only pass")
  PrintN("  owner IWAD remains unchanged: size " + Str(afterSize) + ", MD5 " + afterMd5)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-03 optional real-IWAD deterministic BSP integration (I04)")

TestI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (I04 may be NOT RUN without a WAD argument)")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
