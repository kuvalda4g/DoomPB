; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Sprite namespace catalog and strict sprite frame/rotation assembler.
;
; The catalog covers the interior of S_START..S_END (markers excluded) and keeps
; each entry's raw eight-byte name, absolute WAD directory index and size in
; physical order. It never resolves entries through WADFindLump, so duplicate
; names elsewhere cannot redirect a catalog slot.
;
; Vanilla R_InitSpriteDefs / R_InstallSpriteLump semantics are reproduced for a
; requested four-byte sprite ID:
;   - byte 4 = frame (0..28, i.e. 'A'..'A'+28)
;   - byte 5 = rotation ('0'..'8'); rotation 0 supplies all eight views
;   - a nonzero byte 6 starts a second frame/rotation pair stored in bytes 6/7;
;     that pair uses the same WAD lump with horizontal flip = 1
;   - explicit rotations require all eight slots; a rot=0 lump conflicts with
;     explicit rotations; duplicate slots are rejected
;   - frames 0..highest must be contiguous.
;
; Frame sets store absolute WAD indices and flip bytes, never payload pointers.
; Catalog indices are valid for the current WAD session; rebuild after reopen.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_SPRITE_PBI, #PB_Constant) = 0

#DOOMPB_SPRITE_PBI = 1

XIncludeFile "../Core/Endian.pbi"
XIncludeFile "../WAD/WAD.pbi"

#SPRITE_MaxCount        = 65536
#SPRITE_MaxFrame        = 28
#SPRITE_RotationCount   = 8

#SPRITE_CatalogMagic    = $53504331
#SPRITE_FrameSetMagic   = $53504631

Structure SpriteCatalog
  Magic.l
  Count.l
  FirstLump.l
  LastLump.l
  *Names.Byte
  *WadIndices.Long
  *Sizes.Long
EndStructure

Structure SpriteFrameSet
  Magic.l
  FrameCount.l
  *WadIndices.Long
  *Flips.Byte
EndStructure

Global gSprite_LastError.s = ""

Procedure SpriteSetError(Message.s)
  gSprite_LastError = Message
EndProcedure

Procedure.s SpriteLastError()
  ProcedureReturn gSprite_LastError
EndProcedure

Procedure.i SpriteReadI16LE(*Data.Byte, Offset.i)
  Protected value.i = EndianReadU16LE(*Data, Offset)

  If value >= $8000
    value = value - $10000
  EndIf
  ProcedureReturn value
EndProcedure

