; -----------------------------------------------------------------------------
; DoomPB - shared original-synthetic M3-06 wall-texture test support
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Test-support only: self-authored synthetic WAD resources, patches, PNAMES,
; TEXTURE definitions, COLORMAP tables, flats, vanilla map record buffers and a
; streamed PWAD writer. Every byte is an original synthetic value written
; little-endian at vanilla strides; no commercial IWAD bytes, game graphics,
; copyrighted payload or production output. Fixtures live under an ignored
; temporary directory beside the test executable and are cleaned.
;
; The synthetic texture layout mirrors the independent Python oracle exactly:
;   PNAMES: PATCHA, PATCHB, PATCHUP, PATCHLO;
;   patch A/B are 32x128 solid columns at caller-defined palette values;
;   PATCHUP 96x72 and PATCHLO 64x64 are short (<128) solid columns;
;   TEXTURE1: index0 NODEF (unused genuine definition), index1 TEXMID 64x128
;     composed from A at origin0 and B at origin32 (two-patch composition),
;     index2 TEXUP 96x72 from PATCHUP, index3 TEXLO 64x64 from PATCHLO;
;   COLORMAP has 32 tables, map m texel p -> (p + base + m*step) mod 256;
;   flats F_START/FLOOR1/FLOOR2/CEIL1/CEIL2/F_SKY1/F_END, 4096-byte owned.
; Maps are zero-node synthetic ten-lump levels (one subsector root) with explicit
; signed SIDEDEFS offsets, SEGS offsets and node bbox/child raw fields for tests.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLTEXTURESUPPORT_PBI, #PB_Constant) = 0

#DOOMPB_WALLTEXTURESUPPORT_PBI = 1

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Map/MapTypes.pbi"
XIncludeFile "../../src/Map/MapDecode.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"

#WallTexSupport_MaxReadBytes = 67108864
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #WallTexSupport_Separator = "\"
CompilerElse
  #WallTexSupport_Separator = "/"
CompilerEndIf

Global gWallTexFixtureDirectory.s = ""
Global gWallTexWadFile.i = 0
Global Dim gWallTexWadName.s(65536)
Global Dim gWallTexWadPosition.q(65536)
Global Dim gWallTexWadSize.q(65536)
Global gWallTexWadEntryCount.l = 0

Global Dim gWallTexMapLump.q(10)
Global Dim gWallTexMapLumpSize.q(10)

Structure WallTexSectorSpec
  FloorHeight.l
  CeilingHeight.l
  FloorName.s
  CeilingName.s
  LightLevel.l
  Special.l
  Tag.l
EndStructure

Structure WallTexLineSpec
  V1.l
  V2.l
  Flags.l
  Special.l
  Tag.l
  Side0.l
  Side1.l
EndStructure

Structure WallTexSideSpec
  TextureOffset.l
  RowOffset.l
  Sector.l
  TopName.s
  BottomName.s
  MidName.s
EndStructure

Structure WallTexVertexSpec
  X.l
  Y.l
EndStructure

Structure WallTexSegSpec
  V1.l
  V2.l
  RawAngle.l
  Line.l
  Side.l
  Offset.l
EndStructure

Structure WallTexSubSpec
  NumSegs.l
  FirstSeg.l
EndStructure

Structure WallTexNodeSpec
  OriginX.l
  OriginY.l
  DX.l
  DY.l
  Box0Top.l
  Box0Bottom.l
  Box0Left.l
  Box0Right.l
  Box1Top.l
  Box1Bottom.l
  Box1Left.l
  Box1Right.l
  Child0.l
  Child1.l
EndStructure

Structure WallTexThingSpec
  X.l
  Y.l
  Angle.l
  Type.l
  Options.l
EndStructure

Structure WallTexPatchPlacement
  PNameIndex.l
  OriginX.l
  OriginY.l
  StepDir.l
  ColorMap.l
EndStructure

Structure WallTexTextureSpec
  Name.s
  Width.l
  Height.l
  Masked.i
  PatchCount.l
  *Placements.WallTexPatchPlacement
EndStructure

; ---------------------------------------------------------------------------
; Fixture directory (ignored local test output)
; ---------------------------------------------------------------------------

Procedure.s WallTexFixturePath(FileName.s)
  ProcedureReturn gWallTexFixtureDirectory + FileName
EndProcedure

