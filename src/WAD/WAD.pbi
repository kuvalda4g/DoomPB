; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; WAD container reader: 12-byte header and 16-byte directory entries.
;
; Ported from Linux Doom 1.10 w_wad.c / w_wad.h:
;   wadinfo_t      -> WAD header fields (12 bytes)
;   filelump_t     -> WADLump directory fields (16 bytes)
;   lumpinfo_t     -> WADLump (name, position, size)
;   W_AddFile      -> WADOpen (header/directory part only)
;   W_InitMultipleFiles -> global lifetime management
;
; Intentional differences from the original C code (all stricter):
;   - every read is checked against the file size and against short reads;
;   - negative lump counts/offsets/sizes are rejected;
;   - nonempty lump data must lie inside the file;
;   - directory allocation is bounded by a documented safety limit.
;
; Zero-length lump markers (for example F_START/F_END) are valid. Their
; recorded position may be meaningless (even negative or past EOF). It is
; stored verbatim but never used to seek or read.
;
; Only one WAD is open at a time in M1-01. The lump array is already a plain
; indexed table so M1-02 can add by-name lookup and payload reads without
; changing these entry points; multi-WAD overlays will extend the lifetime API.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WAD_PBI, #PB_Constant) = 0

#DOOMPB_WAD_PBI = 1

XIncludeFile "../Core/Endian.pbi"

#WAD_HeaderSize          = 12
#WAD_LumpEntrySize       = 16
#WAD_LumpNameSize        = 8

; Safety limit, not a format limit. Real Doom IWADs have ~2.3k lumps. The cap
; prevents a malformed header from requesting an enormous directory allocation
; even when the file itself is large enough to pass the range check.
#WAD_MaxDirectoryEntries = 1000000

Enumeration WADKind
  #WAD_KindNone
  #WAD_KindIWAD
  #WAD_KindPWAD
EndEnumeration

Structure WADLump
  Position.l          ; raw signed filepos from the directory entry
  Size.l              ; raw signed size from the directory entry
  NameBytes.a[8]      ; raw 8 name bytes, no NUL assumption
  DisplayName.s       ; NUL-trimmed, printable-only rendering for diagnostics
EndStructure

Global gWAD_IsOpen.i = #False
Global gWAD_Kind.i = #WAD_KindNone
Global gWAD_Path.s = ""
Global gWAD_FileSize.q = 0
Global gWAD_LumpCount.l = 0
Global gWAD_DirectoryOffset.l = 0
Global gWAD_LastError.s = ""
Global Dim gWAD_Lumps.WADLump(0)

Procedure WADSetError(Message.s)
  gWAD_LastError = Message
EndProcedure

; Releases all per-file state. Does not touch the last error message.
Procedure WADReset()
  gWAD_IsOpen = #False
  gWAD_Kind = #WAD_KindNone
  gWAD_Path = ""
  gWAD_FileSize = 0
  gWAD_LumpCount = 0
  gWAD_DirectoryOffset = 0
  ReDim gWAD_Lumps(0)
EndProcedure

Procedure WADClose()
  WADReset()
  gWAD_LastError = ""
EndProcedure

Procedure.s WADDecodeDisplayName(*NameBytes.Byte)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  For i = 0 To #WAD_LumpNameSize - 1
    value = PeekA(*NameBytes + i)
    If value = 0
      Break
    EndIf
    If value >= 32 And value <= 126
      result + Chr(value)
    Else
      result + "."
    EndIf
  Next

  ProcedureReturn result
EndProcedure

; Central failure path for WADOpen. Requires the local variables 'file' and
; 'buffer' of the calling procedure and returns #False from it.
Macro WADAbortOpen(MessageText)
  If buffer <> 0
    FreeMemory(buffer)
    buffer = 0
  EndIf
  If file <> 0
    CloseFile(file)
    file = 0
  EndIf
  WADReset()
  WADSetError(MessageText)
  ProcedureReturn #False
EndMacro

