; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Binary angle measurement (BAM) representation from Linux Doom 1.10
; tables.h/tables.c:
;   angle_t          -> raw unsigned 32-bit bits, carried as Quad (.q)
;   ANG45/ANG90/...  -> unsigned BAM constants
;   FINEANGLES/FINEMASK/ANGLETOFINESHIFT -> sine/cosine table indexing
;   SLOPERANGE/SLOPEBITS/DBITS -> slope lookup constants
;
; A BAM angle is a full 360-degree turn modulo 2^32. The stored value is a bit
; pattern, not a signed positive Long: ANG180 is 2147483648 and would be a
; negative .l. All add/subtract/negate operations below publish the low 32 bits
; constrained to 0..4294967295 (BamWrap32), preserving C unsigned wraparound.
; Tests AG01-AG07 cover representation, wrap, indexing, signed-bit transport and
; determinism; floating-point degrees, Sin(), Cos() or ATan2() are never used
; for BAM values.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
;
; This module has no WAD, graphics, renderer or OS dependency. It includes only
; the fixed-point constant vocabulary (FRACBITS) it needs.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_ANGLE_PBI, #PB_Constant) = 0

#DOOMPB_ANGLE_PBI = 1

XIncludeFile "Fixed.pbi"

; Exact constants from tables.h.
#BAM_FINEANGLES = 8192
#BAM_FINEMASK = #BAM_FINEANGLES - 1
#BAM_ANGLETOFINESHIFT = 19
#BAM_SLOPERANGE = 2048
#BAM_SLOPEBITS = 11
#BAM_DBITS = #FRACBITS - #BAM_SLOPEBITS
#BAM_COSINE_OFFSET = #BAM_FINEANGLES / 4

; Raw unsigned 32-bit values. Hex constants are Quad literals here.
#BAM_ANG45 = $20000000
#BAM_ANG90 = $40000000
#BAM_ANG180 = $80000000
#BAM_ANG270 = $C0000000
#BAM_RAW_MAX = $FFFFFFFF

; Raw angle payload transport. Deep-copying a Quad bit pattern keeps the full
; unsigned ring and avoids storing an oversized value in a signed .l field.
Structure BamAngleValue
  Raw.q
EndStructure

; Low-32 cleanup of any Quad into the raw unsigned BAM ring. Negative inputs and
; inputs above 2^32 are deliberately masked instead of rejected: a raw angle is
; inherently defined by its low 32 bits, matching C unsigned arithmetic.
Procedure.q BamWrap32(Value.q)
  Protected bits.q = Value & $FFFFFFFF

  ProcedureReturn bits
EndProcedure

; Informational predicate for callers that already hold a canonical raw value;
; it is not a gate for any calculation and never generates an error.
Procedure.i BamRawInUnsignedDomain(Value.q)
  ProcedureReturn Bool(Value >= 0 And Value <= #BAM_RAW_MAX)
EndProcedure

; Unsigned add/subtract modulo 2^32, exactly like C angle_t arithmetic.
Procedure.q BamAdd(A.q, B.q)
  ProcedureReturn BamWrap32(A + B)
EndProcedure

Procedure.q BamSubtract(A.q, B.q)
  ProcedureReturn BamWrap32(A - B)
EndProcedure

Procedure.q BamNegate(A.q)
  ProcedureReturn BamWrap32(-A)
EndProcedure

; Fine angle index `(angle >> 19) & 8191` on the raw unsigned representation.
; The Quad input is normalized first, so negative signed-bit payloads and values
; above 2^32 map to their exact low-32 index deterministically.
Procedure.q BamFineIndex(RawAngle.q)
  Protected wrapped.q = BamWrap32(RawAngle)

  ProcedureReturn (wrapped >> #BAM_ANGLETOFINESHIFT) & #BAM_FINEMASK
EndProcedure

CompilerEndIf
