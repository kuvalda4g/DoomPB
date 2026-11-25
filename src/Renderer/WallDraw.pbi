; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-05 bounded solid-color wall-column rasterizer into the M1 indexed
; framebuffer, reusing the M3-04 ordered WallSpan data via a checked
; WallSpanPlan. This is debug geometry, not the original textured colfunc:
; no WAD patch/texture pixels, COLORMAP, lighting, planes, sky, sprites or
; masked midtexture drawing are performed here.
;
; R_RenderSegLoop semantics ported for M3-05:
;   - per frame ceilingclip[x]=-1 and floorclip[x]=viewheight=200 initialization;
;   - yl=(topfrac+HEIGHTUNIT-1)>>12, yh=bottomfrac>>12, exact arithmetic shifts;
;   - yl clamped to ceilingclip[x]+1 and yh to floorclip[x]-1;
;   - one-sided middle tier: draw inclusive yl..yh then close the column to
;     ceilingclip=200/floorclip=-1; absent middle follows source's no-midtexture
;     branch with plane-mark-only clip updates (planes themselves not drawn);
;   - two-sided upper tier: mid=pixhigh>>12 computed BEFORE pixhigh increment,
;     floor clip clamp, draw inclusive yl..mid and ceilingclip=mid, otherwise
;     ceilingclip=yl-1; no-upper + markceiling updates ceilingclip=yl-1;
;   - two-sided lower tier: mid=(pixlow+HEIGHTUNIT-1)>>12 computed BEFORE pixlow
;     increment, ceiling clamp, draw inclusive mid..yh and floorclip=mid,
;     otherwise floorclip=yh+1; no-lower + markfloor updates floorclip=yh+1;
;   - masked two-sided midtextures, plane row storage, silhouette/sprite clip
;     copies and texturecolumn/lighting calculations are omitted as documented;
;   - every column advances scale/topfrac/bottomfrac after tier work; pixhigh/
;     pixlow advance only inside their original active texture-tier branches.
;
; Solid ranges use the original colfunc inclusive drawing contract:
;   R_DrawColumn count=dc_yh-dc_yl; count<0 draws nothing; otherwise count+1
;   inclusive pixels are written. Here direct PaletteIndex bytes are written to
;   the row-major plane; only already valid 0..199 rows and 0..319 columns can
;   reach the buffer. Out-of-frame candidate ranges are safely skipped and
;   counted, never clipped into partial pixels or written beyond 64,000 bytes.
;
; Stable debug palette-index contract (no lighting/COLORMAP dependency):
;   background 0; one-sided middle face 176; upper face 252; lower face 96.
; Distinct non-overlapping indices; optional local presentation may use the
; user's PLAYPAL, but no source pixels are copied into the frame here.
;
; Ownership/lifetime:
;   - WallVerticalClip is caller-owned, zero-initialized once. Begin owns ONE
;     contiguous allocation holding 320 ceilingclip Longs then 320 floorclip
;     Longs; Reset frees it idempotently and validates the derived pointer layout
;     instead of freeing unexplained memory. Arrays are rebuilt per frame, not
;     per column, and there is no allocation in the per-column hot path.
;   - WallDrawTally is caller-owned numeric counters; Reset zeroes it.
;   - FrameBuffer remains the M1 caller-owned 320x200 index plane; this module
;     only writes existing pixels after checking width/height/PixelCount.
;   - FNV-1a64 frame hash covers exactly the 64,000 row-major palette bytes,
;     offset -3750763034362895579, prime 1099511628211, uppercase 16-digit
;     leading-zero text in WallFrameHashHex64.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLDRAW_PBI, #PB_Constant) = 0

#DOOMPB_WALLDRAW_PBI = 1

XIncludeFile "../Graphics/FrameBuffer.pbi"
XIncludeFile "WallProject.pbi"

#WALLDRAW_BackgroundIndex = 0
#WALLDRAW_MiddleIndex     = 176
#WALLDRAW_UpperIndex      = 252
#WALLDRAW_LowerIndex      = 96

