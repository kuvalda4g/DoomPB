; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Headless wall visibility and live occlusion walker from Linux Doom 1.10:
;   r_bsp.c: R_AddLine, R_CheckBBox (checkcoord[12][4]), R_Subsector,
;            R_RenderBSPNode (near child first, far child only after R_CheckBBox);
;   r_main.c/r_state.h: viewangletox, xtoviewangle, clipangle, solidsegs.
;
; This is visible wall-column intervals only: no R_StoreWallRange, drawseg_t,
; vertical projection, textures, COLORMAP, pixels or planes.
;
; R_AddLine phase order is source-faithful:
;   1. angles of seg->v1 and seg->v2 from the explicit camera position;
;   2. span = angle1-angle2 modulo 2^32; span>=ANG180 rejects a backface;
;   3. preserve the original global angle1 value in the published span identity
;      context only (the raw angle is not stored in a span; it is consumed here);
;   4. angle1-=viewangle, angle2-=viewangle with unsigned wrap;
;   5. left: tspan=angle1+clipangle; if tspan>2*clipangle then subtract and
;      tspan>=span rejects; else angle1=clipangle. Right: tspan=clipangle-angle2;
;      same strict checks; else angle2=-clipangle;
;   6. fine indexes (angle+ANG90)>>ANGLETOFINESHIFT; if either reaches outside
;      viewangletox[4096] this is a diagnosed input-invariant failure;
;   7. x1=viewangletox[angle1], x2=viewangletox[angle2]; x1==x2 rejects a
;      zero-pixel seg; x2<=x1 is diagnosed instead of constructing an inverted
;      interval; candidate [x1,x2-1] is inclusive;
;   8. classify: missing back sector -> SOLID; closed door (back ceiling <=
;      front floor or back floor >= front ceiling) -> SOLID; unequal
;      floor/ceiling -> PASS; otherwise identical planes+light+absent middle
;      texture -> SKIP an empty trigger line; all other two-sided -> PASS;
;   9. feed ClipSolidSegment/ClipPassSegment in their original order.
;
; Sector height comparisons use signed map-unit longs directly. Both sides are
; exact multiples of FRACUNIT in the original, so <=/>=/<> relations are
; monotonic-equivalent; no fixed arithmetic is needed for these three tests.
; Height offsets that would need arithmetic are not used in M3-04.
;
; Texture/flat identity policy:
;   - when a decoded FlatCatalog/TextureCatalog is supplied, resolved catalog
;     indices reproduce the original R_FlatNumForName / R_TextureNumForName
;     equality tests. A canonical "-" or all-NUL middle slot is NoTexture;
;     catalog-aware middle absence follows the original `midtexture==0` test,
;     which also covers a genuine first catalog texture index 0 (documented
;     vanilla quirk). Missing/malformed names are explicit build diagnostics;
;   - without catalogs, on already structurally validated maps, a narrowly
;     defined canonical raw eight-byte comparison is used: identical canonical
;     bytes -> identical planes; any malformed/noncanonical flat slot -> not
;     identical (conservative PASS, never a false SKIP). A canonical "-"/all-NUL
;     middle slot is absent; any malformed wall slot is treated as present
;     (conservative PASS). Read/API failures are still explicit errors. This
;     fallback cannot invent a texture index and cannot falsely mark an opaque
;     wall opaque-free;
;   - arbitrary hyphen prefixes and embedded-NUL names are never interpreted as
;     empty NoTexture slots.
;
; R_CheckBBox is source-faithful for every reachable camera/box region:
;   box fields {TOP,BOTTOM,LEFT,RIGHT}; boxx <=left/ <right/ else; boxy >=top/
;   >bottom/ else; boxpos=(boxy<<2)+boxx; boxpos==5 (camera inside) -> visible;
;   exact checkcoord corner selection; camera-relative BAM angles; span>=ANG180
;   conservatively visible; same clipangle/2*clipangle strict clips; same
;   viewangletox projection; sx1==sx2 -> not visible; sx2--; scan live posts
;   with `start->last < sx2`; one post fully containing [sx1,sx2] -> occluded,
;   otherwise potentially visible.
; The C table has {0} placeholder rows 3, 7 and an unreachable trailing row 11;
; boxpos=(boxy<<2)+boxx can only be 0,1,2,4,5,6,8,9,10, so those rows are not
; reachable. They are nevertheless treated as UNKNOWN/conservatively visible if
; ever requested, and any genuine fixed arithmetic/table/index uncertainty is
; UNKNOWN -> the far branch is visited and a counter records the fallback.
; Placeholders are encoded exactly but never decoded as a degenerate culling.
;
; Online BSP traversal:
;   - iterative explicit stack, no recursion; a node visit pushes its far-check
;     below its near child visit, so the complete near subtree processes segs
;     and updates solidsegs BEFORE the far bbox is tested;
;   - root conventions reuse validated MapLevel: node maps root=nodes-1, zero
;     nodes + one subsector root=subsector0 encoded with NF_SUBSECTOR;
;   - raw child encoding checked: high bit NF_SUBSECTOR, low 15 bits leaf index;
;     nonleaf child < nodeCount and < NF_SUBSECTOR;
;   - stack capacity is 2*nodeCount+4 (acyclic current path bound, validated
;     graphs may share children); cycles/DAG explosion terminate at explicit
;     stack/work budgets with diagnostics. No repeated node is silently skipped;
;   - counters are distinct from M3-03 BspTrace: OcclusionSkips counts only far
;     child visits actually pruned by an OCCLUDED bbox verdict, never segment
;     backface/FOV/pixel/empty rejects.
;
; Output WallVisibilityResult owns a deep copy of visible spans and counters,
; never MapLevel/ClipState/WAD/catalog pointers; it remains readable after
; WADClose/MapLevelReset. Every Build is transactional: reset first, failure
; leaves a valid empty result and diagnostics, level/camera/projection intact.
; Hard caps: 1,000,000 spans and 4,000,000 stack work items; range/span storage
; growths follow ClipSegs bounds. No per-seg heap allocation except bounded
; storage growth; no log, window, image, gameplay or external service call.
;
; Source seg order is a subsector's firstseg..firstseg+numsegs-1; emitted spans
; keep that chronology and each seg's fragments left-to-right. One seg may
; produce several visible fragments; span count is not seg count.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLVISIBILITY_PBI, #PB_Constant) = 0

#DOOMPB_WALLVISIBILITY_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Map/MapLevel.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "../Graphics/TextureDefs.pbi"
XIncludeFile "Geometry.pbi"
XIncludeFile "Camera.pbi"
XIncludeFile "Projection.pbi"
XIncludeFile "ClipSegs.pbi"

#WALLVIS_Magic = $57565331
#WALLVIS_MaxSpans = 1000000
#WALLVIS_MaxWorkItems = 4000000
#WALLVIS_NoIndex = -1

; R_AddLine outcome classes used for counters and tests.
#WALLLINE_EmptySkip = 0
#WALLLINE_Backface = 1
#WALLLINE_FovLeft = 2
#WALLLINE_FovRight = 3
#WALLLINE_ZeroWidth = 4
#WALLLINE_Solid = 5
#WALLLINE_Pass = 6

#WALL_EmptySkip = 0
#WALL_Backface = 1
#WALL_FovLeft = 2
#WALL_FovRight = 3
#WALL_ZeroWidth = 4
#WALL_Solid = 5
#WALL_Pass = 6

; R_CheckBBox tri-state helper verdicts (OCCLUDED keeps original false; UNKNOWN
; is the conservative fallback that visits geometry rather than culling it).
#WALLBBOX_Occluded = 0
#WALLBBOX_Visible = 1
#WALLBBOX_Unknown = 2

; Online stack work-item kinds. FarCheck is pushed below Visit so near completes.
#WALLVIS_WorkVisit = 0
#WALLVIS_WorkFarCheck = 1

; checkcoord dimensions and exact C table shape.
#WALL_CHECKCOORD_ROWS = 12
#WALL_CHECKCOORD_COLS = 4

Structure WallSpan
  Subsector.l
  Seg.l
  Linedef.l
  Side.l
  FrontSector.l
  BackSector.l
  FirstX.l
  LastX.l
  Kind.l
EndStructure

Structure WallVisibilityResult
  Magic.l
  Count.l
  Capacity.l
  *Spans.WallSpan
  VisitedNodes.l
  VisitedSubsectors.l
  ProcessedSegs.l
  EmittedFragments.l
  BackfaceRejects.l
  FovLeftRejects.l
  FovRightRejects.l
  FovRejects.l
  PixelWidthRejects.l
  EmptyLineRejects.l
  SolidCandidates.l
  PassCandidates.l
  BboxTests.l
  BboxVisible.l
  BboxOccluded.l
  BboxUnknown.l
  OcclusionSkips.l
  WorkItems.l
  ClipRangeGrowths.l
  ClipSpanGrowths.l
  Allocations.l
EndStructure

Structure WallWorkItem
  Kind.l
  Node.l
  Child.l
  Box.l
EndStructure

Structure WallSlotNameOut
  Value.s
EndStructure

