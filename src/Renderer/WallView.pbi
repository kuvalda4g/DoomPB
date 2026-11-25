; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Renderer view wrapper: the M3-03 fixed BspCamera state plus the separate
; checked signed 16.16 view height (viewz) required by M3-05 wall projection.
;
; Linux Doom 1.10 keeps viewx/viewy/viewangle/viewz as renderer globals set by
; R_SetupFrame. BspCamera already carries X/Y/Heading without mutating M3-03
; meanings. This wrapper adds:
;   - Camera.BspCamera embedded by value, never reinterpreted;
;   - ViewZ.l as signed 16.16 fixed_t (not raw map units).
;
; Derivation policy for a static, non-bobbing preview view:
;   p_local.h VIEWHEIGHT = 41*FRACUNIT;
;   P_SpawnPlayer places the player on ONFLOORZ (p_mobj.c), so the floor-fixed
;   plus VIEWHEIGHT is the checked static view height. The original R_SetupFrame
;   viewz = mo.z + player->viewheight; M3-05 omits bob, viewheight transitions and
;   the `ceilingheight-4*FRACUNIT` clamp documented in PORTING_NOTES.
;
; Every setter is transactional. Floor conversion, the 41-unit addition and
; camera conversion/heading checks all happen before any field is published.
; A failed setter leaves a previously valid view unchanged (except that the
; nested BspCamera setter itself is already transactional).
;
; Ownership: caller zero-initializes WallView once. Reset is idempotent, owns no
; heap memory and leaves a reusable empty (not ready) view. It calls the
; existing BspCameraReset for the nested camera.
;
; This module has no WAD, graphics, map or OS dependency.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLVIEW_PBI, #PB_Constant) = 0

#DOOMPB_WALLVIEW_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "Camera.pbi"

#WALLVIEW_Magic = $57565131
#WALLVIEW_ViewHeightUnits = 41
#WALLVIEW_ViewHeightFixed = 41 * #FRACUNIT

Structure WallView
  Magic.l
  Ready.l
  Camera.BspCamera
  ViewZ.l
EndStructure

Global gWallView_LastError.s = ""

Procedure WallViewSetError(Message.s)
  gWallView_LastError = Message
EndProcedure

Procedure.s WallViewLastError()
  ProcedureReturn gWallView_LastError
EndProcedure

Procedure.i WallViewIsValid(*View.WallView)
  ProcedureReturn Bool(*View <> 0 And *View\Magic = #WALLVIEW_Magic And
                        *View\Ready <> 0 And *View\Camera\Magic = #BSPCAMERA_Magic And
                        *View\Camera\Ready <> 0)
EndProcedure

