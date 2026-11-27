; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M4-01 combined wall + floor/ceiling frame orchestrator. Extends the existing
; online M3-04 BSP/seg pass with the exact plane chronology and reuses the M3-06
; textured wall-column pipeline plus the new M3-05/M3-06-preserving plane modules.
;
; Single online producer, no replay:
;   1. WallVisibilityBuild is invoked with an optional caller-owned PlaneFrame
;      and WallPlaneTimeline. Inside its original near-to-far walk, each visited
;      subsector entry performs R_Subsector eligibility + R_FindPlane in order,
;      and each emitted ClipSpan immediately performs R_StoreWallRange's
;      R_CheckPlane plus the per-column R_RenderSegLoop plane marks BEFORE that
;      span's ceilingclip/floorclip tier mutations (PlaneFillSpan). No plane is
;      ever inferred from final pixels or from an unordered span collection.
;   2. Published WallSpan chronology is projected once into M3-05 WallSpanPlan
;      and then into M3-06 WallTextureSpanPlan exactly as in the textured
;      wall-only frame; used-texture cache, wall scalelight and plane zlight are
;      prebuilt before any pixel loop.
;   3. A fresh vertical clip and a private canonical 320x200 background frame
;      plus an explicit 64,000-byte wall-coverage plane are created. The kept
;      WallSpanPlan/ClipSpan order paints textured wall tiers into the private
;      frame; every painted pixel sets coverage=1. The wall pass finishes first.
;   4. While the WAD is still open, PlaneFlatCacheBuild loads only unique
;      non-sky flats actually referenced by non-empty marked visplanes.
;   5. PlaneDrawPlanes runs AFTER the complete wall pass, turning visplane bands
;      into R_MakeSpans horizontal spans, sampling R_DrawSpan 64x64 flats and
;      remapping through zlight[16][128]/COLORMAP. Sky visplanes are counted and
;      deferred with no flat load or pixel write. Any plane pixel whose coverage
;      bit is nonzero is an explicit overlap failure; planes never silently
;      overwrite a painted wall pixel.
;   6. A P->V string keeps the timer-style cleanup: a canonical FNV-1a64 over
;      exactly the row-major 64,000 palette bytes, zero/nonzero byte audit and a
;      coverage audit; the target frame is replaced only after full success.
;
; Transaction/ownership:
;   - caller target is byte-for-byte untouched until whole-frame success; all
;     drawing occurs in a private FrameBuffer and private coverage plane, and
;     every failure path frees/discards them before returning the prior target;
;   - result owns only deep-copied numeric plan metadata arrays (WallSpanPlan /
;     WallTextureSpanPlan) and copied counters/hash. It retains no MapLevel, WAD,
;     catalog, camera, plane frame, timeline, cache, light table, colormap,
;     frame, coverage, flat image or temporary pointer;
;   - caller-owned PlaneFrame and WallPlaneTimeline are used for the online
;     chronology, then reset and released after counters are copied. On any
;     failure they are reset to reusable empty state by the cleanup path;
;   - caller-owned optional PlaneSpanTrace remains caller-owned; production CLI
;     omits it. A supplied trace receives bounded row/span records; it is not
;     retained by the result and may be partial on failure (caller resets);
;   - no heap allocation, WAD read, FlatLoad, texture compose or COLORMAP decode
;     happens inside per-column/per-pixel loops; only bounded flat/cache/table/
;     frame/coverage allocations happen before drawing starts.
;
; Caps: span/plan metadata 200,000 spans and 64 MiB; visplanes 1,024 and record
; bytes 65,536; plane frame boards 2,637,056; timeline 65,536 visits/events;
; flat cache 1,024 entries/unique flats; trace 262,144 span records.
;
; Accepted M3-05/M3-06 boundary: the plane dry capture uses the same pre-column
; ceiling/floor clip snapshot as the frozen wall rasterizer for the lower-tier
; clamp (documented difference from a C live re-read after top-tier mutation),
; keeping plane bands disjoint from painted wall columns. Bottom row pads are 0
; (source has stale/uninitialized bottoms that cannot emit drawable rows;
; documented safe deviation). zlight negative signed distance adopts the source
; unsigned clamp-127 behavior. Palette index 0 and 255 are ordinary values.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PLANERENDERMAIN_PBI, #PB_Constant) = 0

#DOOMPB_PLANERENDERMAIN_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Core/TrigTables.pbi"
XIncludeFile "../Map/MapLevel.pbi"
XIncludeFile "../Graphics/FrameBuffer.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "../Graphics/TextureDefs.pbi"
XIncludeFile "../Graphics/Colormap.pbi"
XIncludeFile "Projection.pbi"
XIncludeFile "WallVisibility.pbi"
XIncludeFile "WallView.pbi"
XIncludeFile "WallProject.pbi"
XIncludeFile "WallDraw.pbi"
XIncludeFile "WallTextureMapping.pbi"
XIncludeFile "WallTextureCache.pbi"
XIncludeFile "WallLighting.pbi"
XIncludeFile "TexturedWallDraw.pbi"
XIncludeFile "Planes.pbi"
XIncludeFile "PlaneMapping.pbi"
XIncludeFile "PlaneFlatCache.pbi"
XIncludeFile "PlaneDraw.pbi"

#PLANERENDER_Magic = $504C4D31
#PLANERENDER_MaxSpans = 200000
#PLANERENDER_MaxMetadataBytes = 67108864
#PLANERENDER_FrameWidth = #PROJ_VIEWWIDTH
#PLANERENDER_FrameHeight = #PROJ_VIEWHEIGHT
#PLANERENDER_FramePixelCount = #PLANERENDER_FrameWidth * #PLANERENDER_FrameHeight
#PLANERENDER_BackgroundIndex = 0
#PLANERENDER_FNV_Offset = -3750763034362895579
#PLANERENDER_FNV_Prime = 1099511628211
#PLANERENDER_CoverageBytes = #PLANERENDER_FramePixelCount

Structure PlaneRenderResult
  Magic.l
  Ready.l
  SpanCount.l
  SegmentCount.l
  SegmentCapacity.l
  TexturePlanCount.l
  TexturePlanCapacity.l
  *Plans.WallSpanPlan
  *TexturePlans.WallTextureSpanPlan
  Visplanes.l
  RegularVisplanes.l
  SkyVisplanes.l
  EmptyVisplanes.l
  PopulatedVisplanes.l
  SkyDeferredBands.l
  SkyDeferredPixels.l
  PlaneSpans.l
  PlanePixels.l
  PlaneOpenedRows.l
  PlaneClosedRows.l
  PlaneRowCacheHits.l
  PlaneRowCacheMisses.l
  PlaneColormapTexels.l
  FloorVisplanes.l
  CeilingVisplanes.l
  FloorPixels.l
  CeilingPixels.l
  FindCalls.l
  FindReuse.l
  FindCreate.l
  CheckCalls.l
  CheckMerges.l
  CheckSplits.l
  MarkCeilingCalls.l
  MarkFloorCalls.l
  MarkCeilingBands.l
  MarkFloorBands.l
  TimelineVisits.l
  TimelineEvents.l
  ZeroSpanVisits.l
  SkyFindVisits.l
  RegularFindVisits.l
  TimelineMarkedCeilingColumns.l
  TimelineMarkedFloorColumns.l
  TimelineStoredCeilingBands.l
  TimelineStoredFloorBands.l
  WallProcessedColumns.l
  WallTextureColumnsComputed.l
  WallMiddlePixels.l
  WallUpperPixels.l
  WallLowerPixels.l
  WallDrawnPixels.l
  WallMiddleRanges.l
  WallUpperRanges.l
  WallLowerRanges.l
  WallDrawRanges.l
  WallEmptyColumns.l
  WallClippedColumns.l
  WallOutOfFrameColumns.l
  WallTextureSamples.l
  WallUncoveredTexels.l
  WallShortHeightFallbacks.l
  WallCoveredPixels.l
  NonZeroBytes.l
  ZeroBytes.l
  ComposedTextures.l
  RequestedReferences.l
  ReusedReferences.l
  MaskedMidSpans.l
  ShortTextures.l
  TextureCacheAllocations.l
  FlatCacheCount.l
  FlatCacheCapacity.l
  FlatCacheRequestedReferences.l
  FlatCacheUniqueFlats.l
  FlatCacheLoadedFlats.l
  FlatCacheAllocations.l
  PlaneFrameAllocations.l
  TimelineAllocations.l
  ZLightAllocations.l
  WallTableAllocations.l
  VisibilityAllocations.l
  ClipAllocations.l
  FrameAllocations.l
  CoverageAllocations.l
  MetadataAllocations.l
  Allocations.l
  VisitedNodes.l
  VisitedSubsectors.l
  ProcessedSegs.l
  EmittedFragments.l
  SolidCandidates.l
  PassCandidates.l
  BboxTests.l
  BboxOccluded.l
  OcclusionSkips.l
  Hash.q
  FrameWidth.l
  FrameHeight.l