; Exact R_CheckBBox checkcoord[12][4] bytes. Rows 0..10 are the source list;
; rows 3/7 are {0} placeholders, row 5 is the unreachable inside-box row, and
; row 11 is the C declaration's zero-filled trailing row. Only 0,1,2,4,5,6,
; 8,9,10 are geometrically reachable from boxpos=(boxy<<2)+boxx.
DataSection
  WallCheckCoordData:
  Data.b 3,0,2,1, 3,0,2,0, 3,1,2,0, 0,0,0,0
  Data.b 2,0,2,1, 0,0,0,0, 3,1,3,0, 0,0,0,0
  Data.b 2,0,3,1, 2,1,3,1, 2,1,3,0, 0,0,0,0
EndDataSection

Global *gWallCheckCoordData = ?WallCheckCoordData
Global gWall_LastError.s = ""

Procedure WallSetError(Message.s)
  gWall_LastError = Message
EndProcedure

Procedure.s WallVisibilityLastError()
  ProcedureReturn gWall_LastError
EndProcedure

; ---------------------------------------------------------------------------
; Result ownership and accessors
; ---------------------------------------------------------------------------

Procedure.i WallVisibilityReset(*Result.WallVisibilityResult)
  If *Result = 0
    WallSetError("Wall visibility result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Result\Magic = #WALLVIS_Magic
    If *Result\Spans <> 0
      FreeMemory(*Result\Spans)
    EndIf
  ElseIf *Result\Magic <> 0
    WallSetError("Wall visibility result has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Result\Spans <> 0
    WallSetError("Wall visibility result has an unexplained span pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  *Result\Magic = #WALLVIS_Magic
  *Result\Count = 0
  *Result\Capacity = 0
  *Result\Spans = 0
  *Result\VisitedNodes = 0
  *Result\VisitedSubsectors = 0
  *Result\ProcessedSegs = 0
  *Result\EmittedFragments = 0
  *Result\BackfaceRejects = 0
  *Result\FovLeftRejects = 0
  *Result\FovRightRejects = 0
  *Result\FovRejects = 0
  *Result\PixelWidthRejects = 0
  *Result\EmptyLineRejects = 0
  *Result\SolidCandidates = 0
  *Result\PassCandidates = 0
  *Result\BboxTests = 0
  *Result\BboxVisible = 0
  *Result\BboxOccluded = 0
  *Result\BboxUnknown = 0
  *Result\OcclusionSkips = 0
  *Result\WorkItems = 0
  *Result\ClipRangeGrowths = 0
  *Result\ClipSpanGrowths = 0
  *Result\Allocations = 0
  gWall_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i WallVisibilityIsValid(*Result.WallVisibilityResult)
  ProcedureReturn Bool(*Result <> 0 And *Result\Magic = #WALLVIS_Magic)
EndProcedure

Procedure.i WallVisibilityCount(*Result.WallVisibilityResult)
  If WallVisibilityIsValid(*Result) = #False
    WallSetError("Wall visibility result is not initialized.")
    ProcedureReturn -1
  EndIf
  ProcedureReturn *Result\Count
EndProcedure

Procedure.i WallVisibilityGetSpan(*Result.WallVisibilityResult, SpanIndex.i,
                                  *Subsector.Long, *Seg.Long, *Linedef.Long, *Side.Long,
                                  *FrontSector.Long, *BackSector.Long,
                                  *FirstX.Long, *LastX.Long, *Kind.Long)
  Protected *span.WallSpan

  If WallVisibilityIsValid(*Result) = #False
    WallSetError("Wall visibility result is not initialized.")
    ProcedureReturn #False
  EndIf
  If SpanIndex < 0 Or SpanIndex >= *Result\Count
    WallSetError("Wall visibility span index out of range: " + Str(SpanIndex) + ".")
    ProcedureReturn #False
  EndIf
  *span = *Result\Spans + SpanIndex * SizeOf(WallSpan)
  If *Subsector <> 0
    PokeL(*Subsector, *span\Subsector)
  EndIf
  If *Seg <> 0
    PokeL(*Seg, *span\Seg)
  EndIf
  If *Linedef <> 0
    PokeL(*Linedef, *span\Linedef)
  EndIf
  If *Side <> 0
    PokeL(*Side, *span\Side)
  EndIf
  If *FrontSector <> 0
    PokeL(*FrontSector, *span\FrontSector)
  EndIf
  If *BackSector <> 0
    PokeL(*BackSector, *span\BackSector)
  EndIf
  If *FirstX <> 0
    PokeL(*FirstX, *span\FirstX)
  EndIf
  If *LastX <> 0
    PokeL(*LastX, *span\LastX)
  EndIf
  If *Kind <> 0
    PokeL(*Kind, *span\Kind)
  EndIf
  gWall_LastError = ""
  ProcedureReturn #True
EndProcedure

; Aggregate counters. Every output pointer may be null. A successful call
; clears stale diagnostic text.
Procedure.i WallVisibilityGetStats(*Result.WallVisibilityResult,
                                   *VisitedNodes.Long, *VisitedSubsectors.Long,
                                   *ProcessedSegs.Long, *EmittedFragments.Long,
                                   *BackfaceRejects.Long, *FovLeftRejects.Long,
                                   *FovRightRejects.Long, *FovRejects.Long,
                                   *PixelWidthRejects.Long, *EmptyLineRejects.Long,
                                   *SolidCandidates.Long, *PassCandidates.Long,
                                   *BboxTests.Long, *BboxVisible.Long,
                                   *BboxOccluded.Long, *BboxUnknown.Long,
                                   *OcclusionSkips.Long, *WorkItems.Long,
                                   *ClipRangeGrowths.Long, *ClipSpanGrowths.Long,
                                   *Allocations.Long)
  If WallVisibilityIsValid(*Result) = #False
    WallSetError("Wall visibility result is not initialized.")
    ProcedureReturn #False
  EndIf
  If *VisitedNodes <> 0
    PokeL(*VisitedNodes, *Result\VisitedNodes)
  EndIf
  If *VisitedSubsectors <> 0
    PokeL(*VisitedSubsectors, *Result\VisitedSubsectors)
  EndIf
  If *ProcessedSegs <> 0
    PokeL(*ProcessedSegs, *Result\ProcessedSegs)
  EndIf
  If *EmittedFragments <> 0
    PokeL(*EmittedFragments, *Result\EmittedFragments)
  EndIf
  If *BackfaceRejects <> 0
    PokeL(*BackfaceRejects, *Result\BackfaceRejects)
  EndIf
  If *FovLeftRejects <> 0
    PokeL(*FovLeftRejects, *Result\FovLeftRejects)
  EndIf
  If *FovRightRejects <> 0
    PokeL(*FovRightRejects, *Result\FovRightRejects)
  EndIf
  If *FovRejects <> 0
    PokeL(*FovRejects, *Result\FovRejects)
  EndIf
  If *PixelWidthRejects <> 0
    PokeL(*PixelWidthRejects, *Result\PixelWidthRejects)
  EndIf
  If *EmptyLineRejects <> 0
    PokeL(*EmptyLineRejects, *Result\EmptyLineRejects)
  EndIf
  If *SolidCandidates <> 0
    PokeL(*SolidCandidates, *Result\SolidCandidates)
  EndIf
  If *PassCandidates <> 0
    PokeL(*PassCandidates, *Result\PassCandidates)
  EndIf
  If *BboxTests <> 0
    PokeL(*BboxTests, *Result\BboxTests)
  EndIf
  If *BboxVisible <> 0
    PokeL(*BboxVisible, *Result\BboxVisible)
  EndIf
  If *BboxOccluded <> 0
    PokeL(*BboxOccluded, *Result\BboxOccluded)
  EndIf
  If *BboxUnknown <> 0
    PokeL(*BboxUnknown, *Result\BboxUnknown)
  EndIf
  If *OcclusionSkips <> 0
    PokeL(*OcclusionSkips, *Result\OcclusionSkips)
  EndIf
  If *WorkItems <> 0
    PokeL(*WorkItems, *Result\WorkItems)
  EndIf
  If *ClipRangeGrowths <> 0
    PokeL(*ClipRangeGrowths, *Result\ClipRangeGrowths)
  EndIf
  If *ClipSpanGrowths <> 0
    PokeL(*ClipSpanGrowths, *Result\ClipSpanGrowths)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Result\Allocations)
  EndIf
  gWall_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Isolated predicates and table accessors
; ---------------------------------------------------------------------------

; The exact original backface predicate: unsigned span >= ANG180, including
; equality. Exposed for the threshold-vector tests.
Procedure.i WallSpanIsBackface(Span.q)
  ProcedureReturn Bool(Span >= #BAM_ANG180)
EndProcedure

; Original R_AddLine/R_CheckBBox left-edge branch, factored as a pure checked
; helper: tspan=relative+clipangle; strict `tspan > 2*clipangle`; subtract;
; `tspan >= span` rejects; otherwise relative is clipped to clipangle. A span
; exactly on the boundary (tspan==2*clipangle) is not adjusted; this is the
; source's `>`/`>=` asymmetry. Returns adjusted raw and rejected flag.
Procedure.i WallApplyLeftClip(Relative.q, Span.q, Clip.q, *Adjusted.Quad, *Rejected.Long)
  Protected tspan.q
  Protected twoClip.q

  WallSetError("")
  If *Adjusted = 0 Or *Rejected = 0
    WallSetError("WallApplyLeftClip: output pointer is null.")
    ProcedureReturn #False
  EndIf
  twoClip = BamAdd(Clip, Clip)
  tspan = BamAdd(Relative, Clip)
  If tspan > twoClip
    tspan = BamSubtract(tspan, twoClip)
    If tspan >= Span
      PokeQ(*Adjusted, 0)
      *Rejected\l = 1
      ProcedureReturn #True
    EndIf
    PokeQ(*Adjusted, BamWrap32(Clip))
    *Rejected\l = 0
    ProcedureReturn #True
  EndIf
  PokeQ(*Adjusted, BamWrap32(Relative))
  *Rejected\l = 0
  ProcedureReturn #True
EndProcedure

; Original right-edge branch: tspan=clipangle-relative; strict >2*clipangle;
; subtract; `tspan >= span` rejects; otherwise relative is negated clipangle.
; Exact boundary equality is not adjusted.
Procedure.i WallApplyRightClip(Relative.q, Span.q, Clip.q, *Adjusted.Quad, *Rejected.Long)
  Protected tspan.q
  Protected twoClip.q

  WallSetError("")
  If *Adjusted = 0 Or *Rejected = 0
    WallSetError("WallApplyRightClip: output pointer is null.")
    ProcedureReturn #False
  EndIf
  twoClip = BamAdd(Clip, Clip)
  tspan = BamSubtract(Clip, Relative)
  If tspan > twoClip
    tspan = BamSubtract(tspan, twoClip)
    If tspan >= Span
      PokeQ(*Adjusted, 0)
      *Rejected\l = 1
      ProcedureReturn #True
    EndIf
    PokeQ(*Adjusted, BamNegate(Clip))
    *Rejected\l = 0
    ProcedureReturn #True
  EndIf
  PokeQ(*Adjusted, BamWrap32(Relative))
  *Rejected\l = 0
  ProcedureReturn #True
EndProcedure

; Exact checkcoord cell accessor for table-content validation.
Procedure.i WallCheckCoordGet(Row.l, Col.l, *Value.Long)
  WallSetError("")
  If *Value = 0
    WallSetError("WallCheckCoordGet: result pointer is null.")
    ProcedureReturn #False
  EndIf
  If Row < 0 Or Row > #WALL_CHECKCOORD_ROWS - 1
    WallSetError("WallCheckCoordGet: row " + Str(Row) + " is outside 0.." + Str(#WALL_CHECKCOORD_ROWS - 1) + ".")
    ProcedureReturn #False
  EndIf
  If Col < 0 Or Col > #WALL_CHECKCOORD_COLS - 1
    WallSetError("WallCheckCoordGet: column " + Str(Col) + " is outside 0.." + Str(#WALL_CHECKCOORD_COLS - 1) + ".")
    ProcedureReturn #False
  EndIf
  *Value\l = PeekB(*gWallCheckCoordData + Row * #WALL_CHECKCOORD_COLS + Col)
  ProcedureReturn #True
EndProcedure

; Original R_CheckBBox camera-relative box-position classification, factored as a
; pure checked helper so boundary ties can be tested exactly. Coordinates are
; already 16.16 fixed values:
;   boxx = 0 if CameraX <= Left; 1 if CameraX < Right; else 2;
;   boxy = 0 if CameraY >= Top; 1 if CameraY > Bottom; else 2;
;   boxpos = (boxy << 2) + boxx; reachable values 0,1,2,4,5,6,8,9,10.
; The three strict/else ties are authentic (<= for Left, < for Right, >= for Top,
; > for Bottom); equality on Right/Bottom does not select the middle region.
Procedure.i WallBoxPosition(CameraX.l, CameraY.l, BoxTop.l, BoxBottom.l,
                           BoxLeft.l, BoxRight.l,
                           *BoxX.Long, *BoxY.Long, *BoxPos.Long)
  Protected boxXIndex.l
  Protected boxYIndex.l
  Protected boxPosition.l

  WallSetError("")
  If *BoxX = 0 Or *BoxY = 0 Or *BoxPos = 0
    WallSetError("WallBoxPosition: output pointer is null.")
    ProcedureReturn #False
  EndIf

  If CameraX <= BoxLeft
    boxXIndex = 0
  ElseIf CameraX < BoxRight
    boxXIndex = 1
  Else
    boxXIndex = 2
  EndIf
  If CameraY >= BoxTop
    boxYIndex = 0
  ElseIf CameraY > BoxBottom
    boxYIndex = 1
  Else
    boxYIndex = 2
  EndIf
  boxPosition = (boxYIndex << 2) + boxXIndex
  PokeL(*BoxX, boxXIndex)
  PokeL(*BoxY, boxYIndex)
  PokeL(*BoxPos, boxPosition)
  gWall_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Canonical map slot-name readers (local, no MapValidate coupling)
; ---------------------------------------------------------------------------
; Status: 0 = canonical name in *Out\Value, 1 = canonical unused "-"/all-NUL
; slot, 2 = noncanonical name (embedded NUL / trailing bytes / nonprintable),
; 3 = decoder/API read failure with an explicit error.
Procedure.i WallFlatSlotStatus(*Level.MapLevel, SectorIndex.l, Field.l, *Out.WallSlotNameOut)
  Protected byteIndex.i
  Protected value.i
  Protected sawNul.i = 0
  Protected result.s = ""

  sawNul = #False
  For byteIndex = 0 To 7
    value = MapSectorsNameByte(@*Level\Sectors, SectorIndex, Field, byteIndex)
    If value < 0
      WallSetError("Wall flat slot read failed at " + *Level\Name + " sector " + Str(SectorIndex) + " field " + Str(Field) + ".")
      ProcedureReturn 3
    EndIf
    If sawNul
      If value <> 0 And value <> 32
        ProcedureReturn 2
      EndIf
    ElseIf value = 0
      sawNul = #True
    ElseIf value < 32 Or value > 126
      ProcedureReturn 2
    Else
      result + Chr(value)
    EndIf
  Next
  If Len(result) = 0
    ProcedureReturn 2
  EndIf
  *Out\Value = result
  ProcedureReturn 0
EndProcedure

Procedure.i WallWallSlotStatus(*Level.MapLevel, SideIndex.l, Field.l, *Out.WallSlotNameOut)
  Protected byteIndex.i
  Protected value.i
  Protected sawNul.i = 0
  Protected result.s = ""

  value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, 0)
  If value < 0
    WallSetError("Wall wall slot read failed at " + *Level\Name + " sidedef " + Str(SideIndex) + " field " + Str(Field) + ".")
    ProcedureReturn 3
  EndIf
  If value = 0 Or value = Asc("-")
    For byteIndex = 1 To 7
      value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, byteIndex)
      If value < 0
        WallSetError("Wall wall slot read failed at " + *Level\Name + " sidedef " + Str(SideIndex) + " field " + Str(Field) + ".")
        ProcedureReturn 3
      EndIf
      If value <> 0 And value <> 32
        ProcedureReturn 2
      EndIf
    Next
    *Out\Value = ""
    ProcedureReturn 1
  EndIf

  sawNul = #False
  For byteIndex = 0 To 7
    value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, byteIndex)
    If value < 0
      WallSetError("Wall wall slot read failed at " + *Level\Name + " sidedef " + Str(SideIndex) + " field " + Str(Field) + ".")
      ProcedureReturn 3
    EndIf
    If sawNul
      If value <> 0 And value <> 32
        ProcedureReturn 2
      EndIf
    ElseIf value = 0
      sawNul = #True
    ElseIf value < 32 Or value > 126
      ProcedureReturn 2
    Else
      result + Chr(value)
    EndIf
  Next
  If Len(result) = 0
    ProcedureReturn 2
  EndIf
  *Out\Value = result
  ProcedureReturn 0
EndProcedure

; Flat identity between two sectors for one field, catalog-aware or canonical
; raw-byte fallback. Returns #False only on a genuine API/resource error/read
; failure; noncanonical fallback names yield Same=0 (conservative PASS).
Procedure.i WallSectorFlatIdentity(*Level.MapLevel, *Flats.FlatCatalog,
                                   SectorA.l, SectorB.l, Field.l, *Same.Long)
  Protected statusA.i
  Protected statusB.i
  Protected nameA.WallSlotNameOut
  Protected nameB.WallSlotNameOut
  Protected indexA.i
  Protected indexB.i
  Protected byteIndex.i
  Protected byteA.i
  Protected byteB.i

  If *Flats <> 0
    statusA = WallFlatSlotStatus(*Level, SectorA, Field, @nameA)
    If statusA = 3
      ProcedureReturn #False
    EndIf
    If statusA <> 0
      WallSetError("Wall flats: " + *Level\Name + " sector " + Str(SectorA) +
                   " has a noncanonical floor/ceiling flat slot.")
      ProcedureReturn #False
    EndIf
    statusB = WallFlatSlotStatus(*Level, SectorB, Field, @nameB)
    If statusB = 3
      ProcedureReturn #False
    EndIf
    If statusB <> 0
      WallSetError("Wall flats: " + *Level\Name + " sector " + Str(SectorB) +
                   " has a noncanonical floor/ceiling flat slot.")
      ProcedureReturn #False
    EndIf
    indexA = FlatCatalogFindName(*Flats, nameA\Value)
    If indexA < 0
      WallSetError("Wall flats: " + *Level\Name + " sector " + Str(SectorA) +
                   " flat not found in the catalog: " + nameA\Value)
      ProcedureReturn #False
    EndIf
    indexB = FlatCatalogFindName(*Flats, nameB\Value)
    If indexB < 0
      WallSetError("Wall flats: " + *Level\Name + " sector " + Str(SectorB) +
                   " flat not found in the catalog: " + nameB\Value)
      ProcedureReturn #False
    EndIf
    *Same\l = Bool(indexA = indexB)
    ProcedureReturn #True
  EndIf

  ; Canonical raw eight-byte fallback; no resolved index is invented. Any
  ; noncanonical slot is conservatively "not identical".
  statusA = WallFlatSlotStatus(*Level, SectorA, Field, @nameA)
  If statusA = 3
    ProcedureReturn #False
  EndIf
  statusB = WallFlatSlotStatus(*Level, SectorB, Field, @nameB)
  If statusB = 3
    ProcedureReturn #False
  EndIf
  If statusA <> 0 Or statusB <> 0
    *Same\l = 0
    ProcedureReturn #True
  EndIf
  For byteIndex = 0 To 7
    byteA = MapSectorsNameByte(@*Level\Sectors, SectorA, Field, byteIndex)
    byteB = MapSectorsNameByte(@*Level\Sectors, SectorB, Field, byteIndex)
    If byteA < 0 Or byteB < 0
      WallSetError("Wall flats: raw eight-byte comparison read failed.")
      ProcedureReturn #False
    EndIf
    If byteA <> byteB
      *Same\l = 0
      ProcedureReturn #True
    EndIf
  Next
  *Same\l = 1
  ProcedureReturn #True
EndProcedure

; Middle-texture absence for the seg-selected sidedef. Catalog-aware returns the
; original numeric `midtexture==0` result; fallback treats canonical "-"/all-NUL
; as absent and malformed slots as present (conservative PASS).
Procedure.i WallMiddleTextureAbsent(*Level.MapLevel, *Textures.TextureCatalog,
                                    SideIndex.l, *Absent.Long)
  Protected status.i
  Protected nameSlot.WallSlotNameOut
  Protected resolvedIndex.i

  If *Textures <> 0
    status = WallWallSlotStatus(*Level, SideIndex, 2, @nameSlot)
    If status = 3
      ProcedureReturn #False
    EndIf
    If status = 2
      WallSetError("Wall textures: " + *Level\Name + " sidedef " + Str(SideIndex) +
                   " middle slot is noncanonical.")
      ProcedureReturn #False
    EndIf
    If status = 1
      *Absent\l = 1
      ProcedureReturn #True
    EndIf
    resolvedIndex = TextureCatalogFindName(*Textures, nameSlot\Value)
    If resolvedIndex < 0
      WallSetError("Wall textures: " + *Level\Name + " sidedef " + Str(SideIndex) +
                   " middle texture not found in the catalog: " + nameSlot\Value)
      ProcedureReturn #False
    EndIf
    *Absent\l = Bool(resolvedIndex = 0)
    ProcedureReturn #True
  EndIf

  status = WallWallSlotStatus(*Level, SideIndex, 2, @nameSlot)
  If status = 3
    ProcedureReturn #False
  EndIf
  If status = 1
    *Absent\l = 1
    ProcedureReturn #True
  EndIf
  *Absent\l = 0
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_AddLine equivalent
; ---------------------------------------------------------------------------
; CameraX/CameraY/Heading are explicit fixed/BAM values so the core is pure and
; callable by both the public wrapper and the online walker.
Procedure.i WallAddLineCore(*Level.MapLevel, *Projection.Projection,
                            *Flats.FlatCatalog, *Textures.TextureCatalog,
                            *Clip.ClipState, SubsectorIndex.l, SegIndex.l,
                            CameraX.l, CameraY.l, Heading.q,
                            *Outcome.Long, *Emitted.Long)
  Protected v1.l
  Protected v2.l
  Protected segAngle.l
  Protected segLine.l
  Protected segSide.l
  Protected segOffset.l
  Protected vertexX1.l
  Protected vertexY1.l
  Protected vertexX2.l
  Protected vertexY2.l
  Protected fixedX1.l = 0
  Protected fixedY1.l = 0
  Protected fixedX2.l = 0
  Protected fixedY2.l = 0
  Protected frontSector.l
  Protected backSector.l
  Protected lineFlags.l
  Protected lineSpecial.l
  Protected lineTag.l
  Protected side0.l
  Protected side1.l
  Protected selectedSide.l
  Protected selectedSector.l
  Protected frontFloor.l
  Protected frontCeiling.l
  Protected frontLight.l
  Protected backFloor.l
  Protected backCeiling.l
  Protected backLight.l
  Protected angle1.BamAngleValue
  Protected angle2.BamAngleValue
  Protected span.q
  Protected relative1.q
  Protected relative2.q
  Protected tspan.q
  Protected twoClip.q
  Protected clipAngle.q
  Protected adjustedLeft.q = 0
  Protected adjustedRight.q = 0
  Protected rejectedLeft.l = 0
  Protected rejectedRight.l = 0
  Protected fine1.q
  Protected fine2.q
  Protected x1.l = 0
  Protected x2.l = 0
  Protected outcome.l
  Protected emitted.l = 0
  Protected kind.l
  Protected beforeSpans.l
  Protected afterSpans.l
  Protected sameFloor.l = 0
  Protected sameCeiling.l = 0
  Protected sameLight.i
  Protected middleAbsent.l = 0

  WallSetError("")
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallSetError("Wall R_AddLine: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    WallSetError("Wall R_AddLine: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Clip = 0 Or ClipStateIsValid(*Clip) = #False
    WallSetError("Wall R_AddLine: clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Projection\Width <> *Clip\Width
    WallSetError("Wall R_AddLine: projection/clip logical widths differ.")
    ProcedureReturn #False
  EndIf
  If SegIndex < 0 Or SegIndex >= *Level\Segs\Count
    WallSetError("Wall R_AddLine: seg index " + Str(SegIndex) + " is out of range.")
    ProcedureReturn #False
  EndIf
  If SubsectorIndex < 0 Or SubsectorIndex >= *Level\Subsectors\Count
    WallSetError("Wall R_AddLine: subsector index " + Str(SubsectorIndex) + " is out of range.")
    ProcedureReturn #False
  EndIf
  If ProjectionGetClipAngle(*Projection, @clipAngle) = #False
    WallSetError("Wall R_AddLine: cannot read clipangle: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf

  If MapSegsGet(@*Level\Segs, SegIndex, @v1, @v2, @segAngle, @segLine, @segSide, @segOffset) = #False
    WallSetError("Wall R_AddLine: cannot read seg " + Str(SegIndex) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If MapVertexesGet(@*Level\Vertexes, v1, @vertexX1, @vertexY1) = #False
    WallSetError("Wall R_AddLine: cannot read seg v1 vertex " + Str(v1) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If MapVertexesGet(@*Level\Vertexes, v2, @vertexX2, @vertexY2) = #False
    WallSetError("Wall R_AddLine: cannot read seg v2 vertex " + Str(v2) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexX1, @fixedX1) = #False
    WallSetError("Wall R_AddLine: seg v1 X conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexY1, @fixedY1) = #False
    WallSetError("Wall R_AddLine: seg v1 Y conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexX2, @fixedX2) = #False
    WallSetError("Wall R_AddLine: seg v2 X conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(vertexY2, @fixedY2) = #False
    WallSetError("Wall R_AddLine: seg v2 Y conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  If MapLevelGetSegLinks(*Level, SegIndex, @segLine, @segSide, @frontSector, @backSector) = #False
    WallSetError("Wall R_AddLine: cannot read seg " + Str(SegIndex) + " links: " + MapLevelLastError())
    ProcedureReturn #False
  EndIf
  If segLine < 0 Or segLine >= *Level\Linedefs\Count
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " linedef index is invalid: " + Str(segLine) + ".")
    ProcedureReturn #False
  EndIf
  If segSide <> 0 And segSide <> 1
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " side is invalid: " + Str(segSide) + ".")
    ProcedureReturn #False
  EndIf
  If frontSector < 0 Or frontSector >= *Level\Sectors\Count
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " front sector is invalid: " + Str(frontSector) + ".")
    ProcedureReturn #False
  EndIf
  If backSector <> #WALLVIS_NoIndex And (backSector < 0 Or backSector >= *Level\Sectors\Count)
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " back sector is invalid: " + Str(backSector) + ".")
    ProcedureReturn #False
  EndIf

  If MapLinedefsGet(@*Level\Linedefs, segLine, 0, 0, @lineFlags, @lineSpecial, @lineTag, @side0, @side1) = #False
    WallSetError("Wall R_AddLine: cannot read linedef " + Str(segLine) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If segSide = 0
    selectedSide = side0
  Else
    selectedSide = side1
  EndIf
  If selectedSide < 0 Or selectedSide >= *Level\Sidedefs\Count
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " selects a missing sidedef.")
    ProcedureReturn #False
  EndIf
  If MapSidedefsGet(@*Level\Sidedefs, selectedSide, 0, 0, @selectedSector) = #False
    WallSetError("Wall R_AddLine: cannot read seg-selected sidedef " + Str(selectedSide) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If selectedSector < 0 Or selectedSector >= *Level\Sectors\Count Or selectedSector <> frontSector
    WallSetError("Wall R_AddLine: seg-selected sidedef sector disagrees with the derived front sector.")
    ProcedureReturn #False
  EndIf

  ; Original R_PointToAngle(v1)/R_PointToAngle(v2) and span order.
  If GeometryPointToAngleChecked(CameraX, CameraY, fixedX1, fixedY1, @angle1) = #False
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " v1 angle failed: " + GeometryLastError())
    ProcedureReturn #False
  EndIf
  If GeometryPointToAngleChecked(CameraX, CameraY, fixedX2, fixedY2, @angle2) = #False
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " v2 angle failed: " + GeometryLastError())
    ProcedureReturn #False
  EndIf
  span = BamSubtract(angle1\Raw, angle2\Raw)

  ; Backface rejection exactly `span >= ANG180`, before any solidity check.
  If WallSpanIsBackface(span)
    *Outcome\l = #WALLLINE_Backface
    *Emitted\l = 0
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf

  relative1 = BamSubtract(angle1\Raw, Heading)
  relative2 = BamSubtract(angle2\Raw, Heading)

  If WallApplyLeftClip(relative1, span, clipAngle, @adjustedLeft, @rejectedLeft) = #False
    WallSetError("Wall R_AddLine: left FOV clip helper failed: " + WallVisibilityLastError())
    ProcedureReturn #False
  EndIf
  If rejectedLeft <> 0
    *Outcome\l = #WALLLINE_FovLeft
    *Emitted\l = 0
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  relative1 = adjustedLeft

  If WallApplyRightClip(relative2, span, clipAngle, @adjustedRight, @rejectedRight) = #False
    WallSetError("Wall R_AddLine: right FOV clip helper failed: " + WallVisibilityLastError())
    ProcedureReturn #False
  EndIf
  If rejectedRight <> 0
    *Outcome\l = #WALLLINE_FovRight
    *Emitted\l = 0
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  relative2 = adjustedRight

  fine1 = BamFineIndex(BamAdd(relative1, #BAM_ANG90))
  fine2 = BamFineIndex(BamAdd(relative2, #BAM_ANG90))
  If fine1 >= #PROJ_VIEWANGLE_TOX_COUNT Or fine2 >= #PROJ_VIEWANGLE_TOX_COUNT
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " projected fine index is outside viewangletox.")
    ProcedureReturn #False
  EndIf

  If ProjectionGetViewAngleToX(*Projection, Int(fine1), @x1) = #False
    WallSetError("Wall R_AddLine: view x1 lookup failed: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf
  If ProjectionGetViewAngleToX(*Projection, Int(fine2), @x2) = #False
    WallSetError("Wall R_AddLine: view x2 lookup failed: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf

  If x1 = x2
    *Outcome\l = #WALLLINE_ZeroWidth
    *Emitted\l = 0
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  If x2 <= x1
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " produced inverted projected columns " +
                 Str(x1) + ".." + Str(x2) + "; input invariants were violated.")
    ProcedureReturn #False
  EndIf
  If x1 < 0 Or x2 - 1 > *Clip\Width - 1
    WallSetError("Wall R_AddLine: seg " + Str(SegIndex) + " candidate columns " +
                 Str(x1) + ".." + Str(x2 - 1) + " exceed the drawable domain.")
    ProcedureReturn #False
  EndIf

  ; Original occlusion classification order. The seg-selected sidedef's sector
  ; is derived front; backSector=-1 is the one-sided sentinel.
  If backSector = #WALLVIS_NoIndex
    kind = #WALL_KIND_SOLID
  Else
    If MapSectorsGet(@*Level\Sectors, frontSector, @frontFloor, @frontCeiling, @frontLight, 0, 0) = #False
      WallSetError("Wall R_AddLine: cannot read front sector " + Str(frontSector) + ": " + MapDecodeLastError())
      ProcedureReturn #False
    EndIf
    If MapSectorsGet(@*Level\Sectors, backSector, @backFloor, @backCeiling, @backLight, 0, 0) = #False
      WallSetError("Wall R_AddLine: cannot read back sector " + Str(backSector) + ": " + MapDecodeLastError())
      ProcedureReturn #False
    EndIf
    If backCeiling <= frontFloor Or backFloor >= frontCeiling
      kind = #WALL_KIND_SOLID
    ElseIf backCeiling <> frontCeiling Or backFloor <> frontFloor
      kind = #WALL_KIND_PASS
    Else
      sameLight = Bool(backLight = frontLight)
      If WallSectorFlatIdentity(*Level, *Flats, frontSector, backSector, 0, @sameFloor) = #False
        WallSetError("Wall R_AddLine: floor flat identity failed: " + WallVisibilityLastError())
        ProcedureReturn #False
      EndIf
      If WallSectorFlatIdentity(*Level, *Flats, frontSector, backSector, 1, @sameCeiling) = #False
        WallSetError("Wall R_AddLine: ceiling flat identity failed: " + WallVisibilityLastError())
        ProcedureReturn #False
      EndIf
      If WallMiddleTextureAbsent(*Level, *Textures, selectedSide, @middleAbsent) = #False
        WallSetError("Wall R_AddLine: middle texture identity failed: " + WallVisibilityLastError())
        ProcedureReturn #False
      EndIf
      If sameFloor <> 0 And sameCeiling <> 0 And sameLight <> 0 And middleAbsent <> 0
        *Outcome\l = #WALLLINE_EmptySkip
        *Emitted\l = 0
        gWall_LastError = ""
        ProcedureReturn #True
      EndIf
      kind = #WALL_KIND_PASS
    EndIf
  EndIf

  beforeSpans = *Clip\SpanCount
  If kind = #WALL_KIND_SOLID
    If ClipSolidSegment(*Clip, x1, x2 - 1, SubsectorIndex, SegIndex, segLine, segSide,
                        frontSector, backSector) = #False
      WallSetError("Wall R_AddLine: solid clip failed for seg " + Str(SegIndex) + ": " + ClipLastError())
      ProcedureReturn #False
    EndIf
    *Outcome\l = #WALLLINE_Solid
  Else
    If ClipPassSegment(*Clip, x1, x2 - 1, SubsectorIndex, SegIndex, segLine, segSide,
                       frontSector, backSector) = #False
      WallSetError("Wall R_AddLine: pass clip failed for seg " + Str(SegIndex) + ": " + ClipLastError())
      ProcedureReturn #False
    EndIf
    *Outcome\l = #WALLLINE_Pass
  EndIf
  afterSpans = *Clip\SpanCount
  emitted = afterSpans - beforeSpans
  If emitted < 0
    WallSetError("Wall R_AddLine: clip span count went backwards.")
    ProcedureReturn #False
  EndIf
  *Emitted\l = emitted
  gWall_LastError = ""
  ProcedureReturn #True
EndProcedure

; Public wrapper: reads the camera once, then runs the pure core.
Procedure.i WallVisibilityAddLine(*Level.MapLevel, *Camera.BspCamera,
                                  *Projection.Projection, *Flats.FlatCatalog,
                                  *Textures.TextureCatalog, *Clip.ClipState,
                                  SubsectorIndex.l, SegIndex.l,
                                  *Outcome.Long, *Emitted.Long)
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0

  If *Camera = 0 Or BspCameraGet(*Camera, @cameraX, @cameraY, @heading) = #False
    WallSetError("WallVisibilityAddLine: camera is not ready.")
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallAddLineCore(*Level, *Projection, *Flats, *Textures, *Clip,
                                  SubsectorIndex, SegIndex, cameraX, cameraY, heading,
                                  *Outcome, *Emitted)
EndProcedure

; ---------------------------------------------------------------------------
; R_CheckBBox equivalent
; ---------------------------------------------------------------------------
Procedure.i WallCheckBBoxCore(*Level.MapLevel, *Projection.Projection,
                              *Clip.ClipState, NodeIndex.l, BoxIndex.l,
                              CameraX.l, CameraY.l, Heading.q, *Verdict.Long)
  Protected box0Top.l
  Protected box0Bottom.l
  Protected box0Left.l
  Protected box0Right.l
  Protected box1Top.l
  Protected box1Bottom.l
  Protected box1Left.l
  Protected box1Right.l
  Protected topValue.l = 0
  Protected bottomValue.l = 0
  Protected leftValue.l = 0
  Protected rightValue.l = 0
  Protected boxx.l
  Protected boxy.l
  Protected boxpos.l
  Protected row.l
  Protected coordIndex.l
  Protected cornerValue.l = 0
  Protected x1.l = 0
  Protected y1.l = 0
  Protected x2.l = 0
  Protected y2.l = 0
  Protected angle1.BamAngleValue
  Protected angle2.BamAngleValue
  Protected relative1.q
  Protected relative2.q
  Protected span.q
  Protected tspan.q
  Protected twoClip.q
  Protected clipAngle.q
  Protected adjustedLeft.q = 0
  Protected adjustedRight.q = 0
  Protected rejectedLeft.l = 0
  Protected rejectedRight.l = 0
  Protected fine1.q
  Protected fine2.q
  Protected sx1.l = 0
  Protected sx2.l = 0
  Protected startIndex.i
  Protected rangeFirst.l = 0
  Protected rangeLast.l = 0
  Protected Dim bboxCoord.l(3)

  WallSetError("")
  If *Verdict = 0
    WallSetError("WallCheckBBoxCore: verdict pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallSetError("Wall R_CheckBBox: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    WallSetError("Wall R_CheckBBox: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Clip = 0 Or ClipStateIsValid(*Clip) = #False
    WallSetError("Wall R_CheckBBox: clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Projection\Width <> *Clip\Width
    WallSetError("Wall R_CheckBBox: projection/clip logical widths differ.")
    ProcedureReturn #False
  EndIf
  If NodeIndex < 0 Or NodeIndex >= *Level\Nodes\Count
    WallSetError("Wall R_CheckBBox: node index " + Str(NodeIndex) + " is invalid.")
    ProcedureReturn #False
  EndIf
  If BoxIndex <> 0 And BoxIndex <> 1
    WallSetError("Wall R_CheckBBox: bbox index " + Str(BoxIndex) + " must be 0 or 1.")
    ProcedureReturn #False
  EndIf

  If MapNodesGet(@*Level\Nodes, NodeIndex, 0, 0, 0, 0,
                 @box0Top, @box0Bottom, @box0Left, @box0Right,
                 @box1Top, @box1Bottom, @box1Left, @box1Right,
                 0, 0) = #False
    WallSetError("Wall R_CheckBBox: cannot read node " + Str(NodeIndex) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If BoxIndex = 0
    topValue = box0Top
    bottomValue = box0Bottom
    leftValue = box0Left
    rightValue = box0Right
  Else
    topValue = box1Top
    bottomValue = box1Bottom
    leftValue = box1Left
    rightValue = box1Right
  EndIf

  ; Signed map-unit bbox values normally convert exactly (decoded SHORT domain).
  ; A defensive conversion failure is an arithmetic uncertainty: conservative
  ; VISIBLE rather than a silent cull. It is counted in Build as UNKNOWN.
  If FixedFromIntChecked(topValue, @bboxCoord(0)) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If FixedFromIntChecked(bottomValue, @bboxCoord(1)) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If FixedFromIntChecked(leftValue, @bboxCoord(2)) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If FixedFromIntChecked(rightValue, @bboxCoord(3)) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf

  ; Exact original camera-relative box classification and inside-box short path,
  ; delegated to the pure WallBoxPosition helper so boundary ties stay exact.
  If WallBoxPosition(CameraX, CameraY, bboxCoord(0), bboxCoord(1),
                     bboxCoord(2), bboxCoord(3), @boxx, @boxy, @boxpos) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If boxpos = 5
    *Verdict\l = #WALLBBOX_Visible
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  If boxpos < 0 Or boxpos > #WALL_CHECKCOORD_ROWS - 1
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If boxpos = 3 Or boxpos = 7 Or boxpos = 11
    ; Source placeholder/trailing rows; unreachable from canonical boxpos, but
    ; never decoded as the original degenerate {0} corner selection.
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf

  If ProjectionGetClipAngle(*Projection, @clipAngle) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  row = boxpos
  If WallCheckCoordGet(row, 0, @coordIndex) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  cornerValue = bboxCoord(coordIndex)
  x1 = cornerValue
  If WallCheckCoordGet(row, 1, @coordIndex) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  y1 = bboxCoord(coordIndex)
  If WallCheckCoordGet(row, 2, @coordIndex) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  x2 = bboxCoord(coordIndex)
  If WallCheckCoordGet(row, 3, @coordIndex) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If coordIndex < 0 Or coordIndex > 3
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  y2 = bboxCoord(coordIndex)

  If GeometryPointToAngleChecked(CameraX, CameraY, x1, y1, @angle1) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If GeometryPointToAngleChecked(CameraX, CameraY, x2, y2, @angle2) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  relative1 = BamSubtract(angle1\Raw, Heading)
  relative2 = BamSubtract(angle2\Raw, Heading)
  span = BamSubtract(relative1, relative2)
  If span >= #BAM_ANG180
    ; Original "sitting on a line" conservative true.
    *Verdict\l = #WALLBBOX_Visible
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf

  If WallApplyLeftClip(relative1, span, clipAngle, @adjustedLeft, @rejectedLeft) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If rejectedLeft <> 0
    *Verdict\l = #WALLBBOX_Occluded
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  relative1 = adjustedLeft

  If WallApplyRightClip(relative2, span, clipAngle, @adjustedRight, @rejectedRight) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If rejectedRight <> 0
    *Verdict\l = #WALLBBOX_Occluded
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  relative2 = adjustedRight

  fine1 = BamFineIndex(BamAdd(relative1, #BAM_ANG90))
  fine2 = BamFineIndex(BamAdd(relative2, #BAM_ANG90))
  If fine1 >= #PROJ_VIEWANGLE_TOX_COUNT Or fine2 >= #PROJ_VIEWANGLE_TOX_COUNT
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If ProjectionGetViewAngleToX(*Projection, Int(fine1), @sx1) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If ProjectionGetViewAngleToX(*Projection, Int(fine2), @sx2) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  If sx1 = sx2
    *Verdict\l = #WALLBBOX_Occluded
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  sx2 - 1
  If sx2 < 0 Or sx1 < 0 Or sx2 > *Clip\Width - 1 Or sx1 > *Clip\Width - 1
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf

  If ClipCheckInvariants(*Clip) = #False
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  startIndex = 0
  While startIndex < *Clip\RangeCount And PeekL(*Clip\Ranges + startIndex * SizeOf(ClipRange) + 4) < sx2
    startIndex + 1
  Wend
  If startIndex >= *Clip\RangeCount
    *Verdict\l = #WALLBBOX_Unknown
    ProcedureReturn #True
  EndIf
  rangeFirst = PeekL(*Clip\Ranges + startIndex * SizeOf(ClipRange))
  rangeLast = PeekL(*Clip\Ranges + startIndex * SizeOf(ClipRange) + 4)
  If sx1 >= rangeFirst And sx2 <= rangeLast
    *Verdict\l = #WALLBBOX_Occluded
    gWall_LastError = ""
    ProcedureReturn #True
  EndIf
  *Verdict\l = #WALLBBOX_Visible
  gWall_LastError = ""
  ProcedureReturn #True
EndProcedure

; Public wrapper reads the camera once and runs the pure bbox core.
Procedure.i WallCheckBBox(*Level.MapLevel, *Camera.BspCamera,
                          *Projection.Projection, *Clip.ClipState,
                          NodeIndex.l, BoxIndex.l, *Verdict.Long)
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0

  If *Camera = 0 Or BspCameraGet(*Camera, @cameraX, @cameraY, @heading) = #False
    WallSetError("WallCheckBBox: camera is not ready.")
    ProcedureReturn #False
  EndIf
  ProcedureReturn WallCheckBBoxCore(*Level, *Projection, *Clip, NodeIndex, BoxIndex,
                                    cameraX, cameraY, heading, *Verdict)
EndProcedure

; ---------------------------------------------------------------------------
; Online near-to-far BSP visibility walk
; ---------------------------------------------------------------------------
Procedure.i WallVisibilityBuild(*Level.MapLevel, *Camera.BspCamera,
                                *Projection.Projection, *Flats.FlatCatalog,
                                *Textures.TextureCatalog, *Result.WallVisibilityResult)
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
  Protected projectionWidth.l = 0
  Protected nodeCount.l
  Protected subCount.l
  Protected segCount.l
  Protected lineCount.l
  Protected sectorCount.l
  Protected rootIsSubsector.l = 0
  Protected rootIndex.l = 0
  Protected rootRaw.l = 0
  Protected stackCapacity.l
  Protected stackBytes.q
  Protected wideStackCapacity.q
  Protected stackMemory.i
  Protected *stack.WallWorkItem
  Protected stackPointer.i = 0
  Protected clip.ClipState
  Protected clipInitial.i
  Protected itemKind.l
  Protected itemNode.l
  Protected itemChild.l
  Protected itemBox.l
  Protected rawChild.l
  Protected leafIndex.l
  Protected nodeIndex.l
  Protected numSegs.l
  Protected firstSeg.l
  Protected lastSeg.l
  Protected segIndex.l
  Protected derivedSector.l
  Protected nodeOriginX.l
  Protected nodeOriginY.l
  Protected nodeDX.l
  Protected nodeDY.l
  Protected child0.l
  Protected child1.l
  Protected nearRaw.l
  Protected farRaw.l
  Protected side.l = 0
  Protected segOutcome.l = 0
  Protected segEmitted.l = 0
  Protected verdict.l = 0
  Protected clipCountBefore.l
  Protected clipCountAfter.l
  Protected spanBytes.q
  Protected resultMemory.i = 0
  Protected *span.WallSpan
  Protected *clipSpan.ClipSpan
  Protected spanIndex.i
  Protected failure.i = 0
  Protected failureText.s = ""
  Protected visitedNodes.l = 0
  Protected visitedSubsectors.l = 0
  Protected processedSegs.l = 0
  Protected emittedFragments.l = 0
  Protected backfaceRejects.l = 0
  Protected fovLeftRejects.l = 0
  Protected fovRightRejects.l = 0
  Protected fovRejects.l = 0
  Protected pixelWidthRejects.l = 0
  Protected emptyLineRejects.l = 0
  Protected solidCandidates.l = 0
  Protected passCandidates.l = 0
  Protected bboxTests.l = 0
  Protected bboxVisible.l = 0
  Protected bboxOccluded.l = 0
  Protected bboxUnknown.l = 0
  Protected occlusionSkips.l = 0
  Protected workItems.l = 0
  Protected clipRangeGrowths.l = 0
  Protected clipSpanGrowths.l = 0
  Protected clipAllocations.l = 0
  Protected stackAllocations.l = 0
  Protected resultAllocations.l = 0
  Protected savedFailureText.s = ""

  WallSetError("")
  If *Result = 0
    WallSetError("Wall visibility result pointer is null.")
    ProcedureReturn #False
  EndIf
  If WallVisibilityReset(*Result) = #False
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallSetError("Wall visibility build: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Camera = 0 Or BspCameraGet(*Camera, @cameraX, @cameraY, @heading) = #False
    WallSetError("Wall visibility build: camera is not ready.")
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    WallSetError("Wall visibility build: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  If ProjectionGetConstants(*Projection, @projectionWidth, 0, 0, 0, 0, 0, 0, 0, 0) = #False
    WallSetError("Wall visibility build: cannot read projection width: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf
  If projectionWidth <> #PROJ_VIEWWIDTH
    WallSetError("Wall visibility build requires the canonical 320-column projection; got " + Str(projectionWidth) + ".")
    ProcedureReturn #False
  EndIf

  nodeCount = *Level\Nodes\Count
  subCount = *Level\Subsectors\Count
  segCount = *Level\Segs\Count
  lineCount = *Level\Linedefs\Count
  sectorCount = *Level\Sectors\Count
  If nodeCount < 0 Or subCount < 0 Or segCount < 0 Or lineCount < 0 Or sectorCount < 0
    WallSetError("Wall visibility build: record counts are negative/corrupted.")
    ProcedureReturn #False
  EndIf
  If subCount <= 0 Or segCount <= 0 Or lineCount <= 0 Or sectorCount <= 0
    WallSetError("Wall visibility build: required map record sets are empty.")
    ProcedureReturn #False
  EndIf

  If MapLevelGetBspRoot(*Level, @rootIsSubsector, @rootIndex) = #False
    WallSetError("Wall visibility build: cannot read BSP root: " + MapLevelLastError())
    ProcedureReturn #False
  EndIf
  If rootIsSubsector <> 0
    If nodeCount <> 0
      WallSetError("Wall visibility build: a subsector root is inconsistent with a level that has nodes.")
      ProcedureReturn #False
    EndIf
    If subCount <> 1
      WallSetError("Wall visibility build: zero-node root requires exactly one subsector, got " + Str(subCount) + ".")
      ProcedureReturn #False
    EndIf
    If rootIndex < 0 Or rootIndex >= subCount Or rootIndex > #MAP_NF_SUBSECTOR - 1
      WallSetError("Wall visibility build: subsector root index is invalid: " + Str(rootIndex) + ".")
      ProcedureReturn #False
    EndIf
    rootRaw = rootIndex ! #MAP_NF_SUBSECTOR
    stackCapacity = 2
  Else
    If nodeCount = 0
      WallSetError("Wall visibility build: a node root is inconsistent with a zero-node level.")
      ProcedureReturn #False
    EndIf
    If rootIndex < 0 Or rootIndex >= nodeCount Or rootIndex >= #MAP_NF_SUBSECTOR
      WallSetError("Wall visibility build: node root index is invalid or cannot be encoded as a nonleaf: " + Str(rootIndex) + ".")
      ProcedureReturn #False
    EndIf
    rootRaw = rootIndex
    stackCapacity = nodeCount * 2 + 4
  EndIf

  If ClipStateBeginFrame(@clip, projectionWidth) = #False
    WallSetError("Wall visibility build: cannot begin clip frame: " + ClipLastError())
    ProcedureReturn #False
  EndIf
  clipInitial = 1

  wideStackCapacity = stackCapacity
  stackBytes = wideStackCapacity * Int(SizeOf(WallWorkItem))
  stackMemory = AllocateMemory(stackBytes)
  If stackMemory = 0
    failureText = "Out of memory while allocating the bounded wall visibility stack."
    failure = 1
  Else
    stackAllocations = 1
  EndIf

  If failure = 0
    If stackPointer >= stackCapacity
      WallSetError("Wall visibility build: stack capacity cannot hold the root work item.")
      failure = 1
    Else
      *stack = stackMemory
      *stack\Kind = #WALLVIS_WorkVisit
      *stack\Node = #WALLVIS_NoIndex
      *stack\Child = rootRaw
      *stack\Box = #WALLVIS_NoIndex
      stackPointer + 1
      workItems + 1
    EndIf
  EndIf

  While failure = 0 And stackPointer > 0
    stackPointer - 1
    *stack = stackMemory + stackPointer * SizeOf(WallWorkItem)
    itemKind = *stack\Kind
    itemNode = *stack\Node
    itemChild = *stack\Child
    itemBox = *stack\Box
    workItems + 1
    If workItems > #WALLVIS_MaxWorkItems
      failureText = "Wall visibility work budget is exhausted: " + Str(#WALLVIS_MaxWorkItems) + " stack push/pop items."
      failure = 1
      Continue
    EndIf

    ; Visit item: a leaf or a node entry.
    If itemKind = #WALLVIS_WorkVisit
      rawChild = itemChild
      If (rawChild & #MAP_NF_SUBSECTOR) <> 0
        leafIndex = rawChild & $7FFF
        If leafIndex < 0 Or leafIndex >= subCount
          failureText = "BSP leaf references missing subsector " + Str(leafIndex) + "."
          failure = 1
          Continue
        EndIf
        If MapSubsectorsGet(@*Level\Subsectors, leafIndex, @numSegs, @firstSeg) = #False
          failureText = "Cannot read subsector " + Str(leafIndex) + ": " + MapDecodeLastError()
          failure = 1
          Continue
        EndIf
        If numSegs <= 0
          failureText = "Subsector " + Str(leafIndex) + " has no segments."
          failure = 1
          Continue
        EndIf
        If firstSeg < 0
          failureText = "Subsector " + Str(leafIndex) + " has a negative first seg index."
          failure = 1
          Continue
        EndIf
        lastSeg = firstSeg + numSegs - 1
        If lastSeg < firstSeg Or lastSeg >= segCount
          failureText = "Subsector " + Str(leafIndex) + " seg range exceeds SEGS."
          failure = 1
          Continue
        EndIf
        derivedSector = MapLevelGetSubsectorSector(*Level, leafIndex)
        If derivedSector < 0 Or derivedSector >= sectorCount
          failureText = "Subsector " + Str(leafIndex) + " sector is invalid: " + Str(derivedSector) + "."
          failure = 1
          Continue
        EndIf
        visitedSubsectors + 1

        segIndex = firstSeg
        While failure = 0 And segIndex <= lastSeg
          clipCountBefore = clip\SpanCount
          If WallAddLineCore(*Level, *Projection, *Flats, *Textures, @clip,
                             leafIndex, segIndex, cameraX, cameraY, heading,
                             @segOutcome, @segEmitted) = #False
            failureText = WallVisibilityLastError()
            failure = 1
            Continue
          EndIf
          processedSegs + 1
          clipCountAfter = clip\SpanCount
          If clipCountAfter <> clipCountBefore + segEmitted
            failureText = "Wall R_AddLine span counter reconciliation failed for seg " + Str(segIndex) + "."
            failure = 1
            Continue
          EndIf
          emittedFragments + segEmitted
          Select segOutcome
            Case #WALLLINE_EmptySkip
              emptyLineRejects + 1
            Case #WALLLINE_Backface
              backfaceRejects + 1
            Case #WALLLINE_FovLeft
              fovLeftRejects + 1
              fovRejects + 1
            Case #WALLLINE_FovRight
              fovRightRejects + 1
              fovRejects + 1
            Case #WALLLINE_ZeroWidth
              pixelWidthRejects + 1
            Case #WALLLINE_Solid
              solidCandidates + 1
            Case #WALLLINE_Pass
              passCandidates + 1
            Default
              failureText = "Wall R_AddLine returned an unknown outcome code."
              failure = 1
          EndSelect
          If failure <> 0
            Continue
          EndIf
          segIndex + 1
        Wend
        If failure = 0
          ; Leaf visit completed; remaining work continues in chronology.
        Else
          ; Outer while gate stops on the leaf/seg failure.
        EndIf
        Continue
      EndIf

      ; Node entry: point-on-node side, near child, scheduled far check, pushes.
      nodeIndex = rawChild
      If nodeIndex < 0 Or nodeIndex >= nodeCount Or nodeIndex >= #MAP_NF_SUBSECTOR
        failureText = "BSP node index is invalid: " + Str(nodeIndex) + "."
        failure = 1
        Continue
      EndIf
      If MapNodesGet(@*Level\Nodes, nodeIndex, @nodeOriginX, @nodeOriginY,
                     @nodeDX, @nodeDY, 0, 0, 0, 0, 0, 0, 0, 0,
                     @child0, @child1) = #False
        failureText = "Cannot read BSP node " + Str(nodeIndex) + ": " + MapDecodeLastError()
        failure = 1
        Continue
      EndIf
      If FixedFromIntChecked(nodeOriginX, @nodeOriginX) = #False
        failureText = "Node " + Str(nodeIndex) + " origin X conversion failed: " + FixedLastError()
        failure = 1
        Continue
      EndIf
      If FixedFromIntChecked(nodeOriginY, @nodeOriginY) = #False
        failureText = "Node " + Str(nodeIndex) + " origin Y conversion failed: " + FixedLastError()
        failure = 1
        Continue
      EndIf
      If FixedFromIntChecked(nodeDX, @nodeDX) = #False
        failureText = "Node " + Str(nodeIndex) + " direction DX conversion failed: " + FixedLastError()
        failure = 1
        Continue
      EndIf
      If FixedFromIntChecked(nodeDY, @nodeDY) = #False
        failureText = "Node " + Str(nodeIndex) + " direction DY conversion failed: " + FixedLastError()
        failure = 1
        Continue
      EndIf

      side = 0
      If GeometryPointOnNodeSideChecked(cameraX, cameraY, nodeOriginX, nodeOriginY,
                                        nodeDX, nodeDY, @side) = #False
        failureText = "Node " + Str(nodeIndex) + " camera side classification failed: " + GeometryLastError()
        failure = 1
        Continue
      EndIf
      If side <> 0 And side <> 1
        failureText = "Node " + Str(nodeIndex) + " geometry returned an invalid side."
        failure = 1
        Continue
      EndIf

      If side = 0
        nearRaw = child0
        farRaw = child1
      Else
        nearRaw = child1
        farRaw = child0
      EndIf
      If (farRaw & #MAP_NF_SUBSECTOR) <> 0
        If (farRaw & $7FFF) >= subCount
          failureText = "Node " + Str(nodeIndex) + " far leaf references missing subsector."
          failure = 1
          Continue
        EndIf
      ElseIf farRaw < 0 Or farRaw >= nodeCount Or farRaw >= #MAP_NF_SUBSECTOR
        failureText = "Node " + Str(nodeIndex) + " far child node index is invalid: " + Str(farRaw) + "."
        failure = 1
        Continue
      EndIf
      If (nearRaw & #MAP_NF_SUBSECTOR) <> 0
        If (nearRaw & $7FFF) >= subCount
          failureText = "Node " + Str(nodeIndex) + " near leaf references missing subsector."
          failure = 1
          Continue
        EndIf
      ElseIf nearRaw < 0 Or nearRaw >= nodeCount Or nearRaw >= #MAP_NF_SUBSECTOR
        failureText = "Node " + Str(nodeIndex) + " near child node index is invalid: " + Str(nearRaw) + "."
        failure = 1
        Continue
      EndIf
      visitedNodes + 1

      ; LIFO schedule: far check beneath near visit.
      If stackPointer >= stackCapacity
        failureText = "Wall visibility stack overflow on far check push for node " + Str(nodeIndex) + "."
        failure = 1
        Continue
      EndIf
      *stack = stackMemory + stackPointer * SizeOf(WallWorkItem)
      *stack\Kind = #WALLVIS_WorkFarCheck
      *stack\Node = nodeIndex
      *stack\Child = farRaw
      *stack\Box = side ! 1
      stackPointer + 1
      workItems + 1
      If workItems > #WALLVIS_MaxWorkItems
        failureText = "Wall visibility work budget exhausted on far check push."
        failure = 1
        Continue
      EndIf

      If stackPointer >= stackCapacity
        failureText = "Wall visibility stack overflow on near visit push for node " + Str(nodeIndex) + "."
        failure = 1
        Continue
      EndIf
      *stack = stackMemory + stackPointer * SizeOf(WallWorkItem)
      *stack\Kind = #WALLVIS_WorkVisit
      *stack\Node = #WALLVIS_NoIndex
      *stack\Child = nearRaw
      *stack\Box = #WALLVIS_NoIndex
      stackPointer + 1
      workItems + 1
      If workItems > #WALLVIS_MaxWorkItems
        failureText = "Wall visibility work budget exhausted on near visit push."
        failure = 1
        Continue
      EndIf
      Continue
    EndIf

    ; FarCheck item: bbox verdict against the LIVE occlusion state after the
    ; complete near subtree was processed. OCCLUDED prunes the far visit.
    If itemKind = #WALLVIS_WorkFarCheck
      If WallCheckBBoxCore(*Level, *Projection, @clip, itemNode, itemBox,
                           cameraX, cameraY, heading, @verdict) = #False
        failureText = "Far bbox check failed: " + WallVisibilityLastError()
        failure = 1
        Continue
      EndIf
      bboxTests + 1
      Select verdict
        Case #WALLBBOX_Occluded
          bboxOccluded + 1
          occlusionSkips + 1
          Continue
        Case #WALLBBOX_Visible
          bboxVisible + 1
        Case #WALLBBOX_Unknown
          bboxUnknown + 1
        Default
          failureText = "R_CheckBBox returned an unknown verdict code."
          failure = 1
          Continue
      EndSelect
      If failure <> 0
        Continue
      EndIf
      If stackPointer >= stackCapacity
        failureText = "Wall visibility stack overflow on visible far visit push."
        failure = 1
        Continue
      EndIf
      *stack = stackMemory + stackPointer * SizeOf(WallWorkItem)
      *stack\Kind = #WALLVIS_WorkVisit
      *stack\Node = #WALLVIS_NoIndex
      *stack\Child = itemChild
      *stack\Box = #WALLVIS_NoIndex
      stackPointer + 1
      workItems + 1
      If workItems > #WALLVIS_MaxWorkItems
        failureText = "Wall visibility work budget exhausted on far visit push."
        failure = 1
        Continue
      EndIf
      Continue
    EndIf

    failureText = "Wall visibility stack contains an unknown work-item kind."
    failure = 1
    Continue
  Wend

  If failure = 0
    ; Publish the ordered fragments and aggregate counters into owned result
    ; storage. The result was reset-empty at entry; publication is atomic.
    spanIndex = clip\SpanCount
    If spanIndex < 0 Or spanIndex > #WALLVIS_MaxSpans
      failureText = "Wall visibility published span count exceeds the cap."
      failure = 1
    ElseIf spanIndex > 0
      spanBytes = Int(spanIndex) * Int(SizeOf(WallSpan))
      resultMemory = AllocateMemory(spanBytes)
      If resultMemory = 0
        failureText = "Out of memory while publishing wall visibility spans."
        failure = 1
      Else
        resultAllocations = 1
      EndIf
    EndIf
  EndIf

  clipRangeGrowths = clip\RangeGrowths
  clipSpanGrowths = clip\SpanGrowths
  clipAllocations = clip\AllocationCount
  ClipStateGetStats(@clip, 0, 0, 0, @clipRangeGrowths, @clipSpanGrowths, @clipAllocations)

  If failure = 0
    If clip\SpanCount > 0
      For spanIndex = 0 To clip\SpanCount - 1
        *clipSpan = clip\Spans + spanIndex * SizeOf(ClipSpan)
        *span = resultMemory + spanIndex * SizeOf(WallSpan)
        *span\Subsector = *clipSpan\Subsector
        *span\Seg = *clipSpan\Seg
        *span\Linedef = *clipSpan\Linedef
        *span\Side = *clipSpan\Side
        *span\FrontSector = *clipSpan\FrontSector
        *span\BackSector = *clipSpan\BackSector
        *span\FirstX = *clipSpan\FirstX
        *span\LastX = *clipSpan\LastX
        *span\Kind = *clipSpan\Kind
      Next
    EndIf
    *Result\Magic = #WALLVIS_Magic
    *Result\Count = clip\SpanCount
    *Result\Capacity = clip\SpanCount
    *Result\Spans = resultMemory
    *Result\VisitedNodes = visitedNodes
    *Result\VisitedSubsectors = visitedSubsectors
    *Result\ProcessedSegs = processedSegs
    *Result\EmittedFragments = emittedFragments
    *Result\BackfaceRejects = backfaceRejects
    *Result\FovLeftRejects = fovLeftRejects
    *Result\FovRightRejects = fovRightRejects
    *Result\FovRejects = fovRejects
    *Result\PixelWidthRejects = pixelWidthRejects
    *Result\EmptyLineRejects = emptyLineRejects
    *Result\SolidCandidates = solidCandidates
    *Result\PassCandidates = passCandidates
    *Result\BboxTests = bboxTests
    *Result\BboxVisible = bboxVisible
    *Result\BboxOccluded = bboxOccluded
    *Result\BboxUnknown = bboxUnknown
    *Result\OcclusionSkips = occlusionSkips
    *Result\WorkItems = workItems
    *Result\ClipRangeGrowths = clipRangeGrowths
    *Result\ClipSpanGrowths = clipSpanGrowths
    *Result\Allocations = stackAllocations + clipAllocations + resultAllocations
  EndIf

  If clipInitial <> 0
    ClipStateReset(@clip)
  EndIf
  If stackMemory <> 0
    FreeMemory(stackMemory)
  EndIf
  If failure <> 0
    savedFailureText = failureText
    If savedFailureText = ""
      savedFailureText = gWall_LastError
    EndIf
    WallVisibilityReset(*Result)
    WallSetError(savedFailureText)
    ProcedureReturn #False
  EndIf
  gWall_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
