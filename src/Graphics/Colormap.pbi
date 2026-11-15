; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; COLORMAP decoder. The lump is a sequence of 256-byte tables. Every byte is an
; 8-bit palette index, not RGB data. Applying table m to palette index p yields
; mappedIndex = tables[m * 256 + p]; the palette lookup itself belongs to the
; renderer.
;
; The original R_InitColormaps() only reads the whole lump into memory. DoomPB
; keeps the same raw bytes, adds bounds checks and owns a private copy so the
; result never borrows the caller's WAD buffer.
;
; Ownership:
;   - Colormap is caller-owned and must be zero-initialized once, for example
;     with ClearStructure(@cm, Colormap).
;   - ColormapDecode() owns the table allocation and replaces any previous one.
;   - ColormapReset() frees it and leaves the structure reusable. A failed
;     decode clears the previous data (documented replacement policy).
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_COLORMAP_PBI, #PB_Constant) = 0

#DOOMPB_COLORMAP_PBI = 1

#COLORMAP_TableSize      = 256
#COLORMAP_MaxTables      = 256

#COLORMAP_Magic          = $434F4C31

Structure ColormapSet
  Magic.l
  MapCount.l
  *Tables.Byte
EndStructure

Global gColormap_LastError.s = ""

Procedure ColormapSetError(Message.s)
  gColormap_LastError = Message
EndProcedure

Procedure.s ColormapLastError()
  ProcedureReturn gColormap_LastError
EndProcedure

Procedure.i ColormapReset(*Colormap.ColormapSet)
  If *Colormap = 0
    ColormapSetError("Colormap pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Colormap\Magic = #COLORMAP_Magic
    If *Colormap\Tables <> 0
      FreeMemory(*Colormap\Tables)
    EndIf
  EndIf

  *Colormap\Magic = 0
  *Colormap\MapCount = 0
  *Colormap\Tables = 0
  gColormap_LastError = ""
  ProcedureReturn #True
EndProcedure

; Decodes Length bytes into *Result. Length must be a nonzero multiple of 256.
Procedure.i ColormapDecode(*Bytes.Byte, Length.q, *Result.ColormapSet)
  Protected mapCount.q
  Protected tables.i = 0

  If *Result = 0
    ColormapSetError("Colormap result pointer is null.")
    ProcedureReturn #False
  EndIf

  ColormapReset(*Result)

  If Length <= 0
    ColormapSetError("COLORMAP data length must be nonzero.")
    ProcedureReturn #False
  EndIf
  If Length % #COLORMAP_TableSize <> 0
    ColormapSetError("COLORMAP data length is not a multiple of 256 bytes.")
    ProcedureReturn #False
  EndIf

  mapCount = Length / #COLORMAP_TableSize
  If mapCount > #COLORMAP_MaxTables
    ColormapSetError("COLORMAP contains too many tables: " + Str(mapCount) + " (limit " + Str(#COLORMAP_MaxTables) + ").")
    ProcedureReturn #False
  EndIf

  If *Bytes = 0
    ColormapSetError("COLORMAP data pointer is null.")
    ProcedureReturn #False
  EndIf

  tables = AllocateMemory(Length)
  If tables = 0
    ColormapSetError("Out of memory while decoding COLORMAP.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Bytes, tables, Length)

  *Result\Magic = #COLORMAP_Magic
  *Result\MapCount = mapCount
  *Result\Tables = tables
  gColormap_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i ColormapCount(*Colormap.ColormapSet)
  If *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic
    ColormapSetError("Colormap is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Colormap\MapCount
EndProcedure

; Returns the mapped palette index for (MapIndex, PaletteIndex), or -1 when an
; argument is out of range or the colormap is not initialized.
Procedure.i ColormapLookup(*Colormap.ColormapSet, MapIndex.i, PaletteIndex.i)
  If *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic
    ColormapSetError("Colormap is not initialized.")
    ProcedureReturn -1
  EndIf
  If MapIndex < 0 Or MapIndex >= *Colormap\MapCount
    ColormapSetError("Colormap index out of range: " + Str(MapIndex) + " (count " + Str(*Colormap\MapCount) + ").")
    ProcedureReturn -1
  EndIf
  If PaletteIndex < 0 Or PaletteIndex >= #COLORMAP_TableSize
    ColormapSetError("Palette index out of range: " + Str(PaletteIndex) + ".")
    ProcedureReturn -1
  EndIf

  gColormap_LastError = ""
  ProcedureReturn PeekA(*Colormap\Tables + Int(MapIndex) * #COLORMAP_TableSize + Int(PaletteIndex))
EndProcedure

CompilerEndIf
