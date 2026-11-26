; -----------------------------------------------------------------------------
; DoomPB - M3-06 synthetic textured wall integration tests TI01-TI03
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Entirely self-authored synthetic integration through production APIs. Shared
; ../integration/wall_texture_support.pbi writes the PWAD resources/maps and
; tests/fixtures/m3_wall_texture_golden.pbi is the independent Python/source
; oracle (full 64,000-byte frames, span/plan vectors, sample rows, counters,
; FNV hashes and scalelight bins). No commercial WAD bytes, Doom graphics,
; captures or production output are used as the sole oracle.
;
; TI01: synthetic WAD resources -> one-sided middle textured frame; exact plan
;       coordinates/columns/light/scalars, palette sample rows, counters,
;       checksum and full plane against the independent oracle.
; TI02: near solid + farther pass portal, upper/lower tiers, differing heights,
;       masked middles, short textures, diagonal/horizontal lighting, pegging,
;       unchanged M3-04 visibility span vectors, fixed allocation budget, no
;       out-of-frame pixels, portal sample holes and full-plane oracle.
; TI03: A(one-sided)->B(two-sided)->A reopen lifecycle, catalog patch
;       invalidation/stale-resolve rejection, repeated frame determinism, a late
;       RequireDrawnPixels rollback preserving a prior target, malformed synthetic
;       PWADs missing TEXTURE1/PNAMES or COLORMAP failing safely, and reset of
;       every owned buffer/catalog after close.
;
; Exit code: 0 when every assertion passed, otherwise the failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
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
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/FrameBuffer.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Patch.pbi"
XIncludeFile "../../src/Graphics/Texture.pbi"
XIncludeFile "../../src/Graphics/Palette.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../fixtures/m3_wall_texture_golden.pbi"
XIncludeFile "../../tests/integration/wall_texture_support.pbi"

#ITX_FNV_Offset = -3750763034362895579
#ITX_FNV_Prime = 1099511628211
#ITX_ViewWidth = 320
#ITX_ViewHeight = 200
#ITX_FramePixelCount = 64000
#ITX_MaskedMidField = 59

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

Global *gTI01Spans = ?TEXGOLD_TI01_Spans
Global *gTI01PlanL = ?TEXGOLD_TI01_PlanL
Global *gTI01PlanQ = ?TEXGOLD_TI01_PlanQ
Global *gTI01SampleX = ?TEXGOLD_TI01_SampleX
Global *gTI01SampleRows = ?TEXGOLD_TI01_SampleRows
Global *gTI01Frame = ?TEXGOLD_TI01_Frame
Global *gTI01Hash = ?TEXGOLD_TI01_Hash
Global *gTI01SpanHash = ?TEXGOLD_TI01_SpanHash
Global *gTI02Spans = ?TEXGOLD_TI02_Spans
Global *gTI02PlanL = ?TEXGOLD_TI02_PlanL
Global *gTI02PlanQ = ?TEXGOLD_TI02_PlanQ
Global *gTI02SampleX = ?TEXGOLD_TI02_SampleX
Global *gTI02SampleRows = ?TEXGOLD_TI02_SampleRows
Global *gTI02Frame = ?TEXGOLD_TI02_Frame
Global *gTI02Hash = ?TEXGOLD_TI02_Hash
Global *gTI02SpanHash = ?TEXGOLD_TI02_SpanHash

; ---------------------------------------------------------------------------
; Harness and independent fixture accessors/formulas
; ---------------------------------------------------------------------------

Procedure BeginCase(Id.s, Title.s)
  gCaseCount + 1
  PrintN("")
  PrintN("[" + Id + "] " + Title)
EndProcedure

Procedure Check(Ok.i, Description.s)
  gAssertionCount + 1
  If Ok
    PrintN("  PASS: " + Description)
  Else
    PrintN("  FAIL: " + Description)
    gFailureCount + 1
  EndIf
EndProcedure

Procedure.q FnvByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #ITX_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvByte(Hash, Value)
  Hash = FnvByte(Hash, Value >> 8)
  Hash = FnvByte(Hash, Value >> 16)
  Hash = FnvByte(Hash, Value >> 24)
  ProcedureReturn Hash
EndProcedure

; Independent M3-04 aggregate span fingerprint over the nine published numeric
; fields of every span record, source order; never a copied production hash.
Procedure.q TestWallSpanHash(*Result.WallVisibilityResult)
  Protected hash.q = #ITX_FNV_Offset
  Protected index.i
  Protected sub.l = 0
  Protected seg.l = 0
  Protected line.l = 0
  Protected side.l = 0
  Protected front.l = 0
  Protected back.l = 0
  Protected first.l = 0
  Protected last.l = 0
  Protected kind.l = 0

  If WallVisibilityIsValid(*Result) = #False
    ProcedureReturn -1
  EndIf
  For index = 0 To *Result\Count - 1
    If WallVisibilityGetSpan(*Result, index, @sub, @seg, @line, @side,
                             @front, @back, @first, @last, @kind) = #False
      ProcedureReturn -1
    EndIf
    hash = FnvAddLong(hash, sub)
    hash = FnvAddLong(hash, seg)
    hash = FnvAddLong(hash, line)
    hash = FnvAddLong(hash, side)
    hash = FnvAddLong(hash, front)
    hash = FnvAddLong(hash, back)
    hash = FnvAddLong(hash, first)
    hash = FnvAddLong(hash, last)
    hash = FnvAddLong(hash, kind)
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q FnvFrame(*Frame.FrameBuffer)
  Protected hash.q = #ITX_FNV_Offset
  Protected i.i

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #ITX_ViewWidth Or *Frame\Height <> #ITX_ViewHeight Or
     *Frame\PixelCount <> #ITX_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For i = 0 To #ITX_FramePixelCount - 1
    hash = FnvByte(hash, PeekA(*Frame\Pixels + i))
  Next
  ProcedureReturn hash
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

  If ByteIndex < 0 Or ByteIndex > #ITX_FramePixelCount - 1
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

Procedure.q SceneSpanHash(SceneId.s)
  If SceneId = "TI01"
    ProcedureReturn PeekQ(*gTI01SpanHash)
  ElseIf SceneId = "TI02"
    ProcedureReturn PeekQ(*gTI02SpanHash)
  EndIf
  ProcedureReturn -1
EndProcedure

Procedure.i SceneSampleCount(SceneId.s)
  If SceneId = "TI01"
    ProcedureReturn #TEXGOLD_TI01_SampleCount
  ElseIf SceneId = "TI02"
    ProcedureReturn #TEXGOLD_TI02_SampleCount
  EndIf
  ProcedureReturn -1
EndProcedure

Procedure.i SceneSampleX(SceneId.s, SampleIndex.l, *X.Long)
  Protected *base.Long

  If SampleIndex < 0 Or SampleIndex >= SceneSampleCount(SceneId)
    ProcedureReturn #False
  EndIf
  If SceneId = "TI01"
    *base = *gTI01SampleX
  ElseIf SceneId = "TI02"
    *base = *gTI02SampleX
  Else
    ProcedureReturn #False
  EndIf
  *X\l = PeekL(*base + SampleIndex * SizeOf(Long))
  ProcedureReturn #True
EndProcedure

