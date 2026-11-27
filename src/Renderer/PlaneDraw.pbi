; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M4-01 plane span extraction/drawing from Linux Doom 1.10 r_plane.c/r_draw.c:
;   R_DrawPlanes: regular non-sky planes after the wall pass; sky pixels deferred;
;   R_MakeSpans: adjacent-column top/bottom open/close rules with x-1/minx-1/
;     maxx+1 sentinels; closes draw row spans, opens store spanstart=x;
;   R_MapPlane: cachedheight[y] row cache keyed by planeheight; distance=
;     FixedMul(planeheight,yslope[y]); xstep/ystep=FixedMul(distance,base*);
;     length=FixedMul(distance,distscale[x1]); angle=
;     (viewangle+xtoviewangle[x1])>>19; xfrac=viewx+FixedMul(cos,length);
;     yfrac=-viewy-FixedMul(sine,length); zlight index=distance>>LIGHTZSHIFT
;     clamped to 127;
;   R_DrawSpan: count=ds_x2-ds_x1 and the do/while paints count+1 inclusive;
;     spot=((yfrac>>10)&(63*64))+((xfrac>>16)&63); COLORMAP[table][flat byte].
;
; Sentinel and guarded-row policy:
;   - planes.pbi tops use 0xFF and bottom pads 0; R_DrawPlanes writes top[maxx+1]
;     and top[minx-1] 0xFF. MakeSpans is bounded to logical rows 0..199; a closing
;     row t1/b1 is valid and spanstart[row] must be 0..x-1; out-of-frame candidate
;     spans abort rather than partially write.
;   - x runs MinX..MaxX+1 inclusive; draw spans end at x-1, so MaxX=319 closes at
;     x=320 and paints exactly columns 0..319. No 255/200 row is emitted.
;
; Plane lighting: record lightlevel>>LIGHTSEGSHIFT+extralight=0 clamp 0..15;
; zlight[16][128] plays the source distance map-level select, distinct from
; walls' scalelight[16][48]. COLORMAP table m texel p -> tables[m*256+p].
;
; Explicit coverage audit: caller supplies a 64,000-byte wall-coverage plane that
; TexturedWallDrawSpan's optional coverage mask filled. A plane pixel whose
; coverage bit is nonzero is an explicit overlap failure; never silently overwrite.
; Palette index 0 and 255 remain ordinary source/mapped values.
;
; Ownership/output:
;   - caller-owned canonical 320x200 FrameBuffer only; private frames/coverage
;     planes are created by the orchestrator and discarded on failure;
;   - borrowed flat cache image pointers are read once per plane and never
;     retained; cache/colormap/zlight ownership stays caller-side;
;   - caller PlaneDrawTally is reset idempotently at whole-frame entry; counts are
;     held in a private tally and publish atomically on full success. Failure
;     leaves caller tally zeroed; target private partial state is discarded by
;     orchestrator;
;   - optional PlaneSpanTrace is caller-owned bounded horizontal-span audit
;     (row arithmetic, spans, pixels); allocations occur only at Begin, not in
;     row/pixel loops. Trace is audit-only and caller resets on failure.
;
; No WAD read, flat load/cache build, colormap decode or heap allocation happens
; in per-x/per-pixel loops. Original algorithms copyright (C) 1993-1996 by id
; Software, Inc. Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PLANEDRAW_PBI, #PB_Constant) = 0

#DOOMPB_PLANEDRAW_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Core/TrigTables.pbi"
XIncludeFile "../Graphics/FrameBuffer.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "../Graphics/Colormap.pbi"
XIncludeFile "Planes.pbi"
XIncludeFile "PlaneMapping.pbi"
XIncludeFile "PlaneFlatCache.pbi"

#PLANE_DRAW_TallyMagic = $504C4431
#PLANE_DRAW_ViewWidth = #PROJ_VIEWWIDTH
#PLANE_DRAW_ViewHeight = #PROJ_VIEWHEIGHT
#PLANE_DRAW_PixelCount = #PLANE_DRAW_ViewWidth * #PLANE_DRAW_ViewHeight
#PLANE_DRAW_FlatByteSize = #FLAT_ByteSize
#PLANE_DRAW_FlatWidth = #FLAT_Width
#PLANE_DRAW_FlatHeight = #FLAT_Height
#PLANE_DRAW_SpotMaskY = 63 * 64
#PLANE_DRAW_SpotMaskX = 63

#PLANE_DRAW_TraceMagic = $504C5451
#PLANE_DRAW_MaxTraceSpans = 262144
#PLANE_DRAW_ContextMagic = $504C4444

Structure PlaneDrawTally
  Magic.l
  VisplanesScanned.l
  RegularVisplanes.l
  SkyVisplanes.l
  EmptyVisplanes.l
  PopulatedVisplanes.l
  SkyDeferredBands.l
  SkyDeferredPixels.l
  PlaneSpans.l
  PlanePixels.l
  OpenedRows.l
  ClosedRows.l
  RowCacheHits.l
  RowCacheMisses.l
  ColormapTexels.l
  FloorVisplanes.l
  CeilingVisplanes.l
  FloorPixels.l
  CeilingPixels.l
EndStructure

Structure PlaneMapParams
  PlaneHeight.l
  Distance.l
  XStep.l
  YStep.l
  XFrac.l
  YFrac.l
  LightNum.l
  MapIndex.l
  CacheHit.l
EndStructure

Structure PlaneSpanRecord
  PlaneIndex.l
  Row.l
  FirstX.l
  LastX.l
  PlaneHeight.l
  Distance.l
  XStep.l
  YStep.l
  XFrac.l
  YFrac.l
  LightNum.l
  MapIndex.l
  Pixels.l
  CacheHit.l
EndStructure

Structure PlaneSpanTrace
  Magic.l
  Ready.l
  SpanCount.l
  Capacity.l
  *Spans.PlaneSpanRecord
  Allocations.l
EndStructure

Structure PlaneDrawContext
  Magic.l
  *Frame.PlaneFrame
  *Image.FlatImage
  *Colormap.ColormapSet
  *ZTable.PlaneZLightTable
  *Target.FrameBuffer
  *Coverage.Byte
  *Tally.PlaneDrawTally
  *Trace.PlaneSpanTrace
  PlaneIndex.l
  PlaneHeight.l
  LightNum.l
EndStructure

Global gPlaneDraw_LastError.s = ""

Procedure PlaneDrawSetError(Message.s)
  gPlaneDraw_LastError = Message
EndProcedure

Procedure.s PlaneDrawLastError()
  ProcedureReturn gPlaneDraw_LastError
EndProcedure

