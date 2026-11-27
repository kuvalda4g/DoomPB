; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M4-01 visplane frame state from Linux Doom 1.10 r_plane.c/r_bsp.c:
;   R_ClearPlanes: ceilingclip=-1, floorclip=viewheight, visplane reset,
;     cachedheight zero, basexscale/baseyscale for the heading, spanstart=0;
;   R_Subsector: floorplane when floorheight<viewz; ceilingplane when
;     ceilingheight>viewz OR ceilingpic is skyflatnum;
;   R_FindPlane: key (height,picnum,lightlevel), sky normalizes
;     (height=0,lightlevel=0), new top=0xFF/minx=320/maxx=-1;
;   R_CheckPlane: intersection/union bounds; overlap with a set top[x] forces a
;     new independent visplane with the same key, otherwise one plane extends;
;   R_RenderSegLoop plane marks: ceilingclip/floorclip read before the per-column
;     clip mutations; mark rows stored only when top<=bottom.
;
; This module owns the numeric visplane records and the exact row sentinels but
; writes no pixels. It does not include the wall rasterizer or a second BSP walk.
;
; Guarded column model:
;   - each plane owns padded top/bottom arrays of 322 .l entries for logical
;     indexes -1..320; top starts 0xFF, bottom pads start 0. Top only ever gets
;     0..199 or the sentinel 0xFF; bottom only gets 0..199 or a pad 0. No C-style
;     unchecked top[x-1]/top[maxx+1] pointer access exists.
;   - sentinel semantics are the source MakeSpans contract. Bottom pads are 0
;     rather than stale/uninitialized source storage: MakeSpans never emits a row
;     from those positions because t1=0xFF makes the source `>=t1` guards false.
;     This is a documented safe deviation; drawable bands are validated 0..199.
;   - R_CheckPlane overlap reads only logical columns 0..319 through accessors.
;
; Identity:
;   - regular key is canonical fixed height, resolved FlatCatalog flat index and
;     signed map-sector lightlevel. Flat index 0 is a legitimate ordinary flat.
;   - F_SKY1 is resolved once through FlatCatalogFindName and passed as a numeric
;     SkyFlatIndex; equality with that index is the source skyflatnum identity.
;     FindPlane then normalizes the sky key exactly. No sky flat is ever loaded.
;   - floor and ceiling resolve canonical nonempty names through the catalog;
;     unused/malformed/read-failing slots are explicit errors, never invented.
;
; Budgets:
;   - at most 1,024 visplanes by default (vanilla MAXVISPLANES=128 is the source
;     reference; a larger guarded cap is acceptable), optional cap 1..1,024 for
;     bounded failure tests. New/split creation exceeding the cap fails without
;     partial mutation; Build resets the frame on failure.
;   - top+bottom board is one contiguous bounded allocation; records/tables are
;     separate bounded allocations. All count in Allocations.
;   - R_ClearPlanes cachedheight[200]/cacheddistance/cachedxstep/cachedystep and
;     spanstart[200] are frame-owned, zeroed at BeginFrame exactly.
;
; Ownership: caller-owned PlaneFrame is zero-initializable once. Begin resets and
; owns records/boards/tables; Reset frees exactly those recognized allocations,
; checks pointer/layout metadata rather than freeing unexplained memory, and
; leaves a reusable empty object. Failure in Begin/Find/Check never publishes a
; partial Ready frame; caller (Build) resets on any chronology error.
;
; WallPlaneTimeline is a caller-owned numeric chronology audit: one visit record
; per online subsector entry and one event per emitted wall clip-span, recording
; Find/Check allocation indices, merge/split counts and mark band counts in
; traversal order. It owns arrays only, reset idempotently, bounded caps.
;
; Source-visplane structs carried raw short top/bottom; this port carries .l to
; make negative C short values impossible, with explicit guards. Original
; algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PLANES_PBI, #PB_Constant) = 0

#DOOMPB_PLANES_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Map/MapLevel.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "Projection.pbi"
XIncludeFile "WallSpanDefs.pbi"
XIncludeFile "WallIdentity.pbi"
XIncludeFile "PlaneMapping.pbi"

#PLANE_Magic = $504C4631
#PLANE_DefaultMaxVisplanes = 1024
#PLANE_MaxVisplanes = 1024
#PLANE_PaddedColumns = #PLANE_VIEWWIDTH + 2
#PLANE_MaxBoardBytes = #PLANE_MaxVisplanes * #PLANE_PaddedColumns * 2 * 4
#PLANE_MaxRecordBytes = 65536
#PLANE_SkyFlatName = "F_SKY1"

#PLANE_Table_YSlopeOffset = 0
#PLANE_Table_YSlopeBytes = #PLANE_YSLOPE_Count * 4
#PLANE_Table_DistScaleOffset = #PLANE_Table_YSlopeBytes
#PLANE_Table_DistScaleBytes = #PLANE_DISTSCALE_Count * 4
#PLANE_Table_XToViewAngleOffset = #PLANE_Table_DistScaleOffset + #PLANE_Table_DistScaleBytes
#PLANE_Table_XToViewAngleBytes = #PLANE_XTOVIEWANGLE_Count * 8
#PLANE_Table_CachedHeightOffset = #PLANE_Table_XToViewAngleOffset + #PLANE_Table_XToViewAngleBytes
#PLANE_Table_CachedHeightBytes = #PLANE_YSLOPE_Count * 4
#PLANE_Table_CachedDistanceOffset = #PLANE_Table_CachedHeightOffset + #PLANE_Table_CachedHeightBytes
#PLANE_Table_CachedDistanceBytes = #PLANE_YSLOPE_Count * 4
#PLANE_Table_CachedXStepOffset = #PLANE_Table_CachedDistanceOffset + #PLANE_Table_CachedDistanceBytes
#PLANE_Table_CachedXStepBytes = #PLANE_YSLOPE_Count * 4
#PLANE_Table_CachedYStepOffset = #PLANE_Table_CachedXStepOffset + #PLANE_Table_CachedXStepBytes
#PLANE_Table_CachedYStepBytes = #PLANE_YSLOPE_Count * 4
#PLANE_Table_SpanStartOffset = #PLANE_Table_CachedYStepOffset + #PLANE_Table_CachedYStepBytes
#PLANE_Table_SpanStartBytes = #PLANE_YSLOPE_Count * 4
#PLANE_Table_TotalBytes = #PLANE_Table_SpanStartOffset + #PLANE_Table_SpanStartBytes
#PLANE_MaxTableBytes = 10000

#PLANE_Timeline_Magic = $504C5431
#PLANE_Timeline_DefaultVisits = 65536
#PLANE_Timeline_DefaultEvents = 65536
#PLANE_Timeline_MaxVisits = 65536
#PLANE_Timeline_MaxEvents = 65536

Structure PlaneRecord
  Height.l
  FlatPic.l
  LightLevel.l
  Sky.l
  MinX.l
  MaxX.l
  *Top.Long
  *Bottom.Long
EndStructure

Structure PlaneFrame
  Magic.l
  Ready.l
  Width.l
  Height.l
  SkyFlatIndex.l
  ViewX.l
  ViewY.l
  ViewAngle.q
  ViewZ.l
  CenterXFixed.l
  CenterYFixed.l
  ProjectionFixed.l
  BaseXScale.l
  BaseYScale.l
  LastPlane.l
  Capacity.l
  RecordBytes.q
  BoardBytes.q
  *Records.PlaneRecord
  *Boards.Long
  *Tables.Byte
  *YSlope.Long
  *DistScale.Long
  *XToViewAngle.Quad
  *CachedHeight.Long
  *CachedDistance.Long
  *CachedXStep.Long
  *CachedYStep.Long
  *SpanStart.Long
  FindCalls.l
  FindReuse.l
  FindCreate.l
  CheckCalls.l
  CheckMerges.l
  CheckSplits.l
  MarkCeilingCalls.l
  MarkFloorCalls.l
  MarkCeilingBands.l
  MarkFloorBands.l
  SkyVisplanes.l
  Allocations.l
EndStructure

Structure PlaneVisitRecord
  Subsector.l
  Sector.l
  FloorEligible.l
  CeilingEligible.l
  FloorPlane.l
  CeilingPlane.l
  FloorSky.l
  CeilingSky.l
  SegCount.l
  EmittedSpans.l
EndStructure

Structure PlaneSpanEvent
  Subsector.l
  Seg.l
  ClipSpanFirst.l
  ClipSpanLast.l
  ClipSpanKind.l
  CeilingCheck.l
  FloorCheck.l
  CeilingPlaneBefore.l
  CeilingPlaneAfter.l
  FloorPlaneBefore.l
  FloorPlaneAfter.l
  CeilingCheckMerge.l
  CeilingCheckSplit.l
  FloorCheckMerge.l
  FloorCheckSplit.l
  CeilingBands.l
  FloorBands.l
  ProcessedColumns.l
  EmittedRows.l
EndStructure

