; -----------------------------------------------------------------------------
; DoomPB - M2 release integration tests (M2-07)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; End-to-end checks for WAD -> palette/resources -> texture composition ->
; flats/sprites -> validated maps -> resource binding. All synthetic fixtures
; are original. The optional I04 path reads an owner-provided IWAD read-only.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/Palette.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/Patch.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Texture.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/Sprite.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

#FNV_Offset = -3750763034362895579
#FNV_Prime = 1099511628211

Global gFixtureDirectory.s = ""
Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

; Streamed synthetic WAD writer.
Global gWadFile.i = 0
Global gWadEntryCount.i = 0
Global Dim gWadName.s(255)
Global Dim gWadPosition.q(255)
Global Dim gWadSize.q(255)

; Map lump buffers, indexed 1..10 in canonical order.
Global Dim gMapLump(10)
Global Dim gMapLumpSize.q(10)
Global gMapFloor.s = "FLOOR1"
Global gMapCeil.s = "CEIL1"
Global gMapWall.s = "WALL1"
Global gMapWallMode.i = 0

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

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "m2-release-test-tmp" + #FixtureSeparator
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

Procedure Put32(*Data.Byte, Offset.i, Value.q)
  PokeA(*Data + Offset, Value & $FF)
  PokeA(*Data + Offset + 1, (Value >> 8) & $FF)
  PokeA(*Data + Offset + 2, (Value >> 16) & $FF)
  PokeA(*Data + Offset + 3, (Value >> 24) & $FF)
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

; ---------------------------------------------------------------------------
; Canonical FNV-1a64 hashing (explicit little-endian field feeding)
; ---------------------------------------------------------------------------

Procedure.q FnvAddByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvAddByte(Hash, Value & $FF)
  Hash = FnvAddByte(Hash, (Value >> 8) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 16) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

; Canonical level metadata only: counts, links and diagnostics. No pointers,
; structure bytes or allocation addresses are mixed into the hash.
Procedure.q HashLevelMetadata(*Level.MapLevel)
  Protected hash.q = #FNV_Offset
  Protected i.i
  Protected limit.i
  Protected front.l
  Protected back.l
  Protected line.l

  hash = FnvAddLong(hash, *Level\MarkerIndex)
  hash = FnvAddLong(hash, *Level\Things\Count)
  hash = FnvAddLong(hash, *Level\Linedefs\Count)
  hash = FnvAddLong(hash, *Level\Sidedefs\Count)
  hash = FnvAddLong(hash, *Level\Vertexes\Count)
  hash = FnvAddLong(hash, *Level\Segs\Count)
  hash = FnvAddLong(hash, *Level\Subsectors\Count)
  hash = FnvAddLong(hash, *Level\Nodes\Count)
  hash = FnvAddLong(hash, *Level\Sectors\Count)
  hash = FnvAddLong(hash, Int(*Level\Reject\Size))
  hash = FnvAddLong(hash, Int(*Level\RejectRequired))
  hash = FnvAddLong(hash, *Level\Blockmap\Width)
  hash = FnvAddLong(hash, *Level\Blockmap\Height)
  hash = FnvAddLong(hash, *Level\BlockmapCells)
  hash = FnvAddLong(hash, *Level\BspRootIsSubsector)
  hash = FnvAddLong(hash, *Level\BspRootIndex)
  hash = FnvAddLong(hash, *Level\ReachableNodes)
  hash = FnvAddLong(hash, *Level\ReachableSubsectors)

  limit = *Level\Linedefs\Count
  If limit > 16
    limit = 16
  EndIf
  For i = 0 To limit - 1
    MapLevelGetLinedefLinks(*Level, i, @front, @back)
    hash = FnvAddLong(hash, front)
    hash = FnvAddLong(hash, back)
  Next

  limit = *Level\Sectors\Count
  If limit > 16
    limit = 16
  EndIf
  For i = 0 To limit - 1
    hash = FnvAddLong(hash, MapLevelGetSectorLineCount(*Level, i))
    If MapLevelGetSectorLine(*Level, i, 0, @line)
      hash = FnvAddLong(hash, line)
    EndIf
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q HashTextureImage(*Image.TextureImage)
  Protected hash.q = #FNV_Offset
  Protected i.q

  hash = FnvAddLong(hash, *Image\Width)
  hash = FnvAddLong(hash, *Image\Height)
  hash = FnvAddLong(hash, Int(*Image\OpaqueCount))
  For i = 0 To *Image\PixelCount - 1
    hash = FnvAddByte(hash, PeekA(*Image\Pixels + i))
    hash = FnvAddByte(hash, PeekA(*Image\Mask + i))
  Next
  ProcedureReturn hash
EndProcedure

; ---------------------------------------------------------------------------
; Streamed WAD writer
; ---------------------------------------------------------------------------

