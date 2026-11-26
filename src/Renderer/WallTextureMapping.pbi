; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-06 pure wall-texture column mapping helpers, ported from Linux Doom 1.10
; r_segs.c R_StoreWallRange/R_RenderSegLoop, r_data.c R_GetColumn/R_InitTextures
; and r_draw.c R_DrawColumn. No frame writes, cache ownership, lighting or
; resource decoding occur here; every helper is independently testable.
;
; Exact source formulas reproduced:
;   texturewidthmask = highest power of two not exceeding width, minus one;
;   offsetangle = rw_normalangle - rw_angle1 as raw unsigned angle_t;
;     if > ANG180 -> unsigned negate; if > ANG90 -> ANG90;
;     sineval = finesine[offsetangle >> ANGLETOFINESHIFT];
;     rw_offset = FixedMul(hyp, sineval);
;     if (rw_normalangle - rw_angle1) < ANG180 -> -rw_offset;
;     rw_offset += sidedef->textureoffset + curline->offset;    [signed32 additions]
;     rw_centerangle = ANG90 + viewangle - rw_normalangle;      [unsigned wrap]
;   angle = (rw_centerangle + xtoviewangle[x]) >> ANGLETOFINESHIFT;
;     texturecolumn = rw_offset - FixedMul(finetangent[angle], rw_distance);
;     texturecolumn >>= FRACBITS;
;   wrapped column = texturecolumn & texturewidthmask[texture];
;   dc_iscale = 0xffffffffu / (unsigned)rw_scale;
;   frac = dc_texturemid + (dc_yl - centery) * dc_iscale;
;   source_row = (frac >> FRACBITS) & 127;
;
; The original C rw_offset branch is deliberately distinct from the earlier
; R_StoreWallRange distance `abs(rw_normalangle-rw_angle1)` clamp used by M3-05.
; Here the unsigned `>ANG180 -> -`, `>ANG90 -> ANG90` order and the strict
; unsigned `< ANG180` sign test are preserved. The exact raw delta $80000000
; equals ANG180: it is not specialised in this branch (no abs(INT32_MIN)), so
; it clamps to ANG90 and takes the source's negative-sign test result.
;
; Signed 16.16 overflow sites use the already documented M3-05 widened/low32
; helpers (WallFixedAddLow/WallFixedSubLow/WallFixedNegateLow/FixedWrap32Low):
; the C unary minus of a FixedMul result and the three signed additions. These
; are not substitutes for ordinary results; ordinary admitted values remain
; bit-for-bit source-exact.
;
; Vertical source-row policy (documented, bounded, no out-of-plane read):
;   - Height >= 128: `&127` output 0..127 is directly a valid row; for height
;     128 exactly the original byte index; for larger heights only the first
;     128 rows, exactly as C's hard-coded &127.
;   - Height < 128: row128 modulo Height (deterministic vertical wrap, row in
;     0..Height-1). The original single-patch/composite column buffer would
;     instead read adjacent-column bytes past the short column (patch post
;     header/pad bytes or uninitialized composite bytes). That discontinuity is
;     not well-defined by R_GetColumn and is explicitly replaced; every fallback
;     row is bounded and a caller counter records it.
;
; Uncovered source texels are not a transparency sentinel: the sampling helper
; reports mask=0 with its own flag and the composed pixel byte (M2 composition
; stores index 0 and mask 0). Palette index 255 is an ordinary opaque value.
; No index is silently replaced inside this module; opaque-tier policy belongs
; to the cache/draw layer and is tested/counted there.
;
; `dc_iscale` is unsigned 0xFFFFFFFF/positive scale. The original result always
; fits signed fixed_t because R_ScaleFromGlobalAngle clamps scale >= 256
; (quotient <= 16,777,215). A scale <= 1 would make 4,294,967,295 and C's
; assignment to int would low-wrap to -1; that out-of-contract input is rejected
; explicitly. Scale 2 yields the exact signed upper bound 2,147,483,647 and is
; accepted for boundary tests though production can never select it.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLTEXTUREMAPPING_PBI, #PB_Constant) = 0

