; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Vanilla map loader: locate a map marker, verify the adjacent ten lump order,
; read and decode each payload through M2-05, then publish a validated level.
;
; The currently open WAD is used; no second parser or path construction occurs.
; Load is transactional: any failure resets the target level completely.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_MAPLOADER_PBI, #PB_Constant) = 0

#DOOMPB_MAPLOADER_PBI = 1

XIncludeFile "../WAD/WAD.pbi"
XIncludeFile "MapLevel.pbi"
XIncludeFile "MapValidate.pbi"

; Canonicalizes "E#M#"-style map names. Only four ASCII characters are
; accepted; MAPxx and Unicode names are outside this task.
Procedure.s MapCanonicalName(Name.s)
  Protected first.s
  Protected third.s

  If Len(Name) <> 4
    ProcedureReturn ""
  EndIf
  first = UCase(Mid(Name, 1, 1))
  third = UCase(Mid(Name, 3, 1))
  If first <> "E" Or third <> "M"
    ProcedureReturn ""
  EndIf
  If Mid(Name, 2, 1) < "0" Or Mid(Name, 2, 1) > "9"
    ProcedureReturn ""
  EndIf
  If Mid(Name, 4, 1) < "0" Or Mid(Name, 4, 1) > "9"
    ProcedureReturn ""
  EndIf
  ProcedureReturn first + Mid(Name, 2, 1) + third + Mid(Name, 4, 1)
EndProcedure

Procedure.i WadEntryNameEquals(EntryIndex.i, Expected.s)
  Protected i.i
  Protected value.i

  For i = 0 To 7
    If i < Len(Expected)
      value = Asc(Mid(Expected, i + 1, 1))
    Else
      value = 0
    EndIf
    If WADLumpRawNameByte(EntryIndex, i) <> value
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

; Loads Name ("E1M1") from the currently open WAD into *Level.
Procedure.i MapLevelLoad(Name.s, *Level.MapLevel)
  Protected canonical.s
  Protected markerIndex.i
  Protected lumpIndex.i
  Protected i.i
  Protected size.q
  Protected bytes.i = 0
  Protected ok.i = #False
  Protected failureText.s
  Protected Dim expected.s(10)

  If *Level = 0
    MapLevelSetError("Map level pointer is null.")
    ProcedureReturn #False
  EndIf
  MapLevelReset(*Level)

  If WADIsOpen() = #False
    MapLevelSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf
  canonical = MapCanonicalName(Name)
  If canonical = ""
    MapLevelSetError("Invalid map name: expected four ASCII characters like E1M1.")
    ProcedureReturn #False
  EndIf

  markerIndex = WADFindLump(canonical)
  If markerIndex < 0
    MapLevelSetError("Map marker not found: " + canonical)
    ProcedureReturn #False
  EndIf
  If WADLumpSize(markerIndex) <> 0
    MapLevelSetError("Map marker " + canonical + " is not a zero-length lump.")
    ProcedureReturn #False
  EndIf
  If Int(markerIndex) + 10 >= WADGetLumpCount()
    MapLevelSetError("Map " + canonical + " is truncated by end of directory.")
    ProcedureReturn #False
  EndIf

  expected(1) = "THINGS"
  expected(2) = "LINEDEFS"
  expected(3) = "SIDEDEFS"
  expected(4) = "VERTEXES"
  expected(5) = "SEGS"
  expected(6) = "SSECTORS"
  expected(7) = "NODES"
  expected(8) = "SECTORS"
  expected(9) = "REJECT"
  expected(10) = "BLOCKMAP"

  For i = 1 To 10
    lumpIndex = markerIndex + i
    If WadEntryNameEquals(lumpIndex, expected(i)) = #False
      MapLevelSetError("Map " + canonical + " lump +" + Str(i) + " is not " + expected(i) + ".")
      Goto MapLoadFail
    EndIf
  Next

  ; THINGS
  size = WADLumpSize(markerIndex + 1)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading THINGS.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 1, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read THINGS: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapThingsDecode(bytes, size, @*Level\Things)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode THINGS: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; LINEDEFS
  size = WADLumpSize(markerIndex + 2)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading LINEDEFS.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 2, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read LINEDEFS: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapLinedefsDecode(bytes, size, @*Level\Linedefs)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode LINEDEFS: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; SIDEDEFS
  size = WADLumpSize(markerIndex + 3)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading SIDEDEFS.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 3, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read SIDEDEFS: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapSidedefsDecode(bytes, size, @*Level\Sidedefs)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode SIDEDEFS: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; VERTEXES
  size = WADLumpSize(markerIndex + 4)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading VERTEXES.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 4, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read VERTEXES: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapVertexesDecode(bytes, size, @*Level\Vertexes)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode VERTEXES: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; SEGS
  size = WADLumpSize(markerIndex + 5)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading SEGS.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 5, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read SEGS: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapSegsDecode(bytes, size, @*Level\Segs)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode SEGS: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; SSECTORS
  size = WADLumpSize(markerIndex + 6)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading SSECTORS.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 6, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read SSECTORS: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapSubsectorsDecode(bytes, size, @*Level\Subsectors)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode SSECTORS: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; NODES
  size = WADLumpSize(markerIndex + 7)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading NODES.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 7, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read NODES: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapNodesDecode(bytes, size, @*Level\Nodes)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode NODES: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; SECTORS
  size = WADLumpSize(markerIndex + 8)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading SECTORS.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 8, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read SECTORS: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapSectorsDecode(bytes, size, @*Level\Sectors)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode SECTORS: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; REJECT
  size = WADLumpSize(markerIndex + 9)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading REJECT.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 9, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read REJECT: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapRejectDecode(bytes, size, @*Level\Reject)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode REJECT: " + MapDecodeLastError())
    Goto MapLoadFail
  EndIf

  ; BLOCKMAP
  size = WADLumpSize(markerIndex + 10)
  If size > 0
    bytes = AllocateMemory(size)
    If bytes = 0
      MapLevelSetError("Out of memory reading BLOCKMAP.")
      Goto MapLoadFail
    EndIf
    If WADReadLump(markerIndex + 10, bytes, size) = #False
      FreeMemory(bytes)
      bytes = 0
      MapLevelSetError("Cannot read BLOCKMAP: " + WADLastError())
      Goto MapLoadFail
    EndIf
  EndIf
  ok = MapBlockmapDecode(bytes, size, @*Level\Blockmap)
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  If ok = #False
    MapLevelSetError("Cannot decode BLOCKMAP: " + MapBlockmapLastError())
    Goto MapLoadFail
  EndIf

  *Level\MarkerIndex = markerIndex
  If MapValidateLevel(*Level) = #False
    Goto MapLoadFail
  EndIf

  gMapLevel_LastError = ""
  ProcedureReturn #True

MapLoadFail:
  failureText = MapLevelLastError()
  If bytes <> 0
    FreeMemory(bytes)
    bytes = 0
  EndIf
  MapLevelReset(*Level)
  MapLevelSetError(failureText)
  ProcedureReturn #False
EndProcedure

CompilerEndIf
