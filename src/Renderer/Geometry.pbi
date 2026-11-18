; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Renderer-side geometry primitives from Linux Doom 1.10 r_main.c:
;   R_PointToAngle / R_PointToAngle2 -> GeometryPointToAngleChecked /
;                                       GeometryPointToAngle2Checked
;   R_PointToDist                    -> GeometryPointToDistChecked
;   R_PointOnSide                    -> GeometryPointOnNodeSideChecked
;   R_PointOnSegSide                 -> GeometryPointOnSegSideChecked
;
; BAM results are published through BamAngleValue.Raw (raw unsigned 32-bit) to
; avoid an ambiguous zero sentinel and a signed .l for ANG180/ANG270. Distance
; and side values use a checked output pointer; side 0 and side 1 are both valid,
; so failures are never encoded as a side or as distance 0.
;
; Numeric policy (documented deviation for C undefined operations):
;   - fixed coordinate arguments are signed32 fixed_t values;
;   - deltas are computed widened in .q and rejected with a diagnostic when they
;     escape [-2147483648,2147483647]; original C subtraction would overflow;
;   - a negative delta of exactly INT32_MIN is allowed: its unsigned magnitude
;     2147483648 is used for slope comparison/SlopeDiv, whereas C negation/abs
;     is undefined; for distance the same magnitude follows the original
;     conservative FixedDiv guard/formula through an explicit widened helper;
;   - an all-zero delta never reads tantoangle: distance returns fixed 0
;     (deterministic DoomPB policy) instead of the original's invalid 0/0 index.
; Pure four-coordinate wrappers do not mutate viewx/viewy globals; numerical
; equivalence with R_PointToAngle2 is tested.
;
; All scalar helpers are heap-free and independent of WAD/map/graphics state.
; Side helpers use validated indexes only via the MapLevel adapter externally;
; The pure functions take fixed coordinate and line-direction values explicitly.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_GEOMETRY_PBI, #PB_Constant) = 0

#DOOMPB_GEOMETRY_PBI = 1

XIncludeFile "../Core/TrigTables.pbi"

Global gGeometry_LastError.s = ""

Procedure GeometrySetError(Message.s)
  gGeometry_LastError = Message
EndProcedure

Procedure.s GeometryLastError()
  ProcedureReturn gGeometry_LastError
EndProcedure

