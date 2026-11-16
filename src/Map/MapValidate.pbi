; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Cross-reference, derived-link, BSP, REJECT and BLOCKMAP validation for a
; composed map level.
;
; This module consumes the owned record sets from M2-05 and publishes derived
; integer indices only. It never stores pointers into WAD buffers or resource
; catalogs. BSP traversal is iterative with explicit three-state coloring.
;
; Required invariants (vanilla-compatible):
;   - linedef vertices, sidedef sectors and side indices are in range;
;   - a two-sided line has a real back sidedef;
;   - seg side is 0/1 and resolves through its linedef;
;   - subsector ranges are nonempty and inside SEGS;
;   - every BSP child is in range; the graph is acyclic from the last node;
;   - REJECT has at least ceil(sectors^2 / 8) bytes;
;   - every referenced BLOCKMAP line index is inside LINEDEFS.
; Unreachable nodes/subsectors are diagnostics, not hard errors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_MAPVALIDATE_PBI, #PB_Constant) = 0

#DOOMPB_MAPVALIDATE_PBI = 1

XIncludeFile "MapLevel.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "../Graphics/TextureDefs.pbi"

Structure MapSlotNameOut
  Value.s
EndStructure

; Reads one 8-byte flat slot. Returns 0 when *Name holds a name, 2 on a
; canonical error (error text includes map, sector and field).
Procedure.i MapReadFlatSlotName(*Level.MapLevel, SectorIndex.i, Field.i, *Name.MapSlotNameOut)
  Protected byteIndex.i
  Protected value.i
  Protected sawNul.i
  Protected result.s = ""
  Protected fieldName.s
  Protected prefix.s

  If Field = 0
    fieldName = "floor flat"
  Else
    fieldName = "ceiling flat"
  EndIf
  prefix = *Level\Name + " sector " + Str(SectorIndex) + " " + fieldName

  sawNul = #False
  For byteIndex = 0 To 7
    value = MapSectorsNameByte(@*Level\Sectors, SectorIndex, Field, byteIndex)
    If value < 0
      MapLevelSetError(prefix + ": cannot read name bytes.")
      ProcedureReturn 2
    EndIf
    If sawNul
      If value <> 0 And value <> 32
        MapLevelSetError(prefix + " has a noncanonical name (embedded NUL).")
        ProcedureReturn 2
      EndIf
    ElseIf value = 0
      sawNul = #True
    ElseIf value < 32 Or value > 126
      MapLevelSetError(prefix + " has a nonprintable name byte.")
      ProcedureReturn 2
    Else
      result + Chr(value)
    EndIf
  Next

  If Len(result) = 0
    MapLevelSetError(prefix + " is empty.")
    ProcedureReturn 2
  EndIf
  *Name\Value = result
  ProcedureReturn 0
EndProcedure

; Reads one 8-byte wall slot. Returns 0 with a name, 1 for a canonical
; "-"/all-NUL unused slot, 2 on a canonical error.
Procedure.i MapReadWallSlotName(*Level.MapLevel, SideIndex.i, Field.i, *Name.MapSlotNameOut)
  Protected byteIndex.i
  Protected value.i
  Protected sawNul.i
  Protected result.s = ""
  Protected fieldName.s
  Protected prefix.s

  Select Field
    Case 0
      fieldName = "upper texture"
    Case 1
      fieldName = "lower texture"
    Default
      fieldName = "middle texture"
  EndSelect
  prefix = *Level\Name + " sidedef " + Str(SideIndex) + " " + fieldName

  value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, 0)
  If value < 0
    MapLevelSetError(prefix + ": cannot read name bytes.")
    ProcedureReturn 2
  EndIf

  If value = 0 Or value = Asc("-")
    ; Canonical unused slot: the remaining seven bytes must be NUL or space.
    For byteIndex = 1 To 7
      value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, byteIndex)
      If value < 0
        MapLevelSetError(prefix + ": cannot read name bytes.")
        ProcedureReturn 2
      EndIf
      If value <> 0 And value <> 32
        If MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, 0) = Asc("-")
          MapLevelSetError(prefix + " has a noncanonical '-' sentinel (trailing bytes).")
        Else
          MapLevelSetError(prefix + " has a noncanonical empty name (embedded NUL).")
        EndIf
        ProcedureReturn 2
      EndIf
    Next
    *Name\Value = ""
    ProcedureReturn 1
  EndIf

  sawNul = #False
  For byteIndex = 0 To 7
    value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, byteIndex)
    If value < 0
      MapLevelSetError(prefix + ": cannot read name bytes.")
      ProcedureReturn 2
    EndIf
    If sawNul
      If value <> 0 And value <> 32
        MapLevelSetError(prefix + " has a noncanonical name (embedded NUL).")
        ProcedureReturn 2
      EndIf
    ElseIf value = 0
      sawNul = #True
    ElseIf value < 32 Or value > 126
      MapLevelSetError(prefix + " has a nonprintable name byte.")
      ProcedureReturn 2
    Else
      result + Chr(value)
    EndIf
  Next
  *Name\Value = result
  ProcedureReturn 0
