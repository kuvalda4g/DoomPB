; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Decoders for the eight fixed-record vanilla map lumps plus REJECT.
;
; Every decoder validates the exact record stride before allocation, decodes
; fields explicitly as little-endian, and stores native structures. Signed and
; unsigned 16-bit fields are converted according to doomdata.h semantics.
; Cross-lump references (vertex/sector/side indices, BSP child ranges) are NOT
; validated here; M2-06 owns that pass.
;
; Ownership: result objects are caller-owned and zero-initialized once. Decode
; owns a private record array; Reset frees it and is idempotent. A failed decode
; clears previous data. Results remain valid after the source buffer is freed.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_MAPDECODE_PBI, #PB_Constant) = 0

#DOOMPB_MAPDECODE_PBI = 1

XIncludeFile "../Core/Endian.pbi"
XIncludeFile "MapTypes.pbi"

Global gMapDecode_LastError.s = ""

Procedure MapDecodeSetError(Message.s)
  gMapDecode_LastError = Message
EndProcedure

Procedure.s MapDecodeLastError()
  ProcedureReturn gMapDecode_LastError
EndProcedure

Procedure.i MapReadI16LE(*Data.Byte, Offset.i)
  Protected value.i = EndianReadU16LE(*Data, Offset)

  If value >= $8000
    value = value - $10000
  EndIf
  ProcedureReturn value
EndProcedure

; ---------------------------------------------------------------------------
; THINGS
; ---------------------------------------------------------------------------

