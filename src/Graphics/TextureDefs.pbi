; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; TEXTURE1/TEXTURE2 definition decoder.
;
; On-disk layout (little-endian, no native structure overlay):
;   4-byte signed numtextures, numtextures signed 32-bit offsets,
;   each definition: 8-byte raw name, int32 masked, int16 width, int16 height,
;   int32 obsolete columndirectory, int16 patchcount, patchcount placements of
;   10 bytes (int16 originx, originy, patch, stepdir, colormap).
;
; TEXTURE2 is optional: a missing second lump is normal. Both lumps are kept in
; source order, TEXTURE1 first. Texture-name lookup is case-insensitive and
; scans from the first definition, matching R_CheckTextureNumForName(). This is
; deliberately different from WADFindLump(), which returns the last lump.
;
; Only referenced PNAMES entries are resolved, and only after an explicit
; TextureCatalogResolve() call. Resolution stores WAD lump indices, never
; pointers or payload bytes. WADClose()/WADOpen() invalidates those indices, so
; call TextureCatalogInvalidateResolved() or resolve again.
;
; Ownership:
;   - TextureDefs / TextureCatalog are caller-owned and zero-initialized once.
;   - Decode owns private metadata arrays and copies all names/placements.
;   - Reset frees every allocation, is idempotent, and leaves the object
;     reusable. A failed decode clears any previous data.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_TEXTUREDEFS_PBI, #PB_Constant) = 0

#DOOMPB_TEXTUREDEFS_PBI = 1

XIncludeFile "../Core/Endian.pbi"
XIncludeFile "PNames.pbi"
XIncludeFile "../WAD/WAD.pbi"

#TEXTURE_MaxCount              = 65536
#TEXTURE_MaxDimension          = 4096
#TEXTURE_MaxPatchesPerTexture  = 1024
#TEXTURE_MaxTotalPatches       = 65536
#TEXTURE_DefinitionHeaderSize  = 22
#TEXTURE_PatchSize             = 10

#TEXTURE_Magic                 = $54584431
#TEXTURE_CatalogMagic          = $54584331

Structure TexturePatch
  OriginX.l
  OriginY.l
  PNameIndex.l
  StepDir.l
  ColorMap.l
  ResolvedLump.l
EndStructure

Structure TextureDefs
  Magic.l
  Count.l
  SourceKind.l
  TotalPatches.l
  *Names.Byte
  *Widths.Long
  *Heights.Long
  *Masked.Long
  *ColumnDirectory.Long
  *PatchCounts.Long
  *PatchBase.Long
  *Patches.TexturePatch
EndStructure

Structure TextureCatalog
  Magic.l
  HasTexture2.l
  Set1.TextureDefs
  Set2.TextureDefs
EndStructure

Global gTextureDefs_LastError.s = ""

Procedure TextureDefsSetError(Message.s)
  gTextureDefs_LastError = Message
EndProcedure

Procedure.s TextureDefsLastError()
  ProcedureReturn gTextureDefs_LastError
EndProcedure

Procedure.i TextureReadI16LE(*Data.Byte, Offset.i)
  Protected value.i = EndianReadU16LE(*Data, Offset)

  If value >= $8000
    value = value - $10000
  EndIf
  ProcedureReturn value
EndProcedure

