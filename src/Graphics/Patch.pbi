; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Classic Doom picture/patch decoder.
;
;   patch_t:  width, height, leftoffset, topoffset (int16, the offsets signed)
;             columnofs[width] (uint32, relative to the start of the patch)
;   column:   posts followed by a 0xFF topdelta terminator
;   post:     topdelta u8, length u8, unused u8, pixels[length], unused u8
;
; Output is an 8-bit row-major palette-index plane plus a separate opaque mask
; (0 = transparent, 1 = covered by a post). Pixel 255 is an ordinary opaque
; palette index; 0xFF terminates a column only in the topdelta position.
; Posts are applied in source order, so a later overlapping post overwrites an
; earlier one. This is vanilla Doom behaviour; tall-patch relative topdelta
; semantics are intentionally not implemented.
;
; Ownership:
;   - PatchImage is caller-owned and must be zero-initialized once, for example
;     with ClearStructure(@img, PatchImage).
;   - PatchDecode() owns both planes and replaces any previous ones.
;   - PatchReset() releases both planes and leaves the structure reusable.
;   - A failed decode releases all partial allocations and leaves the result
;     empty (Magic cleared). The decoded image never points into the source
;     buffer, so the input may be freed immediately after a successful decode.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PATCH_PBI, #PB_Constant) = 0

#DOOMPB_PATCH_PBI = 1

XIncludeFile "../Core/Endian.pbi"

#PATCH_HeaderSize        = 8
#PATCH_ColumnEntrySize   = 4
#PATCH_MaxDimension      = 4096
#PATCH_MaxPixels         = 16777216

#PATCH_Magic             = $50415431

Structure PatchImage
  Magic.l
  Width.l
  Height.l
  LeftOffset.l
  TopOffset.l
  PixelCount.q
  *Pixels.Byte
  *Mask.Byte
EndStructure

Global gPatch_LastError.s = ""

Procedure PatchSetError(Message.s)
  gPatch_LastError = Message
EndProcedure

Procedure.s PatchLastError()
  ProcedureReturn gPatch_LastError
EndProcedure

