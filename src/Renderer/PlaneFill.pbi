; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M4-01 dry plane-capture chronology for one already-prepared WallSpanPlan.
; Reproduces the exact R_StoreWallRange -> R_RenderSegLoop plane side effects
; without any wall texture sample or pixel write:
;   1. current subsector front plane handles are passed in;
;   2. if markceiling -> ceilingplane = R_CheckPlane(ceilingplane, FirstX, LastX)
;      before any per-column mark; the returned merge/split handle becomes current;
;   3. if markfloor -> floorplane = R_CheckPlane(floorplane, FirstX, LastX);
;   4. for each inclusive column first..last:
;        yl=(topfrac+HEIGHTUNIT-1)>>12 clamped to ceilingclip+1;
;        mark ceiling rows ceilingclip+1..yl-1 before clip updates;
;        yh=bottomfrac>>12 clamped to floorclip-1;
;        mark floor rows yh+1..floorclip-1 before clip updates;
;        then the accepted M3-05/M3-06 wall tier clip branch (middle closure,
;        upper pixhigh clamp/ceilingclip, lower pixlow clamp/floorclip,
;        mark-only ceilingclip/floorclip updates);
;        per-column scale/topfrac/bottomfrac steps;
;   5. no texture column/luminance is computed, no pixel is written.
;
; The primary flow uses WallProjectSpanChecked's already-decided mark flags,
; interpolation fields and tier flags, exactly the plan the wall rasterizer will
; use later. Plane row values are stored by Planes.pbi with guarded bands.
;
; Clip history compatibility: this helper mirrors the accepted M3-05/M3-06
; pre-column ceilingclip/floorclip snapshot for the lower tier clamp. That is an
; intentional documented difference from the C `R_RenderSegLoop` live array re-read
; after a top-tier ceilingclip mutation: the existing M3 wall rasterizer (and its
; frozen frame hashes) uses that snapshot, and the plane-capture clip history must
; be the same authority so later plane bands stay disjoint from painted wall
; pixels. Plane marks themselves occur before any clip mutation, as in C.
;
; Ownership: caller-owned PlaneFrame and WallVerticalClip; *CeilingHandle/
; *FloorHandle are mutable numeric handle slots in frame record order. Tally is
; caller-owned and publishes atomically only after the whole span succeeds; on a
; span failure the caller resets its frame because plane/clip state may be partial.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PLANEFILL_PBI, #PB_Constant) = 0

#DOOMPB_PLANEFILL_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "Planes.pbi"
XIncludeFile "WallProject.pbi"
XIncludeFile "WallDraw.pbi"

#PLANE_FILL_Magic = $504C4C46

Structure PlaneFillTally
  Magic.l
  ProcessedSpans.l
  ProcessedColumns.l
  CeilingChecks.l
  FloorChecks.l
  CeilingMerges.l
  CeilingSplits.l
  FloorMerges.l
  FloorSplits.l
  CeilingBands.l
  FloorBands.l
  ClippedColumns.l
  MiddleClosedColumns.l
  TopTierColumns.l
  BottomTierColumns.l
  MarkOnlyCeilingColumns.l
  MarkOnlyFloorColumns.l
EndStructure

Global gPlaneFill_LastError.s = ""

Procedure PlaneFillSetError(Message.s)
  gPlaneFill_LastError = Message
EndProcedure

Procedure.s PlaneFillLastError()
  ProcedureReturn gPlaneFill_LastError
EndProcedure

