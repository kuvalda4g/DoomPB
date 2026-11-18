; -----------------------------------------------------------------------------
; DoomPB - M3-02 optional real-IWAD geometry integration (I04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Optional harness, owner-provided IWAD path as its first argument (same
; convention as M2/M3-01 I04). Reads the WAD strictly read-only, loads E1M1,
; E1M2 and E4M1 through the existing M2 validated MapLevel APIs, converts a
; bounded deterministic sample of signed map vertex/node fields through
; FixedFromIntChecked and runs node partition side tests, vertex-pair angles and
; distances. Derived M2 links stay owned by MapLevel; no WAD/buffer pointer is
; retained.
;
; Only totals, sampled counts, controlled failure counts and non-reconstructable
; FNV-1a64 hashes are printed. No coordinates, entire level tables, WAD payload
; bytes, graphics or screenshots are printed, stored or copied. Without a path
; argument I04 is reported NOT RUN and that is not a failure.
;
; Exit code: 0 when every assertion passed (or I04 is NOT RUN), otherwise the
; number of failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"

#IWAD_FNV_Offset = -3750763034362895579
#IWAD_FNV_Prime = 1099511628211
#IWAD_SampleStep = 16

Structure GeometryMapStats
  Loaded.l
  VertexTotal.l
  NodeTotal.l
  VertexSamples.l
  NodeSamples.l
  ConvertedFields.q
  SideCalls.q
  SideFront.q
  SideBack.q
  AngleCalls.q
  DistanceCalls.q
  FailureCount.q
  Hash.q
EndStructure

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

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

Procedure.q FnvAddRaw32(Hash.q, Value.q)
  Protected low.q = Value & $FFFFFFFF

  Hash = FnvAddByte(Hash, low & $FF)
  Hash = FnvAddByte(Hash, (low >> 8) & $FF)
  Hash = FnvAddByte(Hash, (low >> 16) & $FF)
  Hash = FnvAddByte(Hash, (low >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

; Deterministic sample index predicate: fixed step plus first/middle/last, so
; every map is bounded to roughly Count/16 + three records.
Procedure.i IsSampledIndex(Index.l, Count.l, Middle.l)
  If Index = 0 Or Index = Middle Or Index = Count - 1
    ProcedureReturn #True
  EndIf
  ProcedureReturn Bool(Index % #IWAD_SampleStep = 0)
EndProcedure

; ---------------------------------------------------------------------------
; I04 per-map measurement
; ---------------------------------------------------------------------------

; Caller zero-initializes *Stats once. Every field is overwritten per call; the
; level is reset on every path and no pointer is retained after return.
Procedure.i MeasureGeometryMap(Name.s, *Stats.GeometryMapStats)
  Protected level.MapLevel
  Protected vertexCount.i
  Protected nodeCount.i
  Protected middleVertex.i
  Protected middleNode.i
  Protected i.i
  Protected rawX.l = 0
  Protected rawY.l = 0
  Protected rawDX.l = 0
  Protected rawDY.l = 0
  Protected fixedX.l = 0
  Protected fixedY.l = 0
  Protected fixedDX.l = 0
  Protected fixedDY.l = 0
  Protected firstX.l = 0
  Protected firstY.l = 0
  Protected middleX.l = 0
  Protected middleY.l = 0
  Protected lastX.l = 0
  Protected lastY.l = 0
  Protected storeFirst.i = 0
  Protected storeMiddle.i = 0
  Protected storeLast.i = 0
  Protected angleOut.BamAngleValue
  Protected side.l = -123
  Protected distance.l = -7777777
  Protected hash.q = #IWAD_FNV_Offset
  Protected loaded.i
  Protected resetOk.i

  *Stats\Loaded = 0
  *Stats\VertexTotal = 0
  *Stats\NodeTotal = 0
  *Stats\VertexSamples = 0
  *Stats\NodeSamples = 0
  *Stats\ConvertedFields = 0
  *Stats\SideCalls = 0
  *Stats\SideFront = 0
  *Stats\SideBack = 0
  *Stats\AngleCalls = 0
  *Stats\DistanceCalls = 0
  *Stats\FailureCount = 0
  *Stats\Hash = 0

  If MapLevelLoad(Name, @level) = #False
    MapLevelReset(@level)
    ProcedureReturn #False
  EndIf
  *Stats\Loaded = 1

  vertexCount = MapVertexesCount(level\Vertexes)
  nodeCount = MapNodesCount(level\Nodes)
  *Stats\VertexTotal = vertexCount
  *Stats\NodeTotal = nodeCount
  If vertexCount <= 0 Or nodeCount <= 0
    MapLevelReset(@level)
    ProcedureReturn #True
  EndIf

  middleVertex = vertexCount / 2
  middleNode = nodeCount / 2

  firstX = 0
  firstY = 0
  middleX = 0
  middleY = 0
  lastX = 0
  lastY = 0
  storeFirst = 0
  storeMiddle = 0
  storeLast = 0

  For i = 0 To vertexCount - 1
    If MapVertexesGet(level\Vertexes, i, @rawX, @rawY) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf

    If FixedFromIntChecked(rawX, @fixedX) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf
    If FixedFromIntChecked(rawY, @fixedY) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf

    If IsSampledIndex(i, vertexCount, middleVertex)
      hash = FnvAddLong(hash, fixedX)
      hash = FnvAddLong(hash, fixedY)
      *Stats\ConvertedFields + 2
      *Stats\VertexSamples + 1
    EndIf

    If i = 0
      firstX = fixedX
      firstY = fixedY
      storeFirst = 1
    EndIf
    If i = middleVertex
      middleX = fixedX
      middleY = fixedY
      storeMiddle = 1
    EndIf
    If i = vertexCount - 1
      lastX = fixedX
      lastY = fixedY
      storeLast = 1
    EndIf
  Next

  For i = 0 To nodeCount - 1
    ; Bboxes and BSP children are deliberately not read here; null destinations
    ; keep the temporary conversion state limited to partition fields.
    If MapNodesGet(level\Nodes, i, @rawX, @rawY, @rawDX, @rawDY,
                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf

    If FixedFromIntChecked(rawX, @fixedX) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf
    If FixedFromIntChecked(rawY, @fixedY) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf
    If FixedFromIntChecked(rawDX, @fixedDX) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf
    If FixedFromIntChecked(rawDY, @fixedDY) = #False
      *Stats\FailureCount + 1
      Continue
    EndIf

    If IsSampledIndex(i, nodeCount, middleNode)
      hash = FnvAddLong(hash, fixedX)
      hash = FnvAddLong(hash, fixedY)
      hash = FnvAddLong(hash, fixedDX)
      hash = FnvAddLong(hash, fixedDY)
      *Stats\ConvertedFields + 4
      *Stats\NodeSamples + 1

      If storeFirst + storeMiddle + storeLast = 3
        side = -123
        If GeometryPointOnNodeSideChecked(firstX, firstY, fixedX, fixedY, fixedDX, fixedDY, @side) = #False
          *Stats\FailureCount + 1
        Else
          hash = FnvAddLong(hash, side)
          *Stats\SideCalls + 1
          If side = 0
            *Stats\SideFront + 1
          Else
            *Stats\SideBack + 1
          EndIf
        EndIf
        side = -123
        If GeometryPointOnNodeSideChecked(middleX, middleY, fixedX, fixedY, fixedDX, fixedDY, @side) = #False
          *Stats\FailureCount + 1
        Else
          hash = FnvAddLong(hash, side)
          *Stats\SideCalls + 1
          If side = 0
            *Stats\SideFront + 1
          Else
            *Stats\SideBack + 1
          EndIf
        EndIf
        side = -123
        If GeometryPointOnNodeSideChecked(lastX, lastY, fixedX, fixedY, fixedDX, fixedDY, @side) = #False
          *Stats\FailureCount + 1
        Else
          hash = FnvAddLong(hash, side)
          *Stats\SideCalls + 1
          If side = 0
            *Stats\SideFront + 1
          Else
            *Stats\SideBack + 1
          EndIf
        EndIf
      EndIf
    EndIf
  Next

  ; Angles and exact distances between the deterministic first/middle/last
  ; vertex pairings, both directions retained.
  If storeFirst + storeMiddle + storeLast = 3
    angleOut\Raw = 0
    If GeometryPointToAngle2Checked(firstX, firstY, lastX, lastY, @angleOut) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddRaw32(hash, angleOut\Raw)
      *Stats\AngleCalls + 1
    EndIf
    distance = -7777777
    If GeometryPointToDistChecked(firstX, firstY, lastX, lastY, @distance) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddLong(hash, distance)
      *Stats\DistanceCalls + 1
    EndIf

    angleOut\Raw = 0
    If GeometryPointToAngle2Checked(firstX, firstY, middleX, middleY, @angleOut) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddRaw32(hash, angleOut\Raw)
      *Stats\AngleCalls + 1
    EndIf
    distance = -7777777
    If GeometryPointToDistChecked(firstX, firstY, middleX, middleY, @distance) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddLong(hash, distance)
      *Stats\DistanceCalls + 1
    EndIf

    angleOut\Raw = 0
    If GeometryPointToAngle2Checked(middleX, middleY, lastX, lastY, @angleOut) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddRaw32(hash, angleOut\Raw)
      *Stats\AngleCalls + 1
    EndIf
    distance = -7777777
    If GeometryPointToDistChecked(middleX, middleY, lastX, lastY, @distance) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddLong(hash, distance)
      *Stats\DistanceCalls + 1
    EndIf

    angleOut\Raw = 0
    If GeometryPointToAngle2Checked(lastX, lastY, firstX, firstY, @angleOut) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddRaw32(hash, angleOut\Raw)
      *Stats\AngleCalls + 1
    EndIf
    distance = -7777777
    If GeometryPointToDistChecked(lastX, lastY, firstX, firstY, @distance) = #False
      *Stats\FailureCount + 1
    Else
      hash = FnvAddLong(hash, distance)
      *Stats\DistanceCalls + 1
    EndIf
  EndIf

  *Stats\Hash = hash
  resetOk = MapLevelReset(@level)
  If resetOk = #False
    *Stats\Loaded = 0
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure CheckGeometryMap(Name.s)
  Protected first.GeometryMapStats
  Protected second.GeometryMapStats
  Protected loadedFirst.i
  Protected loadedSecond.i

  loadedFirst = MeasureGeometryMap(Name, @first)
  Check(Bool(loadedFirst <> 0 And first\Loaded <> 0), Name + " loads through validated MapLevel API")
  Check(Bool(first\VertexTotal > 0 And first\NodeTotal > 0), Name + " has vertex and node records")
  Check(Bool(first\VertexSamples > 0 And first\NodeSamples > 0), Name + " bounded deterministic sample is nonempty")
  Check(Bool(first\ConvertedFields > 0), Name + " signed sampled map fields convert through FixedFromIntChecked")
  Check(Bool(first\FailureCount = 0), Name + " sampled conversions, node sides, angles and distances all succeed")
  Check(Bool(first\SideCalls > 0 And first\AngleCalls > 0 And first\DistanceCalls > 0), Name + " node-side and vertex-pair geometry operations actually ran")

  loadedSecond = MeasureGeometryMap(Name, @second)
  Check(Bool(loadedSecond <> 0 And second\Loaded <> 0), Name + " reloads for reproducibility")
  Check(Bool(first\Hash = second\Hash), Name + " canonical geometry checksum repeats identically")
  Check(Bool(first\VertexSamples = second\VertexSamples And
        first\NodeSamples = second\NodeSamples And
        first\ConvertedFields = second\ConvertedFields And
        first\SideCalls = second\SideCalls And
        first\SideFront = second\SideFront And
        first\SideBack = second\SideBack And
        first\AngleCalls = second\AngleCalls And
        first\DistanceCalls = second\DistanceCalls And
        first\FailureCount = second\FailureCount),
        Name + " bounded counts repeat identically")

  PrintN("  " + Name + ": vertexes " + Str(first\VertexTotal) +
         ", nodes " + Str(first\NodeTotal) +
         ", sampled vertexes " + Str(first\VertexSamples) +
         ", sampled nodes " + Str(first\NodeSamples) +
         ", converted fields " + Str(first\ConvertedFields))
  PrintN("    side calls " + Str(first\SideCalls) + " (front " + Str(first\SideFront) +
         ", back " + Str(first\SideBack) + "), angle calls " + Str(first\AngleCalls) +
         ", distance calls " + Str(first\DistanceCalls) + ", failures " + Str(first\FailureCount))
  PrintN("    FNV-1a64 " + Hex(first\Hash))
EndProcedure

; ---------------------------------------------------------------------------
; I04 optional owner IWAD pass
; ---------------------------------------------------------------------------

Procedure TestI04(Path.s)
  If Path = ""
    PrintN("[I04] Optional real Ultimate Doom read-only geometry integration: NOT RUN (no WAD path argument)")
    ProcedureReturn
  EndIf

  BeginCase("I04", "Optional real Ultimate Doom read-only angle/geometry integration")

  If WADOpen(Path) = #False
    Check(#False, "real IWAD opens read-only: " + WADLastError())
    ProcedureReturn
  EndIf
  Check(#True, "real IWAD opens read-only")
  PrintN("  WAD: " + WADGetPath())
  PrintN("  lumps: " + Str(WADGetLumpCount()))

  CheckGeometryMap("E1M1")
  CheckGeometryMap("E1M2")
  CheckGeometryMap("E4M1")

  WADClose()
  Check(Bool(WADIsOpen() = #False), "WAD closes cleanly after the read-only pass")
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-02 optional real geometry IWAD integration (I04)")

TestI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (I04 may be NOT RUN without a WAD argument)")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
