; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Exact vanilla trigonometry tables from Linux Doom 1.10 tables.h/tables.c:
;   finetangent[4096]       -> signed .l tangent LUT, exact values
;   finesine[10240]         -> signed .l 16.16 sine LUT, exact values
;   finecosine               -> alias of finesine + FINEANGLES/4, not a new table
;   tantoangle[2049]        -> raw BAM angle_t table for slope 0..2048
;   SlopeDiv                 -> DoomSlopeDivChecked, exact unsigned formula
;
; The literal values are generated once by scripts/gen_trig_tables.py from the
; pinned tables.c commit a77dfb96cb91780ca334d0d4cfd86957558007e0 and stored in
; a checked immutable DataSection (TrigTablesData.pbi). No runtime Sin/Cos/ATan
; generator exists. The complete little-endian two's-complement FNV-1a64 hashes
; of all three arrays are verified by tests AG09-AG16 and the generator.
;
; Every lookup uses a validated index and leaves the caller's output untouched
; on failure. BamSin/BamCos are infallible helpers because their index is always
; inside the sine array after BAM normalization. DoomSlopeDivChecked accepts the
; original unsigned argument domain 0..2^32-1 and rejects negative/oversized
; Quad inputs; `num << 3` is deliberately low-32 wrapped exactly like C unsigned
; arithmetic before the unsigned division.
;
; Original table algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
;
; This module has no WAD, map, graphics, renderer or OS dependency. Tables are
; process-lifetime immutable data with no heap ownership or per-call setup.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_TRIGTABLES_PBI, #PB_Constant) = 0

#DOOMPB_TRIGTABLES_PBI = 1

XIncludeFile "Angle.pbi"
XIncludeFile "TrigTablesData.pbi"

; Effective array sizes from tables.h.
#TRIG_FINETANGENT_COUNT = #BAM_FINEANGLES / 2
#TRIG_SINE_COUNT = 5 * #BAM_FINEANGLES / 4
#TRIG_TANTOANGLE_COUNT = #BAM_SLOPERANGE + 1

; Immutable DataSection pointers. The generated data labels come from
; TrigTablesData.pbi and are stable for the process lifetime.
Global *gTrigFinetangent = ?DoomPBTrigFinetangentData
Global *gTrigSine = ?DoomPBTrigSineData
Global *gTrigTanToAngle = ?DoomPBTrigTanToAngleData

Global gTrig_LastError.s = ""

Procedure TrigSetError(Message.s)
  gTrig_LastError = Message
EndProcedure

Procedure.s TrigLastError()
  ProcedureReturn gTrig_LastError
EndProcedure

