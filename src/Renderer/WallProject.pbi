; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-05 vertical wall projection helpers and per-WallSpan numeric render plan,
; ported from Linux Doom 1.10 r_segs.c R_StoreWallRange and r_main.c
; R_ScaleFromGlobalAngle. No pixels, texture sampling, planes, sky drawing,
; lighting, sprites or gameplay are in this module.
;
; Input spacing: the ordered, occlusion-clipped WallSpan records produced by
; M3-04 WallVisibilityBuild are authoritative and unchanged. A span's Seg is
; resolved through MapLevel APIs; its stored SEGS angle is a vanilla 16-bit raw
; value. p_setup.c computes `angle = (SHORT(ml->angle)) << 16`, so the checked
; port conversion wraps the 16-bit bit pattern left by FRACBITS into the raw
; unsigned BAM ring. It must not be confused with a signed map-unit angle.
;
; R_StoreWallRange ordering preserved for M3-05 useful geometry:
;   1. rw_normalangle = seg->angle + ANG90 (unsigned wrap);
;   2. rw_angle1 is reconstructed from the ORIGINAL unclipped view-to-seg-v1
;      angle, not from FirstX/LastX or a relative clipped angle;
;   3. offsetangle = abs(rw_normalangle-rw_angle1), clamp > ANG90, and
;      distangle = ANG90-offsetangle (unsigned angle_t semantics);
;   4. hyp = R_PointToDist(v1.x,v1.y) relative to view; distance = hyp *
;      finesine[distangle>>ANGLETOFINESHIFT];
;   5. scale1=R_ScaleFromGlobalAngle(viewangle+xtoviewangle[FirstX]),
;      scale2=that at LastX; step=(scale2-scale1)/(LastX-FirstX) when longer,
;      single-column policy scale2=scale1/step=0;
;   6. worldtop/worldbottom front offsets, back worldhigh/worldlow when present,
;      F_SKY1 sky boundary hack, floor/ceiling mark decisions/pass-through
;      closed-door override, front-plane wrong-side overrides;
;   7. arithmetic `>>4` into the 12-bit interpolation domain;
;   8. topstep/topfrac/bottomstep/bottomfrac and pixhigh/pixlow edge start/steps;
;   9. tier presence from geometry plus catalog-aware texture translation
;      (numeric zero = NoTexture) without any source-pixel access.
;
; Fixed-point / C undefined-behaviour policy:
;   - ordinary signed 16.16 arithmetic keeps the original algorithm;
;   - subtraction/addition/negation widening to signed64 and explicit low-32
;     two's-complement wrap (WallFixedSubLow/WallFixedAddLow/WallFixedNegateLow/
;     FixedWrap32Low) is the documented M3-01-edge policy for C signed overflow
;     places (`ceilingheight-viewz`, topfrac+HEIGHTUNIT-1, C unary minus of a
;     FixedMul result, incremental additions). These helpers are not used to
;     manufacture ordinary results; tests compare normal values first;
;   - `abs(rw_normalangle-rw_angle1)` is the original unsigned-difference cast to
;     C int then abs. The exact INT32_MIN input has no defined abs; it is rejected
;     with a specific diagnostic rather than masked away. Other raw differences
;     map to their exact signed-magnitude values, then to unsigned angle_t;
;   - R_ScaleFromGlobalAngle's C `int anglea/angleb` assignment is a signed low-32
;     interpretation; raw anglea/angleb reaching $80000000+ would create a
;     negative signed index and out-of-domain table access. Those values are
;     rejected, while all admitted span endpoints are expected positive indexes.
;     The `>> ANGLETOFINESHIFT` indexes and finesine values are checked;
;   - a coincident seg-v1/camera point (hyp zero) is an exceptional degenerate
;     source geometry: GeometryPointToDistChecked documents the deterministic
;     zero primitive result, and WallSegPointDistanceChecked rejects it with a
;     diagnostic rather than driving texture scale from a zero wall distance;
;   - valid offset=ANG90 gives distangle=0 and sineval=0; that is an ordinary
;     original-clamped case. Distance may then be zero and the scale algorithm
;     follows its source denominator-zero comparison branch (no division);
;   - a signed32-overflowing scale2-scale1 difference in scaleStep is rejected
;     as a defined edge diagnostic (ordinary admitted scale spans stay within the
;     original 256..64*FRACUNIT clamp range).
;
; Flat/texture identity policy retains the M3-04 catalog-aware semantics:
;   - resolved TEXTURE1/TEXTURE2 numeric index 0 is the original translation's
;     NoTexture quirk; canonical "-"/all-NUL slots are absent; missing/malformed
;     catalog-aware names are explicit failures; malformed fallback names are
;     conservatively treated as present debug geometry, never invented pixels;
;   - flats use the existing WallSectorFlatIdentity helper for mark-floor/mark-
;     ceiling identity and its fallback raw canonical-byte comparison.
;
; Sky policy: the vanilla hack adjusts worldtop only when a back sector exists
;   and BOTH ceiling flats resolve to F_SKY1/skyflatnum; one-sided or mismatch
;   never triggers it. The same front-sky state is used for the R_StoreWallRange
;   wrong-side ceiling-mark override. Catalog-aware path requires canonical names
;   and the F_SKY1 flat entry; fallback compares only canonical raw F_SKY1 bytes.
;
; Output WallSpanPlan owns numeric copies only: no MapLevel/WAD/catalog/camera
;   pointers are retained. Reset is idempotent. A build either publishes Ready=1
;   after all steps or leaves Ready=0 with a detailed WallProjectLastError; it
;   never publishes a partial successful plan. The caller owns the plan slot
;   (M3-05 frame action stores it in RenderMain-owned metadata).
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLPROJECT_PBI, #PB_Constant) = 0

#DOOMPB_WALLPROJECT_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Core/TrigTables.pbi"
XIncludeFile "../Map/MapLevel.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "../Graphics/TextureDefs.pbi"
XIncludeFile "Geometry.pbi"
XIncludeFile "Projection.pbi"
XIncludeFile "WallSpanDefs.pbi"
XIncludeFile "WallIdentity.pbi"

; Original r_segs.c R_RenderSegLoop interpolation constants.
#WALLPROJ_HeightBits = 12
#WALLPROJ_HeightUnit = 1 << #WALLPROJ_HeightBits
#WALLPROJ_ScaleMin = 256
#WALLPROJ_ScaleMax = 64 * #FRACUNIT
#WALLPROJ_PlanMagic = $57504731
#WALLPROJ_NoSector = -1

; F_SKY1 name is the original r_sky.c SKYFLATNAME; the resolved skyflatnum is a
; catalog flat index, never an invented magic index.
#WALLPROJ_SkyFlatName = "F_SKY1"

