; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Classic screen-space projection tables from Linux Doom 1.10 r_main.c:
;   FIELDOFVIEW 2048, FINEANGLES 8192, ANGLETOFINESHIFT 19;
;   R_InitTextureMapping -> focal length, viewangletox[4096], xtoviewangle[321],
;   clipangle; R_ExecuteSetViewSize defaults for the full 320-column viewport.
;
; The canonical viewport is the original 320-wide logical view:
;   scaledviewwidth=320, detailshift=0, viewwidth=320, viewheight=200,
;   centerx=160, centery=100, centerxfrac=160*FRACUNIT, projection=centerxfrac.
; FIELDOFVIEW/2 = 1024, so the focal tangent index is FINEANGLES/4+FIELDOFVIEW/2
; = 3072.
;
; Exact original operation order is preserved:
;   1. focallength = FixedDiv(centerxfrac, finetangent[3072]);
;   2. for i=0..4095: strict `>2*FRACUNIT` -> -1, strict `< -2*FRACUNIT` ->
;      viewwidth+1, otherwise t = FixedMul(tangent,focallength),
;      t = (centerxfrac-t+FRACUNIT-1)>>FRACBITS, clamp [-1,viewwidth+1];
;   3. for x=0..viewwidth: scan the PRE-fencepost table until it is no longer
;      `>x`, then xtoviewangle[x] = (i<<ANGLETOFINESHIFT)-ANG90 as raw unsigned;
;   4. normalize fenceposts -1 -> 0 and viewwidth+1 -> viewwidth in the
;      published viewangletox table;
;   5. clipangle = xtoviewangle[0].
;
; The pre-fencepost table is retained in owned storage for diagnostics and
; future inverse checks; the published table is the normalized one, exactly as
; the original array ends up after its final loop. The original normalization
; loop also computes an unused local `t`; it is intentionally omitted because it
; has no observable effect and would be a gratuitous arithmetic repeat.
;
; BAM results are carried as raw unsigned Quad values (ANG90/ANG270 do not fit a
; signed Long). viewangletox entries are 32-bit signed Long values restricted to
; 0..viewwidth after normalization. Every inverse-table scan is explicitly
; bounded; the original's unchecked `while` is replaced with a diagnostic when
; the table unexpectedly never crosses the requested column.
;
; Ownership: caller zero-initializes Projection. Init owns two array
; allocations, publishes immutable values and never borrows WAD/map/camera
; memory. Reset is idempotent, frees only recognized owned arrays and leaves an
; empty reusable object. Failed Init/Reset never partial-publish a table; Init
; failures free any allocations and leave an empty valid object with a
; diagnostic. Tables can be computed once and reused for every frame.
;
; No floating-point tan(), Sin(), Cos(), degrees or continuous projection is
; used. Table generation only consumes the exact pinned finetangent DataSection.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PROJECTION_PBI, #PB_Constant) = 0

#DOOMPB_PROJECTION_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Core/TrigTables.pbi"

#PROJECTION_Magic = $50524A31
#PROJECTION_Ready = 1

; Original logical viewport constants (R_ExecuteSetViewSize, screenblocks=11).
#PROJ_FIELDOFVIEW = 2048
#PROJ_VIEWWIDTH = 320
#PROJ_VIEWHEIGHT = 200
#PROJ_CENTERX = #PROJ_VIEWWIDTH / 2
#PROJ_CENTERY = #PROJ_VIEWHEIGHT / 2
#PROJ_CENTERXFIXED = #PROJ_CENTERX << #FRACBITS
#PROJ_CENTERYFIXED = #PROJ_CENTERY << #FRACBITS
#PROJ_PROJECTION = #PROJ_CENTERXFIXED

; Effective array sizes and the exact focal tangent index.
#PROJ_VIEWANGLE_TOX_COUNT = #BAM_FINEANGLES / 2
#PROJ_XTOVIEWANGLE_COUNT = #PROJ_VIEWWIDTH + 1
#PROJ_FOCAL_TANGENT_INDEX = #BAM_FINEANGLES / 4 + #PROJ_FIELDOFVIEW / 2

