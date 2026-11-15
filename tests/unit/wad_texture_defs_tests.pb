; -----------------------------------------------------------------------------
; DoomPB - TEXTURE1/TEXTURE2 definition and PNAMES resolution tests (M2-02)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; All texture data and WADs are synthesized in this program. No Doom resources
; are copied or required. Disposable WADs are written under the ignored build/
; tree and removed after use.
;
; Exit code: 0 when every assertion passed, otherwise the number of failures.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
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

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "wad-texture-test-tmp" + #FixtureSeparator
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
; Generic byte-buffer builder
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

Procedure BBName8(*B.ByteBuffer, Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      BBByte(*B, Asc(Mid(Name, i + 1, 1)))
    Else
      BBByte(*B, 0)
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------------------
; Texture-lump builder
; ---------------------------------------------------------------------------

Procedure TBStart(*B.ByteBuffer, TextureCount.i)
  Protected i.i

  BBInit(*B, 65536)
  BBLong(*B, TextureCount)
  For i = 0 To TextureCount - 1
    BBLong(*B, 0)
  Next
EndProcedure

Procedure TBSetOffset(*B.ByteBuffer, TextureIndex.i, Offset.q)
  BBSetLong(*B, 4 + TextureIndex * 4, Offset)
EndProcedure

Procedure TBAddHeader(*B.ByteBuffer, TextureIndex.i, Name.s, Masked.i, Width.i, Height.i, ColumnDirectory.i, PatchCount.i)
  TBSetOffset(*B, TextureIndex, *B\Pos)
  BBName8(*B, Name)
  BBLong(*B, Masked)
  BBWord(*B, Width)
  BBWord(*B, Height)
  BBLong(*B, ColumnDirectory)
  BBWord(*B, PatchCount)
EndProcedure

Procedure TBAddPatch(*B.ByteBuffer, OriginX.i, OriginY.i, PNameIndex.i, StepDir.i, ColorMap.i)
  BBWord(*B, OriginX)
  BBWord(*B, OriginY)
  BBWord(*B, PNameIndex)
  BBWord(*B, StepDir)
  BBWord(*B, ColorMap)
EndProcedure

Procedure TBAddOneTexture(*B.ByteBuffer, Name.s, Width.i, Height.i, PNameIndex.i)
  TBStart(*B, 1)
  TBAddHeader(*B, 0, Name, 1, Width, Height, 0, 1)
  TBAddPatch(*B, 0, 0, PNameIndex, 0, 0)
EndProcedure

; ---------------------------------------------------------------------------
; PNAMES fixture
; ---------------------------------------------------------------------------

Procedure.i MakePNames(NameCount.i)
  Protected memory.i = AllocateMemory(4 + NameCount * 8)

  If memory <> 0
    FillMemory(memory, 4 + NameCount * 8, 0)
    PokeA(memory, NameCount & $FF)
    PokeA(memory + 1, (NameCount >> 8) & $FF)
    PokeA(memory + 2, (NameCount >> 16) & $FF)
    PokeA(memory + 3, (NameCount >> 24) & $FF)
  EndIf
  ProcedureReturn memory
EndProcedure

Procedure SetPName(*Memory.Byte, NameIndex.i, Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      PokeA(*Memory + 4 + NameIndex * 8 + i, Asc(Mid(Name, i + 1, 1)))
    Else
      PokeA(*Memory + 4 + NameIndex * 8 + i, 0)
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic WAD writer
; ---------------------------------------------------------------------------

Procedure WadEntriesReset()
  gWadCount = 0
EndProcedure

Procedure WadAddEntry(Name.s, *Data.Byte, Size.q)
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

Procedure WriteLumpEntryFile(file.i, Position.q, Size.q, Name.s)
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
  Protected Dim positions.q(63)

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
    WriteLumpEntryFile(file, positions(i), gWadSizes(i), gWadNames(i))
  Next
  CloseFile(file)
  ProcedureReturn #True
EndProcedure

; Reads a lump into a new caller-owned buffer. The WAD must already be open.
Procedure.i LoadLumpByName(Name.s, *OutLength.Long)
  Protected index.i
  Protected size.q
  Protected memory.i

  index = WADFindLump(Name)
  If index < 0
    ProcedureReturn 0
  EndIf
  size = WADLumpSize(index)
  *OutLength\l = size
  If size <= 0
    ProcedureReturn 0
  EndIf
  memory = AllocateMemory(size)
  If memory = 0
    ProcedureReturn 0
  EndIf
  If WADReadLump(index, memory, size) = #False
    FreeMemory(memory)
    ProcedureReturn 0
  EndIf
  ProcedureReturn memory
EndProcedure

Procedure.i MakeDummyPatch(Size.i)
  Protected memory.i = AllocateMemory(Size)

  If memory <> 0
    FillMemory(memory, Size, $AA)
  EndIf
  ProcedureReturn memory
EndProcedure

; ---------------------------------------------------------------------------
; D01 - D20: TEXTURE1/TEXTURE2 binary definitions
; ---------------------------------------------------------------------------

Procedure TestD01SingleTexture()
  BeginCase("D01", "One valid texture with one patch")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs
  Protected width.l, height.l, masked.l, columnDirectory.l, patchCount.l
  Protected originX.l, originY.l, pname.l, stepDir.l, colorMap.l

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "TEXTURE1", 1, 64, 128, $12345678, 1)
  TBAddPatch(@lump, -5, 7, 3, 0, 0)

  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "texture lump decodes")
  Check(Bool(TextureDefsCount(@defs) = 1), "count is 1")
  Check(Bool(TextureDefsDisplayName(@defs, 0) = "TEXTURE1"), "name is TEXTURE1")
  Check(Bool(TextureDefsGetProperties(@defs, 0, @width, @height, @masked, @columnDirectory, @patchCount)), "properties are readable")
  Check(Bool(width = 64 And height = 128), "dimensions are 64x128")
  Check(Bool(masked = 1), "masked flag is preserved")
  Check(Bool(columnDirectory = $12345678), "obsolete column directory is preserved raw")
  Check(Bool(patchCount = 1), "patch count is 1")
  Check(Bool(TextureDefsGetPatch(@defs, 0, 0, @originX, @originY, @pname, @stepDir, @colorMap)), "patch is readable")
  Check(Bool(originX = -5 And originY = 7), "signed patch origin is preserved")
  Check(Bool(pname = 3), "PNAMES index is preserved")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

