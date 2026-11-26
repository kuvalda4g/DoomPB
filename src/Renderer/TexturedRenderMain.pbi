; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-06 transactional textured wall-only frame orchestrator. The M3-04 ordered,
; occlusion-clipped WallSpan records remain the sole authority; every span is
; planned once through the accepted M3-05 WallProjectSpanChecked geometry, then
; material/pegging/light-row fields are derived by the M3-06 helpers. No BSP
; re-walk, visibility re-clip, sort, dedupe or a second renderer geometry formula.
;
; Pipeline per frame:
;   1. reset target-owned result (metadata arrays only);
;   2. one legacy WallSpanPlan metadata array for every published span, built by
;      WallProjectSpanChecked (view camera/viewz/projection/flats/textures);
;   3. used-texture cache built from those plans' already-decided tier flags,
;      composing unique catalog textures while the resolved WAD is open;
;   4. vanilla 320-column scalelight table built from COLORMAP (>=32 gate);
;   5. one WallTextureSpanPlan array with exact texture slots, heights, masks,
;      pegging texturemids, rw_offset/rw_centerangle and light row;
;   6. one 2,560-byte vertical clip allocation, one 64,000-byte private
;      background-cleared frame, then chronological TexturedWallDrawSpan calls;
;   7. canonical FNV-1a64 over exactly the row-major 64,000 palette bytes, a
;      zero/nonzero byte audit, then commit target ownership only on success.
;
; Transaction/ownership:
;   - the caller target is byte-for-byte untouched until whole-frame success;
;     failure frees private frame/clip/light/cache/result-owned metadata and
;     leaves the previous target unchanged; target committed by FrameBufferReset
;     + plane transfer like the existing M3-05 route;
;   - result owns only numeric deep-copied plan metadata arrays and counters/hash;
;     it retains no MapLevel, WAD, catalog, camera, cache, light-table, colormap,
;     frame or texture-image pointer after success/reset;
;   - cache/light table/clip/frame remain local and are released after success
;     publication; all allocations happen before the per-column drawing loops;
;     no per-column/per-pixel heap allocation, texture compose or WAD read occurs;
;   - repeated Reset/Build/render and A->B reopens are deterministic; callers must
;     invalidate/re-resolve catalogs and rebuild cache across WAD sessions. The
;     orchestrator checks TextureCompose's own open-WAD contract.
;
; Masked two-sided middles are detected/deferred: no two-sided MiddleTier exists
; in the M3-05 plan; cache `MaskedMidSpans` is copied into statistics and no
; opaque fill/back-to-front masked draw is performed. Portal/floors/ceilings/sky
; gaps remain index-0 background (M4 scope).
;
; Uncovered composed texels (mesh holes) map composed index 0 (M2 policy) through
; COLORMAP and are counted as UncoveredTexels; short (<128) textures use the
; bounded modulo-height fallback and count ShortHeightFallbacks. These documented
; deterministic alternatives never read outside composed planes.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_TEXTUREDRENDERMAIN_PBI, #PB_Constant) = 0

#DOOMPB_TEXTUREDRENDERMAIN_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
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

#TEXTRENDER_Magic = $54525431
#TEXTRENDER_MaxSpans = 200000
#TEXTRENDER_MaxMetadataBytes = 67108864
#TEXTRENDER_FrameWidth = #PROJ_VIEWWIDTH
#TEXTRENDER_FrameHeight = #PROJ_VIEWHEIGHT
#TEXTRENDER_FramePixelCount = #TEXTRENDER_FrameWidth * #TEXTRENDER_FrameHeight
#TEXTRENDER_BackgroundIndex = 0
#TEXTRENDER_FNV_Offset = -3750763034362895579
#TEXTRENDER_FNV_Prime = 1099511628211

