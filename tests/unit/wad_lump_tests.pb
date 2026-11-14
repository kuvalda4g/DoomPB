; -----------------------------------------------------------------------------
; DoomPB - WAD lump lookup and payload read tests (M1-02)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Every fixture is generated from synthetic bytes by this program. No Doom
; resources are copied or required. Fixtures are written inside the ignored
; build/ tree and removed before exit.
;
; Exit code: 0 when every assertion passed, otherwise the number of failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

Global gFixtureDirectory.s = ""
Global gMainPath.s = ""
Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

; ---------------------------------------------------------------------------
; Test harness
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

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "wad-lump-test-tmp" + #FixtureSeparator
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
; Synthetic fixture writer
; ---------------------------------------------------------------------------

Procedure WriteU32LE(file.i, Value.q)
  WriteByte(file, Value & $FF)
  WriteByte(file, (Value >> 8) & $FF)
  WriteByte(file, (Value >> 16) & $FF)
  WriteByte(file, (Value >> 24) & $FF)
EndProcedure

Procedure WriteWadHeader(file.i, Magic.s, LumpCount.q, DirectoryOffset.q)
  WriteString(file, Magic)
  WriteU32LE(file, LumpCount)
  WriteU32LE(file, DirectoryOffset)
EndProcedure

; Writes the 8 raw name bytes of Name; shorter names are NUL padded.
Procedure WriteLumpEntry(file.i, Position.q, Size.q, Name.s)
  Protected i.i
  Protected value.i

  WriteU32LE(file, Position)
  WriteU32LE(file, Size)
  For i = 0 To 7
    If i < Len(Name)
      value = Asc(Mid(Name, i + 1, 1))
    Else
      value = 0
    EndIf
    WriteByte(file, value)
  Next
EndProcedure

