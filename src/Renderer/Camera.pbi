; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Fixed renderer camera state for deterministic BSP traversal (M3-03).
;
; The original renderer stores viewx/viewy as fixed_t globals and viewangle as
; an unsigned angle_t (r_main.c R_SetupFrame). DoomPB carries the same values in
; a caller-owned structure so traversal never mutates simulation globals:
;   - X/Y are signed 16.16 fixed_t values in .l;
;   - Heading is the raw unsigned 32-bit BAM bit pattern in .q (ANG180 and ANG270
;     are 2147483648 and 3221225472, which do not fit a signed .l field).
;
; Map-unit inputs come from vanilla signed 16-bit records and are converted with
; FixedFromIntChecked. Fixed inputs are accepted as signed32 directly. Every
; setter is transactional: a rejected input leaves the previous camera unchanged.
; Heading must already be a canonical raw BAM value in 0..$FFFFFFFF; it is stored
; for future projection work even though M3-03 cull-free traversal depends only
; on X/Y. No degrees, Sin(), Cos(), ATan2() or floating-point angle is involved.
;
; Ownership: caller zero-initializes BspCamera once. Reset makes it a reusable
; empty (not ready) camera; it owns no heap allocation and is idempotent.
;
; This module has no WAD, map, graphics, OS or gameplay dependency. It includes
; the existing fixed-point and BAM vocabulary only.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_BSPCAMERA_PBI, #PB_Constant) = 0

#DOOMPB_BSPCAMERA_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"

#BSPCAMERA_Magic = $42504331

Structure BspCamera
  Magic.l
  Ready.l
  X.l
  Y.l
  Heading.q
EndStructure

Global gBspCamera_LastError.s = ""

Procedure BspCameraSetError(Message.s)
  gBspCamera_LastError = Message
EndProcedure

Procedure.s BspCameraLastError()
  ProcedureReturn gBspCamera_LastError
EndProcedure

; Empty reusable camera: not ready, zero fields, no heap ownership. A freshly
; zero-initialized caller structure is accepted. A nonzero unrecognized Magic is
; rejected instead of being overwritten.
Procedure.i BspCameraReset(*Camera.BspCamera)
  If *Camera = 0
    BspCameraSetError("Camera pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Camera\Magic <> 0 And *Camera\Magic <> #BSPCAMERA_Magic
    BspCameraSetError("Camera object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf

  *Camera\Magic = #BSPCAMERA_Magic
  *Camera\Ready = 0
  *Camera\X = 0
  *Camera\Y = 0
  *Camera\Heading = 0
  gBspCamera_LastError = ""
  ProcedureReturn #True
EndProcedure

; Shared transactional publication. Inputs must already be validated.
Procedure BspCameraPublish(*Camera.BspCamera, FixedX.l, FixedY.l, HeadingRaw.q)
  *Camera\X = FixedX
  *Camera\Y = FixedY
  *Camera\Heading = HeadingRaw
  *Camera\Magic = #BSPCAMERA_Magic
  *Camera\Ready = 1
  gBspCamera_LastError = ""
EndProcedure

; Checked creation from signed map-unit coordinates (vanilla C SHORT domain).
; Both coordinates are converted before any field is written; an integer outside
; [-32768,32767] or an unrecognized raw heading rejects the whole call.
Procedure.i BspCameraSetMapUnits(*Camera.BspCamera, X.q, Y.q, HeadingRaw.q)
  Protected fixedX.l = 0
  Protected fixedY.l = 0

  BspCameraSetError("")
  If *Camera = 0
    BspCameraSetError("Camera pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Camera\Magic <> 0 And *Camera\Magic <> #BSPCAMERA_Magic
    BspCameraSetError("Camera object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(HeadingRaw) = 0
    BspCameraSetError("Heading must be a raw unsigned BAM value in 0..$FFFFFFFF.")
    ProcedureReturn #False
  EndIf

  If FixedFromIntChecked(X, @fixedX) = #False
    BspCameraSetError("Camera X map unit rejected: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(Y, @fixedY) = #False
    BspCameraSetError("Camera Y map unit rejected: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  BspCameraPublish(*Camera, fixedX, fixedY, HeadingRaw)
  ProcedureReturn #True
EndProcedure

; Checked creation from signed32 fixed coordinates. X/Y are fixed_t by type and
; remain inside the original signed fixed domain; the raw heading still has to
; be canonical unsigned BAM.
Procedure.i BspCameraSetFixed(*Camera.BspCamera, X.l, Y.l, HeadingRaw.q)
  BspCameraSetError("")
  If *Camera = 0
    BspCameraSetError("Camera pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Camera\Magic <> 0 And *Camera\Magic <> #BSPCAMERA_Magic
    BspCameraSetError("Camera object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(HeadingRaw) = 0
    BspCameraSetError("Heading must be a raw unsigned BAM value in 0..$FFFFFFFF.")
    ProcedureReturn #False
  EndIf

  BspCameraPublish(*Camera, X, Y, HeadingRaw)
  ProcedureReturn #True
EndProcedure

; Read-only copy accessors. Any output pointer may be null. Not-ready cameras and
; unrecognized objects fail without writing partial output.
Procedure.i BspCameraGet(*Camera.BspCamera, *X.Long, *Y.Long, *Heading.Quad)
  If *Camera = 0
    BspCameraSetError("Camera pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Camera\Magic <> #BSPCAMERA_Magic Or *Camera\Ready = 0
    BspCameraSetError("Camera is not ready.")
    ProcedureReturn #False
  EndIf
  If *X <> 0
    PokeL(*X, *Camera\X)
  EndIf
  If *Y <> 0
    PokeL(*Y, *Camera\Y)
  EndIf
  If *Heading <> 0
    PokeQ(*Heading, *Camera\Heading)
  EndIf
  gBspCamera_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