#WALLDRAW_ViewWidth  = #PROJ_VIEWWIDTH
#WALLDRAW_ViewHeight = #PROJ_VIEWHEIGHT
#WALLDRAW_PixelCount = #WALLDRAW_ViewWidth * #WALLDRAW_ViewHeight
#WALLDRAW_MaxClipBytes = 2560

#WALLDRAW_ClipMagic  = $57564331
#WALLDRAW_TallyMagic = $57545431

#WALLDRAW_FNV_Offset = -3750763034362895579
#WALLDRAW_FNV_Prime  = 1099511628211

; Private solid-range outcome codes used by the production drawing helper.
#WALLDRAW_RangeEmpty     = 0
#WALLDRAW_RangeDrawn     = 1
#WALLDRAW_RangeOutOfFrame = 2

Structure WallVerticalClip
  Magic.l
  Width.l
  *Ceiling.Long
  *Floor.Long
EndStructure

Structure WallDrawTally
  Magic.l
  ProcessedSpans.l
  ProcessedColumns.l
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
EndStructure

Global gWallDraw_LastError.s = ""

Procedure WallDrawSetError(Message.s)
  gWallDraw_LastError = Message
EndProcedure

Procedure.s WallDrawLastError()
  ProcedureReturn gWallDraw_LastError
EndProcedure

; ---------------------------------------------------------------------------
; Per-frame vertical clip arrays
; ---------------------------------------------------------------------------

