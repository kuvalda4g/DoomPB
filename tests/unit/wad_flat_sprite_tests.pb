; -----------------------------------------------------------------------------
; DoomPB - flat namespace/decoder and sprite namespace/frame tests (M2-04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; All WADs, flats and sprite patches are synthetic. No commercial resources are
; copied or required. Temporary WADs live under the ignored build/ tree.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/Patch.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/Sprite.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

Global gFixtureDirectory.s = ""
Global gWadCount.i = 0
Global Dim gWadNames.s(127)
Global Dim gWadPointers.i(127)
Global Dim gWadSizes.q(127)
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

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "wad-flat-sprite-test-tmp" + #FixtureSeparator
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
; Byte-buffer and synthetic WAD helpers
; ---------------------------------------------------------------------------

Structure ByteBuffer
  *Data.Byte
  Pos.i
  Capacity.i
EndStructure

Procedure BBInit(*B.ByteBuffer, Capacity.i)
  *B\Data = AllocateMemory(Capacity)
  *B\Pos = 0
  *B\Capacity = Capacity
EndProcedure

Procedure BBFree(*B.ByteBuffer)
  If *B\Data <> 0
    FreeMemory(*B\Data)
    *B\Data = 0
  EndIf
  *B\Pos = 0
  *B\Capacity = 0
EndProcedure

Procedure BBByte(*B.ByteBuffer, Value.i)
  PokeA(*B\Data + *B\Pos, Value & $FF)
  *B\Pos + 1
EndProcedure

Procedure BBWord(*B.ByteBuffer, Value.i)
  BBByte(*B, Value & $FF)
  BBByte(*B, (Value >> 8) & $FF)
EndProcedure

Procedure BBLong(*B.ByteBuffer, Value.q)
  BBByte(*B, Value & $FF)
  BBByte(*B, (Value >> 8) & $FF)
  BBByte(*B, (Value >> 16) & $FF)
  BBByte(*B, (Value >> 24) & $FF)
EndProcedure

Procedure BBSetLong(*B.ByteBuffer, Offset.i, Value.q)
  PokeA(*B\Data + Offset, Value & $FF)
  PokeA(*B\Data + Offset + 1, (Value >> 8) & $FF)
  PokeA(*B\Data + Offset + 2, (Value >> 16) & $FF)
  PokeA(*B\Data + Offset + 3, (Value >> 24) & $FF)
EndProcedure

; ---- patch builder ----

Procedure PatchStart(*B.ByteBuffer, Width.i, Height.i, Left.i, Top.i)
  Protected i.i

  BBInit(*B, 65536)
  BBWord(*B, Width)
  BBWord(*B, Height)
  BBWord(*B, Left)
  BBWord(*B, Top)
  For i = 0 To Width - 1
    BBLong(*B, 0)
  Next
EndProcedure

Procedure PatchAddColumn(*B.ByteBuffer, Column.i, *Col.ByteBuffer)
  BBSetLong(*B, 8 + Column * 4, *B\Pos)
  CopyMemory(*Col\Data, *B\Data + *B\Pos, *Col\Pos)
  *B\Pos + *Col\Pos
EndProcedure

Procedure PatchPost(*Col.ByteBuffer, TopDelta.i, PixelsHex.s)
  Protected count.i = Len(PixelsHex) / 2
  Protected i.i

  BBByte(*Col, TopDelta)
  BBByte(*Col, count)
  BBByte(*Col, 0)
  For i = 0 To count - 1
    BBByte(*Col, Val("$" + Mid(PixelsHex, i * 2 + 1, 2)))
  Next
  BBByte(*Col, 0)
EndProcedure

Procedure PatchTerm(*Col.ByteBuffer)
  BBByte(*Col, $FF)
EndProcedure

Procedure SolidPatch(*B.ByteBuffer, Width.i, Height.i, Value.i, Left.i = 0, Top.i = 0)
  Protected col.ByteBuffer
  Protected pixels.s
  Protected i.i

  pixels = ""
  For i = 1 To Height
    pixels + RSet(Hex(Value & $FF), 2, "0")
  Next
  PatchStart(*B, Width, Height, Left, Top)
  For i = 0 To Width - 1
    BBInit(@col, 32)
    PatchPost(@col, 0, pixels)
    PatchTerm(@col)
    PatchAddColumn(*B, i, @col)
    BBFree(@col)
  Next
EndProcedure

Procedure.i MakeFlat(Size.i, Value.i)
  Protected memory.i = AllocateMemory(Size)
  Protected i.i

  If memory <> 0
    For i = 0 To Size - 1
      PokeA(memory + i, (Value + i) & $FF)
    Next
  EndIf
  ProcedureReturn memory
EndProcedure

; ---- WAD assembly ----

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

Procedure.i WadWrite(FileName.s)
  Protected path.s = FixturePath(FileName)
  Protected file.i
  Protected directoryOffset.q
  Protected i.i
  Protected Dim positions.q(127)

  file = CreateFile(#PB_Any, path)
  If file = 0
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
  ProcedureReturn #True
EndProcedure

Procedure.i LoadLumpByIndex(WadIndex.i, *OutLength.Long)
  Protected size.q
  Protected memory.i

  size = WADLumpSize(WadIndex)
  *OutLength\l = size
  If size <= 0
    ProcedureReturn 0
  EndIf
  memory = AllocateMemory(size)
  If memory = 0
    ProcedureReturn 0
  EndIf
  If WADReadLump(WadIndex, memory, size) = #False
    FreeMemory(memory)
    ProcedureReturn 0
  EndIf
  ProcedureReturn memory
EndProcedure

; ---------------------------------------------------------------------------
; F01 - F16: flats
; ---------------------------------------------------------------------------

Procedure TestF01Discover()
  BeginCase("F01", "Discover F_START/F_END and exclude markers")
  Protected f1.i = MakeFlat(4096, 1)
  Protected f2.i = MakeFlat(4096, 2)
  Protected catalog.FlatCatalog
  Protected path.s = "f01.wad"
  Protected startIndex.i
  Protected endIndex.i

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("FLAT1", f1, 4096)
  WadAdd("FLAT2", f2, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  startIndex = WADFindLump("F_START")
  endIndex = WADFindLump("F_END")
  Check(Bool(FlatCatalogBuild(@catalog)), "flat catalog builds")
  Check(Bool(FlatCatalogCount(@catalog) = 2), "two interior flats")
  Check(Bool(catalog\FirstLump = startIndex + 1 And catalog\LastLump = endIndex - 1), "boundaries exclude both markers")
  Check(Bool(FlatCatalogDisplayName(@catalog, 0) = "FLAT1"), "first flat name")
  Check(Bool(FlatCatalogDisplayName(@catalog, 1) = "FLAT2"), "second flat name")
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(f1)
  FreeMemory(f2)
EndProcedure

Procedure TestF02Order()
  BeginCase("F02", "Flat count and WAD indices follow directory order")
  Protected a.i = MakeFlat(4096, $10)
  Protected b.i = MakeFlat(4096, $20)
  Protected catalog.FlatCatalog
  Protected path.s = "f02.wad"
  Protected wadIndex.l
  Protected lumpSize.l
  Protected expected.i

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("ZZZ", a, 4096)
  WadAdd("AAA", b, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  expected = WADFindLump("F_START") + 1
  Check(Bool(FlatCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(FlatCatalogGetEntry(@catalog, 0, @wadIndex, @lumpSize)), "entry 0 readable")
  Check(Bool(wadIndex = expected), "entry 0 keeps its directory index")
  Check(Bool(FlatCatalogGetEntry(@catalog, 1, @wadIndex, @lumpSize)), "entry 1 readable")
  Check(Bool(wadIndex = expected + 1), "entry 1 keeps its directory index")
  Check(Bool(FlatCatalogDisplayName(@catalog, 0) = "ZZZ" And FlatCatalogDisplayName(@catalog, 1) = "AAA"), "physical order is preserved")
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(a)
  FreeMemory(b)
EndProcedure

Procedure TestF03Decode()
  BeginCase("F03", "Decode exactly 4096 bytes row-major")
  Protected memory.i = MakeFlat(4096, 0)
  Protected image.FlatImage
  Protected i.i

  Check(Bool(memory <> 0), "flat buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  For i = 0 To 4095
    PokeA(memory + i, i & $FF)
  Next
  Check(Bool(FlatDecode(memory, 4096, @image)), "flat decodes")
  Check(Bool(image\Width = 64 And image\Height = 64 And image\PixelCount = 4096), "dimensions and count")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = 0), "top-left pixel")
  Check(Bool(FlatImageGetPixel(@image, 63, 0) = 63), "top-right pixel")
  Check(Bool(FlatImageGetPixel(@image, 0, 1) = 64), "second row starts at byte 64")
  Check(Bool(FlatImageGetPixel(@image, 63, 63) = 255), "bottom-right pixel")
  FlatImageReset(@image)
  FreeMemory(memory)
EndProcedure

Procedure TestF04Index255()
  BeginCase("F04", "Palette index 255 is a valid flat color")
  Protected memory.i = MakeFlat(4096, 0)
  Protected image.FlatImage

  FillMemory(memory, 4096, 255)
  Check(Bool(FlatDecode(memory, 4096, @image)), "flat decodes")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = 255 And FlatImageGetPixel(@image, 63, 63) = 255), "index 255 is preserved")
  FlatImageReset(@image)
  FreeMemory(memory)
EndProcedure

Procedure TestF05ShortInput()
  BeginCase("F05", "Reject short flat payloads")
  Protected memory.i = AllocateMemory(4096)
  Protected image.FlatImage

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 4096, 0)
  Check(Bool(FlatDecode(memory, 0, @image) = #False), "length 0 is rejected")
  Check(Bool(FlatDecode(memory, 4095, @image) = #False), "4095 bytes are rejected")
  Check(Bool(FlatDecode(memory, 1, @image) = #False), "one byte is rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestF06LongInput()
  BeginCase("F06", "Reject oversized flat payloads")
  Protected memory.i = AllocateMemory(4097)
  Protected image.FlatImage

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 4097, 0)
  Check(Bool(FlatDecode(memory, 4097, @image) = #False), "4097 bytes are rejected")
  Check(Bool(image\Pixels = 0), "no image survives the failure")
  FreeMemory(memory)
EndProcedure

Procedure TestF07NullAndNegative()
  BeginCase("F07", "Null input, null output and negative lengths")
  Protected memory.i = AllocateMemory(4096)
  Protected image.FlatImage

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(FlatDecode(0, 4096, @image) = #False), "null input is rejected")
  Check(Bool(FlatDecode(memory, 4096, 0) = #False), "null output is rejected")
  Check(Bool(FlatDecode(memory, -1, @image) = #False), "negative length is rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestF08Bounds()
  BeginCase("F08", "Invalid flat coordinates and catalog indices")
  Protected memory.i = MakeFlat(4096, 7)
  Protected image.FlatImage
  Protected catalog.FlatCatalog
  Protected path.s = "f08.wad"
  Protected only.i = MakeFlat(4096, 7)

  Check(Bool(FlatDecode(memory, 4096, @image)), "flat decodes")
  Check(Bool(FlatImageGetPixel(@image, -1, 0) = -1), "negative x is rejected")
  Check(Bool(FlatImageGetPixel(@image, 0, -1) = -1), "negative y is rejected")
  Check(Bool(FlatImageGetPixel(@image, 64, 0) = -1), "x == 64 is rejected")
  Check(Bool(FlatImageGetPixel(@image, 0, 64) = -1), "y == 64 is rejected")
  FlatImageReset(@image)
  FreeMemory(memory)

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("ONLY", only, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(FlatCatalogGetEntry(@catalog, -1, 0, 0) = #False), "negative catalog index rejected")
  Check(Bool(FlatCatalogGetEntry(@catalog, 1, 0, 0) = #False), "index == count rejected")
  Check(Bool(FlatCatalogNameByte(@catalog, 0, 8) = -1), "name byte offset 8 rejected")
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(only)
EndProcedure

Procedure TestF09Ownership()
  BeginCase("F09", "Decoded flat survives source release")
  Protected memory.i = MakeFlat(4096, 3)
  Protected image.FlatImage
  Protected pixel.i

  Check(Bool(FlatDecode(memory, 4096, @image)), "flat decodes")
  pixel = FlatImageGetPixel(@image, 10, 10)
  FreeMemory(memory)
  Check(Bool(FlatImageGetPixel(@image, 10, 10) = pixel), "pixel remains valid after input free")
  FlatImageReset(@image)
EndProcedure

Procedure TestF10ResetAndFailure()
  BeginCase("F10", "Repeated reset/decode and failure clearing")
  Protected memory.i = MakeFlat(4096, $44)
  Protected short.i = AllocateMemory(100)
  Protected image.FlatImage

  Check(Bool(short <> 0), "short buffer allocated")
  If short = 0
    FreeMemory(memory)
    ProcedureReturn
  EndIf
  FillMemory(short, 100, 0)
  Check(Bool(FlatDecode(memory, 4096, @image)), "first decode succeeds")
  Check(Bool(FlatImageReset(@image)), "first reset succeeds")
  Check(Bool(FlatImageReset(@image)), "second reset is idempotent")
  Check(Bool(FlatDecode(memory, 4096, @image)), "decode after reset succeeds")
  Check(Bool(FlatDecode(short, 100, @image) = #False), "failed replacement is rejected")
  Check(Bool(image\Pixels = 0 And image\PixelCount = 0), "failure clears the previous image")
  FreeMemory(memory)
  FreeMemory(short)
EndProcedure

Procedure TestF11MissingMarkers()
  BeginCase("F11", "Missing and reversed namespace markers")
  Protected catalog.FlatCatalog
  Protected path.s = "f11.wad"
  Protected flat.i = MakeFlat(4096, 0)

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("NOEND", flat, 4096)
  Check(Bool(WadWrite(path)), "missing-end WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog) = #False), "missing F_END is rejected")
  Check(Bool(FindString(FlatLastError(), "F_END") > 0), "error identifies F_END")
  WADClose()
  DeleteFile(FixturePath(path))

  path = "f11b.wad"
  WadResetEntries()
  WadAdd("NOEND", flat, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "missing-start WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "second WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog) = #False), "missing F_START is rejected")
  WADClose()
  DeleteFile(FixturePath(path))

  path = "f11c.wad"
  WadResetEntries()
  WadAdd("F_END", 0, 0)
  WadAdd("F_START", 0, 0)
  Check(Bool(WadWrite(path)), "reversed WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "third WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog) = #False), "reversed markers are rejected")
  Check(Bool(FindString(FlatLastError(), "reversed") > 0), "error mentions reversed markers")
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(flat)
EndProcedure

Procedure TestF12EmptyRange()
  BeginCase("F12", "Empty marker range")
  Protected catalog.FlatCatalog
  Protected path.s = "f12.wad"

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "empty-range WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog)), "empty range is accepted")
  Check(Bool(FlatCatalogCount(@catalog) = 0), "count is 0")
  Check(Bool(FlatCatalogFindName(@catalog, "ANY") = -1), "lookup fails in an empty range")
  Check(Bool(FlatCatalogGetEntry(@catalog, 0, 0, 0) = #False), "entry access fails in an empty range")
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
EndProcedure

Procedure TestF13DuplicateMarkers()
  BeginCase("F13", "Duplicate namespace markers use last lookup")
  Protected first.i = MakeFlat(4096, 1)
  Protected second.i = MakeFlat(4096, 2)
  Protected catalog.FlatCatalog
  Protected path.s = "f13.wad"

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("FIRST", first, 4096)
  WadAdd("F_END", 0, 0)
  WadAdd("F_START", 0, 0)
  WadAdd("SECOND", second, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "duplicate-marker WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(FlatCatalogCount(@catalog) = 1), "only the last namespace is used")
  Check(Bool(FlatCatalogDisplayName(@catalog, 0) = "SECOND"), "last namespace contains SECOND")
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(first)
  FreeMemory(second)
EndProcedure

Procedure TestF14NamesAndDuplicates()
  BeginCase("F14", "Raw names and duplicate flat lookup")
  Protected a.i = MakeFlat(4096, 1)
  Protected b.i = MakeFlat(4096, 2)
  Protected c.i = MakeFlat(4096, 3)
  Protected catalog.FlatCatalog
  Protected path.s = "f14.wad"

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("DUP", a, 4096)
  WadAdd("DUP", b, 4096)
  WadAdd("ABCDEFGH", c, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(FlatCatalogFindName(@catalog, "dup") = 1), "duplicate lookup returns the last match")
  Check(Bool(FlatCatalogNameByte(@catalog, 1, 0) = Asc("D")), "raw duplicate name is preserved")
  Check(Bool(FlatCatalogNameByte(@catalog, 2, 7) = Asc("H")), "eight-byte name without NUL is preserved")
  Check(Bool(FlatCatalogFindName(@catalog, "abcdefgh") = 2), "eight-byte lookup is case-insensitive in the query")
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(a)
  FreeMemory(b)
  FreeMemory(c)
EndProcedure

Procedure TestF15WrongSizeEntry()
  BeginCase("F15", "Zero-length / wrong-size interior flat")
  Protected catalog.FlatCatalog
  Protected image.FlatImage
  Protected path.s = "f15.wad"
  Protected shortFlat.i = AllocateMemory(100)

  Check(Bool(shortFlat <> 0), "short flat buffer allocated")
  If shortFlat = 0
    ProcedureReturn
  EndIf
  FillMemory(shortFlat, 100, 0)

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("ZERO", 0, 0)
  WadAdd("SHORT", shortFlat, 100)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@catalog)), "catalog still builds")
  Check(Bool(FlatCatalogCount(@catalog) = 2), "both malformed entries are exposed as metadata")
  Check(Bool(FlatLoad(@catalog, 0, @image) = #False), "zero-length flat fails decode")
  Check(Bool(FlatLoad(@catalog, 1, @image) = #False), "wrong-size flat fails decode")
  Check(Bool(image\Pixels = 0), "no image survives the failure")
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(shortFlat)
EndProcedure

Procedure TestF16Rebuild()
  BeginCase("F16", "WAD reopen requires an explicit catalog rebuild")
  Protected a.i = MakeFlat(4096, 1)
  Protected b.i = MakeFlat(4096, 2)
  Protected catalog.FlatCatalog
  Protected image.FlatImage
  Protected pixel.i
  Protected pathA.s = "f16a.wad"
  Protected pathB.s = "f16b.wad"

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("ONE", a, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(pathA)), "WAD A created")
  Check(Bool(WADOpen(FixturePath(pathA))), "WAD A opens")
  Check(Bool(FlatCatalogBuild(@catalog)), "catalog A builds")
  Check(Bool(FlatLoad(@catalog, 0, @image)), "flat A loads")
  pixel = FlatImageGetPixel(@image, 0, 0)
  WADClose()

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("TWO-A", b, 4096)
  WadAdd("TWO-B", b, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(pathB)), "WAD B created")
  Check(Bool(WADOpen(FixturePath(pathB))), "WAD B opens")
  Check(Bool(FlatCatalogBuild(@catalog)), "catalog rebuilds for WAD B")
  Check(Bool(FlatCatalogCount(@catalog) = 2), "rebuilt catalog uses WAD B entries")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = pixel), "old decoded image remains independent")
  FlatImageReset(@image)
  FlatCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(pathA))
  DeleteFile(FixturePath(pathB))
  FreeMemory(a)
  FreeMemory(b)
EndProcedure

; ---------------------------------------------------------------------------
; S01 - S20: sprites
; ---------------------------------------------------------------------------

Procedure.i AddSpriteWadEntry(*Patch.ByteBuffer, Name.s)
  WadAdd(Name, *Patch\Data, *Patch\Pos)
  ProcedureReturn 0
EndProcedure

Procedure TestS01Discover()
  BeginCase("S01", "Discover S_START/S_END and preserve order")
  Protected p1.ByteBuffer
  Protected p2.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected path.s = "s01.wad"
  Protected wadIndex.l
  Protected lumpSize.l
  Protected expected.i

  SolidPatch(@p1, 2, 2, $11)
  SolidPatch(@p2, 2, 2, $22)
  WadResetEntries()
  WadAdd("S_START", 0, 0)
  AddSpriteWadEntry(@p1, "TROOA0")
  AddSpriteWadEntry(@p2, "TROOA1")
  WadAdd("S_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  expected = WADFindLump("S_START") + 1
  Check(Bool(SpriteCatalogBuild(@catalog)), "sprite catalog builds")
  Check(Bool(SpriteCatalogCount(@catalog) = 2), "two interior sprite lumps")
  Check(Bool(SpriteCatalogGetEntry(@catalog, 0, @wadIndex, @lumpSize)), "entry 0 readable")
  Check(Bool(wadIndex = expected), "entry 0 keeps its directory index")
  Check(Bool(SpriteCatalogDisplayName(@catalog, 0) = "TROOA0"), "entry 0 name")
  Check(Bool(SpriteCatalogDisplayName(@catalog, 1) = "TROOA1"), "entry 1 name")
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@p1)
  BBFree(@p2)
EndProcedure

Procedure TestS02Markers()
  BeginCase("S02", "Missing, reversed, duplicate and empty sprite markers")
  Protected catalog.SpriteCatalog
  Protected path.s = "s02.wad"
  Protected p.ByteBuffer

  SolidPatch(@p, 1, 1, 1)
  WadResetEntries()
  WadAdd("S_START", 0, 0)
  AddSpriteWadEntry(@p, "TROOA0")
  Check(Bool(WadWrite(path)), "missing-end WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog) = #False), "missing S_END is rejected")
  WADClose()

  WadResetEntries()
  WadAdd("S_END", 0, 0)
  WadAdd("S_START", 0, 0)
  Check(Bool(WadWrite("s02b.wad")), "reversed WAD created")
  Check(Bool(WADOpen(FixturePath("s02b.wad"))), "reversed WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog) = #False), "reversed markers are rejected")
  WADClose()

  WadResetEntries()
  WadAdd("S_START", 0, 0)
  WadAdd("S_END", 0, 0)
  Check(Bool(WadWrite("s02c.wad")), "empty WAD created")
  Check(Bool(WADOpen(FixturePath("s02c.wad"))), "empty WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "empty range is accepted")
  Check(Bool(SpriteCatalogCount(@catalog) = 0), "empty count is 0")
  SpriteCatalogReset(@catalog)
  WADClose()

  WadResetEntries()
  WadAdd("S_START", 0, 0)
  AddSpriteWadEntry(@p, "TROOA0")
  WadAdd("S_END", 0, 0)
  WadAdd("S_START", 0, 0)
  AddSpriteWadEntry(@p, "TROOA1")
  WadAdd("S_END", 0, 0)
  Check(Bool(WadWrite("s02d.wad")), "duplicate-marker WAD created")
  Check(Bool(WADOpen(FixturePath("s02d.wad"))), "duplicate WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "duplicate markers build")
  Check(Bool(SpriteCatalogCount(@catalog) = 1), "last namespace is selected")
  Check(Bool(SpriteCatalogDisplayName(@catalog, 0) = "TROOA1"), "last namespace entry is used")
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  DeleteFile(FixturePath("s02b.wad"))
  DeleteFile(FixturePath("s02c.wad"))
  DeleteFile(FixturePath("s02d.wad"))
  BBFree(@p)
EndProcedure

Procedure TestS03RawNames()
  BeginCase("S03", "Raw eight-byte sprite names preserved")
  Protected catalog.SpriteCatalog
  Protected path.s = "s03.wad"
  Protected p.ByteBuffer

  SolidPatch(@p, 1, 1, 1)
  WadResetEntries()
  WadAdd("S_START", 0, 0)
  WadAdd("TROOA0", p\Data, p\Pos)
  WadAdd("WEIRDX1", p\Data, p\Pos)
  WadAdd("S_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteCatalogNameByte(@catalog, 0, 4) = Asc("A")), "frame byte is preserved")
  Check(Bool(SpriteCatalogNameByte(@catalog, 0, 5) = Asc("0")), "rotation byte is preserved")
  Check(Bool(SpriteCatalogNameByte(@catalog, 0, 6) = 0), "unused name byte is NUL")
  Check(Bool(SpriteCatalogDisplayName(@catalog, 1) = "WEIRDX1"), "noncanonical name is exposed as metadata")
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@p)
EndProcedure

Procedure.i BuildSingleIdWad(FileName.s, *Patch.ByteBuffer, Names.s)
  Protected fields.i = 1
  Protected start.i = 1

  ; Names is a semicolon-separated list of up to 16 names.
  Protected Dim parts.s(15)
  Protected count.i = 0
  Protected i.i
  Protected token.s = ""
  Protected ch.s

  For i = 1 To Len(Names)
    ch = Mid(Names, i, 1)
    If ch = ";"
      parts(count) = token
      count + 1
      token = ""
    Else
      token + ch
    EndIf
  Next
  If Len(token) > 0
    parts(count) = token
    count + 1
  EndIf

  WadResetEntries()
  WadAdd("S_START", 0, 0)
  For i = 0 To count - 1
    WadAdd(parts(i), *Patch\Data, *Patch\Pos)
  Next
  WadAdd("S_END", 0, 0)
  ProcedureReturn WadWrite(FileName)
EndProcedure

Procedure TestS04RotationZero()
  BeginCase("S04", "Canonical six-byte TROOA0 maps all rotations")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s04.wad"
  Protected wadIndex.l
  Protected flip.l
  Protected expected.l
  Protected rotation.i

  SolidPatch(@patch, 2, 2, $31)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA0")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  expected = WADFindLump("TROOA0")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "frame set builds")
  Check(Bool(frames\FrameCount = 1), "one frame")
  For rotation = 1 To 8
    Check(Bool(SpriteFrameGet(@frames, 0, rotation, @wadIndex, @flip)), "rotation " + Str(rotation) + " readable")
    Check(Bool(wadIndex = expected And flip = 0), "rotation " + Str(rotation) + " uses the same lump unflipped")
  Next
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS05SingleRotationIncomplete()
  BeginCase("S05", "Single explicit rotation is incomplete")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s05.wad"

  SolidPatch(@patch, 2, 2, $32)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA1")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "incomplete rotations fail")
  Check(Bool(FindString(SpriteLastError(), "missing rotation") > 0), "error identifies missing rotations")
  Check(Bool(SpriteCatalogCount(@catalog) = 1), "catalog still exposes the entry")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS06PairedRotation()
  BeginCase("S06", "Paired A2A8 maps one lump with secondary flip")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s06.wad"
  Protected wadIndex.l
  Protected flip.l
  Protected expected.l

  SolidPatch(@patch, 2, 2, $33)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA1;TROOA2A8;TROOA3;TROOA4;TROOA5;TROOA6;TROOA7")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  expected = WADFindLump("TROOA2A8")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "frame set builds")
  Check(Bool(SpriteFrameGet(@frames, 0, 2, @wadIndex, @flip)), "primary rotation 2 readable")
  Check(Bool(wadIndex = expected And flip = 0), "primary A2 is unflipped")
  Check(Bool(SpriteFrameGet(@frames, 0, 8, @wadIndex, @flip)), "secondary rotation 8 readable")
  Check(Bool(wadIndex = expected And flip = 1), "secondary A8 is flipped")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS07PairedDifferentFrames()
  BeginCase("S07", "Paired name referencing two different frames")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s07.wad"
  Protected wadIndex.l
  Protected flip.l

  SolidPatch(@patch, 2, 2, $34)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA1B2;TROOA2;TROOA3;TROOA4;TROOA5;TROOA6;TROOA7;TROOA8;TROOB1;TROOB3;TROOB4;TROOB5;TROOB6;TROOB7;TROOB8")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "two-frame set builds")
  Check(Bool(frames\FrameCount = 2), "frame count is 2")
  Check(Bool(SpriteFrameGet(@frames, 0, 1, @wadIndex, @flip)), "A1 readable")
  Check(Bool(flip = 0), "A1 is unflipped")
  Check(Bool(SpriteFrameGet(@frames, 1, 2, @wadIndex, @flip)), "B2 readable")
  Check(Bool(flip = 1), "B2 is flipped")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS08EightRotations()
  BeginCase("S08", "Eight explicit rotations form one complete frame")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s08.wad"
  Protected i.i
  Protected names.s = ""
  Protected wadIndex.l
  Protected flip.l

  SolidPatch(@patch, 2, 2, $35)
  For i = 1 To 8
    If i > 1
      names + ";"
    EndIf
    names + "TROOA" + Str(i)
  Next
  Check(Bool(BuildSingleIdWad(path, @patch, names)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "complete frame builds")
  Check(Bool(frames\FrameCount = 1), "frame count is 1")
  For i = 1 To 8
    Check(Bool(SpriteFrameGet(@frames, 0, i, @wadIndex, @flip)), "rotation " + Str(i) + " is present")
  Next
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS09IncompleteRotations()
  BeginCase("S09", "Incomplete rotations fail frame assembly only")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s09.wad"

  SolidPatch(@patch, 2, 2, $36)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA1;TROOA2")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "incomplete frame fails")
  Check(Bool(FindString(SpriteLastError(), "missing rotation 3") > 0), "missing rotation is identified")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS10RotationZeroConflict()
  BeginCase("S10", "rot=0 conflicts with explicit rotations")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s10.wad"

  SolidPatch(@patch, 2, 2, $37)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA0;TROOA1")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "mixed rot=0 fails")
  Check(Bool(FindString(SpriteLastError(), "mixes") > 0), "error identifies the conflict")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS11DuplicateRotation()
  BeginCase("S11", "Duplicate rotation and duplicate rot=0")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s11.wad"

  SolidPatch(@patch, 2, 2, $38)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA1;TROOA1")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "duplicate rotation fails")
  Check(Bool(FindString(SpriteLastError(), "mapped twice") > 0), "duplicate slot is identified")
  WADClose()
  DeleteFile(FixturePath(path))
  SpriteCatalogReset(@catalog)
  SpriteFrameSetReset(@frames)

  Check(Bool(BuildSingleIdWad("s11b.wad", @patch, "TROOA0;TROOA0")), "second WAD created")
  Check(Bool(WADOpen(FixturePath("s11b.wad"))), "second WAD opens")
  SpriteCatalogBuild(@catalog)
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "duplicate rot=0 fails")
  Check(Bool(FindString(SpriteLastError(), "multiple rot=0") > 0), "duplicate rot=0 is identified")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath("s11b.wad"))
  BBFree(@patch)
EndProcedure

Procedure TestS12MissingFrame()
  BeginCase("S12", "Missing intermediate frame; unrelated sprites survive")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s12.wad"

  SolidPatch(@patch, 2, 2, $39)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA0;TROOC0;OTHERA0")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "missing frame B fails")
  Check(Bool(FindString(SpriteLastError(), "missing frame 1") > 0), "missing frame is identified")
  Check(Bool(SpriteCatalogCount(@catalog) = 3), "catalog retains unrelated entries")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS13InvalidPrimaryBytes()
  BeginCase("S13", "Invalid primary frame and rotation bytes")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s13.wad"

  SolidPatch(@patch, 2, 2, $3A)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROO!0;TROOA9")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog scan succeeds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "invalid frame/rotation fails frame assembly")
  Check(Bool(FindString(SpriteLastError(), "invalid primary") > 0), "error identifies the primary field")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS14MalformedPair()
  BeginCase("S14", "Malformed secondary frame/rotation pair")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s14.wad"
  Protected file.i
  Protected directoryOffset.q

  SolidPatch(@patch, 2, 2, $3B)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA1A")), "half-pair WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "half pair is rejected")
  Check(Bool(FindString(SpriteLastError(), "invalid secondary") > 0), "error identifies the secondary field")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()

  Check(Bool(BuildSingleIdWad("s14b.wad", @patch, "TROOA1")), "trailing half-pair WAD created")
  ; Set byte 6 to NUL while byte 7 remains '1': a half-present secondary pair.
  directoryOffset = 12 + patch\Pos
  file = OpenFile(#PB_Any, FixturePath("s14b.wad"))
  Check(Bool(file <> 0), "second WAD opened for raw name edit")
  If file
    FileSeek(file, directoryOffset + 16 + 8 + 6)
    WriteByte(file, 0)
    WriteByte(file, Asc("1"))
    CloseFile(file)
  EndIf
  Check(Bool(WADOpen(FixturePath("s14b.wad"))), "second WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "second catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames) = #False), "byte6=0 byte7 nonzero is rejected")
  Check(Bool(FindString(SpriteLastError(), "incomplete secondary") > 0), "error identifies the incomplete pair")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  DeleteFile(FixturePath("s14b.wad"))
  BBFree(@patch)
EndProcedure

Procedure TestS15PatchInfo()
  BeginCase("S15", "Patch header metadata and signed offsets")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected path.s = "s15.wad"
  Protected width.l, height.l, left.l, top.l

  SolidPatch(@patch, 3, 2, $41, -5, 7)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA0")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteCatalogGetPatchInfo(@catalog, 0, @width, @height, @left, @top)), "header metadata readable")
  Check(Bool(width = 3 And height = 2), "width and height are correct")
  Check(Bool(left = -5 And top = 7), "signed offsets are preserved")
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS16ShortPatch()
  BeginCase("S16", "Zero-length and short sprite headers")
  Protected catalog.SpriteCatalog
  Protected path.s = "s16.wad"
  Protected width.l, height.l, left.l, top.l
  Protected shortSprite.i = AllocateMemory(7)

  Check(Bool(shortSprite <> 0), "short sprite buffer allocated")
  If shortSprite = 0
    ProcedureReturn
  EndIf
  FillMemory(shortSprite, 7, 0)

  WadResetEntries()
  WadAdd("S_START", 0, 0)
  WadAdd("TROOA0", 0, 0)
  WadAdd("TROOB0", shortSprite, 7)
  WadAdd("S_END", 0, 0)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteCatalogGetPatchInfo(@catalog, 0, @width, @height, @left, @top) = #False), "zero-length header fails")
  Check(Bool(SpriteCatalogGetPatchInfo(@catalog, 1, @width, @height, @left, @top) = #False), "seven-byte header fails")
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(shortSprite)
EndProcedure

Procedure TestS17PatchDecode()
  BeginCase("S17", "Selected sprite decodes through PatchDecode")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected path.s = "s17.wad"
  Protected wadIndex.l
  Protected lumpSize.l
  Protected bytes.i
  Protected image.PatchImage

  SolidPatch(@patch, 2, 2, $52)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA0")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteCatalogGetEntry(@catalog, 0, @wadIndex, @lumpSize)), "entry metadata readable")
  bytes = LoadLumpByIndex(wadIndex, @lumpSize)
  Check(Bool(bytes <> 0), "sprite payload loaded")
  If bytes <> 0
    Check(Bool(PatchDecode(bytes, lumpSize, @image)), "PatchDecode accepts the sprite")
    Check(Bool(image\Width = 2 And image\Height = 2), "decoded dimensions")
    Check(Bool(PatchPixelAt(@image, 1, 1) = $52), "decoded pixel value")
    PatchReset(@image)
    FreeMemory(bytes)
  EndIf
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS18InvalidAccessors()
  BeginCase("S18", "Invalid sprite catalog and frame accessors")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s18.wad"
  Protected wadIndex.l
  Protected flip.l

  SolidPatch(@patch, 1, 1, 1)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA0")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteCatalogGetEntry(@catalog, -1, @wadIndex, 0) = #False), "negative catalog index rejected")
  Check(Bool(SpriteCatalogGetEntry(@catalog, 1, @wadIndex, 0) = #False), "index == count rejected")
  Check(Bool(SpriteCatalogNameByte(@catalog, 0, 8) = -1), "name byte offset 8 rejected")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "frame set builds")
  Check(Bool(SpriteFrameGet(@frames, -1, 1, @wadIndex, @flip) = #False), "negative frame rejected")
  Check(Bool(SpriteFrameGet(@frames, 1, 1, @wadIndex, @flip) = #False), "frame == count rejected")
  Check(Bool(SpriteFrameGet(@frames, 0, 0, @wadIndex, @flip) = #False), "rotation 0 rejected by getter")
  Check(Bool(SpriteFrameGet(@frames, 0, 9, @wadIndex, @flip) = #False), "rotation 9 rejected")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS19FrameLifetime()
  BeginCase("S19", "Frame set reset/rebuild and output lifetime")
  Protected patch.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s19.wad"
  Protected firstIndex.l
  Protected secondIndex.l
  Protected flip.l

  SolidPatch(@patch, 1, 1, $63)
  Check(Bool(BuildSingleIdWad(path, @patch, "TROOA0")), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "first build succeeds")
  SpriteFrameGet(@frames, 0, 1, @firstIndex, @flip)
  Check(Bool(SpriteFrameSetReset(@frames)), "frame set resets")
  Check(Bool(frames\WadIndices = 0 And frames\Flips = 0), "reset releases both arrays")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "second build succeeds")
  SpriteFrameGet(@frames, 0, 1, @secondIndex, @flip)
  Check(Bool(firstIndex = secondIndex), "rebuilt frame index is stable")
  SpriteCatalogReset(@catalog)
  WADClose()
  Check(Bool(SpriteFrameGet(@frames, 0, 1, @secondIndex, @flip)), "frame data survives catalog/WAD release")
  SpriteFrameSetReset(@frames)
  DeleteFile(FixturePath(path))
  BBFree(@patch)
EndProcedure

Procedure TestS20DuplicateNamesAndRebuild()
  BeginCase("S20", "Duplicate WAD names do not redirect catalog indices")
  Protected inside.ByteBuffer
  Protected outside.ByteBuffer
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected path.s = "s20.wad"
  Protected wadIndex.l
  Protected lumpSize.l

  SolidPatch(@inside, 1, 1, $71)
  SolidPatch(@outside, 1, 1, $72)
  WadResetEntries()
  WadAdd("S_START", 0, 0)
  WadAdd("TROOA0", inside\Data, inside\Pos)
  WadAdd("S_END", 0, 0)
  WadAdd("TROOA0", outside\Data, outside\Pos)
  Check(Bool(WadWrite(path)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "catalog builds")
  Check(Bool(SpriteCatalogGetEntry(@catalog, 0, @wadIndex, @lumpSize)), "catalog entry readable")
  Check(Bool(wadIndex = WADFindLump("S_START") + 1), "catalog keeps the in-range directory index")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "frames build from the in-range entry")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath(path))
  BBFree(@inside)
  BBFree(@outside)
EndProcedure

; ---------------------------------------------------------------------------
; I01 - I03: synthetic integration
; ---------------------------------------------------------------------------

Procedure TestI01Combined()
  BeginCase("I01", "Synthetic WAD with flat and sprite namespaces")
  Protected flat1.i = MakeFlat(4096, 5)
  Protected flat2.i = MakeFlat(4096, 6)
  Protected sprite.ByteBuffer
  Protected flatCatalog.FlatCatalog
  Protected spriteCatalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected image.FlatImage
  Protected path.s = "i01.wad"
  Protected wadIndex.l
  Protected flip.l

  SolidPatch(@sprite, 2, 2, $81)
  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("FLAT1", flat1, 4096)
  WadAdd("FLAT2", flat2, 4096)
  WadAdd("F_END", 0, 0)
  WadAdd("S_START", 0, 0)
  WadAdd("TROOA0", sprite\Data, sprite\Pos)
  WadAdd("S_END", 0, 0)
  Check(Bool(WadWrite(path)), "combined WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@flatCatalog)), "flat catalog builds")
  Check(Bool(SpriteCatalogBuild(@spriteCatalog)), "sprite catalog builds")
  Check(Bool(FlatCatalogCount(@flatCatalog) = 2), "two flats found")
  Check(Bool(SpriteCatalogCount(@spriteCatalog) = 1), "one sprite found")
  Check(Bool(FlatLoad(@flatCatalog, 1, @image)), "second flat loads")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = (6 & $FF)), "decoded flat pixel is correct")
  Check(Bool(SpriteBuildFrames(@spriteCatalog, "TROO", @frames)), "sprite frames build")
  Check(Bool(SpriteFrameGet(@frames, 0, 1, @wadIndex, @flip)), "frame slot readable")
  FlatImageReset(@image)
  SpriteFrameSetReset(@frames)
  FlatCatalogReset(@flatCatalog)
  SpriteCatalogReset(@spriteCatalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(flat1)
  FreeMemory(flat2)
  BBFree(@sprite)
EndProcedure

Procedure TestI02Malformed()
  BeginCase("I02", "Malformed namespace and resource fixtures fail cleanly")
  Protected flatCatalog.FlatCatalog
  Protected spriteCatalog.SpriteCatalog
  Protected image.FlatImage
  Protected path.s = "i02.wad"
  Protected shortFlat.i = AllocateMemory(100)
  Protected shortSprite.i = AllocateMemory(4)

  Check(Bool(shortFlat <> 0 And shortSprite <> 0), "malformed resource buffers allocated")
  If shortFlat = 0 Or shortSprite = 0
    ProcedureReturn
  EndIf
  FillMemory(shortFlat, 100, 0)
  FillMemory(shortSprite, 4, 0)

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("SHORT", shortFlat, 100)
  WadAdd("S_START", 0, 0)
  WadAdd("TROOA0", shortSprite, 4)
  WadAdd("S_END", 0, 0)
  Check(Bool(WadWrite(path)), "malformed WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@flatCatalog) = #False), "missing F_END fails flat discovery")
  Check(Bool(SpriteCatalogBuild(@spriteCatalog)), "sprite range is still discovered")
  Check(Bool(SpriteCatalogGetPatchInfo(@spriteCatalog, 0, 0, 0, 0, 0) = #False), "short sprite header fails")
  FlatImageReset(@image)
  SpriteCatalogReset(@spriteCatalog)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(shortFlat)
  FreeMemory(shortSprite)
EndProcedure

Procedure TestI03Reopen()
  BeginCase("I03", "WAD A to WAD B rebuild and owned output lifetime")
  Protected flatA.i = MakeFlat(4096, 10)
  Protected flatB.i = MakeFlat(4096, 20)
  Protected flatCatalog.FlatCatalog
  Protected image.FlatImage
  Protected oldPixel.i
  Protected pathA.s = "i03a.wad"
  Protected pathB.s = "i03b.wad"

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("A", flatA, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(pathA)), "WAD A created")
  Check(Bool(WADOpen(FixturePath(pathA))), "WAD A opens")
  Check(Bool(FlatCatalogBuild(@flatCatalog)), "catalog A builds")
  Check(Bool(FlatLoad(@flatCatalog, 0, @image)), "flat A loads")
  oldPixel = FlatImageGetPixel(@image, 0, 0)
  WADClose()

  WadResetEntries()
  WadAdd("F_START", 0, 0)
  WadAdd("B1", flatB, 4096)
  WadAdd("B2", flatB, 4096)
  WadAdd("F_END", 0, 0)
  Check(Bool(WadWrite(pathB)), "WAD B created")
  Check(Bool(WADOpen(FixturePath(pathB))), "WAD B opens")
  Check(Bool(FlatCatalogBuild(@flatCatalog)), "catalog B rebuilds explicitly")
  Check(Bool(FlatCatalogCount(@flatCatalog) = 2), "new namespace count is used")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = oldPixel), "old decoded image is independent")
  FlatImageReset(@image)
  FlatCatalogReset(@flatCatalog)
  WADClose()
  DeleteFile(FixturePath(pathA))
  DeleteFile(FixturePath(pathB))
  FreeMemory(flatA)
  FreeMemory(flatB)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB flats and sprites tests (M2-04)")

If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

TestF01Discover()
TestF02Order()
TestF03Decode()
TestF04Index255()
TestF05ShortInput()
TestF06LongInput()
TestF07NullAndNegative()
TestF08Bounds()
TestF09Ownership()
TestF10ResetAndFailure()
TestF11MissingMarkers()
TestF12EmptyRange()
TestF13DuplicateMarkers()
TestF14NamesAndDuplicates()
TestF15WrongSizeEntry()
TestF16Rebuild()

TestS01Discover()
TestS02Markers()
TestS03RawNames()
TestS04RotationZero()
TestS05SingleRotationIncomplete()
TestS06PairedRotation()
TestS07PairedDifferentFrames()
TestS08EightRotations()
TestS09IncompleteRotations()
TestS10RotationZeroConflict()
TestS11DuplicateRotation()
TestS12MissingFrame()
TestS13InvalidPrimaryBytes()
TestS14MalformedPair()
TestS15PatchInfo()
TestS16ShortPatch()
TestS17PatchDecode()
TestS18InvalidAccessors()
TestS19FrameLifetime()
TestS20DuplicateNamesAndRebuild()

TestI01Combined()
TestI02Malformed()
TestI03Reopen()

CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