EndProcedure

; Optional resource binding; either catalog may be null to skip that category.
Procedure.i MapLevelValidateResources(*Level.MapLevel, *Flats.FlatCatalog, *Textures.TextureCatalog)
  Protected i.i
  Protected field.i
  Protected status.i
  Protected query.s
  Protected nameOut.MapSlotNameOut
  Protected sectorCount.i
  Protected sideCount.i

  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic Or *Level\Ready = 0
    MapLevelSetError("Map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Flats = 0 And *Textures = 0
    gMapLevel_LastError = ""
    ProcedureReturn #True
  EndIf

  sectorCount = *Level\Sectors\Count
  sideCount = *Level\Sidedefs\Count

  If *Flats <> 0
    For i = 0 To sectorCount - 1
      For field = 0 To 1
        nameOut\Value = ""
        status = MapReadFlatSlotName(*Level, i, field, @nameOut)
        If status <> 0
          ProcedureReturn #False
        EndIf
        query = nameOut\Value
        If FlatCatalogFindName(*Flats, query) < 0
          If field = 0
            MapLevelSetError(*Level\Name + " sector " + Str(i) + " floor flat not found: " + query)
          Else
            MapLevelSetError(*Level\Name + " sector " + Str(i) + " ceiling flat not found: " + query)
          EndIf
          ProcedureReturn #False
        EndIf
      Next
    Next
  EndIf

  If *Textures <> 0
    For i = 0 To sideCount - 1
      For field = 0 To 2
        nameOut\Value = ""
        status = MapReadWallSlotName(*Level, i, field, @nameOut)
        If status = 2
          ProcedureReturn #False
        EndIf
        query = nameOut\Value
        If status = 0
          If TextureCatalogFindName(*Textures, query) < 0
            Select field
              Case 0
                MapLevelSetError(*Level\Name + " sidedef " + Str(i) + " upper texture not found: " + query)
              Case 1
                MapLevelSetError(*Level\Name + " sidedef " + Str(i) + " lower texture not found: " + query)
              Default
                MapLevelSetError(*Level\Name + " sidedef " + Str(i) + " middle texture not found: " + query)
            EndSelect
            ProcedureReturn #False
          EndIf
        EndIf
      Next
    Next
  EndIf

  gMapLevel_LastError = ""
  ProcedureReturn #True
EndProcedure

; Validates the decoded sets and fills derived links. Must be called while the
; MapLevel still owns the sets; MapLevelLoad handles transactional cleanup.
Procedure.i MapValidateLevel(*Level.MapLevel)
  Protected lineCount.i
  Protected sideCount.i
  Protected vertexCount.i
  Protected segCount.i
  Protected subCount.i
  Protected nodeCount.i
  Protected sectorCount.i
  Protected *front.Long = 0
  Protected *back.Long = 0
  Protected *segFront.Long = 0
  Protected *segBack.Long = 0
  Protected *subSector.Long = 0
  Protected *lineStart.Long = 0
  Protected *lineList.Long = 0
  Protected *cursor.Long = 0
  Protected totalLines.q = 0
  Protected i.i
  Protected j.i
  Protected v1.l
  Protected v2.l
  Protected flags.l
  Protected special.l
  Protected tag.l
  Protected side0.l
  Protected side1.l
  Protected sectorIdx.l
  Protected frontSector.l
  Protected backSector.l
  Protected itemSide.l
  Protected segLine.l
  Protected segSide.l
  Protected firstSeg.l
  Protected numSegs.l
  Protected child0.l
  Protected child1.l
  Protected rawChild.l
  Protected leafIndex.l
  Protected target.l
  Protected nodeIdx.l
  Protected slot.i
  Protected sp.i
  Protected bspFailure.i = 0
  Protected cycleNode.l = -1
  Protected readNode.l = -1
  Protected *colors.Byte = 0
  Protected *leafSeen.Byte = 0
  Protected *nodeStack.Long = 0
  Protected *slotStack.Byte = 0
  Protected reachableNodes.i = 0
  Protected reachableSubsectors.i = 0
  Protected requiredReject.q
  Protected bitResult.i
  Protected blockWidth.l
  Protected blockHeight.l
  Protected blockCells.q
  Protected cellLineCount.l
  Protected cellLine.l
  Protected totalRefs.q = 0

  If *Level = 0
    MapLevelSetError("Map level pointer is null.")
    ProcedureReturn #False
  EndIf

  lineCount = *Level\Linedefs\Count
  sideCount = *Level\Sidedefs\Count
  vertexCount = *Level\Vertexes\Count
  segCount = *Level\Segs\Count
  subCount = *Level\Subsectors\Count
  nodeCount = *Level\Nodes\Count
  sectorCount = *Level\Sectors\Count

  If vertexCount <= 0 Or lineCount <= 0 Or sideCount <= 0 Or sectorCount <= 0 Or segCount <= 0 Or subCount <= 0
    MapLevelSetError("Map is missing essential geometry (vertices/lines/sides/sectors/segs/subsectors).")
    ProcedureReturn #False
  EndIf

  *front = AllocateMemory(lineCount * 4)
  *back = AllocateMemory(lineCount * 4)
  *segFront = AllocateMemory(segCount * 4)
  *segBack = AllocateMemory(segCount * 4)
  *subSector = AllocateMemory(subCount * 4)
  *lineStart = AllocateMemory((sectorCount + 1) * 4)
  If *front = 0 Or *back = 0 Or *segFront = 0 Or *segBack = 0 Or *subSector = 0 Or *lineStart = 0
    MapLevelSetError("Out of memory while allocating derived map links.")
    If *front <> 0
      FreeMemory(*front)
    EndIf
    If *back <> 0
      FreeMemory(*back)
    EndIf
    If *segFront <> 0
      FreeMemory(*segFront)
    EndIf
    If *segBack <> 0
      FreeMemory(*segBack)
    EndIf
    If *subSector <> 0
      FreeMemory(*subSector)
    EndIf
    If *lineStart <> 0
      FreeMemory(*lineStart)
    EndIf
    ProcedureReturn #False
  EndIf
  FillMemory(*lineStart, (sectorCount + 1) * 4, 0)

  ; SIDEDEFS -> sectors.
  For i = 0 To sideCount - 1
    If MapSidedefsGet(@*Level\Sidedefs, i, 0, 0, @sectorIdx) = #False
      MapLevelSetError("Cannot read sidedef " + Str(i) + ": " + MapDecodeLastError())
      Goto MapValidateCleanup
    EndIf
    If sectorIdx < 0 Or sectorIdx >= sectorCount
      MapLevelSetError("Sidedef " + Str(i) + " references sector " + Str(sectorIdx) + " outside 0.." + Str(sectorCount - 1) + ".")
      Goto MapValidateCleanup
    EndIf
  Next

  ; LINEDEFS -> vertices and sides, derive front/back sectors.
  For i = 0 To lineCount - 1
    If MapLinedefsGet(@*Level\Linedefs, i, @v1, @v2, @flags, @special, @tag, @side0, @side1) = #False
      MapLevelSetError("Cannot read linedef " + Str(i) + ": " + MapDecodeLastError())
      Goto MapValidateCleanup
    EndIf
    If v1 < 0 Or v1 >= vertexCount Or v2 < 0 Or v2 >= vertexCount
      MapLevelSetError("Linedef " + Str(i) + " has vertex references outside 0.." + Str(vertexCount - 1) + ".")
      Goto MapValidateCleanup
    EndIf
    If side0 < 0 Or side0 >= sideCount
      MapLevelSetError("Linedef " + Str(i) + " has an invalid front sidedef " + Str(side0) + ".")
      Goto MapValidateCleanup
    EndIf
    If side1 < -1 Or side1 >= sideCount
      MapLevelSetError("Linedef " + Str(i) + " has an invalid back sidedef " + Str(side1) + ".")
      Goto MapValidateCleanup
    EndIf
    If (flags & #MAP_ML_TWOSIDED) <> 0 And side1 = -1
      MapLevelSetError("Linedef " + Str(i) + " is two-sided but has no back sidedef.")
      Goto MapValidateCleanup
    EndIf

    If MapSidedefsGet(@*Level\Sidedefs, side0, 0, 0, @frontSector) = #False
      MapLevelSetError("Cannot read front sidedef for linedef " + Str(i) + ".")
      Goto MapValidateCleanup
    EndIf
    If side1 >= 0
      If MapSidedefsGet(@*Level\Sidedefs, side1, 0, 0, @backSector) = #False
        MapLevelSetError("Cannot read back sidedef for linedef " + Str(i) + ".")
        Goto MapValidateCleanup
      EndIf
    Else
      backSector = -1
    EndIf
    PokeL(*front + i * 4, frontSector)
    PokeL(*back + i * 4, backSector)
  Next

  ; SEGS -> vertices, linedefs, sides and sectors.
  For i = 0 To segCount - 1
    Protected segV1.l, segV2.l, segAngle.l, segOffset.l
    If MapSegsGet(@*Level\Segs, i, @segV1, @segV2, @segAngle, @segLine, @segSide, @segOffset) = #False
      MapLevelSetError("Cannot read seg " + Str(i) + ": " + MapDecodeLastError())
      Goto MapValidateCleanup
    EndIf
    If segV1 < 0 Or segV1 >= vertexCount Or segV2 < 0 Or segV2 >= vertexCount
      MapLevelSetError("Seg " + Str(i) + " has vertex references outside range.")
      Goto MapValidateCleanup
    EndIf
    If segLine < 0 Or segLine >= lineCount
      MapLevelSetError("Seg " + Str(i) + " references linedef " + Str(segLine) + " outside range.")
      Goto MapValidateCleanup
    EndIf
    If segSide <> 0 And segSide <> 1
      MapLevelSetError("Seg " + Str(i) + " has invalid side " + Str(segSide) + ".")
      Goto MapValidateCleanup
    EndIf
    If MapLinedefsGet(@*Level\Linedefs, segLine, 0, 0, @flags, 0, 0, @side0, @side1) = #False
      MapLevelSetError("Cannot read linedef for seg " + Str(i) + ".")
      Goto MapValidateCleanup
    EndIf
    If segSide = 0
      itemSide = side0
    Else
      itemSide = side1
    EndIf
    If itemSide < 0 Or itemSide >= sideCount
      MapLevelSetError("Seg " + Str(i) + " selects a missing sidedef.")
      Goto MapValidateCleanup
    EndIf
    If MapSidedefsGet(@*Level\Sidedefs, itemSide, 0, 0, @frontSector) = #False
      MapLevelSetError("Cannot read seg sidedef " + Str(i) + ".")
      Goto MapValidateCleanup
    EndIf
    PokeL(*segFront + i * 4, frontSector)
    backSector = -1
    If (flags & #MAP_ML_TWOSIDED) <> 0
      If segSide = 0 And side1 >= 0
        MapSidedefsGet(@*Level\Sidedefs, side1, 0, 0, @backSector)
      ElseIf segSide = 1 And side0 >= 0
        MapSidedefsGet(@*Level\Sidedefs, side0, 0, 0, @backSector)
      EndIf
    EndIf
    PokeL(*segBack + i * 4, backSector)
  Next

  ; SSECTORS -> seg ranges and sector from the first seg.
  For i = 0 To subCount - 1
    If MapSubsectorsGet(@*Level\Subsectors, i, @numSegs, @firstSeg) = #False
      MapLevelSetError("Cannot read subsector " + Str(i) + ".")
      Goto MapValidateCleanup
    EndIf
    If numSegs <= 0
      MapLevelSetError("Subsector " + Str(i) + " has no segs.")
      Goto MapValidateCleanup
    EndIf
    If firstSeg < 0 Or Int(firstSeg) + Int(numSegs) > segCount
      MapLevelSetError("Subsector " + Str(i) + " seg range is outside SEGS.")
      Goto MapValidateCleanup
    EndIf
    PokeL(*subSector + i * 4, PeekL(*segFront + firstSeg * 4))
  Next

  ; Sector line membership (two-pass count/prefix/fill).
  For i = 0 To lineCount - 1
    frontSector = PeekL(*front + i * 4)
    backSector = PeekL(*back + i * 4)
    PokeL(*lineStart + (frontSector + 1) * 4, PeekL(*lineStart + (frontSector + 1) * 4) + 1)
    totalLines + 1
    If backSector >= 0 And backSector <> frontSector
      PokeL(*lineStart + (backSector + 1) * 4, PeekL(*lineStart + (backSector + 1) * 4) + 1)
      totalLines + 1
    EndIf
  Next
  If totalLines > 2000000
    MapLevelSetError("Sector line membership exceeds the safety cap.")
    Goto MapValidateCleanup
  EndIf
  For i = 0 To sectorCount - 1
    PokeL(*lineStart + (i + 1) * 4, PeekL(*lineStart + (i + 1) * 4) + PeekL(*lineStart + i * 4))
  Next
  *lineList = AllocateMemory(totalLines * 4)
  *cursor = AllocateMemory(sectorCount * 4)
  If *lineList = 0 Or *cursor = 0
    MapLevelSetError("Out of memory while building sector line membership.")
    Goto MapValidateCleanup
  EndIf
  CopyMemory(*lineStart, *cursor, sectorCount * 4)
  For i = 0 To lineCount - 1
    frontSector = PeekL(*front + i * 4)
    PokeL(*lineList + PeekL(*cursor + frontSector * 4) * 4, i)
    PokeL(*cursor + frontSector * 4, PeekL(*cursor + frontSector * 4) + 1)
    backSector = PeekL(*back + i * 4)
    If backSector >= 0 And backSector <> frontSector
      PokeL(*lineList + PeekL(*cursor + backSector * 4) * 4, i)
      PokeL(*cursor + backSector * 4, PeekL(*cursor + backSector * 4) + 1)
    EndIf
  Next

  ; BSP child ranges for every node.
  For i = 0 To nodeCount - 1
    If MapNodesGet(@*Level\Nodes, i, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, @child0, @child1) = #False
      MapLevelSetError("Cannot read node " + Str(i) + ".")
      Goto MapValidateCleanup
    EndIf
    For j = 0 To 1
      If j = 0
        rawChild = child0
      Else
        rawChild = child1
      EndIf
      If (rawChild & #MAP_NF_SUBSECTOR) <> 0
        leafIndex = rawChild & $7FFF
        If leafIndex >= subCount
          MapLevelSetError("Node " + Str(i) + " child " + Str(j) + " references missing subsector " + Str(leafIndex) + ".")
          Goto MapValidateCleanup
        EndIf
      Else
        If rawChild >= nodeCount
          MapLevelSetError("Node " + Str(i) + " child " + Str(j) + " references missing node " + Str(rawChild) + ".")
          Goto MapValidateCleanup
        EndIf
      EndIf
    Next
  Next

  ; Iterative DFS from the last node (or the one-subsector special case).
  If nodeCount = 0
    If subCount <> 1
      MapLevelSetError("Zero-node map requires exactly one subsector.")
      Goto MapValidateCleanup
    EndIf
    reachableSubsectors = 1
    *Level\BspRootIsSubsector = 1
    *Level\BspRootIndex = 0
    *Level\UnreachableNodes = 0
    *Level\UnreachableSubsectors = subCount - 1
  Else
    *colors = AllocateMemory(nodeCount)
    *leafSeen = AllocateMemory(subCount)
    *nodeStack = AllocateMemory(nodeCount * 4)
    *slotStack = AllocateMemory(nodeCount)
    If *colors = 0 Or *leafSeen = 0 Or *nodeStack = 0 Or *slotStack = 0
      MapLevelSetError("Out of memory while validating BSP reachability.")
      Goto MapValidateCleanup
    EndIf
    FillMemory(*colors, nodeCount, 0)
    FillMemory(*leafSeen, subCount, 0)

    nodeIdx = nodeCount - 1
    PokeA(*colors + nodeIdx, 1)
    PokeL(*nodeStack, nodeIdx)
    PokeA(*slotStack, 0)
    sp = 0
    bspFailure = 0
    cycleNode = -1
    readNode = -1
    While sp >= 0 And bspFailure = 0
      nodeIdx = PeekL(*nodeStack + sp * 4)
      slot = PeekA(*slotStack + sp)
      If slot < 2
        PokeA(*slotStack + sp, slot + 1)
        If MapNodesGet(@*Level\Nodes, nodeIdx, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, @child0, @child1) = #False
          bspFailure = 1
          readNode = nodeIdx
        Else
          If slot = 0
            rawChild = child0
          Else
            rawChild = child1
          EndIf
          If (rawChild & #MAP_NF_SUBSECTOR) <> 0
            leafIndex = rawChild & $7FFF
            If PeekA(*leafSeen + leafIndex) = 0
              PokeA(*leafSeen + leafIndex, 1)
              reachableSubsectors + 1
            EndIf
          Else
            target = rawChild
            Select PeekA(*colors + target)
              Case 1
                bspFailure = 1
                cycleNode = target
              Case 0
                PokeA(*colors + target, 1)
                sp + 1
                PokeL(*nodeStack + sp * 4, target)
                PokeA(*slotStack + sp, 0)
            EndSelect
          EndIf
        EndIf
      Else
        PokeA(*colors + nodeIdx, 2)
        reachableNodes + 1
        sp - 1
      EndIf
    Wend
    If bspFailure
      If readNode >= 0
        MapLevelSetError("Cannot read node " + Str(readNode) + " during BSP traversal.")
      Else
        MapLevelSetError("BSP cycle detected at node " + Str(cycleNode) + ".")
      EndIf
      Goto MapValidateCleanup
    EndIf
    *Level\BspRootIsSubsector = 0
    *Level\BspRootIndex = nodeCount - 1
    *Level\UnreachableNodes = nodeCount - reachableNodes
    *Level\UnreachableSubsectors = subCount - reachableSubsectors
  EndIf

  ; REJECT size and a few safe matrix probes.
  requiredReject = (Int(sectorCount) * Int(sectorCount) + 7) / 8
  If *Level\Reject\Size < requiredReject
    MapLevelSetError("REJECT is too short: " + Str(*Level\Reject\Size) + " bytes, need " + Str(requiredReject) + ".")
    Goto MapValidateCleanup
  EndIf
  bitResult = MapRejectGetBit(@*Level\Reject, sectorCount, 0, 0)
  If bitResult < 0
    MapLevelSetError("REJECT matrix probe failed: " + MapDecodeLastError())
    Goto MapValidateCleanup
  EndIf
  If sectorCount > 1
    If MapRejectGetBit(@*Level\Reject, sectorCount, sectorCount - 1, sectorCount - 1) < 0
      MapLevelSetError("REJECT last-sector probe failed.")
      Goto MapValidateCleanup
    EndIf
  EndIf
  If sectorCount > 8
    If MapRejectGetBit(@*Level\Reject, sectorCount, 0, 8) < 0
      MapLevelSetError("REJECT cross-byte probe failed.")
      Goto MapValidateCleanup
    EndIf
  EndIf
  *Level\RejectRequired = requiredReject

  ; BLOCKMAP line references.
  If MapBlockmapHeader(@*Level\Blockmap, 0, 0, @blockWidth, @blockHeight) = #False
    MapLevelSetError("Cannot read BLOCKMAP header: " + MapBlockmapLastError())
    Goto MapValidateCleanup
  EndIf
  blockCells = Int(blockWidth) * Int(blockHeight)
  If blockCells <= 0 Or blockCells > #MAP_MaxBlockmapCells
    MapLevelSetError("BLOCKMAP cell count is invalid: " + Str(blockCells) + ".")
    Goto MapValidateCleanup
  EndIf
  For i = 0 To blockHeight - 1
    For j = 0 To blockWidth - 1
      If MapBlockmapGetCell(@*Level\Blockmap, j, i, 0, @cellLineCount, 0) = #False
        MapLevelSetError("Cannot read BLOCKMAP cell " + Str(j) + "," + Str(i) + ": " + MapBlockmapLastError())
        Goto MapValidateCleanup
      EndIf
      totalRefs + cellLineCount
      If totalRefs > 16000000
        MapLevelSetError("BLOCKMAP line-reference scan exceeds the work budget.")
        Goto MapValidateCleanup
      EndIf
      For target = 0 To cellLineCount - 1
        If MapBlockmapGetLine(@*Level\Blockmap, j, i, target, @cellLine) = #False
          MapLevelSetError("Cannot read BLOCKMAP line reference.")
          Goto MapValidateCleanup
        EndIf
        If cellLine < 0 Or cellLine >= lineCount
          MapLevelSetError("BLOCKMAP references linedef " + Str(cellLine) + " outside 0.." + Str(lineCount - 1) + ".")
          Goto MapValidateCleanup
        EndIf
      Next
    Next
  Next
  *Level\BlockmapCells = blockCells

  *Level\FrontSector = *front
  *Level\BackSector = *back
  *Level\SegFrontSector = *segFront
  *Level\SegBackSector = *segBack
  *Level\SubsectorSector = *subSector
  *Level\SectorLineStart = *lineStart
  *Level\SectorLines = *lineList
  *Level\SectorLineTotal = totalLines
  *Level\ReachableNodes = reachableNodes
  *Level\ReachableSubsectors = reachableSubsectors
  *Level\Magic = #MAPLEVEL_Magic
  *Level\Ready = 1
  If *cursor <> 0
    FreeMemory(*cursor)
  EndIf
  If *colors <> 0
    FreeMemory(*colors)
  EndIf
  If *leafSeen <> 0
    FreeMemory(*leafSeen)
  EndIf
  If *nodeStack <> 0
    FreeMemory(*nodeStack)
  EndIf
  If *slotStack <> 0
    FreeMemory(*slotStack)
  EndIf
  gMapLevel_LastError = ""
  ProcedureReturn #True

MapValidateCleanup:
  If *front <> 0
    FreeMemory(*front)
  EndIf
  If *back <> 0
    FreeMemory(*back)
  EndIf
  If *segFront <> 0
    FreeMemory(*segFront)
  EndIf
  If *segBack <> 0
    FreeMemory(*segBack)
  EndIf
  If *subSector <> 0
    FreeMemory(*subSector)
  EndIf
  If *lineStart <> 0
    FreeMemory(*lineStart)
  EndIf
  If *lineList <> 0
    FreeMemory(*lineList)
  EndIf
  If *cursor <> 0
    FreeMemory(*cursor)
  EndIf
  If *colors <> 0
    FreeMemory(*colors)
  EndIf
  If *leafSeen <> 0
    FreeMemory(*leafSeen)
  EndIf
  If *nodeStack <> 0
    FreeMemory(*nodeStack)
  EndIf
  If *slotStack <> 0
    FreeMemory(*slotStack)
  EndIf
  ProcedureReturn #False
EndProcedure

CompilerEndIf