Structure WallSpanPlan
  Magic.l
  Ready.l
  SpanIndex.l
  Subsector.l
  Seg.l
  Linedef.l
  Side.l
  FrontSector.l
  BackSector.l
  FirstX.l
  LastX.l
  Kind.l
  ViewAngle.q
  SegAngleBam.q
  NormalAngle.q
  ReferenceAngle.q
  RawAngularSeparation.q
  OffsetAngle.q
  DistAngle.q
  Hyp.l
  Distance.l
  Scale1.l
  Scale2.l
  ScaleStep.l
  FrontFloorMap.l
  FrontCeilingMap.l
  FrontLight.l
  BackFloorMap.l
  BackCeilingMap.l
  BackLight.l
  FrontFloorFixed.l
  FrontCeilingFixed.l
  BackFloorFixed.l
  BackCeilingFixed.l
  WorldTopRaw.l
  WorldBottomRaw.l
  WorldHighRaw.l
  WorldLowRaw.l
  WorldTop.l
  WorldBottom.l
  WorldHigh.l
  WorldLow.l
  TopFrac.l
  BottomFrac.l
  TopStep.l
  BottomStep.l
  PixHigh.l
  PixLow.l
  PixHighStep.l
  PixLowStep.l
  MarkFloor.l
  MarkCeiling.l
  TopRegion.l
  BottomRegion.l
  TopTexturePresent.l
  BottomTexturePresent.l
  MiddleTexturePresent.l
  TopTier.l
  BottomTier.l
  MiddleTier.l
  FrontSky.l
  BackSky.l
  SkyHack.l
  ClosedDoor.l
  TwoSided.l
EndStructure

Global gWallProject_LastError.s = ""

Procedure WallProjectSetError(Message.s)
  gWallProject_LastError = Message
EndProcedure

Procedure.s WallProjectLastError()
  ProcedureReturn gWallProject_LastError
EndProcedure

Procedure.i WallSpanPlanIsReady(*Plan.WallSpanPlan)
  ProcedureReturn Bool(*Plan <> 0 And *Plan\Magic = #WALLPROJ_PlanMagic And
                        *Plan\Ready <> 0)
EndProcedure