; Builds the shared multi-entry fixture. Entry order, payload positions and
; duplicate names are fixed and visible in the assertions.
Procedure.s BuildMainFixture()
  Protected path.s = FixturePath("main.wad")
  Protected file.i
  Protected start.q
  Protected directoryOffset.q
  Protected Dim positions.q(10)
  Protected Dim sizes.q(10)
  Protected Dim names.s(10)
  Protected i.i

  names(0) = "PLAYPAL"
  names(1) = "TEST"
  names(2) = "TEST"
  names(3) = "ABCDEFGH"
  names(4) = "ABC"
  names(5) = "ABCDEFG1"
  names(6) = "ABCDEFG2"
  names(7) = "LONGLUMP"
  names(8) = "MARKER"
  names(9) = "BINARY"
  names(10) = "lower"

  file = CreateFile(#PB_Any, path)
  If file = 0
    ProcedureReturn ""
  EndIf
  WriteWadHeader(file, "IWAD", 11, 0)

  ; 0: PLAYPAL-like palette bytes.
  start = Loc(file)
  WriteByte(file, $00)
  WriteByte(file, $80)
  WriteByte(file, $FF)
  WriteByte(file, $01)
  WriteByte(file, $02)
  WriteByte(file, $03)
  positions(0) = start
  sizes(0) = Loc(file) - start

  ; 1 and 2: duplicate name with different payloads.
  start = Loc(file)
  WriteString(file, "AAAA")
  positions(1) = start
  sizes(1) = Loc(file) - start

  start = Loc(file)
  WriteString(file, "BBBB")
  positions(2) = start
  sizes(2) = Loc(file) - start

  ; 3: exactly eight name bytes, no NUL.
  start = Loc(file)
  WriteString(file, "12345678")
  positions(3) = start
  sizes(3) = Loc(file) - start

  ; 4: short name requiring NUL padding.
  start = Loc(file)
  WriteString(file, "ab")
  positions(4) = start
  sizes(4) = Loc(file) - start

  ; 5 and 6: same first seven bytes.
  start = Loc(file)
  WriteString(file, "111")
  positions(5) = start
  sizes(5) = Loc(file) - start

  start = Loc(file)
  WriteString(file, "222")
  positions(6) = start
  sizes(6) = Loc(file) - start

  ; 7: eight stored bytes used for a longer-query truncation test.
  start = Loc(file)
  WriteString(file, "12345")
  positions(7) = start
  sizes(7) = Loc(file) - start

  ; 8: zero-length marker with a deliberately invalid recorded position.
  positions(8) = 999999999
  sizes(8) = 0

  ; 9: binary payload with a NUL, a high-bit byte and 0xFF.
  start = Loc(file)
  WriteByte(file, $00)
  WriteByte(file, $80)
  WriteByte(file, $FF)
  WriteByte(file, $7F)
  WriteByte(file, $01)
  positions(9) = start
  sizes(9) = Loc(file) - start

  ; 10: intentionally lowercase stored name (raw bytes stay lowercase).
  start = Loc(file)
  WriteString(file, "lo")
  positions(10) = start
  sizes(10) = Loc(file) - start

  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32LE(file, directoryOffset)
  FileSeek(file, directoryOffset)
  For i = 0 To 10
    WriteLumpEntry(file, positions(i), sizes(i), names(i))
  Next
  CloseFile(file)

  ProcedureReturn path
EndProcedure

; Builds a single-entry WAD whose payload is given as an uppercase hex string.
Procedure.s BuildSingleFixture(FileName.s, LumpName.s, PayloadHex.s)
  Protected path.s = FixturePath(FileName)
  Protected file.i
  Protected payloadSize.i = Len(PayloadHex) / 2
  Protected start.q
  Protected directoryOffset.q
  Protected i.i

  file = CreateFile(#PB_Any, path)
  If file = 0
    ProcedureReturn ""
  EndIf
  WriteWadHeader(file, "IWAD", 1, 0)
  start = Loc(file)
  For i = 0 To payloadSize - 1
    WriteByte(file, Val("$" + Mid(PayloadHex, i * 2 + 1, 2)))
  Next
  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32LE(file, directoryOffset)
  FileSeek(file, directoryOffset)
  WriteLumpEntry(file, start, payloadSize, LumpName)
  CloseFile(file)

  ProcedureReturn path
EndProcedure

; Two entries sharing the same payload start with different declared sizes.
Procedure.s BuildOverlapFixture()
  Protected path.s = FixturePath("overlap.wad")
  Protected file.i
  Protected start.q
  Protected directoryOffset.q

  file = CreateFile(#PB_Any, path)
  If file = 0
    ProcedureReturn ""
  EndIf
  WriteWadHeader(file, "IWAD", 2, 0)
  start = Loc(file)
  WriteString(file, "SHAREDDATA")
  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32LE(file, directoryOffset)
  FileSeek(file, directoryOffset)
  WriteLumpEntry(file, start, 10, "OVERLAPA")
  WriteLumpEntry(file, start, 4, "OVERLAPB")
  CloseFile(file)

  ProcedureReturn path
EndProcedure

; Overwrites Path with a valid but empty 12-byte WAD.
Procedure WriteEmptyWad(Path.s)
  Protected file.i = CreateFile(#PB_Any, Path)

  If file
    WriteWadHeader(file, "IWAD", 0, 0)
    CloseFile(file)
  EndIf
EndProcedure

; ---------------------------------------------------------------------------
; Canary helpers
; ---------------------------------------------------------------------------

Procedure FillBytes(*Buffer.Byte, Count.i, Value.i)
  Protected i.i

  For i = 0 To Count - 1
    PokeA(*Buffer + i, Value)
  Next
EndProcedure

Procedure.i AllBytesAre(*Buffer.Byte, Count.i, Value.i)
  Protected i.i

  For i = 0 To Count - 1
    If PeekA(*Buffer + i) <> Value
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

Procedure.s BufferHex(*Buffer.Byte, Count.i)
  Protected i.i
  Protected result.s = ""

  For i = 0 To Count - 1
    result + RSet(Hex(PeekA(*Buffer + i)), 2, "0")
  Next
  ProcedureReturn result
EndProcedure

; ---------------------------------------------------------------------------
; L01 - L20
; ---------------------------------------------------------------------------

Procedure TestL01CanonicalName()
  BeginCase("L01", "Lookup of a canonical uppercase name")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("PLAYPAL") = 0), "PLAYPAL is found at index 0")
  Check(Bool(WADLumpSize(0) = 6), "PLAYPAL size is 6")
  Check(Bool(WADLastError() = ""), "successful lookup leaves no error text")
  WADClose()
EndProcedure

Procedure TestL02CaseInsensitiveQuery()
  BeginCase("L02", "Lowercase and mixed-case queries")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("playpal") = 0), "lowercase query finds PLAYPAL")
  Check(Bool(WADFindLump("PlayPal") = 0), "mixed-case query finds PLAYPAL")
  Check(Bool(WADFindLump("pLaYpAl") = 0), "alternating case finds PLAYPAL")
  WADClose()
