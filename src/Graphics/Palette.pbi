; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; PLAYPAL decoder. The lump is a sequence of 768-byte palettes, each holding
; 256 RGB triples (red, green, blue; one unsigned byte per channel).
;
; No VGA 0-63 scaling, gamma, byte swapping or BGR conversion is applied here:
; channels are returned exactly as stored. Display-format conversion belongs to
; a later video layer.
;
; Ownership:
;   - PaletteSet is caller-owned and must be zero-initialized once, for example
;     with ClearStructure(@pal, PaletteSet).
;   - PaletteDecode() owns the RGB allocation and replaces any previous one.
;   - PaletteReset() releases the RGB allocation and leaves the structure ready
;     for reuse. PaletteDecode() also resets first, so failed decodes never
;     leave partial data behind.
;   - The Magic field guards against freeing uninitialized or double-reset
;     structures; it is never exposed as part of the public contract.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PALETTE_PBI, #PB_Constant) = 0

#DOOMPB_PALETTE_PBI = 1

#PALETTE_ColorCount = 256
#PALETTE_ByteSize   = 256 * 3
#PALETTE_MaxCount   = 256

#PALETTE_Magic      = $50414C31

Structure PaletteSet
  Magic.l
  Count.l
  *RGB.Byte
EndStructure

Global gPalette_LastError.s = ""

Procedure PaletteSetError(Message.s)
  gPalette_LastError = Message
EndProcedure

Procedure.s PaletteLastError()
  ProcedureReturn gPalette_LastError
EndProcedure

; Releases the decoded RGB block, if any, and clears the metadata. Safe to
; call repeatedly; the structure stays allocated because the caller owns it.
Procedure.i PaletteReset(*Palette.PaletteSet)
  If *Palette = 0
    PaletteSetError("Palette set pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Palette\Magic = #PALETTE_Magic
    If *Palette\RGB <> 0
      FreeMemory(*Palette\RGB)
    EndIf
  EndIf

  *Palette\Magic = 0
  *Palette\Count = 0
  *Palette\RGB = 0
  gPalette_LastError = ""
  ProcedureReturn #True
EndProcedure

; Decodes Length bytes into *Result. Length must be a nonzero multiple of 768.
; The function replaces any previous palette data in *Result.
Procedure.i PaletteDecode(*Bytes.Byte, Length.q, *Result.PaletteSet)
  Protected paletteCount.q
  Protected rgb.i = 0

  If *Result = 0
    PaletteSetError("Palette result pointer is null.")
    ProcedureReturn #False
  EndIf

  PaletteReset(*Result)

  If Length <= 0
    PaletteSetError("PLAYPAL data length must be nonzero.")
    ProcedureReturn #False
  EndIf
  If Length % #PALETTE_ByteSize <> 0
    PaletteSetError("PLAYPAL data length is not a multiple of 768 bytes.")
    ProcedureReturn #False
  EndIf

  paletteCount = Length / #PALETTE_ByteSize
  If paletteCount > #PALETTE_MaxCount
    PaletteSetError("PLAYPAL contains too many palettes: " + Str(paletteCount) + " (limit " + Str(#PALETTE_MaxCount) + ").")
    ProcedureReturn #False
  EndIf

  If *Bytes = 0
    PaletteSetError("PLAYPAL data pointer is null.")
    ProcedureReturn #False
  EndIf

  rgb = AllocateMemory(Length)
  If rgb = 0
    PaletteSetError("Out of memory while decoding PLAYPAL.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Bytes, rgb, Length)

  *Result\Magic = #PALETTE_Magic
  *Result\Count = paletteCount
  *Result\RGB = rgb
  gPalette_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PaletteCount(*Palette.PaletteSet)
  If *Palette = 0 Or *Palette\Magic <> #PALETTE_Magic
    PaletteSetError("Palette set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Palette\Count
EndProcedure

; Reads one RGB triple. The three destination pointers are required; invalid
; indices or pointers leave the destinations untouched.
Procedure.i PaletteGetRGB(*Palette.PaletteSet, PaletteIndex.i, ColorIndex.i, *R.Byte, *G.Byte, *B.Byte)
  Protected offset.q

  If *Palette = 0 Or *Palette\Magic <> #PALETTE_Magic
    PaletteSetError("Palette set is not initialized.")
    ProcedureReturn #False
  EndIf
  If PaletteIndex < 0 Or PaletteIndex >= *Palette\Count
    PaletteSetError("Palette index out of range: " + Str(PaletteIndex) + " (count " + Str(*Palette\Count) + ").")
    ProcedureReturn #False
  EndIf
  If ColorIndex < 0 Or ColorIndex >= #PALETTE_ColorCount
    PaletteSetError("Color index out of range: " + Str(ColorIndex) + " (count " + Str(#PALETTE_ColorCount) + ").")
    ProcedureReturn #False
  EndIf
  If *R = 0 Or *G = 0 Or *B = 0
    PaletteSetError("Palette channel destination pointer is null.")
    ProcedureReturn #False
  EndIf

  offset = Int(PaletteIndex) * #PALETTE_ByteSize + Int(ColorIndex) * 3
  PokeA(*R, PeekA(*Palette\RGB + offset))
  PokeA(*G, PeekA(*Palette\RGB + offset + 1))
  PokeA(*B, PeekA(*Palette\RGB + offset + 2))
  gPalette_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