Procedure.i PlaneFillTallyReset(*Tally.PlaneFillTally)
  If *Tally = 0
    PlaneFillSetError("Plane fill tally pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Tally\Magic <> 0 And *Tally\Magic <> #PLANE_FILL_Magic
    PlaneFillSetError("Plane fill tally has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  FillMemory(*Tally, Int(SizeOf(PlaneFillTally)), 0)
  *Tally\Magic = #PLANE_FILL_Magic
  gPlaneFill_LastError = ""
  ProcedureReturn #True
EndProcedure

; Dry R_RenderSegLoop plane capture for one WallSpanPlan. Mutates the same
; WallVerticalClip that the later wall rasterizer restores from a fresh Begin,
; producing byte-identical clip history and plane row bands. No *FrameBuffer.
Procedure.i PlaneFillSpan(*Frame.PlaneFrame, *Plan.WallSpanPlan,
                          *CeilingHandle.Long, *FloorHandle.Long,
                          *Clip.WallVerticalClip, *Tally.PlaneFillTally)
  Protected firstX.l
  Protected lastX.l
  Protected column.l
  Protected ceilClip.l
  Protected floorClip.l
  Protected yl.l
  Protected yh.l
  Protected mid.l
  Protected storedCeiling.l = 0
  Protected storedFloor.l = 0
  Protected merged.l = 0
  Protected newCeiling.l = 0
  Protected newFloor.l = 0
  Protected ceilingBefore.l = -1
  Protected floorBefore.l = -1
  Protected clippedThis.i = #False
  Protected scaleCurrent.l
  Protected topFracCurrent.l
  Protected bottomFracCurrent.l
  Protected pixHighCurrent.l
  Protected pixLowCurrent.l
  Protected localProcessedColumns.l = 0
  Protected localCeilingChecks.l = 0
  Protected localFloorChecks.l = 0
  Protected localCeilingMerges.l = 0
  Protected localCeilingSplits.l = 0
  Protected localFloorMerges.l = 0
  Protected localFloorSplits.l = 0
  Protected localCeilingBands.l = 0
  Protected localFloorBands.l = 0
  Protected localClippedColumns.l = 0
  Protected localMiddleClosedColumns.l = 0
  Protected localTopTierColumns.l = 0
  Protected localBottomTierColumns.l = 0
  Protected localMarkOnlyCeiling.l = 0
  Protected localMarkOnlyFloor.l = 0

  PlaneFillSetError("")
  If *Frame = 0 Or PlaneFrameIsValid(*Frame) = #False
    PlaneFillSetError("Plane fill span: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Plan = 0 Or WallSpanPlanIsReady(*Plan) = #False
    PlaneFillSetError("Plane fill span: M3-05 wall plan is not ready.")
    ProcedureReturn #False
  EndIf
  If *CeilingHandle = 0 Or *FloorHandle = 0
    PlaneFillSetError("Plane fill span: plane handle output pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Clip = 0 Or *Clip\Magic <> #WALLDRAW_ClipMagic Or
     *Clip\Width <> #PLANE_ViewWidth Or *Clip\Ceiling = 0 Or *Clip\Floor = 0
    PlaneFillSetError("Plane fill span: vertical clip arrays are not initialized.")
    ProcedureReturn #False
  EndIf
  If *Tally = 0 Or *Tally\Magic <> #PLANE_FILL_Magic
    PlaneFillSetError("Plane fill span: tally is not initialized.")
    ProcedureReturn #False
  EndIf

  firstX = *Plan\FirstX
  lastX = *Plan\LastX
  If firstX < 0 Or lastX < 0 Or firstX > #PLANE_ViewWidth - 1 Or
     lastX > #PLANE_ViewWidth - 1 Or firstX > lastX
    PlaneFillSetError("Plane fill span: plan columns are invalid: " + Str(firstX) + ".." + Str(lastX) + ".")
    ProcedureReturn #False
  EndIf
  If *Plan\MarkCeiling <> 0 And (*CeilingHandle\l < 0 Or *CeilingHandle\l >= *Frame\LastPlane)
    PlaneFillSetError("Plane fill span: markceiling plan has no current valid ceilingplane handle.")
    ProcedureReturn #False
  EndIf
  If *Plan\MarkFloor <> 0 And (*FloorHandle\l < 0 Or *FloorHandle\l >= *Frame\LastPlane)
    PlaneFillSetError("Plane fill span: markfloor plan has no current valid floorplane handle.")
    ProcedureReturn #False
  EndIf

  ceilingBefore = *CeilingHandle\l
  floorBefore = *FloorHandle\l

  ; R_StoreWallRange CheckPlane side effects happen before R_RenderSegLoop marks.
  If *Plan\MarkCeiling <> 0
    If PlaneCheckPlane(*Frame, *CeilingHandle\l, firstX, lastX,
                       @newCeiling, @merged) = #False
      PlaneFillSetError("Plane fill span: ceiling R_CheckPlane failed: " + PlanesLastError())
      ProcedureReturn #False
    EndIf
    *CeilingHandle\l = newCeiling
    localCeilingChecks + 1
    If merged <> 0
      localCeilingMerges + 1
    Else
      localCeilingSplits + 1
    EndIf
  EndIf
  If *Plan\MarkFloor <> 0
    If PlaneCheckPlane(*Frame, *FloorHandle\l, firstX, lastX,
                       @newFloor, @merged) = #False
      PlaneFillSetError("Plane fill span: floor R_CheckPlane failed: " + PlanesLastError())
      ProcedureReturn #False
    EndIf
    *FloorHandle\l = newFloor
    localFloorChecks + 1
    If merged <> 0
      localFloorMerges + 1
    Else
      localFloorSplits + 1
    EndIf
  EndIf

  scaleCurrent = *Plan\Scale1
  topFracCurrent = *Plan\TopFrac
  bottomFracCurrent = *Plan\BottomFrac
  pixHighCurrent = *Plan\PixHigh
  pixLowCurrent = *Plan\PixLow

  For column = firstX To lastX
    localProcessedColumns + 1
    clippedThis = #False
    ceilClip = PeekL(*Clip\Ceiling + column * SizeOf(Long))
    floorClip = PeekL(*Clip\Floor + column * SizeOf(Long))

    yl = WallTopEdgeFromFrac(topFracCurrent)
    If yl < ceilClip + 1
      yl = ceilClip + 1
      clippedThis = #True
    EndIf
    If *Plan\MarkCeiling <> 0
      If PlaneMarkCeilingBand(*Frame, *CeilingHandle\l, column,
                              ceilClip, floorClip, yl, @storedCeiling) = #False
        PlaneFillSetError("Plane fill span: ceiling band mark failed at x=" + Str(column) +
                          ": " + PlanesLastError())
        ProcedureReturn #False
      EndIf
      If storedCeiling <> 0
        localCeilingBands + 1
      EndIf
    EndIf

    yh = WallBottomEdgeFromFrac(bottomFracCurrent)
    If yh >= floorClip
      yh = floorClip - 1
      clippedThis = #True
    EndIf
    If *Plan\MarkFloor <> 0
      If PlaneMarkFloorBand(*Frame, *FloorHandle\l, column,
                            ceilClip, floorClip, yh, @storedFloor) = #False
        PlaneFillSetError("Plane fill span: floor band mark failed at x=" + Str(column) +
                          ": " + PlanesLastError())
        ProcedureReturn #False
      EndIf
      If storedFloor <> 0
        localFloorBands + 1
      EndIf
    EndIf

    If *Plan\MiddleTier <> 0
      ; one-sided middle closes the column regardless of an empty range.
      localMiddleClosedColumns + 1
      PokeL(*Clip\Ceiling + column * SizeOf(Long), #PLANE_ViewHeight)
      PokeL(*Clip\Floor + column * SizeOf(Long), -1)
    Else
      If *Plan\TopTier <> 0
        mid = WallPixHighToY(pixHighCurrent)
        pixHighCurrent = WallFixedAddLow(pixHighCurrent, *Plan\PixHighStep)
        If mid >= floorClip
          mid = floorClip - 1
          clippedThis = #True
        EndIf
        localTopTierColumns + 1
        If mid >= yl
          PokeL(*Clip\Ceiling + column * SizeOf(Long), mid)
        Else
          PokeL(*Clip\Ceiling + column * SizeOf(Long), yl - 1)
        EndIf
      ElseIf *Plan\MarkCeiling <> 0
        localMarkOnlyCeiling + 1
        PokeL(*Clip\Ceiling + column * SizeOf(Long), yl - 1)
      EndIf

      If *Plan\BottomTier <> 0
        mid = WallPixLowToY(pixLowCurrent)
        pixLowCurrent = WallFixedAddLow(pixLowCurrent, *Plan\PixLowStep)
        If mid <= ceilClip
          mid = ceilClip + 1
          clippedThis = #True
        EndIf
        localBottomTierColumns + 1
        If mid <= yh
          PokeL(*Clip\Floor + column * SizeOf(Long), mid)
        Else
          PokeL(*Clip\Floor + column * SizeOf(Long), yh + 1)
        EndIf
      ElseIf *Plan\MarkFloor <> 0
        localMarkOnlyFloor + 1
        PokeL(*Clip\Floor + column * SizeOf(Long), yh + 1)
      EndIf
    EndIf

    If clippedThis
      localClippedColumns + 1
    EndIf

    scaleCurrent = WallFixedAddLow(scaleCurrent, *Plan\ScaleStep)
    topFracCurrent = WallFixedAddLow(topFracCurrent, *Plan\TopStep)
    bottomFracCurrent = WallFixedAddLow(bottomFracCurrent, *Plan\BottomStep)
  Next

  *Tally\ProcessedSpans + 1
  *Tally\ProcessedColumns + localProcessedColumns
  *Tally\CeilingChecks + localCeilingChecks
  *Tally\FloorChecks + localFloorChecks
  *Tally\CeilingMerges + localCeilingMerges
  *Tally\CeilingSplits + localCeilingSplits
  *Tally\FloorMerges + localFloorMerges
  *Tally\FloorSplits + localFloorSplits
  *Tally\CeilingBands + localCeilingBands
  *Tally\FloorBands + localFloorBands
  *Tally\ClippedColumns + localClippedColumns
  *Tally\MiddleClosedColumns + localMiddleClosedColumns
  *Tally\TopTierColumns + localTopTierColumns
  *Tally\BottomTierColumns + localBottomTierColumns
  *Tally\MarkOnlyCeilingColumns + localMarkOnlyCeiling
  *Tally\MarkOnlyFloorColumns + localMarkOnlyFloor
  gPlaneFill_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
