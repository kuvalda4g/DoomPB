; -----------------------------------------------------------------------------
; DoomPB - M3-04 optional real-IWAD projection/wall-clipping integration (I04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Optional harness; the owner-provided legal IWAD path is its first argument
; (the same convention as M2/M3-01/M3-02/M3-03 I04). Reads strictly read-only,
; opens the IWAD through WADOpen, builds the decoded PNAMES/TEXTURE1/TEXTURE2
; catalogs and the F_START/F_END flat catalog, initializes the immutable
; classic 320-column Projection once, then for E1M1/E1M2/E4M1:
;   - loads the map through the validated M2 MapLevel APIs;
;   - checks MapLevelValidateResources against the decoded catalogs;
;   - chooses the fixed camera from the player-one THING start, converted with
;     FixedFromIntChecked and the original P_SpawnPlayer raw BAM heading;
;   - keeps the pre-existing cull-free BspTraceBuild as an independent cross-
;     check for reachable leaf/seg/node totals before the M3-04 online walk;
;   - runs the catalog-aware WallVisibilityBuild (the optional route that
;     reproduces original R_FlatNumForName/R_TextureNumForName equality tests);
;   - verifies every published span against the decoded map source records and
;     recomputes its SOLID/PASS classification with the same catalog-aware
;     identity helpers, so no invented identity/kind can pass;
;   - reconciles counters, bbox breakdown and traversal bounds with the
;     cull-free trace, and verifies the accessor aggregate fields;
;   - repeats Build twice (including an explicit Reset) to require identical
;     span identity/order hashes and identical counter fingerprints.
;
; The IWAD is never written: before/after byte size and MD5 are compared. Its
; MD5 may be printed for identification but another legitimate IWAD hash is not
; rejected. Only coarse totals and FNV-1a64 hashes are printed: no map geometry
; coordinates, whole record lists, WAD payload bytes, textures, flats, sprites
; or screenshots are printed, copied, stored or committed.
;
; Without a path argument I04 is reported NOT RUN; that is not failure.
; Exit code: 0 when every assertion passed (or NOT RUN), else failure count.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Fixed.pbi"
XIncludeFile "../../src/Core/Angle.pbi"
XIncludeFile "../../src/Core/TrigTables.pbi"
XIncludeFile "../../src/Renderer/Geometry.pbi"
XIncludeFile "../../src/Renderer/Camera.pbi"
XIncludeFile "../../src/Renderer/Projection.pbi"
XIncludeFile "../../src/Renderer/ClipSegs.pbi"
XIncludeFile "../../src/Renderer/WallVisibility.pbi"
XIncludeFile "../../src/Renderer/BSP.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Map/MapLoader.pbi"

#IWAD_FNV_Offset = -3750763034362895579
#IWAD_FNV_Prime = 1099511628211

; Project policy only: a bound on the optional read-only fingerprint buffer.
#IWAD_Md5MaxBytes = 268435456

Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

; ---------------------------------------------------------------------------
; Harness
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
  Hash = Hash * #IWAD_FNV_Prime
  ProcedureReturn Hash
EndProcedure

Procedure.q FnvAddLong(Hash.q, Value.l)
  Hash = FnvAddByte(Hash, Value & $FF)
  Hash = FnvAddByte(Hash, (Value >> 8) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 16) & $FF)
  Hash = FnvAddByte(Hash, (Value >> 24) & $FF)
  ProcedureReturn Hash
EndProcedure

; Widened integer sum helper for checked 64-bit reconciliation.
Procedure.q Int64Sum(A.l, B.l)
  Protected wideA.q = A
  Protected wideB.q = B
  ProcedureReturn wideA + wideB
EndProcedure

; ---------------------------------------------------------------------------
; Optional read-only file fingerprint (verification only)
; ---------------------------------------------------------------------------

Procedure.s TestFileMd5(Path.s)
  Protected fileSize.q
  Protected bytes.i
  Protected readCount.i
  Protected file.i
  Protected fingerprint.s

  fileSize = FileSize(Path)
  If fileSize < 0 Or fileSize > #IWAD_Md5MaxBytes
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
; Owned lump reader and decoded catalog setup
; ---------------------------------------------------------------------------

Procedure.i ReadLumpBuffer(Name.s, *OutSize.Long)
  Protected index.i
  Protected size.q
  Protected *memory.Byte

  index = WADFindLump(Name)
  If index < 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  size = WADLumpSize(index)
  If size <= 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *memory = AllocateMemory(size)
  If *memory = 0
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  If WADReadLump(index, *memory, size) = #False
    FreeMemory(*memory)
    *OutSize\l = 0
    ProcedureReturn 0
  EndIf
  *OutSize\l = size
  ProcedureReturn *memory
