; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Fixed-point 16.16 arithmetic, ported from Linux Doom 1.10 m_fixed.c/m_fixed.h:
;   fixed_t        -> signed 32-bit Long (.l), 16 integer + 16 fractional bits
;   FixedMul       -> FixedMul
;   FixedDiv       -> FixedDiv (early magnitude guard, saturation)
;   FixedDiv2      -> FixedDiv2Checked (The active C version uses a double, so the
;                     checked helper computes the exact integer quotient and
;                     rejects the same out-of-range domain instead of I_Error)
;   SHORT(..)<<FRACBITS conversion -> FixedFromIntChecked
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
;
; Compatibility choices for C undefined/implementation-defined cases:
;   - magnitudes are widened to signed 64-bit before negation; no Abs() is
;     applied to a signed32 minimum value (the original abs(INT_MIN) is UB);
;   - FixedMul's C narrowing of an out-of-range long long to int32 is replaced
;     by an explicit low-32 two's-complement wrap (FixedWrap32Low), because the
;     original FixedMul does not saturate;
;   - FixedDiv's quotient is an exact 64-bit integer truncated toward zero; it
;     is only evaluated outside the original guard, where the magnitude cannot
;     reach signed32 overflow (the C FixedDiv2 double formula truncates the
;     same values toward zero; parity is covered by tests);
;   - divide-by-zero and out-of-range FixedDiv2 conditions return #False with a
;     diagnostic through FixedLastError() instead of aborting the process.
;
; This module has no WAD, graphics, map, renderer or OS dependency, no heap
; allocation and no random/global simulation state. It can be included alone.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_FIXED_PBI, #PB_Constant) = 0

#DOOMPB_FIXED_PBI = 1

; Fixed-point format constants from m_fixed.h.
#FRACBITS = 16
#FRACUNIT = (1 << #FRACBITS)

; signed 32-bit limits used by fixed_t.
#FIXED_MIN = -2147483648
#FIXED_MAX = 2147483647

; Integer map-unit range that a signed map field (C SHORT) can represent in
; 16.16. +32768 maps to 2147483648, which is one beyond #FIXED_MAX.
#FIXED_INT_MIN = -32768
#FIXED_INT_MAX = 32767

; The original FixedDiv guard compares abs(a)>>14 with abs(b); 14 is separate
; from the 16-bit fraction shift.
#FIXED_DIV_GUARD_SHIFT = 14

Global gFixed_LastError.s = ""

Procedure FixedSetError(Message.s)
  gFixed_LastError = Message
EndProcedure

; Actionable diagnostic for the checked helpers. A successful checked call
; clears it; a failed call sets it. This is a string only, not numeric state.
Procedure.s FixedLastError()
  ProcedureReturn gFixed_LastError
EndProcedure

; Explicit low-32 two's-complement narrowing of a signed 64-bit value.
; PureBasic's assignment of a Quad to a Long was verified to truncate to the
; low 32 bits, but production code does not rely on that implicit behaviour:
; this helper masks the low word, then reinterprets $80000000..$FFFFFFFF with
; two's-complement sign semantics. It is the defined wrap policy for FixedMul
; and also guards results that tests prove to be already in range.
Procedure.l FixedWrap32Low(Value.q)
  Protected lowUnsigned.q = Value & $FFFFFFFF

  If lowUnsigned >= $80000000
    lowUnsigned = lowUnsigned - $100000000
  EndIf

  ProcedureReturn lowUnsigned
EndProcedure

; Original FixedMul:
;   return ((long long)a * (long long)b) >> FRACBITS;
;
; Both operands are widened to signed 64-bit before multiplication, so the
; product is exact for every signed32 pair. PureBasic's right shift on a signed
; Quad is arithmetic (it preserves the sign bit), which is exactly the C
; arithmetic shift: a negative product is floored toward negative infinity, not
; truncated toward zero. The out-of-range 32-bit result follows the explicit
; wrap policy above; FixedMul never saturates.
Procedure.l FixedMul(A.l, B.l)
  Protected wideA.q = A
  Protected wideB.q = B
  Protected product.q = wideA * wideB
  Protected floored.q = product >> #FRACBITS

  ProcedureReturn FixedWrap32Low(floored)
EndProcedure

