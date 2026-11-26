; -----------------------------------------------------------------------------
; DoomPB - M3-06 textured wall-column/vanilla lighting unit tests WT01-WT60
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Standalone wholly synthetic/no-IWAD suite. Includes the accepted M2/M3
; resource, map, geometry, visibility, projection, legacy wall-draw and M3-06
; modules, the public generated numeric/pixel fixture from
; scripts/gen_wall_texture_golden.py, the independently generated M3-05 fixture
; for legacy hash preservation, the shared synthetic WAD/map support module and
; the production PlayPAL/framebuffer presentation converter. Expected mapping,
; lighting, pegging, row, cache, full-frame, hash and scalar values come from the
; independent Python oracle fixture or an explicit integer formula here, never
; from first production output. No commercial WAD bytes, Doom graphics or
; display usage occur.
;
; Exit code: 0 when every assertion passed, otherwise the failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Map/MapTypes.pbi"
XIncludeFile "../../src/Map/MapDecode.pbi"
XIncludeFile "../../src/Map/MapLevel.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"
XIncludeFile "../../src/Map/MapValidate.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/Projection.pbi"
XIncludeFile "../../src/Renderer/ClipSegs.pbi"
XIncludeFile "../../src/Renderer/WallVisibility.pbi"
XIncludeFile "../../src/Renderer/WallView.pbi"
XIncludeFile "../../src/Renderer/WallProject.pbi"
XIncludeFile "../../src/Renderer/WallDraw.pbi"
XIncludeFile "../../src/Renderer/RenderMain.pbi"
XIncludeFile "../../src/Renderer/WallTextureMapping.pbi"
XIncludeFile "../../src/Renderer/WallTextureCache.pbi"
XIncludeFile "../../src/Renderer/WallLighting.pbi"
XIncludeFile "../../src/Renderer/TexturedWallDraw.pbi"
XIncludeFile "../../src/Renderer/TexturedRenderMain.pbi"
XIncludeFile "../../src/Graphics/FrameBuffer.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Patch.pbi"
XIncludeFile "../../src/Graphics/Texture.pbi"
XIncludeFile "../../src/Graphics/Palette.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../fixtures/m3_wall_texture_golden.pbi"
XIncludeFile "../fixtures/m3_wall_projection_golden.pbi"
XIncludeFile "../integration/wall_texture_support.pbi"

#UNIT_FNV_Offset = -3750763034362895579
#UNIT_FNV_Prime = 1099511628211
#UNIT_FramePixelCount = 64000
#UNIT_PlanLSeg = 1
#UNIT_PlanLFirstX = 6
#UNIT_PlanLLastX = 7
#UNIT_PlanLScale1 = 9
#UNIT_PlanLScaleStep = 11
#UNIT_PlanLHyp = 12
#UNIT_PlanLDistance = 13
#UNIT_PlanLWorldTopRaw = 14
#UNIT_PlanLWorldBottomRaw = 15
#UNIT_PlanLWorldLowRaw = 17
#UNIT_PlanLTopFrac = 22
#UNIT_PlanLBottomFrac = 23
#UNIT_PlanLTopStep = 24
#UNIT_PlanLBottomStep = 25
#UNIT_PlanLPixHigh = 26
#UNIT_PlanLPixLow = 27
#UNIT_PlanLPixHighStep = 28
#UNIT_PlanLPixLowStep = 29
#UNIT_PlanLMarkFloor = 30
#UNIT_PlanLMarkCeiling = 31
#UNIT_PlanLTopTier = 34
#UNIT_PlanLBottomTier = 35
#UNIT_PlanLMiddleTier = 36
#UNIT_PlanLTwoSided = 37
#UNIT_PlanLMidTextureIndex = 41
#UNIT_PlanLTopTextureIndex = 42
#UNIT_PlanLBottomTextureIndex = 43
#UNIT_PlanLMaskedMidIndex = 44
#UNIT_PlanLMidTextureMid = 45
#UNIT_PlanLTopTextureMid = 46
#UNIT_PlanLBottomTextureMid = 47
#UNIT_PlanLMidWidth = 48
#UNIT_PlanLMidHeight = 49
#UNIT_PlanLMidWidthMask = 50
#UNIT_PlanLTopWidth = 51
#UNIT_PlanLTopHeight = 52
#UNIT_PlanLTopWidthMask = 53
#UNIT_PlanLBottomWidth = 54
#UNIT_PlanLBottomHeight = 55
#UNIT_PlanLBottomWidthMask = 56
#UNIT_PlanLRawOffset = 57
#UNIT_PlanLLightNum = 58
#UNIT_PlanLMaskedMid = 59
#UNIT_PlanLHasPaintedTier = 60
#UNIT_PlanLSegmentTextured = 61
#UNIT_QViewAngle = 0
#UNIT_QNormalAngle = 1
#UNIT_QReferenceAngle = 2
#UNIT_QCenterAngle = 5
#PALETTE_FormulaBase = 11
#PALETTE_FormulaStep = 5

Global gUCaseCount.i = 0
Global gUAssertionCount.i = 0
Global gUFailureCount.i = 0
Global gUFixedDirPrepared.i = #False

Global *gTI01Spans = ?TEXGOLD_TI01_Spans
Global *gTI01PlanL = ?TEXGOLD_TI01_PlanL
Global *gTI01PlanQ = ?TEXGOLD_TI01_PlanQ
Global *gTI01SampleX = ?TEXGOLD_TI01_SampleX
Global *gTI01SampleRows = ?TEXGOLD_TI01_SampleRows
Global *gTI01Frame = ?TEXGOLD_TI01_Frame
Global *gTI01Hash = ?TEXGOLD_TI01_Hash
Global *gTI02Spans = ?TEXGOLD_TI02_Spans
Global *gTI02PlanL = ?TEXGOLD_TI02_PlanL
Global *gTI02PlanQ = ?TEXGOLD_TI02_PlanQ
Global *gTI02SampleX = ?TEXGOLD_TI02_SampleX
Global *gTI02SampleRows = ?TEXGOLD_TI02_SampleRows
Global *gTI02Frame = ?TEXGOLD_TI02_Frame
Global *gTI02Hash = ?TEXGOLD_TI02_Hash
Global *gScalelightBins = ?TEXGOLD_ScalelightBins
Global *gOldCHash = ?WallGold_C_Hash

Procedure BeginCase(Id.s, Title.s)
  gUCaseCount + 1
  PrintN("")
  PrintN("[" + Id + "] " + Title)
EndProcedure

Procedure Check(Ok.i, Description.s)
  gUAssertionCount + 1
  If Ok
    PrintN("  PASS: " + Description)
  Else
    PrintN("  FAIL: " + Description)
    gUFailureCount + 1
  EndIf
EndProcedure

Procedure.q FnvByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #UNIT_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvFrame(*Frame.FrameBuffer)
  Protected hash.q = #UNIT_FNV_Offset
  Protected i.i

  For i = 0 To #UNIT_FramePixelCount - 1
    hash = FnvByte(hash, PeekA(*Frame\Pixels + i))
  Next
  ProcedureReturn hash
EndProcedure

Procedure.i HexCanonical(Text.s)
  Protected i.i
  Protected value.i

  If Len(Text) <> 16
    ProcedureReturn #False
  EndIf
  For i = 1 To 16
    value = Asc(Mid(Text, i, 1))
    If value < Asc("0") Or value > Asc("F") Or
       (value > Asc("9") And value < Asc("A"))
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

Procedure.i SceneSpanCount(SceneId.s)
  If SceneId = "TI01"
    ProcedureReturn #TEXGOLD_TI01_SpanCount
  ElseIf SceneId = "TI02"
    ProcedureReturn #TEXGOLD_TI02_SpanCount
  EndIf
  ProcedureReturn -1
EndProcedure

