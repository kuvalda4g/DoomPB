; -----------------------------------------------------------------------------
; DoomPB - framebuffer and presentation-math tests (M1-04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; All inputs are synthesized in memory. No window is opened, no Doom resource is
; required and no file is written. Exit code: 0 when every assertion passed,
; otherwise the number of failed assertions.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/Graphics/Palette.pbi"
XIncludeFile "../../src/Graphics/Patch.pbi"
XIncludeFile "../../src/Graphics/FrameBuffer.pbi"

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

Procedure.i FramebufferAllEqual(*Fb.FrameBuffer, Value.i)
  Protected i.q

  For i = 0 To *Fb\PixelCount - 1
    If PeekA(*Fb\Pixels + i) <> Value
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

Procedure.i BuffersEqual(*A.Byte, *B.Byte, Count.q)
  Protected i.q

  For i = 0 To Count - 1
    If PeekA(*A + i) <> PeekA(*B + i)
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Palette fixture
; ---------------------------------------------------------------------------

Procedure.i NewPaletteBytes(PaletteCount.i)
  Protected memory.i = AllocateMemory(PaletteCount * 768)

  If memory <> 0
    FillMemory(memory, PaletteCount * 768, 0)
  EndIf
  ProcedureReturn memory
EndProcedure

Procedure SetPaletteColor(*Memory.Byte, PaletteIndex.i, ColorIndex.i, R.i, G.i, B.i)
  Protected offset.i = PaletteIndex * 768 + ColorIndex * 3

  PokeA(*Memory + offset, R)
  PokeA(*Memory + offset + 1, G)
  PokeA(*Memory + offset + 2, B)
EndProcedure

; ---------------------------------------------------------------------------
; Patch fixture builders (synthetic Doom picture format)
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
; F01 - F13: framebuffer lifecycle and blitting
; ---------------------------------------------------------------------------

Procedure TestF01Create()
  BeginCase("F01", "Create a 320x200 indexed framebuffer")
  Protected fb.FrameBuffer

  Check(Bool(FrameBufferCreate(@fb, 320, 200)), "framebuffer creation succeeds")
  Check(Bool(fb\Width = 320 And fb\Height = 200), "dimensions are 320x200")
  Check(Bool(fb\PixelCount = 64000), "pixel count is 64000")
  Check(Bool(fb\Pixels <> 0), "index plane is allocated")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 0) = 0), "first pixel is readable")
  Check(Bool(FrameBufferGetPixel(@fb, 319, 199) = 0), "last pixel is readable")
  FrameBufferReset(@fb)
EndProcedure

Procedure TestF02ClearZero()
  BeginCase("F02", "Clear the framebuffer with index 0")
  Protected fb.FrameBuffer

  Check(Bool(FrameBufferCreate(@fb, 7, 5)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "clear with index 0 succeeds")
  Check(Bool(FramebufferAllEqual(@fb, 0)), "all 35 indices are 0")
  FrameBufferReset(@fb)
EndProcedure

Procedure TestF03Clear255()
  BeginCase("F03", "Clear with palette index 255")
  Protected fb.FrameBuffer

  Check(Bool(FrameBufferCreate(@fb, 7, 5)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 255)), "clear with index 255 succeeds")
  Check(Bool(FramebufferAllEqual(@fb, 255)), "all indices are 255")
  Check(Bool(FrameBufferGetPixel(@fb, 6, 4) = 255), "last pixel is 255, not transparent")
  FrameBufferReset(@fb)
EndProcedure

; Builds a 2x2 patch with row-major values A, B / C, D.
Procedure.i Build2x2Patch(A.s, B.s, C.s, D.s)
  Protected patch.ByteBuffer
  Protected column.ByteBuffer

  PBStart(@patch, 2, 2, 0, 0)
  BBInit(@column, 32)
  BBPost(@column, 0, A + C)
  BBTerm(@column)
  PBAddColumn(@patch, 0, @column)
  BBFree(@column)
  BBInit(@column, 32)
  BBPost(@column, 0, B + D)
  BBTerm(@column)
  PBAddColumn(@patch, 1, @column)
  BBFree(@column)
  ProcedureReturn patch\Data
EndProcedure