Procedure TestD02DirectoryOrder()
  BeginCase("D02", "Directory order independent of physical offset order")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs
  Protected offsetA.q
  Protected offsetB.q

  TBStart(@lump, 2)
  TBAddHeader(@lump, 0, "AAAA", 0, 16, 16, 0, 0)
  offsetA = PeekL(lump\Data + 4)
  TBAddHeader(@lump, 1, "BBBB", 0, 32, 32, 0, 0)
  offsetB = PeekL(lump\Data + 8)
  TBSetOffset(@lump, 0, offsetB)
  TBSetOffset(@lump, 1, offsetA)

  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "unsorted offsets decode")
  Check(Bool(TextureDefsCount(@defs) = 2), "two definitions are present")
  Check(Bool(TextureDefsDisplayName(@defs, 0) = "BBBB"), "directory index 0 points to BBBB")
  Check(Bool(TextureDefsDisplayName(@defs, 1) = "AAAA"), "directory index 1 points to AAAA")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

Procedure TestD03NegativeOrigins()
  BeginCase("D03", "Negative signed patch origins")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs
  Protected originX.l, originY.l

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "NEG", 0, 8, 8, 0, 1)
  TBAddPatch(@lump, -32768, -123, 0, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "texture decodes")
  Check(Bool(TextureDefsGetPatch(@defs, 0, 0, @originX, @originY, 0, 0, 0)), "patch is readable")
  Check(Bool(originX = -32768), "originx -32768 is preserved")
  Check(Bool(originY = -123), "originy -123 is preserved")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

Procedure TestD04EightByteName()
  BeginCase("D04", "Exactly eight non-NUL texture-name bytes")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "ABCDEFGH", 0, 4, 4, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "texture decodes")
  Check(Bool(TextureDefsGetNameByte(@defs, 0, 7) = Asc("H")), "eighth byte is readable")
  Check(Bool(TextureDefsDisplayName(@defs, 0) = "ABCDEFGH"), "display name is exactly eight bytes")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

Procedure TestD05ShortNamePadding()
  BeginCase("D05", "NUL-padded short texture name")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "ABC", 0, 4, 4, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "texture decodes")
  Check(Bool(TextureDefsGetNameByte(@defs, 0, 2) = Asc("C")), "third byte is present")
  Check(Bool(TextureDefsGetNameByte(@defs, 0, 3) = 0), "fourth byte is NUL padding")
  Check(Bool(TextureDefsDisplayName(@defs, 0) = "ABC"), "display name stops at padding")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

Procedure TestD06HistoricalFields()
  BeginCase("D06", "Masked and historical fields are preserved raw")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs
  Protected masked.l, columnDirectory.l, stepDir.l, colorMap.l

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "FIELDS", $7FFFFFFF, 8, 8, $76543210, 1)
  TBAddPatch(@lump, 0, 0, 0, -1, 99)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "texture decodes")
  Check(Bool(TextureDefsGetProperties(@defs, 0, 0, 0, @masked, @columnDirectory, 0)), "raw properties are readable")
  Check(Bool(masked = $7FFFFFFF), "masked value is preserved")
  Check(Bool(columnDirectory = $76543210), "obsolete column directory is preserved")
  Check(Bool(TextureDefsGetPatch(@defs, 0, 0, 0, 0, 0, @stepDir, @colorMap)), "historical patch fields are readable")
  Check(Bool(stepDir = -1 And colorMap = 99), "stepdir and colormap are preserved")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

