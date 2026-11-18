; -----------------------------------------------------------------------------
; DoomPB - M3-01 optional real-IWAD fixed-point integration (FI04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; This harness is optional and takes an owner-provided IWAD path as its first
; program argument, exactly like the M2 I04 convention. It reads the WAD
; read-only, loads E1M1/E1M2/E4M1 through the existing validated map APIs,
; converts every signed 16-bit vertex coordinate and sector floor/ceiling
; height through FixedFromIntChecked, verifies bounds and reproducibility, then
; closes the WAD.
;
; Only counts, conversion totals and non-reconstructable FNV-1a64 checksums are
; printed. No coordinate lists, entire level tables or WAD payload bytes are
; emitted, stored or copied. Without a path argument FI04 is reported NOT RUN;
; that is not a failure for the clean synthetic suite.
;
; Exit code: 0 when every assertion passed (or FI04 is NOT RUN), otherwise the
; number of failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"

#IWAD_FNV_Offset = -3750763034362895579
#IWAD_FNV_Prime = 1099511628211

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

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

; Canonical FNV-1a64 field feeding, matching the M2 metadata hash convention.
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

; ---------------------------------------------------------------------------
; FI04 measurement pass
; ---------------------------------------------------------------------------

; Loads one map, converts all signed vertex/sector fields to 16.16, hashes the
; converted values in canonical little-endian fixed order, then resets the
; level. The caller-owned outputs are counts and failures; *Loaded reports
; whether the map was loadable. No record is mutated and no WAD buffer is kept.
Procedure.q MeasureFixedMap(Name.s, *Loaded.Long, *VertexCount.Long,
                           *SectorCount.Long, *ConvertedCount.Long,
                           *FailureCount.Long, *HalfFailures.Long)
  Protected level.MapLevel
  Protected vertexCount.i = 0
  Protected sectorCount.i = 0
  Protected converted.i = 0
  Protected failures.i = 0
  Protected halfFailures.i = 0
  Protected i.i
  Protected x.l = 0
  Protected y.l = 0
  Protected floorHeight.l = 0
  Protected ceilingHeight.l = 0
  Protected lightLevel.l = 0
  Protected special.l = 0
  Protected tag.l = 0
  Protected fixedValue.l = 0
  Protected hash.q = #IWAD_FNV_Offset
  Protected resetOk.i

  *Loaded\l = 0
  *VertexCount\l = 0
  *SectorCount\l = 0
  *ConvertedCount\l = 0
  *FailureCount\l = 0
  *HalfFailures\l = 0

  If MapLevelLoad(Name, @level) = #False
    MapLevelReset(@level)
    ProcedureReturn 0
  EndIf
  *Loaded\l = 1

  vertexCount = MapVertexesCount(level\Vertexes)
  sectorCount = MapSectorsCount(level\Sectors)
  *VertexCount\l = vertexCount
  *SectorCount\l = sectorCount

  For i = 0 To vertexCount - 1
    If MapVertexesGet(level\Vertexes, i, @x, @y) = #False
      halfFailures + 1
      Continue
    EndIf
    If FixedFromIntChecked(x, @fixedValue) = #False
      failures + 1
      Continue
    EndIf
    hash = FnvAddLong(hash, fixedValue)
    converted + 1
    If FixedFromIntChecked(y, @fixedValue) = #False
      failures + 1
      Continue
    EndIf
    hash = FnvAddLong(hash, fixedValue)
    converted + 1
  Next

  For i = 0 To sectorCount - 1
    If MapSectorsGet(level\Sectors, i, @floorHeight, @ceilingHeight,
                     @lightLevel, @special, @tag) = #False
      halfFailures + 1
      Continue
    EndIf
    If FixedFromIntChecked(floorHeight, @fixedValue) = #False
      failures + 1
      Continue
    EndIf
    hash = FnvAddLong(hash, fixedValue)
    converted + 1
    If FixedFromIntChecked(ceilingHeight, @fixedValue) = #False
      failures + 1
      Continue
    EndIf
    hash = FnvAddLong(hash, fixedValue)
    converted + 1
  Next

  *ConvertedCount\l = converted
  *FailureCount\l = failures
  *HalfFailures\l = halfFailures

  resetOk = MapLevelReset(@level)
  If resetOk = #False
    *Loaded\l = 0
  EndIf

  ProcedureReturn hash
EndProcedure

Procedure CheckFixedMap(Name.s)
  Protected hashFirst.q
  Protected hashSecond.q
  Protected loadedFirst.l = 0
  Protected loadedSecond.l = 0
  Protected vertexCount.l = 0
  Protected sectorCount.l = 0
  Protected converted.l = 0
  Protected failures.l = 0
  Protected halfFailures.l = 0
  Protected convertedSecond.l = 0
  Protected failuresSecond.l = 0
  Protected halfFailuresSecond.l = 0
  Protected expectedConverted.q

  hashFirst = MeasureFixedMap(Name, @loadedFirst, @vertexCount, @sectorCount,
                              @converted, @failures, @halfFailures)
  Check(Bool(loadedFirst = 1), Name + " loads through the validated map API")
  Check(Bool(vertexCount > 0), Name + " has vertex records")
  Check(Bool(sectorCount > 0), Name + " has sector records")
  Check(Bool(halfFailures = 0), Name + " accessors read every vertex/sector field")
  Check(Bool(failures = 0), Name + " all signed coordinate/height conversions succeed")
  Check(Bool(converted = vertexCount * 2 + sectorCount * 2),
        Name + " converted exactly two fields per vertex and sector")

  hashSecond = MeasureFixedMap(Name, @loadedSecond, @vertexCount,
                               @sectorCount, @convertedSecond, @failuresSecond,
                               @halfFailuresSecond)
  Check(Bool(loadedSecond = 1), Name + " reloads for the reproducibility pass")
  Check(Bool(failuresSecond = 0), Name + " reload conversions all succeed")
  Check(Bool(hashFirst = hashSecond), Name + " fixed-value checksum repeats identically")
  Check(Bool(converted = convertedSecond), Name + " conversion totals repeat identically")

  PrintN("  " + Name + ": vertexes " + Str(vertexCount) + ", sectors " +
         Str(sectorCount) + ", converted fixed fields " + Str(converted) +
         ", failures " + Str(failures) + ", FNV-1a64 " + Hex(hashFirst))
EndProcedure

Procedure TestFI04(Path.s)
  If Path = ""
    PrintN("[FI04] Optional real Ultimate Doom read-only integration: NOT RUN (no WAD path argument)")
    ProcedureReturn
  EndIf

  BeginCase("FI04", "Optional real Ultimate Doom read-only fixed-point bridge")

  If WADOpen(Path) = #False
    Check(#False, "real IWAD opens read-only: " + WADLastError())
    ProcedureReturn
  EndIf
  Check(#True, "real IWAD opens read-only")
  PrintN("  WAD: " + WADGetPath())
  PrintN("  lumps: " + Str(WADGetLumpCount()))

  CheckFixedMap("E1M1")
  CheckFixedMap("E1M2")
  CheckFixedMap("E4M1")

  WADClose()
  Check(Bool(WADIsOpen() = #False), "WAD closes cleanly after the read-only pass")
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-01 optional fixed-point IWAD integration (FI04)")

TestFI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (FI04 may be NOT RUN without a WAD argument)")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