Procedure TestF04BlitOrigin()
  BeginCase("F04", "2x2 patch blit at the origin")
  Protected fb.FrameBuffer
  Protected image.PatchImage
  Protected raw.i = Build2x2Patch("01", "02", "03", "04")

  Check(Bool(raw <> 0), "patch buffer built")
  Check(Bool(PatchDecode(raw, 32, @image)), "synthetic patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "framebuffer cleared")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, 0, 0)), "blit succeeds")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 0) = 1 And FrameBufferGetPixel(@fb, 1, 0) = 2), "row 0 is placed correctly")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 1) = 3 And FrameBufferGetPixel(@fb, 1, 1) = 4), "row 1 is placed correctly")
  FrameBufferReset(@fb)
  PatchReset(@image)
  FreeMemory(raw)
EndProcedure

Procedure TestF05TransparentGap()
  BeginCase("F05", "Transparent patch pixels preserve the destination")
  Protected fb.FrameBuffer
  Protected image.PatchImage
  Protected patch.ByteBuffer
  Protected column.ByteBuffer
  Protected raw.i

  PBStart(@patch, 2, 2, 0, 0)
  BBInit(@column, 32)
  BBPost(@column, 0, "0A")
  BBTerm(@column)
  PBAddColumn(@patch, 0, @column)
  BBFree(@column)
  BBInit(@column, 32)
  BBPost(@column, 0, "0B0C")
  BBTerm(@column)
  PBAddColumn(@patch, 1, @column)
  BBFree(@column)
  raw = patch\Data

  Check(Bool(PatchDecode(raw, patch\Pos, @image)), "synthetic patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 77)), "framebuffer prefilled with 77")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, 0, 0)), "blit succeeds")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 0) = 10 And FrameBufferGetPixel(@fb, 1, 0) = 11), "covered pixels are copied")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 1) = 77), "transparent gap keeps the destination index")
  Check(Bool(FrameBufferGetPixel(@fb, 1, 1) = 12), "second column bottom is copied")
  FrameBufferReset(@fb)
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestF06Opaque255()
  BeginCase("F06", "Opaque source pixel index 255")
  Protected fb.FrameBuffer
  Protected image.PatchImage
  Protected patch.ByteBuffer
  Protected column.ByteBuffer
  Protected raw.i

  PBStart(@patch, 1, 1, 0, 0)
  BBInit(@column, 16)
  BBPost(@column, 0, "FF")
  BBTerm(@column)
  PBAddColumn(@patch, 0, @column)
  BBFree(@column)
  raw = patch\Data

  Check(Bool(PatchDecode(raw, patch\Pos, @image)), "synthetic patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 1, 1)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 7)), "framebuffer prefilled with 7")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, 0, 0)), "blit succeeds")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 0) = 255), "index 255 overwrote the destination")
  FrameBufferReset(@fb)
  PatchReset(@image)
  BBFree(@patch)
EndProcedure

Procedure TestF07OverlappingBlits()
  BeginCase("F07", "Overlapping blits: later opaque pixels win, masked pixels do not")
  Protected fb.FrameBuffer
  Protected first.PatchImage
  Protected second.PatchImage
  Protected firstRaw.i = Build2x2Patch("01", "02", "03", "04")
  Protected patch.ByteBuffer
  Protected column.ByteBuffer
  Protected secondRaw.i

  PBStart(@patch, 2, 2, 0, 0)
  BBInit(@column, 32)
  BBPost(@column, 1, "09")
  BBTerm(@column)
  PBAddColumn(@patch, 0, @column)
  BBFree(@column)
  BBInit(@column, 16)
  BBTerm(@column)
  PBAddColumn(@patch, 1, @column)
  BBFree(@column)
  secondRaw = patch\Data

  Check(Bool(PatchDecode(firstRaw, 32, @first)), "first patch decodes")
  Check(Bool(PatchDecode(secondRaw, patch\Pos, @second)), "second patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "framebuffer cleared")
  Check(Bool(FrameBufferBlitPatch(@fb, @first, 0, 0)), "first blit succeeds")
  Check(Bool(FrameBufferBlitPatch(@fb, @second, 0, 0)), "second blit succeeds")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 0) = 1), "uncovered pixel keeps the first value")
  Check(Bool(FrameBufferGetPixel(@fb, 1, 0) = 2), "transparent second-column pixel is not overwritten")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 1) = 9), "later opaque pixel overwrites the first value")
  Check(Bool(FrameBufferGetPixel(@fb, 1, 1) = 4), "lower-right transparent pixel keeps the first value")
  FrameBufferReset(@fb)
  PatchReset(@first)
  PatchReset(@second)
  FreeMemory(firstRaw)
  BBFree(@patch)