#DOOMPB_WALLTEXTUREMAPPING_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Core/TrigTables.pbi"
XIncludeFile "../Map/MapTypes.pbi"
XIncludeFile "../Graphics/Texture.pbi"
XIncludeFile "WallProject.pbi"

#WALLTEX_MaxTextureDimension = 4096
#WALLTEX_ExactSourceRows = 128
#WALLTEX_ScaleMinAdmit = 2
#WALLTEX_UnsignedScaleNumerator = $FFFFFFFF

Global gWallTextureMapping_LastError.s = ""

Procedure WallTextureMappingSetError(Message.s)
  gWallTextureMapping_LastError = Message
EndProcedure

Procedure.s WallTextureMappingLastError()
  ProcedureReturn gWallTextureMapping_LastError
EndProcedure

; ---------------------------------------------------------------------------
; Original R_InitTextures texturewidthmask generation
; ---------------------------------------------------------------------------

; `j=1; while j*2 <= width: j<<=1; mask=j-1`. Checked for width 1..4096.
Procedure.i WallTextureWidthMaskChecked(Width.l, *Mask.Long)
  Protected power.l = 1

  WallTextureMappingSetError("")
  If *Mask = 0
    WallTextureMappingSetError("WallTextureWidthMaskChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If Width <= 0 Or Width > #WALLTEX_MaxTextureDimension
    WallTextureMappingSetError("Wall texture width is outside 1.." + Str(#WALLTEX_MaxTextureDimension) + ": " + Str(Width) + ".")
    ProcedureReturn #False
  EndIf

  While power * 2 <= Width
    power = power << 1
  Wend
  If power <= 0 Or power > Width
    WallTextureMappingSetError("Texture width-mask power is inconsistent with the checked width.")
    ProcedureReturn #False
  EndIf

  *Mask\l = power - 1
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; r_segs.c R_StoreWallRange rw_offset and rw_centerangle
; ---------------------------------------------------------------------------

; Source-faithful unsigned offsetangle branch plus signed FixedMul/sign/add and
; centerangle wrap. Hyp must be a positive fixed value (M3-05 already rejects a
; coincident seg-v1 zero distance). TextureOffsetMap/SegOffsetMap are raw signed
; 16-bit map units exactly as decoded; p_setup.c stores them as fixed_t by
; `SHORT(field)<<FRACBITS`, so each is converted exactly through
; FixedFromIntChecked before the source-order additions after the negated product.
Procedure.i WallTextureOffsetChecked(ViewAngle.q, NormalAngle.q, ReferenceAngle.q,
                                     Hyp.l, TextureOffsetMap.l, SegOffsetMap.l,
                                     *Offset.Long, *CenterAngle.Quad)
  Protected delta.q
  Protected clampedOffset.q
  Protected shiftedOffset.q
  Protected fineIndex.l
  Protected sineval.l = 0
  Protected product.l
  Protected signedOffset.l
  Protected fixedTextureOffset.l = 0
  Protected fixedSegOffset.l = 0
  Protected summed.l

  WallTextureMappingSetError("")
  If *Offset = 0 Or *CenterAngle = 0
    WallTextureMappingSetError("WallTextureOffsetChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(ViewAngle) = 0 Or BamRawInUnsignedDomain(NormalAngle) = 0 Or
     BamRawInUnsignedDomain(ReferenceAngle) = 0
    WallTextureMappingSetError("WallTextureOffsetChecked: input angle is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf
  If Hyp <= 0
    WallTextureMappingSetError("WallTextureOffsetChecked: hyp must be a positive fixed distance: " + Str(Hyp) + ".")
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(Int(TextureOffsetMap), @fixedTextureOffset) = #False
    WallTextureMappingSetError("WallTextureOffsetChecked: sidedef textureoffset map unit is not representable as fixed_t: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(Int(SegOffsetMap), @fixedSegOffset) = #False
    WallTextureMappingSetError("WallTextureOffsetChecked: seg offset map unit is not representable as fixed_t: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  ; rw_normalangle - rw_angle1 as unsigned angle_t, exact modulo-2^32 ring.
  delta = BamSubtract(NormalAngle, ReferenceAngle)
  clampedOffset = delta
  If clampedOffset > #BAM_ANG180
    clampedOffset = BamNegate(clampedOffset)
  EndIf
  If clampedOffset > #BAM_ANG90
    clampedOffset = #BAM_ANG90
  EndIf

  shiftedOffset.q = clampedOffset >> #BAM_ANGLETOFINESHIFT
  fineIndex = Int(shiftedOffset)
  If fineIndex < 0 Or fineIndex > #TRIG_SINE_COUNT - 1
    WallTextureMappingSetError("WallTextureOffsetChecked: finesine index is outside the table: " + Str(fineIndex) + ".")
    ProcedureReturn #False
  EndIf
  If TrigSineChecked(fineIndex, @sineval) = #False
    WallTextureMappingSetError("WallTextureOffsetChecked: finesine lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  product = FixedMul(Hyp, sineval)
  signedOffset = product
  If delta < #BAM_ANG180
    signedOffset = WallFixedNegateLow(product)
  EndIf
  summed = WallFixedAddLow(signedOffset, fixedTextureOffset)
  summed = WallFixedAddLow(summed, fixedSegOffset)

  *Offset\l = summed
  ; ANG90 + viewangle - rw_normalangle in original left-to-right unsigned order.
  PokeQ(*CenterAngle, BamSubtract(BamAdd(#BAM_ANG90, ViewAngle), NormalAngle))
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; r_segs.c per-column texturecolumn calculation
; ---------------------------------------------------------------------------

; Returns both the signed fixed pre-shift subtraction result and the exact
; `>>FRACBITS` integer texturecolumn, leaving both output pointers untouched on
; failure. The tangent domain is 0..4095; the `(centerangle+xtoviewangle)>>19`
; raw unsigned sum is checked rather than trusting a >4096 tangent index.
Procedure.i WallTextureColumnChecked(Offset.l, CenterAngle.q, XToViewAngle.q,
                                     Distance.l, *ColumnFixed.Long, *Column.Long)
  Protected angleSum.q
  Protected shiftedSum.q
  Protected tangentIndex.l
  Protected tangent.l = 0
  Protected product.l
  Protected columnFixed.l
  Protected column.l

  WallTextureMappingSetError("")
  If BamRawInUnsignedDomain(CenterAngle) = 0 Or BamRawInUnsignedDomain(XToViewAngle) = 0
    WallTextureMappingSetError("WallTextureColumnChecked: angle input is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf
  If Distance < 0
    WallTextureMappingSetError("Wall texture column distance is negative: " + Str(Distance) + ".")
    ProcedureReturn #False
  EndIf

  angleSum = BamAdd(CenterAngle, XToViewAngle)
  shiftedSum.q = angleSum >> #BAM_ANGLETOFINESHIFT
  tangentIndex = Int(shiftedSum)
  If tangentIndex < 0 Or tangentIndex > #TRIG_FINETANGENT_COUNT - 1
    WallTextureMappingSetError("WallTextureColumnChecked: angle fine index is outside finetangent: " + Str(tangentIndex) + ".")
    ProcedureReturn #False
  EndIf
  If TrigTangentChecked(tangentIndex, @tangent) = #False
    WallTextureMappingSetError("WallTextureColumnChecked: finetangent lookup failed: " + TrigLastError())
    ProcedureReturn #False
  EndIf

  product = FixedMul(tangent, Distance)
  columnFixed = WallFixedSubLow(Offset, product)
  column = columnFixed >> #FRACBITS

  If *ColumnFixed <> 0
    PokeL(*ColumnFixed, columnFixed)
  EndIf
  If *Column <> 0
    PokeL(*Column, column)
  EndIf
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; r_data.c R_GetColumn column & texturewidthmask
; ---------------------------------------------------------------------------

; Exact 32-bit signed bit pattern & positive width mask. Negative raw columns
; wrap identically to C two's-complement bit AND (`-1 & 63 = 63`); the result is
; always checked to be a real source column 0..Width-1. No modulo-width formula.
Procedure.i WallTextureColumnWrapChecked(Column.l, WidthMask.l, Width.l, *Wrapped.Long)
  Protected wrappedValue.l

  WallTextureMappingSetError("")
  If *Wrapped = 0
    WallTextureMappingSetError("WallTextureColumnWrapChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If Width <= 0 Or Width > #WALLTEX_MaxTextureDimension
    WallTextureMappingSetError("Wall texture column-wrap width is outside 1.." + Str(#WALLTEX_MaxTextureDimension) + ": " + Str(Width) + ".")
    ProcedureReturn #False
  EndIf
  If WidthMask < 0 Or WidthMask >= Width
    WallTextureMappingSetError("Wall texture width mask " + Str(WidthMask) + " is not a valid 0.." + Str(Width - 1) + " mask for width " + Str(Width) + ".")
    ProcedureReturn #False
  EndIf

  wrappedValue = Column & WidthMask
  If wrappedValue < 0 Or wrappedValue >= Width
    WallTextureMappingSetError("Wrapped texture column escaped width: " + Str(wrappedValue) + ".")
    ProcedureReturn #False
  EndIf
  *Wrapped\l = wrappedValue
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; r_draw.c dc_iscale and frac
; ---------------------------------------------------------------------------

; Exact unsigned 0xFFFFFFFF / (unsigned) positive scale. The result is the
; signed domain fixed_t value used by C; scale 1 produces 4,294,967,295 and is
; rejected because the C int assignment would be an out-of-contract low wrap.
Procedure.i WallTextureIscaleChecked(Scale.l, *IScale.Long)
  Protected numerator.q = #WALLTEX_UnsignedScaleNumerator
  Protected denominator.q
  Protected quotient.q

  WallTextureMappingSetError("")
  If *IScale = 0
    WallTextureMappingSetError("WallTextureIscaleChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If Scale <= 0 Or Scale < #WALLTEX_ScaleMinAdmit
    WallTextureMappingSetError("Wall texture scale is not an admitted positive fixed value >= " + Str(#WALLTEX_ScaleMinAdmit) + ": " + Str(Scale) + ".")
    ProcedureReturn #False
  EndIf

  denominator.q = Int(Scale)
  quotient.q = numerator / denominator
  If quotient <= 0 Or quotient > #FIXED_MAX
    WallTextureMappingSetError("Wall texture iscale quotient is outside signed fixed_t: " + Str(quotient) + ".")
    ProcedureReturn #False
  EndIf

  *IScale\l = FixedWrap32Low(quotient)
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; `frac = dc_texturemid + (dc_yl-centery)*dc_iscale`, exact integer product and
; addition in the documented modular low-32 policy for C signed overflow sites.
; Ordinary values (dc_yl-centery within the 320 view, iscale >=256 product,
; texturemid range) stay exact signed16.16.
Procedure.i WallTextureFracChecked(TextureMid.l, YLow.l, CenterY.l, IScale.l,
                                   *Frac.Long)
  Protected difference.q
  Protected product.q
  Protected productLow.l
  Protected fracValue.l

  WallTextureMappingSetError("")
  If *Frac = 0
    WallTextureMappingSetError("WallTextureFracChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If IScale < 0
    WallTextureMappingSetError("Wall texture iscale must be nonnegative for frac generation: " + Str(IScale) + ".")
    ProcedureReturn #False
  EndIf
  If CenterY < 0 Or CenterY > #WALLTEX_MaxTextureDimension
    WallTextureMappingSetError("Wall texture center Y is outside the admitted view domain: " + Str(CenterY) + ".")
    ProcedureReturn #False
  EndIf

  difference.q = Int(YLow) - Int(CenterY)
  product.q = difference * Int(IScale)
  productLow = FixedWrap32Low(product)
  fracValue = WallFixedAddLow(TextureMid, productLow)

  *Frac\l = fracValue
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; Source `frac += fracstep` performed once per inclusive painted row.
Procedure.l WallTextureFracAdvance(Frac.l, IScale.l)
  ProcedureReturn WallFixedAddLow(Frac, IScale)
EndProcedure

; ---------------------------------------------------------------------------
; r_draw.c source_row = (frac >> FRACBITS) & 127
; ---------------------------------------------------------------------------

; Exact signed fixed arithmetic shift and low seven-bit AND, including negative
; frac values (C x86 arithmetic shift + two's-complement AND).
Procedure.l WallTextureSourceRow128(Frac.l)
  Protected row.l = Frac >> #FRACBITS

  ProcedureReturn row & 127
EndProcedure

; Bounded safe mapping of the exact 0..127 row into a composed plane. Height
; >= 128 preserves the source row byte for byte; a shorter height wraps modulo
; its height and reports the explicit fallback flag/counter policy.
Procedure.i WallTextureSourceRowBounded(Row128.l, Height.l,
                                        *SourceRow.Long, *Fallback.Long)
  Protected sourceRow.l
  Protected fallback.l = 0

  WallTextureMappingSetError("")
  If Row128 < 0 Or Row128 > #WALLTEX_ExactSourceRows - 1
    WallTextureMappingSetError("Wall texture source row128 is outside the original 0..127 domain: " + Str(Row128) + ".")
    ProcedureReturn #False
  EndIf
  If Height <= 0 Or Height > #WALLTEX_MaxTextureDimension
    WallTextureMappingSetError("Wall texture height is outside 1.." + Str(#WALLTEX_MaxTextureDimension) + ": " + Str(Height) + ".")
    ProcedureReturn #False
  EndIf

  If Height >= #WALLTEX_ExactSourceRows
    sourceRow = Row128
  Else
    sourceRow = Row128 % Height
    fallback = 1
  EndIf
  If sourceRow < 0 Or sourceRow >= Height
    WallTextureMappingSetError("Bounded texture source row escaped the composed height.")
    ProcedureReturn #False
  EndIf

  If *SourceRow <> 0
    PokeL(*SourceRow, sourceRow)
  EndIf
  If *Fallback <> 0
    PokeL(*Fallback, fallback)
  EndIf
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Bounded composed-image texel sampling
; ---------------------------------------------------------------------------

; Reads one palette-index texel and its separate opacity mask byte from a
; canonical TextureImage plane. Column is already width-masked and must be
; 0..Width-1; row128 is 0..127 and maps through the bounded policy. Mask bytes
; other than 0/1 are malformed input diagnostics; mask=0 is reported through
; Opaque=0 without substituting any palette value. All offsets are validated
; against Width*Height before PeekA.
Procedure.i WallTextureSampleChecked(*Image.TextureImage, Column.l, Row128.l,
                                     *SourceRow.Long, *Opaque.Long,
                                     *PixelIndex.Long, *Fallback.Long)
  Protected planeWidth.q
  Protected planeHeight.q
  Protected expectedPixels.q
  Protected sourceRow.l
  Protected fallback.l = 0
  Protected opaqueValue.i
  Protected pixelValue.i
  Protected planeOffset.q

  WallTextureMappingSetError("")
  If *Image = 0 Or *Image\Magic <> #TEXTURE_ImageMagic
    WallTextureMappingSetError("Wall texture sampling: composed image is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Image\Width <= 0 Or *Image\Width > #WALLTEX_MaxTextureDimension Or
     *Image\Height <= 0 Or *Image\Height > #WALLTEX_MaxTextureDimension Or
     *Image\Pixels = 0 Or *Image\Mask = 0
    WallTextureMappingSetError("Wall texture sampling: composed image dimensions or planes are invalid.")
    ProcedureReturn #False
  EndIf
  planeWidth.q = Int(*Image\Width)
  planeHeight.q = Int(*Image\Height)
  expectedPixels.q = planeWidth * planeHeight
  If expectedPixels.q <= 0 Or expectedPixels.q > #TEXTURE_MaxOutputPixels Or
     *Image\PixelCount <> expectedPixels.q
    WallTextureMappingSetError("Wall texture sampling: composed plane pixel count is inconsistent: " + Str(*Image\PixelCount) + " vs " + Str(expectedPixels) + ".")
    ProcedureReturn #False
  EndIf
  If Column < 0 Or Column >= *Image\Width
    WallTextureMappingSetError("Wall texture sampling column is outside the composed width: " + Str(Column) + ".")
    ProcedureReturn #False
  EndIf

  If WallTextureSourceRowBounded(Row128, *Image\Height, @sourceRow, @fallback) = #False
    ProcedureReturn #False
  EndIf

  planeOffset.q = Int(sourceRow) * planeWidth + Int(Column)
  If planeOffset.q < 0 Or planeOffset.q >= expectedPixels.q
    WallTextureMappingSetError("Wall texture sampling texel offset escaped the composed plane.")
    ProcedureReturn #False
  EndIf

  opaqueValue = PeekA(*Image\Mask + planeOffset)
  If opaqueValue <> 0 And opaqueValue <> 1
    WallTextureMappingSetError("Wall texture opacity mask contains a non-0/1 byte: " + Str(opaqueValue) + " at row " + Str(sourceRow) + ", column " + Str(Column) + ".")
    ProcedureReturn #False
  EndIf
  pixelValue = PeekA(*Image\Pixels + planeOffset)
  If pixelValue < 0 Or pixelValue > 255
    WallTextureMappingSetError("Wall texture pixel index is outside the palette domain.")
    ProcedureReturn #False
  EndIf

  If *SourceRow <> 0
    PokeL(*SourceRow, sourceRow)
  EndIf
  If *Opaque <> 0
    PokeL(*Opaque, opaqueValue)
  EndIf
  If *PixelIndex <> 0
    PokeL(*PixelIndex, pixelValue)
  EndIf
  If *Fallback <> 0
    PokeL(*Fallback, fallback)
  EndIf
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Texture height and r_segs.c pegging/mid calculations
; ---------------------------------------------------------------------------

; textureheight[i] = texture->height << FRACBITS; checked positive fixed value.
Procedure.i WallTextureHeightFixedChecked(Height.l, *FixedHeight.Long)
  Protected wideHeight.q
  Protected heightFixed.l = 0

  WallTextureMappingSetError("")
  If *FixedHeight = 0
    WallTextureMappingSetError("WallTextureHeightFixedChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If Height <= 0 Or Height > #WALLTEX_MaxTextureDimension
    WallTextureMappingSetError("Wall texture height is outside the checked dimension domain: " + Str(Height) + ".")
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(Height, @heightFixed) = #False
    WallTextureMappingSetError("Wall texture height fixed conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If heightFixed <= 0
    WallTextureMappingSetError("Wall texture fixed height is nonpositive.")
    ProcedureReturn #False
  EndIf

  *FixedHeight\l = heightFixed
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; One-sided middle alignment from R_StoreWallRange:
;   DONTPEGBOTTOM: vtop = frontsector floorheight + textureheight; mid=vtop-viewz;
;   otherwise: mid = worldtop;  always mid += sidedef->rowoffset, where the raw
;   sidedef row offset is p_setup.c `SHORT(rowoffset)<<FRACBITS` (fixed_t).
Procedure.i WallTextureMidOneSidedChecked(WorldTopRaw.l, FrontFloorFixed.l,
                                          ViewZFixed.l, TextureHeightFixed.l,
                                          RowOffsetMap.l, LineFlags.l,
                                          *TextureMid.Long)
  Protected vtop.l
  Protected midValue.l
  Protected fixedRowOffset.l = 0

  WallTextureMappingSetError("")
  If *TextureMid = 0
    WallTextureMappingSetError("WallTextureMidOneSidedChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If TextureHeightFixed <= 0
    WallTextureMappingSetError("One-sided mid texture height must be a positive fixed value.")
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(Int(RowOffsetMap), @fixedRowOffset) = #False
    WallTextureMappingSetError("One-sided mid texture sidedef rowoffset map unit is not representable as fixed_t: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  If (LineFlags & #MAP_ML_DONTPEGBOTTOM) <> 0
    vtop = WallFixedAddLow(FrontFloorFixed, TextureHeightFixed)
    midValue = WallFixedSubLow(vtop, ViewZFixed)
  Else
    midValue = WorldTopRaw
  EndIf
  midValue = WallFixedAddLow(midValue, fixedRowOffset)

  *TextureMid\l = midValue
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; Two-sided upper:
;   DONTPEGTOP: mid=worldtop;
;   otherwise: vtop=backsector ceilingheight+textureheight; mid=vtop-viewz;
;   + p_setup.c `SHORT(rowoffset)<<FRACBITS` fixed_t rowoffset.
Procedure.i WallTextureMidUpperChecked(WorldTopRaw.l, BackCeilingFixed.l,
                                       ViewZFixed.l, TextureHeightFixed.l,
                                       RowOffsetMap.l, LineFlags.l,
                                       *TextureMid.Long)
  Protected vtop.l
  Protected midValue.l
  Protected fixedRowOffset.l = 0

  WallTextureMappingSetError("")
  If *TextureMid = 0
    WallTextureMappingSetError("WallTextureMidUpperChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If TextureHeightFixed <= 0
    WallTextureMappingSetError("Upper texture height must be a positive fixed value.")
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(Int(RowOffsetMap), @fixedRowOffset) = #False
    WallTextureMappingSetError("Upper texture sidedef rowoffset map unit is not representable as fixed_t: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  If (LineFlags & #MAP_ML_DONTPEGTOP) <> 0
    midValue = WorldTopRaw
  Else
    vtop = WallFixedAddLow(BackCeilingFixed, TextureHeightFixed)
    midValue = WallFixedSubLow(vtop, ViewZFixed)
  EndIf
  midValue = WallFixedAddLow(midValue, fixedRowOffset)

  *TextureMid\l = midValue
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

; Two-sided lower:
;   DONTPEGBOTTOM: mid=worldtop (top of texture at top);
;   otherwise: mid=worldlow;
;   + p_setup.c `SHORT(rowoffset)<<FRACBITS` fixed_t rowoffset.
Procedure.i WallTextureMidLowerChecked(WorldTopRaw.l, WorldLowRaw.l,
                                       RowOffsetMap.l, LineFlags.l,
                                       *TextureMid.Long)
  Protected midValue.l
  Protected fixedRowOffset.l = 0

  WallTextureMappingSetError("")
  If *TextureMid = 0
    WallTextureMappingSetError("WallTextureMidLowerChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(Int(RowOffsetMap), @fixedRowOffset) = #False
    WallTextureMappingSetError("Lower texture sidedef rowoffset map unit is not representable as fixed_t: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  If (LineFlags & #MAP_ML_DONTPEGBOTTOM) <> 0
    midValue = WorldTopRaw
  Else
    midValue = WorldLowRaw
  EndIf
  midValue = WallFixedAddLow(midValue, fixedRowOffset)

  *TextureMid\l = midValue
  gWallTextureMapping_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
