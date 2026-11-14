; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Platform-independent indexed software framebuffer.
;
; The authoritative image is a contiguous row-major plane of Width * Height
; 8-bit palette indices (classic target 320 x 200). Nothing in this module
; knows about windows, images or operating-system graphics APIs.
;
; Ownership:
;   - FrameBuffer is caller-owned and must be zero-initialized once, for
;     example with ClearStructure(@fb, FrameBuffer).
;   - FrameBufferCreate owns the pixel plane and replaces any previous one.
;   - FrameBufferReset releases the plane and leaves the structure reusable.
;     It is idempotent; failed creation leaves an empty framebuffer.
;   - Patch blits copy through the patch opacity mask; masked pixels leave the
;     destination unchanged. LeftOffset/TopOffset are metadata and are not
;     applied implicitly.
;   - Conversion writes a caller-owned buffer in canonical row-major RGBA
;     order (R, G, B, 255). No window or WAD call is made here.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_FRAMEBUFFER_PBI, #PB_Constant) = 0

#DOOMPB_FRAMEBUFFER_PBI = 1

XIncludeFile "Palette.pbi"
XIncludeFile "Patch.pbi"

#FRAMEBUFFER_MaxDimension    = 4096
#FRAMEBUFFER_MaxPixels       = 16777216
#FRAMEBUFFER_MaxScale        = 16
#FRAMEBUFFER_MaxOutputPixels = 16777216

#FRAMEBUFFER_Magic           = $46524D31

Structure FrameBuffer
  Magic.l
  Width.l
  Height.l
  PixelCount.q
  *Pixels.Byte
EndStructure

Global gFrameBuffer_LastError.s = ""

Procedure FrameBufferSetError(Message.s)
  gFrameBuffer_LastError = Message
EndProcedure

Procedure.s FrameBufferLastError()
  ProcedureReturn gFrameBuffer_LastError
EndProcedure

; Releases the index plane and clears all metadata. The structure remains
; allocated because the caller owns it.
Procedure.i FrameBufferReset(*FrameBuffer.FrameBuffer)
  If *FrameBuffer = 0
    FrameBufferSetError("Framebuffer pointer is null.")
    ProcedureReturn #False
  EndIf

  If *FrameBuffer\Magic = #FRAMEBUFFER_Magic
    If *FrameBuffer\Pixels <> 0
      FreeMemory(*FrameBuffer\Pixels)
    EndIf
  EndIf

  *FrameBuffer\Magic = 0
  *FrameBuffer\Width = 0
  *FrameBuffer\Height = 0
  *FrameBuffer\PixelCount = 0
  *FrameBuffer\Pixels = 0
  gFrameBuffer_LastError = ""
  ProcedureReturn #True
EndProcedure