EndProcedure

Procedure TestF08LeftTopClip()
  BeginCase("F08", "Left/top clipping")
  Protected fb.FrameBuffer
  Protected image.PatchImage
  Protected raw.i = Build2x2Patch("01", "02", "03", "04")

  Check(Bool(PatchDecode(raw, 32, @image)), "synthetic patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "framebuffer cleared")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, -1, -1)), "clipped blit succeeds")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 0) = 4), "bottom-right source pixel survives at the origin")
  Check(Bool(FrameBufferGetPixel(@fb, 1, 0) = 0), "top-right destination is unchanged")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 1) = 0), "bottom-left destination is unchanged")
  Check(Bool(FrameBufferGetPixel(@fb, 1, 1) = 0), "outside the clipped patch stays unchanged")
  FrameBufferReset(@fb)
  PatchReset(@image)
  FreeMemory(raw)
EndProcedure

Procedure TestF09RightBottomClip()
  BeginCase("F09", "Right/bottom clipping")
  Protected fb.FrameBuffer
  Protected image.PatchImage
  Protected raw.i = Build2x2Patch("01", "02", "03", "04")

  Check(Bool(PatchDecode(raw, 32, @image)), "synthetic patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "framebuffer cleared")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, 1, 1)), "clipped blit succeeds")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 0) = 0 And FrameBufferGetPixel(@fb, 1, 0) = 0), "upper row is unchanged")
  Check(Bool(FrameBufferGetPixel(@fb, 0, 1) = 0), "lower-left is unchanged")
  Check(Bool(FrameBufferGetPixel(@fb, 1, 1) = 1), "first source pixel survives at the corner")
  FrameBufferReset(@fb)
  PatchReset(@image)
  FreeMemory(raw)
EndProcedure

Procedure TestF10FullyOffscreen()
  BeginCase("F10", "Entirely offscreen blit is a safe no-op")
  Protected fb.FrameBuffer
  Protected image.PatchImage
  Protected raw.i = Build2x2Patch("01", "02", "03", "04")

  Check(Bool(PatchDecode(raw, 32, @image)), "synthetic patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 3, 3)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 42)), "framebuffer prefilled with 42")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, -10, -10)), "negative offscreen blit succeeds")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, 100, 100)), "positive offscreen blit succeeds")
  Check(Bool(FramebufferAllEqual(@fb, 42)), "destination is untouched")
  FrameBufferReset(@fb)
  PatchReset(@image)
  FreeMemory(raw)
EndProcedure

Procedure TestF11NullArguments()
  BeginCase("F11", "Null patch/framebuffer arguments")
  Protected fb.FrameBuffer
  Protected image.PatchImage
  Protected raw.i = Build2x2Patch("01", "02", "03", "04")

  Check(Bool(PatchDecode(raw, 32, @image)), "synthetic patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferBlitPatch(@fb, 0, 0, 0) = #False), "null patch is rejected")
  Check(Bool(FrameBufferBlitPatch(0, @image, 0, 0) = #False), "null framebuffer is rejected")
  Check(Bool(FrameBufferClear(0, 0) = #False), "clear on null framebuffer is rejected")
  Check(Bool(FrameBufferGetPixel(0, 0, 0) = -1), "getter on null framebuffer returns -1")
  FrameBufferReset(@fb)
  PatchReset(@image)
  FreeMemory(raw)
EndProcedure

Procedure TestF12InvalidDimensions()
  BeginCase("F12", "Invalid dimensions, overflow and pixel budget")
  Protected fb.FrameBuffer

  Check(Bool(FrameBufferCreate(@fb, 0, 10) = #False), "zero width is rejected")
  Check(Bool(FrameBufferCreate(@fb, 10, 0) = #False), "zero height is rejected")
  Check(Bool(FrameBufferCreate(@fb, -1, 10) = #False), "negative width is rejected")
  Check(Bool(FrameBufferCreate(@fb, 10, -1) = #False), "negative height is rejected")
  Check(Bool(FrameBufferCreate(@fb, 4097, 1) = #False), "width above the dimension cap is rejected")
  Check(Bool(FrameBufferCreate(@fb, 1, 4097) = #False), "height above the dimension cap is rejected")
  Check(Bool(FrameBufferCreate(@fb, 4096, 4097) = #False), "pixel budget is enforced")
  Check(Bool(FrameBufferCreate(@fb, 2147483647, 2) = #False), "huge dimension is rejected before multiplication")
  Check(Bool(fb\Pixels = 0 And fb\PixelCount = 0), "failed creation leaves an empty framebuffer")

  Check(Bool(FrameBufferCreate(@fb, 4, 4)), "valid framebuffer is created")
  Check(Bool(FrameBufferCreate(@fb, 0, 6) = #False), "failed recreation is rejected")
  Check(Bool(fb\Pixels = 0), "failed recreation clears the previous framebuffer")
EndProcedure

Procedure TestF13RepeatedLifecycle()
  BeginCase("F13", "Repeated create/reset lifecycle")
  Protected fb.FrameBuffer

  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "first create succeeds")
  Check(Bool(FrameBufferSetPixel(@fb, 1, 1, 5)), "pixel write succeeds")
  Check(Bool(FrameBufferReset(@fb)), "reset succeeds")
  Check(Bool(fb\Width = 0 And fb\Height = 0 And fb\PixelCount = 0 And fb\Pixels = 0), "reset clears all fields")
  Check(Bool(FrameBufferReset(@fb)), "second reset is idempotent")
  Check(Bool(FrameBufferCreate(@fb, 3, 3)), "second create succeeds")
  Check(Bool(fb\PixelCount = 9), "second create has 9 pixels")
  Check(Bool(FrameBufferReset(@fb)), "second reset succeeds")
  Check(Bool(FrameBufferCreate(@fb, 1, 1)), "third create succeeds")
  Check(Bool(fb\PixelCount = 1), "third create has 1 pixel")
  FrameBufferReset(@fb)
EndProcedure

; ---------------------------------------------------------------------------
; F14 - F20: palette conversion
; ---------------------------------------------------------------------------

Procedure TestF14PaletteZeroConversion()
  BeginCase("F14", "Palette 0 conversion with known RGB")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(8)

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  SetPaletteColor(paletteBytes, 0, 0, 17, 93, 201)
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 1)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "framebuffer cleared to index 0")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, rgba, 8)), "conversion succeeds")
  Check(Bool(PeekA(rgba) = 17 And PeekA(rgba + 1) = 93 And PeekA(rgba + 2) = 201), "RGB channels are exact")
  Check(Bool(PeekA(rgba + 3) = 255), "alpha is 255")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF15ChannelOrder()
  BeginCase("F15", "Asymmetric channel order (no R/B swap)")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(4)

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  SetPaletteColor(paletteBytes, 0, 0, 17, 93, 201)
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 1, 1)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, rgba, 4)), "conversion succeeds")
  Check(Bool(PeekA(rgba) = 17), "R byte comes first")
  Check(Bool(PeekA(rgba + 1) = 93), "G byte comes second")
  Check(Bool(PeekA(rgba + 2) = 201), "B byte comes third")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF16Index255Conversion()
  BeginCase("F16", "Palette index 255 conversion")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(4)

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  SetPaletteColor(paletteBytes, 0, 255, 4, 5, 6)
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 1, 1)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 255)), "framebuffer cleared to index 255")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, rgba, 4)), "conversion succeeds")
  Check(Bool(PeekA(rgba) = 4 And PeekA(rgba + 1) = 5 And PeekA(rgba + 2) = 6), "color 255 is valid")
  Check(Bool(PeekA(rgba + 3) = 255), "index 255 is opaque in the output")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF17PaletteSelection()
  BeginCase("F17", "Only the requested palette is used")
  Protected paletteBytes.i = NewPaletteBytes(2)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(4)

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  SetPaletteColor(paletteBytes, 0, 0, 10, 20, 30)
  SetPaletteColor(paletteBytes, 1, 0, 40, 50, 60)
  Check(Bool(PaletteDecode(paletteBytes, 2 * 768, @pal)), "two palettes decode")
  Check(Bool(FrameBufferCreate(@fb, 1, 1)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, rgba, 4)), "palette 0 conversion succeeds")
  Check(Bool(PeekA(rgba) = 10 And PeekA(rgba + 1) = 20 And PeekA(rgba + 2) = 30), "palette 0 values are used")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 1, rgba, 4)), "palette 1 conversion succeeds")
  Check(Bool(PeekA(rgba) = 40 And PeekA(rgba + 1) = 50 And PeekA(rgba + 2) = 60), "palette 1 values are used")
  Check(Bool(PeekA(rgba + 1) <> 20), "no cross-palette mixing")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF18InvalidPaletteArguments()
  BeginCase("F18", "Invalid palette index and null pointers")
  Protected paletteBytes.i = NewPaletteBytes(2)
  Protected pal.PaletteSet
  Protected empty.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(8)

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  FillMemory(rgba, 8, $CC)
  Check(Bool(PaletteDecode(paletteBytes, 2 * 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 1)), "framebuffer creation succeeds")

  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 2, rgba, 8) = #False), "palette index == count is rejected")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, 0, 8) = #False), "null RGBA destination is rejected")
  Check(Bool(FrameBufferConvertRGBA(@fb, @empty, 0, rgba, 8) = #False), "uninitialized palette is rejected")
  Check(Bool(PeekA(rgba) = $CC And PeekA(rgba + 7) = $CC), "failed conversions leave the destination untouched")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF19CapacityBoundary()
  BeginCase("F19", "Exact and undersized RGBA destination capacity")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected buffer.i = AllocateMemory(20)

  Check(Bool(paletteBytes <> 0 And buffer <> 0), "fixtures allocated")
  If paletteBytes = 0 Or buffer = 0
    ProcedureReturn
  EndIf
  SetPaletteColor(paletteBytes, 0, 0, 1, 2, 3)
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "framebuffer cleared")

  FillMemory(buffer, 20, $CC)
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, buffer + 2, 16)), "exact 16-byte capacity succeeds")
  Check(Bool(PeekA(buffer) = $CC And PeekA(buffer + 1) = $CC), "leading guards are intact")
  Check(Bool(PeekA(buffer + 18) = $CC And PeekA(buffer + 19) = $CC), "trailing guards are intact")
  Check(Bool(PeekA(buffer + 2) = 1 And PeekA(buffer + 3) = 2 And PeekA(buffer + 4) = 3), "converted data starts at the destination")

  FillMemory(buffer, 20, $CC)
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, buffer + 2, 15) = #False), "15-byte capacity is rejected")
  Check(Bool(PeekA(buffer) = $CC And PeekA(buffer + 19) = $CC), "undersized conversion does not touch guards")
  Check(Bool(PeekA(buffer + 2) = $CC And PeekA(buffer + 17) = $CC), "undersized conversion writes nothing")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(buffer)