Procedure.i SceneSpanField(SceneId.s, SpanIndex.l, FieldIndex.l, *Value.Long)
  Protected *base.Long

  If SpanIndex < 0 Or SpanIndex >= SceneSpanCount(SceneId) Or
     FieldIndex < 0 Or FieldIndex >= #TEXGOLD_SpanFieldCount
    ProcedureReturn #False
  EndIf
  If SceneId = "TI01"
    *base = *gTI01Spans
  ElseIf SceneId = "TI02"
    *base = *gTI02Spans
  Else
    ProcedureReturn #False
  EndIf
  *Value\l = PeekL(*base + (SpanIndex * #TEXGOLD_SpanFieldCount + FieldIndex) * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

Procedure.i ScenePlanL(SceneId.s, PlanIndex.l, FieldIndex.l, *Value.Long)
  Protected *base.Long

  If PlanIndex < 0 Or PlanIndex >= SceneSpanCount(SceneId) Or
     FieldIndex < 0 Or FieldIndex >= #TEXGOLD_PlanLFieldCount
    ProcedureReturn #False
  EndIf
  If SceneId = "TI01"
    *base = *gTI01PlanL
  ElseIf SceneId = "TI02"
    *base = *gTI02PlanL
  Else
    ProcedureReturn #False
  EndIf
  *Value\l = PeekL(*base + (PlanIndex * #TEXGOLD_PlanLFieldCount + FieldIndex) * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

Procedure.i ScenePlanQ(SceneId.s, PlanIndex.l, FieldIndex.l, *Value.Quad)
  Protected *base.Byte

  If PlanIndex < 0 Or PlanIndex >= SceneSpanCount(SceneId) Or
     FieldIndex < 0 Or FieldIndex >= #TEXGOLD_PlanQFieldCount
    ProcedureReturn #False
  EndIf
  If SceneId = "TI01"
    *base = *gTI01PlanQ
  ElseIf SceneId = "TI02"
    *base = *gTI02PlanQ
  Else
    ProcedureReturn #False
  EndIf
  *base = *base + (PlanIndex * #TEXGOLD_PlanQFieldCount + FieldIndex) * SizeOf(Quad)
  PokeQ(*Value, PeekQ(*base))
  ProcedureReturn #True
EndProcedure

Procedure.i SceneFrameByte(SceneId.s, ByteIndex.l, *Byte.Long)
  Protected *base.Byte

  If ByteIndex < 0 Or ByteIndex > #TEXGOLD_PixelCount - 1
    ProcedureReturn #False
  EndIf
  If SceneId = "TI01"
    *base = *gTI01Frame
  ElseIf SceneId = "TI02"
    *base = *gTI02Frame
  Else
    ProcedureReturn #False
  EndIf
  *Byte\l = PeekA(*base + ByteIndex)
  ProcedureReturn #True
EndProcedure

Procedure.q SceneHash(SceneId.s)
  If SceneId = "TI01"
    ProcedureReturn PeekQ(*gTI01Hash)
  ElseIf SceneId = "TI02"
    ProcedureReturn PeekQ(*gTI02Hash)
  EndIf
  ProcedureReturn -1
EndProcedure

; Full-plane comparison against the independent Python oracle bytes. Returns the
; mismatch count, -1 for invalid frame dimensions, -2 for a fixture access error.
Procedure.l FrameCompareFixture(SceneId.s, *Frame.FrameBuffer)
  Protected byteIndex.i
  Protected expected.l = 0
  Protected actual.i
  Protected mismatch.l = 0

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #TEXGOLD_ViewWidth Or *Frame\Height <> #TEXGOLD_ViewHeight Or
     *Frame\PixelCount <> #TEXGOLD_PixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For byteIndex = 0 To #TEXGOLD_PixelCount - 1
    If SceneFrameByte(SceneId.s, byteIndex, @expected) = #False
      ProcedureReturn -2
    EndIf
    actual = PeekA(*Frame\Pixels + byteIndex)
    If actual <> expected
      mismatch + 1
    EndIf
  Next
  ProcedureReturn mismatch
EndProcedure

Procedure.l FixtureScalelight(Level.l, ScaleIndex.l)
  If Level < 0 Or Level >= #LIGHT_LEVELS Or ScaleIndex < 0 Or ScaleIndex >= #LIGHT_MAXLIGHTSCALE
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekL(*gScalelightBins + (Level * #LIGHT_MAXLIGHTSCALE + ScaleIndex) * SizeOf(Long))
EndProcedure

; -----------------------------------------------------------------------------
; Independent integer formulas and source vectors
; -----------------------------------------------------------------------------

Procedure.l IMul(A.l, B.l)
  Protected product.q = Int(A) * Int(B)

  product = product >> #FRACBITS
  ProcedureReturn FixedWrap32Low(product)
EndProcedure

Procedure.l IAddLow(A.l, B.l)
  Protected sum.q = Int(A) + Int(B)

  ProcedureReturn FixedWrap32Low(sum)
EndProcedure

Procedure.l ISubLow(A.l, B.l)
  Protected diff.q = Int(A) - Int(B)

  ProcedureReturn FixedWrap32Low(diff)
EndProcedure

Procedure.l INegLow(A.l)
  ProcedureReturn FixedWrap32Low(-Int(A))
EndProcedure

Procedure.l IMapUnitFixed(Raw.l)
  Protected product.q = Int(Raw) * #FRACUNIT

  ProcedureReturn FixedWrap32Low(product)
EndProcedure

Procedure.l ITangent(Index.l)
  Protected value.l = 0

  If TrigTangentChecked(Index, @value) = #False
    ProcedureReturn -999999999
  EndIf
  ProcedureReturn value
EndProcedure

Procedure.l ISine(Index.l)
  Protected value.l = 0

  If TrigSineChecked(Index, @value) = #False
    ProcedureReturn -999999999
  EndIf
  ProcedureReturn value
EndProcedure

; Independent r_segs.c R_StoreWallRange rw_offset + rw_centerangle from raw
; unsigned angles, pinned finesine and raw signed map-unit offsets.
Procedure.i IOffset(ViewAngle.q, NormalAngle.q, ReferenceAngle.q, Hyp.l,
                   TextureOffset.l, SegOffset.l, *Offset.Long, *CenterAngle.Quad)
  Protected delta.q
  Protected angle.q
  Protected shift.q
  Protected index.l
  Protected sine.l
  Protected product.l
  Protected signed.l
  Protected sum.l
  Protected fineOffset.l
  Protected fineSeg.l

  delta = BamSubtract(NormalAngle, ReferenceAngle)
  angle = delta
  If angle > #BAM_ANG180
    angle = BamNegate(angle)
  EndIf
  If angle > #BAM_ANG90
    angle = #BAM_ANG90
  EndIf
  shift.q = angle >> #BAM_ANGLETOFINESHIFT
  index = Int(shift)
  sine = ISine(index)
  If sine = -999999999
    ProcedureReturn #False
  EndIf
  product = IMul(Hyp, sine)
  signed = product
  If delta < #BAM_ANG180
    signed = INegLow(product)
  EndIf
  fineOffset = IMapUnitFixed(TextureOffset)
  fineSeg = IMapUnitFixed(SegOffset)
  sum = IAddLow(signed, fineOffset)
  sum = IAddLow(sum, fineSeg)
  *Offset\l = sum
  PokeQ(*CenterAngle, BamSubtract(BamAdd(#BAM_ANG90, ViewAngle), NormalAngle))
  ProcedureReturn #True
EndProcedure

; Independent per-column texturecolumn from raw sum, pinned tangent, distance.
Procedure.i IColumn(Offset.l, CenterAngle.q, XToViewAngle.q, Distance.l,
                    *Fixed.Long, *Column.Long)
  Protected sum.q
  Protected shift.q
  Protected index.l
  Protected tangent.l
  Protected product.l
  Protected fixed.l
  Protected column.l

  sum = BamAdd(CenterAngle, XToViewAngle)
  shift.q = sum >> #BAM_ANGLETOFINESHIFT
  index = Int(shift)
  If index < 0 Or index >= #TRIG_FINETANGENT_COUNT
    ProcedureReturn #False
  EndIf
  tangent = ITangent(index)
  If tangent = -999999999
    ProcedureReturn #False
  EndIf
  product = IMul(tangent, Distance)
  fixed = ISubLow(Offset, product)
  column = fixed >> #FRACBITS
  *Fixed\l = fixed
  *Column\l = column
  ProcedureReturn #True
EndProcedure

Procedure.i IIscale(Scale.l, *IScale.Long)
  Protected quotient.q

  If Scale <= 0 Or Scale < #WALLTEX_ScaleMinAdmit
    ProcedureReturn #False
  EndIf
  quotient.q = #WALLTEX_UnsignedScaleNumerator / Int(Scale)
  If quotient <= 0 Or quotient > #FIXED_MAX
    ProcedureReturn #False
  EndIf
  *IScale\l = FixedWrap32Low(quotient)
  ProcedureReturn #True
EndProcedure

Procedure.l IFrac(TextureMid.l, YLow.l, CenterY.l, IScale.l)
  Protected diff.q
  Protected product.q
  Protected low.l

  diff.q = Int(YLow) - Int(CenterY)
  product.q = diff * Int(IScale)
  low.l = FixedWrap32Low(product)
  ProcedureReturn IAddLow(TextureMid, low)
EndProcedure

Procedure.l ISourceRow(Frac.l)
  Protected row.l = Frac >> #FRACBITS

  ProcedureReturn row & 127
EndProcedure

Procedure.i IBoundedRow(Row128.l, Height.l, *SourceRow.Long, *Fallback.Long)
  Protected row.l
  Protected fallback.l = 0

  If Row128 < 0 Or Row128 > 127 Or Height <= 0 Or Height > #WALLTEX_MaxTextureDimension
    ProcedureReturn #False
  EndIf
  If Height >= 128
    row = Row128
  Else
    row = Row128 % Height
    fallback = 1
  EndIf
  If row < 0 Or row >= Height
    ProcedureReturn #False
  EndIf
  *SourceRow\l = row
  *Fallback\l = fallback
  ProcedureReturn #True
EndProcedure

; Creates a wholly synthetic composed image plane with uniform pixel/mask.
Procedure.i BuildImage(*Image.TextureImage, Width.l, Height.l, Pixel.l, MaskValue.i)
  Protected count.q
  Protected i.i
  Protected pixels.i
  Protected mask.i
  Protected opaque.q

  TextureImageReset(*Image)
  If *Image = 0 Or Width <= 0 Or Height <= 0 Or Pixel < 0 Or Pixel > 255 Or
     (MaskValue <> 0 And MaskValue <> 1)
    ProcedureReturn #False
  EndIf
  count.q = Int(Width) * Int(Height)
  If count <= 0 Or count > #TEXTURE_MaxOutputPixels
    ProcedureReturn #False
  EndIf
  pixels = AllocateMemory(count)
  mask = AllocateMemory(count)
  If pixels = 0 Or mask = 0
    If pixels <> 0
      FreeMemory(pixels)
    EndIf
    If mask <> 0
      FreeMemory(mask)
    EndIf
    ProcedureReturn #False
  EndIf
  FillMemory(pixels, Int(count), Pixel)
  FillMemory(mask, Int(count), MaskValue)
  opaque = 0
  If MaskValue = 1
    opaque = count
  EndIf
  *Image\Magic = #TEXTURE_ImageMagic
  *Image\Width = Width
  *Image\Height = Height
  *Image\PixelCount = count
  *Image\OpaqueCount = opaque
  *Image\Pixels = pixels
  *Image\Mask = mask
  ProcedureReturn #True
EndProcedure

Procedure.q ImagePlaneFnv(*Image.TextureImage)
  Protected hash.q = #UNIT_FNV_Offset
  Protected i.i

  If *Image = 0 Or *Image\Magic <> #TEXTURE_ImageMagic Or *Image\Pixels = 0 Or *Image\Mask = 0
    ProcedureReturn -1
  EndIf
  For i = 0 To Int(*Image\PixelCount) - 1
    hash = FnvByte(hash, PeekA(*Image\Pixels + i))
  Next
  For i = 0 To Int(*Image\PixelCount) - 1
    hash = FnvByte(hash, PeekA(*Image\Mask + i))
  Next
  ProcedureReturn hash
EndProcedure

; -----------------------------------------------------------------------------
; Synthetic WAD/map/direct-cache builders
; -----------------------------------------------------------------------------

Procedure.i BuildWallMap(*Level.MapLevel, TwoSided.i, BackFloor.l, BackCeiling.l,
                         BackLight.l, TopName.s, BottomName.s, MidName.s,
                         TextureOffset.l, RowOffset.l, SegOffset.l,
                         FrontLight.l = 160)
  Protected Dim sectors.WallTexSectorSpec(1)
  Protected Dim lines.WallTexLineSpec(0)
  Protected Dim sides.WallTexSideSpec(1)
  Protected Dim verts.WallTexVertexSpec(1)
  Protected Dim segs.WallTexSegSpec(0)
  Protected Dim subs.WallTexSubSpec(0)
  Protected Dim nodes.WallTexNodeSpec(0)
  Protected Dim things.WallTexThingSpec(0)
  Protected sectorCount.l = 1
  Protected sideCount.l = 1

  sectors(0)\FloorHeight = 0 : sectors(0)\CeilingHeight = 128
  sectors(0)\FloorName = "FLOOR1" : sectors(0)\CeilingName = "CEIL1"
  sectors(0)\LightLevel = FrontLight
  sides(0)\Sector = 0 : sides(0)\TopName = TopName : sides(0)\BottomName = BottomName
  sides(0)\MidName = MidName : sides(0)\TextureOffset = TextureOffset : sides(0)\RowOffset = RowOffset
  lines(0)\V1 = 0 : lines(0)\V2 = 1 : lines(0)\Side0 = 0 : lines(0)\Side1 = -1
  If TwoSided
    sectors(1)\FloorHeight = BackFloor : sectors(1)\CeilingHeight = BackCeiling
    sectors(1)\FloorName = "FLOOR2" : sectors(1)\CeilingName = "CEIL2"
    sectors(1)\LightLevel = BackLight
    sides(1)\Sector = 1 : sides(1)\TopName = "-" : sides(1)\BottomName = "-" : sides(1)\MidName = "-"
    sectorCount = 2 : sideCount = 2 : lines(0)\Side1 = 1 : lines(0)\Flags = #MAP_ML_TWOSIDED
  EndIf
  verts(0)\X = 100 : verts(0)\Y = 64 : verts(1)\X = 100 : verts(1)\Y = -64
  segs(0)\V1 = 0 : segs(0)\V2 = 1 : segs(0)\RawAngle = 49152
  segs(0)\Line = 0 : segs(0)\Side = 0 : segs(0)\Offset = SegOffset
  subs(0)\NumSegs = 1 : subs(0)\FirstSeg = 0
  ProcedureReturn WallTexBuildMapLevel(*Level, @sectors(0), sectorCount, @lines(0), 1,
                                       @sides(0), sideCount, @verts(0), 2, @segs(0), 1,
                                       @subs(0), 1, @nodes(0), 0, @things(0), 0)
EndProcedure

Procedure.i BuildCMap(*Level.MapLevel)
  Protected Dim sectors.WallTexSectorSpec(1)
  Protected Dim lines.WallTexLineSpec(1)
  Protected Dim sides.WallTexSideSpec(2)
  Protected Dim verts.WallTexVertexSpec(3)
  Protected Dim segs.WallTexSegSpec(1)
  Protected Dim subs.WallTexSubSpec(0)
  Protected Dim nodes.WallTexNodeSpec(0)
  Protected Dim things.WallTexThingSpec(0)

  sectors(0)\FloorHeight = 0 : sectors(0)\CeilingHeight = 128 : sectors(0)\LightLevel = 160
  sectors(0)\FloorName = "FLOOR1" : sectors(0)\CeilingName = "CEIL1"
  sectors(1)\FloorHeight = 32 : sectors(1)\CeilingHeight = 96 : sectors(1)\LightLevel = 160
  sectors(1)\FloorName = "FLOOR2" : sectors(1)\CeilingName = "CEIL2"
  lines(0)\V1 = 0 : lines(0)\V2 = 1 : lines(0)\Side0 = 0 : lines(0)\Side1 = -1
  lines(1)\V1 = 2 : lines(1)\V2 = 3 : lines(1)\Flags = #MAP_ML_TWOSIDED
  lines(1)\Side0 = 1 : lines(1)\Side1 = 2
  sides(0)\Sector = 0 : sides(0)\TopName = "WALL1" : sides(0)\BottomName = "WALL1" : sides(0)\MidName = "WALL1"
  sides(1)\Sector = 0 : sides(1)\TopName = "WALL1" : sides(1)\BottomName = "WALL1" : sides(1)\MidName = "-"
  sides(2)\Sector = 1 : sides(2)\TopName = "WALL1" : sides(2)\BottomName = "WALL1" : sides(2)\MidName = "WALL1"
  verts(0)\X = 100 : verts(0)\Y = 64 : verts(1)\X = 100 : verts(1)\Y = -64
  verts(2)\X = 300 : verts(2)\Y = 32767 : verts(3)\X = 300 : verts(3)\Y = -32767
  segs(0)\V1 = 0 : segs(0)\V2 = 1 : segs(0)\RawAngle = 49152 : segs(0)\Line = 0 : segs(0)\Side = 0
  segs(1)\V1 = 2 : segs(1)\V2 = 3 : segs(1)\RawAngle = 49152 : segs(1)\Line = 1 : segs(1)\Side = 0
  subs(0)\NumSegs = 2 : subs(0)\FirstSeg = 0
  ProcedureReturn WallTexBuildMapLevel(*Level, @sectors(0), 2, @lines(0), 2,
                                       @sides(0), 3, @verts(0), 4, @segs(0), 2,
                                       @subs(0), 1, @nodes(0), 0, @things(0), 0)
EndProcedure

Procedure.i BuildSceneWad(FileName.s, SceneMode.i)
  Protected marker.s = "E1M1"
  Protected ok.i = #False

  If WallTexWadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9)
    If SceneMode = 1
      ok = WallTexBuildT01MapLumps()
      marker = "E1M1"
    ElseIf SceneMode = 2
      ok = WallTexBuildT02MapLumps()
      marker = "E2M1"
    EndIf
    If ok
      ok = WallTexAddMapLumpsToWad(marker)
    EndIf
  EndIf
  If ok
    ok = WallTexWadFinish()
  EndIf
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  WallTexFreeMap()
  ProcedureReturn ok
EndProcedure

; Fully local synthetic scene session: build PWAD, open/decode resources and map
; through production APIs, derive player-one view, build projection/visibility,
; then run the transactional textured frame. WAD is closed and all session
; resources/map/view are reset after the frame attempt; only the caller-owned
; target frame and numeric render result survive for assertions.
Procedure.i RenderTexturedScene(FileName.s, SceneMode.i, Marker.s,
                                *Level.MapLevel, *View.WallView,
                                *Projection.Projection, *Flats.FlatCatalog,
                                *Textures.TextureCatalog,
                                *Colormap.ColormapSet,
                                *Visibility.WallVisibilityResult,
                                *Target.FrameBuffer,
                                *Result.TexturedWallRenderResult,
                                RequirePixels.i = #True)
  Protected pnames.PNamesTable
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0
  Protected wadOk.i = #False
  Protected catalogOk.i = #False
  Protected flatsOk.i = #False
  Protected colormapOk.i = #False
  Protected mapOk.i = #False
  Protected viewOk.i = #False
  Protected projectionOk.i = #False
  Protected visibilityOk.i = #False
  Protected renderOk.i = #False

  If BuildSceneWad(FileName.s, SceneMode.i) = #False
    PrintN("  diagnostic: RenderTexturedScene WAD build failed for " + FileName)
  ElseIf WADOpen(WallTexFixturePath(FileName.s)) = #False
    PrintN("  diagnostic: RenderTexturedScene WAD open failed for " + FileName)
  Else
    wadOk = #True
    If WallTexDecodeWallCatalog(@pnames, *Textures) = #True
      catalogOk = #True
      If WallTexDecodeWallFlats(*Flats) = #True
        flatsOk = #True
        If WallTexDecodeWallColormap(*Colormap) = #True
          colormapOk = #True
          If MapLevelLoad(Marker.s, *Level) = #True
            mapOk = #True
            If WallRenderPlayerStartView(*Level, *View, @thingIndex,
                                         @subsectorIndex, @sectorIndex) = #True
              viewOk = #True
              If ProjectionInitClassic(*Projection) = #True
                projectionOk = #True
                If WallVisibilityBuild(*Level, @*View\Camera, *Projection,
                                       0, 0, *Visibility) = #True
                  visibilityOk = #True
                  renderOk = TexturedWallRenderFrame(*Level, *View, *Projection,
                                                     *Flats, *Textures, *Colormap,
                                                     *Visibility, *Target, *Result,
                                                     RequirePixels.i)
                  If renderOk = #False
                    PrintN("  diagnostic: RenderTexturedScene frame failed: " +
                           TexturedWallRenderLastError())
                  EndIf
                Else
                  PrintN("  diagnostic: RenderTexturedScene visibility failed: " +
                         WallVisibilityLastError())
                EndIf
              Else
                PrintN("  diagnostic: RenderTexturedScene projection failed: " +
                       ProjectionLastError())
              EndIf
            Else
              PrintN("  diagnostic: RenderTexturedScene player view failed: " +
                     WallRenderLastError())
            EndIf
          Else
            PrintN("  diagnostic: RenderTexturedScene map load failed: " + MapLevelLastError())
          EndIf
        Else
          PrintN("  diagnostic: RenderTexturedScene COLORMAP decode failed")
        EndIf
      Else
        PrintN("  diagnostic: RenderTexturedScene flats decode failed")
      EndIf
    Else
      PrintN("  diagnostic: RenderTexturedScene catalog decode failed")
    EndIf
  EndIf

  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(*Textures)
  PNamesReset(@pnames)
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  If mapOk
    MapLevelReset(*Level)
  EndIf
  If viewOk
    WallViewReset(*View)
  EndIf
  If projectionOk
    ProjectionReset(*Projection)
  EndIf
  If visibilityOk
    WallVisibilityReset(*Visibility)
  EndIf
  ProcedureReturn renderOk
EndProcedure

Declare.i CloseSyntheticStream(FileName.s)

Procedure.i BrokenResourceWad(FileName.s)
  Protected *data.Byte = 0
  Protected size.q = 0
  Protected patchSize.l = 0
  Protected Dim specs.WallTexTextureSpec(4)
  Protected Dim nodPlac.WallTexPatchPlacement(0)
  Protected Dim midPlac.WallTexPatchPlacement(1)
  Protected Dim upPlac.WallTexPatchPlacement(0)
  Protected Dim loPlac.WallTexPatchPlacement(0)
  Protected Dim extraPlac.WallTexPatchPlacement(0)

  If WallTexWadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()

  *data = WallTexMakePNames("PATCHA|PATCHB|PATCHUP|PATCHLO", @size)
  If *data = 0 Or size <= 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PNAMES", *data, size)
  FreeMemory(*data)

  specs(0)\Name = "NODEF" : specs(0)\Width = 8 : specs(0)\Height = 128
  specs(0)\PatchCount = 1 : specs(0)\Placements = @nodPlac(0)
  nodPlac(0)\PNameIndex = 0
  specs(1)\Name = "TEXMID" : specs(1)\Width = 64 : specs(1)\Height = 128
  specs(1)\PatchCount = 2 : specs(1)\Placements = @midPlac(0)
  midPlac(0)\PNameIndex = 0 : midPlac(1)\PNameIndex = 1 : midPlac(1)\OriginX = 32
  specs(2)\Name = "TEXUP" : specs(2)\Width = 96 : specs(2)\Height = 72
  specs(2)\PatchCount = 1 : specs(2)\Placements = @upPlac(0)
  upPlac(0)\PNameIndex = 2
  specs(3)\Name = "TEXLO" : specs(3)\Width = 64 : specs(3)\Height = 64
  specs(3)\PatchCount = 1 : specs(3)\Placements = @loPlac(0)
  loPlac(0)\PNameIndex = 3
  specs(4)\Name = "TEXEXTRA" : specs(4)\Width = 64 : specs(4)\Height = 128
  specs(4)\PatchCount = 1 : specs(4)\Placements = @extraPlac(0)
  extraPlac(0)\PNameIndex = 0

  *data = WallTexMakeTextureLump(@specs(0), 5, @size)
  If *data = 0 Or size <= 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("TEXTURE1", *data, size)
  FreeMemory(*data)
  *data = WallTexMakeColormap(32, 17, 9, @size)
  If *data = 0 Or size <= 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("COLORMAP", *data, size)
  FreeMemory(*data)
  *data = WallTexMakeSolidPatch(32, 128, 37, @patchSize)
  If *data = 0 Or patchSize <= 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PATCHA", *data, patchSize)
  FreeMemory(*data)

  *data = WallTexNewZero(16)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexPut16(*data, 0, 32)
  WallTexPut16(*data, 2, 128)
  WallTexWadAdd("PATCHB", *data, 16)
  FreeMemory(*data)
  *data = WallTexMakeSolidPatch(96, 72, 73, @patchSize)
  If *data = 0 Or patchSize <= 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PATCHUP", *data, patchSize)
  FreeMemory(*data)
  *data = WallTexMakeSolidPatch(64, 64, 19, @patchSize)
  If *data = 0 Or patchSize <= 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PATCHLO", *data, patchSize)
  FreeMemory(*data)
  ProcedureReturn WallTexWadFinish()
EndProcedure

Procedure.i CloseSyntheticStream(FileName.s)
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure.i DuplicateTextureWad(FileName.s)
  Protected *data.Byte = 0
  Protected size.q = 0
  Protected patchSize.l = 0
  Protected Dim set1.WallTexTextureSpec(2)
  Protected Dim set2.WallTexTextureSpec(0)
  Protected Dim p1.WallTexPatchPlacement(0)
  Protected Dim pDup1.WallTexPatchPlacement(0)
  Protected Dim pAux.WallTexPatchPlacement(0)
  Protected Dim p2.WallTexPatchPlacement(0)

  If WallTexWadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  *data = WallTexMakePNames("PATCHA|PATCHB", @size)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PNAMES", *data, size)
  FreeMemory(*data)
  *data = WallTexMakeSolidPatch(32, 128, 37, @patchSize)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PATCHA", *data, patchSize)
  FreeMemory(*data)
  *data = WallTexMakeSolidPatch(32, 128, 201, @patchSize)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PATCHB", *data, patchSize)
  FreeMemory(*data)

  set1(0)\Name = "NODEF" : set1(0)\Width = 8 : set1(0)\Height = 128
  set1(0)\PatchCount = 1 : set1(0)\Placements = @p1(0)
  p1(0)\PNameIndex = 0
  set1(1)\Name = "DUP" : set1(1)\Width = 32 : set1(1)\Height = 64
  set1(1)\PatchCount = 1 : set1(1)\Placements = @pDup1(0)
  pDup1(0)\PNameIndex = 0
  set1(2)\Name = "TEXAUX" : set1(2)\Width = 32 : set1(2)\Height = 64
  set1(2)\PatchCount = 1 : set1(2)\Placements = @pAux(0)
  pAux(0)\PNameIndex = 0
  set2(0)\Name = "DUP" : set2(0)\Width = 32 : set2(0)\Height = 128
  set2(0)\PatchCount = 1 : set2(0)\Placements = @p2(0)
  p2(0)\PNameIndex = 1

  *data = WallTexMakeTextureLump(@set1(0), 3, @size)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("TEXTURE1", *data, size)
  FreeMemory(*data)
  *data = WallTexMakeTextureLump(@set2(0), 1, @size)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("TEXTURE2", *data, size)
  FreeMemory(*data)
  ProcedureReturn WallTexWadFinish()
EndProcedure

Procedure.i DuplicatePnamesWad(FileName.s)
  Protected *data.Byte = 0
  Protected size.q = 0
  Protected patchSize.l = 0
  Protected Dim specs.WallTexTextureSpec(0)
  Protected Dim plac.WallTexPatchPlacement(0)

  If WallTexWadBegin(FileName) = #False
    ProcedureReturn #False
  EndIf
  *data = WallTexMakePNames("PATCHA|PATCHA|PATCHB", @size)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PNAMES", *data, size)
  FreeMemory(*data)
  *data = WallTexMakeSolidPatch(32, 64, 37, @patchSize)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PATCHA", *data, patchSize)
  FreeMemory(*data)
  *data = WallTexMakeSolidPatch(32, 128, 201, @patchSize)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("PATCHB", *data, patchSize)
  FreeMemory(*data)
  specs(0)\Name = "DUP" : specs(0)\Width = 32 : specs(0)\Height = 64
  specs(0)\PatchCount = 1 : specs(0)\Placements = @plac(0)
  plac(0)\PNameIndex = 1
  *data = WallTexMakeTextureLump(@specs(0), 1, @size)
  If *data = 0
    ProcedureReturn CloseSyntheticStream(FileName)
  EndIf
  WallTexWadAdd("TEXTURE1", *data, size)
  FreeMemory(*data)
  ProcedureReturn WallTexWadFinish()
EndProcedure

Procedure.i CachePlan(*Plan.WallSpanPlan, Side.l, FrontSector.l, BackSector.l,
                      TopTier.i, BottomTier.i, MiddleTier.i, TwoSided.i)
  If WallSpanPlanReset(*Plan) = #False
    ProcedureReturn #False
  EndIf
  *Plan\Seg = 0 : *Plan\Linedef = 0 : *Plan\Side = Side
  *Plan\FrontSector = FrontSector : *Plan\BackSector = BackSector
  *Plan\FirstX = 160 : *Plan\LastX = 160 : *Plan\Kind = Bool(TwoSided)
  *Plan\TopTier = Bool(TopTier) : *Plan\BottomTier = Bool(BottomTier)
  *Plan\MiddleTier = Bool(MiddleTier) : *Plan\TwoSided = Bool(TwoSided)
  *Plan\Ready = 1
  ProcedureReturn #True
EndProcedure

Procedure.i ManualCacheBegin(*Cache.WallTextureCache, EntryCount.l)
  Protected bytes.q
  Protected memory.i

  If EntryCount < 0 Or EntryCount > #WALLTEXCACHE_MaxUniqueTextures
    ProcedureReturn #False
  EndIf
  If WallTextureCacheReset(*Cache) = #False
    ProcedureReturn #False
  EndIf
  If EntryCount > 0
    bytes.q = Int(EntryCount) * Int(SizeOf(WallTextureEntry))
    memory = AllocateMemory(bytes)
    If memory = 0
      ProcedureReturn #False
    EndIf
    FillMemory(memory, Int(bytes), 0)
    *Cache\Entries = memory : *Cache\Capacity = EntryCount : *Cache\Count = 0
    *Cache\Ready = 1 : *Cache\Allocations = 1
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure.i ManualCacheImage(*Cache.WallTextureCache, EntryIndex.l, CatalogIndex.l,
                             Width.l, Height.l, Pixel.l, MaskValue.i)
  Protected *entry.WallTextureEntry
  Protected mask.l = 0

  If *Cache = 0 Or *Cache\Magic <> #WALLTEXCACHE_Magic Or *Cache\Entries = 0 Or
     EntryIndex < 0 Or EntryIndex >= *Cache\Capacity
    ProcedureReturn #False
  EndIf
  If WallTextureWidthMaskChecked(Width, @mask) = #False
    ProcedureReturn #False
  EndIf
  *entry = *Cache\Entries + EntryIndex * SizeOf(WallTextureEntry)
  If *entry\Image\Magic = #TEXTURE_ImageMagic
    TextureImageReset(@*entry\Image)
  EndIf
  If BuildImage(@*entry\Image, Width, Height, Pixel, MaskValue) = #False
    ProcedureReturn #False
  EndIf
  *entry\CatalogIndex = CatalogIndex : *entry\Width = Width : *entry\Height = Height
  *entry\WidthMask = mask : *entry\ShortHeight = Bool(Height < 128)
  *entry\OpaqueCount = *entry\Image\OpaqueCount
  *Cache\Count = EntryIndex + 1
  ProcedureReturn #True
EndProcedure

Procedure.i ClipFrame(*Clip.WallVerticalClip, *Frame.FrameBuffer)
  FrameBufferReset(*Frame)
  If WallVerticalClipBegin(*Clip) = #False
    ProcedureReturn #False
  EndIf
  If FrameBufferCreate(*Frame, 320, 200) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn FrameBufferClear(*Frame, 0)
EndProcedure

; Standalone COLORMAP 32-table synthetic set from the fixture base/step formula.
Procedure.i BuildColormapSet(*Colormap.ColormapSet, TableCount.l, Base.l, TableStep.l)
  Protected bytes.q
  Protected *data.Byte = 0
  Protected mapIndex.l
  Protected texel.l
  Protected value.i
  Protected ok.i

  If TableCount <= 0 Or TableCount > #COLORMAP_MaxTables Or Base < 0 Or TableStep < 0 Or
     TableCount > 256
    ProcedureReturn #False
  EndIf
  ColormapReset(*Colormap)
  bytes.q = Int(TableCount) * 256
  *data = AllocateMemory(bytes)
  If *data = 0
    ProcedureReturn #False
  EndIf
  FillMemory(*data, Int(bytes), 0)
  For mapIndex = 0 To TableCount - 1
    For texel = 0 To 255
      value = (texel + Base + mapIndex * TableStep) & 255
      PokeA(*data + Int(mapIndex) * 256 + Int(texel), value)
    Next
  Next
  ok = ColormapDecode(*data, bytes, *Colormap)
  FreeMemory(*data)
  ProcedureReturn ok
EndProcedure

Procedure.i BuildLight(*Table.WallScalelightTable, *Colormap.ColormapSet)
  ProcedureReturn WallScalelightTableBuild(*Table, *Colormap)
EndProcedure

; Wholly synthetic 14-palette PLAYPAL byte set; each RGB entry is an independent
; integer formula, decoded through the production PaletteDecode. No Doom bytes.
Procedure.i BuildPalette(*Palette.PaletteSet, Base.l, PaletteStep.l)
  Protected paletteIndex.l
  Protected colorIndex.l
  Protected bytes.q
  Protected *data.Byte = 0
  Protected r.l
  Protected g.l
  Protected b.l

  If Base < 0 Or Base > 255 Or PaletteStep < 0 Or PaletteStep > 255
    ProcedureReturn #False
  EndIf
  bytes.q = 14 * 768
  *data = AllocateMemory(bytes)
  If *data = 0
    ProcedureReturn #False
  EndIf
  FillMemory(*data, Int(bytes), 0)
  For paletteIndex = 0 To 13
    For colorIndex = 0 To 255
      r = (colorIndex + paletteIndex * PaletteStep) & 255
      g = (255 - colorIndex + Base) & 255
      b = (37 + paletteIndex + colorIndex * 3) & 255
      PokeA(*data + (Int(paletteIndex) * 768 + Int(colorIndex) * 3), r)
      PokeA(*data + (Int(paletteIndex) * 768 + Int(colorIndex) * 3) + 1, g)
      PokeA(*data + (Int(paletteIndex) * 768 + Int(colorIndex) * 3) + 2, b)
    Next
  Next
  PaletteReset(*Palette)
  ProcedureReturn PaletteDecode(*data, bytes, *Palette)
EndProcedure

Procedure.l PaletteFormulaR(Color.l, PaletteIndex.l)
  If Color < 0 Or Color > 255 Or PaletteIndex < 0 Or PaletteIndex > 13
    ProcedureReturn -1
  EndIf
  ProcedureReturn (Color + PaletteIndex * #PALETTE_FormulaStep) & 255
EndProcedure

Procedure.l PaletteFormulaG(Color.l, PaletteIndex.l)
  If Color < 0 Or Color > 255 Or PaletteIndex < 0 Or PaletteIndex > 13
    ProcedureReturn -1
  EndIf
  ProcedureReturn (255 - Color + #PALETTE_FormulaBase) & 255
EndProcedure

Procedure.l PaletteFormulaB(Color.l, PaletteIndex.l)
  If Color < 0 Or Color > 255 Or PaletteIndex < 0 Or PaletteIndex > 13
    ProcedureReturn -1
  EndIf
  ProcedureReturn (37 + PaletteIndex + Color * 3) & 255
EndProcedure

Procedure.i LegacyPlanForDraw(*Plan.WallSpanPlan, First.l, Last.l, Kind.i,
                              TopTier.i, BottomTier.i, MiddleTier.i,
                              MarkFloor.i, MarkCeiling.i,
                              Scale1.l, ScaleStep.l, TopFrac.l, BottomFrac.l,
                              TopStep.l, BottomStep.l, PixHigh.l, PixLow.l,
                              PixHighStep.l, PixLowStep.l,
                              RawOffset.l, CenterAngle.q, Distance.l, LightNum.l)
  If WallSpanPlanReset(*Plan) = #False
    ProcedureReturn #False
  EndIf
  *Plan\SpanIndex = 0 : *Plan\Seg = 0 : *Plan\Linedef = 0 : *Plan\Side = 0
  *Plan\FrontSector = 0 : *Plan\BackSector = -1
  *Plan\FirstX = First : *Plan\LastX = Last : *Plan\Kind = Kind
  *Plan\TopTier = Bool(TopTier) : *Plan\BottomTier = Bool(BottomTier)
  *Plan\MiddleTier = Bool(MiddleTier)
  *Plan\MarkFloor = Bool(MarkFloor) : *Plan\MarkCeiling = Bool(MarkCeiling)
  *Plan\Scale1 = Scale1 : *Plan\ScaleStep = ScaleStep
  *Plan\TopFrac = TopFrac : *Plan\BottomFrac = BottomFrac
  *Plan\TopStep = TopStep : *Plan\BottomStep = BottomStep
  *Plan\PixHigh = PixHigh : *Plan\PixLow = PixLow
  *Plan\PixHighStep = PixHighStep : *Plan\PixLowStep = PixLowStep
  *Plan\Distance = Distance
  *Plan\Ready = 1
  ProcedureReturn #True
EndProcedure

Procedure.i TexturePlanForDraw(*TexturePlan.WallTextureSpanPlan,
                               SegmentTextured.i, HasPainted.i, MaskedMid.i,
                               MidSlot.l, TopSlot.l, BottomSlot.l,
                               MidMid.l, TopMid.l, BottomMid.l,
                               MidWidth.l, MidHeight.l, MidMask.l,
                               TopWidth.l, TopHeight.l, TopMask.l,
                               BottomWidth.l, BottomHeight.l, BottomMask.l,
                               RawOffset.l, CenterAngle.q, LightNum.l,
                               MidTextureIndex.l, TopTextureIndex.l, BottomTextureIndex.l)
  If WallTextureSpanPlanReset(*TexturePlan) = #False
    ProcedureReturn #False
  EndIf
  *TexturePlan\SpanIndex = 0 : *TexturePlan\Seg = 0 : *TexturePlan\Linedef = 0
  *TexturePlan\Side = 0 : *TexturePlan\FrontSector = 0 : *TexturePlan\BackSector = -1
  *TexturePlan\FirstX = 160 : *TexturePlan\LastX = 160 : *TexturePlan\Kind = 0
  *TexturePlan\SegmentTextured = Bool(SegmentTextured)
  *TexturePlan\HasPaintedTier = Bool(HasPainted)
  *TexturePlan\MaskedMid = Bool(MaskedMid)
  *TexturePlan\MidCacheSlot = MidSlot : *TexturePlan\TopCacheSlot = TopSlot
  *TexturePlan\BottomCacheSlot = BottomSlot
  *TexturePlan\MidTextureMid = MidMid : *TexturePlan\TopTextureMid = TopMid
  *TexturePlan\BottomTextureMid = BottomMid
  *TexturePlan\MidWidth = MidWidth : *TexturePlan\MidHeight = MidHeight : *TexturePlan\MidWidthMask = MidMask
  *TexturePlan\TopWidth = TopWidth : *TexturePlan\TopHeight = TopHeight : *TexturePlan\TopWidthMask = TopMask
  *TexturePlan\BottomWidth = BottomWidth : *TexturePlan\BottomHeight = BottomHeight : *TexturePlan\BottomWidthMask = BottomMask
  *TexturePlan\RawOffset = RawOffset : *TexturePlan\CenterAngle = CenterAngle
  *TexturePlan\LightNum = LightNum
  *TexturePlan\MidTextureIndex = MidTextureIndex : *TexturePlan\TopTextureIndex = TopTextureIndex
  *TexturePlan\BottomTextureIndex = BottomTextureIndex
  *TexturePlan\Ready = 1
  ProcedureReturn #True
EndProcedure

Procedure.i EmptyTexturePlan(*Plan.WallSpanPlan, *TexturePlan.WallTextureSpanPlan)
  If WallTextureSpanPlanReset(*TexturePlan) = #False
    ProcedureReturn #False
  EndIf
  *TexturePlan\SpanIndex = *Plan\SpanIndex : *TexturePlan\Seg = *Plan\Seg
  *TexturePlan\Linedef = *Plan\Linedef : *TexturePlan\Side = *Plan\Side
  *TexturePlan\FrontSector = *Plan\FrontSector : *TexturePlan\BackSector = *Plan\BackSector
  *TexturePlan\FirstX = *Plan\FirstX : *TexturePlan\LastX = *Plan\LastX
  *TexturePlan\Kind = *Plan\Kind
  *TexturePlan\MidCacheSlot = -1 : *TexturePlan\TopCacheSlot = -1
  *TexturePlan\BottomCacheSlot = -1
  *TexturePlan\SegmentTextured = 0 : *TexturePlan\HasPaintedTier = 0
  *TexturePlan\MaskedMid = 0 : *TexturePlan\Ready = 1
  ProcedureReturn #True
EndProcedure

; -----------------------------------------------------------------------------
; WT01-WT20: catalog/material/mapping/lighting basics
; -----------------------------------------------------------------------------

Procedure WT01()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected found.i
  Protected present.l = 0
  Protected index.l = 0
  Protected pl.l = 0
  Protected wadOk.i = #False

  BeginCase("WT01", "Texture catalog first-match binding and index-zero identity")
  If WallTexBuildStandardResourceWad("u0601.wad", 37, 201, 73, 19, 17, 9) = #False
    Check(#False, "WT01 synthetic resource WAD built")
    ProcedureReturn
  EndIf
  If WADOpen(WallTexFixturePath("u0601.wad")) = #False
    Check(#False, "WT01 synthetic resource WAD opens")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False
    Check(#False, "WT01 PNAMES/TEXTURE1 resolve")
    wadOk = #False
    Goto WT01Done
  EndIf

  Check(Bool(TextureCatalogCount(@textures) = #TEXGOLD_TEXTURE_Count), "WT01 catalog has five definitions")
  Check(Bool(TextureCatalogFindName(@textures, "TEXMID") = 1), "WT01 TEXMID first-match index 1")
  Check(Bool(TextureCatalogFindName(@textures, "TEXUP") = 2), "WT01 TEXUP index 2")
  Check(Bool(TextureCatalogFindName(@textures, "TEXLO") = 3), "WT01 TEXLO index 3")
  Check(Bool(TextureCatalogFindName(@textures, "texextra") = 4), "WT01 case-insensitive TEXEXTRA index 4")
  Check(Bool(TextureCatalogFindName(@textures, "NODEF") = 0), "WT01 definition index 0 stays the NoTexture quirk")
  found = TextureCatalogFindName(@textures, "TEXNOSUCH")
  Check(Bool(found = -1 And TextureDefsLastError() <> ""), "WT01 absent name returns -1 with diagnostic")
  Check(TextureCatalogGetProperties(@textures, 1, 0, 0, 0, 0, 0, 0), "WT01 TEXMID properties readable")

  If BuildWallMap(@level, 0, 0, 0, 0, "-", "-", "NODEF", 0, 0, 0) = #False
    Check(#False, "WT01 one-sided NODEF map built")
    Goto WT01Done
  EndIf
  Check(WallTextureResolvedFieldChecked(@level, @textures, 0, 2, @present, @index),
        "WT01 NODEF slot resolution accepted")
  Check(Bool(present = 0 And index = #WALLTEXCACHE_NoTexture),
        "WT01 explicit present=0/index=-1 distinguishes genuine index 0")
  MapLevelReset(@level)

WT01Done:
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT02()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected present.l = 0
  Protected index.l = 0
  Protected wadOk.i = #False

  BeginCase("WT02", "Canonical absent '-'/all-NUL slots versus valid names")
  If WallTexBuildStandardResourceWad("u0602.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0602.wad")) = #False
    Check(#False, "WT02 synthetic resource WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False
    Check(#False, "WT02 catalog resolves")
    Goto WT02Done
  EndIf
  If BuildWallMap(@level, 1, 32, 96, 96, "-", "", "TEXMID", 0, 0, 0) = #False
    Check(#False, "WT02 mixed-slot two-sided map built")
    Goto WT02Done
  EndIf
  If WallTextureResolvedFieldChecked(@level, @textures, 0, 0, @present, @index)
    Check(Bool(present = 0 And index = #WALLTEXCACHE_NoTexture), "WT02 '-' top slot absent")
  Else
    Check(#False, "WT02 '-' top resolution accepted")
  EndIf
  If WallTextureResolvedFieldChecked(@level, @textures, 0, 1, @present, @index)
    Check(Bool(present = 0 And index = #WALLTEXCACHE_NoTexture), "WT02 all-NUL bottom slot absent")
  Else
    Check(#False, "WT02 all-NUL bottom resolution accepted")
  EndIf
  If WallTextureResolvedFieldChecked(@level, @textures, 0, 2, @present, @index)
    Check(Bool(present = 1 And index = 1), "WT02 valid TEXMID mid slot present index 1")
  Else
    Check(#False, "WT02 TEXMID resolution accepted")
  EndIf
  MapLevelReset(@level)

WT02Done:
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT03()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected planA.WallSpanPlan
  Protected planB.WallSpanPlan
  Protected one.WallSpanPlan
  Protected side.l = 0
  Protected present.l = 0
  Protected index.l = 0
  Protected wadOk.i = #False

  BeginCase("WT03", "Seg-side to sidedef upper/lower/middle selection")
  If WallTexBuildStandardResourceWad("u0603.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0603.wad")) = #False
    Check(#False, "WT03 resource WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False Or
     BuildWallMap(@level, 1, 32, 96, 96, "TEXUP", "TEXLO", "TEXMID", 11, -8, 4) = #False Or
     CachePlan(@planA, 0, 0, 1, 1, 1, 0, 1) = #False Or
     CachePlan(@planB, 1, 1, 0, 0, 0, 0, 1) = #False Or
     CachePlan(@one, 0, 0, -1, 0, 0, 1, 0) = #False
    Check(#False, "WT03 catalog/map/plans prepared")
    Goto WT03Done
  EndIf
  If WallTexturePlanSidedefChecked(@level, @planA, @side)
    Check(Bool(side = 0), "WT03 plan side 0 selects sidedef 0")
  Else
    Check(#False, "WT03 plan side 0 sidedef read")
  EndIf
  If WallTexturePlanSidedefChecked(@level, @planB, @side)
    Check(Bool(side = 1), "WT03 plan side 1 selects sidedef 1")
  Else
    Check(#False, "WT03 plan side 1 sidedef read")
  EndIf
  If WallTexturePlanSidedefChecked(@level, @one, @side)
    Check(Bool(side = 0), "WT03 one-sided selects its only sidedef")
  Else
    Check(#False, "WT03 one-sided sidedef read")
  EndIf
  If WallTextureResolvedFieldChecked(@level, @textures, 0, 0, @present, @index)
    Check(Bool(present = 1 And index = 2), "WT03 side-0 top TEXUP index 2")
  EndIf
  If WallTextureResolvedFieldChecked(@level, @textures, 0, 1, @present, @index)
    Check(Bool(present = 1 And index = 3), "WT03 side-0 bottom TEXLO index 3")
  EndIf
  If WallTextureResolvedFieldChecked(@level, @textures, 0, 2, @present, @index)
    Check(Bool(present = 1 And index = 1), "WT03 side-0 middle TEXMID index 1")
  EndIf
  If WallTextureResolvedFieldChecked(@level, @textures, 1, 2, @present, @index)
    Check(Bool(present = 0 And index = #WALLTEXCACHE_NoTexture), "WT03 side-1 absent middle")
  EndIf
  MapLevelReset(@level)

WT03Done:
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT04()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected bPnames.PNamesTable
  Protected bTextures.TextureCatalog
  Protected level.MapLevel
  Protected image.TextureImage
  Protected present.l = 0
  Protected index.l = 0
  Protected wadOk.i = #False
  Protected brokenOk.i = #False
  Protected ok.i = 0
  Protected *side0.MapSidedef

  BeginCase("WT04", "Embedded-NUL, missing name and unreadable patch resource")
  If WallTexBuildStandardResourceWad("u0604.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0604.wad")) = #False
    Check(#False, "WT04 resource WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False
    Check(#False, "WT04 catalog resolves")
    Goto WT04Done
  EndIf
  Check(BuildWallMap(@level, 0, 0, 0, 0, "-", "-", "TEXMID", 0, 0, 0),
        "WT04 valid field map built for raw embedded-NUL insertion")
  Check(Bool(level\Sidedefs\Count = 1 And level\Sidedefs\Items <> 0),
        "WT04 decoded one sidedef with owned name bytes")
  If level\Sidedefs\Items <> 0
    *side0 = level\Sidedefs\Items
    ; PureBasic string concatenation truncates at Chr(0); exercise the raw WAD
    ; field directly with the original 8-byte embedded-NUL pattern TEX\0MID.
    PokeA(@*side0\MidTexture[0], Asc("T"))
    PokeA(@*side0\MidTexture[1], Asc("E"))
    PokeA(@*side0\MidTexture[2], Asc("X"))
    PokeA(@*side0\MidTexture[3], 0)
    PokeA(@*side0\MidTexture[4], Asc("M"))
    PokeA(@*side0\MidTexture[5], Asc("I"))
    PokeA(@*side0\MidTexture[6], Asc("D"))
    PokeA(@*side0\MidTexture[7], 0)
    Check(Bool(PeekA(@*side0\MidTexture[3]) = 0 And PeekA(@*side0\MidTexture[4]) = Asc("M") And
                PeekA(@*side0\MidTexture[7]) = 0),
          "WT04 raw embedded-NUL bytes preserved in map field")
    ok = WallTextureResolvedFieldChecked(@level, @textures, 0, 2, @present, @index)
    Check(Bool(ok = #False And FindString(WallTextureCacheLastError(), "noncanonical") > 0),
          "WT04 embedded-NUL slot fails with noncanonical diagnostic")
  EndIf
  MapLevelReset(@level)
  Check(BuildWallMap(@level, 0, 0, 0, 0, "-", "-", "TEXNOSUCH", 0, 0, 0),
        "WT04 missing-name slot map built")
  Check(Bool(WallTextureResolvedFieldChecked(@level, @textures, 0, 2, @present, @index) = #False And FindString(WallTextureCacheLastError(), "not found") > 0), "WT04 missing texture fails with catalog diagnostic")
  MapLevelReset(@level)
  WADClose()
  wadOk = #False
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)

  If BrokenResourceWad("u0604broken.wad") = #False Or
     WADOpen(WallTexFixturePath("u0604broken.wad")) = #False
    Check(#False, "WT04 broken resource WAD built/opened")
    ProcedureReturn
  EndIf
  brokenOk = #True
  If WallTexDecodeWallCatalog(@bPnames, @bTextures) = #False
    Check(#False, "WT04 broken catalog resolves nonzero PATCHB")
    Goto WT04Done
  EndIf
  Check(Bool(TextureCompose(@bTextures, 1, @image) = #False),
        "WT04 malformed required PATCHB fails compose")
  Check(Bool(FindString(TextureLastError(), "patch") > 0 And FindString(TextureLastError(), "decode") > 0),
        "WT04 compose failure names patch/decode context")
  Check(Bool(image\Magic = 0 And image\Pixels = 0 And image\Mask = 0),
        "WT04 failed compose leaves output image empty")

WT04Done:
  TextureImageReset(@image)
  If wadOk
    WADClose()
  EndIf
  If brokenOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
  TextureCatalogReset(@bTextures)
  PNamesReset(@bPnames)
EndProcedure

Procedure WT05()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected width.l = 0
  Protected height.l = 0
  Protected patchCount.l = 0
  Protected wadOk.i = #False

  BeginCase("WT05", "Duplicate texture names and TEXTURE1/TEXTURE2 precedence")
  If DuplicateTextureWad("u0605.wad") = #False Or
     WADOpen(WallTexFixturePath("u0605.wad")) = #False
    Check(#False, "WT05 duplicate-definition WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False
    Check(#False, "WT05 TEXTURE1+TEXTURE2 catalog resolves")
    Goto WT05Done
  EndIf
  Check(Bool(TextureCatalogCount(@textures) = 4), "WT05 combined count 3+1 definitions")
  Check(Bool(TextureCatalogFindName(@textures, "DUP") = 1), "WT05 duplicate first-match picks TEXTURE1 index 1")
  Check(TextureCatalogGetProperties(@textures, 1, @width, @height, 0, 0, @patchCount, 0), "WT05 first duplicate properties read")
  Check(Bool(width = 32 And height = 64), "WT05 first duplicate keeps 32x64")
  Check(TextureCatalogGetProperties(@textures, 3, @width, @height, 0, 0, @patchCount, 0), "WT05 TEXTURE2 duplicate properties read")
  Check(Bool(width = 32 And height = 128), "WT05 later duplicate 32x128 not selected")
  Check(Bool(TextureCatalogFindName(@textures, "dup") = 1), "WT05 case-insensitive repeat deterministic")

WT05Done:
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT06()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected image.TextureImage
  Protected resolved.l = 0
  Protected expected.i
  Protected closed.l = 0
  Protected staleResolve.i
  Protected reopened.l = 0
  Protected wadOk.i = #False

  BeginCase("WT06", "Duplicate PNAMES first-match and WAD reopen invalidation")
  If DuplicatePnamesWad("u0606.wad") = #False Or
     WADOpen(WallTexFixturePath("u0606.wad")) = #False
    Check(#False, "WT06 duplicate-PNAMES WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False
    Check(#False, "WT06 catalog resolves")
    Goto WT06Done
  EndIf
  expected = WADFindLump("PATCHA")
  resolved = TextureCatalogGetResolvedPatchLump(@textures, 0, 0)
  Check(Bool(expected >= 0 And resolved >= 0 And resolved = expected), "WT06 second-duplicate PNAME binds first PATCHA lump")
  Check(Bool(PNamesCount(@pnames) = 3), "WT06 duplicate PNAMES count 3")
  Check(Bool(TextureCatalogFindName(@textures, "DUP") = 0), "WT06 first-match DUP index 0 quirk")
  WADClose()
  wadOk = #False
  Check(TextureCatalogInvalidateResolved(@textures), "WT06 invalidation accepted after close")
  closed = TextureCatalogGetResolvedPatchLump(@textures, 0, 0)
  Check(Bool(closed = -1), "WT06 invalidated patch has no stale lump")
  staleResolve = TextureCatalogResolve(@textures, @pnames)
  Check(Bool(staleResolve = #False And FindString(TextureDefsLastError(), "WAD") > 0),
        "WT06 resolve while WAD closed fails explicitly")
  Check(TextureCatalogInvalidateResolved(@textures), "WT06 second invalidation accepted")
  If WADOpen(WallTexFixturePath("u0606.wad")) = #False
    Check(#False, "WT06 WAD reopens")
    Goto WT06Done
  EndIf
  wadOk = #True
  Check(TextureCatalogResolve(@textures, @pnames), "WT06 re-resolves on reopened session")
  expected = WADFindLump("PATCHA")
  reopened = TextureCatalogGetResolvedPatchLump(@textures, 0, 0)
  Check(Bool(reopened >= 0 And reopened = expected), "WT06 reopened resolved lump current and non-stale")
  Check(TextureCompose(@textures, 0, @image), "WT06 reopened compose succeeds")
  Check(Bool(image\Magic = #TEXTURE_ImageMagic And image\Width = 32 And image\Height = 64 And
              TextureImageOpaqueCount(@image) = 2048),
        "WT06 composed image full 32x64 opaque plane")

WT06Done:
  TextureImageReset(@image)
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT07()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected plan.WallSpanPlan
  Protected cache.WallTextureCache
  Protected count.l = 0
  Protected capacity.l = 0
  Protected requested.l = 0
  Protected reused.l = 0
  Protected masked.l = 0
  Protected short.l = 0
  Protected allocs.l = 0
  Protected temp.q = 0
  Protected plane.q = 0
  Protected peak.q = 0
  Protected slot.i = -1
  Protected *image.TextureImage
  Protected wadOk.i = #False

  BeginCase("WT07", "Used-texture cache uniqueness for repeated tiers")
  If WallTexBuildStandardResourceWad("u0607.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0607.wad")) = #False
    Check(#False, "WT07 resource WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False Or
     BuildWallMap(@level, 1, 32, 96, 96, "TEXMID", "TEXMID", "TEXMID", 3, 5, 1) = #False Or
     CachePlan(@plan, 0, 0, 1, 1, 1, 1, 1) = #False
    Check(#False, "WT07 catalog/map/plan prepared")
    Goto WT07Done
  EndIf
  Check(WallTextureCacheBuild(@level, @textures, @plan, 1, @cache), "WT07 cache build succeeds")
  If WallTextureCacheGetStats(@cache, @count, @capacity, @requested, @reused, @masked,
                              @short, @allocs, @temp, @plane, @peak)
    Check(Bool(count = 1 And requested = 3 And reused = 2),
          "WT07 three references to TEXMID compose one entry, reuse 2")
    Check(Bool(short = 0 And masked = 1 And allocs = 4),
          "WT07 128-high two-sided TEXMID masked middle deferred, allocations 4")
  Else
    Check(#False, "WT07 cache stats read")
  EndIf
  slot = WallTextureCacheFindIndex(@cache, 1)
  Check(Bool(slot = 0), "WT07 catalog TEXMID maps to slot 0")
  *image = WallTextureCacheImagePtr(@cache, slot)
  Check(Bool(*image <> 0 And *image\Width = 64 And *image\Height = 128),
        "WT07 shared composed image 64x128")
  If *image <> 0
    Check(Bool(TextureImageGetPixel(*image, 0, 0) = #TEXGOLD_PatchA), "WT07 entry column0 A")
    Check(Bool(TextureImageGetPixel(*image, 32, 0) = #TEXGOLD_PatchB), "WT07 entry column32 B")
  EndIf

WT07Done:
  WallTextureCacheReset(@cache)
  MapLevelReset(@level)
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT08()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected plan.WallSpanPlan
  Protected cache.WallTextureCache
  Protected count.l = 0
  Protected wadOk.i = #False

  BeginCase("WT08", "Cache ownership/reset without double-free")
  If WallTexBuildStandardResourceWad("u0608.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0608.wad")) = #False
    Check(#False, "WT08 resource WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False Or
     BuildWallMap(@level, 0, 0, 0, 0, "-", "-", "TEXMID", 1, -2, 1) = #False Or
     CachePlan(@plan, 0, 0, -1, 0, 0, 1, 0) = #False
    Check(#False, "WT08 catalog/map/plan prepared")
    Goto WT08Done
  EndIf
  Check(WallTextureCacheBuild(@level, @textures, @plan, 1, @cache), "WT08 cache build succeeds")
  count = WallTextureCacheCount(@cache)
  Check(Bool(count = 1), "WT08 owned cache count 1")
  Check(Bool(WallTextureCacheImagePtr(@cache, 0) <> 0), "WT08 borrowed image valid pre-release")
  WADClose()
  wadOk = #False
  Check(TextureCatalogReset(@textures), "WT08 catalog reset after close")
  Check(WallTextureCacheReset(@cache), "WT08 Reset frees image/array after WADClose")
  Check(Bool(cache\Count = 0 And cache\Entries = 0 And cache\Capacity = 0),
        "WT08 reset Cache leaves no entry pointers/count")
  Check(Bool(WallTextureCacheCount(@cache) = 0), "WT08 reset accessor reports empty owned count 0")
  Check(Bool(WallTextureCacheImagePtr(@cache, 0) = 0 And
              FindString(WallTextureCacheLastError(), "out of range") > 0),
        "WT08 reset image accessor rejects entry 0 with diagnostic")
  Check(WallTextureCacheReset(@cache), "WT08 repeated Reset idempotent without double-free")

WT08Done:
  WallTextureCacheReset(@cache)
  MapLevelReset(@level)
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT09()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected fPnames.PNamesTable
  Protected fTextures.TextureCatalog
  Protected level.MapLevel
  Protected plan.WallSpanPlan
  Protected cache.WallTextureCache
  Protected frame.FrameBuffer
  Protected clip.WallVerticalClip
  Protected wadOk.i = #False
  Protected fullOk.i = #False
  Protected count.l = 0

  BeginCase("WT09", "Composition failure leaves cache/target safely recoverable")
  Check(ClipFrame(@clip, @frame), "WT09 canonical target frame/clip prepared")
  Check(Bool(frame\PixelCount = 64000), "WT09 target is exact 64,000 plane")
  FrameBufferClear(@frame, 17)
  If BrokenResourceWad("u0609.wad") = #False Or
     WADOpen(WallTexFixturePath("u0609.wad")) = #False
    Check(#False, "WT09 broken resource WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False Or
     BuildWallMap(@level, 0, 0, 0, 0, "-", "-", "TEXMID", 0, 0, 0) = #False Or
     CachePlan(@plan, 0, 0, -1, 0, 0, 1, 0) = #False
    Check(#False, "WT09 broken-catalog/map/plan prepared")
    Goto WT09Done
  EndIf
  Check(Bool(WallTextureCacheBuild(@level, @textures, @plan, 1, @cache) = #False),
        "WT09 malformed PATCHB makes cache compose fail")
  Check(Bool(FindString(WallTextureCacheLastError(), "compose") > 0),
        "WT09 cache failure carries compose diagnostic")
  Check(Bool(WallTextureCacheIsValid(@cache) And WallTextureCacheCount(@cache) = 0),
        "WT09 failed cache transactionally empty and reusable")
  Check(Bool(FrameBufferGetPixel(@frame, 0, 0) = 17 And FrameBufferGetPixel(@frame, 319, 199) = 17),
        "WT09 cache failure target untouched")
  Check(WallTextureCacheReset(@cache), "WT09 failed cache reset idempotent")
  WADClose()
  wadOk = #False
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
  If WallTexBuildStandardResourceWad("u0609full.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0609full.wad")) = #False
    Check(#False, "WT09 repaired resource WAD built/opened")
    Goto WT09Done
  EndIf
  fullOk = #True
  If WallTexDecodeWallCatalog(@fPnames, @fTextures) = #False
    Check(#False, "WT09 repaired catalog resolves")
    Goto WT09Done
  EndIf
  Check(WallTextureCacheBuild(@level, @fTextures, @plan, 1, @cache), "WT09 rebuilt cache succeeds after repair")
  If WallTextureCacheCount(@cache) = 1
    Check(#True, "WT09 recovered cache owns one TEXMID entry")
  Else
    Check(#False, "WT09 recovered cache owns one TEXMID entry")
  EndIf

WT09Done:
  WallTextureCacheReset(@cache)
  MapLevelReset(@level)
  FrameBufferReset(@frame)
  WallVerticalClipReset(@clip)
  If wadOk
    WADClose()
  EndIf
  If fullOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
  TextureCatalogReset(@fTextures)
  PNamesReset(@fPnames)
EndProcedure

Procedure WT10()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected plan.WallSpanPlan
  Protected cache.WallTextureCache
  Protected *image.TextureImage
  Protected wadOk.i = #False

  BeginCase("WT10", "Compose while WAD open, read owned pixels after close")
  If WallTexBuildStandardResourceWad("u0610.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0610.wad")) = #False
    Check(#False, "WT10 resource WAD built/opened")
    ProcedureReturn
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False Or
     BuildWallMap(@level, 1, 32, 96, 96, "TEXUP", "TEXLO", "TEXMID", 0, 0, 0) = #False Or
     CachePlan(@plan, 0, 0, 1, 1, 1, 1, 1) = #False
    Check(#False, "WT10 catalog/map/plan prepared")
    Goto WT10Done
  EndIf
  Check(WallTextureCacheBuild(@level, @textures, @plan, 1, @cache), "WT10 compose while WAD open")
  Check(Bool(WallTextureCacheCount(@cache) = 3), "WT10 three unique composed entries")
  WADClose()
  wadOk = #False
  Check(WallTextureCacheIsValid(@cache), "WT10 cache valid after close")
  Check(Bool(WallTextureCacheCount(@cache) = 3), "WT10 count survives WAD close")
  *image = WallTextureCacheImagePtr(@cache, WallTextureCacheFindIndex(@cache, 1))
  Check(Bool(*image <> 0 And *image\Magic = #TEXTURE_ImageMagic And *image\Pixels <> 0),
        "WT10 owned TEXMID image readable after close")
  If *image <> 0
    Check(Bool(TextureImageGetPixel(*image, 0, 0) = #TEXGOLD_PatchA), "WT10 post-close column0 A")
    Check(Bool(TextureImageGetPixel(*image, 32, 0) = #TEXGOLD_PatchB), "WT10 post-close column32 B")
    Check(Bool(TextureImageOpaqueCount(*image) = Int(*image\Width) * Int(*image\Height)),
          "WT10 post-close mask fully opaque")
  EndIf

WT10Done:
  WallTextureCacheReset(@cache)
  MapLevelReset(@level)
  If wadOk
    WADClose()
  EndIf
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
EndProcedure

Procedure WT11()
  Protected view.q = 0
  Protected normal.q = 0
  Protected ref.q = 0
  Protected hyp.l = 0
  Protected actualOffset.l = 0
  Protected actualCenter.q = 0
  Protected fixtOffset.l = 0
  Protected fixtCenter.q = 0
  Protected expectedOffset.l = 0
  Protected expectedCenter.q = 0
  Protected segBam.q = 0
  Protected expectedNormal.q = 0

  BeginCase("WT11", "Unsigned BAM normalangle and unclipped reference angle")
  If ScenePlanQ("TI01", 0, #UNIT_QViewAngle, @view) And
     ScenePlanQ("TI01", 0, #UNIT_QNormalAngle, @normal) And
     ScenePlanQ("TI01", 0, #UNIT_QReferenceAngle, @ref) And
     ScenePlanL("TI01", 0, #UNIT_PlanLHyp, @hyp) And
     ScenePlanL("TI01", 0, #UNIT_PlanLRawOffset, @fixtOffset) And
     ScenePlanQ("TI01", 0, #UNIT_QCenterAngle, @fixtCenter)
    Check(#True, "WT11 TI01 fixture plan fields readable")
  Else
    Check(#False, "WT11 TI01 fixture plan fields readable")
    ProcedureReturn
  EndIf
  Check(Bool(BamRawInUnsignedDomain(view) And BamRawInUnsignedDomain(normal) And
              BamRawInUnsignedDomain(ref)), "WT11 raw angles canonical unsigned BAM")
  segBam = Int(49152) << #FRACBITS
  expectedNormal = BamAdd(BamWrap32(segBam), #BAM_ANG90)
  Check(Bool(normal = expectedNormal), "WT11 raw seg angle 49152 normalangle source BAM")
  Check(WallTextureOffsetChecked(view, normal, ref, hyp, 5, -7, @actualOffset, @actualCenter),
        "WT11 production offset with unclipped reference")
  Check(Bool(actualOffset = fixtOffset And actualCenter = fixtCenter),
        "WT11 production rw_offset/center match oracle")
  Check(IOffset(view, normal, ref, hyp, 5, -7, @expectedOffset, @expectedCenter),
        "WT11 independent offset formula evaluates")
  Check(Bool(expectedOffset = fixtOffset And expectedCenter = fixtCenter),
        "WT11 independent formula matches oracle fields")
EndProcedure

Procedure WT12()
  Protected view.q = 0
  Protected normal.q = 0
  Protected ref.q = 0
  Protected hyp.l = 262144
  Protected offset.l = 0
  Protected center.q = 0
  Protected expected.l = 0
  Protected expectedCenter.q = 0
  Protected ok.i
  Protected sine.l = 0
  Protected i.i
  Protected product.l

  BeginCase("WT12", "Offsetangle unsigned/sign comparisons and ANG90 clamp")
  For i = 0 To 4
    Select i
      Case 0 : normal = 0 : ref = 0
      Case 1 : normal = #BAM_ANG45 : ref = 0
      Case 2 : normal = #BAM_ANG90 : ref = 0
      Case 3 : normal = #BAM_ANG180 : ref = 0
      Case 4 : normal = $FFFFFFFF : ref = 0
    EndSelect
    ok = IOffset(view, normal, ref, hyp, 0, 0, @expected, @expectedCenter)
    Check(ok, "WT12 case" + Str(i) + " independent formula evaluates")
    Check(WallTextureOffsetChecked(view, normal, ref, hyp, 0, 0, @offset, @center),
          "WT12 case" + Str(i) + " production helper accepts raw BAM")
    Check(Bool(ok And offset = expected And center = expectedCenter),
          "WT12 case" + Str(i) + " clamped/sign result matches formula")
  Next
  Check(Bool(BamSubtract(#BAM_ANG180, 0) = #BAM_ANG180), "WT12 equality ANG180 raw delta")
  sine = ISine(2048)
  Check(Bool(sine = 65535), "WT12 ANG90 equality finesine index2048 value 65535")
  product = IMul(hyp, sine)
  Check(Bool(product = 262140), "WT12 hyp*65535>>16 equality case product")
EndProcedure

Procedure WT13()
  Protected view.q = 0
  Protected normal.q = 0
  Protected ref.q = 0
  Protected hyp.l = 0
  Protected fixtOffset.l = 0
  Protected fixtCenter.q = 0
  Protected actual.l = 0
  Protected actualCenter.q = 0
  Protected expected.l = 0
  Protected expectedCenter.q = 0
  Protected shifted.l = 0

  BeginCase("WT13", "Signed fixed rw_offset and seg-side offsets")
  If ScenePlanQ("TI01", 0, #UNIT_QViewAngle, @view) And
     ScenePlanQ("TI01", 0, #UNIT_QNormalAngle, @normal) And
     ScenePlanQ("TI01", 0, #UNIT_QReferenceAngle, @ref) And
     ScenePlanL("TI01", 0, #UNIT_PlanLHyp, @hyp) And
     ScenePlanL("TI01", 0, #UNIT_PlanLRawOffset, @fixtOffset) And
     ScenePlanQ("TI01", 0, #UNIT_QCenterAngle, @fixtCenter)
    Check(#True, "WT13 TI01 fixture fields readable")
  Else
    Check(#False, "WT13 TI01 fixture fields readable")
    ProcedureReturn
  EndIf
  Check(WallTextureOffsetChecked(view, normal, ref, hyp, -3, 11, @actual, @actualCenter),
        "WT13 swapped raw additions accepted with fixed shifts")
  shifted = IAddLow(fixtOffset, IAddLow(IMapUnitFixed(-8), IMapUnitFixed(18)))
  Check(Bool(actual = shifted),
        "WT13 signed shifts: textureoffset 5->-3 and segoffset -7->11")
  Check(Bool(actualCenter = fixtCenter), "WT13 offsets do not alter centerangle")
  Check(IOffset(view, normal, ref, hyp, -3, 11, @expected, @expectedCenter),
        "WT13 independent swapped-offset formula evaluates")
  Check(Bool(expected = actual And expectedCenter = actualCenter),
        "WT13 production signed offset matches formula")
EndProcedure

Procedure WT14()
  Protected view.q = 0
  Protected normal.q = 0
  Protected ref.q = 0
  Protected hyp.l = 0
  Protected base.l = 0
  Protected texChange.l = 0
  Protected segChange.l = 0
  Protected center.q = 0
  Protected texShifted.l = 0
  Protected segShifted.l = 0

  BeginCase("WT14", "SIDEDEFS.textureoffset and SEGS.offset distinct contributions")
  If ScenePlanQ("TI01", 0, #UNIT_QViewAngle, @view) And
     ScenePlanQ("TI01", 0, #UNIT_QNormalAngle, @normal) And
     ScenePlanQ("TI01", 0, #UNIT_QReferenceAngle, @ref) And
     ScenePlanL("TI01", 0, #UNIT_PlanLHyp, @hyp)
    Check(#True, "WT14 TI01 angle/hyp fields readable")
  Else
    Check(#False, "WT14 TI01 angle/hyp fields readable")
    ProcedureReturn
  EndIf
  Check(WallTextureOffsetChecked(view, normal, ref, hyp, 5, -7, @base, @center), "WT14 baseline offsets")
  Check(WallTextureOffsetChecked(view, normal, ref, hyp, 12, -7, @texChange, @center),
        "WT14 textureoffset-only change accepted")
  texShifted = IAddLow(base, IMapUnitFixed(7))
  Check(Bool(texChange = texShifted), "WT14 textureoffset 5->12 adds exactly +7<<16 fixed")
  Check(WallTextureOffsetChecked(view, normal, ref, hyp, 5, 2, @segChange, @center),
        "WT14 segoffset-only change accepted")
  segShifted = IAddLow(base, IMapUnitFixed(9))
  Check(Bool(segChange = segShifted), "WT14 segoffset -7->2 adds exactly +9<<16 fixed")
  Check(Bool(texChange <> IAddLow(base, 7) And segChange <> IAddLow(base, 9)),
        "WT14 raw map units are not treated as fixed_t directly")
EndProcedure

Procedure WT15()
  Protected projection.Projection
  Protected fixtOffset.l = 0
  Protected fixtCenter.q = 0
  Protected fixtDistance.l = 0
  Protected xAngle.q = 0
  Protected fixed.l = 0
  Protected column.l = 0
  Protected expFixed.l = 0
  Protected expColumn.l = 0
  Protected x.i

  BeginCase("WT15", "Horizontal texture column at center and adjacent X")
  Check(ProjectionInitClassic(@projection), "WT15 classic projection initializes")
  If ScenePlanL("TI01", 0, #UNIT_PlanLRawOffset, @fixtOffset) And
     ScenePlanQ("TI01", 0, #UNIT_QCenterAngle, @fixtCenter) And
     ScenePlanL("TI01", 0, #UNIT_PlanLDistance, @fixtDistance)
    Check(#True, "WT15 fixture offset/center/distance readable")
  Else
    Check(#False, "WT15 fixture offset/center/distance readable")
    ProjectionReset(@projection)
    ProcedureReturn
  EndIf
  For x = 160 To 161
    If ProjectionGetXToViewAngle(@projection, x, @xAngle)
      Check(#True, "WT15 xtoviewangle x" + Str(x) + " readable")
    Else
      Check(#False, "WT15 xtoviewangle x" + Str(x) + " readable")
      Continue
    EndIf
    Check(WallTextureColumnChecked(fixtOffset, fixtCenter, xAngle, fixtDistance,
                                   @fixed, @column), "WT15 production column x" + Str(x))
    Check(IColumn(fixtOffset, fixtCenter, xAngle, fixtDistance, @expFixed, @expColumn),
          "WT15 independent column x" + Str(x))
    Check(Bool(fixed = expFixed And column = expColumn), "WT15 column x" + Str(x) + " matches oracle")
  Next
  ProjectionReset(@projection)
EndProcedure

Procedure WT16()
  Protected mask.l = 0
  Protected wrapped.l = 0
  Protected raw.l = 0
  Protected expected.l = 0
  Protected i.i

  BeginCase("WT16", "64-wide mask wrap positive/negative columns")
  Check(WallTextureWidthMaskChecked(64, @mask), "WT16 mask generated")
  Check(Bool(mask = 63), "WT16 64 mask 63")
  For i = 0 To 5
    Select i
      Case 0 : raw = 0 : expected = 0
      Case 1 : raw = 64 : expected = 0
      Case 2 : raw = 65 : expected = 1
      Case 3 : raw = -1 : expected = 63
      Case 4 : raw = -64 : expected = 0
      Case 5 : raw = -65 : expected = 63
    EndSelect
    If WallTextureColumnWrapChecked(raw, mask, 64, @wrapped)
      Check(Bool(wrapped = expected), "WT16 raw " + Str(raw) + " wraps " + Str(expected))
      Check(Bool(wrapped >= 0 And wrapped < 64), "WT16 wrapped bounded <64")
    Else
      Check(#False, "WT16 raw " + Str(raw) + " wrap accepted")
    EndIf
  Next
EndProcedure

Procedure WT17()
  Protected mask.l = 0
  Protected wrapped.l = 0
  Protected raw.l = 0
  Protected expected.l = 0
  Protected modulo.l = 0
  Protected i.i

  BeginCase("WT17", "96-wide vanilla mask differs from modulo 96")
  Check(WallTextureWidthMaskChecked(96, @mask), "WT17 mask generated")
  Check(Bool(mask = 63), "WT17 96 mask 63 not modulo")
  For i = 0 To 3
    Select i
      Case 0 : raw = 96 : expected = 32
      Case 1 : raw = 95 : expected = 31
      Case 2 : raw = 127 : expected = 63
      Case 3 : raw = 65 : expected = 1
    EndSelect
    If WallTextureColumnWrapChecked(raw, mask, 96, @wrapped)
      modulo = raw % 96
      Check(Bool(wrapped = expected), "WT17 raw " + Str(raw) + " &63 -> " + Str(expected))
      Check(Bool(wrapped <> modulo), "WT17 differs from modulo96 " + Str(modulo))
    Else
      Check(#False, "WT17 raw " + Str(raw) + " wrap accepted")
    EndIf
  Next
EndProcedure

Procedure WT18()
  Protected mask128.l = 0
  Protected mask256.l = 0
  Protected wrapped.l = 0
  Protected raw.l = 0
  Protected expected.l = 0
  Protected i.i

  BeginCase("WT18", "Width-mask edges for 128/256 textures")
  Check(Bool(WallTextureWidthMaskChecked(128, @mask128) And mask128 = 127), "WT18 128 mask 127")
  Check(Bool(WallTextureWidthMaskChecked(256, @mask256) And mask256 = 255), "WT18 256 mask 255")
  For i = 0 To 5
    Select i
      Case 0 : raw = 128 : expected = 0
      Case 1 : raw = 127 : expected = 127
      Case 2 : raw = -128 : expected = 0
      Case 3 : raw = 256 : expected = 0
      Case 4 : raw = 255 : expected = 255
      Case 5 : raw = -1 : expected = 255
    EndSelect
    If i <= 2
      If WallTextureColumnWrapChecked(raw, mask128, 128, @wrapped)
        Check(Bool(wrapped = expected), "WT18 128 edge raw " + Str(raw) + " -> " + Str(expected))
      Else
        Check(#False, "WT18 128 edge wrap accepted")
      EndIf
    Else
      If WallTextureColumnWrapChecked(raw, mask256, 256, @wrapped)
        Check(Bool(wrapped = expected), "WT18 256 edge raw " + Str(raw) + " -> " + Str(expected))
      Else
        Check(#False, "WT18 256 edge wrap accepted")
      EndIf
    EndIf
  Next
EndProcedure

Procedure WT19()
  Protected mask.l = 63
  Protected wrapped.l = 0
  Protected offSentinel.l = 1234567
  Protected centerSentinel.q = $1122334455667787
  Protected scaleSentinel.l = 7654321
  Protected fixedSentinel.l = -2
  Protected columnSentinel.l = -3
  Protected ok.i

  BeginCase("WT19", "Overflow/negative diagnostics untouched outputs")
  ok = WallTextureOffsetChecked(0, 0, 0, 262144, 32768, -7, @offSentinel, @centerSentinel)
  Check(Bool(ok = #False), "WT19 textureoffset 32768 signed16 domain rejected")
  Check(Bool(offSentinel = 1234567 And centerSentinel = $1122334455667787),
        "WT19 failed offset leaves outputs untouched")
  Check(Bool(FindString(WallTextureMappingLastError(), "textureoffset") > 0),
        "WT19 rejection names textureoffset conversion")
  ok = WallTextureColumnWrapChecked(0, mask, -1, @wrapped)
  Check(Bool(ok = #False), "WT19 negative width rejected")
  ok = WallTextureColumnWrapChecked(-2147483648, mask, 64, @wrapped)
  Check(Bool(ok And wrapped = 0), "WT19 extreme negative raw column maps bounded0")
  ok = WallTextureIscaleChecked(1, @scaleSentinel)
  Check(Bool(ok = #False), "WT19 scale1 out-of-contract quotient rejected")
  Check(Bool(scaleSentinel = 7654321), "WT19 failed iscale leaves output untouched")
  ok = WallTextureColumnChecked(0, 0, 0, -1, @fixedSentinel, @columnSentinel)
  Check(Bool(ok = #False), "WT19 negative distance rejected")
  Check(Bool(fixedSentinel = -2 And columnSentinel = -3), "WT19 failed column leaves outputs untouched")
  Check(Bool(FindString(WallTextureMappingLastError(), "distance") > 0), "WT19 failure names distance")
EndProcedure

Procedure WT20()
  Protected fixed.l = 0
  Protected column.l = 0
  Protected sentinelFixed.l = 77
  Protected sentinelColumn.l = 88
  Protected center.q = 0
  Protected xangle.q = 0
  Protected distance.l = #FRACUNIT
  Protected ok.i
  Protected tangent4095.l
  Protected expectedFixed.l = 0

  BeginCase("WT20", "centerangle+xtoviewangle boundary/table domain")
  center = $7FF80000
  xangle = 0
  tangent4095 = ITangent(4095)
  Check(Bool(tangent4095 <> -999999999), "WT20 pinned tangent index 4095 readable")
  Check(WallTextureColumnChecked(0, center, xangle, distance, @fixed, @column),
        "WT20 raw sum shifting to index 4095 accepted")
  expectedFixed.l = ISubLow(0, IMul(tangent4095, distance))
  Check(Bool(fixed = expectedFixed And column = expectedFixed >> #FRACBITS),
        "WT20 boundary fixed/column matches independent formula")

  center = $80000000
  ok = WallTextureColumnChecked(0, center, 0, distance, @sentinelFixed, @sentinelColumn)
  Check(Bool(ok = #False), "WT20 index 4096 outside finetangent rejected")
  Check(Bool(sentinelFixed = 77 And sentinelColumn = 88), "WT20 rejected index outputs untouched")
  Check(Bool(FindString(WallTextureMappingLastError(), "finetangent") > 0),
        "WT20 rejection names finetangent")

  center = 4294967296
  ok = WallTextureColumnChecked(0, center, 0, 1, @sentinelFixed, @sentinelColumn)
  Check(Bool(ok = #False), "WT20 centerangle outside unsigned BAM rejected")
  Check(Bool(sentinelFixed = 77 And sentinelColumn = 88), "WT20 invalid angle outputs untouched")
  Check(IColumn(0, $50000000, 0, distance, @fixed, @column),
        "WT20 adjacent 0+$50000000 sum stays in finite tangent domain")
EndProcedure

Procedure WT21()
  Protected iscale.l = 0
  Protected expected.l = 0
  Protected ok.i

  BeginCase("WT21", "dc_iscale = 0xFFFFFFFF / scale exact truncation")
  ok = WallTextureIscaleChecked(256, @iscale)
  Check(ok, "WT21 scale 256 iscale accepted")
  Check(Bool(iscale = #TEXGOLD_Iscale256_Value), "WT21 scale256 quotient 16777215 oracle")
  ok = IIscale(256, @expected)
  Check(Bool(ok And expected = iscale), "WT21 production quotient equals independent division")
  ok = WallTextureIscaleChecked(512, @iscale)
  Check(Bool(ok And iscale = #TEXGOLD_Iscale512_Value), "WT21 scale512 quotient 8388607 oracle")
  ok = WallTextureIscaleChecked(2, @iscale)
  Check(Bool(ok And iscale = #TEXGOLD_Iscale2_Value), "WT21 scale2 signed boundary 2147483647")
  ok = WallTextureIscaleChecked(1, @iscale)
  Check(Bool(ok = #False), "WT21 scale1 out-of-contract quotient rejected")
  Check(Bool(FindString(WallTextureMappingLastError(), "scale") > 0), "WT21 iscale rejection names scale")
EndProcedure

Procedure WT22()
  Protected iscale.l = 0
  Protected expectedIscale.l = 0
  Protected frac.l = 0
  Protected expectedFrac.l = 0
  Protected mid.l = 5505024
  Protected negativeMid.l = -327680
  Protected ok.i

  BeginCase("WT22", "Initial frac around centery=100 with signed negative")
  ok = IIscale(104857, @expectedIscale)
  Check(ok, "WT22 production-plan scale 104857 admitted")
  ok = WallTextureIscaleChecked(104857, @iscale)
  Check(Bool(ok And iscale = expectedIscale), "WT22 exact quotient for scale 104857")
  Check(WallTextureFracChecked(mid, 0, 100, iscale, @frac), "WT22 frac at y=0 accepted")
  expectedFrac = IFrac(mid, 0, 100, iscale)
  Check(Bool(frac = expectedFrac), "WT22 y0 frac texturemid + (0-100)*iscale exact")
  Check(WallTextureFracChecked(mid, 120, 100, iscale, @frac), "WT22 frac at y=120 accepted")
  expectedFrac = IFrac(mid, 120, 100, iscale)
  Check(Bool(frac = expectedFrac), "WT22 y120 positive product low32 formula")
  Check(WallTextureFracChecked(negativeMid, 0, 100, iscale, @frac), "WT22 negative texturemid frac")
  expectedFrac = IFrac(negativeMid, 0, 100, iscale)
  Check(Bool(frac < 0 And frac = expectedFrac), "WT22 signed negative frac exact")
EndProcedure

Procedure WT23()
  Protected iscale.l = 40960
  Protected frac.l = 0
  Protected expected.l = 0
  Protected start.l = 5505024
  Protected i.i

  BeginCase("WT23", "Frac advances once per inclusive painted row")
  expected = IFrac(start, 0, 100, iscale)
  frac = expected
  For i = 1 To 5
    frac = WallTextureFracAdvance(frac, iscale)
    expected = IAddLow(expected, iscale)
  Next
  Check(Bool(frac = expected), "WT23 five inclusive advances equal five iscale additions")
  Check(Bool(frac = IFrac(start, 5, 100, iscale)), "WT23 final frac equals closed y5 formula")
EndProcedure

Procedure WT24()
  Protected row.l = 0
  Protected expected.l = 0
  Protected image.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected frac.l
  Protected i.i

  BeginCase("WT24", "128-row source &127 wrap positive/negative frac")
  For i = 0 To 4
    Select i
      Case 0 : frac = 0 : expected = 0
      Case 1 : frac = 127 << 16 : expected = 127
      Case 2 : frac = 128 << 16 : expected = 0
      Case 3 : frac = -65536 : expected = 127
      Case 4 : frac = -1 : expected = 127
    EndSelect
    row = WallTextureSourceRow128(frac)
    Check(Bool(row = expected), "WT24 source row frac case" + Str(i) + " = " + Str(expected))
    Check(Bool(row = ISourceRow(frac)), "WT24 row matches independent shift/AND")
  Next
  Check(Bool(BuildImage(@image, 64, 128, 37, 1)), "WT24 128-high synthetic image built")
  Check(WallTextureSampleChecked(@image, 0, 127, @sourceRow, @opaque, @pixel, @fallback),
        "WT24 row128 127 sample accepted")
  Check(Bool(sourceRow = 127 And opaque = 1 And pixel = 37 And fallback = 0),
        "WT24 height128 preserves exact &127 row, no fallback")
  TextureImageReset(@image)
EndProcedure

Procedure WT25()
  Protected row.l = 0
  Protected fb.l = 0
  Protected image.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected ok.i

  BeginCase("WT25", "32-high source bounded fallback deterministic")
  ok = WallTextureSourceRowBounded(127, 32, @row, @fb)
  Check(ok, "WT25 32-high row127 bounded accepted")
  Check(Bool(row = #TEXGOLD_SourceRow32_127 And fb = 1), "WT25 127%32=31 fallback oracle")
  ok = IBoundedRow(127, 32, @row, @fb)
  Check(Bool(ok And row = 31 And fb = 1), "WT25 independent modulo32 equals production")
  Check(Bool(BuildImage(@image, 32, 32, 73, 1)), "WT25 32-high image built")
  Check(WallTextureSampleChecked(@image, 0, 127, @sourceRow, @opaque, @pixel, @fallback),
        "WT25 32-high sample accepted")
  Check(Bool(sourceRow = 31 And fallback = 1 And pixel = 73), "WT25 sample reads bounded row31 fallback")
  TextureImageReset(@image)
EndProcedure

Procedure WT26()
  Protected row.l = 0
  Protected fb.l = 0
  Protected image.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected ok.i

  BeginCase("WT26", "64-high source bounded fallback deterministic")
  ok = WallTextureSourceRowBounded(127, 64, @row, @fb)
  Check(ok, "WT26 64-high row127 bounded accepted")
  Check(Bool(row = #TEXGOLD_SourceRow64_127 And fb = 1), "WT26 127%64=63 oracle")
  ok = IBoundedRow(127, 64, @row, @fb)
  Check(Bool(ok And row = 63 And fb = 1), "WT26 independent modulo64 equals production")
  Check(Bool(BuildImage(@image, 64, 64, 19, 1)), "WT26 64-high image built")
  Check(WallTextureSampleChecked(@image, 0, 127, @sourceRow, @opaque, @pixel, @fallback),
        "WT26 sample accepted")
  Check(Bool(sourceRow = 63 And fallback = 1 And pixel = 19), "WT26 reads row63 fallback")
  TextureImageReset(@image)
EndProcedure

Procedure WT27()
  Protected row.l = 0
  Protected fb.l = 0
  Protected image.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected ok.i

  BeginCase("WT27", "72-high source bounded fallback deterministic")
  ok = WallTextureSourceRowBounded(127, 72, @row, @fb)
  Check(ok, "WT27 72-high row127 bounded accepted")
  Check(Bool(row = #TEXGOLD_SourceRow72_127 And fb = 1), "WT27 127%72=55 oracle")
  ok = IBoundedRow(127, 72, @row, @fb)
  Check(Bool(ok And row = 55 And fb = 1), "WT27 independent modulo72 equals production")
  Check(Bool(BuildImage(@image, 96, 72, 73, 1)), "WT27 96x72 image built")
  Check(WallTextureSampleChecked(@image, 0, 127, @sourceRow, @opaque, @pixel, @fallback),
        "WT27 96-wide 72-high sample accepted")
  Check(Bool(sourceRow = 55 And fallback = 1), "WT27 row55 bounded fallback")
  TextureImageReset(@image)
EndProcedure

Procedure WT28()
  Protected row.l = 0
  Protected fb.l = 0
  Protected image.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected ok.i

  BeginCase("WT28", "256-high source &127 documented 128-row difference")
  ok = WallTextureSourceRowBounded(127, 256, @row, @fb)
  Check(ok, "WT28 256-high row127 admitted")
  Check(Bool(row = #TEXGOLD_SourceRow256_127 And fb = 0), "WT28 height>=128 preserves 127 no fallback")
  ok = IBoundedRow(127, 256, @row, @fb)
  Check(Bool(ok And row = 127 And fb = 0), "WT28 independent >=128 pass-through")
  Check(Bool(BuildImage(@image, 64, 256, 37, 1)), "WT28 64x256 image built")
  Check(WallTextureSampleChecked(@image, 0, 127, @sourceRow, @opaque, @pixel, @fallback),
        "WT28 256-high sample accepted")
  Check(Bool(sourceRow = 127 And fallback = 0), "WT28 only first 128 rows sampled as C &127")
  TextureImageReset(@image)
EndProcedure

Procedure WT29()
  Protected image.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0

  BeginCase("WT29", "Opaque mask includes palette index 0 and 255")
  Check(Bool(BuildImage(@image, 1, 2, 0, 1)), "WT29 opaque 1x2 image built with index0")
  PokeA(image\Pixels + 1, 255)
  Check(Bool(PeekA(image\Mask + 1) = 1), "WT29 row1 mask opaque1")
  Check(WallTextureSampleChecked(@image, 0, 0, @sourceRow, @opaque, @pixel, @fallback),
        "WT29 row0 sample accepted")
  Check(Bool(opaque = 1 And pixel = 0 And fallback = 1),
        "WT29 opaque palette index0 ordinary; 2-high bounded fallback flagged")
  Check(WallTextureSampleChecked(@image, 0, 1, @sourceRow, @opaque, @pixel, @fallback),
        "WT29 row1 sample accepted")
  Check(Bool(opaque = 1 And pixel = 255), "WT29 palette index255 stays opaque, no sentinel")
  TextureImageReset(@image)
EndProcedure

Procedure WT30()
  Protected image.TextureImage
  Protected malformed.TextureImage
  Protected sourceRow.l = 0
  Protected opaque.l = 0
  Protected pixel.l = 0
  Protected fallback.l = 0
  Protected sentinelRow.l = 91
  Protected sentinelOpaque.l = 92
  Protected sentinelPixel.l = 93
  Protected sentinelFallback.l = 94
  Protected ok.i

  BeginCase("WT30", "Transparent-mask hole handled explicitly; malformed mask rejected")
  Check(Bool(BuildImage(@image, 1, 3, 37, 1)), "WT30 mask-hole image built")
  PokeA(image\Mask + 0, 0)
  PokeA(image\Pixels + 0, 0)
  Check(WallTextureSampleChecked(@image, 0, 0, @sourceRow, @opaque, @pixel, @fallback),
        "WT30 mask-hole sample accepted")
  Check(Bool(opaque = 0 And pixel = 0), "WT30 mask0 uncovered flag separate from ordinary index0")
  Check(WallTextureSampleChecked(@image, 0, 1, @sourceRow, @opaque, @pixel, @fallback),
        "WT30 adjacent covered row sample")
  Check(Bool(opaque = 1 And pixel = 37), "WT30 adjacent row opaque37")
  Check(Bool(BuildImage(@malformed, 1, 3, 37, 1)), "WT30 corrupt-mask image built")
  PokeA(malformed\Mask + 0, 2)
  ok = WallTextureSampleChecked(@malformed, 0, 0, @sentinelRow, @sentinelOpaque,
                                @sentinelPixel, @sentinelFallback)
  Check(Bool(ok = #False), "WT30 non-0/1 mask byte rejected")
  Check(Bool(sentinelRow = 91 And sentinelOpaque = 92 And sentinelPixel = 93 And sentinelFallback = 94),
        "WT30 malformed mask leaves outputs untouched")
  Check(Bool(FindString(WallTextureMappingLastError(), "mask") > 0), "WT30 failure names opacity mask")
  TextureImageReset(@image)
  TextureImageReset(@malformed)
EndProcedure

Procedure WT31()
  Protected worldTop.l = 5701632
  Protected floorFixed.l = 1048576
  Protected viewZ.l = 2686976
  Protected heightFixed.l = 8388608
  Protected worldTopAlt.l = 6291456
  Protected heightAlt.l = 4718592
  Protected rowAlt.l = 0
  Protected mid.l = 0
  Protected expectedAlt.l = 0
  Protected ok.i

  BeginCase("WT31", "One-sided middle default pegging")
  ok = WallTextureMidOneSidedChecked(worldTop, floorFixed, viewZ, heightFixed, 0, 0, @mid)
  Check(ok, "WT31 one-sided default peg accepted")
  Check(Bool(mid = worldTop), "WT31 default mid = worldtop")
  Check(Bool(IMapUnitFixed(0) = 0), "WT31 zero rowoffset no fixed units")
  ; Default branch: alternate front ceiling/worldtop, different texture height
  ; (unused by the source formula) and nonzero rowoffset, independently derived.
  rowAlt = IMapUnitFixed(11)
  ok = WallTextureMidOneSidedChecked(worldTopAlt, floorFixed, viewZ, heightAlt, 11, 0, @mid)
  expectedAlt = IAddLow(worldTopAlt, rowAlt)
  Check(Bool(ok And mid = expectedAlt),
        "WT31 default alternate ceiling/height/rowoffset = worldtop+row")
  Check(Bool(expectedAlt <> worldTop), "WT31 alternate default differs from first worldtop/row")
EndProcedure

Procedure WT32()
  Protected worldTop.l = 5701632
  Protected floorFixed.l = 1048576
  Protected viewZ.l = 2686976
  Protected heightFixed.l = 8388608
  Protected floorAlt.l = 2097152
  Protected heightAlt.l = 4194304
  Protected rowAlt.l = 0
  Protected mid.l = 0
  Protected vtop.l = 0
  Protected vtopAlt.l = 0
  Protected expected.l = 0
  Protected expectedAlt.l = 0
  Protected ok.i

  BeginCase("WT32", "One-sided middle ML_DONTPEGBOTTOM alignment")
  ok = WallTextureMidOneSidedChecked(worldTop, floorFixed, viewZ, heightFixed, 0,
                                     #MAP_ML_DONTPEGBOTTOM, @mid)
  Check(ok, "WT32 DONTPEGBOTTOM accepted")
  vtop = IAddLow(floorFixed, heightFixed)
  expected = ISubLow(vtop, viewZ)
  Check(Bool(mid = expected), "WT32 bottom-peg mid = (floor+texheight)-viewz")
  Check(Bool(mid <> worldTop), "WT32 bottom-peg differs from worldtop for floor16")
  ; Bottom branch: different floorheight(32)/textureheight(64)/negative rowoffset,
  ; independently derived from the original floor+textureheight-viewz formula.
  floorAlt = IMapUnitFixed(32)
  heightAlt = IMapUnitFixed(64)
  rowAlt = IMapUnitFixed(-9)
  ok = WallTextureMidOneSidedChecked(worldTop, floorAlt, viewZ, heightAlt, -9,
                                     #MAP_ML_DONTPEGBOTTOM, @mid)
  vtopAlt = IAddLow(floorAlt, heightAlt)
  expectedAlt = IAddLow(ISubLow(vtopAlt, viewZ), rowAlt)
  Check(Bool(ok And mid = expectedAlt),
        "WT32 bottom alternate floor32/height64/rowoffset-9 formula")
  Check(Bool(expectedAlt <> expected), "WT32 bottom alternate differs from first values")
EndProcedure

Procedure WT33()
  Protected worldTop.l = 5701632
  Protected floorFixed.l = 1048576
  Protected viewZ.l = 2686976
  Protected heightFixed.l = 8388608
  Protected mid.l = 0
  Protected expected.l = 0
  Protected row.l = IMapUnitFixed(-3)
  Protected ok.i

  BeginCase("WT33", "Middle sidedef rowoffset including negative raw map units")
  ok = WallTextureMidOneSidedChecked(worldTop, floorFixed, viewZ, heightFixed, -3, 0, @mid)
  expected = IAddLow(worldTop, row)
  Check(Bool(ok And mid = expected), "WT33 rowoffset -3 shifts worldtop -3<<16 fixed")
  ok = WallTextureMidOneSidedChecked(worldTop, floorFixed, viewZ, heightFixed, 17,
                                     #MAP_ML_DONTPEGBOTTOM, @mid)
  row = IMapUnitFixed(17)
  expected = IAddLow(ISubLow(IAddLow(floorFixed, heightFixed), viewZ), row)
  Check(Bool(ok And mid = expected), "WT33 positive17 rowoffset added after bottom-peg")
  Check(Bool(row = 1114112), "WT33 raw17 rowoffset = 17<<16 fixed")
EndProcedure

Procedure WT34()
  Protected worldTop.l = 5701632
  Protected backCeil.l = 6291456
  Protected viewZ.l = 2686976
  Protected heightFixed.l = 4718592
  Protected mid.l = 0
  Protected expected.l = 0
  Protected row.l = 0
  Protected rowAlt.l = 0
  Protected expectedAlt.l = 0
  Protected ok.i

  BeginCase("WT34", "Two-sided upper default vs ML_DONTPEGTOP")
  ok = WallTextureMidUpperChecked(worldTop, backCeil, viewZ, heightFixed, 0, 0, @mid)
  expected = ISubLow(IAddLow(backCeil, heightFixed), viewZ)
  Check(Bool(ok And mid = expected), "WT34 upper default = backceiling+texheight-viewz")
  Check(Bool(expected <> worldTop), "WT34 default upper differs from worldtop")
  ok = WallTextureMidUpperChecked(worldTop, backCeil, viewZ, heightFixed, 0,
                                  #MAP_ML_DONTPEGTOP, @mid)
  Check(Bool(ok And mid = worldTop), "WT34 DONTPEGTOP upper = worldtop")
  ok = WallTextureMidUpperChecked(worldTop, backCeil, viewZ, heightFixed, -8, 0, @mid)
  row = IMapUnitFixed(-8)
  expected = IAddLow(ISubLow(IAddLow(backCeil, heightFixed), viewZ), row)
  Check(Bool(ok And mid = expected), "WT34 default upper + negative rowoffset fixed")
  ; DONTPEGTOP branch with positive rowoffset and distinct back ceiling argument;
  ; the source upper anchor is worldtop regardless of back ceiling/textureheight.
  rowAlt = IMapUnitFixed(17)
  ok = WallTextureMidUpperChecked(worldTop, 6291456, viewZ, 4718592, 17,
                                  #MAP_ML_DONTPEGTOP, @mid)
  expectedAlt = IAddLow(worldTop, rowAlt)
  Check(Bool(ok And mid = expectedAlt), "WT34 DONTPEGTOP upper + rowoffset17 = worldtop+row")
  Check(Bool(expectedAlt <> worldTop), "WT34 DONTPEGTOP alternate differs from bare worldtop")
EndProcedure

Procedure WT35()
  Protected worldTop.l = 5701632
  Protected worldLow.l = -589824
  Protected mid.l = 0
  Protected expected.l = 0
  Protected row.l = 0
  Protected rowNeg.l = 0
  Protected expectedNeg.l = 0
  Protected ok.i

  BeginCase("WT35", "Two-sided lower default vs ML_DONTPEGBOTTOM")
  ok = WallTextureMidLowerChecked(worldTop, worldLow, 0, 0, @mid)
  Check(Bool(ok And mid = worldLow), "WT35 lower default mid = worldlow")
  ok = WallTextureMidLowerChecked(worldTop, worldLow, 0, #MAP_ML_DONTPEGBOTTOM, @mid)
  Check(Bool(ok And mid = worldTop), "WT35 DONTPEGBOTTOM lower mid = worldtop")
  Check(Bool(worldLow <> worldTop), "WT35 worldlow/worldtop differ")
  ok = WallTextureMidLowerChecked(worldTop, worldLow, 5, #MAP_ML_DONTPEGBOTTOM, @mid)
  row = IMapUnitFixed(5)
  expected = IAddLow(worldTop, row)
  Check(Bool(ok And mid = expected), "WT35 bottom-peg + raw5 rowoffset fixed")
  ; Default lower branch with negative rowoffset; source anchor is worldlow.
  rowNeg = IMapUnitFixed(-3)
  ok = WallTextureMidLowerChecked(worldTop, worldLow, -3, 0, @mid)
  expectedNeg = IAddLow(worldLow, rowNeg)
  Check(Bool(ok And mid = expectedNeg), "WT35 lower default + raw-3 rowoffset fixed")
  Check(Bool(expectedNeg <> worldLow), "WT35 default rowoffset shifts worldlow")
EndProcedure

Procedure WT36()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected plan.WallSpanPlan
  Protected texturePlan.WallTextureSpanPlan
  Protected cache.WallTextureCache
  Protected clip.WallVerticalClip
  Protected frame.FrameBuffer
  Protected tally.WallTextureDrawTally
  Protected projection.Projection
  Protected rawOff.l = 0
  Protected center.q = 0
  Protected distance.l = 0
  Protected scale1.l = 0
  Protected light.l = 0
  Protected ceil.l = 0
  Protected floor.l = 0
  Protected pixel.l

  BeginCase("WT36", "Upper+lower tiers one column no accidental middle fill")
  Check(BuildColormapSet(@colormap, 32, 17, 9), "WT36 synthetic COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT36 scalelight table built")
  Check(ManualCacheBegin(@cache, 2), "WT36 two-entry manual cache initialized")
  Check(ManualCacheImage(@cache, 0, 2, 96, 72, 73, 1), "WT36 upper entry 96x72 pixel73")
  Check(ManualCacheImage(@cache, 1, 3, 64, 64, 19, 1), "WT36 lower entry 64x64 pixel19")
  If ScenePlanL("TI02", 1, #UNIT_PlanLRawOffset, @rawOff) And
     ScenePlanQ("TI02", 1, #UNIT_QCenterAngle, @center) And
     ScenePlanL("TI02", 1, #UNIT_PlanLDistance, @distance) And
     ScenePlanL("TI02", 1, #UNIT_PlanLScale1, @scale1) And
     ScenePlanL("TI02", 1, #UNIT_PlanLLightNum, @light)
    Check(#True, "WT36 TI02 fixture geometry fields readable")
  Else
    Check(#False, "WT36 TI02 fixture fields readable")
    Goto WT36Done
  EndIf
  Check(LegacyPlanForDraw(@plan, 160, 160, 0, 1, 1, 0, 0, 0,
                          scale1, 0, -4095, 815104, 0, 0,
                          245760, 569345, 0, 0, rawOff, center, distance, light),
        "WT36 one-column upper+lower plan prepared")
  Check(TexturePlanForDraw(@texturePlan, 1, 1, 0, -1, 0, 1,
                           0, 0, 0, 0, 0, 0, 96, 72, 63, 64, 64, 63,
                           rawOff, center, light, -1, 2, 3),
        "WT36 texture plan upper/lower slots, no middle")
  Check(ProjectionInitClassic(@projection), "WT36 canonical projection initializes")
  Check(ClipFrame(@clip, @frame), "WT36 clip/frame prepared")
  Check(WallTextureDrawTallyReset(@tally), "WT36 tally reset")
  Check(TexturedWallDrawSpan(@frame, @plan, @texturePlan, @cache,
                             @projection, @table, @colormap, @clip, @tally),
        "WT36 textured span draws upper/lower, no middle fill")
  pixel = FrameBufferGetPixel(@frame, 160, 0)
  Check(Bool(pixel <> 0), "WT36 upper band row0 painted")
  Check(Bool(FrameBufferGetPixel(@frame, 160, 61) = 0), "WT36 middle gap row61 background")
  Check(Bool(FrameBufferGetPixel(@frame, 160, 139) = 0), "WT36 middle gap row139 background")
  pixel = FrameBufferGetPixel(@frame, 160, 140)
  Check(Bool(pixel <> 0), "WT36 lower band row140 painted")
  Check(Bool(tally\MiddlePixels = 0 And tally\MiddleRanges = 0), "WT36 zero middle pixels/ranges")
  Check(Bool(tally\UpperPixels = 61 And tally\LowerPixels = 60 And tally\DrawnPixels = 121),
        "WT36 upper61/lower60 total writes121")
  ceil = PeekL(clip\Ceiling + 160 * SizeOf(Long))
  floor = PeekL(clip\Floor + 160 * SizeOf(Long))
  Check(Bool(ceil = 60 And floor = 140), "WT36 shared clip upper60/lower140")

WT36Done:
  WallTextureDrawTallyReset(@tally)
  WallVerticalClipReset(@clip)
  FrameBufferReset(@frame)
  WallTextureCacheReset(@cache)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
  ProjectionReset(@projection)
EndProcedure

Procedure WT37()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected plan.WallSpanPlan
  Protected texturePlan.WallTextureSpanPlan
  Protected cache.WallTextureCache
  Protected clip.WallVerticalClip
  Protected frame.FrameBuffer
  Protected tally.WallTextureDrawTally
  Protected projection.Projection
  Protected nonzero.l = 0
  Protected r.i
  Protected ceil.l = 0
  Protected floor.l = 0

  BeginCase("WT37", "Open portal/mark-only branches preserve black gap")
  Check(BuildColormapSet(@colormap, 32, 17, 9), "WT37 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT37 light table built")
  Check(ManualCacheBegin(@cache, 0), "WT37 empty direct cache initialized")
  Check(LegacyPlanForDraw(@plan, 160, 160, 0, 0, 0, 0, 1, 1,
                          104857, 0, -4095, 815104, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        "WT37 mark-only one-sided solid plan prepared")
  Check(EmptyTexturePlan(@plan, @texturePlan), "WT37 empty texture plan identity prepared")
  Check(ProjectionInitClassic(@projection), "WT37 canonical projection initializes")
  Check(ClipFrame(@clip, @frame), "WT37 clip/frame prepared")
  Check(WallTextureDrawTallyReset(@tally), "WT37 tally reset")
  Check(TexturedWallDrawSpan(@frame, @plan, @texturePlan, @cache,
                             @projection, @table, @colormap, @clip, @tally),
        "WT37 mark-only span draws no texture")
  For r = 0 To 199
    If FrameBufferGetPixel(@frame, 160, r) <> 0
      nonzero + 1
    EndIf
  Next
  Check(Bool(nonzero = 0), "WT37 all 200 portal-column rows remain index 0")
  Check(Bool(tally\DrawnPixels = 0 And tally\TextureColumnsComputed = 0), "WT37 no painted pixels/coords")
  Check(Bool(tally\EmptyColumns = 1 And tally\DrawRanges = 0), "WT37 empty/mark-only accounting")
  ceil = PeekL(clip\Ceiling + 160 * SizeOf(Long))
  floor = PeekL(clip\Floor + 160 * SizeOf(Long))
  Check(Bool(ceil = -1 And floor = 200), "WT37 mark ceiling -1/floor200 clip updates")
  WallTextureDrawTallyReset(@tally)
  WallVerticalClipReset(@clip)
  FrameBufferReset(@frame)
  WallTextureCacheReset(@cache)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
  ProjectionReset(@projection)
EndProcedure

Procedure WT38()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected plan.WallSpanPlan
  Protected texturePlan.WallTextureSpanPlan
  Protected cache.WallTextureCache
  Protected clip.WallVerticalClip
  Protected frame.FrameBuffer
  Protected tally.WallTextureDrawTally
  Protected span.WallSpan
  Protected spanCount.l = 0
  Protected ready.i = #False
  Protected closed.l = 0
  Protected markFloor.l = 0
  Protected markCeil.l = 0

  BeginCase("WT38", "Closed door front/back heights and clip updates")
  Check(BuildWallMap(@level, 1, 128, 128, 128, "-", "-", "-", 0, 0, 0),
        "WT38 closed-door two-sided map built")
  Check(WallViewSetMapUnits(@view, 0, 0, 0, 0), "WT38 synthetic view set")
  Check(ProjectionInitClassic(@projection), "WT38 projection initializes")
  Check(WallVisibilityBuild(@level, @view\Camera, @projection, 0, 0, @visibility),
        "WT38 closed door visibility built")
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanCount > 0), "WT38 closed-door visible span count")
  If WallVisibilityGetSpan(@visibility, 0, @span\Subsector, @span\Seg, @span\Linedef,
                           @span\Side, @span\FrontSector, @span\BackSector,
                           @span\FirstX, @span\LastX, @span\Kind)
    ready = WallProjectSpanChecked(@level, 0, 0, @projection, 0, 0, 0, 2686976,
                                   0, @span, @plan)
    If ready = #False
      PrintN("diagnostic: WT38 plan err=" + WallProjectLastError())
    EndIf
    Check(Bool(ready), "WT38 closed-door WallProject plan built")
  Else
    Check(#False, "WT38 closed-door span read")
    Goto WT38Done
  EndIf
  If ready
    closed = plan\ClosedDoor : markFloor = plan\MarkFloor : markCeil = plan\MarkCeiling
    Check(Bool(closed = 1), "WT38 backfloor>=frontceiling closed-door flag")
    Check(Bool(markFloor = 1 And markCeil = 1), "WT38 closed door forces both plane marks")
    Check(Bool(plan\TopTier = 0 And plan\BottomTier = 0), "WT38 equal128 heights expose no upper/lower")
  EndIf
  Check(BuildColormapSet(@colormap, 32, 17, 9), "WT38 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT38 light table built")
  Check(ManualCacheBegin(@cache, 0), "WT38 empty cache for absent tiers")
  Check(EmptyTexturePlan(@plan, @texturePlan), "WT38 texture plan copies closed-door identity")
  Check(ClipFrame(@clip, @frame), "WT38 clip/frame prepared")
  Check(WallTextureDrawTallyReset(@tally), "WT38 tally reset")
  If ready
    Check(TexturedWallDrawSpan(@frame, @plan, @texturePlan, @cache,
                               @projection, @table, @colormap, @clip, @tally),
          "WT38 closed-door mark-only span draws no fill")
  Else
    Check(#False, "WT38 closed-door draw attempted without plan")
  EndIf
  Check(Bool(tally\DrawnPixels = 0 And tally\TextureColumnsComputed = 0),
        "WT38 closed door synthetic absence paints zero pixels")
  Check(Bool(markFloor = 1 And markCeil = 1), "WT38 plan plane marks remain authoritative")

WT38Done:
  WallTextureDrawTallyReset(@tally)
  WallVerticalClipReset(@clip)
  FrameBufferReset(@frame)
  WallTextureCacheReset(@cache)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
  WallVisibilityReset(@visibility)
  WallViewReset(@view)
  ProjectionReset(@projection)
  MapLevelReset(@level)
EndProcedure

Procedure WT39()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected plan.WallSpanPlan
  Protected texturePlan.WallTextureSpanPlan
  Protected cache.WallTextureCache
  Protected clip.WallVerticalClip
  Protected frame.FrameBuffer
  Protected tally.WallTextureDrawTally
  Protected projection.Projection
  Protected rawOff.l = 0
  Protected center.q = 0
  Protected distance.l = 0
  Protected scale1.l = 0
  Protected light.l = 0
  Protected midMid.l = 0
  Protected ceil.l = 0
  Protected floor.l = 0

  BeginCase("WT39", "One-column wall span with scaleStep=0")
  Check(BuildColormapSet(@colormap, 32, 17, 9), "WT39 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT39 light table built")
  Check(ManualCacheBegin(@cache, 1), "WT39 one-entry TEXMID cache")
  Check(ManualCacheImage(@cache, 0, 1, 64, 128, 37, 1), "WT39 cache TEXMID 64x128")
  If ScenePlanL("TI01", 0, #UNIT_PlanLRawOffset, @rawOff) And
     ScenePlanQ("TI01", 0, #UNIT_QCenterAngle, @center) And
     ScenePlanL("TI01", 0, #UNIT_PlanLDistance, @distance) And
     ScenePlanL("TI01", 0, #UNIT_PlanLScale1, @scale1) And
     ScenePlanL("TI01", 0, #UNIT_PlanLLightNum, @light) And
     ScenePlanL("TI01", 0, #UNIT_PlanLMidTextureMid, @midMid)
    Check(#True, "WT39 TI01 fixture middle fields readable")
  Else
    Check(#False, "WT39 fixture fields readable")
    Goto WT39Done
  EndIf
  Check(LegacyPlanForDraw(@plan, 160, 160, 0, 0, 0, 1, 0, 0,
                          scale1, 0, -4095, 815104, 0, 0, 0, 0, 0, 0,
                          rawOff, center, distance, light),
        "WT39 one-column solid middle plan prepared")
  Check(TexturePlanForDraw(@texturePlan, 1, 1, 0, 0, -1, -1,
                           midMid, 0, 0, 64, 128, 63, 0, 0, 0, 0, 0, 0,
                           rawOff, center, light, 1, -1, -1),
        "WT39 texture plan middle slot TEXMID")
  Check(ProjectionInitClassic(@projection), "WT39 canonical projection initializes")
  Check(ClipFrame(@clip, @frame), "WT39 clip/frame prepared")
  Check(WallTextureDrawTallyReset(@tally), "WT39 tally reset")
  Check(TexturedWallDrawSpan(@frame, @plan, @texturePlan, @cache,
                             @projection, @table, @colormap, @clip, @tally),
        "WT39 scaleStep0 one-column span draws")
  Check(Bool(tally\ProcessedColumns = 1), "WT39 processed exactly one column")
  Check(Bool(tally\MiddlePixels = 200 And tally\MiddleRanges = 1), "WT39 200 middle rows one range")
  Check(Bool(FrameBufferGetPixel(@frame, 159, 0) = 0 And FrameBufferGetPixel(@frame, 161, 0) = 0),
        "WT39 neighbouring columns remain background")
  ceil = PeekL(clip\Ceiling + 160 * SizeOf(Long))
  floor = PeekL(clip\Floor + 160 * SizeOf(Long))
  Check(Bool(ceil = 200 And floor = -1), "WT39 one-sided middle closes column clip 200/-1")

WT39Done:
  WallTextureDrawTallyReset(@tally)
  WallVerticalClipReset(@clip)
  FrameBufferReset(@frame)
  WallTextureCacheReset(@cache)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
  ProjectionReset(@projection)
EndProcedure

Procedure WT40()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected plan.WallSpanPlan
  Protected texturePlan.WallTextureSpanPlan
  Protected cache.WallTextureCache
  Protected clip.WallVerticalClip
  Protected frame.FrameBuffer
  Protected tally.WallTextureDrawTally
  Protected projection.Projection
  Protected rawOff.l = 0
  Protected center.q = 0
  Protected distance.l = 0
  Protected scale1.l = 0
  Protected light.l = 0
  Protected midMid.l = 0

  BeginCase("WT40", "Ceiling/floor clip overlap yields empty range no OOB writes")
  Check(BuildColormapSet(@colormap, 32, 17, 9), "WT40 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT40 light table built")
  Check(ManualCacheBegin(@cache, 1), "WT40 middle cache initialized")
  Check(ManualCacheImage(@cache, 0, 1, 64, 128, 37, 1), "WT40 cache TEXMID")
  If ScenePlanL("TI01", 0, #UNIT_PlanLRawOffset, @rawOff) And
     ScenePlanQ("TI01", 0, #UNIT_QCenterAngle, @center) And
     ScenePlanL("TI01", 0, #UNIT_PlanLDistance, @distance) And
     ScenePlanL("TI01", 0, #UNIT_PlanLScale1, @scale1) And
     ScenePlanL("TI01", 0, #UNIT_PlanLLightNum, @light) And
     ScenePlanL("TI01", 0, #UNIT_PlanLMidTextureMid, @midMid)
    Check(#True, "WT40 TI01 fixture fields readable")
  Else
    Check(#False, "WT40 fixture fields readable")
    Goto WT40Done
  EndIf
  Check(LegacyPlanForDraw(@plan, 160, 160, 0, 0, 0, 1, 0, 0,
                          scale1, 0, -4095, 815104, 0, 0, 0, 0, 0, 0,
                          rawOff, center, distance, light), "WT40 solid middle plan prepared")
  Check(TexturePlanForDraw(@texturePlan, 1, 1, 0, 0, -1, -1,
                           midMid, 0, 0, 64, 128, 63, 0, 0, 0, 0, 0, 0,
                           rawOff, center, light, 1, -1, -1), "WT40 middle texture plan")
  Check(ProjectionInitClassic(@projection), "WT40 canonical projection initializes")
  Check(ClipFrame(@clip, @frame), "WT40 clip/frame prepared")
  PokeL(clip\Ceiling + 160 * SizeOf(Long), 180)
  PokeL(clip\Floor + 160 * SizeOf(Long), 170)
  Check(WallTextureDrawTallyReset(@tally), "WT40 tally reset")
  Check(TexturedWallDrawSpan(@frame, @plan, @texturePlan, @cache,
                             @projection, @table, @colormap, @clip, @tally),
        "WT40 overlapped clip span processed safely")
  Check(Bool(tally\MiddlePixels = 0 And tally\MiddleRanges = 0 And tally\DrawnPixels = 0),
        "WT40 yl181>yh169 no middle pixel")
  Check(Bool(tally\EmptyColumns = 1 And tally\ClippedColumns = 1 And tally\OutOfFrameColumns = 0),
        "WT40 empty/clipped accounting no out-of-frame")
  Check(Bool(FrameBufferGetPixel(@frame, 160, 181) = 0), "WT40 clipped yl181 not written")
  Check(Bool(FrameBufferGetPixel(@frame, 160, 169) = 0), "WT40 clipped yh169 not written")
  Check(Bool(PeekL(clip\Ceiling + 160 * SizeOf(Long)) = 200 And PeekL(clip\Floor + 160 * SizeOf(Long)) = -1),
        "WT40 one-sided closes clip despite empty range")

WT40Done:
  WallTextureDrawTallyReset(@tally)
  WallVerticalClipReset(@clip)
  FrameBufferReset(@frame)
  WallTextureCacheReset(@cache)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
  ProjectionReset(@projection)
EndProcedure

Procedure WT41()
  Protected good.ColormapSet
  Protected bad31.ColormapSet
  Protected table.WallScalelightTable
  Protected *truncated.Byte = 0
  Protected truncatedBytes.q = 8191
  Protected count.l = 0
  Protected dec.i
  Protected gate.i
  Protected tableBuild.i
  Protected reset.i

  BeginCase("WT41", "Full 32-table COLORMAP availability gate")
  Check(Bool(BuildColormapSet(@good, 32, 17, 9)), "WT41 32x256 synthetic COLORMAP decode succeeds")
  Check(WallLightingValidateColormap(@good, @count), "WT41 >=32 wall lighting gate accepted")
  Check(Bool(count = 32), "WT41 gate reports exactly 32 classic tables")
  Check(BuildLight(@table, @good), "WT41 scalelight table builds from 32 tables")
  Check(Bool(BuildColormapSet(@bad31, 31, 17, 9)), "WT41 31-table COLORMAP is still decoder-valid")
  gate = WallLightingValidateColormap(@bad31, 0)
  Check(Bool(gate = #False), "WT41 31-table COLORMAP rejected by 32-table wall gate")
  Check(Bool(FindString(WallLightingLastError(), "32") > 0), "WT41 gate diagnostic names the 32-table minimum")
  tableBuild = WallScalelightTableBuild(@table, @bad31)
  Check(Bool(tableBuild = #False), "WT41 scalar table build fails on incomplete lighting tables")
  reset = WallScalelightTableReset(@table)
  Check(Bool(reset), "WT41 failed lighting table Reset remains idempotent")

  *truncated = AllocateMemory(truncatedBytes)
  Check(Bool(*truncated <> 0), "WT41 truncated COLORMAP probe buffer allocated")
  If *truncated <> 0
    FillMemory(*truncated, Int(truncatedBytes), 0)
    dec = ColormapDecode(*truncated, truncatedBytes, 0)
    Check(Bool(dec = #False), "WT41 8191-byte truncated COLORMAP decode rejects")
  EndIf
  If *truncated <> 0
    FreeMemory(*truncated)
  EndIf
  WallScalelightTableReset(@table)
  ColormapReset(@good)
  ColormapReset(@bad31)
EndProcedure

Procedure WT42()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected level.l
  Protected scale.l
  Protected mapIndex.l = 0
  Protected mismatch.l = 0
  Protected extreme.l = 0

  BeginCase("WT42", "16x48 scalelight index calculation with independent oracle")
  Check(Bool(BuildColormapSet(@colormap, 32, 17, 9)), "WT42 32-table COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT42 scalelight table built")
  For level = 0 To #LIGHT_LEVELS - 1
    For scale = 0 To #LIGHT_MAXLIGHTSCALE - 1
      If WallLightingTableMapIndexChecked(@table, level, scale, @mapIndex)
        If mapIndex <> FixtureScalelight(level, scale)
          mismatch + 1
        EndIf
      Else
        mismatch + 1
      EndIf
    Next
  Next
  Check(Bool(mismatch = 0), "WT42 all 768 bins match generated startmap/level oracle")
  For level = 0 To #LIGHT_LEVELS - 1
    If WallLightingTableMapIndexChecked(@table, level, 47, @mapIndex)
      If mapIndex <> FixtureScalelight(level, 47)
        extreme + 1
      EndIf
    EndIf
  Next
  Check(Bool(extreme = 0), "WT42 maximum scale47 boundary matches oracle for all rows")
  Check(Bool(WallLightingTableMapIndexChecked(@table, 0, 0, @mapIndex) And mapIndex = 31),
        "WT42 p_lightless row0 scale0 startmap60 clamps to level31")
  Check(Bool(WallLightingTableMapIndexChecked(@table, 15, 0, @mapIndex) And mapIndex = 0),
        "WT42 row15 scale0 startmap0 level0")
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
EndProcedure

Procedure WT43()
  Protected light.l = 0
  Protected expected.l = 0
  Protected ok.i

  BeginCase("WT43", "Horizontal vs vertical front-sector lighting correction")
  ok = WallLightingLightNumChecked(160, 0, -64, 100, 100, 0, @light)
  Check(ok, "WT43 vertical wall light row accepted")
  expected = 11
  Check(Bool(light = expected), "WT43 front160>>4=10 then vertical same X -> lightnum11")
  ok = WallLightingLightNumChecked(160, 64, 64, 100, -64, 0, @light)
  Check(ok, "WT43 horizontal wall light row accepted")
  expected = 9
  Check(Bool(light = expected), "WT43 front160>>4=10 then horizontal same Y -> lightnum9")
EndProcedure

Procedure WT44()
  Protected light.l = 0
  Protected ok.i

  BeginCase("WT44", "Diagonal line neither horizontal nor vertical correction")
  ok = WallLightingLightNumChecked(160, 64, -64, 100, 80, 0, @light)
  Check(ok, "WT44 diagonal front-sector light row accepted")
  Check(Bool(light = 10), "WT44 160>>4 stays 10 for neither equal X nor equal Y")
EndProcedure

Procedure WT45()
  Protected light.l = 0
  Protected ok.i

  BeginCase("WT45", "Bright/dark light levels valid clamping")
  ok = WallLightingLightNumChecked(0, 0, -64, 100, 100, 0, @light)
  Check(Bool(ok And light = 1), "WT45 dark lightlevel0 vertical same-X correction row1")
  ok = WallLightingLightNumChecked(0, 64, 64, 100, -64, 0, @light)
  Check(Bool(ok And light = 0), "WT45 dark horizontal also clamps row0")
  ok = WallLightingLightNumChecked(255, 0, -64, 100, 100, 0, @light)
  Check(Bool(ok And light = 15), "WT45 bright255>>4=15 +vertical clamps upper row15")
  ok = WallLightingLightNumChecked(255, 64, 64, 100, -64, 0, @light)
  Check(Bool(ok And light = 14), "WT45 bright horizontal stays row14 inside clamp")
  ok = WallLightingLightNumChecked(160, 64, -64, 100, 80, 2, @light)
  Check(Bool(ok = #False), "WT45 nonzero deferred extralight value rejected")
  Check(Bool(FindString(WallLightingLastError(), "extralight") > 0), "WT45 extralight rejection diagnostic")
EndProcedure

Procedure WT46()
  Protected index.l = 0
  Protected ok.i

  BeginCase("WT46", "rw_scale>>12 selected column light-index boundaries")
  ok = WallLightingScaleIndexChecked(4095, @index)
  Check(Bool(ok And index = 0), "WT46 scale4095 >>12 index0")
  ok = WallLightingScaleIndexChecked(4096, @index)
  Check(Bool(ok And index = 1), "WT46 scale4096 >>12 index1 boundary")
  ok = WallLightingScaleIndexChecked(196608, @index)
  Check(Bool(ok And index = 47), "WT46 scale196608=48<<12 clamps 47")
  ok = WallLightingScaleIndexChecked(196607, @index)
  Check(Bool(ok And index = 47), "WT46 scale just below 48<<12 remains 47")
  ok = WallLightingScaleIndexChecked(256, @index)
  Check(Bool(ok And index = 0), "WT46 minimum production scale256 index0")
  ok = WallLightingScaleIndexChecked(0, @index)
  Check(Bool(ok = #False), "WT46 nonpositive scale rejected")
EndProcedure

Procedure WT47()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected mapped.l = 0
  Protected expected.l = 0
  Protected level.l = 0
  Protected ok.i
  Protected sentinel.l = 4444

  BeginCase("WT47", "Mapped palette sample includes source index 0 and 255")
  Check(Bool(BuildColormapSet(@colormap, 32, 17, 9)), "WT47 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT47 light table built")
  level = FixtureScalelight(11, 25)
  Check(Bool(level = 4), "WT47 fixture light row11/scale25 map level4")
  ok = WallLightingWallTexelChecked(@colormap, @table, 11, 25, 0, @mapped)
  expected = (0 + 17 + level * 9) & 255
  Check(Bool(ok And mapped = expected), "WT47 source texel0 maps through COLORMAP table level4")
  ok = WallLightingWallTexelChecked(@colormap, @table, 11, 25, 255, @mapped)
  expected = (255 + 17 + level * 9) & 255
  Check(Bool(ok And mapped = expected), "WT47 source texel255 maps as ordinary palette index")
  sentinel = 4444
  ok = WallLightingWallTexelChecked(@colormap, @table, 11, 25, -1, @sentinel)
  Check(Bool(ok = #False And sentinel = 4444), "WT47 negative texel rejected with untouched output")
  ok = WallLightingWallTexelChecked(@colormap, @table, 11, 25, 256, @sentinel)
  Check(Bool(ok = #False And sentinel = 4444), "WT47 texel256 rejected with untouched output")
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
EndProcedure

Procedure WT48()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected image.TextureImage
  Protected before.q = 0
  Protected after.q = 0
  Protected mapped.l = 0
  Protected i.i
  Protected ok.i
  Protected mismatch.l = 0

  BeginCase("WT48", "Repeated lighting does not mutate source composed texture")
  Check(Bool(BuildColormapSet(@colormap, 32, 17, 9)), "WT48 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT48 light table built")
  Check(Bool(BuildImage(@image, 64, 128, 37, 1)), "WT48 synthetic composed source image built")
  before = ImagePlaneFnv(@image)
  Check(Bool(before >= 0), "WT48 source pixel+mask hash readable before lighting")
  For i = 1 To 128
    ok = WallLightingWallTexelChecked(@colormap, @table, 11, (i + 25) % 48, 37, @mapped)
    If ok
      If mapped < 0 Or mapped > 255
        mismatch + 1
      EndIf
    Else
      mismatch + 1
    EndIf
  Next
  after = ImagePlaneFnv(@image)
  Check(Bool(mismatch = 0), "WT48 128 repeated COLORMAP lookups all bounded")
  Check(Bool(after = before), "WT48 source pixels+mask hash unchanged after repeated lighting")
  Check(Bool(image\Magic = #TEXTURE_ImageMagic And image\Pixels <> 0), "WT48 source image ownership intact")
  TextureImageReset(@image)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
EndProcedure

Procedure WT49()
  Protected missing.ColormapSet
  Protected table.WallScalelightTable
  Protected *bytes.Byte = 0
  Protected len.q = 8191
  Protected dec.i
  Protected gate.i
  Protected build.i
  Protected reset.i
  Protected err.s = ""

  BeginCase("WT49", "Missing/truncated COLORMAP yields explicit error/rollback")
  *bytes = AllocateMemory(len)
  Check(Bool(*bytes <> 0), "WT49 truncated COLORMAP buffer allocated")
  If *bytes <> 0
    FillMemory(*bytes, Int(len), 0)
    dec = ColormapDecode(*bytes, len, @missing)
    Check(Bool(dec = #False), "WT49 truncated length rejected by ColormapDecode")
    err = ColormapLastError()
    Check(Bool(ColormapCount(@missing) = 0 And FindString(err, "multiple") > 0),
          "WT49 decoder leaves zero tables with multiple-table-length diagnostic")
    gate = WallLightingValidateColormap(@missing, 0)
    Check(Bool(gate = #False), "WT49 uninitialized COLORMAP fails wall gate")
    build = WallScalelightTableBuild(@table, @missing)
    Check(Bool(build = #False), "WT49 scalelight build rejects missing COLORMAP")
    reset = WallScalelightTableReset(@table)
    Check(Bool(reset), "WT49 failed table is safely resettable")
    FreeMemory(*bytes)
  EndIf
  ColormapReset(@missing)
  WallScalelightTableReset(@table)
EndProcedure

Procedure WT50()
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected spanCount.l = 0
  Protected segmentCount.l = 0
  Protected texturePlanCount.l = 0
  Protected processedColumns.l = 0
  Protected textureColumns.l = 0
  Protected drawnPixels.l = 0
  Protected middlePixels.l = 0
  Protected upperPixels.l = 0
  Protected lowerPixels.l = 0
  Protected middleRanges.l = 0
  Protected upperRanges.l = 0
  Protected lowerRanges.l = 0
  Protected drawRanges.l = 0
  Protected emptyColumns.l = 0
  Protected clippedColumns.l = 0
  Protected outOfFrameColumns.l = 0
  Protected samples.l = 0
  Protected uncovered.l = 0
  Protected fallbacks.l = 0
  Protected nonzero.l = 0
  Protected zeroBytes.l = 0
  Protected composed.l = 0
  Protected requested.l = 0
  Protected reused.l = 0
  Protected masked.l = 0
  Protected shortTex.l = 0
  Protected cacheAlloc.l = 0
  Protected allocs.l = 0
  Protected cacheTemp.q = 0
  Protected cachePlane.q = 0
  Protected cachePeak.q = 0
  Protected hash.q = 0
  Protected mismatch.l = 0
  Protected renderOk.i = #False

  BeginCase("WT50", "Short/irregular texture fallback and policy counters")
  renderOk = RenderTexturedScene("u0650.wad", 2, "E2M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT50 TI02 full synthetic pipeline completes")
  If renderOk
    Check(Bool(TexturedWallRenderGetStats(@result, @spanCount, @segmentCount, 0,
                  @texturePlanCount, 0, @processedColumns, @textureColumns,
                  @drawnPixels, @middlePixels, @upperPixels, @lowerPixels,
                  @middleRanges, @upperRanges, @lowerRanges, @drawRanges,
                  @emptyColumns, @clippedColumns, @outOfFrameColumns, @samples,
                  @uncovered, @fallbacks, @nonzero, @zeroBytes, @composed,
                  @requested, @reused, @masked, @shortTex, @cacheAlloc, @allocs,
                  @cacheTemp, @cachePlane, @cachePeak, @hash)),
          "WT50 full-frame statistics readable")
    Check(Bool(spanCount = #TEXGOLD_TI02_SpanCount And
                segmentCount = #TEXGOLD_TI02_SpanCount And
                texturePlanCount = #TEXGOLD_TI02_SpanCount),
          "WT50 TI02 project plan counts match oracle spans")
    Check(Bool(fallbacks = #TEXGOLD_TI02_ShortHeightFallbacks And shortTex = #TEXGOLD_TI02_ShortTextures),
          "WT50 short-height fallback4143 / two short catalog textures oracle")
    Check(Bool(uncovered = #TEXGOLD_TI02_UncoveredTexels And samples = #TEXGOLD_TI02_TextureSamples),
          "WT50 no mask-hole texels; all 38173 samples policy-counted")
    Check(Bool(processedColumns = #TEXGOLD_TI02_ProcessedColumns And
                drawnPixels = #TEXGOLD_TI02_DrawnPixels And
                outOfFrameColumns = #TEXGOLD_TI02_OutOfFrameColumns),
          "WT50 columns/pixel/no-out-of-frame counters oracle")
    Check(Bool(nonzero = #TEXGOLD_TI02_NonZeroBytes And zeroBytes = #TEXGOLD_TI02_ZeroBytes),
          "WT50 frame byte audit derived from same policy draws")
    mismatch = FrameCompareFixture("TI02", @target)
    Check(Bool(mismatch = 0), "WT50 full 64,000 plane matches independent Python policy frame")
  Else
    Check(#False, "WT50 policy frame rendered")
  EndIf
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure WT51()
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected plan.WallTextureSpanPlan
  Protected spanCount.l = 0
  Protected segmentCount.l = 0
  Protected texturePlanCount.l = 0
  Protected processedColumns.l = 0
  Protected textureColumns.l = 0
  Protected drawnPixels.l = 0
  Protected middlePixels.l = 0
  Protected upperPixels.l = 0
  Protected lowerPixels.l = 0
  Protected middleRanges.l = 0
  Protected upperRanges.l = 0
  Protected lowerRanges.l = 0
  Protected drawRanges.l = 0
  Protected emptyColumns.l = 0
  Protected clippedColumns.l = 0
  Protected outOfFrameColumns.l = 0
  Protected samples.l = 0
  Protected uncovered.l = 0
  Protected fallbacks.l = 0
  Protected nonzero.l = 0
  Protected zeroBytes.l = 0
  Protected composed.l = 0
  Protected requested.l = 0
  Protected reused.l = 0
  Protected masked.l = 0
  Protected shortTex.l = 0
  Protected cacheAlloc.l = 0
  Protected allocs.l = 0
  Protected cacheTemp.q = 0
  Protected cachePlane.q = 0
  Protected cachePeak.q = 0
  Protected hash.q = 0
  Protected mismatch.l = 0
  Protected planMismatch.l = 0
  Protected planIndex.i
  Protected maskedExpected.l = 0
  Protected renderOk.i = #False

  BeginCase("WT51", "Two-sided masked middle detected and deferred, never opaque")
  renderOk = RenderTexturedScene("u0651.wad", 2, "E2M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT51 TI02 full synthetic pipeline completes")
  If renderOk
    Check(Bool(TexturedWallRenderGetStats(@result, @spanCount, @segmentCount, 0,
                  @texturePlanCount, 0, @processedColumns, @textureColumns,
                  @drawnPixels, @middlePixels, @upperPixels, @lowerPixels,
                  @middleRanges, @upperRanges, @lowerRanges, @drawRanges,
                  @emptyColumns, @clippedColumns, @outOfFrameColumns, @samples,
                  @uncovered, @fallbacks, @nonzero, @zeroBytes, @composed,
                  @requested, @reused, @masked, @shortTex, @cacheAlloc, @allocs,
                  @cacheTemp, @cachePlane, @cachePeak, @hash)),
          "WT51 statistics read")
    Check(Bool(masked = #TEXGOLD_TI02_MaskedMidSpans), "WT51 exactly two masked middles detected")
    Check(Bool(shortTex = #TEXGOLD_TI02_ShortTextures), "WT51 masked deferral does not alter short texture count")
    Check(Bool(middlePixels = #TEXGOLD_TI02_MiddlePixels And
                middleRanges = #TEXGOLD_TI02_MiddleRanges),
          "WT51 middle writes stay one-sided 34030/205, masked middles paint nothing")
    Check(Bool(composed = #TEXGOLD_TI02_Composed And requested = #TEXGOLD_TI02_Requested And
                reused = #TEXGOLD_TI02_Reused),
          "WT51 cache composes only painted unique tiers, excluding deferred masked")
    For planIndex = 0 To #TEXGOLD_TI02_SpanCount - 1
      If TexturedWallRenderGetTexturePlan(@result, planIndex, @plan) = #False Or
         ScenePlanL("TI02", planIndex, #UNIT_PlanLMaskedMid, @maskedExpected) = #False
        planMismatch + 1
      Else
        If plan\MaskedMid <> maskedExpected
          planMismatch + 1
        EndIf
        If plan\MaskedMid <> 0 And plan\MidCacheSlot <> -1
          planMismatch + 1
        EndIf
      EndIf
    Next
    Check(Bool(planMismatch = 0), "WT51 every masked plan matches oracle flag and has no cache slot")
    mismatch = FrameCompareFixture("TI02", @target)
    Check(Bool(mismatch = 0), "WT51 portal/masked gaps reproduce oracle bytes with no opaque fill")
  Else
    Check(#False, "WT51 masked deferral frame rendered")
  EndIf
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure WT52()
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected spanCount.l = 0
  Protected segmentCount.l = 0
  Protected texturePlanCount.l = 0
  Protected plan.WallSpanPlan
  Protected expected.l = 0
  Protected actual.l = 0
  Protected mismatch.l = 0
  Protected spanField.l = 0
  Protected planIndex.i
  Protected renderOk.i = #False

  BeginCase("WT52", "Deterministic published span order without BSP re-walk or sort")
  renderOk = RenderTexturedScene("u0652.wad", 2, "E2M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT52 TI02 full synthetic pipeline completes")
  If renderOk
    Check(Bool(TexturedWallRenderResultIsValid(@result)), "WT52 result ready")
    Check(Bool(TexturedWallRenderGetStats(@result, @spanCount, @segmentCount, 0,
                  @texturePlanCount, 0,
                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
          "WT52 span/plan counts read")
    Check(Bool(spanCount = #TEXGOLD_TI02_SpanCount And
                segmentCount = #TEXGOLD_TI02_SpanCount And
                texturePlanCount = #TEXGOLD_TI02_SpanCount),
          "WT52 four oracle spans copied once each")
    For planIndex = 0 To #TEXGOLD_TI02_SpanCount - 1
      If TexturedWallRenderGetPlan(@result, planIndex, @plan) = #False
        mismatch + 1
      Else
        Check(Bool(plan\SpanIndex = planIndex), "WT52 plan chronology index stays " + Str(planIndex))
        For spanField = 0 To #TEXGOLD_SpanFieldCount - 1
          If SceneSpanField("TI02", planIndex, spanField, @expected) = #False
            mismatch + 1
          Else
            Select spanField
              Case 0 : actual = plan\Subsector
              Case 1 : actual = plan\Seg
              Case 2 : actual = plan\Linedef
              Case 3 : actual = plan\Side
              Case 4 : actual = plan\FrontSector
              Case 5 : actual = plan\BackSector
              Case 6 : actual = plan\FirstX
              Case 7 : actual = plan\LastX
              Case 8 : actual = plan\Kind
              Default : actual = -999999
            EndSelect
            If actual <> expected
              mismatch + 1
            EndIf
          EndIf
        Next
      EndIf
    Next
    Check(Bool(mismatch = 0),
          "WT52 plan span IDs/X intervals match oracle visibility chronology, no re-sort")
    Check(Bool(result\SegmentCount = result\TexturePlanCount), "WT52 one textured plan per legacy span")
    mismatch = FrameCompareFixture("TI02", @target)
    Check(Bool(mismatch = 0), "WT52 chronological draw equals independent full-frame oracle")
  Else
    Check(#False, "WT52 ordered frame rendered")
  EndIf
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure WT53()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected projection.Projection
  Protected cache.WallTextureCache
  Protected clip.WallVerticalClip
  Protected frame.FrameBuffer
  Protected tally.WallTextureDrawTally
  Protected planA.WallSpanPlan
  Protected planB.WallSpanPlan
  Protected textureA.WallTextureSpanPlan
  Protected textureB.WallTextureSpanPlan
  Protected rawOff.l = 0
  Protected center.q = 0
  Protected distance.l = 0
  Protected scale1.l = 0
  Protected light.l = 0
  Protected ceil.l = 0
  Protected floor.l = 0
  Protected pixel.l = 0

  BeginCase("WT53", "Multi-span same screen column shared clip state")
  Check(Bool(BuildColormapSet(@colormap, 32, 17, 9)), "WT53 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT53 scalelight table built")
  Check(ManualCacheBegin(@cache, 1), "WT53 one-entry top-image cache initialized")
  Check(ManualCacheImage(@cache, 0, 2, 96, 72, 73, 1), "WT53 top cache image 96x72 pixel73")
  If ScenePlanL("TI01", 0, #UNIT_PlanLRawOffset, @rawOff) And
     ScenePlanQ("TI01", 0, #UNIT_QCenterAngle, @center) And
     ScenePlanL("TI01", 0, #UNIT_PlanLDistance, @distance) And
     ScenePlanL("TI01", 0, #UNIT_PlanLScale1, @scale1) And
     ScenePlanL("TI01", 0, #UNIT_PlanLLightNum, @light)
    Check(#True, "WT53 oracle column/light fields readable")
  Else
    Check(#False, "WT53 oracle column/light fields readable")
    Goto WT53Done
  EndIf
  Check(LegacyPlanForDraw(@planA, 160, 160, 0, 1, 0, 0, 0, 1,
                          scale1, 0, -4095, 815104, 0, 0, 245760, 0, 0, 0,
                          rawOff, center, distance, light),
        "WT53 span A upper tier ceil60 plan prepared")
  Check(LegacyPlanForDraw(@planB, 160, 160, 0, 1, 0, 0, 0, 1,
                          scale1, 0, -4095, 815104, 0, 0, 409600, 0, 0, 0,
                          rawOff, center, distance, light),
        "WT53 span B same column upper tier mid100 plan prepared")
  Check(TexturePlanForDraw(@textureA, 1, 1, 0, -1, 0, -1,
                           0, 0, 0, 0, 0, 0, 96, 72, 63, 0, 0, 0,
                           rawOff, center, light, -1, 2, -1),
        "WT53 plan A texture identity/top material")
  Check(TexturePlanForDraw(@textureB, 1, 1, 0, -1, 0, -1,
                           0, 0, 0, 0, 0, 0, 96, 72, 63, 0, 0, 0,
                           rawOff, center, light, -1, 2, -1),
        "WT53 plan B texture identity/top material")
  Check(ProjectionInitClassic(@projection), "WT53 canonical projection")
  Check(ClipFrame(@clip, @frame), "WT53 clip/frame prepared")
  Check(WallTextureDrawTallyReset(@tally), "WT53 tally reset")
  Check(TexturedWallDrawSpan(@frame, @planA, @textureA, @cache,
                             @projection, @table, @colormap, @clip, @tally),
        "WT53 first span draws column x160")
  Check(TexturedWallDrawSpan(@frame, @planB, @textureB, @cache,
                             @projection, @table, @colormap, @clip, @tally),
        "WT53 second span reuses mutated shared clip")
  Check(Bool(tally\ProcessedColumns = 2 And tally\TextureColumnsComputed = 2),
        "WT53 two screen columns computed")
  Check(Bool(tally\UpperPixels = 101 And tally\DrawnPixels = 101 And tally\UpperRanges = 2),
        "WT53 61+40 upper rows: second span ceil-clipped by first")
  Check(Bool(tally\ClippedColumns = 1 And tally\EmptyColumns = 0),
        "WT53 exactly one later-column clipping, no empty draws")
  ceil = PeekL(clip\Ceiling + 160 * SizeOf(Long))
  floor = PeekL(clip\Floor + 160 * SizeOf(Long))
  Check(Bool(ceil = 100 And floor = 200), "WT53 shared clip ceiling60->100 floor remains200")
  pixel = FrameBufferGetPixel(@frame, 160, 0)
  Check(Bool(pixel <> 0), "WT53 row0 from span A painted")
  pixel = FrameBufferGetPixel(@frame, 160, 60)
  Check(Bool(pixel <> 0), "WT53 row60 from span A painted")
  pixel = FrameBufferGetPixel(@frame, 160, 61)
  Check(Bool(pixel <> 0), "WT53 row61 first painted row of clipped span B")
  pixel = FrameBufferGetPixel(@frame, 160, 100)
  Check(Bool(pixel <> 0), "WT53 row100 last painted row of span B")
  Check(Bool(FrameBufferGetPixel(@frame, 160, 101) = 0), "WT53 row101 not painted")
  Check(Bool(FrameBufferGetPixel(@frame, 161, 50) = 0), "WT53 adjacent column untouched")

WT53Done:
  WallTextureDrawTallyReset(@tally)
  WallVerticalClipReset(@clip)
  FrameBufferReset(@frame)
  WallTextureCacheReset(@cache)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
  ProjectionReset(@projection)
EndProcedure

Procedure WT54()
  Protected colormap.ColormapSet
  Protected table.WallScalelightTable
  Protected image.TextureImage
  Protected frame.FrameBuffer
  Protected pixelCount.l = 0
  Protected samples.l = 0
  Protected uncovered.l = 0
  Protected fallbacks.l = 0
  Protected sentinelPixel.l = 777
  Protected sentinelSamples.l = 778
  Protected outcome.i = -99
  Protected hashBefore.q = 0
  Protected hashAfter.q = 0
  Protected color.l = 0

  BeginCase("WT54", "Canonical 320x200 framebuffer strictly bounded writes")
  Check(Bool(BuildColormapSet(@colormap, 32, 17, 9)), "WT54 COLORMAP built")
  Check(BuildLight(@table, @colormap), "WT54 light table built")
  Check(Bool(BuildImage(@image, 64, 128, 37, 1)), "WT54 64x128 composed image built")
  Check(FrameBufferCreate(@frame, 320, 200), "WT54 exact 320x200 frame created")
  Check(Bool(frame\Width = 320 And frame\Height = 200 And
             frame\PixelCount = 64000 And frame\Pixels <> 0),
        "WT54 row-major plane metadata exact")
  hashBefore = FnvFrame(@frame)
  Check(Bool(hashBefore <> 0), "WT54 zeroed frame hash readable prior to writes")
  outcome = WallTextureDrawColumn(@frame, @image, @table, @colormap,
                                  0, 63, 64, 0, 0, 199, 0, 104857,
                                  10, 2, @pixelCount, @samples,
                                  @uncovered, @fallbacks)
  Check(Bool(outcome = #WALLTEXDRAW_RangeDrawn), "WT54 valid full-column boundary writes")
  Check(Bool(pixelCount = 200 And samples = 200 And uncovered = 0),
        "WT54 exact 200 inclusive rows, all opaque")
  color = FrameBufferGetPixel(@frame, 0, 50)
  Check(Bool(color <> 0), "WT54 x0 row50 painted palette value")
  Check(Bool(FrameBufferGetPixel(@frame, 1, 50) = 0), "WT54 neighbor x1 remains background")
  Check(Bool(FrameBufferGetPixel(@frame, 319, 50) = 0), "WT54 right edge x319 untouched")
  hashAfter = FnvFrame(@frame)
  Check(Bool(hashAfter <> hashBefore), "WT54 valid writes change only expected plane bytes")

  hashBefore = hashAfter
  sentinelPixel = 777 : sentinelSamples = 778
  outcome = WallTextureDrawColumn(@frame, @image, @table, @colormap,
                                  0, 63, 64, -1, 0, 199, 0, 104857,
                                  10, 2, @sentinelPixel, @sentinelSamples,
                                  @uncovered, @fallbacks)
  Check(Bool(outcome = #WALLTEXDRAW_RangeOutOfFrame And sentinelPixel = 0 And sentinelSamples = 778),
        "WT54 negative column safely out-of-frame with untouched sample count")
  Check(Bool(FnvFrame(@frame) = hashBefore), "WT54 negative column wrote no byte")
  Check(Bool(FindString(TexturedWallDrawLastError(), "escaped") > 0),
        "WT54 out-of-frame diagnostic explicit")

  sentinelPixel = 777 : sentinelSamples = 778
  outcome = WallTextureDrawColumn(@frame, @image, @table, @colormap,
                                  0, 63, 64, 320, 0, 199, 0, 104857,
                                  10, 2, @sentinelPixel, @sentinelSamples,
                                  @uncovered, @fallbacks)
  Check(Bool(outcome = #WALLTEXDRAW_RangeOutOfFrame And sentinelPixel = 0),
        "WT54 x320 right-boundary safely skipped")
  Check(Bool(FnvFrame(@frame) = hashBefore), "WT54 x320 wrote no byte")

  sentinelPixel = 777 : sentinelSamples = 778
  outcome = WallTextureDrawColumn(@frame, @image, @table, @colormap,
                                  0, 63, 64, 160, 0, 200, 0, 104857,
                                  10, 2, @sentinelPixel, @sentinelSamples,
                                  @uncovered, @fallbacks)
  Check(Bool(outcome = #WALLTEXDRAW_RangeOutOfFrame And sentinelPixel = 0),
        "WT54 yhigh200 vertical boundary safely skipped")
  Check(Bool(FnvFrame(@frame) = hashBefore), "WT54 yhigh200 wrote no byte")

  sentinelPixel = 777 : sentinelSamples = 778
  outcome = WallTextureDrawColumn(@frame, @image, @table, @colormap,
                                  0, 63, 64, 160, -1, 199, 0, 104857,
                                  10, 2, @sentinelPixel, @sentinelSamples,
                                  @uncovered, @fallbacks)
  Check(Bool(outcome = #WALLTEXDRAW_RangeOutOfFrame And sentinelPixel = 0),
        "WT54 ylow-1 vertical boundary safely skipped")
  Check(Bool(FnvFrame(@frame) = hashBefore), "WT54 ylow-1 wrote no byte")

  FrameBufferReset(@frame)
  TextureImageReset(@image)
  WallScalelightTableReset(@table)
  ColormapReset(@colormap)
EndProcedure

Procedure WT55()
  Protected colormap.ColormapSet
  Protected textures.TextureCatalog
  Protected pnames.PNamesTable
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected spanCount.l = 0
  Protected hashBefore.q = 0
  Protected hashAfter.q = 0
  Protected duplicate.l = 0
  Protected byteIndex.i
  Protected expected.l = 0
  Protected renderOk.i = #False
  Protected wadOk.i = #False

  BeginCase("WT55", "Commit-on-success target; previous frame unchanged on late error")
  Check(BuildWallMap(@level, 0, 0, 0, 0, "-", "-", "-", 0, 0, 0),
        "WT55 one-sided absent-texture map built")
  Check(WallViewSetMapUnits(@view, 0, 0, 0, 0), "WT55 synthetic camera set")
  Check(ProjectionInitClassic(@projection), "WT55 classic projection")
  Check(WallVisibilityBuild(@level, @view\Camera, @projection, 0, 0, @visibility),
        "WT55 visibility built")
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanCount > 0), "WT55 visible mark-only span exists")

  If WallTexBuildStandardResourceWad("u0655.wad", 37, 201, 73, 19, 17, 9) = #False Or
     WADOpen(WallTexFixturePath("u0655.wad")) = #False
    Check(#False, "WT55 catalog resource WAD built/opened")
    Goto WT55Done
  EndIf
  wadOk = #True
  If WallTexDecodeWallCatalog(@pnames, @textures) = #False
    Check(#False, "WT55 catalog decode failed")
    Goto WT55Done
  EndIf
  Check(Bool(BuildColormapSet(@colormap, 32, 17, 9)), "WT55 32-table COLORMAP built")
  Check(FrameBufferCreate(@target, 320, 200), "WT55 previous target frame created")
  For byteIndex = 0 To 63999
    expected = (byteIndex * 37 + 11) & 255
    PokeA(target\Pixels + byteIndex, expected)
  Next
  hashBefore = FnvFrame(@target)
  Check(Bool(hashBefore <> 0), "WT55 previous target bytes prior hash nonzero")
  Check(Bool(TexturedWallRenderResultReset(@result)), "WT55 empty reusable render result")

  renderOk = TexturedWallRenderFrame(@level, @view, @projection, 0, @textures,
                                     @colormap, @visibility, @target, @result, 1)
  Check(Bool(renderOk = #False), "WT55 RequireDrawnPixels refuses mark-only frame")
  Check(Bool(FindString(TexturedWallRenderLastError(), "zero textured wall pixels") > 0),
        "WT55 late frame-phase failure named")
  hashAfter = FnvFrame(@target)
  Check(Bool(hashAfter = hashBefore), "WT55 previous 64,000-byte target unchanged after late error")
  duplicate = 0
  For byteIndex = 0 To 63999
    expected = (byteIndex * 37 + 11) & 255
    If PeekA(target\Pixels + byteIndex) <> expected
      duplicate + 1
    EndIf
  Next
  Check(Bool(duplicate = 0), "WT55 no previous target byte replaced")
  Check(Bool(TexturedWallRenderResultIsValid(@result) And result\Ready = 0 And
             result\Plans = 0 And result\TexturePlans = 0),
        "WT55 failed result transactionally reset, no retained plans")

WT55Done:
  If wadOk
    WADClose()
  EndIf
  PNamesReset(@pnames)
  TextureCatalogReset(@textures)
  ColormapReset(@colormap)
  MapLevelReset(@level)
  WallViewReset(@view)
  ProjectionReset(@projection)
  WallVisibilityReset(@visibility)
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure WT56()
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected hashOne.q = 0
  Protected hashTwo.q = 0
  Protected mismatchOne.l = 0
  Protected mismatchTwo.l = 0
  Protected nonzero.l = 0
  Protected zeroBytes.l = 0
  Protected renderOk.i = #False

  BeginCase("WT56", "Reset/rebuild preserves the full 64,000-byte synthetic frame")
  renderOk = RenderTexturedScene("u0656.wad", 1, "E1M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT56 first TI01 textured frame completes")
  If renderOk
    hashOne = result\Hash
    Check(Bool(hashOne = SceneHash("TI01")), "WT56 first result hash oracle")
    Check(Bool(FnvFrame(@target) = hashOne), "WT56 first canonical byte stream hash independent")
    mismatchOne = FrameCompareFixture("TI01", @target)
    Check(Bool(mismatchOne = 0), "WT56 first full plane exact 64,000 oracle bytes")
    Check(Bool(TexturedWallFrameByteAudit(@target, @nonzero, @zeroBytes)),
          "WT56 first frame byte audit readable")
    Check(Bool(nonzero = #TEXGOLD_TI01_NonZeroBytes And zeroBytes = #TEXGOLD_TI01_ZeroBytes),
          "WT56 first nonzero/zero byte split oracle")
  Else
    Check(#False, "WT56 first frame rendered")
  EndIf

  ; Reset/rebuild all session resources independently while retaining the
  ; previously published target; the second render must be byte-for-byte equal.
  renderOk = RenderTexturedScene("u0656b.wad", 1, "E1M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT56 reset/rebuild second TI01 frame completes")
  If renderOk
    hashTwo = result\Hash
    Check(Bool(hashTwo = hashOne), "WT56 rebuilt frame hash identical to first")
    mismatchTwo = FrameCompareFixture("TI01", @target)
    Check(Bool(mismatchTwo = 0), "WT56 rebuilt full 64,000 plane still exact oracle")
  Else
    Check(#False, "WT56 second frame rendered")
    Goto WT56Done
  EndIf
  Check(Bool(FnvFrame(@target) = hashTwo), "WT56 rebuilt canonical hash still independent")
  Check(Bool(target\Magic = #FRAMEBUFFER_Magic And target\Width = 320 And
             target\Height = 200 And target\PixelCount = 64000),
        "WT56 rebuilt target retains canonical owned plane")

WT56Done:
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure WT57()
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected hash.q = 0
  Protected text.s = ""
  Protected zeroText.s = ""
  Protected smallText.s = ""
  Protected renderOk.i = #False

  BeginCase("WT57", "FNV-1a64 canonical byte stream and leading-zero formatting")
  renderOk = RenderTexturedScene("u0657.wad", 1, "E1M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT57 TI01 textured frame completes")
  If renderOk
    hash = result\Hash
    Check(Bool(hash = SceneHash("TI01")), "WT57 result 64-bit FNV equals oracle hash")
    Check(Bool(FnvFrame(@target) = hash), "WT57 independent 64,000-byte FNV byte stream equals")
    text = TexturedWallRenderGetHashText(@result)
    Check(Bool(text = "119A71B79384D465"), "WT57 exact uppercase oracle hex rendering")
    Check(Bool(Len(text) = 16), "WT57 hash text exactly 16 characters")
    zeroText = WallFrameHashHex64(0)
    Check(Bool(zeroText = "0000000000000000" And Len(zeroText) = 16),
          "WT57 all-zero 64-bit value rendered with 16 leading zeros")
    smallText = WallFrameHashHex64($0000ABCD1234EF56)
    Check(Bool(smallText = "0000ABCD1234EF56" And Len(smallText) = 16),
          "WT57 high-zero small value preserves four leading zeros")
    Check(Bool(#TEXGOLD_FNV_Offset = #UNIT_FNV_Offset And
                #TEXGOLD_FNV_Prime = #UNIT_FNV_Prime),
          "WT57 canonical FNV-1a64 offset/prime constants frozen")
  Else
    Check(#False, "WT57 TI01 hash frame rendered")
  EndIf
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure WT58()
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected spanCount.l = 0
  Protected segmentCount.l = 0
  Protected texturePlanCount.l = 0
  Protected processedColumns.l = 0
  Protected textureColumns.l = 0
  Protected cacheAlloc.l = 0
  Protected totalAlloc.l = 0
  Protected explicitBudget.l = 0
  Protected cacheTemp.q = 0
  Protected cachePlane.q = 0
  Protected cachePeak.q = 0
  Protected renderOk.i = #False

  BeginCase("WT58", "Cache and renderer have no per-column/per-pixel allocations")
  renderOk = RenderTexturedScene("u0658.wad", 2, "E2M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT58 TI02 textured frame completes")
  If renderOk
    Check(Bool(TexturedWallRenderGetStats(@result, @spanCount, @segmentCount, 0,
                  @texturePlanCount, 0, @processedColumns, @textureColumns,
                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                  0, 0, 0, 0, 0, 0, 0,
                  @cacheAlloc, @totalAlloc, @cacheTemp,
                  @cachePlane, @cachePeak, 0)),
          "WT58 allocation counters readable without pixel dumps")
    Check(Bool(spanCount = #TEXGOLD_TI02_SpanCount And
                segmentCount = #TEXGOLD_TI02_SpanCount And
                texturePlanCount = #TEXGOLD_TI02_SpanCount And
                processedColumns = #TEXGOLD_TI02_ProcessedColumns And
                textureColumns = #TEXGOLD_TI02_TextureColumns),
          "WT58 full-frame coverage uses oracle counts")
    Check(Bool(cacheAlloc = #TEXGOLD_TI02_CacheAllocations), "WT58 cache allocations exactly 8 oracle")
    Check(Bool(totalAlloc = #TEXGOLD_TI02_Allocations), "WT58 total allocations exactly 13 oracle")
    explicitBudget = cacheAlloc + 5
    Check(Bool(totalAlloc = explicitBudget), "WT58 13 = cache8 + four plan/table/clip/frame fixed allocations")
    Check(Bool(cacheTemp >= 0 And cachePlane >= 0 And cachePeak >= 0),
          "WT58 cache bytes budgets finite, no per-texel transient allocation")
  Else
    Check(#False, "WT58 allocation frame rendered")
  EndIf
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure WT59()
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected frame.FrameBuffer
  Protected result.WallRenderResult
  Protected spanCount.l = 0
  Protected oldHash.q = 0
  Protected text.s = ""
  Protected drawnPixels.l = 0

  BeginCase("WT59", "Legacy debug mode exact M3-05 synthetic C hash")
  Check(BuildCMap(@level), "WT59 synthetic C two-sided portal map built")
  Check(WallViewSetMapUnits(@view, 0, 0, 0, 0), "WT59 legacy camera at origin/viewz0")
  Check(ProjectionInitClassic(@projection), "WT59 classic projection")
  Check(WallVisibilityBuild(@level, @view\Camera, @projection, 0, 0, @visibility),
        "WT59 M3-04 C visibility built")
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanCount = #WALLGOLD_C_SpanCount), "WT59 C visibility exactly three spans")
  Check(FrameBufferCreate(@frame, 320, 200), "WT59 debug target frame created")
  Check(Bool(WallRenderResultReset(@result)), "WT59 debug result empty reusable")
  If WallRenderFrame(@level, @view, @projection, 0, 0, @visibility,
                     @frame, @result, 0)
    Check(#True, "WT59 legacy debug render succeeds without M3-06 mode")
    spanCount = result\SpanCount
    drawnPixels = result\DrawnPixels
    Check(Bool(spanCount = #WALLGOLD_C_SpanCount), "WT59 retained legacy segment count three")
    Check(Bool(drawnPixels > 0), "WT59 legacy debug wall pixels painted")
    oldHash = PeekQ(*gOldCHash)
    Check(Bool(result\Hash = oldHash), "WT59 result hash equals frozen M3-05 C golden")
    Check(Bool(FnvFrame(@frame) = oldHash), "WT59 independent FNV over full plane equals M3-05 C golden")
    text = WallRenderGetHashText(@result)
    Check(Bool(text = "4D32B97402CD3925"), "WT59 legacy 16-character hex text frozen")
    Check(Bool(PeekQ(*gOldCHash) = $4D32B97402CD3925), "WT59 fixture golden self-consistent")
  Else
    Check(#False, "WT59 legacy debug render succeeds")
  EndIf
  WallRenderResultReset(@result)
  FrameBufferReset(@frame)
  WallVisibilityReset(@visibility)
  WallViewReset(@view)
  ProjectionReset(@projection)
  MapLevelReset(@level)
EndProcedure

Procedure WT60()
  Protected colormap.ColormapSet
  Protected flats.FlatCatalog
  Protected textures.TextureCatalog
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected palette.PaletteSet
  Protected *destination.Byte = 0
  Protected capacity.q = 576000 * 4
  Protected mismatch.l = 0
  Protected Y.l
  Protected X.l
  Protected sourceRow.q = 0
  Protected sourceX.q = 0
  Protected sourceColor.i = 0
  Protected outputRow.q = 0
  Protected destOffset.q = 0
  Protected expectedR.l = 0
  Protected expectedG.l = 0
  Protected expectedB.l = 0
  Protected actualR.i
  Protected actualG.i
  Protected actualB.i
  Protected actualA.i
  Protected hashBefore.q = 0
  Protected hashAfter.q = 0
  Protected scatter.l = 0
  Protected renderOk.i = #False
  Protected scaleOk.i = #False

  BeginCase("WT60", "Nearest-neighbor 320->960 scale equality and raw plane intact")
  renderOk = RenderTexturedScene("u0660.wad", 1, "E1M1", @level, @view,
                                 @projection, @flats, @textures, @colormap,
                                 @visibility, @target, @result, 1)
  Check(Bool(renderOk), "WT60 TI01 textured 320x200 frame completes")
  If renderOk
    Check(Bool(TexturedWallRenderResultIsValid(@result)), "WT60 textured result ready")
    Check(Bool(target\Width = 320 And target\Height = 200 And target\PixelCount = 64000),
          "WT60 raw presentation source plane exact")
    Check(Bool(BuildPalette(@palette, #PALETTE_FormulaBase, #PALETTE_FormulaStep)),
          "WT60 14-palette synthetic PLAYPAL decoded")
    Check(Bool(PaletteCount(@palette) = 14), "WT60 palette count exact")
    hashBefore = FnvFrame(@target)
    *destination = AllocateMemory(capacity)
    Check(Bool(*destination <> 0), "WT60 exact 2,304,000-byte RGBA destination allocated")
    scaleOk = #False
    If *destination <> 0
      scaleOk = FrameBufferScaleNearestRGBA(@target, @palette, 0, 3,
                                            *destination, capacity)
    EndIf
    Check(Bool(scaleOk), "WT60 nearest-neighbor scale3 to 960x600 succeeds")
    ; Whole-output equality: every 3x3 block repeats its source pixel's synthetic
    ; palette index RGB, giving exactly 960*600 RGBA output pixels with alpha255.
    For Y = 0 To 599
      sourceRow = (Int(Y) / 3) * 320
      outputRow = Int(Y) * 960
      For X = 0 To 959
        sourceX = Int(X) / 3
        sourceColor = PeekA(target\Pixels + sourceRow + sourceX)
        expectedR = PaletteFormulaR(sourceColor, 0)
        expectedG = PaletteFormulaG(sourceColor, 0)
        expectedB = PaletteFormulaB(sourceColor, 0)
        destOffset = (outputRow + Int(X)) * 4
        actualR = PeekA(*destination + destOffset)
        actualG = PeekA(*destination + destOffset + 1)
        actualB = PeekA(*destination + destOffset + 2)
        actualA = PeekA(*destination + destOffset + 3)
        If actualR <> expectedR Or actualG <> expectedG Or
           actualB <> expectedB Or actualA <> 255
          mismatch + 1
        EndIf
      Next
    Next
    Check(Bool(mismatch = 0), "WT60 every 960x600 output pixel equals nearest synthetic palette RGB")
    hashAfter = FnvFrame(@target)
    Check(Bool(hashAfter = hashBefore), "WT60 raw 320x200 framebuffer unchanged by presentation scale")
    Check(Bool(capacity = 960 * 600 * 4), "WT60 scaled capacity exact 2,304,000 bytes")
  Else
    Check(#False, "WT60 source frame rendered")
  EndIf
  If *destination <> 0
    FreeMemory(*destination)
  EndIf
  PaletteReset(@palette)
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
EndProcedure

Procedure Main()
  WT01() : WT02() : WT03() : WT04() : WT05()
  WT06() : WT07() : WT08() : WT09() : WT10()
  WT11() : WT12() : WT13() : WT14() : WT15()
  WT16() : WT17() : WT18() : WT19() : WT20()
  WT21() : WT22() : WT23() : WT24() : WT25()
  WT26() : WT27() : WT28() : WT29() : WT30()
  WT31() : WT32() : WT33() : WT34() : WT35()
  WT36() : WT37() : WT38() : WT39() : WT40()
  WT41() : WT42() : WT43() : WT44() : WT45()
  WT46() : WT47() : WT48() : WT49()
  WT50() : WT51() : WT52() : WT53() : WT54()
  WT55() : WT56() : WT57() : WT58() : WT59()
  WT60()
EndProcedure

OpenConsole()
Main()

PrintN("")
PrintN("Cases: " + Str(gUCaseCount) + ", assertions: " + Str(gUAssertionCount) +
       ", failures: " + Str(gUFailureCount))
If gUFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gUFailureCount