; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; BLOCKMAP decoder and checked accessors.
;
; Layout: four LE16 header words (originX:s16, originY:s16, width:u16,
; height:u16), width*height unsigned 16-bit offsets measured in WORDS from the
; start of the lump, then variable blocklists. Each referenced list starts with
; a zero dummy word, contains zero or more line indexes, and ends with 0xFFFF.
; Multiple cells may share one list; offsets need not be sorted or contiguous.
;
; DoomPB validates every referenced list at decode time (within a work budget)
; and keeps an owned copy of the entire lump. It deliberately does not validate
; line indexes against LINEDEFS; M2-06 owns that cross-lump check.
;
; Ownership: caller zero-initializes MapBlockmap once; decode owns the copy;
; reset frees it and is idempotent. Failed decode leaves an empty object.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_BLOCKMAP_PBI, #PB_Constant) = 0

#DOOMPB_BLOCKMAP_PBI = 1

XIncludeFile "../Core/Endian.pbi"
XIncludeFile "MapTypes.pbi"

Global gBlockmap_LastError.s = ""

Procedure MapBlockmapSetError(Message.s)
  gBlockmap_LastError = Message
EndProcedure

Procedure.s MapBlockmapLastError()
  ProcedureReturn gBlockmap_LastError
EndProcedure