; Creates (or recreates) a framebuffer. New pixels are zero-initialized.
Procedure.i FrameBufferCreate(*FrameBuffer.FrameBuffer, Width.i, Height.i)
  Protected pixelCount.q
  Protected pixels.i = 0

  If *FrameBuffer = 0
    FrameBufferSetError("Framebuffer pointer is null.")
    ProcedureReturn #False
  EndIf

  FrameBufferReset(*FrameBuffer)

  If Width <= 0 Or Width > #FRAMEBUFFER_MaxDimension
    FrameBufferSetError("Framebuffer width is invalid: " + Str(Width) + " (allowed 1.." + Str(#FRAMEBUFFER_MaxDimension) + ").")
    ProcedureReturn #False
  EndIf
  If Height <= 0 Or Height > #FRAMEBUFFER_MaxDimension
    FrameBufferSetError("Framebuffer height is invalid: " + Str(Height) + " (allowed 1.." + Str(#FRAMEBUFFER_MaxDimension) + ").")
    ProcedureReturn #False
  EndIf

  pixelCount = Int(Width) * Int(Height)
  If pixelCount > #FRAMEBUFFER_MaxPixels
    FrameBufferSetError("Framebuffer pixel budget exceeded: " + Str(pixelCount) + " (limit " + Str(#FRAMEBUFFER_MaxPixels) + ").")
    ProcedureReturn #False
  EndIf

  pixels = AllocateMemory(pixelCount)
  If pixels = 0
    FrameBufferSetError("Out of memory while allocating the framebuffer.")
    ProcedureReturn #False
  EndIf
  FillMemory(pixels, pixelCount, 0)

  *FrameBuffer\Magic = #FRAMEBUFFER_Magic
  *FrameBuffer\Width = Width
  *FrameBuffer\Height = Height
  *FrameBuffer\PixelCount = pixelCount
  *FrameBuffer\Pixels = pixels
  gFrameBuffer_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i FrameBufferClear(*FrameBuffer.FrameBuffer, PaletteIndex.i)
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    FrameBufferSetError("Framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If PaletteIndex < 0 Or PaletteIndex > 255
    FrameBufferSetError("Clear palette index is out of range: " + Str(PaletteIndex) + ".")
    ProcedureReturn #False
  EndIf

  FillMemory(*FrameBuffer\Pixels, *FrameBuffer\PixelCount, PaletteIndex)
  gFrameBuffer_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i FrameBufferSetPixel(*FrameBuffer.FrameBuffer, X.i, Y.i, PaletteIndex.i)
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    FrameBufferSetError("Framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If X < 0 Or Y < 0 Or X >= *FrameBuffer\Width Or Y >= *FrameBuffer\Height
    FrameBufferSetError("Framebuffer coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn #False
  EndIf
  If PaletteIndex < 0 Or PaletteIndex > 255
    FrameBufferSetError("Pixel palette index is out of range: " + Str(PaletteIndex) + ".")
    ProcedureReturn #False
  EndIf

  PokeA(*FrameBuffer\Pixels + Int(Y) * Int(*FrameBuffer\Width) + Int(X), PaletteIndex)
  gFrameBuffer_LastError = ""
  ProcedureReturn #True
EndProcedure

; Returns the palette index at (X, Y), or -1 for an invalid framebuffer or
; coordinate (palette indices themselves are always 0..255).
Procedure.i FrameBufferGetPixel(*FrameBuffer.FrameBuffer, X.i, Y.i)
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    FrameBufferSetError("Framebuffer is not initialized.")
    ProcedureReturn -1
  EndIf
  If X < 0 Or Y < 0 Or X >= *FrameBuffer\Width Or Y >= *FrameBuffer\Height
    FrameBufferSetError("Framebuffer coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn -1
  EndIf

  ProcedureReturn PeekA(*FrameBuffer\Pixels + Int(Y) * Int(*FrameBuffer\Width) + Int(X))
EndProcedure

; Composites a decoded patch whose top-left corner is placed at (X, Y).
; Pixels with mask=1 are copied; mask=0 leaves the destination unchanged.
; All four edges are clipped. A fully offscreen blit is a successful no-op.
Procedure.i FrameBufferBlitPatch(*FrameBuffer.FrameBuffer, *Patch.PatchImage, X.i, Y.i)
  Protected sourceX0.i
  Protected sourceY0.i
  Protected sourceX1.i
  Protected sourceY1.i
  Protected sourceX.i
  Protected sourceY.i
  Protected destinationX.i
  Protected destinationY.i
  Protected sourceIndex.q
  Protected destinationIndex.q

  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    FrameBufferSetError("Framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Patch = 0 Or *Patch\Magic <> #PATCH_Magic Or *Patch\Pixels = 0 Or *Patch\Mask = 0
    FrameBufferSetError("Patch image is not initialized.")
    ProcedureReturn #False
  EndIf

  sourceX0 = 0
  sourceY0 = 0
  sourceX1 = *Patch\Width
  sourceY1 = *Patch\Height

  If X < 0
    sourceX0 = -X
  EndIf
  If Y < 0
    sourceY0 = -Y
  EndIf
  If X + *Patch\Width > *FrameBuffer\Width
    sourceX1 = *FrameBuffer\Width - X
  EndIf
  If Y + *Patch\Height > *FrameBuffer\Height
    sourceY1 = *FrameBuffer\Height - Y
  EndIf

  If sourceX1 <= sourceX0 Or sourceY1 <= sourceY0
    gFrameBuffer_LastError = ""
    ProcedureReturn #True
  EndIf

  For sourceY = sourceY0 To sourceY1 - 1
    destinationY = Y + sourceY
    For sourceX = sourceX0 To sourceX1 - 1
      sourceIndex = Int(sourceY) * Int(*Patch\Width) + Int(sourceX)
      If PeekA(*Patch\Mask + sourceIndex) = 1
        destinationX = X + sourceX
        destinationIndex = Int(destinationY) * Int(*FrameBuffer\Width) + Int(destinationX)
        PokeA(*FrameBuffer\Pixels + destinationIndex, PeekA(*Patch\Pixels + sourceIndex))
      EndIf
    Next
  Next

  gFrameBuffer_LastError = ""
  ProcedureReturn #True
EndProcedure

; Builds a packed 0x00BBGGRR table for all 256 palette entries.
Procedure.i FrameBufferBuildColorTable(*Palette.PaletteSet, PaletteIndex.i, *Table.Long)
  Protected color.i
  Protected r.i
  Protected g.i
  Protected b.i

  If *Palette = 0 Or *Table = 0
    FrameBufferSetError("Palette or color-table pointer is null.")
    ProcedureReturn #False
  EndIf

  For color = 0 To 255
    If PaletteGetRGB(*Palette, PaletteIndex, color, @r, @g, @b) = #False
      FrameBufferSetError("Cannot read the palette: " + PaletteLastError())
      ProcedureReturn #False
    EndIf
    PokeL(*Table + color * 4, r | (g << 8) | (b << 16))
  Next
  ProcedureReturn #True
EndProcedure

; Converts the whole framebuffer to canonical row-major RGBA bytes
; (R, G, B, 255) using the requested palette. Capacity is in bytes and must be
; at least PixelCount * 4.
Procedure.i FrameBufferConvertRGBA(*FrameBuffer.FrameBuffer, *Palette.PaletteSet, PaletteIndex.i, *Destination.Byte, Capacity.q)
  Protected Dim colors.l(255)
  Protected required.q
  Protected i.q
  Protected color.l
  Protected destination.i

  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    FrameBufferSetError("Framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Destination = 0
    FrameBufferSetError("RGBA destination pointer is null.")
    ProcedureReturn #False
  EndIf

  required = *FrameBuffer\PixelCount * 4
  If Capacity < required
    FrameBufferSetError("RGBA destination capacity is too small: " + Str(Capacity) + " < " + Str(required) + ".")
    ProcedureReturn #False
  EndIf

  If FrameBufferBuildColorTable(*Palette, PaletteIndex, @colors(0)) = #False
    ProcedureReturn #False
  EndIf

  destination = *Destination
  For i = 0 To *FrameBuffer\PixelCount - 1
    color = colors(PeekA(*FrameBuffer\Pixels + i))
    PokeA(destination, color & $FF)
    PokeA(destination + 1, (color >> 8) & $FF)
    PokeA(destination + 2, (color >> 16) & $FF)
    PokeA(destination + 3, $FF)
    destination + 4
  Next

  gFrameBuffer_LastError = ""
  ProcedureReturn #True
EndProcedure

; Converts and scales with exact nearest-neighbor mapping: every source pixel
; becomes a Scale x Scale block. Output is canonical RGBA. No interpolation.
Procedure.i FrameBufferScaleNearestRGBA(*FrameBuffer.FrameBuffer, *Palette.PaletteSet, PaletteIndex.i, Scale.i, *Destination.Byte, Capacity.q)
  Protected Dim colors.l(255)
  Protected outputWidth.q
  Protected outputHeight.q
  Protected outputPixels.q
  Protected required.q
  Protected sourceRow.q
  Protected outputRow.q
  Protected X.q
  Protected Y.q
  Protected color.l
  Protected destination.i

  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    FrameBufferSetError("Framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Destination = 0
    FrameBufferSetError("RGBA destination pointer is null.")
    ProcedureReturn #False
  EndIf
  If Scale <= 0 Or Scale > #FRAMEBUFFER_MaxScale
    FrameBufferSetError("Scale is out of range: " + Str(Scale) + " (allowed 1.." + Str(#FRAMEBUFFER_MaxScale) + ").")
    ProcedureReturn #False
  EndIf

  outputWidth = Int(*FrameBuffer\Width) * Int(Scale)
  outputHeight = Int(*FrameBuffer\Height) * Int(Scale)
  outputPixels = outputWidth * outputHeight
  If outputWidth > #FRAMEBUFFER_MaxDimension * #FRAMEBUFFER_MaxScale Or outputHeight > #FRAMEBUFFER_MaxDimension * #FRAMEBUFFER_MaxScale
    FrameBufferSetError("Scaled output dimensions are too large.")
    ProcedureReturn #False
  EndIf
  If outputPixels > #FRAMEBUFFER_MaxOutputPixels
    FrameBufferSetError("Scaled output pixel budget exceeded: " + Str(outputPixels) + " (limit " + Str(#FRAMEBUFFER_MaxOutputPixels) + ").")
    ProcedureReturn #False
  EndIf

  required = outputPixels * 4
  If Capacity < required
    FrameBufferSetError("Scaled RGBA capacity is too small: " + Str(Capacity) + " < " + Str(required) + ".")
    ProcedureReturn #False
  EndIf

  If FrameBufferBuildColorTable(*Palette, PaletteIndex, @colors(0)) = #False
    ProcedureReturn #False
  EndIf

  destination = *Destination
  For Y = 0 To outputHeight - 1
    sourceRow = (Y / Scale) * *FrameBuffer\Width
    outputRow = Y * outputWidth
    For X = 0 To outputWidth - 1
      color = colors(PeekA(*FrameBuffer\Pixels + sourceRow + (X / Scale)))
      PokeA(destination + (outputRow + X) * 4, color & $FF)
      PokeA(destination + (outputRow + X) * 4 + 1, (color >> 8) & $FF)
      PokeA(destination + (outputRow + X) * 4 + 2, (color >> 16) & $FF)
      PokeA(destination + (outputRow + X) * 4 + 3, $FF)
    Next
  Next

  gFrameBuffer_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
