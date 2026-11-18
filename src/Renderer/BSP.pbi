; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Deterministic, iterative BSP traversal from a fixed camera (M3-03).
;
; Original Linux Doom 1.10 r_bsp.c/r_main.c behaviour reproduced here:
;   R_Subsector -> emit one subsector entry followed by its segments in the
;                  original increasing firstseg..firstseg+numsegs-1 order;
;   R_RenderBSPNode -> if bspnum & NF_SUBSECTOR visit the leaf (root -1 maps to
;                  subsector zero in the original; M2 publishes that safe root
;                  explicitly), otherwise R_PointOnSide(viewx,viewy,node) picks
;                  the near child, visit near first, then visit far.
;
; M3-03 intentionally does not call R_CheckBBox, R_AddLine, R_ClipSolidWallSegment
; or any screen-space predicate: viewangletox, clipangle and the evolving
; solidsegs ranges do not exist yet, so culling would be incomplete. The far child
; is always traversed here. This trace is a chronological BSP walk, not a
; visible-surface list; M3-04 later adds projection/clipping, and a sufficiently
; faithful R_CheckBBox is a later assigned step.
;
; C recursion is replaced by an explicit LIFO work stack of raw 16-bit child
; values. Push order is far first, then near, so the near subtree completes first
; exactly like the recursive original. The stack is bounded by node count + 2
; (a validated acyclic graph cannot have a longer current path); every push/pop
; and index is checked. No recursive call, borrowed level/WAD pointer or per-node
; heap allocation is used.
;
; Root conventions come from validated M2 MapLevel:
;   - node maps: root is nodeCount-1 (BspRootIsSubsector=0);
;   - zero nodes with one subsector: root is subsector 0 (BspRootIsSubsector=1).
; Never assume node 0. On-disk child encoding is unsigned 16-bit: the high bit
; NF_SUBSECTOR ($8000) marks a leaf and the low 15 bits are its index; otherwise
; the value is a node index (< $8000 in canonical vanilla encoding).
;
; Event ownership and ordering contract:
;   - one chronological stream of SUBSECTOR and SEG records;
;   - SUBSECTOR (Kind=0): Subsector, Sector=derived sector; Seg/Linedef/Side/
;     FrontSector/BackSector are documented -1 sentinels;
;   - SEG (Kind=1): Subsector=owning leaf, Seg=absolute segment index,
;     Sector=owning subsector's derived sector, Linedef, Side (0/1),
;     FrontSector and BackSector (BackSector=-1 for a one-sided segment);
;   - no global sorting, deduplication or REJECT/BLOCKMAP visibility test.
;
; The trace owns a deep copy of every published numeric event. It never aliases
; MapLevel records, stack frames, WAD bytes or resource catalog memory, so it
; remains inspectable after MapLevelReset/WADClose. Reset is idempotent and makes
; a reusable empty trace (Magic valid, Count 0, no allocation). Every build is
; transactional: it resets the target trace first and any failure leaves the
; trace empty with an actionable diagnostic; camera and level are never mutated.
;
; Resource limits:
;   - event cap: 1,000,000 published events;
;   - work cap: 4,000,000 stack push/pop items;
;   - initial event storage is bounded to subCount+segCount (at least 2) instead
;     of an enormous array for tiny/empty levels; growth doubles up to the cap
;     only when capacity is exhausted, with checked 64-bit byte arithmetic and
;     clean OOM cleanup;
;   - shared-child DAG references (M2 rejects cycles but may accept sharing) are
;     reproduced deterministically under the hard visit budgets, matching the
;     original recursion's repeated occurrences; the budget prevents explosive
;     expansion. No repeated leaf/node is silently skipped;
;   - counters report visited nodes/subsectors, emitted segs/events, work items
;     and occlusion skips. OcclusionSkips is always zero in M3-03: no culling;
;   - no hot-path log output, screen interaction or external service call.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_BSP_PBI, #PB_Constant) = 0