Procedure.i MapBlockmapReset(*Set.MapBlockmap)
  If *Set = 0
    MapBlockmapSetError("BLOCKMAP result pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Set\Magic = #MAP_BlockmapMagic
    If *Set\Bytes <> 0
      FreeMemory(*Set\Bytes)
    EndIf
  EndIf

  *Set\Magic = 0
  *Set\OriginX = 0
  *Set\OriginY = 0
  *Set\Width = 0
  *Set\Height = 0
  *Set\Size = 0
  *Set\Bytes = 0
  gBlockmap_LastError = ""
  ProcedureReturn #True
EndProcedure

; Local signed reader kept here to avoid widening the generic map API.
Procedure.i MapReadI16(*Data.Byte, Offset.i)
  Protected value.i = EndianReadU16LE(*Data, Offset)

  If value >= $8000
    value = value - $10000
  EndIf
  ProcedureReturn value
EndProcedure

Procedure.i MapBlockmapDecode(*Bytes.Byte, Length.q, *Result.MapBlockmap)
  Protected width.q
  Protected height.q
  Protected cells.q
  Protected tableEnd.q
  Protected memory.i
  Protected copy.i
  Protected cell.i
  Protected offsetWords.i
  Protected position.q
  Protected word.i
  Protected scanned.q = 0

  If *Result = 0
    MapBlockmapSetError("BLOCKMAP result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapBlockmapReset(*Result)

  If Length < 8
    MapBlockmapSetError("BLOCKMAP is shorter than its 8-byte header.")
    ProcedureReturn #False
  EndIf
  If Length % 2 <> 0
    MapBlockmapSetError("BLOCKMAP byte length is odd.")
    ProcedureReturn #False
  EndIf
  If *Bytes = 0
    MapBlockmapSetError("BLOCKMAP data pointer is null.")
    ProcedureReturn #False
  EndIf

  width = EndianReadU16LE(*Bytes, 4)
  height = EndianReadU16LE(*Bytes, 6)
  If width <= 0 Or height <= 0
    MapBlockmapSetError("BLOCKMAP dimensions must be positive.")
    ProcedureReturn #False
  EndIf
  cells = width * height
  If cells > #MAP_MaxBlockmapCells
    MapBlockmapSetError("BLOCKMAP cell count exceeds the cap: " + Str(cells) + ".")
    ProcedureReturn #False
  EndIf
  tableEnd = Int(8) + cells * 2
  If tableEnd > Length
    MapBlockmapSetError("BLOCKMAP offset table is truncated: needs " + Str(tableEnd) + " bytes.")
    ProcedureReturn #False
  EndIf

  ; Copy first, then validate lists against the private copy.
  copy = AllocateMemory(Length)
  If copy = 0
    MapBlockmapSetError("Out of memory while copying BLOCKMAP.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Bytes, copy, Length)

  For cell = 0 To cells - 1
    offsetWords = EndianReadU16LE(copy, 8 + cell * 2)
    position = Int(offsetWords) * 2
    If position < tableEnd
      FreeMemory(copy)
      MapBlockmapSetError("BLOCKMAP cell " + Str(cell) + " offset points inside the header/table.")
      ProcedureReturn #False
    EndIf
    If position + 4 > Length
      FreeMemory(copy)
      MapBlockmapSetError("BLOCKMAP cell " + Str(cell) + " offset leaves no room for a list.")
      ProcedureReturn #False
    EndIf
    word = EndianReadU16LE(copy, position)
    scanned + 1
    If word <> 0
      FreeMemory(copy)
      MapBlockmapSetError("BLOCKMAP cell " + Str(cell) + " list does not start with a zero dummy word.")
      ProcedureReturn #False
    EndIf
    position + 2
    While #True
      If position + 2 > Length
        FreeMemory(copy)
        MapBlockmapSetError("BLOCKMAP cell " + Str(cell) + " list is truncated without 0xFFFF.")
        ProcedureReturn #False
      EndIf
      word = EndianReadU16LE(copy, position)
      scanned + 1
      position + 2
      If word = $FFFF
        Break
      EndIf
      If scanned > #MAP_MaxBlockmapScanWords
        FreeMemory(copy)
        MapBlockmapSetError("BLOCKMAP list validation exceeded the work budget.")
        ProcedureReturn #False
      EndIf
    Wend
    If scanned > #MAP_MaxBlockmapScanWords
      FreeMemory(copy)
      MapBlockmapSetError("BLOCKMAP list validation exceeded the work budget.")
      ProcedureReturn #False
    EndIf
  Next

  *Result\Magic = #MAP_BlockmapMagic
  *Result\OriginX = MapReadI16(copy, 0)
  *Result\OriginY = MapReadI16(copy, 2)
  *Result\Width = width
  *Result\Height = height
  *Result\Size = Length
  *Result\Bytes = copy
  gBlockmap_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapBlockmapHeader(*Set.MapBlockmap, *OriginX.Long, *OriginY.Long, *Width.Long, *Height.Long)
  If *Set = 0 Or *Set\Magic <> #MAP_BlockmapMagic
    MapBlockmapSetError("BLOCKMAP is not initialized.")
    ProcedureReturn #False
  EndIf
  If *OriginX <> 0
    PokeL(*OriginX, *Set\OriginX)
  EndIf
  If *OriginY <> 0
    PokeL(*OriginY, *Set\OriginY)
  EndIf
  If *Width <> 0
    PokeL(*Width, *Set\Width)
  EndIf
  If *Height <> 0
    PokeL(*Height, *Set\Height)
  EndIf
  gBlockmap_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapBlockmapCellPosition(*Set.MapBlockmap, X.i, Y.i)
  Protected cell.q
  Protected offsetWords.i

  If *Set = 0 Or *Set\Magic <> #MAP_BlockmapMagic
    MapBlockmapSetError("BLOCKMAP is not initialized.")
    ProcedureReturn -1
  EndIf
  If X < 0 Or Y < 0 Or X >= *Set\Width Or Y >= *Set\Height
    MapBlockmapSetError("BLOCKMAP cell coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn -1
  EndIf
  cell = Int(Y) * Int(*Set\Width) + Int(X)
  offsetWords = EndianReadU16LE(*Set\Bytes, 8 + cell * 2)
  ProcedureReturn Int(offsetWords) * 2
EndProcedure

; Returns the number of line references in the cell's list (dummy and 0xFFFF
; excluded).
Procedure.i MapBlockmapGetCell(*Set.MapBlockmap, X.i, Y.i, *OffsetWords.Long, *LineCount.Long, *FirstLineByte.Long)
  Protected position.q
  Protected word.i
  Protected count.q = 0

  position = MapBlockmapCellPosition(*Set, X, Y)
  If position < 0
    ProcedureReturn #False
  EndIf
  If *OffsetWords <> 0
    PokeL(*OffsetWords, position / 2)
  EndIf
  position + 2   ; skip dummy
  While position + 2 <= *Set\Size
    word = EndianReadU16LE(*Set\Bytes, position)
    If word = $FFFF
      Break
    EndIf
    count + 1
    position + 2
  Wend
  If *LineCount <> 0
    PokeL(*LineCount, count)
  EndIf
  If *FirstLineByte <> 0
    PokeL(*FirstLineByte, MapBlockmapCellPosition(*Set, X, Y) + 2)
  EndIf
  gBlockmap_LastError = ""
  ProcedureReturn #True
EndProcedure

; LineIndex is zero-based within the blocklist (dummy excluded).
Procedure.i MapBlockmapGetLine(*Set.MapBlockmap, X.i, Y.i, LineIndex.i, *Linedef.Long)
  Protected position.q
  Protected word.i
  Protected index.i = 0

  position = MapBlockmapCellPosition(*Set, X, Y)
  If position < 0
    ProcedureReturn #False
  EndIf
  If LineIndex < 0
    MapBlockmapSetError("BLOCKMAP line index is negative.")
    ProcedureReturn #False
  EndIf
  position + 2
  While position + 2 <= *Set\Size
    word = EndianReadU16LE(*Set\Bytes, position)
    If word = $FFFF
      MapBlockmapSetError("BLOCKMAP line index out of range: " + Str(LineIndex) + ".")
      ProcedureReturn #False
    EndIf
    If index = LineIndex
      If *Linedef <> 0
        PokeL(*Linedef, word)
      EndIf
      gBlockmap_LastError = ""
      ProcedureReturn #True
    EndIf
    index + 1
    position + 2
  Wend
  MapBlockmapSetError("BLOCKMAP list is truncated.")
  ProcedureReturn #False
EndProcedure

CompilerEndIf