Procedure.i TextureDefsReset(*Defs.TextureDefs)
  If *Defs = 0
    TextureDefsSetError("Texture definition pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Defs\Magic = #TEXTURE_Magic
    If *Defs\Names <> 0
      FreeMemory(*Defs\Names)
    EndIf
    If *Defs\Widths <> 0
      FreeMemory(*Defs\Widths)
    EndIf
    If *Defs\Heights <> 0
      FreeMemory(*Defs\Heights)
    EndIf
    If *Defs\Masked <> 0
      FreeMemory(*Defs\Masked)
    EndIf
    If *Defs\ColumnDirectory <> 0
      FreeMemory(*Defs\ColumnDirectory)
    EndIf
    If *Defs\PatchCounts <> 0
      FreeMemory(*Defs\PatchCounts)
    EndIf
    If *Defs\PatchBase <> 0
      FreeMemory(*Defs\PatchBase)
    EndIf
    If *Defs\Patches <> 0
      FreeMemory(*Defs\Patches)
    EndIf
  EndIf

  *Defs\Magic = 0
  *Defs\Count = 0
  *Defs\SourceKind = 0
  *Defs\TotalPatches = 0
  *Defs\Names = 0
  *Defs\Widths = 0
  *Defs\Heights = 0
  *Defs\Masked = 0
  *Defs\ColumnDirectory = 0
  *Defs\PatchCounts = 0
  *Defs\PatchBase = 0
  *Defs\Patches = 0
  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

; Central failure path for TextureDefsDecode. Requires the local allocation
; pointers of the calling procedure.
Macro TextureDefsAbort(MessageText)
  If names <> 0
    FreeMemory(names)
    names = 0
  EndIf
  If widths <> 0
    FreeMemory(widths)
    widths = 0
  EndIf
  If heights <> 0
    FreeMemory(heights)
    heights = 0
  EndIf
  If masked <> 0
    FreeMemory(masked)
    masked = 0
  EndIf
  If columnDirectory <> 0
    FreeMemory(columnDirectory)
    columnDirectory = 0
  EndIf
  If patchCounts <> 0
    FreeMemory(patchCounts)
    patchCounts = 0
  EndIf
  If patchBase <> 0
    FreeMemory(patchBase)
    patchBase = 0
  EndIf
  If patches <> 0
    FreeMemory(patches)
    patches = 0
  EndIf
  TextureDefsSetError(MessageText)
  ProcedureReturn #False
EndMacro

; Decodes one TEXTURE1 or TEXTURE2 payload. SourceKind is left at 0; the
; catalog assigns 1/2 after a successful decode.
Procedure.i TextureDefsDecode(*Bytes.Byte, Length.q, *Result.TextureDefs)
  Protected count.l
  Protected directoryEnd.q
  Protected textureIndex.i
  Protected definitionOffset.q
  Protected requiredBytes.q
  Protected patchCount.i
  Protected totalPatches.q = 0
  Protected width.i
  Protected height.i
  Protected names.i = 0
  Protected widths.i = 0
  Protected heights.i = 0
  Protected masked.i = 0
  Protected columnDirectory.i = 0
  Protected patchCounts.i = 0
  Protected patchBase.i = 0
  Protected patches.i = 0
  Protected patchIndex.i
  Protected *patchPointer.TexturePatch
  Protected patchOffset.q

  If *Result = 0
    TextureDefsSetError("Texture definition result pointer is null.")
    ProcedureReturn #False
  EndIf

  TextureDefsReset(*Result)

  If Length < 4
    TextureDefsSetError("Texture lump is too short for its 4-byte count.")
    ProcedureReturn #False
  EndIf
  If *Bytes = 0
    TextureDefsSetError("Texture lump data pointer is null.")
    ProcedureReturn #False
  EndIf

  count = EndianReadI32LE(*Bytes, 0)
  If count < 0
    TextureDefsSetError("Texture count is negative: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If count > #TEXTURE_MaxCount
    TextureDefsSetError("Texture count exceeds the safety cap: " + Str(count) + " (limit " + Str(#TEXTURE_MaxCount) + ").")
    ProcedureReturn #False
  EndIf

  directoryEnd = Int(4) + Int(count) * 4
  If directoryEnd > Length
    TextureDefsSetError("Texture offset directory is truncated: needs " + Str(directoryEnd) + " bytes, input has " + Str(Length) + ".")
    ProcedureReturn #False
  EndIf

  ; First pass: validate every definition and compute the total patch count
  ; before allocating anything.
  For textureIndex = 0 To count - 1
    definitionOffset = EndianReadI32LE(*Bytes, 4 + textureIndex * 4)
    If definitionOffset < directoryEnd
      TextureDefsAbort("Texture " + Str(textureIndex) + " offset points inside the directory table.")
    EndIf
    If definitionOffset + #TEXTURE_DefinitionHeaderSize > Length
      TextureDefsAbort("Texture " + Str(textureIndex) + " definition header is truncated.")
    EndIf

    width = TextureReadI16LE(*Bytes, definitionOffset + 12)
    height = TextureReadI16LE(*Bytes, definitionOffset + 14)
    If width <= 0 Or width > #TEXTURE_MaxDimension
      TextureDefsAbort("Texture " + Str(textureIndex) + " width is invalid: " + Str(width) + ".")
    EndIf
    If height <= 0 Or height > #TEXTURE_MaxDimension
      TextureDefsAbort("Texture " + Str(textureIndex) + " height is invalid: " + Str(height) + ".")
    EndIf

    patchCount = TextureReadI16LE(*Bytes, definitionOffset + 20)
    If patchCount < 0
      TextureDefsAbort("Texture " + Str(textureIndex) + " patch count is negative: " + Str(patchCount) + ".")
    EndIf
    If patchCount > #TEXTURE_MaxPatchesPerTexture
      TextureDefsAbort("Texture " + Str(textureIndex) + " patch count is too large: " + Str(patchCount) + ".")
    EndIf

    requiredBytes = #TEXTURE_DefinitionHeaderSize + Int(patchCount) * #TEXTURE_PatchSize
    If definitionOffset + requiredBytes > Length
      TextureDefsAbort("Texture " + Str(textureIndex) + " definition is truncated.")
    EndIf

    totalPatches = totalPatches + patchCount
    If totalPatches > #TEXTURE_MaxTotalPatches
      TextureDefsAbort("Total texture patch count exceeds the safety cap: " + Str(totalPatches) + ".")
    EndIf
  Next

  If count > 0
    names = AllocateMemory(Int(count) * 8)
    widths = AllocateMemory(Int(count) * 4)
    heights = AllocateMemory(Int(count) * 4)
    masked = AllocateMemory(Int(count) * 4)
    columnDirectory = AllocateMemory(Int(count) * 4)
    patchCounts = AllocateMemory(Int(count) * 4)
    patchBase = AllocateMemory((Int(count) + 1) * 4)
    If names = 0 Or widths = 0 Or heights = 0 Or masked = 0 Or columnDirectory = 0 Or patchCounts = 0 Or patchBase = 0
      TextureDefsAbort("Out of memory while allocating texture metadata.")
    EndIf
  EndIf
  If totalPatches > 0
    patches = AllocateMemory(totalPatches * SizeOf(TexturePatch))
    If patches = 0
      TextureDefsAbort("Out of memory while allocating texture patch placements.")
    EndIf
  EndIf

  ; Second pass: copy the validated metadata.
  If patchBase <> 0
    PokeL(patchBase, 0)
  EndIf
  For textureIndex = 0 To count - 1
    definitionOffset = EndianReadI32LE(*Bytes, 4 + textureIndex * 4)
    CopyMemory(*Bytes + definitionOffset, names + textureIndex * 8, 8)
    PokeL(widths + textureIndex * 4, TextureReadI16LE(*Bytes, definitionOffset + 12))
    PokeL(heights + textureIndex * 4, TextureReadI16LE(*Bytes, definitionOffset + 14))
    PokeL(masked + textureIndex * 4, EndianReadI32LE(*Bytes, definitionOffset + 8))
    PokeL(columnDirectory + textureIndex * 4, EndianReadI32LE(*Bytes, definitionOffset + 16))
    patchCount = TextureReadI16LE(*Bytes, definitionOffset + 20)
    PokeL(patchCounts + textureIndex * 4, patchCount)
    PokeL(patchBase + (textureIndex + 1) * 4, PeekL(patchBase + textureIndex * 4) + patchCount)

    patchOffset = definitionOffset + #TEXTURE_DefinitionHeaderSize
    For patchIndex = 0 To patchCount - 1
      *patchPointer = patches + (PeekL(patchBase + textureIndex * 4) + patchIndex) * SizeOf(TexturePatch)
      *patchPointer\OriginX = TextureReadI16LE(*Bytes, patchOffset)
      *patchPointer\OriginY = TextureReadI16LE(*Bytes, patchOffset + 2)
      *patchPointer\PNameIndex = TextureReadI16LE(*Bytes, patchOffset + 4)
      *patchPointer\StepDir = TextureReadI16LE(*Bytes, patchOffset + 6)
      *patchPointer\ColorMap = TextureReadI16LE(*Bytes, patchOffset + 8)
      *patchPointer\ResolvedLump = -1
      patchOffset + #TEXTURE_PatchSize
    Next
  Next

  *Result\Magic = #TEXTURE_Magic
  *Result\Count = count
  *Result\SourceKind = 0
  *Result\TotalPatches = totalPatches
  *Result\Names = names
  *Result\Widths = widths
  *Result\Heights = heights
  *Result\Masked = masked
  *Result\ColumnDirectory = columnDirectory
  *Result\PatchCounts = patchCounts
  *Result\PatchBase = patchBase
  *Result\Patches = patches
  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i TextureDefsCount(*Defs.TextureDefs)
  If *Defs = 0 Or *Defs\Magic <> #TEXTURE_Magic
    TextureDefsSetError("Texture definition set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Defs\Count
EndProcedure

Procedure.i TextureDefsGetNameByte(*Defs.TextureDefs, TextureIndex.i, ByteIndex.i)
  If *Defs = 0 Or *Defs\Magic <> #TEXTURE_Magic
    TextureDefsSetError("Texture definition set is not initialized.")
    ProcedureReturn -1
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Defs\Count
    TextureDefsSetError("Texture index out of range: " + Str(TextureIndex) + " (count " + Str(*Defs\Count) + ").")
    ProcedureReturn -1
  EndIf
  If ByteIndex < 0 Or ByteIndex >= 8
    TextureDefsSetError("Texture name byte offset out of range: " + Str(ByteIndex) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Defs\Names + Int(TextureIndex) * 8 + Int(ByteIndex))
EndProcedure

Procedure.s TextureDefsDisplayName(*Defs.TextureDefs, TextureIndex.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  If *Defs = 0 Or *Defs\Magic <> #TEXTURE_Magic
    TextureDefsSetError("Texture definition set is not initialized.")
    ProcedureReturn ""
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Defs\Count
    TextureDefsSetError("Texture index out of range: " + Str(TextureIndex) + " (count " + Str(*Defs\Count) + ").")
    ProcedureReturn ""
  EndIf

  For i = 0 To 7
    value = PeekA(*Defs\Names + Int(TextureIndex) * 8 + i)
    If value = 0
      Break
    EndIf
    If value >= 32 And value <= 126
      result + Chr(value)
    Else
      result + "."
    EndIf
  Next
  gTextureDefs_LastError = ""
  ProcedureReturn result
EndProcedure

; Optional output pointers may be null when the caller does not need a field.
Procedure.i TextureDefsGetProperties(*Defs.TextureDefs, TextureIndex.i, *Width.Long, *Height.Long, *Masked.Long, *ColumnDirectory.Long, *PatchCount.Long)
  Protected base.i

  If *Defs = 0 Or *Defs\Magic <> #TEXTURE_Magic
    TextureDefsSetError("Texture definition set is not initialized.")
    ProcedureReturn #False
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Defs\Count
    TextureDefsSetError("Texture index out of range: " + Str(TextureIndex) + " (count " + Str(*Defs\Count) + ").")
    ProcedureReturn #False
  EndIf

  base = Int(TextureIndex) * 4
  If *Width <> 0
    PokeL(*Width, PeekL(*Defs\Widths + base))
  EndIf
  If *Height <> 0
    PokeL(*Height, PeekL(*Defs\Heights + base))
  EndIf
  If *Masked <> 0
    PokeL(*Masked, PeekL(*Defs\Masked + base))
  EndIf
  If *ColumnDirectory <> 0
    PokeL(*ColumnDirectory, PeekL(*Defs\ColumnDirectory + base))
  EndIf
  If *PatchCount <> 0
    PokeL(*PatchCount, PeekL(*Defs\PatchCounts + base))
  EndIf
  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i TextureDefsGetPatch(*Defs.TextureDefs, TextureIndex.i, PatchIndex.i, *OriginX.Long, *OriginY.Long, *PNameIndex.Long, *StepDir.Long, *ColorMap.Long)
  Protected patchCount.i
  Protected *patchPointer.TexturePatch

  If *Defs = 0 Or *Defs\Magic <> #TEXTURE_Magic
    TextureDefsSetError("Texture definition set is not initialized.")
    ProcedureReturn #False
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Defs\Count
    TextureDefsSetError("Texture index out of range: " + Str(TextureIndex) + " (count " + Str(*Defs\Count) + ").")
    ProcedureReturn #False
  EndIf
  patchCount = PeekL(*Defs\PatchCounts + Int(TextureIndex) * 4)
  If PatchIndex < 0 Or PatchIndex >= patchCount
    TextureDefsSetError("Patch index out of range: " + Str(PatchIndex) + " (count " + Str(patchCount) + ").")
    ProcedureReturn #False
  EndIf

  *patchPointer = *Defs\Patches + (PeekL(*Defs\PatchBase + Int(TextureIndex) * 4) + PatchIndex) * SizeOf(TexturePatch)
  If *OriginX <> 0
    PokeL(*OriginX, *patchPointer\OriginX)
  EndIf
  If *OriginY <> 0
    PokeL(*OriginY, *patchPointer\OriginY)
  EndIf
  If *PNameIndex <> 0
    PokeL(*PNameIndex, *patchPointer\PNameIndex)
  EndIf
  If *StepDir <> 0
    PokeL(*StepDir, *patchPointer\StepDir)
  EndIf
  If *ColorMap <> 0
    PokeL(*ColorMap, *patchPointer\ColorMap)
  EndIf
  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Combined TEXTURE1 + optional TEXTURE2 catalog
; ---------------------------------------------------------------------------

Procedure.i TextureCatalogReset(*Catalog.TextureCatalog)
  If *Catalog = 0
    TextureDefsSetError("Texture catalog pointer is null.")
    ProcedureReturn #False
  EndIf

  TextureDefsReset(@*Catalog\Set1)
  TextureDefsReset(@*Catalog\Set2)
  *Catalog\Magic = 0
  *Catalog\HasTexture2 = 0
  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

; Decodes TEXTURE1 and, when HasTexture2 is nonzero, TEXTURE2. Any failure
; leaves the whole catalog empty.
Procedure.i TextureCatalogDecode(*Texture1Bytes.Byte, Texture1Length.q, *Texture2Bytes.Byte, Texture2Length.q, HasTexture2.i, *Result.TextureCatalog)
  Protected failureText.s

  If *Result = 0
    TextureDefsSetError("Texture catalog result pointer is null.")
    ProcedureReturn #False
  EndIf

  TextureCatalogReset(*Result)

  If TextureDefsDecode(*Texture1Bytes, Texture1Length, @*Result\Set1) = #False
    failureText = TextureDefsLastError()
    TextureCatalogReset(*Result)
    TextureDefsSetError("TEXTURE1: " + failureText)
    ProcedureReturn #False
  EndIf
  *Result\Set1\SourceKind = 1

  If HasTexture2
    If TextureDefsDecode(*Texture2Bytes, Texture2Length, @*Result\Set2) = #False
      failureText = TextureDefsLastError()
      TextureCatalogReset(*Result)
      TextureDefsSetError("TEXTURE2: " + failureText)
      ProcedureReturn #False
    EndIf
    *Result\Set2\SourceKind = 2
    *Result\HasTexture2 = 1
  EndIf

  *Result\Magic = #TEXTURE_CatalogMagic
  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i TextureCatalogCount(*Catalog.TextureCatalog)
  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Catalog\Set1\Count + *Catalog\Set2\Count
EndProcedure

Procedure.i TextureCatalogGetNameByte(*Catalog.TextureCatalog, TextureIndex.i, ByteIndex.i)
  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn -1
  EndIf
  If TextureIndex < *Catalog\Set1\Count
    ProcedureReturn TextureDefsGetNameByte(@*Catalog\Set1, TextureIndex, ByteIndex)
  EndIf
  ProcedureReturn TextureDefsGetNameByte(@*Catalog\Set2, TextureIndex - *Catalog\Set1\Count, ByteIndex)
EndProcedure

Procedure.s TextureCatalogDisplayName(*Catalog.TextureCatalog, TextureIndex.i)
  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn ""
  EndIf
  If TextureIndex < *Catalog\Set1\Count
    ProcedureReturn TextureDefsDisplayName(@*Catalog\Set1, TextureIndex)
  EndIf
  ProcedureReturn TextureDefsDisplayName(@*Catalog\Set2, TextureIndex - *Catalog\Set1\Count)
EndProcedure

Procedure.i TextureCatalogGetProperties(*Catalog.TextureCatalog, TextureIndex.i, *Width.Long, *Height.Long, *Masked.Long, *ColumnDirectory.Long, *PatchCount.Long, *SourceKind.Long)
  Protected result.i

  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Catalog\Set1\Count + *Catalog\Set2\Count
    TextureDefsSetError("Texture index out of range: " + Str(TextureIndex) + ".")
    ProcedureReturn #False
  EndIf

  If TextureIndex < *Catalog\Set1\Count
    result = TextureDefsGetProperties(@*Catalog\Set1, TextureIndex, *Width, *Height, *Masked, *ColumnDirectory, *PatchCount)
    If result And *SourceKind <> 0
      PokeL(*SourceKind, 1)
    EndIf
  Else
    result = TextureDefsGetProperties(@*Catalog\Set2, TextureIndex - *Catalog\Set1\Count, *Width, *Height, *Masked, *ColumnDirectory, *PatchCount)
    If result And *SourceKind <> 0
      PokeL(*SourceKind, 2)
    EndIf
  EndIf
  ProcedureReturn result
EndProcedure

Procedure.i TextureCatalogGetPatch(*Catalog.TextureCatalog, TextureIndex.i, PatchIndex.i, *OriginX.Long, *OriginY.Long, *PNameIndex.Long, *StepDir.Long, *ColorMap.Long)
  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Catalog\Set1\Count + *Catalog\Set2\Count
    TextureDefsSetError("Texture index out of range: " + Str(TextureIndex) + ".")
    ProcedureReturn #False
  EndIf
  If TextureIndex < *Catalog\Set1\Count
    ProcedureReturn TextureDefsGetPatch(@*Catalog\Set1, TextureIndex, PatchIndex, *OriginX, *OriginY, *PNameIndex, *StepDir, *ColorMap)
  EndIf
  ProcedureReturn TextureDefsGetPatch(@*Catalog\Set2, TextureIndex - *Catalog\Set1\Count, PatchIndex, *OriginX, *OriginY, *PNameIndex, *StepDir, *ColorMap)
EndProcedure

; First-match, case-insensitive, eight-byte texture lookup, matching
; R_CheckTextureNumForName(). The "-" no-texture marker is not special here.
Procedure.i TextureCatalogFindName(*Catalog.TextureCatalog, Name.s)
  Protected Dim query.a(7)
  Protected nameLength.i
  Protected i.i
  Protected value.i
  Protected textureIndex.i
  Protected stored.i
  Protected matched.i

  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn -1
  EndIf
  If Name = ""
    TextureDefsSetError("Texture name is empty.")
    ProcedureReturn -1
  EndIf

  nameLength = Len(Name)
  If nameLength > 8
    nameLength = 8
  EndIf
  For i = 0 To Len(Name) - 1
    value = Asc(Mid(Name, i + 1, 1))
    If value < 32 Or value > 126
      TextureDefsSetError("Texture query contains an unsupported character.")
      ProcedureReturn -1
    EndIf
    If value >= 97 And value <= 122
      value = value - 32
    EndIf
    If i < 8
      query(i) = value
    EndIf
  Next
  For i = nameLength To 7
    query(i) = 0
  Next

  For textureIndex = 0 To *Catalog\Set1\Count + *Catalog\Set2\Count - 1
    matched = #True
    For i = 0 To 7
      If textureIndex < *Catalog\Set1\Count
        stored = PeekA(*Catalog\Set1\Names + textureIndex * 8 + i)
      Else
        stored = PeekA(*Catalog\Set2\Names + (textureIndex - *Catalog\Set1\Count) * 8 + i)
      EndIf
      If stored >= 97 And stored <= 122
        stored = stored - 32
      EndIf
      If stored <> query(i)
        matched = #False
        Break
      EndIf
    Next
    If matched
      gTextureDefs_LastError = ""
      ProcedureReturn textureIndex
    EndIf
  Next

  TextureDefsSetError("Texture not found: " + Name)
  ProcedureReturn -1
EndProcedure

Procedure TextureDefsClearResolved(*Defs.TextureDefs)
  Protected textureIndex.i
  Protected patchIndex.i
  Protected patchCount.i
  Protected *patchPointer.TexturePatch

  If *Defs\Count <= 0
    ProcedureReturn
  EndIf
  For textureIndex = 0 To *Defs\Count - 1
    patchCount = PeekL(*Defs\PatchCounts + textureIndex * 4)
    For patchIndex = 0 To patchCount - 1
      *patchPointer = *Defs\Patches + (PeekL(*Defs\PatchBase + textureIndex * 4) + patchIndex) * SizeOf(TexturePatch)
      *patchPointer\ResolvedLump = -1
    Next
  Next
EndProcedure

; Resolves only referenced PNAMES entries. On failure every resolved index in
; the set is cleared, so partial results are never exposed.
Procedure.i TextureDefsResolveInternal(*Defs.TextureDefs, *PNames.PNamesTable, SourceLabel.s)
  Protected Dim queryBytes.a(7)
  Protected textureIndex.i
  Protected patchIndex.i
  Protected patchCount.i
  Protected *patchPointer.TexturePatch
  Protected pNameIndex.i
  Protected pNamesCount.i
  Protected byteIndex.i
  Protected value.i
  Protected length.i
  Protected sawNul.i
  Protected query.s
  Protected lump.i
  Protected failureText.s

  TextureDefsClearResolved(*Defs)

  If *PNames = 0 Or *PNames\Magic <> #PNAMES_Magic
    TextureDefsSetError("PNAMES table is not initialized.")
    ProcedureReturn #False
  EndIf
  pNamesCount = *PNames\Count

  For textureIndex = 0 To *Defs\Count - 1
    patchCount = PeekL(*Defs\PatchCounts + textureIndex * 4)
    For patchIndex = 0 To patchCount - 1
      *patchPointer = *Defs\Patches + (PeekL(*Defs\PatchBase + textureIndex * 4) + patchIndex) * SizeOf(TexturePatch)
      pNameIndex = *patchPointer\PNameIndex
      If pNameIndex < 0 Or pNameIndex >= pNamesCount
        TextureDefsClearResolved(*Defs)
        TextureDefsSetError(SourceLabel + " texture " + Str(textureIndex) + " patch " + Str(patchIndex) + " references invalid PNAMES index " + Str(pNameIndex) + " (count " + Str(pNamesCount) + ").")
        ProcedureReturn #False
      EndIf

      length = 0
      sawNul = #False
      For byteIndex = 0 To 7
        value = PNamesRawNameByte(*PNames, pNameIndex, byteIndex)
        If value < 0
          failureText = PNamesLastError()
          TextureDefsClearResolved(*Defs)
          TextureDefsSetError(SourceLabel + " texture " + Str(textureIndex) + " patch " + Str(patchIndex) + ": " + failureText)
          ProcedureReturn #False
        EndIf
        If sawNul
          If value <> 0
            TextureDefsClearResolved(*Defs)
            TextureDefsSetError(SourceLabel + " texture " + Str(textureIndex) + " patch " + Str(patchIndex) + " references a noncanonical PNAMES name (embedded NUL).")
            ProcedureReturn #False
          EndIf
        Else
          If value = 0
            sawNul = #True
          ElseIf value < 32 Or value > 126
            TextureDefsClearResolved(*Defs)
            TextureDefsSetError(SourceLabel + " texture " + Str(textureIndex) + " patch " + Str(patchIndex) + " references a noncanonical PNAMES name (nonprintable byte).")
            ProcedureReturn #False
          Else
            queryBytes(length) = value
            length + 1
          EndIf
        EndIf
      Next

      If length = 0
        TextureDefsClearResolved(*Defs)
        TextureDefsSetError(SourceLabel + " texture " + Str(textureIndex) + " patch " + Str(patchIndex) + " references an empty PNAMES name.")
        ProcedureReturn #False
      EndIf

      query = ""
      For byteIndex = 0 To length - 1
        query + Chr(queryBytes(byteIndex))
      Next
      lump = WADFindLump(query)
      If lump < 0
        failureText = WADLastError()
        TextureDefsClearResolved(*Defs)
        TextureDefsSetError(SourceLabel + " texture " + Str(textureIndex) + " patch " + Str(patchIndex) + " patch name is missing from the WAD: " + failureText)
        ProcedureReturn #False
      EndIf
      If WADLumpSize(lump) <= 0
        TextureDefsClearResolved(*Defs)
        TextureDefsSetError(SourceLabel + " texture " + Str(textureIndex) + " patch " + Str(patchIndex) + " resolved to a zero-length lump.")
        ProcedureReturn #False
      EndIf
      *patchPointer\ResolvedLump = lump
    Next
  Next

  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

; Resolves all referenced patches in TEXTURE1, then TEXTURE2, atomically.
Procedure.i TextureCatalogResolve(*Catalog.TextureCatalog, *PNames.PNamesTable)
  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If *PNames = 0 Or *PNames\Magic <> #PNAMES_Magic
    TextureDefsSetError("PNAMES table is not initialized.")
    ProcedureReturn #False
  EndIf

  TextureDefsClearResolved(@*Catalog\Set1)
  TextureDefsClearResolved(@*Catalog\Set2)
  If TextureDefsResolveInternal(@*Catalog\Set1, *PNames, "TEXTURE1") = #False
    TextureDefsClearResolved(@*Catalog\Set2)
    ProcedureReturn #False
  EndIf
  If *Catalog\HasTexture2
    If TextureDefsResolveInternal(@*Catalog\Set2, *PNames, "TEXTURE2") = #False
      TextureDefsClearResolved(@*Catalog\Set1)
      ProcedureReturn #False
    EndIf
  EndIf

  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i TextureCatalogInvalidateResolved(*Catalog.TextureCatalog)
  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  TextureDefsClearResolved(@*Catalog\Set1)
  TextureDefsClearResolved(@*Catalog\Set2)
  gTextureDefs_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i TextureCatalogGetResolvedPatchLump(*Catalog.TextureCatalog, TextureIndex.i, PatchIndex.i)
  Protected patchCount.i
  Protected *patchPointer.TexturePatch

  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureDefsSetError("Texture catalog is not initialized.")
    ProcedureReturn -1
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Catalog\Set1\Count + *Catalog\Set2\Count
    TextureDefsSetError("Texture index out of range: " + Str(TextureIndex) + ".")
    ProcedureReturn -1
  EndIf
  If TextureIndex < *Catalog\Set1\Count
    patchCount = PeekL(*Catalog\Set1\PatchCounts + TextureIndex * 4)
    If PatchIndex < 0 Or PatchIndex >= patchCount
      TextureDefsSetError("Patch index out of range: " + Str(PatchIndex) + ".")
      ProcedureReturn -1
    EndIf
    *patchPointer = *Catalog\Set1\Patches + (PeekL(*Catalog\Set1\PatchBase + TextureIndex * 4) + PatchIndex) * SizeOf(TexturePatch)
  Else
    TextureIndex = TextureIndex - *Catalog\Set1\Count
    patchCount = PeekL(*Catalog\Set2\PatchCounts + TextureIndex * 4)
    If PatchIndex < 0 Or PatchIndex >= patchCount
      TextureDefsSetError("Patch index out of range: " + Str(PatchIndex) + ".")
      ProcedureReturn -1
    EndIf
    *patchPointer = *Catalog\Set2\Patches + (PeekL(*Catalog\Set2\PatchBase + TextureIndex * 4) + PatchIndex) * SizeOf(TexturePatch)
  EndIf
  ProcedureReturn *patchPointer\ResolvedLump
EndProcedure

CompilerEndIf