Structure TexturedWallRenderResult
  Magic.l
  Ready.l
  SpanCount.l
  SegmentCount.l
  SegmentCapacity.l
  TexturePlanCount.l
  TexturePlanCapacity.l
  *Plans.WallSpanPlan
  *TexturePlans.WallTextureSpanPlan
  ProcessedColumns.l
  TextureColumnsComputed.l
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
  TextureSamples.l
  UncoveredTexels.l
  ShortHeightFallbacks.l
  NonZeroBytes.l
  ZeroBytes.l
  ComposedTextures.l
  RequestedReferences.l
  ReusedReferences.l
  MaskedMidSpans.l
  ShortTextures.l
  CacheAllocations.l
  Allocations.l
  CacheTempBytes.q
  CachePlaneBytes.q
  CachePeakBytes.q
  Hash.q
  FrameWidth.l
  FrameHeight.l
EndStructure

Global gTexturedRenderMain_LastError.s = ""

Procedure TexturedWallRenderSetError(Message.s)
  gTexturedRenderMain_LastError = Message
EndProcedure

Procedure.s TexturedWallRenderLastError()
  ProcedureReturn gTexturedRenderMain_LastError
EndProcedure

Declare.i WallTexturedRenderFailureFinalize(*Result.TexturedWallRenderResult,
                                           FailureText.s)

