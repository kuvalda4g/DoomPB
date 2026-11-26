; -----------------------------------------------------------------------------
; DoomPB - M3-07 optional real-IWAD RI04 release integration
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Optional harness; the owner-provided legal IWAD path is its first argument.
; Reads strictly read-only through WADOpen, decodes PNAMES/TEXTURE1/TEXTURE2,
; the flat namespace and COLORMAP through production APIs while the WAD remains
; open, initializes the immutable classic 320-column projection and per-map
; loads/validates E1M1/E1M2/E4M1 through the M2 MapLevel APIs.
;
; For each owner map: derive the exact player-one camera/viewz, build the
; unchanged catalog-aware M3-04 visibility, assert the frozen M3-04 span/counter
; FNV fingerprints, rerun the legacy M3-05 debug-color render and assert its
; frozen frame hash, run the M3-06 transactional textured frame twice on a
; reused target with byte-for-byte equality, and independently recompute the
; full 64,000-byte row-major FNV from the published palette plane.
;
; Release-only independent real-resource sampling (test-only oracle):
;   - reads resolved raw owner PATCH lumps and reproduces vanilla patch post/
;     placement composition, transparency and width-mask generation for a
;     deterministic selection of composed textures, then compares pixels/masks/
;     opaque counts to the production cache image;
;   - compares owner raw COLORMAP bytes table-by-table/texel-by-texel with the
;     decoded ColormapLookup domain;
;   - for a safe first-span one-sided middle in each map, independently rebuilds
;     per-column rw_scale/dc_iscale/rw_offset/texturecolumn/width-mask/frac/
;     source-row/light-row/scalelight/raw-COLORMAP mapping and compares the
;     resulting palette byte to the published target pixel.
;
; New textured frame hashes are printed only after repeat equality and remain
; NOT LOCKED: this histogram/selection sampler does not reconstruct whole-span
; clip chronology or a full C wall-only image. The precise residual comparison
; gap is printed instead of claimed C-frame equivalence.
;
; The IWAD is never written: before/after size and MD5 are compared. Only coarse
; decoded resource totals, counters, bounded sample mismatch counts and
; FNV-1a64 hashes are printed; no WAD payload, map coordinates/records, decoded
; pixels, textures, flats or sample arrays are printed, copied, stored or
; committed. Without an argument this optional pass is reported NOT RUN and is
; not failure. Exit code: 0 when every assertion passed (or NOT RUN), otherwise
; the failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/BSP.pbi"
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
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"
XIncludeFile "wall_texture_support.pbi"

#TI04_FNV_Offset = -3750763034362895579
#TI04_FNV_Prime = 1099511628211
#TI04_Md5MaxBytes = 268435456
#TI04_FramePixelCount = 64000

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

; ---------------------------------------------------------------------------
; Harness and independent fingerprints
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

Procedure.q FnvAddByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #TI04_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvAddByte(Hash, Value & $FF)
  Hash = FnvAddByte(Hash, (Value >> 8) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 16) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

; Independent canonical 16-digit uppercase FNV rendering, including leading
; zeros, without calling the production presentation helper.
Procedure.s TestHex64Canonical(Value.q)
  Protected result.s = ""
  Protected shift.i
  Protected nibble.i
  Protected digit.i

  For shift = 15 To 0 Step -1
    nibble = (Value >> (shift * 4)) & $F
    If nibble < 10
      digit = nibble + 48
    Else
      digit = nibble + 55
    EndIf
    result = result + Chr(digit)
  Next
  ProcedureReturn result
EndProcedure

Procedure.i TestHashTextEquals(Value.q, Expected.s)
  Protected actual.s = TestHex64Canonical(Value)

  ProcedureReturn Bool(Len(Expected) = 16 And Len(actual) = 16 And actual = Expected)
EndProcedure

; Independent full-plane FNV over exactly the canonical 64,000 row-major bytes.
Procedure.q TestFrameHash(*Frame.FrameBuffer)
  Protected hash.q = #TI04_FNV_Offset
  Protected i.i

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #PROJ_VIEWWIDTH Or *Frame\Height <> #PROJ_VIEWHEIGHT Or
     *Frame\PixelCount <> #TI04_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For i = 0 To #TI04_FramePixelCount - 1
    hash = FnvAddByte(hash, PeekA(*Frame\Pixels + i))
  Next
  ProcedureReturn hash
EndProcedure