; Opens a WAD, validates the header and reads the complete directory into
; owned memory. The file handle is closed before returning: later milestones
; reopen the file for payload reads, so no descriptor leaks out of the parser.
; Returns #True on success, #False on failure (see WADLastError()).
Procedure.i WADOpen(Path.s)
  Protected file.i = 0
  Protected buffer.i = 0
  Protected fileSize.q
  Protected signature.s
  Protected kind.i = #WAD_KindNone
  Protected lumpCount.l
  Protected directoryOffset.l
  Protected directorySize.q
  Protected directoryEnd.q
  Protected entryIndex.i
  Protected entryPosition.l
  Protected entrySize.l
  Protected entryEnd.q

  WADReset()
  gWAD_LastError = ""

  If Path = ""
    WADSetError("WAD path is empty.")
    ProcedureReturn #False
  EndIf

  fileSize = FileSize(Path)
  If fileSize < 0
    WADSetError("Cannot open WAD file (missing or unreadable): " + Path)
    ProcedureReturn #False
  EndIf

  file = ReadFile(#PB_Any, Path)
  If file = 0
    WADSetError("Cannot read WAD file: " + Path)
    ProcedureReturn #False
  EndIf

  If fileSize < #WAD_HeaderSize
    CloseFile(file)
    WADSetError("WAD file is too short for a header: " + Str(fileSize) + " bytes (minimum " + Str(#WAD_HeaderSize) + ").")
    ProcedureReturn #False
  EndIf

  ; One 16-byte buffer is reused for the header and every directory entry.
  buffer = AllocateMemory(#WAD_LumpEntrySize)
  If buffer = 0
    CloseFile(file)
    WADSetError("Out of memory while reading the WAD directory.")
    ProcedureReturn #False
  EndIf

  If ReadData(file, buffer, #WAD_HeaderSize) <> #WAD_HeaderSize
    WADAbortOpen("WAD header is truncated (short read).")
  EndIf

  signature = Chr(PeekA(buffer)) + Chr(PeekA(buffer + 1)) + Chr(PeekA(buffer + 2)) + Chr(PeekA(buffer + 3))
  If signature = "IWAD"
    kind = #WAD_KindIWAD
  ElseIf signature = "PWAD"
    kind = #WAD_KindPWAD
  Else
    WADAbortOpen("Not a WAD file: expected an exact IWAD or PWAD signature.")
  EndIf

  lumpCount = EndianReadI32LE(buffer, 4)
  directoryOffset = EndianReadI32LE(buffer, 8)

  If lumpCount < 0
    WADAbortOpen("Invalid WAD header: negative lump count (" + Str(lumpCount) + ").")
  EndIf

  If directoryOffset < 0
    WADAbortOpen("Invalid WAD header: negative directory offset (" + Str(directoryOffset) + ").")
  EndIf

  If lumpCount > #WAD_MaxDirectoryEntries
    WADAbortOpen("WAD directory is too large: " + Str(lumpCount) + " entries (safety limit " + Str(#WAD_MaxDirectoryEntries) + ").")
  EndIf

  If lumpCount > 0
    directorySize = lumpCount * #WAD_LumpEntrySize
    directoryEnd = directoryOffset + directorySize
    If directoryEnd > fileSize
      WADAbortOpen("WAD directory is outside the file: entries end at byte " + Str(directoryEnd) + ", file size is " + Str(fileSize) + ".")
    EndIf

    FileSeek(file, directoryOffset)
    If Loc(file) <> directoryOffset
      WADAbortOpen("Cannot seek to the WAD directory at byte " + Str(directoryOffset) + ".")
    EndIf

    ReDim gWAD_Lumps(lumpCount - 1)

    For entryIndex = 0 To lumpCount - 1
      If ReadData(file, buffer, #WAD_LumpEntrySize) <> #WAD_LumpEntrySize
        WADAbortOpen("WAD directory is truncated: short read at entry " + Str(entryIndex) + ".")
      EndIf

      entryPosition = EndianReadI32LE(buffer, 0)
      entrySize = EndianReadI32LE(buffer, 4)

      If entrySize < 0
        WADAbortOpen("Invalid lump entry " + Str(entryIndex) + ": negative size (" + Str(entrySize) + ").")
      EndIf

      ; Zero-length markers keep their raw position without validation; the
      ; position is never dereferenced for them.
      If entrySize > 0
        If entryPosition < 0
          WADAbortOpen("Invalid lump entry " + Str(entryIndex) + ": negative position (" + Str(entryPosition) + ").")
        EndIf
        entryEnd = entryPosition + entrySize
        If entryEnd > fileSize
          WADAbortOpen("Invalid lump entry " + Str(entryIndex) + ": data ends at byte " + Str(entryEnd) + ", file size is " + Str(fileSize) + ".")
        EndIf
      EndIf

      gWAD_Lumps(entryIndex)\Position = entryPosition
      gWAD_Lumps(entryIndex)\Size = entrySize
      gWAD_Lumps(entryIndex)\DisplayName = WADDecodeDisplayName(buffer + 8)
      CopyMemory(buffer + 8, @gWAD_Lumps(entryIndex)\NameBytes[0], #WAD_LumpNameSize)
    Next
  EndIf

  FreeMemory(buffer)
  CloseFile(file)

  gWAD_IsOpen = #True
  gWAD_Kind = kind
  gWAD_Path = Path
  gWAD_FileSize = fileSize
  gWAD_LumpCount = lumpCount
  gWAD_DirectoryOffset = directoryOffset

  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Accessors. All index-based getters are bounds-checked; an invalid index
; returns 0 (numeric) or "" (string) instead of reading out of bounds.
; ---------------------------------------------------------------------------

Procedure.i WADIsOpen()
  ProcedureReturn gWAD_IsOpen
EndProcedure

Procedure.i WADGetKind()
  ProcedureReturn gWAD_Kind
EndProcedure

Procedure.s WADGetKindName()
  Select gWAD_Kind
    Case #WAD_KindIWAD
      ProcedureReturn "IWAD"
    Case #WAD_KindPWAD
      ProcedureReturn "PWAD"
  EndSelect
  ProcedureReturn "none"
EndProcedure

Procedure.q WADGetFileSize()
  ProcedureReturn gWAD_FileSize
EndProcedure

Procedure.l WADGetLumpCount()
  ProcedureReturn gWAD_LumpCount
EndProcedure

Procedure.l WADGetDirectoryOffset()
  ProcedureReturn gWAD_DirectoryOffset
EndProcedure

Procedure.s WADGetPath()
  ProcedureReturn gWAD_Path
EndProcedure

Procedure.s WADLastError()
  ProcedureReturn gWAD_LastError
EndProcedure

Procedure.l WADLumpPosition(Index.i)
  If Index < 0 Or Index >= gWAD_LumpCount
    ProcedureReturn 0
  EndIf
  ProcedureReturn gWAD_Lumps(Index)\Position
EndProcedure

Procedure.l WADLumpSize(Index.i)
  If Index < 0 Or Index >= gWAD_LumpCount
    ProcedureReturn 0
  EndIf
  ProcedureReturn gWAD_Lumps(Index)\Size
EndProcedure

Procedure.i WADLumpIsMarker(Index.i)
  If Index < 0 Or Index >= gWAD_LumpCount
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(gWAD_Lumps(Index)\Size = 0)
EndProcedure

; Returns one raw name byte (0..255), or -1 when either index is invalid.
Procedure.i WADLumpRawNameByte(Index.i, ByteIndex.i)
  If Index < 0 Or Index >= gWAD_LumpCount Or ByteIndex < 0 Or ByteIndex >= #WAD_LumpNameSize
    ProcedureReturn -1
  EndIf
  ProcedureReturn gWAD_Lumps(Index)\NameBytes[ByteIndex]
EndProcedure

; Returns the raw 8 name bytes as 16 uppercase hex digits, or "" if invalid.
; Safe for logs: it never emits raw binary or game payload data.
Procedure.s WADLumpRawNameHex(Index.i)
  Protected i.i
  Protected result.s = ""

  If Index < 0 Or Index >= gWAD_LumpCount
    ProcedureReturn ""
  EndIf
  For i = 0 To #WAD_LumpNameSize - 1
    result + RSet(Hex(gWAD_Lumps(Index)\NameBytes[i]), 2, "0")
  Next

  ProcedureReturn result
EndProcedure

Procedure.s WADLumpDisplayName(Index.i)
  If Index < 0 Or Index >= gWAD_LumpCount
    ProcedureReturn ""
  EndIf
  ProcedureReturn gWAD_Lumps(Index)\DisplayName
EndProcedure

CompilerEndIf