Procedure TestD07ShortHeader()
  BeginCase("D07", "Inputs shorter than the 4-byte count")
  Protected memory.i = AllocateMemory(4)
  Protected defs.TextureDefs

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 4, 0)
  Check(Bool(TextureDefsDecode(memory, 0, @defs) = #False), "length 0 is rejected")
  Check(Bool(TextureDefsDecode(memory, 1, @defs) = #False), "length 1 is rejected")
  Check(Bool(TextureDefsDecode(memory, 2, @defs) = #False), "length 2 is rejected")
  Check(Bool(TextureDefsDecode(memory, 3, @defs) = #False), "length 3 is rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestD08NegativeCount()
  BeginCase("D08", "Negative texture count")
  Protected memory.i = AllocateMemory(4)
  Protected defs.TextureDefs

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  PokeA(memory, $FF)
  PokeA(memory + 1, $FF)
  PokeA(memory + 2, $FF)
  PokeA(memory + 3, $FF)
  Check(Bool(TextureDefsDecode(memory, 4, @defs) = #False), "count -1 is rejected")
  Check(Bool(TextureDefsCount(@defs) = 0), "failed decode leaves no definitions")
  FreeMemory(memory)
EndProcedure

Procedure TestD09CountCap()
  BeginCase("D09", "Count cap and directory arithmetic")
  Protected memory.i = AllocateMemory(4)
  Protected defs.TextureDefs

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  PokeA(memory, $01)
  PokeA(memory + 1, $00)
  PokeA(memory + 2, $01)
  PokeA(memory + 3, $00)   ; 65537
  Check(Bool(TextureDefsDecode(memory, 4, @defs) = #False), "count 65537 is rejected")
  PokeA(memory, $FF)
  PokeA(memory + 1, $FF)
  PokeA(memory + 2, $FF)
  PokeA(memory + 3, $7F)
  Check(Bool(TextureDefsDecode(memory, 4, @defs) = #False), "huge signed count is rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestD10TruncatedDirectory()
  BeginCase("D10", "Truncated offset directory")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 2)
  Check(Bool(TextureDefsDecode(lump\Data, 8, @defs) = #False), "eight bytes cannot hold two offsets")
  Check(Bool(FindString(TextureDefsLastError(), "directory") > 0), "error mentions the directory")
  BBFree(@lump)
EndProcedure

Procedure TestD11InvalidOffsets()
  BeginCase("D11", "Negative and past-EOF definition offsets")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "OFFSET", 0, 8, 8, 0, 0)
  TBSetOffset(@lump, 0, -1)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "negative offset is rejected")
  TBSetOffset(@lump, 0, 999999)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "offset past EOF is rejected")
  BBFree(@lump)
EndProcedure

Procedure TestD12OffsetInsideDirectory()
  BeginCase("D12", "Offset inside the directory table")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "INSIDE", 0, 8, 8, 0, 0)
  TBSetOffset(@lump, 0, 4)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "offset 4 is rejected")
  Check(Bool(FindString(TextureDefsLastError(), "inside the directory") > 0), "strict directory policy is reported")
  BBFree(@lump)
EndProcedure

Procedure TestD13TruncatedDefinition()
  BeginCase("D13", "Truncated 22-byte definition header")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "TRUNC", 0, 8, 8, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, 8 + 21, @defs) = #False), "one byte short of the header is rejected")
  BBFree(@lump)
EndProcedure

Procedure TestD14InvalidDimensions()
  BeginCase("D14", "Zero, negative and oversized dimensions")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "W0", 0, 0, 8, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "zero width is rejected")
  BBFree(@lump)

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "WNEG", 0, -1, 8, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "negative width is rejected")
  BBFree(@lump)

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "H4097", 0, 8, 4097, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "height 4097 is rejected")
  BBFree(@lump)

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "W4097", 0, 4097, 8, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "width 4097 is rejected")
  BBFree(@lump)
EndProcedure

Procedure TestD15InvalidPatchCount()
  BeginCase("D15", "Negative and excessive patch counts")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "PNEG", 0, 8, 8, 0, -1)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "negative patch count is rejected")
  BBFree(@lump)

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "PBIG", 0, 8, 8, 0, 1025)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs) = #False), "patch count above the cap is rejected")
  BBFree(@lump)
EndProcedure

Procedure TestD16TruncatedPatch()
  BeginCase("D16", "Truncated 10-byte patch placement")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "TRUNCP", 0, 8, 8, 0, 1)
  TBAddPatch(@lump, 0, 0, 0, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos - 1, @defs) = #False), "nine-byte patch is rejected")
  Check(Bool(TextureDefsCount(@defs) = 0), "failed decode exposes no partial definition")
  BBFree(@lump)
EndProcedure

Procedure TestD17ExactEndOfInput()
  BeginCase("D17", "Definition ending exactly at EOF")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs

  TBStart(@lump, 1)
  TBAddHeader(@lump, 0, "EXACT", 0, 8, 8, 0, 1)
  TBAddPatch(@lump, 1, 2, 0, 0, 0)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "exact length is accepted")
  Check(Bool(TextureDefsCount(@defs) = 1), "definition is present")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