Procedure.i WadBegin(FileName.s)
  gWadEntryCount = 0
  gWadFile = CreateFile(#PB_Any, FixturePath(FileName))
  If gWadFile = 0
    ProcedureReturn #False
  EndIf
  WriteString(gWadFile, "PWAD", #PB_UTF8)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  WriteByte(gWadFile, 0)
  ProcedureReturn #True
EndProcedure

Procedure WadAdd(Name.s, *Data.Byte, Size.q)
  gWadName(gWadEntryCount) = Name
  gWadPosition(gWadEntryCount) = Loc(gWadFile)
  gWadSize(gWadEntryCount) = Size
  If Size > 0
    WriteData(gWadFile, *Data, Size)
  EndIf
  gWadEntryCount + 1
EndProcedure

Declare Put32File(Value.q)
Declare PutNameFile(Name.s)

Procedure.i WadFinish()
  Protected directoryOffset.q
  Protected i.i
  Protected entryPosition.q
  Protected entrySize.q
  Protected entryName.s

  directoryOffset = Loc(gWadFile)
  FileSeek(gWadFile, 4)
  Put32File(gWadEntryCount)
  Put32File(directoryOffset)
  FileSeek(gWadFile, directoryOffset)
  For i = 0 To gWadEntryCount - 1
    entryPosition = gWadPosition(i)
    entrySize = gWadSize(i)
    entryName = gWadName(i)
    Put32File(entryPosition)
    Put32File(entrySize)
    PutNameFile(entryName)
  Next
  CloseFile(gWadFile)
  gWadFile = 0
  ProcedureReturn #True
EndProcedure

Procedure Put32File(Value.q)
  WriteByte(gWadFile, Value & $FF)
  WriteByte(gWadFile, (Value >> 8) & $FF)
  WriteByte(gWadFile, (Value >> 16) & $FF)
  WriteByte(gWadFile, (Value >> 24) & $FF)
EndProcedure

Procedure PutNameFile(Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      WriteByte(gWadFile, Asc(Mid(Name, i + 1, 1)))
    Else
      WriteByte(gWadFile, 0)
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic resource builders
; ---------------------------------------------------------------------------

; One solid Doom patch column: [topdelta][len][unused][pixels][0xFF].
Procedure.i MakeSolidPatch(Width.i, Height.i, Pixel.i, *OutSize.Long)
  Protected columnBytes.i = 3 + Height + 2
  Protected size.q = 8 + Width * 4 + Width * columnBytes
  Protected *Data.Byte = NewZero(size)
  Protected x.i
  Protected y.i
  Protected cursor.q

  If *Data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  Put16(*Data, 0, Width)
  Put16(*Data, 2, Height)
  Put16(*Data, 4, 0)
  Put16(*Data, 6, 0)
  cursor = 8 + Width * 4
  For x = 0 To Width - 1
    Put32(*Data, 8 + x * 4, cursor + x * columnBytes)
    PokeA(*Data + cursor + x * columnBytes, 0)
    PokeA(*Data + cursor + x * columnBytes + 1, Height)
    PokeA(*Data + cursor + x * columnBytes + 2, 0)
    For y = 0 To Height - 1
      PokeA(*Data + cursor + x * columnBytes + 3 + y, Pixel)
    Next
    PokeA(*Data + cursor + x * columnBytes + 3 + Height, 0)
    PokeA(*Data + cursor + x * columnBytes + 4 + Height, $FF)
  Next
  *OutSize\l = size
  ProcedureReturn *Data
EndProcedure

Procedure.i MakePNames(Joined.s, *OutSize.Long)
  Protected count.i = CountString(Joined, "|") + 1
  Protected size.q = 4 + count * 8
  Protected *Data.Byte = NewZero(size)
  Protected i.i

  If *Data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  Put32(*Data, 0, count)
  For i = 0 To count - 1
    PutName8(*Data, 4 + i * 8, StringField(Joined, i + 1, "|"))
  Next
  *OutSize\l = size
  ProcedureReturn *Data
EndProcedure

Structure TexSpec
  Name.s
  PNameIndex.l
  Width.l
  Height.l
EndStructure

Procedure.i MakeTextureLump(*Specs.TexSpec, Count.i, *OutSize.Long)
  Protected size.q = 4 + Count * 4 + Count * (22 + 10)
  Protected *Data.Byte = NewZero(size)
  Protected i.i
  Protected definitionOffset.q = 4 + Count * 4
  Protected *spec.TexSpec

  If *Data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  Put32(*Data, 0, Count)
  For i = 0 To Count - 1
    *spec = *Specs + i * SizeOf(TexSpec)
    Put32(*Data, 4 + i * 4, definitionOffset)
    PutName8(*Data, definitionOffset, *spec\Name)
    Put32(*Data, definitionOffset + 8, 0)
    Put16(*Data, definitionOffset + 12, *spec\Width)
    Put16(*Data, definitionOffset + 14, *spec\Height)
    Put32(*Data, definitionOffset + 16, 0)
    Put16(*Data, definitionOffset + 20, 1)
    Put16(*Data, definitionOffset + 22, 0)
    Put16(*Data, definitionOffset + 24, 0)
    Put16(*Data, definitionOffset + 26, *spec\PNameIndex)
    Put16(*Data, definitionOffset + 28, 0)
    Put16(*Data, definitionOffset + 30, 0)
    definitionOffset + 32
  Next
  *OutSize\l = size
  ProcedureReturn *Data
EndProcedure

Procedure AddFlatLump(Name.s, Pixel.i)
  Protected *Data.Byte = NewZero(4096)

  If *Data <> 0
    FillMemory(*Data, 4096, Pixel)
    WadAdd(Name, *Data, 4096)
    FreeMemory(*Data)
  EndIf
EndProcedure

Procedure AddPatchLump(Name.s, Pixel.i)
  Protected size.q
  Protected *Data.Byte = MakeSolidPatch(16, 16, Pixel, @size)

  If *Data <> 0
    WadAdd(Name, *Data, size)
    FreeMemory(*Data)
  EndIf
EndProcedure

Procedure AddPaletteLump()
  Protected *Data.Byte = NewZero(768)

  If *Data <> 0
    WadAdd("PLAYPAL", *Data, 768)
    FreeMemory(*Data)
  EndIf
EndProcedure

Procedure AddColormapLump()
  Protected *Data.Byte = NewZero(256)
  Protected i.i

  If *Data <> 0
    For i = 0 To 255
      PokeA(*Data + i, i)
    Next
    WadAdd("COLORMAP", *Data, 256)
    FreeMemory(*Data)
  EndIf
EndProcedure

; Standard PNAMES + TEXTURE1/TEXTURE2 and patch lumps.
Procedure AddStandardTextures(WallPixel.i, IncludeTexture2.i, ExtraBeforePatch.s = "")
  Protected size.q
  Protected *Data.Byte
  Protected Dim specs.TexSpec(2)
  Protected *junk.Byte

  *Data = MakePNames("PATCHA|PATCHB", @size)
  If *Data <> 0
    WadAdd("PNAMES", *Data, size)
    FreeMemory(*Data)
  EndIf

  specs(0)\Name = "WALL1" : specs(0)\PNameIndex = 0 : specs(0)\Width = 16 : specs(0)\Height = 16
  specs(1)\Name = "WALL2" : specs(1)\PNameIndex = 1 : specs(1)\Width = 16 : specs(1)\Height = 16
  *Data = MakeTextureLump(@specs(0), 2, @size)
  If *Data <> 0
    WadAdd("TEXTURE1", *Data, size)
    FreeMemory(*Data)
  EndIf

  If IncludeTexture2
    specs(0)\Name = "WALL1" : specs(0)\PNameIndex = 1 : specs(0)\Width = 16 : specs(0)\Height = 16
    specs(1)\Name = "WALL3" : specs(1)\PNameIndex = 0 : specs(1)\Width = 16 : specs(1)\Height = 16
    *Data = MakeTextureLump(@specs(0), 2, @size)
    If *Data <> 0
      WadAdd("TEXTURE2", *Data, size)
      FreeMemory(*Data)
    EndIf
  EndIf

  If ExtraBeforePatch <> ""
    *junk = NewZero(4)
    WadAdd(ExtraBeforePatch, *junk, 4)
    FreeMemory(*junk)
  EndIf

  AddPatchLump("PATCHA", WallPixel)
  AddPatchLump("PATCHB", $22)
EndProcedure

Procedure AddStandardFlats(FlatPixel.i)
  Protected *Data.Byte

  WadAdd("F_START", 0, 0)
  AddFlatLump("FLOOR1", FlatPixel)
  AddFlatLump("CEIL1", $33)
  WadAdd("F_END", 0, 0)
  *Data = 0
EndProcedure

Procedure AddStandardSprites()
  AddPatchLump("TROOA0", $40)
  AddPatchLump("TROOB1", $41)
  AddPatchLump("TROOB3", $42)
  AddPatchLump("TROOB4", $43)
  AddPatchLump("TROOB5", $44)
  AddPatchLump("TROOB6", $45)
  AddPatchLump("TROOB7", $46)
  AddPatchLump("TROOB2B8", $47)
EndProcedure

Procedure AddSpriteNamespace()
  WadAdd("S_START", 0, 0)
  AddStandardSprites()
  WadAdd("S_END", 0, 0)
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic map builder (one sector, four one-sided walls)
; ---------------------------------------------------------------------------

Procedure MapFree()
  Protected i.i

  For i = 1 To 10
    If gMapLump(i) <> 0
      FreeMemory(gMapLump(i))
    EndIf
    gMapLump(i) = 0
    gMapLumpSize(i) = 0
  Next
EndProcedure

Procedure.i NewMapLump(Kind.i, Size.i)
  If gMapLump(Kind) <> 0
    FreeMemory(gMapLump(Kind))
  EndIf
  gMapLump(Kind) = NewZero(Size)
  gMapLumpSize(Kind) = Size
  ProcedureReturn gMapLump(Kind)
EndProcedure

Procedure BuildMapBuffers()
  Protected i.i

  MapFree()

  NewMapLump(1, 10)
  Put16(gMapLump(1), 6, 1)

  NewMapLump(2, 4 * 14)
  For i = 0 To 3
    Put16(gMapLump(2), i * 14, i)
    Put16(gMapLump(2), i * 14 + 2, (i + 1) % 4)
    Put16(gMapLump(2), i * 14 + 10, i)
    Put16(gMapLump(2), i * 14 + 12, -1)
  Next

  NewMapLump(3, 4 * 30)
  For i = 0 To 3
    Select gMapWallMode
      Case 1
        PutName8(gMapLump(3), i * 30 + 4, "-")
        PutName8(gMapLump(3), i * 30 + 12, "")
        PutName8(gMapLump(3), i * 30 + 20, gMapWall)
      Case 2
        PutName8(gMapLump(3), i * 30 + 4, gMapWall)
        PutName8(gMapLump(3), i * 30 + 12, "")
        PokeA(gMapLump(3) + i * 30 + 20, Asc("A"))
        PokeA(gMapLump(3) + i * 30 + 21, 0)
        PokeA(gMapLump(3) + i * 30 + 22, Asc("B"))
      Default
        PutName8(gMapLump(3), i * 30 + 4, gMapWall)
        PutName8(gMapLump(3), i * 30 + 12, gMapWall)
        PutName8(gMapLump(3), i * 30 + 20, gMapWall)
    EndSelect
    Put16(gMapLump(3), i * 30 + 28, 0)
  Next

  NewMapLump(4, 4 * 4)
  Put16(gMapLump(4), 0, 0): Put16(gMapLump(4), 2, 0)
  Put16(gMapLump(4), 4, 64): Put16(gMapLump(4), 6, 0)
  Put16(gMapLump(4), 8, 64): Put16(gMapLump(4), 10, 64)
  Put16(gMapLump(4), 12, 0): Put16(gMapLump(4), 14, 64)

  NewMapLump(5, 4 * 12)
  For i = 0 To 3
    Put16(gMapLump(5), i * 12, i)
    Put16(gMapLump(5), i * 12 + 2, (i + 1) % 4)
    Put16(gMapLump(5), i * 12 + 6, i)
    Put16(gMapLump(5), i * 12 + 8, 0)
  Next

  NewMapLump(6, 4)
  Put16(gMapLump(6), 0, 4)
  Put16(gMapLump(6), 2, 0)

  NewMapLump(7, 0)

  NewMapLump(8, 26)
  PutName8(gMapLump(8), 4, gMapFloor)
  PutName8(gMapLump(8), 12, gMapCeil)
  Put16(gMapLump(8), 20, 160)

  NewMapLump(9, 1)

  NewMapLump(10, 16)
  Put16(gMapLump(10), 4, 1)
  Put16(gMapLump(10), 6, 1)
  Put16(gMapLump(10), 8, 5)
  Put16(gMapLump(10), 10, 0)
  Put16(gMapLump(10), 12, 0)
  Put16(gMapLump(10), 14, $FFFF)
EndProcedure

Procedure SetSubsectors(Count.i)
  Protected i.i

  NewMapLump(6, Count * 4)
  For i = 0 To Count - 1
    Put16(gMapLump(6), i * 4, 1)
    Put16(gMapLump(6), i * 4 + 2, 0)
  Next
EndProcedure

Procedure SetNodes(Count.i)
  NewMapLump(7, Count * 28)
EndProcedure

Procedure SetNode(Index.i, Child0.i, Child1.i)
  Protected base.i = Index * 28

  Put16(gMapLump(7), base, 0)
  Put16(gMapLump(7), base + 2, 0)
  Put16(gMapLump(7), base + 4, 1)
  Put16(gMapLump(7), base + 6, 0)
  Put16(gMapLump(7), base + 24, Child0)
  Put16(gMapLump(7), base + 26, Child1)
EndProcedure

; Adds the marker plus the ten canonical map lumps to the open WAD.
Procedure AddMapToWad(MarkerName.s, MarkerSize.i, SwapFirstTwo.i, OmitLast.i)
  Protected i.i
  Protected *marker.Byte = 0
  Protected Dim names.s(10)

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

  If SwapFirstTwo
    names(1) = "LINEDEFS"
    names(2) = "THINGS"
  EndIf
  If MarkerSize > 0
    *marker = NewZero(MarkerSize)
    WadAdd(MarkerName, *marker, MarkerSize)
    FreeMemory(*marker)
  Else
    WadAdd(MarkerName, 0, 0)
  EndIf
  For i = 1 To 10
    If OmitLast And i = 10
      Continue
    EndIf
    WadAdd(names(i), gMapLump(i), gMapLumpSize(i))
  Next
EndProcedure

; Full standard synthetic WAD: palette, resources, namespaces and E1M1.
Declare.i ReadLumpBuffer(Name.s, *OutSize.Long)

Procedure BuildFullWadExt(FileName.s, WallPixel.i, FlatPixel.i, IncludeTexture2.i, ExtraBeforePatch.s)
  If WadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  AddPaletteLump()
  AddColormapLump()
  AddStandardTextures(WallPixel, IncludeTexture2, ExtraBeforePatch)
  AddStandardFlats(FlatPixel)
  AddSpriteNamespace()
  AddMapToWad("E1M1", 0, 0, 0)
  ProcedureReturn WadFinish()
EndProcedure

Procedure BuildFullWad(FileName.s, WallPixel.i, FlatPixel.i, IncludeTexture2.i)
  ProcedureReturn BuildFullWadExt(FileName, WallPixel, FlatPixel, IncludeTexture2, "")
EndProcedure

Procedure CloseAndDelete(FileName.s)
  WADClose()
  DeleteFile(FixturePath(FileName))
EndProcedure

Procedure.i LoadStandardCatalogs(*PNames.PNamesTable, *Catalog.TextureCatalog)
  Protected size1.q
  Protected size2.q = 0
  Protected *bytes1.Byte
  Protected *bytes2.Byte = 0
  Protected hasTexture2.i
  Protected ok.i

  *bytes1 = ReadLumpBuffer("PNAMES", @size1)
  If *bytes1 = 0
    ProcedureReturn #False
  EndIf
  ok = PNamesDecode(*bytes1, size1, *PNames)
  FreeMemory(*bytes1)
  If ok = #False
    ProcedureReturn #False
  EndIf

  *bytes1 = ReadLumpBuffer("TEXTURE1", @size1)
  If *bytes1 = 0
    ProcedureReturn #False
  EndIf
  hasTexture2 = Bool(WADFindLump("TEXTURE2") >= 0)
  If hasTexture2
    *bytes2 = ReadLumpBuffer("TEXTURE2", @size2)
    If *bytes2 = 0
      FreeMemory(*bytes1)
      ProcedureReturn #False
    EndIf
  EndIf
  ok = TextureCatalogDecode(*bytes1, size1, *bytes2, size2, hasTexture2, *Catalog)
  FreeMemory(*bytes1)
  If *bytes2 <> 0
    FreeMemory(*bytes2)
  EndIf
  If ok = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn TextureCatalogResolve(*Catalog, *PNames)
EndProcedure

; ---------------------------------------------------------------------------
; Resource helpers
; ---------------------------------------------------------------------------

; Reads a canonical name from a decoded level record. Requires validated data.
Procedure.s SectorSlotName(*Level.MapLevel, SectorIndex.i, Field.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  For i = 0 To 7
    value = MapSectorsNameByte(@*Level\Sectors, SectorIndex, Field, i)
    If value <= 0
      Break
    EndIf
    result + Chr(value)
  Next
  ProcedureReturn result
EndProcedure

Procedure.s SideSlotName(*Level.MapLevel, SideIndex.i, Field.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  For i = 0 To 7
    value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, i)
    If value <= 0
      Break
    EndIf
    result + Chr(value)
  Next
  ProcedureReturn result
EndProcedure

; Counts referenced and distinct names. Used only for diagnostics/reporting.
Procedure.i SummarizeResources(*Level.MapLevel, Label.s)
  Protected flatRefs.i = 0
  Protected wallRefs.i = 0
  Protected i.i
  Protected field.i
  Protected name.s
  Protected NewMap flatSeen.i()
  Protected NewMap wallSeen.i()

  For i = 0 To *Level\Sectors\Count - 1
    For field = 0 To 1
      name = SectorSlotName(*Level, i, field)
      If name <> ""
        flatRefs + 1
        If FindMapElement(flatSeen(), name) = 0
          AddMapElement(flatSeen(), name)
          flatSeen() = 1
        EndIf
      EndIf
    Next
  Next
  For i = 0 To *Level\Sidedefs\Count - 1
    For field = 0 To 2
      name = SideSlotName(*Level, i, field)
      If name <> "" And name <> "-"
        wallRefs + 1
        If FindMapElement(wallSeen(), name) = 0
          AddMapElement(wallSeen(), name)
          wallSeen() = 1
        EndIf
      EndIf
    Next
  Next

  PrintN("  " + Label + ": flat refs " + Str(flatRefs) + ", distinct " + Str(MapSize(flatSeen())) + "; wall refs " + Str(wallRefs) + ", distinct " + Str(MapSize(wallSeen())))
  FreeMap(flatSeen())
  FreeMap(wallSeen())
  ProcedureReturn #True
EndProcedure

; Reads a lump into a fresh owned buffer.
Procedure.i ReadLumpBuffer(Name.s, *OutSize.Long)
  Protected index.i
  Protected size.q
  Protected *memory.Byte

  index = WADFindLump(Name)
  If index < 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  size = WADLumpSize(index)
  If size <= 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *memory = AllocateMemory(size)
  If *memory = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  If WADReadLump(index, *memory, size) = #False
    FreeMemory(*memory)
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *OutSize\l = size
  ProcedureReturn *memory
EndProcedure

; ---------------------------------------------------------------------------
; CLI helper (E31/E32)
; ---------------------------------------------------------------------------

Procedure.s RunCli(ArgumentLine.s, *ExitCode.Long)
  Protected executable.s = GetPathPart(ProgramFilename()) + "DoomPB.exe"
  Protected program.i
  Protected output.s = ""

  *ExitCode\l = -1
  If FileSize(executable) < 0
    ProcedureReturn ""
  EndIf
  program = RunProgram(executable, ArgumentLine, GetPathPart(executable), #PB_Program_Open | #PB_Program_Read)
  If program = 0
    ProcedureReturn ""
  EndIf
  While ProgramRunning(program)
    If AvailableProgramOutput(program)
      output + ReadProgramString(program) + Chr(10)
    Else
      Delay(5)
    EndIf
  Wend
  While AvailableProgramOutput(program)
    output + ReadProgramString(program) + Chr(10)
  Wend
  *ExitCode\l = ProgramExitCode(program)
  CloseProgram(program)
  ProcedureReturn output
EndProcedure

Procedure.s Quote(Text.s)
  ProcedureReturn Chr(34) + Text + Chr(34)
EndProcedure

Procedure ResetMapConfig()
  gMapFloor = "FLOOR1"
  gMapCeil = "CEIL1"
  gMapWall = "WALL1"
  gMapWallMode = 0
EndProcedure

Procedure BuildMapOnlyWad(FileName.s, MarkerName.s, MarkerSize.i, SwapFirstTwo.i, OmitLast.i)
  If WadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  AddMapToWad(MarkerName, MarkerSize, SwapFirstTwo, OmitLast)
  ProcedureReturn WadFinish()
EndProcedure

; Cross-test state for E13-E17.
Global gLevel.MapLevel
Global gPNames.PNamesTable
Global gTexCat.TextureCatalog
Global gFlats.FlatCatalog
Global gTexImg.TextureImage
Global gMetaA.q
Global gImgA.q
Global gPatchIndexA.i
Global gMetaB.q

; ---------------------------------------------------------------------------
; E01 - E12
; ---------------------------------------------------------------------------

Procedure TestE01()
  BeginCase("E01", "Directory -> PNAMES/TEXTURE1 -> resolve -> compose")
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected image.TextureImage
  Protected index.i

  BuildMapBuffers()
  Check(Bool(BuildFullWad("e01.wad", $11, $33, 1)), "synthetic WAD created")
  Check(Bool(WADOpen(FixturePath("e01.wad"))), "WAD opens")
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "PNAMES/TEXTURE1/TEXTURE2 decode and resolve")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(index = 0), "first WALL1 definition selected")
  Check(Bool(TextureCompose(@catalog, index, @image)), "WALL1 composes")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $11), "composed pixel comes from PATCHA")
  Check(Bool(TextureImageOpaqueCount(@image) = 256), "16x16 texture is fully opaque")
  TextureImageReset(@image)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  CloseAndDelete("e01.wad")
EndProcedure

Procedure TestE02()
  BeginCase("E02", "Flat namespace -> FlatLoad -> owned pixels")
  Protected flats.FlatCatalog
  Protected image.FlatImage
  Protected index.i

  BuildMapBuffers()
  BuildFullWad("e02.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e02.wad"))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@flats)), "flat namespace builds")
  index = FlatCatalogFindName(@flats, "FLOOR1")
  Check(Bool(index >= 0), "FLOOR1 found inside F_START/F_END")
  Check(Bool(FlatLoad(@flats, index, @image)), "FLOOR1 decodes")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = $33), "flat pixel is correct")
  Check(Bool(FlatImageGetPixel(@image, 63, 63) = $33), "owned flat plane is complete")
  FlatImageReset(@image)
  FlatCatalogReset(@flats)
  CloseAndDelete("e02.wad")
