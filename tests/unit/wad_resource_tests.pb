; -----------------------------------------------------------------------------
; DoomPB - COLORMAP and PNAMES decoder tests (M2-01)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; All decoder inputs are synthesized in memory. I01-I03 build disposable
; synthetic WADs in the ignored build/ tree to exercise the existing lookup and
; read APIs with the new decoders. No Doom resources are copied or required.
;
; Exit code: 0 when every assertion passed, otherwise the number of failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

Global gFixtureDirectory.s = ""
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

Procedure.s FixturePath(FileName.s)
  ProcedureReturn gFixtureDirectory + FileName
EndProcedure

Procedure.i PrepareFixtureDirectory()
  Protected directorySize.i

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "wad-resource-test-tmp" + #FixtureSeparator
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

; ---------------------------------------------------------------------------
; Synthetic fixtures
; ---------------------------------------------------------------------------

Procedure WriteU32Memory(*Memory.Byte, Offset.i, Value.q)
  PokeA(*Memory + Offset, Value & $FF)
  PokeA(*Memory + Offset + 1, (Value >> 8) & $FF)
  PokeA(*Memory + Offset + 2, (Value >> 16) & $FF)
  PokeA(*Memory + Offset + 3, (Value >> 24) & $FF)
EndProcedure

Procedure WriteU32File(file.i, Value.q)
  WriteByte(file, Value & $FF)
  WriteByte(file, (Value >> 8) & $FF)
  WriteByte(file, (Value >> 16) & $FF)
  WriteByte(file, (Value >> 24) & $FF)
EndProcedure

Procedure WriteWadHeader(file.i, Magic.s, LumpCount.q, DirectoryOffset.q)
  WriteString(file, Magic)
  WriteU32File(file, LumpCount)
  WriteU32File(file, DirectoryOffset)
EndProcedure

Procedure WriteLumpEntry(file.i, Position.q, Size.q, Name.s)
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

; COLORMAP fixture: TableCount tables; byte i of table m = (m*17 + i) & 255.
Procedure.i MakeColormap(TableCount.i)
  Protected length.i = TableCount * 256
  Protected memory.i = AllocateMemory(length)
  Protected m.i
  Protected i.i

  If memory = 0
    ProcedureReturn 0
  EndIf
  For m = 0 To TableCount - 1
    For i = 0 To 255
      PokeA(memory + m * 256 + i, (m * 17 + i) & $FF)
    Next
  Next
  ProcedureReturn memory
EndProcedure

; PNAMES fixture with zero-filled names; the caller fills the name bytes.
Procedure.i MakePNames(NameCount.i)
  Protected memory.i = AllocateMemory(4 + NameCount * 8)

  If memory <> 0
    FillMemory(memory, 4 + NameCount * 8, 0)
    WriteU32Memory(memory, 0, NameCount)
  EndIf
  ProcedureReturn memory
EndProcedure

