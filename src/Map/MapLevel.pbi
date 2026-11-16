; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Composed, validated map level object.
;
; MapLevel owns the ten decoded record sets plus derived integer links:
;   - front/back sector per linedef
;   - front/back sector per seg
;   - sector per subsector
;   - per-sector linedef membership (prefix offsets + flat index list)
;   - BSP root kind/index and reachability diagnostics
;   - REJECT required size and BLOCKMAP cell count
;
; All values are indices/records owned by this object. No pointers into WAD
; buffers, resource catalogs or other temporary storage are retained. Level
; data remains valid after the WAD is closed.
;
; Ownership: caller zero-initializes MapLevel once. Reset frees all sets and
; derived arrays, is idempotent, and leaves an empty reusable object.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_MAPLEVEL_PBI, #PB_Constant) = 0

#DOOMPB_MAPLEVEL_PBI = 1

XIncludeFile "MapTypes.pbi"
XIncludeFile "MapDecode.pbi"
XIncludeFile "Blockmap.pbi"

#MAPLEVEL_Magic = $4D4C5631

Structure MapLevel
  Magic.l
  Ready.l
  MarkerIndex.l
  *FrontSector.Long
  *BackSector.Long
  *SegFrontSector.Long
  *SegBackSector.Long
  *SubsectorSector.Long
  *SectorLineStart.Long
  *SectorLines.Long
  SectorLineTotal.l
  RejectRequired.q
  BlockmapCells.l
  ReachableNodes.l
  ReachableSubsectors.l
  UnreachableNodes.l
  UnreachableSubsectors.l
  BspRootIsSubsector.l
  BspRootIndex.l
  Things.MapThingSet
  Linedefs.MapLinedefSet
  Sidedefs.MapSidedefSet
  Vertexes.MapVertexSet
  Segs.MapSegSet
  Subsectors.MapSubsectorSet
  Nodes.MapNodeSet
  Sectors.MapSectorSet
  Reject.MapReject
  Blockmap.MapBlockmap
EndStructure

Global gMapLevel_LastError.s = ""

Procedure MapLevelSetError(Message.s)
  gMapLevel_LastError = Message
EndProcedure

Procedure.s MapLevelLastError()
  ProcedureReturn gMapLevel_LastError
EndProcedure