#DOOMPB_BSP_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Core/Angle.pbi"
XIncludeFile "../Map/MapLevel.pbi"
XIncludeFile "Geometry.pbi"
XIncludeFile "Camera.pbi"

#BSPTRACE_Magic = $42545331

; Project safety budgets, not vanilla format limits.
#BSP_MaxEvents = 1000000
#BSP_MaxWorkItems = 4000000

#BSP_EventSubsector = 0
#BSP_EventSeg = 1

#BSP_NoIndex = -1

Structure BspEvent
  Kind.l
  Subsector.l
  Seg.l
  Sector.l
  Linedef.l
  Side.l
  FrontSector.l
  BackSector.l
EndStructure

Structure BspTrace
  Magic.l
  Count.l
  Capacity.l
  *Events.BspEvent
  VisitedNodes.l
  VisitedSubsectors.l
  EmittedSegs.l
  EmittedEvents.l
  OcclusionSkips.l
  WorkItems.l
EndStructure

Global gBsp_LastError.s = ""

Procedure BspSetError(Message.s)
  gBsp_LastError = Message
EndProcedure

Procedure.s BspTraceLastError()
  ProcedureReturn gBsp_LastError
EndProcedure

; Empty reusable trace. A freshly zero-initialized caller structure with no
; allocation is accepted; a nonzero unrecognized Magic or an unexplained pointer
; is rejected instead of freeing arbitrary memory. Idempotent.
Procedure.i BspTraceReset(*Trace.BspTrace)
  If *Trace = 0
    BspSetError("BSP trace pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Trace\Magic = #BSPTRACE_Magic
    If *Trace\Events <> 0
      FreeMemory(*Trace\Events)
    EndIf
  ElseIf *Trace\Magic <> 0
    BspSetError("BSP trace object has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Trace\Events <> 0
    BspSetError("BSP trace has an unexplained event pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  *Trace\Magic = #BSPTRACE_Magic
  *Trace\Count = 0
  *Trace\Capacity = 0
  *Trace\Events = 0
  *Trace\VisitedNodes = 0
  *Trace\VisitedSubsectors = 0
  *Trace\EmittedSegs = 0
  *Trace\EmittedEvents = 0
  *Trace\OcclusionSkips = 0
  *Trace\WorkItems = 0
  gBsp_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i BspTraceIsValid(*Trace.BspTrace)
  ProcedureReturn Bool(*Trace <> 0 And *Trace\Magic = #BSPTRACE_Magic)
EndProcedure

; Reading a valid count never erases a build failure diagnostic; the success of
; a build or reset is what clears stale error state. An empty valid trace reports
; 0, while an unrecognized object reports -1 with a diagnostic.
Procedure.i BspTraceCount(*Trace.BspTrace)
  If BspTraceIsValid(*Trace) = #False
    BspSetError("BSP trace is not initialized.")
    ProcedureReturn -1
  EndIf
  ProcedureReturn *Trace\Count
EndProcedure

; Validated copy accessor for one published numeric event. Every output pointer
; may be null. Negative and Count-boundary indices fail without partial writes.
; SUBSECTOR irrelevant fields are already stored as -1; SEG back sector uses the
; documented -1 one-sided sentinel.
Procedure.i BspTraceGet(*Trace.BspTrace, EventIndex.i,
                        *Kind.Long, *Subsector.Long, *Seg.Long, *Sector.Long,
                        *Linedef.Long, *Side.Long, *FrontSector.Long, *BackSector.Long)
  Protected *item.BspEvent

  If BspTraceIsValid(*Trace) = #False
    BspSetError("BSP trace is not initialized.")
    ProcedureReturn #False
  EndIf
  If EventIndex < 0 Or EventIndex >= *Trace\Count
    BspSetError("BSP trace event index out of range: " + Str(EventIndex) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Trace\Events + EventIndex * SizeOf(BspEvent)
  If *Kind <> 0
    PokeL(*Kind, *item\Kind)
  EndIf
  If *Subsector <> 0
    PokeL(*Subsector, *item\Subsector)
  EndIf
  If *Seg <> 0
    PokeL(*Seg, *item\Seg)
  EndIf
  If *Sector <> 0
    PokeL(*Sector, *item\Sector)
  EndIf
  If *Linedef <> 0
    PokeL(*Linedef, *item\Linedef)
  EndIf
  If *Side <> 0
    PokeL(*Side, *item\Side)
  EndIf
  If *FrontSector <> 0
    PokeL(*FrontSector, *item\FrontSector)
  EndIf
  If *BackSector <> 0
    PokeL(*BackSector, *item\BackSector)
  EndIf
  gBsp_LastError = ""
  ProcedureReturn #True
EndProcedure

; Internal bounded append. Grows the event array only when the current capacity
; is exhausted; the cap and all byte arithmetic are checked. On failure the
; caller performs transactional trace reset, which releases any owned events.
Procedure.i BspTraceAppendEvent(*Trace.BspTrace, Kind.l, Subsector.l, Seg.l,
                                Sector.l, Linedef.l, Side.l, FrontSector.l, BackSector.l)
  Protected oldCapacity.l
  Protected newCapacity.l
  Protected wideCapacity.q
  Protected wideCount.q
  Protected wideSize.q
  Protected bytes.q
  Protected memory.i
  Protected *item.BspEvent

  If BspTraceIsValid(*Trace) = #False
    BspSetError("BSP trace is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Trace\Count >= #BSP_MaxEvents
    BspSetError("BSP trace event cap is exhausted: " + Str(#BSP_MaxEvents) + " events.")
    ProcedureReturn #False
  EndIf
  If *Trace\Count >= *Trace\Capacity
    oldCapacity = *Trace\Capacity
    newCapacity = oldCapacity
    If newCapacity < 1
      newCapacity = 1
    EndIf
    If newCapacity <= #BSP_MaxEvents / 2
      newCapacity = newCapacity * 2
    Else
      newCapacity = #BSP_MaxEvents
    EndIf
    If newCapacity <= oldCapacity
      BspSetError("BSP trace capacity growth cannot cover the next event.")
      ProcedureReturn #False
    EndIf
    wideCapacity = newCapacity
    wideSize = SizeOf(BspEvent)
    bytes = wideCapacity * wideSize
    memory = AllocateMemory(bytes)
    If memory = 0
      BspSetError("Out of memory while growing the BSP trace event array.")
      ProcedureReturn #False
    EndIf
    If *Trace\Events <> 0
      wideCount = *Trace\Count
      CopyMemory(*Trace\Events, memory, wideCount * wideSize)
      FreeMemory(*Trace\Events)
    EndIf
    *Trace\Events = memory
    *Trace\Capacity = newCapacity
  EndIf

  *item = *Trace\Events + *Trace\Count * SizeOf(BspEvent)
  *item\Kind = Kind
  *item\Subsector = Subsector
  *item\Seg = Seg
  *item\Sector = Sector
  *item\Linedef = Linedef
  *item\Side = Side
  *item\FrontSector = FrontSector
  *item\BackSector = BackSector
  *Trace\Count + 1
  gBsp_LastError = ""
  ProcedureReturn #True
EndProcedure

; Builds an owned chronological trace from a ready MapLevel and a ready camera.
; The trace is reset first. Any failure (null/unready input, corrupt indices,
; stack/work/event budget exhaustion, geometry overflow, OOM) leaves it empty and
; reports diagnostics; the level and camera remain unchanged.
Procedure.i BspTraceBuild(*Level.MapLevel, *Camera.BspCamera, *Trace.BspTrace)
  Protected traceInitial.i
  Protected cameraX.l = 0
  Protected cameraY.l = 0
  Protected heading.q = 0
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
  Protected wideSubCount.q
  Protected wideSegCount.q
  Protected wideInitialEvents.q
  Protected wideSize.q
  Protected wideTraceInitial.q
  Protected eventBytes.q
  Protected wideFirstSeg.q
  Protected wideNumSegs.q
  Protected *stack.Long
  Protected sp.i = 0
  Protected item.l = 0
  Protected leafIndex.l
  Protected nodeIndex.l
  Protected numSegs.l
  Protected firstSeg.l
  Protected rangeEnd.q
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
  Protected segment.l
  Protected segLine.l
  Protected segSide.l
  Protected segFront.l
  Protected segBack.l
  Protected segIndex.l
  Protected lastSeg.l
  Protected visitedNodes.l = 0
  Protected visitedSubsectors.l = 0
  Protected emittedSegs.l = 0
  Protected workItems.l = 0
  Protected initialEvents.q
  Protected eventMemory.i
  Protected prefix.s
  Protected failureText.s

  BspSetError("")

  If *Trace = 0
    BspSetError("BSP trace pointer is null.")
    ProcedureReturn #False
  EndIf
  If BspTraceReset(*Trace) = #False
    ProcedureReturn #False
  EndIf

  If *Level = 0
    BspSetError("Map level pointer is null.")
    Goto BspBuildFail
  EndIf
  If MapLevelIsReady(*Level) = #False
    BspSetError("Map level is not initialized or not ready.")
    Goto BspBuildFail
  EndIf
  If *Camera = 0
    BspSetError("Camera pointer is null.")
    Goto BspBuildFail
  EndIf
  If BspCameraGet(*Camera, @cameraX, @cameraY, @heading) = #False
    BspSetError("Camera is not ready: " + BspCameraLastError())
    Goto BspBuildFail
  EndIf

  prefix = *Level\Name
  If prefix <> ""
    prefix = "Map " + prefix + ": "
  Else
    prefix = "BSP trace: "
  EndIf

  nodeCount = *Level\Nodes\Count
  subCount = *Level\Subsectors\Count
  segCount = *Level\Segs\Count
  lineCount = *Level\Linedefs\Count
  sectorCount = *Level\Sectors\Count

  If nodeCount < 0 Or subCount < 0 Or segCount < 0 Or lineCount < 0 Or sectorCount < 0
    BspSetError(prefix + "record counts are negative/corrupted.")
    Goto BspBuildFail
  EndIf
  If subCount <= 0 Or segCount <= 0 Or lineCount <= 0 Or sectorCount <= 0
    BspSetError(prefix + "required map record sets are empty.")
    Goto BspBuildFail
  EndIf

  If MapLevelGetBspRoot(*Level, @rootIsSubsector, @rootIndex) = #False
    BspSetError(prefix + "cannot read BSP root: " + MapLevelLastError())
    Goto BspBuildFail
  EndIf

  If rootIsSubsector <> 0
    ; M2's safe equivalent of original R_RenderBSPNode(-1): only a zero-node
    ; level with exactly one subsector may publish a subsector root.
    If nodeCount <> 0
      BspSetError(prefix + "a subsector root is inconsistent with a level that has nodes.")
      Goto BspBuildFail
    EndIf
    If subCount <> 1
      BspSetError(prefix + "zero-node BSP root requires exactly one subsector, got " + Str(subCount) + ".")
      Goto BspBuildFail
    EndIf
    If rootIndex < 0 Or rootIndex >= subCount Or rootIndex > #MAP_NF_SUBSECTOR - 1
      BspSetError(prefix + "BSP subsector root index is invalid: " + Str(rootIndex) + ".")
      Goto BspBuildFail
    EndIf
    rootRaw = rootIndex ! #MAP_NF_SUBSECTOR
    stackCapacity = 1
  Else
    If nodeCount = 0
      BspSetError(prefix + "a node root is inconsistent with a zero-node level.")
      Goto BspBuildFail
    EndIf
    If rootIndex < 0 Or rootIndex >= nodeCount Or rootIndex >= #MAP_NF_SUBSECTOR
      BspSetError(prefix + "BSP node root index is invalid or cannot be encoded as a nonleaf: " + Str(rootIndex) + ".")
      Goto BspBuildFail
    EndIf
    rootRaw = rootIndex
    stackCapacity = nodeCount + 2
  EndIf

  ; A validated acyclic graph has a current-path depth at most node count; the
  ; two pending siblings per level make nodeCount+2 a safe stack bound here.
  wideStackCapacity = stackCapacity
  stackBytes = wideStackCapacity * 4
  *stack = AllocateMemory(stackBytes)
  If *stack = 0
    BspSetError("Out of memory while allocating the bounded BSP work stack.")
    Goto BspBuildFail
  EndIf

  ; Initial storage equals the canonical no-sharing event total, bounded to the
  ; cap, so tiny levels and ordinary vanilla maps do not preallocate a huge array.
  wideSubCount = subCount
  wideSegCount = segCount
  initialEvents = wideSubCount + wideSegCount
  If initialEvents < 2
    initialEvents = 2
  EndIf
  If initialEvents > #BSP_MaxEvents
    initialEvents = #BSP_MaxEvents
  EndIf
  traceInitial = initialEvents
  wideTraceInitial = traceInitial
  wideSize = SizeOf(BspEvent)
  eventBytes = wideTraceInitial * wideSize
  eventMemory = AllocateMemory(eventBytes)
  If eventMemory = 0
    BspSetError("Out of memory while allocating initial BSP trace events.")
    Goto BspBuildFail
  EndIf

  ; Valid trace ownership begins before traversal so Reset can safely release it
  ; on every failure path. No event is externally published until success.
  *Trace\Magic = #BSPTRACE_Magic
  *Trace\Count = 0
  *Trace\Capacity = traceInitial
  *Trace\Events = eventMemory
  *Trace\VisitedNodes = 0
  *Trace\VisitedSubsectors = 0
  *Trace\EmittedSegs = 0
  *Trace\EmittedEvents = 0
  *Trace\OcclusionSkips = 0
  *Trace\WorkItems = 0

  If sp >= stackCapacity
    BspSetError(prefix + "BSP work stack overflow on root push.")
    Goto BspBuildFail
  EndIf
  PokeL(*stack, rootRaw)
  sp + 1
  workItems + 1

  While sp > 0
    sp - 1
    item = PeekL(*stack + sp * 4)
    workItems + 1
    If workItems > #BSP_MaxWorkItems
      BspSetError(prefix + "BSP work budget is exhausted: " + Str(#BSP_MaxWorkItems) + " push/pop items.")
      Goto BspBuildFail
    EndIf

    If (item & #MAP_NF_SUBSECTOR) <> 0
      ; R_Subsector leaf visit.
      leafIndex = item & $7FFF
      If leafIndex < 0 Or leafIndex >= subCount
        BspSetError(prefix + "BSP leaf references missing subsector " + Str(leafIndex) + ".")
        Goto BspBuildFail
      EndIf
      If MapSubsectorsGet(@*Level\Subsectors, leafIndex, @numSegs, @firstSeg) = #False
        BspSetError(prefix + "cannot read subsector " + Str(leafIndex) + ": " + MapDecodeLastError())
        Goto BspBuildFail
      EndIf
      If numSegs <= 0
        BspSetError(prefix + "subsector " + Str(leafIndex) + " has no segments.")
        Goto BspBuildFail
      EndIf
      If firstSeg < 0
        BspSetError(prefix + "subsector " + Str(leafIndex) + " has a negative first seg index.")
        Goto BspBuildFail
      EndIf
      wideFirstSeg = firstSeg
      wideNumSegs = numSegs
      rangeEnd = wideFirstSeg + wideNumSegs
      If rangeEnd > wideSegCount
        BspSetError(prefix + "subsector " + Str(leafIndex) + " seg range exceeds SEGS.")
        Goto BspBuildFail
      EndIf
      derivedSector = MapLevelGetSubsectorSector(*Level, leafIndex)
      If derivedSector < 0 Or derivedSector >= sectorCount
        BspSetError(prefix + "subsector " + Str(leafIndex) + " sector is invalid: " + Str(derivedSector) + ".")
        Goto BspBuildFail
      EndIf

      If BspTraceAppendEvent(*Trace, #BSP_EventSubsector, leafIndex,
                             #BSP_NoIndex, derivedSector, #BSP_NoIndex,
                             #BSP_NoIndex, #BSP_NoIndex, #BSP_NoIndex) = #False
        Goto BspBuildFail
      EndIf
      visitedSubsectors + 1

      lastSeg = firstSeg + numSegs - 1
      For segIndex = firstSeg To lastSeg
        If MapLevelGetSegLinks(*Level, segIndex, @segLine, @segSide, @segFront, @segBack) = #False
          BspSetError(prefix + "cannot read seg " + Str(segIndex) + ": " + MapLevelLastError())
          Goto BspBuildFail
        EndIf
        If segLine < 0 Or segLine >= lineCount
          BspSetError(prefix + "seg " + Str(segIndex) + " linedef index is invalid: " + Str(segLine) + ".")
          Goto BspBuildFail
        EndIf
        If segSide <> 0 And segSide <> 1
          BspSetError(prefix + "seg " + Str(segIndex) + " side is invalid: " + Str(segSide) + ".")
          Goto BspBuildFail
        EndIf
        If segFront < 0 Or segFront >= sectorCount
          BspSetError(prefix + "seg " + Str(segIndex) + " front sector is invalid: " + Str(segFront) + ".")
          Goto BspBuildFail
        EndIf
        If segBack <> #BSP_NoIndex And (segBack < 0 Or segBack >= sectorCount)
          BspSetError(prefix + "seg " + Str(segIndex) + " back sector is invalid: " + Str(segBack) + ".")
          Goto BspBuildFail
        EndIf

        If BspTraceAppendEvent(*Trace, #BSP_EventSeg, leafIndex, segIndex,
                               derivedSector, segLine, segSide, segFront, segBack) = #False
          Goto BspBuildFail
        EndIf
        emittedSegs + 1
      Next
      Continue
    EndIf

    ; R_RenderBSPNode node branch.
    nodeIndex = item
    If nodeIndex < 0 Or nodeIndex >= nodeCount
      BspSetError(prefix + "BSP node index is invalid: " + Str(nodeIndex) + ".")
      Goto BspBuildFail
    EndIf

    If MapNodesGet(@*Level\Nodes, nodeIndex, @nodeOriginX, @nodeOriginY,
                   @nodeDX, @nodeDY, 0, 0, 0, 0, 0, 0, 0, 0,
                   @child0, @child1) = #False
      BspSetError(prefix + "cannot read BSP node " + Str(nodeIndex) + ": " + MapDecodeLastError())
      Goto BspBuildFail
    EndIf

    ; Node fields are signed16 map units and always inside FixedFromIntChecked's
    ; domain in a validated map; the calls are still checked for corrupted memory.
    If FixedFromIntChecked(nodeOriginX, @nodeOriginX) = #False
      BspSetError(prefix + "node " + Str(nodeIndex) + " origin X conversion failed: " + FixedLastError())
      Goto BspBuildFail
    EndIf
    If FixedFromIntChecked(nodeOriginY, @nodeOriginY) = #False
      BspSetError(prefix + "node " + Str(nodeIndex) + " origin Y conversion failed: " + FixedLastError())
      Goto BspBuildFail
    EndIf
    If FixedFromIntChecked(nodeDX, @nodeDX) = #False
      BspSetError(prefix + "node " + Str(nodeIndex) + " direction DX conversion failed: " + FixedLastError())
      Goto BspBuildFail
    EndIf
    If FixedFromIntChecked(nodeDY, @nodeDY) = #False
      BspSetError(prefix + "node " + Str(nodeIndex) + " direction DY conversion failed: " + FixedLastError())
      Goto BspBuildFail
    EndIf

    side = 0
    If GeometryPointOnNodeSideChecked(cameraX, cameraY, nodeOriginX, nodeOriginY,
                                      nodeDX, nodeDY, @side) = #False
      BspSetError(prefix + "node " + Str(nodeIndex) + " camera X " + Str(cameraX) +
                  ", Y " + Str(cameraY) + " side classification failed: " + GeometryLastError())
      Goto BspBuildFail
    EndIf
    If side <> 0 And side <> 1
      BspSetError(prefix + "node " + Str(nodeIndex) + " geometry returned an invalid side.")
      Goto BspBuildFail
    EndIf

    If side = 0
      nearRaw = child0
      farRaw = child1
    Else
      nearRaw = child1
      farRaw = child0
    EndIf

    ; Defensive range check of stored raw children (M2 already validated them).
    If (farRaw & #MAP_NF_SUBSECTOR) <> 0
      If (farRaw & $7FFF) >= subCount
        BspSetError(prefix + "node " + Str(nodeIndex) + " far leaf references missing subsector.")
        Goto BspBuildFail
      EndIf
    ElseIf farRaw < 0 Or farRaw >= nodeCount Or farRaw >= #MAP_NF_SUBSECTOR
      BspSetError(prefix + "node " + Str(nodeIndex) + " far child node index is invalid: " + Str(farRaw) + ".")
      Goto BspBuildFail
    EndIf
    If (nearRaw & #MAP_NF_SUBSECTOR) <> 0
      If (nearRaw & $7FFF) >= subCount
        BspSetError(prefix + "node " + Str(nodeIndex) + " near leaf references missing subsector.")
        Goto BspBuildFail
      EndIf
    ElseIf nearRaw < 0 Or nearRaw >= nodeCount Or nearRaw >= #MAP_NF_SUBSECTOR
      BspSetError(prefix + "node " + Str(nodeIndex) + " near child node index is invalid: " + Str(nearRaw) + ".")
      Goto BspBuildFail
    EndIf

    visitedNodes + 1

    ; Recursive C processes near then far. LIFO: push far first, then near.
    If sp >= stackCapacity
      BspSetError(prefix + "BSP work stack overflow on far-child push for node " + Str(nodeIndex) + ".")
      Goto BspBuildFail
    EndIf
    PokeL(*stack + sp * 4, farRaw)
    sp + 1
    workItems + 1
    If workItems > #BSP_MaxWorkItems
      BspSetError(prefix + "BSP work budget is exhausted: " + Str(#BSP_MaxWorkItems) + " push/pop items.")
      Goto BspBuildFail
    EndIf

    If sp >= stackCapacity
      BspSetError(prefix + "BSP work stack overflow on near-child push for node " + Str(nodeIndex) + ".")
      Goto BspBuildFail
    EndIf
    PokeL(*stack + sp * 4, nearRaw)
    sp + 1
    workItems + 1
    If workItems > #BSP_MaxWorkItems
      BspSetError(prefix + "BSP work budget is exhausted: " + Str(#BSP_MaxWorkItems) + " push/pop items.")
      Goto BspBuildFail
    EndIf
  Wend

  *Trace\VisitedNodes = visitedNodes
  *Trace\VisitedSubsectors = visitedSubsectors
  *Trace\EmittedSegs = emittedSegs
  *Trace\EmittedEvents = *Trace\Count
  *Trace\OcclusionSkips = 0
  *Trace\WorkItems = workItems

  If *stack <> 0
    FreeMemory(*stack)
    *stack = 0
  EndIf
  gBsp_LastError = ""
  ProcedureReturn #True

BspBuildFail:
  failureText = gBsp_LastError
  If *stack <> 0
    FreeMemory(*stack)
    *stack = 0
  EndIf
  BspTraceReset(*Trace)
  BspSetError(failureText)
  ProcedureReturn #False
EndProcedure

CompilerEndIf
