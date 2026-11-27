; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Shared numeric wall-span vocabulary used by the M3-04 visibility publisher,
; ClipSegs, M3-05 projection and the M4-01 plane-fill dry chronology.
;
; This module deliberately holds no allocation, WAD, graphics, map-level or
; renderer state. It exists so WallProject/WallDraw/PlaneFill can share the
; WallSpan record shape without including WallVisibility itself (which would
; create an include cycle with the new online plane hook).
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLSPANDEFS_PBI, #PB_Constant) = 0

#DOOMPB_WALLSPANDEFS_PBI = 1

; Wall classification for published spans (not a drawing request). These are
; the existing numeric values already used by ClipSegs and M3-04.
#WALL_KIND_SOLID = 0
#WALL_KIND_PASS = 1

Structure WallSpan
  Subsector.l
  Seg.l
  Linedef.l
  Side.l
  FrontSector.l
  BackSector.l
  FirstX.l
  LastX.l
  Kind.l
EndStructure

CompilerEndIf
