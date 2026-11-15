; -----------------------------------------------------------------------------
; DoomPB - composite wall texture tests (M2-03)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; All patches, texture definitions, PNAMES tables and WADs are synthetic. No
; Doom resources are copied or required. Temporary WADs are written under the
; ignored build/ tree and removed after use.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Texture.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

Global gFixtureDirectory.s = ""
Global gExtraCount.i = 0
Global Dim gExtraNames.s(63)
Global Dim gExtraPointers.i(63)
Global Dim gExtraSizes.q(63)
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

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "wad-composite-test-tmp" + #FixtureSeparator
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

Procedure.q FnvByte(hash.q, value.i)
  ProcedureReturn (hash ! value) * 1099511628211
EndProcedure

Procedure.q TextureChecksum(*Image.TextureImage)
  Protected i.q
  Protected hash.q = 14695981039346656037

  For i = 0 To *Image\PixelCount - 1
    hash = FnvByte(hash, PeekA(*Image\Pixels + i))
    hash = FnvByte(hash, PeekA(*Image\Mask + i))
  Next
  ProcedureReturn hash
EndProcedure

; ---------------------------------------------------------------------------
; Byte, patch and texture builders
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

; ---- Doom patch builder ----

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

Procedure PatchSetOffset(*B.ByteBuffer, Column.i, Offset.q)
  BBSetLong(*B, 8 + Column * 4, Offset)
EndProcedure

Procedure PatchAddColumn(*B.ByteBuffer, Column.i, *Col.ByteBuffer)
  PatchSetOffset(*B, Column, *B\Pos)
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

; A patch whose every column is fully opaque from row 0 to Height-1.
Procedure SolidPatch(*B.ByteBuffer, Width.i, Height.i, Value.i)
  Protected col.ByteBuffer
  Protected pixels.s
  Protected i.i

  pixels = ""
  For i = 1 To Height
    pixels + RSet(Hex(Value & $FF), 2, "0")
  Next
  PatchStart(*B, Width, Height, 0, 0)
  For i = 0 To Width - 1
    BBInit(@col, 32)
    PatchPost(@col, 0, pixels)
    PatchTerm(@col)
    PatchAddColumn(*B, i, @col)
    BBFree(@col)
  Next
EndProcedure

; ---- Texture definition builder ----

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
  Protected i.i

  TBSetOffset(*B, TextureIndex, *B\Pos)
  For i = 0 To 7
    If i < Len(Name)
      BBByte(*B, Asc(Mid(Name, i + 1, 1)))
    Else
      BBByte(*B, 0)
    EndIf
  Next
  BBLong(*B, Masked)
  BBWord(*B, Width)
  BBWord(*B, Height)
  BBLong(*B, ColumnDirectory)
  BBWord(*B, PatchCount)
EndProcedure

Procedure TBAddPatch(*B.ByteBuffer, OriginX.i, OriginY.i, PNameIndex.i)
  BBWord(*B, OriginX)
  BBWord(*B, OriginY)
  BBWord(*B, PNameIndex)
  BBWord(*B, 0)
  BBWord(*B, 0)
EndProcedure

; One texture with caller-supplied placements (originx/originy/pname triples).
Procedure TBAddTextureWithPlacements(*B.ByteBuffer, Name.s, Width.i, Height.i, *OriginsX.Long, *OriginsY.Long, *PNames.Long, PlacementCount.i)
  Protected i.i

  TBStart(*B, 1)
  TBAddHeader(*B, 0, Name, 0, Width, Height, 0, PlacementCount)
  For i = 0 To PlacementCount - 1
    TBAddPatch(*B, PeekL(*OriginsX + i * 4), PeekL(*OriginsY + i * 4), PeekL(*PNames + i * 4))
  Next
EndProcedure

; ---------------------------------------------------------------------------
; PNAMES and WAD assembly
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

Procedure WadExtrasReset()
  gExtraCount = 0
EndProcedure