; Project safety bounds, not original format limits.
#PROJ_MaxWidth = 320

Structure Projection
  Magic.l
  Ready.l
  Width.l
  ViewHeight.l
  CenterX.l
  CenterY.l
  CenterXFixed.l
  CenterYFixed.l
  ProjectionFixed.l
  FocalLength.l
  FieldOfView.l
  ClipAngle.q
  *ViewAngleToX.Long
  *PreViewAngleToX.Long
  *XToViewAngle.Quad
  ForwardCount.l
  InverseCount.l
  PreCount.l
EndStructure

Global gProjection_LastError.s = ""

Procedure ProjectionSetError(Message.s)
  gProjection_LastError = Message
EndProcedure

Procedure.s ProjectionLastError()
  ProcedureReturn gProjection_LastError
EndProcedure

Procedure.i ProjectionIsValid(*Projection.Projection)
  ProcedureReturn Bool(*Projection <> 0 And *Projection\Magic = #PROJECTION_Magic And *Projection\Ready = 1)
EndProcedure

; Idempotent empty reusable projection. A zero-initialized caller structure is
; accepted; nonzero unrecognized Magic or unexplained owned arrays are rejected
; instead of freeing arbitrary memory.
Procedure.i ProjectionReset(*Projection.Projection)
  If *Projection = 0
    ProjectionSetError("Projection pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Projection\Magic = #PROJECTION_Magic
    If *Projection\ViewAngleToX <> 0
      FreeMemory(*Projection\ViewAngleToX)
    EndIf
    If *Projection\PreViewAngleToX <> 0
      FreeMemory(*Projection\PreViewAngleToX)
    EndIf
    If *Projection\XToViewAngle <> 0
      FreeMemory(*Projection\XToViewAngle)
    EndIf
  ElseIf *Projection\Magic <> 0
    ProjectionSetError("Projection object has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Projection\ViewAngleToX <> 0 Or *Projection\PreViewAngleToX <> 0 Or *Projection\XToViewAngle <> 0
    ProjectionSetError("Projection has unexplained table pointers without a Magic value.")
    ProcedureReturn #False
  EndIf

  *Projection\Magic = #PROJECTION_Magic
  *Projection\Ready = 0
  *Projection\Width = 0
  *Projection\ViewHeight = 0
  *Projection\CenterX = 0
  *Projection\CenterY = 0
  *Projection\CenterXFixed = 0
  *Projection\CenterYFixed = 0
  *Projection\ProjectionFixed = 0
  *Projection\FocalLength = 0
  *Projection\FieldOfView = 0
  *Projection\ClipAngle = 0
  *Projection\ViewAngleToX = 0
  *Projection\PreViewAngleToX = 0
  *Projection\XToViewAngle = 0
  *Projection\ForwardCount = 0
  *Projection\InverseCount = 0
  *Projection\PreCount = 0
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

; Isolated production fencepost predicate, used by ClassicInit and exposed for
; boundary tests. Strict inequalities: tangent exactly 2*FRACUNIT is ordinary,
; tangent exactly -2*FRACUNIT is ordinary.
Procedure.i ProjectionTangentFence(Tangent.l, *Fence.Long)
  ProjectionSetError("")
  If *Fence = 0
    ProjectionSetError("ProjectionTangentFence: result pointer is null.")
    ProcedureReturn #False
  EndIf

  If Tangent > #FRACUNIT * 2
    *Fence\l = -1
    ProcedureReturn #True
  EndIf
  If Tangent < -#FRACUNIT * 2
    *Fence\l = #PROJ_VIEWWIDTH + 1
    ProcedureReturn #True
  EndIf
  *Fence\l = 0
  ProcedureReturn #True
EndProcedure

; Builds the exact canonical 320-column projection table set. Repeated Init is
; a deterministic rebuild; failure is transactional through Reset.
Procedure.i ProjectionInitClassic(*Projection.Projection)
  Protected forwardBytes.q
  Protected preBytes.q
  Protected inverseBytes.q
  Protected forwardMemory.i = 0
  Protected preMemory.i = 0
  Protected inverseMemory.i = 0
  Protected tangentValue.l = 0
  Protected focalTangent.l = 0
  Protected focalLength.l = 0
  Protected fence.l = 0
  Protected i.i
  Protected x.i
  Protected scanIndex.i
  Protected scaledTangent.l = 0
  Protected member.q
  Protected intPart.l = 0
  Protected preValue.l = 0
  Protected postValue.l = 0
  Protected rawAngle.q
  Protected failureText.s = ""

  ProjectionSetError("")
  If *Projection = 0
    ProjectionSetError("Projection pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Projection\Magic <> 0 And *Projection\Magic <> #PROJECTION_Magic
    ProjectionSetError("Projection object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If ProjectionReset(*Projection) = #False
    ProcedureReturn #False
  EndIf

  forwardBytes = Int(#PROJ_VIEWANGLE_TOX_COUNT) * SizeOf(Long)
  preBytes = Int(#PROJ_VIEWANGLE_TOX_COUNT) * SizeOf(Long)
  inverseBytes = Int(#PROJ_XTOVIEWANGLE_COUNT) * SizeOf(Quad)
  forwardMemory = AllocateMemory(forwardBytes)
  preMemory = AllocateMemory(preBytes)
  inverseMemory = AllocateMemory(inverseBytes)
  If forwardMemory = 0 Or preMemory = 0 Or inverseMemory = 0
    If forwardMemory <> 0
      FreeMemory(forwardMemory)
    EndIf
    If preMemory <> 0
      FreeMemory(preMemory)
    EndIf
    If inverseMemory <> 0
      FreeMemory(inverseMemory)
    EndIf
    ProjectionSetError("Out of memory while allocating the classic projection tables.")
    ProcedureReturn #False
  EndIf

  ; Owned storage is published before computation so Reset can always release it
  ; on a late arithmetic/table failure. Ready stays zero until full success.
  *Projection\Magic = #PROJECTION_Magic
  *Projection\Ready = 0
  *Projection\Width = #PROJ_VIEWWIDTH
  *Projection\ViewHeight = #PROJ_VIEWHEIGHT
  *Projection\CenterX = #PROJ_CENTERX
  *Projection\CenterY = #PROJ_CENTERY
  *Projection\CenterXFixed = #PROJ_CENTERXFIXED
  *Projection\CenterYFixed = #PROJ_CENTERYFIXED
  *Projection\ProjectionFixed = #PROJ_PROJECTION
  *Projection\FocalLength = 0
  *Projection\FieldOfView = #PROJ_FIELDOFVIEW
  *Projection\ClipAngle = 0
  *Projection\ViewAngleToX = forwardMemory
  *Projection\PreViewAngleToX = preMemory
  *Projection\XToViewAngle = inverseMemory
  *Projection\ForwardCount = #PROJ_VIEWANGLE_TOX_COUNT
  *Projection\InverseCount = #PROJ_XTOVIEWANGLE_COUNT
  *Projection\PreCount = #PROJ_VIEWANGLE_TOX_COUNT

  If TrigTangentChecked(#PROJ_FOCAL_TANGENT_INDEX, @focalTangent) = #False
    failureText = "Projection focal tangent lookup failed: " + TrigLastError()
    ProjectionReset(*Projection)
    ProjectionSetError(failureText)
    ProcedureReturn #False
  EndIf
  focalLength = FixedDiv(#PROJ_CENTERXFIXED, focalTangent)
  *Projection\FocalLength = focalLength

  ; Forward (pre-fencepost) table, exact source arithmetic and clamp order.
  For i = 0 To #PROJ_VIEWANGLE_TOX_COUNT - 1
    If TrigTangentChecked(i, @tangentValue) = #False
      failureText = "Projection tangent lookup failed at fine index " + Str(i) + ": " + TrigLastError()
      ProjectionReset(*Projection)
      ProjectionSetError(failureText)
      ProcedureReturn #False
    EndIf
    If ProjectionTangentFence(tangentValue, @fence) = #False
      failureText = "Projection fencepost predicate failed at fine index " + Str(i) + ": " + ProjectionLastError()
      ProjectionReset(*Projection)
      ProjectionSetError(failureText)
      ProcedureReturn #False
    EndIf
    If fence <> 0
      preValue = fence
    Else
      scaledTangent = FixedMul(tangentValue, focalLength)
      member = Int(#PROJ_CENTERXFIXED) - Int(scaledTangent) + Int(#FRACUNIT) - 1
      intPart = FixedWrap32Low(member >> #FRACBITS)
      If intPart < -1
        intPart = -1
      ElseIf intPart > #PROJ_VIEWWIDTH + 1
        intPart = #PROJ_VIEWWIDTH + 1
      EndIf
      preValue = intPart
    EndIf
    PokeL(*Projection\PreViewAngleToX + i * SizeOf(Long), preValue)
  Next

  ; Inverse table from the PRE-fencepost values. Original scan is unchecked; the
  ; explicit bound rejects a table that never crosses the column.
  For x = 0 To #PROJ_VIEWWIDTH
    scanIndex = 0
    While scanIndex < #PROJ_VIEWANGLE_TOX_COUNT And PeekL(*Projection\PreViewAngleToX + scanIndex * SizeOf(Long)) > x
      scanIndex + 1
    Wend
    If scanIndex >= #PROJ_VIEWANGLE_TOX_COUNT
      failureText = "Projection pre-fencepost table never crosses screen column " + Str(x) + "."
      ProjectionReset(*Projection)
      ProjectionSetError(failureText)
      ProcedureReturn #False
    EndIf
    rawAngle = BamSubtract(Int(scanIndex) << #BAM_ANGLETOFINESHIFT, #BAM_ANG90)
    PokeQ(*Projection\XToViewAngle + x * SizeOf(Quad), rawAngle)
  Next

  ; Post-fencepost normalization, exact -1 -> 0 and viewwidth+1 -> viewwidth.
  For i = 0 To #PROJ_VIEWANGLE_TOX_COUNT - 1
    preValue = PeekL(*Projection\PreViewAngleToX + i * SizeOf(Long))
    If preValue = -1
      postValue = 0
    ElseIf preValue = #PROJ_VIEWWIDTH + 1
      postValue = #PROJ_VIEWWIDTH
    Else
      postValue = preValue
    EndIf
    If postValue < 0 Or postValue > #PROJ_VIEWWIDTH
      failureText = "Projection normalized column at fine index " + Str(i) +
                    " is outside 0.." + Str(#PROJ_VIEWWIDTH) + ": " + Str(postValue) + "."
      ProjectionReset(*Projection)
      ProjectionSetError(failureText)
      ProcedureReturn #False
    EndIf
    PokeL(*Projection\ViewAngleToX + i * SizeOf(Long), postValue)
  Next

  *Projection\ClipAngle = PeekQ(*Projection\XToViewAngle)
  *Projection\Ready = 1
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

; Read-only copy accessors. Any output pointer may be null. Invalid objects,
; out-of-range indexes and null results leave all outputs untouched and set an
; actionable error; a successful call clears stale error state.
Procedure.i ProjectionGetViewAngleToX(*Projection.Projection, FineIndex.l, *X.Long)
  If ProjectionIsValid(*Projection) = #False
    ProjectionSetError("Projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If FineIndex < 0 Or FineIndex > #PROJ_VIEWANGLE_TOX_COUNT - 1
    ProjectionSetError("Projection fine index out of range: " + Str(FineIndex) + ".")
    ProcedureReturn #False
  EndIf
  If *X = 0
    ProjectionSetError("ProjectionGetViewAngleToX: result pointer is null.")
    ProcedureReturn #False
  EndIf
  PokeL(*X, PeekL(*Projection\ViewAngleToX + FineIndex * SizeOf(Long)))
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i ProjectionGetPreViewAngleToX(*Projection.Projection, FineIndex.l, *X.Long)
  If ProjectionIsValid(*Projection) = #False
    ProjectionSetError("Projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If FineIndex < 0 Or FineIndex > #PROJ_VIEWANGLE_TOX_COUNT - 1
    ProjectionSetError("Projection pre-table fine index out of range: " + Str(FineIndex) + ".")
    ProcedureReturn #False
  EndIf
  If *X = 0
    ProjectionSetError("ProjectionGetPreViewAngleToX: result pointer is null.")
    ProcedureReturn #False
  EndIf
  PokeL(*X, PeekL(*Projection\PreViewAngleToX + FineIndex * SizeOf(Long)))
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i ProjectionGetXToViewAngle(*Projection.Projection, ScreenX.l, *RawAngle.Quad)
  If ProjectionIsValid(*Projection) = #False
    ProjectionSetError("Projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If ScreenX < 0 Or ScreenX > #PROJ_VIEWWIDTH
    ProjectionSetError("Projection inverse screen column out of range: " + Str(ScreenX) + ".")
    ProcedureReturn #False
  EndIf
  If *RawAngle = 0
    ProjectionSetError("ProjectionGetXToViewAngle: result pointer is null.")
    ProcedureReturn #False
  EndIf
  PokeQ(*RawAngle, PeekQ(*Projection\XToViewAngle + ScreenX * SizeOf(Quad)))
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i ProjectionGetClipAngle(*Projection.Projection, *RawAngle.Quad)
  If ProjectionIsValid(*Projection) = #False
    ProjectionSetError("Projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *RawAngle = 0
    ProjectionSetError("ProjectionGetClipAngle: result pointer is null.")
    ProcedureReturn #False
  EndIf
  PokeQ(*RawAngle, *Projection\ClipAngle)
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i ProjectionGetConstants(*Projection.Projection, *Width.Long, *ViewHeight.Long,
                                  *CenterX.Long, *CenterY.Long, *CenterXFixed.Long,
                                  *CenterYFixed.Long, *ProjectionFixed.Long,
                                  *FocalLength.Long, *FieldOfView.Long)
  If ProjectionIsValid(*Projection) = #False
    ProjectionSetError("Projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Width <> 0
    PokeL(*Width, *Projection\Width)
  EndIf
  If *ViewHeight <> 0
    PokeL(*ViewHeight, *Projection\ViewHeight)
  EndIf
  If *CenterX <> 0
    PokeL(*CenterX, *Projection\CenterX)
  EndIf
  If *CenterY <> 0
    PokeL(*CenterY, *Projection\CenterY)
  EndIf
  If *CenterXFixed <> 0
    PokeL(*CenterXFixed, *Projection\CenterXFixed)
  EndIf
  If *CenterYFixed <> 0
    PokeL(*CenterYFixed, *Projection\CenterYFixed)
  EndIf
  If *ProjectionFixed <> 0
    PokeL(*ProjectionFixed, *Projection\ProjectionFixed)
  EndIf
  If *FocalLength <> 0
    PokeL(*FocalLength, *Projection\FocalLength)
  EndIf
  If *FieldOfView <> 0
    PokeL(*FieldOfView, *Projection\FieldOfView)
  EndIf
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i ProjectionGetTableCounts(*Projection.Projection, *ForwardCount.Long,
                                     *InverseCount.Long, *PreCount.Long)
  If ProjectionIsValid(*Projection) = #False
    ProjectionSetError("Projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *ForwardCount <> 0
    PokeL(*ForwardCount, *Projection\ForwardCount)
  EndIf
  If *InverseCount <> 0
    PokeL(*InverseCount, *Projection\InverseCount)
  EndIf
  If *PreCount <> 0
    PokeL(*PreCount, *Projection\PreCount)
  EndIf
  gProjection_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
