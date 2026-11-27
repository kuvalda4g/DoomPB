; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-06 textured wall-column rasterizer. Mirrors the accepted M3-05
; R_RenderSegLoop tier/clip branches byte-for-byte in ordering while replacing
; the solid debug palette index with a composed source texel mapped through the
; vanilla scalelight/COLORMAP table. The legacy M3-05 WallDraw.pbi is untouched.
;
; Source correspondence: r_segs.c R_RenderSegLoop (texturecolumn/lighting/dc_iscale
; independent of tier, one-sided middle closes column 200/-1, upper mid/pixhigh
; order, lower mid/pixlow order, per-column scale/topfrac/bottomfrac step),
; r_draw.c R_DrawColumn (inclusive dc_yl..dc_yh, frac start/step, source_row
; &127, colormap lookup), r_data.c R_GetColumn (texture width mask), and
; r_segs.c walllights[16][48] row/index selection.
;
; Defectively deferred source branches:
;   - two-sided masked midtextures: no `maskedtexturecol` capture, no opaque
;     middle fill and no back-to-front masked draw. The M3-05 plan never sets a
;     two-sided MiddleTier; the mask is detected/counted in the cache and plan.
;     Portal interior gaps remain background index 0 (floors/ceilings are M4);
;   - planes/markfloor/markceiling row storage, sky, sprites and translate/fuzz
;     column variants are omitted as in M3-05; only clip side effects are kept.
;
; Legitimate row/luminance policy:
;   - 128-high (and taller) textures use the exact `&127` source row; shorter
;     textures use the explicitly documented modulo-height bounded fallback and
;     increment ShortHeightFallbacks per sampled row;
;   - mask=1 copies the composed palette index; mask=0 is reported as an
;     UncoveredTexel and the composed index (M2 uncovered=index 0 / mask 0) is
;     mapped through COLORMAP. This is a documented deterministic substitute for
;     the original undefined short-column adjacency/uninitialized composite gap,
;     never a silent palette-0 replacement outside that policy;
;   - palette index 255 is an ordinary opaque source value; no 255 transparency
;     sentinel exists;
;   - all source columns are width-mask wrapped and checked 0..Width-1; source
;     rows are checked 0..Height-1; screen x/y and palette bytes are checked.
;
; Ownership/output:
;   - caller-owned canonical 320x200 FrameBuffer only; private frames are
;     created by the orchestrator and discarded on failure;
;   - a draw span reads the borrowed cache image pointer only at span start and
;     never retains it; no allocation occurs in the per-column or per-row loop;
;   - WallTextureDrawTally is caller-owned counters, reset idempotently; local
;     counts publish atomically only after a whole span succeeds;
;   - out-of-frame computed columns/ranges are safely skipped and counted, never
;     partially written; malformed image/mask/table data abort the span with a
;     diagnostic (orchestrator discards the private frame and target unchanged).
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_TEXTUREDWALLDRAW_PBI, #PB_Constant) = 0

#DOOMPB_TEXTUREDWALLDRAW_PBI = 1

XIncludeFile "../Graphics/FrameBuffer.pbi"
XIncludeFile "WallDraw.pbi"
XIncludeFile "WallTextureCache.pbi"
XIncludeFile "WallLighting.pbi"

#WALLTEXDRAW_TallyMagic = $57544631
#WALLTEXDRAW_ViewWidth = #PROJ_VIEWWIDTH
#WALLTEXDRAW_ViewHeight = #PROJ_VIEWHEIGHT
#WALLTEXDRAW_PixelCount = #WALLTEXDRAW_ViewWidth * #WALLTEXDRAW_ViewHeight
#WALLTEXDRAW_RangeEmpty = 0
#WALLTEXDRAW_RangeDrawn = 1
#WALLTEXDRAW_RangeOutOfFrame = 2
#WALLTEXDRAW_RangeError = -1

Structure WallTextureDrawTally
  Magic.l
  ProcessedSpans.l
  ProcessedColumns.l
  TextureColumnsComputed.l
  MiddlePixels.l
  UpperPixels.l
  LowerPixels.l
  DrawnPixels.l
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
EndStructure