Procedure AddWadExtra(Name.s, *Data.Byte, Size.q)
  gExtraNames(gExtraCount) = Name
  gExtraPointers(gExtraCount) = *Data
  gExtraSizes(gExtraCount) = Size
  gExtraCount + 1
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

Procedure.i BuildWadFile(FileName.s, *Texture.ByteBuffer, PNamesMemory.i, PNamesSize.q)
  Protected path.s = FixturePath(FileName)
  Protected file.i
  Protected total.i = gExtraCount + 2
  Protected directoryOffset.q
  Protected i.i
  Protected Dim positions.q(63)
  Protected Dim names.s(63)
  Protected Dim pointers.i(63)
  Protected Dim sizes.q(63)

  names(0) = "TEXTURE1"
  pointers(0) = *Texture\Data
  sizes(0) = *Texture\Pos
  names(1) = "PNAMES"
  pointers(1) = PNamesMemory
  sizes(1) = PNamesSize
  For i = 0 To gExtraCount - 1
    names(i + 2) = gExtraNames(i)
    pointers(i + 2) = gExtraPointers(i)
    sizes(i + 2) = gExtraSizes(i)
  Next

  file = CreateFile(#PB_Any, path)
  If file = 0
    ProcedureReturn #False
  EndIf
  WriteString(file, "PWAD")
  WriteU32File(file, total)
  WriteU32File(file, 0)
  For i = 0 To total - 1
    positions(i) = Loc(file)
    If sizes(i) > 0
      WriteData(file, pointers(i), sizes(i))
    EndIf
  Next
  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32File(file, directoryOffset)
  FileSeek(file, directoryOffset)
  For i = 0 To total - 1
    WriteLumpEntryFile(file, positions(i), sizes(i), names(i))
  Next
  CloseFile(file)
  ProcedureReturn #True
EndProcedure

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

; Builds the WAD, opens it, decodes PNAMES/TEXTURE1, releases the raw payloads
; and optionally resolves the catalog. Leaves the WAD open on success.
Procedure.i BuildLoadCatalog(FileName.s, *Texture.ByteBuffer, PNamesMemory.i, PNamesSize.q, DoResolve.i, *Catalog.TextureCatalog, *Names.PNamesTable)
  Protected path.s = FixturePath(FileName)
  Protected t1.i
  Protected t1Size.l
  Protected namesBytes.i
  Protected namesSize.l

  If BuildWadFile(FileName, *Texture, PNamesMemory, PNamesSize) = #False
    TextureImageSetError("Cannot create synthetic WAD.")
    ProcedureReturn #False
  EndIf
  If WADOpen(path) = #False
    DeleteFile(path)
    ProcedureReturn #False
  EndIf

  t1 = LoadLumpByName("TEXTURE1", @t1Size)
  namesBytes = LoadLumpByName("PNAMES", @namesSize)
  If t1 = 0 Or namesBytes = 0
    If t1 <> 0
      FreeMemory(t1)
    EndIf
    If namesBytes <> 0
      FreeMemory(namesBytes)
    EndIf
    WADClose()
    DeleteFile(path)
    ProcedureReturn #False
  EndIf

  If PNamesDecode(namesBytes, namesSize, *Names) = #False
    FreeMemory(t1)
    FreeMemory(namesBytes)
    WADClose()
    DeleteFile(path)
    ProcedureReturn #False
  EndIf
  If TextureCatalogDecode(t1, t1Size, 0, 0, 0, *Catalog) = #False
    FreeMemory(t1)
    FreeMemory(namesBytes)
    WADClose()
    DeleteFile(path)
    ProcedureReturn #False
  EndIf
  FreeMemory(t1)
  FreeMemory(namesBytes)

  If DoResolve
    If TextureCatalogResolve(*Catalog, *Names) = #False
      WADClose()
      DeleteFile(path)
      ProcedureReturn #False
    EndIf
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure CleanupCase(FileName.s, *Catalog.TextureCatalog, *Names.PNamesTable, *Image.TextureImage)
  TextureImageReset(*Image)
  TextureCatalogReset(*Catalog)
  PNamesReset(*Names)
  WADClose()
  DeleteFile(FixturePath(FileName))
EndProcedure

; Builds PNAMES from the current extra-lump names, in extras order.
Procedure.i PNamesFromExtras()
  Protected memory.i = MakePNames(gExtraCount)
  Protected i.i

  If memory <> 0
    For i = 0 To gExtraCount - 1
      SetPName(memory, i, gExtraNames(i))
    Next
  EndIf
  ProcedureReturn memory
EndProcedure

; ---------------------------------------------------------------------------
; X01 - X30
; ---------------------------------------------------------------------------

Procedure TestX01SinglePatch()
  BeginCase("X01", "One opaque 2x2 patch at the origin")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x01.wad"

  SolidPatch(@patch, 2, 2, $11)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEXTURE1", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads and resolves")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(image\Width = 2 And image\Height = 2), "dimensions are 2x2")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $11 And TextureImageGetPixel(@image, 1, 1) = $11), "all indices are 0x11")
  Check(Bool(TextureImageOpaqueCount(@image) = 4), "all four pixels are opaque")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX02TransparentGaps()
  BeginCase("X02", "Patch with transparent gaps")
  Protected patch.ByteBuffer, col.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x02.wad"

  PatchStart(@patch, 2, 3, 0, 0)
  BBInit(@col, 32)
  PatchPost(@col, 0, "15")
  PatchPost(@col, 2, "16")
  PatchTerm(@col)
  PatchAddColumn(@patch, 0, @col)
  BBFree(@col)
  BBInit(@col, 32)
  PatchPost(@col, 1, "17")
  PatchTerm(@col)
  PatchAddColumn(@patch, 1, @col)
  BBFree(@col)

  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX2", 0, 2, 3, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $15 And TextureImageGetPixel(@image, 1, 1) = $17), "post pixels are present")
  Check(Bool(TextureImageIsOpaque(@image, 0, 1) = 0), "gap row is transparent")
  Check(Bool(TextureImageIsOpaque(@image, 1, 0) = 0 And TextureImageIsOpaque(@image, 1, 2) = 0), "empty areas stay transparent")
  Check(Bool(TextureImageOpaqueCount(@image) = 3), "exactly three opaque pixels")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX03Index255()
  BeginCase("X03", "Opaque palette index 255")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x03.wad"

  SolidPatch(@patch, 1, 1, 255)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX3", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = 255), "index 255 is preserved")
  Check(Bool(TextureImageIsOpaque(@image, 0, 0) = 1), "index 255 is opaque")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX04LaterOpaqueWins()
  BeginCase("X04", "Two patches at the same origin: later opaque pixels win")
  Protected first.ByteBuffer, second.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x04.wad"

  SolidPatch(@first, 2, 2, $11)
  SolidPatch(@second, 2, 2, $22)
  WadExtrasReset()
  AddWadExtra("PATCH1", first\Data, first\Pos)
  AddWadExtra("PATCH2", second\Data, second\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX4", 0, 2, 2, 0, 2)
  TBAddPatch(@tex, 0, 0, 0)
  TBAddPatch(@tex, 0, 0, 1)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 20, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $22 And TextureImageGetPixel(@image, 1, 1) = $22), "later patch wins")
  Check(Bool(TextureImageOpaqueCount(@image) = 4), "all pixels are opaque")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@first)
  BBFree(@second)
  BBFree(@tex)