EndProcedure

; PNAMES/TEXTURE1/TEXTURE2 decode plus patch resolution, and F_START/F_END flat
; discovery, all from the current read-only WAD. Counts are returned only for
; coarse reporting; no names/bytes are printed.
Procedure.i TestLoadCatalogs(*PNames.PNamesTable, *Catalog.TextureCatalog,
                             *Flats.FlatCatalog, *OutPNames.Long,
                             *OutTextures.Long, *OutFlats.Long)
  Protected size1.q
  Protected size2.q = 0
  Protected *bytes1.Byte
  Protected *bytes2.Byte = 0
  Protected hasTexture2.i
  Protected ok.i
  Protected pNamesCount.l
  Protected textureCount.l
  Protected flatCount.l

  *OutPNames\l = 0
  *OutTextures\l = 0
  *OutFlats\l = 0

  *bytes1 = ReadLumpBuffer("PNAMES", @size1)
  If *bytes1 = 0
    ProcedureReturn #False
  EndIf
  ok = PNamesDecode(*bytes1, size1, *PNames)
  FreeMemory(*bytes1)
  If ok = #False
    ProcedureReturn #False
  EndIf
  pNamesCount = PNamesCount(*PNames)
  If pNamesCount <= 0
    ProcedureReturn #False
  EndIf
  *OutPNames\l = pNamesCount

  *bytes1 = ReadLumpBuffer("TEXTURE1", @size1)
  If *bytes1 = 0
    ProcedureReturn #False
  EndIf
  hasTexture2 = Bool(WADFindLump("TEXTURE2") >= 0)
  If hasTexture2
    *bytes2 = ReadLumpBuffer("TEXTURE2", @size2)
    If *bytes2 = 0
      FreeMemory(*bytes1)
      ProcedureReturn #False
    EndIf
  EndIf
  ok = TextureCatalogDecode(*bytes1, size1, *bytes2, size2, hasTexture2, *Catalog)
  FreeMemory(*bytes1)
  If *bytes2 <> 0
    FreeMemory(*bytes2)
  EndIf
  If ok = #False
    ProcedureReturn #False
  EndIf
  ok = TextureCatalogResolve(*Catalog, *PNames)
  If ok = #False
    ProcedureReturn #False
  EndIf
  textureCount = TextureCatalogCount(*Catalog)
  If textureCount <= 0
    ProcedureReturn #False
  EndIf
  *OutTextures\l = textureCount

  ok = FlatCatalogBuild(*Flats)
  If ok = #False
    ProcedureReturn #False
  EndIf
  flatCount = FlatCatalogCount(*Flats)
  If flatCount <= 0
    ProcedureReturn #False
  EndIf
  *OutFlats\l = flatCount
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Fixed camera selection from validated map data (original P_SpawnPlayer rule)
; ---------------------------------------------------------------------------

