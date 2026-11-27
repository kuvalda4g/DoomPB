; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Headless solid/pass wall-column interval state from Linux Doom 1.10 r_bsp.c:
;   cliprange_t {first,last}, solidsegs[MAXSEGS=32], newend;
;   R_ClearClipSegs      -> ClipStateBeginFrame
;   R_ClipSolidWallSegment -> ClipSolidSegment
;   R_ClipPassWallSegment  -> ClipPassSegment
;
; Columns and ends are inclusive, exactly as the original int first/last pairs.
; Initial clip posts are fixed sentinels:
;   [-0x7FFFFFFF, -1]    [viewwidth, +0x7FFFFFFF]
; The drawable domain [0..viewwidth-1] starts unoccluded.
;
; Observable emission order is reproduced: every still-uncovered subspan is
; emitted left-to-right before a SOLID operation updates occlusion state, and a
; solid interval then expands/merges posts so later walls cannot re-emit covered
; pixels. PASS operations emit uncovered subspans but never modify occlusion.
;
; Safety adaptation versus original pointer arithmetic:
;   - the fixed two-post array is replaced by a bounded, owned, checked range
;     container (initial capacity 4, doubling growth, hard range cap 1024);
;   - solid insertion/merge compaction never mutates or removes the two fixed
;     sentinels. The original can extend a sentinel and delete the far sentinel
;     when a wall reaches the screen boundary or fills the whole width; DoomPB
;     keeps both sentinels and inserts/consolidates real posts between them. The
;     emitted subspans and the screen-domain union coverage are identical, so
;     only the private interval representation differs;
;   - the original `goto crunch` pointer compaction is replaced by a checked
;     one-sided compaction preserving the intended sorted, disjoint real-post
;     list; every final real post still has at least a one-pixel gap from its
;     neighbour (boundary sentinels may remain adjacent to the drawable domain);
;   - all indexes, capacities, span budgets and byte arithmetic are checked;
;     invalid/inverted/out-of-domain ranges are explicit errors and leave state
;     untouched; an operation pre-reserves its required storage and caps before
;     any emission or mutation, so failures cannot partial-publish;
;   - iteration is bounded by range count and explicit budgets; no recursion,
;     pointer indexing, arbitrary while scan or negative-column post exists.
;
; This module is independent of MapLevel/Projection/WAD/graphics and fully
; testable with tiny widths 1..320. The canonical Doom frame uses width 320.
;
; Visible wall-span records carry source identity supplied by the caller:
;   Subsector, Seg, Linedef, Side, FrontSector, BackSector (all .l indices,
;   -1 is the one-sided/documented sentinel), FirstX/LastX inclusive and
;   WallKind (#WALL_KIND_SOLID / #WALL_KIND_PASS). No texture/pixel data.
;
; Ownership: caller zero-initializes ClipState. BeginFrame resets and owns a
; ranges array plus a spans array; Reset frees both, is idempotent and leaves a
; reusable empty object. Failed BeginFrame leaves an owner-free empty object
; with an error. Every failed clip operation leaves ranges+spans unchanged.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_CLIPSEGS_PBI, #PB_Constant) = 0

#DOOMPB_CLIPSEGS_PBI = 1

XIncludeFile "WallSpanDefs.pbi"

#CLIP_Magic = $434C5031

; Exact sentinel bounds from R_ClearClipSegs.
#CLIP_SentinelMinFirst = -2147483647
#CLIP_SentinelMinLast = -1
#CLIP_SentinelMaxLast = 2147483647

; Project safety caps, not vanilla MAXSEGS.
#CLIP_MaxWidth = 320
#CLIP_MaxRanges = 1024
#CLIP_MaxSpans = 1000000
#CLIP_RangeInitialCapacity = 4
#CLIP_SpanInitialCapacity = 64

Structure ClipRange
  First.l
  Last.l
EndStructure

Structure ClipSpan
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

Structure ClipState
  Magic.l
  Ready.l
  Width.l
  RangeCount.l
  RangeCapacity.l
  *Ranges.ClipRange
  SpanCount.l
  SpanCapacity.l
  *Spans.ClipSpan
  RangeGrowths.l
  SpanGrowths.l
  AllocationCount.l
EndStructure

Global gClip_LastError.s = ""

Procedure ClipSetError(Message.s)
  gClip_LastError = Message
EndProcedure

Procedure.s ClipLastError()
  ProcedureReturn gClip_LastError
EndProcedure

Procedure.i ClipStateIsValid(*State.ClipState)
  ProcedureReturn Bool(*State <> 0 And *State\Magic = #CLIP_Magic And *State\Ready = 1)
EndProcedure

; Idempotent empty reusable clip state. A zero-initialized caller structure is
; accepted; unrecognized Magic or unexplained owned arrays are rejected.
Procedure.i ClipStateReset(*State.ClipState)
  If *State = 0
    ClipSetError("Clip state pointer is null.")
    ProcedureReturn #False
  EndIf
  If *State\Magic = #CLIP_Magic
    If *State\Ranges <> 0
      FreeMemory(*State\Ranges)
    EndIf
    If *State\Spans <> 0
      FreeMemory(*State\Spans)
    EndIf
  ElseIf *State\Magic <> 0
    ClipSetError("Clip state object has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *State\Ranges <> 0 Or *State\Spans <> 0
    ClipSetError("Clip state has unexplained ranges/spans pointers without a Magic value.")
    ProcedureReturn #False
  EndIf

  *State\Magic = #CLIP_Magic
  *State\Ready = 0
  *State\Width = 0
  *State\RangeCount = 0
  *State\RangeCapacity = 0
  *State\Ranges = 0
  *State\SpanCount = 0
  *State\SpanCapacity = 0
  *State\Spans = 0
  *State\RangeGrowths = 0
  *State\SpanGrowths = 0
  *State\AllocationCount = 0
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

; Starts a fresh frame at an explicit logical width. Canonical M3-04 width is
; 320; tiny widths 1..320 are accepted for independent interval tests. The two
; exact sentinel posts are installed and no visible span is published yet.
Procedure.i ClipStateBeginFrame(*State.ClipState, Width.l)
  Protected rangesBytes.q
  Protected spansBytes.q
  Protected rangesMemory.i = 0
  Protected spansMemory.i = 0
  Protected *range.ClipRange

  ClipSetError("")
  If *State = 0
    ClipSetError("Clip state pointer is null.")
    ProcedureReturn #False
  EndIf
  If *State\Magic <> 0 And *State\Magic <> #CLIP_Magic
    ClipSetError("Clip state object has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If Width < 1 Or Width > #CLIP_MaxWidth
    ClipSetError("Clip frame width " + Str(Width) + " is outside 1.." + Str(#CLIP_MaxWidth) + ".")
    ProcedureReturn #False
  EndIf
  If ClipStateReset(*State) = #False
    ProcedureReturn #False
  EndIf

  rangesBytes = Int(#CLIP_RangeInitialCapacity) * SizeOf(ClipRange)
  spansBytes = Int(#CLIP_SpanInitialCapacity) * SizeOf(ClipSpan)
  rangesMemory = AllocateMemory(rangesBytes)
  spansMemory = AllocateMemory(spansBytes)
  If rangesMemory = 0 Or spansMemory = 0
    If rangesMemory <> 0
      FreeMemory(rangesMemory)
    EndIf
    If spansMemory <> 0
      FreeMemory(spansMemory)
    EndIf
    ClipSetError("Out of memory while allocating initial clip ranges/spans.")
    ProcedureReturn #False
  EndIf

  *State\Magic = #CLIP_Magic
  *State\Ready = 0
  *State\Width = Width
  *State\RangeCount = 0
  *State\RangeCapacity = #CLIP_RangeInitialCapacity
  *State\Ranges = rangesMemory
  *State\SpanCount = 0
  *State\SpanCapacity = #CLIP_SpanInitialCapacity
  *State\Spans = spansMemory
  *State\AllocationCount = 2

  *range = *State\Ranges
  *range\First = #CLIP_SentinelMinFirst
  *range\Last = #CLIP_SentinelMinLast
  *range = *State\Ranges + SizeOf(ClipRange)
  *range\First = Width
  *range\Last = #CLIP_SentinelMaxLast
  *State\RangeCount = 2
  *State\RangeGrowths = 0
  *State\SpanGrowths = 0
  *State\Ready = 1
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

; Internal invariant check, run before any mutation/emission. Sentinels must be
; exact; real posts are inside 0..width-1, sorted and separated by at least one
; uncovered pixel except the allowed boundary adjacency to the drawable domain.
Procedure.i ClipCheckInvariants(*State.ClipState)
  Protected i.i
  Protected *range.ClipRange
  Protected *prev.ClipRange
  Protected realCount.i

  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If *State\RangeCount < 2 Or *State\RangeCount > *State\RangeCapacity
    ClipSetError("Clip range count is outside its allocated storage.")
    ProcedureReturn #False
  EndIf
  *range = *State\Ranges
  If *range\First <> #CLIP_SentinelMinFirst Or *range\Last <> #CLIP_SentinelMinLast
    ClipSetError("Clip left sentinel was corrupted.")
    ProcedureReturn #False
  EndIf
  *range = *State\Ranges + (*State\RangeCount - 1) * SizeOf(ClipRange)
  If *range\First <> *State\Width Or *range\Last <> #CLIP_SentinelMaxLast
    ClipSetError("Clip right sentinel was corrupted.")
    ProcedureReturn #False
  EndIf

  realCount = *State\RangeCount - 2
  If realCount > 0
    For i = 1 To *State\RangeCount - 2
      *range = *State\Ranges + i * SizeOf(ClipRange)
      If *range\First < 0 Or *range\Last > *State\Width - 1 Or *range\First > *range\Last
        ClipSetError("Clip real range " + Str(i) + " is outside the drawable domain.")
        ProcedureReturn #False
      EndIf
      If i >= 2
        *prev = *State\Ranges + (i - 1) * SizeOf(ClipRange)
        If *range\First < *prev\Last + 2
          ClipSetError("Clip real ranges " + Str(i - 1) + " and " + Str(i) + " are not disjoint and sorted.")
          ProcedureReturn #False
        EndIf
      EndIf
    Next
  EndIf
  If realCount > 0
    *range = *State\Ranges + (*State\RangeCount - 2) * SizeOf(ClipRange)
    If *range\Last > *State\Width - 1
      ClipSetError("Clip last real range exceeds the drawable domain.")
      ProcedureReturn #False
    EndIf
  EndIf
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

; Bounded geometric growth of the range array. Needed is checked before any
; replacement; old storage is untouched when the allocation fails.
Procedure.i ClipGrowRanges(*State.ClipState, Needed.l)
  Protected oldCapacity.l
  Protected newCapacity.l
  Protected wideCapacity.q
  Protected bytes.q
  Protected memory.i
  Protected copyBytes.q

  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If Needed < 0
    ClipSetError("Clip range growth request is negative.")
    ProcedureReturn #False
  EndIf
  If Needed <= *State\RangeCapacity
    ProcedureReturn #True
  EndIf
  If Needed > #CLIP_MaxRanges
    ClipSetError("Clip range cap " + Str(#CLIP_MaxRanges) + " cannot cover " + Str(Needed) + " posts.")
    ProcedureReturn #False
  EndIf

  oldCapacity = *State\RangeCapacity
  newCapacity = oldCapacity
  If newCapacity < #CLIP_RangeInitialCapacity
    newCapacity = #CLIP_RangeInitialCapacity
  EndIf
  While newCapacity < Needed And newCapacity < #CLIP_MaxRanges
    If newCapacity <= #CLIP_MaxRanges / 2
      newCapacity = newCapacity * 2
    Else
      newCapacity = #CLIP_MaxRanges
    EndIf
    If newCapacity <= oldCapacity
      ClipSetError("Clip range growth cannot cover the requested count.")
      ProcedureReturn #False
    EndIf
  Wend
  If newCapacity < Needed
    newCapacity = Needed
  EndIf
  If newCapacity > #CLIP_MaxRanges
    ClipSetError("Clip range growth exceeds the hard cap.")
    ProcedureReturn #False
  EndIf

  wideCapacity = newCapacity
  bytes = wideCapacity * Int(SizeOf(ClipRange))
  memory = AllocateMemory(bytes)
  If memory = 0
    ClipSetError("Out of memory while growing clip ranges.")
    ProcedureReturn #False
  EndIf
  If *State\Ranges <> 0
    copyBytes = Int(*State\RangeCount) * Int(SizeOf(ClipRange))
    CopyMemory(*State\Ranges, memory, copyBytes)
    FreeMemory(*State\Ranges)
  EndIf
  *State\Ranges = memory
  *State\RangeCapacity = newCapacity
  *State\RangeGrowths + 1
  *State\AllocationCount + 1
  ProcedureReturn #True
EndProcedure

; Bounded geometric growth of the span array. Same transactional rule.
Procedure.i ClipGrowSpans(*State.ClipState, Needed.l)
  Protected oldCapacity.l
  Protected newCapacity.l
  Protected wideCapacity.q
  Protected bytes.q
  Protected memory.i
  Protected copyBytes.q

  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If Needed < 0
    ClipSetError("Clip span growth request is negative.")
    ProcedureReturn #False
  EndIf
  If Needed <= *State\SpanCapacity
    ProcedureReturn #True
  EndIf
  If Needed > #CLIP_MaxSpans
    ClipSetError("Clip span cap " + Str(#CLIP_MaxSpans) + " cannot cover " + Str(Needed) + " published spans.")
    ProcedureReturn #False
  EndIf

  oldCapacity = *State\SpanCapacity
  newCapacity = oldCapacity
  If newCapacity < #CLIP_SpanInitialCapacity
    newCapacity = #CLIP_SpanInitialCapacity
  EndIf
  While newCapacity < Needed And newCapacity < #CLIP_MaxSpans
    If newCapacity <= #CLIP_MaxSpans / 2
      newCapacity = newCapacity * 2
    Else
      newCapacity = #CLIP_MaxSpans
    EndIf
    If newCapacity <= oldCapacity
      ClipSetError("Clip span growth cannot cover the requested count.")
      ProcedureReturn #False
    EndIf
  Wend
  If newCapacity < Needed
    newCapacity = Needed
  EndIf
  If newCapacity > #CLIP_MaxSpans
    ClipSetError("Clip span growth exceeds the hard cap.")
    ProcedureReturn #False
  EndIf

  wideCapacity = newCapacity
  bytes = wideCapacity * Int(SizeOf(ClipSpan))
  memory = AllocateMemory(bytes)
  If memory = 0
    ClipSetError("Out of memory while growing clip spans.")
    ProcedureReturn #False
  EndIf
  If *State\Spans <> 0
    copyBytes = Int(*State\SpanCount) * Int(SizeOf(ClipSpan))
    CopyMemory(*State\Spans, memory, copyBytes)
    FreeMemory(*State\Spans)
  EndIf
  *State\Spans = memory
  *State\SpanCapacity = newCapacity
  *State\SpanGrowths + 1
  *State\AllocationCount + 1
  ProcedureReturn #True
EndProcedure

; Internal append of one visible fragment. Callers pre-reserve capacity and the
; budget before mutation, so this only writes an in-budget record.
Procedure.i ClipAppendSpan(*State.ClipState, First.l, Last.l, Kind.l,
                          Subsector.l, Seg.l, Linedef.l, Side.l, FrontSector.l, BackSector.l)
  Protected *span.ClipSpan

  If *State\SpanCount >= #CLIP_MaxSpans
    ClipSetError("Clip span cap is exhausted.")
    ProcedureReturn #False
  EndIf
  If *State\SpanCount >= *State\SpanCapacity
    ClipSetError("Clip span storage capacity is exhausted without a pre-reservation.")
    ProcedureReturn #False
  EndIf
  *span = *State\Spans + *State\SpanCount * SizeOf(ClipSpan)
  *span\Subsector = Subsector
  *span\Seg = Seg
  *span\Linedef = Linedef
  *span\Side = Side
  *span\FrontSector = FrontSector
  *span\BackSector = BackSector
  *span\FirstX = First
  *span\LastX = Last
  *span\Kind = Kind
  *State\SpanCount + 1
  ProcedureReturn #True
EndProcedure

; First real post whose Last touches First (inclusive adjacency), or -1 when no
; real post touches. Sentinels are fixed and not candidates for mutation.
Procedure.i ClipFindRealStart(*State.ClipState, First.l)
  Protected i.i
  Protected *range.ClipRange

  If *State\RangeCount > 2
    For i = 1 To *State\RangeCount - 2
      *range = *State\Ranges + i * SizeOf(ClipRange)
      If *range\Last >= First - 1
        ProcedureReturn i
      EndIf
    Next
  EndIf
  ProcedureReturn -1
EndProcedure

; Insert a real post at an index already covered by range growth. Shifts the
; following real posts and the right sentinel down one slot; the left sentinel
; is untouched.
Procedure.i ClipInsertRange(*State.ClipState, InsertIndex.l, First.l, Last.l)
  Protected i.i
  Protected *dst.ClipRange
  Protected *src.ClipRange

  If InsertIndex < 1 Or InsertIndex > *State\RangeCount - 1
    ClipSetError("Clip insert index is outside the real-post/sentinel slots.")
    ProcedureReturn #False
  EndIf
  If *State\RangeCount >= *State\RangeCapacity
    ClipSetError("Clip insert has no pre-reserved range capacity.")
    ProcedureReturn #False
  EndIf
  For i = *State\RangeCount - 1 To InsertIndex Step -1
    *src = *State\Ranges + i * SizeOf(ClipRange)
    *dst = *State\Ranges + (i + 1) * SizeOf(ClipRange)
    *dst\First = *src\First
    *dst\Last = *src\Last
  Next
  *dst = *State\Ranges + InsertIndex * SizeOf(ClipRange)
  *dst\First = First
  *dst\Last = Last
  *State\RangeCount + 1
  ProcedureReturn #True
EndProcedure

; Checked compaction: keep the updated start post, remove real posts start+1
; through next inclusive, and shift the remaining real posts/right sentinel
; upward. Sentinels survive. No element outside the valid range is read/written.
Procedure.i ClipCompact(*State.ClipState, StartIndex.l, NextIndex.l)
  Protected removedCount.l
  Protected i.i
  Protected totalMove.l
  Protected *dst.ClipRange
  Protected *src.ClipRange

  If StartIndex < 1 Or NextIndex < StartIndex Or NextIndex > *State\RangeCount - 2
    ClipSetError("Clip compaction indexes reference a sentinel or are inverted.")
    ProcedureReturn #False
  EndIf
  removedCount = NextIndex - StartIndex
  totalMove = *State\RangeCount - 1 - NextIndex
  If totalMove > 0
    For i = NextIndex + 1 To *State\RangeCount - 1
      *src = *State\Ranges + i * SizeOf(ClipRange)
      *dst = *State\Ranges + (i - removedCount) * SizeOf(ClipRange)
      *dst\First = *src\First
      *dst\Last = *src\Last
    Next
  EndIf
  *State\RangeCount = *State\RangeCount - removedCount
  ProcedureReturn #True
EndProcedure

; Solid wall clipping: probe first/last inclusive. Returns #False with an error
; on any invalid input/state/cap; the previous ranges and spans stay unchanged.
; On success emits uncovered fragments left-to-right and merges occlusion posts.
Procedure.i ClipSolidSegment(*State.ClipState, First.l, Last.l,
                             Subsector.l, Seg.l, Linedef.l, Side.l,
                             FrontSector.l, BackSector.l)
  Protected startIndex.i
  Protected insertNeeded.i
  Protected startFirst.l
  Protected startLast.l
  Protected nextIndex.i
  Protected nextFirst.l
  Protected nextLast.l
  Protected gapFirst.l
  Protected gapLast.l
  Protected predictedRanges.q
  Protected predictedSpans.q
  Protected worstSpans.q

  ClipSetError("")
  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If First < 0 Or Last < First Or Last > *State\Width - 1
    ClipSetError("Clip solid span " + Str(First) + ".." + Str(Last) + " is invalid, inverted or outside 0.." + Str(*State\Width - 1) + ".")
    ProcedureReturn #False
  EndIf
  If ClipCheckInvariants(*State) = #False
    ProcedureReturn #False
  EndIf

  ; A span fully contained by an existing post emits nothing and needs no new
  ; storage; this original early-return branch is handled before any growth.
  startIndex = ClipFindRealStart(*State, First)
  insertNeeded = 0
  If startIndex >= 0
    startFirst = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange))
    If First >= startFirst
      startLast = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange) + 4)
      If Last <= startLast
        gClip_LastError = ""
        ProcedureReturn #True
      EndIf
    EndIf
  EndIf
  If startIndex < 0
    insertNeeded = 1
  ElseIf First < startFirst And Last >= startFirst - 1
    insertNeeded = 0
  ElseIf First < startFirst
    insertNeeded = 1
  EndIf
  predictedRanges = Int(*State\RangeCount) + insertNeeded
  worstSpans = Int(*State\RangeCount) + 3
  predictedSpans = Int(*State\SpanCount) + worstSpans
  If predictedRanges > #CLIP_MaxRanges
    ClipSetError("Clip solid insertion would exceed the real range cap.")
    ProcedureReturn #False
  EndIf
  If predictedSpans > #CLIP_MaxSpans
    ClipSetError("Clip solid fragments would exceed the visible span cap.")
    ProcedureReturn #False
  EndIf
  If ClipGrowSpans(*State, Int(predictedSpans)) = #False
    ProcedureReturn #False
  EndIf
  If insertNeeded <> 0
    If ClipGrowRanges(*State, Int(predictedRanges)) = #False
      ProcedureReturn #False
    EndIf
  EndIf

  If startIndex < 0
    ; No real post touches: entire span is visible; insert sorted before the
    ; fixed right sentinel (all real posts sit below the new range).
    If ClipAppendSpan(*State, First, Last, #WALL_KIND_SOLID, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
      ProcedureReturn #False
    EndIf
    If ClipInsertRange(*State, *State\RangeCount - 1, First, Last) = #False
      ProcedureReturn #False
    EndIf
    gClip_LastError = ""
    ProcedureReturn #True
  EndIf

  startFirst = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange))
  startLast = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange) + 4)

  If First < startFirst
    If Last < startFirst - 1
      ; Post entirely visible above start: emit whole, insert before start.
      If ClipAppendSpan(*State, First, Last, #WALL_KIND_SOLID, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
        ProcedureReturn #False
      EndIf
      If ClipInsertRange(*State, startIndex, First, Last) = #False
        ProcedureReturn #False
      EndIf
      gClip_LastError = ""
      ProcedureReturn #True
    EndIf
    ; Visible fragment above start; extend the post down to the new First.
    If ClipAppendSpan(*State, First, startFirst - 1, #WALL_KIND_SOLID, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
      ProcedureReturn #False
    EndIf
    PokeL(*State\Ranges + startIndex * SizeOf(ClipRange), First)
    startFirst = First
  EndIf

  If Last <= startLast
    gClip_LastError = ""
    ProcedureReturn #True
  EndIf

  nextIndex = startIndex
  While nextIndex + 1 <= *State\RangeCount - 2 And Last >= PeekL(*State\Ranges + (nextIndex + 1) * SizeOf(ClipRange)) - 1
    nextLast = PeekL(*State\Ranges + nextIndex * SizeOf(ClipRange) + 4)
    nextFirst = PeekL(*State\Ranges + (nextIndex + 1) * SizeOf(ClipRange))
    gapFirst = nextLast + 1
    gapLast = nextFirst - 1
    If gapFirst > gapLast
      ClipSetError("Clip solid gap computed inverted; range invariant was violated.")
      ProcedureReturn #False
    EndIf
    If ClipAppendSpan(*State, gapFirst, gapLast, #WALL_KIND_SOLID, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
      ProcedureReturn #False
    EndIf
    nextIndex + 1
    nextLast = PeekL(*State\Ranges + nextIndex * SizeOf(ClipRange) + 4)
    If Last <= nextLast
      PokeL(*State\Ranges + startIndex * SizeOf(ClipRange) + 4, nextLast)
      If nextIndex <> startIndex
        If ClipCompact(*State, startIndex, nextIndex) = #False
          ProcedureReturn #False
        EndIf
      EndIf
      gClip_LastError = ""
      ProcedureReturn #True
    EndIf
  Wend

  nextLast = PeekL(*State\Ranges + nextIndex * SizeOf(ClipRange) + 4)
  If ClipAppendSpan(*State, nextLast + 1, Last, #WALL_KIND_SOLID, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
    ProcedureReturn #False
  EndIf
  PokeL(*State\Ranges + startIndex * SizeOf(ClipRange) + 4, Last)
  If nextIndex <> startIndex
    If ClipCompact(*State, startIndex, nextIndex) = #False
      ProcedureReturn #False
    EndIf
  EndIf
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

; Pass wall clipping: emits uncovered fragments only; never modifies occlusion.
Procedure.i ClipPassSegment(*State.ClipState, First.l, Last.l,
                            Subsector.l, Seg.l, Linedef.l, Side.l,
                            FrontSector.l, BackSector.l)
  Protected startIndex.i
  Protected startFirst.l
  Protected startLast.l
  Protected nextIndex.i
  Protected nextFirst.l
  Protected nextLast.l
  Protected gapFirst.l
  Protected gapLast.l
  Protected predictedSpans.q
  Protected worstSpans.q

  ClipSetError("")
  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If First < 0 Or Last < First Or Last > *State\Width - 1
    ClipSetError("Clip pass span " + Str(First) + ".." + Str(Last) + " is invalid, inverted or outside 0.." + Str(*State\Width - 1) + ".")
    ProcedureReturn #False
  EndIf
  If ClipCheckInvariants(*State) = #False
    ProcedureReturn #False
  EndIf

  startIndex = ClipFindRealStart(*State, First)
  If startIndex >= 0
    startFirst = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange))
    If First >= startFirst
      startLast = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange) + 4)
      If Last <= startLast
        gClip_LastError = ""
        ProcedureReturn #True
      EndIf
    EndIf
  EndIf

  worstSpans = Int(*State\RangeCount) + 3
  predictedSpans = Int(*State\SpanCount) + worstSpans
  If predictedSpans > #CLIP_MaxSpans
    ClipSetError("Clip pass fragments would exceed the visible span cap.")
    ProcedureReturn #False
  EndIf
  If ClipGrowSpans(*State, Int(predictedSpans)) = #False
    ProcedureReturn #False
  EndIf

  If startIndex < 0
    If ClipAppendSpan(*State, First, Last, #WALL_KIND_PASS, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
      ProcedureReturn #False
    EndIf
    gClip_LastError = ""
    ProcedureReturn #True
  EndIf

  startFirst = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange))
  startLast = PeekL(*State\Ranges + startIndex * SizeOf(ClipRange) + 4)
  If First < startFirst
    If Last < startFirst - 1
      If ClipAppendSpan(*State, First, Last, #WALL_KIND_PASS, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
        ProcedureReturn #False
      EndIf
      gClip_LastError = ""
      ProcedureReturn #True
    EndIf
    If ClipAppendSpan(*State, First, startFirst - 1, #WALL_KIND_PASS, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
      ProcedureReturn #False
    EndIf
  EndIf
  If Last <= startLast
    gClip_LastError = ""
    ProcedureReturn #True
  EndIf

  nextIndex = startIndex
  While nextIndex + 1 <= *State\RangeCount - 2 And Last >= PeekL(*State\Ranges + (nextIndex + 1) * SizeOf(ClipRange)) - 1
    nextLast = PeekL(*State\Ranges + nextIndex * SizeOf(ClipRange) + 4)
    nextFirst = PeekL(*State\Ranges + (nextIndex + 1) * SizeOf(ClipRange))
    gapFirst = nextLast + 1
    gapLast = nextFirst - 1
    If gapFirst > gapLast
      ClipSetError("Clip pass gap computed inverted; range invariant was violated.")
      ProcedureReturn #False
    EndIf
    If ClipAppendSpan(*State, gapFirst, gapLast, #WALL_KIND_PASS, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
      ProcedureReturn #False
    EndIf
    nextIndex + 1
    nextLast = PeekL(*State\Ranges + nextIndex * SizeOf(ClipRange) + 4)
    If Last <= nextLast
      gClip_LastError = ""
      ProcedureReturn #True
    EndIf
  Wend

  nextLast = PeekL(*State\Ranges + nextIndex * SizeOf(ClipRange) + 4)
  If ClipAppendSpan(*State, nextLast + 1, Last, #WALL_KIND_PASS, Subsector, Seg, Linedef, Side, FrontSector, BackSector) = #False
    ProcedureReturn #False
  EndIf
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

; Read-only solid/seclusion range accessors; indexes include the two fixed
; sentinels and every real post, so callers can diagnose the whole array.
Procedure.i ClipStateGetRange(*State.ClipState, RangeIndex.i, *First.Long, *Last.Long)
  Protected *range.ClipRange

  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If RangeIndex < 0 Or RangeIndex > *State\RangeCount - 1
    ClipSetError("Clip range index out of range: " + Str(RangeIndex) + ".")
    ProcedureReturn #False
  EndIf
  *range = *State\Ranges + RangeIndex * SizeOf(ClipRange)
  If *First <> 0
    PokeL(*First, *range\First)
  EndIf
  If *Last <> 0
    PokeL(*Last, *range\Last)
  EndIf
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

; Read-only visible-span accessor with source identity and inclusive endpoints.
Procedure.i ClipStateGetSpan(*State.ClipState, SpanIndex.i,
                             *Subsector.Long, *Seg.Long, *Linedef.Long, *Side.Long,
                             *FrontSector.Long, *BackSector.Long,
                             *FirstX.Long, *LastX.Long, *Kind.Long)
  Protected *span.ClipSpan

  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If SpanIndex < 0 Or SpanIndex > *State\SpanCount - 1
    ClipSetError("Clip visible span index out of range: " + Str(SpanIndex) + ".")
    ProcedureReturn #False
  EndIf
  *span = *State\Spans + SpanIndex * SizeOf(ClipSpan)
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
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

; Aggregate counters: logical width, two sentinel-inclusive range count,
; published span count, storage growth/allocation counts.
Procedure.i ClipStateGetStats(*State.ClipState, *Width.Long, *RangeCount.Long,
                              *SpanCount.Long, *RangeGrowths.Long,
                              *SpanGrowths.Long, *AllocationCount.Long)
  If ClipStateIsValid(*State) = #False
    ClipSetError("Clip state is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Width <> 0
    PokeL(*Width, *State\Width)
  EndIf
  If *RangeCount <> 0
    PokeL(*RangeCount, *State\RangeCount)
  EndIf
  If *SpanCount <> 0
    PokeL(*SpanCount, *State\SpanCount)
  EndIf
  If *RangeGrowths <> 0
    PokeL(*RangeGrowths, *State\RangeGrowths)
  EndIf
  If *SpanGrowths <> 0
    PokeL(*SpanGrowths, *State\SpanGrowths)
  EndIf
  If *AllocationCount <> 0
    PokeL(*AllocationCount, *State\AllocationCount)
  EndIf
  gClip_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
