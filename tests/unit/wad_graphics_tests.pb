; -----------------------------------------------------------------------------
; DoomPB - PLAYPAL and Doom patch decoder tests (M1-03)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Every input buffer is synthesized in memory. No Doom resources are copied or
; required, and no files are written. Exit code: 0 when every assertion passed,
; otherwise the number of failed assertions.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/Graphics/Palette.pbi"
XIncludeFile "../../src/Graphics/Patch.pbi"

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

; ---------------------------------------------------------------------------
; Byte buffer and patch/column builders
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

; Appends a post whose pixels are given as an uppercase hex string.
Procedure BBPost(*B.ByteBuffer, TopDelta.i, PixelsHex.s)
  Protected pixelCount.i = Len(PixelsHex) / 2
  Protected i.i

  BBByte(*B, TopDelta)
  BBByte(*B, pixelCount)
  BBByte(*B, 0)
  For i = 0 To pixelCount - 1
    BBByte(*B, Val("$" + Mid(PixelsHex, i * 2 + 1, 2)))
  Next
  BBByte(*B, 0)
EndProcedure

Procedure BBPostEmpty(*B.ByteBuffer, TopDelta.i)
  BBByte(*B, TopDelta)
  BBByte(*B, 0)
  BBByte(*B, 0)
  BBByte(*B, 0)
EndProcedure

Procedure BBTerm(*B.ByteBuffer)
  BBByte(*B, $FF)
EndProcedure

Procedure PBStart(*B.ByteBuffer, Width.i, Height.i, Left.i, Top.i)
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

Procedure PBSetOffset(*B.ByteBuffer, Column.i, Offset.q)
  BBSetLong(*B, 8 + Column * 4, Offset)
EndProcedure

Procedure PBAddColumn(*B.ByteBuffer, Column.i, *Column.ByteBuffer)
  PBSetOffset(*B, Column, *B\Pos)
  CopyMemory(*Column\Data, *B\Data + *B\Pos, *Column\Pos)
  *B\Pos + *Column\Pos
EndProcedure

; ---------------------------------------------------------------------------
; Palette fixture
; ---------------------------------------------------------------------------

; Allocates Count * 768 bytes with a deterministic non-repeating byte pattern.
Procedure.i MakePaletteBytes(Count.i)
  Protected length.i = Count * 768
  Protected memory.i = AllocateMemory(length)
  Protected i.i

  If memory = 0
    ProcedureReturn 0
  EndIf
  For i = 0 To length - 1
    PokeA(memory + i, (i * 37 + 11) & $FF)
  Next
  ProcedureReturn memory
EndProcedure

; ---------------------------------------------------------------------------
; P01 - P10
; ---------------------------------------------------------------------------