; Original P_SpawnPlayer (p_mobj.c) sets heading as
; `mobj->angle = ANG45 * (mthing->angle/45)` with integer division truncation.
; The raw unsigned BAM value is stored; the M3-04 projection/clip work consumes
; it, unlike the M3-03 cull-free trace.
Procedure.i TestChooseCamera(*Level.MapLevel, *Camera.BspCamera, *PlayerThing.Long)
  Protected thingCount.i
  Protected i.i
  Protected x.l
  Protected y.l
  Protected angle.l
  Protected type.l
  Protected options.l
  Protected quotient.l
  Protected wideQuotient.q
  Protected rawHeading.q
  Protected vertexX.l = 0
  Protected vertexY.l = 0

  *PlayerThing\l = 0
  thingCount = MapThingsCount(@*Level\Things)
  For i = 0 To thingCount - 1
    If MapThingsGet(@*Level\Things, i, @x, @y, @angle, @type, @options) = #False
      Continue
    EndIf
    If type = 1
      quotient = angle / 45
      wideQuotient = quotient
      rawHeading = BamWrap32(#BAM_ANG45 * wideQuotient)
      If BspCameraSetMapUnits(*Camera, x, y, rawHeading) = #False
        ProcedureReturn #False
      EndIf
      *PlayerThing\l = 1
      ProcedureReturn #True
    EndIf
  Next

  ; Documented fallback: vertex 0 in signed map units with canonical ANG90.
  If MapVertexesGet(@*Level\Vertexes, 0, @vertexX, @vertexY) = #False
    ProcedureReturn #False
  EndIf
  If BspCameraSetMapUnits(*Camera, vertexX, vertexY, #BAM_ANG90) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent source-faithful span classification and identity audit
; ---------------------------------------------------------------------------

; Recompute R_AddLine's SOLID/PASS classification from the decoded sectors and
; the same catalog-aware flat/middle identity helpers used by the production
; route. *Kind = -1 signals the equal-planes+identical-flats/light+absent-middle
; EMPTY SKIP case, for which R_AddLine emits no span at all. Returns #False only
; on a genuine read/resource error.
Procedure.i TestSpanExpectedKind(*Level.MapLevel, *Flats.FlatCatalog,
                                *Textures.TextureCatalog, FrontSector.l,
                                BackSector.l, SideIndex.l, *Kind.Long)
  Protected frontFloor.l = 0
  Protected frontCeiling.l = 0
  Protected frontLight.l = 0
  Protected backFloor.l = 0
  Protected backCeiling.l = 0
  Protected backLight.l = 0
  Protected sameLight.i
  Protected sameFloor.l = 0
  Protected sameCeiling.l = 0
  Protected middleAbsent.l = 0

  *Kind\l = -1
  If FrontSector < 0 Or FrontSector >= *Level\Sectors\Count
    ProcedureReturn #False
  EndIf
  If MapSectorsGet(@*Level\Sectors, FrontSector, @frontFloor, @frontCeiling,
                   @frontLight, 0, 0) = #False
    ProcedureReturn #False
  EndIf

  If BackSector = #WALLVIS_NoIndex
    *Kind\l = #WALL_KIND_SOLID
    ProcedureReturn #True
  EndIf
  If BackSector < 0 Or BackSector >= *Level\Sectors\Count
    ProcedureReturn #False
  EndIf
  If MapSectorsGet(@*Level\Sectors, BackSector, @backFloor, @backCeiling,
                   @backLight, 0, 0) = #False
    ProcedureReturn #False
  EndIf

  If backCeiling <= frontFloor Or backFloor >= frontCeiling
    *Kind\l = #WALL_KIND_SOLID
    ProcedureReturn #True
  EndIf
  If backCeiling <> frontCeiling Or backFloor <> frontFloor
    *Kind\l = #WALL_KIND_PASS
    ProcedureReturn #True
  EndIf

  sameLight = Bool(backLight = frontLight)
  If WallSectorFlatIdentity(*Level, *Flats, FrontSector, BackSector, 0,
                            @sameFloor) = #False
    ProcedureReturn #False
  EndIf
  If WallSectorFlatIdentity(*Level, *Flats, FrontSector, BackSector, 1,
                            @sameCeiling) = #False
    ProcedureReturn #False
  EndIf
  If WallMiddleTextureAbsent(*Level, *Textures, SideIndex,
                             @middleAbsent) = #False
    ProcedureReturn #False
  EndIf
  If sameFloor <> 0 And sameCeiling <> 0 And sameLight <> 0 And middleAbsent <> 0
    *Kind\l = -1
    ProcedureReturn #True
  EndIf
  *Kind\l = #WALL_KIND_PASS
  ProcedureReturn #True
EndProcedure

; Full audit of one published span:
;   - its seg links must match the decoded SEGS record exactly;
;   - the seg-selected sidedef must exist and name the published front sector;
;   - all record indices and inclusive screen columns are valid;
;   - the recomputed R_AddLine classification must equal the published kind, and
;     an EMPTY SKIP classification cannot correspond to a published span.
Procedure.i TestSpanFaithful(*Level.MapLevel, *Flats.FlatCatalog,
                             *Textures.TextureCatalog, *Result.WallVisibilityResult,
                             SpanIndex.i)
  Protected spanSub.l = 0
  Protected spanSeg.l = 0
  Protected spanLine.l = 0
  Protected spanSide.l = 0
  Protected spanFront.l = 0
  Protected spanBack.l = 0
  Protected spanFirst.l = 0
  Protected spanLast.l = 0
  Protected spanKind.l = -1
  Protected linkLine.l = 0
  Protected linkSide.l = 0
  Protected linkFront.l = 0
  Protected linkBack.l = 0
  Protected lineFlags.l = 0
  Protected lineSpecial.l = 0
  Protected lineTag.l = 0
  Protected lineSide0.l = 0
  Protected lineSide1.l = 0
  Protected selectedSide.l = 0
  Protected selectedSector.l = 0
  Protected expectedKind.l = -1
  Protected columnValid.i

  If WallVisibilityGetSpan(*Result, SpanIndex, @spanSub, @spanSeg, @spanLine,
                           @spanSide, @spanFront, @spanBack, @spanFirst,
                           @spanLast, @spanKind) = #False
    ProcedureReturn #False
  EndIf

  If spanSub < 0 Or spanSub >= *Level\Subsectors\Count
    ProcedureReturn #False
  EndIf
  If spanSeg < 0 Or spanSeg >= *Level\Segs\Count
    ProcedureReturn #False
  EndIf
  If spanLine < 0 Or spanLine >= *Level\Linedefs\Count
    ProcedureReturn #False
  EndIf
  If spanSide <> 0 And spanSide <> 1
    ProcedureReturn #False
  EndIf
  If spanFront < 0 Or spanFront >= *Level\Sectors\Count
    ProcedureReturn #False
  EndIf
  If spanBack <> #WALLVIS_NoIndex And
     (spanBack < 0 Or spanBack >= *Level\Sectors\Count)
    ProcedureReturn #False
  EndIf
  columnValid = Bool(spanFirst >= 0 And spanLast >= 0 And
                     spanFirst <= spanLast And
                     spanFirst <= #PROJ_VIEWWIDTH - 1 And
                     spanLast <= #PROJ_VIEWWIDTH - 1)
  If columnValid = #False
    ProcedureReturn #False
  EndIf
  If spanKind <> #WALL_KIND_SOLID And spanKind <> #WALL_KIND_PASS
    ProcedureReturn #False
  EndIf

  If MapLevelGetSegLinks(*Level, spanSeg, @linkLine, @linkSide, @linkFront,
                         @linkBack) = #False
    ProcedureReturn #False
  EndIf
  If linkLine <> spanLine Or linkSide <> spanSide Or
     linkFront <> spanFront Or linkBack <> spanBack
    ProcedureReturn #False
  EndIf

  If MapLinedefsGet(@*Level\Linedefs, spanLine, 0, 0, @lineFlags,
                    @lineSpecial, @lineTag, @lineSide0, @lineSide1) = #False
    ProcedureReturn #False
  EndIf
  If spanSide = 0
    selectedSide = lineSide0
  Else
    selectedSide = lineSide1
  EndIf
  If selectedSide < 0 Or selectedSide >= *Level\Sidedefs\Count
    ProcedureReturn #False
  EndIf
  If MapSidedefsGet(@*Level\Sidedefs, selectedSide, 0, 0,
                    @selectedSector) = #False
    ProcedureReturn #False
  EndIf
  If selectedSector <> spanFront
    ProcedureReturn #False
  EndIf

  If TestSpanExpectedKind(*Level, *Flats, *Textures, spanFront, spanBack,
                          selectedSide, @expectedKind) = #False
    ProcedureReturn #False
  EndIf
  If expectedKind = -1
    ; The original R_AddLine EMPTY SKIP path emits nothing; a surviving span is
    ; therefore an identity/kind inconsistency.
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(expectedKind = spanKind)
EndProcedure

; ---------------------------------------------------------------------------
; Result fingerprints and accessor reconciliation
; ---------------------------------------------------------------------------

; FNV over the published M3-04 WallSpan numeric fields in chronological order.
; A complex return type needs explicit width; a non-valid result yields -1.
Procedure.q TestWallResultHash(*Result.WallVisibilityResult)
  Protected hash.q = #IWAD_FNV_Offset
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

; FNV over Count and every published aggregate counter. Separate from the span
; hash so a counter-only regression cannot be masked by identical span order.
Procedure.q TestWallCountsHash(*Result.WallVisibilityResult, *Ok.Long)
  Protected hash.q = #IWAD_FNV_Offset

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

; The 21-output accessor must expose exactly the result's own aggregate fields.
Procedure.i TestStatsAccessorMatches(*Result.WallVisibilityResult)
  Protected vNodes.l
  Protected vSubs.l
  Protected pSegs.l
  Protected eFrags.l
  Protected bFace.l
  Protected fLeft.l
  Protected fRight.l
  Protected fAny.l
  Protected pWidth.l
  Protected eLine.l
  Protected solidC.l
  Protected passC.l
  Protected bTests.l
  Protected bVisible.l
  Protected bOccluded.l
  Protected bUnknown.l
  Protected occlSkips.l
  Protected work.l
  Protected rangeG.l
  Protected spanG.l
  Protected allocs.l

  If WallVisibilityGetStats(*Result, @vNodes, @vSubs, @pSegs, @eFrags,
                            @bFace, @fLeft, @fRight, @fAny, @pWidth, @eLine,
                            @solidC, @passC, @bTests, @bVisible, @bOccluded,
                            @bUnknown, @occlSkips, @work, @rangeG, @spanG,
                            @allocs) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(vNodes = *Result\VisitedNodes And
                       vSubs = *Result\VisitedSubsectors And
                       pSegs = *Result\ProcessedSegs And
                       eFrags = *Result\EmittedFragments And
                       bFace = *Result\BackfaceRejects And
                       fLeft = *Result\FovLeftRejects And
                       fRight = *Result\FovRightRejects And
                       fAny = *Result\FovRejects And
                       pWidth = *Result\PixelWidthRejects And
                       eLine = *Result\EmptyLineRejects And
                       solidC = *Result\SolidCandidates And
                       passC = *Result\PassCandidates And
                       bTests = *Result\BboxTests And
                       bVisible = *Result\BboxVisible And
                       bOccluded = *Result\BboxOccluded And
                       bUnknown = *Result\BboxUnknown And
                       occlSkips = *Result\OcclusionSkips And
                       work = *Result\WorkItems And
                       rangeG = *Result\ClipRangeGrowths And
                       spanG = *Result\ClipSpanGrowths And
                       allocs = *Result\Allocations)
EndProcedure

; ---------------------------------------------------------------------------
; Per-map real-IWAD measurement
; ---------------------------------------------------------------------------

; Expected cull-free totals are the historic M3-03/M2 measurements reused as a
; cross-check only; they are never imposed as a generic loader rule. Every span
; and counter assertion below is structural/source-derived, not a memorised
; pixel or geometry fingerprint.
Procedure CheckWallMap(Name.s, ExpectedSubsectors.l, ExpectedSegs.l,
                       ExpectedNodes.l, *Projection.Projection,
                       *Flats.FlatCatalog, *Textures.TextureCatalog)
  Protected level.MapLevel
  Protected camera.BspCamera
  Protected trace.BspTrace
  Protected resultA.WallVisibilityResult
  Protected resultB.WallVisibilityResult
  Protected resultC.WallVisibilityResult
  Protected playerThing.l = 0
  Protected traceCount.l = -1
  Protected traceTotal.q = 0
  Protected expectedTotal.q = 0
  Protected countA.l = -1
  Protected countB.l = -1
  Protected countC.l = -1
  Protected hashA.q = -1
  Protected hashB.q = -1
  Protected hashC.q = -1
  Protected countHashA.q = -1
  Protected countHashB.q = -1
  Protected countHashC.q = -1
  Protected hashOkA.l = 0
  Protected hashOkB.l = 0
  Protected hashOkC.l = 0
  Protected i.i
  Protected badSpans.l = 0
  Protected firstBad.l = -1
  Protected rejectSum.q = 0
  Protected bboxSum.q = 0
  Protected resetOk.i = 0

  MapLevelReset(@level)
  Check(Bool(MapLevelLoad(Name, @level) <> 0), Name + " loads through validated M2 MapLevel API")
  Check(Bool(MapLevelIsReady(@level) <> 0 And level\Name = Name),
        Name + " loaded level identity/readiness is canonical")
  Check(Bool(MapLevelValidateResources(@level, *Flats, *Textures) <> 0),
        Name + " references resolve through the decoded flat/texture catalogs")
  Check(Bool(TestChooseCamera(@level, @camera, @playerThing) <> 0),
        Name + " fixed camera derived from validated player-one THING start")
  Check(Bool(playerThing <> 0), Name + " player-one THING start actually present")

  ; Unchanged M3-03 cull-free trace as an independent reachable-set cross-check.
  Check(Bool(BspTraceBuild(@level, @camera, @trace) <> 0),
        Name + " pre-existing cull-free BspTraceBuild succeeds")
  traceCount = BspTraceCount(@trace)
  expectedTotal = Int64Sum(ExpectedSubsectors, ExpectedSegs)
  traceTotal = traceCount
  Check(Bool(trace\VisitedNodes = ExpectedNodes),
        Name + " cull-free trace visits the expected node count " + Str(ExpectedNodes))
  Check(Bool(trace\VisitedSubsectors = ExpectedSubsectors And
             trace\EmittedSegs = ExpectedSegs),
        Name + " cull-free trace covers expected " + Str(ExpectedSubsectors) +
        " leaves/" + Str(ExpectedSegs) + " segs")
  Check(Bool(traceTotal = expectedTotal),
        Name + " cull-free event total reconciles to " + Str(Int64Sum(ExpectedSubsectors, ExpectedSegs)))
  Check(Bool(trace\OcclusionSkips = 0), Name + " unchanged cull-free trace retains zero occlusion skips")

  ; Catalog-aware online visibility walk (the original resolved-index route).
  Check(Bool(ProjectionIsValid(*Projection) <> 0),
        Name + " shared immutable classic projection is valid")
  Check(Bool(WallVisibilityBuild(@level, @camera, *Projection, *Flats,
                                 *Textures, @resultA) <> 0),
        Name + " catalog-aware M3-04 online visible walk succeeds")
  countA = WallVisibilityCount(@resultA)
  Check(Bool(countA >= 1), Name + " the online walk publishes at least one visible wall span")

  For i = 0 To countA - 1
    If TestSpanFaithful(@level, *Flats, *Textures, @resultA, i) = #False
      If firstBad < 0
        firstBad = i
      EndIf
      badSpans + 1
    EndIf
  Next
  Check(Bool(badSpans = 0 And firstBad < 0),
        Name + " all " + Str(countA) +
        " spans match decoded seg/line/side/sector identity and recomputed SOLID/PASS kind")

  ; Counter reconciliation from distinct outcome classes and bbox tri-state.
  rejectSum = resultA\EmptyLineRejects
  rejectSum = rejectSum + resultA\BackfaceRejects
  rejectSum = rejectSum + resultA\FovLeftRejects
  rejectSum = rejectSum + resultA\FovRightRejects
  rejectSum = rejectSum + resultA\PixelWidthRejects
  rejectSum = rejectSum + resultA\SolidCandidates
  rejectSum = rejectSum + resultA\PassCandidates

  Check(Bool(resultA\EmittedFragments = countA),
        Name + " published fragment counter equals the owned span count")
  Check(Bool(rejectSum = resultA\ProcessedSegs),
        Name + " every processed seg maps to exactly one published outcome class")
  Check(Bool(Int64Sum(resultA\FovLeftRejects, resultA\FovRightRejects) = resultA\FovRejects),
        Name + " angular reject total reconciles left+right")
  bboxSum = resultA\BboxVisible
  bboxSum = bboxSum + resultA\BboxOccluded
  bboxSum = bboxSum + resultA\BboxUnknown
  Check(Bool(bboxSum = resultA\BboxTests),
        Name + " bbox tri-state breakdown reconciles to every evaluated box")
  Check(Bool(resultA\OcclusionSkips = resultA\BboxOccluded),
        Name + " occlusion skips count only actual OCCLUDED bbox verdicts")
  Check(Bool(resultA\BboxTests = resultA\VisitedNodes),
        Name + " every visited node runs exactly one far-child bbox check")
  Check(Bool(resultA\BboxUnknown = 0),
        Name + " normal vanilla tree yields no conservative R_CheckBBox fallback")
  Check(Bool(resultA\WorkItems > 0 And resultA\Allocations >= 1),
        Name + " bounded stack work and owned allocations were actually recorded")

  ; The online walk must be a real subset of the cull-free reachable set.
  Check(Bool(resultA\VisitedNodes <= trace\VisitedNodes And
             resultA\VisitedSubsectors <= trace\VisitedSubsectors And
             resultA\ProcessedSegs <= trace\EmittedSegs),
        Name + " online visit/seg totals stay within cull-free reachable totals")
  Check(Bool(resultA\OcclusionSkips > 0 And
             resultA\VisitedSubsectors < trace\VisitedSubsectors),
        Name + " live solidsegs actually prune a far subtree (fewer leaf visits than cull-free)")

  Check(Bool(TestStatsAccessorMatches(@resultA) <> 0),
        Name + " WallVisibilityGetStats exposes exactly the result aggregate fields")

  hashA = TestWallResultHash(@resultA)
  countHashA = TestWallCountsHash(@resultA, @hashOkA)
  Check(Bool(hashA <> -1 And countHashA <> -1 And hashOkA <> 0),
        Name + " visible span and counter fingerprints computed from a valid result")

  ; Duplicate Build (Build resets its own result) must be bit-for-bit stable.
  Check(Bool(WallVisibilityBuild(@level, @camera, *Projection, *Flats,
                                 *Textures, @resultB) <> 0),
        Name + " duplicate catalog-aware Build succeeds")
  countB = WallVisibilityCount(@resultB)
  hashB = TestWallResultHash(@resultB)
  countHashB = TestWallCountsHash(@resultB, @hashOkB)
  Check(Bool(countB = countA And hashB = hashA And countHashB = countHashA),
        Name + " duplicate Build is deterministic in span identity/order and counters")
  Check(Bool(resultB\VisitedNodes = resultA\VisitedNodes And
             resultB\VisitedSubsectors = resultA\VisitedSubsectors And
             resultB\ProcessedSegs = resultA\ProcessedSegs And
             resultB\BboxTests = resultA\BboxTests And
             resultB\OcclusionSkips = resultA\OcclusionSkips),
        Name + " duplicate Build traversal/bbox counters repeat exactly")
  Check(Bool(resultB\SolidCandidates = resultA\SolidCandidates And
             resultB\PassCandidates = resultA\PassCandidates And
             resultB\FovLeftRejects = resultA\FovLeftRejects And
             resultB\FovRightRejects = resultA\FovRightRejects And
             resultB\BackfaceRejects = resultA\BackfaceRejects And
             resultB\PixelWidthRejects = resultA\PixelWidthRejects And
             resultB\EmptyLineRejects = resultA\EmptyLineRejects),
        Name + " duplicate Build classification/angular rejects repeat exactly")
  Check(Bool(resultB\ClipRangeGrowths = resultA\ClipRangeGrowths And
             resultB\ClipSpanGrowths = resultA\ClipSpanGrowths And
             resultB\WorkItems = resultA\WorkItems And
             resultB\Allocations = resultA\Allocations),
        Name + " duplicate Build clip growth/work/allocation totals repeat exactly")

  ; Explicit Reset then Build proves the owner is reusable without stale spans.
  resetOk = WallVisibilityReset(@resultB)
  Check(Bool(resetOk <> 0 And WallVisibilityIsValid(@resultB) <> 0 And
             WallVisibilityCount(@resultB) = 0),
        Name + " explicit result Reset is idempotent and leaves a reusable empty owner")
  Check(Bool(WallVisibilityBuild(@level, @camera, *Projection, *Flats,
                                 *Textures, @resultC) <> 0),
        Name + " Reset/reused owner Build after WAD data changes nothing")
  countC = WallVisibilityCount(@resultC)
  hashC = TestWallResultHash(@resultC)
  countHashC = TestWallCountsHash(@resultC, @hashOkC)
  Check(Bool(countC = countA And hashC = hashA And countHashC = countHashA),
        Name + " Reset/reimplied Build reproduces the original span/counter fingerprints")

  Check(Bool(resultA\Spans <> 0 Or countA = 0),
        Name + " published spans have owned storage or a legal empty frame")

  PrintN("  " + Name + ": cull-free " + Str(trace\VisitedNodes) + " nodes/" +
         Str(trace\VisitedSubsectors) + " leaves/" + Str(trace\EmittedSegs) +
         " segs; online spans " + Str(countA))
  PrintN("    online nodes " + Str(resultA\VisitedNodes) +
         ", leaves " + Str(resultA\VisitedSubsectors) +
         ", processed segs " + Str(resultA\ProcessedSegs) +
         ", solid/pass candidates " + Str(resultA\SolidCandidates) + "/" +
         Str(resultA\PassCandidates))
  PrintN("    rejects: backface " + Str(resultA\BackfaceRejects) +
         ", fov left/right " + Str(resultA\FovLeftRejects) + "/" +
         Str(resultA\FovRightRejects) + ", zero-width " +
         Str(resultA\PixelWidthRejects) + ", empty " + Str(resultA\EmptyLineRejects))
  PrintN("    bboxes " + Str(resultA\BboxTests) + " = visible/occluded/unknown " +
         Str(resultA\BboxVisible) + "/" + Str(resultA\BboxOccluded) + "/" +
         Str(resultA\BboxUnknown) + ", occlusion skips " +
         Str(resultA\OcclusionSkips))
  PrintN("    clip growth ranges/spans " + Str(resultA\ClipRangeGrowths) + "/" +
         Str(resultA\ClipSpanGrowths) + ", allocations " +
         Str(resultA\Allocations) + ", work items " + Str(resultA\WorkItems))
  PrintN("    FNV-1a64 spans " + Hex(hashA) + ", counters " + Hex(countHashA))
  If firstBad >= 0
    PrintN("    first invalid span index: " + Str(firstBad))
  EndIf

  WallVisibilityReset(@resultC)
  WallVisibilityReset(@resultB)
  WallVisibilityReset(@resultA)
  BspTraceReset(@trace)
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; I04 optional owner IWAD pass
; ---------------------------------------------------------------------------

Procedure TestI04(Path.s)
  Protected beforeSize.q = 0
  Protected afterSize.q = 0
  Protected beforeMd5.s = ""
  Protected afterMd5.s = ""
  Protected p.PNamesTable
  Protected catalog.TextureCatalog
  Protected flats.FlatCatalog
  Protected projection.Projection
  Protected pNamesCount.l = 0
  Protected textureCount.l = 0
  Protected flatCount.l = 0
  Protected projectionWidth.l = 0
  Protected projectionHeight.l = 0
  Protected centerX.l = 0
  Protected centerY.l = 0
  Protected Dim mapNames.s(2)
  Protected i.i

  If Path = ""
    PrintN("[I04] Optional real Ultimate Doom read-only projection/wall-clipping integration: NOT RUN (no WAD path argument)")
    ProcedureReturn
  EndIf

  BeginCase("I04", "Optional real Ultimate Doom read-only catalog-aware projection/wall-clipping integration")

  beforeSize = FileSize(Path)
  Check(Bool(beforeSize > 0), "owner IWAD path reports a positive size before reading")
  beforeMd5 = TestFileMd5(Path)
  Check(Bool(beforeMd5 <> ""), "owner IWAD read-only MD5 fingerprint computed before opening")
  PrintN("  owner IWAD size " + Str(beforeSize) + ", MD5 " + beforeMd5)

  If WADOpen(Path) = #False
    Check(#False, "real IWAD opens read-only: " + WADLastError())
    ProcedureReturn
  EndIf
  Check(#True, "real IWAD opens read-only")
  PrintN("  lumps: " + Str(WADGetLumpCount()))

  Check(Bool(TestLoadCatalogs(@p, @catalog, @flats, @pNamesCount,
                              @textureCount, @flatCount) <> 0),
        "PNAMES/TEXTURE1/TEXTURE2 decode+resolve and F_START/F_END flat catalog build")
  Check(Bool(pNamesCount > 0 And textureCount > 0 And flatCount > 0),
        "decoded patch, texture and flat catalog counts are positive")
  PrintN("  PNAMES " + Str(pNamesCount) + ", textures " + Str(textureCount) +
         ", flats " + Str(flatCount))

  Check(Bool(ProjectionInitClassic(@projection) <> 0),
        "immutable classic 320-column projection initializes once")
  Check(Bool(ProjectionIsValid(@projection) <> 0),
        "projection owner is valid and reusable for every map")
  Check(Bool(ProjectionGetConstants(@projection, @projectionWidth,
                                   @projectionHeight, @centerX, @centerY,
                                   0, 0, 0, 0, 0) <> 0),
        "projection constants are readable")
  Check(Bool(projectionWidth = #PROJ_VIEWWIDTH And
             projectionHeight = #PROJ_VIEWHEIGHT And
             centerX = #PROJ_CENTERX And centerY = #PROJ_CENTERY),
        "projection publishes the canonical 320x200 centered viewport")
  PrintN("  projection viewport " + Str(projectionWidth) + "x" +
         Str(projectionHeight) + ", center " + Str(centerX) + "," + Str(centerY))

  mapNames(0) = "E1M1"
  mapNames(1) = "E1M2"
  mapNames(2) = "E4M1"
  CheckWallMap("E1M1", 239, 747, 238, @projection, @flats, @catalog)
  CheckWallMap("E1M2", 448, 1463, 447, @projection, @flats, @catalog)
  CheckWallMap("E4M1", 196, 695, 195, @projection, @flats, @catalog)

  WADClose()
  Check(Bool(WADIsOpen() = #False), "WAD closes cleanly after the read-only catalog-aware pass")
  afterSize = FileSize(Path)
  afterMd5 = TestFileMd5(Path)
  Check(Bool(afterSize = beforeSize), "owner IWAD byte size unchanged after read-only pass")
  Check(Bool(afterMd5 <> "" And afterMd5 = beforeMd5), "owner IWAD MD5 fingerprint unchanged after read-only pass")
  PrintN("  owner IWAD remains unchanged: size " + Str(afterSize) + ", MD5 " + afterMd5)

  ProjectionReset(@projection)
  TextureCatalogReset(@catalog)
  PNamesReset(@p)
  FlatCatalogReset(@flats)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB M3-04 optional real-IWAD projection/wall-clipping integration (I04)")

TestI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (I04 may be NOT RUN without a WAD argument)")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
