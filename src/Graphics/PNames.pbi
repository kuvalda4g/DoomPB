; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; PNAMES decoder. The lump starts with a little-endian signed 32-bit count N,
; followed by N consecutive eight-byte patch names. The names are opaque bytes:
; they may be NUL-padded, exactly eight bytes long, lowercase, or contain high
; bytes. Order and duplicates are preserved exactly because TEXTURE1/TEXTURE2
; patch references are numeric indices into this table.
;
; The original R_InitTextures() reads the count with LONG(), copies each name
; with strncpy() and resolves it through W_CheckNumForName(). DoomPB only
; decodes the table here; name-to-lump resolution is deferred to M2-02.
;
; Ownership:
;   - PNamesTable is caller-owned and must be zero-initialized once.
;   - PNamesDecode() owns a private copy of the name bytes.
;   - PNamesReset() frees it and leaves the structure reusable. A failed decode
;     clears previous data.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PNAMES_PBI, #PB_Constant) = 0

#DOOMPB_PNAMES_PBI = 1

XIncludeFile "../Core/Endian.pbi"

#PNAMES_HeaderSize       = 4
#PNAMES_NameSize         = 8
#PNAMES_MaxCount         = 65536

#PNAMES_Magic            = $504E4131

Structure PNamesTable
  Magic.l
  Count.l
  *Names.Byte
EndStructure

Global gPNames_LastError.s = ""

Procedure PNamesSetError(Message.s)
  gPNames_LastError = Message
EndProcedure

Procedure.s PNamesLastError()
  ProcedureReturn gPNames_LastError
EndProcedure

Procedure.i PNamesReset(*PNames.PNamesTable)
  If *PNames = 0
    PNamesSetError("PNAMES pointer is null.")
    ProcedureReturn #False
  EndIf

  If *PNames\Magic = #PNAMES_Magic
    If *PNames\Names <> 0
      FreeMemory(*PNames\Names)
    EndIf
  EndIf

  *PNames\Magic = 0
  *PNames\Count = 0
  *PNames\Names = 0
  gPNames_LastError = ""
  ProcedureReturn #True
EndProcedure

; Decodes a PNAMES payload. Trailing bytes after the declared name array are
; accepted and ignored, matching Doom's use of the declared count only.
Procedure.i PNamesDecode(*Bytes.Byte, Length.q, *Result.PNamesTable)
  Protected count.l
  Protected required.q
  Protected names.i = 0

  If *Result = 0
    PNamesSetError("PNAMES result pointer is null.")
    ProcedureReturn #False
  EndIf

  PNamesReset(*Result)

  If Length < #PNAMES_HeaderSize
    PNamesSetError("PNAMES is too short for its 4-byte count.")
    ProcedureReturn #False
  EndIf
  If *Bytes = 0
    PNamesSetError("PNAMES data pointer is null.")
    ProcedureReturn #False
  EndIf

  count = EndianReadI32LE(*Bytes, 0)
  If count < 0
    PNamesSetError("PNAMES count is negative: " + Str(count) + ".")
    ProcedureReturn #False
  EndIf
  If count > #PNAMES_MaxCount
    PNamesSetError("PNAMES contains too many names: " + Str(count) + " (limit " + Str(#PNAMES_MaxCount) + ").")
    ProcedureReturn #False
  EndIf

  required = Int(#PNAMES_HeaderSize) + Int(count) * #PNAMES_NameSize
  If required > Length
    PNamesSetError("PNAMES name table is truncated: needs " + Str(required) + " bytes, input has " + Str(Length) + ".")
    ProcedureReturn #False
  EndIf

  If count > 0
    names = AllocateMemory(Int(count) * #PNAMES_NameSize)
    If names = 0
      PNamesSetError("Out of memory while decoding PNAMES.")
      ProcedureReturn #False
    EndIf
    CopyMemory(*Bytes + #PNAMES_HeaderSize, names, Int(count) * #PNAMES_NameSize)
  EndIf

  *Result\Magic = #PNAMES_Magic
  *Result\Count = count
  *Result\Names = names
  gPNames_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i PNamesCount(*PNames.PNamesTable)
  If *PNames = 0 Or *PNames\Magic <> #PNAMES_Magic
    PNamesSetError("PNAMES table is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *PNames\Count
EndProcedure

; Returns one raw name byte (0..255), or -1 for an invalid table, name index or
; byte offset. ByteOffset is limited to 0..7.
Procedure.i PNamesRawNameByte(*PNames.PNamesTable, NameIndex.i, ByteOffset.i)
  If *PNames = 0 Or *PNames\Magic <> #PNAMES_Magic
    PNamesSetError("PNAMES table is not initialized.")
    ProcedureReturn -1
  EndIf
  If NameIndex < 0 Or NameIndex >= *PNames\Count
    PNamesSetError("PNAMES name index out of range: " + Str(NameIndex) + " (count " + Str(*PNames\Count) + ").")
    ProcedureReturn -1
  EndIf
  If ByteOffset < 0 Or ByteOffset >= #PNAMES_NameSize
    PNamesSetError("PNAMES byte offset out of range: " + Str(ByteOffset) + ".")
    ProcedureReturn -1
  EndIf

  ProcedureReturn PeekA(*PNames\Names + Int(NameIndex) * #PNAMES_NameSize + Int(ByteOffset))
EndProcedure

; Printable diagnostic rendering: stops at the first NUL, maps bytes outside
; 32..126 to '.', and never reads beyond the eighth name byte.
Procedure.s PNamesDisplayName(*PNames.PNamesTable, NameIndex.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  If *PNames = 0 Or *PNames\Magic <> #PNAMES_Magic
    PNamesSetError("PNAMES table is not initialized.")
    ProcedureReturn ""
  EndIf
  If NameIndex < 0 Or NameIndex >= *PNames\Count
    PNamesSetError("PNAMES name index out of range: " + Str(NameIndex) + " (count " + Str(*PNames\Count) + ").")
    ProcedureReturn ""
  EndIf

  For i = 0 To #PNAMES_NameSize - 1
    value = PeekA(*PNames\Names + Int(NameIndex) * #PNAMES_NameSize + i)
    If value = 0
      Break
    EndIf
    If value >= 32 And value <= 126
      result + Chr(value)
    Else
      result + "."
    EndIf
  Next

  gPNames_LastError = ""
  ProcedureReturn result
EndProcedure

CompilerEndIf