Procedure.i PatchReset(*Image.PatchImage)
  If *Image = 0
    PatchSetError("Patch image pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Image\Magic = #PATCH_Magic
    If *Image\Pixels <> 0
      FreeMemory(*Image\Pixels)
    EndIf
    If *Image\Mask <> 0
      FreeMemory(*Image\Mask)
    EndIf
  EndIf

  *Image\Magic = 0
  *Image\Width = 0
  *Image\Height = 0
  *Image\LeftOffset = 0
  *Image\TopOffset = 0
  *Image\PixelCount = 0
  *Image\Pixels = 0
  *Image\Mask = 0
  gPatch_LastError = ""
  ProcedureReturn #True
EndProcedure

; Central failure path: frees the partially built planes and returns #False.
; Requires local variables 'pixels' and 'mask' in the calling procedure.
Macro PatchAbort(MessageText)
  If pixels <> 0
    FreeMemory(pixels)
    pixels = 0
  EndIf
  If mask <> 0
    FreeMemory(mask)
    mask = 0
  EndIf
  PatchSetError(MessageText)
  ProcedureReturn #False
EndMacro

Procedure.i PatchDecode(*Bytes.Byte, Length.q, *Result.PatchImage)
  Protected width.i
  Protected height.i
  Protected leftOffset.l
  Protected topOffset.l
  Protected tableEnd.q
  Protected pixelCount.q
  Protected pixels.i = 0
  Protected mask.i = 0
  Protected columnIndex.i
  Protected columnOffset.q
  Protected cursor.q
  Protected topDelta.i
  Protected postLength.i
  Protected pixelIndex.i
  Protected outputIndex.q
  Protected terminated.i

  If *Result = 0
    PatchSetError("Patch result pointer is null.")
    ProcedureReturn #False
  EndIf

  PatchReset(*Result)

  If Length < #PATCH_HeaderSize
    PatchSetError("Patch is too short for its 8-byte header.")
    ProcedureReturn #False
  EndIf
  If *Bytes = 0
    PatchSetError("Patch data pointer is null.")
    ProcedureReturn #False
  EndIf

  width = EndianReadU16LE(*Bytes, 0)
  height = EndianReadU16LE(*Bytes, 2)
  leftOffset = EndianReadU16LE(*Bytes, 4)
  topOffset = EndianReadU16LE(*Bytes, 6)
  If leftOffset >= $8000
    leftOffset = leftOffset - $10000
  EndIf
  If topOffset >= $8000
    topOffset = topOffset - $10000
  EndIf

  If width = 0 Or width > #PATCH_MaxDimension
    PatchAbort("Patch width is invalid: " + Str(width) + " (allowed 1.." + Str(#PATCH_MaxDimension) + ").")
  EndIf
  If height = 0 Or height > #PATCH_MaxDimension
    PatchAbort("Patch height is invalid: " + Str(height) + " (allowed 1.." + Str(#PATCH_MaxDimension) + ").")
  EndIf

  tableEnd = Int(#PATCH_HeaderSize) + Int(width) * #PATCH_ColumnEntrySize
  If tableEnd > Length
    PatchAbort("Patch column table is truncated: needs " + Str(tableEnd) + " bytes, input has " + Str(Length) + ".")
  EndIf

  pixelCount = Int(width) * Int(height)
  If pixelCount > #PATCH_MaxPixels
    PatchAbort("Patch pixel budget exceeded: " + Str(pixelCount) + " (limit " + Str(#PATCH_MaxPixels) + ").")
  EndIf

  pixels = AllocateMemory(pixelCount)
  mask = AllocateMemory(pixelCount)
  If pixels = 0 Or mask = 0
    PatchAbort("Out of memory while allocating patch planes.")
  EndIf
  FillMemory(pixels, pixelCount, 0)
  FillMemory(mask, pixelCount, 0)

  For columnIndex = 0 To width - 1
    columnOffset = EndianReadU32LE(*Bytes, #PATCH_HeaderSize + columnIndex * #PATCH_ColumnEntrySize)
    If columnOffset < tableEnd
      PatchAbort("Patch column " + Str(columnIndex) + " offset points inside the header table.")
    EndIf
    If columnOffset >= Length
      PatchAbort("Patch column " + Str(columnIndex) + " offset is outside the input.")
    EndIf

    cursor = columnOffset
    terminated = #False
    While cursor < Length
      topDelta = PeekA(*Bytes + cursor)
      If topDelta = $FF
        terminated = #True
        Break
      EndIf

      ; topdelta, length and the unused byte must all exist.
      If cursor + 3 > Length
        PatchAbort("Patch column " + Str(columnIndex) + " has a truncated post header.")
      EndIf
      postLength = PeekA(*Bytes + cursor + 1)

      If Int(topDelta) + Int(postLength) > height
        PatchAbort("Patch column " + Str(columnIndex) + " post exceeds the image height.")
      EndIf
      If cursor + Int(postLength) + 4 > Length
        PatchAbort("Patch column " + Str(columnIndex) + " has a truncated post.")
      EndIf

      For pixelIndex = 0 To postLength - 1
        outputIndex = (Int(topDelta) + pixelIndex) * Int(width) + columnIndex
        PokeA(pixels + outputIndex, PeekA(*Bytes + cursor + 3 + pixelIndex))
        PokeA(mask + outputIndex, 1)
      Next

      ; A post is always at least four bytes, so the cursor strictly advances.
      cursor + Int(postLength) + 4
    Wend

    If terminated = #False
      PatchAbort("Patch column " + Str(columnIndex) + " has no 0xFF terminator.")
    EndIf
  Next

  *Result\Magic = #PATCH_Magic
  *Result\Width = width
  *Result\Height = height
  *Result\LeftOffset = leftOffset
  *Result\TopOffset = topOffset
  *Result\PixelCount = pixelCount
  *Result\Pixels = pixels
  *Result\Mask = mask
  gPatch_LastError = ""
  ProcedureReturn #True
EndProcedure

; Returns the palette index at (X, Y), or -1 for an invalid image/coordinate.
Procedure.i PatchPixelAt(*Image.PatchImage, X.i, Y.i)
  If *Image = 0 Or *Image\Magic <> #PATCH_Magic
    PatchSetError("Patch image is not initialized.")
    ProcedureReturn -1
  EndIf
  If X < 0 Or Y < 0 Or X >= *Image\Width Or Y >= *Image\Height
    PatchSetError("Patch coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Image\Pixels + Int(Y) * Int(*Image\Width) + Int(X))
EndProcedure

; Returns the mask at (X, Y): 0 = transparent, 1 = opaque, -1 = invalid input.
Procedure.i PatchOpaqueAt(*Image.PatchImage, X.i, Y.i)
  If *Image = 0 Or *Image\Magic <> #PATCH_Magic
    PatchSetError("Patch image is not initialized.")
    ProcedureReturn -1
  EndIf
  If X < 0 Or Y < 0 Or X >= *Image\Width Or Y >= *Image\Height
    PatchSetError("Patch coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Image\Mask + Int(Y) * Int(*Image\Width) + Int(X))
EndProcedure

CompilerEndIf
