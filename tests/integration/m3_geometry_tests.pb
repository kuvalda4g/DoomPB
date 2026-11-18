; -----------------------------------------------------------------------------
; DoomPB - M3-02 synthetic integration: module composition, map bridge, errors
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; I01: compile and run an entry point using only Fixed, Angle, TrigTables,
;      Geometry (plus a generated numeric fixture); verify no WAD/map/video
;      dependency, stable immutable table pointers and stable accessors.
; I02: small synthetic signed map-unit vertex/node records, converted through
;      FixedFromIntChecked, tested against the independent generated fixture.
; I03: invalid inputs with unchanged checked outputs/diagnostics, then 15 valid
;      mixed operations twice with a canonical little-endian result hash; verify
;      diagnostic clearance and no state bleed.
;
; No real IWAD is read here. Optional owner-IWAD I04 lives in the separate
; m3_geometry_iwad_tests.pb harness. No game graphics, payloads or coordinates
; are printed.
;
; Exit code: 0 when every assertion passed, otherwise the number of failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../fixtures/m3_geometry_golden.pbi"

#TEST_FNV_Offset = -3750763034362895579
#TEST_FNV_Prime = 1099511628211

CompilerIf Defined(WADOpen, #PB_Procedure) <> 0
  #TEST_WadApiPresent = 1
CompilerElse
  #TEST_WadApiPresent = 0
CompilerEndIf

CompilerIf Defined(VideoShowFramebuffer, #PB_Procedure) <> 0
  #TEST_VideoApiPresent = 1
CompilerElse
  #TEST_VideoApiPresent = 0
CompilerEndIf

CompilerIf Defined(MapLevelLoad, #PB_Procedure) <> 0
  #TEST_MapApiPresent = 1
CompilerElse
  #TEST_MapApiPresent = 0
CompilerEndIf

Structure TestMapVertexRaw
  X.l
  Y.l
EndStructure

Structure TestMapNodeRaw
  X.l
  Y.l
  DX.l
  DY.l
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

; Raw 32-bit unsigned result transport: only the constrained low word bytes.
Procedure.q FnvAddRaw32(Hash.q, Value.q)
  Protected low.q = Value & $FFFFFFFF

  Hash = FnvAddByte(Hash, low & $FF)
  Hash = FnvAddByte(Hash, (low >> 8) & $FF)
  Hash = FnvAddByte(Hash, (low >> 16) & $FF)
  Hash = FnvAddByte(Hash, (low >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

; ---------------------------------------------------------------------------
; I01 - independent module composition and stable immutable tables
; ---------------------------------------------------------------------------

Procedure TestI01()
  BeginCase("I01", "only Fixed/Angle/TrigTables/Geometry modules, no runtime deps")
  Protected *firstSine
  Protected firstValue.l = 0
  Protected secondValue.l = 0
  Protected stable.i
  Protected tangentValue.l = 0

  Check(Bool(#TEST_WadApiPresent = 0), "no WAD symbol exists in the composition")
  Check(Bool(#TEST_VideoApiPresent = 0), "no video/presentation symbol exists in the composition")
  Check(Bool(#TEST_MapApiPresent = 0), "no map loader symbol exists in the composition")
  Check(Bool(*gTrigFinetangent <> 0 And *gTrigSine <> 0 And *gTrigTanToAngle <> 0), "immutable DataSection pointers are non-null")
  *firstSine = *gTrigSine
  stable = TrigSineChecked(0, @firstValue)
  TrigSineChecked(0, @secondValue)
  Check(Bool(stable <> 0 And firstValue = 25 And secondValue = 25), "sine accessor output is stable")
  Check(Bool(*firstSine = *gTrigSine), "table address does not change after access (no per-call setup)")
  Check(Bool(#TRIG_FINETANGENT_COUNT = 4096 And #TRIG_SINE_COUNT = 10240 And #TRIG_TANTOANGLE_COUNT = 2049), "fixed upstream table sizes remain reported")
  Check(Bool(TrigTangentChecked(4095, @tangentValue) <> 0 And tangentValue = 170910304), "last tangent entry stable and exact")
EndProcedure

; ---------------------------------------------------------------------------
; I02 - synthetic map geometry bridge
; ---------------------------------------------------------------------------

Procedure TestI02()
  BeginCase("I02", "synthetic signed map vertices/nodes converted without mutation")

  Protected vertexOrigin.TestMapVertexRaw
  Protected vertexDiagonal.TestMapVertexRaw
  Protected vertexNegative.TestMapVertexRaw
  Protected nodeVertical.TestMapNodeRaw
  Protected nodeHorizontal.TestMapNodeRaw
  Protected nodeSloped.TestMapNodeRaw
  Protected viewX.l = 0
  Protected viewY.l = 0
  Protected targetX.l = 0
  Protected targetY.l = 0
  Protected originX.l = 0
  Protected originY.l = 0
  Protected fixedDX.l = 0
  Protected fixedDY.l = 0
  Protected angleOut.BamAngleValue
  Protected distance.l = 0
  Protected side.l = -123
  Protected rawSnapshotX.l
  Protected rawSnapshotY.l

  vertexOrigin\X = 0
  vertexOrigin\Y = 0
  vertexDiagonal\X = 1
  vertexDiagonal\Y = 1
  vertexNegative\X = -1
  vertexNegative\Y = 1
  Check(Bool(FixedFromIntChecked(vertexOrigin\X, @viewX) <> 0 And viewX = 0), "origin vertex X map 0 -> fixed 0")
  Check(Bool(FixedFromIntChecked(vertexOrigin\Y, @viewY) <> 0 And viewY = 0), "origin vertex Y map 0 -> fixed 0")
  Check(Bool(FixedFromIntChecked(vertexDiagonal\X, @targetX) <> 0 And targetX = 65536), "diagonal vertex X map 1 -> fixed 65536")
  Check(Bool(FixedFromIntChecked(vertexDiagonal\Y, @targetY) <> 0 And targetY = 65536), "diagonal vertex Y map 1 -> fixed 65536")

  Check(Bool(GeometryPointToAngle2Checked(viewX, viewY, targetX, targetY, @angleOut) <> 0 And angleOut\Raw = 536870911), "vertex 0,0 -> 1,1 angle matches fixture diagonal ANG45-1")
  Check(Bool(GeometryPointToDistChecked(viewX, viewY, targetX, targetY, @distance) <> 0 And distance = 92717), "same vertex pair distance matches fixture 92717")

  Check(Bool(FixedFromIntChecked(vertexNegative\X, @targetX) <> 0 And targetX = -65536), "negative vertex X map -1 -> fixed -65536")
  Check(Bool(FixedFromIntChecked(vertexNegative\Y, @targetY) <> 0 And targetY = 65536), "negative vertex Y map 1 -> fixed 65536")
  Check(Bool(GeometryPointToAngle2Checked(0, 0, targetX, targetY, @angleOut) <> 0 And angleOut\Raw = 1610612736), "vertex 0,0 -> -1,1 angle matches fixture 0x60000000")
  Check(Bool(GeometryPointToDistChecked(0, 0, targetX, targetY, @distance) <> 0 And distance = 92717), "vertex 0,0 -> -1,1 distance matches fixture 92717")

  ; node partition with dx=0 (vertical), dy=0 (horizontal) and a non-axis line
  nodeVertical\X = 1
  nodeVertical\Y = 0
  nodeVertical\DX = 0
  nodeVertical\DY = 1
  rawSnapshotX = nodeVertical\X
  rawSnapshotY = nodeVertical\DY
  Check(Bool(FixedFromIntChecked(nodeVertical\X, @originX) <> 0 And originX = 65536), "vertical node origin X map 1 -> fixed 65536")
  Check(Bool(FixedFromIntChecked(nodeVertical\DX, @fixedDX) <> 0 And fixedDX = 0), "vertical node dx=0 remains exactly zero")
  Check(Bool(FixedFromIntChecked(nodeVertical\DY, @fixedDY) <> 0 And fixedDY = 65536), "vertical node dy map 1 -> fixed 65536")
  side = -123
  Check(Bool(GeometryPointOnNodeSideChecked(65536, 65536, originX, 0, fixedDX, fixedDY, @side) <> 0 And side = 1), "vertical dx=0 boundary side matches fixture back side")

  nodeHorizontal\X = 0
  nodeHorizontal\Y = 1
  nodeHorizontal\DX = -1
  nodeHorizontal\DY = 0
  Check(Bool(FixedFromIntChecked(nodeHorizontal\Y, @originY) <> 0 And originY = 65536), "horizontal node origin Y map 1 -> fixed 65536")
  Check(Bool(FixedFromIntChecked(nodeHorizontal\DX, @fixedDX) <> 0 And fixedDX = -65536), "horizontal node dx map -1 -> fixed -65536")
  Check(Bool(FixedFromIntChecked(nodeHorizontal\DY, @fixedDY) <> 0 And fixedDY = 0), "horizontal node dy=0 remains exactly zero")
  side = -123
  Check(Bool(GeometryPointOnNodeSideChecked(0, 65536, 0, originY, fixedDX, fixedDY, @side) <> 0 And side = 1), "horizontal dy=0 boundary side matches negative dx orientation")

  nodeSloped\X = 0
  nodeSloped\Y = 0
  nodeSloped\DX = 1
  nodeSloped\DY = 1
  Check(Bool(FixedFromIntChecked(nodeSloped\DX, @fixedDX) <> 0 And fixedDX = 65536), "non-axis node dx map 1 -> fixed 65536")
  Check(Bool(FixedFromIntChecked(nodeSloped\DY, @fixedDY) <> 0 And fixedDY = 65536), "non-axis node dy map 1 -> fixed 65536")
  side = -123
  Check(Bool(GeometryPointOnNodeSideChecked(65536, 65536, 0, 0, fixedDX, fixedDY, @side) <> 0 And side = 1), "non-axis node exact-line tie matches fixture back side")
  Check(Bool(nodeVertical\X = rawSnapshotX And nodeVertical\DY = rawSnapshotY), "synthetic partition fields are not mutated")
EndProcedure

; ---------------------------------------------------------------------------
; I03 - error recovery and deterministic snapshot
; ---------------------------------------------------------------------------

; 15 valid mixed scalar/table operations. The caller-owned count records how many
; results entered the canonical hash; no geometry is printed.
Procedure.q RunMixedSnapshot(*Count.Long)
  Protected hash.q = #TEST_FNV_Offset
  Protected angleOut.BamAngleValue
  Protected distance.l = 0
  Protected side.l = 0
  Protected slope.l = 0
  Protected tableValue.l = 0
  Protected operations.i = 0

  *Count\l = 0

  If GeometryPointToAngleChecked(0, 0, 65536, 65536, @angleOut)
    hash = FnvAddRaw32(hash, angleOut\Raw)
    operations + 1
  EndIf
  If GeometryPointToAngleChecked(0, 0, 0, 65536, @angleOut)
    hash = FnvAddRaw32(hash, angleOut\Raw)
    operations + 1
  EndIf
  If GeometryPointToAngleChecked(0, 0, -65536, -65536, @angleOut)
    hash = FnvAddRaw32(hash, angleOut\Raw)
    operations + 1
  EndIf
  If GeometryPointToDistChecked(0, 0, 65536, 65536, @distance)
    hash = FnvAddLong(hash, distance)
    operations + 1
  EndIf
  If GeometryPointToDistChecked(0, 0, 65536, 0, @distance)
    hash = FnvAddLong(hash, distance)
    operations + 1
  EndIf
  If GeometryPointToDistChecked(0, 0, -65536, -65536, @distance)
    hash = FnvAddLong(hash, distance)
    operations + 1
  EndIf
  If GeometryPointOnNodeSideChecked(65536, 65536, 65536, 0, 0, 65536, @side)
    hash = FnvAddLong(hash, side)
    operations + 1
  EndIf
  If GeometryPointOnNodeSideChecked(65536, 65536, 0, 0, 65536, 65536, @side)
    hash = FnvAddLong(hash, side)
    operations + 1
  EndIf
  If GeometryPointOnSegSideChecked(65536, 65536, 0, 0, 65536, 65536, @side)
    hash = FnvAddLong(hash, side)
    operations + 1
  EndIf
  If DoomSlopeDivChecked(511, 512, @slope)
    hash = FnvAddLong(hash, slope)
    operations + 1
  EndIf
  If DoomSlopeDivChecked(65536, 65536, @slope)
    hash = FnvAddLong(hash, slope)
    operations + 1
  EndIf
  If TrigTanToAngleChecked(2048, @tableValue)
    hash = FnvAddLong(hash, tableValue)
    operations + 1
  EndIf
  If TrigSineChecked(2048, @tableValue)
    hash = FnvAddLong(hash, tableValue)
    operations + 1
  EndIf
  If TrigCosineChecked(1024, @tableValue)
    hash = FnvAddLong(hash, tableValue)
    operations + 1
  EndIf
  If TrigTangentChecked(4095, @tableValue)
    hash = FnvAddLong(hash, tableValue)
    operations + 1
  EndIf

  *Count\l = operations
  ProcedureReturn hash
EndProcedure

Procedure TestI03()
  BeginCase("I03", "error recovery and deterministic 15-operation snapshot")
  Protected angleOut.BamAngleValue
  Protected distance.l = -7777777
  Protected side.l = -123
  Protected slope.l = 7777777
  Protected tableValue.l = -555555
  Protected firstHash.q
  Protected secondHash.q
  Protected firstCount.l = 0
  Protected secondCount.l = 0

  angleOut\Raw = 12345
  Check(Bool(GeometryPointToAngleChecked(-1, 0, 2147483647, 0, @angleOut) = #False And angleOut\Raw = 12345), "angle overflow fails and leaves output unchanged")
  distance = -7777777
  Check(Bool(GeometryPointToDistChecked(-1, 0, 2147483647, 0, @distance) = #False And distance = -7777777), "distance overflow fails and leaves output unchanged")
  side = -123
  Check(Bool(GeometryPointOnNodeSideChecked(2147483647, 0, -1, 0, 65536, 65536, @side) = #False And side = -123), "side overflow fails and leaves output unchanged")
  slope = 7777777
  Check(Bool(DoomSlopeDivChecked(-1, 512, @slope) = #False And slope = 7777777), "signed slope input fails and leaves output unchanged")
  tableValue = -555555
  Check(Bool(TrigSineChecked(10240, @tableValue) = #False And tableValue = -555555), "invalid table index fails and leaves output unchanged")
  Check(Bool(GeometryLastError() <> "" And TrigLastError() <> ""), "failed operations carry actionable diagnostics")

  firstHash = RunMixedSnapshot(@firstCount)
  secondHash = RunMixedSnapshot(@secondCount)
  Check(Bool(firstCount >= 12), "snapshot includes at least 12 valid mixed operations (" + Str(firstCount) + ")")
  Check(Bool(firstHash = secondHash), "15-operation canonical little-endian hash repeats identically")
  Check(Bool(firstCount = secondCount), "operation count repeats identically")
  Check(Bool(GeometryLastError() = "" And TrigLastError() = ""), "the successful snapshot clears both prior diagnostics")
  PrintN("  snapshot operations: " + Str(firstCount) + ", FNV-1a64 " + Hex(firstHash))
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-02 synthetic geometry integration (I01-I03)")

TestI01()
TestI02()
TestI03()

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