Procedure.i SceneSampleRow(SceneId.s, SampleIndex.l, Row.l, *Value.Long)
  Protected *base.Byte

  If SampleIndex < 0 Or SampleIndex >= SceneSampleCount(SceneId) Or
     Row < 0 Or Row >= #TEXGOLD_SampleRowBytes
    ProcedureReturn #False
  EndIf
  If SceneId = "TI01"
    *base = *gTI01SampleRows
  ElseIf SceneId = "TI02"
    *base = *gTI02SampleRows
  Else
    ProcedureReturn #False
  EndIf
  *Value\l = PeekA(*base + SampleIndex * #TEXGOLD_SampleRowBytes + Row)
  ProcedureReturn #True
EndProcedure

Procedure.l FrameCompareFixture(SceneId.s, *Frame.FrameBuffer)
  Protected byteIndex.i
  Protected expected.l = 0
  Protected actual.i
  Protected mismatch.l = 0

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #ITX_ViewWidth Or *Frame\Height <> #ITX_ViewHeight Or
     *Frame\PixelCount <> #ITX_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For byteIndex = 0 To #ITX_FramePixelCount - 1
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

; Compares every fixture sample column's 200 row-major palette bytes with the
; produced frame; returns mismatch count or negative validity codes.
Procedure.l FrameSampleMismatchFixture(SceneId.s, *Frame.FrameBuffer)
  Protected sampleCount.i
  Protected sampleIndex.i
  Protected sampleX.l = 0
  Protected row.l = 0
  Protected expected.l = 0
  Protected actual.i
  Protected mismatch.l = 0

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #ITX_ViewWidth Or *Frame\Height <> #ITX_ViewHeight Or
     *Frame\PixelCount <> #ITX_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  sampleCount = SceneSampleCount(SceneId.s)
  If sampleCount < 0
    ProcedureReturn -2
  EndIf
  For sampleIndex = 0 To sampleCount - 1
    If SceneSampleX(SceneId.s, sampleIndex, @sampleX) = #False
      ProcedureReturn -2
    EndIf
    For row = 0 To #TEXGOLD_SampleRowBytes - 1
      If SceneSampleRow(SceneId.s, sampleIndex, row, @expected) = #False
        ProcedureReturn -2
      EndIf
      actual = PeekA(*Frame\Pixels + Int(row) * #ITX_ViewWidth + Int(sampleX))
      If actual <> expected
        mismatch + 1
      EndIf
    Next
  Next
  ProcedureReturn mismatch
EndProcedure

; Independent byte comparison of a private first-plane copy versus a repeat.
Procedure.l FrameCopyMismatch(*Copy.Byte, *Frame.FrameBuffer)
  Protected byteIndex.i

  If *Copy = 0 Or *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #ITX_ViewWidth Or *Frame\Height <> #ITX_ViewHeight Or
     *Frame\PixelCount <> #ITX_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  Protected mismatch.l = 0
  For byteIndex = 0 To #ITX_FramePixelCount - 1
    If PeekA(*Frame\Pixels + byteIndex) <> PeekA(*Copy + byteIndex)
      mismatch + 1
    EndIf
  Next
  ProcedureReturn mismatch
EndProcedure

; Fixture combined ordered field -> production legacy/texture numeric value.
; Invalid field indexes return -999999 to force an explicit mismatch.
Procedure.l ProductionPlanField(*Legacy.WallSpanPlan, *Tex.WallTextureSpanPlan,
                                FieldIndex.l)
  Select FieldIndex
    Case 0 : ProcedureReturn *Legacy\Subsector
    Case 1 : ProcedureReturn *Legacy\Seg
    Case 2 : ProcedureReturn *Legacy\Linedef
    Case 3 : ProcedureReturn *Legacy\Side
    Case 4 : ProcedureReturn *Legacy\FrontSector
    Case 5 : ProcedureReturn *Legacy\BackSector
    Case 6 : ProcedureReturn *Legacy\FirstX
    Case 7 : ProcedureReturn *Legacy\LastX
    Case 8 : ProcedureReturn *Legacy\Kind
    Case 9 : ProcedureReturn *Legacy\Scale1
    Case 10 : ProcedureReturn *Legacy\Scale2
    Case 11 : ProcedureReturn *Legacy\ScaleStep
    Case 12 : ProcedureReturn *Legacy\Hyp
    Case 13 : ProcedureReturn *Legacy\Distance
    Case 14 : ProcedureReturn *Legacy\WorldTopRaw
    Case 15 : ProcedureReturn *Legacy\WorldBottomRaw
    Case 16 : ProcedureReturn *Legacy\WorldHighRaw
    Case 17 : ProcedureReturn *Legacy\WorldLowRaw
    Case 18 : ProcedureReturn *Legacy\WorldTop
    Case 19 : ProcedureReturn *Legacy\WorldBottom
    Case 20 : ProcedureReturn *Legacy\WorldHigh
    Case 21 : ProcedureReturn *Legacy\WorldLow
    Case 22 : ProcedureReturn *Legacy\TopFrac
    Case 23 : ProcedureReturn *Legacy\BottomFrac
    Case 24 : ProcedureReturn *Legacy\TopStep
    Case 25 : ProcedureReturn *Legacy\BottomStep
    Case 26 : ProcedureReturn *Legacy\PixHigh
    Case 27 : ProcedureReturn *Legacy\PixLow
    Case 28 : ProcedureReturn *Legacy\PixHighStep
    Case 29 : ProcedureReturn *Legacy\PixLowStep
    Case 30 : ProcedureReturn *Legacy\MarkFloor
    Case 31 : ProcedureReturn *Legacy\MarkCeiling
    Case 32 : ProcedureReturn *Legacy\TopRegion
    Case 33 : ProcedureReturn *Legacy\BottomRegion
    Case 34 : ProcedureReturn *Legacy\TopTier
    Case 35 : ProcedureReturn *Legacy\BottomTier
    Case 36 : ProcedureReturn *Legacy\MiddleTier
    Case 37 : ProcedureReturn *Legacy\TwoSided
    Case 38 : ProcedureReturn *Legacy\FrontLight
    Case 39 : ProcedureReturn *Legacy\ClosedDoor
    Case 40 : ProcedureReturn *Legacy\SkyHack
    Case 41 : ProcedureReturn *Tex\MidTextureIndex
    Case 42 : ProcedureReturn *Tex\TopTextureIndex
    Case 43 : ProcedureReturn *Tex\BottomTextureIndex
    Case 44 : ProcedureReturn *Tex\MaskedMidIndex
    Case 45 : ProcedureReturn *Tex\MidTextureMid
    Case 46 : ProcedureReturn *Tex\TopTextureMid
    Case 47 : ProcedureReturn *Tex\BottomTextureMid
    Case 48 : ProcedureReturn *Tex\MidWidth
    Case 49 : ProcedureReturn *Tex\MidHeight
    Case 50 : ProcedureReturn *Tex\MidWidthMask
    Case 51 : ProcedureReturn *Tex\TopWidth
    Case 52 : ProcedureReturn *Tex\TopHeight
    Case 53 : ProcedureReturn *Tex\TopWidthMask
    Case 54 : ProcedureReturn *Tex\BottomWidth
    Case 55 : ProcedureReturn *Tex\BottomHeight
    Case 56 : ProcedureReturn *Tex\BottomWidthMask
    Case 57 : ProcedureReturn *Tex\RawOffset
    Case 58 : ProcedureReturn *Tex\LightNum
    Case 59 : ProcedureReturn *Tex\MaskedMid
    Case 60 : ProcedureReturn *Tex\HasPaintedTier
    Case 61 : ProcedureReturn *Tex\SegmentTextured
    Default : ProcedureReturn -999999
  EndSelect
EndProcedure

Procedure.q ProductionPlanQ(*Legacy.WallSpanPlan, *Tex.WallTextureSpanPlan,
                            FieldIndex.l)
  Select FieldIndex
    Case 0 : ProcedureReturn *Legacy\ViewAngle
    Case 1 : ProcedureReturn *Legacy\NormalAngle
    Case 2 : ProcedureReturn *Legacy\ReferenceAngle
    Case 3 : ProcedureReturn *Legacy\OffsetAngle
    Case 4 : ProcedureReturn *Legacy\DistAngle
    Case 5 : ProcedureReturn *Tex\CenterAngle
    Default : ProcedureReturn -999999
  EndSelect
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic session prepare/cleanup
; ---------------------------------------------------------------------------

; Opens an already built synthetic PWAD, decodes catalogs/flats/COLORMAP and
; loads the marker map through production APIs, then derives player-one view,
; classic projection and catalog-aware M3-04 visibility. Leaves the WAD open and
; every decoded resource caller-owned for a subsequent textured frame.
Procedure.i PrepareSyntheticSession(FileName.s, Marker.s,
                                    *Pnames.PNamesTable,
                                    *Textures.TextureCatalog,
                                    *Flats.FlatCatalog,
                                    *Colormap.ColormapSet,
                                    *Level.MapLevel, *View.WallView,
                                    *Projection.Projection,
                                    *Visibility.WallVisibilityResult)
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0

  PNamesReset(*Pnames)
  TextureCatalogReset(*Textures)
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  MapLevelReset(*Level)
  WallViewReset(*View)
  ProjectionReset(*Projection)
  WallVisibilityReset(*Visibility)

  If WADOpen(WallTexFixturePath(FileName.s)) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallCatalog(*Pnames, *Textures) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallFlats(*Flats) = #False
    ProcedureReturn #False
  EndIf
  If WallTexDecodeWallColormap(*Colormap) = #False
    ProcedureReturn #False
  EndIf
  If MapLevelLoad(Marker.s, *Level) = #False
    ProcedureReturn #False
  EndIf
  If WallRenderPlayerStartView(*Level, *View, @thingIndex, @subsectorIndex,
                               @sectorIndex) = #False
    ProcedureReturn #False
  EndIf
  If ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallVisibilityBuild(*Level, @*View\Camera, *Projection,
                                      *Flats, *Textures, *Visibility)
EndProcedure

; Closes the current read-only synthetic WAD session and resets all caller-owned
; decoded resources/map/view/projection/visibility. Target/result-owned frames
; are deliberately retained by the caller when a lifecycle keeps them.
Procedure SyntheticSessionCleanup(*Pnames.PNamesTable,
                                  *Textures.TextureCatalog,
                                  *Flats.FlatCatalog,
                                  *Colormap.ColormapSet,
                                  *Level.MapLevel, *View.WallView,
                                  *Projection.Projection,
                                  *Visibility.WallVisibilityResult)
  If WADIsOpen()
    WADClose()
  EndIf
  PNamesReset(*Pnames)
  TextureCatalogReset(*Textures)
  FlatCatalogReset(*Flats)
  ColormapReset(*Colormap)
  MapLevelReset(*Level)
  WallViewReset(*View)
  ProjectionReset(*Projection)
  WallVisibilityReset(*Visibility)
EndProcedure

; ---------------------------------------------------------------------------
; Tiny malformed/blank synthetic PWAD helpers for TI03
; ---------------------------------------------------------------------------

; Resource-only failure selectors: map/palette/flats always present; TEXTURE1/
; PNAMES or COLORMAP independently omitted to exercise safe missing-resource
; paths. No commercial bytes, no production output oracle.
Procedure.i BuildMalformedSceneWad(FileName.s, IncludeTextures.i,
                                  IncludeColormap.i)
  Protected ok.i = #False

  If WallTexWadBegin(FileName.s) = #False
    ProcedureReturn #False
  EndIf
  WallTexAddPalette()
  WallTexAddStandardFlatNamespace()
  If WallTexAddStandardWallResources(37, 201, 73, 19, 17, 9,
                                     IncludeTextures.i, IncludeColormap.i)
    If WallTexBuildT01MapLumps()
      If WallTexAddMapLumpsToWad("E1M1")
        ok = WallTexWadFinish()
      EndIf
    EndIf
  EndIf
  If gWallTexWadFile <> 0
    CloseFile(gWallTexWadFile)
    gWallTexWadFile = 0
  EndIf
  WallTexFreeMap()
  ProcedureReturn ok
EndProcedure

; Direct validated one-sector absent-texture map used to force the genuine
; post-frame-phase RequireDrawnPixels failure without relying on a bad WAD.
Procedure.i BuildBlankWallMap(*Level.MapLevel)
  Protected Dim sectors.WallTexSectorSpec(1)
  Protected Dim lines.WallTexLineSpec(0)
  Protected Dim sides.WallTexSideSpec(1)
  Protected Dim verts.WallTexVertexSpec(1)
  Protected Dim segs.WallTexSegSpec(0)
  Protected Dim subs.WallTexSubSpec(0)
  Protected Dim nodes.WallTexNodeSpec(0)
  Protected Dim things.WallTexThingSpec(0)

  sectors(0)\FloorHeight = 0
  sectors(0)\CeilingHeight = 128
  sectors(0)\FloorName = "FLOOR1"
  sectors(0)\CeilingName = "CEIL1"
  sectors(0)\LightLevel = 160
  sides(0)\Sector = 0 : sides(0)\TopName = "-"
  sides(0)\BottomName = "-" : sides(0)\MidName = "-"
  sides(0)\TextureOffset = 0 : sides(0)\RowOffset = 0
  lines(0)\V1 = 0 : lines(0)\V2 = 1 : lines(0)\Side0 = 0 : lines(0)\Side1 = -1
  verts(0)\X = 100 : verts(0)\Y = 64 : verts(1)\X = 100 : verts(1)\Y = -64
  segs(0)\V1 = 0 : segs(0)\V2 = 1 : segs(0)\RawAngle = 49152
  segs(0)\Line = 0 : segs(0)\Side = 0 : segs(0)\Offset = 0
  subs(0)\NumSegs = 1 : subs(0)\FirstSeg = 0
  ProcedureReturn WallTexBuildMapLevel(*Level, @sectors(0), 1, @lines(0), 1,
                                       @sides(0), 1, @verts(0), 2, @segs(0), 1,
                                       @subs(0), 1, @nodes(0), 0, @things(0), 0)
EndProcedure

Procedure.i BuildBlankSceneView(*Level.MapLevel, *View.WallView,
                                *Projection.Projection,
                                *Visibility.WallVisibilityResult)
  If WallViewSetMapUnits(*View, 0, 0, 0, 0) = #False
    ProcedureReturn #False
  EndIf
  If ProjectionInitClassic(*Projection) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallVisibilityBuild(*Level, @*View\Camera, *Projection,
                                      0, 0, *Visibility)
EndProcedure

; Complete standard synthetic scene PWAD: palette, flats, PNAMES/TEXTURE1/
; COLORMAP/patches, T01 or T02 ten-lump map section. Every byte self-authored
; and matching the independent generator support layout.
Procedure.i BuildSceneWad(FileName.s, SceneMode.i)
  Protected marker.s = "E1M1"
  Protected ok.i = #False

  If WallTexWadBegin(FileName.s) = #False
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

; ---------------------------------------------------------------------------
; TI01: one-sided middle synthetic WAD -> textured frame
; ---------------------------------------------------------------------------

Procedure TestTI01()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
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
  Protected nonzeroBytes.l = 0
  Protected zeroBytes.l = 0
  Protected composed.l = 0
  Protected requested.l = 0
  Protected reused.l = 0
  Protected masked.l = 0
  Protected shortTex.l = 0
  Protected cacheAlloc.l = 0
  Protected totalAlloc.l = 0
  Protected cacheTemp.q = 0
  Protected cachePlane.q = 0
  Protected cachePeak.q = 0
  Protected statsHash.q = 0
  Protected hash.q = 0
  Protected spanHash.q = 0
  Protected expected.l = 0
  Protected actual.l = 0
  Protected spanField.l = 0
  Protected planField.l = 0
  Protected qField.l = 0
  Protected expectedQuad.q = 0
  Protected actualQuad.q = 0
  Protected plan.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected spanCountMismatch.l = 0
  Protected spanFieldMismatch.l = 0
  Protected planFieldMismatch.l = 0
  Protected planQMismatch.l = 0
  Protected frameMismatch.l = 0
  Protected sampleMismatch.l = 0
  Protected planIndex.i
  Protected renderOk.i = #False

  BeginCase("TI01", "Synthetic WAD resources -> one-sided middle textured frame vs oracle")

  Check(Bool(BuildSceneWad("itx01.wad", 1)), "TI01 synthetic PWAD built")
  If PrepareSyntheticSession("itx01.wad", "E1M1", @pnames, @textures, @flats,
                             @colormap, @level, @view, @projection, @visibility)
    Check(#True, "TI01 production decode/map/player/projection/visibility prepared")
  Else
    Check(#False, "TI01 session prepared")
    Goto TI01Done
  EndIf
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanCount = #TEXGOLD_TI01_SpanCount And
             spanCount = SceneSpanCount("TI01")),
        "TI01 one visible wall span matches oracle count")
  Check(Bool(WallVisibilityIsValid(@visibility)), "TI01 M3-04 visibility result valid")
  ; Visibility numeric span vector against the independent geometry oracle.
  spanFieldMismatch = 0
  For planIndex = 0 To spanCount - 1
    If WallVisibilityGetSpan(@visibility, planIndex, @plan\Subsector,
                             @plan\Seg, @plan\Linedef, @plan\Side,
                             @plan\FrontSector, @plan\BackSector,
                             @plan\FirstX, @plan\LastX, @plan\Kind) = #False
      spanFieldMismatch + 1
    Else
      For spanField = 0 To #TEXGOLD_SpanFieldCount - 1
        If SceneSpanField("TI01", planIndex, spanField, @expected) = #False
          spanFieldMismatch + 1
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
            spanFieldMismatch + 1
          EndIf
        EndIf
      Next
    EndIf
  Next
  Check(Bool(spanFieldMismatch = 0),
        "TI01 M3-04 visibility span IDs/X/kind vector unchanged vs oracle")
  spanHash = TestWallSpanHash(@visibility)
  Check(Bool(spanHash <> -1 And spanHash = SceneSpanHash("TI01")),
        "TI01 M3-04 visibility span hash unchanged vs independent oracle")

  Check(FrameBufferCreate(@target, 320, 200), "TI01 canonical target frame created")
  Check(Bool(TexturedWallRenderResultReset(@result)), "TI01 textured result empty reusable")
  renderOk = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(renderOk), "TI01 transactional textured frame succeeds")
  If renderOk
    hash = result\Hash
    Check(Bool(hash = SceneHash("TI01")), "TI01 textured checksum equals independent oracle")
    Check(Bool(FnvFrame(@target) = hash), "TI01 independent full-plane FNV equals checksum")
    Check(Bool(TexturedWallRenderGetStats(@result, @spanCount, @segmentCount, 0,
                  @texturePlanCount, 0, @processedColumns, @textureColumns,
                  @drawnPixels, @middlePixels, @upperPixels, @lowerPixels,
                  @middleRanges, @upperRanges, @lowerRanges, @drawRanges,
                  @emptyColumns, @clippedColumns, @outOfFrameColumns, @samples,
                  @uncovered, @fallbacks, @nonzeroBytes, @zeroBytes, @composed,
                  @requested, @reused, @masked, @shortTex, @cacheAlloc, @totalAlloc,
                  @cacheTemp, @cachePlane, @cachePeak, @statsHash)),
          "TI01 detailed counters read")
    Check(Bool(spanCount = #TEXGOLD_TI01_SpanCount And
                segmentCount = #TEXGOLD_TI01_SpanCount And
                texturePlanCount = #TEXGOLD_TI01_SpanCount),
          "TI01 one legacy/textured plan per oracle span")
    Check(Bool(processedColumns = #TEXGOLD_TI01_ProcessedColumns And
                textureColumns = #TEXGOLD_TI01_TextureColumns And
                drawnPixels = #TEXGOLD_TI01_DrawnPixels And
                middlePixels = #TEXGOLD_TI01_MiddlePixels),
          "TI01 column/row/write counters exact oracle")
    Check(Bool(middleRanges = #TEXGOLD_TI01_MiddleRanges And
                drawRanges = #TEXGOLD_TI01_DrawRanges And
                upperPixels = #TEXGOLD_TI01_UpperPixels And
                lowerPixels = #TEXGOLD_TI01_LowerPixels),
          "TI01 middle-only tier counters exact oracle")
    Check(Bool(emptyColumns = #TEXGOLD_TI01_EmptyColumns And
                clippedColumns = #TEXGOLD_TI01_ClippedColumns And
                outOfFrameColumns = #TEXGOLD_TI01_OutOfFrameColumns),
          "TI01 clip/empty/oob accounting exact oracle")
    Check(Bool(samples = #TEXGOLD_TI01_TextureSamples And
                uncovered = #TEXGOLD_TI01_UncoveredTexels And
                fallbacks = #TEXGOLD_TI01_ShortHeightFallbacks),
          "TI01 texture sample/mask-hole/fallback counters exact oracle")
    Check(Bool(nonzeroBytes = #TEXGOLD_TI01_NonZeroBytes And zeroBytes = #TEXGOLD_TI01_ZeroBytes),
          "TI01 frame byte audit exact oracle")
    Check(Bool(composed = #TEXGOLD_TI01_Composed And requested = #TEXGOLD_TI01_Requested And
                reused = #TEXGOLD_TI01_Reused And masked = #TEXGOLD_TI01_MaskedMidSpans),
          "TI01 cache composition/reuse/masked counters exact oracle")
    Check(Bool(cacheAlloc = #TEXGOLD_TI01_CacheAllocations And
                totalAlloc = #TEXGOLD_TI01_Allocations),
          "TI01 fixed allocation budget exact oracle")
    Check(Bool(result\FrameWidth = 320 And result\FrameHeight = 200),
          "TI01 result frame dimensions canonical")

    ; Numeric span vectors in published chronology.
    spanFieldMismatch = 0
    For planIndex = 0 To #TEXGOLD_TI01_SpanCount - 1
      If TexturedWallRenderGetPlan(@result, planIndex, @plan) = #False
        spanFieldMismatch + 1
      Else
        For spanField = 0 To #TEXGOLD_SpanFieldCount - 1
          If SceneSpanField("TI01", planIndex, spanField, @expected) = #False
            spanFieldMismatch + 1
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
              spanFieldMismatch + 1
            EndIf
          EndIf
        Next
      EndIf
    Next
    Check(Bool(spanFieldMismatch = 0),
          "TI01 legacy span IDs/X/kind vectors equal independent oracle")
    Check(Bool(plan\SpanIndex = #TEXGOLD_TI01_SpanCount - 1),
          "TI01 last plan chronological index")

    ; Full 62-field material/geometry and 6-field quad vectors, independently.
    planFieldMismatch = 0
    planQMismatch = 0
    For planIndex = 0 To #TEXGOLD_TI01_SpanCount - 1
      If TexturedWallRenderGetPlan(@result, planIndex, @plan) = #False Or
         TexturedWallRenderGetTexturePlan(@result, planIndex, @texPlan) = #False
        planFieldMismatch + 1
        planQMismatch + 1
      Else
        For planField = 0 To #TEXGOLD_PlanLFieldCount - 1
          If ScenePlanL("TI01", planIndex, planField, @expected) = #False
            planFieldMismatch + 1
          Else
            actual = ProductionPlanField(@plan, @texPlan, planField)
            If actual <> expected
              planFieldMismatch + 1
              PrintN("  diagnostic: TI01 plan field " + Str(planField) + " actual " +
                     Str(actual) + " expected " + Str(expected))
            EndIf
          EndIf
        Next
        For qField = 0 To #TEXGOLD_PlanQFieldCount - 1
          If ScenePlanQ("TI01", planIndex, qField, @expectedQuad) = #False
            planQMismatch + 1
          Else
            actualQuad = ProductionPlanQ(@plan, @texPlan, qField)
            If actualQuad <> expectedQuad
              planQMismatch + 1
            EndIf
          EndIf
        Next
      EndIf
    Next
    Check(Bool(planFieldMismatch = 0),
          "TI01 all 62 r_segs/r_data material/pegging/light scalar fields equal oracle")
    Check(Bool(planQMismatch = 0),
          "TI01 all 6 signed BAM angle/hyp/distance quad fields equal oracle")

    frameMismatch = FrameCompareFixture("TI01", @target)
    Check(Bool(frameMismatch = 0), "TI01 full 64,000 row-major plane equals Python oracle")
    sampleMismatch = FrameSampleMismatchFixture("TI01", @target)
    Check(Bool(sampleMismatch = 0), "TI01 all fixture sample columns and 200 rows equal oracle palette")
  Else
    Check(#False, "TI01 textured frame rendered")
  EndIf

TI01Done:
  SyntheticSessionCleanup(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
EndProcedure

; ---------------------------------------------------------------------------
; TI02: two-sided portal, tiers, masked/short textures and full plane oracle
; ---------------------------------------------------------------------------

Procedure TestTI02()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
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
  Protected nonzeroBytes.l = 0
  Protected zeroBytes.l = 0
  Protected composed.l = 0
  Protected requested.l = 0
  Protected reused.l = 0
  Protected masked.l = 0
  Protected shortTex.l = 0
  Protected cacheAlloc.l = 0
  Protected totalAlloc.l = 0
  Protected cacheTemp.q = 0
  Protected cachePlane.q = 0
  Protected cachePeak.q = 0
  Protected statsHash.q = 0
  Protected hash.q = 0
  Protected spanHash.q = 0
  Protected expected.l = 0
  Protected actual.l = 0
  Protected expectedQuad.q = 0
  Protected actualQuad.q = 0
  Protected plan.WallSpanPlan
  Protected texPlan.WallTextureSpanPlan
  Protected spanField.l = 0
  Protected planField.l = 0
  Protected qField.l = 0
  Protected spanVectorMismatch.l = 0
  Protected planFieldMismatch.l = 0
  Protected planQMismatch.l = 0
  Protected maskedMismatch.l = 0
  Protected maskedExpected.l = 0
  Protected frameMismatch.l = 0
  Protected sampleMismatch.l = 0
  Protected planIndex.i
  Protected renderOk.i = #False

  BeginCase("TI02", "Two-sided portal/tier synthetic texture frame vs oracle")

  Check(Bool(BuildSceneWad("itx02.wad", 2)), "TI02 synthetic PWAD built")
  If PrepareSyntheticSession("itx02.wad", "E2M1", @pnames, @textures, @flats,
                             @colormap, @level, @view, @projection, @visibility)
    Check(#True, "TI02 production decode/map/player/projection/visibility prepared")
  Else
    Check(#False, "TI02 session prepared")
    Goto TI02Done
  EndIf
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanCount = #TEXGOLD_TI02_SpanCount And
             spanCount = SceneSpanCount("TI02")),
        "TI02 four visible spans match oracle chronology count")

  ; M3-04 unchanged: every published span vector must equal the independent
  ; geometry oracle in the same chronology; no re-sort or extra span.
  spanVectorMismatch = 0
  For planIndex = 0 To spanCount - 1
    If WallVisibilityGetSpan(@visibility, planIndex, @plan\Subsector,
                             @plan\Seg, @plan\Linedef, @plan\Side,
                             @plan\FrontSector, @plan\BackSector,
                             @plan\FirstX, @plan\LastX, @plan\Kind) = #False
      spanVectorMismatch + 1
    Else
      For spanField = 0 To #TEXGOLD_SpanFieldCount - 1
        If SceneSpanField("TI02", planIndex, spanField, @expected) = #False
          spanVectorMismatch + 1
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
            spanVectorMismatch + 1
          EndIf
        EndIf
      Next
    EndIf
  Next
  Check(Bool(spanVectorMismatch = 0),
        "TI02 M3-04 visibility span IDs/X/kind chronology unchanged vs oracle")
  Check(Bool(WallVisibilityIsValid(@visibility)), "TI02 M3-04 result remains valid")
  spanHash = TestWallSpanHash(@visibility)
  Check(Bool(spanHash <> -1 And spanHash = SceneSpanHash("TI02")),
        "TI02 M3-04 visibility span hash unchanged vs independent oracle")

  Check(FrameBufferCreate(@target, 320, 200), "TI02 canonical target frame created")
  Check(Bool(TexturedWallRenderResultReset(@result)), "TI02 textured result empty reusable")
  renderOk = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(renderOk), "TI02 transactional two-sided textured frame succeeds")
  If renderOk
    hash = result\Hash
    Check(Bool(hash = SceneHash("TI02")), "TI02 textured checksum equals independent oracle")
    Check(Bool(FnvFrame(@target) = hash), "TI02 independent full-plane FNV equals checksum")
    Check(Bool(TexturedWallRenderGetStats(@result, @spanCount, @segmentCount, 0,
                  @texturePlanCount, 0, @processedColumns, @textureColumns,
                  @drawnPixels, @middlePixels, @upperPixels, @lowerPixels,
                  @middleRanges, @upperRanges, @lowerRanges, @drawRanges,
                  @emptyColumns, @clippedColumns, @outOfFrameColumns, @samples,
                  @uncovered, @fallbacks, @nonzeroBytes, @zeroBytes, @composed,
                  @requested, @reused, @masked, @shortTex, @cacheAlloc, @totalAlloc,
                  @cacheTemp, @cachePlane, @cachePeak, @statsHash)),
          "TI02 detailed counters read without pixel dumps")
    Check(Bool(spanCount = #TEXGOLD_TI02_SpanCount And
                segmentCount = #TEXGOLD_TI02_SpanCount And
                texturePlanCount = #TEXGOLD_TI02_SpanCount),
          "TI02 one plan per oracle span")
    Check(Bool(processedColumns = #TEXGOLD_TI02_ProcessedColumns And
                textureColumns = #TEXGOLD_TI02_TextureColumns And
                drawnPixels = #TEXGOLD_TI02_DrawnPixels),
          "TI02 column/texture-column/write counters exact oracle")
    Check(Bool(middlePixels = #TEXGOLD_TI02_MiddlePixels And
                upperPixels = #TEXGOLD_TI02_UpperPixels And
                lowerPixels = #TEXGOLD_TI02_LowerPixels),
          "TI02 middle/upper/lower differing-height pixel counts exact oracle")
    Check(Bool(middleRanges = #TEXGOLD_TI02_MiddleRanges And
                upperRanges = #TEXGOLD_TI02_UpperRanges And
                lowerRanges = #TEXGOLD_TI02_LowerRanges And
                drawRanges = #TEXGOLD_TI02_DrawRanges),
          "TI02 tier range counts exact oracle")
    Check(Bool(emptyColumns = #TEXGOLD_TI02_EmptyColumns And
                clippedColumns = #TEXGOLD_TI02_ClippedColumns And
                outOfFrameColumns = #TEXGOLD_TI02_OutOfFrameColumns),
          "TI02 clip/empty/no-out-of-frame accounting exact oracle")
    Check(Bool(samples = #TEXGOLD_TI02_TextureSamples And uncovered = #TEXGOLD_TI02_UncoveredTexels And
                fallbacks = #TEXGOLD_TI02_ShortHeightFallbacks),
          "TI02 4143 short-row fallbacks/no uncovered samples exact oracle")
    Check(Bool(masked = #TEXGOLD_TI02_MaskedMidSpans And shortTex = #TEXGOLD_TI02_ShortTextures),
          "TI02 two masked middles deferred and two short textures exact oracle")
    Check(Bool(composed = #TEXGOLD_TI02_Composed And requested = #TEXGOLD_TI02_Requested And
                reused = #TEXGOLD_TI02_Reused),
          "TI02 cache unique refs/composition/reuse exact oracle")
    Check(Bool(cacheAlloc = #TEXGOLD_TI02_CacheAllocations And
                totalAlloc = #TEXGOLD_TI02_Allocations And
                totalAlloc = cacheAlloc + 5),
          "TI02 fixed allocation budget, no per-column growth")
    Check(Bool(nonzeroBytes = #TEXGOLD_TI02_NonZeroBytes And zeroBytes = #TEXGOLD_TI02_ZeroBytes),
          "TI02 frame palette byte audit exact oracle")

    ; Plan vectors and both signed quad vectors.
    planFieldMismatch = 0
    planQMismatch = 0
    maskedMismatch = 0
    For planIndex = 0 To #TEXGOLD_TI02_SpanCount - 1
      If TexturedWallRenderGetPlan(@result, planIndex, @plan) = #False Or
         TexturedWallRenderGetTexturePlan(@result, planIndex, @texPlan) = #False
        planFieldMismatch + 1
        planQMismatch + 1
        maskedMismatch + 1
      Else
        For planField = 0 To #TEXGOLD_PlanLFieldCount - 1
          If ScenePlanL("TI02", planIndex, planField, @expected) = #False
            planFieldMismatch + 1
          Else
            actual = ProductionPlanField(@plan, @texPlan, planField)
            If actual <> expected
              planFieldMismatch + 1
              PrintN("  diagnostic: TI02 plan field " + Str(planField) + " actual " +
                     Str(actual) + " expected " + Str(expected))
            EndIf
          EndIf
        Next
        For qField = 0 To #TEXGOLD_PlanQFieldCount - 1
          If ScenePlanQ("TI02", planIndex, qField, @expectedQuad) = #False
            planQMismatch + 1
          Else
            actualQuad = ProductionPlanQ(@plan, @texPlan, qField)
            If actualQuad <> expectedQuad
              planQMismatch + 1
            EndIf
          EndIf
        Next
        ; Deferred masked middles carry oracle flag and absent cache slots.
        If ScenePlanL("TI02", planIndex, #ITX_MaskedMidField, @maskedExpected) = #False
          maskedMismatch + 1
        Else
          If maskedExpected < 0
            maskedMismatch + 1
          Else
            If texPlan\MaskedMid <> maskedExpected
              maskedMismatch + 1
            EndIf
            If texPlan\MaskedMid <> 0 And texPlan\MidCacheSlot <> -1
              maskedMismatch + 1
            EndIf
          EndIf
        EndIf
      EndIf
    Next
    Check(Bool(planFieldMismatch = 0),
          "TI02 all 62 geometry/material/pegging/lightning scalar fields equal oracle")
    Check(Bool(planQMismatch = 0), "TI02 all 6 signed BAM fields equal oracle")
    Check(Bool(maskedMismatch = 0), "TI02 masked flag/slot deferral matches cache-policy oracle")
    Check(Bool(result\SegmentCount = result\TexturePlanCount), "TI02 one textured plan per legacy span")

    frameMismatch = FrameCompareFixture("TI02", @target)
    Check(Bool(frameMismatch = 0), "TI02 full 64,000 plane/portal holes equal Python oracle")
    sampleMismatch = FrameSampleMismatchFixture("TI02", @target)
    Check(Bool(sampleMismatch = 0), "TI02 all fixture portal/tier sample columns 200 rows equal oracle")
  Else
    Check(#False, "TI02 textured frame rendered")
  EndIf

TI02Done:
  SyntheticSessionCleanup(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
  TexturedWallRenderResultReset(@result)
  FrameBufferReset(@target)
EndProcedure

; ---------------------------------------------------------------------------
; TI03: A->B->A lifecycle, invalidation/stale, repeat, late rollback, malformed
; ---------------------------------------------------------------------------

Procedure TestTI03()
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected level.MapLevel
  Protected view.WallView
  Protected projection.Projection
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected result.TexturedWallRenderResult
  Protected blankLevel.MapLevel
  Protected blankView.WallView
  Protected blankProjection.Projection
  Protected blankVisibility.WallVisibilityResult
  Protected malformedTarget.FrameBuffer
  Protected malformedResult.TexturedWallRenderResult
  Protected *copyA.Byte = 0
  Protected hashA.q = 0
  Protected hashB.q = 0
  Protected hashA2.q = 0
  Protected hashA3.q = 0
  Protected hashPrior.q = 0
  Protected hashAfter.q = 0
  Protected staleLump.i = 0
  Protected typedResolveIndex.i = 0
  Protected typedResolveIndexReopen.i = 0
  Protected patternMismatch.l = 0
  Protected copyMismatch.l = 0
  Protected frameMismatch.l = 0
  Protected sensitive.l = 0
  Protected testOk.i = #False
  Protected renderA.i = #False
  Protected renderB.i = #False
  Protected renderA2.i = #False
  Protected renderA3.i = #False
  Protected renderLate.i = #False
  Protected malformedCatalog.i = #False
  Protected malformedColormap.i = #False
  Protected malformedResultOk.i = 0
  Protected malformedRun.i = 0
  Protected byteIndex.i
  Protected expectedColor.l = 0
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0
  Protected spanCount.l = 0
  Protected malformedPath.s = ""
  Protected colormapMagicBefore.l = 0
  Protected materialsStillResolve.l = 0

  BeginCase("TI03", "A-B-A lifecycle, invalidation, repeat determinism, rollback and missing resources")

  Check(Bool(BuildSceneWad("itx03a.wad", 1)), "TI03 file A synthetic PWAD built")
  Check(Bool(BuildSceneWad("itx03b.wad", 2)), "TI03 file B synthetic PWAD built")
  Check(Bool(BuildMalformedSceneWad("itx03notex.wad", #False, #True)),
        "TI03 synthetic PWAD missing TEXTURE1/PNAMES built")
  Check(Bool(BuildMalformedSceneWad("itx03nocol.wad", #True, #False)),
        "TI03 synthetic PWAD missing COLORMAP built")

  ; Session A: initial textured frame + resolved patch while WAD open.
  If PrepareSyntheticSession("itx03a.wad", "E1M1", @pnames, @textures, @flats,
                             @colormap, @level, @view, @projection, @visibility)
    Check(#True, "TI03 A session decode/load/view/visibility prepared")
  Else
    Check(#False, "TI03 A session prepared")
    Goto TI03Done
  EndIf
  typedResolveIndex = TextureCatalogGetResolvedPatchLump(@textures, 1, 0)
  Check(Bool(typedResolveIndex >= 0), "TI03 A patch0 resolves while WAD open")
  Check(FrameBufferCreate(@target, 320, 200), "TI03 A target frame created")
  Check(Bool(TexturedWallRenderResultReset(@result)), "TI03 A result empty reusable")
  renderA = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                    @textures, @colormap, @visibility, @target,
                                    @result, 1)
  Check(Bool(renderA), "TI03 A initial textured frame succeeds")
  If renderA
    hashA = result\Hash
    Check(Bool(hashA = SceneHash("TI01")), "TI03 A hash equals TI01 oracle")
    *copyA = AllocateMemory(#ITX_FramePixelCount)
    Check(Bool(*copyA <> 0), "TI03 private A full-plane copy allocated")
    If *copyA <> 0
      CopyMemory(target\Pixels, *copyA, #ITX_FramePixelCount)
    EndIf
  Else
    Check(#False, "TI03 A initial textured frame rendered")
  EndIf
  SyntheticSessionCleanup(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  ; Catalog invalidation after WAD close: no stale resolved patch index survives.
  staleLump = TextureCatalogGetResolvedPatchLump(@textures, 1, 0)
  Check(Bool(staleLump = -1), "TI03 invalidated catalog exposes no stale patch lump")
  Check(Bool(FindString(TextureDefsLastError(), "initialized") > 0),
        "TI03 invalidated resolution named explicit uninitialized catalog")
  Check(Bool(TextureCatalogCount(@textures) = 0), "TI03 reset catalog count zero")
  Check(Bool(WADIsOpen() = #False), "TI03 A WAD closed before B session")

  ; Session B: different two-sided scene, deterministic hash; catalog re-resolve.
  If PrepareSyntheticSession("itx03b.wad", "E2M1", @pnames, @textures, @flats,
                             @colormap, @level, @view, @projection, @visibility)
    Check(#True, "TI03 B session decode/load/view/visibility prepared")
  Else
    Check(#False, "TI03 B session prepared")
    Goto TI03Done
  EndIf
  typedResolveIndexReopen = TextureCatalogGetResolvedPatchLump(@textures, 1, 0)
  Check(Bool(typedResolveIndexReopen >= 0), "TI03 reopened B patch0 re-resolves current lump")
  renderB = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                    @textures, @colormap, @visibility, @target,
                                    @result, 1)
  Check(Bool(renderB), "TI03 B textured frame succeeds")
  If renderB
    hashB = result\Hash
    Check(Bool(hashB = SceneHash("TI02")), "TI03 B hash equals TI02 oracle")
    Check(Bool(hashB <> hashA), "TI03 independently keyed A/B full frames differ")
  Else
    Check(#False, "TI03 B textured frame rendered")
  EndIf
  SyntheticSessionCleanup(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)

  ; Reopen A from a fresh session after B close: repeat frame deterministic and
  ; full bytes identical to the privately retained initial A plane.
  If PrepareSyntheticSession("itx03a.wad", "E1M1", @pnames, @textures, @flats,
                             @colormap, @level, @view, @projection, @visibility)
    Check(#True, "TI03 fresh A-reopen session prepared")
  Else
    Check(#False, "TI03 fresh A-reopen session prepared")
    Goto TI03Done
  EndIf
  typedResolveIndexReopen = TextureCatalogGetResolvedPatchLump(@textures, 1, 0)
  Check(Bool(typedResolveIndexReopen >= 0), "TI03 fresh A patch resolve non-stale and valid")
  renderA2 = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(renderA2), "TI03 A-reopen frame succeeds")
  If renderA2
    hashA2 = result\Hash
    Check(Bool(hashA2 = hashA), "TI03 A-reopen deterministic hash equals initial A")
    copyMismatch = FrameCopyMismatch(*copyA, @target)
    Check(Bool(copyMismatch = 0), "TI03 A-reopen full 64,000 plane byte-for-byte identical")
  Else
    Check(#False, "TI03 A-reopen frame rendered")
  EndIf

  renderA3 = TexturedWallRenderFrame(@level, @view, @projection, @flats,
                                     @textures, @colormap, @visibility, @target,
                                     @result, 1)
  Check(Bool(renderA3), "TI03 A repeated second frame succeeds")
  If renderA3 And renderA2
    hashA3 = result\Hash
    Check(Bool(hashA3 = hashA2), "TI03 repeated second frame deterministic hash")
    copyMismatch = FrameCopyMismatch(*copyA, @target)
    Check(Bool(copyMismatch = 0), "TI03 repeated second frame exact initial A bytes")
  Else
    Check(#False, "TI03 repeated second frame rendered")
  EndIf

  ; Targeted late failure: a genuine absent-texture visible map still reaches the
  ; per-span draw phase and only then fails RequireDrawnPixels; prior procedural
  ; target must remain wholly untouched.
  hashPrior = FnvFrame(@target)
  Check(Bool(hashPrior = hashA3), "TI03 late-rollback prior target hash is repeated A")
  Check(Bool(BuildBlankWallMap(@blankLevel)), "TI03 direct blank-texture map built")
  Check(Bool(BuildBlankSceneView(@blankLevel, @blankView, @blankProjection, @blankVisibility)),
        "TI03 blank map projection/visibility fallback built")
  spanCount = WallVisibilityCount(@blankVisibility)
  Check(Bool(spanCount >= 1), "TI03 blank map still publishes a visible mark-only span")
  renderLate = TexturedWallRenderFrame(@blankLevel, @blankView, @blankProjection,
                                      0, @textures, @colormap, @blankVisibility,
                                      @target, @result, 1)
  Check(Bool(renderLate = #False), "TI03 RequireDrawnPixels refuses mark-only map")
  Check(Bool(FindString(TexturedWallRenderLastError(), "zero textured wall pixels") > 0),
        "TI03 late frame-phase failure named")
  hashAfter = FnvFrame(@target)
  Check(Bool(hashAfter = hashPrior), "TI03 prior procedural frame unchanged after late error")
  Check(Bool(TexturedWallRenderResultIsValid(@result) And result\Ready = 0 And
             result\Plans = 0 And result\TexturePlans = 0),
        "TI03 failed result transactionally reset")

  SyntheticSessionCleanup(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
  MapLevelReset(@blankLevel)
  WallViewReset(@blankView)
  ProjectionReset(@blankProjection)
  WallVisibilityReset(@blankVisibility)

  ; Missing TEXTURE1/PNAMES: map/palette/flats/COLORMAP present, catalog absent;
  ; the orchestrator refuses before any private frame write and leaves prior
  ; procedural target untouched.
  If WADOpen(WallTexFixturePath("itx03notex.wad")) = #False
    Check(#False, "TI03 missing-texture WAD opens")
    Goto TI03Done
  EndIf
  Check(#True, "TI03 synthetic WAD omits TEXTURE1/PNAMES and opens")
  malformedCatalog = WallTexDecodeWallCatalog(@pnames, @textures)
  Check(Bool(malformedCatalog = #False), "TI03 missing catalog decode fails safely")
  Check(Bool((FindString(PNamesLastError(), "PNAMES") > 0) Or
             (FindString(WADLastError(), "PNAMES") > 0)),
        "TI03 missing catalog diagnostic names PNAMES/TEXTURE resource")
  Check(Bool(MapLevelLoad("E1M1", @level)), "TI03 malformed WAD map decodes independently")
  Check(Bool(WallViewSetMapUnits(@view, 0, 0, 0, 0)), "TI03 malformed view set")
  Check(Bool(ProjectionInitClassic(@projection)), "TI03 malformed projection initialized")
  hashPrior = FnvFrame(@target)
  malformedResultOk.i = TexturedWallRenderResultReset(@malformedResult)
  Check(Bool(malformedResultOk), "TI03 malformed result empty reusable")
  malformedRun.i = TexturedWallRenderFrame(@level, @view, @projection, 0,
                                           @textures, @colormap, 0,
                                           @target, @malformedResult, 1)
  Check(Bool(malformedRun = #False), "TI03 missing texture catalog render fails")
  Check(Bool(FindString(TexturedWallRenderLastError(), "texture catalog") > 0),
        "TI03 missing texture failure named catalog")
  hashAfter = FnvFrame(@target)
  Check(Bool(hashAfter = hashPrior), "TI03 missing-texture rollback preserves prior target")
  Check(Bool(TexturedWallRenderResultIsValid(@malformedResult) And
             malformedResult\Ready = 0 And malformedResult\Plans = 0),
        "TI03 missing-texture result reset")
  ColormapReset(@colormap) : FlatCatalogReset(@flats) : PNamesReset(@pnames)
  TextureCatalogReset(@textures)
  MapLevelReset(@level) : WallViewReset(@view) : ProjectionReset(@projection)
  WADClose()

  ; Missing COLORMAP: catalogs/flats/map/patch resources present but lighting
  ; tables absent; orchestrator gate rejects and target stays prior frame.
  If WADOpen(WallTexFixturePath("itx03nocol.wad")) = #False
    Check(#False, "TI03 missing-COLORMAP WAD opens")
    Goto TI03Done
  EndIf
  Check(#True, "TI03 synthetic WAD omits COLORMAP and opens")
  materialsStillResolve.l = WallTexDecodeWallCatalog(@pnames, @textures)
  materialsStillResolve.l = materialsStillResolve.l + WallTexDecodeWallFlats(@flats)
  Check(Bool(materialsStillResolve = 2),
        "TI03 missing-COLORMAP WAD still decodes catalog+flats")
  Check(Bool(WallTexDecodeWallColormap(@colormap) = #False), "TI03 COLORMAP decode failure explicit")
  colormapMagicBefore = ColormapCount(@colormap)
  Check(Bool(colormapMagicBefore = 0), "TI03 absent COLORMAP leaves zero tables")
  Check(Bool(MapLevelLoad("E1M1", @level)), "TI03 missing-COLORMAP map decodes")
  Check(Bool(WallViewSetMapUnits(@view, 0, 0, 0, 0)), "TI03 malformed view set B")
  Check(Bool(ProjectionInitClassic(@projection)), "TI03 malformed projection B")
  hashPrior = FnvFrame(@target)
  malformedRun.i = TexturedWallRenderFrame(@level, @view, @projection, 0,
                                           @textures, @colormap, 0,
                                           @target, @malformedResult, 1)
  Check(Bool(malformedRun = #False), "TI03 missing lighting render fails")
  Check(Bool(FindString(TexturedWallRenderLastError(), "COLORMAP") > 0),
        "TI03 missing COLORMAP gate diagnostics")
  hashAfter = FnvFrame(@target)
  Check(Bool(hashAfter = hashPrior), "TI03 missing-COLORMAP rollback preserves prior target")
  ColormapReset(@colormap) : FlatCatalogReset(@flats) : PNamesReset(@pnames)
  TextureCatalogReset(@textures)
  MapLevelReset(@level) : WallViewReset(@view) : ProjectionReset(@projection)
  WADClose()

  ; All owned buffers must reset cleanly after close/lifecycle.
  FrameBufferReset(@target)
  TexturedWallRenderResultReset(@result)
  TexturedWallRenderResultReset(@malformedResult)
  FrameBufferReset(@malformedTarget)
  Check(Bool(target\Pixels = 0 And target\PixelCount = 0 And target\Magic = 0),
        "TI03 final target plane freed/reset")
  Check(Bool(result\Plans = 0 And result\TexturePlans = 0 And result\Ready = 0),
        "TI03 final render result metadata freed/reset")
  Check(Bool(textures\Magic = 0 And pnames\Magic = 0 And flats\Magic = 0 And colormap\Magic = 0),
        "TI03 final decoded catalogs/COLORMAP structures cleared")
  Check(Bool(WADIsOpen() = #False), "TI03 no WAD session remains open")
  If *copyA <> 0
    FreeMemory(*copyA)
    *copyA = 0
  EndIf

TI03Done:
  If *copyA <> 0
    FreeMemory(*copyA)
  EndIf
  TexturedWallRenderResultReset(@result)
  TexturedWallRenderResultReset(@malformedResult)
  FrameBufferReset(@target)
  FrameBufferReset(@malformedTarget)
  MapLevelReset(@blankLevel)
  MapLevelReset(@level)
  SyntheticSessionCleanup(@pnames, @textures, @flats, @colormap, @level,
                          @view, @projection, @visibility)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

Procedure Main()
  TestTI01()
  TestTI02()
  TestTI03()
EndProcedure

OpenConsole()
Main()

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) +
       ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