Global gTexturedWallDraw_LastError.s = ""

Procedure TexturedWallDrawSetError(Message.s)
  gTexturedWallDraw_LastError = Message
EndProcedure

Procedure.s TexturedWallDrawLastError()
  ProcedureReturn gTexturedWallDraw_LastError
EndProcedure

Procedure.i WallTextureDrawTallyReset(*Tally.WallTextureDrawTally)
  If *Tally = 0
    TexturedWallDrawSetError("Wall texture draw tally pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Tally\Magic <> 0 And *Tally\Magic <> #WALLTEXDRAW_TallyMagic
    TexturedWallDrawSetError("Wall texture draw tally has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  FillMemory(*Tally, Int(SizeOf(WallTextureDrawTally)), 0)
  *Tally\Magic = #WALLTEXDRAW_TallyMagic
  gTexturedWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Bounded textured column writer
; ---------------------------------------------------------------------------

; Draws one inclusive tier range from an already-validated composed image at a
; source column produced by the raw texturecolumn width mask. Returns outcome
; codes 0 empty, 1 drawn, 2 safely skipped out-of-frame, -1 diagnostic failure.
; On -1 no pixel was necessarily written yet; caller's private frame is discarded
; by the orchestrator, and *PixelCount etc remain untouched.
Procedure.i WallTextureDrawColumn(*FrameBuffer.FrameBuffer,
                                  *Image.TextureImage,
                                  *Table.WallScalelightTable,
                                  *Colormap.ColormapSet,
                                  RawColumn.l, WidthMask.l, TextureWidth.l,
                                  Column.l, YLow.l, YHigh.l,
                                  TextureMid.l, IScale.l,
                                  LightNum.l, ScaleIndex.l,
                                  *PixelCount.Long, *Samples.Long,
                                  *Uncovered.Long, *ShortFallbacks.Long,
                                   *Coverage.Byte = 0)
  Protected wrapped.l = 0
  Protected frac.l = 0
  Protected row.l
  Protected row128.l
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixelIndex.l = 0
  Protected fallback.l = 0
  Protected mappedIndex.l = 0
  Protected planeOffset.q
  Protected localSamples.l = 0
  Protected localUncovered.l = 0
  Protected localFallbacks.l = 0
  Protected rowWidth.l
  Protected imageWidth.l

  TexturedWallDrawSetError("")
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic Or
     *FrameBuffer\Width <> #WALLTEXDRAW_ViewWidth Or
     *FrameBuffer\Height <> #WALLTEXDRAW_ViewHeight Or
     *FrameBuffer\PixelCount <> #WALLTEXDRAW_PixelCount Or *FrameBuffer\Pixels = 0
    TexturedWallDrawSetError("Textured wall column framebuffer is not the canonical 320x200 plane.")
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf
  If *Image = 0 Or *Image\Magic <> #TEXTURE_ImageMagic Or *Image\Pixels = 0 Or *Image\Mask = 0
    TexturedWallDrawSetError("Textured wall column composed image is not initialized.")
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf
  If TextureWidth <= 0 Or TextureWidth > #WALLTEX_MaxTextureDimension Or
     *Image\Width <> TextureWidth
    TexturedWallDrawSetError("Textured wall column texture width disagrees with the composed image.")
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf
  If WallTextureColumnWrapChecked(RawColumn, WidthMask, TextureWidth, @wrapped) = #False
    TexturedWallDrawSetError("Textured wall column wrap failed: " + WallTextureMappingLastError())
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf
  If WallLightingValidateColormap(*Colormap, 0) = #False
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf
  If WallScalelightTableIsValid(*Table) = #False
    TexturedWallDrawSetError("Textured wall column light table is not initialized.")
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf
  If LightNum < 0 Or LightNum >= #LIGHT_LEVELS Or ScaleIndex < 0 Or ScaleIndex >= #LIGHT_MAXLIGHTSCALE
    TexturedWallDrawSetError("Textured wall column light row/scale index is outside 0..15/0..47.")
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf

  If YLow > YHigh
    If *PixelCount <> 0
      PokeL(*PixelCount, 0)
    EndIf
    gTexturedWallDraw_LastError = ""
    ProcedureReturn #WALLTEXDRAW_RangeEmpty
  EndIf
  If Column < 0 Or Column > #WALLTEXDRAW_ViewWidth - 1 Or
     YLow < 0 Or YHigh < 0 Or YLow > #WALLTEXDRAW_ViewHeight - 1 Or
     YHigh > #WALLTEXDRAW_ViewHeight - 1
    If *PixelCount <> 0
      PokeL(*PixelCount, 0)
    EndIf
    TexturedWallDrawSetError("Textured wall tier escaped the 320x200 plane: x=" + Str(Column) +
                             ", y=" + Str(YLow) + ".." + Str(YHigh) + ".")
    ProcedureReturn #WALLTEXDRAW_RangeOutOfFrame
  EndIf

  If WallTextureFracChecked(TextureMid, YLow, #PROJ_CENTERY, IScale, @frac) = #False
    TexturedWallDrawSetError("Textured wall column initial frac failed: " + WallTextureMappingLastError())
    ProcedureReturn #WALLTEXDRAW_RangeError
  EndIf
  imageWidth.l = *Image\Width
  rowWidth = Int(#WALLTEXDRAW_ViewWidth)

  For row = YLow To YHigh
    row128 = WallTextureSourceRow128(frac)
    If WallTextureSampleChecked(*Image, wrapped, row128, @sourceRow, @opaque,
                                @pixelIndex, @fallback) = #False
      TexturedWallDrawSetError("Textured wall texel sample failed at x=" + Str(Column) +
                               ", y=" + Str(row) + ": " + WallTextureMappingLastError())
      ProcedureReturn #WALLTEXDRAW_RangeError
    EndIf
    If WallLightingWallTexelChecked(*Colormap, *Table, LightNum, ScaleIndex,
                                    pixelIndex, @mappedIndex) = #False
      TexturedWallDrawSetError("Textured wall COLORMAP lookup failed at x=" + Str(Column) +
                               ", y=" + Str(row) + ": " + WallLightingLastError())
      ProcedureReturn #WALLTEXDRAW_RangeError
    EndIf
    planeOffset.q = Int(row) * rowWidth + Int(Column)
    If planeOffset.q < 0 Or planeOffset.q >= #WALLTEXDRAW_PixelCount
      TexturedWallDrawSetError("Textured wall destination offset escaped the canonical plane.")
      ProcedureReturn #WALLTEXDRAW_RangeError
    EndIf
    If mappedIndex < 0 Or mappedIndex > 255
      TexturedWallDrawSetError("Textured wall mapped palette index is outside 0..255.")
      ProcedureReturn #WALLTEXDRAW_RangeError
    EndIf
    PokeA(*FrameBuffer\Pixels + planeOffset, mappedIndex)
    If *Coverage <> 0
      PokeA(*Coverage + planeOffset, 1)
    EndIf
    localSamples + 1
    If opaque = 0
      localUncovered + 1
    EndIf
    If fallback <> 0
      localFallbacks + 1
    EndIf
    frac = WallTextureFracAdvance(frac, IScale)
  Next

  If *PixelCount <> 0
    PokeL(*PixelCount, YHigh - YLow + 1)
  EndIf
  If *Samples <> 0
    PokeL(*Samples, localSamples)
  EndIf
  If *Uncovered <> 0
    PokeL(*Uncovered, localUncovered)
  EndIf
  If *ShortFallbacks <> 0
    PokeL(*ShortFallbacks, localFallbacks)
  EndIf
  gTexturedWallDraw_LastError = ""
  ProcedureReturn #WALLTEXDRAW_RangeDrawn
EndProcedure

; ---------------------------------------------------------------------------
; R_RenderSegLoop textured equivalent for one WallSpanPlan
; ---------------------------------------------------------------------------

; Draws one prepared span into an already-cleared 320x200 frame and mutates the
; shared vertical ceilingclip/floorclip state in M3-05 source order. Texture
; column/lighting/iscale are computed once per processed screen x if any
; texture exists; each painted tier wraps that raw column with its own width
; mask. Masked-only spans compute the coordinate/luminance branches but paint
; nothing. Local counters publish at span success only.
Procedure.i TexturedWallDrawSpan(*FrameBuffer.FrameBuffer,
                                 *Plan.WallSpanPlan,
                                 *TexturePlan.WallTextureSpanPlan,
                                 *Cache.WallTextureCache,
                                 *Projection.Projection,
                                 *Table.WallScalelightTable,
                                 *Colormap.ColormapSet,
                                 *Clip.WallVerticalClip,
                                 *Tally.WallTextureDrawTally,
                                  *Coverage.Byte = 0)
  Protected firstX.l
  Protected lastX.l
  Protected column.l
  Protected ceilClip.l
  Protected floorClip.l
  Protected yl.l
  Protected yh.l
  Protected mid.l
  Protected clippedThis.i
  Protected scaleCurrent.l
  Protected topFracCurrent.l
  Protected bottomFracCurrent.l
  Protected pixHighCurrent.l
  Protected pixLowCurrent.l
  Protected xAngle.q = 0
  Protected fixedColumn.l = 0
  Protected rawColumn.l = 0
  Protected columnComputed.i = #False
  Protected scaleIndex.l = 0
  Protected iScale.l = 0
  Protected wrapped.l = 0
  Protected rangeOutcome.i
  Protected drewAnything.i
  Protected localProcessedColumns.l = 0
  Protected localTextureColumns.l = 0
  Protected localMiddlePixels.l = 0
  Protected localUpperPixels.l = 0
  Protected localLowerPixels.l = 0
  Protected localMiddleRanges.l = 0
  Protected localUpperRanges.l = 0
  Protected localLowerRanges.l = 0
  Protected localDrawRanges.l = 0
  Protected localEmptyColumns.l = 0
  Protected localClippedColumns.l = 0
  Protected localOutOfFrameColumns.l = 0
  Protected localSamples.l = 0
  Protected localUncovered.l = 0
  Protected localFallbacks.l = 0
  Protected pixelCount.l = 0
  Protected samples.l = 0
  Protected uncovered.l = 0
  Protected fallbacks.l = 0
  Protected *midImage.TextureImage = 0
  Protected *topImage.TextureImage = 0
  Protected *bottomImage.TextureImage = 0

  TexturedWallDrawSetError("")
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    TexturedWallDrawSetError("Textured wall span: framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If *FrameBuffer\Width <> #WALLTEXDRAW_ViewWidth Or
     *FrameBuffer\Height <> #WALLTEXDRAW_ViewHeight Or
     *FrameBuffer\PixelCount <> #WALLTEXDRAW_PixelCount Or *FrameBuffer\Pixels = 0
    TexturedWallDrawSetError("Textured wall span: framebuffer is not the canonical 320x200 plane.")
    ProcedureReturn #False
  EndIf
  If *Plan = 0 Or WallSpanPlanIsReady(*Plan) = #False
    TexturedWallDrawSetError("Textured wall span: M3-05 render plan is not ready.")
    ProcedureReturn #False
  EndIf
  If *TexturePlan = 0 Or WallTextureSpanPlanIsReady(*TexturePlan) = #False
    TexturedWallDrawSetError("Textured wall span: textured span plan is not ready.")
    ProcedureReturn #False
  EndIf
  If *TexturePlan\Seg <> *Plan\Seg Or *TexturePlan\Linedef <> *Plan\Linedef Or
     *TexturePlan\Side <> *Plan\Side Or *TexturePlan\FirstX <> *Plan\FirstX Or
     *TexturePlan\LastX <> *Plan\LastX Or *TexturePlan\Kind <> *Plan\Kind
    TexturedWallDrawSetError("Textured wall span plan identity disagrees with the M3-05 plan.")
    ProcedureReturn #False
  EndIf
  If *Cache = 0 Or WallTextureCacheIsValid(*Cache) = #False
    TexturedWallDrawSetError("Textured wall span: texture cache is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    TexturedWallDrawSetError("Textured wall span: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Table = 0 Or WallScalelightTableIsValid(*Table) = #False
    TexturedWallDrawSetError("Textured wall span: scalelight table is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic
    TexturedWallDrawSetError("Textured wall span: COLORMAP is not initialized.")
    ProcedureReturn #False
  EndIf
  If WallLightingValidateColormap(*Colormap, 0) = #False
    ProcedureReturn #False
  EndIf
  If *Clip = 0 Or *Clip\Magic <> #WALLDRAW_ClipMagic Or
     *Clip\Width <> #WALLTEXDRAW_ViewWidth Or *Clip\Ceiling = 0 Or *Clip\Floor = 0
    TexturedWallDrawSetError("Textured wall span: vertical clip arrays are not initialized.")
    ProcedureReturn #False
  EndIf
  If *Tally = 0 Or *Tally\Magic <> #WALLTEXDRAW_TallyMagic
    TexturedWallDrawSetError("Textured wall span: draw tally is not initialized.")
    ProcedureReturn #False
  EndIf

  firstX = *Plan\FirstX
  lastX = *Plan\LastX
  If firstX < 0 Or lastX < 0 Or firstX > #WALLTEXDRAW_ViewWidth - 1 Or
     lastX > #WALLTEXDRAW_ViewWidth - 1 Or firstX > lastX
    TexturedWallDrawSetError("Textured wall span: plan columns are invalid: " + Str(firstX) + ".." + Str(lastX) + ".")
    ProcedureReturn #False
  EndIf

  ; Borrowed image pointers once per span; no retention after draw.
  If *Plan\MiddleTier <> 0
    If *TexturePlan\MidCacheSlot < 0
      TexturedWallDrawSetError("Textured wall span: middle cache slot is absent.")
      ProcedureReturn #False
    EndIf
    *midImage = WallTextureCacheImagePtr(*Cache, *TexturePlan\MidCacheSlot)
    If *midImage = 0 Or *midImage\Magic <> #TEXTURE_ImageMagic Or
       *midImage\Width <> *TexturePlan\MidWidth Or *midImage\Height <> *TexturePlan\MidHeight
      TexturedWallDrawSetError("Textured wall span: middle composed image metadata is invalid/mismatched.")
      ProcedureReturn #False
    EndIf
  EndIf
  If *Plan\TopTier <> 0
    If *TexturePlan\TopCacheSlot < 0
      TexturedWallDrawSetError("Textured wall span: top cache slot is absent.")
      ProcedureReturn #False
    EndIf
    *topImage = WallTextureCacheImagePtr(*Cache, *TexturePlan\TopCacheSlot)
    If *topImage = 0 Or *topImage\Magic <> #TEXTURE_ImageMagic Or
       *topImage\Width <> *TexturePlan\TopWidth Or *topImage\Height <> *TexturePlan\TopHeight
      TexturedWallDrawSetError("Textured wall span: top composed image metadata is invalid/mismatched.")
      ProcedureReturn #False
    EndIf
  EndIf
  If *Plan\BottomTier <> 0
    If *TexturePlan\BottomCacheSlot < 0
      TexturedWallDrawSetError("Textured wall span: bottom cache slot is absent.")
      ProcedureReturn #False
    EndIf
    *bottomImage = WallTextureCacheImagePtr(*Cache, *TexturePlan\BottomCacheSlot)
    If *bottomImage = 0 Or *bottomImage\Magic <> #TEXTURE_ImageMagic Or
       *bottomImage\Width <> *TexturePlan\BottomWidth Or *bottomImage\Height <> *TexturePlan\BottomHeight
      TexturedWallDrawSetError("Textured wall span: bottom composed image metadata is invalid/mismatched.")
      ProcedureReturn #False
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
    drewAnything = #False
    pixelCount = 0

    yl = WallTopEdgeFromFrac(topFracCurrent)
    If yl < ceilClip + 1
      yl = ceilClip + 1
      clippedThis = #True
    EndIf
    yh = WallBottomEdgeFromFrac(bottomFracCurrent)
    If yh >= floorClip
      yh = floorClip - 1
      clippedThis = #True
    EndIf

    columnComputed = #False
    If *TexturePlan\SegmentTextured <> 0
      If ProjectionGetXToViewAngle(*Projection, column, @xAngle) = #False
        TexturedWallDrawSetError("Textured wall span: xtoviewangle lookup failed at x=" + Str(column) + ": " + ProjectionLastError())
        ProcedureReturn #False
      EndIf
      If WallTextureColumnChecked(*TexturePlan\RawOffset, *TexturePlan\CenterAngle,
                                  xAngle, *Plan\Distance, @fixedColumn,
                                  @rawColumn) = #False
        TexturedWallDrawSetError("Textured wall span: texturecolumn failed at x=" + Str(column) + ": " + WallTextureMappingLastError())
        ProcedureReturn #False
      EndIf
      If WallLightingScaleIndexChecked(scaleCurrent, @scaleIndex) = #False
        TexturedWallDrawSetError("Textured wall span: column lighting index failed at x=" + Str(column) + ": " + WallLightingLastError())
        ProcedureReturn #False
      EndIf
      If WallTextureIscaleChecked(scaleCurrent, @iScale) = #False
        TexturedWallDrawSetError("Textured wall span: column iscale failed at x=" + Str(column) + ": " + WallTextureMappingLastError())
        ProcedureReturn #False
      EndIf
      columnComputed = #True
      localTextureColumns + 1
    EndIf

    If *Plan\MiddleTier <> 0
      If columnComputed = #False
        TexturedWallDrawSetError("Textured wall span: one-sided middle tier has no computed texturecolumn.")
        ProcedureReturn #False
      EndIf
      rangeOutcome = WallTextureDrawColumn(*FrameBuffer, *midImage, *Table,
                                           *Colormap, rawColumn,
                                           *TexturePlan\MidWidthMask,
                                           *TexturePlan\MidWidth, column, yl, yh,
                                           *TexturePlan\MidTextureMid, iScale,
                                           *TexturePlan\LightNum, scaleIndex,
                                           @pixelCount, @samples, @uncovered,
                                           @fallbacks, *Coverage)
      If rangeOutcome = #WALLTEXDRAW_RangeError
        ProcedureReturn #False
      ElseIf rangeOutcome = #WALLTEXDRAW_RangeOutOfFrame
        localOutOfFrameColumns + 1
      ElseIf rangeOutcome = #WALLTEXDRAW_RangeDrawn
        drewAnything = #True
        localMiddlePixels + pixelCount
        localMiddleRanges + 1
        localDrawRanges + 1
        localSamples + samples
        localUncovered + uncovered
        localFallbacks + fallbacks
      EndIf
      ; Source closes the column after the one-sided middle colfunc regardless
      ; of an empty clipped range.
      PokeL(*Clip\Ceiling + column * SizeOf(Long), #WALLTEXDRAW_ViewHeight)
      PokeL(*Clip\Floor + column * SizeOf(Long), -1)
    Else
      If *Plan\TopTier <> 0
        mid = WallPixHighToY(pixHighCurrent)
        pixHighCurrent = WallFixedAddLow(pixHighCurrent, *Plan\PixHighStep)
        If mid >= floorClip
          mid = floorClip - 1
          clippedThis = #True
        EndIf
        If mid >= yl
          If columnComputed = #False
            TexturedWallDrawSetError("Textured wall span: upper tier has no computed texturecolumn.")
            ProcedureReturn #False
          EndIf
          rangeOutcome = WallTextureDrawColumn(*FrameBuffer, *topImage, *Table,
                                               *Colormap, rawColumn,
                                               *TexturePlan\TopWidthMask,
                                               *TexturePlan\TopWidth, column, yl, mid,
                                               *TexturePlan\TopTextureMid, iScale,
                                               *TexturePlan\LightNum, scaleIndex,
                                               @pixelCount, @samples, @uncovered,
                                               @fallbacks, *Coverage)
          If rangeOutcome = #WALLTEXDRAW_RangeError
            ProcedureReturn #False
          ElseIf rangeOutcome = #WALLTEXDRAW_RangeOutOfFrame
            localOutOfFrameColumns + 1
          ElseIf rangeOutcome = #WALLTEXDRAW_RangeDrawn
            drewAnything = #True
            localUpperPixels + pixelCount
            localUpperRanges + 1
            localDrawRanges + 1
            localSamples + samples
            localUncovered + uncovered
            localFallbacks + fallbacks
          EndIf
          PokeL(*Clip\Ceiling + column * SizeOf(Long), mid)
        Else
          PokeL(*Clip\Ceiling + column * SizeOf(Long), yl - 1)
        EndIf
      ElseIf *Plan\MarkCeiling <> 0
        PokeL(*Clip\Ceiling + column * SizeOf(Long), yl - 1)
      EndIf

      If *Plan\BottomTier <> 0
        mid = WallPixLowToY(pixLowCurrent)
        pixLowCurrent = WallFixedAddLow(pixLowCurrent, *Plan\PixLowStep)
        If mid <= ceilClip
          mid = ceilClip + 1
          clippedThis = #True
        EndIf
        If mid <= yh
          If columnComputed = #False
            TexturedWallDrawSetError("Textured wall span: lower tier has no computed texturecolumn.")
            ProcedureReturn #False
          EndIf
          rangeOutcome = WallTextureDrawColumn(*FrameBuffer, *bottomImage, *Table,
                                               *Colormap, rawColumn,
                                               *TexturePlan\BottomWidthMask,
                                               *TexturePlan\BottomWidth, column, mid, yh,
                                               *TexturePlan\BottomTextureMid, iScale,
                                               *TexturePlan\LightNum, scaleIndex,
                                               @pixelCount, @samples, @uncovered,
                                               @fallbacks, *Coverage)
          If rangeOutcome = #WALLTEXDRAW_RangeError
            ProcedureReturn #False
          ElseIf rangeOutcome = #WALLTEXDRAW_RangeOutOfFrame
            localOutOfFrameColumns + 1
          ElseIf rangeOutcome = #WALLTEXDRAW_RangeDrawn
            drewAnything = #True
            localLowerPixels + pixelCount
            localLowerRanges + 1
            localDrawRanges + 1
            localSamples + samples
            localUncovered + uncovered
            localFallbacks + fallbacks
          EndIf
          PokeL(*Clip\Floor + column * SizeOf(Long), mid)
        Else
          PokeL(*Clip\Floor + column * SizeOf(Long), yh + 1)
        EndIf
      ElseIf *Plan\MarkFloor <> 0
        PokeL(*Clip\Floor + column * SizeOf(Long), yh + 1)
      EndIf
    EndIf

    If clippedThis
      localClippedColumns + 1
    EndIf
    If drewAnything = #False
      localEmptyColumns + 1
    EndIf

    scaleCurrent = WallFixedAddLow(scaleCurrent, *Plan\ScaleStep)
    topFracCurrent = WallFixedAddLow(topFracCurrent, *Plan\TopStep)
    bottomFracCurrent = WallFixedAddLow(bottomFracCurrent, *Plan\BottomStep)
  Next

  *Tally\ProcessedSpans + 1
  *Tally\ProcessedColumns + localProcessedColumns
  *Tally\TextureColumnsComputed + localTextureColumns
  *Tally\MiddlePixels + localMiddlePixels
  *Tally\UpperPixels + localUpperPixels
  *Tally\LowerPixels + localLowerPixels
  *Tally\DrawnPixels + localMiddlePixels + localUpperPixels + localLowerPixels
  *Tally\MiddleRanges + localMiddleRanges
  *Tally\UpperRanges + localUpperRanges
  *Tally\LowerRanges + localLowerRanges
  *Tally\DrawRanges + localDrawRanges
  *Tally\EmptyColumns + localEmptyColumns
  *Tally\ClippedColumns + localClippedColumns
  *Tally\OutOfFrameColumns + localOutOfFrameColumns
  *Tally\TextureSamples + localSamples
  *Tally\UncoveredTexels + localUncovered
  *Tally\ShortHeightFallbacks + localFallbacks
  gTexturedWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