EndProcedure

Procedure TestX05LaterTransparent()
  BeginCase("X05", "Later transparent pixels leave earlier values intact")
  Protected first.ByteBuffer, second.ByteBuffer, col.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x05.wad"

  SolidPatch(@first, 2, 2, $11)
  PatchStart(@second, 2, 2, 0, 0)
  BBInit(@col, 32)
  PatchPost(@col, 0, "22")
  PatchTerm(@col)
  PatchAddColumn(@second, 0, @col)
  BBFree(@col)
  BBInit(@col, 16)
  PatchTerm(@col)
  PatchAddColumn(@second, 1, @col)
  BBFree(@col)

  WadExtrasReset()
  AddWadExtra("PATCH1", first\Data, first\Pos)
  AddWadExtra("PATCH2", second\Data, second\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX5", 0, 2, 2, 0, 2)
  TBAddPatch(@tex, 0, 0, 0)
  TBAddPatch(@tex, 0, 0, 1)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 20, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $22), "later opaque pixel overwrites")
  Check(Bool(TextureImageGetPixel(@image, 1, 0) = $11 And TextureImageGetPixel(@image, 1, 1) = $11), "transparent pixels keep earlier values")
  Check(Bool(TextureImageOpaqueCount(@image) = 4), "earlier mask remains opaque")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@first)
  BBFree(@second)
  BBFree(@tex)