; Widened nonnegative magnitude division preserving FixedDiv's original guard:
;   if ((abs(a) >> 14) >= abs(b)) return sign-dependent saturation;
; This helper is only used when a magnitude above signed32 (an INT32_MIN delta's
; absolute value) cannot be represented as fixed_t .l. Both inputs are
; nonnegative, so the original sign-dependent branch always yields MAXINT. The
; guard guarantees the quotient stays inside signed32 in the non-saturated path.
Procedure.l GeometryDivMagnitude(Num.q, Den.q)
  Protected quotient.q

  If (Num >> #FIXED_DIV_GUARD_SHIFT) >= Den
    ProcedureReturn #FIXED_MAX
  EndIf

  quotient = Num * #FRACUNIT / Den
  ProcedureReturn quotient
EndProcedure

; R_PointToAngle with an explicit view origin. Original branch order, strict
; `x > y` ties, all `-1` boundary constants and unsigned angle wrap are kept.
Procedure.i GeometryPointToAngleChecked(ViewX.l, ViewY.l, X.l, Y.l, *Result.BamAngleValue)
  Protected deltaX.q
  Protected deltaY.q
  Protected magnitudeX.q
  Protected magnitudeY.q
  Protected slope.l = 0
  Protected atan.l = 0
  Protected raw.q
  Protected lowered.i
  Protected raised.i

  GeometrySetError("")
  If *Result = 0
    GeometrySetError("GeometryPointToAngleChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf

  deltaX = X - ViewX
  deltaY = Y - ViewY
  If deltaX < #FIXED_MIN Or deltaX > #FIXED_MAX
    GeometrySetError("GeometryPointToAngleChecked: X-ViewX delta " + Str(deltaX) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf
  If deltaY < #FIXED_MIN Or deltaY > #FIXED_MAX
    GeometrySetError("GeometryPointToAngleChecked: Y-ViewY delta " + Str(deltaY) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf

  If deltaX = 0 And deltaY = 0
    *Result\Raw = 0
    ProcedureReturn #True
  EndIf

  lowered = Bool(deltaX >= 0)
  raised = Bool(deltaY >= 0)
  If lowered
    magnitudeX = deltaX
  Else
    magnitudeX = -deltaX
  EndIf
  If raised
    magnitudeY = deltaY
  Else
    magnitudeY = -deltaY
  EndIf

  ; Original first-octant flip gives x>y on magnitudes. Ordinary values are
  ; signed-positive; the INT32_MIN magnitude 2147483648 has no signed peer, so
  ; the documented unsigned comparison below is used.
  If magnitudeX > magnitudeY
    If DoomSlopeDivChecked(magnitudeY, magnitudeX, @slope) = #False
      GeometrySetError("GeometryPointToAngleChecked: " + TrigLastError())
      ProcedureReturn #False
    EndIf
  Else
    If DoomSlopeDivChecked(magnitudeX, magnitudeY, @slope) = #False
      GeometrySetError("GeometryPointToAngleChecked: " + TrigLastError())
      ProcedureReturn #False
    EndIf
  EndIf
  If TrigTanToAngleChecked(slope, @atan) = #False
    GeometrySetError("GeometryPointToAngleChecked: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  If lowered
    If raised
      If magnitudeX > magnitudeY
        raw = BamWrap32(atan)
      Else
        raw = BamSubtract(#BAM_ANG90 - 1, atan)
      EndIf
    Else
      If magnitudeX > magnitudeY
        raw = BamNegate(atan)
      Else
        raw = BamAdd(#BAM_ANG270, atan)
      EndIf
    EndIf
  Else
    If raised
      If magnitudeX > magnitudeY
        raw = BamSubtract(#BAM_ANG180 - 1, atan)
      Else
        raw = BamAdd(#BAM_ANG90, atan)
      EndIf
    Else
      If magnitudeX > magnitudeY
        raw = BamAdd(#BAM_ANG180, atan)
      Else
        raw = BamSubtract(#BAM_ANG270 - 1, atan)
      EndIf
    EndIf
  EndIf

  *Result\Raw = raw
  ProcedureReturn #True
EndProcedure

; Pure four-coordinate equivalent of R_PointToAngle2. The original stores
; x1/y1 into global viewx/viewy and calls R_PointToAngle(x2,y2); this wrapper has
; the same output values with no hidden global mutation.
Procedure.i GeometryPointToAngle2Checked(X1.l, Y1.l, X2.l, Y2.l, *Result.BamAngleValue)
  ProcedureReturn GeometryPointToAngleChecked(X1, Y1, X2, Y2, *Result)
EndProcedure

; R_PointToDist with explicit view origin and the original algorithm:
;   dx = abs(x-viewx); dy = abs(y-viewy); larger first;
;   angle = (tantoangle[FixedDiv(dy,dx)>>DBITS] + ANG90) >> ANGLETOFINESHIFT;
;   dist = FixedDiv(dx, finesine[angle]);   // cosine through sin(90+theta)
Procedure.i GeometryPointToDistChecked(ViewX.l, ViewY.l, X.l, Y.l, *Result.Long)
  Protected deltaX.q
  Protected deltaY.q
  Protected magnitudeX.q
  Protected magnitudeY.q
  Protected swapped.q
  Protected magnitudeXValue.l = 0
  Protected magnitudeYValue.l = 0
  Protected ratio.l = 0
  Protected slopeIndex.l = 0
  Protected atan.l = 0
  Protected fineAngle.l = 0
  Protected sine.l = 0
  Protected distance.l = 0

  GeometrySetError("")
  If *Result = 0
    GeometrySetError("GeometryPointToDistChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf

  deltaX = X - ViewX
  deltaY = Y - ViewY
  If deltaX < #FIXED_MIN Or deltaX > #FIXED_MAX
    GeometrySetError("GeometryPointToDistChecked: X-ViewX delta " + Str(deltaX) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf
  If deltaY < #FIXED_MIN Or deltaY > #FIXED_MAX
    GeometrySetError("GeometryPointToDistChecked: Y-ViewY delta " + Str(deltaY) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf

  If deltaX >= 0
    magnitudeX = deltaX
  Else
    magnitudeX = -deltaX
  EndIf
  If deltaY >= 0
    magnitudeY = deltaY
  Else
    magnitudeY = -deltaY
  EndIf
  If magnitudeY > magnitudeX
    swapped = magnitudeX
    magnitudeX = magnitudeY
    magnitudeY = swapped
  EndIf

  ; Deterministic policy for coincident points: distance 0 and no table access.
  ; The original computes FixedDiv(0,0) -> saturation and then indexes
  ; tantoangle with a huge out-of-domain value.
  If magnitudeX = 0
    *Result\l = 0
    ProcedureReturn #True
  EndIf

  If magnitudeX <= #FIXED_MAX And magnitudeY <= #FIXED_MAX
    ; Both magnitudes proven inside signed32 here; .l narrowing is exact.
    magnitudeXValue = magnitudeX
    magnitudeYValue = magnitudeY
    ratio = FixedDiv(magnitudeYValue, magnitudeXValue)
  Else
    ratio = GeometryDivMagnitude(magnitudeY, magnitudeX)
  EndIf

  slopeIndex = ratio >> #BAM_DBITS
  If slopeIndex < 0 Or slopeIndex > #BAM_SLOPERANGE
    GeometrySetError("GeometryPointToDistChecked: slope index " + Str(slopeIndex) + " is outside the tantoangle domain.")
    ProcedureReturn #False
  EndIf
  If TrigTanToAngleChecked(slopeIndex, @atan) = #False
    GeometrySetError("GeometryPointToDistChecked: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  ; Original conversion is unsigned: (angle_t + ANG90) >> ANGLETOFINESHIFT.
  ; BamFineIndex is 0..8191 here, so its low-32 narrowing to .l is exact.
  fineAngle = BamFineIndex(BamAdd(atan, #BAM_ANG90))
  If TrigSineChecked(fineAngle, @sine) = #False
    GeometrySetError("GeometryPointToDistChecked: " + TrigLastError())
    ProcedureReturn #False
  EndIf
  If sine <= 0
    GeometrySetError("GeometryPointToDistChecked: sine lookup produced a nonpositive cosine.")
    ProcedureReturn #False
  EndIf

  If magnitudeX <= #FIXED_MAX
    magnitudeXValue = magnitudeX
    distance = FixedDiv(magnitudeXValue, sine)
  Else
    distance = GeometryDivMagnitude(magnitudeX, sine)
  EndIf

  *Result\l = distance
  ProcedureReturn #True
EndProcedure

; Shared body of R_PointOnSide/R_PointOnSegSide: origin plus a fixed line
; direction. Vertical/horizontal fast paths keep `<=` boundaries and the sign of
; the direction; the sign-bit shortcut is the original XOR expression; the
; general branch computes the two FixedMul products and returns back side on an
; exact equality tie (right is not less than left).
Procedure.i GeometryPointSideCoreChecked(Context.s, X.l, Y.l, OriginX.l, OriginY.l,
                                        LineDX.l, LineDY.l, *Result.Long)
  Protected deltaX.q
  Protected deltaY.q
  Protected signBits.q
  Protected shortcutBits.q
  Protected deltaXValue.l = 0
  Protected deltaYValue.l = 0
  Protected left.l = 0
  Protected right.l = 0

  GeometrySetError("")
  If *Result = 0
    GeometrySetError(Context + ": result pointer is null.")
    ProcedureReturn #False
  EndIf

  If LineDX = 0
    If X <= OriginX
      *Result\l = Bool(LineDY > 0)
    Else
      *Result\l = Bool(LineDY < 0)
    EndIf
    ProcedureReturn #True
  EndIf
  If LineDY = 0
    If Y <= OriginY
      *Result\l = Bool(LineDX < 0)
    Else
      *Result\l = Bool(LineDX > 0)
    EndIf
    ProcedureReturn #True
  EndIf

  deltaX = X - OriginX
  deltaY = Y - OriginY
  If deltaX < #FIXED_MIN Or deltaX > #FIXED_MAX
    GeometrySetError(Context + ": X-OriginX delta " + Str(deltaX) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf
  If deltaY < #FIXED_MIN Or deltaY > #FIXED_MAX
    GeometrySetError(Context + ": Y-OriginY delta " + Str(deltaY) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf

  ; Original 32-bit sign-bit shortcut: (dy^dx^dxdelta^dydelta)&0x80000000,
  ; then (dy^dxdelta)&0x80000000 decides "left is negative".
  signBits = BamWrap32(LineDY) ! BamWrap32(LineDX) ! BamWrap32(deltaX) ! BamWrap32(deltaY)
  If (signBits & $80000000) <> 0
    shortcutBits = BamWrap32(LineDY) ! BamWrap32(deltaX)
    If (shortcutBits & $80000000) <> 0
      *Result\l = 1
    Else
      *Result\l = 0
    EndIf
    ProcedureReturn #True
  EndIf

  ; Deltas were checked inside signed32 above; this .l narrowing is exact.
  deltaXValue = deltaX
  deltaYValue = deltaY
  left = FixedMul(FixedToIntFloor(LineDY), deltaXValue)
  right = FixedMul(deltaYValue, FixedToIntFloor(LineDX))
  If right < left
    *Result\l = 0
  Else
    *Result\l = 1
  EndIf
  ProcedureReturn #True
EndProcedure

; R_PointOnSide: node partition origin (node.x,node.y) and direction
; (node.dx,node.dy), both fixed_t. Returns checked side 0 front / 1 back.
Procedure.i GeometryPointOnNodeSideChecked(X.l, Y.l, NodeOriginX.l, NodeOriginY.l,
                                           NodeDX.l, NodeDY.l, *Result.Long)
  ProcedureReturn GeometryPointSideCoreChecked("GeometryPointOnNodeSideChecked",
                                               X, Y, NodeOriginX, NodeOriginY,
                                               NodeDX, NodeDY, *Result)
EndProcedure

; R_PointOnSegSide: starts from seg->v1, deriving ldx=v2x-v1x, ldy=v2y-v1y.
; The pure API takes fixed vertex coordinates; original directions/order are
; retained. Static endpoint deltas are checked before any product.
Procedure.i GeometryPointOnSegSideChecked(X.l, Y.l, V1X.l, V1Y.l, V2X.l, V2Y.l,
                                           *Result.Long)
  Protected lineDX.q
  Protected lineDY.q
  Protected lineDXValue.l = 0
  Protected lineDYValue.l = 0

  GeometrySetError("")
  If *Result = 0
    GeometrySetError("GeometryPointOnSegSideChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf

  lineDX = V2X - V1X
  lineDY = V2Y - V1Y
  If lineDX < #FIXED_MIN Or lineDX > #FIXED_MAX
    GeometrySetError("GeometryPointOnSegSideChecked: V2X-V1X delta " + Str(lineDX) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf
  If lineDY < #FIXED_MIN Or lineDY > #FIXED_MAX
    GeometrySetError("GeometryPointOnSegSideChecked: V2Y-V1Y delta " + Str(lineDY) + " overflows the signed 32-bit fixed domain.")
    ProcedureReturn #False
  EndIf

  ; Both deltas were checked inside signed32 above; this narrowing is exact.
  lineDXValue = lineDX
  lineDYValue = lineDY
  ProcedureReturn GeometryPointSideCoreChecked("GeometryPointOnSegSideChecked",
                                               X, Y, V1X, V1Y,
                                               lineDXValue, lineDYValue, *Result)
EndProcedure

CompilerEndIf