Procedure.i PlaneDrawTallyReset(*Tally.PlaneDrawTally)
  If *Tally = 0
    PlaneDrawSetError("Plane draw tally pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Tally\Magic <> 0 And *Tally\Magic <> #PLANE_DRAW_TallyMagic
    PlaneDrawSetError("Plane draw tally has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  FillMemory(*Tally, Int(SizeOf(PlaneDrawTally)), 0)
  *Tally\Magic = #PLANE_DRAW_TallyMagic
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneDrawContextIsValid(*Context.PlaneDrawContext)
  ProcedureReturn Bool(*Context <> 0 And *Context\Magic = #PLANE_DRAW_ContextMagic)
EndProcedure

; ---------------------------------------------------------------------------
; Bounded horizontal-span audit recorder
; ---------------------------------------------------------------------------

Procedure.i PlaneSpanTraceIsValid(*Trace.PlaneSpanTrace)
  ProcedureReturn Bool(*Trace <> 0 And *Trace\Magic = #PLANE_DRAW_TraceMagic And
                        *Trace\Ready <> 0)
EndProcedure

Procedure.i PlaneSpanTraceReset(*Trace.PlaneSpanTrace)
  If *Trace = 0
    PlaneDrawSetError("Plane span trace pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Trace\Magic = #PLANE_DRAW_TraceMagic
    If *Trace\Spans <> 0
      If *Trace\Capacity < 1 Or *Trace\Capacity > #PLANE_DRAW_MaxTraceSpans Or
         *Trace\SpanCount < 0 Or *Trace\SpanCount > *Trace\Capacity
        PlaneDrawSetError("Plane span trace owned pointer/capacity metadata is inconsistent.")
        ProcedureReturn #False
      EndIf
      FreeMemory(*Trace\Spans)
    EndIf
  ElseIf *Trace\Magic <> 0
    PlaneDrawSetError("Plane span trace has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Trace\Spans <> 0
    PlaneDrawSetError("Plane span trace has an unexplained span pointer without a Magic value.")
    ProcedureReturn #False
  EndIf
  FillMemory(*Trace, Int(SizeOf(PlaneSpanTrace)), 0)
  *Trace\Magic = #PLANE_DRAW_TraceMagic
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneSpanTraceBegin(*Trace.PlaneSpanTrace,
                                MaxSpans.l = #PLANE_DRAW_MaxTraceSpans)
  Protected spanBytes.q
  Protected spansMemory.i = 0

  PlaneDrawSetError("")
  If *Trace = 0
    PlaneDrawSetError("PlaneSpanTraceBegin: trace pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Trace\Magic <> 0 And *Trace\Magic <> #PLANE_DRAW_TraceMagic
    PlaneDrawSetError("PlaneSpanTraceBegin: trace has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If PlaneSpanTraceReset(*Trace) = #False
    ProcedureReturn #False
  EndIf
  If MaxSpans < 1 Or MaxSpans > #PLANE_DRAW_MaxTraceSpans
    PlaneDrawSetError("Plane span trace capacity is outside 1.." + Str(#PLANE_DRAW_MaxTraceSpans) + ": " +
                      Str(MaxSpans) + ".")
    ProcedureReturn #False
  EndIf
  spanBytes = Int(MaxSpans) * Int(SizeOf(PlaneSpanRecord))
  If spanBytes <= 0 Or spanBytes <> Int(MaxSpans) * Int(SizeOf(PlaneSpanRecord))
    PlaneDrawSetError("Plane span trace byte arithmetic is invalid.")
    ProcedureReturn #False
  EndIf
  spansMemory = AllocateMemory(spanBytes)
  If spansMemory = 0
    PlaneDrawSetError("Out of memory while allocating the bounded plane span trace.")
    ProcedureReturn #False
  EndIf
  FillMemory(spansMemory, Int(spanBytes), 0)
  *Trace\Magic = #PLANE_DRAW_TraceMagic
  *Trace\Ready = 1
  *Trace\Capacity = MaxSpans
  *Trace\Spans = spansMemory
  *Trace\Allocations = 1
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneSpanTraceAdd(*Trace.PlaneSpanTrace, PlaneIndex.l, Row.l,
                              FirstX.l, LastX.l, PlaneHeight.l, Distance.l,
                              XStep.l, YStep.l, XFrac.l, YFrac.l,
                              LightNum.l, MapIndex.l, Pixels.l, CacheHit.l)
  Protected *span.PlaneSpanRecord

  PlaneDrawSetError("")
  If *Trace = 0
    ProcedureReturn #True
  EndIf
  If PlaneSpanTraceIsValid(*Trace) = #False
    PlaneDrawSetError("Plane span trace add: trace is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or Row < 0 Or Row > #PLANE_DRAW_ViewHeight - 1 Or
     FirstX < 0 Or LastX < 0 Or FirstX > #PLANE_DRAW_ViewWidth - 1 Or
     LastX > #PLANE_DRAW_ViewWidth - 1 Or FirstX > LastX Or Pixels < 0
    PlaneDrawSetError("Plane span trace record fields are invalid.")
    ProcedureReturn #False
  EndIf
  If MapIndex < 0 Or MapIndex > #PLANE_ZLIGHT_MaxMapIndex Or
     LightNum < 0 Or LightNum > #PLANE_LIGHTLEVELS - 1 Or CacheHit < 0 Or CacheHit > 1
    PlaneDrawSetError("Plane span trace lighting/cache fields are invalid.")
    ProcedureReturn #False
  EndIf
  If *Trace\SpanCount >= *Trace\Capacity Or *Trace\Spans = 0
    PlaneDrawSetError("Plane span trace budget is exhausted under cap " + Str(*Trace\Capacity) + ".")
    ProcedureReturn #False
  EndIf
  *span = *Trace\Spans + Int(*Trace\SpanCount) * SizeOf(PlaneSpanRecord)
  *span\PlaneIndex = PlaneIndex
  *span\Row = Row
  *span\FirstX = FirstX
  *span\LastX = LastX
  *span\PlaneHeight = PlaneHeight
  *span\Distance = Distance
  *span\XStep = XStep
  *span\YStep = YStep
  *span\XFrac = XFrac
  *span\YFrac = YFrac
  *span\LightNum = LightNum
  *span\MapIndex = MapIndex
  *span\Pixels = Pixels
  *span\CacheHit = CacheHit
  *Trace\SpanCount + 1
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneSpanTraceGetStats(*Trace.PlaneSpanTrace,
                                   *SpanCount.Long, *Capacity.Long, *Allocations.Long)
  If PlaneSpanTraceIsValid(*Trace) = #False
    PlaneDrawSetError("Plane span trace statistics: trace is not initialized.")
    ProcedureReturn #False
  EndIf
  If *SpanCount <> 0
    PokeL(*SpanCount, *Trace\SpanCount)
  EndIf
  If *Capacity <> 0
    PokeL(*Capacity, *Trace\Capacity)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Trace\Allocations)
  EndIf
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneSpanTraceGetSpan(*Trace.PlaneSpanTrace, SpanIndex.l,
                                  *PlaneIndex.Long, *Row.Long,
                                  *FirstX.Long, *LastX.Long,
                                  *PlaneHeight.Long, *Distance.Long,
                                  *XStep.Long, *YStep.Long,
                                  *XFrac.Long, *YFrac.Long,
                                  *LightNum.Long, *MapIndex.Long,
                                  *Pixels.Long, *CacheHit.Long)
  Protected *span.PlaneSpanRecord

  PlaneDrawSetError("")
  If PlaneSpanTraceIsValid(*Trace) = #False
    PlaneDrawSetError("Plane span trace access: trace is not initialized.")
    ProcedureReturn #False
  EndIf
  If SpanIndex < 0 Or SpanIndex >= *Trace\SpanCount Or *Trace\Spans = 0
    PlaneDrawSetError("Plane span trace index is outside the recorded range.")
    ProcedureReturn #False
  EndIf
  *span = *Trace\Spans + Int(SpanIndex) * SizeOf(PlaneSpanRecord)
  If *PlaneIndex <> 0
    PokeL(*PlaneIndex, *span\PlaneIndex)
  EndIf
  If *Row <> 0
    PokeL(*Row, *span\Row)
  EndIf
  If *FirstX <> 0
    PokeL(*FirstX, *span\FirstX)
  EndIf
  If *LastX <> 0
    PokeL(*LastX, *span\LastX)
  EndIf
  If *PlaneHeight <> 0
    PokeL(*PlaneHeight, *span\PlaneHeight)
  EndIf
  If *Distance <> 0
    PokeL(*Distance, *span\Distance)
  EndIf
  If *XStep <> 0
    PokeL(*XStep, *span\XStep)
  EndIf
  If *YStep <> 0
    PokeL(*YStep, *span\YStep)
  EndIf
  If *XFrac <> 0
    PokeL(*XFrac, *span\XFrac)
  EndIf
  If *YFrac <> 0
    PokeL(*YFrac, *span\YFrac)
  EndIf
  If *LightNum <> 0
    PokeL(*LightNum, *span\LightNum)
  EndIf
  If *MapIndex <> 0
    PokeL(*MapIndex, *span\MapIndex)
  EndIf
  If *Pixels <> 0
    PokeL(*Pixels, *span\Pixels)
  EndIf
  If *CacheHit <> 0
    PokeL(*CacheHit, *span\CacheHit)
  EndIf
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_MapPlane exact row parameters
; ---------------------------------------------------------------------------

; Source row cache and start-coordinate arithmetic. LightNum is the already
; clamped sector row from R_DrawPlanes. PlaneHeight is checked abs(height-viewz).
Procedure.i PlaneMapRowParameters(*Frame.PlaneFrame, *ZTable.PlaneZLightTable,
                                  PlaneHeight.l, Row.l, FirstX.l,
                                  LightNum.l, *Params.PlaneMapParams)
  Protected yslope.l = 0
  Protected cachedHeightValue.l
  Protected distance.l = 0
  Protected xStep.l = 0
  Protected yStep.l = 0
  Protected length.l
  Protected angleIndex.l
  Protected cosine.l = 0
  Protected sine.l = 0
  Protected cosProduct.l
  Protected sineProduct.l
  Protected rawAngle.q = 0
  Protected xFrac.l = 0
  Protected yFrac.l = 0
  Protected mapIndex.l = 0
  Protected cacheHit.l = 0

  PlaneDrawSetError("")
  If *Params = 0
    PlaneDrawSetError("PlaneMapRowParameters: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlaneDrawSetError("PlaneMapRowParameters: plane frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If *ZTable = 0 Or PlaneZLightTableIsValid(*ZTable) = #False
    PlaneDrawSetError("PlaneMapRowParameters: zlight table is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneHeight < 0
    PlaneDrawSetError("PlaneMapRowParameters: planeheight is negative: " + Str(PlaneHeight) + ".")
    ProcedureReturn #False
  EndIf
  If Row < 0 Or Row > #PLANE_DRAW_ViewHeight - 1
    PlaneDrawSetError("PlaneMapRowParameters: row is outside 0..199: " + Str(Row) + ".")
    ProcedureReturn #False
  EndIf
  If FirstX < 0 Or FirstX > #PLANE_DRAW_ViewWidth - 1
    PlaneDrawSetError("PlaneMapRowParameters: first column is outside 0..319: " + Str(FirstX) + ".")
    ProcedureReturn #False
  EndIf
  If LightNum < 0 Or LightNum > #PLANE_LIGHTLEVELS - 1
    PlaneDrawSetError("PlaneMapRowParameters: light row is outside 0..15: " + Str(LightNum) + ".")
    ProcedureReturn #False
  EndIf

  yslope = PeekL(*Frame\YSlope + Row * SizeOf(Long))
  cachedHeightValue = PeekL(*Frame\CachedHeight + Row * SizeOf(Long))
  If PlaneHeight = cachedHeightValue
    cacheHit = 1
    distance = PeekL(*Frame\CachedDistance + Row * SizeOf(Long))
    xStep = PeekL(*Frame\CachedXStep + Row * SizeOf(Long))
    yStep = PeekL(*Frame\CachedYStep + Row * SizeOf(Long))
  Else
    cacheHit = 0
    distance = FixedMul(PlaneHeight, yslope)
    xStep = FixedMul(distance, *Frame\BaseXScale)
    yStep = FixedMul(distance, *Frame\BaseYScale)
    PokeL(*Frame\CachedHeight + Row * SizeOf(Long), PlaneHeight)
    PokeL(*Frame\CachedDistance + Row * SizeOf(Long), distance)
    PokeL(*Frame\CachedXStep + Row * SizeOf(Long), xStep)
    PokeL(*Frame\CachedYStep + Row * SizeOf(Long), yStep)
  EndIf

  length = FixedMul(distance, PeekL(*Frame\DistScale + FirstX * SizeOf(Long)))
  rawAngle = BamAdd(*Frame\ViewAngle, PeekQ(*Frame\XToViewAngle + FirstX * SizeOf(Quad)))
  angleIndex = Int(BamFineIndex(rawAngle))
  If TrigCosineChecked(angleIndex, @cosine) = #False
    PlaneDrawSetError("Plane map row cosine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf
  If TrigSineChecked(angleIndex, @sine) = #False
    PlaneDrawSetError("Plane map row sine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  cosProduct = FixedMul(cosine, length)
  sineProduct = FixedMul(sine, length)
  xFrac = PlaneFixedAddLow(*Frame\ViewX, cosProduct)
  yFrac = PlaneFixedSubLow(PlaneFixedNegateLow(*Frame\ViewY), sineProduct)

  If PlaneZLightMapIndex(*ZTable, LightNum, distance, @mapIndex) = #False
    PlaneDrawSetError("Plane map row zlight select failed: " + PlaneMappingLastError())
    ProcedureReturn #False
  EndIf

  *Params\PlaneHeight = PlaneHeight
  *Params\Distance = distance
  *Params\XStep = xStep
  *Params\YStep = yStep
  *Params\XFrac = xFrac
  *Params\YFrac = yFrac
  *Params\LightNum = LightNum
  *Params\MapIndex = mapIndex
  *Params\CacheHit = cacheHit
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_DrawSpan inclusive sampler + explicit wall coverage audit
; ---------------------------------------------------------------------------

; Paints exactly [FirstX..LastX] inclusive in screen Row from the validated
; 64x64 FlatImage remapped through COLORMAP table MapIndex. A nonzero coverage
; bit at any target pixel aborts explicitly (no overwrite); earlier writes stay
; private and are discarded by the orchestrator on failure.
Procedure.i PlaneDrawOneSpan(*Target.FrameBuffer, *Coverage.Byte,
                             *Image.FlatImage, *Colormap.ColormapSet,
                             *Params.PlaneMapParams, Row.l,
                             FirstX.l, LastX.l, *Tally.PlaneDrawTally,
                             *Pixels.Long)
  Protected rowWidth.l
  Protected pixel.l
  Protected count.l
  Protected xFrac.l
  Protected yFrac.l
  Protected xStep.l
  Protected yStep.l
  Protected mapIndex.l
  Protected sourceSpot.l
  Protected sourceByte.l
  Protected tableOffset.q
  Protected mappedValue.i
  Protected destinationOffset.q
  Protected coverageValue.i
  Protected localPixels.l = 0

  PlaneDrawSetError("")
  If *Pixels = 0
    PlaneDrawSetError("PlaneDrawOneSpan: pixel output pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Target = 0 Or *Target\Magic <> #FRAMEBUFFER_Magic Or
     *Target\Width <> #PLANE_DRAW_ViewWidth Or *Target\Height <> #PLANE_DRAW_ViewHeight Or
     *Target\PixelCount <> #PLANE_DRAW_PixelCount Or *Target\Pixels = 0
    PlaneDrawSetError("Plane span draw: framebuffer is not the canonical 320x200 index plane.")
    ProcedureReturn #False
  EndIf
  If *Coverage = 0
    PlaneDrawSetError("Plane span draw: wall coverage plane pointer is null (explicit audit required).")
    ProcedureReturn #False
  EndIf
  If *Image = 0 Or *Image\Magic <> #FLAT_ImageMagic Or *Image\Pixels = 0 Or
     *Image\Width <> #PLANE_DRAW_FlatWidth Or *Image\Height <> #PLANE_DRAW_FlatHeight Or
     *Image\PixelCount <> #PLANE_DRAW_FlatByteSize
    PlaneDrawSetError("Plane span draw: FlatImage is not the exact 64x64/4096-byte flat.")
    ProcedureReturn #False
  EndIf
  If *Colormap = 0 Or PlaneColormapValidate(*Colormap, 0) = #False
    PlaneDrawSetError("Plane span draw: COLORMAP is not the validated >=32-table set.")
    ProcedureReturn #False
  EndIf
  If *Params = 0
    PlaneDrawSetError("Plane span draw: row-map parameters pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Tally = 0 Or *Tally\Magic <> #PLANE_DRAW_TallyMagic
    PlaneDrawSetError("Plane span draw: tally is not initialized.")
    ProcedureReturn #False
  EndIf
  If Row < 0 Or Row > #PLANE_DRAW_ViewHeight - 1
    PlaneDrawSetError("Plane span draw: screen row is outside 0..199: " + Str(Row) + ".")
    ProcedureReturn #False
  EndIf
  If FirstX < 0 Or LastX < 0 Or FirstX > #PLANE_DRAW_ViewWidth - 1 Or
     LastX > #PLANE_DRAW_ViewWidth - 1 Or FirstX > LastX
    PlaneDrawSetError("Plane span draw: horizontal columns are invalid: " + Str(FirstX) + ".." + Str(LastX) + ".")
    ProcedureReturn #False
  EndIf
  If *Params\MapIndex < 0 Or *Params\MapIndex > #PLANE_ZLIGHT_MaxMapIndex
    PlaneDrawSetError("Plane span draw: COLORMAP map index is outside 0..31.")
    ProcedureReturn #False
  EndIf

  rowWidth = Int(#PLANE_DRAW_ViewWidth)
  count = LastX - FirstX
  xFrac = *Params\XFrac
  yFrac = *Params\YFrac
  xStep = *Params\XStep
  yStep = *Params\YStep
  mapIndex = *Params\MapIndex

  ; Source `do { ... } while (count--)`: count+1 inclusive destination pixels.
  For pixel = 0 To count
    sourceSpot = ((yFrac >> 10) & #PLANE_DRAW_SpotMaskY) +
                 ((xFrac >> 16) & #PLANE_DRAW_SpotMaskX)
    If sourceSpot < 0 Or sourceSpot > #PLANE_DRAW_FlatByteSize - 1
      PlaneDrawSetError("Plane span draw: source spot escaped the 64x64 flat: " + Str(sourceSpot) + ".")
      ProcedureReturn #False
    EndIf
    sourceByte = PeekA(*Image\Pixels + sourceSpot)
    If sourceByte < 0 Or sourceByte > 255
      PlaneDrawSetError("Plane span draw: flat source byte is outside 0..255.")
      ProcedureReturn #False
    EndIf
    tableOffset.q = Int(mapIndex) * #COLORMAP_TableSize + Int(sourceByte)
    If tableOffset.q < 0 Or tableOffset.q >= Int(*Colormap\MapCount) * #COLORMAP_TableSize
      PlaneDrawSetError("Plane span draw: COLORMAP texel offset escaped the decoded tables.")
      ProcedureReturn #False
    EndIf
    mappedValue = PeekA(*Colormap\Tables + tableOffset)
    If mappedValue < 0 Or mappedValue > 255
      PlaneDrawSetError("Plane span draw: mapped palette index is outside 0..255.")
      ProcedureReturn #False
    EndIf
    destinationOffset.q = Int(Row) * rowWidth + Int(FirstX) + Int(pixel)
    If destinationOffset.q < 0 Or destinationOffset.q >= #PLANE_DRAW_PixelCount
      PlaneDrawSetError("Plane span draw: destination offset escaped the canonical 320x200 plane.")
      ProcedureReturn #False
    EndIf
    coverageValue = PeekA(*Coverage + destinationOffset.q)
    If coverageValue <> 0
      If coverageValue <> 1
        PlaneDrawSetError("Plane span draw: wall coverage byte is not 0/1.")
        ProcedureReturn #False
      EndIf
      PlaneDrawSetError("Plane span draw: explicit wall coverage overlap at x=" +
                        Str(FirstX + pixel) + ", y=" + Str(Row) + ".")
      ProcedureReturn #False
    EndIf
    PokeA(*Target\Pixels + destinationOffset.q, mappedValue)
    *Tally\ColormapTexels + 1
    localPixels + 1
    xFrac = PlaneFixedAddLow(xFrac, xStep)
    yFrac = PlaneFixedAddLow(yFrac, yStep)
  Next

  *Pixels\l = localPixels
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_MapPlane + R_DrawSpan for one MakeSpans closing/opening row span
; ---------------------------------------------------------------------------

Procedure.i PlaneDrawRowSpan(*Context.PlaneDrawContext, Row.l,
                             FirstX.l, LastX.l)
  Protected params.PlaneMapParams
  Protected *frame.PlaneFrame
  Protected *image.FlatImage
  Protected *colormap.ColormapSet
  Protected *zTable.PlaneZLightTable
  Protected *target.FrameBuffer
  Protected *coverage.Byte
  Protected *tally.PlaneDrawTally
  Protected *trace.PlaneSpanTrace
  Protected pixels.l = 0

  PlaneDrawSetError("")
  If PlaneDrawContextIsValid(*Context) = #False
    PlaneDrawSetError("Plane row span: draw context is not initialized.")
    ProcedureReturn #False
  EndIf
  *frame = *Context\Frame
  *image = *Context\Image
  *colormap = *Context\Colormap
  *zTable = *Context\ZTable
  *target = *Context\Target
  *coverage = *Context\Coverage
  *tally = *Context\Tally
  *trace = *Context\Trace
  If *frame = 0 Or *image = 0 Or *colormap = 0 Or *zTable = 0 Or
     *target = 0 Or *coverage = 0 Or *tally = 0
    PlaneDrawSetError("Plane row span: draw context business pointers are incomplete.")
    ProcedureReturn #False
  EndIf
  If Row < 0 Or Row > #PLANE_DRAW_ViewHeight - 1 Or
     FirstX < 0 Or LastX < 0 Or FirstX > #PLANE_DRAW_ViewWidth - 1 Or
     LastX > #PLANE_DRAW_ViewWidth - 1 Or FirstX > LastX
    PlaneDrawSetError("Plane row span: row/columns are invalid.")
    ProcedureReturn #False
  EndIf

  If PlaneMapRowParameters(*frame, *zTable, *Context\PlaneHeight, Row, FirstX,
                           *Context\LightNum, @params) = #False
    PlaneDrawSetError("Plane row span: R_MapPlane parameters failed: " + PlaneDrawLastError())
    ProcedureReturn #False
  EndIf
  If *tally\Magic <> #PLANE_DRAW_TallyMagic
    PlaneDrawSetError("Plane row span: private tally is not initialized.")
    ProcedureReturn #False
  EndIf
  *tally\PlaneSpans + 1
  *tally\ClosedRows + 1
  If params\CacheHit <> 0
    *tally\RowCacheHits + 1
  Else
    *tally\RowCacheMisses + 1
  EndIf

  If PlaneDrawOneSpan(*target, *coverage, *image, *colormap, @params, Row,
                      FirstX, LastX, *tally, @pixels) = #False
    ProcedureReturn #False
  EndIf
  *tally\PlanePixels + pixels

  If *trace <> 0
    If PlaneSpanTraceAdd(*trace, *Context\PlaneIndex, Row, FirstX, LastX,
                         params\PlaneHeight, params\Distance,
                         params\XStep, params\YStep, params\XFrac, params\YFrac,
                         params\LightNum, params\MapIndex, pixels,
                         params\CacheHit) = #False
      PlaneDrawSetError("Plane row span: span trace add failed: " + PlaneDrawLastError())
      ProcedureReturn #False
    EndIf
  EndIf
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Exact R_MakeSpans source branch order. Caller supplies adjacent column values.
; ---------------------------------------------------------------------------

Declare.i PlaneDrawGetWorkTally(*Context.PlaneDrawContext)

Procedure.i PlaneMakeSpans(*Context.PlaneDrawContext, X.l,
                           T1.l, B1.l, T2.l, B2.l)
  Protected *frame.PlaneFrame
  Protected row.l
  Protected spanStartX.l
  Protected endX.l

  PlaneDrawSetError("")
  If PlaneDrawContextIsValid(*Context) = #False
    PlaneDrawSetError("PlaneMakeSpans: draw context is not initialized.")
    ProcedureReturn #False
  EndIf
  *frame = *Context\Frame
  If *frame = 0 Or PlaneFrameIsValid(*frame) = #False
    PlaneDrawSetError("PlaneMakeSpans: plane frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If X < 0 Or X > #PLANE_ViewWidth
    PlaneDrawSetError("PlaneMakeSpans: x is outside the padded logical domain 0..320: " + Str(X) + ".")
    ProcedureReturn #False
  EndIf
  If T1 < 0 Or T1 > 255 Or T2 < 0 Or T2 > 255 Or
     B1 < 0 Or B1 > #PLANE_DRAW_ViewHeight - 1 Or
     B2 < 0 Or B2 > #PLANE_DRAW_ViewHeight - 1
    PlaneDrawSetError("PlaneMakeSpans: adjacent top/bottom values are outside the guarded bands.")
    ProcedureReturn #False
  EndIf

  ; 1. close rows whose previous top rises to the current top and stays inside b1.
  While T1 < T2 And T1 <= B1
    If T1 < 0 Or T1 > #PLANE_DRAW_ViewHeight - 1
      PlaneDrawSetError("PlaneMakeSpans: closing top row is not drawable: " + Str(T1) + ".")
      ProcedureReturn #False
    EndIf
    spanStartX = PeekL(*frame\SpanStart + Int(T1) * SizeOf(Long))
    endX = X - 1
    If spanStartX < 0 Or spanStartX > #PLANE_DRAW_ViewWidth - 1 Or
       endX < 0 Or endX > #PLANE_DRAW_ViewWidth - 1 Or spanStartX > endX
      PlaneDrawSetError("PlaneMakeSpans: closing span start/end is invalid: row " + Str(T1) +
                        ", start " + Str(spanStartX) + ", end " + Str(endX) + ".")
      ProcedureReturn #False
    EndIf
    If PlaneDrawRowSpan(*Context, T1, spanStartX, endX) = #False
      ProcedureReturn #False
    EndIf
    T1 + 1
  Wend

  ; 2. close bottom rows descending while they stay at/above the updated t1.
  While B1 > B2 And B1 >= T1
    If B1 < 0 Or B1 > #PLANE_DRAW_ViewHeight - 1
      PlaneDrawSetError("PlaneMakeSpans: closing bottom row is not drawable: " + Str(B1) + ".")
      ProcedureReturn #False
    EndIf
    spanStartX = PeekL(*frame\SpanStart + Int(B1) * SizeOf(Long))
    endX = X - 1
    If spanStartX < 0 Or spanStartX > #PLANE_DRAW_ViewWidth - 1 Or
       endX < 0 Or endX > #PLANE_DRAW_ViewWidth - 1 Or spanStartX > endX
      PlaneDrawSetError("PlaneMakeSpans: closing bottom span start/end is invalid: row " + Str(B1) +
                        ", start " + Str(spanStartX) + ", end " + Str(endX) + ".")
      ProcedureReturn #False
    EndIf
    If PlaneDrawRowSpan(*Context, B1, spanStartX, endX) = #False
      ProcedureReturn #False
    EndIf
    B1 - 1
  Wend

  ; 3. open top rows ascending below the previous top and inside b2.
  While T2 < T1 And T2 <= B2
    If T2 < 0 Or T2 > #PLANE_DRAW_ViewHeight - 1
      PlaneDrawSetError("PlaneMakeSpans: opening top row is not drawable: " + Str(T2) + ".")
      ProcedureReturn #False
    EndIf
    If X > #PLANE_DRAW_ViewWidth - 1
      PlaneDrawSetError("PlaneMakeSpans: opening span start x is outside 0..319: " + Str(X) + ".")
      ProcedureReturn #False
    EndIf
    PokeL(*frame\SpanStart + Int(T2) * SizeOf(Long), X)
    PlaneDrawGetWorkTally(*Context)
    *Context\Tally\OpenedRows + 1
    T2 + 1
  Wend

  ; 4. open bottom rows descending while they stay at/above the updated t2.
  While B2 > B1 And B2 >= T2
    If B2 < 0 Or B2 > #PLANE_DRAW_ViewHeight - 1
      PlaneDrawSetError("PlaneMakeSpans: opening bottom row is not drawable: " + Str(B2) + ".")
      ProcedureReturn #False
    EndIf
    If X > #PLANE_DRAW_ViewWidth - 1
      PlaneDrawSetError("PlaneMakeSpans: opening span start x is outside 0..319: " + Str(X) + ".")
      ProcedureReturn #False
    EndIf
    PokeL(*frame\SpanStart + Int(B2) * SizeOf(Long), X)
    *Context\Tally\OpenedRows + 1
    B2 - 1
  Wend

  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; Small internal accessor for the private tally identity in MakeSpans; it does
; not publish caller counters and clears no diagnostics.
Procedure.i PlaneDrawGetWorkTally(*Context.PlaneDrawContext)
  Protected *tally.PlaneDrawTally

  *tally = *Context\Tally
  If *tally = 0 Or *tally\Magic <> #PLANE_DRAW_TallyMagic
    PlaneDrawSetError("PlaneMakeSpans: private tally is not initialized.")
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_DrawPlanes transactional whole-frame plane pass
; ---------------------------------------------------------------------------

; Draws every created visplane in creation order: minx>maxx/empty skip, sky
; deferral with explicit band/pixel counts and no flat sampling, then regular
; planes with loaded used flats, zlight rows, MakeSpans and covered-pixel audit.
Procedure.i PlaneDrawPlanes(*Frame.PlaneFrame, *Cache.PlaneFlatCache,
                            *Colormap.ColormapSet, *ZTable.PlaneZLightTable,
                            *Target.FrameBuffer, *Coverage.Byte,
                            *Tally.PlaneDrawTally,
                            *Trace.PlaneSpanTrace = 0)
  Protected workTally.PlaneDrawTally
  Protected context.PlaneDrawContext
  Protected *record.PlaneRecord
  Protected planeIndex.l
  Protected recordCount.l = 0
  Protected height.l = 0
  Protected flatPic.l = 0
  Protected lightLevel.l = 0
  Protected sky.l = 0
  Protected minX.l = 0
  Protected maxX.l = 0
  Protected stopX.l = 0
  Protected columnX.l
  Protected topValue1.l = 0
  Protected topValue2.l = 0
  Protected bottomValue1.l = 0
  Protected bottomValue2.l = 0
  Protected used.l = 0
  Protected planeHeight.l = 0
  Protected lightNum.l = 0
  Protected skyBands.l = 0
  Protected skyPixels.l = 0
  Protected pixels.l = 0
  Protected *image.FlatImage = 0
  Protected failureText.s = ""
  Protected localScanned.l = 0
  Protected localRegular.l = 0
  Protected localSky.l = 0
  Protected localEmpty.l = 0
  Protected localPopulated.l = 0
  Protected localFloorVisplanes.l = 0
  Protected localCeilingVisplanes.l = 0
  Protected localFloorPixels.l = 0
  Protected localCeilingPixels.l = 0
  Protected planePixelsBefore.l = 0
  Protected planePixelsDelta.l = 0
  Protected planeIsFloor.i = #False

  PlaneDrawSetError("")
  If *Frame = 0 Or PlaneFrameIsValid(*Frame) = #False
    PlaneDrawSetError("PlaneDrawPlanes: plane frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Cache = 0 Or PlaneFlatCacheIsValid(*Cache) = #False
    PlaneDrawSetError("PlaneDrawPlanes: flat cache is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Colormap = 0 Or PlaneColormapValidate(*Colormap, 0) = #False
    PlaneDrawSetError("PlaneDrawPlanes: COLORMAP is not the validated >=32-table set.")
    ProcedureReturn #False
  EndIf
  If *ZTable = 0 Or PlaneZLightTableIsValid(*ZTable) = #False
    PlaneDrawSetError("PlaneDrawPlanes: zlight table is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Target = 0 Or *Target\Magic <> #FRAMEBUFFER_Magic Or
     *Target\Width <> #PLANE_DRAW_ViewWidth Or *Target\Height <> #PLANE_DRAW_ViewHeight Or
     *Target\PixelCount <> #PLANE_DRAW_PixelCount Or *Target\Pixels = 0
    PlaneDrawSetError("PlaneDrawPlanes: target framebuffer is not the canonical 320x200 index plane.")
    ProcedureReturn #False
  EndIf
  If *Coverage = 0
    PlaneDrawSetError("PlaneDrawPlanes: wall coverage plane pointer is null (explicit audit required).")
    ProcedureReturn #False
  EndIf
  If *Tally = 0 Or PlaneDrawTallyReset(*Tally) = #False
    ProcedureReturn #False
  EndIf
  If *Trace <> 0 And PlaneSpanTraceIsValid(*Trace) = #False
    PlaneDrawSetError("PlaneDrawPlanes: supplied span trace is not initialized.")
    ProcedureReturn #False
  EndIf

  ; Private whole-frame tally: increments happen here only, atomic caller publish.
  If PlaneDrawTallyReset(@workTally) = #False
    PlaneDrawSetError("PlaneDrawPlanes: private work tally initialization failed.")
    ProcedureReturn #False
  EndIf

  recordCount = *Frame\LastPlane
  If recordCount < 0 Or recordCount > *Frame\Capacity
    PlaneDrawSetError("PlaneDrawPlanes: visplane count is outside the frame capacity.")
    ProcedureReturn #False
  EndIf
  localScanned = recordCount
  workTally\VisplanesScanned + localScanned

  For planeIndex = 0 To recordCount - 1
    *record = *Frame\Records + Int(planeIndex) * SizeOf(PlaneRecord)
    height = *record\Height
    flatPic = *record\FlatPic
    lightLevel = *record\LightLevel
    sky = *record\Sky
    minX = *record\MinX
    maxX = *record\MaxX
    If sky <> 0 And sky <> 1
      failureText = "PlaneDrawPlanes: plane " + Str(planeIndex) + " sky flag is invalid."
      Goto PlaneDrawFailure
    EndIf
    If flatPic < 0 Or flatPic >= #FLAT_MaxCount
      failureText = "PlaneDrawPlanes: plane " + Str(planeIndex) + " flat index is invalid: " + Str(flatPic) + "."
      Goto PlaneDrawFailure
    EndIf
    If lightLevel < -32768 Or lightLevel > 32767
      failureText = "PlaneDrawPlanes: plane " + Str(planeIndex) + " lightlevel is outside the signed map domain."
      Goto PlaneDrawFailure
    EndIf
    If minX < 0 Or minX > #PLANE_ViewWidth
      failureText = "PlaneDrawPlanes: plane " + Str(planeIndex) + " minx is invalid: " + Str(minX) + "."
      Goto PlaneDrawFailure
    EndIf
    If maxX < -1 Or maxX > #PLANE_DRAW_ViewWidth - 1
      failureText = "PlaneDrawPlanes: plane " + Str(planeIndex) + " maxx is invalid: " + Str(maxX) + "."
      Goto PlaneDrawFailure
    EndIf
    If minX > maxX
      ; source `if (pl->minx > pl->maxx) continue`.
      localEmpty + 1
      workTally\EmptyVisplanes + 1
      If sky <> 0
        localSky + 1
        workTally\SkyVisplanes + 1
      Else
        localRegular + 1
        workTally\RegularVisplanes + 1
      EndIf
      Continue
    EndIf
    If minX > #PLANE_DRAW_ViewWidth - 1
      failureText = "PlaneDrawPlanes: nonempty plane " + Str(planeIndex) + " minx exceeds columns."
      Goto PlaneDrawFailure
    EndIf

    If sky <> 0
      localSky + 1
      workTally\SkyVisplanes + 1
      skyBands = 0
      skyPixels = 0
      For columnX = minX To maxX
        If PlaneColumnValue(*Frame, planeIndex, columnX, #True, @topValue1) = #False Or
           PlaneColumnValue(*Frame, planeIndex, columnX, #False, @bottomValue1) = #False
          failureText = "PlaneDrawPlanes: sky plane column access failed: " + PlanesLastError()
          Goto PlaneDrawFailure
        EndIf
        If topValue1 <> 255
          If topValue1 > bottomValue1
            failureText = "PlaneDrawPlanes: sky plane column top exceeds bottom."
            Goto PlaneDrawFailure
          EndIf
          skyBands + 1
          skyPixels + (bottomValue1 - topValue1 + 1)
        EndIf
      Next
      workTally\SkyDeferredBands + skyBands
      workTally\SkyDeferredPixels + skyPixels
      Continue
    EndIf

    localRegular + 1
    workTally\RegularVisplanes + 1
    If PlaneRecordHasBands(*Frame, planeIndex, @used) = #False
      failureText = "PlaneDrawPlanes: used-band scan failed: " + PlanesLastError()
      Goto PlaneDrawFailure
    EndIf
    If used = 0
      localEmpty + 1
      workTally\EmptyVisplanes + 1
      Continue
    EndIf
    localPopulated + 1
    workTally\PopulatedVisplanes + 1
    planeIsFloor = Bool(height < *Frame\ViewZ)
    If planeIsFloor
      localFloorVisplanes + 1
      workTally\FloorVisplanes + 1
    Else
      localCeilingVisplanes + 1
      workTally\CeilingVisplanes + 1
    EndIf

    *image = PlaneFlatCacheImagePtr(*Cache, flatPic)
    If *image = 0
      failureText = "PlaneDrawPlanes: loaded flat lookup failed: " + PlaneFlatCacheLastError()
      Goto PlaneDrawFailure
    EndIf
    If PlaneLightRowChecked(lightLevel, 0, @lightNum) = #False
      failureText = "PlaneDrawPlanes: plane light row failed: " + PlaneMappingLastError()
      Goto PlaneDrawFailure
    EndIf
    If PlaneHeightChecked(height, *Frame\ViewZ, @planeHeight) = #False
      failureText = "PlaneDrawPlanes: planeheight failed: " + PlaneMappingLastError()
      Goto PlaneDrawFailure
    EndIf

    If PlaneTopSentinelSet(*Frame, planeIndex, maxX + 1) = #False Or
       PlaneTopSentinelSet(*Frame, planeIndex, minX - 1) = #False
      failureText = "PlaneDrawPlanes: plane top sentinel setup failed: " + PlanesLastError()
      Goto PlaneDrawFailure
    EndIf

    context\Magic = #PLANE_DRAW_ContextMagic
    context\Frame = *Frame
    context\Image = *image
    context\Colormap = *Colormap
    context\ZTable = *ZTable
    context\Target = *Target
    context\Coverage = *Coverage
    context\Tally = @workTally
    context\Trace = *Trace
    context\PlaneIndex = planeIndex
    context\PlaneHeight = planeHeight
    context\LightNum = lightNum

    planePixelsBefore = workTally\PlanePixels
    stopX = maxX + 1
    If stopX <= minX Or stopX > #PLANE_ViewWidth
      failureText = "PlaneDrawPlanes: plane stop x is invalid: " + Str(minX) + ".." + Str(stopX) + "."
      Goto PlaneDrawFailure
    EndIf
    For columnX = minX To stopX
      If PlaneColumnValue(*Frame, planeIndex, columnX - 1, #True, @topValue1) = #False Or
         PlaneColumnValue(*Frame, planeIndex, columnX - 1, #False, @bottomValue1) = #False Or
         PlaneColumnValue(*Frame, planeIndex, columnX, #True, @topValue2) = #False Or
         PlaneColumnValue(*Frame, planeIndex, columnX, #False, @bottomValue2) = #False
        failureText = "PlaneDrawPlanes: plane column access failed at x=" + Str(columnX) +
                      ": " + PlanesLastError()
        Goto PlaneDrawFailure
      EndIf
      If PlaneMakeSpans(@context, columnX, topValue1, bottomValue1,
                        topValue2, bottomValue2) = #False
        failureText = "PlaneDrawPlanes: MakeSpans/row draw failed at x=" + Str(columnX) +
                      ": " + PlaneDrawLastError()
        Goto PlaneDrawFailure
      EndIf
    Next
    planePixelsDelta = workTally\PlanePixels - planePixelsBefore
    If planePixelsDelta < 0
      failureText = "PlaneDrawPlanes: per-plane pixel accounting went backwards."
      Goto PlaneDrawFailure
    EndIf
    If planeIsFloor
      localFloorPixels + planePixelsDelta
      workTally\FloorPixels + planePixelsDelta
    Else
      localCeilingPixels + planePixelsDelta
      workTally\CeilingPixels + planePixelsDelta
    EndIf
  Next

  ; Atomic caller tally publication after all planes succeeded.
  *Tally\VisplanesScanned = workTally\VisplanesScanned
  *Tally\RegularVisplanes = workTally\RegularVisplanes
  *Tally\SkyVisplanes = workTally\SkyVisplanes
  *Tally\EmptyVisplanes = workTally\EmptyVisplanes
  *Tally\PopulatedVisplanes = workTally\PopulatedVisplanes
  *Tally\SkyDeferredBands = workTally\SkyDeferredBands
  *Tally\SkyDeferredPixels = workTally\SkyDeferredPixels
  *Tally\PlaneSpans = workTally\PlaneSpans
  *Tally\PlanePixels = workTally\PlanePixels
  *Tally\OpenedRows = workTally\OpenedRows
  *Tally\ClosedRows = workTally\ClosedRows
  *Tally\RowCacheHits = workTally\RowCacheHits
  *Tally\RowCacheMisses = workTally\RowCacheMisses
  *Tally\ColormapTexels = workTally\ColormapTexels
  *Tally\FloorVisplanes = workTally\FloorVisplanes
  *Tally\CeilingVisplanes = workTally\CeilingVisplanes
  *Tally\FloorPixels = workTally\FloorPixels
  *Tally\CeilingPixels = workTally\CeilingPixels
  gPlaneDraw_LastError = ""
  ProcedureReturn #True

  PlaneDrawFailure:
  If failureText = ""
    failureText = gPlaneDraw_LastError
  EndIf
  PlaneDrawSetError(failureText)
  ProcedureReturn #False
EndProcedure

; ---------------------------------------------------------------------------
; Counters accessor
; ---------------------------------------------------------------------------

Procedure.i PlaneDrawGetStats(*Tally.PlaneDrawTally,
                              *VisplanesScanned.Long, *RegularVisplanes.Long,
                              *SkyVisplanes.Long, *EmptyVisplanes.Long,
                              *PopulatedVisplanes.Long,
                              *SkyDeferredBands.Long, *SkyDeferredPixels.Long,
                              *PlaneSpans.Long, *PlanePixels.Long,
                              *OpenedRows.Long, *ClosedRows.Long,
                              *RowCacheHits.Long, *RowCacheMisses.Long,
                              *ColormapTexels.Long,
                              *FloorVisplanes.Long, *CeilingVisplanes.Long,
                              *FloorPixels.Long, *CeilingPixels.Long)
  If *Tally = 0 Or *Tally\Magic <> #PLANE_DRAW_TallyMagic
    PlaneDrawSetError("Plane draw statistics: tally is not initialized.")
    ProcedureReturn #False
  EndIf
  If *VisplanesScanned <> 0
    PokeL(*VisplanesScanned, *Tally\VisplanesScanned)
  EndIf
  If *RegularVisplanes <> 0
    PokeL(*RegularVisplanes, *Tally\RegularVisplanes)
  EndIf
  If *SkyVisplanes <> 0
    PokeL(*SkyVisplanes, *Tally\SkyVisplanes)
  EndIf
  If *EmptyVisplanes <> 0
    PokeL(*EmptyVisplanes, *Tally\EmptyVisplanes)
  EndIf
  If *PopulatedVisplanes <> 0
    PokeL(*PopulatedVisplanes, *Tally\PopulatedVisplanes)
  EndIf
  If *SkyDeferredBands <> 0
    PokeL(*SkyDeferredBands, *Tally\SkyDeferredBands)
  EndIf
  If *SkyDeferredPixels <> 0
    PokeL(*SkyDeferredPixels, *Tally\SkyDeferredPixels)
  EndIf
  If *PlaneSpans <> 0
    PokeL(*PlaneSpans, *Tally\PlaneSpans)
  EndIf
  If *PlanePixels <> 0
    PokeL(*PlanePixels, *Tally\PlanePixels)
  EndIf
  If *OpenedRows <> 0
    PokeL(*OpenedRows, *Tally\OpenedRows)
  EndIf
  If *ClosedRows <> 0
    PokeL(*ClosedRows, *Tally\ClosedRows)
  EndIf
  If *RowCacheHits <> 0
    PokeL(*RowCacheHits, *Tally\RowCacheHits)
  EndIf
  If *RowCacheMisses <> 0
    PokeL(*RowCacheMisses, *Tally\RowCacheMisses)
  EndIf
  If *ColormapTexels <> 0
    PokeL(*ColormapTexels, *Tally\ColormapTexels)
  EndIf
  If *FloorVisplanes <> 0
    PokeL(*FloorVisplanes, *Tally\FloorVisplanes)
  EndIf
  If *CeilingVisplanes <> 0
    PokeL(*CeilingVisplanes, *Tally\CeilingVisplanes)
  EndIf
  If *FloorPixels <> 0
    PokeL(*FloorPixels, *Tally\FloorPixels)
  EndIf
  If *CeilingPixels <> 0
    PokeL(*CeilingPixels, *Tally\CeilingPixels)
  EndIf
  gPlaneDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