Procedure SetName(*PNamesMemory.Byte, NameIndex.i, Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      PokeA(*PNamesMemory + 4 + NameIndex * 8 + i, Asc(Mid(Name, i + 1, 1)))
    Else
      PokeA(*PNamesMemory + 4 + NameIndex * 8 + i, 0)
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------------------
; C01 - C13: COLORMAP
; ---------------------------------------------------------------------------

Procedure TestC01SingleTable()
  BeginCase("C01", "One complete 256-byte colormap table")
  Protected memory.i = MakeColormap(1)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "synthetic table allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(ColormapDecode(memory, 256, @cm)), "one table decodes")
  Check(Bool(ColormapCount(@cm) = 1), "count is 1")
  Check(Bool(ColormapLookup(@cm, 0, 0) = 0), "entry 0 is 0")
  Check(Bool(ColormapLookup(@cm, 0, 128) = 128), "entry 128 is 128")
  Check(Bool(ColormapLookup(@cm, 0, 255) = 255), "entry 255 is 255")
  Check(Bool(ColormapLastError() = ""), "successful lookup clears the error")
  ColormapReset(@cm)
  FreeMemory(memory)
EndProcedure

Procedure TestC02MultipleTables()
  BeginCase("C02", "Multiple tables and the 256-byte row stride")
  Protected memory.i = MakeColormap(3)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "synthetic tables allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(ColormapDecode(memory, 3 * 256, @cm)), "three tables decode")
  Check(Bool(ColormapCount(@cm) = 3), "count is 3")
  Check(Bool(ColormapLookup(@cm, 0, 0) = 0), "table 0 entry 0")
  Check(Bool(ColormapLookup(@cm, 1, 0) = 17), "table 1 entry 0 uses the 256-byte stride")
  Check(Bool(ColormapLookup(@cm, 1, 1) = 18), "table 1 entry 1")
  Check(Bool(ColormapLookup(@cm, 2, 255) = 33), "table 2 entry 255 wraps as stored")
  ColormapReset(@cm)
  FreeMemory(memory)
EndProcedure

Procedure TestC03UnsignedBytes()
  BeginCase("C03", "Palette-index values 0, 128 and 255")
  Protected memory.i = AllocateMemory(256)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "synthetic table allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 256, 0)
  PokeA(memory, 0)
  PokeA(memory + 1, 200)
  PokeA(memory + 128, 128)
  PokeA(memory + 255, 255)
  Check(Bool(ColormapDecode(memory, 256, @cm)), "table decodes")
  Check(Bool(ColormapLookup(@cm, 0, 0) = 0), "zero is preserved")
  Check(Bool(ColormapLookup(@cm, 0, 1) = 200), "ordinary value is preserved")
  Check(Bool(ColormapLookup(@cm, 0, 128) = 128), "high-bit 128 stays unsigned")
  Check(Bool(ColormapLookup(@cm, 0, 255) = 255), "255 is preserved")
  ColormapReset(@cm)
  FreeMemory(memory)
EndProcedure

Procedure TestC04NullData()
  BeginCase("C04", "Null data pointer with positive length")
  Protected cm.ColormapSet

  Check(Bool(ColormapDecode(0, 256, @cm) = #False), "null pointer is rejected")
  Check(Bool(FindString(ColormapLastError(), "null") > 0), "error mentions the null pointer")
  Check(Bool(ColormapCount(@cm) = 0), "no colormap data survives the failure")
EndProcedure

Procedure TestC05ZeroAndNegativeLength()
  BeginCase("C05", "Zero and negative input lengths")
  Protected memory.i = AllocateMemory(256)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 256, 0)
  Check(Bool(ColormapDecode(memory, 0, @cm) = #False), "zero length is rejected")
  Check(Bool(ColormapDecode(memory, -256, @cm) = #False), "negative length is rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestC06PartialTables()
  BeginCase("C06", "Incomplete 256-byte tables")
  Protected memory.i = AllocateMemory(512)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 512, 0)
  Check(Bool(ColormapDecode(memory, 255, @cm) = #False), "length 255 is rejected")
  Check(Bool(ColormapDecode(memory, 257, @cm) = #False), "length 257 is rejected")
  Check(Bool(ColormapDecode(memory, 511, @cm) = #False), "length 511 is rejected")
  Check(Bool(ColormapDecode(memory, 512, @cm) = #True), "length 512 is accepted")
  Check(Bool(ColormapCount(@cm) = 2), "512 bytes decode as two tables")
  ColormapReset(@cm)
  FreeMemory(memory)
EndProcedure

Procedure TestC07ThirtyFourTables()
  BeginCase("C07", "34-table synthetic input")
  Protected memory.i = MakeColormap(34)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "34 tables allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(ColormapDecode(memory, 34 * 256, @cm)), "34 tables decode")
  Check(Bool(ColormapCount(@cm) = 34), "count is 34")
  Check(Bool(ColormapLookup(@cm, 33, 0) = ((33 * 17 + 0) & $FF)), "last table entry 0")
  Check(Bool(ColormapLookup(@cm, 33, 255) = ((33 * 17 + 255) & $FF)), "last table entry 255 wraps as stored")
  Check(Bool(ColormapLookup(@cm, 31, 10) = ((31 * 17 + 10) & $FF)), "lighting-table boundary entry")
  ColormapReset(@cm)
  FreeMemory(memory)
EndProcedure

Procedure TestC08TableCap()
  BeginCase("C08", "Safety cap and oversize length")
  Protected over.i = MakeColormap(257)
  Protected atCap.i = MakeColormap(256)
  Protected cm.ColormapSet

  Check(Bool(over <> 0 And atCap <> 0), "cap fixtures allocated")
  If over = 0 Or atCap = 0
    If over <> 0
      FreeMemory(over)
    EndIf
    If atCap <> 0
      FreeMemory(atCap)
    EndIf
    ProcedureReturn
  EndIf

  Check(Bool(ColormapDecode(over, 257 * 256, @cm) = #False), "257 tables are rejected")
  Check(Bool(FindString(ColormapLastError(), "too many") > 0), "cap error is specific")
  Check(Bool(ColormapCount(@cm) = 0), "cap failure leaves no data")

  Check(Bool(ColormapDecode(atCap, 256 * 256, @cm)), "256 tables are accepted at the cap")
  Check(Bool(ColormapCount(@cm) = 256), "cap count is 256")
  Check(Bool(ColormapLookup(@cm, 255, 255) = ((255 * 17 + 255) & $FF)), "last entry at the cap is readable")
  ColormapReset(@cm)
  FreeMemory(over)
  FreeMemory(atCap)
EndProcedure

Procedure TestC09InvalidMapIndex()
  BeginCase("C09", "Invalid colormap indices")
  Protected memory.i = MakeColormap(2)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "tables allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(ColormapDecode(memory, 512, @cm)), "two tables decode")
  Check(Bool(ColormapLookup(@cm, -1, 0) = -1), "map index -1 is rejected")
  Check(Bool(ColormapLookup(@cm, 2, 0) = -1), "map index == count is rejected")
  Check(Bool(ColormapLookup(@cm, 99999, 0) = -1), "large map index is rejected")
  Check(Bool(FindString(ColormapLastError(), "out of range") > 0), "error explains the range")
  ColormapReset(@cm)
  FreeMemory(memory)
EndProcedure

Procedure TestC10InvalidColorIndex()
  BeginCase("C10", "Invalid palette-index lookups")
  Protected memory.i = MakeColormap(1)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "table allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(ColormapDecode(memory, 256, @cm)), "table decodes")
  Check(Bool(ColormapLookup(@cm, 0, -1) = -1), "color index -1 is rejected")
  Check(Bool(ColormapLookup(@cm, 0, 256) = -1), "color index 256 is rejected")
  Check(Bool(ColormapLookup(@cm, 0, 99999) = -1), "large color index is rejected")
  ColormapReset(@cm)
  FreeMemory(memory)
EndProcedure

Procedure TestC11InputIndependence()
  BeginCase("C11", "Decoded data survives freeing the input")
  Protected memory.i = AllocateMemory(258)
  Protected cm.ColormapSet

  Check(Bool(memory <> 0), "guarded buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 258, $CC)
  FillMemory(memory + 1, 256, $5A)
  Check(Bool(ColormapDecode(memory + 1, 256, @cm)), "table decodes from an unaligned address")
  Check(Bool(PeekA(memory) = $CC And PeekA(memory + 257) = $CC), "input guards are intact")
  FreeMemory(memory)
  memory = 0
  Check(Bool(ColormapLookup(@cm, 0, 10) = $5A), "lookup still works after input is freed")
  ColormapReset(@cm)
EndProcedure

Procedure TestC12RepeatedDecodeAndReset()
  BeginCase("C12", "Repeated decode and reset")
  Protected first.i = MakeColormap(1)
  Protected second.i = MakeColormap(2)
  Protected cm.ColormapSet

  Check(Bool(first <> 0 And second <> 0), "fixtures allocated")
  If first = 0 Or second = 0
    ProcedureReturn
  EndIf
  Check(Bool(ColormapDecode(first, 256, @cm)), "first decode succeeds")
  Check(Bool(ColormapDecode(second, 512, @cm)), "second decode replaces the first")
  Check(Bool(ColormapCount(@cm) = 2), "replacement count is 2")
  Check(Bool(ColormapLookup(@cm, 1, 0) = 17), "replacement data is active")
  Check(Bool(ColormapReset(@cm)), "reset succeeds")
  Check(Bool(cm\Tables = 0 And cm\MapCount = 0), "reset clears the data")
  Check(Bool(ColormapReset(@cm)), "second reset is idempotent")
  Check(Bool(ColormapDecode(first, 256, @cm)), "decode after reset succeeds")
  ColormapReset(@cm)
  FreeMemory(first)
  FreeMemory(second)
EndProcedure

Procedure TestC13FailureReplacementPolicy()
  BeginCase("C13", "Malformed replacement clears the previous table")
  Protected good.i = MakeColormap(1)
  Protected malformed.i = AllocateMemory(300)
  Protected cm.ColormapSet

  Check(Bool(good <> 0 And malformed <> 0), "fixtures allocated")
  If good = 0 Or malformed = 0
    ProcedureReturn
  EndIf
  FillMemory(malformed, 300, 0)
  Check(Bool(ColormapDecode(good, 256, @cm)), "valid decode succeeds")
  Check(Bool(ColormapLookup(@cm, 0, 1) = 1), "valid data is readable")
  Check(Bool(ColormapDecode(malformed, 300, @cm) = #False), "malformed replacement is rejected")
  Check(Bool(ColormapCount(@cm) = 0), "failed replacement clears the old table")
  Check(Bool(ColormapLookup(@cm, 0, 1) = -1), "old data is no longer readable")
  Check(Bool(ColormapDecode(good, 256, @cm)), "valid decode after failure succeeds")
  Check(Bool(ColormapLastError() = ""), "success clears the failure error")
  ColormapReset(@cm)
  FreeMemory(good)
  FreeMemory(malformed)
EndProcedure

; ---------------------------------------------------------------------------
; N01 - N15: PNAMES
; ---------------------------------------------------------------------------

Procedure TestN01EmptyTable()
  BeginCase("N01", "Empty PNAMES table (N=0)")
  Protected memory.i = MakePNames(0)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "4-byte fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(PNamesDecode(memory, 4, @names)), "empty table decodes")
  Check(Bool(PNamesCount(@names) = 0), "count is 0")
  Check(Bool(PNamesRawNameByte(@names, 0, 0) = -1), "no name index 0 exists")
  Check(Bool(PNamesReset(@names)), "empty table resets")
  FreeMemory(memory)
EndProcedure

Procedure TestN02ShortName()
  BeginCase("N02", "NUL-padded short name")
  Protected memory.i = MakePNames(1)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  SetName(memory, 0, "ABC")
  Check(Bool(PNamesDecode(memory, 12, @names)), "table decodes")
  Check(Bool(PNamesCount(@names) = 1), "count is 1")
  Check(Bool(PNamesRawNameByte(@names, 0, 0) = Asc("A")), "first byte is A")
  Check(Bool(PNamesRawNameByte(@names, 0, 2) = Asc("C")), "third byte is C")
  Check(Bool(PNamesRawNameByte(@names, 0, 3) = 0), "fourth byte is NUL padding")
  Check(Bool(PNamesDisplayName(@names, 0) = "ABC"), "display name stops at padding")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN03EightByteName()
  BeginCase("N03", "Exactly eight non-NUL name bytes")
  Protected memory.i = MakePNames(1)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  SetName(memory, 0, "ABCDEFGH")
  Check(Bool(PNamesDecode(memory, 12, @names)), "table decodes")
  Check(Bool(PNamesRawNameByte(@names, 0, 7) = Asc("H")), "eighth byte is readable")
  Check(Bool(PNamesDisplayName(@names, 0) = "ABCDEFGH"), "display name is exactly eight bytes")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN04OrderedNames()
  BeginCase("N04", "Several names keep their original order")
  Protected memory.i = MakePNames(3)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  SetName(memory, 0, "ONE")
  SetName(memory, 1, "TWO")
  SetName(memory, 2, "THREE")
  Check(Bool(PNamesDecode(memory, 4 + 3 * 8, @names)), "table decodes")
  Check(Bool(PNamesCount(@names) = 3), "count is 3")
  Check(Bool(PNamesDisplayName(@names, 0) = "ONE"), "index 0 is ONE")
  Check(Bool(PNamesDisplayName(@names, 1) = "TWO"), "index 1 is TWO")
  Check(Bool(PNamesDisplayName(@names, 2) = "THREE"), "index 2 is THREE")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN05Duplicates()
  BeginCase("N05", "Duplicate names are preserved")
  Protected memory.i = MakePNames(2)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  SetName(memory, 0, "DUP")
  SetName(memory, 1, "DUP")
  Check(Bool(PNamesDecode(memory, 20, @names)), "table decodes")
  Check(Bool(PNamesCount(@names) = 2), "both duplicate entries remain")
  Check(Bool(PNamesDisplayName(@names, 0) = "DUP"), "first duplicate is readable")
  Check(Bool(PNamesDisplayName(@names, 1) = "DUP"), "second duplicate is readable")
  Check(Bool(PNamesRawNameByte(@names, 0, 0) = PNamesRawNameByte(@names, 1, 0)), "duplicate bytes match")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN06EmbeddedNul()
  BeginCase("N06", "Embedded NUL and trailing name bytes")
  Protected memory.i = MakePNames(1)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  PokeA(memory + 4, Asc("A"))
  PokeA(memory + 5, 0)
  PokeA(memory + 6, Asc("B"))
  PokeA(memory + 7, 0)
  PokeA(memory + 8, Asc("C"))
  PokeA(memory + 9, 0)
  PokeA(memory + 10, 0)
  PokeA(memory + 11, 0)
  Check(Bool(PNamesDecode(memory, 12, @names)), "table decodes")
  Check(Bool(PNamesRawNameByte(@names, 0, 1) = 0), "embedded NUL is preserved")
  Check(Bool(PNamesRawNameByte(@names, 0, 2) = Asc("B")), "byte after NUL is preserved")
  Check(Bool(PNamesDisplayName(@names, 0) = "A"), "display stops at the first NUL")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN07Lowercase()
  BeginCase("N07", "Lowercase stored bytes are not uppercased")
  Protected memory.i = MakePNames(1)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  SetName(memory, 0, "lower")
  Check(Bool(PNamesDecode(memory, 12, @names)), "table decodes")
  Check(Bool(PNamesRawNameByte(@names, 0, 0) = Asc("l")), "first byte stays lowercase")
  Check(Bool(PNamesRawNameByte(@names, 0, 4) = Asc("r")), "last letter stays lowercase")
  Check(Bool(PNamesDisplayName(@names, 0) = "lower"), "display preserves lowercase")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN08HighBytes()
  BeginCase("N08", "High bytes 0x80 and 0xFF")
  Protected memory.i = MakePNames(1)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  PokeA(memory + 4, $80)
  PokeA(memory + 5, $FF)
  PokeA(memory + 6, Asc("X"))
  Check(Bool(PNamesDecode(memory, 12, @names)), "table decodes")
  Check(Bool(PNamesRawNameByte(@names, 0, 0) = $80), "0x80 is preserved unsigned")
  Check(Bool(PNamesRawNameByte(@names, 0, 1) = $FF), "0xFF is preserved unsigned")
  Check(Bool(PNamesDisplayName(@names, 0) = "..X"), "nonprintable bytes are escaped")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN09ShortHeader()
  BeginCase("N09", "Buffer shorter than the 4-byte count")
  Protected memory.i = AllocateMemory(4)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 4, 0)
  Check(Bool(PNamesDecode(memory, 0, @names) = #False), "length 0 is rejected")
  Check(Bool(PNamesDecode(memory, 3, @names) = #False), "length 3 is rejected")
  Check(Bool(PNamesDecode(0, 4, @names) = #False), "null pointer with length 4 is rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestN10NegativeCount()
  BeginCase("N10", "Negative PNAMES count")
  Protected memory.i = AllocateMemory(4)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  WriteU32Memory(memory, 0, -1)
  Check(Bool(PNamesDecode(memory, 4, @names) = #False), "count -1 is rejected")
  Check(Bool(FindString(PNamesLastError(), "negative") > 0), "error mentions the negative count")
  Check(Bool(PNamesCount(@names) = 0), "no names survive the failure")
  FreeMemory(memory)
EndProcedure

Procedure TestN11CountCap()
  BeginCase("N11", "Count above the safety cap")
  Protected memory.i = AllocateMemory(4)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  WriteU32Memory(memory, 0, 65537)
  Check(Bool(PNamesDecode(memory, 4, @names) = #False), "count 65537 is rejected")
  WriteU32Memory(memory, 0, 2147483647)
  Check(Bool(PNamesDecode(memory, 4, @names) = #False), "huge count is rejected before multiplication")
  Check(Bool(FindString(PNamesLastError(), "too many") > 0), "cap error is specific")
  FreeMemory(memory)
EndProcedure

Procedure TestN12TruncatedTable()
  BeginCase("N12", "Declared count exceeds the supplied bytes")
  Protected memory.i = AllocateMemory(20)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 20, 0)
  WriteU32Memory(memory, 0, 2)
  Check(Bool(PNamesDecode(memory, 12, @names) = #False), "one missing name is rejected")
  Check(Bool(FindString(PNamesLastError(), "truncated") > 0), "error mentions truncation")
  Check(Bool(PNamesDecode(memory, 20, @names) = #True), "complete two-name table is accepted")
  Check(Bool(PNamesCount(@names) = 2), "accepted count is 2")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN13TrailingBytes()
  BeginCase("N13", "Trailing bytes after the declared names")
  Protected memory.i = MakePNames(1)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  SetName(memory, 0, "ONE")
  Check(Bool(PNamesDecode(memory, 16, @names)), "table with four trailing bytes decodes")
  Check(Bool(PNamesCount(@names) = 1), "trailing bytes are not counted as names")
  Check(Bool(PNamesDisplayName(@names, 0) = "ONE"), "declared name is intact")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN14InvalidAccessors()
  BeginCase("N14", "Invalid name indices and byte offsets")
  Protected memory.i = MakePNames(2)
  Protected names.PNamesTable

  Check(Bool(memory <> 0), "fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  SetName(memory, 0, "A")
  SetName(memory, 1, "B")
  Check(Bool(PNamesDecode(memory, 20, @names)), "table decodes")
  Check(Bool(PNamesRawNameByte(@names, -1, 0) = -1), "name index -1 is rejected")
  Check(Bool(PNamesRawNameByte(@names, 2, 0) = -1), "name index == count is rejected")
  Check(Bool(PNamesRawNameByte(@names, 99999, 0) = -1), "large name index is rejected")
  Check(Bool(PNamesRawNameByte(@names, 0, -1) = -1), "byte offset -1 is rejected")
  Check(Bool(PNamesRawNameByte(@names, 0, 8) = -1), "byte offset 8 is rejected")
  Check(Bool(PNamesRawNameByte(@names, 0, 999) = -1), "large byte offset is rejected")
  Check(Bool(PNamesDisplayName(@names, 5) = ""), "invalid display index returns empty text")
  PNamesReset(@names)
  FreeMemory(memory)
EndProcedure

Procedure TestN15Lifetime()
  BeginCase("N15", "Reuse, reset and bad-after-good")
  Protected good.i = MakePNames(2)
  Protected bad.i = AllocateMemory(4)
  Protected names.PNamesTable

  Check(Bool(good <> 0 And bad <> 0), "fixtures allocated")
  If good = 0 Or bad = 0
    ProcedureReturn
  EndIf
  SetName(good, 0, "ONE")
  SetName(good, 1, "TWO")
  WriteU32Memory(bad, 0, -1)

  Check(Bool(PNamesDecode(good, 20, @names)), "valid decode succeeds")
  Check(Bool(PNamesReset(@names)), "reset succeeds")
  Check(Bool(names\Names = 0 And names\Count = 0), "reset releases the copy")
  Check(Bool(PNamesReset(@names)), "second reset is idempotent")
  Check(Bool(PNamesDecode(good, 20, @names)), "decode after reset succeeds")
  Check(Bool(PNamesDecode(bad, 4, @names) = #False), "bad replacement is rejected")
  Check(Bool(PNamesCount(@names) = 0), "bad replacement clears the old table")
  Check(Bool(PNamesDecode(good, 20, @names)), "good decode after bad succeeds")
  Check(Bool(PNamesDisplayName(@names, 1) = "TWO"), "recovered table is readable")
  PNamesReset(@names)
  FreeMemory(good)
  FreeMemory(bad)
EndProcedure

; ---------------------------------------------------------------------------
; I01 - I03: synthetic WAD integration
; ---------------------------------------------------------------------------

Procedure.s BuildIntegratedWad()
  Protected path.s = FixturePath("integrated.wad")
  Protected file.i
  Protected colormap.i = MakeColormap(2)
  Protected names.i = MakePNames(2)
  Protected directoryOffset.q

  If colormap = 0 Or names = 0
    If colormap <> 0
      FreeMemory(colormap)
    EndIf
    If names <> 0
      FreeMemory(names)
    EndIf
    ProcedureReturn ""
  EndIf
  SetName(names, 0, "PATCH_A")
  SetName(names, 1, "PATCH_B")

  file = CreateFile(#PB_Any, path)
  If file = 0
    FreeMemory(colormap)
    FreeMemory(names)
    ProcedureReturn ""
  EndIf
  WriteWadHeader(file, "IWAD", 2, 0)
  WriteData(file, colormap, 2 * 256)
  WriteData(file, names, 4 + 2 * 8)
  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32File(file, directoryOffset)
  FileSeek(file, directoryOffset)
  WriteLumpEntry(file, 12, 2 * 256, "COLORMAP")
  WriteLumpEntry(file, 12 + 2 * 256, 4 + 2 * 8, "PNAMES")
  CloseFile(file)
  FreeMemory(colormap)
  FreeMemory(names)
  ProcedureReturn path
EndProcedure

Procedure TestI01SyntheticWad()
  BeginCase("I01", "Synthetic WAD with COLORMAP and PNAMES")
  Protected path.s = BuildIntegratedWad()
  Protected colormapIndex.i
  Protected namesIndex.i
  Protected colormapBytes.i
  Protected namesBytes.i
  Protected colormapSize.q
  Protected namesSize.q
  Protected cm.ColormapSet
  Protected names.PNamesTable

  Check(Bool(path <> ""), "synthetic WAD created")
  If path = ""
    ProcedureReturn
  EndIf
  Check(Bool(WADOpen(path)), "WAD opens")
  colormapIndex = WADFindLump("COLORMAP")
  namesIndex = WADFindLump("PNAMES")
  Check(Bool(colormapIndex >= 0 And namesIndex >= 0), "both lumps are found")
  colormapSize = WADLumpSize(colormapIndex)
  namesSize = WADLumpSize(namesIndex)
  Check(Bool(colormapSize = 512), "COLORMAP size is 512")
  Check(Bool(namesSize = 20), "PNAMES size is 20")

  colormapBytes = AllocateMemory(colormapSize)
  namesBytes = AllocateMemory(namesSize)
  Check(Bool(colormapBytes <> 0 And namesBytes <> 0), "payload buffers allocated")
  If colormapBytes <> 0 And namesBytes <> 0
    Check(Bool(WADReadLump(colormapIndex, colormapBytes, colormapSize)), "COLORMAP reads")
    Check(Bool(WADReadLump(namesIndex, namesBytes, namesSize)), "PNAMES reads")
    Check(Bool(ColormapDecode(colormapBytes, colormapSize, @cm)), "COLORMAP decodes")
    Check(Bool(PNamesDecode(namesBytes, namesSize, @names)), "PNAMES decodes")
    Check(Bool(ColormapCount(@cm) = 2), "decoded map count is 2")
    Check(Bool(ColormapLookup(@cm, 1, 1) = 18), "integrated lookup is correct")
    Check(Bool(PNamesCount(@names) = 2), "decoded PNAMES count is 2")
    Check(Bool(PNamesDisplayName(@names, 1) = "PATCH_B"), "second patch name is correct")
  EndIf
  If colormapBytes <> 0
    FreeMemory(colormapBytes)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  ColormapReset(@cm)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
EndProcedure

Procedure.s BuildDuplicateWad()
  Protected path.s = FixturePath("duplicates.wad")
  Protected file.i
  Protected firstMap.i = AllocateMemory(256)
  Protected secondMap.i = MakeColormap(2)
  Protected firstNames.i = MakePNames(1)
  Protected secondNames.i = MakePNames(2)
  Protected directoryOffset.q

  If firstMap = 0 Or secondMap = 0 Or firstNames = 0 Or secondNames = 0
    ProcedureReturn ""
  EndIf
  FillMemory(firstMap, 256, 11)
  SetName(firstNames, 0, "FIRST")
  SetName(secondNames, 0, "SECOND")
  SetName(secondNames, 1, "THIRD")

  file = CreateFile(#PB_Any, path)
  If file = 0
    ProcedureReturn ""
  EndIf
  WriteWadHeader(file, "PWAD", 4, 0)
  WriteData(file, firstMap, 256)
  WriteData(file, secondMap, 512)
  WriteData(file, firstNames, 12)
  WriteData(file, secondNames, 20)
  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32File(file, directoryOffset)
  FileSeek(file, directoryOffset)
  WriteLumpEntry(file, 12, 256, "COLORMAP")
  WriteLumpEntry(file, 12 + 256, 512, "COLORMAP")
  WriteLumpEntry(file, 12 + 256 + 512, 12, "PNAMES")
  WriteLumpEntry(file, 12 + 256 + 512 + 12, 20, "PNAMES")
  CloseFile(file)
  FreeMemory(firstMap)
  FreeMemory(secondMap)
  FreeMemory(firstNames)
  FreeMemory(secondNames)
  ProcedureReturn path
EndProcedure

Procedure TestI02DuplicateLumps()
  BeginCase("I02", "Duplicate COLORMAP/PNAMES lumps: last entry wins")
  Protected path.s = BuildDuplicateWad()
  Protected index.i
  Protected bytes.i
  Protected size.q
  Protected cm.ColormapSet
  Protected names.PNamesTable

  Check(Bool(path <> ""), "duplicate synthetic WAD created")
  If path = ""
    ProcedureReturn
  EndIf
  Check(Bool(WADOpen(path)), "WAD opens")
  index = WADFindLump("COLORMAP")
  size = WADLumpSize(index)
  Check(Bool(index >= 0 And size = 512), "later COLORMAP is selected")
  bytes = AllocateMemory(size)
  If bytes <> 0
    Check(Bool(WADReadLump(index, bytes, size)), "later COLORMAP reads")
    Check(Bool(ColormapDecode(bytes, size, @cm)), "later COLORMAP decodes")
    Check(Bool(ColormapCount(@cm) = 2), "selected COLORMAP has 2 tables")
    Check(Bool(ColormapLookup(@cm, 0, 0) = 0), "selected COLORMAP data is correct")
    FreeMemory(bytes)
  EndIf

  index = WADFindLump("PNAMES")
  size = WADLumpSize(index)
  Check(Bool(index >= 0 And size = 20), "later PNAMES is selected")
  bytes = AllocateMemory(size)
  If bytes <> 0
    Check(Bool(WADReadLump(index, bytes, size)), "later PNAMES reads")
    Check(Bool(PNamesDecode(bytes, size, @names)), "later PNAMES decodes")
    Check(Bool(PNamesCount(@names) = 2), "selected PNAMES has 2 names")
    Check(Bool(PNamesDisplayName(@names, 0) = "SECOND"), "selected PNAMES order is intact")
    FreeMemory(bytes)
  EndIf
  ColormapReset(@cm)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
EndProcedure

Procedure TestI03MissingAndEmpty()
  BeginCase("I03", "Missing and zero-length required lumps")
  Protected path.s = FixturePath("empty_lump.wad")
  Protected file.i
  Protected index.i
  Protected cm.ColormapSet
  Protected names.PNamesTable

  file = CreateFile(#PB_Any, path)
  Check(Bool(file <> 0), "zero-length-lump WAD created")
  If file = 0
    ProcedureReturn
  EndIf
  WriteWadHeader(file, "IWAD", 1, 12)
  WriteLumpEntry(file, 0, 0, "COLORMAP")
  CloseFile(file)

  Check(Bool(WADOpen(path)), "WAD opens")
  index = WADFindLump("COLORMAP")
  Check(Bool(index >= 0 And WADLumpSize(index) = 0), "zero-length COLORMAP is found")
  Check(Bool(ColormapDecode(0, 0, @cm) = #False), "empty COLORMAP cannot be decoded")
  Check(Bool(WADFindLump("PNAMES") = -1), "missing PNAMES is not found")
  ColormapReset(@cm)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB COLORMAP/PNAMES decoder tests (M2-01)")

If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

TestC01SingleTable()
TestC02MultipleTables()
TestC03UnsignedBytes()
TestC04NullData()
TestC05ZeroAndNegativeLength()
TestC06PartialTables()
TestC07ThirtyFourTables()
TestC08TableCap()
TestC09InvalidMapIndex()
TestC10InvalidColorIndex()
TestC11InputIndependence()
TestC12RepeatedDecodeAndReset()
TestC13FailureReplacementPolicy()

TestN01EmptyTable()
TestN02ShortName()
TestN03EightByteName()
TestN04OrderedNames()
TestN05Duplicates()
TestN06EmbeddedNul()
TestN07Lowercase()
TestN08HighBytes()
TestN09ShortHeader()
TestN10NegativeCount()
TestN11CountCap()
TestN12TruncatedTable()
TestN13TrailingBytes()
TestN14InvalidAccessors()
TestN15Lifetime()

TestI01SyntheticWad()
TestI02DuplicateLumps()
TestI03MissingAndEmpty()

CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