Procedure MapLevelReset(*Level.MapLevel)
  If *Level = 0
    MapLevelSetError("Map level pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Level\Magic = #MAPLEVEL_Magic
    If *Level\FrontSector <> 0
      FreeMemory(*Level\FrontSector)
    EndIf
    If *Level\BackSector <> 0
      FreeMemory(*Level\BackSector)
    EndIf
    If *Level\SegFrontSector <> 0
      FreeMemory(*Level\SegFrontSector)
    EndIf
    If *Level\SegBackSector <> 0
      FreeMemory(*Level\SegBackSector)
    EndIf
    If *Level\SubsectorSector <> 0
      FreeMemory(*Level\SubsectorSector)
    EndIf
    If *Level\SectorLineStart <> 0
      FreeMemory(*Level\SectorLineStart)
    EndIf
    If *Level\SectorLines <> 0
      FreeMemory(*Level\SectorLines)
    EndIf
  EndIf

  MapThingsReset(@*Level\Things)
  MapLinedefsReset(@*Level\Linedefs)
  MapSidedefsReset(@*Level\Sidedefs)
  MapVertexesReset(@*Level\Vertexes)
  MapSegsReset(@*Level\Segs)
  MapSubsectorsReset(@*Level\Subsectors)
  MapNodesReset(@*Level\Nodes)
  MapSectorsReset(@*Level\Sectors)
  MapRejectReset(@*Level\Reject)
  MapBlockmapReset(@*Level\Blockmap)

  *Level\Magic = 0
  *Level\Ready = 0
  *Level\MarkerIndex = 0
  *Level\FrontSector = 0
  *Level\BackSector = 0
  *Level\SegFrontSector = 0
  *Level\SegBackSector = 0
  *Level\SubsectorSector = 0
  *Level\SectorLineStart = 0
  *Level\SectorLines = 0
  *Level\SectorLineTotal = 0
  *Level\RejectRequired = 0
  *Level\BlockmapCells = 0
  *Level\ReachableNodes = 0
  *Level\ReachableSubsectors = 0
  *Level\UnreachableNodes = 0
  *Level\UnreachableSubsectors = 0
  *Level\BspRootIsSubsector = 0
  *Level\BspRootIndex = 0
  gMapLevel_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapLevelIsReady(*Level.MapLevel)
  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(*Level\Ready <> 0)
EndProcedure

Procedure.i MapLevelGetLinedefLinks(*Level.MapLevel, LineIndex.i, *FrontSector.Long, *BackSector.Long)
  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic Or *Level\Ready = 0
    MapLevelSetError("Map level is not ready.")
    ProcedureReturn #False
  EndIf
  If LineIndex < 0 Or LineIndex >= *Level\Linedefs\Count
    MapLevelSetError("Linedef index out of range: " + Str(LineIndex) + ".")
    ProcedureReturn #False
  EndIf
  If *FrontSector <> 0
    PokeL(*FrontSector, PeekL(*Level\FrontSector + LineIndex * 4))
  EndIf
  If *BackSector <> 0
    PokeL(*BackSector, PeekL(*Level\BackSector + LineIndex * 4))
  EndIf
  gMapLevel_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapLevelGetSegLinks(*Level.MapLevel, SegIndex.i, *LineIndex.Long, *SideIndex.Long, *FrontSector.Long, *BackSector.Long)
  Protected *item.MapSeg

  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic Or *Level\Ready = 0
    MapLevelSetError("Map level is not ready.")
    ProcedureReturn #False
  EndIf
  If SegIndex < 0 Or SegIndex >= *Level\Segs\Count
    MapLevelSetError("Seg index out of range: " + Str(SegIndex) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Level\Segs\Items + SegIndex * SizeOf(MapSeg)
  If *LineIndex <> 0
    PokeL(*LineIndex, *item\Linedef)
  EndIf
  If *SideIndex <> 0
    PokeL(*SideIndex, *item\Side)
  EndIf
  If *FrontSector <> 0
    PokeL(*FrontSector, PeekL(*Level\SegFrontSector + SegIndex * 4))
  EndIf
  If *BackSector <> 0
    PokeL(*BackSector, PeekL(*Level\SegBackSector + SegIndex * 4))
  EndIf
  gMapLevel_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapLevelGetSubsectorSector(*Level.MapLevel, SubsectorIndex.i)
  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic Or *Level\Ready = 0
    MapLevelSetError("Map level is not ready.")
    ProcedureReturn -1
  EndIf
  If SubsectorIndex < 0 Or SubsectorIndex >= *Level\Subsectors\Count
    MapLevelSetError("Subsector index out of range: " + Str(SubsectorIndex) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekL(*Level\SubsectorSector + SubsectorIndex * 4)
EndProcedure

Procedure.i MapLevelGetBspRoot(*Level.MapLevel, *RootIsSubsector.Long, *RootIndex.Long)
  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic Or *Level\Ready = 0
    MapLevelSetError("Map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *RootIsSubsector <> 0
    PokeL(*RootIsSubsector, *Level\BspRootIsSubsector)
  EndIf
  If *RootIndex <> 0
    PokeL(*RootIndex, *Level\BspRootIndex)
  EndIf
  gMapLevel_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapLevelGetSectorLineCount(*Level.MapLevel, SectorIndex.i)
  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic Or *Level\Ready = 0
    MapLevelSetError("Map level is not ready.")
    ProcedureReturn -1
  EndIf
  If SectorIndex < 0 Or SectorIndex >= *Level\Sectors\Count
    MapLevelSetError("Sector index out of range: " + Str(SectorIndex) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekL(*Level\SectorLineStart + (SectorIndex + 1) * 4) - PeekL(*Level\SectorLineStart + SectorIndex * 4)
EndProcedure

Procedure.i MapLevelGetSectorLine(*Level.MapLevel, SectorIndex.i, LineOrdinal.i, *LineIndex.Long)
  Protected start.l
  Protected count.l

  If *Level = 0 Or *Level\Magic <> #MAPLEVEL_Magic Or *Level\Ready = 0
    MapLevelSetError("Map level is not ready.")
    ProcedureReturn #False
  EndIf
  If SectorIndex < 0 Or SectorIndex >= *Level\Sectors\Count
    MapLevelSetError("Sector index out of range: " + Str(SectorIndex) + ".")
    ProcedureReturn #False
  EndIf
  start = PeekL(*Level\SectorLineStart + SectorIndex * 4)
  count = PeekL(*Level\SectorLineStart + (SectorIndex + 1) * 4) - start
  If LineOrdinal < 0 Or LineOrdinal >= count
    MapLevelSetError("Sector line ordinal out of range: " + Str(LineOrdinal) + ".")
    ProcedureReturn #False
  EndIf
  If *LineIndex <> 0
    PokeL(*LineIndex, PeekL(*Level\SectorLines + (start + LineOrdinal) * 4))
  EndIf
  gMapLevel_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