Procedure.i MapThingsReset(*Set.MapThingSet)
  If *Set = 0
    MapDecodeSetError("THINGS result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapThingsDecode(*Bytes.Byte, Length.q, *Result.MapThingSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapThing

  If *Result = 0
    MapDecodeSetError("THINGS result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapThingsReset(*Result)
  If Length < 0
    MapDecodeSetError("THINGS length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_ThingSize <> 0
    MapDecodeSetError("THINGS length is not a multiple of 10 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_ThingSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("THINGS record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("THINGS data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapThing))
    If items = 0
      MapDecodeSetError("Out of memory while decoding THINGS.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_ThingSize
      *item = items + i * SizeOf(MapThing)
      *item\X = MapReadI16LE(*Bytes, offset)
      *item\Y = MapReadI16LE(*Bytes, offset + 2)
      *item\Angle = MapReadI16LE(*Bytes, offset + 4)
      *item\Type = MapReadI16LE(*Bytes, offset + 6)
      *item\Options = MapReadI16LE(*Bytes, offset + 8)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapThingsCount(*Set.MapThingSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("THINGS set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapThingsGet(*Set.MapThingSet, Index.i, *X.Long, *Y.Long, *Angle.Long, *Type.Long, *Options.Long)
  Protected *item.MapThing

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("THINGS set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("THINGS index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapThing)
  If *X <> 0
    PokeL(*X, *item\X)
  EndIf
  If *Y <> 0
    PokeL(*Y, *item\Y)
  EndIf
  If *Angle <> 0
    PokeL(*Angle, *item\Angle)
  EndIf
  If *Type <> 0
    PokeL(*Type, *item\Type)
  EndIf
  If *Options <> 0
    PokeL(*Options, *item\Options)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; LINEDEFS
; ---------------------------------------------------------------------------

Procedure.i MapLinedefsReset(*Set.MapLinedefSet)
  If *Set = 0
    MapDecodeSetError("LINEDEFS result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapLinedefsDecode(*Bytes.Byte, Length.q, *Result.MapLinedefSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapLinedef

  If *Result = 0
    MapDecodeSetError("LINEDEFS result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapLinedefsReset(*Result)
  If Length < 0
    MapDecodeSetError("LINEDEFS length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_LinedefSize <> 0
    MapDecodeSetError("LINEDEFS length is not a multiple of 14 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_LinedefSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("LINEDEFS record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("LINEDEFS data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapLinedef))
    If items = 0
      MapDecodeSetError("Out of memory while decoding LINEDEFS.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_LinedefSize
      *item = items + i * SizeOf(MapLinedef)
      *item\V1 = EndianReadU16LE(*Bytes, offset)
      *item\V2 = EndianReadU16LE(*Bytes, offset + 2)
      *item\Flags = EndianReadU16LE(*Bytes, offset + 4)
      *item\Special = MapReadI16LE(*Bytes, offset + 6)
      *item\Tag = MapReadI16LE(*Bytes, offset + 8)
      *item\Side0 = MapReadI16LE(*Bytes, offset + 10)
      *item\Side1 = MapReadI16LE(*Bytes, offset + 12)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapLinedefsCount(*Set.MapLinedefSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("LINEDEFS set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapLinedefsGet(*Set.MapLinedefSet, Index.i, *V1.Long, *V2.Long, *Flags.Long, *Special.Long, *Tag.Long, *Side0.Long, *Side1.Long)
  Protected *item.MapLinedef

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("LINEDEFS set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("LINEDEFS index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapLinedef)
  If *V1 <> 0
    PokeL(*V1, *item\V1)
  EndIf
  If *V2 <> 0
    PokeL(*V2, *item\V2)
  EndIf
  If *Flags <> 0
    PokeL(*Flags, *item\Flags)
  EndIf
  If *Special <> 0
    PokeL(*Special, *item\Special)
  EndIf
  If *Tag <> 0
    PokeL(*Tag, *item\Tag)
  EndIf
  If *Side0 <> 0
    PokeL(*Side0, *item\Side0)
  EndIf
  If *Side1 <> 0
    PokeL(*Side1, *item\Side1)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; SIDEDEFS
; ---------------------------------------------------------------------------

Procedure.i MapSidedefsReset(*Set.MapSidedefSet)
  If *Set = 0
    MapDecodeSetError("SIDEDEFS result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSidedefsDecode(*Bytes.Byte, Length.q, *Result.MapSidedefSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapSidedef

  If *Result = 0
    MapDecodeSetError("SIDEDEFS result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapSidedefsReset(*Result)
  If Length < 0
    MapDecodeSetError("SIDEDEFS length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_SidedefSize <> 0
    MapDecodeSetError("SIDEDEFS length is not a multiple of 30 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_SidedefSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("SIDEDEFS record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("SIDEDEFS data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapSidedef))
    If items = 0
      MapDecodeSetError("Out of memory while decoding SIDEDEFS.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_SidedefSize
      *item = items + i * SizeOf(MapSidedef)
      *item\TextureOffset = MapReadI16LE(*Bytes, offset)
      *item\RowOffset = MapReadI16LE(*Bytes, offset + 2)
      CopyMemory(*Bytes + offset + 4, @*item\TopTexture[0], 8)
      CopyMemory(*Bytes + offset + 12, @*item\BottomTexture[0], 8)
      CopyMemory(*Bytes + offset + 20, @*item\MidTexture[0], 8)
      *item\Sector = EndianReadU16LE(*Bytes, offset + 28)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSidedefsCount(*Set.MapSidedefSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SIDEDEFS set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapSidedefsGet(*Set.MapSidedefSet, Index.i, *TextureOffset.Long, *RowOffset.Long, *Sector.Long)
  Protected *item.MapSidedef

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SIDEDEFS set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SIDEDEFS index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapSidedef)
  If *TextureOffset <> 0
    PokeL(*TextureOffset, *item\TextureOffset)
  EndIf
  If *RowOffset <> 0
    PokeL(*RowOffset, *item\RowOffset)
  EndIf
  If *Sector <> 0
    PokeL(*Sector, *item\Sector)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSidedefsNameByte(*Set.MapSidedefSet, Index.i, Field.i, ByteOffset.i)
  Protected *item.MapSidedef
  Protected *name.Byte

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SIDEDEFS set is not initialized.")
    ProcedureReturn -1
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SIDEDEFS index out of range: " + Str(Index) + ".")
    ProcedureReturn -1
  EndIf
  If Field < 0 Or Field > 2
    MapDecodeSetError("SIDEDEFS name field out of range: " + Str(Field) + ".")
    ProcedureReturn -1
  EndIf
  If ByteOffset < 0 Or ByteOffset > 7
    MapDecodeSetError("SIDEDEFS name byte offset out of range: " + Str(ByteOffset) + ".")
    ProcedureReturn -1
  EndIf
  *item = *Set\Items + Index * SizeOf(MapSidedef)
  Select Field
    Case 0
      *name = @*item\TopTexture[0]
    Case 1
      *name = @*item\BottomTexture[0]
    Default
      *name = @*item\MidTexture[0]
  EndSelect
  ProcedureReturn PeekA(*name + ByteOffset)
EndProcedure

Procedure.s MapSidedefsDisplayName(*Set.MapSidedefSet, Index.i, Field.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SIDEDEFS set is not initialized.")
    ProcedureReturn ""
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SIDEDEFS index out of range: " + Str(Index) + ".")
    ProcedureReturn ""
  EndIf
  If Field < 0 Or Field > 2
    MapDecodeSetError("SIDEDEFS name field out of range: " + Str(Field) + ".")
    ProcedureReturn ""
  EndIf
  For i = 0 To 7
    value = MapSidedefsNameByte(*Set, Index, Field, i)
    If value < 0
      ProcedureReturn ""
    EndIf
    If value = 0
      Break
    EndIf
    If value >= 32 And value <= 126
      result + Chr(value)
    Else
      result + "."
    EndIf
  Next
  gMapDecode_LastError = ""
  ProcedureReturn result
EndProcedure

; ---------------------------------------------------------------------------
; VERTEXES
; ---------------------------------------------------------------------------

Procedure.i MapVertexesReset(*Set.MapVertexSet)
  If *Set = 0
    MapDecodeSetError("VERTEXES result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapVertexesDecode(*Bytes.Byte, Length.q, *Result.MapVertexSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapVertex

  If *Result = 0
    MapDecodeSetError("VERTEXES result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapVertexesReset(*Result)
  If Length < 0
    MapDecodeSetError("VERTEXES length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_VertexSize <> 0
    MapDecodeSetError("VERTEXES length is not a multiple of 4 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_VertexSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("VERTEXES record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("VERTEXES data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapVertex))
    If items = 0
      MapDecodeSetError("Out of memory while decoding VERTEXES.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_VertexSize
      *item = items + i * SizeOf(MapVertex)
      *item\X = MapReadI16LE(*Bytes, offset)
      *item\Y = MapReadI16LE(*Bytes, offset + 2)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapVertexesCount(*Set.MapVertexSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("VERTEXES set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapVertexesGet(*Set.MapVertexSet, Index.i, *X.Long, *Y.Long)
  Protected *item.MapVertex

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("VERTEXES set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("VERTEXES index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapVertex)
  If *X <> 0
    PokeL(*X, *item\X)
  EndIf
  If *Y <> 0
    PokeL(*Y, *item\Y)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; SEGS
; ---------------------------------------------------------------------------

Procedure.i MapSegsReset(*Set.MapSegSet)
  If *Set = 0
    MapDecodeSetError("SEGS result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSegsDecode(*Bytes.Byte, Length.q, *Result.MapSegSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapSeg

  If *Result = 0
    MapDecodeSetError("SEGS result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapSegsReset(*Result)
  If Length < 0
    MapDecodeSetError("SEGS length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_SegSize <> 0
    MapDecodeSetError("SEGS length is not a multiple of 12 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_SegSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("SEGS record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("SEGS data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapSeg))
    If items = 0
      MapDecodeSetError("Out of memory while decoding SEGS.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_SegSize
      *item = items + i * SizeOf(MapSeg)
      *item\V1 = EndianReadU16LE(*Bytes, offset)
      *item\V2 = EndianReadU16LE(*Bytes, offset + 2)
      *item\Angle = EndianReadU16LE(*Bytes, offset + 4)
      *item\Linedef = EndianReadU16LE(*Bytes, offset + 6)
      *item\Side = MapReadI16LE(*Bytes, offset + 8)
      *item\Offset = MapReadI16LE(*Bytes, offset + 10)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSegsCount(*Set.MapSegSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SEGS set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapSegsGet(*Set.MapSegSet, Index.i, *V1.Long, *V2.Long, *Angle.Long, *Linedef.Long, *Side.Long, *Offset.Long)
  Protected *item.MapSeg

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SEGS set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SEGS index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapSeg)
  If *V1 <> 0
    PokeL(*V1, *item\V1)
  EndIf
  If *V2 <> 0
    PokeL(*V2, *item\V2)
  EndIf
  If *Angle <> 0
    PokeL(*Angle, *item\Angle)
  EndIf
  If *Linedef <> 0
    PokeL(*Linedef, *item\Linedef)
  EndIf
  If *Side <> 0
    PokeL(*Side, *item\Side)
  EndIf
  If *Offset <> 0
    PokeL(*Offset, *item\Offset)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; SSECTORS
; ---------------------------------------------------------------------------

Procedure.i MapSubsectorsReset(*Set.MapSubsectorSet)
  If *Set = 0
    MapDecodeSetError("SSECTORS result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSubsectorsDecode(*Bytes.Byte, Length.q, *Result.MapSubsectorSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapSubsector

  If *Result = 0
    MapDecodeSetError("SSECTORS result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapSubsectorsReset(*Result)
  If Length < 0
    MapDecodeSetError("SSECTORS length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_SubsectorSize <> 0
    MapDecodeSetError("SSECTORS length is not a multiple of 4 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_SubsectorSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("SSECTORS record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("SSECTORS data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapSubsector))
    If items = 0
      MapDecodeSetError("Out of memory while decoding SSECTORS.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_SubsectorSize
      *item = items + i * SizeOf(MapSubsector)
      *item\NumSegs = EndianReadU16LE(*Bytes, offset)
      *item\FirstSeg = EndianReadU16LE(*Bytes, offset + 2)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSubsectorsCount(*Set.MapSubsectorSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SSECTORS set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapSubsectorsGet(*Set.MapSubsectorSet, Index.i, *NumSegs.Long, *FirstSeg.Long)
  Protected *item.MapSubsector

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SSECTORS set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SSECTORS index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapSubsector)
  If *NumSegs <> 0
    PokeL(*NumSegs, *item\NumSegs)
  EndIf
  If *FirstSeg <> 0
    PokeL(*FirstSeg, *item\FirstSeg)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; NODES
; ---------------------------------------------------------------------------

Procedure.i MapNodesReset(*Set.MapNodeSet)
  If *Set = 0
    MapDecodeSetError("NODES result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapNodesDecode(*Bytes.Byte, Length.q, *Result.MapNodeSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapNode

  If *Result = 0
    MapDecodeSetError("NODES result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapNodesReset(*Result)
  If Length < 0
    MapDecodeSetError("NODES length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_NodeSize <> 0
    MapDecodeSetError("NODES length is not a multiple of 28 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_NodeSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("NODES record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("NODES data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapNode))
    If items = 0
      MapDecodeSetError("Out of memory while decoding NODES.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_NodeSize
      *item = items + i * SizeOf(MapNode)
      *item\X = MapReadI16LE(*Bytes, offset)
      *item\Y = MapReadI16LE(*Bytes, offset + 2)
      *item\DX = MapReadI16LE(*Bytes, offset + 4)
      *item\DY = MapReadI16LE(*Bytes, offset + 6)
      *item\Box0Top = MapReadI16LE(*Bytes, offset + 8)
      *item\Box0Bottom = MapReadI16LE(*Bytes, offset + 10)
      *item\Box0Left = MapReadI16LE(*Bytes, offset + 12)
      *item\Box0Right = MapReadI16LE(*Bytes, offset + 14)
      *item\Box1Top = MapReadI16LE(*Bytes, offset + 16)
      *item\Box1Bottom = MapReadI16LE(*Bytes, offset + 18)
      *item\Box1Left = MapReadI16LE(*Bytes, offset + 20)
      *item\Box1Right = MapReadI16LE(*Bytes, offset + 22)
      *item\Child0 = EndianReadU16LE(*Bytes, offset + 24)
      *item\Child1 = EndianReadU16LE(*Bytes, offset + 26)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapNodesCount(*Set.MapNodeSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("NODES set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapNodesGet(*Set.MapNodeSet, Index.i, *X.Long, *Y.Long, *DX.Long, *DY.Long, *Box0Top.Long, *Box0Bottom.Long, *Box0Left.Long, *Box0Right.Long, *Box1Top.Long, *Box1Bottom.Long, *Box1Left.Long, *Box1Right.Long, *Child0.Long, *Child1.Long)
  Protected *item.MapNode

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("NODES set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("NODES index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapNode)
  If *X <> 0
    PokeL(*X, *item\X)
  EndIf
  If *Y <> 0
    PokeL(*Y, *item\Y)
  EndIf
  If *DX <> 0
    PokeL(*DX, *item\DX)
  EndIf
  If *DY <> 0
    PokeL(*DY, *item\DY)
  EndIf
  If *Box0Top <> 0
    PokeL(*Box0Top, *item\Box0Top)
  EndIf
  If *Box0Bottom <> 0
    PokeL(*Box0Bottom, *item\Box0Bottom)
  EndIf
  If *Box0Left <> 0
    PokeL(*Box0Left, *item\Box0Left)
  EndIf
  If *Box0Right <> 0
    PokeL(*Box0Right, *item\Box0Right)
  EndIf
  If *Box1Top <> 0
    PokeL(*Box1Top, *item\Box1Top)
  EndIf
  If *Box1Bottom <> 0
    PokeL(*Box1Bottom, *item\Box1Bottom)
  EndIf
  If *Box1Left <> 0
    PokeL(*Box1Left, *item\Box1Left)
  EndIf
  If *Box1Right <> 0
    PokeL(*Box1Right, *item\Box1Right)
  EndIf
  If *Child0 <> 0
    PokeL(*Child0, *item\Child0)
  EndIf
  If *Child1 <> 0
    PokeL(*Child1, *item\Child1)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

; ChildIndex 0 or 1. Returns 1 for a subsector child, 0 for a node child.
Procedure.i MapNodesChildIsSubsector(*Set.MapNodeSet, Index.i, ChildIndex.i)
  Protected *item.MapNode

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("NODES set is not initialized.")
    ProcedureReturn -1
  EndIf
  If Index < 0 Or Index >= *Set\Count Or ChildIndex < 0 Or ChildIndex > 1
    MapDecodeSetError("NODES child access out of range.")
    ProcedureReturn -1
  EndIf
  *item = *Set\Items + Index * SizeOf(MapNode)
  If ChildIndex = 0
    ProcedureReturn Bool((*item\Child0 & #MAP_NF_SUBSECTOR) <> 0)
  EndIf
  ProcedureReturn Bool((*item\Child1 & #MAP_NF_SUBSECTOR) <> 0)
EndProcedure

; Child index with the 0x8000 flag masked off.
Procedure.i MapNodesChildIndex(*Set.MapNodeSet, Index.i, ChildIndex.i)
  Protected *item.MapNode

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("NODES set is not initialized.")
    ProcedureReturn -1
  EndIf
  If Index < 0 Or Index >= *Set\Count Or ChildIndex < 0 Or ChildIndex > 1
    MapDecodeSetError("NODES child access out of range.")
    ProcedureReturn -1
  EndIf
  *item = *Set\Items + Index * SizeOf(MapNode)
  If ChildIndex = 0
    ProcedureReturn *item\Child0 & $7FFF
  EndIf
  ProcedureReturn *item\Child1 & $7FFF
EndProcedure

; ---------------------------------------------------------------------------
; SECTORS
; ---------------------------------------------------------------------------

Procedure.i MapSectorsReset(*Set.MapSectorSet)
  If *Set = 0
    MapDecodeSetError("SECTORS result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RecordsMagic
    If *Set\Items <> 0
      FreeMemory(*Set\Items)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Count = 0
  *Set\Items = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSectorsDecode(*Bytes.Byte, Length.q, *Result.MapSectorSet)
  Protected count.q
  Protected items.i
  Protected i.i
  Protected offset.i
  Protected *item.MapSector

  If *Result = 0
    MapDecodeSetError("SECTORS result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapSectorsReset(*Result)
  If Length < 0
    MapDecodeSetError("SECTORS length is negative.")
    ProcedureReturn #False
  EndIf
  If Length % #MAP_SectorSize <> 0
    MapDecodeSetError("SECTORS length is not a multiple of 26 bytes.")
    ProcedureReturn #False
  EndIf
  count = Length / #MAP_SectorSize
  If count > #MAP_MaxRecords
    MapDecodeSetError("SECTORS record count exceeds the cap: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("SECTORS data pointer is null.")
    ProcedureReturn #False
  EndIf
  If count > 0
    items = AllocateMemory(count * SizeOf(MapSector))
    If items = 0
      MapDecodeSetError("Out of memory while decoding SECTORS.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      offset = i * #MAP_SectorSize
      *item = items + i * SizeOf(MapSector)
      *item\FloorHeight = MapReadI16LE(*Bytes, offset)
      *item\CeilingHeight = MapReadI16LE(*Bytes, offset + 2)
      CopyMemory(*Bytes + offset + 4, @*item\FloorPic[0], 8)
      CopyMemory(*Bytes + offset + 12, @*item\CeilingPic[0], 8)
      *item\LightLevel = MapReadI16LE(*Bytes, offset + 20)
      *item\Special = MapReadI16LE(*Bytes, offset + 22)
      *item\Tag = MapReadI16LE(*Bytes, offset + 24)
    Next
  EndIf
  *Result\Magic = #MAP_RecordsMagic
  *Result\Count = count
  *Result\Items = items
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSectorsCount(*Set.MapSectorSet)
  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SECTORS set is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Set\Count
EndProcedure

Procedure.i MapSectorsGet(*Set.MapSectorSet, Index.i, *FloorHeight.Long, *CeilingHeight.Long, *LightLevel.Long, *Special.Long, *Tag.Long)
  Protected *item.MapSector

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SECTORS set is not initialized.")
    ProcedureReturn #False
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SECTORS index out of range: " + Str(Index) + ".")
    ProcedureReturn #False
  EndIf
  *item = *Set\Items + Index * SizeOf(MapSector)
  If *FloorHeight <> 0
    PokeL(*FloorHeight, *item\FloorHeight)
  EndIf
  If *CeilingHeight <> 0
    PokeL(*CeilingHeight, *item\CeilingHeight)
  EndIf
  If *LightLevel <> 0
    PokeL(*LightLevel, *item\LightLevel)
  EndIf
  If *Special <> 0
    PokeL(*Special, *item\Special)
  EndIf
  If *Tag <> 0
    PokeL(*Tag, *item\Tag)
  EndIf
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapSectorsNameByte(*Set.MapSectorSet, Index.i, Field.i, ByteOffset.i)
  Protected *item.MapSector
  Protected *name.Byte

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SECTORS set is not initialized.")
    ProcedureReturn -1
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SECTORS index out of range: " + Str(Index) + ".")
    ProcedureReturn -1
  EndIf
  If Field < 0 Or Field > 1
    MapDecodeSetError("SECTORS name field out of range: " + Str(Field) + ".")
    ProcedureReturn -1
  EndIf
  If ByteOffset < 0 Or ByteOffset > 7
    MapDecodeSetError("SECTORS name byte offset out of range: " + Str(ByteOffset) + ".")
    ProcedureReturn -1
  EndIf
  *item = *Set\Items + Index * SizeOf(MapSector)
  If Field = 0
    *name = @*item\FloorPic[0]
  Else
    *name = @*item\CeilingPic[0]
  EndIf
  ProcedureReturn PeekA(*name + ByteOffset)
EndProcedure

Procedure.s MapSectorsDisplayName(*Set.MapSectorSet, Index.i, Field.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  If *Set = 0 Or *Set\Magic <> #MAP_RecordsMagic
    MapDecodeSetError("SECTORS set is not initialized.")
    ProcedureReturn ""
  EndIf
  If Index < 0 Or Index >= *Set\Count
    MapDecodeSetError("SECTORS index out of range: " + Str(Index) + ".")
    ProcedureReturn ""
  EndIf
  If Field < 0 Or Field > 1
    MapDecodeSetError("SECTORS name field out of range: " + Str(Field) + ".")
    ProcedureReturn ""
  EndIf
  For i = 0 To 7
    value = MapSectorsNameByte(*Set, Index, Field, i)
    If value < 0
      ProcedureReturn ""
    EndIf
    If value = 0
      Break
    EndIf
    If value >= 32 And value <= 126
      result + Chr(value)
    Else
      result + "."
    EndIf
  Next
  gMapDecode_LastError = ""
  ProcedureReturn result
EndProcedure

; ---------------------------------------------------------------------------
; REJECT
; ---------------------------------------------------------------------------

Procedure.i MapRejectReset(*Set.MapReject)
  If *Set = 0
    MapDecodeSetError("REJECT result pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Set\Magic = #MAP_RejectMagic
    If *Set\Bytes <> 0
      FreeMemory(*Set\Bytes)
    EndIf
  EndIf
  *Set\Magic = 0
  *Set\Size = 0
  *Set\Bytes = 0
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i MapRejectDecode(*Bytes.Byte, Length.q, *Result.MapReject)
  Protected memory.i

  If *Result = 0
    MapDecodeSetError("REJECT result pointer is null.")
    ProcedureReturn #False
  EndIf
  MapRejectReset(*Result)
  If Length < 0
    MapDecodeSetError("REJECT length is negative.")
    ProcedureReturn #False
  EndIf
  If Length > 0 And *Bytes = 0
    MapDecodeSetError("REJECT data pointer is null.")
    ProcedureReturn #False
  EndIf
  If Length > 0
    memory = AllocateMemory(Length)
    If memory = 0
      MapDecodeSetError("Out of memory while copying REJECT.")
      ProcedureReturn #False
    EndIf
    CopyMemory(*Bytes, memory, Length)
  EndIf
  *Result\Magic = #MAP_RejectMagic
  *Result\Size = Length
  *Result\Bytes = memory
  gMapDecode_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.q MapRejectSize(*Set.MapReject)
  If *Set = 0 Or *Set\Magic <> #MAP_RejectMagic
    MapDecodeSetError("REJECT set is not initialized.")
    ProcedureReturn -1
  EndIf
  ProcedureReturn *Set\Size
EndProcedure

Procedure.i MapRejectRawByte(*Set.MapReject, Index.q)
  If *Set = 0 Or *Set\Magic <> #MAP_RejectMagic
    MapDecodeSetError("REJECT set is not initialized.")
    ProcedureReturn -1
  EndIf
  If Index < 0 Or Index >= *Set\Size
    MapDecodeSetError("REJECT byte index out of range.")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Set\Bytes + Index)
EndProcedure

; Returns 1 (rejected), 0 (visible), or -1 on error. Bit order is LSB-first.
Procedure.i MapRejectGetBit(*Set.MapReject, SectorCount.i, FromSector.i, ToSector.i)
  Protected bitIndex.q
  Protected byteIndex.q
  Protected value.i

  If *Set = 0 Or *Set\Magic <> #MAP_RejectMagic
    MapDecodeSetError("REJECT set is not initialized.")
    ProcedureReturn -1
  EndIf
  If SectorCount <= 0 Or SectorCount > #MAP_MaxRecords
    MapDecodeSetError("REJECT sector count is invalid: " + Str(SectorCount) + ".")
    ProcedureReturn -1
  EndIf
  If FromSector < 0 Or FromSector >= SectorCount Or ToSector < 0 Or ToSector >= SectorCount
    MapDecodeSetError("REJECT sector index out of range.")
    ProcedureReturn -1
  EndIf
  bitIndex = Int(FromSector) * Int(SectorCount) + Int(ToSector)
  byteIndex = bitIndex / 8
  If byteIndex >= *Set\Size
    MapDecodeSetError("REJECT matrix byte is outside the raw payload.")
    ProcedureReturn -1
  EndIf
  value = PeekA(*Set\Bytes + byteIndex)
  ProcedureReturn (value >> (bitIndex & 7)) & 1
EndProcedure

CompilerEndIf