EndProcedure

Procedure TestE03()
  BeginCase("E03", "Sprite namespace and strict frame/rotation selection")
  Protected catalog.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected wadIndex.l
  Protected flip.l

  BuildMapBuffers()
  BuildFullWad("e03.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e03.wad"))), "WAD opens")
  Check(Bool(SpriteCatalogBuild(@catalog)), "sprite namespace builds")
  Check(Bool(SpriteBuildFrames(@catalog, "TROO", @frames)), "TROO frames build")
  Check(Bool(frames\FrameCount = 2), "two frames present")
  Check(Bool(SpriteFrameGet(@frames, 0, 1, @wadIndex, @flip) And flip = 0), "A1 unflipped")
  Check(Bool(SpriteFrameGet(@frames, 0, 8, @wadIndex, @flip) And flip = 0), "A8 comes from A0 unflipped")
  Check(Bool(SpriteFrameGet(@frames, 1, 2, @wadIndex, @flip) And flip = 0), "B2 primary is unflipped")
  Check(Bool(SpriteFrameGet(@frames, 1, 8, @wadIndex, @flip) And flip = 1), "B8 secondary is flipped")
  SpriteFrameSetReset(@frames)
  SpriteCatalogReset(@catalog)
  CloseAndDelete("e03.wad")