EndProcedure

Procedure TestX06PartialOverlap()
  BeginCase("X06", "Partially overlapping 2x2 patches")
  Protected first.ByteBuffer, second.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x06.wad"

  SolidPatch(@first, 2, 2, $31)
  SolidPatch(@second, 2, 2, $42)
  WadExtrasReset()
  AddWadExtra("PATCH1", first\Data, first\Pos)
  AddWadExtra("PATCH2", second\Data, second\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX6", 0, 3, 3, 0, 2)
  TBAddPatch(@tex, 0, 0, 0)
  TBAddPatch(@tex, 1, 1, 1)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 20, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $31), "top-left is from the first patch")
  Check(Bool(TextureImageGetPixel(@image, 1, 1) = $42 And TextureImageGetPixel(@image, 2, 2) = $42), "overlap is won by the second patch")
  Check(Bool(TextureImageGetPixel(@image, 2, 0) = 0), "uncovered top-right remains zero")
  Check(Bool(TextureImageOpaqueCount(@image) = 7), "coverage is seven pixels")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@first)
  BBFree(@second)
  BBFree(@tex)
EndProcedure

Procedure TestX07NegativeOriginX()
  BeginCase("X07", "Negative originx clips the left edge")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x07.wad"

  SolidPatch(@patch, 2, 2, $33)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX7", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, -1, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $33 And TextureImageGetPixel(@image, 0, 1) = $33), "right source column appears at x=0")
  Check(Bool(TextureImageGetPixel(@image, 1, 0) = 0 And TextureImageIsOpaque(@image, 1, 0) = 0), "right destination stays uncovered")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX08NegativeOriginY()
  BeginCase("X08", "Negative originy clips the top edge")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x08.wad"

  SolidPatch(@patch, 2, 2, $34)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX8", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, 0, -1, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $34 And TextureImageGetPixel(@image, 1, 0) = $34), "bottom source row appears at y=0")
  Check(Bool(TextureImageGetPixel(@image, 0, 1) = 0 And TextureImageIsOpaque(@image, 0, 1) = 0), "bottom destination stays uncovered")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX09RightClip()
  BeginCase("X09", "Positive origin clips the right edge")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x09.wad"

  SolidPatch(@patch, 2, 2, $35)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX9", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, 1, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 1, 0) = $35 And TextureImageGetPixel(@image, 1, 1) = $35), "left source column appears at x=1")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = 0), "left destination is uncovered")
  Check(Bool(TextureImageGetPixel(@image, 2, 0) = -1), "out-of-range reads are rejected")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX10BottomClip()
  BeginCase("X10", "Positive origin clips the bottom edge")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x10.wad"

  SolidPatch(@patch, 2, 2, $36)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX10", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, 0, 1, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 1) = $36 And TextureImageGetPixel(@image, 1, 1) = $36), "top source row appears at y=1")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = 0), "top destination is uncovered")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX11FullyOffscreen()
  BeginCase("X11", "Patch completely outside the texture")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x11.wad"

  SolidPatch(@patch, 2, 2, $37)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX11", 0, 2, 2, 0, 2)
  TBAddPatch(@tex, -10, -10, 0)
  TBAddPatch(@tex, 50, 50, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageOpaqueCount(@image) = 0), "no pixel is opaque")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = 0), "index plane stays deterministic zero")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX12NoOverlap()
  BeginCase("X12", "Placement with no overlapping rows or columns")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x12.wad"

  SolidPatch(@patch, 1, 1, $38)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX12", 0, 4, 4, 0, 1)
  TBAddPatch(@tex, 10, 10, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageOpaqueCount(@image) = 0), "nothing becomes opaque")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = 0), "pixels remain zero")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX13InternalOffsetsIgnored()
  BeginCase("X13", "Patch internal LeftOffset/TopOffset are not applied twice")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x13.wad"

  PatchStart(@patch, 2, 2, -3, 5)
  Protected col.ByteBuffer
  BBInit(@col, 32)
  PatchPost(@col, 0, "4142")
  PatchTerm(@col)
  PatchAddColumn(@patch, 0, @col)
  BBFree(@col)
  BBInit(@col, 32)
  PatchPost(@col, 0, "4344")
  PatchTerm(@col)
  PatchAddColumn(@patch, 1, @col)
  BBFree(@col)

  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX13", 0, 4, 4, 0, 1)
  TBAddPatch(@tex, 1, 1, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 1, 1) = $41 And TextureImageGetPixel(@image, 2, 2) = $44), "placement uses only texture origins")
  Check(Bool(TextureImageIsOpaque(@image, 0, 0) = 0), "internal offset did not shift the patch to the origin")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX14NonSquareStride()
  BeginCase("X14", "Non-square texture and patch row stride")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x14.wad"

  SolidPatch(@patch, 2, 1, $51)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX14", 0, 3, 2, 0, 1)
  TBAddPatch(@tex, 1, 1, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 1, 1) = $51 And TextureImageGetPixel(@image, 2, 1) = $51), "patch occupies the second row")
  Check(Bool(TextureImageGetPixel(@image, 0, 1) = 0 And TextureImageGetPixel(@image, 1, 0) = 0), "row stride is three")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX15PaletteExtremes()
  BeginCase("X15", "Palette indices 0 and 255 are preserved")
  Protected patch.ByteBuffer, col.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x15.wad"

  PatchStart(@patch, 2, 1, 0, 0)
  BBInit(@col, 16)
  PatchPost(@col, 0, "00")
  PatchTerm(@col)
  PatchAddColumn(@patch, 0, @col)
  BBFree(@col)
  BBInit(@col, 16)
  PatchPost(@col, 0, "FF")
  PatchTerm(@col)
  PatchAddColumn(@patch, 1, @col)
  BBFree(@col)

  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX15", 0, 2, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = 0), "index 0 is preserved")
  Check(Bool(TextureImageGetPixel(@image, 1, 0) = 255), "index 255 is preserved")
  Check(Bool(TextureImageOpaqueCount(@image) = 2), "both indices are opaque")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX16OneByOneBoundary()
  BeginCase("X16", "1x1 texture and coordinate boundaries")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x16.wad"

  SolidPatch(@patch, 1, 1, $61)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX16", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $61), "the single pixel is correct")
  Check(Bool(TextureImageGetPixel(@image, 1, 0) = -1 And TextureImageGetPixel(@image, 0, 1) = -1), "boundary coordinates are rejected")
  Check(Bool(TextureImageIsOpaque(@image, 0, 0) = 1), "the single pixel is opaque")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX17AllTransparent()
  BeginCase("X17", "All-transparent patch and empty post columns")
  Protected patch.ByteBuffer, col.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x17.wad"

  PatchStart(@patch, 2, 2, 0, 0)
  BBInit(@col, 16)
  PatchTerm(@col)
  PatchAddColumn(@patch, 0, @col)
  BBFree(@col)
  BBInit(@col, 16)
  PatchTerm(@col)
  PatchAddColumn(@patch, 1, @col)
  BBFree(@col)

  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX17", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageOpaqueCount(@image) = 0), "no opaque pixels")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = 0 And TextureImageGetPixel(@image, 1, 1) = 0), "indices stay zero")
  Check(Bool(TextureImageIsOpaque(@image, 0, 0) = 0), "mask stays transparent")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX18ThreeOverlays()
  BeginCase("X18", "Three overlapping patches")
  Protected first.ByteBuffer, second.ByteBuffer, third.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x18.wad"

  SolidPatch(@first, 2, 2, $11)
  SolidPatch(@second, 2, 2, $22)
  SolidPatch(@third, 2, 2, $33)
  WadExtrasReset()
  AddWadExtra("PATCH1", first\Data, first\Pos)
  AddWadExtra("PATCH2", second\Data, second\Pos)
  AddWadExtra("PATCH3", third\Data, third\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX18", 0, 2, 2, 0, 3)
  TBAddPatch(@tex, 0, 0, 0)
  TBAddPatch(@tex, 0, 0, 1)
  TBAddPatch(@tex, 0, 0, 2)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 28, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $33 And TextureImageGetPixel(@image, 1, 1) = $33), "last opaque patch wins")
  Check(Bool(TextureImageOpaqueCount(@image) = 4), "coverage is four pixels")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@first)
  BBFree(@second)
  BBFree(@third)
  BBFree(@tex)