Procedure.i SpriteCatalogReset(*Catalog.SpriteCatalog)
  If *Catalog = 0
    SpriteSetError("Sprite catalog pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Catalog\Magic = #SPRITE_CatalogMagic
    If *Catalog\Names <> 0
      FreeMemory(*Catalog\Names)
    EndIf
    If *Catalog\WadIndices <> 0
      FreeMemory(*Catalog\WadIndices)
    EndIf
    If *Catalog\Sizes <> 0
      FreeMemory(*Catalog\Sizes)
    EndIf
  EndIf

  *Catalog\Magic = 0
  *Catalog\Count = 0
  *Catalog\FirstLump = 0
  *Catalog\LastLump = 0
  *Catalog\Names = 0
  *Catalog\WadIndices = 0
  *Catalog\Sizes = 0
  gSprite_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i SpriteFrameSetReset(*FrameSet.SpriteFrameSet)
  If *FrameSet = 0
    SpriteSetError("Sprite frame-set pointer is null.")
    ProcedureReturn #False
  EndIf

  If *FrameSet\Magic = #SPRITE_FrameSetMagic
    If *FrameSet\WadIndices <> 0
      FreeMemory(*FrameSet\WadIndices)
    EndIf
    If *FrameSet\Flips <> 0
      FreeMemory(*FrameSet\Flips)
    EndIf
  EndIf

  *FrameSet\Magic = 0
  *FrameSet\FrameCount = 0
  *FrameSet\WadIndices = 0
  *FrameSet\Flips = 0
  gSprite_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i SpriteCatalogBuild(*Catalog.SpriteCatalog)
  Protected startIndex.i
  Protected endIndex.i
  Protected count.q
  Protected names.i = 0
  Protected indices.i = 0
  Protected sizes.i = 0
  Protected i.i
  Protected byteIndex.i
  Protected absoluteIndex.i

  If *Catalog = 0
    SpriteSetError("Sprite catalog pointer is null.")
    ProcedureReturn #False
  EndIf
  SpriteCatalogReset(*Catalog)

  If WADIsOpen() = #False
    SpriteSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf

  startIndex = WADFindLump("S_START")
  endIndex = WADFindLump("S_END")
  If startIndex < 0
    SpriteSetError("S_START marker is missing.")
    ProcedureReturn #False
  EndIf
  If endIndex < 0
    SpriteSetError("S_END marker is missing.")
    ProcedureReturn #False
  EndIf
  If startIndex >= endIndex
    SpriteSetError("Sprite namespace markers are reversed: S_START=" + Str(startIndex) + ", S_END=" + Str(endIndex) + ".")
    ProcedureReturn #False
  EndIf

  count = Int(endIndex) - Int(startIndex) - 1
  If count > #SPRITE_MaxCount
    SpriteSetError("Sprite namespace is too large: " + Str(count) + " entries.")
    ProcedureReturn #False
  EndIf

  If count > 0
    names = AllocateMemory(count * 8)
    indices = AllocateMemory(count * 4)
    sizes = AllocateMemory(count * 4)
    If names = 0 Or indices = 0 Or sizes = 0
      If names <> 0
        FreeMemory(names)
      EndIf
      If indices <> 0
        FreeMemory(indices)
      EndIf
      If sizes <> 0
        FreeMemory(sizes)
      EndIf
      SpriteSetError("Out of memory while building the sprite catalog.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      absoluteIndex = startIndex + 1 + i
      For byteIndex = 0 To 7
        PokeA(names + i * 8 + byteIndex, WADLumpRawNameByte(absoluteIndex, byteIndex))
      Next
      PokeL(indices + i * 4, absoluteIndex)
      PokeL(sizes + i * 4, WADLumpSize(absoluteIndex))
    Next
  EndIf

  *Catalog\Magic = #SPRITE_CatalogMagic
  *Catalog\Count = count
  *Catalog\FirstLump = startIndex + 1
  *Catalog\LastLump = endIndex - 1
  *Catalog\Names = names
  *Catalog\WadIndices = indices
  *Catalog\Sizes = sizes
  gSprite_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i SpriteCatalogCount(*Catalog.SpriteCatalog)
  If *Catalog = 0 Or *Catalog\Magic <> #SPRITE_CatalogMagic
    SpriteSetError("Sprite catalog is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Catalog\Count
EndProcedure

Procedure.i SpriteCatalogGetEntry(*Catalog.SpriteCatalog, SpriteIndex.i, *WadIndex.Long, *LumpSize.Long)
  If *Catalog = 0 Or *Catalog\Magic <> #SPRITE_CatalogMagic
    SpriteSetError("Sprite catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If SpriteIndex < 0 Or SpriteIndex >= *Catalog\Count
    SpriteSetError("Sprite catalog index out of range: " + Str(SpriteIndex) + " (count " + Str(*Catalog\Count) + ").")
    ProcedureReturn #False
  EndIf
  If *WadIndex <> 0
    PokeL(*WadIndex, PeekL(*Catalog\WadIndices + SpriteIndex * 4))
  EndIf
  If *LumpSize <> 0
    PokeL(*LumpSize, PeekL(*Catalog\Sizes + SpriteIndex * 4))
  EndIf
  gSprite_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i SpriteCatalogNameByte(*Catalog.SpriteCatalog, SpriteIndex.i, ByteOffset.i)
  If *Catalog = 0 Or *Catalog\Magic <> #SPRITE_CatalogMagic
    SpriteSetError("Sprite catalog is not initialized.")
    ProcedureReturn -1
  EndIf
  If SpriteIndex < 0 Or SpriteIndex >= *Catalog\Count
    SpriteSetError("Sprite catalog index out of range: " + Str(SpriteIndex) + ".")
    ProcedureReturn -1
  EndIf
  If ByteOffset < 0 Or ByteOffset >= 8
    SpriteSetError("Sprite name byte offset out of range: " + Str(ByteOffset) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Catalog\Names + SpriteIndex * 8 + ByteOffset)
EndProcedure

Procedure.s SpriteCatalogDisplayName(*Catalog.SpriteCatalog, SpriteIndex.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  If *Catalog = 0 Or *Catalog\Magic <> #SPRITE_CatalogMagic
    SpriteSetError("Sprite catalog is not initialized.")
    ProcedureReturn ""
  EndIf
  If SpriteIndex < 0 Or SpriteIndex >= *Catalog\Count
    SpriteSetError("Sprite catalog index out of range: " + Str(SpriteIndex) + ".")
    ProcedureReturn ""
  EndIf
  For i = 0 To 7
    value = PeekA(*Catalog\Names + SpriteIndex * 8 + i)
    If value = 0
      Break
    EndIf
    If value >= 32 And value <= 126
      result + Chr(value)
    Else
      result + "."
    EndIf
  Next
  gSprite_LastError = ""
  ProcedureReturn result
EndProcedure

; Reads patch header metadata only. Full post/column validation is delegated to
; PatchDecode() when a sprite is actually decoded.
Procedure.i SpriteCatalogGetPatchInfo(*Catalog.SpriteCatalog, SpriteIndex.i, *Width.Long, *Height.Long, *LeftOffset.Long, *TopOffset.Long)
  Protected wadIndex.l
  Protected lumpSize.l
  Protected bytes.i
  Protected width.i
  Protected height.i
  Protected leftOffset.i
  Protected topOffset.i

  If *Catalog = 0 Or *Catalog\Magic <> #SPRITE_CatalogMagic
    SpriteSetError("Sprite catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If SpriteIndex < 0 Or SpriteIndex >= *Catalog\Count
    SpriteSetError("Sprite catalog index out of range: " + Str(SpriteIndex) + ".")
    ProcedureReturn #False
  EndIf
  If WADIsOpen() = #False
    SpriteSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf

  wadIndex = PeekL(*Catalog\WadIndices + SpriteIndex * 4)
  lumpSize = PeekL(*Catalog\Sizes + SpriteIndex * 4)
  If lumpSize < 8
    SpriteSetError("Sprite lump is too short for a patch header: " + Str(lumpSize) + " bytes.")
    ProcedureReturn #False
  EndIf

  bytes = AllocateMemory(lumpSize)
  If bytes = 0
    SpriteSetError("Out of memory while reading sprite header metadata.")
    ProcedureReturn #False
  EndIf
  If WADReadLump(wadIndex, bytes, lumpSize) = #False
    SpriteSetError("Cannot read sprite lump: " + WADLastError())
    FreeMemory(bytes)
    ProcedureReturn #False
  EndIf

  width = EndianReadU16LE(bytes, 0)
  height = EndianReadU16LE(bytes, 2)
  leftOffset = SpriteReadI16LE(bytes, 4)
  topOffset = SpriteReadI16LE(bytes, 6)
  FreeMemory(bytes)

  If width = 0 Or height = 0
    SpriteSetError("Sprite patch header has zero width or height.")
    ProcedureReturn #False
  EndIf
  If *Width <> 0
    PokeL(*Width, width)
  EndIf
  If *Height <> 0
    PokeL(*Height, height)
  EndIf
  If *LeftOffset <> 0
    PokeL(*LeftOffset, leftOffset)
  EndIf
  If *TopOffset <> 0
    PokeL(*TopOffset, topOffset)
  EndIf
  gSprite_LastError = ""
  ProcedureReturn #True
EndProcedure

; Installs one frame/rotation slot. Rotation 0 fills all eight slots; explicit
; rotations set one slot. Returns #False on duplicate/conflict errors.
Procedure.i SpriteInstallSlot(*State.Byte, *Slots.Long, *Flips.Byte, *MaxFrame.Long, Frame.i, Rotation.i, WadIndex.i, Flip.i, SpriteID.s)
  Protected r.i
  Protected state.i

  If Frame < 0 Or Frame > #SPRITE_MaxFrame
    SpriteSetError("Sprite " + SpriteID + " has an out-of-range frame index.")
    ProcedureReturn #False
  EndIf
  If Rotation < 0 Or Rotation > 8
    SpriteSetError("Sprite " + SpriteID + " has an out-of-range rotation.")
    ProcedureReturn #False
  EndIf

  state = PeekA(*State + Frame)
  If Rotation = 0
    If state = 1
      SpriteSetError("Sprite " + SpriteID + " frame " + Str(Frame) + " has multiple rot=0 lumps.")
      ProcedureReturn #False
    EndIf
    If state = 2
      SpriteSetError("Sprite " + SpriteID + " frame " + Str(Frame) + " mixes rot=0 and explicit rotations.")
      ProcedureReturn #False
    EndIf
    PokeA(*State + Frame, 1)
    For r = 0 To 7
      PokeL(*Slots + (Frame * 8 + r) * 4, WadIndex)
      PokeA(*Flips + Frame * 8 + r, Flip)
    Next
  Else
    If state = 1
      SpriteSetError("Sprite " + SpriteID + " frame " + Str(Frame) + " mixes rot=0 and explicit rotations.")
      ProcedureReturn #False
    EndIf
    If PeekL(*Slots + (Frame * 8 + Rotation - 1) * 4) <> -1
      SpriteSetError("Sprite " + SpriteID + " frame " + Str(Frame) + " rotation " + Str(Rotation) + " is mapped twice.")
      ProcedureReturn #False
    EndIf
    PokeA(*State + Frame, 2)
    PokeL(*Slots + (Frame * 8 + Rotation - 1) * 4, WadIndex)
    PokeA(*Flips + Frame * 8 + Rotation - 1, Flip)
  EndIf

  If Frame > *MaxFrame\l
    *MaxFrame\l = Frame
  EndIf
  ProcedureReturn #True
EndProcedure

; Builds a strict frame set for a four-byte sprite ID. Invalid or incomplete
; groups fail here without invalidating the catalog.
Procedure.i SpriteBuildFrames(*Catalog.SpriteCatalog, SpriteID.s, *Result.SpriteFrameSet)
  Protected Dim query.a(3)
  Protected Dim state.b(#SPRITE_MaxFrame)
  Protected Dim slots.l(#SPRITE_MaxFrame * #SPRITE_RotationCount + 7)
  Protected Dim flips.b(#SPRITE_MaxFrame * #SPRITE_RotationCount + 7)
  Protected i.i
  Protected byteIndex.i
  Protected value.i
  Protected frame.i
  Protected rotation.i
  Protected frame2.i
  Protected rotation2.i
  Protected secondary.i
  Protected wadIndex.l
  Protected lumpSize.l
  Protected matched.i
  Protected maxFrame.l = -1
  Protected frameCount.i
  Protected indices.i = 0
  Protected flipBytes.i = 0
  Protected sourceIndex.i
  Protected targetIndex.i

  If *Result = 0
    SpriteSetError("Sprite frame-set pointer is null.")
    ProcedureReturn #False
  EndIf
  SpriteFrameSetReset(*Result)

  If *Catalog = 0 Or *Catalog\Magic <> #SPRITE_CatalogMagic
    SpriteSetError("Sprite catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If WADIsOpen() = #False
    SpriteSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf
  If Len(SpriteID) <> 4
    SpriteSetError("Sprite ID must be exactly four characters.")
    ProcedureReturn #False
  EndIf
  For i = 0 To 3
    value = Asc(Mid(SpriteID, i + 1, 1))
    If value < 32 Or value > 126
      SpriteSetError("Sprite ID contains an unsupported character.")
      ProcedureReturn #False
    EndIf
    If value >= 97 And value <= 122
      value = value - 32
    EndIf
    query(i) = value
  Next

  For i = 0 To #SPRITE_MaxFrame
    PokeA(@state(0) + i, 0)
  Next
  For i = 0 To (#SPRITE_MaxFrame * #SPRITE_RotationCount + 7)
    PokeL(@slots(0) + i * 4, -1)
    PokeA(@flips(0) + i, 0)
  Next

  For sourceIndex = 0 To *Catalog\Count - 1
    matched = #True
    For byteIndex = 0 To 3
      If PeekA(*Catalog\Names + sourceIndex * 8 + byteIndex) <> query(byteIndex)
        matched = #False
        Break
      EndIf
    Next
    If matched = #False
      Continue
    EndIf

    frame = PeekA(*Catalog\Names + sourceIndex * 8 + 4) - 65
    rotation = PeekA(*Catalog\Names + sourceIndex * 8 + 5) - 48
    If frame < 0 Or frame > #SPRITE_MaxFrame
      SpriteSetError("Sprite " + SpriteID + " has an invalid primary frame byte at catalog index " + Str(sourceIndex) + ".")
      ProcedureReturn #False
    EndIf
    If rotation < 0 Or rotation > 8
      SpriteSetError("Sprite " + SpriteID + " has an invalid primary rotation byte at catalog index " + Str(sourceIndex) + ".")
      ProcedureReturn #False
    EndIf

    wadIndex = PeekL(*Catalog\WadIndices + sourceIndex * 4)
    lumpSize = PeekL(*Catalog\Sizes + sourceIndex * 4)
    If lumpSize <= 0
      SpriteSetError("Sprite " + SpriteID + " references a zero-length lump at catalog index " + Str(sourceIndex) + ".")
      ProcedureReturn #False
    EndIf

    If SpriteInstallSlot(@state(0), @slots(0), @flips(0), @maxFrame, frame, rotation, wadIndex, 0, SpriteID) = #False
      ProcedureReturn #False
    EndIf

    value = PeekA(*Catalog\Names + sourceIndex * 8 + 6)
    secondary = PeekA(*Catalog\Names + sourceIndex * 8 + 7)
    If value <> 0
      frame2 = value - 65
      rotation2 = secondary - 48
      If frame2 < 0 Or frame2 > #SPRITE_MaxFrame
        SpriteSetError("Sprite " + SpriteID + " has an invalid secondary frame byte at catalog index " + Str(sourceIndex) + ".")
        ProcedureReturn #False
      EndIf
      If rotation2 < 0 Or rotation2 > 8
        SpriteSetError("Sprite " + SpriteID + " has an invalid secondary rotation byte at catalog index " + Str(sourceIndex) + ".")
        ProcedureReturn #False
      EndIf
      If SpriteInstallSlot(@state(0), @slots(0), @flips(0), @maxFrame, frame2, rotation2, wadIndex, 1, SpriteID) = #False
        ProcedureReturn #False
      EndIf
    ElseIf secondary <> 0
      SpriteSetError("Sprite " + SpriteID + " has an incomplete secondary frame/rotation pair at catalog index " + Str(sourceIndex) + ".")
      ProcedureReturn #False
    EndIf
  Next

  If maxFrame < 0
    SpriteSetError("No sprite lumps found for ID " + SpriteID + ".")
    ProcedureReturn #False
  EndIf

  frameCount = maxFrame + 1
  For frame = 0 To maxFrame
    Select PeekA(@state(0) + frame)
      Case 0
        SpriteSetError("Sprite " + SpriteID + " is missing frame " + Str(frame) + ".")
        ProcedureReturn #False
      Case 2
        For rotation = 0 To 7
          If PeekL(@slots(0) + (frame * 8 + rotation) * 4) = -1
            SpriteSetError("Sprite " + SpriteID + " frame " + Str(frame) + " is missing rotation " + Str(rotation + 1) + ".")
            ProcedureReturn #False
          EndIf
        Next
    EndSelect
  Next

  indices = AllocateMemory(frameCount * #SPRITE_RotationCount * 4)
  flipBytes = AllocateMemory(frameCount * #SPRITE_RotationCount)
  If indices = 0 Or flipBytes = 0
    If indices <> 0
      FreeMemory(indices)
    EndIf
    If flipBytes <> 0
      FreeMemory(flipBytes)
    EndIf
    SpriteSetError("Out of memory while building sprite frames.")
    ProcedureReturn #False
  EndIf
  For frame = 0 To frameCount - 1
    For rotation = 0 To 7
      targetIndex = (frame * 8 + rotation) * 4
      PokeL(indices + targetIndex, PeekL(@slots(0) + targetIndex))
      PokeA(flipBytes + frame * 8 + rotation, PeekA(@flips(0) + frame * 8 + rotation))
    Next
  Next

  *Result\Magic = #SPRITE_FrameSetMagic
  *Result\FrameCount = frameCount
  *Result\WadIndices = indices
  *Result\Flips = flipBytes
  gSprite_LastError = ""
  ProcedureReturn #True
EndProcedure

; Rotation is 1..8; frame index is zero-based ('A' = 0).
Procedure.i SpriteFrameGet(*FrameSet.SpriteFrameSet, FrameIndex.i, Rotation.i, *WadIndex.Long, *Flip.Long)
  Protected offset.i

  If *FrameSet = 0 Or *FrameSet\Magic <> #SPRITE_FrameSetMagic
    SpriteSetError("Sprite frame set is not initialized.")
    ProcedureReturn #False
  EndIf
  If FrameIndex < 0 Or FrameIndex >= *FrameSet\FrameCount
    SpriteSetError("Sprite frame index out of range: " + Str(FrameIndex) + ".")
    ProcedureReturn #False
  EndIf
  If Rotation < 1 Or Rotation > #SPRITE_RotationCount
    SpriteSetError("Sprite rotation out of range: " + Str(Rotation) + " (allowed 1..8).")
    ProcedureReturn #False
  EndIf

  offset = FrameIndex * 8 + Rotation - 1
  If *WadIndex <> 0
    PokeL(*WadIndex, PeekL(*FrameSet\WadIndices + offset * 4))
  EndIf
  If *Flip <> 0
    PokeL(*Flip, PeekA(*FrameSet\Flips + offset))
  EndIf
  gSprite_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
