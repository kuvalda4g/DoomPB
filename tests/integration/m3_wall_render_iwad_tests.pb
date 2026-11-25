; -----------------------------------------------------------------------------
; DoomPB - M3-05 optional real-IWAD wall-render integration (WI04)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Optional harness; the owner-provided legal IWAD path is its first argument
; (the same convention as M2/M3-01/M3-02/M3-03/M3-04 optional passes). Reads
; strictly read-only, opens the IWAD through WADOpen, builds the decoded
; PNAMES/TEXTURE1/TEXTURE2 catalogs and the F_START/F_END flat catalog,
; initializes the immutable classic 320-column Projection once, then for
; E1M1/E1M2/E4M1:
;   - loads the map through the validated M2 MapLevel APIs;
;   - checks MapLevelValidateResources against the decoded catalogs;
;   - derives the fixed camera + checked static viewz from the exact player-one
;     THING start using WallRenderPlayerStartView, and independently derives the
;     same THING index, point-in-subsector leaf, floor sector and floor+41 fixed
;     viewz; camera X/Y/raw heading equivalence with the historic M3-04 camera
;     selection is required before any M3-04 fingerprint is reused;
;   - keeps the pre-existing cull-free BspTraceBuild as an independent cross-
;     check for reachable leaf/seg/node totals;
;   - runs the catalog-aware WallVisibilityBuild from the equivalent view
;     camera and verifies every published span against decoded map records and
;     independently recomputed SOLID/PASS/SKIP classification;
;   - asserts the unchanged M3-04 span and counter FNV fingerprints where the
;     same camera/catalog conditions apply, and repeats Build (including Reset)
;     for deterministic span/counter/bbox/clip/work/allocation identity;
;   - renders the complete M3-05 wall-only 320x200 debug-color frame through
;     WallRenderFrame with M2 catalogs, then independently hashes the exact
;     64,000 row-major palette bytes, checks canonical 16-digit uppercase text,
;     nonzero middle/upper/lower and background palette indices, tier-count
;     reconciliation, column/tier-range boundaries, zero out-of-frame columns,
;     three checked allocations and accessor aggregate equality;
;   - repeats render twice (including explicit visibility Reset and caller
;     target reuse) and requires identical production/independent frame hashes;
;     once independently locked, each map's expected frame-hash text is also
;     asserted. The locked values are derived only after source-identity and
;     M3-04 fingerprint preservation pass, repeated compiled agreement, and
;     owner visual inspection; no unreviewed first-output is frozen blindly.
;
; The IWAD is never written: before/after byte size and MD5 are compared. Its
; MD5 may be printed for identification but another legitimate IWAD hash is not
; rejected. Only coarse totals and FNV-1a64 hashes are printed: no map geometry
; coordinates, whole record lists, WAD payload bytes, textures, flats, sprites
; or screenshots are printed, copied, stored or committed.
;
; Without a path argument WI04 is reported NOT RUN; that is not failure.
; Exit code: 0 when every assertion passed (or NOT RUN), else failure count.
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
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Graphics/FrameBuffer.pbi"
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

; Independent canonical 16-nibble uppercase rendering of a signed64 bit pattern,
; including leading zeros that the built-in Hex() omits for positive values.
; It never calls the production WallFrameHashHex64 helper.
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

; Exact 16-digit uppercase comparison against a locked FNV-1a64 fingerprint.
; Hex() on a signed .q prints the unsigned two's-complement value; expected
; constants are canonical uppercase text, including leading zeros when needed.
Procedure.i TestHashTextEquals(Value.q, Expected.s)
  Protected actual.s = TestHex64Canonical(Value)
  ProcedureReturn Bool(Len(Expected) = 16 And Len(actual) = 16 And actual = Expected)
EndProcedure

; Strict canonical 16-character uppercase hexadecimal shape: no lowercase,
; whitespace, sign or missing leading zero can masquerade as a frame hash.
Procedure.i TestCanonicalHexText(Text.s)
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

; Unchanged M3-04 accepted owner-IWAD span fingerprints from the catalog-aware
; camera conditions captured by tests/integration/m3_wall_clip_iwad_tests.pb
; (E1M1 74B485154CE29B0B, E1M2 8AC0627513C4B619, E4M1 9FD0B15A0F33197E).
Procedure.s TestExpectedSpanHash(Name.s)
  If Name = "E1M1"
    ProcedureReturn "74B485154CE29B0B"
  ElseIf Name = "E1M2"
    ProcedureReturn "8AC0627513C4B619"
  ElseIf Name = "E4M1"
    ProcedureReturn "9FD0B15A0F33197E"
  EndIf
  ProcedureReturn ""
EndProcedure

; Unchanged M3-04 counter fingerprints captured from the same accepted harness
; run; a counter-only regression cannot be masked by equal span order.
Procedure.s TestExpectedCountsHash(Name.s)
  If Name = "E1M1"
    ProcedureReturn "7ADB45DBF2611B77"
  ElseIf Name = "E1M2"
    ProcedureReturn "83CAB0E1049B850A"
  ElseIf Name = "E4M1"
    ProcedureReturn "CCAA2442EB270717"
  EndIf
  ProcedureReturn ""