EndProcedure

Procedure TestE04()
  BeginCase("E04", "Integrated ten-lump map load and BSP validation")
  Protected level.MapLevel

  BuildMapBuffers()
  BuildFullWad("e04.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e04.wad"))), "WAD opens")
  Check(Bool(MapLevelLoad("E1M1", @level)), "E1M1 loads")
  Check(Bool(level\Things\Count = 1 And level\Linedefs\Count = 4), "record counts")
  Check(Bool(level\Sectors\Count = 1 And level\Segs\Count = 4), "geometry counts")
  Check(Bool(level\BspRootIsSubsector = 1 And level\BspRootIndex = 0), "zero-node BSP root")
  Check(Bool(level\ReachableSubsectors = 1 And level\UnreachableSubsectors = 0), "BSP reachability")
  MapLevelReset(@level)
  CloseAndDelete("e04.wad")
EndProcedure

Procedure TestE05()
  BeginCase("E05", "Full flat and wall-texture binding")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog

  BuildMapBuffers()
  BuildFullWad("e05.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e05.wad"))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@flats)), "flats build")
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "textures build")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog)), "all flats and wall textures resolve")
  Check(Bool(MapLevelLastError() = ""), "success clears the binding error")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("e05.wad")
EndProcedure

Procedure TestE06()
  BeginCase("E06", "Canonical '-' and all-NUL wall slots are skipped")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog

  gMapWallMode = 1
  BuildMapBuffers()
  BuildFullWad("e06.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e06.wad"))), "WAD opens")
  FlatCatalogBuild(@flats)
  LoadStandardCatalogs(@p, @catalog)
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog)), "sentinel slots do not fail binding")
  Check(Bool(FlatCatalogFindName(@flats, "-") < 0), "no false flat lookup for '-'")
  Check(Bool(TextureCatalogFindName(@catalog, "-") < 0), "no false texture lookup for '-'")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("e06.wad")
EndProcedure

Procedure TestE07()
  BeginCase("E07", "Missing referenced flat fails with field/record diagnostic")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected message.s

  BuildMapBuffers()
  PutName8(gMapLump(8), 4, "NOPE")
  BuildFullWad("e07.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e07.wad"))), "WAD opens")
  FlatCatalogBuild(@flats)
  LoadStandardCatalogs(@p, @catalog)
  Check(Bool(MapLevelLoad("E1M1", @level)), "map geometry still loads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog) = #False), "missing floor flat fails")
  message = MapLevelLastError()
  Check(Bool(FindString(message, "E1M1") > 0), "diagnostic names the map")
  Check(Bool(FindString(message, "sector 0") > 0), "diagnostic names the sector")
  Check(Bool(FindString(message, "floor") > 0), "diagnostic names the field")
  Check(Bool(FindString(message, "NOPE") > 0), "diagnostic names the missing resource")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("e07.wad")
EndProcedure

Procedure TestE08()
  BeginCase("E08", "Missing referenced wall texture fails with diagnostic")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected message.s
  Protected i.i

  BuildMapBuffers()
  For i = 0 To 3
    PutName8(gMapLump(3), i * 30 + 4, "NOPE")
    PutName8(gMapLump(3), i * 30 + 12, "NOPE")
    PutName8(gMapLump(3), i * 30 + 20, "NOPE")
  Next
  BuildFullWad("e08.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e08.wad"))), "WAD opens")
  FlatCatalogBuild(@flats)
  LoadStandardCatalogs(@p, @catalog)
  Check(Bool(MapLevelLoad("E1M1", @level)), "map geometry loads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog) = #False), "missing wall texture fails")
  message = MapLevelLastError()
  Check(Bool(FindString(message, "sidedef 0") > 0), "diagnostic names the sidedef")
  Check(Bool(FindString(message, "upper") > 0), "diagnostic names the field")
  Check(Bool(FindString(message, "NOPE") > 0), "diagnostic names the texture")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("e08.wad")
EndProcedure

Procedure TestE09()
  BeginCase("E09", "Embedded-NUL resource name is rejected")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog

  gMapWallMode = 2
  BuildMapBuffers()
  BuildFullWad("e09.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e09.wad"))), "WAD opens")
  FlatCatalogBuild(@flats)
  LoadStandardCatalogs(@p, @catalog)
  Check(Bool(MapLevelLoad("E1M1", @level)), "map geometry loads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog) = #False), "embedded-NUL texture name fails")
  Check(Bool(FindString(MapLevelLastError(), "noncanonical") > 0), "error marks the name as noncanonical")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("e09.wad")
EndProcedure

Procedure TestE10()
  BeginCase("E10", "TEXTURE1 definition wins over TEXTURE2 for the same name")
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected image.TextureImage
  Protected index.i
  Protected sourceKind.l

  BuildMapBuffers()
  BuildFullWad("e10.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e10.wad"))), "WAD opens")
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "catalog resolves")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(index = 0), "first definition index is 0")
  Check(Bool(TextureCatalogGetProperties(@catalog, index, 0, 0, 0, 0, 0, @sourceKind) And sourceKind = 1), "definition comes from TEXTURE1")
  Check(Bool(TextureCompose(@catalog, index, @image)), "WALL1 composes")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $11), "TEXTURE1 patch pixels win")
  TextureImageReset(@image)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  CloseAndDelete("e10.wad")
EndProcedure

Procedure TestE11()
  BeginCase("E11", "Duplicate patch lump uses the last WAD entry")
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected image.TextureImage
  Protected index.i

  BuildMapBuffers()
  WadBegin("e11.wad")
  AddPaletteLump()
  AddColormapLump()
  AddStandardTextures($11, 1)
  AddPatchLump("PATCHA", $15)
  AddStandardFlats($33)
  AddSpriteNamespace()
  AddMapToWad("E1M1", 0, 0, 0)
  WadFinish()
  Check(Bool(WADOpen(FixturePath("e11.wad"))), "WAD opens")
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "catalog resolves")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(TextureCompose(@catalog, index, @image)), "WALL1 composes")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $15), "last duplicate PATCHA wins")
  TextureImageReset(@image)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  CloseAndDelete("e11.wad")
EndProcedure

