; -----------------------------------------------------------------------------
; DoomPB - vanilla map binary decoder tests (M2-05)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; All map records and WADs are synthetic. No Doom map data is copied or
; required. Temporary WADs live under the ignored build/ tree.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "../../src/Core/Endian.pbi"
XIncludeFile "../../src/WAD/WAD.pbi"
XIncludeFile "../../src/Map/MapTypes.pbi"
XIncludeFile "../../src/Map/MapDecode.pbi"
XIncludeFile "../../src/Map/Blockmap.pbi"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #FixtureSeparator = "\"
CompilerElse
  #FixtureSeparator = "/"
CompilerEndIf

Global gFixtureDirectory.s = ""
Global gWadCount.i = 0
Global Dim gWadNames.s(31)
Global Dim gWadPointers.i(31)
Global Dim gWadSizes.q(31)
Global gCaseCount.i = 0
Global gAssertionCount.i = 0
Global gFailureCount.i = 0

; ---------------------------------------------------------------------------
; Harness and helpers
; ---------------------------------------------------------------------------

Procedure BeginCase(Id.s, Title.s)
  gCaseCount + 1
  PrintN("")
  PrintN("[" + Id + "] " + Title)
EndProcedure

Procedure Check(Ok.i, Description.s)
  gAssertionCount + 1
  If Ok
    PrintN("  PASS: " + Description)
  Else
    PrintN("  FAIL: " + Description)
    gFailureCount + 1
  EndIf
EndProcedure

Procedure.s FixturePath(FileName.s)
  ProcedureReturn gFixtureDirectory + FileName
EndProcedure

