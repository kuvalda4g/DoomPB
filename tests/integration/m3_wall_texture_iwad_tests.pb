; -----------------------------------------------------------------------------
; DoomPB - M3-06 optional real-IWAD textured wall integration (TI04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Optional harness; the owner-provided legal IWAD path is its first argument.
; Reads strictly read-only through WADOpen, decodes PNAMES/TEXTURE1/TEXTURE2,
; the flat namespace and COLORMAP through production APIs while the WAD remains
; open, initializes the immutable classic 320-column projection and per-map
; loads/validates E1M1/E1M2/E4M1 through the M2 MapLevel APIs.
;
; For each map: derive the exact player-one camera/viewz, build the unchanged
; catalog-aware M3-04 visibility, assert the frozen M3-04 span/counter FNV
; fingerprints, rerun the legacy M3-05 debug-color render and assert its frozen
; frame hash, then run the M3-06 transactional textured frame twice with a
; caller target reuse, compare full 64,000-byte frame bytes/hash across repeats,
; require textured pixels/counter reconciliation and no out-of-frame writes,
; and prove the textured frame differs from the debug-color frame where expected.
;
; New textured frame hashes are printed only after repeat equality and are NOT
; frozen here; owner visual window review and independent C-equivalent sampling
; must precede any golden lock, as required by the M3-06 task.
;
; The IWAD is never written: before/after size and MD5 are compared. Only coarse
; decoded resource totals, counters and FNV-1a64 hashes are printed; no WAD
; payload, map coordinates/records, decoded pixels, textures, flats or capture
; bytes are printed, copied, stored or committed. Without an argument this
; optional pass is reported NOT RUN and is not failure.
; Exit code: 0 when every assertion passed (or NOT RUN), otherwise failures.
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

Procedure CheckOwnerMap(Name.s, *Projection.Projection,
                       *Flats.FlatCatalog, *Textures.TextureCatalog,
                       *Colormap.ColormapSet)
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

  PrintN("  " + Name + " stable textured hash (NOT LOCKED pending independent C-equivalent sampling): " +
         TestHex64Canonical(texturedHashOne))
  PrintN("  " + Name + " counters: spans " + Str(spanCount) + ", columns " +
         Str(processedColumns) + ", middle/upper/lower " + Str(middlePixels) + "/" +
         Str(upperPixels) + "/" + Str(lowerPixels) + ", masked " + Str(masked) +
         ", short textures " + Str(shortTex) + ", short-row fallbacks " + Str(fallbacks) +
         ", uncovered " + Str(uncovered) + ", allocations " + Str(totalAlloc))
  PrintN("  " + Name + " nonzero textured frame palette bytes " + Str(nonzeroBytes))

CheckOwnerMapDone:
  If *frameCopy <> 0
    FreeMemory(*frameCopy)
  EndIf
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

Procedure TestTI04(Path.s)
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

  If Path.s = ""
    PrintN("[TI04] Optional real Ultimate Doom textured-wall integration: NOT RUN (no WAD path argument)")
    ProcedureReturn
  EndIf

  BeginCase("TI04", "Optional real Ultimate Doom read-only textured walls + frozen M3-04/M3-05 fingerprints")

  beforeSize = FileSize(Path.s)
  Check(Bool(beforeSize > 0), "owner IWAD path positive before reading")
  beforeMd5 = TestFileMd5(Path.s)
  Check(Bool(beforeMd5 <> ""), "owner IWAD read-only MD5 computed before opening")
  PrintN("  owner IWAD size " + Str(beforeSize) + ", MD5 " + beforeMd5)

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

  Check(Bool(ProjectionInitClassic(@projection)), "immutable classic projection initializes once")
  Check(Bool(ProjectionGetConstants(@projection, @projectionWidth, @projectionHeight,
                                   @centerX, @centerY, 0, 0, 0, 0, 0)),
        "projection constants readable")
  Check(Bool(projectionWidth = #PROJ_VIEWWIDTH And projectionHeight = #PROJ_VIEWHEIGHT And
             centerX = #PROJ_CENTERX And centerY = #PROJ_CENTERY),
        "projection publishes canonical 320x200 centered viewport")
  PrintN("  projection viewport " + Str(projectionWidth) + "x" + Str(projectionHeight))

  CheckOwnerMap("E1M1", @projection, @flats, @catalog, @colormap)
  CheckOwnerMap("E1M2", @projection, @flats, @catalog, @colormap)
  CheckOwnerMap("E4M1", @projection, @flats, @catalog, @colormap)

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
PrintN("DoomPB M3-06 optional real-IWAD textured wall integration (TI04)")

TestTI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (TI04 may be NOT RUN without a WAD argument)")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