; Checked static view-height derivation from a signed map-unit floor height:
;   floor_fixed = floor_map_units << FRACBITS       (FixedFromIntChecked)
;   viewz       = floor_fixed + 41*FRACUNIT         (widened signed64 sum)
;
; The final sum must stay in signed32 fixed_t; an overflowing sum is a specific
; diagnostic instead of an implicit wrap or a guessed floor. *ViewZ remains
; untouched on every failure.
Procedure.i WallViewHeightFromFloorChecked(FloorUnits.q, *ViewZ.Long)
  Protected floorFixed.l = 0
  Protected sum.q

  WallViewSetError("")
  If *ViewZ = 0
    WallViewSetError("WallViewHeightFromFloorChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(FloorUnits, @floorFixed) = #False
    WallViewSetError("Wall view floor height rejected: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  sum = Int(floorFixed) + Int(#WALLVIEW_ViewHeightFixed)
  If sum < #FIXED_MIN Or sum > #FIXED_MAX
    WallViewSetError("Wall view height floor+41 units overflows signed 32-bit fixed_t: " + Str(sum) + ".")
    ProcedureReturn #False
  EndIf

  *ViewZ\l = sum
  gWallView_LastError = ""
  ProcedureReturn #True
EndProcedure

; Explicit checked view from signed32 fixed camera coordinates and a signed32
; fixed view height. Raw heading must be canonical unsigned BAM.
Procedure.i WallViewSetFixed(*View.WallView, X.l, Y.l, HeadingRaw.q, ViewZ.l)
  WallViewSetError("")
  If *View = 0
    WallViewSetError("WallView pointer is null.")
    ProcedureReturn #False
  EndIf
  If *View\Magic <> 0 And *View\Magic <> #WALLVIEW_Magic
    WallViewSetError("WallView object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf

  If BspCameraSetFixed(@*View\Camera, X, Y, HeadingRaw) = #False
    WallViewSetError("Wall view camera rejected: " + BspCameraLastError())
    ProcedureReturn #False
  EndIf

  *View\Magic = #WALLVIEW_Magic
  *View\Ready = 1
  *View\ViewZ = ViewZ
  gWallView_LastError = ""
  ProcedureReturn #True
EndProcedure

; Checked view from signed map-unit coordinates, the P_SpawnPlayer heading and
; a signed map-unit floor shape. Floor conversion/viewz derivation is complete
; before the camera setter runs; the view fields are published only after both.
Procedure.i WallViewSetMapUnits(*View.WallView, X.q, Y.q, HeadingRaw.q, FloorUnits.q)
  Protected viewZ.l = 0

  WallViewSetError("")
  If *View = 0
    WallViewSetError("WallView pointer is null.")
    ProcedureReturn #False
  EndIf
  If *View\Magic <> 0 And *View\Magic <> #WALLVIEW_Magic
    WallViewSetError("WallView object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf

  If WallViewHeightFromFloorChecked(FloorUnits, @viewZ) = #False
    ProcedureReturn #False
  EndIf

  If BspCameraSetMapUnits(@*View\Camera, X, Y, HeadingRaw) = #False
    WallViewSetError("Wall view camera rejected: " + BspCameraLastError())
    ProcedureReturn #False
  EndIf

  *View\Magic = #WALLVIEW_Magic
  *View\Ready = 1
  *View\ViewZ = viewZ
  gWallView_LastError = ""
  ProcedureReturn #True
EndProcedure

; Copies an already valid camera state by value into the nested camera and
; publishes an explicit fixed view height. The source camera is never mutated.
Procedure.i WallViewSetFromCamera(*View.WallView, *Camera.BspCamera, ViewZ.l)
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0

  WallViewSetError("")
  If *Camera = 0 Or BspCameraGet(*Camera, @cameraX, @cameraY, @heading) = #False
    WallViewSetError("Wall view source camera is not ready: " + BspCameraLastError())
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallViewSetFixed(*View, cameraX, cameraY, heading, ViewZ)
EndProcedure

; Idempotent empty reusable wrapper. The nested BspCamera owns no memory; a
; genuinely zero-initialized caller structure is accepted.
Procedure.i WallViewReset(*View.WallView)
  If *View = 0
    WallViewSetError("WallView pointer is null.")
    ProcedureReturn #False
  EndIf
  If *View\Magic <> 0 And *View\Magic <> #WALLVIEW_Magic
    WallViewSetError("WallView object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If BspCameraReset(@*View\Camera) = #False
    WallViewSetError("Wall view nested camera reset failed: " + BspCameraLastError())
    ProcedureReturn #False
  EndIf

  *View\Magic = #WALLVIEW_Magic
  *View\Ready = 0
  *View\ViewZ = 0
  gWallView_LastError = ""
  ProcedureReturn #True
EndProcedure

; Read-only copy accessors. Each output pointer may be null; not-ready/wrapped
; views fail without partial writes.
Procedure.i WallViewGet(*View.WallView, *X.Long, *Y.Long, *Heading.Quad, *ViewZ.Long)
  If WallViewIsValid(*View) = #False
    WallViewSetError("Wall view is not ready.")
    ProcedureReturn #False
  EndIf
  If *X <> 0
    PokeL(*X, *View\Camera\X)
  EndIf
  If *Y <> 0
    PokeL(*Y, *View\Camera\Y)
  EndIf
  If *Heading <> 0
    PokeQ(*Heading, *View\Camera\Heading)
  EndIf
  If *ViewZ <> 0
    PokeL(*ViewZ, *View\ViewZ)
  EndIf
  gWallView_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