EndProcedure

Procedure TestX19SharedPatchLump()
  BeginCase("X19", "Same patch lump referenced by several placements")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x19.wad"

  SolidPatch(@patch, 1, 1, $44)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX19", 0, 4, 1, 0, 2)
  TBAddPatch(@tex, 0, 0, 0)
  TBAddPatch(@tex, 3, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $44 And TextureImageGetPixel(@image, 3, 0) = $44), "both placements use the shared lump")
  Check(Bool(TextureImageGetPixel(@image, 1, 0) = 0 And TextureImageGetPixel(@image, 2, 0) = 0), "gaps stay uncovered")
  Check(Bool(TextureImageOpaqueCount(@image) = 2), "exactly two opaque pixels")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX20InvalidTextureIndex()
  BeginCase("X20", "Invalid texture catalog index")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x20.wad"

  SolidPatch(@patch, 1, 1, $55)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX20", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, -1, @image) = #False), "index -1 is rejected")
  Check(Bool(TextureCompose(@catalog, 1, @image) = #False), "index == count is rejected")
  Check(Bool(image\Pixels = 0 And image\Mask = 0), "failed compose leaves empty output")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX21UnresolvedCatalog()
  BeginCase("X21", "Compose from an unresolved catalog")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x21.wad"

  SolidPatch(@patch, 1, 1, $56)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX21", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 0, @catalog, @names)), "fixture decodes without resolution")
  Check(Bool(TextureCompose(@catalog, 0, @image) = #False), "compose fails on unresolved placements")
  Check(Bool(FindString(TextureLastError(), "unresolved") > 0), "error identifies the unresolved patch")
  Check(Bool(image\Pixels = 0), "output remains empty")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX22MissingOrZeroLength()
  BeginCase("X22", "Missing and zero-length referenced patches")
  Protected tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x22.wad"

  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX22", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  WadExtrasReset()
  pnames = MakePNames(1)
  SetPName(pnames, 0, "MISSING")
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names) = #False), "missing patch fails loading/resolution")
  Check(Bool(FindString(TextureDefsLastError(), "missing") > 0), "error identifies the missing patch")
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(pnames)

  path = "x22b.wad"
  WadExtrasReset()
  AddWadExtra("ZERO", 0, 0)
  pnames = MakePNames(1)
  SetPName(pnames, 0, "ZERO")
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names) = #False), "zero-length patch fails resolution")
  Check(Bool(FindString(TextureDefsLastError(), "zero-length") > 0), "error identifies the zero-length patch")
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(pnames)
  BBFree(@tex)
EndProcedure

Procedure TestX23MalformedPatch()
  BeginCase("X23", "Malformed patch payload in a valid WAD")
  Protected badPatch.i = AllocateMemory(8)
  Protected tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x23.wad"

  Check(Bool(badPatch <> 0), "malformed-patch buffer allocated")
  If badPatch = 0
    ProcedureReturn
  EndIf
  FillMemory(badPatch, 8, 0)   ; width=0, height=0

  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX23", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  WadExtrasReset()
  AddWadExtra("BADPATCH", badPatch, 8)
  pnames = PNamesFromExtras()
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "catalog loads because the lump is nonzero")
  Check(Bool(TextureCompose(@catalog, 0, @image) = #False), "malformed patch fails composition")
  Check(Bool(FindString(TextureLastError(), "decode") > 0), "composer reports the decoder failure")
  Check(Bool(image\Pixels = 0 And image\Mask = 0), "failed compose leaves empty output")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  FreeMemory(badPatch)
  BBFree(@tex)
EndProcedure

Procedure TestX24RepeatedCompose()
  BeginCase("X24", "Repeated compose and reset")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x24.wad"
  Protected first.q, second.q

  SolidPatch(@patch, 2, 1, $71)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX24", 0, 2, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "first compose succeeds")
  first = TextureChecksum(@image)
  Check(Bool(TextureImageReset(@image)), "reset succeeds")
  Check(Bool(image\Pixels = 0 And image\Mask = 0), "reset releases both planes")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "second compose succeeds")
  second = TextureChecksum(@image)
  Check(Bool(first = second), "repeated compose is deterministic")
  Check(Bool(TextureImageReset(@image)), "second reset succeeds")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX25FailureAfterSuccess()
  BeginCase("X25", "Failed compose after an earlier success")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x25.wad"

  SolidPatch(@patch, 1, 1, $72)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX25", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "first compose succeeds")
  Check(Bool(TextureImageOpaqueCount(@image) = 1), "first output is valid")
  Check(Bool(TextureCompose(@catalog, 9, @image) = #False), "invalid index fails")
  Check(Bool(image\Pixels = 0 And image\Mask = 0 And image\PixelCount = 0), "failure clears previous output")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = -1), "cleared output is not readable")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX26PixelBudgetBoundary()
  BeginCase("X26", "Maximum allowed texture pixel budget")
  Protected tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x26.wad"

  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX26", 0, 4096, 4096, 0, 0)
  WadExtrasReset()
  pnames = MakePNames(0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 4, 1, @catalog, @names)), "4096x4096 catalog loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "maximum budget composes")
  Check(Bool(image\PixelCount = 4096 * 4096), "pixel count is exactly the cap")
  Check(Bool(TextureImageOpaqueCount(@image) = 0), "no patches means no opaque pixels")
  Check(Bool(TextureImageGetPixel(@image, 4095, 4095) = 0), "last pixel is deterministic zero")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@tex)