Procedure TestE12()
  BeginCase("E12", "Flat lookup stays inside its namespace")
  Protected flats.FlatCatalog
  Protected image.FlatImage
  Protected index.i
  Protected wadIndex.l
  Protected lumpSize.l

  BuildMapBuffers()
  WadBegin("e12.wad")
  AddPaletteLump()
  AddColormapLump()
  AddStandardTextures($11, 1)
  AddStandardFlats($33)
  AddFlatLump("FLOOR1", $55)
  AddSpriteNamespace()
  AddMapToWad("E1M1", 0, 0, 0)
  WadFinish()
  Check(Bool(WADOpen(FixturePath("e12.wad"))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@flats)), "flat namespace builds")
  index = FlatCatalogFindName(@flats, "FLOOR1")
  Check(Bool(index >= 0), "FLOOR1 found")
  Check(Bool(FlatLoad(@flats, index, @image)), "interior flat decodes")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = $33), "interior flat pixels are used")
  Check(Bool(FlatCatalogGetEntry(@flats, index, @wadIndex, @lumpSize)), "entry metadata readable")
  Check(Bool(wadIndex <> WADFindLump("FLOOR1")), "outside-namespace duplicate is not selected")
  FlatImageReset(@image)
  FlatCatalogReset(@flats)
  CloseAndDelete("e12.wad")
EndProcedure

; ---------------------------------------------------------------------------
; E13 - E17: deterministic lifetime and reopen/invalidation
; ---------------------------------------------------------------------------

Procedure TestE13()
  BeginCase("E13", "WAD A: catalogs, composed image and map load together")
  Protected image.TextureImage
  Protected index.i

  BuildMapBuffers()
  BuildFullWad("e13a.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e13a.wad"))), "WAD A opens")
  Check(Bool(FlatCatalogBuild(@gFlats)), "flat catalog builds")
  Check(Bool(LoadStandardCatalogs(@gPNames, @gTexCat)), "texture catalog builds and resolves")
  index = TextureCatalogFindName(@gTexCat, "WALL1")
  Check(Bool(TextureCompose(@gTexCat, index, @image)), "WALL1 composes")
  gImgA = HashTextureImage(@image)
  TextureImageReset(@image)
  gPatchIndexA = TextureCatalogGetResolvedPatchLump(@gTexCat, index, 0)
  Check(Bool(gPatchIndexA >= 0), "patch WAD index captured")
  Check(Bool(MapLevelLoad("E1M1", @gLevel)), "E1M1 loads")
  Check(Bool(MapLevelValidateResources(@gLevel, @gFlats, @gTexCat)), "resources bind")
  gMetaA = HashLevelMetadata(@gLevel)
  Check(Bool(gMetaA <> 0), "metadata checksum computed")
EndProcedure

