; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-05 transactional wall-only frame orchestrator plus the static player-one
; start lookup required by the opt-in preview.
;
; It consumes the M3-04 WallVisibilityBuild result as the only authority for
; near-to-far ordered, occlusion-clipped WallSpan records. Never traverses BSP,
; clips walls or sorts fragments again. For each published span in its existing
; chronology it builds one WallSpanPlan, draws solid-color tiers via WallDraw,
; and keeps shared per-column ceilingclip/floorclip state exactly as
; R_ClearPlanes/R_RenderSegLoop would initialize/use it for this frame.
;
; Frame transaction:
;   - the caller's target FrameBuffer is never touched until the WHOLE frame
;     succeeded; drawing happens into a fresh private 320x200 background-cleared
;     FrameBuffer;
;   - only after all span plans/draws and the 64,000-byte FNV hash succeed is the
;     prior target released and replaced by the new owned pixel plane;
;   - on every failure the private frame, clip arrays and result-owned metadata
;     are released, the target remains byte-for-byte unchanged, and an actionable
;     diagnostic is returned;
;   - `RequireDrawnPixels=1` turns a zero-wall-pixel expected-visible frame into a
;     failure; `RequireDrawnPixels=0` allows a legitimately empty debug scene.
;
; Ownership:
;   - WallRenderResult Reset is idempotent and frees only its recognized
;     WallSpanPlan metadata array, leaving reusable zero counters;
;   - numeric metadata copies only IDs/scales/heights/flags; no MapLevel, WAD,
;     catalog, camera, visibility or framebuffer pointers remain owned;
;   - one metadata allocation sized for the input visibility span count, one
;     2,560-byte vertical clip allocation and one 64,000-byte private frame
;     allocation happen per Build; none happen in the per-column drawing loop.
;     Count is published as observed Allocations; span/metadata budgets are
;     checked with wide signed64 size arithmetic before allocation;
;   - a successful result does not own the target; caller can reset/recreate/
;     render again across repeated A->B geometry cycles without retained stale
;     state.
;
; Player-one static view:
;   - exactly one THING type=1 is required; absent or duplicated type=1 records
;     are explicit failures (no vertex-0 fallback, no guessed sector/heading);
;   - x/y as signed 16-bit map units -> checked fixed; heading follows original
;     p_mobj.c `ANG45 * (mthing->angle/45)` with C integer truncation and unsigned
;     BAM wrap;
;   - R_PointInSubsector equivalent: zero-node special subsector 0, otherwise a
;     bounded node side walk from MapLevelGetBspRoot, existing
;     GeometryPointOnNodeSideChecked and raw NF_SUBSECTOR child encoding; cycles/
;     out-of-range children fail rather than loop or guess;
;   - viewz = subsector sector floorheight <<16 + VIEWHEIGHT(41*FRACUNIT), checked
;     against signed32 fixed_t; no bob, viewheight transitions or ceiling-4 clamp.
;
; The deterministic frame hash uses WallFrameHash64 over the exact row-major
; 64,000 palette indices (offset/prime documented in WallDraw.pbi). Result text
; is canonical 16 uppercase hex digits. No RGBA, window, screenshot or
; copyrighted payload enters this module.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_RENDERMAIN_PBI, #PB_Constant) = 0

#DOOMPB_RENDERMAIN_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Map/MapLevel.pbi"
XIncludeFile "../Graphics/FrameBuffer.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "../Graphics/TextureDefs.pbi"
XIncludeFile "Geometry.pbi"
XIncludeFile "Projection.pbi"
XIncludeFile "WallVisibility.pbi"
XIncludeFile "WallView.pbi"
XIncludeFile "WallProject.pbi"
XIncludeFile "WallDraw.pbi"

#RENDER_Magic = $52454D31
#RENDER_MaxSpans = 200000
#RENDER_MaxMetadataBytes = 67108864
#RENDER_FrameWidth = #PROJ_VIEWWIDTH
#RENDER_FrameHeight = #PROJ_VIEWHEIGHT
#RENDER_NoThing = -1

Structure WallRenderResult
  Magic.l
  Ready.l
  SpanCount.l
  SegmentCount.l
  SegmentCapacity.l
  *Plans.WallSpanPlan
  ProcessedColumns.l
  DrawnPixels.l
  MiddlePixels.l
  UpperPixels.l
  LowerPixels.l
  MiddleRanges.l
  UpperRanges.l
  LowerRanges.l
  DrawRanges.l
  EmptyColumns.l
  ClippedColumns.l
  OutOfFrameColumns.l
  Allocations.l
  Hash.q
  FrameWidth.l
  FrameHeight.l