EndProcedure

Procedure TestX27ManyPlacements()
  BeginCase("X27", "Many placements within the safe budget")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x27.wad"
  Protected Dim originsX.l(63)
  Protected Dim originsY.l(63)
  Protected Dim pnamesIndex.l(63)
  Protected i.i

  SolidPatch(@patch, 1, 1, $77)
  For i = 0 To 63
    originsX(i) = i
    originsY(i) = 0
    pnamesIndex(i) = 0
  Next
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBAddTextureWithPlacements(@tex, "TEX27", 64, 1, @originsX(0), @originsY(0), @pnamesIndex(0), 64)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "64 placements compose")
  Check(Bool(TextureImageOpaqueCount(@image) = 64), "all 64 pixels are opaque")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $77 And TextureImageGetPixel(@image, 63, 0) = $77), "first and last placements are correct")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX28OutputIndependence()
  BeginCase("X28", "Output survives freeing input resources")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x28.wad"
  Protected value.i

  SolidPatch(@patch, 1, 1, $78)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX28", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  value = TextureImageGetPixel(@image, 0, 0)
  TextureCatalogReset(@catalog)
  PNamesReset(@names)
  WADClose()
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = value), "output remains valid after catalog/WAD release")
  Check(Bool(TextureImageOpaqueCount(@image) = 1), "mask remains valid after release")
  TextureImageReset(@image)
  DeleteFile(FixturePath(path))
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

