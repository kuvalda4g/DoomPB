; -----------------------------------------------------------------------------
; DoomPB - map loader and cross-reference validation tests (M2-06)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; All map data and WADs are synthetic. No commercial resources are included.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Map/MapTypes.pbi"
XIncludeFile "../../src/Map/MapDecode.pbi"
XIncludeFile "../../src/Map/Blockmap.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

Global gFixtureDirectory.s = ""
Global gWadCount.i = 0
Global Dim gWadNames.s(63)
Global Dim gWadPointers.i(63)
Global Dim gWadSizes.q(63)
Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

; Current synthetic map buffers, indexed 1..10 in canonical order.
Global Dim gLump(10)
Global Dim gLumpSize.q(10)

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

Procedure.s FixturePath(FileName.s)
  ProcedureReturn gFixtureDirectory + FileName
EndProcedure

Procedure.i PrepareFixtureDirectory()
  Protected directorySize.i

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "wad-map-loader-test-tmp" + #FixtureSeparator
  directorySize = FileSize(gFixtureDirectory)
  If directorySize = -1
    ProcedureReturn CreateDirectory(gFixtureDirectory)
  EndIf
  If directorySize = -2
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure CleanupFixtureDirectory()
  Protected directory.i
  Protected entryName.s

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
  DeleteDirectory(gFixtureDirectory, "*")
EndProcedure

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

Procedure FreeMapBuffers()
  Protected i.i

  For i = 1 To 10
    If gLump(i) <> 0
      FreeMemory(gLump(i))
    EndIf
    gLump(i) = 0
    gLumpSize(i) = 0
  Next
EndProcedure

Procedure.i NewLump(Kind.i, Size.i)
  If gLump(Kind) <> 0
    FreeMemory(gLump(Kind))
  EndIf
  gLump(Kind) = NewZero(Size)
  gLumpSize(Kind) = Size
  ProcedureReturn gLump(Kind)
EndProcedure

Procedure BuildDefaultMap()
  Protected i.i
  Protected *p.Byte

  FreeMapBuffers()

  NewLump(1, 10)
  Put16(gLump(1), 6, 1)   ; one player start

  NewLump(2, 4 * 14)
  For i = 0 To 3
    Put16(gLump(2), i * 14, i)
    Put16(gLump(2), i * 14 + 2, (i + 1) % 4)
    Put16(gLump(2), i * 14 + 10, i)
    Put16(gLump(2), i * 14 + 12, -1)
  Next

  NewLump(3, 4 * 30)
  For i = 0 To 3
    PutName8(gLump(3), i * 30 + 4, "-")
    PutName8(gLump(3), i * 30 + 12, "-")
    PutName8(gLump(3), i * 30 + 20, "-")
    Put16(gLump(3), i * 30 + 28, 0)
  Next

  NewLump(4, 4 * 4)
  Put16(gLump(4), 0, 0): Put16(gLump(4), 2, 0)
  Put16(gLump(4), 4, 64): Put16(gLump(4), 6, 0)
  Put16(gLump(4), 8, 64): Put16(gLump(4), 10, 64)
  Put16(gLump(4), 12, 0): Put16(gLump(4), 14, 64)

  NewLump(5, 4 * 12)
  For i = 0 To 3
    Put16(gLump(5), i * 12, i)
    Put16(gLump(5), i * 12 + 2, (i + 1) % 4)
    Put16(gLump(5), i * 12 + 6, i)
    Put16(gLump(5), i * 12 + 8, 0)
  Next

  NewLump(6, 4)
  Put16(gLump(6), 0, 4)
  Put16(gLump(6), 2, 0)

  NewLump(7, 0)

  NewLump(8, 26)
  PutName8(gLump(8), 4, "FLOOR0_1")
  PutName8(gLump(8), 12, "CEIL1_1")
  Put16(gLump(8), 20, 160)

  NewLump(9, 1)

  NewLump(10, 16)
  Put16(gLump(10), 4, 1)
  Put16(gLump(10), 6, 1)
  Put16(gLump(10), 8, 5)
  Put16(gLump(10), 10, 0)
  Put16(gLump(10), 12, 0)
  Put16(gLump(10), 14, $FFFF)
EndProcedure