EndProcedure

Procedure TestL03MissingName()
  BeginCase("L03", "Missing name and invalid query text")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("NOSUCH") = -1), "unknown name returns -1")
  Check(Bool(FindString(WADLastError(), "not found") > 0), "error explains the missing lump")
  Check(Bool(WADIsOpen() = #True), "failed lookup keeps the WAD open")

  Check(Bool(WADFindLump("") = -1), "empty query returns -1")
  Check(Bool(FindString(WADLastError(), "empty") > 0), "empty query produces a specific error")
  Check(Bool(WADFindLump(Chr(233)) = -1), "non-ASCII query returns -1")
  Check(Bool(FindString(WADLastError(), "unsupported") > 0), "non-ASCII query produces a specific error")

  Check(Bool(WADFindLump("PLAYPAL") = 0), "a later successful lookup works")
  Check(Bool(WADLastError() = ""), "invalid-query and not-found errors are cleared by success")
  WADClose()
EndProcedure

Procedure TestL04DuplicateLastWins()
  BeginCase("L04", "Duplicate names: the last directory entry wins")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("TEST") = 2), "TEST resolves to the later index 2")
  Check(Bool(WADLumpSize(2) = 4), "winning duplicate has size 4")
  WADClose()
EndProcedure

Procedure TestL05EightByteName()
  BeginCase("L05", "Exactly eight name bytes without a NUL terminator")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("ABCDEFGH") = 3), "eight-byte name is found")
  Check(Bool(WADLumpRawNameHex(3) = "4142434445464748"), "all eight raw bytes are preserved")
  Check(Bool(WADLumpRawNameByte(3, 7) = Asc("H")), "last byte is not NUL")
  WADClose()
EndProcedure

Procedure TestL06ShortNamePadding()
  BeginCase("L06", "Short names use NUL padding, not prefix matching")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("ABC") = 4), "ABC matches the NUL-padded entry")
  Check(Bool(WADFindLump("AB") = -1), "AB does not match ABC by prefix")
  Check(Bool(WADFindLump("ABCDEFG") = -1), "seven-byte query does not match ABCDEFGH")
  WADClose()
EndProcedure

Procedure TestL07SimilarNames()
  BeginCase("L07", "Names sharing the first seven bytes do not collide")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("ABCDEFG1") = 5), "ABCDEFG1 finds index 5")
  Check(Bool(WADFindLump("ABCDEFG2") = 6), "ABCDEFG2 finds index 6")
  WADClose()
EndProcedure

Procedure TestL08LongQueryTruncation()
  BeginCase("L08", "Query longer than eight bytes uses the first eight")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("LONGLUMP9") = 7), "nine-byte query matches the eight stored bytes")
  Check(Bool(WADFindLump("LONGLUMPXYZ") = 7), "longer query also truncates to eight bytes")
  Check(Bool(WADLumpDisplayName(7) = "LONGLUMP"), "stored name is unchanged")
  WADClose()
EndProcedure

