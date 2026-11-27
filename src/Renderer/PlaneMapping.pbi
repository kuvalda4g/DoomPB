; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M4-01 flat-visplane projection preparation and vanilla plane lighting from
; Linux Doom 1.10 r_main.c/r_plane.c:
;   R_ExecuteSetViewSize: yslope[y], distscale[x], basexscale/baseyscale;
;   R_InitLightTables: zlight[LIGHTLEVELS=16][MAXLIGHTZ=128] with
;     LIGHTZSHIFT=20, DISTMAP=2, NUMCOLORMAPS=32;
;   R_DrawPlanes row light ` (pl->lightlevel>>LIGHTSEGSHIFT)+extralight` and
;     distance index `distance>>LIGHTZSHIFT`, clamp >=MAXLIGHTZ -> 127.
;
; Source arithmetic and clamp order are preserved exactly:
;   dy = abs(((y-100)<<16) + FRACUNIT/2), numerator = (320/2)*FRACUNIT;
;   yslope = FixedDiv(numerator, dy);
;   cosadj = abs(finecosine[xtoviewangle[x]>>19]); distscale = FixedDiv(1,cosadj);
;   heading angle = (viewangle-ANG90)>>19;
;   basexscale = FixedDiv(finecosine[angle],centerxfrac);
;   baseyscale = -FixedDiv(finesine[angle],centerxfrac);
;   startmap = ((LIGHTLEVELS-1-i)*2)*NUMCOLORMAPS/LIGHTLEVELS;
;   scale = FixedDiv((SCREENWIDTH/2*FRACUNIT),(j+1)<<LIGHTZSHIFT)>>LIGHTSCALESHIFT;
;   level = startmap - scale/DISTMAP, clamped 0..31.
;
; BAM indexing uses the accepted unsigned 8191-masked fine index, so the
; original's raw `>>19` table read is bounded and keeps the cosine alias.
; The zlight table owns only numeric COLORMAP map indexes 0..31; it borrows no
; trick table pointer, so the table remains independent of a reopened COLORMAP.
;
; Fixed-point edge policy: signed subtraction/negation is widened to signed64
; and the low 32 bits are wrapped explicitly (documented M3-01 policy for C
; signed overflow). PlaneHeight uses the source abs but rejects the undefined
; abs(INT32_MIN) magnitude and any magnitude outside signed32 fixed_t.
;
; Ownership: PlaneZLightTable is caller-owned; Reset frees the single
; 16*128-Long allocation idempotently. Build validates the >=32-table COLORMAP,
; allocates once, fills every bin, and publishes Ready only after full success.
;
; No heap allocation, WAD read, flat pixel, framebuffer or RGB access occurs.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PLANEMAPPING_PBI, #PB_Constant) = 0

#DOOMPB_PLANEMAPPING_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Core/TrigTables.pbi"
XIncludeFile "../Graphics/Colormap.pbi"
XIncludeFile "Projection.pbi"

; Pinned r_main.h/r_plane.c constants.
#PLANE_LIGHTLEVELS = 16
#PLANE_LIGHTSEGSHIFT = 4
#PLANE_MAXLIGHTZ = 128
#PLANE_LIGHTZSHIFT = 20
#PLANE_LIGHTSCALESHIFT = 12
#PLANE_NUMCOLORMAPS = 32
#PLANE_DISTMAP = 2
#PLANE_SCREENWIDTH = #PROJ_VIEWWIDTH
#PLANE_CENTERY = #PROJ_CENTERY
#PLANE_DETAILSHIFT = 0
#PLANE_ZLIGHT_BinCount = #PLANE_LIGHTLEVELS * #PLANE_MAXLIGHTZ
#PLANE_ZLIGHT_MapMin = #PLANE_NUMCOLORMAPS
#PLANE_ZLIGHT_MaxMapIndex = #PLANE_NUMCOLORMAPS - 1