Procedure TestD18EmptyTable()
  BeginCase("D18", "Empty texture directory")
  Protected memory.i = AllocateMemory(4)
  Protected defs.TextureDefs

  Check(Bool(memory <> 0), "4-byte fixture allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 4, 0)
  Check(Bool(TextureDefsDecode(memory, 4, @defs)), "count 0 decodes")
  Check(Bool(TextureDefsCount(@defs) = 0), "empty count is 0")
  Check(Bool(TextureDefsGetNameByte(@defs, 0, 0) = -1), "no definition index 0 exists")
  TextureDefsReset(@defs)
  FreeMemory(memory)
EndProcedure

Procedure TestD19Reuse()
  BeginCase("D19", "Decode, failure, decode and double reset")
  Protected good.ByteBuffer
  Protected bad.ByteBuffer
  Protected defs.TextureDefs

  TBAddOneTexture(@good, "GOOD", 16, 16, 0)
  TBStart(@bad, 1)
  TBAddHeader(@bad, 0, "BAD", 0, 0, 16, 0, 0)

  Check(Bool(TextureDefsDecode(good\Data, good\Pos, @defs)), "first decode succeeds")
  Check(Bool(TextureDefsDecode(bad\Data, bad\Pos, @defs) = #False), "failed replacement is rejected")
  Check(Bool(TextureDefsCount(@defs) = 0), "failure clears old definitions")
  Check(Bool(TextureDefsDecode(good\Data, good\Pos, @defs)), "decode after failure succeeds")
  Check(Bool(TextureDefsReset(@defs)), "reset succeeds")
  Check(Bool(TextureDefsReset(@defs)), "second reset is idempotent")
  Check(Bool(defs\Names = 0 And defs\Count = 0), "reset clears owned storage")
  BBFree(@good)
  BBFree(@bad)
EndProcedure

Procedure TestD20DuplicateOffsets()
  BeginCase("D20", "Two directory entries with the same definition offset")
  Protected lump.ByteBuffer
  Protected defs.TextureDefs
  Protected offset.q

  TBStart(@lump, 2)
  TBAddHeader(@lump, 0, "SHARED", 0, 8, 8, 0, 0)
  offset = PeekL(lump\Data + 4)
  TBSetOffset(@lump, 1, offset)
  Check(Bool(TextureDefsDecode(lump\Data, lump\Pos, @defs)), "duplicate offset decodes")
  Check(Bool(TextureDefsCount(@defs) = 2), "both directory entries are preserved")
  Check(Bool(TextureDefsDisplayName(@defs, 0) = "SHARED"), "first entry is SHARED")
  Check(Bool(TextureDefsDisplayName(@defs, 1) = "SHARED"), "second entry is SHARED")
  TextureDefsReset(@defs)
  BBFree(@lump)
EndProcedure

; ---------------------------------------------------------------------------
; R01 - R10: PNAMES and WAD resolution
; ---------------------------------------------------------------------------

Procedure.s BuildResolutionWad(FileName.s, PNamesMemory.i)
  ; Adds PNAMES, TEXTURE1 and one PATCH1 lump. The caller supplies PNAMES bytes.
  Protected texture.ByteBuffer
  Protected patch.i = MakeDummyPatch(16)

  TBAddOneTexture(@texture, "WALL1", 64, 64, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", PNamesMemory, 4 + 8)
  WadAddEntry("PATCH1", patch, 16)
  If WadWrite(FileName) = #False
    BBFree(@texture)
    FreeMemory(patch)
    ProcedureReturn ""
  EndIf
  BBFree(@texture)
  FreeMemory(patch)
  ProcedureReturn FixturePath(FileName)
EndProcedure

Procedure TestR01ResolveOne()
  BeginCase("R01", "Resolve one referenced PNAMES entry")
  Protected pnamesMemory.i = MakePNames(1)
  Protected path.s
  Protected catalog.TextureCatalog
  Protected names.PNamesTable
  Protected t1.i, t1Size.l
  Protected namesSize.l
  Protected namesBytes.i
  Protected expected.i

  Check(Bool(pnamesMemory <> 0), "PNAMES fixture allocated")
  If pnamesMemory = 0
    ProcedureReturn
  EndIf
  SetPName(pnamesMemory, 0, "PATCH1")
  path = BuildResolutionWad("resolve1.wad", pnamesMemory)
  Check(Bool(path <> ""), "synthetic WAD created")
  If path = ""
    FreeMemory(pnamesMemory)
    ProcedureReturn
  EndIf
  Check(Bool(WADOpen(path)), "WAD opens")
  expected = WADFindLump("PATCH1")
  Check(Bool(expected >= 0), "patch lump exists")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  Check(Bool(t1 <> 0 And namesBytes <> 0), "resource buffers loaded")
  If t1 <> 0 And namesBytes <> 0
    Check(Bool(PNamesDecode(namesBytes, namesSize, @names)), "PNAMES decodes")
    Check(Bool(TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)), "TEXTURE1 decodes")
    Check(Bool(TextureCatalogResolve(@catalog, @names)), "resolution succeeds")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = expected), "resolved lump index matches WADFindLump")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
EndProcedure

Procedure TestR02SharedPName()
  BeginCase("R02", "Multiple placements referencing one PNAMES entry")
  Protected pnamesMemory.i = MakePNames(1)
  Protected texture.ByteBuffer
  Protected patch.i = MakeDummyPatch(16)
  Protected path.s = FixturePath("resolve2.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l
  Protected expected.i

  SetPName(pnamesMemory, 0, "PATCH1")
  TBStart(@texture, 1)
  TBAddHeader(@texture, 0, "WALL2", 0, 64, 64, 0, 2)
  TBAddPatch(@texture, 0, 0, 0, 0, 0)
  TBAddPatch(@texture, 32, 0, 0, 0, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  WadAddEntry("PATCH1", patch, 16)
  Check(Bool(WadWrite("resolve2.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  expected = WADFindLump("PATCH1")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  Check(Bool(t1 <> 0 And namesBytes <> 0), "resources loaded")
  If t1 <> 0 And namesBytes <> 0
    Check(Bool(PNamesDecode(namesBytes, namesSize, @names)), "PNAMES decodes")
    Check(Bool(TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)), "TEXTURE1 decodes")
    Check(Bool(TextureCatalogResolve(@catalog, @names)), "resolution succeeds")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = expected), "first placement resolves correctly")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 1) = expected), "second placement uses the same index")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
  FreeMemory(patch)
  BBFree(@texture)