EndProcedure

Procedure TestF20EdgeAndRowBoundary()
  BeginCase("F20", "First/last pixels and row boundaries")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(3 * 2 * 4)
  Protected X.i
  Protected Y.i

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  For X = 0 To 255
    SetPaletteColor(paletteBytes, 0, X, X, 10, 20)
  Next
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 3, 2)), "framebuffer creation succeeds")
  For Y = 0 To 1
    For X = 0 To 2
      Check(Bool(FrameBufferSetPixel(@fb, X, Y, 1 + Y * 3 + X)), "pixel " + Str(X) + "," + Str(Y) + " is writable")
    Next
  Next
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, rgba, 24)), "conversion succeeds")
  Check(Bool(PeekA(rgba) = 1), "first pixel index is 1")
  Check(Bool(PeekA(rgba + 2 * 4) = 3), "end of the first row is index 3")
  Check(Bool(PeekA(rgba + 3 * 4) = 4), "start of the second row is index 4")
  Check(Bool(PeekA(rgba + 5 * 4) = 6), "last pixel index is 6")
  Check(Bool(PeekA(rgba + 5 * 4 + 3) = 255), "last alpha is 255")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

; ---------------------------------------------------------------------------
; F21 - F24: nearest-neighbour scaling and end-to-end
; ---------------------------------------------------------------------------