; finetangent lookup for an original fine-angle index 0..4095.
Procedure.i TrigTangentChecked(FineIndex.l, *Result.Long)
  TrigSetError("")
  If *Result = 0
    TrigSetError("TrigTangentChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If FineIndex < 0 Or FineIndex > #TRIG_FINETANGENT_COUNT - 1
    TrigSetError("TrigTangentChecked: fine index " + Str(FineIndex) + " is outside 0.." + Str(#TRIG_FINETANGENT_COUNT - 1) + ".")
    ProcedureReturn #False
  EndIf

  *Result\l = PeekL(*gTrigFinetangent + FineIndex * 4)
  ProcedureReturn #True
EndProcedure

; finesine lookup for an original sine index 0..10239.
Procedure.i TrigSineChecked(SineIndex.l, *Result.Long)
  TrigSetError("")
  If *Result = 0
    TrigSetError("TrigSineChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If SineIndex < 0 Or SineIndex > #TRIG_SINE_COUNT - 1
    TrigSetError("TrigSineChecked: sine index " + Str(SineIndex) + " is outside 0.." + Str(#TRIG_SINE_COUNT - 1) + ".")
    ProcedureReturn #False
  EndIf

  *Result\l = PeekL(*gTrigSine + SineIndex * 4)
  ProcedureReturn #True
EndProcedure

; Cosine through the original alias offset: sine[FINEANGLES/4 + index], with an
; accepted cosine/fine index 0..8191. This is not a separately calculated table.
Procedure.i TrigCosineChecked(FineIndex.l, *Result.Long)
  TrigSetError("")
  If *Result = 0
    TrigSetError("TrigCosineChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If FineIndex < 0 Or FineIndex > #BAM_FINEMASK
    TrigSetError("TrigCosineChecked: fine index " + Str(FineIndex) + " is outside 0.." + Str(#BAM_FINEMASK) + ".")
    ProcedureReturn #False
  EndIf

  *Result\l = PeekL(*gTrigSine + (FineIndex + #BAM_COSINE_OFFSET) * 4)
  ProcedureReturn #True
EndProcedure

; tantoangle lookup for a slope index 0..2048 (including the exact endpoint).
; Table entries are raw BAM angle_t values but remain signed-positive .l values
; in the pinned data; the caller treats them as unsigned bit patterns.
Procedure.i TrigTanToAngleChecked(SlopeIndex.l, *Result.Long)
  TrigSetError("")
  If *Result = 0
    TrigSetError("TrigTanToAngleChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If SlopeIndex < 0 Or SlopeIndex > #TRIG_TANTOANGLE_COUNT - 1
    TrigSetError("TrigTanToAngleChecked: slope index " + Str(SlopeIndex) + " is outside 0.." + Str(#TRIG_TANTOANGLE_COUNT - 1) + ".")
    ProcedureReturn #False
  EndIf

  *Result\l = PeekL(*gTrigTanToAngle + SlopeIndex * 4)
  ProcedureReturn #True
EndProcedure

; Infallible sine helper: `finesine[angle >> ANGLETOFINESHIFT]` directly. The
; normalized BAM index is always 0..8191, hence inside all 10240 entries.
Procedure.l BamSin(RawAngle.q)
  Protected fineIndex.q = BamFineIndex(RawAngle)

  ProcedureReturn PeekL(*gTrigSine + fineIndex * 4)
EndProcedure

; Infallible cosine helper through the original sine offset alias.
Procedure.l BamCos(RawAngle.q)
  Protected fineIndex.q = BamFineIndex(RawAngle)

  ProcedureReturn PeekL(*gTrigSine + (fineIndex + #BAM_COSINE_OFFSET) * 4)
EndProcedure

; Vanilla SlopeDiv from tables.c:
;   if (den < 512) return SLOPERANGE;
;   ans = (num << 3) / (den >> 8);
;   return ans <= SLOPERANGE ? ans : SLOPERANGE;
;
; Arguments are unsigned 32-bit in C. The checked API rejects negative or
; >2^32-1 Quad inputs explicitly; valid arguments reproduce the unsigned shift
; modulo 2^32 (num << 3 masks the low word), unsigned `den >> 8` and unsigned
; division. It does not use the non-equivalent `(num*2048)/den` formula.
Procedure.i DoomSlopeDivChecked(Num.q, Den.q, *Result.Long)
  Protected numerator.q
  Protected denWord.q
  Protected answer.q

  TrigSetError("")
  If *Result = 0
    TrigSetError("DoomSlopeDivChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If Num < 0 Or Num > #BAM_RAW_MAX
    TrigSetError("DoomSlopeDivChecked: numerator " + Str(Num) + " is outside the unsigned 32-bit domain.")
    ProcedureReturn #False
  EndIf
  If Den < 0 Or Den > #BAM_RAW_MAX
    TrigSetError("DoomSlopeDivChecked: denominator " + Str(Den) + " is outside the unsigned 32-bit domain.")
    ProcedureReturn #False
  EndIf

  If Den < 512
    *Result\l = #BAM_SLOPERANGE
    ProcedureReturn #True
  EndIf

  numerator = BamWrap32(Num << 3)
  denWord = Den >> 8
  answer = numerator / denWord

  If answer > #BAM_SLOPERANGE
    answer = #BAM_SLOPERANGE
  EndIf

  *Result\l = answer
  ProcedureReturn #True
EndProcedure

CompilerEndIf