EndStructure

Global gRenderMain_LastError.s = ""

Procedure WallRenderSetError(Message.s)
  gRenderMain_LastError = Message
EndProcedure

Procedure.s WallRenderLastError()
  ProcedureReturn gRenderMain_LastError
EndProcedure

Procedure.i WallRenderResultIsValid(*Result.WallRenderResult)
  ProcedureReturn Bool(*Result <> 0 And *Result\Magic = #RENDER_Magic)
EndProcedure

; Idempotent empty reusable result. A zero-initialized caller structure is
; accepted; unrecognized Magic or unexplained owned metadata pointers are
; rejected instead of freeing arbitrary memory.
Procedure.i WallRenderResultReset(*Result.WallRenderResult)
  If *Result = 0
    WallRenderSetError("Wall render result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Result\Magic = #RENDER_Magic
    If *Result\Plans <> 0
      FreeMemory(*Result\Plans)
    EndIf
  ElseIf *Result\Magic <> 0
    WallRenderSetError("Wall render result has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Result\Plans <> 0
    WallRenderSetError("Wall render result has an unexplained metadata pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Result, Int(SizeOf(WallRenderResult)), 0)
  *Result\Magic = #RENDER_Magic
  *Result\Ready = 0
  *Result\FrameWidth = 0
  *Result\FrameHeight = 0
  gRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Player-one static view (p_mobj.c P_SpawnPlayer / r_main.c R_PointInSubsector)
; ---------------------------------------------------------------------------

; Bounded R_PointInSubsector equivalent with checked node fixed conversion,
; existing exact point-side primitive, raw NF_SUBSECTOR leaf decoding and a
; nodeCount-bounded walk that diagnoses corrupt cycles/targets. Returns the
; checked subsector index.
Procedure.i WallPlayerSubsectorChecked(*Level.MapLevel, ThingXFixed.l,
                                      ThingYFixed.l, *SubsectorIndex.Long)
  Protected rootIsSubsector.l = 0
  Protected rootIndex.l = 0
  Protected nodeCount.i
  Protected subCount.i
  Protected currentNode.l
  Protected nodeSteps.i = 0
  Protected nodeX.l = 0
  Protected nodeY.l = 0
  Protected nodeDX.l = 0
  Protected nodeDY.l = 0
  Protected child0.l = 0
  Protected child1.l = 0
  Protected rawChild.l
  Protected leafIndex.l
  Protected side.l = 0
  Protected fixedOriginX.l = 0
  Protected fixedOriginY.l = 0
  Protected fixedDX.l = 0
  Protected fixedDY.l = 0

  WallRenderSetError("")
  If *SubsectorIndex = 0
    WallRenderSetError("WallPlayerSubsectorChecked: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallRenderSetError("Player subsector lookup: map level is not ready.")
    ProcedureReturn #False
  EndIf
  nodeCount = MapNodesCount(@*Level\Nodes)
  If nodeCount < 0
    WallRenderSetError("Player subsector lookup: NODES set is not initialized.")
    ProcedureReturn #False
  EndIf
  subCount = MapSubsectorsCount(@*Level\Subsectors)
  If subCount < 0
    WallRenderSetError("Player subsector lookup: SSECTORS set is not initialized.")
    ProcedureReturn #False
  EndIf
  If MapLevelGetBspRoot(*Level, @rootIsSubsector, @rootIndex) = #False
    WallRenderSetError("Player subsector lookup: BSP root read failed: " + MapLevelLastError())
    ProcedureReturn #False
  EndIf

  If rootIsSubsector <> 0
    If rootIndex < 0 Or rootIndex >= subCount
      WallRenderSetError("Player subsector lookup: subsector root index is invalid: " + Str(rootIndex) + ".")
      ProcedureReturn #False
    EndIf
    *SubsectorIndex\l = rootIndex
    gRenderMain_LastError = ""
    ProcedureReturn #True
  EndIf

  If nodeCount = 0
    WallRenderSetError("Player subsector lookup: zero-node map did not expose a subsector root.")
    ProcedureReturn #False
  EndIf
  currentNode = rootIndex
  If currentNode < 0 Or currentNode >= nodeCount
    WallRenderSetError("Player subsector lookup: node root index is invalid: " + Str(currentNode) + ".")
    ProcedureReturn #False
  EndIf

  While nodeSteps <= nodeCount
    If MapNodesGet(@*Level\Nodes, currentNode, @nodeX, @nodeY, @nodeDX, @nodeDY,
                   0, 0, 0, 0, 0, 0, 0, 0, @child0, @child1) = #False
      WallRenderSetError("Player subsector lookup cannot read node " + Str(currentNode) + ": " + MapDecodeLastError())
      ProcedureReturn #False
    EndIf
    If FixedFromIntChecked(nodeX, @fixedOriginX) = #False
      WallRenderSetError("Player subsector lookup node origin X conversion failed: " + FixedLastError())
      ProcedureReturn #False
    EndIf
    If FixedFromIntChecked(nodeY, @fixedOriginY) = #False
      WallRenderSetError("Player subsector lookup node origin Y conversion failed: " + FixedLastError())
      ProcedureReturn #False
    EndIf
    If FixedFromIntChecked(nodeDX, @fixedDX) = #False
      WallRenderSetError("Player subsector lookup node DX conversion failed: " + FixedLastError())
      ProcedureReturn #False
    EndIf
    If FixedFromIntChecked(nodeDY, @fixedDY) = #False
      WallRenderSetError("Player subsector lookup node DY conversion failed: " + FixedLastError())
      ProcedureReturn #False
    EndIf
    If GeometryPointOnNodeSideChecked(ThingXFixed, ThingYFixed,
                                      fixedOriginX, fixedOriginY,
                                      fixedDX, fixedDY, @side) = #False
      WallRenderSetError("Player subsector lookup node-side primitive failed: " + GeometryLastError())
      ProcedureReturn #False
    EndIf
    If side = 0
      rawChild = child0
    Else
      rawChild = child1
    EndIf
    If (rawChild & #MAP_NF_SUBSECTOR) <> 0
      leafIndex = rawChild & $7FFF
      If leafIndex < 0 Or leafIndex >= subCount
        WallRenderSetError("Player subsector lookup child references missing subsector " + Str(leafIndex) + ".")
        ProcedureReturn #False
      EndIf
      *SubsectorIndex\l = leafIndex
      gRenderMain_LastError = ""
      ProcedureReturn #True
    EndIf
    If rawChild < 0 Or rawChild >= nodeCount
      WallRenderSetError("Player subsector lookup child references missing node/false leaf: " + Str(rawChild) + ".")
      ProcedureReturn #False
    EndIf
    currentNode = rawChild
    nodeSteps + 1
  Wend

  WallRenderSetError("Player subsector lookup exceeded the node-count work budget (cycle or corrupt target).")
  ProcedureReturn #False
EndProcedure

; Locates exactly one type=1 THING, converts its signed 16-bit start coordinates
; to fixed, applies the original 45-degree quantization, resolves its floor
; sector through the BSP subsector walk and publishes a WallView using
; floor_fixed + 41*FRACUNIT. No duplicate/missing selection fallback exists.
Procedure.i WallRenderPlayerStartView(*Level.MapLevel, *View.WallView,
                                      *ThingIndex.Long, *SubsectorIndex.Long,
                                      *SectorIndex.Long)
  Protected thingCount.i
  Protected i.i
  Protected thingX.l = 0
  Protected thingY.l = 0
  Protected thingAngle.l = 0
  Protected thingType.l = 0
  Protected thingOptions.l = 0
  Protected matchCount.i = 0
  Protected chosenThing.l = -1
  Protected fixedX.l = 0
  Protected fixedY.l = 0
  Protected quotient.q
  Protected headingRaw.q
  Protected subsector.l = 0
  Protected sector.l = 0
  Protected floorHeight.l = 0
  Protected floorFixed.l = 0
  Protected viewZ.q
  Protected viewZValue.l = 0

  WallRenderSetError("")
  If *ThingIndex = 0 Or *SubsectorIndex = 0 Or *SectorIndex = 0
    WallRenderSetError("WallRenderPlayerStartView: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If *View = 0 Or *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallRenderSetError("Player start view: map level or view is not ready/valid.")
    ProcedureReturn #False
  EndIf

  thingCount = MapThingsCount(@*Level\Things)
  If thingCount < 0
    WallRenderSetError("Player start view: THINGS set is not initialized.")
    ProcedureReturn #False
  EndIf
  For i = 0 To thingCount - 1
    If MapThingsGet(@*Level\Things, i, @thingX, @thingY, @thingAngle,
                    @thingType, @thingOptions) = #False
      WallRenderSetError("Player start view cannot read THING " + Str(i) + ": " + MapDecodeLastError())
      ProcedureReturn #False
    EndIf
    If thingType = 1
      matchCount + 1
      If matchCount > 1
        WallRenderSetError("Player-one THING type=1 is duplicated ambiguously; refusing to choose one.")
        ProcedureReturn #False
      EndIf
      chosenThing = i
    EndIf
  Next
  If matchCount = 0
    WallRenderSetError("Player-one THING (type=1) is absent; no guessed spawn camera is used.")
    ProcedureReturn #False
  EndIf

  If MapThingsGet(@*Level\Things, Int(chosenThing), @thingX, @thingY, @thingAngle,
                  @thingType, @thingOptions) = #False
    WallRenderSetError("Player start view cannot re-read chosen THING " + Str(chosenThing) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(thingX, @fixedX) = #False
    WallRenderSetError("Player start view THING X conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(thingY, @fixedY) = #False
    WallRenderSetError("Player start view THING Y conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  ; p_mobj.c: mobj->angle = ANG45 * (mthing->angle/45), C int quotient and
  ; unsigned angle_t product wrap. The checked quotient truncates toward zero.
  quotient.q = WallQuotientTruncTowardZero(Int(thingAngle), 45)
  headingRaw = BamWrap32(#BAM_ANG45 * quotient)

  If WallPlayerSubsectorChecked(*Level, fixedX, fixedY, @subsector) = #False
    WallRenderSetError("Player start view subsector resolution failed: " + WallRenderLastError())
    ProcedureReturn #False
  EndIf
  sector = MapLevelGetSubsectorSector(*Level, subsector)
  If sector < 0 Or sector >= *Level\Sectors\Count
    WallRenderSetError("Player start view subsector " + Str(subsector) + " sector is invalid: " + Str(sector) + ".")
    ProcedureReturn #False
  EndIf
  If MapSectorsGet(@*Level\Sectors, sector, @floorHeight, 0, 0, 0, 0) = #False
    WallRenderSetError("Player start view cannot read floor sector " + Str(sector) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(floorHeight, @floorFixed) = #False
    WallRenderSetError("Player start view floor height conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  viewZ.q = Int(floorFixed) + Int(#WALLVIEW_ViewHeightFixed)
  If viewZ < #FIXED_MIN Or viewZ > #FIXED_MAX
    WallRenderSetError("Player start view floor+VIEWHEIGHT overflows signed32 fixed_t: " + Str(viewZ) + ".")
    ProcedureReturn #False
  EndIf
  viewZValue = viewZ

  If WallViewSetFixed(*View, fixedX, fixedY, headingRaw, viewZValue) = #False
    WallRenderSetError("Player start view publication failed: " + WallViewLastError())
    ProcedureReturn #False
  EndIf

  *ThingIndex\l = chosenThing
  *SubsectorIndex\l = subsector
  *SectorIndex\l = sector
  gRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Transactional frame build
; ---------------------------------------------------------------------------

; Builds one complete wall-only 320x200 frame. *Target remains untouched on any
; failure. Success replaces it by a newly owned canonical index plane and
; publishes result-owned numeric metadata/counters/hash. The source visibility
; result is read through its accessors in its published order, never sorted or
; deduplicated.
Procedure.i WallRenderFrame(*Level.MapLevel, *View.WallView,
                              *Projection.Projection, *Flats.FlatCatalog,
                              *Textures.TextureCatalog,
                              *Visibility.WallVisibilityResult,
                              *Target.FrameBuffer,
                              *Result.WallRenderResult,
                              RequireDrawnPixels.i = #False)
  Protected spanCount.l
  Protected metadataBytes.q
  Protected metadataMemory.i = 0
  Protected planIndex.i
  Protected spanSub.l = 0
  Protected spanSeg.l = 0
  Protected spanLine.l = 0
  Protected spanSide.l = 0
  Protected spanFront.l = 0
  Protected spanBack.l = 0
  Protected spanFirst.l = 0
  Protected spanLast.l = 0
  Protected spanKind.l = 0
  Protected span.WallSpan
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected cameraHeading.q = 0
  Protected cameraViewZ.l = 0
  Protected projectionFixed.l = 0
  Protected clip.WallVerticalClip
  Protected tally.WallDrawTally
  Protected frame.FrameBuffer
  Protected clipStarted.i = #False
  Protected frameStarted.i = #False
  Protected planCount.i = 0
  Protected spanHash.q = 0
  Protected allocations.l = 0
  Protected failureText.s = ""
  Protected *plan.WallSpanPlan

  WallRenderSetError("")
  If *Result = 0
    WallRenderSetError("WallRenderFrame: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If WallRenderResultReset(*Result) = #False
    ProcedureReturn #False
  EndIf
  If *Target = 0
    WallRenderSetError("WallRenderFrame: target framebuffer pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Target\Magic <> 0 And *Target\Magic <> #FRAMEBUFFER_Magic
    WallRenderSetError("WallRenderFrame: target framebuffer has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallRenderSetError("WallRenderFrame: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *View = 0 Or WallViewIsValid(*View) = #False
    WallRenderSetError("WallRenderFrame: wall view is not ready.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    WallRenderSetError("WallRenderFrame: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Projection\Width <> #RENDER_FrameWidth Or *Projection\ViewHeight <> #RENDER_FrameHeight
    WallRenderSetError("WallRenderFrame: non-canonical 320x200 projection.")
    ProcedureReturn #False
  EndIf
  If *Visibility = 0 Or WallVisibilityIsValid(*Visibility) = #False
    WallRenderSetError("WallRenderFrame: wall visibility result is not initialized.")
    ProcedureReturn #False
  EndIf

  If WallViewGet(*View, @cameraX, @cameraY, @cameraHeading, @cameraViewZ) = #False
    WallRenderSetError("WallRenderFrame: cannot read wall view: " + WallViewLastError())
    ProcedureReturn #False
  EndIf
  If ProjectionGetConstants(*Projection, 0, 0, 0, 0, 0, 0, @projectionFixed, 0, 0) = #False
    WallRenderSetError("WallRenderFrame: cannot read projection constant: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf

  spanCount = WallVisibilityCount(*Visibility)
  If spanCount < 0
    WallRenderSetError("WallRenderFrame: cannot read visibility span count: " + WallVisibilityLastError())
    ProcedureReturn #False
  EndIf
  If spanCount > #RENDER_MaxSpans
    WallRenderSetError("WallRenderFrame: visibility span count " + Str(spanCount) +
                       " exceeds the renderer budget " + Str(#RENDER_MaxSpans) + ".")
    ProcedureReturn #False
  EndIf
  metadataBytes = Int(spanCount) * SizeOf(WallSpanPlan)
  If metadataBytes < 0 Or metadataBytes > #RENDER_MaxMetadataBytes
    WallRenderSetError("WallRenderFrame: wall plan metadata bytes " + Str(metadataBytes) +
                       " exceed the checked budget " + Str(#RENDER_MaxMetadataBytes) + ".")
    ProcedureReturn #False
  EndIf

  ; Owned per-frame clip arrays, rebuilt with exact -1/200 initialization.
  If WallVerticalClipBegin(@clip) = #False
    WallRenderSetError("WallRenderFrame: clip array allocation failed: " + WallDrawLastError())
    ProcedureReturn #False
  EndIf
  clipStarted = #True
  allocations = allocations + 1
  If WallDrawTallyReset(@tally) = #False
    failureText = "WallRenderFrame: tally initialization failed: " + WallDrawLastError()
    Goto RenderMainFailure
  EndIf

  ; One metadata allocation for the whole frame: every source-span slot; no
  ; per-span/per-column heap allocation while drawing.
  If spanCount > 0
    metadataMemory = AllocateMemory(metadataBytes)
    If metadataMemory = 0
      failureText = "WallRenderFrame: out of memory for wall plan metadata."
      Goto RenderMainFailure
    EndIf
    FillMemory(metadataMemory, Int(metadataBytes), 0)
    allocations = allocations + 1
  EndIf
  *Result\SegmentCapacity = spanCount
  *Result\Plans = metadataMemory

  If FrameBufferCreate(@frame, #RENDER_FrameWidth, #RENDER_FrameHeight) = #False
    failureText = "WallRenderFrame: private framebuffer creation failed: " + FrameBufferLastError()
    Goto RenderMainFailure
  EndIf
  frameStarted = #True
  allocations = allocations + 1
  If FrameBufferClear(@frame, #WALLDRAW_BackgroundIndex) = #False
    failureText = "WallRenderFrame: private framebuffer clear failed: " + FrameBufferLastError()
    Goto RenderMainFailure
  EndIf

  For planIndex = 0 To spanCount - 1
    If WallVisibilityGetSpan(*Visibility, planIndex, @spanSub, @spanSeg,
                             @spanLine, @spanSide, @spanFront, @spanBack,
                             @spanFirst, @spanLast, @spanKind) = #False
      failureText = "WallRenderFrame span " + Str(planIndex) + " access failed: " + WallVisibilityLastError()
      Goto RenderMainFailure
    EndIf

    ; Local authoritative copy of the published numeric span fields only. The
    ; M3-04 result is read-only here and its order/identity are unchanged.
    span\Subsector = spanSub
    span\Seg = spanSeg
    span\Linedef = spanLine
    span\Side = spanSide
    span\FrontSector = spanFront
    span\BackSector = spanBack
    span\FirstX = spanFirst
    span\LastX = spanLast
    span\Kind = spanKind

    If spanCount > 0
      *plan = *Result\Plans + planIndex * SizeOf(WallSpanPlan)
    Else
      *plan = 0
    EndIf
    If WallProjectSpanChecked(*Level, *Flats, *Textures, *Projection,
                              cameraX, cameraY, cameraHeading, cameraViewZ,
                              planIndex, @span, *plan) = #False
      failureText = "WallRenderFrame span " + Str(planIndex) +
                    " projection failed: " + WallProjectLastError()
      Goto RenderMainFailure
    EndIf

    If WallDrawSpan(@frame, *plan, @clip, @tally) = #False
      failureText = "WallRenderFrame span " + Str(planIndex) +
                    " drawing failed: " + WallDrawLastError()
      Goto RenderMainFailure
    EndIf
    planCount + 1
  Next

  If planCount <> spanCount Or tally\ProcessedSpans <> spanCount
    failureText = "WallRenderFrame span accounting disagrees with the visibility count."
    Goto RenderMainFailure
  EndIf
  If RequireDrawnPixels <> 0 And tally\DrawnPixels = 0
    failureText = "WallRenderFrame produced zero wall pixels for an expected-visible frame."
    Goto RenderMainFailure
  EndIf
  If WallFrameHash64(@frame, @spanHash) = #False
    failureText = "WallRenderFrame frame hash failed: " + WallDrawLastError()
    Goto RenderMainFailure
  EndIf

  ; Success is the only point where the caller's previous frame is released.
  If FrameBufferReset(*Target) = #False
    failureText = "WallRenderFrame target framebuffer reset failed: " + FrameBufferLastError()
    Goto RenderMainFailure
  EndIf
  *Target\Magic = #FRAMEBUFFER_Magic
  *Target\Width = frame\Width
  *Target\Height = frame\Height
  *Target\PixelCount = frame\PixelCount
  *Target\Pixels = frame\Pixels
  ; Transfer ownership: the private local must no longer own the plane.
  frame\Magic = 0
  frame\Width = 0
  frame\Height = 0
  frame\PixelCount = 0
  frame\Pixels = 0
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)

  *Result\SpanCount = spanCount
  *Result\SegmentCount = planCount
  *Result\ProcessedColumns = tally\ProcessedColumns
  *Result\DrawnPixels = tally\DrawnPixels
  *Result\MiddlePixels = tally\MiddlePixels
  *Result\UpperPixels = tally\UpperPixels
  *Result\LowerPixels = tally\LowerPixels
  *Result\MiddleRanges = tally\MiddleRanges
  *Result\UpperRanges = tally\UpperRanges
  *Result\LowerRanges = tally\LowerRanges
  *Result\DrawRanges = tally\DrawRanges
  *Result\EmptyColumns = tally\EmptyColumns
  *Result\ClippedColumns = tally\ClippedColumns
  *Result\OutOfFrameColumns = tally\OutOfFrameColumns
  *Result\Allocations = allocations
  *Result\Hash = spanHash
  *Result\FrameWidth = #RENDER_FrameWidth
  *Result\FrameHeight = #RENDER_FrameHeight
  *Result\Ready = 1
  gRenderMain_LastError = ""
  ProcedureReturn #True

  RenderMainFailure:
  If frameStarted
    FrameBufferReset(@frame)
  EndIf
  If clipStarted
    WallVerticalClipReset(@clip)
  EndIf
  WallRenderResultReset(*Result)
  If failureText = ""
    failureText = gRenderMain_LastError
  EndIf
  WallRenderSetError(failureText)
  ProcedureReturn #False
EndProcedure

; ---------------------------------------------------------------------------
; Read-only result accessors
; ---------------------------------------------------------------------------

; All output pointers may be null; accesses are bounded and never write partial
; output on failure. Stats are valid on a reset READY=0 result as zero counters.
Procedure.i WallRenderGetStats(*Result.WallRenderResult,
                                *SpanCount.Long, *SegmentCount.Long,
                                *SegmentCapacity.Long, *ProcessedColumns.Long,
                                *DrawnPixels.Long, *MiddlePixels.Long,
                                *UpperPixels.Long, *LowerPixels.Long,
                                *MiddleRanges.Long, *UpperRanges.Long,
                                *LowerRanges.Long, *DrawRanges.Long,
                                *EmptyColumns.Long, *ClippedColumns.Long,
                                *OutOfFrameColumns.Long, *Allocations.Long,
                                *Hash.Quad, *NonzeroPixels.Long)
  If WallRenderResultIsValid(*Result) = #False
    WallRenderSetError("Wall render result is not initialized.")
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
  If *ProcessedColumns <> 0
    PokeL(*ProcessedColumns, *Result\ProcessedColumns)
  EndIf
  If *DrawnPixels <> 0
    PokeL(*DrawnPixels, *Result\DrawnPixels)
  EndIf
  If *MiddlePixels <> 0
    PokeL(*MiddlePixels, *Result\MiddlePixels)
  EndIf
  If *UpperPixels <> 0
    PokeL(*UpperPixels, *Result\UpperPixels)
  EndIf
  If *LowerPixels <> 0
    PokeL(*LowerPixels, *Result\LowerPixels)
  EndIf
  If *MiddleRanges <> 0
    PokeL(*MiddleRanges, *Result\MiddleRanges)
  EndIf
  If *UpperRanges <> 0
    PokeL(*UpperRanges, *Result\UpperRanges)
  EndIf
  If *LowerRanges <> 0
    PokeL(*LowerRanges, *Result\LowerRanges)
  EndIf
  If *DrawRanges <> 0
    PokeL(*DrawRanges, *Result\DrawRanges)
  EndIf
  If *EmptyColumns <> 0
    PokeL(*EmptyColumns, *Result\EmptyColumns)
  EndIf
  If *ClippedColumns <> 0
    PokeL(*ClippedColumns, *Result\ClippedColumns)
  EndIf
  If *OutOfFrameColumns <> 0
    PokeL(*OutOfFrameColumns, *Result\OutOfFrameColumns)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Result\Allocations)
  EndIf
  If *Hash <> 0
    PokeQ(*Hash, *Result\Hash)
  EndIf
  If *NonzeroPixels <> 0
    PokeL(*NonzeroPixels, Bool(*Result\DrawnPixels <> 0))
  EndIf
  gRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.s WallRenderGetHashText(*Result.WallRenderResult)
  If WallRenderResultIsValid(*Result) = #False
    WallRenderSetError("Wall render result is not initialized.")
    ProcedureReturn ""
  EndIf
  gRenderMain_LastError = ""
  ProcedureReturn WallFrameHashHex64(*Result\Hash)
EndProcedure

; Deep numeric copy of the prepared plan stored for a processed span. No
; returned plan retains any level/WAD/catalog/framebuffer pointer.
Procedure.i WallRenderGetPlan(*Result.WallRenderResult, PlanIndex.l,
                              *Out.WallSpanPlan)
  If WallRenderResultIsValid(*Result) = #False
    WallRenderSetError("Wall render result is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Out = 0
    WallRenderSetError("WallRenderGetPlan: output plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlanIndex < 0 Or PlanIndex >= *Result\SegmentCount Or *Result\Plans = 0
    WallRenderSetError("WallRenderGetPlan: plan index " + Str(PlanIndex) +
                       " is outside 0.." + Str(*Result\SegmentCount - 1) + ".")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Result\Plans + Int(PlanIndex) * SizeOf(WallSpanPlan), *Out,
             Int(SizeOf(WallSpanPlan)))
  gRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