Procedure TestX29DuplicatePatchLumps()
  BeginCase("X29", "Duplicate patch lump names use the last WAD entry")
  Protected first.ByteBuffer, second.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x29.wad"

  SolidPatch(@first, 1, 1, $11)
  SolidPatch(@second, 1, 1, $22)
  WadExtrasReset()
  AddWadExtra("DUPP", first\Data, first\Pos)
  AddWadExtra("DUPP", second\Data, second\Pos)
  pnames = MakePNames(1)
  SetPName(pnames, 0, "DUPP")
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX29", 0, 1, 1, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose succeeds")
  Check(Bool(TextureImageGetPixel(@image, 0, 0) = $22), "last duplicate patch lump is used")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@first)
  BBFree(@second)
  BBFree(@tex)
EndProcedure

Procedure TestX30ReopenAndReResolve()
  BeginCase("X30", "WAD close/reopen with explicit re-resolution")
  Protected patch.ByteBuffer, tex.ByteBuffer
  Protected pnames.i, catalog.TextureCatalog, names.PNamesTable, image.TextureImage
  Protected path.s = "x30.wad"
  Protected first.q, second.q

  SolidPatch(@patch, 2, 2, $7A)
  WadExtrasReset()
  AddWadExtra("PATCH1", patch\Data, patch\Pos)
  pnames = PNamesFromExtras()
  TBStart(@tex, 1)
  TBAddHeader(@tex, 0, "TEX30", 0, 2, 2, 0, 1)
  TBAddPatch(@tex, 0, 0, 0)
  Check(Bool(BuildLoadCatalog(path, @tex, pnames, 12, 1, @catalog, @names)), "fixture loads")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "initial compose succeeds")
  first = TextureChecksum(@image)
  Check(Bool(TextureCatalogInvalidateResolved(@catalog)), "resolved state invalidated")
  Check(Bool(TextureCompose(@catalog, 0, @image) = #False), "compose fails without resolution")
  WADClose()
  Check(Bool(WADOpen(FixturePath(path))), "WAD reopens")
  Check(Bool(TextureCatalogResolve(@catalog, @names)), "catalog re-resolves")
  Check(Bool(TextureCompose(@catalog, 0, @image)), "compose after re-resolution succeeds")
  second = TextureChecksum(@image)
  Check(Bool(first = second), "checksum is stable across reopen")
  CleanupCase(path, @catalog, @names, @image)
  FreeMemory(pnames)
  BBFree(@patch)
  BBFree(@tex)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB composite wall texture tests (M2-03)")

If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

TestX01SinglePatch()
TestX02TransparentGaps()
TestX03Index255()
TestX04LaterOpaqueWins()
TestX05LaterTransparent()
TestX06PartialOverlap()
TestX07NegativeOriginX()
TestX08NegativeOriginY()
TestX09RightClip()
TestX10BottomClip()
TestX11FullyOffscreen()
TestX12NoOverlap()
TestX13InternalOffsetsIgnored()
TestX14NonSquareStride()
TestX15PaletteExtremes()
TestX16OneByOneBoundary()
TestX17AllTransparent()
TestX18ThreeOverlays()
TestX19SharedPatchLump()
TestX20InvalidTextureIndex()
TestX21UnresolvedCatalog()
TestX22MissingOrZeroLength()
TestX23MalformedPatch()
TestX24RepeatedCompose()
TestX25FailureAfterSuccess()
TestX26PixelBudgetBoundary()
TestX27ManyPlacements()
TestX28OutputIndependence()
TestX29DuplicatePatchLumps()
TestX30ReopenAndReResolve()

CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