; Original FixedDiv:
;   if ((abs(a) >> 14) >= abs(b))
;       return (a ^ b) < 0 ? MININT : MAXINT;
;   return FixedDiv2(a, b);
;
; The guard is evaluated first, exactly as in C, with safe widened magnitudes.
; In the non-saturating branch the quotient is the exact integer
; a*FRACUNIT/b truncated toward zero. The guard guarantees its magnitude stays
; within the original's non-failing FixedDiv2 domain, so no checked error is
; possible. A zero denominator is always caught by the guard: (x >> 14) >= 0,
; and therefore returns saturation instead of attempting a division.
Procedure.l FixedDiv(A.l, B.l)
  Protected wideA.q = A
  Protected wideB.q = B
  Protected magnitudeA.q = wideA
  Protected magnitudeB.q = wideB
  Protected scaledA.q
  Protected quotient.q

  If magnitudeA < 0
    magnitudeA = -magnitudeA
  EndIf
  If magnitudeB < 0
    magnitudeB = -magnitudeB
  EndIf

  If (magnitudeA >> #FIXED_DIV_GUARD_SHIFT) >= magnitudeB
    If (A ! B) < 0
      ProcedureReturn #FIXED_MIN
    Else
      ProcedureReturn #FIXED_MAX
    EndIf
  EndIf

  scaledA = wideA * #FRACUNIT
  quotient = scaledA / wideB

  ProcedureReturn FixedWrap32Low(quotient)
EndProcedure

; Safe equivalent of the active C FixedDiv2:
;   c = ((double)a) / ((double)b) * FRACUNIT;
;   if (c >= 2147483648.0 || c < -2147483648.0) I_Error(...);
;   return (fixed_t)c;
;
; No unchecked FixedDiv2 is exported: the original's out-of-range and zero
; denominator cases abort the engine. This checked form computes the same exact
; integer quotient, truncating toward zero. It returns #False for a null output
; pointer, a zero denominator, or a quotient outside signed32 fixed range
; (quotient > #FIXED_MAX or quotient < #FIXED_MIN). On failure *Result is not
; modified; on success it receives the narrowed value and the error is cleared.
Procedure.i FixedDiv2Checked(A.l, B.l, *Result.Long)
  Protected wideA.q = A
  Protected wideB.q = B
  Protected scaledA.q
  Protected quotient.q

  FixedSetError("")
  If *Result = 0
    FixedSetError("FixedDiv2Checked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If wideB = 0
    FixedSetError("FixedDiv2Checked: denominator is zero.")
    ProcedureReturn #False
  EndIf

  scaledA = wideA * #FRACUNIT
  quotient = scaledA / wideB

  If quotient > #FIXED_MAX Or quotient < #FIXED_MIN
    FixedSetError("FixedDiv2Checked: quotient is outside the signed 32-bit fixed range.")
    ProcedureReturn #False
  EndIf

  *Result\l = FixedWrap32Low(quotient)
  ProcedureReturn #True
EndProcedure

; Checked conversion of a signed integer/map-unit coordinate to 16.16.
; The signed map fields decoded by MapDecode are C SHORT values, hence already
; inside [-32768,32767]; this API accepts a wide Quad and rejects wider input.
;
; A representable integer must be in [-32768,32767] because fixed_t's integer
; part is signed16. The input is bounded before multiplication, so a huge Quad
; cannot overflow the 64-bit intermediate. The product Value*FRACUNIT is then
; recomputed in 64-bit and post-checked against #FIXED_MIN/#FIXED_MAX before the
; result is published. On failure *Result is left unchanged.
Procedure.i FixedFromIntChecked(Value.q, *Result.Long)
  Protected scaled.q

  FixedSetError("")
  If *Result = 0
    FixedSetError("FixedFromIntChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If Value < #FIXED_INT_MIN Or Value > #FIXED_INT_MAX
    FixedSetError("FixedFromIntChecked: integer " + Str(Value) + " cannot be represented as 16.16 fixed-point.")
    ProcedureReturn #False
  EndIf

  scaled = Value * #FRACUNIT

  If scaled < #FIXED_MIN Or scaled > #FIXED_MAX
    FixedSetError("FixedFromIntChecked: scaled value is outside the signed 32-bit fixed range.")
    ProcedureReturn #False
  EndIf

  *Result\l = scaled
  ProcedureReturn #True
EndProcedure

; Integer part by the original renderer's arithmetic shift:
;   value >> FRACBITS
; Negative fixed values floor toward negative infinity: -1 -> -1 and
; -65537 -> -2. This is the helper future geometry code must use instead of a
; truncating division.
Procedure.l FixedToIntFloor(Value.l)
  Protected result.l = Value >> #FRACBITS

  ProcedureReturn result
EndProcedure

; Optional diagnostic distinction: integer part truncated toward zero.
; -1 -> 0 and -65537 -> -1. It must never silently replace FixedToIntFloor in
; renderer code, because Doom's original uses the arithmetic shift.
Procedure.l FixedToIntTrunc(Value.l)
  Protected result.l = Value / #FRACUNIT

  ProcedureReturn result
EndProcedure

CompilerEndIf