EndProcedure

Procedure TestR03InvalidPNameIndex()
  BeginCase("R03", "Negative and out-of-range PNAMES indices")
  Protected pnamesMemory.i = MakePNames(1)
  Protected texture.ByteBuffer
  Protected patch.i = MakeDummyPatch(16)
  Protected path.s = FixturePath("resolve3.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l

  SetPName(pnamesMemory, 0, "PATCH1")
  TBStart(@texture, 1)
  TBAddHeader(@texture, 0, "WALL3", 0, 64, 64, 0, 1)
  TBAddPatch(@texture, 0, 0, -1, 0, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  WadAddEntry("PATCH1", patch, 16)
  Check(Bool(WadWrite("resolve3.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    Check(Bool(PNamesDecode(namesBytes, namesSize, @names)), "PNAMES decodes")
    Check(Bool(TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)), "TEXTURE1 decodes")
    Check(Bool(TextureCatalogResolve(@catalog, @names) = #False), "negative PNAMES index fails resolution")
    Check(Bool(FindString(TextureDefsLastError(), "invalid PNAMES index") > 0), "error identifies the bad index")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = -1), "no stale resolved index remains")
  EndIf

  TextureCatalogReset(@catalog)
  If t1 <> 0
    FreeMemory(t1)
    t1 = 0
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
    namesBytes = 0
  EndIf
  BBFree(@texture)
  TBStart(@texture, 1)
  TBAddHeader(@texture, 0, "WALL3B", 0, 64, 64, 0, 1)
  TBAddPatch(@texture, 0, 0, 1, 0, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  WadAddEntry("PATCH1", patch, 16)
  Check(Bool(WadWrite("resolve3b.wad")), "second synthetic WAD created")
  WADClose()
  Check(Bool(WADOpen(FixturePath("resolve3b.wad"))), "second WAD opens")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names) = #False), "index == count fails resolution")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(FixturePath("resolve3.wad"))
  DeleteFile(FixturePath("resolve3b.wad"))
  FreeMemory(pnamesMemory)
  FreeMemory(patch)
  BBFree(@texture)
EndProcedure

Procedure TestR04MissingPatch()
  BeginCase("R04", "Referenced PNAMES entry missing from the WAD")
  Protected pnamesMemory.i = MakePNames(1)
  Protected texture.ByteBuffer
  Protected path.s = FixturePath("resolve4.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l

  SetPName(pnamesMemory, 0, "MISSING")
  TBAddOneTexture(@texture, "WALL4", 32, 32, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  Check(Bool(WadWrite("resolve4.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names) = #False), "missing patch fails resolution")
    Check(Bool(FindString(TextureDefsLastError(), "missing from the WAD") > 0), "error identifies the missing patch")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = -1), "no fallback index is stored")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
  BBFree(@texture)
EndProcedure

Procedure TestR05UnusedMissing()
  BeginCase("R05", "Unused missing PNAMES entry does not fail resolution")
  Protected pnamesMemory.i = MakePNames(2)
  Protected texture.ByteBuffer
  Protected patch.i = MakeDummyPatch(16)
  Protected path.s = FixturePath("resolve5.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l
  Protected expected.i

  SetPName(pnamesMemory, 0, "MISSING")
  SetPName(pnamesMemory, 1, "PRESENT")
  TBAddOneTexture(@texture, "WALL5", 16, 16, 1)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 20)
  WadAddEntry("PRESENT", patch, 16)
  Check(Bool(WadWrite("resolve5.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  expected = WADFindLump("PRESENT")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names)), "resolution succeeds with an unused missing entry")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = expected), "referenced entry resolves")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
  FreeMemory(patch)
  BBFree(@texture)
EndProcedure

Procedure TestR06DuplicateLumpLastWins()
  BeginCase("R06", "Duplicate patch lump names: last directory entry wins")
  Protected pnamesMemory.i = MakePNames(1)
  Protected texture.ByteBuffer
  Protected first.i = MakeDummyPatch(16)
  Protected second.i = MakeDummyPatch(32)
  Protected path.s = FixturePath("resolve6.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l
  Protected expected.i

  SetPName(pnamesMemory, 0, "DUP")
  TBAddOneTexture(@texture, "WALL6", 16, 16, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  WadAddEntry("DUP", first, 16)
  WadAddEntry("DUP", second, 32)
  Check(Bool(WadWrite("resolve6.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  expected = WADFindLump("DUP")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names)), "resolution succeeds")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = expected), "later duplicate lump wins")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
  FreeMemory(first)
  FreeMemory(second)
  BBFree(@texture)
EndProcedure

Procedure TestR07TextureFirstMatch()
  BeginCase("R07", "Duplicate texture names across TEXTURE1/TEXTURE2")
  Protected t1.ByteBuffer
  Protected t2.ByteBuffer
  Protected catalog.TextureCatalog

  TBStart(@t1, 2)
  TBAddHeader(@t1, 0, "DUP", 0, 16, 16, 0, 0)
  TBAddHeader(@t1, 1, "AAA", 0, 16, 16, 0, 0)
  TBStart(@t2, 2)
  TBAddHeader(@t2, 0, "DUP", 0, 32, 32, 0, 0)
  TBAddHeader(@t2, 1, "BBB", 0, 32, 32, 0, 0)

  Check(Bool(TextureCatalogDecode(t1\Data, t1\Pos, t2\Data, t2\Pos, 1, @catalog)), "catalog decodes")
  Check(Bool(TextureCatalogCount(@catalog) = 4), "TEXTURE1 definitions precede TEXTURE2")
  Check(Bool(TextureCatalogFindName(@catalog, "DUP") = 0), "duplicate texture lookup returns the first index")
  Check(Bool(TextureCatalogFindName(@catalog, "aaa") = 1), "case-insensitive lookup in TEXTURE1")
  Check(Bool(TextureCatalogFindName(@catalog, "BBB") = 3), "TEXTURE2 definition has the combined index")
  TextureCatalogReset(@catalog)
  BBFree(@t1)
  BBFree(@t2)
EndProcedure

Procedure TestR08OptionalTexture2()
  BeginCase("R08", "TEXTURE2 missing versus malformed")
  Protected t1.ByteBuffer
  Protected malformed.ByteBuffer
  Protected catalog.TextureCatalog

  TBStart(@t1, 1)
  TBAddHeader(@t1, 0, "ONLY1", 0, 16, 16, 0, 0)
  TBStart(@malformed, 1)   ; declares one texture but no offset directory entry
  Check(Bool(TextureCatalogDecode(t1\Data, t1\Pos, 0, 0, 0, @catalog)), "absent TEXTURE2 is accepted")
  Check(Bool(TextureCatalogCount(@catalog) = 1), "catalog has only TEXTURE1 definitions")
  TextureCatalogReset(@catalog)

  Check(Bool(TextureCatalogDecode(t1\Data, t1\Pos, malformed\Data, malformed\Pos, 1, @catalog) = #False), "malformed TEXTURE2 is rejected")
  Check(Bool(FindString(TextureDefsLastError(), "TEXTURE2") > 0), "error identifies TEXTURE2")
  Check(Bool(TextureCatalogCount(@catalog) = 0), "failed catalog decode leaves no partial definitions")
  BBFree(@t1)
  BBFree(@malformed)
EndProcedure

Procedure TestR09NoncanonicalAndZeroLength()
  BeginCase("R09", "Zero-length patch and noncanonical PNAMES name")
  Protected pnamesMemory.i = MakePNames(1)
  Protected texture.ByteBuffer
  Protected path.s = FixturePath("resolve9.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l

  SetPName(pnamesMemory, 0, "ZERO")
  TBAddOneTexture(@texture, "WALL9", 16, 16, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  WadAddEntry("ZERO", 0, 0)
  Check(Bool(WadWrite("resolve9.wad")), "zero-length-patch WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names) = #False), "zero-length patch fails resolution")
    Check(Bool(FindString(TextureDefsLastError(), "zero-length") > 0), "error identifies the zero-length lump")
  EndIf

  ; Noncanonical name: 'A', NUL, 'B' in the same PNAMES entry.
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  PokeA(namesBytes + 4, Asc("A"))
  PokeA(namesBytes + 5, 0)
  PokeA(namesBytes + 6, Asc("B"))
  PokeA(namesBytes + 7, 0)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names) = #False), "embedded-NUL PNAMES name fails resolution")
    Check(Bool(FindString(TextureDefsLastError(), "noncanonical") > 0), "error identifies the noncanonical name")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
  BBFree(@texture)
EndProcedure

Procedure TestR10Invalidation()
  BeginCase("R10", "WAD close/reopen invalidation and re-resolution")
  Protected pnamesMemory.i = MakePNames(1)
  Protected texture.ByteBuffer
  Protected patch.i = MakeDummyPatch(16)
  Protected path.s = FixturePath("resolve10.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l
  Protected expected.i

  SetPName(pnamesMemory, 0, "PATCH1")
  TBAddOneTexture(@texture, "WALL10", 16, 16, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  WadAddEntry("PATCH1", patch, 16)
  Check(Bool(WadWrite("resolve10.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  expected = WADFindLump("PATCH1")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names)), "initial resolution succeeds")
    Check(Bool(TextureCatalogInvalidateResolved(@catalog)), "invalidation succeeds")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = -1), "invalidation removes stale indices")
    WADClose()
    Check(Bool(WADOpen(path)), "WAD reopens")
    Check(Bool(TextureCatalogResolve(@catalog, @names)), "re-resolution after reopen succeeds")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = expected), "re-resolved index is correct")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
  FreeMemory(patch)
  BBFree(@texture)
EndProcedure

; ---------------------------------------------------------------------------
; I01 - I03: synthetic WAD integration
; ---------------------------------------------------------------------------

Procedure TestI01RawBuffersReleased()
  BeginCase("I01", "Synthetic WAD; raw buffers released after decode")
  Protected pnamesMemory.i = MakePNames(1)
  Protected texture.ByteBuffer
  Protected patch.i = MakeDummyPatch(16)
  Protected path.s = FixturePath("integrated1.wad")
  Protected names.PNamesTable
  Protected catalog.TextureCatalog
  Protected namesBytes.i
  Protected namesSize.l
  Protected t1.i
  Protected t1Size.l
  Protected expected.i
  Protected width.l

  SetPName(pnamesMemory, 0, "PATCH1")
  TBAddOneTexture(@texture, "WALL1", 64, 64, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  WadAddEntry("PATCH1", patch, 16)
  Check(Bool(WadWrite("integrated1.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  expected = WADFindLump("PATCH1")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  Check(Bool(t1 <> 0 And namesBytes <> 0), "raw resources loaded")
  If t1 <> 0 And namesBytes <> 0
    Check(Bool(PNamesDecode(namesBytes, namesSize, @names)), "PNAMES decodes")
    Check(Bool(TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)), "TEXTURE1 decodes")
    FreeMemory(t1)
    t1 = 0
    FreeMemory(namesBytes)
    namesBytes = 0
    Check(Bool(TextureCatalogGetProperties(@catalog, 0, @width, 0, 0, 0, 0, 0)), "decoded properties survive input release")
    Check(Bool(width = 64), "width remains 64")
    Check(Bool(TextureCatalogResolve(@catalog, @names)), "resolution works after raw buffers are freed")
    Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = expected), "resolved index is correct")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(path)
  FreeMemory(pnamesMemory)
  FreeMemory(patch)
  BBFree(@texture)
EndProcedure

Procedure TestI02Texture2Order()
  BeginCase("I02", "Synthetic WAD with TEXTURE1 and TEXTURE2")
  Protected t1Build.ByteBuffer
  Protected t2Build.ByteBuffer
  Protected t1.i
  Protected t2.i
  Protected t1Size.l
  Protected t2Size.l
  Protected catalog.TextureCatalog
  Protected path.s = FixturePath("integrated2.wad")

  TBStart(@t1Build, 1)
  TBAddHeader(@t1Build, 0, "SHARED", 0, 16, 16, 0, 0)
  TBStart(@t2Build, 2)
  TBAddHeader(@t2Build, 0, "SHARED", 0, 32, 32, 0, 0)
  TBAddHeader(@t2Build, 1, "SECOND", 0, 48, 48, 0, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", t1Build\Data, t1Build\Pos)
  WadAddEntry("TEXTURE2", t2Build\Data, t2Build\Pos)
  Check(Bool(WadWrite("integrated2.wad")), "synthetic WAD created")
  Check(Bool(WADOpen(path)), "WAD opens")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  t2 = LoadLumpByName("TEXTURE2", @t2Size)
  Check(Bool(t1 <> 0 And t2 <> 0), "both texture lumps loaded")
  If t1 <> 0 And t2 <> 0
    Check(Bool(TextureCatalogDecode(t1, t1Size, t2, t2Size, 1, @catalog)), "catalog decodes")
    Check(Bool(TextureCatalogCount(@catalog) = 3), "three definitions in source order")
    Check(Bool(TextureCatalogFindName(@catalog, "SHARED") = 0), "first-match across lumps returns TEXTURE1")
    Check(Bool(TextureCatalogFindName(@catalog, "SECOND") = 2), "TEXTURE2 retains its combined index")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If t2 <> 0
    FreeMemory(t2)
  EndIf
  TextureCatalogReset(@catalog)
  WADClose()
  DeleteFile(path)
  BBFree(@t1Build)
  BBFree(@t2Build)
EndProcedure

Procedure TestI03FailurePaths()
  BeginCase("I03", "Missing TEXTURE1, malformed TEXTURE2 and invalid patch")
  Protected texture.ByteBuffer
  Protected malformed.ByteBuffer
  Protected pnamesMemory.i = MakePNames(1)
  Protected catalog.TextureCatalog
  Protected names.PNamesTable
  Protected path.s
  Protected t1.i, t1Size.l
  Protected t2.i, t2Size.l
  Protected namesBytes.i, namesSize.l

  ; Missing TEXTURE1.
  WadEntriesReset()
  WadAddEntry("PNAMES", pnamesMemory, 12)
  Check(Bool(WadWrite("integrated3a.wad")), "WAD without TEXTURE1 created")
  Check(Bool(WADOpen(FixturePath("integrated3a.wad"))), "WAD opens")
  Check(Bool(WADFindLump("TEXTURE1") = -1), "missing TEXTURE1 is reported")
  WADClose()
  DeleteFile(FixturePath("integrated3a.wad"))

  ; Malformed TEXTURE2 with a valid TEXTURE1.
  TBStart(@texture, 1)
  TBAddHeader(@texture, 0, "VALID1", 0, 16, 16, 0, 0)
  TBStart(@malformed, 1)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("TEXTURE2", malformed\Data, 4)   ; declares one texture, no directory entry
  Check(Bool(WadWrite("integrated3b.wad")), "malformed-TEXTURE2 WAD created")
  Check(Bool(WADOpen(FixturePath("integrated3b.wad"))), "WAD opens")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  t2 = LoadLumpByName("TEXTURE2", @t2Size)
  If t1 <> 0 And t2 <> 0
    Check(Bool(TextureCatalogDecode(t1, t1Size, t2, t2Size, 1, @catalog) = #False), "malformed TEXTURE2 fails catalog decode")
    Check(Bool(TextureCatalogCount(@catalog) = 0), "catalog is empty after the failure")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If t2 <> 0
    FreeMemory(t2)
  EndIf
  TextureCatalogReset(@catalog)
  WADClose()
  DeleteFile(FixturePath("integrated3b.wad"))

  ; Invalid referenced patch: PNAMES points to a name absent from the WAD.
  SetPName(pnamesMemory, 0, "MISSING")
  TBStart(@texture, 1)
  TBAddHeader(@texture, 0, "BROKEN", 0, 16, 16, 0, 1)
  TBAddPatch(@texture, 0, 0, 0, 0, 0)
  WadEntriesReset()
  WadAddEntry("TEXTURE1", texture\Data, texture\Pos)
  WadAddEntry("PNAMES", pnamesMemory, 12)
  Check(Bool(WadWrite("integrated3c.wad")), "invalid-patch WAD created")
  Check(Bool(WADOpen(FixturePath("integrated3c.wad"))), "WAD opens")
  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 <> 0 And namesBytes <> 0
    PNamesDecode(namesBytes, namesSize, @names)
    TextureCatalogDecode(t1, t1Size, 0, 0, 0, @catalog)
    Check(Bool(TextureCatalogResolve(@catalog, @names) = #False), "invalid referenced patch fails resolution")
  EndIf
  If t1 <> 0
    FreeMemory(t1)
  EndIf
  If namesBytes <> 0
    FreeMemory(namesBytes)
  EndIf
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(FixturePath("integrated3c.wad"))
  FreeMemory(pnamesMemory)
  BBFree(@texture)
  BBFree(@malformed)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB TEXTURE1/TEXTURE2 definition tests (M2-02)")

If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

TestD01SingleTexture()
TestD02DirectoryOrder()
TestD03NegativeOrigins()
TestD04EightByteName()
TestD05ShortNamePadding()
TestD06HistoricalFields()
TestD07ShortHeader()
TestD08NegativeCount()
TestD09CountCap()
TestD10TruncatedDirectory()
TestD11InvalidOffsets()
TestD12OffsetInsideDirectory()
TestD13TruncatedDefinition()
TestD14InvalidDimensions()
TestD15InvalidPatchCount()
TestD16TruncatedPatch()
TestD17ExactEndOfInput()
TestD18EmptyTable()
TestD19Reuse()
TestD20DuplicateOffsets()

TestR01ResolveOne()
TestR02SharedPName()
TestR03InvalidPNameIndex()
TestR04MissingPatch()
TestR05UnusedMissing()
TestR06DuplicateLumpLastWins()
TestR07TextureFirstMatch()
TestR08OptionalTexture2()
TestR09NoncanonicalAndZeroLength()
TestR10Invalidation()

TestI01RawBuffersReleased()
TestI02Texture2Order()
TestI03FailurePaths()

CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