; Two-sector variant: one two-sided line (sides 0/1) and one one-sided line.
Procedure BuildTwoSectorMap()
  BuildDefaultMap()
  NewLump(2, 2 * 14)
  Put16(gLump(2), 0, 0)
  Put16(gLump(2), 2, 1)
  Put16(gLump(2), 4, #MAP_ML_TWOSIDED)
  Put16(gLump(2), 10, 0)
  Put16(gLump(2), 12, 1)
  Put16(gLump(2), 14, 2)
  Put16(gLump(2), 16, 3)
  Put16(gLump(2), 24, 2)
  Put16(gLump(2), 26, -1)

  NewLump(3, 3 * 30)
  PutName8(gLump(3), 4, "-"): PutName8(gLump(3), 12, "-"): PutName8(gLump(3), 20, "-")
  Put16(gLump(3), 28, 0)
  PutName8(gLump(3), 34, "-"): PutName8(gLump(3), 42, "-"): PutName8(gLump(3), 50, "-")
  Put16(gLump(3), 58, 1)
  PutName8(gLump(3), 64, "-"): PutName8(gLump(3), 72, "-"): PutName8(gLump(3), 80, "-")
  Put16(gLump(3), 88, 1)

  NewLump(5, 2 * 12)
  Put16(gLump(5), 0, 0): Put16(gLump(5), 2, 1)
  Put16(gLump(5), 6, 0): Put16(gLump(5), 8, 0)
  Put16(gLump(5), 12, 2): Put16(gLump(5), 14, 3)
  Put16(gLump(5), 18, 1): Put16(gLump(5), 20, 0)

  NewLump(6, 4)
  Put16(gLump(6), 0, 2)
  Put16(gLump(6), 2, 0)

  NewLump(8, 2 * 26)
  PutName8(gLump(8), 4, "FLOOR0_1")
  PutName8(gLump(8), 12, "CEIL1_1")
  Put16(gLump(8), 20, 160)
  PutName8(gLump(8), 30, "FLOOR0_1")
  PutName8(gLump(8), 38, "CEIL1_1")
  Put16(gLump(8), 46, 160)

  NewLump(9, 1)
EndProcedure

Procedure SetSubsectors(Count.i)
  Protected i.i

  NewLump(6, Count * 4)
  For i = 0 To Count - 1
    Put16(gLump(6), i * 4, 1)
    Put16(gLump(6), i * 4 + 2, 0)
  Next
EndProcedure

Procedure SetNodes(Count.i)
  NewLump(7, Count * 28)
EndProcedure

Procedure SetNode(Index.i, X.i, Y.i, DX.i, DY.i, Child0.i, Child1.i)
  Protected base.i = Index * 28

  Put16(gLump(7), base, X)
  Put16(gLump(7), base + 2, Y)
  Put16(gLump(7), base + 4, DX)
  Put16(gLump(7), base + 6, DY)
  Put16(gLump(7), base + 24, Child0)
  Put16(gLump(7), base + 26, Child1)
EndProcedure

; ---------------------------------------------------------------------------
; WAD writer
; ---------------------------------------------------------------------------

Procedure WadResetEntries()
  gWadCount = 0
EndProcedure

Procedure WadAdd(Name.s, *Data.Byte, Size.q)
  gWadNames(gWadCount) = Name
  gWadPointers(gWadCount) = *Data
  gWadSizes(gWadCount) = Size
  gWadCount + 1
EndProcedure

Procedure WriteU32File(file.i, Value.q)
  WriteByte(file, Value & $FF)
  WriteByte(file, (Value >> 8) & $FF)
  WriteByte(file, (Value >> 16) & $FF)
  WriteByte(file, (Value >> 24) & $FF)
EndProcedure

Procedure WriteEntryFile(file.i, Position.q, Size.q, Name.s)
  Protected i.i

  WriteU32File(file, Position)
  WriteU32File(file, Size)
  For i = 0 To 7
    If i < Len(Name)
      WriteByte(file, Asc(Mid(Name, i + 1, 1)))
    Else
      WriteByte(file, 0)
    EndIf
  Next
EndProcedure

Procedure.i WriteMapWad(FileName.s, PrefixMarkers.i = 0, RenameIndex.i = 0, SwapFirstTwo.i = 0, OmitLast.i = 0, MarkerSize.i = 0)
  Protected path.s = FixturePath(FileName)
  Protected file.i
  Protected directoryOffset.q
  Protected i.i
  Protected markerData.i = 0
  Protected Dim positions.q(63)
  Protected Dim names.s(10)
  Protected name.s

  names(1) = "THINGS"
  names(2) = "LINEDEFS"
  names(3) = "SIDEDEFS"
  names(4) = "VERTEXES"
  names(5) = "SEGS"
  names(6) = "SSECTORS"
  names(7) = "NODES"
  names(8) = "SECTORS"
  names(9) = "REJECT"
  names(10) = "BLOCKMAP"

  WadResetEntries()
  For i = 1 To PrefixMarkers
    WadAdd("E1M1", 0, 0)
  Next
  If MarkerSize > 0
    markerData = NewZero(MarkerSize)
    WadAdd("E1M1", markerData, MarkerSize)
  Else
    WadAdd("E1M1", 0, 0)
  EndIf
  For i = 1 To 10
    If OmitLast And i = 10
      Continue
    EndIf
    name = names(i)
    If RenameIndex = i
      name = "BOGUS"
    EndIf
    If SwapFirstTwo
      If i = 1
        name = "LINEDEFS"
      ElseIf i = 2
        name = "THINGS"
      EndIf
    EndIf
    WadAdd(name, gLump(i), gLumpSize(i))
  Next

  file = CreateFile(#PB_Any, path)
  If file = 0
    If markerData <> 0
      FreeMemory(markerData)
    EndIf
    ProcedureReturn #False
  EndIf
  WriteString(file, "PWAD")
  WriteU32File(file, gWadCount)
  WriteU32File(file, 0)
  For i = 0 To gWadCount - 1
    positions(i) = Loc(file)
    If gWadSizes(i) > 0
      WriteData(file, gWadPointers(i), gWadSizes(i))
    EndIf
  Next
  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32File(file, directoryOffset)
  FileSeek(file, directoryOffset)
  For i = 0 To gWadCount - 1
    WriteEntryFile(file, positions(i), gWadSizes(i), gWadNames(i))
  Next
  CloseFile(file)
  If markerData <> 0
    FreeMemory(markerData)
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure.i OpenMapWad(FileName.s)
  ProcedureReturn WADOpen(FixturePath(FileName))
EndProcedure

Procedure CloseAndDelete(FileName.s)
  WADClose()
  DeleteFile(FixturePath(FileName))
EndProcedure

; ---------------------------------------------------------------------------
; L01 - L12: marker and load transaction
; ---------------------------------------------------------------------------

Procedure TestL01ValidLoad()
  BeginCase("L01", "Valid ten-lump map loads with expected counts")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l01.wad")), "synthetic WAD created")
  Check(Bool(OpenMapWad("l01.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MapLevelIsReady(@level)), "level is ready")
  Check(Bool(level\Things\Count = 1 And level\Linedefs\Count = 4), "record counts are correct")
  Check(Bool(level\Reject\Size = 1 And level\RejectRequired = 1), "REJECT size and requirement")
  Check(Bool(level\BspRootIsSubsector = 1 And level\BspRootIndex = 0), "zero-node root is subsector 0")
  MapLevelReset(@level)
  CloseAndDelete("l01.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL02MissingMarker()
  BeginCase("L02", "Missing map marker")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l02.wad")), "WAD created")
  Check(Bool(OpenMapWad("l02.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M2", @level) = #False), "missing marker fails")
  Check(Bool(FindString(MapLevelLastError(), "marker not found") > 0), "error names the marker")
  MapLevelReset(@level)
  CloseAndDelete("l02.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL03DuplicateMarker()
  BeginCase("L03", "Last matching map marker is selected")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l03.wad", 2)), "WAD with duplicate markers created")
  Check(Bool(OpenMapWad("l03.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads from the last marker")
  Check(Bool(level\MarkerIndex = 2), "last marker index is used")
  Check(Bool(level\Linedefs\Count = 4), "complete block after the last marker is used")
  MapLevelReset(@level)
  CloseAndDelete("l03.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL04MissingLump()
  BeginCase("L04", "Missing required lump name")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l04.wad", 0, 8)), "WAD with renamed SECTORS created")
  Check(Bool(OpenMapWad("l04.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "missing SECTORS fails")
  Check(Bool(FindString(MapLevelLastError(), "SECTORS") > 0), "error names SECTORS")
  MapLevelReset(@level)
  CloseAndDelete("l04.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL05WrongOrder()
  BeginCase("L05", "Correct names in wrong order")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l05.wad", 0, 0, 1)), "WAD with swapped names created")
  Check(Bool(OpenMapWad("l05.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "wrong order fails")
  MapLevelReset(@level)
  CloseAndDelete("l05.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL06Truncated()
  BeginCase("L06", "Map truncated by end of directory")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l06.wad", 0, 0, 0, 1)), "truncated WAD created")
  Check(Bool(OpenMapWad("l06.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "truncated map fails")
  Check(Bool(FindString(MapLevelLastError(), "truncated") > 0), "error mentions truncation")
  MapLevelReset(@level)
  CloseAndDelete("l06.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL07NonzeroMarker()
  BeginCase("L07", "Nonzero map marker is rejected")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l07.wad", 0, 0, 0, 0, 4)), "WAD with nonzero marker created")
  Check(Bool(OpenMapWad("l07.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "nonzero marker fails")
  Check(Bool(FindString(MapLevelLastError(), "zero-length") > 0), "marker policy is reported")
  MapLevelReset(@level)
  CloseAndDelete("l07.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL08InvalidNames()
  BeginCase("L08", "Invalid, overlong and Unicode map names")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l08.wad")), "WAD created")
  Check(Bool(OpenMapWad("l08.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1X", @level) = #False), "overlong name rejected")
  Check(Bool(MapLevelLoad("MAP01", @level) = #False), "MAPxx not claimed by this task")
  Check(Bool(MapLevelLoad("E1M" + Chr(233), @level) = #False), "Unicode name rejected")
  MapLevelReset(@level)
  CloseAndDelete("l08.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL09BadRecordLength()
  BeginCase("L09", "Bad binary record length fails without partial level")
  Protected level.MapLevel

  BuildDefaultMap()
  NewLump(4, 5)
  Check(Bool(WriteMapWad("l09.wad")), "WAD created")
  Check(Bool(OpenMapWad("l09.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "5-byte VERTEXES rejected")
  Check(Bool(MapLevelIsReady(@level) = #False), "no partial ready level")
  MapLevelReset(@level)
  CloseAndDelete("l09.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL10SecondLevel()
  BeginCase("L10", "Loading a second level replaces the first")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l10a.wad")), "WAD A created")
  Check(Bool(OpenMapWad("l10a.wad")), "WAD A opens")
  Check(Bool(MapLevelLoad("E1M1", @level) And level\Linedefs\Count = 4), "first level loads")
  WADClose()

  BuildDefaultMap()
  NewLump(1, 20)
  Check(Bool(WriteMapWad("l10b.wad")), "WAD B created")
  Check(Bool(OpenMapWad("l10b.wad")), "WAD B opens")
  Check(Bool(MapLevelLoad("E1M1", @level) And level\Things\Count = 2), "second level replaces counts")
  MapLevelReset(@level)
  CloseAndDelete("l10b.wad")
  DeleteFile(FixturePath("l10a.wad"))
  FreeMapBuffers()
EndProcedure

Procedure TestL11FailureAfterSuccess()
  BeginCase("L11", "Failure after success leaves an empty target")
  Protected level.MapLevel

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l11.wad")), "WAD created")
  Check(Bool(OpenMapWad("l11.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level)), "first load succeeds")
  Check(Bool(MapLevelLoad("E9M9", @level) = #False), "second load fails")
  Check(Bool(MapLevelIsReady(@level) = #False And level\Linedefs\Count = 0), "target is empty after failure")
  MapLevelReset(@level)
  CloseAndDelete("l11.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL12ResetAndOwnership()
  BeginCase("L12", "Repeated reset and owned data")
  Protected level.MapLevel
  Protected front.l, back.l

  BuildDefaultMap()
  Check(Bool(WriteMapWad("l12.wad")), "WAD created")
  Check(Bool(OpenMapWad("l12.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(level\Linedefs\Count = 4), "records are present")
  Check(Bool(MapLevelGetLinedefLinks(@level, 0, @front, @back) And front = 0 And back = -1), "owned links readable")
  Check(Bool(MapLevelReset(@level)), "first reset")
  Check(Bool(MapLevelReset(@level)), "second reset")
  Check(Bool(MapLevelIsReady(@level) = #False And level\Linedefs\Items = 0), "reset clears ownership")
  CloseAndDelete("l12.wad")
  FreeMapBuffers()
EndProcedure

; ---------------------------------------------------------------------------
; L13 - L25: references and links
; ---------------------------------------------------------------------------

Procedure TestL13ValidVertices()
  BeginCase("L13", "Valid linedef vertex references")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l13.wad")
  OpenMapWad("l13.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "valid vertex references accepted")
  Check(Bool(level\Vertexes\Count = 4), "vertex count")
  MapLevelReset(@level)
  CloseAndDelete("l13.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL14BadVertex()
  BeginCase("L14", "Linedef vertex index at NumVertices")
  Protected level.MapLevel

  BuildDefaultMap()
  Put16(gLump(2), 0, 4)
  WriteMapWad("l14.wad")
  OpenMapWad("l14.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "vertex index 4 rejected")
  Check(Bool(FindString(MapLevelLastError(), "vertex") > 0), "error mentions vertices")
  MapLevelReset(@level)
  CloseAndDelete("l14.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL15FrontBackSectors()
  BeginCase("L15", "Two-sided linedef derives front/back sectors")
  Protected level.MapLevel
  Protected front.l, back.l

  BuildTwoSectorMap()
  WriteMapWad("l15.wad")
  OpenMapWad("l15.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "two-sector map loads")
  Check(Bool(MapLevelGetLinedefLinks(@level, 0, @front, @back)), "line links readable")
  Check(Bool(front = 0 And back = 1), "front/back sectors are 0/1")
  MapLevelReset(@level)
  CloseAndDelete("l15.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL16BadSidedefSector()
  BeginCase("L16", "Sidedef sector index at NumSectors")
  Protected level.MapLevel

  BuildTwoSectorMap()
  Put16(gLump(3), 28, 2)
  WriteMapWad("l16.wad")
  OpenMapWad("l16.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "sector 2 rejected")
  Check(Bool(FindString(MapLevelLastError(), "sector") > 0), "error mentions sector")
  MapLevelReset(@level)
  CloseAndDelete("l16.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL17BadFrontSide()
  BeginCase("L17", "Invalid front sidedef index")
  Protected level.MapLevel

  BuildDefaultMap()
  Put16(gLump(2), 10, 5)
  WriteMapWad("l17.wad")
  OpenMapWad("l17.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "front side 5 rejected")
  MapLevelReset(@level)
  CloseAndDelete("l17.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL18BackSentinel()
  BeginCase("L18", "Back side -1 remains a sentinel")
  Protected level.MapLevel
  Protected front.l, back.l

  BuildTwoSectorMap()
  WriteMapWad("l18.wad")
  OpenMapWad("l18.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MapLevelGetLinedefLinks(@level, 1, @front, @back)), "one-sided line readable")
  Check(Bool(front = 1 And back = -1), "back sector is -1")
  MapLevelReset(@level)
  CloseAndDelete("l18.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL19NegativeBack()
  BeginCase("L19", "Negative back side other than -1")
  Protected level.MapLevel

  BuildTwoSectorMap()
  Put16(gLump(2), 12, -2)
  WriteMapWad("l19.wad")
  OpenMapWad("l19.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "back side -2 rejected")
  MapLevelReset(@level)
  CloseAndDelete("l19.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL20TwoSidedNoBack()
  BeginCase("L20", "ML_TWOSIDED without a back side")
  Protected level.MapLevel

  BuildTwoSectorMap()
  Put16(gLump(2), 4, #MAP_ML_TWOSIDED)
  Put16(gLump(2), 12, -1)
  WriteMapWad("l20.wad")
  OpenMapWad("l20.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "two-sided flag without back side rejected")
  MapLevelReset(@level)
  CloseAndDelete("l20.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL21SegLinks()
  BeginCase("L21", "Valid seg links through linedef/sidedef")
  Protected level.MapLevel
  Protected line.l, side.l, front.l, back.l

  BuildTwoSectorMap()
  WriteMapWad("l21.wad")
  OpenMapWad("l21.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MapLevelGetSegLinks(@level, 0, @line, @side, @front, @back)), "seg links readable")
  Check(Bool(line = 0 And side = 0 And front = 0 And back = 1), "seg resolves line 0 side 0 sectors 0/1")
  MapLevelReset(@level)
  CloseAndDelete("l21.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL22BadSegSide()
  BeginCase("L22", "Seg side outside 0/1")
  Protected level.MapLevel

  BuildTwoSectorMap()
  Put16(gLump(5), 8, 2)
  WriteMapWad("l22.wad")
  OpenMapWad("l22.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "seg side 2 rejected")
  MapLevelReset(@level)
  CloseAndDelete("l22.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL23BadSegIndices()
  BeginCase("L23", "Seg vertex and linedef indexes out of range")
  Protected level.MapLevel

  BuildTwoSectorMap()
  Put16(gLump(5), 0, 99)
  WriteMapWad("l23a.wad")
  OpenMapWad("l23a.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "seg vertex 99 rejected")
  CloseAndDelete("l23a.wad")

  BuildTwoSectorMap()
  Put16(gLump(5), 6, 99)
  WriteMapWad("l23b.wad")
  OpenMapWad("l23b.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "seg linedef 99 rejected")
  MapLevelReset(@level)
  CloseAndDelete("l23b.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL24SubsectorRange()
  BeginCase("L24", "Subsector seg range outside SEGS")
  Protected level.MapLevel

  BuildTwoSectorMap()
  WriteMapWad("l24a.wad")
  Put16(gLump(6), 0, 2)
  Put16(gLump(6), 2, 1)
  WriteMapWad("l24a.wad")
  OpenMapWad("l24a.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "firstseg+numsegs beyond SEGS rejected")
  CloseAndDelete("l24a.wad")

  BuildTwoSectorMap()
  Put16(gLump(6), 0, 2)
  Put16(gLump(6), 2, 65535)
  WriteMapWad("l24b.wad")
  OpenMapWad("l24b.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "u16 overflow range rejected")
  MapLevelReset(@level)
  CloseAndDelete("l24b.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL25SubsectorSectorAndMembership()
  BeginCase("L25", "Subsector sector and deduplicated sector membership")
  Protected level.MapLevel
  Protected line.l

  BuildTwoSectorMap()
  ; Make the back side use the same sector as the front: line appears once.
  Put16(gLump(3), 58, 0)
  WriteMapWad("l25.wad")
  OpenMapWad("l25.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MapLevelGetSubsectorSector(@level, 0) = 0), "subsector sector from first seg")
  Check(Bool(MapLevelGetSectorLineCount(@level, 0) = 1), "same-sector back side is not duplicated")
  Check(Bool(MapLevelGetSectorLine(@level, 0, 0, @line) And line = 0), "first sector line is line 0")
  Check(Bool(MapLevelGetSectorLineCount(@level, 1) = 1), "other sector has one line")
  Check(Bool(MapLevelGetSectorLine(@level, 1, 0, @line) And line = 1), "second sector line is line 1")
  MapLevelReset(@level)
  CloseAndDelete("l25.wad")
  FreeMapBuffers()
EndProcedure

; ---------------------------------------------------------------------------
; L26 - L37: BSP
; ---------------------------------------------------------------------------

Procedure TestL26SingleNode()
  BeginCase("L26", "Single node with two subsector leaves")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(2)
  SetNodes(1)
  SetNode(0, 0, 0, 1, 0, $8000, $8001)
  WriteMapWad("l26.wad")
  OpenMapWad("l26.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "single-node BSP loads")
  Check(Bool(level\BspRootIsSubsector = 0 And level\BspRootIndex = 0), "root is node 0")
  Check(Bool(level\ReachableNodes = 1 And level\ReachableSubsectors = 2), "reachability counts")
  MapLevelReset(@level)
  CloseAndDelete("l26.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL27AcyclicTree()
  BeginCase("L27", "Multi-node acyclic BSP tree")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(3)
  SetNodes(2)
  SetNode(0, 0, 0, 1, 0, $8000, $8001)
  SetNode(1, 0, 0, 1, 1, 0, $8002)
  WriteMapWad("l27.wad")
  OpenMapWad("l27.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "acyclic tree loads")
  Check(Bool(level\BspRootIsSubsector = 0 And level\BspRootIndex = 1), "last node is the root")
  Check(Bool(level\ReachableNodes = 2 And level\ReachableSubsectors = 3), "all nodes/subsectors reachable")
  MapLevelReset(@level)
  CloseAndDelete("l27.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL28LeafZero()
  BeginCase("L28", "NF_SUBSECTOR leaf zero")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(2)
  SetNodes(1)
  SetNode(0, 0, 0, 1, 0, $8000, $8001)
  WriteMapWad("l28.wad")
  OpenMapWad("l28.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "leaf 0 accepted")
  Check(Bool(level\ReachableSubsectors = 2), "both leaves reached")
  MapLevelReset(@level)
  CloseAndDelete("l28.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL29InvalidNodeChild()
  BeginCase("L29", "Invalid node child index")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(2)
  SetNodes(1)
  SetNode(0, 0, 0, 1, 0, 5, $8001)
  WriteMapWad("l29.wad")
  OpenMapWad("l29.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "node child 5 rejected")
  MapLevelReset(@level)
  CloseAndDelete("l29.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL30InvalidLeaf()
  BeginCase("L30", "Invalid subsector leaf index")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(2)
  SetNodes(1)
  SetNode(0, 0, 0, 1, 0, $8002, $8001)
  WriteMapWad("l30.wad")
  OpenMapWad("l30.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "leaf 2 with two subsectors rejected")
  MapLevelReset(@level)
  CloseAndDelete("l30.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL31SelfCycle()
  BeginCase("L31", "Node self-cycle")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(1)
  SetNodes(1)
  SetNode(0, 0, 0, 1, 0, 0, $8000)
  WriteMapWad("l31.wad")
  OpenMapWad("l31.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "self-cycle rejected")
  Check(Bool(FindString(MapLevelLastError(), "cycle") > 0), "error mentions cycle")
  MapLevelReset(@level)
  CloseAndDelete("l31.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL32TwoNodeCycle()
  BeginCase("L32", "Two-node cycle")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(1)
  SetNodes(2)
  SetNode(0, 0, 0, 1, 0, 1, $8000)
  SetNode(1, 0, 0, 1, 0, 0, $8000)
  WriteMapWad("l32.wad")
  OpenMapWad("l32.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "two-node cycle rejected")
  MapLevelReset(@level)
  CloseAndDelete("l32.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL33DeepCycle()
  BeginCase("L33", "Three-node cycle")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(1)
  SetNodes(3)
  SetNode(0, 0, 0, 1, 0, 1, $8000)
  SetNode(1, 0, 0, 1, 0, 2, $8000)
  SetNode(2, 0, 0, 1, 0, 0, $8000)
  WriteMapWad("l33.wad")
  OpenMapWad("l33.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "three-node cycle rejected")
  MapLevelReset(@level)
  CloseAndDelete("l33.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL34ZeroNodeOneSub()
  BeginCase("L34", "Zero-node one-subsector special case")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l34.wad")
  OpenMapWad("l34.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "zero-node one-subsector map loads")
  Check(Bool(level\BspRootIsSubsector = 1 And level\BspRootIndex = 0), "root is subsector 0")
  MapLevelReset(@level)
  CloseAndDelete("l34.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL35ZeroNodeMultiSub()
  BeginCase("L35", "Zero-node multi-subsector case")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(2)
  WriteMapWad("l35.wad")
  OpenMapWad("l35.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "zero-node multi-subsector rejected")
  Check(Bool(FindString(MapLevelLastError(), "exactly one subsector") > 0), "error explains the exception")
  MapLevelReset(@level)
  CloseAndDelete("l35.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL36UnreachableNode()
  BeginCase("L36", "Unreachable node is reported, not fatal")
  Protected level.MapLevel

  BuildDefaultMap()
  SetSubsectors(2)
  SetNodes(2)
  SetNode(0, 0, 0, 1, 0, $8000, $8001)
  SetNode(1, 0, 0, 1, 0, $8000, $8001)
  WriteMapWad("l36.wad")
  OpenMapWad("l36.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map with an unreachable node loads")
  Check(Bool(level\ReachableNodes = 1 And level\UnreachableNodes = 1), "unreachable node counted")
  MapLevelReset(@level)
  CloseAndDelete("l36.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL37DeepChain()
  BeginCase("L37", "Deep acyclic chain is iterative")
  Protected level.MapLevel
  Protected depth.i = 200
  Protected i.i

  BuildDefaultMap()
  SetSubsectors(depth + 1)
  SetNodes(depth)
  For i = 0 To depth - 1
    If i = 0
      SetNode(i, 0, 0, 1, 0, $8000, $8000 + depth)
    Else
      SetNode(i, 0, 0, 1, 0, $8000 + i, i - 1)
    EndIf
  Next
  WriteMapWad("l37.wad")
  OpenMapWad("l37.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "200-node chain loads without stack recursion")
  Check(Bool(level\ReachableNodes = depth And level\ReachableSubsectors = depth + 1), "deep chain fully reachable")
  MapLevelReset(@level)
  CloseAndDelete("l37.wad")
  FreeMapBuffers()
EndProcedure

; ---------------------------------------------------------------------------
; L38 - L52: REJECT, BLOCKMAP, resources, lifecycle, CLI contract
; ---------------------------------------------------------------------------

Procedure TestL38RejectExact()
  BeginCase("L38", "Exact ceil(N^2/8) REJECT length")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l38.wad")
  OpenMapWad("l38.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "1-byte REJECT for one sector accepted")
  Check(Bool(level\RejectRequired = 1), "required size is 1")
  MapLevelReset(@level)
  CloseAndDelete("l38.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL39RejectShort()
  BeginCase("L39", "REJECT one byte short")
  Protected level.MapLevel

  BuildDefaultMap()
  NewLump(9, 0)
  WriteMapWad("l39.wad")
  OpenMapWad("l39.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "empty REJECT rejected")
  Check(Bool(FindString(MapLevelLastError(), "too short") > 0), "error mentions short REJECT")
  MapLevelReset(@level)
  CloseAndDelete("l39.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL40RejectPadding()
  BeginCase("L40", "REJECT padding allowed and bits addressable")
  Protected level.MapLevel

  BuildDefaultMap()
  NewLump(9, 8)
  PokeA(gLump(9), $01)
  WriteMapWad("l40.wad")
  OpenMapWad("l40.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "padded REJECT accepted")
  Check(Bool(level\Reject\Size = 8), "padding is preserved")
  Check(Bool(MapRejectGetBit(@level\Reject, 1, 0, 0) = 1), "actual matrix bit readable")
  MapLevelReset(@level)
  CloseAndDelete("l40.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL41BlockmapValid()
  BeginCase("L41", "Valid one-cell BLOCKMAP line list")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l41.wad")
  OpenMapWad("l41.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "valid BLOCKMAP accepted")
  Check(Bool(level\BlockmapCells = 1), "one blockmap cell")
  MapLevelReset(@level)
  CloseAndDelete("l41.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL42BlockmapBadLine()
  BeginCase("L42", "BLOCKMAP line index out of range")
  Protected level.MapLevel

  BuildDefaultMap()
  Put16(gLump(10), 12, 99)
  WriteMapWad("l42.wad")
  OpenMapWad("l42.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "line 99 rejected")
  Check(Bool(FindString(MapLevelLastError(), "BLOCKMAP") > 0), "error identifies BLOCKMAP")
  MapLevelReset(@level)
  CloseAndDelete("l42.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL43BlockmapTerminator()
  BeginCase("L43", "BLOCKMAP terminator is not a linedef")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l43.wad")
  OpenMapWad("l43.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "terminator alone does not create a bad line reference")
  Check(Bool(MapBlockmapGetLine(@level\Blockmap, 0, 0, 0, 0) And 0 = 0), "only the real line is exposed")
  MapLevelReset(@level)
  CloseAndDelete("l43.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL44BlockmapShared()
  BeginCase("L44", "Shared BLOCKMAP offsets")
  Protected level.MapLevel

  BuildDefaultMap()
  NewLump(10, 16)
  Put16(gLump(10), 4, 2)
  Put16(gLump(10), 6, 1)
  Put16(gLump(10), 8, 6)
  Put16(gLump(10), 10, 6)
  Put16(gLump(10), 12, 0)
  Put16(gLump(10), 14, $FFFF)
  WriteMapWad("l44.wad")
  OpenMapWad("l44.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "shared offsets accepted")
  Check(Bool(level\BlockmapCells = 2), "two cells")
  MapLevelReset(@level)
  CloseAndDelete("l44.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL45BlockmapBadOffset()
  BeginCase("L45", "Malformed BLOCKMAP offset/list propagates")
  Protected level.MapLevel

  BuildDefaultMap()
  Put16(gLump(10), 8, 4)
  WriteMapWad("l45.wad")
  OpenMapWad("l45.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "offset into table rejected")
  MapLevelReset(@level)
  CloseAndDelete("l45.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL46BlockmapHuge()
  BeginCase("L46", "Large BLOCKMAP dimensions bounded")
  Protected level.MapLevel

  BuildDefaultMap()
  Put16(gLump(10), 4, $FFFF)
  Put16(gLump(10), 6, $FFFF)
  WriteMapWad("l46.wad")
  OpenMapWad("l46.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "huge blockmap rejected")
  MapLevelReset(@level)
  CloseAndDelete("l46.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL47NoCatalogs()
  BeginCase("L47", "Structural map validates without resource catalogs")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l47.wad")
  OpenMapWad("l47.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads without catalogs")
  Check(Bool(MapLevelValidateResources(@level, 0, 0)), "null catalogs skip binding")
  MapLevelReset(@level)
  CloseAndDelete("l47.wad")
  FreeMapBuffers()
EndProcedure

Procedure.i MakeWallTextureCatalog(*Catalog.TextureCatalog)
  Protected memory.i = NewZero(30)
  Protected ok.i

  PokeL(memory, 1)        ; texture count = 1
  PokeL(memory + 4, 8)    ; definition offset
  PutName8(memory, 8, "WALL")
  PokeL(memory + 16, 0)   ; masked
  Put16(memory, 20, 64)   ; width
  Put16(memory, 22, 64)   ; height
  PokeL(memory + 24, 0)   ; column directory
  Put16(memory, 28, 0)    ; patch count = 0
  ok = TextureCatalogDecode(memory, 30, 0, 0, 0, *Catalog)
  FreeMemory(memory)
  ProcedureReturn ok
EndProcedure

Procedure TestL48ResourceSentinel()
  BeginCase("L48", "Resource binding honors - texture sentinel")
  Protected level.MapLevel
  Protected catalog.TextureCatalog

  BuildDefaultMap()
  PutName8(gLump(3), 4, "WALL")
  WriteMapWad("l48.wad")
  OpenMapWad("l48.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MakeWallTextureCatalog(@catalog)), "synthetic texture catalog builds")
  Check(Bool(MapLevelValidateResources(@level, 0, @catalog)), "WALL found and - slots skipped")
  TextureCatalogReset(@catalog)
  MapLevelReset(@level)
  CloseAndDelete("l48.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL49ResourceMalformed()
  BeginCase("L49", "Resource binding rejects malformed names")
  Protected level.MapLevel
  Protected catalog.TextureCatalog

  BuildDefaultMap()
  PokeA(gLump(3) + 4, Asc("A"))
  PokeA(gLump(3) + 5, 0)
  PokeA(gLump(3) + 6, Asc("B"))
  WriteMapWad("l49.wad")
  OpenMapWad("l49.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "structural map loads")
  Check(Bool(MakeWallTextureCatalog(@catalog)), "catalog builds")
  Check(Bool(MapLevelValidateResources(@level, 0, @catalog) = #False), "embedded-NUL texture name rejected")
  TextureCatalogReset(@catalog)
  MapLevelReset(@level)
  CloseAndDelete("l49.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL50WadReload()
  BeginCase("L50", "WAD A to WAD B reload has no stale level")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l50a.wad")
  OpenMapWad("l50a.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) And level\Linedefs\Count = 4), "WAD A loads")
  WADClose()

  BuildDefaultMap()
  NewLump(1, 20)
  WriteMapWad("l50b.wad")
  OpenMapWad("l50b.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) And level\Things\Count = 2), "WAD B replaces level")
  Check(Bool(level\Linedefs\Count = 4), "fresh WAD B records are used")
  MapLevelReset(@level)
  CloseAndDelete("l50b.wad")
  DeleteFile(FixturePath("l50a.wad"))
  FreeMapBuffers()
EndProcedure

Procedure TestL51RepeatedLoadCleanup()
  BeginCase("L51", "Repeated load/reset and late error cleanup")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l51.wad")
  OpenMapWad("l51.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "first load")
  Check(Bool(MapLevelReset(@level)), "reset")
  WADClose()
  Put16(gLump(10), 12, 5)   ; late out-of-range BLOCKMAP linedef
  WriteMapWad("l51.wad")
  OpenMapWad("l51.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "late validation error")
  Check(Bool(MapLevelIsReady(@level) = #False), "failed load leaves empty level")
  MapLevelReset(@level)
  Check(Bool(MapLevelReset(@level)), "reset after failure")
  CloseAndDelete("l51.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestL52CliContract()
  BeginCase("L52", "Map-info diagnostics contract")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("l52.wad")
  OpenMapWad("l52.wad")
  Check(Bool(MapLevelLoad("e1m1", @level)), "lowercase map query accepted")
  Check(Bool(level\MarkerIndex = 0), "diagnostic marker index available")
  Check(Bool(level\RejectRequired = 1 And level\BlockmapCells = 1), "diagnostic REJECT/BLOCKMAP values available")
  Check(Bool(MapLevelGetBspRoot(@level, 0, 0)), "diagnostic BSP root accessor available")
  MapLevelReset(@level)
  CloseAndDelete("l52.wad")
  Check(Bool(MapLevelIsReady(@level) = #False), "reset leaves a clean diagnostic state")
  FreeMapBuffers()
EndProcedure

; ---------------------------------------------------------------------------
; I01 - I03
; ---------------------------------------------------------------------------

Procedure TestI01MinimalComplete()
  BeginCase("I01", "Minimal complete synthetic E1M1")
  Protected level.MapLevel
  Protected front.l, back.l
  Protected rootLeaf.l, rootIndex.l
  Protected line.l

  BuildDefaultMap()
  Check(Bool(WriteMapWad("i01.wad")), "WAD created")
  Check(Bool(OpenMapWad("i01.wad")), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level)), "level loads and validates")
  Check(Bool(MapLevelGetLinedefLinks(@level, 0, @front, @back)), "line link readable")
  Check(Bool(front = 0 And back = -1), "front sector and back sentinel")
  Check(Bool(MapLevelGetBspRoot(@level, @rootLeaf, @rootIndex) And rootLeaf = 1 And rootIndex = 0), "subsector root")
  Check(Bool(MapLevelGetSectorLineCount(@level, 0) = 4), "four sector lines")
  Check(Bool(MapLevelGetSectorLine(@level, 0, 3, @line) And line = 3), "sector line order preserved")
  MapLevelReset(@level)
  Check(Bool(MapLevelIsReady(@level) = #False), "reset clears readiness")
  CloseAndDelete("i01.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestI02CorruptMaps()
  BeginCase("I02", "Corrupt synthetic maps fail cleanly")
  Protected level.MapLevel

  BuildDefaultMap()
  WriteMapWad("i02a.wad", 0, 3)   ; missing SIDEDEFS name
  OpenMapWad("i02a.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "misnamed lump rejected")
  CloseAndDelete("i02a.wad")

  BuildTwoSectorMap()
  Put16(gLump(5), 8, 9)   ; invalid seg side
  WriteMapWad("i02b.wad")
  OpenMapWad("i02b.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "invalid seg side rejected")
  CloseAndDelete("i02b.wad")

  BuildDefaultMap()
  SetSubsectors(2)
  SetNodes(1)
  SetNode(0, 0, 0, 1, 0, 9, $8001)
  WriteMapWad("i02c.wad")
  OpenMapWad("i02c.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "invalid node child rejected")
  CloseAndDelete("i02c.wad")

  BuildDefaultMap()
  NewLump(9, 0)
  WriteMapWad("i02d.wad")
  OpenMapWad("i02d.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "undersized REJECT rejected")
  CloseAndDelete("i02d.wad")

  BuildDefaultMap()
  Put16(gLump(10), 12, 88)
  WriteMapWad("i02e.wad")
  OpenMapWad("i02e.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "out-of-range blockmap line rejected")
  Check(Bool(WADFindLump("E1M1") >= 0), "unrelated WAD lookup still works")
  MapLevelReset(@level)
  CloseAndDelete("i02e.wad")
  FreeMapBuffers()
EndProcedure

Procedure TestI03WadABOwnership()
  BeginCase("I03", "WAD A to WAD B with owned first level")
  Protected level.MapLevel
  Protected firstReady.i

  BuildDefaultMap()
  WriteMapWad("i03a.wad")
  OpenMapWad("i03a.wad")
  Check(Bool(MapLevelLoad("E1M1", @level)), "WAD A level loads")
  firstReady = MapLevelIsReady(@level)
  WADClose()
  Check(Bool(firstReady = 1 And level\Linedefs\Count = 4), "owned level survives WAD close")
  Check(Bool(MapLevelGetSectorLineCount(@level, 0) = 4), "owned derived links survive close")
  MapLevelReset(@level)

  BuildDefaultMap()
  NewLump(1, 20)
  WriteMapWad("i03b.wad")
  OpenMapWad("i03b.wad")
  Check(Bool(MapLevelLoad("E1M1", @level) And level\Things\Count = 2), "WAD B loads into the same object")
  MapLevelReset(@level)
  CloseAndDelete("i03b.wad")
  DeleteFile(FixturePath("i03a.wad"))
  FreeMapBuffers()
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB map loader/validation tests (M2-06)")

If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

TestL01ValidLoad()
TestL02MissingMarker()
TestL03DuplicateMarker()
TestL04MissingLump()
TestL05WrongOrder()
TestL06Truncated()
TestL07NonzeroMarker()
TestL08InvalidNames()
TestL09BadRecordLength()
TestL10SecondLevel()
TestL11FailureAfterSuccess()
TestL12ResetAndOwnership()
TestL13ValidVertices()
TestL14BadVertex()
TestL15FrontBackSectors()
TestL16BadSidedefSector()
TestL17BadFrontSide()
TestL18BackSentinel()
TestL19NegativeBack()
TestL20TwoSidedNoBack()
TestL21SegLinks()
TestL22BadSegSide()
TestL23BadSegIndices()
TestL24SubsectorRange()
TestL25SubsectorSectorAndMembership()
TestL26SingleNode()
TestL27AcyclicTree()
TestL28LeafZero()
TestL29InvalidNodeChild()
TestL30InvalidLeaf()
TestL31SelfCycle()
TestL32TwoNodeCycle()
TestL33DeepCycle()
TestL34ZeroNodeOneSub()
TestL35ZeroNodeMultiSub()
TestL36UnreachableNode()
TestL37DeepChain()
TestL38RejectExact()
TestL39RejectShort()
TestL40RejectPadding()
TestL41BlockmapValid()
TestL42BlockmapBadLine()
TestL43BlockmapTerminator()
TestL44BlockmapShared()
TestL45BlockmapBadOffset()
TestL46BlockmapHuge()
TestL47NoCatalogs()
TestL48ResourceSentinel()
TestL49ResourceMalformed()
TestL50WadReload()
TestL51RepeatedLoadCleanup()
TestL52CliContract()

TestI01MinimalComplete()
TestI02CorruptMaps()
TestI03WadABOwnership()

CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