Procedure.i WallVerticalClipReset(*Clip.WallVerticalClip)
  Protected expectedFloor.i

  If *Clip = 0
    WallDrawSetError("WallVerticalClip pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Clip\Magic = #WALLDRAW_ClipMagic
    If *Clip\Ceiling <> 0
      If *Clip\Width <= 0 Or *Clip\Floor <> *Clip\Ceiling + Int(*Clip\Width) * SizeOf(Long)
        WallDrawSetError("Wall vertical clip owned pointers are inconsistent with their width.")
        ProcedureReturn #False
      EndIf
      FreeMemory(*Clip\Ceiling)
    ElseIf *Clip\Floor <> 0
      WallDrawSetError("Wall vertical clip has a floor pointer without its ceiling base.")
      ProcedureReturn #False
    EndIf
  ElseIf *Clip\Magic <> 0
    WallDrawSetError("Wall vertical clip has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Clip\Ceiling <> 0 Or *Clip\Floor <> 0
    WallDrawSetError("Wall vertical clip has owned pointers without a Magic value.")
    ProcedureReturn #False
  EndIf

  *Clip\Magic = #WALLDRAW_ClipMagic
  *Clip\Width = 0
  *Clip\Ceiling = 0
  *Clip\Floor = 0
  gWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; Allocates the canonical 320x200 clip arrays once per frame and initializes
; exactly ceilingclip=-1 / floorclip=200. Repeated Begin rebuilds deterministically.
Procedure.i WallVerticalClipBegin(*Clip.WallVerticalClip)
  Protected bytes.q
  Protected *block.Long
  Protected column.i

  WallDrawSetError("")
  If *Clip = 0
    WallDrawSetError("WallVerticalClip pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Clip\Magic <> 0 And *Clip\Magic <> #WALLDRAW_ClipMagic
    WallDrawSetError("Wall vertical clip has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If WallVerticalClipReset(*Clip) = #False
    ProcedureReturn #False
  EndIf

  bytes = Int(#WALLDRAW_ViewWidth) * 2 * SizeOf(Long)
  If bytes <= 0 Or bytes > #WALLDRAW_MaxClipBytes
    WallDrawSetError("Wall vertical clip array size is outside the checked frame budget: " + Str(bytes) + ".")
    ProcedureReturn #False
  EndIf
  *block = AllocateMemory(bytes)
  If *block = 0
    WallDrawSetError("Out of memory while allocating the wall vertical clip arrays.")
    ProcedureReturn #False
  EndIf
  FillMemory(*block, Int(bytes), 0)
  *Clip\Ceiling = *block
  *Clip\Floor = *block + Int(#WALLDRAW_ViewWidth) * SizeOf(Long)
  For column = 0 To #WALLDRAW_ViewWidth - 1
    PokeL(*Clip\Ceiling + column * SizeOf(Long), -1)
    PokeL(*Clip\Floor + column * SizeOf(Long), #WALLDRAW_ViewHeight)
  Next
  *Clip\Width = #WALLDRAW_ViewWidth
  *Clip\Magic = #WALLDRAW_ClipMagic
  gWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i WallVerticalClipGet(*Clip.WallVerticalClip, Column.l,
                                *Ceiling.Long, *Floor.Long)
  If *Clip = 0 Or *Clip\Magic <> #WALLDRAW_ClipMagic Or
     *Clip\Width <> #WALLDRAW_ViewWidth Or *Clip\Ceiling = 0 Or *Clip\Floor = 0
    WallDrawSetError("Wall vertical clip arrays are not initialized.")
    ProcedureReturn #False
  EndIf
  If Column < 0 Or Column > #WALLDRAW_ViewWidth - 1
    WallDrawSetError("Wall vertical clip column is out of range: " + Str(Column) + ".")
    ProcedureReturn #False
  EndIf
  If *Ceiling <> 0
    PokeL(*Ceiling, PeekL(*Clip\Ceiling + Column * SizeOf(Long)))
  EndIf
  If *Floor <> 0
    PokeL(*Floor, PeekL(*Clip\Floor + Column * SizeOf(Long)))
  EndIf
  gWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Counters
; ---------------------------------------------------------------------------

Procedure.i WallDrawTallyReset(*Tally.WallDrawTally)
  If *Tally = 0
    WallDrawSetError("WallDrawTally pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Tally\Magic <> 0 And *Tally\Magic <> #WALLDRAW_TallyMagic
    WallDrawSetError("WallDrawTally has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Tally, Int(SizeOf(WallDrawTally)), 0)
  *Tally\Magic = #WALLDRAW_TallyMagic
  gWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Bounded solid-color column helper
; ---------------------------------------------------------------------------

; Inclusive byte-column writer. Returns RangeEmpty when yl>yh, RangeOutOfFrame
; when any boundary/column exceeds the 320x200 plane (no partial mutation), and
; RangeDrawn after writing count+1 inclusive pixels. Only valid prechecked rows
; and existing framebuffer bytes are touched; no allocation happens here.
Procedure.i WallDrawSolidColumn(*FrameBuffer.FrameBuffer, Column.l,
                                YLow.l, YHigh.l, PaletteIndex.l,
                                *PixelCount.Long)
  Protected row.l
  Protected rowWidth.l
  Protected offset.i

  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic Or
     *FrameBuffer\Width <> #WALLDRAW_ViewWidth Or
     *FrameBuffer\Height <> #WALLDRAW_ViewHeight Or
     *FrameBuffer\PixelCount <> #WALLDRAW_PixelCount Or *FrameBuffer\Pixels = 0
    WallDrawSetError("Solid wall column framebuffer is not the canonical 320x200 plane.")
    ProcedureReturn #WALLDRAW_RangeOutOfFrame
  EndIf
  If *PixelCount = 0
    WallDrawSetError("WallDrawSolidColumn: pixel-count output pointer is null.")
    ProcedureReturn #WALLDRAW_RangeOutOfFrame
  EndIf

  If YLow > YHigh
    *PixelCount\l = 0
    gWallDraw_LastError = ""
    ProcedureReturn #WALLDRAW_RangeEmpty
  EndIf
  If Column < 0 Or Column > #WALLDRAW_ViewWidth - 1 Or
     YLow < 0 Or YHigh < 0 Or YLow > #WALLDRAW_ViewHeight - 1 Or
     YHigh > #WALLDRAW_ViewHeight - 1
    PokeL(*PixelCount, 0)
    WallDrawSetError("Solid wall column escaped the 320x200 plane: x=" + Str(Column) +
                     ", y=" + Str(YLow) + ".." + Str(YHigh) + ".")
    ProcedureReturn #WALLDRAW_RangeOutOfFrame
  EndIf
  If PaletteIndex < 0 Or PaletteIndex > 255
    WallDrawSetError("Solid wall debug palette index is outside 0..255: " + Str(PaletteIndex) + ".")
    ProcedureReturn #WALLDRAW_RangeOutOfFrame
  EndIf

  rowWidth = Int(#WALLDRAW_ViewWidth)
  For row = YLow To YHigh
    offset.i = row * rowWidth + Int(Column)
    PokeA(*FrameBuffer\Pixels + offset, PaletteIndex)
  Next
  *PixelCount\l = YHigh - YLow + 1
  gWallDraw_LastError = ""
  ProcedureReturn #WALLDRAW_RangeDrawn
EndProcedure

; ---------------------------------------------------------------------------
; R_RenderSegLoop solid-color equivalent for one WallSpanPlan
; ---------------------------------------------------------------------------

; Draws one prepared span into an already-cleared 320x200 frame and mutates the
; shared clip arrays. Early plan/buffer/clip errors fail before any pixel write
; and leave *Tally untouched; successful spans publish counters atomically at
; the end. Out-of-frame computed vertical candidates are skipped/counted rather
; than failing the frame or touching memory outside the 64,000-byte plane.
Procedure.i WallDrawSpan(*FrameBuffer.FrameBuffer, *Plan.WallSpanPlan,
                         *Clip.WallVerticalClip, *Tally.WallDrawTally)
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
  Protected pixelCount.l = 0
  Protected rangeOutcome.i
  Protected drewAnything.i
  Protected localProcessedColumns.l = 0
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

  WallDrawSetError("")
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    WallDrawSetError("Wall span draw: framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If *FrameBuffer\Width <> #WALLDRAW_ViewWidth Or
     *FrameBuffer\Height <> #WALLDRAW_ViewHeight Or
     *FrameBuffer\PixelCount <> #WALLDRAW_PixelCount Or *FrameBuffer\Pixels = 0
    WallDrawSetError("Wall span draw: framebuffer is not the canonical 320x200 plane.")
    ProcedureReturn #False
  EndIf
  If *Plan = 0 Or WallSpanPlanIsReady(*Plan) = #False
    WallDrawSetError("Wall span draw: render plan is not ready.")
    ProcedureReturn #False
  EndIf
  If *Clip = 0 Or *Clip\Magic <> #WALLDRAW_ClipMagic Or
     *Clip\Width <> #WALLDRAW_ViewWidth Or *Clip\Ceiling = 0 Or *Clip\Floor = 0
    WallDrawSetError("Wall span draw: vertical clip arrays are not initialized.")
    ProcedureReturn #False
  EndIf
  If *Tally = 0 Or *Tally\Magic <> #WALLDRAW_TallyMagic
    WallDrawSetError("Wall span draw: tally is not initialized.")
    ProcedureReturn #False
  EndIf

  firstX = *Plan\FirstX
  lastX = *Plan\LastX
  If firstX < 0 Or lastX < 0 Or firstX > #WALLDRAW_ViewWidth - 1 Or
     lastX > #WALLDRAW_ViewWidth - 1 Or firstX > lastX
    WallDrawSetError("Wall span draw: plan columns are invalid: " + Str(firstX) + ".." + Str(lastX) + ".")
    ProcedureReturn #False
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

    ; Original markfloor/markceiling plane row storage is omitted; those plane
    ; assignments do not mutate ceilingclip/floorclip in R_RenderSegLoop.

    If *Plan\MiddleTier <> 0
      rangeOutcome = WallDrawSolidColumn(*FrameBuffer, column, yl, yh,
                                         #WALLDRAW_MiddleIndex, @pixelCount)
      If rangeOutcome = #WALLDRAW_RangeOutOfFrame
        localOutOfFrameColumns + 1
      ElseIf rangeOutcome = #WALLDRAW_RangeDrawn
        drewAnything = #True
        localMiddlePixels + pixelCount
        localMiddleRanges + 1
        localDrawRanges + 1
      EndIf
      ; Source closes the column after the one-sided middle colfunc regardless
      ; of an empty clipped range.
      PokeL(*Clip\Ceiling + column * SizeOf(Long), #WALLDRAW_ViewHeight)
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
          rangeOutcome = WallDrawSolidColumn(*FrameBuffer, column, yl, mid,
                                            #WALLDRAW_UpperIndex, @pixelCount)
          If rangeOutcome = #WALLDRAW_RangeOutOfFrame
            localOutOfFrameColumns + 1
          ElseIf rangeOutcome = #WALLDRAW_RangeDrawn
            drewAnything = #True
            localUpperPixels + pixelCount
            localUpperRanges + 1
            localDrawRanges + 1
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
          rangeOutcome = WallDrawSolidColumn(*FrameBuffer, column, mid, yh,
                                            #WALLDRAW_LowerIndex, @pixelCount)
          If rangeOutcome = #WALLDRAW_RangeOutOfFrame
            localOutOfFrameColumns + 1
          ElseIf rangeOutcome = #WALLDRAW_RangeDrawn
            drewAnything = #True
            localLowerPixels + pixelCount
            localLowerRanges + 1
            localDrawRanges + 1
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

    ; Source per-column end-step order is independent of tiers/marks.
    scaleCurrent = WallFixedAddLow(scaleCurrent, *Plan\ScaleStep)
    topFracCurrent = WallFixedAddLow(topFracCurrent, *Plan\TopStep)
    bottomFracCurrent = WallFixedAddLow(bottomFracCurrent, *Plan\BottomStep)
  Next

  *Tally\ProcessedSpans + 1
  *Tally\ProcessedColumns + localProcessedColumns
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
  gWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Deterministic frame fingerprints
; ---------------------------------------------------------------------------

; FNV-1a64 over exactly the 64,000 row-major palette-index bytes of a canonical
; 320x200 FrameBuffer. *Hash is untouched on invalid frames/pointer.
Procedure.i WallFrameHash64(*FrameBuffer.FrameBuffer, *Hash.Quad)
  Protected hash.q = #WALLDRAW_FNV_Offset
  Protected byteIndex.i
  Protected value.i

  WallDrawSetError("")
  If *Hash = 0
    WallDrawSetError("WallFrameHash64: hash pointer is null.")
    ProcedureReturn #False
  EndIf
  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    WallDrawSetError("WallFrameHash64: framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If *FrameBuffer\Width <> #WALLDRAW_ViewWidth Or
     *FrameBuffer\Height <> #WALLDRAW_ViewHeight Or
     *FrameBuffer\PixelCount <> #WALLDRAW_PixelCount Or *FrameBuffer\Pixels = 0
    WallDrawSetError("WallFrameHash64: framebuffer is not the exact 320x200 index plane.")
    ProcedureReturn #False
  EndIf

  For byteIndex = 0 To #WALLDRAW_PixelCount - 1
    value = PeekA(*FrameBuffer\Pixels + byteIndex)
    hash = hash ! (Int(value) & $FF)
    hash = hash * #WALLDRAW_FNV_Prime
  Next
  PokeQ(*Hash, hash)
  gWallDraw_LastError = ""
  ProcedureReturn #True
EndProcedure

; Canonical 16-character uppercase hexadecimal rendering of a full 64-bit FNV
; value, including leading zeros. Pure integer nibble extraction; no formatting
; dependence on negative shifts or platform library codes.
Procedure.s WallFrameHashHex64(Hash.q)
  Protected nibbleChars.s = "0123456789ABCDEF"
  Protected result.s = ""
  Protected shift.i
  Protected nibble.i

  For shift = 60 To 0 Step -4
    nibble = (Hash >> shift) & $F
    result + Mid(nibbleChars, nibble + 1, 1)
  Next
  ProcedureReturn result
EndProcedure

CompilerEndIf