Procedure.i WallTexPrepareFixtureDirectory()
  Protected directorySize.q
  Protected directory.i

  gWallTexFixtureDirectory = GetPathPart(ProgramFilename()) + "m3-wall-texture-test-tmp" + #WallTexSupport_Separator
  directorySize = FileSize(gWallTexFixtureDirectory)
  If directorySize <= 0
    ; PureBasic CreateDirectory returns numeric 0 on success; verify usability via
    ; ExamineDirectory below instead of trusting its scalar return.
    CreateDirectory(gWallTexFixtureDirectory)
  EndIf
  directory = ExamineDirectory(#PB_Any, gWallTexFixtureDirectory, "*")
  If directory = 0
    ProcedureReturn #False
  EndIf
  FinishDirectory(directory)
  ProcedureReturn #True
EndProcedure

Procedure.i WallTexCleanupFixtureDirectory()
  Protected directory.i
  Protected entryName.s
  Protected deleted.i

  If gWallTexFixtureDirectory = ""
    ProcedureReturn #False
  EndIf
  directory = ExamineDirectory(#PB_Any, gWallTexFixtureDirectory, "*")
  If directory <> 0
    While NextDirectoryEntry(directory)
      entryName = DirectoryEntryName(directory)
      If entryName <> "." And entryName <> ".."
        DeleteFile(gWallTexFixtureDirectory + entryName)
      EndIf
    Wend
    FinishDirectory(directory)
  EndIf
  deleted = DeleteDirectory(gWallTexFixtureDirectory, "*.*")
  ProcedureReturn deleted
EndProcedure

; ---------------------------------------------------------------------------
; Little-endian memory packers
; ---------------------------------------------------------------------------

Procedure WallTexPut16(*Data.Byte, Offset.i, Value.l)
  PokeA(*Data + Offset, Value & $FF)
  PokeA(*Data + Offset + 1, (Value >> 8) & $FF)
EndProcedure

Procedure WallTexPut32(*Data.Byte, Offset.i, Value.l)
  PokeA(*Data + Offset, Value & $FF)
  PokeA(*Data + Offset + 1, (Value >> 8) & $FF)
  PokeA(*Data + Offset + 2, (Value >> 16) & $FF)
  PokeA(*Data + Offset + 3, (Value >> 24) & $FF)
EndProcedure

Procedure WallTexPutName8(*Data.Byte, Offset.i, Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      PokeA(*Data + Offset + i, Asc(Mid(Name, i + 1, 1)))
    Else
      PokeA(*Data + Offset + i, 0)
    EndIf
  Next
EndProcedure

Procedure.i WallTexNewZero(Size.q)
  Protected memory.i

  If Size <= 0
    ProcedureReturn 0
  EndIf
  memory = AllocateMemory(Size)
  If memory <> 0
    FillMemory(memory, Int(Size), 0)
  EndIf
  ProcedureReturn memory
EndProcedure

; ---------------------------------------------------------------------------
; Streamed PWAD writer
; ---------------------------------------------------------------------------

Declare WallTexPut32File(Value.l)
Declare WallTexPutNameFile(Name.s)

Procedure.i WallTexWadBegin(FileName.s)
  gWallTexWadEntryCount = 0
  gWallTexWadFile = CreateFile(#PB_Any, WallTexFixturePath(FileName))
  If gWallTexWadFile = 0
    ProcedureReturn #False
  EndIf
  WriteString(gWallTexWadFile, "PWAD", #PB_UTF8)
  WriteByte(gWallTexWadFile, 0)
  WriteByte(gWallTexWadFile, 0)
  WriteByte(gWallTexWadFile, 0)
  WriteByte(gWallTexWadFile, 0)
  WriteByte(gWallTexWadFile, 0)
  WriteByte(gWallTexWadFile, 0)
  WriteByte(gWallTexWadFile, 0)
  WriteByte(gWallTexWadFile, 0)
  ProcedureReturn #True
EndProcedure

Procedure WallTexWadAdd(Name.s, *Data.Byte, Size.q)
  If gWallTexWadEntryCount >= 65536
    ProcedureReturn
  EndIf
  gWallTexWadName(gWallTexWadEntryCount) = Name
  gWallTexWadPosition(gWallTexWadEntryCount) = Loc(gWallTexWadFile)
  gWallTexWadSize(gWallTexWadEntryCount) = Size
  If Size > 0 And *Data <> 0
    WriteData(gWallTexWadFile, *Data, Size)
  EndIf
  gWallTexWadEntryCount + 1
EndProcedure

Procedure.i WallTexWadFinish()
  Protected directoryOffset.q
  Protected i.i

  directoryOffset = Loc(gWallTexWadFile)
  FileSeek(gWallTexWadFile, 4)
  WallTexPut32File(gWallTexWadEntryCount)
  WallTexPut32File(FixedWrap32Low(directoryOffset))
  FileSeek(gWallTexWadFile, directoryOffset)
  For i = 0 To gWallTexWadEntryCount - 1
    WallTexPut32File(FixedWrap32Low(gWallTexWadPosition(i)))
    WallTexPut32File(FixedWrap32Low(gWallTexWadSize(i)))
    WallTexPutNameFile(gWallTexWadName(i))
  Next
  CloseFile(gWallTexWadFile)
  gWallTexWadFile = 0
  ProcedureReturn #True
EndProcedure

Procedure WallTexPut32File(Value.l)
  WriteByte(gWallTexWadFile, Value & $FF)
  WriteByte(gWallTexWadFile, (Value >> 8) & $FF)
  WriteByte(gWallTexWadFile, (Value >> 16) & $FF)
  WriteByte(gWallTexWadFile, (Value >> 24) & $FF)
EndProcedure

Procedure WallTexPutNameFile(Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      WriteByte(gWallTexWadFile, Asc(Mid(Name, i + 1, 1)))
    Else
      WriteByte(gWallTexWadFile, 0)
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic Doom patch builders (original column/post layout)
; ---------------------------------------------------------------------------

; One solid column in the exact Patch.pbi/Doom post layout:
; [topdelta=0][length][unused][pixels height][unused][0xFF terminator],
; repeated for every width column, with original header and absolute offsets.
Procedure.i WallTexMakeSolidPatch(Width.l, Height.l, Pixel.l, *OutSize.Long)
  Protected columnBytes.l = Height + 5
  Protected size.q = 8 + Int(Width) * 4 + Int(Width) * columnBytes
  Protected *data.Byte
  Protected x.l
  Protected y.l
  Protected cursor.q
  Protected columnOffset.q

  If Width <= 0 Or Height <= 0 Or Pixel < 0 Or Pixel > 255
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *data = WallTexNewZero(size)
  If *data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  WallTexPut16(*data, 0, Width)
  WallTexPut16(*data, 2, Height)
  WallTexPut16(*data, 4, 0)
  WallTexPut16(*data, 6, 0)
  cursor = 8 + Int(Width) * 4
  For x = 0 To Width - 1
    columnOffset = cursor + Int(x) * columnBytes
    WallTexPut32(*data, 8 + Int(x) * 4, FixedWrap32Low(columnOffset))
    PokeA(*data + columnOffset, 0)
    PokeA(*data + columnOffset + 1, Height & $FF)
    PokeA(*data + columnOffset + 2, 0)
    For y = 0 To Height - 1
      PokeA(*data + columnOffset + 3 + y, Pixel)
    Next
    PokeA(*data + columnOffset + 3 + Height, 0)
    PokeA(*data + columnOffset + 4 + Height, $FF)
  Next
  *OutSize\l = FixedWrap32Low(size)
  ProcedureReturn *data
EndProcedure

; Two-post sparse patch in the exact Patch.pbi/Doom post layout: opaque through
; HoleStart with a 0xFF-free follow-on post at HoleStart, then marker plus opaque
; through the gap end to height, then the 0xFF column terminator. Synthetic
; mask-hole tests only; no commercial imagery.
Procedure.i WallTexMakeSparsePatch(Width.l, Height.l, Pixel.l,
                                   HoleStart.l, HoleLength.l, *OutSize.Long)
  Protected *data.Byte
  Protected *column.Byte
  Protected x.l
  Protected cursor.q
  Protected size.q
  Protected totalColumnBytes.l
  Protected y.l
  Protected postStart.l
  Protected secondBase.l

  If Width <= 0 Or Height <= 0 Or Pixel < 0 Or Pixel > 255 Or
     HoleStart < 0 Or HoleLength < 0 Or HoleStart + HoleLength > Height
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  totalColumnBytes = Height + 10
  size.q = 8 + Int(Width) * 4 + Int(Width) * totalColumnBytes
  *data = WallTexNewZero(size)
  If *data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  WallTexPut16(*data, 0, Width)
  WallTexPut16(*data, 2, Height)
  WallTexPut16(*data, 4, 0)
  WallTexPut16(*data, 6, 0)
  cursor = 8 + Int(Width) * 4
  For x = 0 To Width - 1
    *column = *data + cursor + Int(x) * totalColumnBytes
    WallTexPut32(*data, 8 + Int(x) * 4,
                 FixedWrap32Low(cursor + Int(x) * totalColumnBytes))
    PokeA(*column, 0)
    PokeA(*column + 1, HoleStart & $FF)
    PokeA(*column + 2, 0)
    For y = 0 To HoleStart - 1
      PokeA(*column + 3 + y, Pixel)
    Next
    PokeA(*column + 3 + HoleStart, 0)
    postStart = HoleStart + HoleLength
    secondBase = HoleStart + 4
    PokeA(*column + secondBase, postStart & $FF)
    PokeA(*column + secondBase + 1, (Height - postStart) & $FF)
    PokeA(*column + secondBase + 2, 0)
    For y = postStart To Height - 1
      PokeA(*column + secondBase + 3 + (y - postStart), Pixel)
    Next
    PokeA(*column + secondBase + 3 + (Height - postStart), 0)
    PokeA(*column + secondBase + 4 + (Height - postStart), $FF)
  Next
  *OutSize\l = FixedWrap32Low(size)
  ProcedureReturn *data
EndProcedure

; ---------------------------------------------------------------------------
; PNAMES and TEXTURE1 builders
; ---------------------------------------------------------------------------

Procedure.i WallTexMakePNames(Joined.s, *OutSize.Long)
  Protected count.l = CountString(Joined, "|") + 1
  Protected size.q = 4 + Int(count) * 8
  Protected *data.Byte
  Protected i.i

  If count <= 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *data = WallTexNewZero(size)
  If *data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  WallTexPut32(*data, 0, count)
  For i = 0 To count - 1
    WallTexPutName8(*data, 4 + Int(i) * 8, StringField(Joined, Int(i) + 1, "|"))
  Next
  *OutSize\l = FixedWrap32Low(size)
  ProcedureReturn *data
EndProcedure

Procedure.i WallTexMakeTextureLump(*Specs.WallTexTextureSpec, Count.l, *OutSize.Long)
  Protected totalPatches.l = 0
  Protected definitionBytes.q = 0
  Protected placementsBytes.q = 0
  Protected size.q
  Protected *data.Byte
  Protected i.i
  Protected patchIndex.i
  Protected *spec.WallTexTextureSpec
  Protected *placement.WallTexPatchPlacement
  Protected definitionOffset.q
  Protected placementOffset.q

  If *Specs = 0 Or Count <= 0 Or Count > 65536
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  For i = 0 To Count - 1
    *spec = *Specs + Int(i) * SizeOf(WallTexTextureSpec)
    If *spec\Width <= 0 Or *spec\Height <= 0 Or *spec\PatchCount < 0 Or
       *spec\PatchCount > 1024 Or *spec\Placements = 0 Or Len(*spec\Name) = 0
      *OutSize\l = 0
      ProcedureReturn 0
    EndIf
    totalPatches + *spec\PatchCount
    definitionBytes = definitionBytes + 22
    placementsBytes = placementsBytes + Int(*spec\PatchCount) * 10
  Next
  If totalPatches > 65536
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  size.q = 4 + Int(Count) * 4 + definitionBytes + placementsBytes
  If size.q <= 0 Or size.q > 1000000
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *data = WallTexNewZero(size)
  If *data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  WallTexPut32(*data, 0, Count)
  definitionOffset.q = 4 + Int(Count) * 4
  For i = 0 To Count - 1
    *spec = *Specs + Int(i) * SizeOf(WallTexTextureSpec)
    WallTexPut32(*data, 4 + Int(i) * 4, FixedWrap32Low(definitionOffset))
    WallTexPutName8(*data, Int(definitionOffset), *spec\Name)
    WallTexPut32(*data, Int(definitionOffset) + 8, 0)
    WallTexPut16(*data, Int(definitionOffset) + 12, *spec\Width)
    WallTexPut16(*data, Int(definitionOffset) + 14, *spec\Height)
    WallTexPut32(*data, Int(definitionOffset) + 16, 0)
    WallTexPut16(*data, Int(definitionOffset) + 20, *spec\PatchCount)
    placementOffset.q = definitionOffset + 22
    *placement = *spec\Placements
    For patchIndex = 0 To *spec\PatchCount - 1
      WallTexPut16(*data, Int(placementOffset), *placement\OriginX)
      WallTexPut16(*data, Int(placementOffset) + 2, *placement\OriginY)
      WallTexPut16(*data, Int(placementOffset) + 4, *placement\PNameIndex)
      WallTexPut16(*data, Int(placementOffset) + 6, *placement\StepDir)
      WallTexPut16(*data, Int(placementOffset) + 8, *placement\ColorMap)
      placementOffset = placementOffset + 10
      *placement = *placement + SizeOf(WallTexPatchPlacement)
    Next
    definitionOffset = definitionOffset + 22 + Int(*spec\PatchCount) * 10
  Next
  *OutSize\l = FixedWrap32Low(size)
  ProcedureReturn *data
EndProcedure

; ---------------------------------------------------------------------------
; Palettes, COLORMAP and flats
; ---------------------------------------------------------------------------

Procedure WallTexAddPalette()
  Protected *data.Byte = WallTexNewZero(768)

  If *data <> 0
    WallTexWadAdd("PLAYPAL", *data, 768)
    FreeMemory(*data)
  EndIf
EndProcedure

; Synthetic 256-byte tables: for map m, every palette texel p maps to
; (p + BaseOffset + m*StepDelta) mod 256. 32 complete classic lighting tables.
Procedure.i WallTexMakeColormap(TableCount.l, BaseOffset.l, StepDelta.l, *OutSize.Long)
  Protected size.q = Int(TableCount) * 256
  Protected *data.Byte
  Protected mapIndex.l
  Protected texel.l
  Protected value.l

  If TableCount < 32 Or TableCount > 256 Or BaseOffset < 0 Or StepDelta < 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *data = WallTexNewZero(size)
  If *data = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  For mapIndex = 0 To TableCount - 1
    For texel = 0 To 255
      value = (texel + BaseOffset + mapIndex * StepDelta) & 255
      PokeA(*data + Int(mapIndex) * 256 + Int(texel), value)
    Next
  Next
  *OutSize\l = FixedWrap32Low(size)
  ProcedureReturn *data
EndProcedure

Procedure WallTexAddFlat(Name.s, Pixel.l)
  Protected *data.Byte = WallTexNewZero(4096)

  If *data <> 0 And Pixel >= 0 And Pixel <= 255
    FillMemory(*data, 4096, Pixel)
    WallTexWadAdd(Name, *data, 4096)
    FreeMemory(*data)
  EndIf
EndProcedure

Procedure WallTexAddF_SKY1()
  WallTexAddFlat("F_SKY1", 80)
EndProcedure

Procedure WallTexAddStandardFlatNamespace()
  WallTexWadAdd("F_START", 0, 0)
  WallTexAddFlat("FLOOR1", 45)
  WallTexAddFlat("FLOOR2", 46)
  WallTexAddFlat("CEIL1", 47)
  WallTexAddFlat("CEIL2", 48)
  WallTexAddF_SKY1()
  WallTexWadAdd("F_END", 0, 0)
EndProcedure

; ---------------------------------------------------------------------------
; Standard synthetic wall resources (matching the oracle resource layout)
; ---------------------------------------------------------------------------

; The two trailing flags are test-failure selectors only: they let a wholly
; synthetic malformed PWAD omit TEXTURE1/PNAMES or COLORMAP while keeping the
; map/patch/flat/palette resources independently present. Normal callers use
; the default #True values and get the exact oracle resource layout.
Procedure.i WallTexAddStandardWallResources(PatchAPixel.l, PatchBPixel.l,
                                           PatchUpPixel.l, PatchLoPixel.l,
                                           ColormapBase.l, ColormapStep.l,
                                           IncludeTextures.i = #True,
                                           IncludeColormap.i = #True)
  Protected *data.Byte
  Protected size.q
  Protected patchSize.l
  Protected patchBytes.Byte
  Protected Dim specs.WallTexTextureSpec(4)
  Protected Dim nodPlac.WallTexPatchPlacement(1)
  Protected Dim midPlac.WallTexPatchPlacement(2)
  Protected Dim upPlac.WallTexPatchPlacement(1)
  Protected Dim loPlac.WallTexPatchPlacement(1)

  If IncludeTextures
    *data = WallTexMakePNames("PATCHA|PATCHB|PATCHUP|PATCHLO", @size)
    If *data = 0
      ProcedureReturn #False
    EndIf
    WallTexWadAdd("PNAMES", *data, size)
    FreeMemory(*data)
  EndIf

  If IncludeTextures
    specs(0)\Name = "NODEF"
    specs(0)\Width = 8
    specs(0)\Height = 128
    specs(0)\Masked = 0
    specs(0)\PatchCount = 1
    nodPlac(0)\PNameIndex = 0
    nodPlac(0)\OriginX = 0
    nodPlac(0)\OriginY = 0
    specs(0)\Placements = @nodPlac(0)

    specs(1)\Name = "TEXMID"
    specs(1)\Width = 64
    specs(1)\Height = 128
    specs(1)\Masked = 0
    specs(1)\PatchCount = 2
    midPlac(0)\PNameIndex = 0
    midPlac(0)\OriginX = 0
    midPlac(0)\OriginY = 0
    midPlac(1)\PNameIndex = 1
    midPlac(1)\OriginX = 32
    midPlac(1)\OriginY = 0
    specs(1)\Placements = @midPlac(0)

    specs(2)\Name = "TEXUP"
    specs(2)\Width = 96
    specs(2)\Height = 72
    specs(2)\Masked = 0
    specs(2)\PatchCount = 1
    upPlac(0)\PNameIndex = 2
    upPlac(0)\OriginX = 0
    upPlac(0)\OriginY = 0
    specs(2)\Placements = @upPlac(0)

    specs(3)\Name = "TEXLO"
    specs(3)\Width = 64
    specs(3)\Height = 64
    specs(3)\Masked = 0
    specs(3)\PatchCount = 1
    loPlac(0)\PNameIndex = 3
    loPlac(0)\OriginX = 0
    loPlac(0)\OriginY = 0
    specs(3)\Placements = @loPlac(0)

    specs(4)\Name = "TEXEXTRA"
    specs(4)\Width = 64
    specs(4)\Height = 128
    specs(4)\Masked = 0
    specs(4)\PatchCount = 1
    Dim extraPlac.WallTexPatchPlacement(1)
    extraPlac(0)\PNameIndex = 0
    extraPlac(0)\OriginX = 0
    extraPlac(0)\OriginY = 0
    specs(4)\Placements = @extraPlac(0)

    *data = WallTexMakeTextureLump(@specs(0), 5, @size)
    If *data = 0
      ProcedureReturn #False
    EndIf
    WallTexWadAdd("TEXTURE1", *data, size)
    FreeMemory(*data)
  EndIf

  If IncludeColormap
    *data = WallTexMakeColormap(32, ColormapBase, ColormapStep, @size)
    If *data = 0
      ProcedureReturn #False
    EndIf
    WallTexWadAdd("COLORMAP", *data, size)
    FreeMemory(*data)
  EndIf

  *data = WallTexMakeSolidPatch(32, 128, PatchAPixel, @patchSize)
  If *data = 0
    ProcedureReturn #False
  EndIf
  WallTexWadAdd("PATCHA", *data, patchSize)
  FreeMemory(*data)

  *data = WallTexMakeSolidPatch(32, 128, PatchBPixel, @patchSize)
  If *data = 0
    ProcedureReturn #False
  EndIf
  WallTexWadAdd("PATCHB", *data, patchSize)
  FreeMemory(*data)

  *data = WallTexMakeSolidPatch(96, 72, PatchUpPixel, @patchSize)
  If *data = 0
    ProcedureReturn #False
  EndIf
  WallTexWadAdd("PATCHUP", *data, patchSize)
  FreeMemory(*data)

  *data = WallTexMakeSolidPatch(64, 64, PatchLoPixel, @patchSize)
  If *data = 0
    ProcedureReturn #False
  EndIf
  WallTexWadAdd("PATCHLO", *data, patchSize)
  FreeMemory(*data)

  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic map record buffers and WAD map sections
; ---------------------------------------------------------------------------

Procedure WallTexFreeMap()
  Protected i.i

  For i = 1 To 10
    If gWallTexMapLump(i) <> 0
      FreeMemory(gWallTexMapLump(i))
    EndIf
    gWallTexMapLump(i) = 0
    gWallTexMapLumpSize(i) = 0
  Next
EndProcedure

Procedure.i WallTexNewMapLump(Kind.i, Size.q)
  If gWallTexMapLump(Kind) <> 0
    FreeMemory(gWallTexMapLump(Kind))
  EndIf
  gWallTexMapLump(Kind) = WallTexNewZero(Size)
  gWallTexMapLumpSize(Kind) = Size
  ProcedureReturn gWallTexMapLump(Kind)
EndProcedure

; Builds ten original synthetic map lump buffers from caller-defined vanilla
; records. THINGS may be empty; nodes may be zero; REJECT minimum bytes and one
; synthetic BLOCKMAP cell listing every line. All disk fields little-endian at
; exact strides; no pointers or native structures are overlaid on disk bytes.
Procedure.i WallTexBuildMapLumps(*Sectors.WallTexSectorSpec, SectorCount.l,
                                 *Lines.WallTexLineSpec, LineCount.l,
                                 *Sides.WallTexSideSpec, SideCount.l,
                                 *Vertices.WallTexVertexSpec, VertexCount.l,
                                 *Segs.WallTexSegSpec, SegCount.l,
                                 *Subs.WallTexSubSpec, SubCount.l,
                                 *Nodes.WallTexNodeSpec, NodeCount.l,
                                 *Things.WallTexThingSpec, ThingCount.l)
  Protected i.i
  Protected *sector.WallTexSectorSpec
  Protected *line.WallTexLineSpec
  Protected *side.WallTexSideSpec
  Protected *vertex.WallTexVertexSpec
  Protected *seg.WallTexSegSpec
  Protected *sub.WallTexSubSpec
  Protected *node.WallTexNodeSpec
  Protected *thing.WallTexThingSpec
  Protected *bytes.Byte
  Protected rejectBytes.q
  Protected blockmapBytes.q
  Protected blockmapPosition.q

  If SectorCount < 1 Or SectorCount > #MAP_MaxRecords Or
     LineCount < 1 Or LineCount > #MAP_MaxRecords Or
     SideCount < 1 Or SideCount > #MAP_MaxRecords Or
     VertexCount < 1 Or VertexCount > #MAP_MaxRecords Or
     SegCount < 1 Or SegCount > #MAP_MaxRecords Or
     SubCount < 1 Or SubCount > #MAP_MaxRecords Or
     NodeCount < 0 Or NodeCount > #MAP_MaxRecords Or
     ThingCount < 0 Or ThingCount > #MAP_MaxRecords Or
     *Sectors = 0 Or *Lines = 0 Or *Sides = 0 Or *Vertices = 0 Or
     *Segs = 0 Or *Subs = 0
    ProcedureReturn #False
  EndIf
  If NodeCount > 0 And *Nodes = 0
    ProcedureReturn #False
  EndIf
  If ThingCount > 0 And *Things = 0
    ProcedureReturn #False
  EndIf

  WallTexFreeMap()

  ; THINGS.
  If ThingCount = 0
    gWallTexMapLump(1) = 0
    gWallTexMapLumpSize(1) = 0
  Else
    If WallTexNewMapLump(1, Int(ThingCount) * #MAP_ThingSize) = 0
      ProcedureReturn #False
    EndIf
    *thing = *Things
    For i = 0 To ThingCount - 1
      WallTexPut16(gWallTexMapLump(1), Int(i) * #MAP_ThingSize, *thing\X)
      WallTexPut16(gWallTexMapLump(1), Int(i) * #MAP_ThingSize + 2, *thing\Y)
      WallTexPut16(gWallTexMapLump(1), Int(i) * #MAP_ThingSize + 4, *thing\Angle)
      WallTexPut16(gWallTexMapLump(1), Int(i) * #MAP_ThingSize + 6, *thing\Type)
      WallTexPut16(gWallTexMapLump(1), Int(i) * #MAP_ThingSize + 8, *thing\Options)
      *thing = *thing + SizeOf(WallTexThingSpec)
    Next
  EndIf

  ; LINEDEFS.
  If WallTexNewMapLump(2, Int(LineCount) * #MAP_LinedefSize) = 0
    ProcedureReturn #False
  EndIf
  *line = *Lines
  For i = 0 To LineCount - 1
    WallTexPut16(gWallTexMapLump(2), Int(i) * #MAP_LinedefSize, *line\V1)
    WallTexPut16(gWallTexMapLump(2), Int(i) * #MAP_LinedefSize + 2, *line\V2)
    WallTexPut16(gWallTexMapLump(2), Int(i) * #MAP_LinedefSize + 4, *line\Flags)
    WallTexPut16(gWallTexMapLump(2), Int(i) * #MAP_LinedefSize + 6, *line\Special)
    WallTexPut16(gWallTexMapLump(2), Int(i) * #MAP_LinedefSize + 8, *line\Tag)
    WallTexPut16(gWallTexMapLump(2), Int(i) * #MAP_LinedefSize + 10, *line\Side0)
    WallTexPut16(gWallTexMapLump(2), Int(i) * #MAP_LinedefSize + 12, *line\Side1)
    *line = *line + SizeOf(WallTexLineSpec)
  Next

  ; SIDEDEFS.
  If WallTexNewMapLump(3, Int(SideCount) * #MAP_SidedefSize) = 0
    ProcedureReturn #False
  EndIf
  *side = *Sides
  For i = 0 To SideCount - 1
    WallTexPut16(gWallTexMapLump(3), Int(i) * #MAP_SidedefSize, *side\TextureOffset)
    WallTexPut16(gWallTexMapLump(3), Int(i) * #MAP_SidedefSize + 2, *side\RowOffset)
    WallTexPutName8(gWallTexMapLump(3), Int(i) * #MAP_SidedefSize + 4, *side\TopName)
    WallTexPutName8(gWallTexMapLump(3), Int(i) * #MAP_SidedefSize + 12, *side\BottomName)
    WallTexPutName8(gWallTexMapLump(3), Int(i) * #MAP_SidedefSize + 20, *side\MidName)
    WallTexPut16(gWallTexMapLump(3), Int(i) * #MAP_SidedefSize + 28, *side\Sector)
    *side = *side + SizeOf(WallTexSideSpec)
  Next

  ; VERTEXES.
  If WallTexNewMapLump(4, Int(VertexCount) * #MAP_VertexSize) = 0
    ProcedureReturn #False
  EndIf
  *vertex = *Vertices
  For i = 0 To VertexCount - 1
    WallTexPut16(gWallTexMapLump(4), Int(i) * #MAP_VertexSize, *vertex\X)
    WallTexPut16(gWallTexMapLump(4), Int(i) * #MAP_VertexSize + 2, *vertex\Y)
    *vertex = *vertex + SizeOf(WallTexVertexSpec)
  Next

  ; SEGS.
  If WallTexNewMapLump(5, Int(SegCount) * #MAP_SegSize) = 0
    ProcedureReturn #False
  EndIf
  *seg = *Segs
  For i = 0 To SegCount - 1
    WallTexPut16(gWallTexMapLump(5), Int(i) * #MAP_SegSize, *seg\V1)
    WallTexPut16(gWallTexMapLump(5), Int(i) * #MAP_SegSize + 2, *seg\V2)
    WallTexPut16(gWallTexMapLump(5), Int(i) * #MAP_SegSize + 4, *seg\RawAngle)
    WallTexPut16(gWallTexMapLump(5), Int(i) * #MAP_SegSize + 6, *seg\Line)
    WallTexPut16(gWallTexMapLump(5), Int(i) * #MAP_SegSize + 8, *seg\Side)
    WallTexPut16(gWallTexMapLump(5), Int(i) * #MAP_SegSize + 10, *seg\Offset)
    *seg = *seg + SizeOf(WallTexSegSpec)
  Next

  ; SSECTORS.
  If WallTexNewMapLump(6, Int(SubCount) * #MAP_SubsectorSize) = 0
    ProcedureReturn #False
  EndIf
  *sub = *Subs
  For i = 0 To SubCount - 1
    WallTexPut16(gWallTexMapLump(6), Int(i) * #MAP_SubsectorSize, *sub\NumSegs)
    WallTexPut16(gWallTexMapLump(6), Int(i) * #MAP_SubsectorSize + 2, *sub\FirstSeg)
    *sub = *sub + SizeOf(WallTexSubSpec)
  Next

  ; NODES.
  If NodeCount > 0
    If WallTexNewMapLump(7, Int(NodeCount) * #MAP_NodeSize) = 0
      ProcedureReturn #False
    EndIf
    *node = *Nodes
    For i = 0 To NodeCount - 1
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize, *node\OriginX)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 2, *node\OriginY)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 4, *node\DX)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 6, *node\DY)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 8, *node\Box0Top)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 10, *node\Box0Bottom)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 12, *node\Box0Left)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 14, *node\Box0Right)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 16, *node\Box1Top)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 18, *node\Box1Bottom)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 20, *node\Box1Left)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 22, *node\Box1Right)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 24, *node\Child0)
      WallTexPut16(gWallTexMapLump(7), Int(i) * #MAP_NodeSize + 26, *node\Child1)
      *node = *node + SizeOf(WallTexNodeSpec)
    Next
  Else
    gWallTexMapLump(7) = 0
    gWallTexMapLumpSize(7) = 0
  EndIf

  ; SECTORS.
  If WallTexNewMapLump(8, Int(SectorCount) * #MAP_SectorSize) = 0
    ProcedureReturn #False
  EndIf
  *sector = *Sectors
  For i = 0 To SectorCount - 1
    WallTexPut16(gWallTexMapLump(8), Int(i) * #MAP_SectorSize, *sector\FloorHeight)
    WallTexPut16(gWallTexMapLump(8), Int(i) * #MAP_SectorSize + 2, *sector\CeilingHeight)
    WallTexPutName8(gWallTexMapLump(8), Int(i) * #MAP_SectorSize + 4, *sector\FloorName)
    WallTexPutName8(gWallTexMapLump(8), Int(i) * #MAP_SectorSize + 12, *sector\CeilingName)
    WallTexPut16(gWallTexMapLump(8), Int(i) * #MAP_SectorSize + 20, *sector\LightLevel)
    WallTexPut16(gWallTexMapLump(8), Int(i) * #MAP_SectorSize + 22, *sector\Special)
    WallTexPut16(gWallTexMapLump(8), Int(i) * #MAP_SectorSize + 24, *sector\Tag)
    *sector = *sector + SizeOf(WallTexSectorSpec)
  Next

  ; REJECT minimum bytes for sectors, all zero synthetic bits.
  rejectBytes.q = Int(SectorCount) * Int(SectorCount) + 7
  rejectBytes = rejectBytes >> 3
  If rejectBytes <= 0
    rejectBytes = 1
  EndIf
  If WallTexNewMapLump(9, rejectBytes) = 0
    ProcedureReturn #False
  EndIf

  ; One-cell BLOCKMAP listing every line; header origin0/0, 1x1, offset word5.
  blockmapBytes.q = Int(LineCount) * 2 + 14
  If WallTexNewMapLump(10, blockmapBytes) = 0
    ProcedureReturn #False
  EndIf
  *bytes = gWallTexMapLump(10)
  WallTexPut16(*bytes, 0, 0)
  WallTexPut16(*bytes, 2, 0)
  WallTexPut16(*bytes, 4, 1)
  WallTexPut16(*bytes, 6, 1)
  WallTexPut16(*bytes, 8, 5)
  WallTexPut16(*bytes, 10, 0)
  blockmapPosition = 12
  For i = 0 To LineCount - 1
    WallTexPut16(*bytes, Int(blockmapPosition), Int(i))
    blockmapPosition = blockmapPosition + 2
  Next
  WallTexPut16(*bytes, Int(blockmapPosition), $FFFF)

  ProcedureReturn #True
EndProcedure

; Writes the built map section to the current WAD stream: zero-length marker,
; then the ten canonical lump names in stored order (empty THINGS accepted).
Procedure.i WallTexAddMapLumpsToWad(MarkerName.s)
  Protected i.i
  Protected LumpName.s

  WallTexWadAdd(MarkerName, 0, 0)
  For i = 1 To 10
    Select i
      Case 1
        LumpName = "THINGS"
      Case 2
        LumpName = "LINEDEFS"
      Case 3
        LumpName = "SIDEDEFS"
      Case 4
        LumpName = "VERTEXES"
      Case 5
        LumpName = "SEGS"
      Case 6
        LumpName = "SSECTORS"
      Case 7
        LumpName = "NODES"
      Case 8
        LumpName = "SECTORS"
      Case 9
        LumpName = "REJECT"
      Case 10
        LumpName = "BLOCKMAP"
    EndSelect
    WallTexWadAdd(LumpName, gWallTexMapLump(i), gWallTexMapLumpSize(i))
  Next
  ProcedureReturn #True
EndProcedure

; Decodes the synthetic map buffers through the real M2 decoders, derives/
; validates links with MapValidateLevel, then releases the buffers. A valid
; caller-owned MapLevel independent of WAD results. THINGS empty is accepted.
Procedure.i WallTexBuildMapLevel(*Level.MapLevel,
                                 *Sectors.WallTexSectorSpec, SectorCount.l,
                                 *Lines.WallTexLineSpec, LineCount.l,
                                 *Sides.WallTexSideSpec, SideCount.l,
                                 *Vertices.WallTexVertexSpec, VertexCount.l,
                                 *Segs.WallTexSegSpec, SegCount.l,
                                 *Subs.WallTexSubSpec, SubCount.l,
                                 *Nodes.WallTexNodeSpec, NodeCount.l,
                                 *Things.WallTexThingSpec, ThingCount.l)
  Protected ok.i

  If *Level = 0
    ProcedureReturn #False
  EndIf
  MapLevelReset(*Level)
  If WallTexBuildMapLumps(*Sectors, SectorCount, *Lines, LineCount,
                          *Sides, SideCount, *Vertices, VertexCount,
                          *Segs, SegCount, *Subs, SubCount, *Nodes, NodeCount,
                          *Things, ThingCount) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapThingsDecode(gWallTexMapLump(1), gWallTexMapLumpSize(1), @*Level\Things) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapLinedefsDecode(gWallTexMapLump(2), gWallTexMapLumpSize(2), @*Level\Linedefs) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapSidedefsDecode(gWallTexMapLump(3), gWallTexMapLumpSize(3), @*Level\Sidedefs) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapVertexesDecode(gWallTexMapLump(4), gWallTexMapLumpSize(4), @*Level\Vertexes) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapSegsDecode(gWallTexMapLump(5), gWallTexMapLumpSize(5), @*Level\Segs) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapSubsectorsDecode(gWallTexMapLump(6), gWallTexMapLumpSize(6), @*Level\Subsectors) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapNodesDecode(gWallTexMapLump(7), gWallTexMapLumpSize(7), @*Level\Nodes) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapSectorsDecode(gWallTexMapLump(8), gWallTexMapLumpSize(8), @*Level\Sectors) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapRejectDecode(gWallTexMapLump(9), gWallTexMapLumpSize(9), @*Level\Reject) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf
  If MapBlockmapDecode(gWallTexMapLump(10), gWallTexMapLumpSize(10), @*Level\Blockmap) = #False
    WallTexFreeMap()
    ProcedureReturn #False
  EndIf

  WallTexFreeMap()
  ok = MapValidateLevel(*Level)
  If ok = #False
    MapLevelReset(*Level)
  EndIf
  ProcedureReturn ok
EndProcedure

; ---------------------------------------------------------------------------
; Existing-WAD resource readers (production decoders, synthetic WAD only)
; -----------------------------------------------------------------------------

; Reads a named lump into a caller-owned buffer while the WAD is open. OutSize
; untouched on failure; no WAD bytes copied to disk/logs/fixtures.
Procedure.i WallTexReadLumpBuffer(Name.s, *OutSize.Long)
  Protected lumpIndex.i = 0
  Protected lumpSize.q = 0
  Protected *buffer.Byte = 0

  If *OutSize = 0
    ProcedureReturn #False
  EndIf
  lumpIndex = WADFindLump(Name)
  If lumpIndex < 0
    ProcedureReturn #False
  EndIf
  lumpSize = WADLumpSize(lumpIndex)
  If lumpSize <= 0 Or lumpSize > #WallTexSupport_MaxReadBytes
    ProcedureReturn #False
  EndIf
  *buffer = AllocateMemory(lumpSize)
  If *buffer = 0
    ProcedureReturn #False
  EndIf
  If WADReadLump(lumpIndex, *buffer, lumpSize) = #False
    FreeMemory(*buffer)
    ProcedureReturn #False
  EndIf
  *OutSize\l = FixedWrap32Low(lumpSize)
  ProcedureReturn *buffer
EndProcedure

; Decodes PNAMES + TEXTURE1/TEXTURE2 through production APIs and resolves patch
; lumps against the open WAD. Texture2 is optional but a present unreadable/empty
; lump fails. Owned buffers are released on every path. The caller must reset the
; catalog across WAD sessions.
Procedure.i WallTexDecodeWallCatalog(*Pnames.PNamesTable, *Textures.TextureCatalog)
  Protected *pnamesBytes.Byte = 0
  Protected pnamesSize.q = 0
  Protected *texture1Bytes.Byte = 0
  Protected texture1Size.q = 0
  Protected *texture2Bytes.Byte = 0
  Protected texture2Size.q = 0
  Protected hasTexture2.i = #False
  Protected ok.i = #False

  If *Pnames = 0 Or *Textures = 0
    ProcedureReturn #False
  EndIf

  *pnamesBytes = WallTexReadLumpBuffer("PNAMES", @pnamesSize)
  If *pnamesBytes = 0
    ProcedureReturn #False
  EndIf
  If PNamesDecode(*pnamesBytes, pnamesSize, *Pnames) = #False
    FreeMemory(*pnamesBytes)
    ProcedureReturn #False
  EndIf
  FreeMemory(*pnamesBytes)

  *texture1Bytes = WallTexReadLumpBuffer("TEXTURE1", @texture1Size)
  If *texture1Bytes = 0
    ProcedureReturn #False
  EndIf
  hasTexture2 = Bool(WADFindLump("TEXTURE2") >= 0)
  If hasTexture2
    *texture2Bytes = WallTexReadLumpBuffer("TEXTURE2", @texture2Size)
    If *texture2Bytes = 0
      FreeMemory(*texture1Bytes)
      ProcedureReturn #False
    EndIf
  EndIf
  If TextureCatalogDecode(*texture1Bytes, texture1Size, *texture2Bytes,
                          texture2Size, hasTexture2, *Textures) = #False
    FreeMemory(*texture1Bytes)
    If *texture2Bytes <> 0
      FreeMemory(*texture2Bytes)
    EndIf
    ProcedureReturn #False
  EndIf
  FreeMemory(*texture1Bytes)
  If *texture2Bytes <> 0
    FreeMemory(*texture2Bytes)
  EndIf

  ok = TextureCatalogResolve(*Textures, *Pnames)
  If ok = #False
    TextureCatalogReset(*Textures)
  EndIf
  ProcedureReturn ok
EndProcedure

; Original flat namespace through FlatCatalogBuild using the open WAD.
Procedure.i WallTexDecodeWallFlats(*Flats.FlatCatalog)
  If *Flats = 0
    ProcedureReturn #False
  EndIf
  ProcedureReturn FlatCatalogBuild(*Flats)
EndProcedure

; Reads/decodes COLORMAP through the existing resource decoder.
Procedure.i WallTexDecodeWallColormap(*Colormap.ColormapSet)
  Protected colormapSize.q = 0
  Protected *bytes.Byte = 0
  Protected ok.i = #False

  If *Colormap = 0
    ProcedureReturn #False
  EndIf
  *bytes = WallTexReadLumpBuffer("COLORMAP", @colormapSize)
  If *bytes = 0
    ProcedureReturn #False
  EndIf
  ok = ColormapDecode(*bytes, colormapSize, *Colormap)
  FreeMemory(*bytes)
  If ok = #False
    ColormapReset(*Colormap)
  EndIf
  ProcedureReturn ok
EndProcedure

; Builds a complete synthetic resource-only PWAD: PLAYPAL (14 palettes),
; standard flats, PNAMES/TEXTURE1/COLORMAP, four patches. No map or commercial
; bytes. The file is finished/closed for production WAD open.
Procedure.i WallTexBuildStandardResourceWad(FileName.s,
                                           PatchAPixel.l, PatchBPixel.l,
                                           PatchUpPixel.l, PatchLoPixel.l,
                                           ColormapBase.l, ColormapStep.l,
                                           IncludeFlats.i = #True)
  If WallTexWadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  If IncludeFlats
    WallTexAddStandardFlatNamespace()
  EndIf
  If WallTexAddStandardWallResources(PatchAPixel, PatchBPixel, PatchUpPixel,
                                     PatchLoPixel, ColormapBase, ColormapStep) = #False
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallTexWadFinish()
EndProcedure

; ---------------------------------------------------------------------------
; Wrapped standard synthetic map WAD sections for TI01 / TI02 layouts
; ---------------------------------------------------------------------------

; TI01 one-sided middle: one sector, vertical wall x=100 y[-64,64] raw49152,
; player type=1 at (0,0) angle0. Same geometry as the oracle TI01 scene.
Procedure.i WallTexBuildT01MapLumps()
  Protected Dim sectors.WallTexSectorSpec(1)
  Protected Dim lines.WallTexLineSpec(1)
  Protected Dim sides.WallTexSideSpec(1)
  Protected Dim verts.WallTexVertexSpec(2)
  Protected Dim segs.WallTexSegSpec(1)
  Protected Dim subs.WallTexSubSpec(1)
  Protected Dim things.WallTexThingSpec(1)

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"
  sectors(0)\LightLevel = 160
  lines(0)\V1 = 0
  lines(0)\V2 = 1
  lines(0)\Flags = 0
  lines(0)\Side0 = 0
  lines(0)\Side1 = -1
  sides(0)\TextureOffset = 5
  sides(0)\RowOffset = -3
  sides(0)\Sector = 0
  sides(0)\TopName = "-"
  sides(0)\BottomName = "-"
  sides(0)\MidName = "TEXMID"
  verts(0)\X = 100 : verts(0)\Y = 64
  verts(1)\X = 100 : verts(1)\Y = -64
  segs(0)\V1 = 0
  segs(0)\V2 = 1
  segs(0)\RawAngle = 49152
  segs(0)\Line = 0
  segs(0)\Side = 0
  segs(0)\Offset = -7
  subs(0)\NumSegs = 1
  subs(0)\FirstSeg = 0
  things(0)\X = 0
  things(0)\Y = 0
  things(0)\Angle = 0
  things(0)\Type = 1
  things(0)\Options = 0
  ProcedureReturn WallTexBuildMapLumps(@sectors(0), 1, @lines(0), 1, @sides(0), 1,
                                      @verts(0), 2, @segs(0), 1, @subs(0), 1,
                                      0, 0, @things(0), 1)
EndProcedure

; TI02 two-sided portal room: near solid vertical center, far vertical two-sided
; with upper/lower/masked middle, an extra horizontal two-sided line and a
; diagonal two-sided line. Two sectors with distinct planes/light. All segs in
; one zero-node subsector. Player at (0,0) angle0 (same oracle camera).
Procedure.i WallTexBuildT02MapLumps()
  Protected Dim sectors.WallTexSectorSpec(2)
  Protected Dim lines.WallTexLineSpec(3)
  Protected Dim sides.WallTexSideSpec(6)
  Protected Dim verts.WallTexVertexSpec(8)
  Protected Dim segs.WallTexSegSpec(3)
  Protected Dim subs.WallTexSubSpec(1)
  Protected Dim things.WallTexThingSpec(1)

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"
  sectors(0)\LightLevel = 160
  sectors(1)\FloorHeight = 32
  sectors(1)\CeilingHeight = 96
  sectors(1)\FloorName = "FLOOR2"
  sectors(1)\CeilingName = "CEIL2"
  sectors(1)\LightLevel = 96

  lines(0)\V1 = 0 : lines(0)\V2 = 1 : lines(0)\Flags = 0
  lines(0)\Side0 = 0 : lines(0)\Side1 = -1
  lines(1)\V1 = 2 : lines(1)\V2 = 3
  lines(1)\Flags = #MAP_ML_TWOSIDED + #MAP_ML_DONTPEGTOP
  lines(1)\Side0 = 1 : lines(1)\Side1 = 2
  lines(2)\V1 = 4 : lines(2)\V2 = 5
  lines(2)\Flags = #MAP_ML_TWOSIDED
  lines(2)\Side0 = 3 : lines(2)\Side1 = 4

  sides(0)\TextureOffset = 0 : sides(0)\RowOffset = 0 : sides(0)\Sector = 0
  sides(0)\TopName = "-" : sides(0)\BottomName = "-" : sides(0)\MidName = "TEXMID"
  sides(1)\TextureOffset = 11 : sides(1)\RowOffset = -8 : sides(1)\Sector = 0
  sides(1)\TopName = "TEXUP" : sides(1)\BottomName = "TEXLO" : sides(1)\MidName = "TEXMID"
  sides(2)\TextureOffset = 0 : sides(2)\RowOffset = 0 : sides(2)\Sector = 1
  sides(2)\TopName = "-" : sides(2)\BottomName = "-" : sides(2)\MidName = "-"
  sides(3)\TextureOffset = 3 : sides(3)\RowOffset = 5 : sides(3)\Sector = 0
  sides(3)\TopName = "TEXUP" : sides(3)\BottomName = "TEXLO" : sides(3)\MidName = "-"
  sides(4)\TextureOffset = 0 : sides(4)\RowOffset = 0 : sides(4)\Sector = 1
  sides(4)\TopName = "TEXLO" : sides(4)\BottomName = "TEXUP" : sides(4)\MidName = "-"

  verts(0)\X = 100 : verts(0)\Y = 64
  verts(1)\X = 100 : verts(1)\Y = -64
  verts(2)\X = 300 : verts(2)\Y = 32767
  verts(3)\X = 300 : verts(3)\Y = -32767
  verts(4)\X = 200 : verts(4)\Y = 240
  verts(5)\X = 300 : verts(5)\Y = 240
  verts(6)\X = 80 : verts(6)\Y = -200
  verts(7)\X = 160 : verts(7)\Y = -320

  segs(0)\V1 = 0 : segs(0)\V2 = 1 : segs(0)\RawAngle = 49152
  segs(0)\Line = 0 : segs(0)\Side = 0 : segs(0)\Offset = 0
  segs(1)\V1 = 2 : segs(1)\V2 = 3 : segs(1)\RawAngle = 49152
  segs(1)\Line = 1 : segs(1)\Side = 0 : segs(1)\Offset = 4
  segs(2)\V1 = 4 : segs(2)\V2 = 5 : segs(2)\RawAngle = 0
  segs(2)\Line = 2 : segs(2)\Side = 0 : segs(2)\Offset = 2

  subs(0)\NumSegs = 3 : subs(0)\FirstSeg = 0
  things(0)\X = 0 : things(0)\Y = 0 : things(0)\Angle = 0
  things(0)\Type = 1 : things(0)\Options = 0
  ; The diagonal line is deliberately not included as a visible seg in the TI02
  ; frame: its exact orientation correction is checked through map vertex data
  ; and the WallLighting helper, without inventing an unverified span.
  ProcedureReturn WallTexBuildMapLumps(@sectors(0), 2, @lines(0), 3, @sides(0), 6,
                                      @verts(0), 8, @segs(0), 3, @subs(0), 1,
                                      0, 0, @things(0), 1)
EndProcedure

CompilerEndIf