EndProcedure

; M3-05 WI04 frame-hash locks. Values are populated only after the compiled
; renderer passes source-identity/M3-04 fingerprint preservation, independent
; full-plane hashing, confirmed repeat agreement and owner visual inspection.
; Empty text means "not yet locked" and causes an explicit NOT LOCKED report
; rather than pretending a guessed expected value exists.
Procedure.s TestExpectedFrameHash(Name.s)
  If Name = "E1M1"
    ProcedureReturn "4A923E4D357C7BD1"
  ElseIf Name = "E1M2"
    ProcedureReturn "0C9627E5C2FD8D35"
  ElseIf Name = "E4M1"
    ProcedureReturn "9AEB8BDD16834359"
  EndIf
  ProcedureReturn ""
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
; *PlayerThing returns 1-based index+1 of the first type=1 record, or -1 for the
; documented vertex-0 fallback. Zero is never a valid chosen-record marker.
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
      *PlayerThing\l = i + 1
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
  *PlayerThing\l = -1
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent player point-in-subsector and equivalent view derivation
; ---------------------------------------------------------------------------

; Test-only original R_PointInSubsector equivalent, separate from the production
; WallPlayerSubsectorChecked helper. It uses the checked map root, checked node
; fixed conversion, the shared exact R_PointOnSide primitive and the raw
; NF_SUBSECTOR child encoding, bounded to nodeCount node branches. No production
; traversal result is consulted. Returns checked leaf and derived floor sector.
Procedure.i TestPointSubsectorIndependent(*Level.MapLevel, ThingFixedX.l,
                                         ThingFixedY.l, *Leaf.Long, *FloorSector.Long)
  Protected rootIsSubsector.l = 0
  Protected rootIndex.l = 0
  Protected nodeCount.i
  Protected subCount.i
  Protected currentNode.l = 0
  Protected nodeSteps.i = 0
  Protected rawChild.l = 0
  Protected leafIndex.l = 0
  Protected nodeX.l = 0
  Protected nodeY.l = 0
  Protected nodeDX.l = 0
  Protected nodeDY.l = 0
  Protected child0.l = 0
  Protected child1.l = 0
  Protected side.l = 0

  *Leaf\l = -1
  *FloorSector\l = -1
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    ProcedureReturn #False
  EndIf
  nodeCount = *Level\Nodes\Count
  subCount = *Level\Subsectors\Count
  If nodeCount < 0 Or subCount <= 0
    ProcedureReturn #False
  EndIf
  If MapLevelGetBspRoot(*Level, @rootIsSubsector, @rootIndex) = #False
    ProcedureReturn #False
  EndIf
  If rootIsSubsector <> 0
    If nodeCount <> 0 Or rootIndex < 0 Or rootIndex >= subCount
      ProcedureReturn #False
    EndIf
    leafIndex = rootIndex & $7FFF
    If MapLevelGetSubsectorSector(*Level, leafIndex) < 0
      ProcedureReturn #False
    EndIf
    *Leaf\l = leafIndex
    *FloorSector\l = MapLevelGetSubsectorSector(*Level, leafIndex)
    ProcedureReturn #True
  EndIf
  If nodeCount = 0 Or rootIndex < 0 Or rootIndex >= nodeCount
    ProcedureReturn #False
  EndIf
  currentNode = rootIndex
  While #True
    If nodeSteps > nodeCount
      ProcedureReturn #False
    EndIf
    If currentNode < 0 Or currentNode >= nodeCount
      ProcedureReturn #False
    EndIf
    If MapNodesGet(@*Level\Nodes, currentNode, @nodeX, @nodeY, @nodeDX, @nodeDY,
                   0, 0, 0, 0, 0, 0, 0, 0, @child0, @child1) = #False
      ProcedureReturn #False
    EndIf
    If FixedFromIntChecked(nodeX, @nodeX) = #False Or
       FixedFromIntChecked(nodeY, @nodeY) = #False Or
       FixedFromIntChecked(nodeDX, @nodeDX) = #False Or
       FixedFromIntChecked(nodeDY, @nodeDY) = #False
      ProcedureReturn #False
    EndIf
    If GeometryPointOnNodeSideChecked(ThingFixedX, ThingFixedY, nodeX, nodeY,
                                      nodeDX, nodeDY, @side) = #False
      ProcedureReturn #False
    EndIf
    If side = 0
      rawChild = child0
    Else
      rawChild = child1
    EndIf
    If (rawChild & #MAP_NF_SUBSECTOR) <> 0
      leafIndex = rawChild & $7FFF
      If leafIndex < 0 Or leafIndex >= subCount
        ProcedureReturn #False
      EndIf
      If MapLevelGetSubsectorSector(*Level, leafIndex) < 0
        ProcedureReturn #False
      EndIf
      *Leaf\l = leafIndex
      *FloorSector\l = MapLevelGetSubsectorSector(*Level, leafIndex)
      ProcedureReturn #True
    EndIf
    If rawChild < 0 Or rawChild >= nodeCount Or rawChild >= #MAP_NF_SUBSECTOR
      ProcedureReturn #False
    EndIf
    currentNode = rawChild
    nodeSteps + 1
  Wend
  ProcedureReturn #False
EndProcedure

; Derives the production WallRenderPlayerStartView and the independent THING/
; point-in-subsector/floor/viewz equivalents, then publishes granular equality
; flags for camera X/Y/raw heading, chosen THING, leaf, floor sector and viewz.
; Setup failures leave outputs invalid and equalities zero; no partial expected
; value is fabricated from a failed call.
Procedure.i TestEquivalentPlayerView(*Level.MapLevel, *View.WallView,
                                     *ReferenceCamera.BspCamera,
                                     *ViewThing.Long, *ViewSub.Long, *ViewSector.Long,
                                     *RefThing.Long, *PointLeaf.Long, *PointSector.Long,
                                     *ThingEqual.Long, *LeafEqual.Long, *SectorEqual.Long,
                                     *CameraEqual.Long, *ViewZEqual.Long)
  Protected setupOk.i
  Protected viewX.l = 0
  Protected viewY.l = 0
  Protected viewHeading.q = 0
  Protected viewZ.l = 0
  Protected refX.l = 0
  Protected refY.l = 0
  Protected refHeading.q = 0
  Protected refThingRawIndex.l = 0
  Protected refThingX.l = 0
  Protected refThingY.l = 0
  Protected refThingAngle.l = 0
  Protected refThingType.l = 0
  Protected refThingOptions.l = 0
  Protected pointFixedX.l = 0
  Protected pointFixedY.l = 0
  Protected floorHeight.l = 0
  Protected floorFixed.l = 0
  Protected derivedViewZ.q = 0

  *ViewThing\l = -1
  *ViewSub\l = -1
  *ViewSector\l = -1
  *RefThing\l = -1
  *PointLeaf\l = -1
  *PointSector\l = -1
  *ThingEqual\l = 0
  *LeafEqual\l = 0
  *SectorEqual\l = 0
  *CameraEqual\l = 0
  *ViewZEqual\l = 0

  If WallViewReset(*View) = #False Or BspCameraReset(*ReferenceCamera) = #False
    ProcedureReturn #False
  EndIf
  setupOk = WallRenderPlayerStartView(*Level, *View, *ViewThing,
                                      *ViewSub, *ViewSector)
  If setupOk = #False
    ProcedureReturn #False
  EndIf
  If TestChooseCamera(*Level, *ReferenceCamera, *RefThing) = #False
    ProcedureReturn #False
  EndIf

  ; Independent THING record selection is the chosen reference index, because
  ; WallRenderPlayerStartView's exact-one rule must agree before render use.
  If *RefThing\l <= 0
    ProcedureReturn #True
  EndIf
  refThingRawIndex = *RefThing\l - 1
  If MapThingsGet(@*Level\Things, refThingRawIndex, @refThingX, @refThingY,
                  @refThingAngle, @refThingType, @refThingOptions) = #False
    ProcedureReturn #False
  EndIf
  If refThingType <> 1
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(refThingX, @pointFixedX) = #False Or
     FixedFromIntChecked(refThingY, @pointFixedY) = #False
    ProcedureReturn #False
  EndIf
  If TestPointSubsectorIndependent(*Level, pointFixedX, pointFixedY,
                                   *PointLeaf, *PointSector) = #False
    ProcedureReturn #False
  EndIf

  If WallViewGet(*View, @viewX, @viewY, @viewHeading, @viewZ) = #False
    ProcedureReturn #False
  EndIf
  If BspCameraGet(*ReferenceCamera, @refX, @refY, @refHeading) = #False
    ProcedureReturn #False
  EndIf
  If MapSectorsGet(@*Level\Sectors, *PointSector\l, @floorHeight, 0, 0, 0, 0) = #False
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(floorHeight, @floorFixed) = #False
    ProcedureReturn #False
  EndIf
  derivedViewZ = Int(floorFixed) + Int(#WALLVIEW_ViewHeightFixed)
  If derivedViewZ < #FIXED_MIN Or derivedViewZ > #FIXED_MAX
    ProcedureReturn #False
  EndIf

  *ThingEqual\l = Bool(*RefThing\l > 0 And *ViewThing\l = *RefThing\l - 1)
  *LeafEqual\l = Bool(*ViewSub\l = *PointLeaf\l)
  *SectorEqual\l = Bool(*ViewSector\l = *PointSector\l)
  *CameraEqual\l = Bool(viewX = refX And viewY = refY And viewHeading = refHeading)
  *ViewZEqual\l = Bool(viewZ = derivedViewZ)
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Independent M3-05 full-plane FNV and palette-index audit
; ---------------------------------------------------------------------------

; Independent FNV-1a64 over exactly 64,000 row-major palette indices, offset
; -3750763034362895579 / prime 1099511628211. This is a separate harness
; implementation used to validate the production WallRenderResult hash and the
; caller target bytes; no production hash function is called here.
Procedure.q TestFrameFnv(*Buffer.FrameBuffer)
  Protected hash.q = #IWAD_FNV_Offset
  Protected byteIndex.i

  If *Buffer = 0 Or *Buffer\Magic <> #FRAMEBUFFER_Magic Or
     *Buffer\Width <> #WALLDRAW_ViewWidth Or *Buffer\Height <> #WALLDRAW_ViewHeight Or
     *Buffer\PixelCount <> #WALLDRAW_PixelCount
    ProcedureReturn -1
  EndIf
  For byteIndex = 0 To #WALLDRAW_PixelCount - 1
    hash = FnvAddByte(hash, PeekA(*Buffer\Pixels + byteIndex))
  Next
  ProcedureReturn hash
EndProcedure

; Counts every canonical debug palette index in the complete row-major plane and
; rejects any byte outside the documented background/middle/upper/lower set.
; *Other counts non-contract bytes; sum must reconcile to exactly 64,000.
Procedure.i TestPaletteAudit(*Buffer.FrameBuffer, *Background.Long,
                             *Middle.Long, *Upper.Long, *Lower.Long, *Other.Long,
                             *DistinctKinds.Long)
  Protected value.i
  Protected column.i
  Protected row.i
  Protected background.l = 0
  Protected middle.l = 0
  Protected upper.l = 0
  Protected lower.l = 0
  Protected other.l = 0
  Protected kinds.l = 0

  *Background\l = 0
  *Middle\l = 0
  *Upper\l = 0
  *Lower\l = 0
  *Other\l = 0
  *DistinctKinds\l = 0
  If *Buffer = 0 Or *Buffer\Magic <> #FRAMEBUFFER_Magic
    ProcedureReturn #False
  EndIf
  For row = 0 To #WALLDRAW_ViewHeight - 1
    For column = 0 To #WALLDRAW_ViewWidth - 1
      value = FrameBufferGetPixel(*Buffer, column, row)
      If value = #WALLDRAW_BackgroundIndex
        background + 1
      ElseIf value = #WALLDRAW_MiddleIndex
        middle + 1
      ElseIf value = #WALLDRAW_UpperIndex
        upper + 1
      ElseIf value = #WALLDRAW_LowerIndex
        lower + 1
      Else
        other + 1
      EndIf
    Next
  Next
  If background > 0
    kinds + 1
  EndIf
  If middle > 0
    kinds + 1
  EndIf
  If upper > 0
    kinds + 1
  EndIf
  If lower > 0
    kinds + 1
  EndIf
  *Background\l = background
  *Middle\l = middle
  *Upper\l = upper
  *Lower\l = lower
  *Other\l = other
  *DistinctKinds\l = kinds
  ProcedureReturn Bool(other = 0 And
                       background + middle + upper + lower = #WALLDRAW_PixelCount And
                       kinds >= 2 And background > 0)
EndProcedure

; The 18-output WallRenderGetStats accessor must expose exactly the result's own
; numeric counters and signed64 hash. No output pointer is required except those
; exercised here; all bounded fields are read through the public accessor.
Procedure.i TestRenderStatsAccessorMatches(*Result.WallRenderResult)
  Protected spanCount.l
  Protected segmentCount.l
  Protected segmentCapacity.l
  Protected processed.l
  Protected drawn.l
  Protected middle.l
  Protected upper.l
  Protected lower.l
  Protected middleRanges.l
  Protected upperRanges.l
  Protected lowerRanges.l
  Protected drawRanges.l
  Protected empty.l
  Protected clipped.l
  Protected outOfFrame.l
  Protected allocations.l
  Protected hashValue.q
  Protected nonzero.l

  If WallRenderGetStats(*Result, @spanCount, @segmentCount, @segmentCapacity,
                        @processed, @drawn, @middle, @upper, @lower,
                        @middleRanges, @upperRanges, @lowerRanges, @drawRanges,
                        @empty, @clipped, @outOfFrame, @allocations,
                        @hashValue, @nonzero) = #False
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(spanCount = *Result\SpanCount And
                       segmentCount = *Result\SegmentCount And
                       segmentCapacity = *Result\SegmentCapacity And
                       processed = *Result\ProcessedColumns And
                       drawn = *Result\DrawnPixels And
                       middle = *Result\MiddlePixels And
                       upper = *Result\UpperPixels And
                       lower = *Result\LowerPixels And
                       middleRanges = *Result\MiddleRanges And
                       upperRanges = *Result\UpperRanges And
                       lowerRanges = *Result\LowerRanges And
                       drawRanges = *Result\DrawRanges And
                       empty = *Result\EmptyColumns And
                       clipped = *Result\ClippedColumns And
                       outOfFrame = *Result\OutOfFrameColumns And
                       allocations = *Result\Allocations And
                       hashValue = *Result\Hash And
                       nonzero = Bool(*Result\DrawnPixels <> 0))
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
  Protected view.WallView
  Protected target.FrameBuffer
  Protected renderA.WallRenderResult
  Protected renderB.WallRenderResult
  Protected renderC.WallRenderResult
  Protected viewThing.l = -1
  Protected viewSub.l = -1
  Protected viewSector.l = -1
  Protected pointLeaf.l = -1
  Protected pointSector.l = -1
  Protected thingEqual.l = 0
  Protected leafEqual.l = 0
  Protected sectorEqual.l = 0
  Protected cameraEqual.l = 0
  Protected viewZEqual.l = 0
  Protected viewSetupOk.i = 0
  Protected renderOkA.i = 0
  Protected renderOkB.i = 0
  Protected renderOkC.i = 0
  Protected frameHashA.q = -1
  Protected frameHashB.q = -1
  Protected frameHashC.q = -1
  Protected targetHashA.q = -1
  Protected targetHashB.q = -1
  Protected targetHashC.q = -1
  Protected frameTextA.s = ""
  Protected frameTextB.s = ""
  Protected frameTextC.s = ""
  Protected expectedSpan.s = ""
  Protected expectedCounts.s = ""
  Protected expectedFrame.s = ""
  Protected background.l = 0
  Protected middle.l = 0
  Protected upper.l = 0
  Protected lower.l = 0
  Protected otherColors.l = 0
  Protected distinctKinds.l = 0
  Protected auditOk.i = 0
  Protected pixelValue.i = -1
  Protected frameValid.i = 0
  Protected allocationOk.i = 0
  Protected statsOk.i = 0

  MapLevelReset(@level)
  Check(Bool(MapLevelLoad(Name, @level) <> 0), Name + " loads through validated M2 MapLevel API")
  Check(Bool(MapLevelIsReady(@level) <> 0 And level\Name = Name),
        Name + " loaded level identity/readiness is canonical")
  Check(Bool(MapLevelValidateResources(@level, *Flats, *Textures) <> 0),
        Name + " references resolve through the decoded flat/texture catalogs")
  Check(Bool(TestChooseCamera(@level, @camera, @playerThing) <> 0),
        Name + " historic M3-04 camera derivation succeeds")
  Check(Bool(playerThing > 0),
        Name + " validated player-one THING start actually present, no vertex fallback")

  ; Production static view and independent THING/point-in-subsector/floor/viewz
  ; equivalence must pass before the M3-04 fingerprints or a frame are trusted.
  viewSetupOk = TestEquivalentPlayerView(@level, @view, @camera,
                                         @viewThing, @viewSub, @viewSector,
                                         @playerThing, @pointLeaf, @pointSector,
                                         @thingEqual, @leafEqual, @sectorEqual,
                                         @cameraEqual, @viewZEqual)
  Check(Bool(viewSetupOk <> 0),
        Name + " production WallRenderPlayerStartView and independent equivalents prepare")
  Check(Bool(thingEqual <> 0),
        Name + " production view selects exactly the independently chosen THING record")
  Check(Bool(leafEqual <> 0),
        Name + " production view subsector equals independent R_PointInSubsector leaf")
  Check(Bool(sectorEqual <> 0),
        Name + " production view floor sector equals the independent leaf-derived sector")
  Check(Bool(cameraEqual <> 0),
        Name + " view camera fixed X/Y/raw heading equal historic M3-04 camera state")
  Check(Bool(viewZEqual <> 0),
        Name + " checked viewz equals independent floorheight<<16 + 41*FRACUNIT")

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
  Check(Bool(WallVisibilityBuild(@level, @view\Camera, *Projection, *Flats,
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

  ; Preserve the accepted M3-04 owner-IWAD fingerprints for the same camera/
  ; catalog conditions; camera equivalence above is a precondition of reuse.
  expectedSpan = TestExpectedSpanHash(Name)
  expectedCounts = TestExpectedCountsHash(Name)
  Check(Bool(expectedSpan <> "" And TestHashTextEquals(hashA, expectedSpan)),
        Name + " unchanged M3-04 span fingerprint " + expectedSpan + " preserved")
  Check(Bool(expectedCounts <> "" And TestHashTextEquals(countHashA, expectedCounts)),
        Name + " unchanged M3-04 counter fingerprint " + expectedCounts + " preserved")

  ; ---------------------------------------------------------------------------
  ; First complete M3-05 compiled frame from visibility result A
  ; ---------------------------------------------------------------------------
  Check(Bool(FrameBufferReset(@target) <> 0), Name + " caller target released before first frame")
  Check(Bool(FrameBufferGetPixel(@target, 0, 0) = -1),
        Name + " released target pixel access is safely rejected")
  Check(Bool(WallRenderResultReset(@renderA) <> 0 And
             WallRenderResultReset(@renderB) <> 0 And
             WallRenderResultReset(@renderC) <> 0),
        Name + " three frame-result owners reset before render use")
  renderOkA = WallRenderFrame(@level, @view, *Projection, *Flats, *Textures,
                              @resultA, @target, @renderA, #True)
  Check(Bool(renderOkA <> 0), Name + " expected-visible M3-05 frame renders with nonzero pixels")
  Check(Bool(WallRenderResultIsValid(@renderA) <> 0), Name + " first render result is valid")
  Check(Bool(renderA\Ready <> 0 And renderA\FrameWidth = #WALLDRAW_ViewWidth And
             renderA\FrameHeight = #WALLDRAW_ViewHeight),
        Name + " result publishes a ready canonical 320x200 frame")
  Check(Bool(renderA\SpanCount = countA And renderA\SegmentCount = countA And
             renderA\SegmentCapacity = countA),
        Name + " frame consumes every ordered visible span/segment without filtering")
  ; M3-04 publishes every raw R_AddLine candidate interval in its chronology, so
  ; overlapping portal spans can process the same physical screen column more
  ; than once. ProcessedColumns is therefore bounded by SpanCount*320 candidate
  ; column operations, while every mapped pixel row remains inside 0..199 and
  ; OutOfFrameColumns stays zero. Unique-column coverage is not assumed here.
  Check(Bool(renderA\ProcessedColumns > 0 And
             renderA\ProcessedColumns <= renderA\SpanCount * #WALLDRAW_ViewWidth),
        Name + " raw-span candidate column operations are positive and span-bounded")
  Check(Bool(renderA\OutOfFrameColumns = 0),
        Name + " every candidate tier range stayed inside y=0..199, zero out-of-frame")
  Check(Bool(renderA\ClippedColumns <= renderA\ProcessedColumns And
             renderA\EmptyColumns <= renderA\ProcessedColumns),
        Name + " clipped/empty column counters stay inside the processed-column operations")
  Check(Bool(renderA\DrawnPixels > 0), Name + " actual painted pixel count is positive")
  Check(Bool((renderA\MiddleRanges + renderA\UpperRanges + renderA\LowerRanges) = renderA\DrawRanges),
        Name + " published middle/upper/lower range counts reconcile to all draw ranges")
  Check(Bool(renderA\Allocations = 3),
        Name + " exactly metadata/clip/frame allocations, no per-column heap growth")
  allocationOk = Bool(renderA\Allocations = 3 And renderA\Plans <> 0)
  Check(Bool(allocationOk <> 0), Name + " useful span metadata owner and bounded three allocations")

  statsOk = TestRenderStatsAccessorMatches(@renderA)
  Check(Bool(statsOk <> 0), Name + " WallRenderGetStats exposes exactly the frame aggregate fields")

  frameValid = Bool(Bool(target\Magic = #FRAMEBUFFER_Magic) <> 0 And
                    target\Width = #WALLDRAW_ViewWidth And
                    target\Height = #WALLDRAW_ViewHeight And
                    target\PixelCount = #WALLDRAW_PixelCount)
  Check(Bool(frameValid <> 0), Name + " caller target owns a valid exact 64,000-byte 320x200 plane")

  frameHashA = TestFrameFnv(@target)
  targetHashA = frameHashA
  frameTextA = WallRenderGetHashText(@renderA)
  Check(Bool(frameHashA <> -1), Name + " independent harness FNV over all 64,000 palette bytes computes")
  Check(Bool(renderA\Hash = frameHashA),
        Name + " production frame hash equals independent full-plane FNV byte-for-byte")
  Check(Bool(renderA\Hash <> 0), Name + " independent frame fingerprint is nonzero")
  Check(Bool(TestCanonicalHexText(frameTextA) <> 0),
        Name + " production hash text is canonical 16 uppercase hex digits")
  Check(Bool(TestHashTextEquals(renderA\Hash, frameTextA)),
        Name + " production signed64 hash renders the same canonical 16-digit text")

  auditOk = TestPaletteAudit(@target, @background, @middle, @upper, @lower,
                            @otherColors, @distinctKinds)
  Check(Bool(auditOk <> 0),
        Name + " all 64,000 bytes are contract background/middle/upper/lower indices")
  Check(Bool(background + middle + upper + lower = #WALLDRAW_PixelCount),
        Name + " palette audit categories reconcile to exact 64,000 bytes")
  Check(Bool(background > 0 And middle + upper + lower > 0 And
             distinctKinds >= 2),
        Name + " frame satisfies at least two distinctive palette indices including background")
  Check(Bool(middle + upper + lower = renderA\DrawnPixels),
        Name + " audit nonbackground bytes equal result DrawnPixels, no phantom painted count")
  Check(Bool(background = #WALLDRAW_PixelCount - renderA\DrawnPixels),
        Name + " audit background bytes are exactly the unpainted remainder")
  Check(Bool(renderA\MiddlePixels = middle And renderA\UpperPixels = upper And
             renderA\LowerPixels = lower),
        Name + " per-tier produced counters equal independently audited pixel counts")

  pixelValue = FrameBufferGetPixel(@target, 0, 0)
  Check(Bool(pixelValue >= 0), Name + " frame row0/column0 boundary pixel is safely readable")
  pixelValue = FrameBufferGetPixel(@target, #WALLDRAW_ViewWidth - 1, #WALLDRAW_ViewHeight - 1)
  Check(Bool(pixelValue >= 0), Name + " frame row199/column319 boundary pixel is safely readable")
  pixelValue = FrameBufferGetPixel(@target, -1, 0)
  Check(Bool(pixelValue = -1), Name + " negative column boundary access rejects with -1")
  pixelValue = FrameBufferGetPixel(@target, 0, #WALLDRAW_ViewHeight)
  Check(Bool(pixelValue = -1), Name + " row200 boundary access rejects with -1")

  expectedFrame = TestExpectedFrameHash(Name)
  If expectedFrame = ""
    PrintN("    frame text " + frameTextA +
           " is NOT LOCKED yet (derivation/repeat/visual gate pending)")
  Else
    Check(Bool(TestCanonicalHexText(expectedFrame) <> 0 And
               frameTextA = expectedFrame),
          Name + " locked expected frame hash " + expectedFrame + " equals the compiled frame")
  EndIf
  PrintN("  " + Name + ": frame spans " + Str(renderA\SpanCount) +
         ", processed columns " + Str(renderA\ProcessedColumns) +
         ", drawn/tiers " + Str(renderA\DrawnPixels) + "/" +
         Str(renderA\MiddlePixels) + "/" + Str(renderA\UpperPixels) + "/" +
         Str(renderA\LowerPixels) +
         ", background " + Str(background) + ", allocations " + Str(renderA\Allocations))
  PrintN("    frame FNV-1a64 " + frameTextA + ", audit kinds " + Str(distinctKinds))

  ; Duplicate Build (Build resets its own result) must be bit-for-bit stable.
  Check(Bool(WallVisibilityBuild(@level, @view\Camera, *Projection, *Flats,
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

  ; Second independent compiled frame from duplicate Build result B.
  renderOkB = WallRenderFrame(@level, @view, *Projection, *Flats, *Textures,
                              @resultB, @target, @renderB, #True)
  Check(Bool(renderOkB <> 0), Name + " duplicate expected-visible frame render succeeds")
  Check(Bool(WallRenderResultIsValid(@renderB) <> 0), Name + " duplicate render result valid")
  frameHashB = TestFrameFnv(@target)
  targetHashB = frameHashB
  frameTextB = WallRenderGetHashText(@renderB)
  Check(Bool(frameHashB = frameHashA And targetHashB = targetHashA),
        Name + " duplicate full-plane independent FNV equals first frame byte-for-byte")
  Check(Bool(renderB\Hash = frameHashB And renderB\Hash = renderA\Hash And
             renderB\Hash <> 0),
        Name + " duplicate production hash equals first and independent full-plane FNV")
  Check(Bool(TestCanonicalHexText(frameTextB) <> 0 And frameTextB = frameTextA),
        Name + " duplicate canonical 16-digit hash text repeats exactly")
  Check(Bool(Bool(target\Magic = #FRAMEBUFFER_Magic) <> 0 And
             renderB\SpanCount = renderA\SpanCount And
             renderB\SegmentCount = renderA\SegmentCount And
             renderB\SegmentCapacity = renderA\SegmentCapacity And
             renderB\ProcessedColumns = renderA\ProcessedColumns And
             renderB\DrawnPixels = renderA\DrawnPixels And
             renderB\MiddlePixels = renderA\MiddlePixels And
             renderB\UpperPixels = renderA\UpperPixels And
             renderB\LowerPixels = renderA\LowerPixels And
             renderB\MiddleRanges = renderA\MiddleRanges And
             renderB\UpperRanges = renderA\UpperRanges And
             renderB\LowerRanges = renderA\LowerRanges And
             renderB\DrawRanges = renderA\DrawRanges And
             renderB\EmptyColumns = renderA\EmptyColumns And
             renderB\ClippedColumns = renderA\ClippedColumns And
             renderB\OutOfFrameColumns = renderA\OutOfFrameColumns And
             renderB\Allocations = renderA\Allocations),
        Name + " duplicate frame counters/tier ranges/allocations repeat exactly")
  If expectedFrame = ""
    PrintN("    duplicate frame text " + frameTextB + " remains unlocked pending repetition gate")
  Else
    Check(Bool(TestCanonicalHexText(expectedFrame) <> 0 And
               frameTextB = expectedFrame),
          Name + " locked expected frame equals the duplicate compiled frame")
  EndIf
  PrintN("    duplicate frame FNV-1a64 " + frameTextB +
         ", drawn " + Str(renderB\DrawnPixels) + ", processed " + Str(renderB\ProcessedColumns))

  ; Explicit Reset then Build proves the SAME owner is reusable without stale spans.
  resetOk = WallVisibilityReset(@resultB)
  Check(Bool(resetOk <> 0 And WallVisibilityIsValid(@resultB) <> 0 And
             WallVisibilityCount(@resultB) = 0),
        Name + " explicit result Reset is idempotent and leaves a reusable empty owner")
  Check(Bool(WallVisibilityBuild(@level, @view\Camera, *Projection, *Flats,
                                 *Textures, @resultB) <> 0),
        Name + " Reset/reused same owner Build succeeds after WAD data changes nothing")
  countC = WallVisibilityCount(@resultB)
  hashC = TestWallResultHash(@resultB)
  countHashC = TestWallCountsHash(@resultB, @hashOkC)
  Check(Bool(countC = countA And hashC = hashA And countHashC = countHashA),
        Name + " Reset/reused same-owner Build reproduces the original span/counter fingerprints")
  Check(Bool(resultB\VisitedNodes = resultA\VisitedNodes And
             resultB\VisitedSubsectors = resultA\VisitedSubsectors And
             resultB\ProcessedSegs = resultA\ProcessedSegs And
             resultB\SolidCandidates = resultA\SolidCandidates And
             resultB\PassCandidates = resultA\PassCandidates And
             resultB\OcclusionSkips = resultA\OcclusionSkips),
        Name + " Reset/reused same-owner Build keeps traversal/classification counters")

  ; Third independent compiled frame after explicit Reset/reused Build.
  renderOkC = WallRenderFrame(@level, @view, *Projection, *Flats, *Textures,
                              @resultB, @target, @renderC, #True)
  Check(Bool(renderOkC <> 0), Name + " Reset/reused expected-visible frame render succeeds")
  Check(Bool(WallRenderResultIsValid(@renderC) <> 0), Name + " Reset/reused render result valid")
  frameHashC = TestFrameFnv(@target)
  targetHashC = frameHashC
  frameTextC = WallRenderGetHashText(@renderC)
  Check(Bool(frameHashC = frameHashA And targetHashC = targetHashA And
             renderC\Hash = frameHashC And renderC\Hash <> 0),
        Name + " Reset/reused production/independent frame FNV equals first compiled frame")
  Check(Bool(TestCanonicalHexText(frameTextC) <> 0 And frameTextC = frameTextA),
        Name + " Reset/reused canonical hash text repeats first frame exactly")
  Check(Bool(Bool(target\Magic = #FRAMEBUFFER_Magic) <> 0 And
             renderC\DrawnPixels = renderA\DrawnPixels And
             renderC\ProcessedColumns = renderA\ProcessedColumns And
             renderC\SpanCount = renderA\SpanCount And
             renderC\Allocations = renderA\Allocations),
        Name + " Reset/reused frame painted/processed/span/allocation totals repeat exactly")
  If expectedFrame = ""
    PrintN("    Reset/reused frame text " + frameTextC + " remains unlocked pending repetition gate")
  Else
    Check(Bool(TestCanonicalHexText(expectedFrame) <> 0 And
               frameTextC = expectedFrame),
          Name + " locked expected frame equals the Reset/reused compiled frame")
  EndIf
  PrintN("    Reset/reused frame FNV-1a64 " + frameTextC +
         ", drawn " + Str(renderC\DrawnPixels) + ", processed " + Str(renderC\ProcessedColumns))

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

  Check(Bool(WallRenderResultReset(@renderA) <> 0 And
             WallRenderResultReset(@renderB) <> 0 And
             WallRenderResultReset(@renderC) <> 0),
        Name + " three frame results reset idempotently after the render pass")
  Check(Bool(renderA\Ready = 0 And renderA\Plans = 0 And renderA\SpanCount = 0 And
             renderA\SegmentCapacity = 0 And renderA\Hash = 0),
        Name + " frame result Reset freed span metadata and left reusable zero counters")
  Check(Bool(FrameBufferReset(@target) <> 0 And Bool(target\Magic = #FRAMEBUFFER_Magic) = 0),
        Name + " caller target plane released cleanly after the full render pass")
  WallVisibilityReset(@resultB)
  WallVisibilityReset(@resultA)
  WallViewReset(@view)
  BspTraceReset(@trace)
  MapLevelReset(@level)
EndProcedure

; ---------------------------------------------------------------------------
; WI04 optional owner IWAD pass
; ---------------------------------------------------------------------------

Procedure TestWI04(Path.s)
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
    PrintN("[WI04] Optional real Ultimate Doom read-only wall-render integration: NOT RUN (no WAD path argument)")
    ProcedureReturn
  EndIf

  BeginCase("WI04", "Optional real Ultimate Doom read-only catalog-aware wall visibility and compiled 320x200 frame integration")

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
PrintN("DoomPB M3-05 optional real-IWAD wall-render integration (WI04)")

TestWI04(ProgramParameter(0))

PrintN("")
PrintN("Cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS (WI04 may be NOT RUN without a WAD argument)")
  End 0
EndIf
PrintN("RESULT: FAIL")
End gFailureCount