; Idempotent plan preparation. A zero-initialized caller slot and a previously
; owned plan are accepted; a nonzero unrecognized Magic is rejected. All numeric
; fields are zeroed so a failed build cannot be mistaken for stale success.
Procedure.i WallSpanPlanReset(*Plan.WallSpanPlan)
  If *Plan = 0
    WallProjectSetError("Wall span plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Plan\Magic <> 0 And *Plan\Magic <> #WALLPROJ_PlanMagic
    WallProjectSetError("Wall span plan has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Plan, Int(SizeOf(WallSpanPlan)), 0)
  *Plan\Magic = #WALLPROJ_PlanMagic
  *Plan\Ready = 0
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Explicit signed32 overflow-policy helpers (normal values are exact)
; ---------------------------------------------------------------------------

; Widened signed64 addition/ subtraction/negation followed by the explicit
; M3-01 low-32 two's-complement wrap for places where C signed overflow is UB.
; These helpers are infallible and have no percent/float arithmetic.
Procedure.l WallFixedAddLow(A.l, B.l)
  Protected wideSum.q = Int(A) + Int(B)

  ProcedureReturn FixedWrap32Low(wideSum)
EndProcedure

Procedure.l WallFixedSubLow(A.l, B.l)
  Protected wideDifference.q = Int(A) - Int(B)

  ProcedureReturn FixedWrap32Low(wideDifference)
EndProcedure

Procedure.l WallFixedNegateLow(A.l)
  Protected widened.q = Int(A)

  If widened <> 0
    widened = -widened
  EndIf
  ProcedureReturn FixedWrap32Low(widened)
EndProcedure

; Exact per-column edge extraction, source-faithful rounding:
;   yl = (topfrac+HEIGHTUNIT-1)>>HEIGHTBITS       ceil edge, arithmetic >>;
;   yh = bottomfrac>>HEIGHTBITS                   floor edge, arithmetic >>;
;   upper mid = pixhigh>>HEIGHTBITS; lower mid = (pixlow+HEIGHTUNIT-1)>>12.
Procedure.l WallTopEdgeFromFrac(Frac.l)
  Protected summed.l = WallFixedAddLow(Frac, #WALLPROJ_HeightUnit - 1)

  ProcedureReturn summed >> #WALLPROJ_HeightBits
EndProcedure

Procedure.l WallBottomEdgeFromFrac(Frac.l)
  ProcedureReturn Frac >> #WALLPROJ_HeightBits
EndProcedure

Procedure.l WallPixHighToY(PixHigh.l)
  ProcedureReturn PixHigh >> #WALLPROJ_HeightBits
EndProcedure

Procedure.l WallPixLowToY(PixLow.l)
  Protected summed.l = WallFixedAddLow(PixLow, #WALLPROJ_HeightUnit - 1)

  ProcedureReturn summed >> #WALLPROJ_HeightBits
EndProcedure

; Incremental starts/steps exactly as r_segs.c uses them, with the documented
; widened wrap for the start subtraction, unary-minus negation and additions:
;   topfrac = (centeryfrac>>4) - FixedMul(worldtop, scale);
;   topstep = -FixedMul(scalestep, worldtop).
Procedure.l WallHeightStart(CenterYShifted.l, ShiftedHeight.l, Scale.l)
  Protected product.l = FixedMul(ShiftedHeight, Scale)
  Protected difference.q = Int(CenterYShifted) - Int(product)

  ProcedureReturn FixedWrap32Low(difference)
EndProcedure

Procedure.l WallHeightStepNegated(ScaleStep.l, ShiftedHeight.l)
  Protected product.l = FixedMul(ScaleStep, ShiftedHeight)
  Protected negated.q = Int(product)

  If negated <> 0
    negated = -negated
  EndIf
  ProcedureReturn FixedWrap32Low(negated)
EndProcedure

; ---------------------------------------------------------------------------
; SEGS raw-angle / BAM / angular separation / wall distance
; ---------------------------------------------------------------------------

; Checked p_setup.c SEGS angle conversion. Input is the signed-or-unsigned
; 16-bit raw bit value accepted by the original SHORT macro; both -16384 and
; 49152 denote the same bits. `(bits << 16) & 0xFFFFFFFF` reproduces the C
; SHORT(...)<<FRACBITS low-32 raw BAM value for all 16-bit inputs.
Procedure.i WallSegRawAngleToBamChecked(SegRaw.q, *RawAngle.Quad)
  Protected bits.q

  WallProjectSetError("")
  If *RawAngle = 0
    WallProjectSetError("WallSegRawAngleToBamChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If SegRaw < -32768 Or SegRaw > 65535
    WallProjectSetError("SEGS raw angle is outside the signed/unsigned 16-bit domain: " + Str(SegRaw) + ".")
    ProcedureReturn #False
  EndIf

  bits = SegRaw & $FFFF
  PokeQ(*RawAngle, BamWrap32(bits << #FRACBITS))
  ProcedureReturn #True
EndProcedure

; rw_normalangle = seg angle + ANG90, unsigned angle_t wrap.
Procedure.i WallSegNormalAngleChecked(SegRaw.q, *NormalAngle.Quad)
  Protected segBam.q = 0

  WallProjectSetError("")
  If *NormalAngle = 0
    WallProjectSetError("WallSegNormalAngleChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If WallSegRawAngleToBamChecked(SegRaw, @segBam) = #False
    ProcedureReturn #False
  EndIf
  PokeQ(*NormalAngle, BamAdd(segBam, #BAM_ANG90))
  ProcedureReturn #True
EndProcedure

; Source `abs(rw_normalangle-rw_angle1)` transport, exactly for every raw
; difference except the undefined abs(INT32_MIN) edge:
;   delta = rw_normalangle-rw_angle1 modulo 2^32;
;   C int low-32 interpretation; abs magnitude = delta or 2^32-delta;
;   then unsigned angle_t clamp `if > ANG90 -> ANG90`.
; Both the unclamped magnitude and the R_StoreWallRange-clamped offset raw are
; published. INT32_MIN delta (raw $80000000 exactly) is rejected.
Procedure.i WallAngleOffsetChecked(NormalAngle.q, ReferenceAngle.q,
                                  *Magnitude.Quad, *OffsetAngle.Quad)
  Protected delta.q
  Protected magnitude.q

  WallProjectSetError("")
  If *Magnitude = 0 Or *OffsetAngle = 0
    WallProjectSetError("WallAngleOffsetChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(NormalAngle) = 0 Or BamRawInUnsignedDomain(ReferenceAngle) = 0
    WallProjectSetError("WallAngleOffsetChecked: input angle is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf

  delta = BamSubtract(NormalAngle, ReferenceAngle)
  If delta = $80000000
    WallProjectSetError("Angular separation equals the abs(INT32_MIN) undefined edge; it has no defined C magnitude.")
    ProcedureReturn #False
  EndIf
  If delta <= $7FFFFFFF
    magnitude = delta
  Else
    magnitude = $100000000 - delta
  EndIf
  PokeQ(*Magnitude, magnitude)

  If magnitude > #BAM_ANG90
    PokeQ(*OffsetAngle, #BAM_ANG90)
  Else
    PokeQ(*OffsetAngle, magnitude)
  EndIf
  ProcedureReturn #True
EndProcedure

; Exact original clamp + distance angle + finesine lookup:
;   if offsetangle > ANG90 -> ANG90; distangle = ANG90-offsetangle;
;   sine = finesine[distangle>>ANGLETOFINESHIFT] (0..2048, checked table index).
; Input OffsetAngle is the raw magnitude/raw angle_t value; a noncanonical
; negative/over-range Quad is rejected before the unsigned subtraction.
Procedure.i WallDistanceAngleChecked(OffsetAngle.q, *ClampedOffset.Quad,
                                      *DistAngle.Quad, *FineIndex.Long, *Sine.Long)
  Protected clamped.q

  WallProjectSetError("")
  If *ClampedOffset = 0 Or *DistAngle = 0 Or *FineIndex = 0 Or *Sine = 0
    WallProjectSetError("WallDistanceAngleChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If OffsetAngle < 0 Or OffsetAngle > #BAM_RAW_MAX
    WallProjectSetError("WallDistanceAngleChecked: offset angle is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf

  If OffsetAngle > #BAM_ANG90
    clamped = #BAM_ANG90
  Else
    clamped = OffsetAngle
  EndIf
  PokeQ(*ClampedOffset, clamped)
  PokeQ(*DistAngle, BamSubtract(#BAM_ANG90, clamped))

  *FineIndex\l = Int(BamFineIndex(BamSubtract(#BAM_ANG90, clamped)))
  If TrigSineChecked(*FineIndex\l, *Sine) = #False
    WallProjectSetError("Wall distance sine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; R_PointToDist(v1) with coincidence policy and nonpositive-value rejection.
; A zero hyp is declared unsupported for wall scale/distance because the
; original geometry is degenerate (view point exactly on seg v1); a negative
; widened/wrapped result is likewise rejected. No divide happens here.
Procedure.i WallSegPointDistanceChecked(ViewX.l, ViewY.l, V1X.l, V1Y.l,
                                       *Hyp.Long)
  Protected hyp.l

  WallProjectSetError("")
  If *Hyp = 0
    WallProjectSetError("WallSegPointDistanceChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If GeometryPointToDistChecked(ViewX, ViewY, V1X, V1Y, @hyp) = #False
    WallProjectSetError("Wall v1 point distance failed: " + GeometryLastError())
    ProcedureReturn #False
  EndIf
  If hyp < 0
    WallProjectSetError("Wall v1 point distance produced a nonpositive fixed hyp: " + Str(hyp) + ".")
    ProcedureReturn #False
  EndIf
  If hyp = 0
    WallProjectSetError("Seg v1 coincides with the camera; zero wall distance is a diagnosed unsupported geometry edge.")
    ProcedureReturn #False
  EndIf

  *Hyp\l = hyp
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; rw_distance = FixedMul(hyp,finesine[distangle>>19]). A positive hypsine=0 is
; the ordinary offset=ANG90 clamped case; the source result is zero and is
; accepted so R_ScaleFromGlobalAngle can follow den==num>>16 without division.
Procedure.i WallWallDistanceChecked(Hyp.l, Sineval.l, *Distance.Long)
  WallProjectSetError("")
  If *Distance = 0
    WallProjectSetError("WallWallDistanceChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If Hyp <= 0
    WallProjectSetError("Wall distance input hyp must be a positive fixed value: " + Str(Hyp) + ".")
    ProcedureReturn #False
  EndIf
  If Sineval < 0 Or Sineval > #FRACUNIT
    WallProjectSetError("Wall distance sine value is outside the positive fixed sine domain: " + Str(Sineval) + ".")
    ProcedureReturn #False
  EndIf

  *Distance\l = FixedMul(Hyp, Sineval)
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_ScaleFromGlobalAngle exact calculation
; ---------------------------------------------------------------------------

; C `int angle` low-32 interpretation + `angle>>ANGLETOFINESHIFT` followed by
; a checked finesine lookup. The source `int` angle can only be a valid 0..4095
; index when the unsigned expression's low32 is < $80000000; larger raw values
; are negative signed indexes/out-of-domain table accesses and are rejected,
; never masked. *FineIndex and *Sine are untouched on failure.
Procedure.i WallSignedSineIndexChecked(RawAngle.q, *FineIndex.Long, *Sine.Long)
  Protected wrapped.q
  Protected signedAngle.q
  Protected fineIndex.l

  WallProjectSetError("")
  If *FineIndex = 0 Or *Sine = 0
    WallProjectSetError("WallSignedSineIndexChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  wrapped = BamWrap32(RawAngle)
  If wrapped > $7FFFFFFF
    WallProjectSetError("R_ScaleFromGlobalAngle signed angle low32 is $80000000+ (negative C int) and outside the finesine index domain: raw $ " + Hex(wrapped) + ".")
    ProcedureReturn #False
  EndIf

  signedAngle = wrapped
  fineIndex = Int(signedAngle) >> #BAM_ANGLETOFINESHIFT
  If fineIndex < 0 Or fineIndex > #TRIG_SINE_COUNT - 1
    WallProjectSetError("R_ScaleFromGlobalAngle sine index " + Str(fineIndex) + " is outside finesine.")
    ProcedureReturn #False
  EndIf
  If TrigSineChecked(fineIndex, *Sine) = #False
    WallProjectSetError("R_ScaleFromGlobalAngle sine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  *FineIndex\l = fineIndex
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; Shared source branch given the two checked sines:
;   num = FixedMul(projection,sineb) << detailshift(0);
;   den = FixedMul(rw_distance,sinea);
;   if den > num>>16 -> FixedDiv(num,den), clamp 256..64*FRACUNIT;
;   else -> 64*FRACUNIT.
; The C `num>>16` is an arithmetic signed shift and is used unchanged.
Procedure.i WallScaleFromSinesChecked(Projection.l, Distance.l,
                                     SineA.l, SineB.l, *Scale.Long)
  Protected num.l
  Protected numHigh.l
  Protected den.l
  Protected scale.l = 0

  WallProjectSetError("")
  If *Scale = 0
    WallProjectSetError("WallScaleFromSinesChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf

  num = FixedMul(Projection, SineB)
  numHigh = num >> #FRACBITS
  den = FixedMul(Distance, SineA)
  If den > numHigh
    scale = FixedDiv(num, den)
    If scale > #WALLPROJ_ScaleMax
      scale = #WALLPROJ_ScaleMax
    ElseIf scale < #WALLPROJ_ScaleMin
      scale = #WALLPROJ_ScaleMin
    EndIf
  Else
    scale = #WALLPROJ_ScaleMax
  EndIf

  *Scale\l = scale
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; Exact R_ScaleFromGlobalAngle:
;   anglea = ANG90 + (visangle - viewangle)     [unsigned wrap -> C int]
;   angleb = ANG90 + (visangle - rw_normalangle)
;   sinea/sineb = finesine[angle >> 19]
; then shared num/den/clamp branch. detailshift=0 for the canonical view.
Procedure.i WallScaleFromGlobalAngleChecked(ViewAngle.q, VisAngle.q,
                                           NormalAngle.q, Distance.l,
                                           Projection.l, *Scale.Long)
  Protected angleA.q
  Protected angleB.q
  Protected angleAIndex.l = 0
  Protected angleBIndex.l = 0
  Protected sineA.l = 0
  Protected sineB.l = 0

  WallProjectSetError("")
  If *Scale = 0
    WallProjectSetError("WallScaleFromGlobalAngleChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(ViewAngle) = 0 Or BamRawInUnsignedDomain(VisAngle) = 0 Or
     BamRawInUnsignedDomain(NormalAngle) = 0
    WallProjectSetError("Wall scale input angle is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf

  angleA = BamAdd(BamSubtract(VisAngle, ViewAngle), #BAM_ANG90)
  angleB = BamAdd(BamSubtract(VisAngle, NormalAngle), #BAM_ANG90)

  If WallSignedSineIndexChecked(angleA, @angleAIndex, @sineA) = #False
    WallProjectSetError("Wall scale anglea sine failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If WallSignedSineIndexChecked(angleB, @angleBIndex, @sineB) = #False
    WallProjectSetError("Wall scale angleb sine failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf

  If WallScaleFromSinesChecked(Projection, Distance, sineA, sineB, *Scale) = #False
    ProcedureReturn #False
  EndIf
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; Signed quotient truncated toward zero, explicit integer formula (span divisor
; is positive; numerator sign carried separately).
Procedure.q WallQuotientTruncTowardZero(Numerator.q, Denominator.q)
  Protected magnitudeN.q
  Protected magnitudeD.q
  Protected quotient.q

  If Numerator < 0
    magnitudeN = -Numerator
  Else
    magnitudeN = Numerator
  EndIf
  If Denominator < 0
    magnitudeD = -Denominator
  Else
    magnitudeD = Denominator
  EndIf
  quotient = magnitudeN / magnitudeD
  If Numerator < 0 And Denominator >= 0
    quotient = -quotient
  ElseIf Numerator >= 0 And Denominator < 0
    quotient = -quotient
  EndIf
  ProcedureReturn quotient
EndProcedure

; Original scale endpoint/step:
;   scale1 at FirstX; scale2 at LastX when LastX>FirstX;
;   scaleStep = (scale2-scale1)/(LastX-FirstX), C integer trunc toward zero;
;   single column -> scale2=scale1, scaleStep=0.
; The source scale2-scale1 subtraction is signed32; an actual signed-overflow
; difference is rejected as an edge diagnostic rather than wrapped.
Procedure.i WallScaleStepChecked(FirstX.l, LastX.l, Scale1.l, Scale2.l,
                                 *FinalScale2.Long, *ScaleStep.Long)
  Protected difference.q
  Protected span.l
  Protected quotient.q

  WallProjectSetError("")
  If *FinalScale2 = 0 Or *ScaleStep = 0
    WallProjectSetError("WallScaleStepChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If FirstX < 0 Or LastX < 0 Or FirstX > #PROJ_VIEWWIDTH - 1 Or
     LastX > #PROJ_VIEWWIDTH - 1 Or FirstX > LastX
    WallProjectSetError("Wall scale step columns are invalid: " + Str(FirstX) + ".." + Str(LastX) + ".")
    ProcedureReturn #False
  EndIf

  If LastX = FirstX
    PokeL(*FinalScale2, Scale1)
    *ScaleStep\l = 0
    gWallProject_LastError = ""
    ProcedureReturn #True
  EndIf

  difference.q = Int(Scale2) - Int(Scale1)
  If difference.q < #FIXED_MIN Or difference.q > #FIXED_MAX
    WallProjectSetError("Wall scale endpoint difference overflows signed 32-bit fixed_t: " + Str(difference) + ".")
    ProcedureReturn #False
  EndIf

  span = LastX - FirstX
  quotient.q = WallQuotientTruncTowardZero(difference, Int(span))
  PokeL(*FinalScale2, Scale2)
  *ScaleStep\l = FixedWrap32Low(quotient)
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Sky identity and wall-slot presence
; ---------------------------------------------------------------------------

; Original skyflatnum identity for one sector ceiling flat. Catalog-aware:
; canonical slot is required, the name must resolve, and F_SKY1 must exist in
; the same flat catalog. Fallback: only a canonical raw eight-byte F_SKY1 name
; is sky; canonical unused/malformed slots are conservatively non-sky and never
; trigger the outdoor hack. Read failures are explicit.
Procedure.i WallSectorSkyChecked(*Level.MapLevel, *Flats.FlatCatalog,
                                 SectorIndex.l, *IsSky.Long, *SkyIndex.Long)
  Protected status.i
  Protected nameFlat.WallSlotNameOut
  Protected ceilingIndex.i
  Protected skyNameIndex.i

  WallProjectSetError("")
  If *IsSky = 0
    WallProjectSetError("WallSectorSkyChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallProjectSetError("Wall sky check: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If SectorIndex < 0 Or SectorIndex >= *Level\Sectors\Count
    WallProjectSetError("Wall sky check: sector index " + Str(SectorIndex) + " is out of range.")
    ProcedureReturn #False
  EndIf

  status = WallFlatSlotStatus(*Level, SectorIndex, 1, @nameFlat)
  If status = 3
    WallProjectSetError("Wall sky check: ceiling flat slot read failed at sector " + Str(SectorIndex) + ".")
    ProcedureReturn #False
  EndIf

  If *Flats <> 0
    If status = 2
      WallProjectSetError("Wall sky check: sector " + Str(SectorIndex) + " ceiling flat slot is noncanonical.")
      ProcedureReturn #False
    EndIf
    If status = 1
      *IsSky\l = 0
      If *SkyIndex <> 0
        *SkyIndex\l = -1
      EndIf
      ProcedureReturn #True
    EndIf
    ceilingIndex = FlatCatalogFindName(*Flats, nameFlat\Value)
    If ceilingIndex < 0
      WallProjectSetError("Wall sky check: ceiling flat not found in catalog: " + nameFlat\Value)
      ProcedureReturn #False
    EndIf
    skyNameIndex = FlatCatalogFindName(*Flats, #WALLPROJ_SkyFlatName)
    If skyNameIndex < 0
      WallProjectSetError("Wall sky check: catalog has no F_SKY1 flat (skyflatnum cannot be resolved).")
      ProcedureReturn #False
    EndIf
    *IsSky\l = Bool(ceilingIndex = skyNameIndex)
    If *SkyIndex <> 0
      *SkyIndex\l = skyNameIndex
    EndIf
    gWallProject_LastError = ""
    ProcedureReturn #True
  EndIf

  If status = 2
    *IsSky\l = 0
    If *SkyIndex <> 0
      *SkyIndex\l = -1
    EndIf
    ProcedureReturn #True
  EndIf
  If status = 1
    *IsSky\l = 0
    If *SkyIndex <> 0
      *SkyIndex\l = -1
    EndIf
    ProcedureReturn #True
  EndIf
  *IsSky\l = Bool(nameFlat\Value = #WALLPROJ_SkyFlatName)
  If *SkyIndex <> 0
    *SkyIndex\l = -1
  EndIf
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; Original texturetranslation[]-driven tier presence for one sidedef slot field
; (0=top,1=bottom,2=middle):
;   catalog-aware: canonical name resolves; absent "-"/all-NUL -> 0; resolved
;     index 0 is original NoTexture -> absent; malformed/missing -> explicit error;
;   fallback: canonical "-"/all-NUL absent; canonical nonempty present with no
;     invented numeric index; noncanonical conservative present debug geometry.
; Returns Present=1 when the debug tier may be drawn; no source pixel is read.
Procedure.i WallSideTexturePresentChecked(*Level.MapLevel, *Textures.TextureCatalog,
                                          SideIndex.l, Field.l, *Present.Long)
  Protected status.i
  Protected nameSlot.WallSlotNameOut
  Protected resolvedIndex.i

  WallProjectSetError("")
  If *Present = 0
    WallProjectSetError("WallSideTexturePresentChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallProjectSetError("Wall texture presence: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If SideIndex < 0 Or SideIndex >= *Level\Sidedefs\Count
    WallProjectSetError("Wall texture presence: sidedef index " + Str(SideIndex) + " is out of range.")
    ProcedureReturn #False
  EndIf
  If Field < 0 Or Field > 2
    WallProjectSetError("Wall texture presence: sidedef texture field " + Str(Field) + " must be 0,1,2.")
    ProcedureReturn #False
  EndIf

  status = WallWallSlotStatus(*Level, SideIndex, Field, @nameSlot)
  If status = 3
    WallProjectSetError("Wall texture presence: sidedef " + Str(SideIndex) + " field " + Str(Field) + " read failed.")
    ProcedureReturn #False
  EndIf

  If *Textures <> 0
    If status = 2
      WallProjectSetError("Wall texture presence: sidedef " + Str(SideIndex) +
                          " field " + Str(Field) + " name is noncanonical.")
      ProcedureReturn #False
    EndIf
    If status = 1
      *Present\l = 0
      ProcedureReturn #True
    EndIf
    resolvedIndex = TextureCatalogFindName(*Textures, nameSlot\Value)
    If resolvedIndex < 0
      WallProjectSetError("Wall texture presence: sidedef " + Str(SideIndex) +
                          " field " + Str(Field) + " texture not found in catalog: " + nameSlot\Value)
      ProcedureReturn #False
    EndIf
    *Present\l = Bool(resolvedIndex <> 0)
    gWallProject_LastError = ""
    ProcedureReturn #True
  EndIf

  If status = 2
    *Present\l = 1
    ProcedureReturn #True
  EndIf
  If status = 1
    *Present\l = 0
    ProcedureReturn #True
  EndIf
  *Present\l = 1
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Per-span plan construction
; ---------------------------------------------------------------------------

; Recomputes and publishes the M3-05 useful R_StoreWallRange geometry into
; *Plan. `SpanIndex` is diagnostic metadata; all map record indexes are re-read
; and cross-checked through validated MapLevel APIs before any arithmetic.
; Returns #False with ready=0 on any invalid input, malformed identity, out-of-
; domain table index or unsupported documented arithmetic edge.
Procedure.i WallProjectSpanChecked(*Level.MapLevel, *Flats.FlatCatalog,
                                   *Textures.TextureCatalog,
                                   *Projection.Projection,
                                   ViewX.l, ViewY.l, HeadingRaw.q, ViewZFixed.l,
                                   SpanIndex.l, *Span.WallSpan,
                                   *Plan.WallSpanPlan)
  Protected spanSub.l
  Protected spanSeg.l
  Protected spanLine.l
  Protected spanSide.l
  Protected spanFront.l
  Protected spanBack.l
  Protected spanFirst.l
  Protected spanLast.l
  Protected spanKind.l
  Protected segV1.l
  Protected segV2.l
  Protected segAngleRaw.l
  Protected segLine.l
  Protected segSide.l
  Protected segOffset.l
  Protected linkLine.l
  Protected linkSide.l
  Protected linkFront.l
  Protected linkBack.l
  Protected vertexX1.l
  Protected vertexY1.l
  Protected fixedX1.l = 0
  Protected fixedY1.l = 0
  Protected subFirstSeg.l
  Protected subNumSegs.l
  Protected lineFlags.l
  Protected lineSpecial.l
  Protected lineTag.l
  Protected lineSide0.l
  Protected lineSide1.l
  Protected selectedSide.l
  Protected selectedSector.l
  Protected frontFloor.l
  Protected frontCeiling.l
  Protected frontLight.l
  Protected backFloor.l
  Protected backCeiling.l
  Protected backLight.l
  Protected frontFloorFixed.l = 0
  Protected frontCeilingFixed.l = 0
  Protected backFloorFixed.l = 0
  Protected backCeilingFixed.l = 0
  Protected clampedOffset.q
  Protected distAngle.q
  Protected sineIndex.l = 0
  Protected sineval.l = 0
  Protected scaleRaw.q
  Protected normalAngle.q
  Protected referenceAngle.BamAngleValue
  Protected magnitude.q = 0
  Protected offsetAngle.q = 0
  Protected hyp.l = 0
  Protected distance.l = 0
  Protected inverseFirst.q = 0
  Protected inverseLast.q = 0
  Protected visFirst.q
  Protected visLast.q
  Protected scale1.l = 0
  Protected scale2.l = 0
  Protected scaleStep.l = 0
  Protected finalScale2.l = 0
  Protected sameFloor.l = 0
  Protected sameCeiling.l = 0
  Protected sameLight.i = #False
  Protected topPresent.l = 0
  Protected bottomPresent.l = 0
  Protected middlePresent.l = 0
  Protected frontSky.l = 0
  Protected backSky.l = 0
  Protected skyIndex.l = 0
  Protected topRegion.i = #False
  Protected bottomRegion.i = #False
  Protected markFloor.i = #False
  Protected markCeiling.i = #False
  Protected closedDoor.i = #False
  Protected skyHack.i = #False
  Protected validityText.s = ""

  WallProjectSetError("")
  If *Plan = 0
    WallProjectSetError("WallProjectSpanChecked: plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If WallSpanPlanReset(*Plan) = #False
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallProjectSetError("WallSpan projection: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    WallProjectSetError("WallSpan projection: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Projection\Width <> #PROJ_VIEWWIDTH Or *Projection\ViewHeight <> #PROJ_VIEWHEIGHT
    WallProjectSetError("WallSpan projection: non-canonical 320x200 viewport.")
    ProcedureReturn #False
  EndIf
  If *Span = 0
    WallProjectSetError("WallSpan projection: span pointer is null.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(HeadingRaw) = 0
    WallProjectSetError("WallSpan projection: camera heading is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf

  spanSub = *Span\Subsector
  spanSeg = *Span\Seg
  spanLine = *Span\Linedef
  spanSide = *Span\Side
  spanFront = *Span\FrontSector
  spanBack = *Span\BackSector
  spanFirst = *Span\FirstX
  spanLast = *Span\LastX
  spanKind = *Span\Kind

  If SpanIndex < 0
    WallProjectSetError("WallSpan projection span index is negative: " + Str(SpanIndex) + ".")
    ProcedureReturn #False
  EndIf
  If spanFirst < 0 Or spanLast < 0 Or spanFirst > #PROJ_VIEWWIDTH - 1 Or
     spanLast > #PROJ_VIEWWIDTH - 1 Or spanFirst > spanLast
    WallProjectSetError("WallSpan projection columns are invalid: " + Str(spanFirst) + ".." + Str(spanLast) + ".")
    ProcedureReturn #False
  EndIf
  If spanKind <> #WALL_KIND_SOLID And spanKind <> #WALL_KIND_PASS
    WallProjectSetError("WallSpan projection kind is not SOLID/PASS: " + Str(spanKind) + ".")
    ProcedureReturn #False
  EndIf
  If spanSub < 0 Or spanSub >= *Level\Subsectors\Count
    WallProjectSetError("WallSpan projection subsector index is invalid: " + Str(spanSub) + ".")
    ProcedureReturn #False
  EndIf
  If spanSeg < 0 Or spanSeg >= *Level\Segs\Count
    WallProjectSetError("WallSpan projection seg index is invalid: " + Str(spanSeg) + ".")
    ProcedureReturn #False
  EndIf
  If spanLine < 0 Or spanLine >= *Level\Linedefs\Count
    WallProjectSetError("WallSpan projection linedef index is invalid: " + Str(spanLine) + ".")
    ProcedureReturn #False
  EndIf
  If spanSide <> 0 And spanSide <> 1
    WallProjectSetError("WallSpan projection side is invalid: " + Str(spanSide) + ".")
    ProcedureReturn #False
  EndIf
  If spanFront < 0 Or spanFront >= *Level\Sectors\Count
    WallProjectSetError("WallSpan projection front sector index is invalid: " + Str(spanFront) + ".")
    ProcedureReturn #False
  EndIf
  If spanBack <> #WALLPROJ_NoSector And
     (spanBack < 0 Or spanBack >= *Level\Sectors\Count)
    WallProjectSetError("WallSpan projection back sector index is invalid: " + Str(spanBack) + ".")
    ProcedureReturn #False
  EndIf

  If MapSubsectorsGet(@*Level\Subsectors, spanSub, @subNumSegs, @subFirstSeg) = #False
    WallProjectSetError("WallSpan projection cannot read subsector " + Str(spanSub) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If subNumSegs <= 0 Or subFirstSeg < 0 Or
     spanSeg < subFirstSeg Or spanSeg >= subFirstSeg + subNumSegs
    WallProjectSetError("WallSpan projection seg " + Str(spanSeg) +
                         " is outside subsector " + Str(spanSub) + "'s segment range.")
    ProcedureReturn #False
  EndIf

  If MapSegsGet(@*Level\Segs, spanSeg, @segV1, @segV2, @segAngleRaw,
                @segLine, @segSide, @segOffset) = #False
    WallProjectSetError("WallSpan projection cannot read seg " + Str(spanSeg) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If segLine <> spanLine Or segSide <> spanSide Or
     segV1 < 0 Or segV1 >= *Level\Vertexes\Count Or
     segV2 < 0 Or segV2 >= *Level\Vertexes\Count
    WallProjectSetError("WallSpan projection seg " + Str(spanSeg) +
                         " decoded fields disagree with the published span/vertex indexes.")
    ProcedureReturn #False
  EndIf

  If MapLevelGetSegLinks(*Level, spanSeg, @linkLine, @linkSide, @linkFront,
                         @linkBack) = #False
    WallProjectSetError("WallSpan projection cannot read seg links: " + MapLevelLastError())
    ProcedureReturn #False
  EndIf
  If linkLine <> spanLine Or linkSide <> spanSide Or
     linkFront <> spanFront Or linkBack <> spanBack
    WallProjectSetError("WallSpan projection seg " + Str(spanSeg) +
                         " derived links disagree with the published span.")
    ProcedureReturn #False
  EndIf

  If MapLinedefsGet(@*Level\Linedefs, spanLine, 0, 0, @lineFlags, @lineSpecial,
                    @lineTag, @lineSide0, @lineSide1) = #False
    WallProjectSetError("WallSpan projection cannot read linedef " + Str(spanLine) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If spanSide = 0
    selectedSide = lineSide0
  Else
    selectedSide = lineSide1
  EndIf
  If selectedSide < 0 Or selectedSide >= *Level\Sidedefs\Count
    WallProjectSetError("WallSpan projection seg " + Str(spanSeg) + " selects a missing sidedef.")
    ProcedureReturn #False
  EndIf
  If MapSidedefsGet(@*Level\Sidedefs, selectedSide, 0, 0, @selectedSector) = #False
    WallProjectSetError("WallSpan projection cannot read sidedef " + Str(selectedSide) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If selectedSector <> spanFront
    WallProjectSetError("WallSpan projection sidedef sector disagrees with the published front sector.")
    ProcedureReturn #False
  EndIf

  If MapVertexesGet(@*Level\Vertexes, segV1, @vertexX1, @vertexY1) = #False
    WallProjectSetError("WallSpan projection cannot read seg v1 vertex " + Str(segV1) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexX1, @fixedX1) = #False
    WallProjectSetError("WallSpan projection v1 X conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexY1, @fixedY1) = #False
    WallProjectSetError("WallSpan projection v1 Y conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  If MapSectorsGet(@*Level\Sectors, spanFront, @frontFloor, @frontCeiling,
                   @frontLight, 0, 0) = #False
    WallProjectSetError("WallSpan projection cannot read front sector " + Str(spanFront) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(frontFloor, @frontFloorFixed) = #False
    WallProjectSetError("WallSpan projection front floor conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(frontCeiling, @frontCeilingFixed) = #False
    WallProjectSetError("WallSpan projection front ceiling conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  backFloor = 0
  backCeiling = 0
  backLight = 0
  backFloorFixed = 0
  backCeilingFixed = 0
  If spanBack <> #WALLPROJ_NoSector
    If MapSectorsGet(@*Level\Sectors, spanBack, @backFloor, @backCeiling,
                     @backLight, 0, 0) = #False
      WallProjectSetError("WallSpan projection cannot read back sector " + Str(spanBack) + ": " + MapDecodeLastError())
      ProcedureReturn #False
    EndIf
    If FixedFromIntChecked(backFloor, @backFloorFixed) = #False
      WallProjectSetError("WallSpan projection back floor conversion failed: " + FixedLastError())
      ProcedureReturn #False
    EndIf
    If FixedFromIntChecked(backCeiling, @backCeilingFixed) = #False
      WallProjectSetError("WallSpan projection back ceiling conversion failed: " + FixedLastError())
      ProcedureReturn #False
    EndIf
  Else
    backFloorFixed = frontFloorFixed
    backCeilingFixed = frontCeilingFixed
  EndIf

  ; Original raw rw_normalangle and original unclipped v1 reference angle.
  If WallSegRawAngleToBamChecked(segAngleRaw, @scaleRaw) = #False
    WallProjectSetError("WallSpan projection seg raw-angle conversion failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If WallSegNormalAngleChecked(segAngleRaw, @normalAngle) = #False
    WallProjectSetError("WallSpan projection normal-angle conversion failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If GeometryPointToAngleChecked(ViewX, ViewY, fixedX1, fixedY1, @referenceAngle) = #False
    WallProjectSetError("WallSpan projection seg v1 reference angle failed: " + GeometryLastError())
    ProcedureReturn #False
  EndIf

  If WallAngleOffsetChecked(normalAngle, referenceAngle\Raw, @magnitude, @offsetAngle) = #False
    WallProjectSetError("WallSpan projection angular offset failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If WallDistanceAngleChecked(offsetAngle, @clampedOffset, @distAngle,
                              @sineIndex, @sineval) = #False
    WallProjectSetError("WallSpan projection distance angle/sine failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If WallSegPointDistanceChecked(ViewX, ViewY, fixedX1, fixedY1, @hyp) = #False
    WallProjectSetError("WallSpan projection seg v1 point distance failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If WallWallDistanceChecked(hyp, sineval, @distance) = #False
    WallProjectSetError("WallSpan projection wall distance failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf

  If ProjectionGetXToViewAngle(*Projection, spanFirst, @inverseFirst) = #False
    WallProjectSetError("WallSpan projection first-column inverse angle failed: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf
  visFirst = BamAdd(HeadingRaw, inverseFirst)
  If WallScaleFromGlobalAngleChecked(HeadingRaw, visFirst, normalAngle,
                                     distance, *Projection\ProjectionFixed,
                                     @scale1) = #False
    WallProjectSetError("WallSpan projection scale1 failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If spanLast > spanFirst
    If ProjectionGetXToViewAngle(*Projection, spanLast, @inverseLast) = #False
      WallProjectSetError("WallSpan projection last-column inverse angle failed: " + ProjectionLastError())
      ProcedureReturn #False
    EndIf
    visLast = BamAdd(HeadingRaw, inverseLast)
    If WallScaleFromGlobalAngleChecked(HeadingRaw, visLast, normalAngle,
                                       distance, *Projection\ProjectionFixed,
                                       @scale2) = #False
      WallProjectSetError("WallSpan projection scale2 failed: " + WallProjectLastError())
      ProcedureReturn #False
    EndIf
  Else
    scale2 = scale1
  EndIf
  If WallScaleStepChecked(spanFirst, spanLast, scale1, scale2,
                          @finalScale2, @scaleStep) = #False
    WallProjectSetError("WallSpan projection scale step failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  scale2 = finalScale2

  ; Front/back original fixed offsets, explicit widened subtraction policy.
  *Plan\WorldTopRaw = WallFixedSubLow(frontCeilingFixed, ViewZFixed)
  *Plan\WorldBottomRaw = WallFixedSubLow(frontFloorFixed, ViewZFixed)
  If spanBack <> #WALLPROJ_NoSector
    *Plan\WorldHighRaw = WallFixedSubLow(backCeilingFixed, ViewZFixed)
    *Plan\WorldLowRaw = WallFixedSubLow(backFloorFixed, ViewZFixed)
  Else
    *Plan\WorldHighRaw = 0
    *Plan\WorldLowRaw = 0
  EndIf

  ; Sky-flat identity and source outdoor-height hack (before mark/shift).
  If WallSectorSkyChecked(*Level, *Flats, spanFront, @frontSky, @skyIndex) = #False
    WallProjectSetError("WallSpan projection front sky identity failed: " + WallProjectLastError())
    ProcedureReturn #False
  EndIf
  If spanBack <> #WALLPROJ_NoSector
    If WallSectorSkyChecked(*Level, *Flats, spanBack, @backSky, @skyIndex) = #False
      WallProjectSetError("WallSpan projection back sky identity failed: " + WallProjectLastError())
      ProcedureReturn #False
    EndIf
    If frontSky <> 0 And backSky <> 0
      skyHack = #True
      *Plan\WorldTopRaw = *Plan\WorldHighRaw
    EndIf
  Else
    backSky = 0
  EndIf

  ; Original source classification/closed-door tests on signed map-unit heights.
  If spanBack <> #WALLPROJ_NoSector
    If backCeiling <= frontFloor Or backFloor >= frontCeiling
      closedDoor = #True
    EndIf
  EndIf

  If spanBack = #WALLPROJ_NoSector
    markFloor = #True
    markCeiling = #True
    If WallSideTexturePresentChecked(*Level, *Textures, selectedSide, 2,
                                     @middlePresent) = #False
      WallProjectSetError("WallSpan projection middle texture presence failed: " + WallProjectLastError())
      ProcedureReturn #False
    EndIf
    topPresent = 0
    bottomPresent = 0
  Else
    sameLight = Bool(backLight = frontLight)
    If WallSectorFlatIdentity(*Level, *Flats, spanFront, spanBack, 0,
                              @sameFloor) = #False
      WallProjectSetError("WallSpan projection floor flat identity failed: " + WallIdentityLastError())
      ProcedureReturn #False
    EndIf
    If WallSectorFlatIdentity(*Level, *Flats, spanFront, spanBack, 1,
                              @sameCeiling) = #False
      WallProjectSetError("WallSpan projection ceiling flat identity failed: " + WallIdentityLastError())
      ProcedureReturn #False
    EndIf
    markFloor = Bool(*Plan\WorldLowRaw <> *Plan\WorldBottomRaw Or
                     sameFloor = 0 Or sameLight = #False)
    markCeiling = Bool(*Plan\WorldHighRaw <> *Plan\WorldTopRaw Or
                       sameCeiling = 0 Or sameLight = #False)
    If closedDoor
      markFloor = #True
      markCeiling = #True
    EndIf
    topRegion = Bool(*Plan\WorldHighRaw < *Plan\WorldTopRaw)
    bottomRegion = Bool(*Plan\WorldLowRaw > *Plan\WorldBottomRaw)
    If topRegion
      If WallSideTexturePresentChecked(*Level, *Textures, selectedSide, 0,
                                       @topPresent) = #False
        WallProjectSetError("WallSpan projection top texture presence failed: " + WallProjectLastError())
        ProcedureReturn #False
      EndIf
    Else
      topPresent = 0
    EndIf
    If bottomRegion
      If WallSideTexturePresentChecked(*Level, *Textures, selectedSide, 1,
                                       @bottomPresent) = #False
        WallProjectSetError("WallSpan projection bottom texture presence failed: " + WallProjectLastError())
        ProcedureReturn #False
      EndIf
    Else
      bottomPresent = 0
    EndIf
    middlePresent = 0
  EndIf

  ; Original front-plane wrong-side override (sky exempt for ceiling).
  If frontFloorFixed >= ViewZFixed
    markFloor = #False
  EndIf
  If frontCeilingFixed <= ViewZFixed And frontSky = 0
    markCeiling = #False
  EndIf

  *Plan\WorldTop = *Plan\WorldTopRaw >> 4
  *Plan\WorldBottom = *Plan\WorldBottomRaw >> 4
  If spanBack <> #WALLPROJ_NoSector
    *Plan\WorldHigh = *Plan\WorldHighRaw >> 4
    *Plan\WorldLow = *Plan\WorldLowRaw >> 4
  Else
    *Plan\WorldHigh = 0
    *Plan\WorldLow = 0
  EndIf

  *Plan\TopStep = WallHeightStepNegated(scaleStep, *Plan\WorldTop)
  *Plan\TopFrac = WallHeightStart(#PROJ_CENTERYFIXED >> 4, *Plan\WorldTop, scale1)
  *Plan\BottomStep = WallHeightStepNegated(scaleStep, *Plan\WorldBottom)
  *Plan\BottomFrac = WallHeightStart(#PROJ_CENTERYFIXED >> 4, *Plan\WorldBottom, scale1)

  If spanBack <> #WALLPROJ_NoSector And topRegion
    *Plan\PixHigh = WallHeightStart(#PROJ_CENTERYFIXED >> 4, *Plan\WorldHigh, scale1)
    *Plan\PixHighStep = WallHeightStepNegated(scaleStep, *Plan\WorldHigh)
  Else
    *Plan\PixHigh = 0
    *Plan\PixHighStep = 0
  EndIf
  If spanBack <> #WALLPROJ_NoSector And bottomRegion
    *Plan\PixLow = WallHeightStart(#PROJ_CENTERYFIXED >> 4, *Plan\WorldLow, scale1)
    *Plan\PixLowStep = WallHeightStepNegated(scaleStep, *Plan\WorldLow)
  Else
    *Plan\PixLow = 0
    *Plan\PixLowStep = 0
  EndIf

  ; Numeric publication. No pointers retained.
  *Plan\SpanIndex = SpanIndex
  *Plan\Subsector = spanSub
  *Plan\Seg = spanSeg
  *Plan\Linedef = spanLine
  *Plan\Side = spanSide
  *Plan\FrontSector = spanFront
  *Plan\BackSector = spanBack
  *Plan\FirstX = spanFirst
  *Plan\LastX = spanLast
  *Plan\Kind = spanKind
  *Plan\ViewAngle = BamWrap32(HeadingRaw)
  *Plan\SegAngleBam = BamWrap32(scaleRaw)
  *Plan\NormalAngle = normalAngle
  *Plan\ReferenceAngle = referenceAngle\Raw
  *Plan\RawAngularSeparation = magnitude
  *Plan\OffsetAngle = clampedOffset
  *Plan\DistAngle = distAngle
  *Plan\Hyp = hyp
  *Plan\Distance = distance
  *Plan\Scale1 = scale1
  *Plan\Scale2 = scale2
  *Plan\ScaleStep = scaleStep
  *Plan\FrontFloorMap = frontFloor
  *Plan\FrontCeilingMap = frontCeiling
  *Plan\FrontLight = frontLight
  *Plan\BackFloorMap = backFloor
  *Plan\BackCeilingMap = backCeiling
  *Plan\BackLight = backLight
  *Plan\FrontFloorFixed = frontFloorFixed
  *Plan\FrontCeilingFixed = frontCeilingFixed
  *Plan\BackFloorFixed = backFloorFixed
  *Plan\BackCeilingFixed = backCeilingFixed
  *Plan\MarkFloor = Bool(markFloor)
  *Plan\MarkCeiling = Bool(markCeiling)
  *Plan\TopRegion = Bool(topRegion)
  *Plan\BottomRegion = Bool(bottomRegion)
  *Plan\TopTexturePresent = topPresent
  *Plan\BottomTexturePresent = bottomPresent
  *Plan\MiddleTexturePresent = middlePresent
  *Plan\TopTier = Bool(spanBack <> #WALLPROJ_NoSector And topRegion And topPresent <> 0)
  *Plan\BottomTier = Bool(spanBack <> #WALLPROJ_NoSector And bottomRegion And bottomPresent <> 0)
  *Plan\MiddleTier = Bool(spanBack = #WALLPROJ_NoSector And middlePresent <> 0)
  *Plan\FrontSky = Bool(frontSky)
  *Plan\BackSky = Bool(backSky)
  *Plan\SkyHack = Bool(skyHack)
  *Plan\ClosedDoor = Bool(closedDoor)
  *Plan\TwoSided = Bool(spanBack <> #WALLPROJ_NoSector)
  *Plan\Ready = 1
  gWallProject_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
