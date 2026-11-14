; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Explicit little-endian decoding helpers.
;
; Binary game data (WAD and map formats) is always little-endian regardless of
; the host byte order. These helpers decode field by field from a byte buffer;
; they never overlay a PureBasic structure on untrusted file bytes.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_ENDIAN_PBI, #PB_Constant) = 0

#DOOMPB_ENDIAN_PBI = 1

; Reads an unsigned 16-bit little-endian value from *Data + Offset.
; Offset must point to at least two readable bytes; callers validate ranges.
Procedure.q EndianReadU16LE(*Data.Byte, Offset.i)
  Protected b0.q = PeekA(*Data + Offset)
  Protected b1.q = PeekA(*Data + Offset + 1)

  ProcedureReturn b0 | (b1 << 8)
EndProcedure

; Reads an unsigned 32-bit little-endian value from *Data + Offset as a
; zero-extended 64-bit integer. Offset must point to four readable bytes.
Procedure.q EndianReadU32LE(*Data.Byte, Offset.i)
  Protected b0.q = PeekA(*Data + Offset)
  Protected b1.q = PeekA(*Data + Offset + 1)
  Protected b2.q = PeekA(*Data + Offset + 2)
  Protected b3.q = PeekA(*Data + Offset + 3)

  ProcedureReturn b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
EndProcedure

; Reads a signed 32-bit little-endian value (C 'int' / Doom fixed_t field).
; The unsigned value is reinterpreted with two's-complement semantics.
Procedure.l EndianReadI32LE(*Data.Byte, Offset.i)
  Protected unsignedValue.q = EndianReadU32LE(*Data, Offset)

  If unsignedValue >= $80000000
    unsignedValue = unsignedValue - $100000000
  EndIf

  ProcedureReturn unsignedValue
EndProcedure

CompilerEndIf
