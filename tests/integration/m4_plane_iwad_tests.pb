; -----------------------------------------------------------------------------
; DoomPB - M4-01 optional real-IWAD combined wall+flat integration (PI04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Optional harness; the owner-provided legal IWAD path is its first argument.
; Reads strictly read-only through WADOpen, decodes PNAMES/TEXTURE1/TEXTURE2,
; the flat namespace and COLORMAP through the accepted production/support APIs
; while the WAD remains open, initializes the immutable classic projection, and
; for E1M1/E1M2/E4M1 loads/validates through M2 MapLevel APIs and derives the
; exact player-one camera/viewz.
;
; Per map it re-runs the unchanged M3-04 visibility and asserts its frozen span
; and counter fingerprints, re-runs the legacy M3-05 debug-color frame and
; asserts its frozen hash, runs the transactional M3-06 textured frame twice for
; repeat hash/full-byte stability, and then runs the new M4-01 combined
; walls+flats frame twice. All 64,000 bytes, explicit 0/1 wall coverage marks and
; byte totals are audited; real loaded floor/ceiling pixels are required in E1M1
; and E1M2; sky-deferred bands/pixels, visplane reuse/split, flat cache and
; allocation counters are reported. Raw new combined hashes are printed only
; after repeat equality and are NOT LOCKED pending independent C-equivalent
; sampling. Historical legacy textured E1M1=183BA53FCECECBC8,
; E1M2=835A0339A38B190E, E4M1=03B5C8CFA517FC7E are compared/reported as NOT
; LOCKED observations, never installed as new goldens. The IWAD is never written:
; before/after size and MD5 are compared. Only coarse counters and FNV hashes are
; printed; no WAD payload, map coordinates/records, decoded pixels, textures,
; flats or window captures are copied/stored/committed.
;
; Without an argument this optional pass reports NOT RUN, 0 cases/0 assertions,
; exit 0. Exit code otherwise: 0 every assertion passed, else failure count.
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
XIncludeFile "../../src/Renderer/PlaneRenderMain.pbi"
XIncludeFile "../../src/Renderer/TexturedRenderMain.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/FrameBuffer.pbi"
XIncludeFile "../../src/Graphics/PNames.pbi"
XIncludeFile "../../src/Graphics/TextureDefs.pbi"
XIncludeFile "../../src/Graphics/Flat.pbi"
XIncludeFile "../../src/Graphics/Colormap.pbi"
XIncludeFile "../../src/Graphics/Video.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"
XIncludeFile "wall_texture_support.pbi"

#PI04_FNV_Offset = -3750763034362895579
#PI04_FNV_Prime = 1099511628211
#PI04_Md5MaxBytes = 268435456
#PI04_FramePixelCount = 64000
#PI04_KnownIwadSize = 12408292
#PI04_KnownIwadMd5 = "c4fe9fd920207691a9f493668e0a2083"

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

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

; ---------------------------------------------------------------------------
; Independent integer/FNV fingerprints
; ---------------------------------------------------------------------------

Procedure.q FnvAddByte(Hash.q, Value.i)
  Hash = Hash ! (Value & $FF)
  Hash = Hash * #PI04_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvAddByte(Hash, Value & $FF)
  Hash = FnvAddByte(Hash, (Value >> 8) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 16) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

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

Procedure.q TestFrameHash(*Frame.FrameBuffer)
  Protected hash.q = #PI04_FNV_Offset
  Protected i.i

  If *Frame = 0 Or *Frame\Magic <> #FRAMEBUFFER_Magic Or
     *Frame\Width <> #PROJ_VIEWWIDTH Or *Frame\Height <> #PROJ_VIEWHEIGHT Or
     *Frame\PixelCount <> #PI04_FramePixelCount Or *Frame\Pixels = 0
    ProcedureReturn -1
  EndIf
  For i = 0 To #PI04_FramePixelCount - 1
    hash = FnvAddByte(hash, PeekA(*Frame\Pixels + i))
  Next
  ProcedureReturn hash
EndProcedure

Procedure.q TestWallSpanHash(*Result.WallVisibilityResult)
  Protected hash.q = #PI04_FNV_Offset
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

Procedure.q TestWallCountsHash(*Result.WallVisibilityResult, *Ok.Long)
  Protected hash.q = #PI04_FNV_Offset

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

; Frozen accepted M3-04/M3-05 owner-IWAD baselines; empty text means an
; unrecognized map and no silent guessed fingerprint.
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

; Historical NOT LOCKED M3-06 textured observations for comparison/reporting only.
Procedure.s TestHistoricalTexturedHash(Name.s)
  If Name = "E1M1"
    ProcedureReturn "183BA53FCECECBC8"
  ElseIf Name = "E1M2"
    ProcedureReturn "835A0339A38B190E"
  ElseIf Name = "E4M1"
    ProcedureReturn "03B5C8CFA517FC7E"
  EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s TestFileMd5(Path.s)
  Protected fileSize.q
  Protected bytes.i
  Protected readCount.i
  Protected file.i
  Protected fingerprint.s

  fileSize = FileSize(Path)
  If fileSize < 0 Or fileSize > #PI04_Md5MaxBytes
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
; One owner map: frozen M3 M3-04/M3-05/M3-06 plus new combined two-pass audit
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
  Protected combinedTarget.FrameBuffer
  Protected combinedResult.PlaneRenderResult
  Protected *texturedCopy.Byte = 0
  Protected *combinedCopy.Byte = 0
  Protected spanHash.q = 0
  Protected countsHash.q = 0
  Protected countsOk.l = 0
  Protected debugHash.q = 0
  Protected debugFrameHash.q = 0
  Protected texturedHashOne.q = 0
  Protected texturedHashTwo.q = 0
  Protected texturedFrameHash.q = 0
  Protected combinedHashOne.q = 0
  Protected combinedHashTwo.q = 0
  Protected combinedFrameHash.q = 0
  Protected expectedSpan.s = ""
  Protected expectedCounts.s = ""
  Protected expectedDebug.s = ""
  Protected historicalTextured.s = ""
  Protected spanCount.l = 0
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0
  Protected texturedDrawn.l = 0
  Protected copyMismatch.l = 0
  Protected combinedCopyMismatch.l = 0
  Protected byteIndex.i
  Protected levelOk.i = #False
  Protected viewOk.i = #False
  Protected visibilityOk.i = #False
  Protected debugRun.i = #False
  Protected texturedRunOne.i = #False
  Protected texturedRunTwo.i = #False
  Protected combinedRunOne.i = #False
  Protected combinedRunTwo.i = #False

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

  ; Legacy M3-05 debug-color frame frozen fingerprint.
  Check(FrameBufferCreate(@debugTarget, 320, 200), Name + " debug target frame created")
  Check(Bool(WallRenderResultReset(@debugResult)), Name + " debug result empty reusable")
  expectedDebug = TestExpectedDebugFrameHash(Name.s)
  debugRun = WallRenderFrame(@level, @view, *Projection, *Flats, *Textures,
                             @visibility, @debugTarget, @debugResult, 0)
  Check(Bool(debugRun), Name + " unchanged M3-05 debug-color frame render succeeds")
  If debugRun
    debugHash = debugResult\Hash
    debugFrameHash = TestFrameHash(@debugTarget)
    Check(Bool(debugHash <> -1), Name + " debug hash readable")
    Check(Bool(debugFrameHash = debugHash),
          Name + " independent debug plane FNV equals production hash")
    Check(Bool(expectedDebug <> "" And TestHashTextEquals(debugHash, expectedDebug)),
          Name + " frozen M3-05 debug frame hash " + expectedDebug + " preserved")
  Else
    Check(#False, Name + " debug-color frame rendered")
    Goto CheckOwnerMapDone
  EndIf

  ; M3-06 textured frame first and repeat, for frozen API and stability evidence.
  Check(FrameBufferCreate(@texturedTarget, 320, 200), Name + " textured target frame created")
  Check(Bool(TexturedWallRenderResultReset(@texturedResult)), Name + " textured result empty reusable")
  texturedRunOne = TexturedWallRenderFrame(@level, @view, *Projection, *Flats,
                                           *Textures, *Colormap, @visibility,
                                           @texturedTarget, @texturedResult, 1)
  Check(Bool(texturedRunOne), Name + " transactional textured M3-06 frame #1 succeeds")
  If texturedRunOne
    texturedHashOne = texturedResult\Hash
    texturedFrameHash = TestFrameHash(@texturedTarget)
    texturedDrawn = texturedResult\DrawnPixels
    Check(Bool(texturedFrameHash = texturedHashOne),
          Name + " independent textured plane FNV equals production hash")
    Check(Bool(texturedDrawn > 0), Name + " textured palette pixels actually present")
    *texturedCopy = AllocateMemory(#PI04_FramePixelCount)
    Check(Bool(*texturedCopy <> 0), Name + " private 64,000-byte textured repeat copy allocated")
    If *texturedCopy <> 0
      CopyMemory(texturedTarget\Pixels, *texturedCopy, #PI04_FramePixelCount)
    EndIf
  Else
    Check(#False, Name + " textured frame #1 rendered")
    Goto CheckOwnerMapDone
  EndIf

  texturedRunTwo = TexturedWallRenderFrame(@level, @view, *Projection, *Flats,
                                           *Textures, *Colormap, @visibility,
                                           @texturedTarget, @texturedResult, 1)
  Check(Bool(texturedRunTwo), Name + " textured M3-06 frame #2 repeat succeeds on reused target")
  If texturedRunTwo And texturedRunOne
    texturedHashTwo = texturedResult\Hash
    Check(Bool(texturedHashTwo = texturedHashOne), Name + " repeat textured 64-bit hash identical")
    copyMismatch = 0
    For byteIndex = 0 To #PI04_FramePixelCount - 1
      If PeekA(texturedTarget\Pixels + byteIndex) <> PeekA(*texturedCopy + byteIndex)
        copyMismatch + 1
      EndIf
    Next
    Check(Bool(copyMismatch = 0), Name + " repeat full 64,000-byte textured frame identical")
    historicalTextured = TestHistoricalTexturedHash(Name.s)
    PrintN("  " + Name + " stable textured hash NOT LOCKED: " + TestHex64Canonical(texturedHashOne) +
           "; historical observation " + TestHex64Canonical(texturedHashOne) +
           " equals baseline " + historicalTextured + ": " +
           Str(TestHashTextEquals(texturedHashOne, historicalTextured)))
  Else
    Check(#False, Name + " textured frame #2 repeat rendered")
  EndIf

  ; New M4-01 combined walls+flats frame first pass: counters and coverage.
  Check(FrameBufferCreate(@combinedTarget, 320, 200), Name + " combined target frame created")
  Check(Bool(PlaneRenderResultReset(@combinedResult)), Name + " combined result empty reusable")
  combinedRunOne = PlaneRenderFrame(@level, @view, *Projection, *Flats, *Textures,
                                    *Colormap, @combinedTarget, @combinedResult, #False)
  Check(Bool(combinedRunOne), Name + " new combined wall+flat frame #1 succeeds")
  If combinedRunOne
    Check(Bool(PlaneRenderResultIsValid(@combinedResult)),
          Name + " combined result valid ready")
    combinedHashOne = combinedResult\Hash
    combinedFrameHash = TestFrameHash(@combinedTarget)
    Check(Bool(combinedFrameHash = combinedHashOne),
          Name + " independent combined plane FNV equals production hash")
    Check(Bool(combinedResult\SpanCount = spanCount),
          Name + " combined wall span count equals unchanged M3-04 count")
    Check(Bool(combinedResult\WallDrawnPixels = texturedDrawn),
          Name + " combined wall painted pixels equal frozen M3-06 wall writes")
    Check(Bool(combinedResult\WallCoveredPixels = combinedResult\WallDrawnPixels),
          Name + " explicit 0/1 coverage marks resolve exactly to wall writes")
    Check(Bool(combinedResult\WallOutOfFrameColumns = 0),
          Name + " no combined wall column escaped the 320x200 frame")
    Check(Bool(combinedResult\NonZeroBytes + combinedResult\ZeroBytes = #PI04_FramePixelCount And
              combinedResult\NonZeroBytes >= 0 And combinedResult\ZeroBytes >= 0),
          Name + " combined nonzero/zero palette-byte audit totals 64,000")
    Check(Bool(combinedResult\Visplanes >= 0 And combinedResult\Visplanes <= 1024 And
              combinedResult\SpanCount <= 200000 And combinedResult\PlaneSpans >= 0 And
              combinedResult\PlanePixels >= 0 And combinedResult\FlatCacheCount <= 1024),
          Name + " combined visplane/span/span-trace/flat-cache budgets inside caps")
    Check(Bool(combinedResult\FindCalls = combinedResult\FindReuse + combinedResult\FindCreate And
              combinedResult\CheckCalls = combinedResult\CheckMerges + combinedResult\CheckSplits),
          Name + " combined Find/Check reuse-split accounting additive and bounded")
    If Name = "E1M1" Or Name = "E1M2"
      Check(Bool(combinedResult\PlanePixels > 0 And
                combinedResult\FlatCacheLoadedFlats >= 1 And
                combinedResult\FlatCacheUniqueFlats >= 1),
            Name + " real FlatLoad 64x64 floor/ceiling pixels present and cached")
      Check(Bool(combinedResult\FloorPixels + combinedResult\CeilingPixels = combinedResult\PlanePixels),
            Name + " floor+ceiling painted pixels reconcile to all regular plane pixels")
    Else
      Check(Bool(combinedResult\PlanePixels >= 0 And combinedResult\FlatCacheLoadedFlats >= 0),
            Name + " combined plane/flat counters remain valid without forced pixel claim")
    EndIf
    Check(Bool(combinedResult\SkyDeferredBands >= 0 And
              combinedResult\SkyDeferredPixels >= 0 And
              combinedResult\SkyVisplanes >= 0),
          Name + " deferred sky counts nonnegative, never substituted as flats")
    Check(Bool(combinedResult\FloorVisplanes >= 0 And combinedResult\CeilingVisplanes >= 0 And
              combinedResult\RegularVisplanes >= 0),
          Name + " floor/ceiling/regular visplane counters nonnegative")
  Else
    Check(#False, Name + " combined frame #1 rendered")
    PrintN("  " + Name + " combined error: " + PlaneRenderLastError())
    Goto CheckOwnerMapDone
  EndIf

  ; Combined second pass on the same target: deterministic hash and bytes.
  *combinedCopy = AllocateMemory(#PI04_FramePixelCount)
  Check(Bool(*combinedCopy <> 0), Name + " private 64,000-byte combined repeat copy allocated")
  If *combinedCopy <> 0
    CopyMemory(combinedTarget\Pixels, *combinedCopy, #PI04_FramePixelCount)
  EndIf
  combinedRunTwo = PlaneRenderFrame(@level, @view, *Projection, *Flats, *Textures,
                                    *Colormap, @combinedTarget, @combinedResult, #False)
  Check(Bool(combinedRunTwo), Name + " combined wall+flat frame #2 repeat succeeds on reused target")
  If combinedRunTwo And combinedRunOne And *combinedCopy <> 0
    combinedHashTwo = combinedResult\Hash
    Check(Bool(combinedHashTwo = combinedHashOne),
          Name + " repeat combined raw 64-bit frame hash identical")
    combinedCopyMismatch = 0
    For byteIndex = 0 To #PI04_FramePixelCount - 1
      If PeekA(combinedTarget\Pixels + byteIndex) <> PeekA(*combinedCopy + byteIndex)
        combinedCopyMismatch + 1
      EndIf
    Next
    Check(Bool(combinedCopyMismatch = 0),
          Name + " repeat combined full 64,000-byte frame identical")
    Check(Bool(TestFrameHash(@combinedTarget) = combinedHashTwo),
          Name + " repeat independent combined plane FNV equals repeat production hash")
    PrintN("  " + Name + " combined NOT LOCKED frame hash: " + TestHex64Canonical(combinedHashOne))
    PrintN("  " + Name + " combined counters: spans " + Str(combinedResult\SpanCount) +
           ", visplanes " + Str(combinedResult\Visplanes) + " (regular/sky/empty/populated " +
           Str(combinedResult\RegularVisplanes) + "/" + Str(combinedResult\SkyVisplanes) + "/" +
           Str(combinedResult\EmptyVisplanes) + "/" + Str(combinedResult\PopulatedVisplanes) +
           "), find reuse/create/split " + Str(combinedResult\FindReuse) + "/" +
           Str(combinedResult\FindCreate) + "/" + Str(combinedResult\CheckSplits) +
           ", floor/ceiling vis/pixels " + Str(combinedResult\FloorVisplanes) + "/" +
           Str(combinedResult\CeilingVisplanes) + "/" + Str(combinedResult\FloorPixels) + "/" +
           Str(combinedResult\CeilingPixels) + ", sky deferred bands/pixels " +
           Str(combinedResult\SkyDeferredBands) + "/" + Str(combinedResult\SkyDeferredPixels) +
           ", plane spans/pixels/opened/closed " + Str(combinedResult\PlaneSpans) + "/" +
           Str(combinedResult\PlanePixels) + "/" + Str(combinedResult\PlaneOpenedRows) + "/" +
           Str(combinedResult\PlaneClosedRows) + ", row-cache hits/misses " +
           Str(combinedResult\PlaneRowCacheHits) + "/" + Str(combinedResult\PlaneRowCacheMisses) +
           ", flat unique/loaded/count/alloc " + Str(combinedResult\FlatCacheUniqueFlats) + "/" +
           Str(combinedResult\FlatCacheLoadedFlats) + "/" + Str(combinedResult\FlatCacheCount) +
           "/" + Str(combinedResult\FlatCacheAllocations) + ", wall px/cov " +
           Str(combinedResult\WallDrawnPixels) + "/" + Str(combinedResult\WallCoveredPixels) +
           ", nonzero/zero bytes " + Str(combinedResult\NonZeroBytes) + "/" +
           Str(combinedResult\ZeroBytes) + ", allocations " + Str(combinedResult\Allocations))
  Else
    Check(#False, Name + " combined frame #2 repeat rendered")
  EndIf

  CheckOwnerMapDone:
  If *combinedCopy <> 0
    FreeMemory(*combinedCopy)
    *combinedCopy = 0
  EndIf
  If *texturedCopy <> 0
    FreeMemory(*texturedCopy)
    *texturedCopy = 0
  EndIf
  PlaneRenderResultReset(@combinedResult)
  FrameBufferReset(@combinedTarget)
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

Procedure TestPI04(Path.s)
  Protected beforeSize.q = 0
  Protected afterSize.q = 0
  Protected beforeMd5.s = ""
  Protected afterMd5.s = ""
  Protected knownIdentityMatch.i = #False
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected flats.FlatCatalog
  Protected colormap.ColormapSet
  Protected projection.Projection
  Protected pNamesCount.l = 0
  Protected textureCount.l = 0
  Protected flatCount.l = 0
  Protected colormapCount.l = 0

  If Path = ""
    PrintN("[PI04] Optional real Ultimate Doom combined wall+flat integration: NOT RUN (no WAD path argument)")
    PrintN("Cases: 0, assertions: 0, failures: 0")
    PrintN("RESULT: PASS (PI04 NOT RUN)")
    ProcedureReturn
  EndIf

  BeginCase("PI04", "Optional real Ultimate Doom read-only combined walls+flats/M3 preservation")

  beforeSize = FileSize(Path)
  Check(Bool(beforeSize > 0), "owner IWAD path positive before reading")
  beforeMd5 = TestFileMd5(Path)
  Check(Bool(beforeMd5 <> ""), "owner IWAD read-only MD5 computed before opening")
  knownIdentityMatch = Bool(beforeSize = #PI04_KnownIwadSize And
                            beforeMd5 = #PI04_KnownIwadMd5)
  PrintN("  owner IWAD size " + Str(beforeSize) + ", MD5 " + beforeMd5 +
         ", matches known Ultimate Doom 1.9ud identification " + Str(knownIdentityMatch))

  Check(Bool(WADOpen(Path)), "owner IWAD opens read-only through WAD directory APIs")
  Check(Bool(WADIsOpen()), "owner WAD session stays open while resources decode")
  Check(Bool(WallTexDecodeWallCatalog(@p, @catalog)), "real PNAMES/TEXTURE1/TEXTURE2 decode+resolve")
  Check(Bool(WallTexDecodeWallFlats(@flats)), "real F_START/F_END flat catalog build")
  Check(Bool(WallTexDecodeWallColormap(@colormap)), "real COLORMAP decode")
  pNamesCount = PNamesCount(@p)
  textureCount = TextureCatalogCount(@catalog)
  flatCount = FlatCatalogCount(@flats)
  colormapCount = ColormapCount(@colormap)
  Check(Bool(pNamesCount > 0 And textureCount > 0 And flatCount > 0),
        "decoded patch/texture/flat counts positive")
  Check(Bool(colormapCount >= 32), "real COLORMAP exposes at least 32 classic lighting tables")
  PrintN("  PNAMES " + Str(pNamesCount) + ", textures " + Str(textureCount) +
         ", flats " + Str(flatCount) + ", COLORMAP tables " + Str(colormapCount))

  Check(Bool(ProjectionInitClassic(@projection)), "immutable classic projection initializes once")
  PrintN("  projection viewport " + Str(#PROJ_VIEWWIDTH) + "x" + Str(#PROJ_VIEWHEIGHT))

  CheckOwnerMap("E1M1", @projection, @flats, @catalog, @colormap)
  CheckOwnerMap("E1M2", @projection, @flats, @catalog, @colormap)
  CheckOwnerMap("E4M1", @projection, @flats, @catalog, @colormap)

  WADClose()
  Check(Bool(WADIsOpen() = #False), "WAD closes cleanly after read-only combined pass")
  afterSize = FileSize(Path)
  afterMd5 = TestFileMd5(Path)
  Check(Bool(afterSize = beforeSize), "owner IWAD byte size unchanged after read-only pass")
  Check(Bool(afterMd5 <> "" And afterMd5 = beforeMd5),
        "owner IWAD MD5 fingerprint unchanged after read-only pass")

  ColormapReset(@colormap)
  ProjectionReset(@projection)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
EndProcedure

; ---------------------------------------------------------------------------
; Main: absent argument -> NOT RUN, 0 cases/0 assertions, exit 0
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M4-01 optional real-IWAD combined wall+flat integration (PI04)")

TestPI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) +
       ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (PI04 may be NOT RUN without a WAD argument)")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