Procedure TestL09ZeroLengthMarker()
  BeginCase("L09", "Zero-length marker with an invalid recorded offset")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("MARKER") = 8), "marker is found by name")
  Check(Bool(WADLumpSize(8) = 0), "marker size is 0")
  Check(Bool(WADLumpPosition(8) = 999999999), "raw invalid position is preserved")
  Check(Bool(WADReadLump(8, 0, 0) = #True), "marker reads successfully with a null buffer")
  Check(Bool(WADLastError() = ""), "marker read leaves no error text")
  WADClose()
EndProcedure

Procedure TestL10BinaryPayload()
  BeginCase("L10", "Binary payload with 00, 80 and FF bytes")

  Protected buffer.i
  Protected found.i

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  found = WADFindLump("BINARY")
  Check(Bool(found = 9), "BINARY is found at index 9")
  buffer = AllocateMemory(5)
  Check(Bool(buffer <> 0), "read buffer allocated")
  If buffer <> 0 And found = 9
    Check(Bool(WADReadLump(found, buffer, 5) = #True), "binary lump reads successfully")
    Check(Bool(BufferHex(buffer, 5) = "0080FF7F01"), "bytes match exactly (no string conversion)")
    FreeMemory(buffer)
  EndIf
  WADClose()
EndProcedure

Procedure TestL11ReadByIndex()
  BeginCase("L11", "Reading duplicate names by explicit index")

  Protected buffer.i
  Protected found.i

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  found = WADFindLump("TEST")
  Check(Bool(found = 2), "name lookup selects the later duplicate")
  buffer = AllocateMemory(4)
  Check(Bool(buffer <> 0), "read buffer allocated")
  If buffer <> 0 And found = 2
    Check(Bool(WADReadLump(1, buffer, 4) = #True), "index 1 reads successfully")
    Check(Bool(BufferHex(buffer, 4) = "41414141"), "index 1 contains AAAA, not the lookup winner")
    Check(Bool(WADReadLump(2, buffer, 4) = #True), "index 2 reads successfully")
    Check(Bool(BufferHex(buffer, 4) = "42424242"), "index 2 contains BBBB")
    FreeMemory(buffer)
  EndIf
  WADClose()
EndProcedure

Procedure TestL12ExactCapacityGuards()
  BeginCase("L12", "Buffer exactly the required size with guard bytes")

  Protected buffer.i

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  buffer = AllocateMemory(8)
  Check(Bool(buffer <> 0), "canary buffer allocated")
  If buffer <> 0
    FillBytes(buffer, 8, $CC)
    Check(Bool(WADReadLump(1, buffer + 2, 4) = #True), "read with capacity 4 succeeds")
    Check(Bool(PeekA(buffer) = $CC And PeekA(buffer + 1) = $CC), "leading canary bytes are unchanged")
    Check(Bool(BufferHex(buffer + 2, 4) = "41414141"), "payload is written at the requested address")
    Check(Bool(PeekA(buffer + 6) = $CC And PeekA(buffer + 7) = $CC), "trailing canary bytes are unchanged")
    FreeMemory(buffer)
  EndIf
  WADClose()
EndProcedure

Procedure TestL13BadDestinations()
  BeginCase("L13", "Undersized, negative and null destination arguments")

  Protected buffer.i

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  buffer = AllocateMemory(8)
  Check(Bool(buffer <> 0), "canary buffer allocated")
  If buffer <> 0
    FillBytes(buffer, 8, $CC)
    Check(Bool(WADReadLump(1, buffer, 3) = #False), "capacity 3 for a 4-byte lump fails")
    Check(Bool(AllBytesAre(buffer, 8, $CC)), "undersized read does not modify the buffer")
    Check(Bool(FindString(WADLastError(), "capacity") > 0), "error mentions capacity")

    Check(Bool(WADReadLump(1, buffer, -1) = #False), "negative capacity fails")
    Check(Bool(AllBytesAre(buffer, 8, $CC)), "negative-capacity read does not modify the buffer")

    Check(Bool(WADReadLump(1, 0, 4) = #False), "null destination for a nonempty lump fails")
    Check(Bool(FindString(WADLastError(), "null") > 0), "error mentions the null destination")

    Check(Bool(WADReadLump(1, buffer, 0) = #False), "zero capacity for a nonempty lump fails")
    Check(Bool(AllBytesAre(buffer, 8, $CC)), "zero-capacity read does not modify the buffer")
    FreeMemory(buffer)
  EndIf
  WADClose()
EndProcedure

Procedure TestL14InvalidIndices()
  BeginCase("L14", "Invalid indices and reads before open")

  Protected buffer.i
  Protected count.i

  buffer = AllocateMemory(16)
  Check(Bool(buffer <> 0), "read buffer allocated")

  WADClose()
  Check(Bool(WADFindLump("PLAYPAL") = -1), "lookup before open returns -1")
  Check(Bool(FindString(WADLastError(), "No WAD") > 0), "lookup error says no WAD is open")
  If buffer <> 0
    Check(Bool(WADReadLump(0, buffer, 16) = #False), "read before open fails")
    Check(Bool(FindString(WADLastError(), "No WAD") > 0), "read error says no WAD is open")
  EndIf

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  count = WADGetLumpCount()
  If buffer <> 0
    Check(Bool(WADReadLump(-1, buffer, 16) = #False), "index -1 fails")
    Check(Bool(WADReadLump(count, buffer, 16) = #False), "index equal to count fails")
    Check(Bool(WADReadLump(count + 1000, buffer, 16) = #False), "large index fails")
    Check(Bool(WADReadLump(0, buffer, 16) = #True), "valid index still reads")
    FreeMemory(buffer)
  EndIf
  WADClose()
EndProcedure

Procedure TestL15EmptyPayloadNullBuffer()
  BeginCase("L15", "Empty payload with null pointer and zero capacity")

  Protected buffer.i

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("MARKER") = 8), "marker index resolved")

  Check(Bool(WADReadLump(8, 0, 0) = #True), "null destination and zero capacity succeed")
  Check(Bool(WADLastError() = ""), "successful zero-length read clears the error")

  buffer = AllocateMemory(8)
  Check(Bool(buffer <> 0), "canary buffer allocated")
  If buffer <> 0
    FillBytes(buffer, 8, $CC)
    Check(Bool(WADReadLump(8, buffer, 8) = #True), "marker read with a real buffer succeeds")
    Check(Bool(AllBytesAre(buffer, 8, $CC)), "marker read writes no bytes")
    FreeMemory(buffer)
  EndIf
  WADClose()
EndProcedure

Procedure TestL16MissingFileAfterOpen()
  BeginCase("L16", "Source file removed after a successful open")

  Protected path.s = BuildSingleFixture("rename.wad", "TARGET", "5441524745542121")
  Protected movedPath.s = FixturePath("rename_moved.wad")
  Protected buffer.i

  Check(Bool(path <> ""), "single-entry fixture created")
  Check(Bool(WADOpen(path)), "fixture opens")
  buffer = AllocateMemory(8)
  Check(Bool(buffer <> 0), "read buffer allocated")
  If buffer <> 0
    Check(Bool(WADReadLump(0, buffer, 8) = #True), "payload reads before removal")
    Check(Bool(BufferHex(buffer, 8) = "5441524745542121"), "payload bytes are correct")

    Check(Bool(RenameFile(path, movedPath) <> 0), "fixture renamed away")
    Check(Bool(WADReadLump(0, buffer, 8) = #False), "read after removal fails")
    Check(Bool(FindString(WADLastError(), "Cannot reopen") > 0), "error explains the missing file")
    Check(Bool(WADFindLump("TARGET") = 0), "directory snapshot still answers lookups")

    Check(Bool(RenameFile(movedPath, path) <> 0), "fixture renamed back")
    Check(Bool(WADReadLump(0, buffer, 8) = #True), "read succeeds after the file returns")
    Check(Bool(BufferHex(buffer, 8) = "5441524745542121"), "content is correct after recovery")
    FreeMemory(buffer)
  EndIf

  WADClose()
  DeleteFile(path)
  DeleteFile(movedPath)
EndProcedure

Procedure TestL17ChangedFileSize()
  BeginCase("L17", "Source file truncated or extended after open")

  Protected path.s = BuildSingleFixture("shrink.wad", "TARGET", "5441524745542121")
  Protected buffer.i
  Protected file.i

  Check(Bool(path <> ""), "single-entry fixture created")
  Check(Bool(WADOpen(path)), "fixture opens")
  buffer = AllocateMemory(8)
  Check(Bool(buffer <> 0), "read buffer allocated")
  If buffer <> 0
    Check(Bool(WADReadLump(0, buffer, 8) = #True), "original payload reads")

    WriteEmptyWad(path)
    Check(Bool(FileSize(path) = 12), "fixture truncated to 12 bytes")
    Check(Bool(WADReadLump(0, buffer, 8) = #False), "read after truncation fails")
    Check(Bool(FindString(WADLastError(), "size changed") > 0), "error reports the changed size")

    path = BuildSingleFixture("shrink.wad", "TARGET", "5441524745542121")
    Check(Bool(WADReadLump(0, buffer, 8) = #True), "read succeeds after restoring the file")

    file = OpenFile(#PB_Any, path, #PB_File_Append)
    Check(Bool(file <> 0), "fixture reopened for appending")
    If file
      WriteByte(file, $AA)
      CloseFile(file)
    EndIf
    Check(Bool(WADReadLump(0, buffer, 8) = #False), "read after extension fails")
    Check(Bool(FindString(WADLastError(), "size changed") > 0), "extension is reported as a size change")

    path = BuildSingleFixture("shrink.wad", "TARGET", "5441524745542121")
    Check(Bool(WADReadLump(0, buffer, 8) = #True), "read succeeds after the second restore")
    FreeMemory(buffer)
  EndIf

  WADClose()
  DeleteFile(path)
EndProcedure

Procedure TestL18ReopenLifecycle()
  BeginCase("L18", "Close/reopen and failed open followed by success")

  Protected path.s = FixturePath("badmagic.wad")
  Protected file.i
  Protected buffer.i

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADFindLump("PLAYPAL") = 0), "lookup before close succeeds")
  buffer = AllocateMemory(6)
  Check(Bool(buffer <> 0), "read buffer allocated")
  If buffer <> 0
    Check(Bool(WADReadLump(0, buffer, 6) = #True), "read before close succeeds")
    WADClose()
    Check(Bool(WADFindLump("PLAYPAL") = -1), "lookup after close fails")
    Check(Bool(WADReadLump(0, buffer, 6) = #False), "read after close fails")

    file = CreateFile(#PB_Any, path)
    Check(Bool(file <> 0), "invalid fixture created")
    If file
      WriteWadHeader(file, "BAD!", 0, 0)
      CloseFile(file)
    EndIf
    Check(Bool(WADOpen(path) = #False), "invalid WAD is rejected")
    Check(Bool(WADFindLump("PLAYPAL") = -1), "failed open leaves no lookup state")

    Check(Bool(WADOpen(gMainPath)), "reopen succeeds")
    Check(Bool(WADFindLump("PLAYPAL") = 0), "lookup after reopen succeeds")
    Check(Bool(WADReadLump(0, buffer, 6) = #True), "read after reopen succeeds")
    Check(Bool(WADGetPath() = gMainPath), "path was refreshed")
    Check(Bool(WADLastError() = ""), "no stale error after reopen and read")
    FreeMemory(buffer)
  EndIf

  WADClose()
  DeleteFile(path)
EndProcedure

Procedure TestL19OverlappingRanges()
  BeginCase("L19", "Entries with overlapping/shared payload ranges")

  Protected path.s = BuildOverlapFixture()
  Protected buffer.i

  Check(Bool(path <> ""), "overlap fixture created")
  Check(Bool(WADOpen(path)), "overlap fixture opens")
  Check(Bool(WADFindLump("OVERLAPA") = 0), "first overlapping entry is found")
  Check(Bool(WADFindLump("OVERLAPB") = 1), "second overlapping entry is found")
  buffer = AllocateMemory(10)
  Check(Bool(buffer <> 0), "read buffer allocated")
  If buffer <> 0
    Check(Bool(WADReadLump(0, buffer, 10) = #True), "larger overlapping entry reads")
    Check(Bool(BufferHex(buffer, 10) = "53484152454444415441"), "larger entry contains SHAREDDATA")
    FillBytes(buffer, 10, $CC)
    Check(Bool(WADReadLump(1, buffer, 4) = #True), "smaller overlapping entry reads")
    Check(Bool(BufferHex(buffer, 4) = "53484152"), "smaller entry contains SHAR")
    Check(Bool(AllBytesAre(buffer + 4, 6, $CC)), "smaller read leaves later bytes untouched")
    FreeMemory(buffer)
  EndIf
  WADClose()
  DeleteFile(path)
EndProcedure

Procedure TestL20CapacityBoundary()
  BeginCase("L20", "Oversized capacity is harmless and does not truncate")

  Protected buffer.i

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  buffer = AllocateMemory(8)
  Check(Bool(buffer <> 0), "canary buffer allocated")
  If buffer <> 0
    FillBytes(buffer, 8, $CC)
    Check(Bool(WADReadLump(2, buffer, $7FFFFFFF) = #True), "capacity 0x7FFFFFFF succeeds")
    Check(Bool(BufferHex(buffer, 4) = "42424242"), "exactly 4 bytes are written")
    Check(Bool(AllBytesAre(buffer + 4, 4, $CC)), "trailing canaries survive a huge capacity")

    Check(Bool(WADReadLump(2, buffer, 9223372036854775807) = #True), "maximum signed 64-bit capacity succeeds")
    Check(Bool(BufferHex(buffer, 4) = "42424242"), "no byte-count truncation at the maximum capacity")
    Check(Bool(WADLastError() = ""), "successful reads clear the error")
    FreeMemory(buffer)
  EndIf
  WADClose()
EndProcedure

; Extra compatibility case requested by M1-02: stored raw bytes are never
; uppercased, so an UPCASE query does not match a lowercase stored name.
Procedure TestX01LowercaseStoredName()
  BeginCase("X01", "Lowercase stored name keeps raw bytes and does not match")

  Check(Bool(WADOpen(gMainPath)), "main fixture opens")
  Check(Bool(WADLumpRawNameHex(10) = "6C6F776572000000"), "raw lowercase bytes are preserved")
  Check(Bool(WADLumpDisplayName(10) = "lower"), "display name shows the stored lowercase text")
  Check(Bool(WADFindLump("LOWER") = -1), "uppercased query does not match lowercase storage")
  Check(Bool(WADFindLump("lower") = -1), "lowercase query is normalized and still does not match")
  Check(Bool(WADLumpRawNameHex(10) = "6C6F776572000000"), "lookups did not rewrite directory bytes")
  Check(Bool(WADFindLump("PLAYPAL") = 0), "normal uppercase lookup still works")
  Check(Bool(WADLastError() = ""), "success clears the not-found error")
  WADClose()
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB WAD lump lookup/payload tests (M1-02)")

If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

gMainPath = BuildMainFixture()
If gMainPath = ""
  PrintN("FAIL: cannot create the main synthetic WAD")
  CleanupFixtureDirectory()
  End 1
EndIf
WADClose()

TestL01CanonicalName()
TestL02CaseInsensitiveQuery()
TestL03MissingName()
TestL04DuplicateLastWins()
TestL05EightByteName()
TestL06ShortNamePadding()
TestL07SimilarNames()
TestL08LongQueryTruncation()
TestL09ZeroLengthMarker()
TestL10BinaryPayload()
TestL11ReadByIndex()
TestL12ExactCapacityGuards()
TestL13BadDestinations()
TestL14InvalidIndices()
TestL15EmptyPayloadNullBuffer()
TestL16MissingFileAfterOpen()
TestL17ChangedFileSize()
TestL18ReopenLifecycle()
TestL19OverlappingRanges()
TestL20CapacityBoundary()
TestX01LowercaseStoredName()

WADClose()
CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