#PLANE_ZLIGHT_Magic = $504C4C31
#PLANE_VIEWHEIGHT = #PROJ_VIEWHEIGHT
#PLANE_VIEWWIDTH = #PROJ_VIEWWIDTH
#PLANE_YSLOPE_Count = #PLANE_VIEWHEIGHT
#PLANE_DISTSCALE_Count = #PLANE_VIEWWIDTH
#PLANE_XTOVIEWANGLE_Count = #PLANE_VIEWWIDTH + 1

Structure PlaneZLightTable
  Magic.l
  Ready.l
  LightRows.l
  DistanceBins.l
  *MapIndex.Long
  Allocations.l
EndStructure

Global gPlaneMapping_LastError.s = ""

Procedure PlaneMappingSetError(Message.s)
  gPlaneMapping_LastError = Message
EndProcedure

Procedure.s PlaneMappingLastError()
  ProcedureReturn gPlaneMapping_LastError
EndProcedure

; Widened signed64 addition/subtraction/negation then explicit low-32 wrap for
; the same C signed-overflow edge policy used by the accepted wall projection.
Procedure.l PlaneFixedAddLow(A.l, B.l)
  Protected wideSum.q = Int(A) + Int(B)

  ProcedureReturn FixedWrap32Low(wideSum)
EndProcedure

Procedure.l PlaneFixedSubLow(A.l, B.l)
  Protected wideDifference.q = Int(A) - Int(B)

  ProcedureReturn FixedWrap32Low(wideDifference)
EndProcedure

Procedure.l PlaneFixedNegateLow(A.l)
  Protected widened.q = Int(A)

  If widened <> 0
    widened = -widened
  EndIf
  ProcedureReturn FixedWrap32Low(widened)
EndProcedure

; ---------------------------------------------------------------------------
; PlaneZLightTable: R_InitLightTables
; ---------------------------------------------------------------------------

Procedure.i PlaneZLightTableIsValid(*Table.PlaneZLightTable)
  ProcedureReturn Bool(*Table <> 0 And *Table\Magic = #PLANE_ZLIGHT_Magic And
                        *Table\Ready <> 0)
EndProcedure