Procedure TestE14()
  BeginCase("E14", "Owned level and composed image survive WADClose")
  Protected image.TextureImage
  Protected index.i

  WADClose()
  Check(Bool(MapLevelIsReady(@gLevel) = #True), "level still ready after close")
  Check(Bool(MapLevelGetSectorLineCount(@gLevel, 0) = 4), "derived sector links still readable")
  Check(Bool(HashLevelMetadata(@gLevel) = gMetaA), "metadata checksum unchanged after close")
  index = TextureCatalogFindName(@gTexCat, "WALL1")
  Check(Bool(index >= 0), "catalog metadata still readable")
  Check(Bool(TextureCompose(@gTexCat, index, @image) = #False), "compose requires an open WAD")
  TextureImageReset(@image)
EndProcedure

Procedure TestE15()
  BeginCase("E15", "WAD B index shift and explicit invalidation")
  Protected image.TextureImage
  Protected index.i

  BuildMapBuffers()
  BuildFullWadExt("e13b.wad", $22, $44, 1, "JUNKA")
  Check(Bool(WADOpen(FixturePath("e13b.wad"))), "WAD B opens")
  Check(Bool(WADFindLump("PATCHA") <> gPatchIndexA), "PATCHA directory index moved")
  Check(Bool(TextureCatalogInvalidateResolved(@gTexCat)), "explicit invalidation succeeds")
  index = TextureCatalogFindName(@gTexCat, "WALL1")
  Check(Bool(TextureCompose(@gTexCat, index, @image) = #False), "stale resolution cannot be composed")
  Check(Bool(FindString(TextureLastError(), "unresolved") > 0), "compose reports an unresolved patch")
  TextureImageReset(@image)
EndProcedure

Procedure TestE16()
  BeginCase("E16", "WAD B re-resolve uses B data")
  Protected image.TextureImage
  Protected index.i

  Check(Bool(TextureCatalogResolve(@gTexCat, @gPNames)), "catalog re-resolves against WAD B")
  Check(Bool(FlatCatalogBuild(@gFlats)), "flat catalog rebuilds for WAD B")
  index = TextureCatalogFindName(@gTexCat, "WALL1")
  Check(Bool(TextureCompose(@gTexCat, index, @image)), "WALL1 composes on WAD B")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $22), "B patch pixel is used")
  TextureImageReset(@image)
  MapLevelReset(@gLevel)
  Check(Bool(MapLevelLoad("E1M1", @gLevel)), "E1M1 loads from WAD B")
  Check(Bool(MapLevelValidateResources(@gLevel, @gFlats, @gTexCat)), "WAD B resources bind")
  gMetaB = HashLevelMetadata(@gLevel)
  MapLevelReset(@gLevel)
  Check(Bool(MapLevelLoad("E1M1", @gLevel)), "E1M1 reloads from WAD B")
  Check(Bool(HashLevelMetadata(@gLevel) = gMetaB), "B metadata is stable across the reload")
EndProcedure

Procedure TestE17()
  BeginCase("E17", "Reopen WAD A and restore deterministic results")
  Protected image.TextureImage
  Protected index.i

  MapLevelReset(@gLevel)
  WADClose()
  Check(Bool(WADOpen(FixturePath("e13a.wad"))), "WAD A reopens")
  Check(Bool(TextureCatalogInvalidateResolved(@gTexCat)), "old resolution invalidated")
  Check(Bool(TextureCatalogResolve(@gTexCat, @gPNames)), "catalog re-resolves against WAD A")
  Check(Bool(FlatCatalogBuild(@gFlats)), "flat catalog rebuilds for WAD A")
  index = TextureCatalogFindName(@gTexCat, "WALL1")
  Check(Bool(TextureCompose(@gTexCat, index, @image)), "WALL1 composes again")
  Check(Bool(HashTextureImage(@image) = gImgA), "composed image checksum is deterministic")
  TextureImageReset(@image)
  Check(Bool(MapLevelLoad("E1M1", @gLevel)), "E1M1 reloads")
  Check(Bool(HashLevelMetadata(@gLevel) = gMetaA), "metadata checksum matches the first load")

  TextureCatalogReset(@gTexCat)
  PNamesReset(@gPNames)
  FlatCatalogReset(@gFlats)
  MapLevelReset(@gLevel)
  CloseAndDelete("e13a.wad")
  DeleteFile(FixturePath("e13b.wad"))
EndProcedure

; ---------------------------------------------------------------------------
; E18 - E24: map lifecycle and failure paths
; ---------------------------------------------------------------------------

Procedure TestE18()
  BeginCase("E18", "Repeated MapLevelLoad/Reset cycles stay consistent")
  Protected level.MapLevel
  Protected i.i
  Protected allReady.i = #True

  BuildMapBuffers()
  BuildFullWad("e18.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e18.wad"))), "WAD opens")
  For i = 1 To 5
    If MapLevelLoad("E1M1", @level) = #False
      allReady = #False
    EndIf
    If level\Linedefs\Count <> 4 Or level\MarkerIndex < 0
      allReady = #False
    EndIf
    MapLevelReset(@level)
    If MapLevelIsReady(@level) <> #False Or level\Linedefs\Items <> 0
      allReady = #False
    EndIf
  Next
  Check(Bool(allReady), "five load/reset cycles are consistent")
  Check(Bool(MapLevelReset(@level)), "final reset is idempotent")
  CloseAndDelete("e18.wad")
EndProcedure

Procedure TestE19()
  BeginCase("E19", "Late validation failure clears a previously loaded level")
  Protected level.MapLevel

  BuildMapBuffers()
  BuildMapOnlyWad("e19a.wad", "E1M1", 0, 0, 0)
  Check(Bool(WADOpen(FixturePath("e19a.wad"))), "good map opens")
  Check(Bool(MapLevelLoad("E1M1", @level)), "good map loads")
  WADClose()

  Put16(gMapLump(10), 12, 99)
  BuildMapOnlyWad("e19b.wad", "E1M1", 0, 0, 0)
  Check(Bool(WADOpen(FixturePath("e19b.wad"))), "bad map opens")
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "late BLOCKMAP error fails the load")
  Check(Bool(MapLevelIsReady(@level) = #False And level\Linedefs\Count = 0), "failed load leaves an empty level")
  Check(Bool(MapLevelReset(@level)), "reset after failure succeeds")
  CloseAndDelete("e19b.wad")
  DeleteFile(FixturePath("e19a.wad"))
EndProcedure

Procedure TestE20()
  BeginCase("E20", "Resource-binding failure does not mutate the level")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected front1.l, back1.l, front2.l, back2.l
  Protected lineCount1.i, lineCount2.i
  Protected line1.l, line2.l

  BuildMapBuffers()
  PutName8(gMapLump(8), 4, "NOPE")
  BuildFullWad("e20.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("e20.wad"))), "WAD opens")
  FlatCatalogBuild(@flats)
  LoadStandardCatalogs(@p, @catalog)
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  MapLevelGetLinedefLinks(@level, 0, @front1, @back1)
  MapLevelGetLinedefLinks(@level, 1, @front2, @back2)
  lineCount1 = MapLevelGetSectorLineCount(@level, 0)
  MapLevelGetSectorLine(@level, 0, 0, @line1)
  MapLevelGetSectorLine(@level, 0, 1, @line2)
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog) = #False), "binding fails")
  Check(Bool(MapLevelIsReady(@level) = #True), "source level remains ready")
  Check(Bool(MapLevelGetLinedefLinks(@level, 0, @front2, @back2) And front2 = front1 And back2 = back1), "line links unchanged")
  Check(Bool(MapLevelGetSectorLineCount(@level, 0) = lineCount1), "sector membership unchanged")
  Check(Bool(MapLevelGetSectorLine(@level, 0, 1, @line2) And line2 = line1 + 1), "membership order unchanged")
  Check(Bool(MapLevelReset(@level)), "cleanup after a failed binding")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  CloseAndDelete("e20.wad")
EndProcedure

Procedure TestE21()
  BeginCase("E21", "Missing, misordered and nonzero markers fail cleanly")
  Protected level.MapLevel

  BuildMapBuffers()
  BuildMapOnlyWad("e21a.wad", "E1M9", 0, 0, 0)
  WADOpen(FixturePath("e21a.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "missing marker fails")
  Check(Bool(FindString(MapLevelLastError(), "marker not found") > 0), "missing-marker diagnostic")
  Check(Bool(MapLevelIsReady(@level) = #False), "no partial level after missing marker")
  CloseAndDelete("e21a.wad")

  BuildMapBuffers()
  BuildMapOnlyWad("e21b.wad", "E1M1", 0, 1, 0)
  WADOpen(FixturePath("e21b.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "misordered lumps fail")
  CloseAndDelete("e21b.wad")

  BuildMapBuffers()
  BuildMapOnlyWad("e21c.wad", "E1M1", 4, 0, 0)
  WADOpen(FixturePath("e21c.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "nonzero marker fails")
  Check(Bool(FindString(MapLevelLastError(), "zero-length") > 0), "marker-size diagnostic")
  MapLevelReset(@level)
  CloseAndDelete("e21c.wad")
EndProcedure

Procedure TestE22()
  BeginCase("E22", "Invalid cross references fail before use")
  Protected level.MapLevel

  BuildMapBuffers()
  Put16(gMapLump(2), 0, 99)
  BuildMapOnlyWad("e22a.wad", "E1M1", 0, 0, 0)
  WADOpen(FixturePath("e22a.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "bad linedef vertex fails")
  CloseAndDelete("e22a.wad")

  BuildMapBuffers()
  Put16(gMapLump(5), 8, 2)
  BuildMapOnlyWad("e22b.wad", "E1M1", 0, 0, 0)
  WADOpen(FixturePath("e22b.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "bad seg side fails")
  CloseAndDelete("e22b.wad")

  BuildMapBuffers()
  Put16(gMapLump(6), 2, 65535)
  BuildMapOnlyWad("e22c.wad", "E1M1", 0, 0, 0)
  WADOpen(FixturePath("e22c.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "bad subsector range fails")
  Check(Bool(MapLevelIsReady(@level) = #False), "no partial level after bad references")
  MapLevelReset(@level)
  CloseAndDelete("e22c.wad")
EndProcedure

Procedure TestE23()
  BeginCase("E23", "Cyclic BSP fails, then a valid BSP reloads")
  Protected level.MapLevel

  BuildMapBuffers()
  SetSubsectors(2)
  SetNodes(1)
  SetNode(0, 0, $8001)
  BuildMapOnlyWad("e23a.wad", "E1M1", 0, 0, 0)
  WADOpen(FixturePath("e23a.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "self-cycle rejected")
  Check(Bool(FindString(MapLevelLastError(), "cycle") > 0), "cycle diagnostic")
  CloseAndDelete("e23a.wad")

  BuildMapBuffers()
  SetSubsectors(2)
  SetNodes(1)
  SetNode(0, $8000, $8001)
  BuildMapOnlyWad("e23b.wad", "E1M1", 0, 0, 0)
  WADOpen(FixturePath("e23b.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level)), "valid BSP reloads after the failure")
  Check(Bool(level\ReachableSubsectors = 2), "valid BSP is fully reachable")
  MapLevelReset(@level)
  CloseAndDelete("e23b.wad")
EndProcedure

Procedure TestE24()
  BeginCase("E24", "Short REJECT and out-of-range BLOCKMAP fail")
  Protected level.MapLevel

  BuildMapBuffers()
  NewMapLump(9, 0)
  BuildMapOnlyWad("e24a.wad", "E1M1", 0, 0, 0)
  WADOpen(FixturePath("e24a.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "empty REJECT fails")
  CloseAndDelete("e24a.wad")

  BuildMapBuffers()
  Put16(gMapLump(10), 12, 88)
  BuildMapOnlyWad("e24b.wad", "E1M1", 0, 0, 0)
  WADOpen(FixturePath("e24b.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level) = #False), "BLOCKMAP line 88 fails")
  Check(Bool(FindString(MapLevelLastError(), "BLOCKMAP") > 0), "BLOCKMAP diagnostic")
  MapLevelReset(@level)
  CloseAndDelete("e24b.wad")
EndProcedure

; ---------------------------------------------------------------------------
; E25 - E30: catalogs, malformed data and determinism
; ---------------------------------------------------------------------------

Procedure TestE25()
  BeginCase("E25", "Missing/corrupt PNAMES or TEXTURE1 fails explicitly")
  Protected size.q
  Protected *bytes.Byte
  Protected catalog.TextureCatalog
  Protected emptyPNames.PNamesTable
  Protected malformed.b
  Protected Dim specs.TexSpec(1)

  specs(0)\Name = "WALL1" : specs(0)\PNameIndex = 0 : specs(0)\Width = 16 : specs(0)\Height = 16

  WadBegin("e25.wad")
  AddPatchLump("PATCHA", $11)
  *bytes = MakeTextureLump(@specs(0), 1, @size)
  WadAdd("TEXTURE1", *bytes, size)
  FreeMemory(*bytes)
  WadFinish()
  Check(Bool(WADOpen(FixturePath("e25.wad"))), "WAD without PNAMES opens")
  Check(Bool(WADFindLump("PNAMES") < 0), "PNAMES is absent")
  Check(Bool(LoadStandardCatalogs(@emptyPNames, @catalog) = #False), "catalog setup fails without PNAMES")
  Check(Bool(TextureCatalogGetResolvedPatchLump(@catalog, 0, 0) = -1), "no stale resolved state is exposed")
  CloseAndDelete("e25.wad")

  WadBegin("e25b.wad")
  *bytes = NewZero(4)
  Put32(*bytes, 0, $FFFFFFFF)
  WadAdd("PNAMES", *bytes, 4)
  FreeMemory(*bytes)
  WadFinish()
  WADOpen(FixturePath("e25b.wad"))
  *bytes = ReadLumpBuffer("PNAMES", @size)
  Check(Bool(*bytes <> 0), "malformed PNAMES readable")
  Check(Bool(PNamesDecode(*bytes, size, @emptyPNames) = #False), "negative PNAMES count rejected")
  FreeMemory(*bytes)
  WADClose()

  ; A good catalog is fully reset by a malformed replacement.
  BuildMapBuffers()
  BuildFullWad("e25c.wad", $11, $33, 1)
  WADOpen(FixturePath("e25c.wad"))
  Check(Bool(LoadStandardCatalogs(@emptyPNames, @catalog)), "good catalog decodes")
  Check(Bool(TextureCatalogCount(@catalog) = 4), "four definitions before the failure")
  malformed = 1
  Check(Bool(TextureCatalogDecode(@malformed, 1, 0, 0, 0, @catalog) = #False), "malformed TEXTURE1 rejected")
  Check(Bool(TextureCatalogCount(@catalog) = 0), "failed decode clears the old catalog")
  TextureCatalogReset(@catalog)
  PNamesReset(@emptyPNames)
  CloseAndDelete("e25c.wad")
  DeleteFile(FixturePath("e25.wad"))
  DeleteFile(FixturePath("e25b.wad"))
EndProcedure

Procedure TestE26()
  BeginCase("E26", "Malformed TEXTURE2 rejected; absent TEXTURE2 accepted")
  Protected Dim specs.TexSpec(1)
  Protected size.q
  Protected *texture1.Byte
  Protected catalog.TextureCatalog
  Protected malformed.b = 0

  specs(0)\Name = "WALL1" : specs(0)\PNameIndex = 0 : specs(0)\Width = 16 : specs(0)\Height = 16
  *texture1 = MakeTextureLump(@specs(0), 1, @size)
  Check(Bool(*texture1 <> 0), "TEXTURE1 fixture built")
  Check(Bool(TextureCatalogDecode(*texture1, size, 0, 0, 0, @catalog)), "absent TEXTURE2 is valid")
  Check(Bool(TextureCatalogCount(@catalog) = 1 And catalog\HasTexture2 = 0), "only TEXTURE1 definitions are present")
  Check(Bool(TextureCatalogDecode(*texture1, size, @malformed, 1, 1, @catalog) = #False), "malformed TEXTURE2 is rejected")
  Check(Bool(FindString(TextureDefsLastError(), "TEXTURE2") > 0), "error identifies TEXTURE2")
  Check(Bool(TextureCatalogCount(@catalog) = 0), "failed catalog decode leaves no definitions")
  FreeMemory(*texture1)
  TextureCatalogReset(@catalog)
EndProcedure

Procedure TestE27()
  BeginCase("E27", "Malformed referenced patch fails composition")
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected image.TextureImage
  Protected index.i
  Protected *bad.Byte

  BuildMapBuffers()
  WadBegin("e27.wad")
  AddPaletteLump()
  AddColormapLump()
  AddStandardTextures($11, 0)
  *bad = NewZero(5)
  WadAdd("PATCHA", *bad, 5)
  FreeMemory(*bad)
  WadFinish()
  WADOpen(FixturePath("e27.wad"))
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "resolution accepts a nonzero malformed lump")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(TextureCompose(@catalog, index, @image) = #False), "composition fails")
  Check(Bool(FindString(TextureLastError(), "decode") > 0), "composition reports the patch decoder")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = -1), "no partial image is exposed")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  CloseAndDelete("e27.wad")
EndProcedure

Procedure TestE28()
  BeginCase("E28", "Interior zero-length flat is metadata only")
  Protected flats.FlatCatalog
  Protected image.FlatImage
  Protected index.i

  WadBegin("e28.wad")
  WadAdd("F_START", 0, 0)
  WadAdd("EMPTY", 0, 0)
  AddFlatLump("FLOOR1", $33)
  WadAdd("F_END", 0, 0)
  WadFinish()
  WADOpen(FixturePath("e28.wad"))
  Check(Bool(FlatCatalogBuild(@flats)), "namespace catalog builds")
  Check(Bool(FlatCatalogCount(@flats) = 2), "both interior entries are catalogued")
  index = FlatCatalogFindName(@flats, "EMPTY")
  Check(Bool(index >= 0), "zero-length flat is found as metadata")
  Check(Bool(FlatLoad(@flats, index, @image) = #False), "zero-length flat cannot decode")
  Check(Bool(FlatImageGetPixel(@image, 0, 0) = -1), "no partial flat image is exposed")
  FlatCatalogReset(@flats)
  CloseAndDelete("e28.wad")
EndProcedure

Procedure TestE29()
  BeginCase("E29", "Identical loads yield the same canonical metadata checksum")
  Protected level.MapLevel
  Protected first.q
  Protected second.q

  BuildMapBuffers()
  BuildFullWad("e29.wad", $11, $33, 1)
  WADOpen(FixturePath("e29.wad"))
  Check(Bool(MapLevelLoad("E1M1", @level)), "first load")
  first = HashLevelMetadata(@level)
  MapLevelReset(@level)
  Check(Bool(MapLevelLoad("E1M1", @level)), "second load")
  second = HashLevelMetadata(@level)
  Check(Bool(first = second), "metadata checksums are identical")
  Check(Bool(first <> 0), "checksum is nonzero")
  PrintN("  metadata checksum: " + Hex(first))
  MapLevelReset(@level)
  CloseAndDelete("e29.wad")
EndProcedure

Procedure TestE30()
  BeginCase("E30", "Canonical hash uses explicit ordered bytes")
  Protected a.q
  Protected b.q

  a = FnvAddByte(FnvAddByte(#FNV_Offset, 1), 2)
  b = FnvAddByte(FnvAddByte(#FNV_Offset, 2), 1)
  Check(Bool(a <> b), "field order affects the hash")
  a = FnvAddLong(#FNV_Offset, $01020304)
  Check(Bool(a <> 0), "explicit little-endian field hashing works")
  Check(Bool(a = FnvAddLong(#FNV_Offset, $01020304)), "field hashing is deterministic")
EndProcedure

; ---------------------------------------------------------------------------
; E31 - E32: legacy CLI compatibility
; ---------------------------------------------------------------------------

Procedure TestE31()
  BeginCase("E31", "Legacy CLI modes remain available")
  Protected output.s
  Protected exitCode.l
  Protected wadPath.s

  BuildMapBuffers()
  BuildFullWad("e31.wad", $11, $33, 1)
  wadPath = FixturePath("e31.wad")

  output = RunCli("--version", @exitCode)
  Check(Bool(exitCode = 0), "--version exits 0")
  Check(Bool(FindString(output, "DoomPB 0.2.0") > 0), "--version reports 0.2.0")

  output = RunCli("--help", @exitCode)
  Check(Bool(exitCode = 0), "--help exits 0")
  Check(Bool(FindString(output, "Usage:") > 0), "--help prints usage")

  output = RunCli("--iwad " + Quote(wadPath) + " --dump-info", @exitCode)
  Check(Bool(exitCode = 0), "--dump-info exits 0")
  Check(Bool(FindString(output, "Lumps:") > 0), "--dump-info prints directory metadata")

  output = RunCli("--iwad " + Quote(wadPath) + " --lump-info PLAYPAL", @exitCode)
  Check(Bool(exitCode = 0), "--lump-info exits 0")
  Check(Bool(FindString(output, "Size:") > 0), "--lump-info prints lump metadata")
  DeleteFile(wadPath)
EndProcedure

Procedure TestE32()
  BeginCase("E32", "CLI failures keep documented exit codes")
  Protected output.s
  Protected exitCode.l
  Protected missing.s = FixturePath("definitely-missing-m207.wad")

  output = RunCli("--iwad " + Quote(missing) + " --map-info E1M1", @exitCode)
  Check(Bool(exitCode = 1), "missing IWAD for --map-info exits 1")
  Check(Bool(FindString(output, "Cannot open WAD") > 0), "missing IWAD diagnostic printed")

  output = RunCli("--dump-info --show-title", @exitCode)
  Check(Bool(exitCode = 2), "conflicting options exit 2")

  output = RunCli("--lump-info", @exitCode)
  Check(Bool(exitCode = 2), "--lump-info without a name exits 2")
EndProcedure

; ---------------------------------------------------------------------------
; I01 - I03: integration and lifecycle
; ---------------------------------------------------------------------------

Procedure TestI01()
  BeginCase("I01", "Synthetic resource and map pipeline passes together")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected image.TextureImage
  Protected index.i
  Protected image2.TextureImage

  BuildMapBuffers()
  BuildFullWad("i01.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("i01.wad"))), "WAD opens")
  Check(Bool(FlatCatalogBuild(@flats)), "flats build")
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "textures resolve")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(TextureCompose(@catalog, index, @image)), "WALL1 composes")
  index = TextureCatalogFindName(@catalog, "WALL2")
  Check(Bool(TextureCompose(@catalog, index, @image2)), "WALL2 composes")
  Check(Bool(TextureImageOpaqueCount(@image) = 256 And TextureImageOpaqueCount(@image2) = 256), "both textures are complete")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map loads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog)), "all referenced resources resolve")
  Check(Bool(MapLevelGetSectorLineCount(@level, 0) = 4), "sector membership derived")
  TextureImageReset(@image)
  TextureImageReset(@image2)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("i01.wad")
EndProcedure

Procedure TestI02()
  BeginCase("I02", "Damaged resource failure and clean recovery")
  Protected level.MapLevel
  Protected flats.FlatCatalog
  Protected p.PNamesTable
  Protected catalog.TextureCatalog

  BuildMapBuffers()
  PutName8(gMapLump(8), 4, "NOPE")
  BuildFullWad("i02a.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("i02a.wad"))), "damaged map WAD opens")
  FlatCatalogBuild(@flats)
  LoadStandardCatalogs(@p, @catalog)
  Check(Bool(MapLevelLoad("E1M1", @level)), "map geometry loads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog) = #False), "missing flat fails binding")
  Check(Bool(MapLevelIsReady(@level) = #True), "map data is not destroyed")
  MapLevelReset(@level)
  FlatCatalogReset(@flats)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  CloseAndDelete("i02a.wad")

  ResetMapConfig()
  BuildMapBuffers()
  BuildFullWad("i02b.wad", $11, $33, 1)
  Check(Bool(WADOpen(FixturePath("i02b.wad"))), "recovered WAD opens")
  Check(Bool(FlatCatalogBuild(@flats)), "flats rebuild")
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "textures rebuild")
  Check(Bool(MapLevelLoad("E1M1", @level)), "map reloads")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog)), "recovered binding passes")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("i02b.wad")
EndProcedure

Declare.i MapLevelReadyUnchanged(*Level.MapLevel, Expected.q)

Procedure TestI03()
  BeginCase("I03", "A to B to A lifecycle is deterministic and independent")
  Protected level.MapLevel
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected flats.FlatCatalog
  Protected image.TextureImage
  Protected index.i
  Protected hashA.q
  Protected hashB.q
  Protected metaA.q

  BuildMapBuffers()
  BuildFullWad("i03a.wad", $11, $33, 1)
  BuildFullWadExt("i03b.wad", $22, $44, 1, "JUNKA")
  Check(Bool(WADOpen(FixturePath("i03a.wad"))), "WAD A opens")
  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "A catalog resolves")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(TextureCompose(@catalog, index, @image)), "A texture composes")
  hashA = HashTextureImage(@image)
  TextureImageReset(@image)
  Check(Bool(MapLevelLoad("E1M1", @level)), "A map loads")
  metaA = HashLevelMetadata(@level)
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog) = #False), "flats were not built yet")
  Check(Bool(FlatCatalogBuild(@flats)), "A flats build")
  Check(Bool(MapLevelValidateResources(@level, @flats, @catalog)), "A resources bind")
  WADClose()

  Check(Bool(WADOpen(FixturePath("i03b.wad"))), "WAD B opens")
  Check(Bool(TextureCatalogInvalidateResolved(@catalog)), "A resolution invalidated")
  Check(Bool(TextureCatalogResolve(@catalog, @p)), "B resolution succeeds")
  Check(Bool(FlatCatalogBuild(@flats)), "B flats build")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(TextureCompose(@catalog, index, @image)), "B texture composes")
  hashB = HashTextureImage(@image)
  Check(Bool(hashB <> hashA), "B content differs from A")
  TextureImageReset(@image)
  WADClose()

  Check(Bool(WADOpen(FixturePath("i03a.wad"))), "WAD A reopens")
  Check(Bool(TextureCatalogInvalidateResolved(@catalog) And TextureCatalogResolve(@catalog, @p)), "A resolution restored")
  Check(Bool(FlatCatalogBuild(@flats)), "A flats restored")
  index = TextureCatalogFindName(@catalog, "WALL1")
  Check(Bool(TextureCompose(@catalog, index, @image)), "A texture composes again")
  Check(Bool(HashTextureImage(@image) = hashA), "A checksum is deterministic")
  TextureImageReset(@image)
  Check(Bool(MapLevelReadyUnchanged(@level, metaA)), "owned A level metadata is unchanged")
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  MapLevelReset(@level)
  CloseAndDelete("i03a.wad")
  DeleteFile(FixturePath("i03b.wad"))
EndProcedure

Procedure.i MapLevelReadyUnchanged(*Level.MapLevel, Expected.q)
  If MapLevelIsReady(*Level) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(HashLevelMetadata(*Level) = Expected)
EndProcedure

; ---------------------------------------------------------------------------
; I04: real IWAD integration (optional, read-only)
; ---------------------------------------------------------------------------

Procedure.i ReadAndDecodePalette()
  Protected size.q
  Protected *bytes.Byte
  Protected palette.PaletteSet
  Protected ok.i

  *bytes = ReadLumpBuffer("PLAYPAL", @size)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  ok = PaletteDecode(*bytes, size, @palette)
  PaletteReset(@palette)
  FreeMemory(*bytes)
  ProcedureReturn ok
EndProcedure

Procedure.i ReadAndDecodeColormap()
  Protected size.q
  Protected *bytes.Byte
  Protected maps.ColormapSet
  Protected ok.i

  *bytes = ReadLumpBuffer("COLORMAP", @size)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  ok = ColormapDecode(*bytes, size, @maps)
  ColormapReset(@maps)
  FreeMemory(*bytes)
  ProcedureReturn ok
EndProcedure

Procedure TestI04(Path.s)
  BeginCase("I04", "Real Ultimate Doom IWAD: resources, maps and binding")
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected flats.FlatCatalog
  Protected sprites.SpriteCatalog
  Protected frames.SpriteFrameSet
  Protected level.MapLevel
  Protected image.TextureImage
  Protected patch.PatchImage
  Protected size.q
  Protected *bytes.Byte
  Protected index.i
  Protected i.i
  Protected total.i
  Protected composed.i = 0
  Protected failed.i = 0
  Protected opaque.q = 0
  Protected wadIndex.l
  Protected flip.l
  Protected mapName.s
  Protected hasTexture2.i
  Protected size2.q = 0
  Protected *bytes2.Byte = 0
  Protected ok.i = #True

  If WADOpen(Path) = #False
    Check(#False, "real IWAD opens: " + WADLastError())
    ProcedureReturn
  EndIf
  Check(#True, "real IWAD opens read-only")
  PrintN("  WAD: " + WADGetPath())
  PrintN("  lumps: " + Str(WADGetLumpCount()))

  Check(Bool(ReadAndDecodePalette()), "PLAYPAL decodes")
  Check(Bool(ReadAndDecodeColormap()), "COLORMAP decodes")

  Check(Bool(LoadStandardCatalogs(@p, @catalog)), "PNAMES/TEXTURE1/TEXTURE2 decode and resolve")
  total = TextureCatalogCount(@catalog)
  PrintN("  textures: " + Str(total))
  For i = 0 To total - 1
    If TextureCompose(@catalog, i, @image)
      composed + 1
      opaque + TextureImageOpaqueCount(@image)
    Else
      failed + 1
    EndIf
    TextureImageReset(@image)
  Next
  Check(Bool(failed = 0), "all wall textures compose")
  PrintN("  composed: " + Str(composed) + ", opaque pixels: " + Str(opaque))

  Check(Bool(FlatCatalogBuild(@flats)), "flat namespace builds")
  PrintN("  flats: " + Str(FlatCatalogCount(@flats)))
  Check(Bool(FlatCatalogCount(@flats) > 0), "interior flats discovered")
  Check(Bool(SpriteCatalogBuild(@sprites)), "sprite namespace builds")
  PrintN("  sprite entries: " + Str(SpriteCatalogCount(@sprites)))
  Check(Bool(SpriteCatalogCount(@sprites) > 0), "interior sprite entries discovered")
  If SpriteBuildFrames(@sprites, "TROO", @frames)
    Check(Bool(frames\FrameCount > 0), "TROO frame metadata builds")
    If SpriteFrameGet(@frames, 0, 1, @wadIndex, @flip)
      *bytes = ReadLumpBuffer("TROOA1", @size)
      If *bytes <> 0
        Check(Bool(PatchDecode(*bytes, size, @patch)), "sample sprite patch decodes")
        PatchReset(@patch)
        FreeMemory(*bytes)
      Else
        Check(#False, "sample TROOA1 patch lump exists")
      EndIf
    EndIf
    SpriteFrameSetReset(@frames)
  Else
    Check(#False, "TROO frames build: " + SpriteLastError())
  EndIf

  Protected Dim mapNames.s(2)
  mapNames(0) = "E1M1"
  mapNames(1) = "E1M2"
  mapNames(2) = "E4M1"
  For i = 0 To 2
    mapName = mapNames(i)
    MapLevelReset(@level)
    If MapLevelLoad(mapName, @level) = #False
      Check(#False, mapName + " loads: " + MapLevelLastError())
      ok = #False
      Continue
    EndIf
    Check(Bool(MapLevelValidateResources(@level, @flats, @catalog)), mapName + " references resolve")
    SummarizeResources(@level, mapName)
    Check(Bool(HashLevelMetadata(@level) <> 0), mapName + " metadata checksum computed")
    PrintN("  " + mapName + " metadata hash: " + Hex(HashLevelMetadata(@level)))
    MapLevelReset(@level)
  Next

  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
  SpriteCatalogReset(@sprites)
  WADClose()
  Check(Bool(ok), "real IWAD pipeline completed")
  Check(Bool(WADIsOpen() = #False), "WAD closed after the real run")
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M2 release integration tests (M2-07)")
If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

ResetMapConfig()
ResetMapConfig()
TestE01()
ResetMapConfig()
TestE02()
ResetMapConfig()
TestE03()
ResetMapConfig()
TestE04()
ResetMapConfig()
TestE05()
ResetMapConfig()
TestE06()
ResetMapConfig()
TestE07()
ResetMapConfig()
TestE08()
ResetMapConfig()
TestE09()
ResetMapConfig()
TestE10()
ResetMapConfig()
TestE11()
ResetMapConfig()
TestE12()
ResetMapConfig()
TestE13()
ResetMapConfig()
TestE14()
ResetMapConfig()
TestE15()
ResetMapConfig()
TestE16()
ResetMapConfig()
TestE17()
ResetMapConfig()
TestE18()
ResetMapConfig()
TestE19()
ResetMapConfig()
TestE20()
ResetMapConfig()
TestE21()
ResetMapConfig()
TestE22()
ResetMapConfig()
TestE23()
ResetMapConfig()
TestE24()
ResetMapConfig()
TestE25()
ResetMapConfig()
TestE26()
ResetMapConfig()
TestE27()
ResetMapConfig()
TestE28()
ResetMapConfig()
TestE29()
ResetMapConfig()
TestE30()
ResetMapConfig()
TestE31()
ResetMapConfig()
TestE32()
ResetMapConfig()
TestI01()
ResetMapConfig()
TestI02()
ResetMapConfig()
TestI03()

If ProgramParameter(0) <> "" And FileSize(ProgramParameter(0)) >= 0
  TestI04(ProgramParameter(0))
Else
  PrintN("")
  PrintN("[I04] Real IWAD integration: NOT RUN (no WAD path argument)")
EndIf

MapFree()
CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