Procedure TestP01SinglePalette()
  BeginCase("P01", "One complete 768-byte palette")
  Protected memory.i = MakePaletteBytes(1)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i

  Check(Bool(memory <> 0), "synthetic palette allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(PaletteDecode(memory, 768, @pal)), "one palette decodes")
  Check(Bool(PaletteCount(@pal) = 1), "palette count is 1")
  Check(Bool(PaletteGetRGB(@pal, 0, 0, @r, @g, @b)), "color 0 is readable")
  Check(Bool(r = PeekA(memory) And g = PeekA(memory + 1) And b = PeekA(memory + 2)), "color 0 preserves RGB order")
  Check(Bool(PaletteGetRGB(@pal, 0, 255, @r, @g, @b)), "color 255 is readable")
  Check(Bool(r = PeekA(memory + 765) And g = PeekA(memory + 766) And b = PeekA(memory + 767)), "color 255 comes from the last triple")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP02TwoPalettes()
  BeginCase("P02", "Two distinct palettes do not mix")
  Protected memory.i = AllocateMemory(2 * 768)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i

  Check(Bool(memory <> 0), "synthetic palettes allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 2 * 768, 0)
  PokeA(memory + 0, 1)
  PokeA(memory + 1, 2)
  PokeA(memory + 2, 3)
  PokeA(memory + 768 + 0, 4)
  PokeA(memory + 768 + 1, 5)
  PokeA(memory + 768 + 2, 6)
  PokeA(memory + 768 + 765, 7)
  PokeA(memory + 768 + 766, 8)
  PokeA(memory + 768 + 767, 9)

  Check(Bool(PaletteDecode(memory, 2 * 768, @pal)), "two palettes decode")
  Check(Bool(PaletteCount(@pal) = 2), "count is 2")
  Check(Bool(PaletteGetRGB(@pal, 0, 0, @r, @g, @b)), "palette 0 color 0 reads")
  Check(Bool(r = 1 And g = 2 And b = 3), "palette 0 keeps its own values")
  Check(Bool(PaletteGetRGB(@pal, 1, 0, @r, @g, @b)), "palette 1 color 0 reads")
  Check(Bool(r = 4 And g = 5 And b = 6), "palette 1 keeps its own values")
  Check(Bool(PaletteGetRGB(@pal, 1, 255, @r, @g, @b)), "palette 1 color 255 reads")
  Check(Bool(r = 7 And g = 8 And b = 9), "palette 1 last color is correct")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP03FourteenPalettes()
  BeginCase("P03", "14 palettes (10,752 bytes) and boundary indexing")
  Protected memory.i = MakePaletteBytes(14)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i
  Protected offset.i

  Check(Bool(memory <> 0), "14 synthetic palettes allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(PaletteDecode(memory, 14 * 768, @pal)), "14 palettes decode")
  Check(Bool(PaletteCount(@pal) = 14), "count is 14")
  offset = 13 * 768 + 255 * 3
  Check(Bool(PaletteGetRGB(@pal, 13, 255, @r, @g, @b)), "last palette/color reads")
  Check(Bool(r = PeekA(memory + offset) And g = PeekA(memory + offset + 1) And b = PeekA(memory + offset + 2)), "last triple matches the source")
  Check(Bool(PaletteGetRGB(@pal, 14, 0, @r, @g, @b) = #False), "palette index 14 is rejected")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP04ChannelExtremes()
  BeginCase("P04", "RGB values 00, 80 and FF")
  Protected memory.i = AllocateMemory(768)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i

  Check(Bool(memory <> 0), "palette buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 768, 0)
  PokeA(memory + 0, $00)
  PokeA(memory + 1, $80)
  PokeA(memory + 2, $FF)
  PokeA(memory + 3, $FF)
  PokeA(memory + 4, $00)
  PokeA(memory + 5, $80)

  Check(Bool(PaletteDecode(memory, 768, @pal)), "palette decodes")
  Check(Bool(PaletteGetRGB(@pal, 0, 0, @r, @g, @b)), "color 0 reads")
  Check(Bool(r = $00 And g = $80 And b = $FF), "00/80/FF are preserved exactly")
  Check(Bool(PaletteGetRGB(@pal, 0, 1, @r, @g, @b)), "color 1 reads")
  Check(Bool(r = $FF And g = $00 And b = $80), "no clipping or channel swapping")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP05InvalidLengths()
  BeginCase("P05", "Invalid and non-multiple PLAYPAL lengths")
  Protected memory.i = AllocateMemory(1536)
  Protected pal.PaletteSet

  Check(Bool(memory <> 0), "buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 1536, 0)

  Check(Bool(PaletteDecode(memory, 0, @pal) = #False), "length 0 is rejected")
  Check(Bool(PaletteDecode(memory, 1, @pal) = #False), "length 1 is rejected")
  Check(Bool(PaletteDecode(memory, 767, @pal) = #False), "length 767 is rejected")
  Check(Bool(PaletteDecode(memory, 769, @pal) = #False), "length 769 is rejected")
  Check(Bool(PaletteDecode(memory, 1535, @pal) = #False), "length 1535 is rejected")
  Check(Bool(PaletteDecode(memory, 1536, @pal) = #True), "length 1536 (2 palettes) is accepted")
  Check(Bool(PaletteCount(@pal) = 2), "accepted boundary has 2 palettes")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP06NullAndNegativeLength()
  BeginCase("P06", "Null input pointer and negative length")
  Protected pal.PaletteSet

  Check(Bool(PaletteDecode(0, 768, @pal) = #False), "null pointer with nonzero length is rejected")
  Check(Bool(FindString(PaletteLastError(), "null") > 0), "null-pointer error is actionable")
  Check(Bool(PaletteDecode(0, 0, @pal) = #False), "null pointer with zero length is rejected")
  Check(Bool(PaletteDecode(0, -768, @pal) = #False), "negative length is rejected")
  Check(Bool(PaletteCount(@pal) = 0), "failed decodes leave an empty palette set")
EndProcedure

Procedure TestP07InvalidIndices()
  BeginCase("P07", "Negative and out-of-range palette/color indices")
  Protected memory.i = MakePaletteBytes(2)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i

  Check(Bool(memory <> 0), "synthetic palettes allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(PaletteDecode(memory, 2 * 768, @pal)), "palette decodes")
  r = $CC
  g = $CC
  b = $CC
  Check(Bool(PaletteGetRGB(@pal, -1, 0, @r, @g, @b) = #False), "palette index -1 is rejected")
  Check(Bool(PaletteGetRGB(@pal, 2, 0, @r, @g, @b) = #False), "palette index == count is rejected")
  Check(Bool(PaletteGetRGB(@pal, 0, -1, @r, @g, @b) = #False), "color index -1 is rejected")
  Check(Bool(PaletteGetRGB(@pal, 0, 256, @r, @g, @b) = #False), "color index 256 is rejected")
  Check(Bool(r = $CC And g = $CC And b = $CC), "rejected access leaves channel bytes untouched")
  Check(Bool(PaletteGetRGB(@pal, 0, 0, 0, @g, @b) = #False), "null channel pointer is rejected")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP08ResetAndRecovery()
  BeginCase("P08", "Decode -> reset -> decode and failure -> success")
  Protected memory.i = MakePaletteBytes(1)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i

  Check(Bool(memory <> 0), "synthetic palette allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  Check(Bool(PaletteDecode(memory, 768, @pal)), "first decode succeeds")
  Check(Bool(PaletteReset(@pal)), "reset succeeds")
  Check(Bool(PaletteCount(@pal) = 0), "reset clears the count")
  Check(Bool(pal\RGB = 0), "reset releases the RGB pointer")
  Check(Bool(PaletteGetRGB(@pal, 0, 0, @r, @g, @b) = #False), "access after reset fails")
  Check(Bool(PaletteDecode(memory, 768, @pal)), "decode after reset succeeds")
  Check(Bool(PaletteCount(@pal) = 1), "re-decoded count is correct")
  Check(Bool(PaletteDecode(memory, 769, @pal) = #False), "failed decode after success is rejected")
  Check(Bool(PaletteCount(@pal) = 0), "failed decode leaves an empty set")
  Check(Bool(PaletteDecode(memory, 768, @pal)), "success after failure works")
  Check(Bool(PaletteGetRGB(@pal, 0, 0, @r, @g, @b)), "recovered palette is readable")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP09GuardBytes()
  BeginCase("P09", "Input guard bytes and output boundaries")
  Protected memory.i = AllocateMemory(770)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i

  Check(Bool(memory <> 0), "guarded buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 770, $CC)
  FillMemory(memory + 1, 768, $5A)
  Check(Bool(PaletteDecode(memory + 1, 768, @pal)), "palette decodes from an unaligned address")
  Check(Bool(PeekA(memory) = $CC), "leading guard byte is intact")
  Check(Bool(PeekA(memory + 769) = $CC), "trailing guard byte is intact")
  Check(Bool(PaletteGetRGB(@pal, 0, 255, @r, @g, @b)), "last color is readable")
  Check(Bool(r = $5A And g = $5A And b = $5A), "last color matches the guarded source")
  Check(Bool(PaletteGetRGB(@pal, 0, 256, @r, @g, @b) = #False), "one past the last color is rejected")
  Check(Bool(PaletteGetRGB(@pal, 1, 0, @r, @g, @b) = #False), "one past the last palette is rejected")
  PaletteReset(@pal)
  FreeMemory(memory)
EndProcedure

Procedure TestP10PaletteCap()
  BeginCase("P10", "Palette count cap and allocation boundary")
  Protected over.i = AllocateMemory(257 * 768)
  Protected atCap.i = AllocateMemory(256 * 768)
  Protected pal.PaletteSet
  Protected r.i, g.i, b.i

  Check(Bool(over <> 0 And atCap <> 0), "cap test buffers allocated")
  If over = 0 Or atCap = 0
    If over <> 0
      FreeMemory(over)
    EndIf
    If atCap <> 0
      FreeMemory(atCap)
    EndIf
    ProcedureReturn
  EndIf
  FillMemory(over, 257 * 768, 0)
  FillMemory(atCap, 256 * 768, 0)

  Check(Bool(PaletteDecode(over, 257 * 768, @pal) = #False), "257 palettes are rejected before allocation")
  Check(Bool(FindString(PaletteLastError(), "too many") > 0), "cap error is specific")
  Check(Bool(PaletteCount(@pal) = 0), "cap failure leaves no palette data")

  Check(Bool(PaletteDecode(atCap, 256 * 768, @pal)), "256 palettes are accepted at the cap")
  Check(Bool(PaletteCount(@pal) = 256), "cap count is 256")
  Check(Bool(PaletteGetRGB(@pal, 255, 255, @r, @g, @b)), "last palette/color at the cap is readable")
  PaletteReset(@pal)
  FreeMemory(over)
  FreeMemory(atCap)
EndProcedure

; ---------------------------------------------------------------------------
; G01 - G24
; ---------------------------------------------------------------------------

Procedure TestG01MinimalPatch()
  BeginCase("G01", "Minimal 1x1 opaque patch")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 1, 0, 0)
  BBInit(@col, 64)
  BBPost(@col, 0, "2A")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "1x1 patch decodes")
  Check(Bool(image\Width = 1 And image\Height = 1), "dimensions are 1x1")
  Check(Bool(image\PixelCount = 1), "pixel count is 1")
  Check(Bool(PatchPixelAt(@image, 0, 0) = $2A), "pixel value is 0x2A")
  Check(Bool(PatchOpaqueAt(@image, 0, 0) = 1), "pixel is opaque")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG02RowMajor()
  BeginCase("G02", "2x3 patch and row-major orientation")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 2, 3, 0, 0)
  BBInit(@col, 64)
  BBPost(@col, 0, "010203")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)
  BBInit(@col, 64)
  BBPost(@col, 0, "040506")
  BBTerm(@col)
  PBAddColumn(@patch, 1, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "patch decodes")
  Check(Bool(PatchPixelAt(@image, 0, 0) = 1 And PatchPixelAt(@image, 1, 0) = 4), "row 0 is left-to-right")
  Check(Bool(PatchPixelAt(@image, 0, 1) = 2 And PatchPixelAt(@image, 1, 1) = 5), "row 1 is left-to-right")
  Check(Bool(PatchPixelAt(@image, 0, 2) = 3 And PatchPixelAt(@image, 1, 2) = 6), "row 2 is left-to-right")
  Check(Bool(PatchOpaqueAt(@image, 0, 1) = 1 And PatchOpaqueAt(@image, 1, 2) = 1), "all covered pixels are opaque")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG03TransparentGap()
  BeginCase("G03", "Multiple posts with a transparent gap")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 3, 0, 0)
  BBInit(@col, 64)
  BBPost(@col, 0, "0A")
  BBPost(@col, 2, "14")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "patch decodes")
  Check(Bool(PatchPixelAt(@image, 0, 0) = 10), "first post pixel is present")
  Check(Bool(PatchOpaqueAt(@image, 0, 0) = 1), "first post is opaque")
  Check(Bool(PatchOpaqueAt(@image, 0, 1) = 0), "gap row is transparent")
  Check(Bool(PatchPixelAt(@image, 0, 1) = 0), "gap pixel is zero-initialized")
  Check(Bool(PatchPixelAt(@image, 0, 2) = 20), "second post pixel is present")
  Check(Bool(PatchOpaqueAt(@image, 0, 2) = 1), "second post is opaque")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG04EmptyColumn()
  BeginCase("G04", "Empty transparent column")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 2, 0, 0)
  BBInit(@col, 16)
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "patch with an empty column decodes")
  Check(Bool(PatchOpaqueAt(@image, 0, 0) = 0), "row 0 is transparent")
  Check(Bool(PatchOpaqueAt(@image, 0, 1) = 0), "row 1 is transparent")
  Check(Bool(PatchPixelAt(@image, 0, 0) = 0 And PatchPixelAt(@image, 0, 1) = 0), "transparent pixels are zero")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG05Pixel255()
  BeginCase("G05", "Pixel value 255 is opaque, not a terminator")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 1, 0, 0)
  BBInit(@col, 16)
  BBPost(@col, 0, "FF")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "patch decodes")
  Check(Bool(PatchPixelAt(@image, 0, 0) = 255), "pixel index 255 is preserved")
  Check(Bool(PatchOpaqueAt(@image, 0, 0) = 1), "pixel 255 is opaque")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG06NegativeOffsets()
  BeginCase("G06", "Signed negative left/top offsets")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 1, -5, -7)
  BBInit(@col, 16)
  BBPost(@col, 0, "33")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "patch decodes")
  Check(Bool(image\LeftOffset = -5), "left offset is -5")
  Check(Bool(image\TopOffset = -7), "top offset is -7")
  Check(Bool(image\Width = 1 And image\Height = 1), "offsets do not change dimensions")
  Check(Bool(PatchPixelAt(@image, 0, 0) = $33), "pixel data is unchanged")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG07PositiveOffsets()
  BeginCase("G07", "Nonzero positive offsets")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 2, 1, 13, 17)
  BBInit(@col, 16)
  BBPost(@col, 0, "44")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)
  BBInit(@col, 16)
  BBPost(@col, 0, "55")
  BBTerm(@col)
  PBAddColumn(@patch, 1, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "patch decodes")
  Check(Bool(image\LeftOffset = 13 And image\TopOffset = 17), "offsets are stored exactly")
  Check(Bool(PatchPixelAt(@image, 0, 0) = $44 And PatchPixelAt(@image, 1, 0) = $55), "decode does not shift pixel coordinates")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG08UnsortedAndSharedOffsets()
  BeginCase("G08", "Shared and unsorted column offsets")
  Protected patch.ByteBuffer
  Protected colA.ByteBuffer
  Protected colB.ByteBuffer
  Protected image.PatchImage
  Protected sharedOffset.q
  Protected offsetA.q
  Protected offsetB.q

  ; First image: both columns share one column payload.
  PBStart(@patch, 2, 1, 0, 0)
  sharedOffset = patch\Pos
  BBInit(@colA, 16)
  BBPost(@colA, 0, "4D")
  BBTerm(@colA)
  PBAddColumn(@patch, 0, @colA)
  PBSetOffset(@patch, 1, sharedOffset)
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "shared-offset patch decodes")
  Check(Bool(PatchPixelAt(@image, 0, 0) = $4D And PatchPixelAt(@image, 1, 0) = $4D), "both columns decode the shared payload")
  PatchReset(@image)
  BBFree(@colA)
  BBFree(@patch)

  ; Second image: column 0 points to the later payload, column 1 to the earlier.
  PBStart(@patch, 2, 1, 0, 0)
  BBInit(@colA, 16)
  BBPost(@colA, 0, "0B")
  BBTerm(@colA)
  offsetA = patch\Pos
  PBAddColumn(@patch, 1, @colA)
  BBFree(@colA)
  BBInit(@colB, 16)
  BBPost(@colB, 0, "16")
  BBTerm(@colB)
  offsetB = patch\Pos
  PBAddColumn(@patch, 0, @colB)
  BBFree(@colB)
  PBSetOffset(@patch, 0, offsetB)
  PBSetOffset(@patch, 1, offsetA)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "unsorted-offset patch decodes")
  Check(Bool(PatchPixelAt(@image, 0, 0) = $16), "column 0 uses its declared later offset")
  Check(Bool(PatchPixelAt(@image, 1, 0) = $0B), "column 1 uses its declared earlier offset")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG09OverlappingPosts()
  BeginCase("G09", "Overlapping posts: later values win")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 3, 0, 0)
  BBInit(@col, 64)
  BBPost(@col, 0, "0102")
  BBPost(@col, 1, "0908")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "overlapping posts decode")
  Check(Bool(PatchPixelAt(@image, 0, 0) = 1), "row 0 keeps the first post value")
  Check(Bool(PatchPixelAt(@image, 0, 1) = 9), "row 1 takes the later post value")
  Check(Bool(PatchPixelAt(@image, 0, 2) = 8), "row 2 takes the later post value")
  Check(Bool(PatchOpaqueAt(@image, 0, 1) = 1), "overlap remains opaque")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG10ZeroLengthPost()
  BeginCase("G10", "Zero-length post followed by a valid post")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 2, 0, 0)
  BBInit(@col, 32)
  BBPostEmpty(@col, 0)
  BBPost(@col, 1, "07")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "zero-length post advances cleanly")
  Check(Bool(PatchOpaqueAt(@image, 0, 0) = 0), "zero-length post leaves its row transparent")
  Check(Bool(PatchPixelAt(@image, 0, 1) = 7), "following post is decoded")
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestG11ShortInputs()
  BeginCase("G11", "Inputs shorter than the patch header")
  Protected memory.i = AllocateMemory(8)
  Protected image.PatchImage
  Protected length.i

  Check(Bool(memory <> 0), "short buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 8, 0)

  For length = 0 To 7
    Check(Bool(PatchDecode(memory, length, @image) = #False), "length " + Str(length) + " is rejected")
  Next
  Check(Bool(image\Pixels = 0 And image\Mask = 0), "failed decode leaves no output")
  FreeMemory(memory)
EndProcedure

Procedure TestG12InvalidDimensions()
  BeginCase("G12", "Zero, negative and oversized dimensions")
  Protected memory.i = AllocateMemory(16)
  Protected image.PatchImage

  Check(Bool(memory <> 0), "header buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 16, 0)

  Check(Bool(PatchDecode(memory, 8, @image) = #False), "zero width is rejected")
  PokeA(memory + 0, 1)
  Check(Bool(PatchDecode(memory, 12, @image) = #False), "zero height is rejected")
  ; 0xFFFF is a negative int16 and also above the dimension cap.
  PokeA(memory + 0, $FF)
  PokeA(memory + 1, $FF)
  PokeA(memory + 2, 1)
  Check(Bool(PatchDecode(memory, 8, @image) = #False), "negative/oversized width is rejected")
  PokeA(memory + 0, 1)
  PokeA(memory + 1, 0)
  PokeA(memory + 2, $FF)
  PokeA(memory + 3, $FF)
  Check(Bool(PatchDecode(memory, 12, @image) = #False), "negative/oversized height is rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestG13TruncatedTable()
  BeginCase("G13", "Column table beyond the input length")
  Protected patch.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 2, 1, 0, 0)
  Check(Bool(patch\Pos = 16), "builder wrote a 16-byte header/table")
  Check(Bool(PatchDecode(patch\Data, patch\Pos - 1, @image) = #False), "one byte short of the table is rejected")
  Check(Bool(FindString(PatchLastError(), "column table") > 0), "table error is specific")
  BBFree(@patch)
EndProcedure

Procedure TestG14ColumnOffsetOob()
  BeginCase("G14", "Column offset beyond EOF or exactly EOF")
  Protected patch.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 1, 0, 0)
  PBSetOffset(@patch, 0, patch\Pos)
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "offset exactly at EOF is rejected")
  PBSetOffset(@patch, 0, 999999)
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "offset far past EOF is rejected")
  PBSetOffset(@patch, 0, 0)
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "offset inside the header is rejected")
  Check(Bool(image\Pixels = 0), "failed offsets leave no output")
  BBFree(@patch)
EndProcedure

Procedure TestG15TruncatedPostHeader()
  BeginCase("G15", "Truncated post header")
  Protected patch.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 1, 0, 0)
  PBSetOffset(@patch, 0, patch\Pos)
  BBByte(@patch, 0)   ; topdelta only, length byte missing
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "truncated post header is rejected")
  BBFree(@patch)
EndProcedure

Procedure TestG16TruncatedPost()
  BeginCase("G16", "Truncated post body and missing trailing pad")
  Protected patch.ByteBuffer
  Protected image.PatchImage

  ; Height 6 lets the declared five-pixel post pass the vertical range check,
  ; so the missing bytes are what must be detected.
  PBStart(@patch, 1, 6, 0, 0)
  PBSetOffset(@patch, 0, patch\Pos)
  BBByte(@patch, 0)
  BBByte(@patch, 5)   ; claims five pixels
  BBByte(@patch, 0)
  BBByte(@patch, $AA)
  BBByte(@patch, $BB)
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "truncated post body is rejected")
  Check(Bool(FindString(PatchLastError(), "truncated") > 0), "truncation error is specific")
  BBFree(@patch)
EndProcedure

Procedure TestG17MissingTerminator()
  BeginCase("G17", "Missing 0xFF column terminator")
  Protected patch.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 1, 0, 0)
  PBSetOffset(@patch, 0, patch\Pos)
  BBPost(@patch, 0, "05")
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "column without a terminator is rejected")
  Check(Bool(FindString(PatchLastError(), "terminator") > 0), "terminator error is specific")
  BBFree(@patch)
EndProcedure

Procedure TestG18PostExceedsHeight()
  BeginCase("G18", "topdelta + length exceeds height")
  Protected patch.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 1, 2, 0, 0)
  PBSetOffset(@patch, 0, patch\Pos)
  BBPost(@patch, 1, "0102")
  BBTerm(@patch)
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "post extending past the bottom is rejected")
  Check(Bool(image\PixelCount = 0 And image\Pixels = 0), "rejected post leaves no output")
  BBFree(@patch)
EndProcedure

Procedure TestG19GiantDimensions()
  BeginCase("G19", "Giant declared dimensions and budget overflow")
  Protected memory.i = AllocateMemory(8)
  Protected image.PatchImage

  Check(Bool(memory <> 0), "header buffer allocated")
  If memory = 0
    ProcedureReturn
  EndIf
  FillMemory(memory, 8, $FF)
  Check(Bool(PatchDecode(memory, 8, @image) = #False), "65535x65535 is rejected before allocation")
  Check(Bool(image\Pixels = 0 And image\Mask = 0), "no planes were allocated")
  ; A 4096x4096 header with no column table is also rejected before allocation.
  PokeA(memory + 0, $00)
  PokeA(memory + 1, $10)
  PokeA(memory + 2, $00)
  PokeA(memory + 3, $10)
  Check(Bool(PatchDecode(memory, 8, @image) = #False), "maximum dimensions without a table are rejected")
  FreeMemory(memory)
EndProcedure

Procedure TestG20CorruptSecondColumn()
  BeginCase("G20", "Corrupt second column after a valid first column")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@patch, 2, 1, 0, 0)
  BBInit(@col, 16)
  BBPost(@col, 0, "28")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)
  PBSetOffset(@patch, 1, 888888)
  Check(Bool(PatchDecode(patch\Data, patch\Pos, @image) = #False), "corrupt second column fails the decode")
  Check(Bool(image\Pixels = 0 And image\Mask = 0), "partial output is released")
  Check(Bool(image\Width = 0 And image\Height = 0), "metadata is cleared")
  BBFree(@patch)
EndProcedure

Procedure TestG21FailureThenSuccess()
  BeginCase("G21", "Failure followed by a successful decode with the same result")
  Protected bad.ByteBuffer
  Protected good.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage

  PBStart(@bad, 1, 1, 0, 0)
  PBSetOffset(@bad, 0, bad\Pos)
  BBByte(@bad, 0)
  Check(Bool(PatchDecode(bad\Data, bad\Pos, @image) = #False), "malformed patch fails")
  BBFree(@bad)

  PBStart(@good, 1, 1, 0, 0)
  BBInit(@col, 16)
  BBPost(@col, 0, "6B")
  BBTerm(@col)
  PBAddColumn(@good, 0, @col)
  BBFree(@col)

  Check(Bool(PatchDecode(good\Data, good\Pos, @image)), "valid patch decodes into the same structure")
  Check(Bool(PatchPixelAt(@image, 0, 0) = $6B), "decoded pixel is correct")
  PatchReset(@image)
  BBFree(@good)
EndProcedure

Procedure TestG22InputFreed()
  BeginCase("G22", "Decoded image survives freeing the raw input")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage
  Protected raw.i

  PBStart(@patch, 1, 1, 0, 0)
  BBInit(@col, 16)
  BBPost(@col, 0, "7C")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)
  raw = patch\Data

  Check(Bool(PatchDecode(raw, patch\Pos, @image)), "patch decodes")
  FreeMemory(raw)
  patch\Data = 0
  patch\Pos = 0
  patch\Capacity = 0

  Check(Bool(PatchPixelAt(@image, 0, 0) = $7C), "pixel remains readable after input is freed")
  Check(Bool(PatchOpaqueAt(@image, 0, 0) = 1), "mask remains readable after input is freed")
  PatchReset(@image)
EndProcedure

Procedure TestG23Canaries()
  BeginCase("G23", "Guard bytes around input and output bounds")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected guarded.i
  Protected image.PatchImage
  Protected i.i

  PBStart(@patch, 2, 2, 0, 0)
  BBInit(@col, 16)
  BBPost(@col, 0, "1112")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)
  BBInit(@col, 16)
  BBPost(@col, 0, "2122")
  BBTerm(@col)
  PBAddColumn(@patch, 1, @col)
  BBFree(@col)

  guarded = AllocateMemory(patch\Pos + 4)
  Check(Bool(guarded <> 0), "guarded input buffer allocated")
  If guarded = 0
    BBFree(@patch)
    ProcedureReturn
  EndIf
  FillMemory(guarded, patch\Pos + 4, $CC)
  CopyMemory(patch\Data, guarded + 2, patch\Pos)

  Check(Bool(PatchDecode(guarded + 2, patch\Pos, @image)), "patch decodes from an unaligned guarded buffer")
  Check(Bool(PeekA(guarded) = $CC And PeekA(guarded + 1) = $CC), "leading input guards are intact")
  Check(Bool(PeekA(guarded + 2 + patch\Pos) = $CC And PeekA(guarded + 3 + patch\Pos) = $CC), "trailing input guards are intact")
  Check(Bool(image\PixelCount = 4), "pixel count is exactly width*height")

  For i = 0 To 3
    Check(Bool(PatchOpaqueAt(@image, i % 2, i / 2) = 1), "in-range mask access " + Str(i) + " is valid")
  Next
  Check(Bool(PatchPixelAt(@image, -1, 0) = -1), "negative X is rejected")
  Check(Bool(PatchPixelAt(@image, 2, 0) = -1), "X == width is rejected")
  Check(Bool(PatchPixelAt(@image, 0, 2) = -1), "Y == height is rejected")
  Check(Bool(PatchOpaqueAt(@image, 0, 2) = -1), "mask access out of range is rejected")
  Check(Bool(PatchPixelAt(@image, 0, 0) = $11), "in-range pixels are unchanged by rejected accesses")

  PatchReset(@image)
  FreeMemory(guarded)
  BBFree(@patch)
EndProcedure

Procedure TestG24DecodeCycles()
  BeginCase("G24", "Multiple decode/reset cycles")
  Protected patch.ByteBuffer
  Protected col.ByteBuffer
  Protected image.PatchImage
  Protected cycle.i

  PBStart(@patch, 1, 2, 0, 0)
  BBInit(@col, 32)
  BBPost(@col, 0, "31")
  BBPost(@col, 1, "32")
  BBTerm(@col)
  PBAddColumn(@patch, 0, @col)
  BBFree(@col)

  For cycle = 1 To 5
    Check(Bool(PatchDecode(patch\Data, patch\Pos, @image)), "cycle " + Str(cycle) + " decodes")
    Check(Bool(PatchPixelAt(@image, 0, 0) = $31 And PatchPixelAt(@image, 0, 1) = $32), "cycle " + Str(cycle) + " pixels are stable")
    Check(Bool(PatchReset(@image)), "cycle " + Str(cycle) + " resets")
    Check(Bool(image\PixelCount = 0 And image\Pixels = 0 And image\Mask = 0), "cycle " + Str(cycle) + " releases both planes")
  Next
  BBFree(@patch)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB PLAYPAL/patch decoder tests (M1-03)")

TestP01SinglePalette()
TestP02TwoPalettes()
TestP03FourteenPalettes()
TestP04ChannelExtremes()
TestP05InvalidLengths()
TestP06NullAndNegativeLength()
TestP07InvalidIndices()
TestP08ResetAndRecovery()
TestP09GuardBytes()
TestP10PaletteCap()

TestG01MinimalPatch()
TestG02RowMajor()
TestG03TransparentGap()
TestG04EmptyColumn()
TestG05Pixel255()
TestG06NegativeOffsets()
TestG07PositiveOffsets()
TestG08UnsortedAndSharedOffsets()
TestG09OverlappingPosts()
TestG10ZeroLengthPost()
TestG11ShortInputs()
TestG12InvalidDimensions()
TestG13TruncatedTable()
TestG14ColumnOffsetOob()
TestG15TruncatedPostHeader()
TestG16TruncatedPost()
TestG17MissingTerminator()
TestG18PostExceedsHeight()
TestG19GiantDimensions()
TestG20CorruptSecondColumn()
TestG21FailureThenSuccess()
TestG22InputFreed()
TestG23Canaries()
TestG24DecodeCycles()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