Procedure.i PlaneZLightTableReset(*Table.PlaneZLightTable)
  If *Table = 0
    PlaneMappingSetError("Plane zlight table pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Table\Magic = #PLANE_ZLIGHT_Magic
    If *Table\MapIndex <> 0
      If *Table\LightRows <> #PLANE_LIGHTLEVELS Or
         *Table\DistanceBins <> #PLANE_MAXLIGHTZ Or *Table\Allocations < 1
        PlaneMappingSetError("Plane zlight table owned pointer/capacity metadata is inconsistent.")
        ProcedureReturn #False
      EndIf
      FreeMemory(*Table\MapIndex)
    EndIf
  ElseIf *Table\Magic <> 0
    PlaneMappingSetError("Plane zlight table has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Table\MapIndex <> 0
    PlaneMappingSetError("Plane zlight table has an unexplained map-index pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Table, Int(SizeOf(PlaneZLightTable)), 0)
  *Table\Magic = #PLANE_ZLIGHT_Magic
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; COLORMAP availability gate for plane lighting: classic zlight references map
; levels 0..31 only, so at least 32 complete tables are required.
Procedure.i PlaneColormapValidate(*Colormap.ColormapSet, *MapCount.Long)
  If *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic
    PlaneMappingSetError("Plane lighting: COLORMAP is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Colormap\MapCount <= 0 Or *Colormap\MapCount > #COLORMAP_MaxTables
    PlaneMappingSetError("Plane lighting: COLORMAP map count is outside the decoder domain.")
    ProcedureReturn #False
  EndIf
  If *Colormap\Tables = 0
    PlaneMappingSetError("Plane lighting: COLORMAP table pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Colormap\MapCount < #PLANE_ZLIGHT_MapMin
    PlaneMappingSetError("Plane lighting requires at least " + Str(#PLANE_ZLIGHT_MapMin) +
                         " COLORMAP tables; the lump has " + Str(*Colormap\MapCount) + ".")
    ProcedureReturn #False
  EndIf
  If *MapCount <> 0
    PokeL(*MapCount, *Colormap\MapCount)
  EndIf
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; Exact source table generation. One allocation holds 16 rows of 128 numeric
; COLORMAP level indexes; no trick pointer is stored.
Procedure.i PlaneZLightTableBuild(*Table.PlaneZLightTable,
                                  *Colormap.ColormapSet)
  Protected binBytes.q
  Protected rowIndex.l
  Protected distanceIndex.l
  Protected startMap.l
  Protected numerator.l
  Protected denominator.q
  Protected scaleFixed.l = 0
  Protected scaled.l
  Protected level.l
  Protected binIndex.i
  Protected allocations.l = 0

  PlaneMappingSetError("")
  If *Table = 0
    PlaneMappingSetError("PlaneZLightTableBuild: table pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Table\Magic <> 0 And *Table\Magic <> #PLANE_ZLIGHT_Magic
    PlaneMappingSetError("PlaneZLightTableBuild: table has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If PlaneZLightTableReset(*Table) = #False
    ProcedureReturn #False
  EndIf
  If PlaneColormapValidate(*Colormap, 0) = #False
    ProcedureReturn #False
  EndIf

  binBytes = Int(#PLANE_ZLIGHT_BinCount) * SizeOf(Long)
  If binBytes <= 0 Or binBytes <> Int(#PLANE_ZLIGHT_BinCount) * Int(SizeOf(Long))
    PlaneMappingSetError("Plane zlight bin byte arithmetic is invalid.")
    ProcedureReturn #False
  EndIf
  *Table\MapIndex = AllocateMemory(binBytes)
  If *Table\MapIndex = 0
    PlaneMappingSetError("Out of memory for the plane zlight map-index table.")
    ProcedureReturn #False
  EndIf
  FillMemory(*Table\MapIndex, Int(binBytes), 0)
  allocations + 1

  numerator = Int(#PLANE_SCREENWIDTH / 2) * #FRACUNIT
  For rowIndex = 0 To #PLANE_LIGHTLEVELS - 1
    startMap = ((#PLANE_LIGHTLEVELS - 1 - rowIndex) * 2) * #PLANE_NUMCOLORMAPS / #PLANE_LIGHTLEVELS
    If startMap < 0 Or startMap > (#PLANE_LIGHTLEVELS - 1) * 2 * #PLANE_NUMCOLORMAPS / #PLANE_LIGHTLEVELS
      PlaneMappingSetError("Plane zlight startmap is outside the source domain for row " +
                           Str(rowIndex) + ": " + Str(startMap) + ".")
      FreeMemory(*Table\MapIndex)
      *Table\MapIndex = 0
      ProcedureReturn #False
    EndIf
    For distanceIndex = 0 To #PLANE_MAXLIGHTZ - 1
      denominator.q = (Int(distanceIndex) + 1) << #PLANE_LIGHTZSHIFT
      If denominator.q <= 0
        PlaneMappingSetError("Plane zlight distance denominator is nonpositive.")
        FreeMemory(*Table\MapIndex)
        *Table\MapIndex = 0
        ProcedureReturn #False
      EndIf
      scaleFixed = FixedDiv(numerator, FixedWrap32Low(denominator.q))
      If scaleFixed = #FIXED_MIN
        PlaneMappingSetError("Plane zlight distance scale hit the negative saturation edge.")
        FreeMemory(*Table\MapIndex)
        *Table\MapIndex = 0
        ProcedureReturn #False
      EndIf
      scaled = scaleFixed >> #PLANE_LIGHTSCALESHIFT
      If scaled < 0
        PlaneMappingSetError("Plane zlight scale shift produced a negative value.")
        FreeMemory(*Table\MapIndex)
        *Table\MapIndex = 0
        ProcedureReturn #False
      EndIf
      level = startMap - (scaled / #PLANE_DISTMAP)
      If level < 0
        level = 0
      EndIf
      If level >= #PLANE_NUMCOLORMAPS
        level = #PLANE_ZLIGHT_MaxMapIndex
      EndIf
      If level < 0 Or level > #PLANE_ZLIGHT_MaxMapIndex
        PlaneMappingSetError("Plane zlight level clamp failed.")
        FreeMemory(*Table\MapIndex)
        *Table\MapIndex = 0
        ProcedureReturn #False
      EndIf
      binIndex = rowIndex * #PLANE_MAXLIGHTZ + distanceIndex
      PokeL(*Table\MapIndex + binIndex * SizeOf(Long), level)
    Next
  Next

  *Table\Magic = #PLANE_ZLIGHT_Magic
  *Table\Ready = 1
  *Table\LightRows = #PLANE_LIGHTLEVELS
  *Table\DistanceBins = #PLANE_MAXLIGHTZ
  *Table\Allocations = allocations
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; source `distance>>LIGHTZSHIFT`, clamp >=MAXLIGHTZ -> 127, zlight[row][index].
; Distance is signed fixed and ordinary positive for a visible plane; negative
; behavior reproduces the arithmetic shift and is bounded to 0 by the clamp;
; an unusable table/index is an explicit error, never a table OOB read.
Procedure.i PlaneZLightMapIndex(*Table.PlaneZLightTable, LightNum.l,
                                Distance.l, *MapIndex.Long)
  Protected distanceBin.q
  Protected distanceIndex.l
  Protected binIndex.i
  Protected mapIndex.l

  PlaneMappingSetError("")
  If *MapIndex = 0
    PlaneMappingSetError("PlaneZLightMapIndex: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneZLightTableIsValid(*Table) = #False
    PlaneMappingSetError("Plane zlight table is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Table\MapIndex = 0 Or *Table\LightRows <> #PLANE_LIGHTLEVELS Or
     *Table\DistanceBins <> #PLANE_MAXLIGHTZ
    PlaneMappingSetError("Plane zlight table owned storage/metadata is inconsistent.")
    ProcedureReturn #False
  EndIf
  If LightNum < 0 Or LightNum >= #PLANE_LIGHTLEVELS
    PlaneMappingSetError("Plane zlight light row is outside 0..15: " + Str(LightNum) + ".")
    ProcedureReturn #False
  EndIf

  distanceBin = Int(Distance) >> #PLANE_LIGHTZSHIFT
  ; Source `unsigned index = distance >> LIGHTZSHIFT`: a negative signed fixed
  ; distance becomes a huge unsigned value and therefore clamps to 127. A
  ; negative shifted value reproduces that unsigned conversion, not a silent 0.
  If distanceBin >= #PLANE_MAXLIGHTZ Or distanceBin < 0
    distanceIndex = #PLANE_MAXLIGHTZ - 1
  Else
    distanceIndex = Int(distanceBin)
  EndIf
  If distanceIndex < 0 Or distanceIndex > #PLANE_MAXLIGHTZ - 1
    PlaneMappingSetError("Plane zlight distance index clamp failed.")
    ProcedureReturn #False
  EndIf

  binIndex = LightNum * #PLANE_MAXLIGHTZ + distanceIndex
  mapIndex = PeekL(*Table\MapIndex + binIndex * SizeOf(Long))
  If mapIndex < 0 Or mapIndex > #PLANE_ZLIGHT_MaxMapIndex
    PlaneMappingSetError("Plane zlight map level is outside 0..31: " + Str(mapIndex) + ".")
    ProcedureReturn #False
  EndIf
  *MapIndex\l = mapIndex
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; yslope / distscale / base scales
; ---------------------------------------------------------------------------

; R_ExecuteSetViewSize per-row yslope, exact half-pixel horizon bias and clamp-free
; FixedDiv. Row must be 0..199; dy cannot be zero for an integer row.
Procedure.i PlaneYSlopeValue(Row.l, CenterXFixed.l, ViewWidth.l, *YSlope.Long)
  Protected dy.q
  Protected numerator.l

  PlaneMappingSetError("")
  If *YSlope = 0
    PlaneMappingSetError("PlaneYSlopeValue: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If Row < 0 Or Row > #PLANE_YSLOPE_Count - 1
    PlaneMappingSetError("Plane Yslope row is outside 0..199: " + Str(Row) + ".")
    ProcedureReturn #False
  EndIf
  If CenterXFixed <= 0 Or ViewWidth < 1 Or ViewWidth > #PLANE_VIEWWIDTH
    PlaneMappingSetError("Plane Yslope projection center/width is invalid: centerx " + Str(CenterXFixed) +
                         ", width " + Str(ViewWidth) + ".")
    ProcedureReturn #False
  EndIf

  dy = (Int(Row) - #PLANE_CENTERY) << #FRACBITS
  dy = dy + #FRACUNIT / 2
  If dy < 0
    dy = -dy
  EndIf
  If dy = 0
    PlaneMappingSetError("Plane Yslope horizon delta is zero (undefined FixedDiv).")
    ProcedureReturn #False
  EndIf
  If dy > #FIXED_MAX
    PlaneMappingSetError("Plane Yslope horizon delta magnitude exceeds signed32 fixed_t.")
    ProcedureReturn #False
  EndIf

  numerator = Int(ViewWidth) / 2 * #FRACUNIT

  *YSlope\l = FixedDiv(numerator, FixedWrap32Low(dy))
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; Checked canonical yslope[200] table fill.
Procedure.i PlaneYSlopeTable(CenterXFixed.l, ViewWidth.l, *Out.Long)
  Protected row.l
  Protected value.l = 0

  PlaneMappingSetError("")
  If *Out = 0
    PlaneMappingSetError("PlaneYSlopeTable: output pointer is null.")
    ProcedureReturn #False
  EndIf
  For row = 0 To #PLANE_YSLOPE_Count - 1
    If PlaneYSlopeValue(row, CenterXFixed, ViewWidth, @value) = #False
      ProcedureReturn #False
    EndIf
    PokeL(*Out + row * SizeOf(Long), value)
  Next
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; R_ExecuteSetViewSize distscale for one xtoviewangle entry:
;   cosadj = abs(finecosine[raw>>19]); distscale = FixedDiv(FRACUNIT,cosadj).
; The unsigned fine index is bounded 0..8191 through BamFineIndex.
Procedure.i PlaneDistScaleFromAngle(RawAngle.q, *CosAdj.Long, *DistScale.Long)
  Protected fineIndex.l
  Protected cosine.l
  Protected magnitude.q

  PlaneMappingSetError("")
  If *CosAdj = 0 Or *DistScale = 0
    PlaneMappingSetError("PlaneDistScaleFromAngle: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(RawAngle) = 0
    PlaneMappingSetError("Plane distscale angle is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf
  fineIndex = Int(BamFineIndex(RawAngle))
  If TrigCosineChecked(fineIndex, @cosine) = #False
    PlaneMappingSetError("Plane distscale cosine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  magnitude.q = Int(cosine)
  If magnitude < 0
    magnitude = -magnitude
  EndIf
  If magnitude > #FIXED_MAX
    PlaneMappingSetError("Plane distscale cosine magnitude exceeds signed32 fixed_t.")
    ProcedureReturn #False
  EndIf

  *CosAdj\l = FixedWrap32Low(magnitude)
  *DistScale\l = FixedDiv(#FRACUNIT, FixedWrap32Low(magnitude))
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; Per-column distscale table from a caller-owned raw xtoviewangle[321] array.
Procedure.i PlaneDistScaleTableFromRaw(*RawAngles.Quad, Count.l, *Out.Long)
  Protected screenX.l
  Protected cosAdj.l = 0
  Protected scale.l = 0

  PlaneMappingSetError("")
  If *RawAngles = 0 Or *Out = 0
    PlaneMappingSetError("PlaneDistScaleTableFromRaw: input or output pointer is null.")
    ProcedureReturn #False
  EndIf
  If Count < 1 Or Count > #PLANE_XTOVIEWANGLE_Count
    PlaneMappingSetError("Plane distscale table count is outside 1..321: " + Str(Count) + ".")
    ProcedureReturn #False
  EndIf
  For screenX = 0 To Count - 1
    If PlaneDistScaleFromAngle(PeekQ(*RawAngles + screenX * SizeOf(Quad)),
                               @cosAdj, @scale) = #False
      ProcedureReturn #False
    EndIf
    PokeL(*Out + screenX * SizeOf(Long), scale)
  Next
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; R_ClearPlanes base scale:
;   angle = (viewangle-ANG90)>>19;
;   basexscale = FixedDiv(finecosine[angle],centerxfrac);
;   baseyscale = -FixedDiv(finesine[angle],centerxfrac).
Procedure.i PlaneBaseScaleFromHeading(ViewAngleRaw.q, CenterXFixed.l,
                                     *BaseXScale.Long, *BaseYScale.Long)
  Protected fineIndex.l
  Protected cosine.l = 0
  Protected sine.l = 0
  Protected xScale.l
  Protected yScale.l

  PlaneMappingSetError("")
  If *BaseXScale = 0 Or *BaseYScale = 0
    PlaneMappingSetError("PlaneBaseScaleFromHeading: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(ViewAngleRaw) = 0
    PlaneMappingSetError("Plane base-scale heading is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf
  If CenterXFixed <= 0
    PlaneMappingSetError("Plane base-scale centerxfrac must be positive.")
    ProcedureReturn #False
  EndIf

  fineIndex = Int(BamFineIndex(BamSubtract(ViewAngleRaw, #BAM_ANG90)))
  If TrigCosineChecked(fineIndex, @cosine) = #False
    PlaneMappingSetError("Plane base-scale cosine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf
  If TrigSineChecked(fineIndex, @sine) = #False
    PlaneMappingSetError("Plane base-scale sine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  xScale = FixedDiv(cosine, CenterXFixed)
  yScale = PlaneFixedNegateLow(FixedDiv(sine, CenterXFixed))

  *BaseXScale\l = xScale
  *BaseYScale\l = yScale
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Plane height / lighting clamp
; ---------------------------------------------------------------------------

; Source planeheight = abs(pl->height-viewz). C signed subtraction and abs of a
; signed32 minimum are undefined; DoomPB widens, rejects abs(INT32_MIN), and
; rejects any residual magnitude outside signed32 fixed_t.
Procedure.i PlaneHeightChecked(PlaneHeight.l, ViewZ.l, *Magnitude.Long)
  Protected difference.q
  Protected magnitude.q

  PlaneMappingSetError("")
  If *Magnitude = 0
    PlaneMappingSetError("PlaneHeightChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf

  difference.q = Int(PlaneHeight) - Int(ViewZ)
  magnitude = difference.q
  If magnitude < 0
    magnitude = -magnitude
  EndIf
  If magnitude = 2147483648
    PlaneMappingSetError("Plane height difference equals the abs(INT32_MIN) undefined edge.")
    ProcedureReturn #False
  EndIf
  If magnitude > #FIXED_MAX
    PlaneMappingSetError("Plane height magnitude exceeds signed32 fixed_t: " + Str(magnitude) + ".")
    ProcedureReturn #False
  EndIf
  *Magnitude\l = FixedWrap32Low(magnitude)
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; R_DrawPlanes sector light row: light=(lightlevel>>4)+extralight (static 0),
; clamp 0..15. A negative sector light is outside the signed SHORT map domain.
Procedure.i PlaneLightRowChecked(LightLevel.l, ExtraLight.l, *LightNum.Long)
  Protected shifted.l

  PlaneMappingSetError("")
  If *LightNum = 0
    PlaneMappingSetError("PlaneLightRowChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If LightLevel < -32768 Or LightLevel > 32767
    PlaneMappingSetError("Plane sector lightlevel is outside the signed 16-bit map domain: " + Str(LightLevel) + ".")
    ProcedureReturn #False
  EndIf
  If ExtraLight <> 0
    PlaneMappingSetError("Plane dynamic extralight is deferred; only the static 0 MVP value is supported: " + Str(ExtraLight) + ".")
    ProcedureReturn #False
  EndIf

  shifted = LightLevel >> #PLANE_LIGHTSEGSHIFT
  If shifted < 0
    shifted = 0
  EndIf
  If shifted >= #PLANE_LIGHTLEVELS
    shifted = #PLANE_LIGHTLEVELS - 1
  EndIf
  *LightNum\l = shifted
  gPlaneMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