EndStructure

Global gPlaneRenderMain_LastError.s = ""

Procedure PlaneRenderSetError(Message.s)
  gPlaneRenderMain_LastError = Message
EndProcedure

Procedure.s PlaneRenderLastError()
  ProcedureReturn gPlaneRenderMain_LastError
EndProcedure

Declare.i PlaneRenderFailureFinalize(*Result.PlaneRenderResult, FailureText.s)

Procedure.i PlaneRenderResultIsValid(*Result.PlaneRenderResult)
  ProcedureReturn Bool(*Result <> 0 And *Result\Magic = #PLANERENDER_Magic)
EndProcedure

; Idempotent empty reusable result: frees only the recognized numeric plan arrays
; (never pointers inside the numeric records). Foreign Magic or unexplained
; pointers are rejected, not freed.
Procedure.i PlaneRenderResultReset(*Result.PlaneRenderResult)
  If *Result = 0
    PlaneRenderSetError("Plane render result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Result\Magic = #PLANERENDER_Magic
    If *Result\Plans <> 0
      FreeMemory(*Result\Plans)
    EndIf
    If *Result\TexturePlans <> 0
      FreeMemory(*Result\TexturePlans)
    EndIf
  ElseIf *Result\Magic <> 0
    PlaneRenderSetError("Plane render result has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Result\Plans <> 0 Or *Result\TexturePlans <> 0
    PlaneRenderSetError("Plane render result has an unexplained metadata pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Result, Int(SizeOf(PlaneRenderResult)), 0)
  *Result\Magic = #PLANERENDER_Magic
  *Result\Ready = 0
  gPlaneRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent canonical frame byte audit (verification/statistics only)
; ---------------------------------------------------------------------------

Procedure.i PlaneRenderFrameByteAudit(*FrameBuffer.FrameBuffer,
                                      *NonZeroBytes.Long, *ZeroBytes.Long)
  Protected byteIndex.i
  Protected value.i
  Protected nonzero.l = 0

  PlaneRenderSetError("")
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic Or
     *FrameBuffer\Width <> #PLANERENDER_FrameWidth Or
     *FrameBuffer\Height <> #PLANERENDER_FrameHeight Or
     *FrameBuffer\PixelCount <> #PLANERENDER_FramePixelCount Or *FrameBuffer\Pixels = 0
    PlaneRenderSetError("Plane render byte audit: framebuffer is not the exact 320x200 plane.")
    ProcedureReturn #False
  EndIf

  For byteIndex = 0 To #PLANERENDER_FramePixelCount - 1
    value = PeekA(*FrameBuffer\Pixels + byteIndex)
    If value <> 0
      nonzero + 1
    EndIf
  Next
  If *NonZeroBytes <> 0
    PokeL(*NonZeroBytes, nonzero)
  EndIf
  If *ZeroBytes <> 0
    PokeL(*ZeroBytes, Int(#PLANERENDER_FramePixelCount) - nonzero)
  EndIf
  gPlaneRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; Explicit 64,000-byte wall-coverage audit: every byte must be 0 or 1; the count
; of nonzero cells is the number of distinct wall-painted pixels. A plane draw
; pixel with a nonzero coverage cell aborts inside PlaneDrawOneSpan, so success
; proves no plane overwrote a wall column.
Procedure.i PlaneRenderCoverageAudit(*Coverage.Byte, *CoveredPixels.Long)
  Protected cellIndex.i
  Protected value.i
  Protected covered.l = 0

  PlaneRenderSetError("")
  If *Coverage = 0 Or *CoveredPixels = 0
    PlaneRenderSetError("Plane coverage audit: coverage/result pointer is null.")
    ProcedureReturn #False
  EndIf
  For cellIndex = 0 To Int(#PLANERENDER_CoverageBytes) - 1
    value = PeekA(*Coverage + cellIndex)
    If value <> 0 And value <> 1
      PlaneRenderSetError("Plane coverage audit: coverage byte is not 0/1 at cell " +
                          Str(cellIndex) + ": " + Str(value) + ".")
      ProcedureReturn #False
    EndIf
    If value <> 0
      covered + 1
    EndIf
  Next
  *CoveredPixels\l = covered
  gPlaneRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Transactional combined wall + plane frame build
; ---------------------------------------------------------------------------

; One complete combined frame. *Target remains byte-for-byte unchanged on every
; failure; success replaces it by a newly owned canonical index plane. Result
; publishes only copied numeric metadata/counters/hash. The caller-owned
; PlaneFrame/Timeline are used internally and reset before return.
Procedure.i PlaneRenderFrame(*Level.MapLevel, *View.WallView,
                             *Projection.Projection,
                             *Flats.FlatCatalog,
                             *Textures.TextureCatalog,
                             *Colormap.ColormapSet,
                             *Target.FrameBuffer,
                             *Result.PlaneRenderResult,
                             RequirePlanePixels.i = #False,
                             *Trace.PlaneSpanTrace = 0)
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected cameraHeading.q = 0
  Protected cameraViewZ.l = 0
  Protected spanCount.l = 0
  Protected segmentCount.l = 0
  Protected legacyBytes.q
  Protected textureBytes.q
  Protected legacyMemory.i = 0
  Protected textureMemory.i = 0
  Protected visibility.WallVisibilityResult
  Protected planeFrame.PlaneFrame
  Protected timeline.WallPlaneTimeline
  Protected visibleSpan.WallSpan
  Protected spanSub.l = 0
  Protected spanSeg.l = 0
  Protected spanLine.l = 0
  Protected spanSide.l = 0
  Protected spanFront.l = 0
  Protected spanBack.l = 0
  Protected spanFirst.l = 0
  Protected spanLast.l = 0
  Protected spanKind.l = 0
  Protected *plan.WallSpanPlan
  Protected *texturePlan.WallTextureSpanPlan
  Protected clip.WallVerticalClip
  Protected table.WallScalelightTable
  Protected zlight.PlaneZLightTable
  Protected cache.WallTextureCache
  Protected flatsCache.PlaneFlatCache
  Protected wallTally.WallTextureDrawTally
  Protected planeTally.PlaneDrawTally
  Protected frame.FrameBuffer
  Protected *coverage.Byte = 0
  Protected coverageMemory.i = 0
  Protected clipStarted.i = #False
  Protected tableStarted.i = #False
  Protected zlightStarted.i = #False
  Protected cacheStarted.i = #False
  Protected flatCacheStarted.i = #False
  Protected wallClipStarted.i = #False
  Protected frameStarted.i = #False
  Protected coverageStarted.i = #False
  Protected visibilityStarted.i = #False
  Protected planCount.l = 0
  Protected texturePlanCount.l = 0
  Protected spanHash.q = 0
  Protected explicitAllocations.l = 0
  Protected allocationTotal.l = 0
  Protected visibilityAllocations.l = 0
  Protected clipAllocations.l = 0
  Protected tableAllocCount.l = 0
  Protected zlightAllocCount.l = 0
  Protected frameAllocCount.l = 0
  Protected coverageAllocCount.l = 0
  Protected metadataAllocations.l = 0
  Protected cacheCount.l = 0
  Protected cacheCapacity.l = 0
  Protected cacheRequestedReferences.l = 0
  Protected cacheReusedReferences.l = 0
  Protected cacheMaskedMidSpans.l = 0
  Protected cacheShortTextures.l = 0
  Protected cacheAllocations.l = 0
  Protected cacheTempBytes.q = 0
  Protected cachePlaneBytes.q = 0
  Protected cachePeakBytes.q = 0
  Protected flatCacheCount.l = 0
  Protected flatCacheCapacity.l = 0
  Protected flatCacheRequested.l = 0
  Protected flatCacheUnique.l = 0
  Protected flatCacheLoaded.l = 0
  Protected flatCacheAllocCount.l = 0
  Protected planeFrameAllocCount.l = 0
  Protected timelineAllocCount.l = 0
  Protected wallCoveredPixels.l = 0
  Protected nonzeroBytes.l = 0
  Protected zeroBytes.l = 0

  ; Counters copied from the caller-owned plane/timeline frames before reset.
  Protected visplanes.l = 0
  Protected drawScanned.l = 0
  Protected regularVisplanes.l = 0
  Protected skyVisplanes.l = 0
  Protected emptyVisplanes.l = 0
  Protected populatedVisplanes.l = 0
  Protected skyDeferredBands.l = 0
  Protected skyDeferredPixels.l = 0
  Protected planeSpans.l = 0
  Protected planePixels.l = 0
  Protected planeOpenedRows.l = 0
  Protected planeClosedRows.l = 0
  Protected planeRowCacheHits.l = 0
  Protected planeRowCacheMisses.l = 0
  Protected planeColormapTexels.l = 0
  Protected floorVisplanes.l = 0
  Protected ceilingVisplanes.l = 0
  Protected floorPixels.l = 0
  Protected ceilingPixels.l = 0
  Protected findCalls.l = 0
  Protected findReuse.l = 0
  Protected findCreate.l = 0
  Protected checkCalls.l = 0
  Protected checkMerges.l = 0
  Protected checkSplits.l = 0
  Protected markCeilingCalls.l = 0
  Protected markFloorCalls.l = 0
  Protected markCeilingBands.l = 0
  Protected markFloorBands.l = 0
  Protected timelineVisits.l = 0
  Protected timelineEvents.l = 0
  Protected zeroSpanVisits.l = 0
  Protected skyFindVisits.l = 0
  Protected regularFindVisits.l = 0
  Protected timelineMarkCeilingColumns.l = 0
  Protected timelineMarkFloorColumns.l = 0
  Protected timelineStoredCeilingBands.l = 0
  Protected timelineStoredFloorBands.l = 0
  Protected visitedNodes.l = 0
  Protected visitedSubsectors.l = 0
  Protected processedSegs.l = 0
  Protected emittedFragments.l = 0
  Protected solidCandidates.l = 0
  Protected passCandidates.l = 0
  Protected bboxTests.l = 0
  Protected bboxOccluded.l = 0
  Protected occlusionSkips.l = 0

  Protected failureText.s = ""
  Protected savedFailureText.s = ""

  PlaneRenderSetError("")
  If *Result = 0
    PlaneRenderSetError("PlaneRenderFrame: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneRenderResultReset(*Result) = #False
    ProcedureReturn #False
  EndIf
  If *Target = 0
    PlaneRenderSetError("PlaneRenderFrame: target framebuffer pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Target\Magic <> 0 And *Target\Magic <> #FRAMEBUFFER_Magic
    PlaneRenderSetError("PlaneRenderFrame: target framebuffer has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If *Target\Magic = 0 And *Target\Pixels <> 0
    PlaneRenderSetError("PlaneRenderFrame: target framebuffer has an unexplained pixel pointer without a Magic value.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    PlaneRenderSetError("PlaneRenderFrame: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *View = 0 Or WallViewIsValid(*View) = #False
    PlaneRenderSetError("PlaneRenderFrame: wall view is not ready.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    PlaneRenderSetError("PlaneRenderFrame: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Projection\Width <> #PLANERENDER_FrameWidth Or
     *Projection\ViewHeight <> #PLANERENDER_FrameHeight
    PlaneRenderSetError("PlaneRenderFrame: non-canonical 320x200 full-detail projection.")
    ProcedureReturn #False
  EndIf
  If *Flats = 0 Or *Flats\Magic <> #FLAT_CatalogMagic
    PlaneRenderSetError("PlaneRenderFrame: flat catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Textures = 0 Or *Textures\Magic <> #TEXTURE_CatalogMagic
    PlaneRenderSetError("PlaneRenderFrame: texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic
    PlaneRenderSetError("PlaneRenderFrame: COLORMAP is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneColormapValidate(*Colormap, 0) = #False
    PlaneRenderSetError("PlaneRenderFrame: COLORMAP lacks classic plane/wall lighting tables: " +
                        PlaneMappingLastError())
    ProcedureReturn #False
  EndIf
  If *Trace <> 0 And PlaneSpanTraceIsValid(*Trace) = #False
    PlaneRenderSetError("PlaneRenderFrame: supplied plane span trace is not initialized.")
    ProcedureReturn #False
  EndIf

  If WallViewGet(*View, @cameraX, @cameraY, @cameraHeading, @cameraViewZ) = #False
    PlaneRenderSetError("PlaneRenderFrame: cannot read wall view: " + WallViewLastError())
    ProcedureReturn #False
  EndIf

  ; Exact online producer: camera and ViewZFixed flow into the unchanged M3-04
  ; near-to-far walker, with the optional plane frame/timeline chronology hooks.
  visibilityStarted = #True
  If WallVisibilityBuild(*Level, *View\Camera, *Projection, *Flats, *Textures,
                         @visibility, cameraViewZ, @planeFrame, @timeline) = #False
    failureText = "PlaneRenderFrame online visibility+plane chronology failed: " +
                  WallVisibilityLastError()
    Goto PlaneRenderFailure
  EndIf
  spanCount = WallVisibilityCount(@visibility)
  If spanCount < 0
    failureText = "PlaneRenderFrame cannot read visibility span count: " + WallVisibilityLastError()
    Goto PlaneRenderFailure
  EndIf
  If spanCount > #PLANERENDER_MaxSpans
    failureText = "PlaneRenderFrame visibility span count " + Str(spanCount) +
                  " exceeds the renderer budget " + Str(#PLANERENDER_MaxSpans) + "."
    Goto PlaneRenderFailure
  EndIf

  If WallVisibilityGetStats(@visibility, @visitedNodes, @visitedSubsectors,
                            @processedSegs, @emittedFragments, 0, 0, 0, 0, 0, 0,
                            @solidCandidates, @passCandidates, @bboxTests, 0,
                            @bboxOccluded, 0, @occlusionSkips, 0, 0, 0,
                            @visibilityAllocations) = #False
    failureText = "PlaneRenderFrame cannot read visibility counters: " + WallVisibilityLastError()
    Goto PlaneRenderFailure
  EndIf

  ; One owned legacy plan array for the whole frame, one textured-plan array.
  If spanCount > 0
    legacyBytes = Int(spanCount) * Int(SizeOf(WallSpanPlan))
    textureBytes = Int(spanCount) * Int(SizeOf(WallTextureSpanPlan))
    If legacyBytes <= 0 Or legacyBytes > #PLANERENDER_MaxMetadataBytes Or
       textureBytes <= 0 Or textureBytes > #PLANERENDER_MaxMetadataBytes
      failureText = "PlaneRenderFrame wall/plane metadata byte budgets are exceeded."
      Goto PlaneRenderFailure
    EndIf
    legacyMemory = AllocateMemory(legacyBytes)
    If legacyMemory = 0
      failureText = "PlaneRenderFrame: out of memory for M3-05 wall plan metadata."
      Goto PlaneRenderFailure
    EndIf
    FillMemory(legacyMemory, Int(legacyBytes), 0)
    explicitAllocations + 1
    metadataAllocations + 1
    *Result\SegmentCapacity = spanCount
    *Result\Plans = legacyMemory

    textureMemory = AllocateMemory(textureBytes)
    If textureMemory = 0
      failureText = "PlaneRenderFrame: out of memory for textured plan metadata."
      Goto PlaneRenderFailure
    EndIf
    FillMemory(textureMemory, Int(textureBytes), 0)
    explicitAllocations + 1
    metadataAllocations + 1
    *Result\TexturePlanCapacity = spanCount
    *Result\TexturePlans = textureMemory
  EndIf

  ; Build every legacy plan in published visibility chronology (same accepted
  ; M3-05 geometry used by the dry plane capture during the online walk).
  For segmentCount = 0 To spanCount - 1
    ; Read the complete span identity through the published accessor with local
    ; output cells so no numeric record field is assumed for missing fields.
    If WallVisibilityGetSpan(@visibility, segmentCount, @spanSub, @spanSeg,
                             @spanLine, @spanSide, @spanFront, @spanBack,
                             @spanFirst, @spanLast, @spanKind) = #False
      failureText = "PlaneRenderFrame span " + Str(segmentCount) +
                    " full access failed: " + WallVisibilityLastError()
      Goto PlaneRenderFailure
    EndIf
    visibleSpan\Subsector = spanSub
    visibleSpan\Seg = spanSeg
    visibleSpan\Linedef = spanLine
    visibleSpan\Side = spanSide
    visibleSpan\FrontSector = spanFront
    visibleSpan\BackSector = spanBack
    visibleSpan\FirstX = spanFirst
    visibleSpan\LastX = spanLast
    visibleSpan\Kind = spanKind
    *plan = *Result\Plans + segmentCount * SizeOf(WallSpanPlan)
    If WallProjectSpanChecked(*Level, *Flats, *Textures, *Projection,
                              cameraX, cameraY, cameraHeading, cameraViewZ,
                              segmentCount, @visibleSpan, *plan) = #False
      failureText = "PlaneRenderFrame span " + Str(segmentCount) +
                    " projection failed: " + WallProjectLastError()
      Goto PlaneRenderFailure
    EndIf
    planCount + 1
  Next
  If planCount <> spanCount
    failureText = "PlaneRenderFrame legacy plan accounting disagrees with the visibility count."
    Goto PlaneRenderFailure
  EndIf

  ; Used-texture cache built from the already-decided M3-05 tier flags, while WAD open.
  cacheStarted = #True
  If WallTextureCacheBuild(*Level, *Textures, *Result\Plans, spanCount, @cache) = #False
    failureText = "PlaneRenderFrame texture cache build failed: " + WallTextureCacheLastError()
    Goto PlaneRenderFailure
  EndIf
  If WallTextureCacheGetStats(@cache, @cacheCount, @cacheCapacity,
                              @cacheRequestedReferences, @cacheReusedReferences,
                              @cacheMaskedMidSpans, @cacheShortTextures,
                              @cacheAllocations, @cacheTempBytes, @cachePlaneBytes,
                              @cachePeakBytes) = #False
    failureText = "PlaneRenderFrame texture-cache statistics read failed: " + WallTextureCacheLastError()
    Goto PlaneRenderFailure
  EndIf

  ; Vanilla 320-column wall scalelight table from the >=32-table COLORMAP.
  tableStarted = #True
  If WallScalelightTableBuild(@table, *Colormap) = #False
    failureText = "PlaneRenderFrame wall scalelight table build failed: " + WallLightingLastError()
    Goto PlaneRenderFailure
  EndIf
  tableAllocCount = table\Allocations

  ; Classic plane zlight[16][128] from the same decoded COLORMAP; independent
  ; numeric map-index storage, never a wall scalelight pointer.
  zlightStarted = #True
  If PlaneZLightTableBuild(@zlight, *Colormap) = #False
    failureText = "PlaneRenderFrame plane zlight table build failed: " + PlaneMappingLastError()
    Goto PlaneRenderFailure
  EndIf
  zlightAllocCount = zlight\Allocations

  ; One textured material/pegging/light plan per legacy plan.
  For texturePlanCount = 0 To spanCount - 1
    *plan = *Result\Plans + texturePlanCount * SizeOf(WallSpanPlan)
    *texturePlan = *Result\TexturePlans + texturePlanCount * SizeOf(WallTextureSpanPlan)
    If WallTextureSpanPrepareChecked(*Level, *Textures, @cache, *plan,
                                     cameraViewZ, *texturePlan) = #False
      failureText = "PlaneRenderFrame span " + Str(texturePlanCount) +
                    " texture plan preparation failed: " + WallTextureCacheLastError()
      Goto PlaneRenderFailure
    EndIf
  Next

  ; Owned per-frame vertical clip arrays, exactly -1/200 initialization.
  wallClipStarted = #True
  If WallVerticalClipBegin(@clip) = #False
    failureText = "PlaneRenderFrame: vertical clip array allocation failed: " + WallDrawLastError()
    Goto PlaneRenderFailure
  EndIf
  clipAllocations = 1
  If WallTextureDrawTallyReset(@wallTally) = #False
    failureText = "PlaneRenderFrame: wall tally initialization failed: " + TexturedWallDrawLastError()
    Goto PlaneRenderFailure
  EndIf

  ; Private canonical frame cleared before any pixel write.
  frameStarted = #True
  If FrameBufferCreate(@frame, #PLANERENDER_FrameWidth, #PLANERENDER_FrameHeight) = #False
    failureText = "PlaneRenderFrame: private framebuffer creation failed: " + FrameBufferLastError()
    Goto PlaneRenderFailure
  EndIf
  frameAllocCount = 1
  If FrameBufferClear(@frame, #PLANERENDER_BackgroundIndex) = #False
    failureText = "PlaneRenderFrame: private framebuffer clear failed: " + FrameBufferLastError()
    Goto PlaneRenderFailure
  EndIf

  ; Private explicit wall-coverage plane: zeroed before the wall pass.
  coverageStarted = #True
  coverageMemory = AllocateMemory(#PLANERENDER_CoverageBytes)
  If coverageMemory = 0
    failureText = "PlaneRenderFrame: out of memory for the explicit wall-coverage plane."
    Goto PlaneRenderFailure
  EndIf
  coverageAllocCount = 1
  *coverage = coverageMemory
  FillMemory(*coverage, Int(#PLANERENDER_CoverageBytes), 0)

  ; Chronological textured wall pass into the private frame: no sort/dedupe/BSP
  ; rewalk; coverage=1 for each painted pixel via the optional mask.
  For segmentCount = 0 To spanCount - 1
    *plan = *Result\Plans + segmentCount * SizeOf(WallSpanPlan)
    *texturePlan = *Result\TexturePlans + segmentCount * SizeOf(WallTextureSpanPlan)
    If TexturedWallDrawSpan(@frame, *plan, *texturePlan, @cache, *Projection,
                            @table, *Colormap, @clip, @wallTally, *coverage) = #False
      failureText = "PlaneRenderFrame span " + Str(segmentCount) +
                    " textured wall drawing failed: " + TexturedWallDrawLastError()
      Goto PlaneRenderFailure
    EndIf
  Next
  If wallTally\ProcessedSpans <> spanCount Or wallTally\ProcessedColumns < 0 Or
     wallTally\DrawnPixels < 0
    failureText = "Plane wall pass span/pixel accounting disagrees with the visibility count."
    Goto PlaneRenderFailure
  EndIf
  ; Load only unique, actually used, non-sky flats while the resolved WAD is open.
  flatCacheStarted = #True
  If PlaneFlatCacheBuild(@flatsCache, *Flats, @planeFrame) = #False
    failureText = "PlaneRenderFrame flat cache build failed: " + PlaneFlatCacheLastError()
    Goto PlaneRenderFailure
  EndIf
  If PlaneFlatCacheGetStats(@flatsCache, @flatCacheCount, @flatCacheCapacity,
                            @flatCacheRequested, @flatCacheUnique, @flatCacheLoaded,
                            @flatCacheAllocCount) = #False
    failureText = "PlaneRenderFrame flat-cache statistics read failed: " + PlaneFlatCacheLastError()
    Goto PlaneRenderFailure
  EndIf

  ; A single plane pass requires the caller-owned tally to be reset-empty at entry;
  ; PlaneDrawPlanes publishes only on full success. The frame's vertical clip for
  ; plane drawing is the private PlaneFrame's cached tables and spanstart, not the
  ; wall clip. Draw after the complete wall pass.
  If PlaneDrawPlanes(@planeFrame, @flatsCache, *Colormap, @zlight,
                     @frame, *coverage, @planeTally, *Trace) = #False
    failureText = "PlaneRenderFrame plane drawing failed: " + PlaneDrawLastError()
    Goto PlaneRenderFailure
  EndIf

  ; Copy and validate frame/timeline/plane counters before their release.
  If PlaneFrameGetStats(@planeFrame, @visplanes, @findCalls, @findReuse,
                        @findCreate, @checkCalls, @checkMerges, @checkSplits,
                        @markCeilingCalls, @markFloorCalls, @markCeilingBands,
                        @markFloorBands, @skyVisplanes, @planeFrameAllocCount) = #False
    failureText = "PlaneRenderFrame plane-frame statistics read failed: " + PlanesLastError()
    Goto PlaneRenderFailure
  EndIf
  If PlaneTimelineGetStats(@timeline, @timelineVisits, @timelineEvents,
                           @zeroSpanVisits, @skyFindVisits, @regularFindVisits,
                           @timelineMarkCeilingColumns, @timelineMarkFloorColumns,
                           @timelineStoredCeilingBands, @timelineStoredFloorBands,
                           @timelineAllocCount) = #False
    failureText = "PlaneRenderFrame plane-timeline statistics read failed: " + PlanesLastError()
    Goto PlaneRenderFailure
  EndIf
  If PlaneDrawGetStats(@planeTally, @drawScanned, @regularVisplanes, @skyVisplanes,
                       @emptyVisplanes, @populatedVisplanes, @skyDeferredBands,
                       @skyDeferredPixels, @planeSpans, @planePixels,
                       @planeOpenedRows, @planeClosedRows, @planeRowCacheHits,
                       @planeRowCacheMisses, @planeColormapTexels,
                       @floorVisplanes, @ceilingVisplanes, @floorPixels,
                       @ceilingPixels) = #False
    failureText = "PlaneRenderFrame plane-draw statistics read failed: " + PlaneDrawLastError()
    Goto PlaneRenderFailure
  EndIf

  ; The plane draw scanned exactly the frame's created visplane count.
  If visplanes < 0 Or visplanes > planeFrame\Capacity Or drawScanned <> visplanes
    failureText = "PlaneRenderFrame plane draw scan/creation accounting disagrees."
    Goto PlaneRenderFailure
  EndIf
  If RequirePlanePixels <> 0 And planePixels = 0
    failureText = "PlaneRenderFrame produced zero regular flat pixels for an expected-visible floor/ceiling frame."
    Goto PlaneRenderFailure
  EndIf

  ; Explicit wall/plane coverage audit: wall coverage cells are 0/1, the covered
  ; count must equal the wall writes, and successful plane drawing proves it
  ; never wrote a covered wall pixel. Compare coverage marks, not palette bytes.
  If PlaneRenderCoverageAudit(*coverage, @wallCoveredPixels) = #False
    failureText = "PlaneRenderFrame coverage audit failed: " + PlaneRenderLastError()
    Goto PlaneRenderFailure
  EndIf
  If wallCoveredPixels <> wallTally\DrawnPixels
    failureText = "PlaneRenderFrame wall coverage count " + Str(wallCoveredPixels) +
                  " disagrees with painted wall pixels " + Str(wallTally\DrawnPixels) + "."
    Goto PlaneRenderFailure
  EndIf

  ; Authoritative hash exactly over the private frame's 64,000 palette bytes.
  If WallFrameHash64(@frame, @spanHash) = #False
    failureText = "PlaneRenderFrame frame hash failed: " + WallDrawLastError()
    Goto PlaneRenderFailure
  EndIf
  If PlaneRenderFrameByteAudit(@frame, @nonzeroBytes, @zeroBytes) = #False
    failureText = "PlaneRenderFrame byte audit failed: " + PlaneRenderLastError()
    Goto PlaneRenderFailure
  EndIf

  ; Success: sole point of target release/replacement.
  If FrameBufferReset(*Target) = #False
    failureText = "PlaneRenderFrame target framebuffer reset failed: " + FrameBufferLastError()
    Goto PlaneRenderFailure
  EndIf
  *Target\Magic = #FRAMEBUFFER_Magic
  *Target\Width = frame\Width
  *Target\Height = frame\Height
  *Target\PixelCount = frame\PixelCount
  *Target\Pixels = frame\Pixels
  frame\Magic = 0
  frame\Width = 0
  frame\Height = 0
  frame\PixelCount = 0
  frame\Pixels = 0
  FrameBufferReset(@frame)

  ; Copied numeric statistics publication. Local owning objects are released.
  allocationTotal = explicitAllocations + visibilityAllocations + clipAllocations +
                    tableAllocCount + zlightAllocCount + frameAllocCount +
                    coverageAllocCount + planeFrameAllocCount + timelineAllocCount +
                    cacheAllocations + flatCacheAllocCount
  *Result\SpanCount = spanCount
  *Result\SegmentCount = planCount
  *Result\TexturePlanCount = spanCount
  *Result\Visplanes = visplanes
  *Result\RegularVisplanes = regularVisplanes
  *Result\SkyVisplanes = skyVisplanes
  *Result\EmptyVisplanes = emptyVisplanes
  *Result\PopulatedVisplanes = populatedVisplanes
  *Result\SkyDeferredBands = skyDeferredBands
  *Result\SkyDeferredPixels = skyDeferredPixels
  *Result\PlaneSpans = planeSpans
  *Result\PlanePixels = planePixels
  *Result\PlaneOpenedRows = planeOpenedRows
  *Result\PlaneClosedRows = planeClosedRows
  *Result\PlaneRowCacheHits = planeRowCacheHits
  *Result\PlaneRowCacheMisses = planeRowCacheMisses
  *Result\PlaneColormapTexels = planeColormapTexels
  *Result\FloorVisplanes = floorVisplanes
  *Result\CeilingVisplanes = ceilingVisplanes
  *Result\FloorPixels = floorPixels
  *Result\CeilingPixels = ceilingPixels
  *Result\FindCalls = findCalls
  *Result\FindReuse = findReuse
  *Result\FindCreate = findCreate
  *Result\CheckCalls = checkCalls
  *Result\CheckMerges = checkMerges
  *Result\CheckSplits = checkSplits
  *Result\MarkCeilingCalls = markCeilingCalls
  *Result\MarkFloorCalls = markFloorCalls
  *Result\MarkCeilingBands = markCeilingBands
  *Result\MarkFloorBands = markFloorBands
  *Result\TimelineVisits = timelineVisits
  *Result\TimelineEvents = timelineEvents
  *Result\ZeroSpanVisits = zeroSpanVisits
  *Result\SkyFindVisits = skyFindVisits
  *Result\RegularFindVisits = regularFindVisits
  *Result\TimelineMarkedCeilingColumns = timelineMarkCeilingColumns
  *Result\TimelineMarkedFloorColumns = timelineMarkFloorColumns
  *Result\TimelineStoredCeilingBands = timelineStoredCeilingBands
  *Result\TimelineStoredFloorBands = timelineStoredFloorBands
  *Result\WallProcessedColumns = wallTally\ProcessedColumns
  *Result\WallTextureColumnsComputed = wallTally\TextureColumnsComputed
  *Result\WallMiddlePixels = wallTally\MiddlePixels
  *Result\WallUpperPixels = wallTally\UpperPixels
  *Result\WallLowerPixels = wallTally\LowerPixels
  *Result\WallDrawnPixels = wallTally\DrawnPixels
  *Result\WallMiddleRanges = wallTally\MiddleRanges
  *Result\WallUpperRanges = wallTally\UpperRanges
  *Result\WallLowerRanges = wallTally\LowerRanges
  *Result\WallDrawRanges = wallTally\DrawRanges
  *Result\WallEmptyColumns = wallTally\EmptyColumns
  *Result\WallClippedColumns = wallTally\ClippedColumns
  *Result\WallOutOfFrameColumns = wallTally\OutOfFrameColumns
  *Result\WallTextureSamples = wallTally\TextureSamples
  *Result\WallUncoveredTexels = wallTally\UncoveredTexels
  *Result\WallShortHeightFallbacks = wallTally\ShortHeightFallbacks
  *Result\WallCoveredPixels = wallCoveredPixels
  *Result\NonZeroBytes = nonzeroBytes
  *Result\ZeroBytes = zeroBytes
  *Result\ComposedTextures = cacheCount
  *Result\RequestedReferences = cacheRequestedReferences
  *Result\ReusedReferences = cacheReusedReferences
  *Result\MaskedMidSpans = cacheMaskedMidSpans
  *Result\ShortTextures = cacheShortTextures
  *Result\TextureCacheAllocations = cacheAllocations
  *Result\FlatCacheCount = flatCacheCount
  *Result\FlatCacheCapacity = flatCacheCapacity
  *Result\FlatCacheRequestedReferences = flatCacheRequested
  *Result\FlatCacheUniqueFlats = flatCacheUnique
  *Result\FlatCacheLoadedFlats = flatCacheLoaded
  *Result\FlatCacheAllocations = flatCacheAllocCount
  *Result\PlaneFrameAllocations = planeFrameAllocCount
  *Result\TimelineAllocations = timelineAllocCount
  *Result\ZLightAllocations = zlightAllocCount
  *Result\WallTableAllocations = tableAllocCount
  *Result\VisibilityAllocations = visibilityAllocations
  *Result\ClipAllocations = clipAllocations
  *Result\FrameAllocations = frameAllocCount
  *Result\CoverageAllocations = coverageAllocCount
  *Result\MetadataAllocations = metadataAllocations
  *Result\Allocations = allocationTotal
  *Result\VisitedNodes = visitedNodes
  *Result\VisitedSubsectors = visitedSubsectors
  *Result\ProcessedSegs = processedSegs
  *Result\EmittedFragments = emittedFragments
  *Result\SolidCandidates = solidCandidates
  *Result\PassCandidates = passCandidates
  *Result\BboxTests = bboxTests
  *Result\BboxOccluded = bboxOccluded
  *Result\OcclusionSkips = occlusionSkips
  *Result\Hash = spanHash
  *Result\FrameWidth = #PLANERENDER_FrameWidth
  *Result\FrameHeight = #PLANERENDER_FrameHeight
  *Result\Ready = 1

  ; Release local owning objects after publication; caller plane/timeline and
  ; visibility result are reset exactly once. Coverage is private bytes.
  If *coverage <> 0
    FreeMemory(*coverage)
    *coverage = 0
  EndIf
  WallVerticalClipReset(@clip)
  WallScalelightTableReset(@table)
  PlaneZLightTableReset(@zlight)
  WallTextureCacheReset(@cache)
  PlaneFlatCacheReset(@flatsCache)
  PlaneFrameReset(@planeFrame)
  PlaneTimelineReset(@timeline)
  WallVisibilityReset(@visibility)
  gPlaneRenderMain_LastError = ""
  ProcedureReturn #True

  PlaneRenderFailure:
  If coverageMemory <> 0
    FreeMemory(coverageMemory)
  EndIf
  If frameStarted
    FrameBufferReset(@frame)
  EndIf
  If wallClipStarted
    WallVerticalClipReset(@clip)
  EndIf
  If tableStarted
    WallScalelightTableReset(@table)
  EndIf
  If zlightStarted
    PlaneZLightTableReset(@zlight)
  EndIf
  If cacheStarted
    WallTextureCacheReset(@cache)
  EndIf
  If flatCacheStarted
    PlaneFlatCacheReset(@flatsCache)
  EndIf
  If visibilityStarted
    WallVisibilityReset(@visibility)
  EndIf
  ; The online Build either published or already reset the caller-owned plane
  ; frame/timeline; the cleanup reset is idempotent and leaves reusable empties.
  PlaneFrameReset(@planeFrame)
  PlaneTimelineReset(@timeline)
  If failureText = ""
    failureText = gPlaneRenderMain_LastError
  EndIf
  savedFailureText = failureText
  If savedFailureText = ""
    If PlaneRenderLastError() <> ""
      savedFailureText = PlaneRenderLastError()
    ElseIf WallVisibilityLastError() <> ""
      savedFailureText = WallVisibilityLastError()
    ElseIf PlaneDrawLastError() <> ""
      savedFailureText = PlaneDrawLastError()
    Else
      savedFailureText = "Combined plane frame failed without a specific diagnostic."
    EndIf
  EndIf
  PlaneRenderFailureFinalize(*Result, savedFailureText)
  ProcedureReturn #False
EndProcedure

; Transaction failure finalizer: release result-owned plan arrays and preserve
; the deepest failure text. Target was never touched.
Procedure.i PlaneRenderFailureFinalize(*Result.PlaneRenderResult, FailureText.s)
  Protected saved.s = FailureText
  If saved = ""
    saved = gPlaneRenderMain_LastError
    If saved = ""
      saved = "Combined plane frame failed without a specific diagnostic."
    EndIf
  EndIf
  If PlaneRenderResultReset(*Result) = #False
    ; Preserve the transaction failure text over reset metadata diagnostics.
    If saved = ""
      saved = gPlaneRenderMain_LastError
    EndIf
  EndIf
  PlaneRenderSetError(saved)
  ProcedureReturn #False
EndProcedure

; ---------------------------------------------------------------------------
; Read-only accessors
; ---------------------------------------------------------------------------

; All output pointers may be null; accesses bounded and never partial writes.
Procedure.i PlaneRenderGetStats(*Result.PlaneRenderResult,
                                *SpanCount.Long, *SegmentCount.Long,
                                *SegmentCapacity.Long,
                                *TexturePlanCount.Long, *TexturePlanCapacity.Long,
                                *Visplanes.Long, *RegularVisplanes.Long,
                                *SkyVisplanes.Long, *EmptyVisplanes.Long,
                                *PopulatedVisplanes.Long,
                                *SkyDeferredBands.Long, *SkyDeferredPixels.Long,
                                *PlaneSpans.Long, *PlanePixels.Long,
                                *PlaneOpenedRows.Long, *PlaneClosedRows.Long,
                                *PlaneRowCacheHits.Long, *PlaneRowCacheMisses.Long,
                                *PlaneColormapTexels.Long,
                                *FloorVisplanes.Long, *CeilingVisplanes.Long,
                                *FloorPixels.Long, *CeilingPixels.Long,
                                *FindCalls.Long, *FindReuse.Long, *FindCreate.Long,
                                *CheckCalls.Long, *CheckMerges.Long, *CheckSplits.Long,
                                *MarkCeilingCalls.Long, *MarkFloorCalls.Long,
                                *MarkCeilingBands.Long, *MarkFloorBands.Long,
                                *TimelineVisits.Long, *TimelineEvents.Long,
                                *ZeroSpanVisits.Long, *SkyFindVisits.Long,
                                *RegularFindVisits.Long,
                                *TimelineMarkedCeilingColumns.Long,
                                *TimelineMarkedFloorColumns.Long,
                                *TimelineStoredCeilingBands.Long,
                                *TimelineStoredFloorBands.Long,
                                *WallProcessedColumns.Long,
                                *WallTextureColumnsComputed.Long,
                                *WallMiddlePixels.Long, *WallUpperPixels.Long,
                                *WallLowerPixels.Long, *WallDrawnPixels.Long,
                                *WallMiddleRanges.Long, *WallUpperRanges.Long,
                                *WallLowerRanges.Long, *WallDrawRanges.Long,
                                *WallEmptyColumns.Long, *WallClippedColumns.Long,
                                *WallOutOfFrameColumns.Long,
                                *WallTextureSamples.Long,
                                *WallUncoveredTexels.Long,
                                *WallShortHeightFallbacks.Long,
                                *WallCoveredPixels.Long,
                                *NonZeroBytes.Long, *ZeroBytes.Long,
                                *ComposedTextures.Long,
                                *RequestedReferences.Long,
                                *ReusedReferences.Long,
                                *MaskedMidSpans.Long, *ShortTextures.Long,
                                *TextureCacheAllocations.Long,
                                *FlatCacheCount.Long, *FlatCacheCapacity.Long,
                                *FlatCacheRequestedReferences.Long,
                                *FlatCacheUniqueFlats.Long,
                                *FlatCacheLoadedFlats.Long,
                                *FlatCacheAllocations.Long,
                                *PlaneFrameAllocations.Long,
                                *TimelineAllocations.Long,
                                *ZLightAllocations.Long,
                                *WallTableAllocations.Long,
                                *VisibilityAllocations.Long,
                                *ClipAllocations.Long, *FrameAllocations.Long,
                                *CoverageAllocations.Long,
                                *MetadataAllocations.Long,
                                *Allocations.Long,
                                *VisitedNodes.Long, *VisitedSubsectors.Long,
                                *ProcessedSegs.Long, *EmittedFragments.Long,
                                *SolidCandidates.Long, *PassCandidates.Long,
                                *BboxTests.Long, *BboxOccluded.Long,
                                *OcclusionSkips.Long,
                                *Hash.Quad)
  If PlaneRenderResultIsValid(*Result) = #False
    PlaneRenderSetError("Plane render result is not initialized.")
    ProcedureReturn #False
  EndIf
  If *SpanCount <> 0
    PokeL(*SpanCount, *Result\SpanCount)
  EndIf
  If *SegmentCount <> 0
    PokeL(*SegmentCount, *Result\SegmentCount)
  EndIf
  If *SegmentCapacity <> 0
    PokeL(*SegmentCapacity, *Result\SegmentCapacity)
  EndIf
  If *TexturePlanCount <> 0
    PokeL(*TexturePlanCount, *Result\TexturePlanCount)
  EndIf
  If *TexturePlanCapacity <> 0
    PokeL(*TexturePlanCapacity, *Result\TexturePlanCapacity)
  EndIf
  If *Visplanes <> 0
    PokeL(*Visplanes, *Result\Visplanes)
  EndIf
  If *RegularVisplanes <> 0
    PokeL(*RegularVisplanes, *Result\RegularVisplanes)
  EndIf
  If *SkyVisplanes <> 0
    PokeL(*SkyVisplanes, *Result\SkyVisplanes)
  EndIf
  If *EmptyVisplanes <> 0
    PokeL(*EmptyVisplanes, *Result\EmptyVisplanes)
  EndIf
  If *PopulatedVisplanes <> 0
    PokeL(*PopulatedVisplanes, *Result\PopulatedVisplanes)
  EndIf
  If *SkyDeferredBands <> 0
    PokeL(*SkyDeferredBands, *Result\SkyDeferredBands)
  EndIf
  If *SkyDeferredPixels <> 0
    PokeL(*SkyDeferredPixels, *Result\SkyDeferredPixels)
  EndIf
  If *PlaneSpans <> 0
    PokeL(*PlaneSpans, *Result\PlaneSpans)
  EndIf
  If *PlanePixels <> 0
    PokeL(*PlanePixels, *Result\PlanePixels)
  EndIf
  If *PlaneOpenedRows <> 0
    PokeL(*PlaneOpenedRows, *Result\PlaneOpenedRows)
  EndIf
  If *PlaneClosedRows <> 0
    PokeL(*PlaneClosedRows, *Result\PlaneClosedRows)
  EndIf
  If *PlaneRowCacheHits <> 0
    PokeL(*PlaneRowCacheHits, *Result\PlaneRowCacheHits)
  EndIf
  If *PlaneRowCacheMisses <> 0
    PokeL(*PlaneRowCacheMisses, *Result\PlaneRowCacheMisses)
  EndIf
  If *PlaneColormapTexels <> 0
    PokeL(*PlaneColormapTexels, *Result\PlaneColormapTexels)
  EndIf
  If *FloorVisplanes <> 0
    PokeL(*FloorVisplanes, *Result\FloorVisplanes)
  EndIf
  If *CeilingVisplanes <> 0
    PokeL(*CeilingVisplanes, *Result\CeilingVisplanes)
  EndIf
  If *FloorPixels <> 0
    PokeL(*FloorPixels, *Result\FloorPixels)
  EndIf
  If *CeilingPixels <> 0
    PokeL(*CeilingPixels, *Result\CeilingPixels)
  EndIf
  If *FindCalls <> 0
    PokeL(*FindCalls, *Result\FindCalls)
  EndIf
  If *FindReuse <> 0
    PokeL(*FindReuse, *Result\FindReuse)
  EndIf
  If *FindCreate <> 0
    PokeL(*FindCreate, *Result\FindCreate)
  EndIf
  If *CheckCalls <> 0
    PokeL(*CheckCalls, *Result\CheckCalls)
  EndIf
  If *CheckMerges <> 0
    PokeL(*CheckMerges, *Result\CheckMerges)
  EndIf
  If *CheckSplits <> 0
    PokeL(*CheckSplits, *Result\CheckSplits)
  EndIf
  If *MarkCeilingCalls <> 0
    PokeL(*MarkCeilingCalls, *Result\MarkCeilingCalls)
  EndIf
  If *MarkFloorCalls <> 0
    PokeL(*MarkFloorCalls, *Result\MarkFloorCalls)
  EndIf
  If *MarkCeilingBands <> 0
    PokeL(*MarkCeilingBands, *Result\MarkCeilingBands)
  EndIf
  If *MarkFloorBands <> 0
    PokeL(*MarkFloorBands, *Result\MarkFloorBands)
  EndIf
  If *TimelineVisits <> 0
    PokeL(*TimelineVisits, *Result\TimelineVisits)
  EndIf
  If *TimelineEvents <> 0
    PokeL(*TimelineEvents, *Result\TimelineEvents)
  EndIf
  If *ZeroSpanVisits <> 0
    PokeL(*ZeroSpanVisits, *Result\ZeroSpanVisits)
  EndIf
  If *SkyFindVisits <> 0
    PokeL(*SkyFindVisits, *Result\SkyFindVisits)
  EndIf
  If *RegularFindVisits <> 0
    PokeL(*RegularFindVisits, *Result\RegularFindVisits)
  EndIf
  If *TimelineMarkedCeilingColumns <> 0
    PokeL(*TimelineMarkedCeilingColumns, *Result\TimelineMarkedCeilingColumns)
  EndIf
  If *TimelineMarkedFloorColumns <> 0
    PokeL(*TimelineMarkedFloorColumns, *Result\TimelineMarkedFloorColumns)
  EndIf
  If *TimelineStoredCeilingBands <> 0
    PokeL(*TimelineStoredCeilingBands, *Result\TimelineStoredCeilingBands)
  EndIf
  If *TimelineStoredFloorBands <> 0
    PokeL(*TimelineStoredFloorBands, *Result\TimelineStoredFloorBands)
  EndIf
  If *WallProcessedColumns <> 0
    PokeL(*WallProcessedColumns, *Result\WallProcessedColumns)
  EndIf
  If *WallTextureColumnsComputed <> 0
    PokeL(*WallTextureColumnsComputed, *Result\WallTextureColumnsComputed)
  EndIf
  If *WallMiddlePixels <> 0
    PokeL(*WallMiddlePixels, *Result\WallMiddlePixels)
  EndIf
  If *WallUpperPixels <> 0
    PokeL(*WallUpperPixels, *Result\WallUpperPixels)
  EndIf
  If *WallLowerPixels <> 0
    PokeL(*WallLowerPixels, *Result\WallLowerPixels)
  EndIf
  If *WallDrawnPixels <> 0
    PokeL(*WallDrawnPixels, *Result\WallDrawnPixels)
  EndIf
  If *WallMiddleRanges <> 0
    PokeL(*WallMiddleRanges, *Result\WallMiddleRanges)
  EndIf
  If *WallUpperRanges <> 0
    PokeL(*WallUpperRanges, *Result\WallUpperRanges)
  EndIf
  If *WallLowerRanges <> 0
    PokeL(*WallLowerRanges, *Result\WallLowerRanges)
  EndIf
  If *WallDrawRanges <> 0
    PokeL(*WallDrawRanges, *Result\WallDrawRanges)
  EndIf
  If *WallEmptyColumns <> 0
    PokeL(*WallEmptyColumns, *Result\WallEmptyColumns)
  EndIf
  If *WallClippedColumns <> 0
    PokeL(*WallClippedColumns, *Result\WallClippedColumns)
  EndIf
  If *WallOutOfFrameColumns <> 0
    PokeL(*WallOutOfFrameColumns, *Result\WallOutOfFrameColumns)
  EndIf
  If *WallTextureSamples <> 0
    PokeL(*WallTextureSamples, *Result\WallTextureSamples)
  EndIf
  If *WallUncoveredTexels <> 0
    PokeL(*WallUncoveredTexels, *Result\WallUncoveredTexels)
  EndIf
  If *WallShortHeightFallbacks <> 0
    PokeL(*WallShortHeightFallbacks, *Result\WallShortHeightFallbacks)
  EndIf
  If *WallCoveredPixels <> 0
    PokeL(*WallCoveredPixels, *Result\WallCoveredPixels)
  EndIf
  If *NonZeroBytes <> 0
    PokeL(*NonZeroBytes, *Result\NonZeroBytes)
  EndIf
  If *ZeroBytes <> 0
    PokeL(*ZeroBytes, *Result\ZeroBytes)
  EndIf
  If *ComposedTextures <> 0
    PokeL(*ComposedTextures, *Result\ComposedTextures)
  EndIf
  If *RequestedReferences <> 0
    PokeL(*RequestedReferences, *Result\RequestedReferences)
  EndIf
  If *ReusedReferences <> 0
    PokeL(*ReusedReferences, *Result\ReusedReferences)
  EndIf
  If *MaskedMidSpans <> 0
    PokeL(*MaskedMidSpans, *Result\MaskedMidSpans)
  EndIf
  If *ShortTextures <> 0
    PokeL(*ShortTextures, *Result\ShortTextures)
  EndIf
  If *TextureCacheAllocations <> 0
    PokeL(*TextureCacheAllocations, *Result\TextureCacheAllocations)
  EndIf
  If *FlatCacheCount <> 0
    PokeL(*FlatCacheCount, *Result\FlatCacheCount)
  EndIf
  If *FlatCacheCapacity <> 0
    PokeL(*FlatCacheCapacity, *Result\FlatCacheCapacity)
  EndIf
  If *FlatCacheRequestedReferences <> 0
    PokeL(*FlatCacheRequestedReferences, *Result\FlatCacheRequestedReferences)
  EndIf
  If *FlatCacheUniqueFlats <> 0
    PokeL(*FlatCacheUniqueFlats, *Result\FlatCacheUniqueFlats)
  EndIf
  If *FlatCacheLoadedFlats <> 0
    PokeL(*FlatCacheLoadedFlats, *Result\FlatCacheLoadedFlats)
  EndIf
  If *FlatCacheAllocations <> 0
    PokeL(*FlatCacheAllocations, *Result\FlatCacheAllocations)
  EndIf
  If *PlaneFrameAllocations <> 0
    PokeL(*PlaneFrameAllocations, *Result\PlaneFrameAllocations)
  EndIf
  If *TimelineAllocations <> 0
    PokeL(*TimelineAllocations, *Result\TimelineAllocations)
  EndIf
  If *ZLightAllocations <> 0
    PokeL(*ZLightAllocations, *Result\ZLightAllocations)
  EndIf
  If *WallTableAllocations <> 0
    PokeL(*WallTableAllocations, *Result\WallTableAllocations)
  EndIf
  If *VisibilityAllocations <> 0
    PokeL(*VisibilityAllocations, *Result\VisibilityAllocations)
  EndIf
  If *ClipAllocations <> 0
    PokeL(*ClipAllocations, *Result\ClipAllocations)
  EndIf
  If *FrameAllocations <> 0
    PokeL(*FrameAllocations, *Result\FrameAllocations)
  EndIf
  If *CoverageAllocations <> 0
    PokeL(*CoverageAllocations, *Result\CoverageAllocations)
  EndIf
  If *MetadataAllocations <> 0
    PokeL(*MetadataAllocations, *Result\MetadataAllocations)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Result\Allocations)
  EndIf
  If *VisitedNodes <> 0
    PokeL(*VisitedNodes, *Result\VisitedNodes)
  EndIf
  If *VisitedSubsectors <> 0
    PokeL(*VisitedSubsectors, *Result\VisitedSubsectors)
  EndIf
  If *ProcessedSegs <> 0
    PokeL(*ProcessedSegs, *Result\ProcessedSegs)
  EndIf
  If *EmittedFragments <> 0
    PokeL(*EmittedFragments, *Result\EmittedFragments)
  EndIf
  If *SolidCandidates <> 0
    PokeL(*SolidCandidates, *Result\SolidCandidates)
  EndIf
  If *PassCandidates <> 0
    PokeL(*PassCandidates, *Result\PassCandidates)
  EndIf
  If *BboxTests <> 0
    PokeL(*BboxTests, *Result\BboxTests)
  EndIf
  If *BboxOccluded <> 0
    PokeL(*BboxOccluded, *Result\BboxOccluded)
  EndIf
  If *OcclusionSkips <> 0
    PokeL(*OcclusionSkips, *Result\OcclusionSkips)
  EndIf
  If *Hash <> 0
    PokeQ(*Hash, *Result\Hash)
  EndIf
  gPlaneRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.s PlaneRenderGetHashText(*Result.PlaneRenderResult)
  If PlaneRenderResultIsValid(*Result) = #False
    PlaneRenderSetError("Plane render result is not initialized.")
    ProcedureReturn ""
  EndIf
  gPlaneRenderMain_LastError = ""
  ProcedureReturn WallFrameHashHex64(*Result\Hash)
EndProcedure

; Deep numeric copy of the M3-05 wall plan stored for a processed span.
Procedure.i PlaneRenderGetPlan(*Result.PlaneRenderResult, PlanIndex.l,
                               *Out.WallSpanPlan)
  If PlaneRenderResultIsValid(*Result) = #False
    PlaneRenderSetError("Plane render result is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Out = 0
    PlaneRenderSetError("PlaneRenderGetPlan: output plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlanIndex < 0 Or PlanIndex >= *Result\SegmentCount Or *Result\Plans = 0
    PlaneRenderSetError("PlaneRenderGetPlan: plan index is outside the processed range.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Result\Plans + Int(PlanIndex) * SizeOf(WallSpanPlan), *Out,
             Int(SizeOf(WallSpanPlan)))
  gPlaneRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; Deep numeric copy of the textured material/pegging/light plan. No pointer.
Procedure.i PlaneRenderGetTexturePlan(*Result.PlaneRenderResult, PlanIndex.l,
                                      *Out.WallTextureSpanPlan)
  If PlaneRenderResultIsValid(*Result) = #False
    PlaneRenderSetError("Plane render result is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Out = 0
    PlaneRenderSetError("PlaneRenderGetTexturePlan: output plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlanIndex < 0 Or PlanIndex >= *Result\TexturePlanCount Or *Result\TexturePlans = 0
    PlaneRenderSetError("PlaneRenderGetTexturePlan: plan index is outside the processed range.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Result\TexturePlans + Int(PlanIndex) * SizeOf(WallTextureSpanPlan), *Out,
             Int(SizeOf(WallTextureSpanPlan)))
  gPlaneRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