Procedure TestF21NearestNeighbor()
  BeginCase("F21", "3x nearest-neighbour block mapping")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(6 * 6 * 4)
  Protected X.i
  Protected Y.i
  Protected source.i
  Protected red.i
  Protected expected.i
  Protected wrong.i = 0

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  For X = 0 To 255
    SetPaletteColor(paletteBytes, 0, X, X * 10, 0, 0)
  Next
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferSetPixel(@fb, 0, 0, 1)), "source pixel 1 written")
  Check(Bool(FrameBufferSetPixel(@fb, 1, 0, 2)), "source pixel 2 written")
  Check(Bool(FrameBufferSetPixel(@fb, 0, 1, 3)), "source pixel 3 written")
  Check(Bool(FrameBufferSetPixel(@fb, 1, 1, 4)), "source pixel 4 written")

  Check(Bool(FrameBufferScaleNearestRGBA(@fb, @pal, 0, 3, rgba, 6 * 6 * 4)), "3x scaling succeeds")
  For Y = 0 To 5
    For X = 0 To 5
      source = (Y / 3) * 2 + (X / 3)
      expected = (source + 1) * 10
      red = PeekA(rgba + (Y * 6 + X) * 4)
      If red <> expected
        wrong + 1
      EndIf
    Next
  Next
  Check(Bool(wrong = 0), "every source pixel becomes a 3x3 block with no interpolation")
  Check(Bool(PeekA(rgba + 3 * 4) = 20), "block boundary at x=3 uses source column 1")
  Check(Bool(PeekA(rgba + (3 * 6) * 4) = 30), "block boundary at y=3 uses source row 1")
  Check(Bool(PeekA(rgba + (5 * 6 + 5) * 4) = 40), "bottom-right block uses source pixel 4")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF22InvalidScale()
  BeginCase("F22", "Invalid scale and output-size guards")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected big.FrameBuffer
  Protected rgba.i = AllocateMemory(8)

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 3, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferScaleNearestRGBA(@fb, @pal, 0, 0, rgba, 8) = #False), "scale 0 is rejected")
  Check(Bool(FrameBufferScaleNearestRGBA(@fb, @pal, 0, -1, rgba, 8) = #False), "negative scale is rejected")
  Check(Bool(FrameBufferScaleNearestRGBA(@fb, @pal, 0, 17, rgba, 8) = #False), "scale above the cap is rejected")
  Check(Bool(FrameBufferScaleNearestRGBA(@fb, @pal, 0, 2, rgba, 8) = #False), "undersized scaled capacity is rejected")
  Check(Bool(FrameBufferScaleNearestRGBA(@fb, @pal, 0, 2, 0, 8) = #False), "null scaled destination is rejected")
  FrameBufferReset(@fb)

  Check(Bool(FrameBufferCreate(@big, 4096, 4096)), "large source framebuffer is created")
  Check(Bool(FrameBufferScaleNearestRGBA(@big, @pal, 0, 2, rgba, 8) = #False), "scaled pixel budget is enforced before allocation")
  FrameBufferReset(@big)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF23FailureThenSuccess()
  BeginCase("F23", "Failure then successful reuse")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected fb.FrameBuffer
  Protected rgba.i = AllocateMemory(8)

  Check(Bool(paletteBytes <> 0 And rgba <> 0), "fixtures allocated")
  If paletteBytes = 0 Or rgba = 0
    ProcedureReturn
  EndIf
  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 1)), "framebuffer creation succeeds")

  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, rgba, 4) = #False), "undersized conversion fails")
  Check(Bool(FrameBufferLastError() <> ""), "failure records an error")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, rgba, 8)), "subsequent conversion succeeds")
  Check(Bool(FrameBufferLastError() = ""), "success clears the error")

  Check(Bool(FrameBufferCreate(@fb, 0, 1) = #False), "invalid recreation fails")
  Check(Bool(FrameBufferCreate(@fb, 1, 1)), "valid recreation succeeds")
  Check(Bool(FrameBufferLastError() = ""), "successful recreation clears the error")
  FrameBufferReset(@fb)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(rgba)
EndProcedure

Procedure TestF24EndToEnd()
  BeginCase("F24", "End-to-end palette + patch + framebuffer + RGBA")
  Protected paletteBytes.i = NewPaletteBytes(1)
  Protected pal.PaletteSet
  Protected image.PatchImage
  Protected raw.i = Build2x2Patch("00", "01", "02", "03")
  Protected fb.FrameBuffer
  Protected first.i = AllocateMemory(16)
  Protected second.i = AllocateMemory(16)
  Protected expected.i = AllocateMemory(16)
  Protected i.i

  Check(Bool(paletteBytes <> 0 And first <> 0 And second <> 0 And expected <> 0), "fixtures allocated")
  If paletteBytes = 0 Or first = 0 Or second = 0 Or expected = 0
    ProcedureReturn
  EndIf
  SetPaletteColor(paletteBytes, 0, 0, 1, 2, 3)
  SetPaletteColor(paletteBytes, 0, 1, 4, 5, 6)
  SetPaletteColor(paletteBytes, 0, 2, 7, 8, 9)
  SetPaletteColor(paletteBytes, 0, 3, 10, 11, 12)

  Check(Bool(PaletteDecode(paletteBytes, 768, @pal)), "palette decodes")
  Check(Bool(PatchDecode(raw, 32, @image)), "patch decodes")
  Check(Bool(FrameBufferCreate(@fb, 2, 2)), "framebuffer creation succeeds")
  Check(Bool(FrameBufferClear(@fb, 0)), "framebuffer cleared")
  Check(Bool(FrameBufferBlitPatch(@fb, @image, 0, 0)), "patch is composited")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, first, 16)), "first conversion succeeds")
  Check(Bool(FrameBufferConvertRGBA(@fb, @pal, 0, second, 16)), "second conversion succeeds")
  Check(Bool(BuffersEqual(first, second, 16)), "conversion is deterministic")

  FillMemory(expected, 16, 0)
  PokeA(expected, 1): PokeA(expected + 1, 2): PokeA(expected + 2, 3): PokeA(expected + 3, 255)
  PokeA(expected + 4, 4): PokeA(expected + 5, 5): PokeA(expected + 6, 6): PokeA(expected + 7, 255)
  PokeA(expected + 8, 7): PokeA(expected + 9, 8): PokeA(expected + 10, 9): PokeA(expected + 11, 255)
  PokeA(expected + 12, 10): PokeA(expected + 13, 11): PokeA(expected + 14, 12): PokeA(expected + 15, 255)
  Check(Bool(BuffersEqual(first, expected, 16)), "row-major RGBA matches the expected pixels")
  For i = 0 To 3
    Check(Bool(FrameBufferGetPixel(@fb, i % 2, i / 2) = i), "framebuffer pixel " + Str(i) + " is correct")
  Next

  FrameBufferReset(@fb)
  PatchReset(@image)
  PaletteReset(@pal)
  FreeMemory(paletteBytes)
  FreeMemory(first)
  FreeMemory(second)
  FreeMemory(expected)
  FreeMemory(raw)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB framebuffer/presentation tests (M1-04)")

TestF01Create()
TestF02ClearZero()
TestF03Clear255()
TestF04BlitOrigin()
TestF05TransparentGap()
TestF06Opaque255()
TestF07OverlappingBlits()
TestF08LeftTopClip()
TestF09RightBottomClip()
TestF10FullyOffscreen()
TestF11NullArguments()
TestF12InvalidDimensions()
TestF13RepeatedLifecycle()
TestF14PaletteZeroConversion()
TestF15ChannelOrder()
TestF16Index255Conversion()
TestF17PaletteSelection()
TestF18InvalidPaletteArguments()
TestF19CapacityBoundary()
TestF20EdgeAndRowBoundary()
TestF21NearestNeighbor()
TestF22InvalidScale()
TestF23FailureThenSuccess()
TestF24EndToEnd()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