Structure WallPlaneTimeline
  Magic.l
  Ready.l
  VisitCount.l
  VisitCapacity.l
  EventCount.l
  EventCapacity.l
  *Visits.PlaneVisitRecord
  *Events.PlaneSpanEvent
  ZeroSpanSubsectorVisits.l
  SkyPlaneFindVisits.l
  RegularPlaneFindVisits.l
  MarkedCeilingColumns.l
  MarkedFloorColumns.l
  StoredCeilingBands.l
  StoredFloorBands.l
  Allocations.l
EndStructure

Global gPlanes_LastError.s = ""

Procedure PlanesSetError(Message.s)
  gPlanes_LastError = Message
EndProcedure

Procedure.s PlanesLastError()
  ProcedureReturn gPlanes_LastError
EndProcedure

; ---------------------------------------------------------------------------
; PlaneFrame ownership and begin
; ---------------------------------------------------------------------------

Procedure.i PlaneFrameIsValid(*Frame.PlaneFrame)
  ProcedureReturn Bool(*Frame <> 0 And *Frame\Magic = #PLANE_Magic And
                        *Frame\Ready <> 0)
EndProcedure

Procedure.i PlaneFrameReset(*Frame.PlaneFrame)
  If *Frame = 0
    PlanesSetError("Plane frame pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Frame\Magic = #PLANE_Magic
    If *Frame\Records <> 0 Or *Frame\Boards <> 0 Or *Frame\Tables <> 0
      If *Frame\Records = 0 Or *Frame\Boards = 0
        PlanesSetError("Plane frame owned records/boards are inconsistent.")
        ProcedureReturn #False
      EndIf
      If *Frame\Capacity <= 0 Or *Frame\Capacity > #PLANE_MaxVisplanes Or
         *Frame\RecordBytes <> Int(*Frame\Capacity) * Int(SizeOf(PlaneRecord)) Or
         *Frame\BoardBytes <> 2 * Int(*Frame\Capacity) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long))
        PlanesSetError("Plane frame owned metadata is inconsistent with its capacity.")
        ProcedureReturn #False
      EndIf
      If *Frame\Tables <> 0 And
         (*Frame\YSlope <> *Frame\Tables + #PLANE_Table_YSlopeOffset Or
          *Frame\DistScale <> *Frame\Tables + #PLANE_Table_DistScaleOffset Or
          *Frame\XToViewAngle <> *Frame\Tables + #PLANE_Table_XToViewAngleOffset Or
          *Frame\CachedHeight <> *Frame\Tables + #PLANE_Table_CachedHeightOffset Or
          *Frame\CachedDistance <> *Frame\Tables + #PLANE_Table_CachedDistanceOffset Or
          *Frame\CachedXStep <> *Frame\Tables + #PLANE_Table_CachedXStepOffset Or
          *Frame\CachedYStep <> *Frame\Tables + #PLANE_Table_CachedYStepOffset Or
          *Frame\SpanStart <> *Frame\Tables + #PLANE_Table_SpanStartOffset)
        PlanesSetError("Plane frame table pointers are inconsistent with their owned block.")
        ProcedureReturn #False
      EndIf
      FreeMemory(*Frame\Records)
      FreeMemory(*Frame\Boards)
      If *Frame\Tables <> 0
        FreeMemory(*Frame\Tables)
      EndIf
    ElseIf *Frame\YSlope <> 0 Or *Frame\DistScale <> 0 Or *Frame\XToViewAngle <> 0 Or
           *Frame\CachedHeight <> 0 Or *Frame\CachedDistance <> 0 Or
           *Frame\CachedXStep <> 0 Or *Frame\CachedYStep <> 0 Or *Frame\SpanStart <> 0
      PlanesSetError("Plane frame has unexplained table pointers without owned records.")
      ProcedureReturn #False
    EndIf
  ElseIf *Frame\Magic <> 0
    PlanesSetError("Plane frame has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Frame\Records <> 0 Or *Frame\Boards <> 0 Or *Frame\Tables <> 0 Or
         *Frame\YSlope <> 0 Or *Frame\DistScale <> 0 Or *Frame\XToViewAngle <> 0 Or
         *Frame\CachedHeight <> 0 Or *Frame\CachedDistance <> 0 Or
         *Frame\CachedXStep <> 0 Or *Frame\CachedYStep <> 0 Or *Frame\SpanStart <> 0
    PlanesSetError("Plane frame has owned pointers without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Frame, Int(SizeOf(PlaneFrame)), 0)
  *Frame\Magic = #PLANE_Magic
  *Frame\Ready = 0
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Checks the one-time F_SKY1 flat catalog binding used as skyflatnum identity.
Procedure.i PlaneResolveSkyFlat(*Flats.FlatCatalog, *SkyFlatIndex.Long)
  Protected index.i

  PlanesSetError("")
  If *SkyFlatIndex = 0
    PlanesSetError("PlaneResolveSkyFlat: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Flats = 0 Or *Flats\Magic <> #FLAT_CatalogMagic
    PlanesSetError("Plane sky identity: flat catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  index = FlatCatalogFindName(*Flats, #PLANE_SkyFlatName)
  If index < 0
    PlanesSetError("Plane sky identity: catalog has no F_SKY1 flat (skyflatnum cannot be resolved).")
    ProcedureReturn #False
  EndIf
  If index >= #FLAT_MaxCount
    PlanesSetError("Plane sky identity: resolved F_SKY1 index exceeds the flat domain.")
    ProcedureReturn #False
  EndIf
  *SkyFlatIndex\l = index
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; R_ClearPlanes + exact canonical projection preparation. The optional sky
; index is the resolved F_SKY1 catalog flat; -1 means no sky identity is
; available for this frame. Optional maximum visplanes 1..1024 allows bounded
; creation-failure tests without silently enlarging unlimited storage.
Procedure.i PlaneFrameBegin(*Frame.PlaneFrame, *Projection.Projection,
                            ViewX.l, ViewY.l, ViewAngleRaw.q, ViewZ.l,
                            SkyFlatIndex.l = -1, MaxVisplanes.l = #PLANE_MaxVisplanes)
  Protected recordBytes.q
  Protected boardBytes.q
  Protected tableBytes.q
  Protected recordsMemory.i = 0
  Protected boardsMemory.i = 0
  Protected tablesMemory.i = 0
  Protected planeIndex.i
  Protected columnOffset.i
  Protected topColumn.i
  Protected row.l
  Protected screenX.l
  Protected rawAngle.q = 0
  Protected cosAdj.l = 0
  Protected distScale.l = 0
  Protected baseX.l = 0
  Protected baseY.l = 0
  Protected centerXFixed.l = 0
  Protected centerYFixed.l = 0
  Protected projectionFixed.l = 0
  Protected viewWidth.l = 0
  Protected viewHeight.l = 0
  Protected failureText.s = ""

  PlanesSetError("")
  If *Frame = 0
    PlanesSetError("PlaneFrameBegin: frame pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Frame\Magic <> 0 And *Frame\Magic <> #PLANE_Magic
    PlanesSetError("PlaneFrameBegin: frame has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameReset(*Frame) = #False
    ProcedureReturn #False
  EndIf
  If *Projection = 0 Or ProjectionIsValid(*Projection) = #False
    PlanesSetError("Plane frame begin: projection is not initialized.")
    ProcedureReturn #False
  EndIf
  ; Order must match ProjectionGetConstants' eight numeric/address outputs:
  ; Width, ViewHeight, CenterX, CenterY, CenterXFixed, CenterYFixed,
  ; ProjectionFixed, FocalLength, FieldOfView.
  If ProjectionGetConstants(*Projection, @viewWidth, @viewHeight, 0, 0,
                            @centerXFixed, @centerYFixed,
                            @projectionFixed, 0, 0) = #False
    PlanesSetError("Plane frame begin: cannot read projection constants: " + ProjectionLastError())
    ProcedureReturn #False
  EndIf
  If viewWidth <> #PLANE_VIEWWIDTH Or viewHeight <> #PLANE_VIEWHEIGHT Or
     centerXFixed <> #PROJ_CENTERXFIXED Or centerYFixed <> #PROJ_CENTERYFIXED Or
     projectionFixed <> #PROJ_PROJECTION
    PlanesSetError("Plane frame begin requires the canonical 320x200 full-detail projection.")
    ProcedureReturn #False
  EndIf
  If BamRawInUnsignedDomain(ViewAngleRaw) = 0
    PlanesSetError("Plane frame begin: view heading is outside the raw unsigned BAM domain.")
    ProcedureReturn #False
  EndIf
  If SkyFlatIndex <> -1 And (SkyFlatIndex < 0 Or SkyFlatIndex >= #FLAT_MaxCount)
    PlanesSetError("Plane frame begin: sky flat index is invalid: " + Str(SkyFlatIndex) + ".")
    ProcedureReturn #False
  EndIf
  If MaxVisplanes < 1 Or MaxVisplanes > #PLANE_MaxVisplanes
    PlanesSetError("Plane frame begin: visplane cap is outside 1.." + Str(#PLANE_MaxVisplanes) + ": " + Str(MaxVisplanes) + ".")
    ProcedureReturn #False
  EndIf

  recordBytes = Int(MaxVisplanes) * Int(SizeOf(PlaneRecord))
  boardBytes = 2 * Int(MaxVisplanes) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long))
  tableBytes = #PLANE_Table_TotalBytes
  If recordBytes <= 0 Or recordBytes > #PLANE_MaxRecordBytes Or
     boardBytes <= 0 Or boardBytes > #PLANE_MaxBoardBytes Or
     tableBytes <= 0 Or tableBytes > #PLANE_MaxTableBytes Or
     recordBytes <> Int(MaxVisplanes) * Int(SizeOf(PlaneRecord)) Or
     boardBytes <> 2 * Int(MaxVisplanes) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long))
    PlanesSetError("Plane frame byte budgets/layout arithmetic are invalid.")
    ProcedureReturn #False
  EndIf

  recordsMemory = AllocateMemory(recordBytes)
  boardsMemory = AllocateMemory(boardBytes)
  tablesMemory = AllocateMemory(tableBytes)
  If recordsMemory = 0 Or boardsMemory = 0 Or tablesMemory = 0
    If recordsMemory <> 0
      FreeMemory(recordsMemory)
    EndIf
    If boardsMemory <> 0
      FreeMemory(boardsMemory)
    EndIf
    If tablesMemory <> 0
      FreeMemory(tablesMemory)
    EndIf
    PlanesSetError("Out of memory while allocating the bounded plane frame arrays.")
    ProcedureReturn #False
  EndIf
  FillMemory(recordsMemory, Int(recordBytes), 0)
  FillMemory(boardsMemory, Int(boardBytes), 0)
  FillMemory(tablesMemory, Int(tableBytes), 0)

  *Frame\Magic = #PLANE_Magic
  *Frame\Ready = 0
  *Frame\Width = #PLANE_VIEWWIDTH
  *Frame\Height = #PLANE_VIEWHEIGHT
  *Frame\SkyFlatIndex = SkyFlatIndex
  *Frame\ViewX = ViewX
  *Frame\ViewY = ViewY
  *Frame\ViewAngle = BamWrap32(ViewAngleRaw)
  *Frame\ViewZ = ViewZ
  *Frame\CenterXFixed = centerXFixed
  *Frame\CenterYFixed = centerYFixed
  *Frame\ProjectionFixed = projectionFixed
  *Frame\LastPlane = 0
  *Frame\Capacity = MaxVisplanes
  *Frame\RecordBytes = recordBytes
  *Frame\BoardBytes = boardBytes
  *Frame\Records = recordsMemory
  *Frame\Boards = boardsMemory
  *Frame\Tables = tablesMemory
  *Frame\YSlope = tablesMemory + #PLANE_Table_YSlopeOffset
  *Frame\DistScale = tablesMemory + #PLANE_Table_DistScaleOffset
  *Frame\XToViewAngle = tablesMemory + #PLANE_Table_XToViewAngleOffset
  *Frame\CachedHeight = tablesMemory + #PLANE_Table_CachedHeightOffset
  *Frame\CachedDistance = tablesMemory + #PLANE_Table_CachedDistanceOffset
  *Frame\CachedXStep = tablesMemory + #PLANE_Table_CachedXStepOffset
  *Frame\CachedYStep = tablesMemory + #PLANE_Table_CachedYStepOffset
  *Frame\SpanStart = tablesMemory + #PLANE_Table_SpanStartOffset
  *Frame\Allocations = 3

  ; Every plane row band starts as source 0xFF top; padded bottom pads are 0.
  For planeIndex = 0 To MaxVisplanes - 1
    columnOffset = Int(planeIndex) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long))
    For topColumn = 0 To #PLANE_PaddedColumns - 1
      PokeL(*Frame\Boards + columnOffset + topColumn * SizeOf(Long), 255)
    Next
  Next

  If PlaneYSlopeTable(centerXFixed, viewWidth, *Frame\YSlope) = #False
    failureText = "Plane frame yslope table failed: " + PlaneMappingLastError()
    PlaneFrameReset(*Frame)
    PlanesSetError(failureText)
    ProcedureReturn #False
  EndIf
  For screenX = 0 To #PLANE_XTOVIEWANGLE_Count - 1
    If ProjectionGetXToViewAngle(*Projection, screenX, @rawAngle) = #False
      failureText = "Plane frame xtoviewangle copy failed at x=" + Str(screenX) + ": " + ProjectionLastError()
      PlaneFrameReset(*Frame)
      PlanesSetError(failureText)
      ProcedureReturn #False
    EndIf
    PokeQ(*Frame\XToViewAngle + screenX * SizeOf(Quad), rawAngle)
  Next
  If PlaneDistScaleTableFromRaw(*Frame\XToViewAngle, #PLANE_DISTSCALE_Count,
                               *Frame\DistScale) = #False
    failureText = "Plane frame full distscale table failed: " + PlaneMappingLastError()
    PlaneFrameReset(*Frame)
    PlanesSetError(failureText)
    ProcedureReturn #False
  EndIf

  If PlaneBaseScaleFromHeading(*Frame\ViewAngle, centerXFixed,
                               @baseX, @baseY) = #False
    failureText = "Plane frame base scales failed: " + PlaneMappingLastError()
    PlaneFrameReset(*Frame)
    PlanesSetError(failureText)
    ProcedureReturn #False
  EndIf
  *Frame\BaseXScale = baseX
  *Frame\BaseYScale = baseY

  For row = 0 To #PLANE_YSLOPE_Count - 1
    PokeL(*Frame\CachedHeight + row * SizeOf(Long), 0)
    PokeL(*Frame\CachedDistance + row * SizeOf(Long), 0)
    PokeL(*Frame\CachedXStep + row * SizeOf(Long), 0)
    PokeL(*Frame\CachedYStep + row * SizeOf(Long), 0)
    PokeL(*Frame\SpanStart + row * SizeOf(Long), 0)
  Next

  *Frame\Ready = 1
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Visplane accessors and exact row-sentinel storage
; ---------------------------------------------------------------------------

Procedure.i PlaneCount(*Frame.PlaneFrame, *LastPlane.Long)
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If *LastPlane <> 0
    PokeL(*LastPlane, *Frame\LastPlane)
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneRecordGet(*Frame.PlaneFrame, PlaneIndex.l,
                           *Height.Long, *FlatPic.Long, *LightLevel.Long,
                           *Sky.Long, *MinX.Long, *MaxX.Long)
  Protected *record.PlaneRecord

  PlanesSetError("")
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane record access: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or PlaneIndex >= *Frame\LastPlane Or PlaneIndex >= *Frame\Capacity Or
     *Frame\Records = 0
    PlanesSetError("Plane record access index is outside the created range: " + Str(PlaneIndex) + ".")
    ProcedureReturn #False
  EndIf
  *record = *Frame\Records + Int(PlaneIndex) * SizeOf(PlaneRecord)
  If *Height <> 0
    PokeL(*Height, *record\Height)
  EndIf
  If *FlatPic <> 0
    PokeL(*FlatPic, *record\FlatPic)
  EndIf
  If *LightLevel <> 0
    PokeL(*LightLevel, *record\LightLevel)
  EndIf
  If *Sky <> 0
    PokeL(*Sky, *record\Sky)
  EndIf
  If *MinX <> 0
    PokeL(*MinX, *record\MinX)
  EndIf
  If *MaxX <> 0
    PokeL(*MaxX, *record\MaxX)
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Padded logical column accessor: x may be -1..320 (sentinel pads); the owned
; array index is x+1. Values are bounded 0..255 (top) / 0..199 (bottom).
Procedure.i PlaneColumnValue(*Frame.PlaneFrame, PlaneIndex.l, X.l, IsTop.i, *Value.Long)
  Protected columnIndex.l
  Protected *record.PlaneRecord
  Protected *board.Long
  Protected value.l

  PlanesSetError("")
  If *Value = 0
    PlanesSetError("PlaneColumnValue: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane column access: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or PlaneIndex >= *Frame\LastPlane Or PlaneIndex >= *Frame\Capacity Or
     *Frame\Records = 0 Or *Frame\Boards = 0
    PlanesSetError("Plane column access index is outside the created range: " + Str(PlaneIndex) + ".")
    ProcedureReturn #False
  EndIf
  If X < -1 Or X > #PLANE_ViewWidth
    PlanesSetError("Plane column access x is outside the padded logical domain -1..320: " + Str(X) + ".")
    ProcedureReturn #False
  EndIf
  *record = *Frame\Records + Int(PlaneIndex) * SizeOf(PlaneRecord)
  If IsTop
    *board = *record\Top
  Else
    *board = *record\Bottom
  EndIf
  If *board = 0
    PlanesSetError("Plane record owned row pointer is absent.")
    ProcedureReturn #False
  EndIf
  columnIndex = X + 1
  value = PeekL(*board + columnIndex * SizeOf(Long))
  If IsTop And (value < 0 Or value > 255)
    PlanesSetError("Plane top row value is outside 0..255: " + Str(value) + ".")
    ProcedureReturn #False
  EndIf
  If IsTop = #False And (value < 0 Or value > #PLANE_ViewHeight - 1)
    PlanesSetError("Plane bottom row value is outside 0..199: " + Str(value) + ".")
    ProcedureReturn #False
  EndIf
  *Value\l = value
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Internal/directed row-band store. For tests it allows explicitly setting the
; sentinel/padded model; production marks only store drawable 0..199 bands.
Procedure.i PlaneColumnSetBand(*Frame.PlaneFrame, PlaneIndex.l, X.l,
                               TopValue.l, BottomValue.l)
  Protected columnIndex.l
  Protected *record.PlaneRecord
  Protected *topBoard.Long
  Protected *bottomBoard.Long

  PlanesSetError("")
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane band store: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or PlaneIndex >= *Frame\LastPlane Or PlaneIndex >= *Frame\Capacity Or
     *Frame\Records = 0 Or *Frame\Boards = 0
    PlanesSetError("Plane band store index is outside the created range: " + Str(PlaneIndex) + ".")
    ProcedureReturn #False
  EndIf
  If X < 0 Or X > #PLANE_ViewWidth - 1
    PlanesSetError("Plane band store x is outside 0..319: " + Str(X) + ".")
    ProcedureReturn #False
  EndIf
  If TopValue < 0 Or TopValue > 255
    PlanesSetError("Plane band top value is outside 0..255: " + Str(TopValue) + ".")
    ProcedureReturn #False
  EndIf
  If BottomValue < 0 Or BottomValue > #PLANE_ViewHeight - 1
    PlanesSetError("Plane band bottom value is outside 0..199: " + Str(BottomValue) + ".")
    ProcedureReturn #False
  EndIf
  If TopValue < 255 And TopValue > BottomValue
    PlanesSetError("Plane band top exceeds bottom: " + Str(TopValue) + " > " + Str(BottomValue) + ".")
    ProcedureReturn #False
  EndIf
  *record = *Frame\Records + Int(PlaneIndex) * SizeOf(PlaneRecord)
  *topBoard = *record\Top
  *bottomBoard = *record\Bottom
  If *topBoard = 0 Or *bottomBoard = 0
    PlanesSetError("Plane record owned row pointers are absent.")
    ProcedureReturn #False
  EndIf
  columnIndex = X + 1
  PokeL(*topBoard + columnIndex * SizeOf(Long), TopValue)
  PokeL(*bottomBoard + columnIndex * SizeOf(Long), BottomValue)
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Checks whether any logical column has a set (non-sentinel) top row, i.e. the
; plane actually carries a drawable band candidate. Used to load only flats
; actually used and to count empty visplanes.
Procedure.i PlaneRecordHasBands(*Frame.PlaneFrame, PlaneIndex.l, *Used.Long)
  Protected *record.PlaneRecord
  Protected columnX.l
  Protected topValue.l

  PlanesSetError("")
  If *Used = 0
    PlanesSetError("PlaneRecordHasBands: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane band use scan: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or PlaneIndex >= *Frame\LastPlane Or PlaneIndex >= *Frame\Capacity Or
     *Frame\Records = 0
    PlanesSetError("Plane band use scan index is outside the created range.")
    ProcedureReturn #False
  EndIf
  *record = *Frame\Records + Int(PlaneIndex) * SizeOf(PlaneRecord)
  If *record\Top = 0
    PlanesSetError("Plane band use scan owned top pointer is absent.")
    ProcedureReturn #False
  EndIf
  *Used\l = 0
  For columnX = 0 To #PLANE_ViewWidth - 1
    topValue = PeekL(*record\Top + (columnX + 1) * SizeOf(Long))
    If topValue <> 255
      If topValue < 0 Or topValue > #PLANE_ViewHeight - 1
        PlanesSetError("Plane band use scan found an invalid top row value: " + Str(topValue) + ".")
        ProcedureReturn #False
      EndIf
      *Used\l = 1
      Break
    EndIf
  Next
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Source R_DrawPlanes sentinel writes `pl->top[maxx+1]=0xff; pl->top[minx-1]=0xff`.
; The padded logical setter accepts x -1..320 and writes only the top sentinel.
Procedure.i PlaneTopSentinelSet(*Frame.PlaneFrame, PlaneIndex.l, X.l)
  Protected columnIndex.l
  Protected *record.PlaneRecord
  Protected *board.Long

  PlanesSetError("")
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane top sentinel set: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or PlaneIndex >= *Frame\LastPlane Or PlaneIndex >= *Frame\Capacity Or
     *Frame\Records = 0
    PlanesSetError("Plane top sentinel set index is outside the created range: " + Str(PlaneIndex) + ".")
    ProcedureReturn #False
  EndIf
  If X < -1 Or X > #PLANE_ViewWidth
    PlanesSetError("Plane top sentinel x is outside the padded logical domain -1..320: " + Str(X) + ".")
    ProcedureReturn #False
  EndIf
  *record = *Frame\Records + Int(PlaneIndex) * SizeOf(PlaneRecord)
  *board = *record\Top
  If *board = 0
    PlanesSetError("Plane top sentinel set owned row pointer is absent.")
    ProcedureReturn #False
  EndIf
  columnIndex = X + 1
  PokeL(*board + columnIndex * SizeOf(Long), 255)
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_FindPlane
; ---------------------------------------------------------------------------

; Exact canonical key and duplicate scan order. Sky records use the normalized
; (height=0, sky FlatPic, lightlevel=0) identity. A legitimate flat index 0 is an
; ordinary key; no name-string heuristic or palette-zero visibility test exists.
Procedure.i PlaneFindPlane(*Frame.PlaneFrame, Height.l, FlatPic.l,
                           LightLevel.l, *PlaneIndex.Long)
  Protected normalizedHeight.l = 0
  Protected normalizedLight.l = 0
  Protected isSky.l = 0
  Protected planeIndex.l
  Protected *record.PlaneRecord
  Protected *topBoard.Long
  Protected *bottomBoard.Long
  Protected columnOffset.i
  Protected topColumn.i

  PlanesSetError("")
  If *PlaneIndex = 0
    PlanesSetError("PlaneFindPlane: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("PlaneFindPlane: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If FlatPic < 0 Or FlatPic >= #FLAT_MaxCount
    PlanesSetError("PlaneFindPlane: flat catalog index is outside 0.." + Str(#FLAT_MaxCount - 1) +
                   ": " + Str(FlatPic) + ".")
    ProcedureReturn #False
  EndIf
  If LightLevel < -32768 Or LightLevel > 32767
    PlanesSetError("PlaneFindPlane: sector lightlevel is outside the signed 16-bit domain: " + Str(LightLevel) + ".")
    ProcedureReturn #False
  EndIf
  If *Frame\Records = 0 Or *Frame\Boards = 0
    PlanesSetError("PlaneFindPlane: frame owned arrays are absent.")
    ProcedureReturn #False
  EndIf

  normalizedHeight = Height
  normalizedLight = LightLevel
  If *Frame\SkyFlatIndex <> -1 And FlatPic = *Frame\SkyFlatIndex
    normalizedHeight = 0
    normalizedLight = 0
    isSky = 1
  EndIf

  For planeIndex = 0 To *Frame\LastPlane - 1
    *record = *Frame\Records + Int(planeIndex) * SizeOf(PlaneRecord)
    If normalizedHeight = *record\Height And FlatPic = *record\FlatPic And
       normalizedLight = *record\LightLevel
      *Frame\FindCalls + 1
      *Frame\FindReuse + 1
      *PlaneIndex\l = planeIndex
      gPlanes_LastError = ""
      ProcedureReturn #True
    EndIf
  Next

  *Frame\FindCalls + 1
  If *Frame\LastPlane >= *Frame\Capacity
    PlanesSetError("R_FindPlane: no more visplanes under the bounded cap " + Str(*Frame\Capacity) + ".")
    ProcedureReturn #False
  EndIf
  *Frame\FindCreate + 1
  If isSky
    *Frame\SkyVisplanes + 1
  EndIf

  planeIndex = *Frame\LastPlane
  *record = *Frame\Records + Int(planeIndex) * SizeOf(PlaneRecord)
  *record\Height = normalizedHeight
  *record\FlatPic = FlatPic
  *record\LightLevel = normalizedLight
  *record\Sky = isSky
  *record\MinX = #PLANE_ViewWidth
  *record\MaxX = -1
  columnOffset = Int(planeIndex) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long))
  *topBoard = *Frame\Boards + columnOffset
  *bottomBoard = *Frame\Boards + Int(*Frame\Capacity) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long)) +
                columnOffset
  *record\Top = *topBoard
  *record\Bottom = *bottomBoard
  For topColumn = 0 To #PLANE_PaddedColumns - 1
    PokeL(*topBoard + topColumn * SizeOf(Long), 255)
    PokeL(*bottomBoard + topColumn * SizeOf(Long), 0)
  Next
  *Frame\LastPlane = planeIndex + 1
  *PlaneIndex\l = planeIndex
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_CheckPlane
; ---------------------------------------------------------------------------

; Exact intersection/union bounds and overlap test. The returned plane is either
; the same extended plane (Merged=1) or a newly created independent plane with
; the same key (Merged=0). Overlap tests only set rows (top != 0xFF). Creation
; order is LastPlane chronology; counters remain distinct.
Procedure.i PlaneCheckPlane(*Frame.PlaneFrame, OldPlaneIndex.l,
                            Start.l, Stop.l, *NewPlaneIndex.Long, *Merged.Long)
  Protected *old.PlaneRecord
  Protected intrl.l
  Protected intrh.l
  Protected unionl.l
  Protected unionh.l
  Protected columnX.l
  Protected topValue.l
  Protected found.l = 0
  Protected newIndex.l
  Protected *newRecord.PlaneRecord
  Protected *topBoard.Long
  Protected *bottomBoard.Long
  Protected columnOffset.i
  Protected topColumn.i

  PlanesSetError("")
  If *NewPlaneIndex = 0 Or *Merged = 0
    PlanesSetError("PlaneCheckPlane: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("PlaneCheckPlane: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If OldPlaneIndex < 0 Or OldPlaneIndex >= *Frame\LastPlane Or
     OldPlaneIndex >= *Frame\Capacity Or *Frame\Records = 0 Or *Frame\Boards = 0
    PlanesSetError("PlaneCheckPlane: plane index is outside the created range: " + Str(OldPlaneIndex) + ".")
    ProcedureReturn #False
  EndIf
  If Start < 0 Or Stop < 0 Or Start > #PLANE_ViewWidth - 1 Or
     Stop > #PLANE_ViewWidth - 1 Or Start > Stop
    PlanesSetError("PlaneCheckPlane: columns are invalid: " + Str(Start) + ".." + Str(Stop) + ".")
    ProcedureReturn #False
  EndIf

  *Frame\CheckCalls + 1
  *old = *Frame\Records + Int(OldPlaneIndex) * SizeOf(PlaneRecord)
  If *old\Top = 0 Or *old\Bottom = 0
    PlanesSetError("PlaneCheckPlane: old plane owned row pointers are absent.")
    ProcedureReturn #False
  EndIf

  If Start < *old\MinX
    intrl = *old\MinX
    unionl = Start
  Else
    unionl = *old\MinX
    intrl = Start
  EndIf
  If Stop > *old\MaxX
    intrh = *old\MaxX
    unionh = Stop
  Else
    unionh = *old\MaxX
    intrh = Stop
  EndIf

  found = 0
  If intrl <= intrh
    If intrl < 0 Or intrl > #PLANE_ViewWidth - 1 Or
       intrh < 0 Or intrh > #PLANE_ViewWidth - 1
      PlanesSetError("PlaneCheckPlane: intersection bounds are outside drawable columns: " +
                     Str(intrl) + ".." + Str(intrh) + ".")
      ProcedureReturn #False
    EndIf
    For columnX = intrl To intrh
      topValue = PeekL(*old\Top + (columnX + 1) * SizeOf(Long))
      If topValue <> 255
        If topValue < 0 Or topValue > #PLANE_ViewHeight - 1
          PlanesSetError("PlaneCheckPlane: overlap test found an invalid top row value: " + Str(topValue) + ".")
          ProcedureReturn #False
        EndIf
        found = 1
        Break
      EndIf
    Next
  EndIf

  If found = 0
    *old\MinX = unionl
    *old\MaxX = unionh
    *Frame\CheckMerges + 1
    *Merged\l = 1
    *NewPlaneIndex\l = OldPlaneIndex
    gPlanes_LastError = ""
    ProcedureReturn #True
  EndIf

  If *Frame\LastPlane >= *Frame\Capacity
    PlanesSetError("R_CheckPlane: no more visplanes for a required split under cap " +
                   Str(*Frame\Capacity) + ".")
    ProcedureReturn #False
  EndIf
  *Frame\CheckSplits + 1
  newIndex = *Frame\LastPlane
  *newRecord = *Frame\Records + Int(newIndex) * SizeOf(PlaneRecord)
  *newRecord\Height = *old\Height
  *newRecord\FlatPic = *old\FlatPic
  *newRecord\LightLevel = *old\LightLevel
  *newRecord\Sky = *old\Sky
  If *newRecord\Sky <> 0
    *Frame\SkyVisplanes + 1
  EndIf
  *newRecord\MinX = Start
  *newRecord\MaxX = Stop
  columnOffset = Int(newIndex) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long))
  *topBoard = *Frame\Boards + columnOffset
  *bottomBoard = *Frame\Boards + Int(*Frame\Capacity) * Int(#PLANE_PaddedColumns) * Int(SizeOf(Long)) +
                columnOffset
  *newRecord\Top = *topBoard
  *newRecord\Bottom = *bottomBoard
  For topColumn = 0 To #PLANE_PaddedColumns - 1
    PokeL(*topBoard + topColumn * SizeOf(Long), 255)
    PokeL(*bottomBoard + topColumn * SizeOf(Long), 0)
  Next
  *Frame\LastPlane = newIndex + 1
  *Merged\l = 0
  *NewPlaneIndex\l = newIndex
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_RenderSegLoop mark-only row storage (source order preserved by caller)
; ---------------------------------------------------------------------------

; Exact ceiling mark sub-block using already-read clip values and computed yl:
;   top=ceilingclip+1; bottom=yl-1; bottom>=floorclip -> floorclip-1;
;   store only top<=bottom; row values remain 0..199.
Procedure.i PlaneMarkCeilingBand(*Frame.PlaneFrame, PlaneIndex.l, X.l,
                                 CeilingClip.l, FloorClip.l, YL.l,
                                 *Stored.Long)
  Protected top.l
  Protected bottom.l
  Protected *record.PlaneRecord

  PlanesSetError("")
  If *Stored = 0
    PlanesSetError("PlaneMarkCeilingBand: stored output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane ceiling mark: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or PlaneIndex >= *Frame\LastPlane Or PlaneIndex >= *Frame\Capacity Or
     *Frame\Records = 0
    PlanesSetError("Plane ceiling mark index is outside the created range: " + Str(PlaneIndex) + ".")
    ProcedureReturn #False
  EndIf
  If X < 0 Or X > #PLANE_ViewWidth - 1
    PlanesSetError("Plane ceiling mark column is outside 0..319: " + Str(X) + ".")
    ProcedureReturn #False
  EndIf
  If CeilingClip < -1 Or CeilingClip > #PLANE_ViewHeight Or
     FloorClip < -1 Or FloorClip > #PLANE_ViewHeight
    PlanesSetError("Plane ceiling mark clip value is outside -1..200.")
    ProcedureReturn #False
  EndIf

  *Frame\MarkCeilingCalls + 1
  *Stored\l = 0
  top = CeilingClip + 1
  bottom = YL - 1
  If bottom >= FloorClip
    bottom = FloorClip - 1
  EndIf
  If top <= bottom
    If top < 0 Or top > #PLANE_ViewHeight - 1 Or
       bottom < 0 Or bottom > #PLANE_ViewHeight - 1
      PlanesSetError("Plane ceiling mark produced a non-drawable band: top " + Str(top) +
                     ", bottom " + Str(bottom) + ".")
      ProcedureReturn #False
    EndIf
    *record = *Frame\Records + Int(PlaneIndex) * SizeOf(PlaneRecord)
    If *record\Top = 0 Or *record\Bottom = 0
      PlanesSetError("Plane ceiling mark owned row pointers are absent.")
      ProcedureReturn #False
    EndIf
    PokeL(*record\Top + (X + 1) * SizeOf(Long), top)
    PokeL(*record\Bottom + (X + 1) * SizeOf(Long), bottom)
    *Frame\MarkCeilingBands + 1
    *Stored\l = 1
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Exact floor mark sub-block:
;   top=yh+1; bottom=floorclip-1; top<=ceilingclip -> ceilingclip+1;
;   store only top<=bottom; 0..199.
Procedure.i PlaneMarkFloorBand(*Frame.PlaneFrame, PlaneIndex.l, X.l,
                               CeilingClip.l, FloorClip.l, YH.l,
                               *Stored.Long)
  Protected top.l
  Protected bottom.l
  Protected *record.PlaneRecord

  PlanesSetError("")
  If *Stored = 0
    PlanesSetError("PlaneMarkFloorBand: stored output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane floor mark: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlaneIndex < 0 Or PlaneIndex >= *Frame\LastPlane Or PlaneIndex >= *Frame\Capacity Or
     *Frame\Records = 0
    PlanesSetError("Plane floor mark index is outside the created range: " + Str(PlaneIndex) + ".")
    ProcedureReturn #False
  EndIf
  If X < 0 Or X > #PLANE_ViewWidth - 1
    PlanesSetError("Plane floor mark column is outside 0..319: " + Str(X) + ".")
    ProcedureReturn #False
  EndIf
  If CeilingClip < -1 Or CeilingClip > #PLANE_ViewHeight Or
     FloorClip < -1 Or FloorClip > #PLANE_ViewHeight
    PlanesSetError("Plane floor mark clip value is outside -1..200.")
    ProcedureReturn #False
  EndIf

  *Frame\MarkFloorCalls + 1
  *Stored\l = 0
  top = YH + 1
  bottom = FloorClip - 1
  If top <= CeilingClip
    top = CeilingClip + 1
  EndIf
  If top <= bottom
    If top < 0 Or top > #PLANE_ViewHeight - 1 Or
       bottom < 0 Or bottom > #PLANE_ViewHeight - 1
      PlanesSetError("Plane floor mark produced a non-drawable band: top " + Str(top) +
                     ", bottom " + Str(bottom) + ".")
      ProcedureReturn #False
    EndIf
    *record = *Frame\Records + Int(PlaneIndex) * SizeOf(PlaneRecord)
    If *record\Top = 0 Or *record\Bottom = 0
      PlanesSetError("Plane floor mark owned row pointers are absent.")
      ProcedureReturn #False
    EndIf
    PokeL(*record\Top + (X + 1) * SizeOf(Long), top)
    PokeL(*record\Bottom + (X + 1) * SizeOf(Long), bottom)
    *Frame\MarkFloorBands + 1
    *Stored\l = 1
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_Subsector plane selection
; ---------------------------------------------------------------------------

; Source eligibility and FindPlane calls in R_Subsector order:
;   floor: floorheight < viewz -> FindPlane (even if its flat is the sky index,
;     FindPlane normalizes it, exactly as the original generic lookup does);
;   ceiling: ceilingheight > viewz OR ceilingpic == skyflatnum -> FindPlane;
;   wrong-side ordinary surfaces produce -1 (no plane).
; Submitted fixed heights are checked map-unit conversions. The front sector
; is the canonical derived subsector sector; plane pic is a resolved catalog
; index, never an invented fallback.
Procedure.i PlaneSubsectorPrepare(*Frame.PlaneFrame, *Level.MapLevel,
                                  *Flats.FlatCatalog, SectorIndex.l,
                                  SkyFlatIndex.l, ViewZ.l,
                                  *FloorPlane.Long, *CeilingPlane.Long)
  Protected floorMap.l
  Protected ceilingMap.l
  Protected lightLevel.l
  Protected floorFixed.l = 0
  Protected ceilingFixed.l = 0
  Protected floorStatus.i
  Protected ceilingStatus.i
  Protected floorName.WallSlotNameOut
  Protected ceilingName.WallSlotNameOut
  Protected floorIndex.i
  Protected ceilingIndex.i
  Protected floorEligible.l = 0
  Protected ceilingEligible.l = 0
  Protected floorPlane.l = -1
  Protected ceilingPlane.l = -1
  Protected outputIndex.l = 0

  PlanesSetError("")
  If *FloorPlane = 0 Or *CeilingPlane = 0
    PlanesSetError("PlaneSubsectorPrepare: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane subsector entry: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    PlanesSetError("Plane subsector entry: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If SectorIndex < 0 Or SectorIndex >= *Level\Sectors\Count
    PlanesSetError("Plane subsector entry: sector index is invalid: " + Str(SectorIndex) + ".")
    ProcedureReturn #False
  EndIf
  If *Flats = 0 Or *Flats\Magic <> #FLAT_CatalogMagic
    PlanesSetError("Plane subsector entry: flat catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If SkyFlatIndex <> -1 And (SkyFlatIndex < 0 Or SkyFlatIndex >= #FLAT_MaxCount)
    PlanesSetError("Plane subsector entry: sky flat index is invalid.")
    ProcedureReturn #False
  EndIf

  If MapSectorsGet(@*Level\Sectors, SectorIndex, @floorMap, @ceilingMap,
                   @lightLevel, 0, 0) = #False
    PlanesSetError("Plane subsector entry cannot read sector " + Str(SectorIndex) +
                   ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(floorMap, @floorFixed) = #False
    PlanesSetError("Plane subsector floor conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf
  If FixedFromIntChecked(ceilingMap, @ceilingFixed) = #False
    PlanesSetError("Plane subsector ceiling conversion failed: " + FixedLastError())
    ProcedureReturn #False
  EndIf

  floorStatus = WallFlatSlotStatus(*Level, SectorIndex, 0, @floorName)
  If floorStatus = 3
    PlanesSetError("Plane subsector entry: floor flat slot read failed.")
    ProcedureReturn #False
  EndIf
  If floorStatus <> 0
    PlanesSetError("Plane subsector entry: sector " + Str(SectorIndex) +
                   " floor flat slot is noncanonical/unused.")
    ProcedureReturn #False
  EndIf
  floorIndex = FlatCatalogFindName(*Flats, floorName\Value)
  If floorIndex < 0
    PlanesSetError("Plane subsector entry: floor flat not found in catalog: " + floorName\Value)
    ProcedureReturn #False
  EndIf

  ceilingStatus = WallFlatSlotStatus(*Level, SectorIndex, 1, @ceilingName)
  If ceilingStatus = 3
    PlanesSetError("Plane subsector entry: ceiling flat slot read failed.")
    ProcedureReturn #False
  EndIf
  If ceilingStatus <> 0
    PlanesSetError("Plane subsector entry: sector " + Str(SectorIndex) +
                   " ceiling flat slot is noncanonical/unused.")
    ProcedureReturn #False
  EndIf
  ceilingIndex = FlatCatalogFindName(*Flats, ceilingName\Value)
  If ceilingIndex < 0
    PlanesSetError("Plane subsector entry: ceiling flat not found in catalog: " + ceilingName\Value)
    ProcedureReturn #False
  EndIf

  If floorFixed < ViewZ
    floorEligible = 1
    If PlaneFindPlane(*Frame, floorFixed, floorIndex, lightLevel, @outputIndex) = #False
      PlanesSetError("Plane subsector floor R_FindPlane failed: " + PlanesLastError())
      ProcedureReturn #False
    EndIf
    floorPlane = outputIndex
  EndIf
  If ceilingFixed > ViewZ Or (SkyFlatIndex <> -1 And ceilingIndex = SkyFlatIndex)
    ceilingEligible = 1
    If PlaneFindPlane(*Frame, ceilingFixed, ceilingIndex, lightLevel, @outputIndex) = #False
      PlanesSetError("Plane subsector ceiling R_FindPlane failed: " + PlanesLastError())
      ProcedureReturn #False
    EndIf
    ceilingPlane = outputIndex
  EndIf

  *FloorPlane\l = floorPlane
  *CeilingPlane\l = ceilingPlane
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; PlaneFrame counter accessors
; ---------------------------------------------------------------------------

Procedure.i PlaneFrameGetStats(*Frame.PlaneFrame, *Visplanes.Long,
                               *FindCalls.Long, *FindReuse.Long, *FindCreate.Long,
                               *CheckCalls.Long, *CheckMerges.Long, *CheckSplits.Long,
                               *MarkCeilingCalls.Long, *MarkFloorCalls.Long,
                               *MarkCeilingBands.Long, *MarkFloorBands.Long,
                               *SkyVisplanes.Long, *Allocations.Long)
  If PlaneFrameIsValid(*Frame) = #False
    PlanesSetError("Plane frame statistics: frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Visplanes <> 0
    PokeL(*Visplanes, *Frame\LastPlane)
  EndIf
  If *FindCalls <> 0
    PokeL(*FindCalls, *Frame\FindCalls)
  EndIf
  If *FindReuse <> 0
    PokeL(*FindReuse, *Frame\FindReuse)
  EndIf
  If *FindCreate <> 0
    PokeL(*FindCreate, *Frame\FindCreate)
  EndIf
  If *CheckCalls <> 0
    PokeL(*CheckCalls, *Frame\CheckCalls)
  EndIf
  If *CheckMerges <> 0
    PokeL(*CheckMerges, *Frame\CheckMerges)
  EndIf
  If *CheckSplits <> 0
    PokeL(*CheckSplits, *Frame\CheckSplits)
  EndIf
  If *MarkCeilingCalls <> 0
    PokeL(*MarkCeilingCalls, *Frame\MarkCeilingCalls)
  EndIf
  If *MarkFloorCalls <> 0
    PokeL(*MarkFloorCalls, *Frame\MarkFloorCalls)
  EndIf
  If *MarkCeilingBands <> 0
    PokeL(*MarkCeilingBands, *Frame\MarkCeilingBands)
  EndIf
  If *MarkFloorBands <> 0
    PokeL(*MarkFloorBands, *Frame\MarkFloorBands)
  EndIf
  If *SkyVisplanes <> 0
    PokeL(*SkyVisplanes, *Frame\SkyVisplanes)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Frame\Allocations)
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; WallPlaneTimeline chronology audit (owned numeric arrays)
; ---------------------------------------------------------------------------

Procedure.i PlaneTimelineIsValid(*Timeline.WallPlaneTimeline)
  ProcedureReturn Bool(*Timeline <> 0 And *Timeline\Magic = #PLANE_Timeline_Magic And
                        *Timeline\Ready <> 0)
EndProcedure

Procedure.i PlaneTimelineReset(*Timeline.WallPlaneTimeline)
  If *Timeline = 0
    PlanesSetError("Plane timeline pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Timeline\Magic = #PLANE_Timeline_Magic
    If *Timeline\Visits <> 0 Or *Timeline\Events <> 0
      If *Timeline\Visits = 0 Or *Timeline\Events = 0
        PlanesSetError("Plane timeline owned visit/event arrays are inconsistent.")
        ProcedureReturn #False
      EndIf
      If *Timeline\VisitCapacity <= 0 Or *Timeline\VisitCapacity > #PLANE_Timeline_MaxVisits Or
         *Timeline\EventCapacity <= 0 Or *Timeline\EventCapacity > #PLANE_Timeline_MaxEvents
        PlanesSetError("Plane timeline capacity metadata is inconsistent.")
        ProcedureReturn #False
      EndIf
      FreeMemory(*Timeline\Visits)
      FreeMemory(*Timeline\Events)
    EndIf
  ElseIf *Timeline\Magic <> 0
    PlanesSetError("Plane timeline has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Timeline\Visits <> 0 Or *Timeline\Events <> 0
    PlanesSetError("Plane timeline has owned pointers without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Timeline, Int(SizeOf(WallPlaneTimeline)), 0)
  *Timeline\Magic = #PLANE_Timeline_Magic
  *Timeline\Ready = 0
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneTimelineBegin(*Timeline.WallPlaneTimeline,
                               MaxVisits.l = #PLANE_Timeline_DefaultVisits,
                               MaxEvents.l = #PLANE_Timeline_DefaultEvents)
  Protected visitBytes.q
  Protected eventBytes.q
  Protected visitMemory.i = 0
  Protected eventMemory.i = 0

  PlanesSetError("")
  If *Timeline = 0
    PlanesSetError("PlaneTimelineBegin: timeline pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Timeline\Magic <> 0 And *Timeline\Magic <> #PLANE_Timeline_Magic
    PlanesSetError("PlaneTimelineBegin: timeline has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If PlaneTimelineReset(*Timeline) = #False
    ProcedureReturn #False
  EndIf
  If MaxVisits < 1 Or MaxVisits > #PLANE_Timeline_MaxVisits
    PlanesSetError("Plane timeline visit cap is outside 1.." + Str(#PLANE_Timeline_MaxVisits) + ": " +
                   Str(MaxVisits) + ".")
    ProcedureReturn #False
  EndIf
  If MaxEvents < 1 Or MaxEvents > #PLANE_Timeline_MaxEvents
    PlanesSetError("Plane timeline event cap is outside 1.." + Str(#PLANE_Timeline_MaxEvents) + ": " +
                   Str(MaxEvents) + ".")
    ProcedureReturn #False
  EndIf

  visitBytes = Int(MaxVisits) * Int(SizeOf(PlaneVisitRecord))
  eventBytes = Int(MaxEvents) * Int(SizeOf(PlaneSpanEvent))
  If visitBytes <= 0 Or eventBytes <= 0 Or
     visitBytes <> Int(MaxVisits) * Int(SizeOf(PlaneVisitRecord)) Or
     eventBytes <> Int(MaxEvents) * Int(SizeOf(PlaneSpanEvent))
    PlanesSetError("Plane timeline array byte arithmetic is invalid.")
    ProcedureReturn #False
  EndIf
  visitMemory = AllocateMemory(visitBytes)
  eventMemory = AllocateMemory(eventBytes)
  If visitMemory = 0 Or eventMemory = 0
    If visitMemory <> 0
      FreeMemory(visitMemory)
    EndIf
    If eventMemory <> 0
      FreeMemory(eventMemory)
    EndIf
    PlanesSetError("Out of memory while allocating the bounded plane timeline arrays.")
    ProcedureReturn #False
  EndIf
  FillMemory(visitMemory, Int(visitBytes), 0)
  FillMemory(eventMemory, Int(eventBytes), 0)

  *Timeline\Magic = #PLANE_Timeline_Magic
  *Timeline\Ready = 1
  *Timeline\VisitCapacity = MaxVisits
  *Timeline\EventCapacity = MaxEvents
  *Timeline\Visits = visitMemory
  *Timeline\Events = eventMemory
  *Timeline\Allocations = 2
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Adds one subsector entry record in traversal order; capacity failure is an
; explicit chronology error without publishing a partial record.
Procedure.i PlaneTimelineAddVisit(*Timeline.WallPlaneTimeline,
                                  Subsector.l, Sector.l, FloorEligible.l,
                                  CeilingEligible.l, FloorPlane.l, CeilingPlane.l,
                                  FloorSky.l, CeilingSky.l, SegCount.l,
                                  EmittedSpans.l)
  Protected *visit.PlaneVisitRecord

  PlanesSetError("")
  If PlaneTimelineIsValid(*Timeline) = #False
    PlanesSetError("Plane timeline add visit: timeline is not initialized.")
    ProcedureReturn #False
  EndIf
  If Subsector < 0 Or Sector < 0 Or FloorPlane < -1 Or CeilingPlane < -1 Or
     SegCount < 0 Or EmittedSpans < 0
    PlanesSetError("Plane timeline visit record fields are invalid.")
    ProcedureReturn #False
  EndIf
  If *Timeline\VisitCount >= *Timeline\VisitCapacity Or *Timeline\Visits = 0
    PlanesSetError("Plane timeline visit budget is exhausted under cap " + Str(*Timeline\VisitCapacity) + ".")
    ProcedureReturn #False
  EndIf
  *visit = *Timeline\Visits + Int(*Timeline\VisitCount) * SizeOf(PlaneVisitRecord)
  *visit\Subsector = Subsector
  *visit\Sector = Sector
  *visit\FloorEligible = Bool(FloorEligible)
  *visit\CeilingEligible = Bool(CeilingEligible)
  *visit\FloorPlane = FloorPlane
  *visit\CeilingPlane = CeilingPlane
  *visit\FloorSky = Bool(FloorSky)
  *visit\CeilingSky = Bool(CeilingSky)
  *visit\SegCount = SegCount
  *visit\EmittedSpans = EmittedSpans
  *Timeline\VisitCount + 1
  If EmittedSpans = 0
    *Timeline\ZeroSpanSubsectorVisits + 1
  EndIf
  If FloorSky <> 0 Or CeilingSky <> 0
    *Timeline\SkyPlaneFindVisits + 1
  Else
    *Timeline\RegularPlaneFindVisits + 1
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Adds one emitted clip-span event in the online w.r.t. order. Check booleans
; mean the source mark decision was true; band counters are stored row bands.
Procedure.i PlaneTimelineAddEvent(*Timeline.WallPlaneTimeline,
                                  Subsector.l, Seg.l, FirstX.l, LastX.l, Kind.l,
                                  CeilingCheck.l, FloorCheck.l,
                                  CeilingBefore.l, CeilingAfter.l,
                                  FloorBefore.l, FloorAfter.l,
                                  CeilingMerge.l, CeilingSplit.l,
                                  FloorMerge.l, FloorSplit.l,
                                  CeilingBands.l, FloorBands.l,
                                  ProcessedColumns.l, EmittedRows.l)
  Protected *event.PlaneSpanEvent

  PlanesSetError("")
  If PlaneTimelineIsValid(*Timeline) = #False
    PlanesSetError("Plane timeline add event: timeline is not initialized.")
    ProcedureReturn #False
  EndIf
  If Subsector < 0 Or Seg < 0 Or FirstX < 0 Or LastX < 0 Or
     FirstX > #PLANE_ViewWidth - 1 Or LastX > #PLANE_ViewWidth - 1 Or FirstX > LastX Or
     Kind <> #WALL_KIND_SOLID And Kind <> #WALL_KIND_PASS
    PlanesSetError("Plane timeline event span fields are invalid.")
    ProcedureReturn #False
  EndIf
  If *Timeline\EventCount >= *Timeline\EventCapacity Or *Timeline\Events = 0
    PlanesSetError("Plane timeline event budget is exhausted under cap " + Str(*Timeline\EventCapacity) + ".")
    ProcedureReturn #False
  EndIf
  *event = *Timeline\Events + Int(*Timeline\EventCount) * SizeOf(PlaneSpanEvent)
  *event\Subsector = Subsector
  *event\Seg = Seg
  *event\ClipSpanFirst = FirstX
  *event\ClipSpanLast = LastX
  *event\ClipSpanKind = Kind
  *event\CeilingCheck = Bool(CeilingCheck)
  *event\FloorCheck = Bool(FloorCheck)
  *event\CeilingPlaneBefore = CeilingBefore
  *event\CeilingPlaneAfter = CeilingAfter
  *event\FloorPlaneBefore = FloorBefore
  *event\FloorPlaneAfter = FloorAfter
  *event\CeilingCheckMerge = Bool(CeilingMerge)
  *event\CeilingCheckSplit = Bool(CeilingSplit)
  *event\FloorCheckMerge = Bool(FloorMerge)
  *event\FloorCheckSplit = Bool(FloorSplit)
  *event\CeilingBands = CeilingBands
  *event\FloorBands = FloorBands
  *event\ProcessedColumns = ProcessedColumns
  *event\EmittedRows = EmittedRows
  *Timeline\EventCount + 1
  If CeilingCheck <> 0
    *Timeline\MarkedCeilingColumns + ProcessedColumns
  EndIf
  If FloorCheck <> 0
    *Timeline\MarkedFloorColumns + ProcessedColumns
  EndIf
  *Timeline\StoredCeilingBands + CeilingBands
  *Timeline\StoredFloorBands + FloorBands
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

; Read-only timeline counters/accessors. Null outputs are allowed.
Procedure.i PlaneTimelineGetStats(*Timeline.WallPlaneTimeline,
                                  *VisitCount.Long, *EventCount.Long,
                                  *ZeroSpanVisits.Long, *SkyFindVisits.Long,
                                  *RegularFindVisits.Long, *MarkedCeilingColumns.Long,
                                  *MarkedFloorColumns.Long, *StoredCeilingBands.Long,
                                  *StoredFloorBands.Long, *Allocations.Long)
  If PlaneTimelineIsValid(*Timeline) = #False
    PlanesSetError("Plane timeline statistics: timeline is not initialized.")
    ProcedureReturn #False
  EndIf
  If *VisitCount <> 0
    PokeL(*VisitCount, *Timeline\VisitCount)
  EndIf
  If *EventCount <> 0
    PokeL(*EventCount, *Timeline\EventCount)
  EndIf
  If *ZeroSpanVisits <> 0
    PokeL(*ZeroSpanVisits, *Timeline\ZeroSpanSubsectorVisits)
  EndIf
  If *SkyFindVisits <> 0
    PokeL(*SkyFindVisits, *Timeline\SkyPlaneFindVisits)
  EndIf
  If *RegularFindVisits <> 0
    PokeL(*RegularFindVisits, *Timeline\RegularPlaneFindVisits)
  EndIf
  If *MarkedCeilingColumns <> 0
    PokeL(*MarkedCeilingColumns, *Timeline\MarkedCeilingColumns)
  EndIf
  If *MarkedFloorColumns <> 0
    PokeL(*MarkedFloorColumns, *Timeline\MarkedFloorColumns)
  EndIf
  If *StoredCeilingBands <> 0
    PokeL(*StoredCeilingBands, *Timeline\StoredCeilingBands)
  EndIf
  If *StoredFloorBands <> 0
    PokeL(*StoredFloorBands, *Timeline\StoredFloorBands)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Timeline\Allocations)
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneTimelineGetVisit(*Timeline.WallPlaneTimeline, VisitIndex.l,
                                  *Subsector.Long, *Sector.Long,
                                  *FloorEligible.Long, *CeilingEligible.Long,
                                  *FloorPlane.Long, *CeilingPlane.Long,
                                  *FloorSky.Long, *CeilingSky.Long,
                                  *SegCount.Long, *EmittedSpans.Long)
  Protected *visit.PlaneVisitRecord

  PlanesSetError("")
  If PlaneTimelineIsValid(*Timeline) = #False
    PlanesSetError("Plane timeline visit access: timeline is not initialized.")
    ProcedureReturn #False
  EndIf
  If VisitIndex < 0 Or VisitIndex >= *Timeline\VisitCount Or *Timeline\Visits = 0
    PlanesSetError("Plane timeline visit index is outside the recorded range.")
    ProcedureReturn #False
  EndIf
  *visit = *Timeline\Visits + Int(VisitIndex) * SizeOf(PlaneVisitRecord)
  If *Subsector <> 0
    PokeL(*Subsector, *visit\Subsector)
  EndIf
  If *Sector <> 0
    PokeL(*Sector, *visit\Sector)
  EndIf
  If *FloorEligible <> 0
    PokeL(*FloorEligible, *visit\FloorEligible)
  EndIf
  If *CeilingEligible <> 0
    PokeL(*CeilingEligible, *visit\CeilingEligible)
  EndIf
  If *FloorPlane <> 0
    PokeL(*FloorPlane, *visit\FloorPlane)
  EndIf
  If *CeilingPlane <> 0
    PokeL(*CeilingPlane, *visit\CeilingPlane)
  EndIf
  If *FloorSky <> 0
    PokeL(*FloorSky, *visit\FloorSky)
  EndIf
  If *CeilingSky <> 0
    PokeL(*CeilingSky, *visit\CeilingSky)
  EndIf
  If *SegCount <> 0
    PokeL(*SegCount, *visit\SegCount)
  EndIf
  If *EmittedSpans <> 0
    PokeL(*EmittedSpans, *visit\EmittedSpans)
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PlaneTimelineGetEvent(*Timeline.WallPlaneTimeline, EventIndex.l,
                                  *Subsector.Long, *Seg.Long,
                                  *FirstX.Long, *LastX.Long, *Kind.Long,
                                  *CeilingCheck.Long, *FloorCheck.Long,
                                  *CeilingBefore.Long, *CeilingAfter.Long,
                                  *FloorBefore.Long, *FloorAfter.Long,
                                  *CeilingMerge.Long, *CeilingSplit.Long,
                                  *FloorMerge.Long, *FloorSplit.Long,
                                  *CeilingBands.Long, *FloorBands.Long,
                                  *ProcessedColumns.Long, *EmittedRows.Long)
  Protected *event.PlaneSpanEvent

  PlanesSetError("")
  If PlaneTimelineIsValid(*Timeline) = #False
    PlanesSetError("Plane timeline event access: timeline is not initialized.")
    ProcedureReturn #False
  EndIf
  If EventIndex < 0 Or EventIndex >= *Timeline\EventCount Or *Timeline\Events = 0
    PlanesSetError("Plane timeline event index is outside the recorded range.")
    ProcedureReturn #False
  EndIf
  *event = *Timeline\Events + Int(EventIndex) * SizeOf(PlaneSpanEvent)
  If *Subsector <> 0
    PokeL(*Subsector, *event\Subsector)
  EndIf
  If *Seg <> 0
    PokeL(*Seg, *event\Seg)
  EndIf
  If *FirstX <> 0
    PokeL(*FirstX, *event\ClipSpanFirst)
  EndIf
  If *LastX <> 0
    PokeL(*LastX, *event\ClipSpanLast)
  EndIf
  If *Kind <> 0
    PokeL(*Kind, *event\ClipSpanKind)
  EndIf
  If *CeilingCheck <> 0
    PokeL(*CeilingCheck, *event\CeilingCheck)
  EndIf
  If *FloorCheck <> 0
    PokeL(*FloorCheck, *event\FloorCheck)
  EndIf
  If *CeilingBefore <> 0
    PokeL(*CeilingBefore, *event\CeilingPlaneBefore)
  EndIf
  If *CeilingAfter <> 0
    PokeL(*CeilingAfter, *event\CeilingPlaneAfter)
  EndIf
  If *FloorBefore <> 0
    PokeL(*FloorBefore, *event\FloorPlaneBefore)
  EndIf
  If *FloorAfter <> 0
    PokeL(*FloorAfter, *event\FloorPlaneAfter)
  EndIf
  If *CeilingMerge <> 0
    PokeL(*CeilingMerge, *event\CeilingCheckMerge)
  EndIf
  If *CeilingSplit <> 0
    PokeL(*CeilingSplit, *event\CeilingCheckSplit)
  EndIf
  If *FloorMerge <> 0
    PokeL(*FloorMerge, *event\FloorCheckMerge)
  EndIf
  If *FloorSplit <> 0
    PokeL(*FloorSplit, *event\FloorCheckSplit)
  EndIf
  If *CeilingBands <> 0
    PokeL(*CeilingBands, *event\CeilingBands)
  EndIf
  If *FloorBands <> 0
    PokeL(*FloorBands, *event\FloorBands)
  EndIf
  If *ProcessedColumns <> 0
    PokeL(*ProcessedColumns, *event\ProcessedColumns)
  EndIf
  If *EmittedRows <> 0
    PokeL(*EmittedRows, *event\EmittedRows)
  EndIf
  gPlanes_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