; FNV over the published M3-04 WallSpan numeric fields in chronology.
Procedure.q TestWallSpanHash(*Result.WallVisibilityResult)
  Protected hash.q = #TI04_FNV_Offset
  Protected i.i
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
  For i = 0 To *Result\Count - 1
    If WallVisibilityGetSpan(*Result, i, @sub, @seg, @line, @side,
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

; Separate M3-04 aggregate counter fingerprint.
Procedure.q TestWallCountsHash(*Result.WallVisibilityResult, *Ok.Long)
  Protected hash.q = #TI04_FNV_Offset

  *Ok\l = Bool(WallVisibilityIsValid(*Result))
  If *Ok\l = 0
    ProcedureReturn -1
  EndIf
  hash = FnvAddLong(hash, *Result\Count)
  hash = FnvAddLong(hash, *Result\VisitedNodes)
  hash = FnvAddLong(hash, *Result\VisitedSubsectors)
  hash = FnvAddLong(hash, *Result\ProcessedSegs)
  hash = FnvAddLong(hash, *Result\EmittedFragments)
  hash = FnvAddLong(hash, *Result\BackfaceRejects)
  hash = FnvAddLong(hash, *Result\FovLeftRejects)
  hash = FnvAddLong(hash, *Result\FovRightRejects)
  hash = FnvAddLong(hash, *Result\FovRejects)
  hash = FnvAddLong(hash, *Result\PixelWidthRejects)
  hash = FnvAddLong(hash, *Result\EmptyLineRejects)
  hash = FnvAddLong(hash, *Result\SolidCandidates)
  hash = FnvAddLong(hash, *Result\PassCandidates)
  hash = FnvAddLong(hash, *Result\BboxTests)
  hash = FnvAddLong(hash, *Result\BboxVisible)
  hash = FnvAddLong(hash, *Result\BboxOccluded)
  hash = FnvAddLong(hash, *Result\BboxUnknown)
  hash = FnvAddLong(hash, *Result\OcclusionSkips)
  hash = FnvAddLong(hash, *Result\WorkItems)
  hash = FnvAddLong(hash, *Result\ClipRangeGrowths)
  hash = FnvAddLong(hash, *Result\ClipSpanGrowths)
  hash = FnvAddLong(hash, *Result\Allocations)
  ProcedureReturn hash
EndProcedure

; Frozen baseline M3-04 and M3-05 fingerprints from the accepted owner-IWAD
; harness runs. Empty text means an unrecognized map name and no silent guess.
Procedure.s TestExpectedM3SpanHash(Name.s)
  If Name = "E1M1"
    ProcedureReturn "74B485154CE29B0B"
  ElseIf Name = "E1M2"
    ProcedureReturn "8AC0627513C4B619"
  ElseIf Name = "E4M1"
    ProcedureReturn "9FD0B15A0F33197E"
  EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s TestExpectedM3CountsHash(Name.s)
  If Name = "E1M1"
    ProcedureReturn "7ADB45DBF2611B77"
  ElseIf Name = "E1M2"
    ProcedureReturn "83CAB0E1049B850A"
  ElseIf Name = "E4M1"
    ProcedureReturn "CCAA2442EB270717"
  EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s TestExpectedDebugFrameHash(Name.s)
  If Name = "E1M1"
    ProcedureReturn "4A923E4D357C7BD1"
  ElseIf Name = "E1M2"
    ProcedureReturn "0C9627E5C2FD8D35"
  ElseIf Name = "E4M1"
    ProcedureReturn "9AEB8BDD16834359"
  EndIf
  ProcedureReturn ""
EndProcedure

; Optional read-only file fingerprint for identity verification only.
Procedure.s TestFileMd5(Path.s)
  Protected fileSize.q
  Protected bytes.i
  Protected readCount.i
  Protected file.i
  Protected fingerprint.s

  fileSize = FileSize(Path)
  If fileSize < 0 Or fileSize > #TI04_Md5MaxBytes
    ProcedureReturn ""
  EndIf
  bytes = AllocateMemory(fileSize)
  If bytes = 0
    ProcedureReturn ""
  EndIf
  file = ReadFile(#PB_Any, Path)
  If file = 0
    FreeMemory(bytes)
    ProcedureReturn ""
  EndIf
  readCount = ReadData(file, bytes, fileSize)
  CloseFile(file)
  If readCount <> fileSize
    FreeMemory(bytes)
    ProcedureReturn ""
  EndIf
  UseMD5Fingerprint()
  fingerprint = Fingerprint(bytes, fileSize, #PB_Cipher_MD5)
  FreeMemory(bytes)
  ProcedureReturn fingerprint
EndProcedure

; ---------------------------------------------------------------------------
; One owner map: unchanged M3-04/M3-05 fingerprints and M3-06 textured frames
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Test-only independent resource oracles (no production compose/mapping helper)
; ---------------------------------------------------------------------------

; R_InitTextures `j=1; while j*2 <= width j<<=1; mask=j-1` recomputation.
Procedure.i IndependentWidthMaskValue(Width.l, *Mask.Long)
  Protected power.l = 1

  If *Mask = 0 Or Width <= 0 Or Width > 4096
    ProcedureReturn #False
  EndIf
  While power * 2 <= Width
    power = power << 1
  Wend
  If power <= 0 Or power > Width
    ProcedureReturn #False
  EndIf
  *Mask\l = power - 1
  ProcedureReturn #True
EndProcedure

; Independent raw-PATCH composition: reads each resolved owner patch lump
; through WADReadLump, parses vanilla 8-byte patch header/column table/posts
; (topdelta,length,unused,pixels,unused), applies placements in order with
; transparency (mask1 overwrites), clips negative/over-height origins, then
; compares all pixel/mask bytes and opaque count to the production composed
; TextureImage borrowed for the cache duration. Output counters only.
Procedure.i IndependentComposeMismatch(*Catalog.TextureCatalog,
                                       TextureIndex.i,
                                       *OwnerImage.TextureImage,
                                       *PixelMismatch.Long,
                                       *MaskMismatch.Long,
                                       *OpaqueMismatch.Long,
                                       *CompareOk.Long)
  Protected width.l = 0
  Protected height.l = 0
  Protected masked.l = 0
  Protected columnDirectory.l = 0
  Protected patchCount.l = 0
  Protected sourceKind.l = 0
  Protected pixelCount.q = 0
  Protected patchIndex.i
  Protected originX.l = 0
  Protected originY.l = 0
  Protected pNameIndex.l = 0
  Protected stepDir.l = 0
  Protected colorMap.l = 0
  Protected resolvedLump.i = 0
  Protected lumpSize.q = 0
  Protected *raw.Byte = 0
  Protected patchWidth.l = 0
  Protected patchHeight.l = 0
  Protected columnTableEnd.q = 0
  Protected textureColumn.i
  Protected patchColumn.i
  Protected columnOffset.q = 0
  Protected cursor.q = 0
  Protected topDelta.i = 0
  Protected postLength.i = 0
  Protected terminated.i = #False
  Protected postPixel.i
  Protected destX.i
  Protected destY.i
  Protected pixelOffset.q = 0
  Protected byteIndex.q = 0
  Protected pixelMismatch.l = 0
  Protected maskMismatch.l = 0
  Protected oracleOpaque.l = 0
  Protected productionOpaque.l = 0
  Protected *oraclePixels.Byte = 0
  Protected *oracleMasks.Byte = 0

  *PixelMismatch\l = -1
  *MaskMismatch\l = -1
  *OpaqueMismatch\l = -1
  *CompareOk\l = 0

  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    ProcedureReturn #False
  EndIf
  If *OwnerImage = 0 Or *OwnerImage\Magic <> #TEXTURE_ImageMagic Or
     *OwnerImage\Pixels = 0 Or *OwnerImage\Mask = 0 Or *OwnerImage\Width <= 0 Or
     *OwnerImage\Height <= 0
    ProcedureReturn #False
  EndIf
  If TextureCatalogGetProperties(*Catalog, TextureIndex, @width, @height,
                                 @masked, @columnDirectory, @patchCount,
                                 @sourceKind) = #False
    ProcedureReturn #False
  EndIf
  If width <= 0 Or width > 4096 Or height <= 0 Or height > 4096 Or
     patchCount < 0 Or patchCount > 1024
    ProcedureReturn #False
  EndIf
  If width <> *OwnerImage\Width Or height <> *OwnerImage\Height
    ProcedureReturn #False
  EndIf
  pixelCount = Int(width) * Int(height)
  If pixelCount <= 0 Or pixelCount > #TEXTURE_MaxOutputPixels
    ProcedureReturn #False
  EndIf
  *oraclePixels = AllocateMemory(pixelCount)
  *oracleMasks = AllocateMemory(pixelCount)
  If *oraclePixels = 0 Or *oracleMasks = 0
    If *oraclePixels <> 0
      FreeMemory(*oraclePixels)
    EndIf
    If *oracleMasks <> 0
      FreeMemory(*oracleMasks)
    EndIf
    ProcedureReturn #False
  EndIf
  FillMemory(*oraclePixels, Int(pixelCount), 0)
  FillMemory(*oracleMasks, Int(pixelCount), 0)

  For patchIndex = 0 To patchCount - 1
    If TextureCatalogGetPatch(*Catalog, TextureIndex, patchIndex, @originX,
                              @originY, @pNameIndex, @stepDir, @colorMap) = #False
      Goto IndependentComposeFailure
    EndIf
    resolvedLump = TextureCatalogGetResolvedPatchLump(*Catalog, TextureIndex,
                                                     patchIndex)
    If resolvedLump < 0
      Goto IndependentComposeFailure
    EndIf
    lumpSize = WADLumpSize(resolvedLump)
    If lumpSize <= 0 Or lumpSize > 67108864
      Goto IndependentComposeFailure
    EndIf
    *raw = AllocateMemory(lumpSize)
    If *raw = 0
      Goto IndependentComposeFailure
    EndIf
    If WADReadLump(resolvedLump, *raw, lumpSize) = #False
      Goto IndependentComposeFailure
    EndIf
    If lumpSize < 8
      Goto IndependentComposeFailure
    EndIf
    patchWidth = Int(EndianReadU16LE(*raw, 0))
    patchHeight = Int(EndianReadU16LE(*raw, 2))
    If patchWidth <= 0 Or patchWidth > 4096 Or patchHeight <= 0 Or
       patchHeight > 4096
      Goto IndependentComposeFailure
    EndIf
    columnTableEnd = 8 + Int(patchWidth) * 4
    If columnTableEnd > lumpSize
      Goto IndependentComposeFailure
    EndIf

    For textureColumn = 0 To width - 1
      patchColumn = textureColumn - originX
      If patchColumn < 0 Or patchColumn >= patchWidth
        Continue
      EndIf
      columnOffset = EndianReadU32LE(*raw, 8 + patchColumn * 4)
      If columnOffset < 0 Or columnOffset >= lumpSize
        Goto IndependentComposeFailure
      EndIf
      cursor = columnOffset
      terminated = #False
      While cursor < lumpSize
        topDelta = PeekA(*raw + cursor)
        If topDelta = $FF
          terminated = #True
          Break
        EndIf
        If cursor + 3 > lumpSize
          Goto IndependentComposeFailure
        EndIf
        postLength = PeekA(*raw + cursor + 1)
        If topDelta + postLength > patchHeight
          Goto IndependentComposeFailure
        EndIf
        If cursor + Int(postLength) + 4 > lumpSize
          Goto IndependentComposeFailure
        EndIf
        For postPixel = 0 To postLength - 1
          destX = textureColumn
          destY = originY + topDelta + postPixel
          If destY >= 0 And destY < height And destX >= 0 And destX < width
            pixelOffset = Int(destY) * Int(width) + Int(destX)
            PokeA(*oraclePixels + pixelOffset,
                  PeekA(*raw + cursor + 3 + postPixel))
            PokeA(*oracleMasks + pixelOffset, 1)
          EndIf
        Next
        cursor = cursor + Int(postLength) + 4
      Wend
      If terminated = #False
        Goto IndependentComposeFailure
      EndIf
    Next
    FreeMemory(*raw)
    *raw = 0
  Next

  pixelMismatch = 0
  maskMismatch = 0
  oracleOpaque = 0
  For byteIndex = 0 To Int(pixelCount) - 1
    If PeekA(*oraclePixels + byteIndex) <> PeekA(*OwnerImage\Pixels + byteIndex)
      pixelMismatch + 1
    EndIf
    If PeekA(*oracleMasks + byteIndex) <> PeekA(*OwnerImage\Mask + byteIndex)
      maskMismatch + 1
    EndIf
    If PeekA(*oracleMasks + byteIndex) = 1
      oracleOpaque + 1
    EndIf
  Next
  productionOpaque = Int(*OwnerImage\OpaqueCount)
  FreeMemory(*oraclePixels)
  FreeMemory(*oracleMasks)
  *PixelMismatch\l = pixelMismatch
  *MaskMismatch\l = maskMismatch
  *OpaqueMismatch\l = oracleOpaque - productionOpaque
  *CompareOk\l = 1
  ProcedureReturn #True

  IndependentComposeFailure:
  If *raw <> 0
    FreeMemory(*raw)
    *raw = 0
  EndIf
  If *oraclePixels <> 0
    FreeMemory(*oraclePixels)
    *oraclePixels = 0
  EndIf
  If *oracleMasks <> 0
    FreeMemory(*oracleMasks)
    *oracleMasks = 0
  EndIf
  ProcedureReturn #False
EndProcedure

; Raw owner COLORMAP bytes vs decoded ColormapLookup, table/texel exhaustive.
Procedure.i IndependentColormapMismatch(*RawBytes.Byte, RawSize.q,
                                        *Colormap.ColormapSet,
                                        *TableMismatch.Long,
                                        *TexelMismatch.Long,
                                        *CompareOk.Long)
  Protected rawTables.q = 0
  Protected decodedTables.l = 0
  Protected tableIndex.l
  Protected texelIndex.l
  Protected rawByte.i = 0
  Protected decodedByte.i = 0
  Protected tableMismatch.l = 0
  Protected texelMismatch.l = 0
  Protected rawOffset.q = 0

  *TableMismatch\l = -1
  *TexelMismatch\l = -1
  *CompareOk\l = 0
  If *RawBytes = 0 Or RawSize <= 0 Or RawSize % 256 <> 0 Or
     *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic Or *Colormap\Tables = 0
    ProcedureReturn #False
  EndIf
  rawTables = RawSize / 256
  decodedTables = *Colormap\MapCount
  If decodedTables <= 0 Or decodedTables > #COLORMAP_MaxTables
    ProcedureReturn #False
  EndIf
  If rawTables <> Int(decodedTables)
    *TableMismatch\l = 1
    ProcedureReturn #False
  EndIf
  For tableIndex = 0 To decodedTables - 1
    For texelIndex = 0 To 255
      rawOffset = Int(tableIndex) * 256 + Int(texelIndex)
      If rawOffset < 0 Or rawOffset >= RawSize
        texelMismatch + 1
      Else
        rawByte = PeekA(*RawBytes + rawOffset)
        decodedByte = ColormapLookup(*Colormap, tableIndex, texelIndex)
        If decodedByte < 0 Or decodedByte <> rawByte
          texelMismatch + 1
        EndIf
      EndIf
    Next
  Next
  *TableMismatch\l = 0
  *TexelMismatch\l = texelMismatch
  *CompareOk\l = 1
  ProcedureReturn #True
EndProcedure

; Test-only first-span one-sided-middle pixel oracle. Rebuilds the source
; column/vertical/lighting/COLORMAP formulas from accepted plan geometry fields
; and raw COLORMAP bytes; compares only one bounded palette byte with the
; published target. does not reconstruct earlier/far clip chronology.
Procedure.i IndependentOwnerPixelSample(*Level.MapLevel,
                                        *Projection.Projection,
                                        *Visibility.WallVisibilityResult,
                                        *Plans.WallSpanPlan,
                                        *TexturePlans.WallTextureSpanPlan,
                                        PlanCount.l,
                                        *Cache.WallTextureCache,
                                        *Colormap.ColormapSet,
                                        *RawColormap.Byte, RawSize.q,
                                        *Target.FrameBuffer,
                                        *Attempted.Long, *Matched.Long,
                                        *Mismatch.Long, *Reason.Long)
  Protected *plan.WallSpanPlan
  Protected *texturePlan.WallTextureSpanPlan
  Protected firstX.l = 0
  Protected lastX.l = 0
  Protected sampleX.l = 0
  Protected elapsed.l = 0
  Protected scaleCurrent.l = 0
  Protected topFracCurrent.l = 0
  Protected bottomFracCurrent.l = 0
  Protected yTop.l = 0
  Protected yBottom.l = 0
  Protected sampleY.l = 0
  Protected rawColumn.l = 0
  Protected wrapped.l = 0
  Protected xAngle.q = 0
  Protected angleSum.q = 0
  Protected angleShifted.q = 0
  Protected tangentIndex.l = 0
  Protected tangent.l = 0
  Protected product.l = 0
  Protected columnFixed.l = 0
  Protected iScale.l = 0
  Protected numerator.q = $FFFFFFFF
  Protected quotient.q = 0
  Protected frac.l = 0
  Protected difference.q = 0
  Protected fracProduct.q = 0
  Protected fracProductLow.l = 0
  Protected sourceRow.l = 0
  Protected row128.l = 0
  Protected textureHeight.l = 0
  Protected imageOffset.q = 0
  Protected sourcePixel.l = 0
  Protected sourceMask.l = 0
  Protected midIndex.l = 0
  Protected entryIndex.l = 0
  Protected ownerImagePtr.i = 0
  Protected *ownerImage.TextureImage
  Protected midWidth.l = 0
  Protected midWidthMask.l = 0
  Protected midHeight.l = 0
  Protected textureMid.l = 0
  Protected spanSeg.l = 0
  Protected spanFront.l = 0
  Protected spanSub.l = 0
  Protected spanLine.l = 0
  Protected spanSide.l = 0
  Protected spanBack.l = 0
  Protected spanFirst.l = 0
  Protected spanLast.l = 0
  Protected spanKind.l = 0
  Protected *sector.MapSector
  Protected *vertex.MapVertex
  Protected *segment.MapSeg
  Protected *v1.MapVertex
  Protected *v2.MapVertex
  Protected frontLight.l = 0
  Protected lightNum.l = 0
  Protected scaleIndex.l = 0
  Protected startMap.l = 0
  Protected stepNumerator.l = 0
  Protected stepDenominator.l = 0
  Protected stepValue.l = 0
  Protected mapIndex.l = 0
  Protected mapOffset.q = 0
  Protected rawTableCount.q = 0
  Protected expectedByte.l = 0
  Protected actualByte.l = 0

  *Attempted\l = 0
  *Matched\l = 0
  *Mismatch\l = 0
  *Reason\l = 0

  If *Level = 0 Or MapLevelIsReady(*Level) = #False Or *Projection = 0 Or
     ProjectionIsValid(*Projection) = #False Or *Visibility = 0 Or
     WallVisibilityIsValid(*Visibility) = #False Or *Plans = 0 Or
     *TexturePlans = 0 Or PlanCount <= 0 Or *Cache = 0 Or
     WallTextureCacheIsValid(*Cache) = #False Or *Target = 0 Or
     *Target\Magic <> #FRAMEBUFFER_Magic Or *Target\Width <> 320 Or
     *Target\Height <> 200 Or *Target\Pixels = 0 Or *RawColormap = 0 Or
     RawSize < 32 * 256
    *Reason\l = 1
    ProcedureReturn #True
  EndIf

  *plan = *Plans + Int(0) * SizeOf(WallSpanPlan)
  *texturePlan = *TexturePlans + Int(0) * SizeOf(WallTextureSpanPlan)
  If WallSpanPlanIsReady(*plan) = #False Or
     *texturePlan\Magic <> #WALLTEXSPAN_Magic
    *Reason\l = 2
    ProcedureReturn #True
  EndIf
  firstX = *plan\FirstX
  lastX = *plan\LastX
  If firstX < 0 Or lastX > 319 Or firstX > lastX Or
     *texturePlan\SegmentTextured = 0 Or *plan\MiddleTier = 0 Or
     *texturePlan\MaskedMid <> 0 Or
     *texturePlan\MidTextureIndex = #WALLTEXSPAN_NoTexture
    *Reason\l = 3
    ProcedureReturn #True
  EndIf

  sampleX = (firstX + lastX) / 2
  elapsed = sampleX - firstX
  scaleCurrent = WallFixedAddLow(*plan\Scale1,
                                 FixedWrap32Low(Int(elapsed) * Int(*plan\ScaleStep)))
  topFracCurrent = WallFixedAddLow(*plan\TopFrac,
                                   FixedWrap32Low(Int(elapsed) * Int(*plan\TopStep)))
  bottomFracCurrent = WallFixedAddLow(*plan\BottomFrac,
                                      FixedWrap32Low(Int(elapsed) * Int(*plan\BottomStep)))
  If scaleCurrent <= 0
    *Reason\l = 4
    ProcedureReturn #True
  EndIf
  yTop = FixedWrap32Low(Int(topFracCurrent) + 4095) >> 12
  yBottom = FixedWrap32Low(Int(bottomFracCurrent) + 4095) >> 12
  If yTop < 0
    yTop = 0
  EndIf
  If yBottom > 199
    yBottom = 199
  EndIf
  If yTop > yBottom
    *Reason\l = 5
    ProcedureReturn #True
  EndIf
  sampleY = (yTop + yBottom) / 2

  If ProjectionGetXToViewAngle(*Projection, sampleX, @xAngle) = #False
    *Reason\l = 6
    ProcedureReturn #True
  EndIf
  angleSum = BamAdd(*texturePlan\CenterAngle, xAngle)
  angleShifted = angleSum >> #BAM_ANGLETOFINESHIFT
  tangentIndex = Int(angleShifted)
  If tangentIndex < 0 Or tangentIndex > #TRIG_FINETANGENT_COUNT - 1
    *Reason\l = 7
    ProcedureReturn #True
  EndIf
  If TrigTangentChecked(tangentIndex, @tangent) = #False
    *Reason\l = 8
    ProcedureReturn #True
  EndIf
  product = FixedMul(tangent, *plan\Distance)
  columnFixed = FixedWrap32Low(Int(*texturePlan\RawOffset) - Int(product))
  rawColumn = columnFixed >> #FRACBITS
  midWidth = *texturePlan\MidWidth
  midHeight = *texturePlan\MidHeight
  midWidthMask = *texturePlan\MidWidthMask
  If midWidth <= 0 Or midHeight <= 0 Or midWidthMask < 0 Or
     midWidthMask >= midWidth
    *Reason\l = 9
    ProcedureReturn #True
  EndIf
  wrapped = rawColumn & midWidthMask
  If wrapped < 0 Or wrapped >= midWidth
    *Reason\l = 10
    ProcedureReturn #True
  EndIf

  quotient = numerator / Int(scaleCurrent)
  If quotient <= 0 Or quotient > #FIXED_MAX
    *Reason\l = 11
    ProcedureReturn #True
  EndIf
  iScale = FixedWrap32Low(quotient)
  textureMid = *texturePlan\MidTextureMid
  difference = Int(sampleY) - Int(#PROJ_CENTERY)
  fracProduct = difference * Int(iScale)
  fracProductLow = FixedWrap32Low(fracProduct)
  frac = FixedWrap32Low(Int(textureMid) + Int(fracProductLow))
  row128 = (frac >> #FRACBITS) & 127
  If row128 < 0 Or row128 > 127
    *Reason\l = 12
    ProcedureReturn #True
  EndIf
  textureHeight = midHeight
  If textureHeight >= 128
    sourceRow = row128
  Else
    sourceRow = row128 % textureHeight
  EndIf
  If sourceRow < 0 Or sourceRow >= textureHeight
    *Reason\l = 13
    ProcedureReturn #True
  EndIf

  midIndex = *texturePlan\MidTextureIndex
  entryIndex = WallTextureCacheFindIndex(*Cache, midIndex)
  If entryIndex < 0
    *Reason\l = 14
    ProcedureReturn #True
  EndIf
  ownerImagePtr = WallTextureCacheImagePtr(*Cache, entryIndex)
  If ownerImagePtr = 0
    *Reason\l = 15
    ProcedureReturn #True
  EndIf
  *ownerImage = ownerImagePtr
  If *ownerImage\Width <> midWidth Or *ownerImage\Height <> midHeight Or
     *ownerImage\Pixels = 0 Or *ownerImage\Mask = 0
    *Reason\l = 16
    ProcedureReturn #True
  EndIf
  imageOffset = Int(sourceRow) * Int(midWidth) + Int(wrapped)
  If imageOffset < 0 Or imageOffset >= *ownerImage\PixelCount
    *Reason\l = 17
    ProcedureReturn #True
  EndIf
  sourcePixel = PeekA(*ownerImage\Pixels + imageOffset)
  sourceMask = PeekA(*ownerImage\Mask + imageOffset)
  If sourcePixel < 0 Or sourcePixel > 255 Or sourceMask <> 0 And sourceMask <> 1
    *Reason\l = 18
    ProcedureReturn #True
  EndIf

  ; First chronological span must exist at index0; front sectors and seg raw
  ; vertices are read from MapLevel, not from a precomputed light row field.
  If WallVisibilityGetSpan(*Visibility, 0, @spanSub, @spanSeg, @spanLine,
                           @spanSide, @spanFront, @spanBack, @spanFirst,
                           @spanLast, @spanKind) = #False
    *Reason\l = 19
    ProcedureReturn #True
  EndIf
  If spanFront < 0 Or spanFront >= *Level\Sectors\Count Or
     spanSeg < 0 Or spanSeg >= *Level\Segs\Count
    *Reason\l = 20
    ProcedureReturn #True
  EndIf
  *sector.MapSector = *Level\Sectors\Items + Int(spanFront) * SizeOf(MapSector)
  frontLight = *sector\LightLevel
  *segment.MapSeg = *Level\Segs\Items + Int(spanSeg) * SizeOf(MapSeg)
  If *segment\V1 < 0 Or *segment\V1 >= *Level\Vertexes\Count Or
     *segment\V2 < 0 Or *segment\V2 >= *Level\Vertexes\Count
    *Reason\l = 21
    ProcedureReturn #True
  EndIf
  *v1.MapVertex = *Level\Vertexes\Items + *segment\V1 * SizeOf(MapVertex)
  *v2.MapVertex = *Level\Vertexes\Items + *segment\V2 * SizeOf(MapVertex)
  If frontLight < 0
    *Reason\l = 22
    ProcedureReturn #True
  EndIf
  lightNum = frontLight >> 4
  If *v1\Y = *v2\Y
    lightNum = lightNum - 1
  ElseIf *v1\X = *v2\X
    lightNum = lightNum + 1
  EndIf
  If lightNum < 0
    lightNum = 0
  ElseIf lightNum >= 16
    lightNum = 15
  EndIf

  scaleIndex = scaleCurrent >> #LIGHT_SCALESHIFT
  If scaleIndex >= #LIGHT_MAXLIGHTSCALE
    scaleIndex = #LIGHT_MAXLIGHTSCALE - 1
  EndIf
  startMap = ((16 - 1 - lightNum) * 2) * 32 / 16
  stepNumerator = scaleIndex * 320
  stepDenominator = 320 << 0
  If stepDenominator <= 0
    *Reason\l = 23
    ProcedureReturn #True
  EndIf
  stepValue = stepNumerator / stepDenominator / 2
  mapIndex = startMap - stepValue
  If mapIndex < 0
    mapIndex = 0
  ElseIf mapIndex > 31
    mapIndex = 31
  EndIf

  rawTableCount = RawSize / 256
  mapOffset = Int(mapIndex) * 256 + Int(sourcePixel)
  If mapOffset < 0 Or mapOffset >= RawSize
    *Reason\l = 24
    ProcedureReturn #True
  EndIf
  expectedByte = PeekA(*RawColormap + mapOffset)
  actualByte = FrameBufferGetPixel(*Target, Int(sampleX), Int(sampleY))
  If actualByte < 0
    *Reason\l = 25
    ProcedureReturn #True
  EndIf
  *Attempted\l = 1
  If expectedByte = actualByte
    *Matched\l = 1
    *Mismatch\l = 0
  Else
    *Matched\l = 0
    *Mismatch\l = 1
  EndIf
  ProcedureReturn #True
EndProcedure; ---------------------------------------------------------------------------
; Owner-map pipeline + release-only independent resource sampling
; ---------------------------------------------------------------------------

Procedure CheckOwnerMap(Name.s, *Projection.Projection,
                       *Flats.FlatCatalog, *Textures.TextureCatalog,
                       *Colormap.ColormapSet,
                       *RawColormap.Byte, RawColormapSize.q)
  Protected level.MapLevel
  Protected view.WallView
  Protected visibility.WallVisibilityResult
  Protected debugTarget.FrameBuffer
  Protected debugResult.WallRenderResult
  Protected texturedTarget.FrameBuffer
  Protected texturedResult.TexturedWallRenderResult
  Protected *frameCopy.Byte = 0
  Protected spanHash.q = 0
  Protected countsHash.q = 0
  Protected countsOk.l = 0
  Protected debugHash.q = 0
  Protected texturedHashOne.q = 0
  Protected texturedHashTwo.q = 0
  Protected debugFrameHash.q = 0
  Protected texturedFrameHashOne.q = 0
  Protected texturedFrameHashTwo.q = 0
  Protected expectedSpan.s = ""
  Protected expectedCounts.s = ""
  Protected expectedDebug.s = ""
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
  Protected debugDrawn.l = 0
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0
  Protected byteIndex.i
  Protected copyMismatch.l = 0
  Protected texturedText.s = ""
  Protected debugText.s = ""
  Protected levelOk.i = #False
  Protected viewOk.i = #False
  Protected visibilityOk.i = #False
  Protected debugRun.i = #False
  Protected texturedRunOne.i = #False
  Protected texturedRunTwo.i = #False
  Protected cache.WallTextureCache
  Protected compStatCount.l = 0
  Protected compStatCapacity.l = 0
  Protected compStatRequested.l = 0
  Protected compStatReused.l = 0
  Protected compStatMasked.l = 0
  Protected compStatShort.l = 0
  Protected compAllocations.l = 0
  Protected compTemp.q = 0
  Protected compPlane.q = 0
  Protected compPeak.q = 0
  Protected compSampleLimit.l = 6
  Protected compSampled.l = 0
  Protected compParseBad.l = 0
  Protected compPixelMismatch.l = 0
  Protected compMaskMismatch.l = 0
  Protected compOpaqueMismatch.l = 0
  Protected compWidthBad.l = 0
  Protected compEntryIndex.l
  Protected compCatalogIndex.l = 0
  Protected compWidth.l = 0
  Protected compHeight.l = 0
  Protected compMask.l = 0
  Protected compShort.l = 0
  Protected compOpaque.q = 0
  Protected compPixels.q = 0
  Protected compImagePtr.i = 0
  Protected *compImage.TextureImage
  Protected compIndMask.l = 0
  Protected compPixelBad.l = 0
  Protected compMaskBad.l = 0
  Protected compOpaqueBad.l = 0
  Protected compOk.l = 0
  Protected colormapTableMismatch.l = 0
  Protected colormapTexelMismatch.l = 0
  Protected colormapOk.i = #False
  Protected attemptSample.l = 0
  Protected matchSample.l = 0
  Protected mismatchSample.l = 0
  Protected sampleReason.l = 0

  MapLevelReset(@level)
  Check(Bool(MapLevelLoad(Name.s, @level)), Name + " loads through validated M2 MapLevel API")
  Check(Bool(MapLevelIsReady(@level) And level\Name = Name), Name + " level identity/readiness canonical")
  levelOk = #True
  Check(Bool(MapLevelValidateResources(@level, *Flats, *Textures)),
        Name + " decoded flat/texture references resolve")

  viewOk = WallRenderPlayerStartView(@level, @view, @thingIndex,
                                     @subsectorIndex, @sectorIndex)
  Check(Bool(viewOk), Name + " player-one start view derived from THINGS")
  Check(Bool(thingIndex >= 0 And subsectorIndex >= 0 And sectorIndex >= 0),
        Name + " validated player THING/subsector/floor sector indices present")
  Check(Bool(WallViewIsValid(@view) And view\Camera <> 0),
        Name + " static view camera ready, no bob/flash mutation")

  visibilityOk = WallVisibilityBuild(@level, @view\Camera, *Projection, *Flats,
                                     *Textures, @visibility)
  Check(Bool(visibilityOk), Name + " unchanged catalog-aware M3-04 visibility build")
  spanCount = WallVisibilityCount(@visibility)
  Check(Bool(spanCount >= 1), Name + " at least one visible wall span published")

  expectedSpan = TestExpectedM3SpanHash(Name.s)
  expectedCounts = TestExpectedM3CountsHash(Name.s)
  spanHash = TestWallSpanHash(@visibility)
  countsHash = TestWallCountsHash(@visibility, @countsOk)
  Check(Bool(expectedSpan <> "" And countsOk <> 0 And
             TestHashTextEquals(spanHash, expectedSpan)),
        Name + " frozen M3-04 span fingerprint " + expectedSpan + " preserved")
  Check(Bool(expectedCounts <> "" And TestHashTextEquals(countsHash, expectedCounts)),
        Name + " frozen M3-04 counter fingerprint " + expectedCounts + " preserved")

  ; Legacy M3-05 debug-color frame: exact frozen frame fingerprint and text.
  Check(FrameBufferCreate(@debugTarget, 320, 200), Name + " debug target frame created")
  Check(Bool(WallRenderResultReset(@debugResult)), Name + " debug result empty reusable")
  expectedDebug = TestExpectedDebugFrameHash(Name.s)
  debugRun = WallRenderFrame(@level, @view, *Projection, *Flats, *Textures,
                             @visibility, @debugTarget, @debugResult, 0)
  Check(Bool(debugRun), Name + " unchanged M3-05 debug-color frame render succeeds")
  If debugRun
    debugHash = debugResult\Hash
    Check(Bool(debugHash <> -1), Name + " debug hash readable")
    debugFrameHash = TestFrameHash(@debugTarget)
    debugDrawn = debugResult\DrawnPixels
    Check(Bool(debugFrameHash = debugHash), Name + " independent debug plane FNV equals production hash")
    debugText = TestHex64Canonical(debugHash)
    Check(Bool(expectedDebug <> "" And TestHashTextEquals(debugHash, expectedDebug)),
          Name + " frozen M3-05 debug frame hash " + expectedDebug + " preserved")
    Check(Bool(debugDrawn > 0), Name + " debug-color frame painted wall pixels")
  Else
    Check(#False, Name + " debug-color frame rendered")
    Goto CheckOwnerMapDone
  EndIf

  ; M3-06 textured frame #1 on a caller target; owned result/counters published.
  Check(FrameBufferCreate(@texturedTarget, 320, 200), Name + " textured target frame created")
  Check(Bool(TexturedWallRenderResultReset(@texturedResult)), Name + " textured result empty reusable")
  texturedRunOne = TexturedWallRenderFrame(@level, @view, *Projection, *Flats,
                                           *Textures, *Colormap, @visibility,
                                           @texturedTarget, @texturedResult, 1)
  Check(Bool(texturedRunOne), Name + " transactional textured frame #1 succeeds")
  If texturedRunOne
    texturedHashOne = texturedResult\Hash
    texturedFrameHashOne = TestFrameHash(@texturedTarget)
    texturedText = TexturedWallRenderGetHashText(@texturedResult)
    Check(Bool(texturedFrameHashOne = texturedHashOne),
          Name + " textured independent full-plane FNV equals production hash")
    Check(Bool(texturedText = TestHex64Canonical(texturedHashOne) And Len(texturedText) = 16),
          Name + " textured canonical 16-character hex text")
    Check(Bool(texturedHashOne <> debugHash),
          Name + " textured frame differs from M3-05 debug-color frame where expected")
    Check(Bool(TexturedWallRenderGetStats(@texturedResult, @spanCount, @segmentCount, 0,
                  @texturePlanCount, 0, @processedColumns, @textureColumns,
                  @drawnPixels, @middlePixels, @upperPixels, @lowerPixels,
                  @middleRanges, @upperRanges, @lowerRanges, @drawRanges,
                  @emptyColumns, @clippedColumns, @outOfFrameColumns, @samples,
                  @uncovered, @fallbacks, @nonzeroBytes, @zeroBytes, @composed,
                  @requested, @reused, @masked, @shortTex, @cacheAlloc, @totalAlloc,
                  @cacheTemp, @cachePlane, @cachePeak, @statsHash)),
          Name + " textured detailed counters read without pixel dumps")
    Check(Bool(spanCount >= 1 And segmentCount = spanCount And texturePlanCount = spanCount),
          Name + " one legacy/textured plan per published M3-04 span")
    Check(Bool(drawnPixels > 0 And nonzeroBytes > 0),
          Name + " textured palette/texture pixels actually present")
    Check(Bool(drawnPixels = middlePixels + upperPixels + lowerPixels),
          Name + " middle+upper+lower pixels reconcile to all drawn wall pixels")
    Check(Bool(drawRanges = middleRanges + upperRanges + lowerRanges),
          Name + " per-tier draw ranges reconcile to every painted range")
    Check(Bool(processedColumns > 0 And textureColumns > 0),
          Name + " textured coordinate columns computed, mark-only spans excluded")
    Check(Bool(outOfFrameColumns = 0), Name + " no textured range escaped 320x200")
    Check(Bool(composed >= 1 And requested >= 1), Name + " useful textures composed/cached while WAD open")
    Check(Bool(totalAlloc = cacheAlloc + 5),
          Name + " allocations are fixed frame/plan/table/clip budget, no per-column growth")
    Check(Bool(masked >= 0 And shortTex >= 0), Name + " masked-middle/short-texture counters bounded")

    ; Release-only independent raw-resource sampling while owner WAD is open:
    ; cache is rebuilt from the published plan array, then raw PATCH lumps,
    ; raw COLORMAP bytes and one safe first-span middle pixel are compared by
    ; separate test-only formulas. No texture pixels/coordinates are printed.
    WallTextureCacheReset(@cache)
    Check(Bool(WallTextureCacheBuild(@level, *Textures, texturedResult\Plans,
                                     segmentCount, @cache)),
          Name + " independent-sampler cache rebuilt from published plan array")
    Check(Bool(WallTextureCacheGetStats(@cache, @compStatCount, @compStatCapacity,
                                        @compStatRequested, @compStatReused,
                                        @compStatMasked, @compStatShort,
                                        @compAllocations, @compTemp, @compPlane,
                                        @compPeak) And compStatCount >= 1),
          Name + " composed cache has material for bounded real-resource sampling")
    compSampled = 0
    compParseBad = 0
    compPixelMismatch = 0
    compMaskMismatch = 0
    compOpaqueMismatch = 0
    compWidthBad = 0
    compSampleLimit = compStatCount
    If compSampleLimit > 6
      compSampleLimit = 6
    EndIf
    For compEntryIndex = 0 To compSampleLimit - 1
      compCatalogIndex = 0
      compWidth = 0
      compHeight = 0
      compMask = 0
      compShort = 0
      compOpaque = 0
      compPixels = 0
      compImagePtr = 0
      compIndMask = 0
      compPixelBad = 0
      compMaskBad = 0
      compOpaqueBad = 0
      compOk = 0
      If WallTextureCacheEntryGet(@cache, compEntryIndex, @compCatalogIndex,
                                  @compWidth, @compHeight, @compMask,
                                  @compShort, @compOpaque, @compPixels) = #False
        compParseBad + 1
        Continue
      EndIf
      compImagePtr = WallTextureCacheImagePtr(@cache, compEntryIndex)
      If compImagePtr = 0
        compParseBad + 1
        Continue
      EndIf
      *compImage = compImagePtr
      If IndependentWidthMaskValue(compWidth, @compIndMask) = #False Or
         compIndMask <> compMask
        compWidthBad + 1
      EndIf
      If IndependentComposeMismatch(*Textures, Int(compCatalogIndex),
                                    *compImage, @compPixelBad, @compMaskBad,
                                    @compOpaqueBad, @compOk) = #False
        compParseBad + 1
        Continue
      EndIf
      compSampled + 1
      compPixelMismatch + compPixelBad
      compMaskMismatch + compMaskBad
      compOpaqueMismatch + compOpaqueBad
    Next
    Check(Bool(compSampled >= 1 And compParseBad = 0 And
               compPixelMismatch = 0 And compMaskMismatch = 0 And
               compWidthBad = 0 And compOpaqueMismatch = 0),
          Name + " independent raw-PATCH composition equals production for " +
          Str(compSampled) + " bounded textures (0 pixel/mask/mask-width mismatch)")

    colormapTableMismatch = 0
    colormapTexelMismatch = 0
    colormapOk = IndependentColormapMismatch(*RawColormap, RawColormapSize,
                                             *Colormap, @colormapTableMismatch,
                                             @colormapTexelMismatch, @compOk)
    Check(Bool(colormapOk And colormapTableMismatch = 0 And
               colormapTexelMismatch = 0),
          Name + " raw owner COLORMAP tables/texels equal decoded lookup exhaustively")

    attemptSample = 0
    matchSample = 0
    mismatchSample = 0
    sampleReason = 0
    Check(Bool(IndependentOwnerPixelSample(@level, *Projection, @visibility,
                                           texturedResult\Plans,
                                           texturedResult\TexturePlans,
                                           segmentCount, @cache, *Colormap,
                                           *RawColormap, RawColormapSize,
                                           @texturedTarget, @attemptSample,
                                           @matchSample, @mismatchSample,
                                           @sampleReason)),
          Name + " test-only column/row/lighting sampler evaluated")
    If attemptSample <> 0
      Check(Bool(matchSample = 1 And mismatchSample = 0),
            Name + " bounded independent column/row/COLORMAP palette byte equals target")
      PrintN("  " + Name + " independent first-span middle pixel samples matched " +
             Str(matchSample) + ", mismatches " + Str(mismatchSample))
    Else
      PrintN("  " + Name +
             " frame-pixel independent sample NOT RUN: no safe first-span one-sided middle (reason " +
             Str(sampleReason) + ")")
    EndIf

    PrintN("  " + Name + " independent raw composition samples " + Str(compSampled) +
           ", pixel mismatch " + Str(compPixelMismatch) + ", mask mismatch " +
           Str(compMaskMismatch) + ", opaque-count mismatch " + Str(compOpaqueMismatch) +
           ", width-mask mismatch " + Str(compWidthBad))
    PrintN("  " + Name + " independent raw COLORMAP mismatches: tables " +
           Str(colormapTableMismatch) + ", texels " + Str(colormapTexelMismatch))
    WallTextureCacheReset(@cache)

    ; Preserve full first plane bytes privately for byte-for-byte repeat auditing.
    *frameCopy = AllocateMemory(#TI04_FramePixelCount)
    Check(Bool(*frameCopy <> 0), Name + " private 64,000-byte repeat copy allocated")
    If *frameCopy <> 0
      CopyMemory(texturedTarget\Pixels, *frameCopy, #TI04_FramePixelCount)
    EndIf
  Else
    Check(#False, Name + " textured frame #1 rendered")
  EndIf

  ; Reset result/renderer state implicitly, reuse same target, rerun textured #2.
  texturedRunTwo = TexturedWallRenderFrame(@level, @view, *Projection, *Flats,
                                           *Textures, *Colormap, @visibility,
                                           @texturedTarget, @texturedResult, 1)
  Check(Bool(texturedRunTwo), Name + " textured frame #2 repeat succeeds on reused target")
  If texturedRunTwo And texturedRunOne
    texturedHashTwo = texturedResult\Hash
    texturedFrameHashTwo = TestFrameHash(@texturedTarget)
    Check(Bool(texturedHashTwo = texturedHashOne), Name + " repeat textured 64-bit hash identical")
    Check(Bool(texturedFrameHashTwo = texturedHashTwo),
          Name + " repeat independent plane FNV equals repeat production hash")
    copyMismatch = 0
    If *frameCopy <> 0
      For byteIndex = 0 To #TI04_FramePixelCount - 1
        If PeekA(texturedTarget\Pixels + byteIndex) <> PeekA(*frameCopy + byteIndex)
          copyMismatch + 1
        EndIf
      Next
    Else
      copyMismatch = -1
    EndIf
    Check(Bool(copyMismatch = 0), Name + " repeat full 64,000-byte textured frame byte-for-byte identical")
  Else
    Check(#False, Name + " textured frame #2 repeat rendered")
  EndIf

  PrintN("  " + Name + " observed textured hash (NOT LOCKED): " +
         TestHex64Canonical(texturedHashOne))
  PrintN("  " + Name + " counters: spans " + Str(spanCount) + ", columns " +
         Str(processedColumns) + ", middle/upper/lower " + Str(middlePixels) + "/" +
         Str(upperPixels) + "/" + Str(lowerPixels) + ", masked " + Str(masked) +
         ", short textures " + Str(shortTex) + ", short-row fallbacks " + Str(fallbacks) +
         ", uncovered " + Str(uncovered) + ", allocations " + Str(totalAlloc))
  PrintN("  " + Name + " nonzero textured frame palette bytes " + Str(nonzeroBytes))
  PrintN("  " + Name + " residual reference gap: whole clipped-span chronology and " +
         "a complete same-camera C wall-only image comparison are REFERENCE UNAVAILABLE; " +
         "independent composition/COLORMAP and bounded first-span column/row samples are separate evidence")

CheckOwnerMapDone:
  If *frameCopy <> 0
    FreeMemory(*frameCopy)
  EndIf
  WallTextureCacheReset(@cache)
  TexturedWallRenderResultReset(@texturedResult)
  FrameBufferReset(@texturedTarget)
  WallRenderResultReset(@debugResult)
  FrameBufferReset(@debugTarget)
  If visibilityOk
    WallVisibilityReset(@visibility)
  EndIf
  If viewOk
    WallViewReset(@view)
  EndIf
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; Optional owner-IWAD pass
; ---------------------------------------------------------------------------

Procedure TestRI04(Path.s)
  Protected beforeSize.q = 0
  Protected afterSize.q = 0
  Protected beforeMd5.s = ""
  Protected afterMd5.s = ""
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected projection.Projection
  Protected pNamesCount.l = 0
  Protected textureCount.l = 0
  Protected flatCount.l = 0
  Protected colormapCount.l = 0
  Protected projectionWidth.l = 0
  Protected projectionHeight.l = 0
  Protected centerX.l = 0
  Protected centerY.l = 0
  Protected colormapLump.i = -1
  Protected rawColormapSize.q = 0
  Protected *rawColormap.Byte = 0
  Protected knownMd5.i = #False

  If Path.s = ""
    PrintN("[RI04] Optional real Ultimate Doom release integration: NOT RUN (no WAD path argument)")
    ProcedureReturn
  EndIf

  BeginCase("RI04", "Optional real Ultimate Doom read-only textured walls + frozen M3-04/M3-05 fingerprints")

  beforeSize = FileSize(Path.s)
  Check(Bool(beforeSize > 0), "owner IWAD path positive before reading")
  beforeMd5 = TestFileMd5(Path.s)
  Check(Bool(beforeMd5 <> ""), "owner IWAD read-only MD5 computed before opening")
  PrintN("  owner IWAD size " + Str(beforeSize) + ", MD5 " + beforeMd5)
  knownMd5 = Bool(beforeMd5 = "c4fe9fd920207691a9f493668e0a2083" And
                  beforeSize = 12408292)
  If knownMd5
    PrintN("  known Ultimate Doom 1.9ud local identity 12408292 bytes/MD5 observed")
  Else
    PrintN("  other legal compatible owner IWAD accepted (identification is informational only)")
  EndIf

  If WADOpen(Path.s) = #False
    Check(#False, "real IWAD opens read-only: " + WADLastError())
    ProcedureReturn
  EndIf
  Check(#True, "real IWAD opens read-only")
  PrintN("  lumps: " + Str(WADGetLumpCount()))

  Check(Bool(WallTexDecodeWallCatalog(@p, @catalog)), "real PNAMES/TEXTURE1/TEXTURE2 decode+resolve")
  Check(Bool(WallTexDecodeWallFlats(@flats)), "real F_START/F_END flat catalog build")
  Check(Bool(WallTexDecodeWallColormap(@colormap)), "real COLORMAP decode")
  pNamesCount = PNamesCount(@p)
  textureCount = TextureCatalogCount(@catalog)
  flatCount = FlatCatalogCount(@flats)
  colormapCount = ColormapCount(@colormap)
  Check(Bool(pNamesCount > 0 And textureCount > 0 And flatCount > 0),
        "decoded patch/texture/flat counts positive")
  Check(Bool(colormapCount >= 32 And WallLightingValidateColormap(@colormap, 0)),
        "real COLORMAP exposes at least 32 classic wall lighting tables")
  PrintN("  PNAMES " + Str(pNamesCount) + ", textures " + Str(textureCount) +
         ", flats " + Str(flatCount) + ", COLORMAP tables " + Str(colormapCount))

  ; Raw owner COLORMAP bytes are retained only for the test-only independent
  ; decode/sample oracle; released before WADClose and never printed.
  colormapLump = WADFindLump("COLORMAP")
  Check(Bool(colormapLump >= 0), "raw COLORMAP lump found for independent oracle")
  If colormapLump >= 0
    rawColormapSize = WADLumpSize(colormapLump)
    If rawColormapSize >= 32 * 256 And rawColormapSize <= 1048576 And
       rawColormapSize % 256 = 0
      *rawColormap = AllocateMemory(rawColormapSize)
    EndIf
    Check(Bool(*rawColormap <> 0),
          "raw COLORMAP bytes allocated for test-only independent oracle")
    If *rawColormap <> 0
      Check(Bool(WADReadLump(colormapLump, *rawColormap, rawColormapSize)),
            "raw COLORMAP read through read-only WADReadLump")
      Check(Bool(Int(rawColormapSize / 256) = colormapCount),
            "raw/decoded COLORMAP table counts agree before sampling")
    EndIf
  EndIf

  Check(Bool(ProjectionInitClassic(@projection)), "immutable classic projection initializes once")
  Check(Bool(ProjectionGetConstants(@projection, @projectionWidth, @projectionHeight,
                                   @centerX, @centerY, 0, 0, 0, 0, 0)),
        "projection constants readable")
  Check(Bool(projectionWidth = #PROJ_VIEWWIDTH And projectionHeight = #PROJ_VIEWHEIGHT And
             centerX = #PROJ_CENTERX And centerY = #PROJ_CENTERY),
        "projection publishes canonical 320x200 centered viewport")
  PrintN("  projection viewport " + Str(projectionWidth) + "x" + Str(projectionHeight))

  CheckOwnerMap("E1M1", @projection, @flats, @catalog, @colormap,
                *rawColormap, rawColormapSize)
  CheckOwnerMap("E1M2", @projection, @flats, @catalog, @colormap,
                *rawColormap, rawColormapSize)
  CheckOwnerMap("E4M1", @projection, @flats, @catalog, @colormap,
                *rawColormap, rawColormapSize)

  If *rawColormap <> 0
    FreeMemory(*rawColormap)
    *rawColormap = 0
  EndIf
  WADClose()
  Check(Bool(WADIsOpen() = #False), "WAD closes cleanly after read-only textured pass")
  afterSize = FileSize(Path.s)
  afterMd5 = TestFileMd5(Path.s)
  Check(Bool(afterSize = beforeSize), "owner IWAD byte size unchanged after read-only pass")
  Check(Bool(afterMd5 <> "" And afterMd5 = beforeMd5), "owner IWAD MD5 fingerprint unchanged")
  PrintN("  owner IWAD remains unchanged: size " + Str(afterSize))

  ColormapReset(@colormap)
  ProjectionReset(@projection)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-07 optional real-IWAD RI04 release integration")

TestRI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (RI04 may be NOT RUN without a WAD argument)")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