Procedure.i TexturedWallRenderResultIsValid(*Result.TexturedWallRenderResult)
  ProcedureReturn Bool(*Result <> 0 And *Result\Magic = #TEXTRENDER_Magic)
EndProcedure

; Idempotent empty reusable result; frees only recognized numeric plan arrays
; (never pointers inside the numeric plan records). Unexplained pointers or a
; foreign Magic are rejected, not freed.
Procedure.i TexturedWallRenderResultReset(*Result.TexturedWallRenderResult)
  If *Result = 0
    TexturedWallRenderSetError("Textured wall render result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Result\Magic = #TEXTRENDER_Magic
    If *Result\Plans <> 0
      FreeMemory(*Result\Plans)
    EndIf
    If *Result\TexturePlans <> 0
      FreeMemory(*Result\TexturePlans)
    EndIf
  ElseIf *Result\Magic <> 0
    TexturedWallRenderSetError("Textured wall render result has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Result\Plans <> 0 Or *Result\TexturePlans <> 0
    TexturedWallRenderSetError("Textured wall render result has an unexplained metadata pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Result, Int(SizeOf(TexturedWallRenderResult)), 0)
  *Result\Magic = #TEXTRENDER_Magic
  *Result\Ready = 0
  gTexturedRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent canonical frame byte audit (verification/statistics only)
; ---------------------------------------------------------------------------

; Counts nonzero palette bytes in the exact 64,000 row-major plane; ZeroBytes is
; PixelCount - NonZeroBytes. Zero bytes are genuine palette index 0 (background
; or a COLORMAP-mapped source texel) and are reported, not conflated with
; painted-write counters.
Procedure.i TexturedWallFrameByteAudit(*FrameBuffer.FrameBuffer,
                                       *NonZeroBytes.Long, *ZeroBytes.Long)
  Protected byteIndex.i
  Protected value.i
  Protected nonzero.l = 0

  TexturedWallRenderSetError("")
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic Or
     *FrameBuffer\Width <> #TEXTRENDER_FrameWidth Or
     *FrameBuffer\Height <> #TEXTRENDER_FrameHeight Or
     *FrameBuffer\PixelCount <> #TEXTRENDER_FramePixelCount Or *FrameBuffer\Pixels = 0
    TexturedWallRenderSetError("Textured wall byte audit: framebuffer is not the exact 320x200 plane.")
    ProcedureReturn #False
  EndIf

  For byteIndex = 0 To #TEXTRENDER_FramePixelCount - 1
    value = PeekA(*FrameBuffer\Pixels + byteIndex)
    If value <> 0
      nonzero + 1
    EndIf
  Next
  If *NonZeroBytes <> 0
    PokeL(*NonZeroBytes, nonzero)
  EndIf
  If *ZeroBytes <> 0
    PokeL(*ZeroBytes, Int(#TEXTRENDER_FramePixelCount) - nonzero)
  EndIf
  gTexturedRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Transactional textured frame build
; ---------------------------------------------------------------------------

; Builds one complete textured wall-only 320x200 frame. *Target remains
; byte-for-byte unchanged on every failure; success replaces it by a newly owned
; canonical index plane and publishes result-owned numeric metadata/counters/
; hash. The M3-04 result is read only in its published chronology.
Procedure.i TexturedWallRenderFrame(*Level.MapLevel, *View.WallView,
                                    *Projection.Projection,
                                    *Flats.FlatCatalog,
                                    *Textures.TextureCatalog,
                                    *Colormap.ColormapSet,
                                    *Visibility.WallVisibilityResult,
                                    *Target.FrameBuffer,
                                    *Result.TexturedWallRenderResult,
                                    RequireDrawnPixels.i = #False)
  Protected spanCount.l
  Protected legacyBytes.q
  Protected textureBytes.q
  Protected legacyMemory.i = 0
  Protected textureMemory.i = 0
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
  Protected table.WallScalelightTable
  Protected cache.WallTextureCache
  Protected tally.WallTextureDrawTally
  Protected frame.FrameBuffer
  Protected *plan.WallSpanPlan
  Protected *texturePlan.WallTextureSpanPlan
  Protected clipStarted.i = #False
  Protected frameStarted.i = #False
  Protected tableStarted.i = #False
  Protected cacheAttempted.i = #False
  Protected planCount.i = 0
  Protected spanHash.q = 0
  Protected explicitAllocations.l = 0
  Protected tableAllocCount.l = 0
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
  Protected nonzeroBytes.l = 0
  Protected zeroBytes.l = 0
  Protected allocationTotal.l = 0
  Protected allocationCacheAdd.l = 0
  Protected failureText.s = ""
  Protected savedFailureText.s = ""

  TexturedWallRenderSetError("")
  If *Result = 0
    TexturedWallRenderSetError("TexturedWallRenderFrame: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If TexturedWallRenderResultReset(*Result) = #False
    ProcedureReturn #False
  EndIf
  If *Target = 0
    TexturedWallRenderSetError("TexturedWallRenderFrame: target framebuffer pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Target\Magic <> 0 And *Target\Magic <> #FRAMEBUFFER_Magic
    TexturedWallRenderSetError("TexturedWallRenderFrame: target framebuffer has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If *Target\Magic = 0 And *Target\Pixels <> 0
    TexturedWallRenderSetError("TexturedWallRenderFrame: target framebuffer has an unexplained pixel pointer without a Magic value.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *View = 0 Or WallViewIsValid(*View) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: wall view is not ready.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Projection\Width <> #TEXTRENDER_FrameWidth Or *Projection\ViewHeight <> #TEXTRENDER_FrameHeight
    TexturedWallRenderSetError("TexturedWallRenderFrame: non-canonical 320x200 projection.")
    ProcedureReturn #False
  EndIf
  If *Textures = 0 Or *Textures\Magic <> #TEXTURE_CatalogMagic
    TexturedWallRenderSetError("TexturedWallRenderFrame: texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic
    TexturedWallRenderSetError("TexturedWallRenderFrame: COLORMAP is not initialized.")
    ProcedureReturn #False
  EndIf
  If WallLightingValidateColormap(*Colormap, 0) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: COLORMAP lacks classic wall lighting tables: " + WallLightingLastError())
    ProcedureReturn #False
  EndIf
  If *Visibility = 0 Or WallVisibilityIsValid(*Visibility) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: wall visibility result is not initialized.")
    ProcedureReturn #False
  EndIf

  If WallViewGet(*View, @cameraX, @cameraY, @cameraHeading, @cameraViewZ) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: cannot read wall view: " + WallViewLastError())
    ProcedureReturn #False
  EndIf
  If ProjectionGetConstants(*Projection, 0, 0, 0, 0, 0, 0, @projectionFixed, 0, 0) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: cannot read projection constant: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf

  spanCount = WallVisibilityCount(*Visibility)
  If spanCount < 0
    TexturedWallRenderSetError("TexturedWallRenderFrame: cannot read visibility span count: " + WallVisibilityLastError())
    ProcedureReturn #False
  EndIf
  If spanCount > #TEXTRENDER_MaxSpans
    TexturedWallRenderSetError("TexturedWallRenderFrame: visibility span count " + Str(spanCount) +
                               " exceeds the renderer budget " + Str(#TEXTRENDER_MaxSpans) + ".")
    ProcedureReturn #False
  EndIf

  ; One owned legacy plan array for the whole frame, one textured-plan array.
  If spanCount > 0
    legacyBytes = Int(spanCount) * Int(SizeOf(WallSpanPlan))
    textureBytes = Int(spanCount) * Int(SizeOf(WallTextureSpanPlan))
    If legacyBytes < 0 Or legacyBytes > #TEXTRENDER_MaxMetadataBytes Or
       textureBytes < 0 Or textureBytes > #TEXTRENDER_MaxMetadataBytes
      TexturedWallRenderSetError("Textured wall plan metadata byte budgets are exceeded.")
      ProcedureReturn #False
    EndIf
    legacyMemory = AllocateMemory(legacyBytes)
    If legacyMemory = 0
      failureText = "TexturedWallRenderFrame: out of memory for M3-05 wall plan metadata."
      Goto TexturedRenderFailure
    EndIf
    FillMemory(legacyMemory, Int(legacyBytes), 0)
    explicitAllocations + 1
    *Result\SegmentCapacity = spanCount
    *Result\Plans = legacyMemory

    textureMemory = AllocateMemory(textureBytes)
    If textureMemory = 0
      failureText = "TexturedWallRenderFrame: out of memory for textured plan metadata."
      Goto TexturedRenderFailure
    EndIf
    FillMemory(textureMemory, Int(textureBytes), 0)
    explicitAllocations + 1
    *Result\TexturePlanCapacity = spanCount
    *Result\TexturePlans = textureMemory
  EndIf

  ; Build every legacy plan in published visibility chronology.
  For planIndex = 0 To spanCount - 1
    If WallVisibilityGetSpan(*Visibility, planIndex, @spanSub, @spanSeg,
                             @spanLine, @spanSide, @spanFront, @spanBack,
                             @spanFirst, @spanLast, @spanKind) = #False
      failureText = "TexturedWallRenderFrame span " + Str(planIndex) + " access failed: " + WallVisibilityLastError()
      Goto TexturedRenderFailure
    EndIf
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
      failureText = "TexturedWallRenderFrame span " + Str(planIndex) +
                    " projection failed: " + WallProjectLastError()
      Goto TexturedRenderFailure
    EndIf
    planCount + 1
  Next
  If planCount <> spanCount
    failureText = "Textured wall legacy plan accounting disagrees with the visibility count."
    Goto TexturedRenderFailure
  EndIf

  ; Used-texture cache from the already-decided M3-05 tier flags, while WAD open.
  cacheAttempted = #True
  If WallTextureCacheBuild(*Level, *Textures, *Result\Plans, spanCount, @cache) = #False
    failureText = "TexturedWallRenderFrame texture cache build failed: " + WallTextureCacheLastError()
    Goto TexturedRenderFailure
  EndIf
  If WallTextureCacheGetStats(@cache, @cacheCount, @cacheCapacity,
                              @cacheRequestedReferences, @cacheReusedReferences,
                              @cacheMaskedMidSpans, @cacheShortTextures,
                              @cacheAllocations, @cacheTempBytes, @cachePlaneBytes,
                              @cachePeakBytes) = #False
    failureText = "TexturedWallRenderFrame cache statistics read failed: " + WallTextureCacheLastError()
    Goto TexturedRenderFailure
  EndIf

  ; Vanilla 320-column scalelight table from the >=32-table COLORMAP.
  tableStarted = #True
  If WallScalelightTableBuild(@table, *Colormap) = #False
    failureText = "TexturedWallRenderFrame scalelight table build failed: " + WallLightingLastError()
    Goto TexturedRenderFailure
  EndIf
  tableAllocCount = table\Allocations
  explicitAllocations + tableAllocCount

  ; One textured material/pegging/light row prompt per legacy plan.
  For planIndex = 0 To spanCount - 1
    *plan = *Result\Plans + planIndex * SizeOf(WallSpanPlan)
    *texturePlan = *Result\TexturePlans + planIndex * SizeOf(WallTextureSpanPlan)
    If WallTextureSpanPrepareChecked(*Level, *Textures, @cache, *plan,
                                     cameraViewZ, *texturePlan) = #False
      failureText = "TexturedWallRenderFrame span " + Str(planIndex) +
                    " texture plan preparation failed: " + WallTextureCacheLastError()
      Goto TexturedRenderFailure
    EndIf
  Next

  ; Owned per-frame vertical clip arrays, exactly -1/200 initialization.
  If WallVerticalClipBegin(@clip) = #False
    TexturedWallRenderSetError("TexturedWallRenderFrame: clip array allocation failed: " + WallDrawLastError())
    Goto TexturedRenderFailure
  EndIf
  clipStarted = #True
  explicitAllocations + 1
  If WallTextureDrawTallyReset(@tally) = #False
    failureText = "TexturedWallRenderFrame: textured tally initialization failed: " + TexturedWallDrawLastError()
    Goto TexturedRenderFailure
  EndIf

  ; Private canonical frame cleared before any pixel write.
  If FrameBufferCreate(@frame, #TEXTRENDER_FrameWidth, #TEXTRENDER_FrameHeight) = #False
    failureText = "TexturedWallRenderFrame: private framebuffer creation failed: " + FrameBufferLastError()
    Goto TexturedRenderFailure
  EndIf
  frameStarted = #True
  explicitAllocations + 1
  If FrameBufferClear(@frame, #TEXTRENDER_BackgroundIndex) = #False
    failureText = "TexturedWallRenderFrame: private framebuffer clear failed: " + FrameBufferLastError()
    Goto TexturedRenderFailure
  EndIf

  ; Chronological draw: no sort/dedupe/BSP/clip refresh.
  For planIndex = 0 To spanCount - 1
    *plan = *Result\Plans + planIndex * SizeOf(WallSpanPlan)
    *texturePlan = *Result\TexturePlans + planIndex * SizeOf(WallTextureSpanPlan)
    If TexturedWallDrawSpan(@frame, *plan, *texturePlan, @cache, *Projection,
                            @table, *Colormap, @clip, @tally) = #False
      failureText = "TexturedWallRenderFrame span " + Str(planIndex) +
                    " textured drawing failed: " + TexturedWallDrawLastError()
      Goto TexturedRenderFailure
    EndIf
  Next

  If tally\ProcessedSpans <> spanCount Or tally\ProcessedColumns < 0
    failureText = "Textured wall span accounting disagrees with the visibility count."
    Goto TexturedRenderFailure
  EndIf
  If RequireDrawnPixels <> 0 And tally\DrawnPixels = 0
    failureText = "TexturedWallRenderFrame produced zero textured wall pixels for an expected-visible frame."
    Goto TexturedRenderFailure
  EndIf

  ; Authoritative hash exactly over the private frame's 64,000 palette bytes.
  If WallFrameHash64(@frame, @spanHash) = #False
    failureText = "TexturedWallRenderFrame frame hash failed: " + WallDrawLastError()
    Goto TexturedRenderFailure
  EndIf
  If TexturedWallFrameByteAudit(@frame, @nonzeroBytes, @zeroBytes) = #False
    failureText = "TexturedWallRenderFrame byte audit failed: " + TexturedWallRenderLastError()
    Goto TexturedRenderFailure
  EndIf

  ; Success: sole point of target release/replacement.
  If FrameBufferReset(*Target) = #False
    failureText = "TexturedWallRenderFrame target framebuffer reset failed: " + FrameBufferLastError()
    Goto TexturedRenderFailure
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

  ; Local composition/share resources released after successful publication.
  WallVerticalClipReset(@clip)
  WallScalelightTableReset(@table)
  WallTextureCacheReset(@cache)

  allocationTotal = explicitAllocations + cacheAllocations
  *Result\SpanCount = spanCount
  *Result\SegmentCount = planCount
  *Result\TexturePlanCount = spanCount
  *Result\ProcessedColumns = tally\ProcessedColumns
  *Result\TextureColumnsComputed = tally\TextureColumnsComputed
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
  *Result\TextureSamples = tally\TextureSamples
  *Result\UncoveredTexels = tally\UncoveredTexels
  *Result\ShortHeightFallbacks = tally\ShortHeightFallbacks
  *Result\NonZeroBytes = nonzeroBytes
  *Result\ZeroBytes = zeroBytes
  *Result\ComposedTextures = cacheCount
  *Result\RequestedReferences = cacheRequestedReferences
  *Result\ReusedReferences = cacheReusedReferences
  *Result\MaskedMidSpans = cacheMaskedMidSpans
  *Result\ShortTextures = cacheShortTextures
  *Result\CacheAllocations = cacheAllocations
  *Result\Allocations = allocationTotal
  *Result\CacheTempBytes = cacheTempBytes
  *Result\CachePlaneBytes = cachePlaneBytes
  *Result\CachePeakBytes = cachePeakBytes
  *Result\Hash = spanHash
  *Result\FrameWidth = #TEXTRENDER_FrameWidth
  *Result\FrameHeight = #TEXTRENDER_FrameHeight
  *Result\Ready = 1
  gTexturedRenderMain_LastError = ""
  ProcedureReturn #True

  TexturedRenderFailure:
  If frameStarted
    FrameBufferReset(@frame)
  EndIf
  If clipStarted
    WallVerticalClipReset(@clip)
  EndIf
  If tableStarted
    WallScalelightTableReset(@table)
  EndIf
  If cacheAttempted
    WallTextureCacheReset(@cache)
  EndIf
  WallTexturedRenderFailureFinalize(*Result, failureText)
  ProcedureReturn #False

EndProcedure

; Transaction failure finalizer: release result-owned plan arrays and preserve
; the deepest failure text. Target was never touched.
Procedure.i WallTexturedRenderFailureFinalize(*Result.TexturedWallRenderResult,
                                              FailureText.s)
  Protected saved.s = FailureText
  If saved = ""
    saved = gTexturedRenderMain_LastError
    If saved = ""
      saved = "Textured wall frame failed without a specific diagnostic."
    EndIf
  EndIf
  TexturedWallRenderResultReset(*Result)
  TexturedWallRenderSetError(saved)
  ProcedureReturn #False
EndProcedure

; ---------------------------------------------------------------------------
; Read-only accessors
; ---------------------------------------------------------------------------

; All output pointers may be null; accesses bounded and never partial writes.
Procedure.i TexturedWallRenderGetStats(*Result.TexturedWallRenderResult,
                                       *SpanCount.Long, *SegmentCount.Long,
                                       *SegmentCapacity.Long,
                                       *TexturePlanCount.Long,
                                       *TexturePlanCapacity.Long,
                                       *ProcessedColumns.Long,
                                       *TextureColumnsComputed.Long,
                                       *DrawnPixels.Long, *MiddlePixels.Long,
                                       *UpperPixels.Long, *LowerPixels.Long,
                                       *MiddleRanges.Long, *UpperRanges.Long,
                                       *LowerRanges.Long, *DrawRanges.Long,
                                       *EmptyColumns.Long, *ClippedColumns.Long,
                                       *OutOfFrameColumns.Long,
                                       *TextureSamples.Long,
                                       *UncoveredTexels.Long,
                                       *ShortHeightFallbacks.Long,
                                       *NonZeroBytes.Long, *ZeroBytes.Long,
                                       *ComposedTextures.Long,
                                       *RequestedReferences.Long,
                                       *ReusedReferences.Long,
                                       *MaskedMidSpans.Long,
                                       *ShortTextures.Long,
                                       *CacheAllocations.Long,
                                       *Allocations.Long,
                                       *CacheTempBytes.Quad,
                                       *CachePlaneBytes.Quad,
                                       *CachePeakBytes.Quad,
                                       *Hash.Quad)
  If TexturedWallRenderResultIsValid(*Result) = #False
    TexturedWallRenderSetError("Textured wall render result is not initialized.")
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
  If *ProcessedColumns <> 0
    PokeL(*ProcessedColumns, *Result\ProcessedColumns)
  EndIf
  If *TextureColumnsComputed <> 0
    PokeL(*TextureColumnsComputed, *Result\TextureColumnsComputed)
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
  If *TextureSamples <> 0
    PokeL(*TextureSamples, *Result\TextureSamples)
  EndIf
  If *UncoveredTexels <> 0
    PokeL(*UncoveredTexels, *Result\UncoveredTexels)
  EndIf
  If *ShortHeightFallbacks <> 0
    PokeL(*ShortHeightFallbacks, *Result\ShortHeightFallbacks)
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
  If *CacheAllocations <> 0
    PokeL(*CacheAllocations, *Result\CacheAllocations)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Result\Allocations)
  EndIf
  If *CacheTempBytes <> 0
    PokeQ(*CacheTempBytes, *Result\CacheTempBytes)
  EndIf
  If *CachePlaneBytes <> 0
    PokeQ(*CachePlaneBytes, *Result\CachePlaneBytes)
  EndIf
  If *CachePeakBytes <> 0
    PokeQ(*CachePeakBytes, *Result\CachePeakBytes)
  EndIf
  If *Hash <> 0
    PokeQ(*Hash, *Result\Hash)
  EndIf
  gTexturedRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.s TexturedWallRenderGetHashText(*Result.TexturedWallRenderResult)
  If TexturedWallRenderResultIsValid(*Result) = #False
    TexturedWallRenderSetError("Textured wall render result is not initialized.")
    ProcedureReturn ""
  EndIf
  gTexturedRenderMain_LastError = ""
  ProcedureReturn WallFrameHashHex64(*Result\Hash)
EndProcedure

; Deep numeric copy of the legacy M3-05 plan stored for a processed span.
Procedure.i TexturedWallRenderGetPlan(*Result.TexturedWallRenderResult,
                                      PlanIndex.l, *Out.WallSpanPlan)
  If TexturedWallRenderResultIsValid(*Result) = #False
    TexturedWallRenderSetError("Textured wall render result is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Out = 0
    TexturedWallRenderSetError("TexturedWallRenderGetPlan: output plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlanIndex < 0 Or PlanIndex >= *Result\SegmentCount Or *Result\Plans = 0
    TexturedWallRenderSetError("TexturedWallRenderGetPlan: plan index is outside the processed range.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Result\Plans + Int(PlanIndex) * SizeOf(WallSpanPlan), *Out,
             Int(SizeOf(WallSpanPlan)))
  gTexturedRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

; Deep numeric copy of the textured material/pegging/light plan. No pointer.
Procedure.i TexturedWallRenderGetTexturePlan(*Result.TexturedWallRenderResult,
                                             PlanIndex.l,
                                             *Out.WallTextureSpanPlan)
  If TexturedWallRenderResultIsValid(*Result) = #False
    TexturedWallRenderSetError("Textured wall render result is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Out = 0
    TexturedWallRenderSetError("TexturedWallRenderGetTexturePlan: output plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlanIndex < 0 Or PlanIndex >= *Result\TexturePlanCount Or *Result\TexturePlans = 0
    TexturedWallRenderSetError("TexturedWallRenderGetTexturePlan: texture plan index is outside the processed range.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Result\TexturePlans + Int(PlanIndex) * SizeOf(WallTextureSpanPlan), *Out,
             Int(SizeOf(WallTextureSpanPlan)))
  gTexturedRenderMain_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