Procedure.i PrepareFixtureDirectory()
  Protected directorySize.i

  gFixtureDirectory = GetPathPart(ProgramFilename()) + "wad-map-test-tmp" + #FixtureSeparator
  directorySize = FileSize(gFixtureDirectory)
  If directorySize = -1
    ProcedureReturn CreateDirectory(gFixtureDirectory)
  EndIf
  If directorySize = -2
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure CleanupFixtureDirectory()
  Protected directory.i
  Protected entryName.s

  directory = ExamineDirectory(#PB_Any, gFixtureDirectory, "*")
  If directory
    While NextDirectoryEntry(directory)
      If DirectoryEntryType(directory) = #PB_DirectoryEntry_File
        entryName = DirectoryEntryName(directory)
        DeleteFile(gFixtureDirectory + entryName)
      EndIf
    Wend
    FinishDirectory(directory)
  EndIf
  DeleteDirectory(gFixtureDirectory, "*")
EndProcedure

Procedure.i NewBuf(Size.i)
  Protected memory.i = AllocateMemory(Size)

  If memory <> 0
    FillMemory(memory, Size, 0)
  EndIf
  ProcedureReturn memory
EndProcedure

Procedure PutU16(*Data.Byte, Offset.i, Value.i)
  PokeA(*Data + Offset, Value & $FF)
  PokeA(*Data + Offset + 1, (Value >> 8) & $FF)
EndProcedure

Procedure PutName8(*Data.Byte, Offset.i, Name.s)
  Protected i.i

  For i = 0 To 7
    If i < Len(Name)
      PokeA(*Data + Offset + i, Asc(Mid(Name, i + 1, 1)))
    Else
      PokeA(*Data + Offset + i, 0)
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------------------
; Synthetic WAD writer
; ---------------------------------------------------------------------------

Procedure WadResetEntries()
  gWadCount = 0
EndProcedure

Procedure WadAdd(Name.s, *Data.Byte, Size.q)
  gWadNames(gWadCount) = Name
  gWadPointers(gWadCount) = *Data
  gWadSizes(gWadCount) = Size
  gWadCount + 1
EndProcedure

Procedure WriteU32File(file.i, Value.q)
  WriteByte(file, Value & $FF)
  WriteByte(file, (Value >> 8) & $FF)
  WriteByte(file, (Value >> 16) & $FF)
  WriteByte(file, (Value >> 24) & $FF)
EndProcedure

Procedure WriteEntryFile(file.i, Position.q, Size.q, Name.s)
  Protected i.i

  WriteU32File(file, Position)
  WriteU32File(file, Size)
  For i = 0 To 7
    If i < Len(Name)
      WriteByte(file, Asc(Mid(Name, i + 1, 1)))
    Else
      WriteByte(file, 0)
    EndIf
  Next
EndProcedure

Procedure.i WadWrite(FileName.s)
  Protected path.s = FixturePath(FileName)
  Protected file.i
  Protected directoryOffset.q
  Protected i.i
  Protected Dim positions.q(31)

  file = CreateFile(#PB_Any, path)
  If file = 0
    ProcedureReturn #False
  EndIf
  WriteString(file, "PWAD")
  WriteU32File(file, gWadCount)
  WriteU32File(file, 0)
  For i = 0 To gWadCount - 1
    positions(i) = Loc(file)
    If gWadSizes(i) > 0
      WriteData(file, gWadPointers(i), gWadSizes(i))
    EndIf
  Next
  directoryOffset = Loc(file)
  FileSeek(file, 8)
  WriteU32File(file, directoryOffset)
  FileSeek(file, directoryOffset)
  For i = 0 To gWadCount - 1
    WriteEntryFile(file, positions(i), gWadSizes(i), gWadNames(i))
  Next
  CloseFile(file)
  ProcedureReturn #True
EndProcedure

Procedure.i LoadLumpByName(Name.s, *OutLength.Long)
  Protected index.i
  Protected size.q
  Protected memory.i

  index = WADFindLump(Name)
  If index < 0
    ProcedureReturn 0
  EndIf
  size = WADLumpSize(index)
  *OutLength\l = size
  If size <= 0
    ProcedureReturn 0
  EndIf
  memory = NewBuf(size)
  If memory = 0
    ProcedureReturn 0
  EndIf
  If WADReadLump(index, memory, size) = #False
    FreeMemory(memory)
    ProcedureReturn 0
  EndIf
  ProcedureReturn memory
EndProcedure

; ---------------------------------------------------------------------------
; M01 - M06: common decoding/lifetime
; ---------------------------------------------------------------------------

Procedure TestM01OneRecord()
  BeginCase("M01", "Each fixed-record type accepts one record")
  Protected thingSet.MapThingSet
  Protected lineSet.MapLinedefSet
  Protected sideSet.MapSidedefSet
  Protected vertexSet.MapVertexSet
  Protected segSet.MapSegSet
  Protected subSet.MapSubsectorSet
  Protected nodeSet.MapNodeSet
  Protected sectorSet.MapSectorSet
  Protected thingBuf.i = NewBuf(10)
  Protected lineBuf.i = NewBuf(14)
  Protected sideBuf.i = NewBuf(30)
  Protected vertexBuf.i = NewBuf(4)
  Protected segBuf.i = NewBuf(12)
  Protected subBuf.i = NewBuf(4)
  Protected nodeBuf.i = NewBuf(28)
  Protected sectorBuf.i = NewBuf(26)

  Check(Bool(MapThingsDecode(thingBuf, 10, @thingSet) And MapThingsCount(@thingSet) = 1), "THINGS count 1")
  Check(Bool(MapLinedefsDecode(lineBuf, 14, @lineSet) And MapLinedefsCount(@lineSet) = 1), "LINEDEFS count 1")
  Check(Bool(MapSidedefsDecode(sideBuf, 30, @sideSet) And MapSidedefsCount(@sideSet) = 1), "SIDEDEFS count 1")
  Check(Bool(MapVertexesDecode(vertexBuf, 4, @vertexSet) And MapVertexesCount(@vertexSet) = 1), "VERTEXES count 1")
  Check(Bool(MapSegsDecode(segBuf, 12, @segSet) And MapSegsCount(@segSet) = 1), "SEGS count 1")
  Check(Bool(MapSubsectorsDecode(subBuf, 4, @subSet) And MapSubsectorsCount(@subSet) = 1), "SSECTORS count 1")
  Check(Bool(MapNodesDecode(nodeBuf, 28, @nodeSet) And MapNodesCount(@nodeSet) = 1), "NODES count 1")
  Check(Bool(MapSectorsDecode(sectorBuf, 26, @sectorSet) And MapSectorsCount(@sectorSet) = 1), "SECTORS count 1")
  MapThingsReset(@thingSet)
  MapLinedefsReset(@lineSet)
  MapSidedefsReset(@sideSet)
  MapVertexesReset(@vertexSet)
  MapSegsReset(@segSet)
  MapSubsectorsReset(@subSet)
  MapNodesReset(@nodeSet)
  MapSectorsReset(@sectorSet)
  FreeMemory(thingBuf)
  FreeMemory(lineBuf)
  FreeMemory(sideBuf)
  FreeMemory(vertexBuf)
  FreeMemory(segBuf)
  FreeMemory(subBuf)
  FreeMemory(nodeBuf)
  FreeMemory(sectorBuf)
EndProcedure

Procedure TestM02PartialRecords()
  BeginCase("M02", "Partial trailing records are rejected")
  Protected thingSet.MapThingSet
  Protected lineSet.MapLinedefSet
  Protected sideSet.MapSidedefSet
  Protected vertexSet.MapVertexSet
  Protected segSet.MapSegSet
  Protected subSet.MapSubsectorSet
  Protected nodeSet.MapNodeSet
  Protected sectorSet.MapSectorSet
  Protected buf.i

  buf = NewBuf(64)
  Check(Bool(MapThingsDecode(buf, 9, @thingSet) = #False And MapThingsDecode(buf, 11, @thingSet) = #False), "THINGS 9/11 bytes rejected")
  Check(Bool(MapLinedefsDecode(buf, 13, @lineSet) = #False And MapLinedefsDecode(buf, 15, @lineSet) = #False), "LINEDEFS 13/15 bytes rejected")
  Check(Bool(MapSidedefsDecode(buf, 29, @sideSet) = #False And MapSidedefsDecode(buf, 31, @sideSet) = #False), "SIDEDEFS 29/31 bytes rejected")
  Check(Bool(MapVertexesDecode(buf, 3, @vertexSet) = #False And MapVertexesDecode(buf, 5, @vertexSet) = #False), "VERTEXES 3/5 bytes rejected")
  Check(Bool(MapSegsDecode(buf, 11, @segSet) = #False And MapSegsDecode(buf, 13, @segSet) = #False), "SEGS 11/13 bytes rejected")
  Check(Bool(MapSubsectorsDecode(buf, 3, @subSet) = #False And MapSubsectorsDecode(buf, 5, @subSet) = #False), "SSECTORS 3/5 bytes rejected")
  Check(Bool(MapNodesDecode(buf, 27, @nodeSet) = #False And MapNodesDecode(buf, 29, @nodeSet) = #False), "NODES 27/29 bytes rejected")
  Check(Bool(MapSectorsDecode(buf, 25, @sectorSet) = #False And MapSectorsDecode(buf, 27, @sectorSet) = #False), "SECTORS 25/27 bytes rejected")
  FreeMemory(buf)
EndProcedure

Procedure TestM03EmptyTables()
  BeginCase("M03", "Zero-length fixed records produce empty tables")
  Protected thingSet.MapThingSet
  Protected lineSet.MapLinedefSet
  Protected sideSet.MapSidedefSet
  Protected vertexSet.MapVertexSet
  Protected segSet.MapSegSet
  Protected subSet.MapSubsectorSet
  Protected nodeSet.MapNodeSet
  Protected sectorSet.MapSectorSet
  Protected x.l

  Check(Bool(MapThingsDecode(0, 0, @thingSet) And MapThingsCount(@thingSet) = 0), "THINGS empty succeeds")
  Check(Bool(MapLinedefsDecode(0, 0, @lineSet) And MapLinedefsCount(@lineSet) = 0), "LINEDEFS empty succeeds")
  Check(Bool(MapSidedefsDecode(0, 0, @sideSet) And MapSidedefsCount(@sideSet) = 0), "SIDEDEFS empty succeeds")
  Check(Bool(MapVertexesDecode(0, 0, @vertexSet) And MapVertexesCount(@vertexSet) = 0), "VERTEXES empty succeeds")
  Check(Bool(MapSegsDecode(0, 0, @segSet) And MapSegsCount(@segSet) = 0), "SEGS empty succeeds")
  Check(Bool(MapSubsectorsDecode(0, 0, @subSet) And MapSubsectorsCount(@subSet) = 0), "SSECTORS empty succeeds")
  Check(Bool(MapNodesDecode(0, 0, @nodeSet) And MapNodesCount(@nodeSet) = 0), "NODES empty succeeds")
  Check(Bool(MapSectorsDecode(0, 0, @sectorSet) And MapSectorsCount(@sectorSet) = 0), "SECTORS empty succeeds")
  Check(Bool(MapThingsGet(@thingSet, 0, @x, 0, 0, 0, 0) = #False), "empty THINGS getter fails")
  Check(Bool(MapNodesGet(@nodeSet, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) = #False), "empty NODES getter fails")
  MapThingsReset(@thingSet)
  MapLinedefsReset(@lineSet)
  MapSidedefsReset(@sideSet)
  MapVertexesReset(@vertexSet)
  MapSegsReset(@segSet)
  MapSubsectorsReset(@subSet)
  MapNodesReset(@nodeSet)
  MapSectorsReset(@sectorSet)
EndProcedure

Procedure TestM04NullArguments()
  BeginCase("M04", "Null pointers and negative lengths")
  Protected thingSet.MapThingSet
  Protected nodeSet.MapNodeSet
  Protected rejectSet.MapReject
  Protected buf.i = NewBuf(28)

  Check(Bool(buf <> 0), "buffer allocated")
  If buf = 0
    ProcedureReturn
  EndIf
  Check(Bool(MapThingsDecode(0, 10, @thingSet) = #False), "THINGS null input rejected")
  Check(Bool(MapThingsDecode(buf, 10, 0) = #False), "THINGS null output rejected")
  Check(Bool(MapThingsDecode(buf, -10, @thingSet) = #False), "THINGS negative length rejected")
  Check(Bool(MapNodesDecode(buf, 28, 0) = #False), "NODES null output rejected")
  Check(Bool(MapRejectDecode(0, 1, @rejectSet) = #False), "REJECT null input rejected")
  Check(Bool(MapRejectDecode(buf, -1, @rejectSet) = #False), "REJECT negative length rejected")
  MapThingsReset(@thingSet)
  MapNodesReset(@nodeSet)
  MapRejectReset(@rejectSet)
  FreeMemory(buf)
EndProcedure

Procedure TestM05RepeatedLifecycle()
  BeginCase("M05", "Decode twice, reset twice, decode after reset")
  Protected buf.i = NewBuf(10)
  Protected set.MapThingSet

  PokeA(buf, 1)
  Check(Bool(MapThingsDecode(buf, 10, @set) And MapThingsCount(@set) = 1), "first decode")
  Check(Bool(MapThingsDecode(buf, 10, @set) And MapThingsCount(@set) = 1), "second decode replaces safely")
  Check(Bool(MapThingsReset(@set)), "first reset")
  Check(Bool(MapThingsReset(@set)), "second reset")
  Check(Bool(MapThingsDecode(buf, 10, @set) And MapThingsCount(@set) = 1), "decode after reset")
  MapThingsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM06FailureAndIndependence()
  BeginCase("M06", "Failure clears old data; records survive input release")
  Protected good.i = NewBuf(4)
  Protected bad.i = NewBuf(5)
  Protected set.MapVertexSet
  Protected x.l, y.l

  PutU16(good, 0, $7FFF)
  PutU16(good, 2, $FFFF)
  Check(Bool(MapVertexesDecode(good, 4, @set) And MapVertexesCount(@set) = 1), "valid decode")
  Check(Bool(MapVertexesDecode(bad, 5, @set) = #False), "failed replacement rejected")
  Check(Bool(MapVertexesCount(@set) = 0), "failure clears old records")
  Check(Bool(MapVertexesDecode(good, 4, @set)), "decode again")
  FreeMemory(good)
  Check(Bool(MapVertexesGet(@set, 0, @x, @y) And x = 32767 And y = -1), "record survives input release")
  MapVertexesReset(@set)
  FreeMemory(bad)
EndProcedure

; ---------------------------------------------------------------------------
; M07 - M10: THINGS
; ---------------------------------------------------------------------------

Procedure TestM07SignedThing()
  BeginCase("M07", "THINGS signed coordinates and odd angle")
  Protected buf.i = NewBuf(10)
  Protected set.MapThingSet
  Protected x.l, y.l, angle.l, type.l, options.l

  PutU16(buf, 0, -123)
  PutU16(buf, 2, 456)
  PutU16(buf, 4, 359)
  PutU16(buf, 6, 1)
  PutU16(buf, 8, 7)
  Check(Bool(MapThingsDecode(buf, 10, @set)), "THING decodes")
  Check(Bool(MapThingsGet(@set, 0, @x, @y, @angle, @type, @options)), "fields readable")
  Check(Bool(x = -123 And y = 456 And angle = 359), "signed x/y and angle preserved")
  MapThingsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM08ThingOffsets()
  BeginCase("M08", "THINGS five fields at correct offsets")
  Protected buf.i = NewBuf(10)
  Protected set.MapThingSet
  Protected x.l, y.l, angle.l, type.l, options.l

  PutU16(buf, 0, 11)
  PutU16(buf, 2, 22)
  PutU16(buf, 4, 33)
  PutU16(buf, 6, 44)
  PutU16(buf, 8, 55)
  MapThingsDecode(buf, 10, @set)
  MapThingsGet(@set, 0, @x, @y, @angle, @type, @options)
  Check(Bool(x = 11 And y = 22 And angle = 33 And type = 44 And options = 55), "all five offsets are exact")
  MapThingsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM09ThingHighBits()
  BeginCase("M09", "THINGS high bits and option signs survive")
  Protected buf.i = NewBuf(10)
  Protected set.MapThingSet
  Protected type.l, options.l

  PutU16(buf, 6, $8000)
  PutU16(buf, 8, $FFFF)
  MapThingsDecode(buf, 10, @set)
  MapThingsGet(@set, 0, 0, 0, 0, @type, @options)
  Check(Bool(type = -32768), "type 0x8000 round-trips as signed")
  Check(Bool(options = -1), "options 0xFFFF round-trips as signed")
  MapThingsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM10ThingOrderAndBounds()
  BeginCase("M10", "THINGS order and invalid index")
  Protected buf.i = NewBuf(30)
  Protected set.MapThingSet
  Protected type.l
  Protected i.i

  For i = 0 To 2
    PutU16(buf, i * 10, 100 + i)
    PutU16(buf, i * 10 + 6, 10 + i)
  Next
  Check(Bool(MapThingsDecode(buf, 30, @set) And MapThingsCount(@set) = 3), "three THINGS decode")
  For i = 0 To 2
    MapThingsGet(@set, i, 0, 0, 0, @type, 0)
    Check(Bool(type = 10 + i), "record " + Str(i) + " preserves order")
  Next
  Check(Bool(MapThingsGet(@set, -1, 0, 0, 0, 0, 0) = #False), "index -1 rejected")
  Check(Bool(MapThingsGet(@set, 3, 0, 0, 0, 0, 0) = #False), "index == count rejected")
  MapThingsReset(@set)
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M11 - M15: LINEDEFS
; ---------------------------------------------------------------------------

Procedure TestM11LinedefOffsets()
  BeginCase("M11", "LINEDEFS seven fields at correct offsets")
  Protected buf.i = NewBuf(14)
  Protected set.MapLinedefSet
  Protected v1.l, v2.l, flags.l, special.l, tag.l, side0.l, side1.l

  PutU16(buf, 0, 10)
  PutU16(buf, 2, 20)
  PutU16(buf, 4, 30)
  PutU16(buf, 6, 40)
  PutU16(buf, 8, 50)
  PutU16(buf, 10, 0)
  PutU16(buf, 12, 1)
  MapLinedefsDecode(buf, 14, @set)
  MapLinedefsGet(@set, 0, @v1, @v2, @flags, @special, @tag, @side0, @side1)
  Check(Bool(v1 = 10 And v2 = 20 And flags = 30 And special = 40 And tag = 50 And side0 = 0 And side1 = 1), "all seven fields exact")
  MapLinedefsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM12NegativeSide()
  BeginCase("M12", "LINEDEFS back-side -1 preserved")
  Protected buf.i = NewBuf(14)
  Protected set.MapLinedefSet
  Protected side0.l, side1.l

  PutU16(buf, 10, 5)
  PutU16(buf, 12, -1)
  MapLinedefsDecode(buf, 14, @set)
  MapLinedefsGet(@set, 0, 0, 0, 0, 0, 0, @side0, @side1)
  Check(Bool(side0 = 5 And side1 = -1), "side -1 is not coerced to 65535")
  MapLinedefsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM13HighFlags()
  BeginCase("M13", "LINEDEFS high flag bits preserve")
  Protected buf.i = NewBuf(14)
  Protected set.MapLinedefSet
  Protected flags.l

  PutU16(buf, 4, $FFFF)
  MapLinedefsDecode(buf, 14, @set)
  MapLinedefsGet(@set, 0, 0, 0, @flags, 0, 0, 0, 0)
  Check(Bool(flags = $FFFF), "flags are unsigned 16-bit")
  Check(Bool((flags & #MAP_ML_TWOSIDED) <> 0), "two-sided bit survives")
  MapLinedefsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM14RawReferences()
  BeginCase("M14", "LINEDEFS references stay raw")
  Protected buf.i = NewBuf(14)
  Protected set.MapLinedefSet
  Protected v1.l, v2.l

  PutU16(buf, 0, 65530)
  PutU16(buf, 2, 40000)
  MapLinedefsDecode(buf, 14, @set)
  MapLinedefsGet(@set, 0, @v1, @v2, 0, 0, 0, 0, 0)
  Check(Bool(v1 = 65530 And v2 = 40000), "large vertex references are retained")
  MapLinedefsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM15LinedefBounds()
  BeginCase("M15", "LINEDEFS invalid indexes")
  Protected buf.i = NewBuf(14)
  Protected set.MapLinedefSet

  MapLinedefsDecode(buf, 14, @set)
  Check(Bool(MapLinedefsGet(@set, -1, 0, 0, 0, 0, 0, 0, 0) = #False), "index -1 rejected")
  Check(Bool(MapLinedefsGet(@set, 1, 0, 0, 0, 0, 0, 0, 0) = #False), "index == count rejected")
  MapLinedefsReset(@set)
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M16 - M19: SIDEDEFS
; ---------------------------------------------------------------------------

Procedure TestM16SidedefFields()
  BeginCase("M16", "SIDEDEFS offsets and sector")
  Protected buf.i = NewBuf(30)
  Protected set.MapSidedefSet
  Protected textureOffset.l, rowOffset.l, sector.l

  PutU16(buf, 0, -10)
  PutU16(buf, 2, 20)
  PutU16(buf, 28, 65535)
  MapSidedefsDecode(buf, 30, @set)
  MapSidedefsGet(@set, 0, @textureOffset, @rowOffset, @sector)
  Check(Bool(textureOffset = -10 And rowOffset = 20), "signed offsets preserved")
  Check(Bool(sector = 65535), "sector is unsigned 16-bit")
  MapSidedefsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM17SidedefNames()
  BeginCase("M17", "SIDEDEFS three independent eight-byte names")
  Protected buf.i = NewBuf(30)
  Protected set.MapSidedefSet

  PokeA(buf + 4, Asc("T"))
  PokeA(buf + 6, 0)
  PokeA(buf + 12, Asc("B"))
  PokeA(buf + 19, Asc("X"))
  PokeA(buf + 20, Asc("M"))
  MapSidedefsDecode(buf, 30, @set)
  Check(Bool(MapSidedefsNameByte(@set, 0, 0, 0) = Asc("T")), "top name byte 0")
  Check(Bool(MapSidedefsNameByte(@set, 0, 0, 2) = 0), "top name embedded NUL preserved")
  Check(Bool(MapSidedefsNameByte(@set, 0, 1, 0) = Asc("B")), "bottom name is independent")
  Check(Bool(MapSidedefsNameByte(@set, 0, 1, 7) = Asc("X")), "bottom trailing byte preserved")
  Check(Bool(MapSidedefsNameByte(@set, 0, 2, 0) = Asc("M")), "middle name is independent")
  MapSidedefsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM18SidedefNonAscii()
  BeginCase("M18", "SIDEDEFS lowercase and high bytes do not leak")
  Protected buf.i = NewBuf(30)
  Protected set.MapSidedefSet

  PutName8(buf, 4, "lower")
  PokeA(buf + 12, $80)
  PokeA(buf + 20, $FF)
  MapSidedefsDecode(buf, 30, @set)
  Check(Bool(MapSidedefsNameByte(@set, 0, 0, 0) = Asc("l")), "lowercase byte preserved")
  Check(Bool(MapSidedefsNameByte(@set, 0, 1, 0) = $80), "high byte preserved in bottom")
  Check(Bool(MapSidedefsNameByte(@set, 0, 2, 0) = $FF), "high byte preserved in middle")
  Check(Bool(MapSidedefsDisplayName(@set, 0, 1) = "."), "nonprintable display is escaped")
  MapSidedefsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM19SidedefGetterBounds()
  BeginCase("M19", "SIDEDEFS invalid getters")
  Protected buf.i = NewBuf(30)
  Protected set.MapSidedefSet

  MapSidedefsDecode(buf, 30, @set)
  Check(Bool(MapSidedefsNameByte(@set, -1, 0, 0) = -1), "negative index rejected")
  Check(Bool(MapSidedefsNameByte(@set, 0, 3, 0) = -1), "field 3 rejected")
  Check(Bool(MapSidedefsNameByte(@set, 0, 0, 8) = -1), "byte offset 8 rejected")
  Check(Bool(MapSidedefsGet(@set, 1, 0, 0, 0) = #False), "index == count rejected")
  MapSidedefsReset(@set)
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M20 - M22: VERTEXES
; ---------------------------------------------------------------------------

Procedure TestM20VertexExtremes()
  BeginCase("M20", "VERTEXES 16-bit extremes")
  Protected buf.i = NewBuf(4)
  Protected set.MapVertexSet
  Protected x.l, y.l

  PutU16(buf, 0, $8000)
  PutU16(buf, 2, $7FFF)
  MapVertexesDecode(buf, 4, @set)
  MapVertexesGet(@set, 0, @x, @y)
  Check(Bool(x = -32768 And y = 32767), "extremes preserved")
  MapVertexesReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM21VertexOrder()
  BeginCase("M21", "VERTEXES order and 4-byte stride")
  Protected buf.i = NewBuf(12)
  Protected set.MapVertexSet
  Protected x.l, y.l
  Protected i.i

  For i = 0 To 2
    PutU16(buf, i * 4, i + 1)
    PutU16(buf, i * 4 + 2, -(i + 1))
  Next
  MapVertexesDecode(buf, 12, @set)
  For i = 0 To 2
    MapVertexesGet(@set, i, @x, @y)
    Check(Bool(x = i + 1 And y = -(i + 1)), "vertex " + Str(i) + " at expected stride")
  Next
  MapVertexesReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM22VertexTruncation()
  BeginCase("M22", "VERTEXES odd/truncated input")
  Protected buf.i = NewBuf(6)
  Protected set.MapVertexSet

  Check(Bool(MapVertexesDecode(buf, 1, @set) = #False), "one byte rejected")
  Check(Bool(MapVertexesDecode(buf, 3, @set) = #False), "three bytes rejected")
  Check(Bool(MapVertexesDecode(buf, 5, @set) = #False), "five bytes rejected")
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M23 - M26: SEGS
; ---------------------------------------------------------------------------

Procedure TestM23SegFields()
  BeginCase("M23", "SEGS six fields and raw high-bit angle")
  Protected buf.i = NewBuf(12)
  Protected set.MapSegSet
  Protected v1.l, v2.l, angle.l, linedef.l, side.l, offset.l

  PutU16(buf, 0, 10)
  PutU16(buf, 2, 20)
  PutU16(buf, 4, $FFFF)
  PutU16(buf, 6, 40)
  PutU16(buf, 8, 1)
  PutU16(buf, 10, 60)
  MapSegsDecode(buf, 12, @set)
  MapSegsGet(@set, 0, @v1, @v2, @angle, @linedef, @side, @offset)
  Check(Bool(v1 = 10 And v2 = 20 And angle = 65535 And linedef = 40 And side = 1 And offset = 60), "all six fields exact")
  MapSegsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM24SegSignedOffset()
  BeginCase("M24", "SEGS signed offset and side")
  Protected buf.i = NewBuf(12)
  Protected set.MapSegSet
  Protected side.l, offset.l

  PutU16(buf, 8, 0)
  PutU16(buf, 10, -123)
  MapSegsDecode(buf, 12, @set)
  MapSegsGet(@set, 0, 0, 0, 0, 0, @side, @offset)
  Check(Bool(side = 0 And offset = -123), "side 0 and negative offset preserved")
  MapSegsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM25SegLargeIndexes()
  BeginCase("M25", "SEGS large raw indexes are not dereferenced")
  Protected buf.i = NewBuf(12)
  Protected set.MapSegSet
  Protected v1.l, v2.l, linedef.l

  PutU16(buf, 0, 65535)
  PutU16(buf, 2, 40000)
  PutU16(buf, 6, 65535)
  MapSegsDecode(buf, 12, @set)
  MapSegsGet(@set, 0, @v1, @v2, 0, @linedef, 0, 0)
  Check(Bool(v1 = 65535 And v2 = 40000 And linedef = 65535), "raw indexes retained")
  MapSegsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM26SegTruncation()
  BeginCase("M26", "SEGS truncated input clears output")
  Protected buf.i = NewBuf(24)
  Protected set.MapSegSet

  PokeA(buf + 0, 1)
  MapSegsDecode(buf, 12, @set)
  Check(Bool(MapSegsCount(@set) = 1), "valid first record")
  Check(Bool(MapSegsDecode(buf, 11, @set) = #False), "11-byte input rejected")
  Check(Bool(MapSegsCount(@set) = 0), "failure clears previous records")
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M27 - M29: SSECTORS
; ---------------------------------------------------------------------------

Procedure TestM27SubsectorEdges()
  BeginCase("M27", "SSECTORS unsigned edge values")
  Protected buf.i = NewBuf(4)
  Protected set.MapSubsectorSet
  Protected numsegs.l, firstseg.l

  PutU16(buf, 0, $FFFF)
  PutU16(buf, 2, $FFFF)
  MapSubsectorsDecode(buf, 4, @set)
  MapSubsectorsGet(@set, 0, @numsegs, @firstseg)
  Check(Bool(numsegs = 65535 And firstseg = 65535), "unsigned edges retained")
  MapSubsectorsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM28SubsectorOrder()
  BeginCase("M28", "SSECTORS zero count and order")
  Protected buf.i = NewBuf(8)
  Protected set.MapSubsectorSet
  Protected numsegs.l, firstseg.l

  PutU16(buf, 0, 0)
  PutU16(buf, 2, 7)
  PutU16(buf, 4, 3)
  PutU16(buf, 6, 9)
  MapSubsectorsDecode(buf, 8, @set)
  MapSubsectorsGet(@set, 0, @numsegs, @firstseg)
  Check(Bool(numsegs = 0 And firstseg = 7), "zero count is valid")
  MapSubsectorsGet(@set, 1, @numsegs, @firstseg)
  Check(Bool(numsegs = 3 And firstseg = 9), "second record is in order")
  MapSubsectorsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM29SubsectorTruncation()
  BeginCase("M29", "SSECTORS partial record and bad getters")
  Protected buf.i = NewBuf(4)
  Protected set.MapSubsectorSet

  MapSubsectorsDecode(buf, 4, @set)
  Check(Bool(MapSubsectorsDecode(buf, 3, @set) = #False), "partial record rejected")
  Check(Bool(MapSubsectorsGet(@set, 0, 0, 0) = #False), "getter after failure fails")
  Check(Bool(MapSubsectorsGet(@set, -1, 0, 0) = #False), "negative index rejected")
  Check(Bool(MapSubsectorsGet(@set, 1, 0, 0) = #False), "index == count rejected")
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M30 - M34: NODES
; ---------------------------------------------------------------------------

Procedure TestM30NodeFields()
  BeginCase("M30", "NODES partition and bbox byte order")
  Protected buf.i = NewBuf(28)
  Protected set.MapNodeSet
  Protected x.l, y.l, dx.l, dy.l
  Protected b0t.l, b0b.l, b0l.l, b0r.l, b1t.l, b1b.l, b1l.l, b1r.l

  PutU16(buf, 0, 11)
  PutU16(buf, 2, 22)
  PutU16(buf, 4, 33)
  PutU16(buf, 6, 44)
  PutU16(buf, 8, 1)
  PutU16(buf, 10, 2)
  PutU16(buf, 12, 3)
  PutU16(buf, 14, 4)
  PutU16(buf, 16, 5)
  PutU16(buf, 18, 6)
  PutU16(buf, 20, 7)
  PutU16(buf, 22, 8)
  Check(Bool(MapNodesDecode(buf, 28, @set)), "NODE decodes")
  MapNodesGet(@set, 0, @x, @y, @dx, @dy, @b0t, @b0b, @b0l, @b0r, @b1t, @b1b, @b1l, @b1r, 0, 0)
  Check(Bool(x = 11 And y = 22 And dx = 33 And dy = 44), "partition fields exact")
  Check(Bool(b0t = 1 And b0b = 2 And b0l = 3 And b0r = 4), "first bbox order is top/bottom/left/right")
  Check(Bool(b1t = 5 And b1b = 6 And b1l = 7 And b1r = 8), "second bbox order")
  MapNodesReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM31SubsectorZero()
  BeginCase("M31", "NF_SUBSECTOR child 0x8000")
  Protected buf.i = NewBuf(28)
  Protected set.MapNodeSet
  Protected child.l

  PutU16(buf, 24, $8000)
  MapNodesDecode(buf, 28, @set)
  Check(Bool(MapNodesChildIsSubsector(@set, 0, 0) = 1), "child 0 is a subsector")
  Check(Bool(MapNodesChildIndex(@set, 0, 0) = 0), "subsector index is zero")
  MapNodesGet(@set, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, @child, 0)
  Check(Bool(child = $8000), "raw child bits preserved")
  MapNodesReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM32SubsectorFFFF()
  BeginCase("M32", "NF_SUBSECTOR child 0xFFFF")
  Protected buf.i = NewBuf(28)
  Protected set.MapNodeSet

  PutU16(buf, 26, $FFFF)
  MapNodesDecode(buf, 28, @set)
  Check(Bool(MapNodesChildIsSubsector(@set, 0, 1) = 1), "child 1 is a subsector")
  Check(Bool(MapNodesChildIndex(@set, 0, 1) = 32767), "subsector index is 32767")
  MapNodesReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM33NodeChild()
  BeginCase("M33", "Unflagged child is a node index")
  Protected buf.i = NewBuf(28)
  Protected set.MapNodeSet
  Protected raw.l

  PutU16(buf, 24, $1234)
  MapNodesDecode(buf, 28, @set)
  Check(Bool(MapNodesChildIsSubsector(@set, 0, 0) = 0), "child is a node")
  Check(Bool(MapNodesChildIndex(@set, 0, 0) = $1234), "node index is the raw value")
  MapNodesGet(@set, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, @raw, 0)
  Check(Bool(raw = $1234), "raw child bits preserved")
  MapNodesReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM34NodeTruncationNegatives()
  BeginCase("M34", "NODES truncation and negative bbox")
  Protected buf.i = NewBuf(28)
  Protected set.MapNodeSet
  Protected b0t.l, b1r.l

  PutU16(buf, 8, $8000)
  PutU16(buf, 22, $FFFF)
  Check(Bool(MapNodesDecode(buf, 27, @set) = #False), "27-byte NODE rejected")
  Check(Bool(MapNodesDecode(buf, 28, @set)), "complete NODE accepted")
  MapNodesGet(@set, 0, 0, 0, 0, 0, @b0t, 0, 0, 0, 0, 0, 0, @b1r, 0, 0)
  Check(Bool(b0t = -32768 And b1r = -1), "negative bbox values preserved")
  MapNodesReset(@set)
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M35 - M38: SECTORS
; ---------------------------------------------------------------------------

Procedure TestM35SectorFields()
  BeginCase("M35", "SECTORS signed heights/light/special/tag")
  Protected buf.i = NewBuf(26)
  Protected set.MapSectorSet
  Protected floorH.l, ceilH.l, light.l, special.l, tag.l

  PutU16(buf, 0, -100)
  PutU16(buf, 2, 200)
  PutU16(buf, 20, -1)
  PutU16(buf, 22, 30000)
  PutU16(buf, 24, -2)
  MapSectorsDecode(buf, 26, @set)
  MapSectorsGet(@set, 0, @floorH, @ceilH, @light, @special, @tag)
  Check(Bool(floorH = -100 And ceilH = 200), "heights signed")
  Check(Bool(light = -1 And special = 30000 And tag = -2), "light/special/tag signed")
  MapSectorsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM36SectorNames()
  BeginCase("M36", "SECTORS floor/ceiling eight-byte names")
  Protected buf.i = NewBuf(26)
  Protected set.MapSectorSet

  PutName8(buf, 4, "FLOOR")
  PutName8(buf, 12, "CEIL")
  MapSectorsDecode(buf, 26, @set)
  Check(Bool(MapSectorsDisplayName(@set, 0, 0) = "FLOOR"), "floor pic decoded")
  Check(Bool(MapSectorsDisplayName(@set, 0, 1) = "CEIL"), "ceiling pic decoded independently")
  Check(Bool(MapSectorsNameByte(@set, 0, 0, 7) = 0), "floor padding preserved")
  MapSectorsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM37SkyAndDashNames()
  BeginCase("M37", "F_SKY1 and dash names stored as data")
  Protected buf.i = NewBuf(26)
  Protected set.MapSectorSet

  PutName8(buf, 4, "F_SKY1")
  PutName8(buf, 12, "-")
  MapSectorsDecode(buf, 26, @set)
  Check(Bool(MapSectorsDisplayName(@set, 0, 0) = "F_SKY1"), "F_SKY1 remains ordinary metadata")
  Check(Bool(MapSectorsNameByte(@set, 0, 1, 0) = Asc("-")), "dash name byte preserved")
  MapSectorsReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM38SectorMalformed()
  BeginCase("M38", "SECTORS malformed length and bad getters")
  Protected buf.i = NewBuf(52)
  Protected set.MapSectorSet

  Check(Bool(MapSectorsDecode(buf, 25, @set) = #False), "25-byte SECTOR rejected")
  Check(Bool(MapSectorsDecode(buf, 52, @set) And MapSectorsCount(@set) = 2), "two records accepted")
  Check(Bool(MapSectorsGet(@set, 2, 0, 0, 0, 0, 0) = #False), "index == count rejected")
  Check(Bool(MapSectorsNameByte(@set, 0, 2, 0) = -1), "field 2 rejected")
  MapSectorsReset(@set)
  FreeMemory(buf)
EndProcedure

; ---------------------------------------------------------------------------
; M39 - M42: REJECT
; ---------------------------------------------------------------------------

Procedure TestM39RejectBits()
  BeginCase("M39", "REJECT LSB-first 3x3 matrix")
  Protected buf.i = NewBuf(2)
  Protected set.MapReject

  PokeA(buf + 0, %10001011)   ; bits 0,1,3,7
  PokeA(buf + 1, %00000001)   ; bit 8
  Check(Bool(MapRejectDecode(buf, 2, @set)), "REJECT decodes")
  Check(Bool(MapRejectGetBit(@set, 3, 0, 0) = 1), "bit 0 set")
  Check(Bool(MapRejectGetBit(@set, 3, 0, 1) = 1), "bit 1 set")
  Check(Bool(MapRejectGetBit(@set, 3, 1, 0) = 1), "bit 3 set")
  Check(Bool(MapRejectGetBit(@set, 3, 2, 1) = 1), "bit 7 set")
  Check(Bool(MapRejectGetBit(@set, 3, 2, 2) = 1), "bit 8 crosses into the second byte")
  Check(Bool(MapRejectGetBit(@set, 3, 0, 2) = 0), "bit 2 is clear")
  MapRejectReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM40RejectEmpty()
  BeginCase("M40", "Empty REJECT and inaccessible bit")
  Protected set.MapReject

  Check(Bool(MapRejectDecode(0, 0, @set)), "empty REJECT decodes")
  Check(Bool(MapRejectSize(@set) = 0), "size is zero")
  Check(Bool(MapRejectRawByte(@set, 0) = -1), "raw byte access fails")
  Check(Bool(MapRejectGetBit(@set, 3, 0, 0) = -1), "matrix bit access fails")
  MapRejectReset(@set)
EndProcedure

Procedure TestM41RejectBounds()
  BeginCase("M41", "REJECT invalid sector counts and indices")
  Protected buf.i = NewBuf(1)
  Protected set.MapReject

  MapRejectDecode(buf, 1, @set)
  Check(Bool(MapRejectGetBit(@set, 0, 0, 0) = -1), "sector count 0 rejected")
  Check(Bool(MapRejectGetBit(@set, -1, 0, 0) = -1), "negative count rejected")
  Check(Bool(MapRejectGetBit(@set, 65537, 0, 0) = -1), "oversized count rejected")
  Check(Bool(MapRejectGetBit(@set, 1, -1, 0) = -1), "negative from rejected")
  Check(Bool(MapRejectGetBit(@set, 1, 1, 0) = -1), "from == count rejected")
  Check(Bool(MapRejectGetBit(@set, 8, 1, 7) = -1), "truncated matrix rejected")
  MapRejectReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM42RejectLifetime()
  BeginCase("M42", "REJECT owned copy and repeated decode")
  Protected buf.i = NewBuf(2)
  Protected set.MapReject

  PokeA(buf + 0, $01)
  PokeA(buf + 1, $02)
  MapRejectDecode(buf, 2, @set)
  FreeMemory(buf)
  Check(Bool(MapRejectRawByte(@set, 0) = $01 And MapRejectRawByte(@set, 1) = $02), "copy survives input release")
  Check(Bool(MapRejectGetBit(@set, 4, 0, 0) = 1 And MapRejectGetBit(@set, 4, 2, 1) = 1), "bits remain correct")
  Check(Bool(MapRejectReset(@set)), "first reset")
  Check(Bool(MapRejectReset(@set)), "second reset")
  Check(Bool(MapRejectDecode(0, 0, @set) And MapRejectSize(@set) = 0), "redecode after reset")
  MapRejectReset(@set)
EndProcedure

; ---------------------------------------------------------------------------
; M43 - M48: BLOCKMAP
; ---------------------------------------------------------------------------

Procedure TestM43ValidOneByOne()
  BeginCase("M43", "Valid 1x1 BLOCKMAP")
  Protected buf.i = NewBuf(16)
  Protected set.MapBlockmap
  Protected originX.l, originY.l, width.l, height.l
  Protected offsetWords.l, lineCount.l, linedef.l

  PutU16(buf, 0, -10)
  PutU16(buf, 2, 20)
  PutU16(buf, 4, 1)
  PutU16(buf, 6, 1)
  PutU16(buf, 8, 5)
  PutU16(buf, 10, 0)
  PutU16(buf, 12, 7)
  PutU16(buf, 14, $FFFF)
  Check(Bool(MapBlockmapDecode(buf, 16, @set)), "BLOCKMAP decodes")
  MapBlockmapHeader(@set, @originX, @originY, @width, @height)
  Check(Bool(originX = -10 And originY = 20 And width = 1 And height = 1), "header signed origin and dimensions")
  Check(Bool(MapBlockmapGetCell(@set, 0, 0, @offsetWords, @lineCount, 0)), "cell readable")
  Check(Bool(offsetWords = 5 And lineCount = 1), "word offset and line count")
  Check(Bool(MapBlockmapGetLine(@set, 0, 0, 0, @linedef) And linedef = 7), "line reference")
  MapBlockmapReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM44SharedEmptyList()
  BeginCase("M44", "Shared offset and empty blocklist")
  Protected buf.i = NewBuf(16)
  Protected set.MapBlockmap
  Protected lineCount.l

  PutU16(buf, 4, 2)
  PutU16(buf, 6, 1)
  PutU16(buf, 8, 6)
  PutU16(buf, 10, 6)
  PutU16(buf, 12, 0)
  PutU16(buf, 14, $FFFF)
  Check(Bool(MapBlockmapDecode(buf, 16, @set)), "shared-offset BLOCKMAP decodes")
  Check(Bool(MapBlockmapGetCell(@set, 0, 0, 0, @lineCount, 0) And lineCount = 0), "first cell list is empty")
  Check(Bool(MapBlockmapGetCell(@set, 1, 0, 0, @lineCount, 0) And lineCount = 0), "second cell shares the empty list")
  Check(Bool(MapBlockmapGetLine(@set, 0, 0, 0, 0) = #False), "no line exists in the empty list")
  MapBlockmapReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM45HighOffset()
  BeginCase("M45", "Unsigned word offset >= 0x8000")
  Protected length.i = $8005 * 2 + 6
  Protected buf.i
  Protected set.MapBlockmap
  Protected offsetWords.l, lineCount.l

  buf = NewBuf(length)
  Check(Bool(buf <> 0), "padded BLOCKMAP allocated")
  If buf = 0
    ProcedureReturn
  EndIf
  PutU16(buf, 4, 1)
  PutU16(buf, 6, 1)
  PutU16(buf, 8, $8005)
  PutU16(buf, $8005 * 2, 0)
  PutU16(buf, $8005 * 2 + 2, 3)
  PutU16(buf, $8005 * 2 + 4, $FFFF)
  Check(Bool(MapBlockmapDecode(buf, length, @set)), "high unsigned offset decodes")
  Check(Bool(MapBlockmapGetCell(@set, 0, 0, @offsetWords, @lineCount, 0)), "high-offset cell readable")
  Check(Bool(offsetWords = $8005 And lineCount = 1), "offset is not sign-extended")
  MapBlockmapReset(@set)
  FreeMemory(buf)
EndProcedure

Procedure TestM46BlockmapSizes()
  BeginCase("M46", "BLOCKMAP zero/huge/odd sizes")
  Protected small.i = NewBuf(8)
  Protected odd.i = NewBuf(9)
  Protected shortTable.i = NewBuf(8)
  Protected set.MapBlockmap

  Check(Bool(MapBlockmapDecode(odd, 9, @set) = #False), "odd byte length rejected")
  PutU16(small, 4, 0)
  PutU16(small, 6, 1)
  Check(Bool(MapBlockmapDecode(small, 8, @set) = #False), "zero width rejected")
  PutU16(small, 4, 1)
  PutU16(small, 6, 0)
  Check(Bool(MapBlockmapDecode(small, 8, @set) = #False), "zero height rejected")
  PutU16(shortTable, 4, 2)
  PutU16(shortTable, 6, 2)
  Check(Bool(MapBlockmapDecode(shortTable, 8, @set) = #False), "missing offset table rejected")
  PutU16(shortTable, 4, $FFFF)
  PutU16(shortTable, 6, $FFFF)
  Check(Bool(MapBlockmapDecode(shortTable, 8, @set) = #False), "huge cell product rejected")
  FreeMemory(small)
  FreeMemory(odd)
  FreeMemory(shortTable)
EndProcedure

Procedure TestM47BlockmapOffsets()
  BeginCase("M47", "Invalid BLOCKMAP offsets")
  Protected intoHeader.i = NewBuf(12)
  Protected beyond.i = NewBuf(12)
  Protected noRoom.i = NewBuf(12)
  Protected set.MapBlockmap

  PutU16(intoHeader, 4, 1)
  PutU16(intoHeader, 6, 1)
  PutU16(intoHeader, 8, 4)
  Check(Bool(MapBlockmapDecode(intoHeader, 12, @set) = #False), "offset into header/table rejected")
  PutU16(beyond, 4, 1)
  PutU16(beyond, 6, 1)
  PutU16(beyond, 8, 1000)
  Check(Bool(MapBlockmapDecode(beyond, 12, @set) = #False), "offset beyond input rejected")
  PutU16(noRoom, 4, 1)
  PutU16(noRoom, 6, 1)
  PutU16(noRoom, 8, 6)
  PutU16(noRoom, 10, 0)
  Check(Bool(MapBlockmapDecode(noRoom, 12, @set) = #False), "no room for terminator rejected")
  FreeMemory(intoHeader)
  FreeMemory(beyond)
  FreeMemory(noRoom)
EndProcedure

Procedure TestM48BlockmapLists()
  BeginCase("M48", "Unterminated/truncated lists clear output")
  Protected good.i = NewBuf(16)
  Protected bad.i = NewBuf(14)
  Protected set.MapBlockmap

  PutU16(good, 4, 1)
  PutU16(good, 6, 1)
  PutU16(good, 8, 5)
  PutU16(good, 10, 0)
  PutU16(good, 12, 7)
  PutU16(good, 14, $FFFF)
  Check(Bool(MapBlockmapDecode(good, 16, @set)), "valid BLOCKMAP first")
  PutU16(bad, 4, 1)
  PutU16(bad, 6, 1)
  PutU16(bad, 8, 5)
  PutU16(bad, 10, 0)
  PutU16(bad, 12, 7)
  Check(Bool(MapBlockmapDecode(bad, 14, @set) = #False), "unterminated list rejected")
  Check(Bool(set\Bytes = 0 And set\Width = 0), "failure clears previous output")
  FreeMemory(good)
  FreeMemory(bad)
EndProcedure

; ---------------------------------------------------------------------------
; I01 - I03: synthetic WAD integration
; ---------------------------------------------------------------------------

Procedure.i MakeMapLumps()
  ; Returns a pointer to a 10-element pointer array? PureBasic has no easy
  ; return; the caller supplies buffers directly in BuildMapWad.
  ProcedureReturn 0
EndProcedure

Procedure.i BuildMapWad(FileName.s)
  ; Builds E1M1 marker plus minimal valid ten lumps.
  Protected thing.i = NewBuf(10)
  Protected line.i = NewBuf(14)
  Protected side.i = NewBuf(30)
  Protected vertex.i = NewBuf(4)
  Protected seg.i = NewBuf(12)
  Protected sub.i = NewBuf(4)
  Protected node.i = NewBuf(28)
  Protected sector.i = NewBuf(26)
  Protected reject.i = NewBuf(2)
  Protected blockmap.i = NewBuf(16)

  PokeA(thing + 6, 1)
  PokeA(blockmap + 4, 1)
  PokeA(blockmap + 6, 1)
  PutU16(blockmap, 8, 5)
  PutU16(blockmap, 12, 0)
  PutU16(blockmap, 14, $FFFF)

  WadResetEntries()
  WadAdd("E1M1", 0, 0)
  WadAdd("THINGS", thing, 10)
  WadAdd("LINEDEFS", line, 14)
  WadAdd("SIDEDEFS", side, 30)
  WadAdd("VERTEXES", vertex, 4)
  WadAdd("SEGS", seg, 12)
  WadAdd("SSECTORS", sub, 4)
  WadAdd("NODES", node, 28)
  WadAdd("SECTORS", sector, 26)
  WadAdd("REJECT", reject, 2)
  WadAdd("BLOCKMAP", blockmap, 16)
  Protected ok.i = WadWrite(FileName)
  FreeMemory(thing)
  FreeMemory(line)
  FreeMemory(side)
  FreeMemory(vertex)
  FreeMemory(seg)
  FreeMemory(sub)
  FreeMemory(node)
  FreeMemory(sector)
  FreeMemory(reject)
  FreeMemory(blockmap)
  ProcedureReturn ok
EndProcedure

Procedure TestI01SyntheticMap()
  BeginCase("I01", "Synthetic ten-lump map sequence")
  Protected path.s = "map.wad"
  Protected size.l
  Protected bytes.i
  Protected thingSet.MapThingSet
  Protected vertexSet.MapVertexSet
  Protected sectorSet.MapSectorSet
  Protected rejectSet.MapReject
  Protected blockmapSet.MapBlockmap

  Check(Bool(BuildMapWad(path)), "synthetic map WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(WADFindLump("E1M1") >= 0), "E1M1 marker found")
  bytes = LoadLumpByName("THINGS", @size)
  Check(Bool(bytes <> 0 And MapThingsDecode(bytes, size, @thingSet) And MapThingsCount(@thingSet) = 1), "THINGS decodes from WAD")
  If bytes <> 0
    FreeMemory(bytes)
  EndIf
  bytes = LoadLumpByName("VERTEXES", @size)
  Check(Bool(bytes <> 0 And MapVertexesDecode(bytes, size, @vertexSet) And MapVertexesCount(@vertexSet) = 1), "VERTEXES decodes from WAD")
  If bytes <> 0
    FreeMemory(bytes)
  EndIf
  bytes = LoadLumpByName("SECTORS", @size)
  Check(Bool(bytes <> 0 And MapSectorsDecode(bytes, size, @sectorSet) And MapSectorsCount(@sectorSet) = 1), "SECTORS decodes from WAD")
  If bytes <> 0
    FreeMemory(bytes)
  EndIf
  bytes = LoadLumpByName("REJECT", @size)
  Check(Bool(bytes <> 0 And MapRejectDecode(bytes, size, @rejectSet) And MapRejectSize(@rejectSet) = 2), "REJECT decodes from WAD")
  If bytes <> 0
    FreeMemory(bytes)
  EndIf
  bytes = LoadLumpByName("BLOCKMAP", @size)
  Check(Bool(bytes <> 0 And MapBlockmapDecode(bytes, size, @blockmapSet)), "BLOCKMAP decodes from WAD")
  If bytes <> 0
    FreeMemory(bytes)
  EndIf
  MapThingsReset(@thingSet)
  MapVertexesReset(@vertexSet)
  MapSectorsReset(@sectorSet)
  MapRejectReset(@rejectSet)
  MapBlockmapReset(@blockmapSet)
  WADClose()
  DeleteFile(FixturePath(path))
EndProcedure

Procedure TestI02BadWad()
  BeginCase("I02", "Missing/truncated map resources fail cleanly")
  Protected path.s = "badmap.wad"
  Protected badBlockmap.i = NewBuf(12)
  Protected set.MapBlockmap

  PutU16(badBlockmap, 4, 1)
  PutU16(badBlockmap, 6, 1)
  PutU16(badBlockmap, 8, 5)
  PutU16(badBlockmap, 10, 0)   ; no terminator
  WadResetEntries()
  WadAdd("E1M1", 0, 0)
  WadAdd("BLOCKMAP", badBlockmap, 12)
  Check(Bool(WadWrite(path)), "bad map WAD created")
  Check(Bool(WADOpen(FixturePath(path))), "WAD opens")
  Check(Bool(WADFindLump("THINGS") = -1), "missing THINGS reported")
  Check(Bool(MapBlockmapDecode(badBlockmap, 12, @set) = #False), "malformed BLOCKMAP rejected")
  Check(Bool(WADFindLump("E1M1") >= 0), "unrelated lookup still works")
  WADClose()
  DeleteFile(FixturePath(path))
  FreeMemory(badBlockmap)
EndProcedure

Procedure TestI03ReopenLifecycle()
  BeginCase("I03", "Decoded data survives WAD close/reopen")
  Protected pathA.s = "mapa.wad"
  Protected pathB.s = "mapb.wad"
  Protected size.l
  Protected bytes.i
  Protected set.MapVertexSet
  Protected x.l, y.l
  Protected vertexA.i = NewBuf(4)
  Protected vertexB.i = NewBuf(4)

  PutU16(vertexA, 0, 100)
  PutU16(vertexA, 2, 200)
  PutU16(vertexB, 0, -300)
  PutU16(vertexB, 2, 400)
  WadResetEntries()
  WadAdd("VERTEXES", vertexA, 4)
  Check(Bool(WadWrite(pathA)), "WAD A created")
  WadResetEntries()
  WadAdd("VERTEXES", vertexB, 4)
  Check(Bool(WadWrite(pathB)), "WAD B created")

  Check(Bool(WADOpen(FixturePath(pathA))), "WAD A opens")
  bytes = LoadLumpByName("VERTEXES", @size)
  Check(Bool(bytes <> 0 And MapVertexesDecode(bytes, size, @set)), "WAD A vertex decodes")
  If bytes <> 0
    FreeMemory(bytes)
  EndIf
  WADClose()
  Check(Bool(MapVertexesGet(@set, 0, @x, @y) And x = 100 And y = 200), "decoded record survives WAD close")
  MapVertexesReset(@set)

  Check(Bool(WADOpen(FixturePath(pathB))), "WAD B opens")
  bytes = LoadLumpByName("VERTEXES", @size)
  Check(Bool(bytes <> 0 And MapVertexesDecode(bytes, size, @set)), "WAD B vertex decodes")
  If bytes <> 0
    FreeMemory(bytes)
  EndIf
  Check(Bool(MapVertexesGet(@set, 0, @x, @y) And x = -300 And y = 400), "fresh WAD B data is used")
  MapVertexesReset(@set)
  WADClose()
  DeleteFile(FixturePath(pathA))
  DeleteFile(FixturePath(pathB))
  FreeMemory(vertexA)
  FreeMemory(vertexB)
EndProcedure

; ---------------------------------------------------------------------------
; Main
; ---------------------------------------------------------------------------

OpenConsole()
PrintN("DoomPB vanilla map binary tests (M2-05)")

If PrepareFixtureDirectory() = #False
  PrintN("FAIL: cannot create fixture directory at " + gFixtureDirectory)
  End 1
EndIf
PrintN("Fixture directory: " + gFixtureDirectory)

TestM01OneRecord()
TestM02PartialRecords()
TestM03EmptyTables()
TestM04NullArguments()
TestM05RepeatedLifecycle()
TestM06FailureAndIndependence()
TestM07SignedThing()
TestM08ThingOffsets()
TestM09ThingHighBits()
TestM10ThingOrderAndBounds()
TestM11LinedefOffsets()
TestM12NegativeSide()
TestM13HighFlags()
TestM14RawReferences()
TestM15LinedefBounds()
TestM16SidedefFields()
TestM17SidedefNames()
TestM18SidedefNonAscii()
TestM19SidedefGetterBounds()
TestM20VertexExtremes()
TestM21VertexOrder()
TestM22VertexTruncation()
TestM23SegFields()
TestM24SegSignedOffset()
TestM25SegLargeIndexes()
TestM26SegTruncation()
TestM27SubsectorEdges()
TestM28SubsectorOrder()
TestM29SubsectorTruncation()
TestM30NodeFields()
TestM31SubsectorZero()
TestM32SubsectorFFFF()
TestM33NodeChild()
TestM34NodeTruncationNegatives()
TestM35SectorFields()
TestM36SectorNames()
TestM37SkyAndDashNames()
TestM38SectorMalformed()
TestM39RejectBits()
TestM40RejectEmpty()
TestM41RejectBounds()
TestM42RejectLifetime()
TestM43ValidOneByOne()
TestM44SharedEmptyList()
TestM45HighOffset()
TestM46BlockmapSizes()
TestM47BlockmapOffsets()
TestM48BlockmapLists()

TestI01SyntheticMap()
TestI02BadWad()
TestI03ReopenLifecycle()

CleanupFixtureDirectory()

PrintN("")
PrintN("Test cases: " + Str(gCaseCount) + ", assertions: " + Str(gAssertionCount) + ", failures: " + Str(gFailureCount))
If gFailureCount = 0
  PrintN("RESULT: PASS")
  End 0
EndIf

PrintN("RESULT: FAIL")
End gFailureCount
